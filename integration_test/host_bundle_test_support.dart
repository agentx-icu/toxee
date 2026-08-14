import 'dart:io';

import 'package:window_manager/window_manager.dart';

/// Initializes desktop plugins required by host-bundle widget harnesses.
///
/// These harnesses mount `EchoUIKitApp` directly, bypassing `main()`,
/// `AppBootstrap`, and `DesktopShellBootstrap`. On macOS, the second frame's
/// `DesktopWindowFrame.isMaximized` call otherwise reaches the native Swift
/// `WindowManager.mainWindow` force-unwrap before initialization and SIGTRAPs.
Future<void> ensureHostBundleWindowManagerInitialized() async {
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
  }
}
