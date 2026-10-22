import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../util/app_tray.dart';
import '../util/logger.dart';
import '../util/platform_utils.dart';
import '../util/prefs.dart';
import 'desktop_window_state.dart';
import 'single_session_guard.dart';
import 'desktop_window_geometry.dart';
import 'windows_window_resurface.dart';

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
      titleBarStyle: PlatformUtils.isLinux ? TitleBarStyle.normal : TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );

    final savedBounds = await Prefs.getWindowBounds();
    final savedMaximized = await Prefs.getWindowMaximized();
    final displays = await screenRetriever.getAllDisplays().catchError((Object _) => <Display>[]);
    final restored = restoreDesktopBounds(savedBounds, displays.map((d) =>
        (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size)).toList());
    final state = DesktopWindowState()..install();
    await windowManager.setPreventClose(true);

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (restored != null) {
        try {
          await windowManager.setBounds(restored);
        } catch (e) {
          AppLogger.warn('Could not restore window bounds: $e');
        }
      }
      await windowManager.show();
      await windowManager.focus();
      state.normalBounds = await windowManager.getBounds();
      if (savedMaximized) {
        try {
          await windowManager.maximize();
        } catch (e) {
          AppLogger.warn('Could not maximize window: $e');
        }
      }
    });
    state.restoring = false;
    await SingleSessionGuard.markDesktopReady();
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
