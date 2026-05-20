import AVFoundation
import CallKit
import Flutter
import Foundation
import UIKit

/// Bridges iOS CallKit (`CXProvider` + `CXCallController`) to Dart via a
/// `MethodChannel`. Owns a small UUID ↔ Dart-side-callId map because Tox
/// invite IDs (e.g. `native_av_<friendNumber>` or signaling invite IDs)
/// are not UUIDs, but CallKit requires UUIDs.
///
/// Wire-up:
/// - Dart calls `reportIncomingCall(callId, ...)` → we mint or reuse a UUID,
///   call `provider.reportNewIncomingCall(...)` so the lock-screen UI appears.
/// - User taps "Answer" / "End" in the system call UI → CallKit invokes the
///   `CXProviderDelegate` action → we forward the intent to Dart via
///   `callkit/action` method calls (`answer` / `end` / `mute`) and complete the
///   CallKit action. Dart then drives the actual `acceptCall` / `hangUp`.
///
/// Audio session handoff: when CallKit activates the AVAudioSession we forward
/// `audioSessionDidActivate` to Dart so the existing `CallAudioPlatform` /
/// `CallAudioChannel` stack can reconcile route preferences. The CallKit
/// activation always wins; trying to re-activate from Dart at the same instant
/// can race with CallKit's own session manipulation.
///
/// Note: PushKit (terminated-app receive) is intentionally NOT implemented
/// here. Tox is fully P2P with no push relay, so there is no APNs sender that
/// can wake the app from a terminated state. See
/// `doc/architecture/MOBILE_BACKGROUND.en.md`.
@objc final class CallKitProvider: NSObject {
  private let provider: CXProvider
  private let callController = CXCallController()
  private var channel: FlutterMethodChannel?

  /// Maps the Dart-side call identifier (Tox invite ID) ↔ CallKit UUID.
  /// Both directions are needed because CallKit identifies calls by UUID,
  /// but Dart tracks them by invite ID (`native_av_<n>` or signaling ID).
  private var uuidByCallId: [String: UUID] = [:]
  private var callIdByUuid: [UUID: String] = [:]

  /// Set of UUIDs we've already reported as `endedAt` to CallKit. Dart and
  /// CallKit can race to end the same call (e.g. user taps End on the
  /// lock-screen UI while a remote hang-up arrives simultaneously); we keep
  /// this set so a duplicate `reportCallEnded` from Dart doesn't try to end an
  /// already-ended call (which CallKit would log as an error).
  private var endedUuids: Set<UUID> = []

  override init() {
    let config = CXProviderConfiguration(localizedName: "Toxee")
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.maximumCallGroups = 1
    // Tox identities aren't phone numbers; use generic handles.
    config.supportedHandleTypes = [.generic]
    // App icon for the system call UI. The asset must be present in the
    // app's asset catalog; `UIImage(named:)` falls back to nil if missing,
    // in which case CallKit shows its default placeholder.
    if let icon = UIImage(named: "AppIcon") {
      config.iconTemplateImageData = icon.pngData()
    }
    self.provider = CXProvider(configuration: config)
    super.init()
    // Run delegate callbacks on the main queue so MethodChannel handlers and
    // CallKit callbacks share the same access serialization for
    // uuidByCallId/callIdByUuid maps. Without this, delegate methods would run
    // on CXProvider's internal serial queue while `handle(methodCall:result:)`
    // runs on the main thread, racing on the Dictionary/Set state below
    // (Swift collections are value types but their accesses are not atomic
    // when reached through a shared reference). AVAudioSession activation
    // callbacks are happy to fire on the main queue.
    self.provider.setDelegate(self, queue: DispatchQueue.main)
  }

  // MARK: - Channel registration

  @objc func register(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "toxee/callkit",
      binaryMessenger: binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(methodCall: call, result: result)
    }
    self.channel = methodChannel
  }

  // MARK: - Dart → Native

  private func handle(methodCall call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "reportIncomingCall":
      guard
        let callId = args?["callId"] as? String,
        let displayName = args?["displayName"] as? String
      else {
        result(invalidArgs(for: call.method))
        return
      }
      let hasVideo = (args?["hasVideo"] as? Bool) ?? false
      reportIncomingCall(callId: callId, displayName: displayName, hasVideo: hasVideo, result: result)
    case "reportOutgoingCall":
      guard let callId = args?["callId"] as? String else {
        result(invalidArgs(for: call.method))
        return
      }
      let displayName = (args?["displayName"] as? String) ?? callId
      let hasVideo = (args?["hasVideo"] as? Bool) ?? false
      reportOutgoingCall(callId: callId, displayName: displayName, hasVideo: hasVideo, result: result)
    case "reportCallConnected":
      guard let callId = args?["callId"] as? String else {
        result(invalidArgs(for: call.method))
        return
      }
      reportCallConnected(callId: callId)
      result(nil)
    case "reportCallEnded":
      guard let callId = args?["callId"] as? String else {
        result(invalidArgs(for: call.method))
        return
      }
      let reason = (args?["reason"] as? String) ?? "hangup"
      reportCallEnded(callId: callId, reason: reason)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func invalidArgs(for method: String) -> FlutterError {
    FlutterError(
      code: "INVALID_ARGS",
      message: "Missing required arguments for \(method)",
      details: nil
    )
  }

  private func uuidFor(callId: String, allocate: Bool) -> UUID? {
    if let existing = uuidByCallId[callId] { return existing }
    guard allocate else { return nil }
    let uuid = UUID()
    uuidByCallId[callId] = uuid
    callIdByUuid[uuid] = callId
    return uuid
  }

  private func reportIncomingCall(callId: String, displayName: String, hasVideo: Bool, result: @escaping FlutterResult) {
    let uuid = uuidFor(callId: callId, allocate: true)!
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callId)
    update.localizedCallerName = displayName
    update.hasVideo = hasVideo
    update.supportsDTMF = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsHolding = false
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if let error = error {
        // CallKit refused to show the UI — most commonly because the user has
        // toxee blocked under Settings → Phone → Silence Unknown Callers, or
        // because the system is already showing another call. We surface this
        // to Dart so it can fall back to the in-app ringtone + notification
        // path without leaking a stale UUID.
        self?.uuidByCallId.removeValue(forKey: callId)
        self?.callIdByUuid.removeValue(forKey: uuid)
        result(FlutterError(
          code: "REPORT_FAILED",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }
      result(nil)
    }
  }

  private func reportOutgoingCall(callId: String, displayName: String, hasVideo: Bool, result: @escaping FlutterResult) {
    let uuid = uuidFor(callId: callId, allocate: true)!
    let handle = CXHandle(type: .generic, value: callId)
    let startAction = CXStartCallAction(call: uuid, handle: handle)
    startAction.isVideo = hasVideo
    startAction.contactIdentifier = displayName
    let transaction = CXTransaction(action: startAction)
    callController.request(transaction) { error in
      if let error = error {
        result(FlutterError(
          code: "REPORT_FAILED",
          message: error.localizedDescription,
          details: nil
        ))
        return
      }
      result(nil)
    }
  }

  private func reportCallConnected(callId: String) {
    guard let uuid = uuidFor(callId: callId, allocate: false) else { return }
    provider.reportOutgoingCall(with: uuid, connectedAt: Date())
  }

  private func reportCallEnded(callId: String, reason: String) {
    guard let uuid = uuidFor(callId: callId, allocate: false) else { return }
    if endedUuids.contains(uuid) {
      // Already reported by the delegate path (user tapped End in the system
      // UI). Just clear local state and bail; calling reportCall(with:endedAt:reason:)
      // again is a no-op from CallKit's POV but logs a complaint.
      cleanupMapping(uuid: uuid, callId: callId)
      return
    }
    let cxReason = mapReason(reason)
    provider.reportCall(with: uuid, endedAt: Date(), reason: cxReason)
    endedUuids.insert(uuid)
    cleanupMapping(uuid: uuid, callId: callId)
  }

  private func cleanupMapping(uuid: UUID, callId: String) {
    uuidByCallId.removeValue(forKey: callId)
    callIdByUuid.removeValue(forKey: uuid)
    // Keep endedUuids around briefly to deduplicate late callbacks; trim if
    // it grows unboundedly. In practice calls are infrequent so capping at
    // 32 is more than enough.
    if endedUuids.count > 32 {
      endedUuids.removeFirst()
    }
  }

  /// Map a Dart-side end-reason string to a `CXCallEndedReason`. The Dart
  /// vocabulary is `hangup` | `cancel` | `reject` | `timeout` | `network_error`
  /// (mirrors `CallServiceManager._emitCallRecord` reasons).
  private func mapReason(_ reason: String) -> CXCallEndedReason {
    switch reason {
    case "reject":
      return .declinedElsewhere
    case "timeout":
      return .unanswered
    case "network_error":
      return .failed
    case "remote_hangup":
      return .remoteEnded
    default:
      // Default to `.remoteEnded`; `hangup` / `cancel` from this app's
      // perspective both terminate the CallKit session — the difference is
      // only meaningful in the call-record, not in CallKit's history.
      return .remoteEnded
    }
  }

  // MARK: - Native → Dart

  private func dispatchAction(_ action: String, callId: String, extra: [String: Any] = [:]) {
    var payload: [String: Any] = ["action": action, "callId": callId]
    for (k, v) in extra { payload[k] = v }
    channel?.invokeMethod("onCallKitAction", arguments: payload)
  }
}

// MARK: - CXProviderDelegate

extension CallKitProvider: CXProviderDelegate {
  func providerDidReset(_ provider: CXProvider) {
    // OS reset (rare; e.g. CallKit daemon crash). Wipe local state.
    uuidByCallId.removeAll()
    callIdByUuid.removeAll()
    endedUuids.removeAll()
    channel?.invokeMethod("onCallKitReset", arguments: nil)
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let callId = callIdByUuid[action.callUUID] else {
      action.fail()
      return
    }
    dispatchAction("answer", callId: callId)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let callId = callIdByUuid[action.callUUID] else {
      action.fail()
      return
    }
    // Mark as ended so a subsequent Dart `reportCallEnded` doesn't try to
    // double-report. We still tell Dart so it can drive its own hang-up path.
    endedUuids.insert(action.callUUID)
    dispatchAction("end", callId: callId)
    // CallKit requires action.fulfill() within ~5s. Our Dart-side hangUp() is
    // async, but: (1) the audio session is owned by CallKit (it deactivates on
    // fulfill, releasing it to other apps), (2) the ToxAV/signaling cleanup
    // is non-blocking and runs to completion regardless of CallKit state.
    // So immediate fulfill here is safe — the call IS ended from CallKit's
    // POV, and Dart cleans up its own state without holding CallKit's queue.
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard let callId = callIdByUuid[action.callUUID] else {
      action.fail()
      return
    }
    dispatchAction("mute", callId: callId, extra: ["muted": action.isMuted])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    // Tox does not support hold. Fulfill so CallKit doesn't believe the call
    // is in an inconsistent state, but don't propagate the intent to Dart.
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    guard let callId = callIdByUuid[action.callUUID] else {
      action.fail()
      return
    }
    // Tell CallKit we've started ringing; Dart-side `reportCallConnected`
    // will later mark it as connected.
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
    dispatchAction("start", callId: callId)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    channel?.invokeMethod("onAudioSessionActivated", arguments: nil)
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    channel?.invokeMethod("onAudioSessionDeactivated", arguments: nil)
  }
}
