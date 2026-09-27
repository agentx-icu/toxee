import Cocoa
import FlutterMacOS
import ImageIO

class MainFlutterWindow: NSWindow {
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

    let mediaTranscodeChannel = FlutterMethodChannel(
      name: "toxee/media_transcode",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
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
