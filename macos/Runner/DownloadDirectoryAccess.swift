import Cocoa
import FlutterMacOS

/// Hold every granted URL until process exit: changing settings must not revoke
/// a grant while an asynchronous/native transfer still uses the old directory.
final class DownloadDirectoryAccess {
  private var grants: [String: URL] = [:]
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "toxee/download_directory", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self,
            let args = call.arguments as? [String: Any], let path = args["path"] as? String
      else { return result(FlutterError(code: "ARGS", message: "Missing folder", details: nil)) }
      guard call.method == "retain" || call.method == "restore" else {
        return result(FlutterMethodNotImplemented)
      }
      do {
        let key = "downloads.bookmark." + path
        var url = URL(fileURLWithPath: path, isDirectory: true)
        var stale = false
        if call.method == "restore", let data = UserDefaults.standard.data(forKey: key) {
          url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        let alreadyHeld = self.grants[url.path] != nil
        let accessed = !alreadyHeld && url.startAccessingSecurityScopedResource()
        do {
          let probe = url.appendingPathComponent(".toxee-access-" + UUID().uuidString)
          try Data().write(to: probe, options: .withoutOverwriting)
          try FileManager.default.removeItem(at: probe)
          let data = try url.bookmarkData(options: .withSecurityScope,
                                         includingResourceValuesForKeys: nil, relativeTo: nil)
          UserDefaults.standard.set(data, forKey: "downloads.bookmark." + url.path)
          if accessed { self.grants[url.path] = url }
          result(url.path)
        } catch {
          if accessed { url.stopAccessingSecurityScopedResource() }
          throw error
        }
      } catch {
        result(FlutterError(code: "ACCESS", message: "Choose the downloads folder again", details: nil))
      }
    }
  }

  deinit {
    for url in grants.values { url.stopAccessingSecurityScopedResource() }
  }
}
