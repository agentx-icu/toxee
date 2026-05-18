import Flutter
import AVFoundation
import Foundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      CallAudioChannel.shared.register(binaryMessenger: controller.binaryMessenger)

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
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
