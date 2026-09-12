import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../util/app_tray.dart';
import '../util/logger.dart';
import '../util/platform_utils.dart';
import '../util/prefs.dart';
import 'session_shutdown.dart';
import 'windows_window_resurface.dart';

class _WindowStateListener with WindowListener {
  bool _closing = false;

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    // The desktop app terminates after its last window closes
    // (`applicationShouldTerminateAfterLastWindowClosed`), so this is the last
    // thing a close-driven exit ever logs. Say so explicitly: a process that
    // vanished with this line was closed, one without it was killed or exited
    // some other way.
    AppLogger.info('[DesktopShell] window close requested — app will exit');
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
    // Closing the window terminates the app, so this is the app's real exit
    // path and it must run the same account teardown a logout does — otherwise
    // a password-protected profile is left in plaintext on disk. See
    // `SessionShutdown` for the full rationale and the limits of this approach.
    await SessionShutdown.tearDownActiveAccount(
      timeout: const Duration(seconds: 10),
      logContext: 'DesktopShell',
    );
    await windowManager.destroy();
  }
}

/// Window manager and tray initialization (desktop only).
class DesktopShellBootstrap {
  DesktopShellBootstrap._();

  /// Primary display work area in logical pixels, or null when it cannot be
  /// determined (headless CI, exotic WMs).
  static Future<Size?> _workArea() async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      return display.visibleSize ?? display.size;
    } catch (e) {
      AppLogger.warn('[DesktopShell] primary display lookup failed: $e');
      return null;
    }
  }

  /// [preferred] clamped to the work area. At Windows 150 % on a 1366×768
  /// panel (911×512 logical) or 200 % on 1920×1080 (960×540) the unclamped
  /// 960×600 minimum was larger than the screen, so the OS clipped the
  /// window's own top bar / caption buttons. Below 720 px the app falls back
  /// to its bottom-nav tier, which stays usable.
  static Size _fitWorkArea(Size preferred, Size? work) {
    if (work == null) return preferred;
    return Size(
      math.min(preferred.width, work.width),
      math.min(preferred.height, work.height),
    );
  }

  static Future<void> initializeIfNeeded() async {
    if (!PlatformUtils.isDesktop) return;

    await windowManager.ensureInitialized();
    final work = await _workArea();
    final minSize = _fitWorkArea(const Size(960, 600), work);
    await windowManager.setMinimumSize(minSize);
    final defaultSize = _fitWorkArea(const Size(1280, 800), work);
    final windowOptions = WindowOptions(
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
    // A saved size larger than today's work area (display swapped, DPI
    // scaling raised) would also come up clipped: fall back to the default.
    final validBounds =
        savedBounds != null &&
        savedBounds.width >= minSize.width &&
        savedBounds.height >= minSize.height &&
        savedBounds.width <= (work?.width ?? 4096) &&
        savedBounds.height <= (work?.height ?? 4096) &&
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
