import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../util/app_tray.dart';
import '../util/logger.dart';
import '../util/platform_utils.dart';
import '../util/prefs.dart';

class _WindowStateListener with WindowListener {
  bool _closing = false;

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      final bounds = await windowManager.getBounds();
      await Prefs.setWindowBounds(bounds);
      final maximized = await windowManager.isMaximized();
      await Prefs.setWindowMaximized(maximized);
    } catch (e, stackTrace) {
      AppLogger.warn('Failed to persist window state before close: $e');
      AppLogger.logError(
        'Window state persistence error during onWindowClose',
        e,
        stackTrace,
      );
    }
    await windowManager.destroy();
  }
}

/// Window manager and tray initialization (desktop only).
class DesktopShellBootstrap {
  DesktopShellBootstrap._();

  static Future<void> initializeIfNeeded() async {
    if (!PlatformUtils.isDesktop) return;

    await windowManager.ensureInitialized();
    const minSize = Size(960, 600);
    await windowManager.setMinimumSize(minSize);
    const defaultSize = Size(1280, 800);
    const windowOptions = WindowOptions(
      size: defaultSize,
      minimumSize: minSize,
      title: 'Toxee',
      center: true,
      // Hide the native title bar but KEEP the macOS traffic lights — they sit
      // at the top-left inside our custom 48px title bar (which reserves space
      // for them). On Windows/Linux this flag is a no-op and the custom title
      // bar draws its own caption buttons at the top-right.
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );

    final savedBounds = await Prefs.getWindowBounds();
    final savedMaximized = await Prefs.getWindowMaximized();
    // Defensive bounds-on-screen check: window_manager does not expose a
    // multi-display API, so we reject obviously-off-screen origins (e.g.
    // the user unplugged the secondary monitor between sessions) and fall
    // back to the centered default rather than restoring an invisible window.
    final validBounds =
        savedBounds != null &&
        savedBounds.width >= minSize.width &&
        savedBounds.height >= minSize.height &&
        savedBounds.width <= 4096 &&
        savedBounds.height <= 4096 &&
        savedBounds.left > -savedBounds.width + 100 &&
        savedBounds.top > -100 &&
        savedBounds.left < 10000 &&
        savedBounds.top < 10000;

    windowManager.addListener(_WindowStateListener());
    await windowManager.setPreventClose(true);

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (validBounds) {
        try {
          await windowManager.setBounds(savedBounds);
        } catch (e) {
          AppLogger.warn('Could not restore window bounds: $e');
        }
      }
      await windowManager.show();
      await windowManager.focus();
      if (savedMaximized) {
        try {
          await windowManager.maximize();
        } catch (e) {
          AppLogger.warn('Could not maximize window: $e');
        }
      }
    });
    if (AppTray.instance.isSupported) {
      await AppTray.instance.init();
    }
  }
}
