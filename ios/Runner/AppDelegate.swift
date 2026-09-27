import Flutter
import AVFoundation
import Foundation
import ImageIO
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
        // Images and videos are imported from the file, not a decoded
        // UIImage, so the original format (GIF animation, HEIC) survives.
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String, !path.isEmpty,
          FileManager.default.isReadableFile(atPath: path)
        else {
          result(FlutterError(
            code: "INVALID_ARGS",
            message: "Expected readable media path",
            details: nil))
          return
        }
        let mimeType = args["mimeType"] as? String ?? "image/png"
        let isVideo = mimeType.hasPrefix("video/")
        guard isVideo || mimeType.hasPrefix("image/") else {
          result(FlutterError(
            code: "INVALID_ARGS",
            message: "Not an image or video: \(mimeType)",
            details: nil))
          return
        }
        // Photos goes by the extension; received files often have none, so
        // import a hard link (a copy if linking fails) named displayName.
        var fileURL = URL(fileURLWithPath: path)
        var stagingDir: URL?
        if let displayName = args["displayName"] as? String, !displayName.isEmpty,
          (displayName as NSString).pathExtension.lowercased()
            != fileURL.pathExtension.lowercased()
        {
          let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
          let staged = dir.appendingPathComponent(
            (displayName as NSString).lastPathComponent)
          do {
            try FileManager.default.createDirectory(
              at: dir, withIntermediateDirectories: true)
            stagingDir = dir
            do {
              try FileManager.default.linkItem(at: fileURL, to: staged)
            } catch {
              try FileManager.default.copyItem(at: fileURL, to: staged)
            }
            fileURL = staged
          } catch {
            if let dir = stagingDir { try? FileManager.default.removeItem(at: dir) }
            result(FlutterError(
              code: "SAVE_FAILED",
              message: error.localizedDescription,
              details: nil))
            return
          }
        }
        let importURL = fileURL
        let cleanupDir = stagingDir
        var created = false
        PHPhotoLibrary.shared().performChanges({
          let request = isVideo
            ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: importURL)
            : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: importURL)
          created = request != nil
        }) { success, error in
          let success = success && created
          if let dir = cleanupDir { try? FileManager.default.removeItem(at: dir) }
          DispatchQueue.main.async {
            if success {
              result(path)
            } else {
              result(FlutterError(
                code: "SAVE_FAILED",
                message: error?.localizedDescription ?? "Could not save to Photos",
                details: nil))
            }
          }
        }
      }

      let mediaTranscodeChannel = FlutterMethodChannel(
        name: "toxee/media_transcode",
        binaryMessenger: controller.binaryMessenger)
      mediaTranscodeChannel.setMethodCallHandler { (call, result) in
        guard call.method == "heicToJpeg",
          let args = call.arguments as? [String: Any],
          let source = args["source"] as? String,
          let target = args["target"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let error = toxeeHeicToJpeg(source: source, target: target)
          DispatchQueue.main.async {
            result(error.map { FlutterError(code: "FAILED", message: $0, details: nil) })
          }
        }
      }

      #if DEBUG
      // L3 test seam, DEBUG builds only (release Dart must not be able to pop
      // arbitrary presented UIKit flows; the Dart side additionally gates on
      // kDebugMode + TOXEE_L3_TEST): report / dismiss a natively PRESENTED
      // view controller covering the FlutterViewController — the file bubble's
      // document preview, a share sheet, an alert. Flutter frames pause
      // underneath it, so the real-UI harness can neither see it nor tap its
      // Done button; `dismiss` does exactly what Done does (pop the presented
      // chain from the root).
      let nativeCoverChannel = FlutterMethodChannel(
        name: "toxee/native_cover",
        binaryMessenger: controller.binaryMessenger)
      nativeCoverChannel.setMethodCallHandler { [weak controller] (call, result) in
        guard let root = controller else {
          let gone: [String: Any] = ["presented": false, "controller": "", "dismissed": false]
          result(gone)
          return
        }
        var top: UIViewController = root
        while let next = top.presentedViewController { top = next }
        let presented = top !== root
        let name = String(describing: type(of: top))
        switch call.method {
        case "probe":
          let payload: [String: Any] = ["presented": presented, "controller": name]
          result(payload)
        case "dismiss":
          guard presented else {
            let payload: [String: Any] = ["presented": false, "controller": name, "dismissed": false]
            result(payload)
            return
          }
          root.dismiss(animated: false) {
            let payload: [String: Any] = ["presented": true, "controller": name, "dismissed": true]
            result(payload)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      #endif
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

/// HEIC / HEIF -> JPEG for sending (checklist M2): desktop peers often cannot
/// show HEIC. The first image is re-encoded at quality 0.9 with its
/// orientation and colour metadata, minus the GPS block. Returns an error
/// message, or nil on success.
func toxeeHeicToJpeg(source: String, target: String) -> String? {
  guard
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
    CGImageSourceGetCount(src) > 0
  else { return "unreadable image" }
  guard
    let dest = CGImageDestinationCreateWithURL(
      URL(fileURLWithPath: target) as CFURL, "public.jpeg" as CFString, 1, nil)
  else { return "cannot create JPEG" }
  let properties: [CFString: Any] = [
    kCGImageDestinationLossyCompressionQuality: 0.9,
    // kCFNull removes the key: no location leaves the device.
    kCGImagePropertyGPSDictionary: kCFNull as Any,
  ]
  CGImageDestinationAddImageFromSource(dest, src, 0, properties as CFDictionary)
  return CGImageDestinationFinalize(dest) ? nil : "JPEG encoding failed"
}
