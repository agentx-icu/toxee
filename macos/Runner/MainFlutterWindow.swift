import Cocoa
import FlutterMacOS

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
    
    super.awakeFromNib()
  }
}
