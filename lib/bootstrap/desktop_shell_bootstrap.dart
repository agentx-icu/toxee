import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../util/app_tray.dart';
import '../util/logger.dart';
import '../util/platform_utils.dart';
import '../util/prefs.dart';
import 'windows_window_resurface.dart';

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
    // Windows/VM HiDPI re-surface nudge. window_manager's
    // hidden-create → setBounds → show sequence can leave the Flutter engine's
    // render surface (swapchain) sized to the PRE-show window metrics, so the
    // painted scene fills only part of the grown window and the rest composites
    // black. Observed live on a Parallels HiDPI Windows guest as a large black
    // band above the UI. A resize emits a fresh WM_SIZE the engine tracks,
    // forcing it to re-surface to the real client area — BUT only once the engine
    // has actually created its surface (the FIRST frame, after runApp). Nudging
    // inside waitUntilReadyToShow is too early and has no effect, so fire it
    // post-first-frame, off the bootstrap path (not awaited). Grow then restore
    // (matches the proven SetWindowPos repro) with a settle between so the engine
    // processes each resize. Desktop-window-only — no mobile counterpart (mobile
    // has no window_manager surface). macOS is unaffected (it renders correctly
    // without the nudge), so gate to Windows to avoid a needless startup flicker.
    if (PlatformUtils.isWindows) {
      unawaited(_nudgeRenderSurfaceAfterFirstFrame());
    }
  }

  /// Forces the Flutter engine to re-size its render surface to the real window
  /// client area after the first frame (see the call site for why). Fire-and-
  /// forget; failures are non-fatal (the worst case is the pre-existing band).
  ///
  /// NOTE: this issues a raw user32 `SetWindowPos` (via dart:ffi) rather than
  /// `windowManager.setSize` — the latter was verified live to NOT retrigger the
  /// engine re-surface, while a real SetWindowPos does.
  static Future<void> _nudgeRenderSurfaceAfterFirstFrame() async {
    try {
      // Wait past the first rendered frame so the engine surface exists.
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      await nudgeWindowsRenderSurface();
    } catch (e) {
      AppLogger.warn('Window re-surface nudge failed: $e');
    }
  }
}
