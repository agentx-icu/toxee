import Flutter
import AVFoundation
import Foundation
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Held as instance properties so the delegates stay alive for the app's
  // lifetime — both CallKit (`CXProvider`) and BGTaskScheduler retain weak
  // references back into us via their handlers.
  private let callKitProvider = CallKitProvider()
  private let backgroundTasks = BackgroundTaskController()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // BGTaskScheduler launch handlers MUST be registered before
    // `application(_:didFinishLaunchingWithOptions:)` returns or iOS traps.
    // The Dart-side handler is wired later via the MethodChannel; before
    // Dart connects, the task will simply call `setTaskCompleted(false)`
    // when its expiration handler fires (~30s), which is fine.
    backgroundTasks.registerLaunchHandlers()

    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      CallAudioChannel.shared.register(binaryMessenger: controller.binaryMessenger)
      callKitProvider.register(binaryMessenger: controller.binaryMessenger)
      backgroundTasks.register(binaryMessenger: controller.binaryMessenger)

      // iOS backup-exclusion channel — used by Dart-side AppPaths to mark
      // derivable / ephemeral directories (logs, file_recv, QR cache) with
      // NSURLIsExcludedFromBackupResourceKey so they don't bloat iCloud /
      // iTunes backups and so Apple review doesn't flag the app.
      let backupChannel = FlutterMethodChannel(
        name: "toxee/ios_backup",
        binaryMessenger: controller.binaryMessenger)
      backupChannel.setMethodCallHandler { (call, result) in
        guard call.method == "markExcludedFromBackup" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String, !path.isEmpty
        else {
          result(FlutterError(
            code: "INVALID_ARGS",
            message: "Expected {path: String}",
            details: nil))
          return
        }
        var url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
          // Setting the resource value requires the target to exist. Create
          // the directory defensively; Dart-side callers may invoke us
          // before the directory itself has been created.
          do {
            try FileManager.default.createDirectory(
              at: url, withIntermediateDirectories: true, attributes: nil)
          } catch {
            // Non-fatal: report and bail out.
            result(FlutterError(
              code: "CREATE_FAILED",
              message: "Could not create \(path): \(error.localizedDescription)",
              details: nil))
            return
          }
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(nil)
        } catch {
          result(FlutterError(
            code: "SET_FAILED",
            message: "setResourceValues failed for \(path): \(error.localizedDescription)",
            details: nil))
        }
      }

      let qrSaveChannel = FlutterMethodChannel(
        name: "toxee/qr_save",
        binaryMessenger: controller.binaryMessenger)
      qrSaveChannel.setMethodCallHandler { (call, result) in
        guard call.method == "saveImageToGallery" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String, !path.isEmpty,
          let image = UIImage(contentsOfFile: path)
        else {
          result(FlutterError(
            code: "INVALID_ARGS",
            message: "Expected readable image path",
            details: nil))
          return
        }
        PHPhotoLibrary.shared().performChanges({
          PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
          DispatchQueue.main.async {
            if success {
              result(path)
            } else {
              result(FlutterError(
                code: "SAVE_FAILED",
                message: error?.localizedDescription ?? "Could not save image to Photos",
                details: nil))
            }
          }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    // Whenever we leave foreground, queue up the next BG refresh window.
    // Without this the system would only ever run the first refresh.
    backgroundTasks.scheduleNextRefresh()
    super.applicationDidEnterBackground(application)
  }
}
