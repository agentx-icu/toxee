import BackgroundTasks
import Flutter
import Foundation
import UIKit

/// Wires `BGAppRefreshTask` into Dart via a MethodChannel so that when iOS
/// grants the app a brief background slice, the existing
/// `FfiChatService.startPolling()` machinery gets a chance to drain Tox events
/// and maintain DHT presence.
///
/// Why BG refresh and not BGProcessingTask:
/// - `BGProcessingTask` allows longer runtime but iOS only schedules it when
///   the device is plugged in + idle, which is rarely true for a chat app.
/// - `BGAppRefreshTask` is throttled to ~30 sec but runs while the device is
///   in normal use, which matches the "keep Tox warm" use case better.
///
/// LIMITATIONS (documented also in doc/architecture/MOBILE_BACKGROUND.en.md):
/// - iOS decides scheduling adaptively from user-usage signals. There is no
///   way to force it. We submit a request asking for "no earlier than 15
///   minutes from now" but the system may delay much longer, or skip entirely.
/// - The app must be at least suspended (not terminated) for BG refresh to
///   fire. After force-quit, iOS will not deliver this task.
/// - The 30-sec budget is a hard cap. The Dart handler must self-terminate
///   well within that window and call back so we can `setTaskCompleted(true)`.
@objc final class BackgroundTaskController: NSObject {
  /// Must match the entry registered in `Info.plist`'s
  /// `BGTaskSchedulerPermittedIdentifiers`. We pin to the app's bundle id so
  /// the namespace can't collide with system tasks.
  static let refreshIdentifier = "com.toxee.app.refresh"

  /// Soft target for how often we ask the system to refresh us. iOS treats
  /// this as a floor, not a guarantee.
  static let refreshInterval: TimeInterval = 15 * 60

  /// Hard cap (sec) we give the Dart handler before forcefully completing
  /// the BG task. Apple gives BGAppRefreshTask ~30 sec total; we budget 25
  /// to leave room for cleanup.
  static let taskBudgetSec: TimeInterval = 25

  private var channel: FlutterMethodChannel?

  /// Pending refresh-complete callbacks keyed by request id. The Dart handler
  /// calls back `refreshCompleted` with the same id when it's done draining.
  ///
  /// Concurrency: this map is touched from three contexts — the BGTaskScheduler
  /// handler queue (write on task delivery), the MethodChannel main thread
  /// (read+write on `refreshCompleted`), and the main queue watchdog
  /// (read+write on timeout). Swift Dictionary is not thread-safe, so all
  /// accesses go through `storePendingTask` / `popPendingTask`, which
  /// serialize through `stateQueue`. The atomicity of `popPendingTask`
  /// guarantees exactly one of {Dart-completion, watchdog} drives the
  /// `setTaskCompleted` call for any given requestId.
  private let stateQueue = DispatchQueue(label: "com.toxee.bg_refresh.state")
  private var _pendingTasks: [String: BGAppRefreshTask] = [:]

  private func storePendingTask(_ task: BGAppRefreshTask, requestId: String) {
    stateQueue.sync { _pendingTasks[requestId] = task }
  }

  private func popPendingTask(requestId: String) -> BGAppRefreshTask? {
    return stateQueue.sync { _pendingTasks.removeValue(forKey: requestId) }
  }

  // MARK: - Registration

  /// Call from `application(_:didFinishLaunchingWithOptions:)` BEFORE
  /// `applicationDidFinishLaunching` returns. `BGTaskScheduler.register`
  /// otherwise traps with an "All launch handlers must be registered before
  /// application finishes launching" assertion.
  @objc func registerLaunchHandlers() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: BackgroundTaskController.refreshIdentifier,
      using: nil
    ) { [weak self] task in
      guard let refresh = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self?.handleRefresh(task: refresh)
    }
  }

  @objc func register(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "toxee/bg_refresh",
      binaryMessenger: binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(methodCall: call, result: result)
    }
    self.channel = methodChannel
  }

  // MARK: - Scheduling

  /// Schedule the next refresh window. Call from `applicationDidEnterBackground`.
  /// Safe to call repeatedly; `submit` overwrites any pending request with the
  /// same identifier.
  @objc func scheduleNextRefresh() {
    let request = BGAppRefreshTaskRequest(
      identifier: BackgroundTaskController.refreshIdentifier
    )
    request.earliestBeginDate = Date(
      timeIntervalSinceNow: BackgroundTaskController.refreshInterval
    )
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      // Most common failures:
      // - `.unavailable`: Background App Refresh disabled in Settings (user
      //   choice); nothing we can do.
      // - `.tooManyPendingTaskRequests`: we already have one queued.
      // Both are benign. Log for diagnostics.
      NSLog("[BackgroundTaskController] BGTaskScheduler.submit failed: \(error)")
    }
  }

  // MARK: - Task handling

  private func handleRefresh(task: BGAppRefreshTask) {
    // Always re-schedule before handling. If the handler crashes mid-way iOS
    // would otherwise stop calling us entirely.
    scheduleNextRefresh()

    let requestId = UUID().uuidString
    storePendingTask(task, requestId: requestId)

    // If the system pulls the rug (e.g. user opens the app, BG context ends),
    // we must call setTaskCompleted promptly or iOS de-prioritises us.
    task.expirationHandler = { [weak self, weak task] in
      guard let self = self else { return }
      _ = self.popPendingTask(requestId: requestId)
      task?.setTaskCompleted(success: false)
    }

    // Hand off to Dart. Dart must call `refreshCompleted` with the same id
    // when done. We also arm a hard watchdog at `taskBudgetSec`.
    channel?.invokeMethod(
      "performRefresh",
      arguments: ["requestId": requestId]
    )

    DispatchQueue.main.asyncAfter(
      deadline: .now() + BackgroundTaskController.taskBudgetSec
    ) { [weak self] in
      guard let self = self,
            let pending = self.popPendingTask(requestId: requestId)
      else { return }
      // Watchdog only fires when Dart fails to call refreshCompleted within
      // budget — report failure so iOS deprioritizes future refresh windows
      // accordingly. Reporting success here would mislead the scheduler into
      // thinking the task drained cleanly and preserve our priority despite
      // the silent miss.
      pending.setTaskCompleted(success: false)
    }
  }

  // MARK: - Dart → Native

  private func handle(methodCall call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "scheduleNextRefresh":
      scheduleNextRefresh()
      result(nil)
    case "refreshCompleted":
      let args = call.arguments as? [String: Any]
      guard let requestId = args?["requestId"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing requestId", details: nil))
        return
      }
      let success = (args?["success"] as? Bool) ?? true
      if let task = popPendingTask(requestId: requestId) {
        task.setTaskCompleted(success: success)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
