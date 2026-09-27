import Cocoa
import FlutterMacOS
import ImageIO
import AVFoundation

class MainFlutterWindow: NSWindow {
  private var mediaTranscoder: ToxeeMediaTranscoder?

  override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
    super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    // Follow the system appearance (light/dark) as early as possible so the
    // window background behind the Flutter surface doesn't flash a contrasting
    // color on startup or during live-resize (white in dark mode looked jarring).
    self.backgroundColor = NSColor.windowBackgroundColor
    self.isOpaque = true
  }
  
  override func awakeFromNib() {
    // Ensure background color is set (in case awakeFromNib is called before init)
    self.backgroundColor = NSColor.windowBackgroundColor
    self.isOpaque = true
    
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    mediaTranscoder = ToxeeMediaTranscoder(
      channel: FlutterMethodChannel(
        name: "toxee/media_transcode", binaryMessenger: flutterViewController.engine.binaryMessenger))
    
    super.awakeFromNib()
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

/// `toxee/media_transcode` (checklist M2): converts outgoing media that
/// desktop peers may not display.
///
///  - `heicToJpeg({source, target})` — see [toxeeHeicToJpeg].
///  - `probeVideo({source})` — the video track's codec four-char code
///    ("hvc1" / "hev1" for HEVC, "avc1" for H.264), nil if unreadable.
///  - `transcodeToH264({id, source, target})` — H.264 / AAC MP4 at up to
///    1920x1080 (AVAssetExportPreset1920x1080, one of the size presets
///    documented to produce H.264; HDR is tone-mapped to SDR). Reports
///    `progress({id, progress})` back to Dart every 0.25 s; the result is
///    checked to really be H.264 before success.
///  - `cancelTranscode({id})` — the transcode then fails with CANCELLED.
final class ToxeeMediaTranscoder {
  private let channel: FlutterMethodChannel
  private var sessions: [String: AVAssetExportSession] = [:]

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let source = args["source"] as? String
    let target = args["target"] as? String
    let id = args["id"] as? String
    // AVFoundation goes by the extension; received files often have none.
    let ext = args["ext"] as? String
    switch call.method {
    case "heicToJpeg":
      guard let source, let target else { return result(Self.badArgs) }
      DispatchQueue.global(qos: .userInitiated).async {
        let error = toxeeHeicToJpeg(source: source, target: target)
        DispatchQueue.main.async {
          result(error.map { FlutterError(code: "FAILED", message: $0, details: nil) })
        }
      }
    case "probeVideo":
      guard let source else { return result(Self.badArgs) }
      DispatchQueue.global(qos: .userInitiated).async {
        guard let staged = Self.readable(source, ext: ext) else {
          return DispatchQueue.main.async { result(Self.stagingFailed) }
        }
        let (url, staging) = staged
        let codec = Self.codec(of: url.path, media: .video)
        Self.remove(staging)
        DispatchQueue.main.async { result(codec) }
      }
    case "transcodeToH264":
      guard let source, let target, let id else { return result(Self.badArgs) }
      transcode(id: id, source: source, ext: ext, target: target, result: result)
    case "cancelTranscode":
      if let id { sessions[id]?.cancelExport() }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Could not give the file a readable name: probing it as-is would read
  /// "no video" and let an HEVC file through, so this is an error.
  private static let stagingFailed =
    FlutterError(code: "FAILED", message: "cannot open the video", details: nil)

  private static let badArgs =
    FlutterError(code: "INVALID_ARGS", message: "missing arguments", details: nil)

  /// [path], or a hard link (a copy if linking fails) to it named with
  /// [ext] in a fresh temp dir — returned second, for [remove] afterwards.
  /// Nil when that staging fails. May copy: call off the main thread.
  private static func readable(_ path: String, ext: String?) -> (URL, URL?)? {
    let url = URL(fileURLWithPath: path)
    guard let ext, !ext.isEmpty, url.pathExtension.lowercased() != ext else {
      return (url, nil)
    }
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let staged = dir.appendingPathComponent("source.\(ext)")
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      do {
        try FileManager.default.linkItem(at: url, to: staged)
      } catch {
        try FileManager.default.copyItem(at: url, to: staged)
      }
      return (staged, dir)
    } catch {
      remove(dir)
      return nil
    }
  }

  private static func remove(_ dir: URL?) {
    if let dir { try? FileManager.default.removeItem(at: dir) }
  }

  private static func codec(of path: String, media: AVMediaType) -> String? {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = asset.tracks(withMediaType: media).first,
      let first = track.formatDescriptions.first
    else { return nil }
    let type = CMFormatDescriptionGetMediaSubType(first as! CMFormatDescription)
    let bytes = [24, 16, 8, 0].map { UInt8((type >> UInt32($0)) & 0xFF) }
    return String(bytes: bytes, encoding: .ascii)
  }

  private func transcode(
    id: String, source: String, ext: String?, target: String,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let staged = Self.readable(source, ext: ext)
      DispatchQueue.main.async { [weak self] in
        guard let staged else { return result(Self.stagingFailed) }
        self?.export(id: id, url: staged.0, staging: staged.1, target: target, result: result)
      }
    }
  }

  /// Main thread: owns [sessions] and the progress timer.
  private func export(
    id: String, url: URL, staging: URL?, target: String,
    result: @escaping FlutterResult
  ) {
    let asset = AVURLAsset(url: url)
    guard
      let session = AVAssetExportSession(
        asset: asset, presetName: AVAssetExportPreset1920x1080),
      session.supportedFileTypes.contains(.mp4)
    else {
      Self.remove(staging)
      return result(
        FlutterError(code: "FAILED", message: "cannot export this video", details: nil))
    }
    // Export to a .mp4 name (the session goes by it), then move onto target.
    let outDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let output = outDir.appendingPathComponent("out.mp4")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    session.outputURL = output
    session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true
    sessions[id] = session
    let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
    let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
      [weak self, weak session] _ in
      guard let session else { return }
      self?.channel.invokeMethod(
        "progress", arguments: ["id": id, "progress": Double(session.progress)])
    }
    session.exportAsynchronously { [weak self] in
      let status = session.status
      let message = session.error?.localizedDescription
      // The preset is a promise, not a proof: check what came out.
      let video = Self.codec(of: output.path, media: .video)
      let audio = hasAudio ? Self.codec(of: output.path, media: .audio) : "none"
      Self.remove(staging)
      var moveError: String?
      if status == .completed {
        do {
          try? FileManager.default.removeItem(atPath: target)
          try FileManager.default.moveItem(at: output, to: URL(fileURLWithPath: target))
        } catch {
          moveError = error.localizedDescription
        }
      }
      Self.remove(outDir)
      DispatchQueue.main.async {
        timer.invalidate()
        self?.sessions[id] = nil
        let error: FlutterError?
        switch status {
        case .completed where moveError != nil:
          error = FlutterError(code: "FAILED", message: moveError, details: nil)
        case .completed where video == "avc1" && (audio == "aac " || audio == "none"):
          error = nil
        case .completed:
          error = FlutterError(
            code: "FAILED",
            message: "unexpected output: \(video ?? "no video") / \(audio ?? "no audio")",
            details: nil)
        case .cancelled:
          error = FlutterError(code: "CANCELLED", message: nil, details: nil)
        default:
          error = FlutterError(code: "FAILED", message: message ?? "export failed", details: nil)
        }
        if error != nil { try? FileManager.default.removeItem(atPath: target) }
        result(error)
      }
    }
  }
}
