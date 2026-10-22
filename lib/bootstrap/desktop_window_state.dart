import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import '../util/logger.dart';
import '../util/prefs.dart';
import 'desktop_window_geometry.dart';
import 'session_shutdown.dart';

/// One awaited exit for both caption close and framework quit (e.g. Cmd+Q).
class DesktopWindowState with WindowListener, ScreenListener {
  DesktopWindowState({this.checkpointSession});
  final Future<bool> Function()? checkpointSession;
  Rect? normalBounds;
  bool restoring = true;
  Timer? _debounce;
  Future<void> _pending = Future.value();
  Future<bool>? _exit;
  bool _closing = false;
  AppLifecycleListener? _lifecycle;

  void install() {
    windowManager.addListener(this);
    screenRetriever.addListener(this);
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        return await prepareToExit() ? AppExitResponse.exit : AppExitResponse.cancel;
      },
    );
  }

  Future<void> rememberNormalBounds() async {
    if (restoring ||
        await windowManager.isMaximized() ||
        await windowManager.isFullScreen() ||
        await windowManager.isMinimized()) {
      return;
    }
    normalBounds = await windowManager.getBounds();
    await Prefs.setWindowBounds(normalBounds!);
  }

  void _schedule() {
    if (restoring || _exit != null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _pending = _pending.then((_) => rememberNormalBounds()).catchError((
        Object e,
      ) {
        AppLogger.warn('Window checkpoint failed: $e');
      });
    });
  }

  @override
  void onWindowMove() => _schedule();
  @override
  void onWindowResize() => _schedule();

  Future<bool> prepareToExit() => _exit ??= _prepare().then((saved) {
    if (!saved) _exit = null;
    return saved;
  });
  Future<bool> _prepare() async {
    var saved = true;
    _debounce?.cancel();
    await _pending;
    try {
      await rememberNormalBounds();
      if (normalBounds != null) await Prefs.setWindowBounds(normalBounds!);
      await Prefs.setWindowMaximized(await windowManager.isMaximized());
    } catch (e) {
      AppLogger.warn('Window exit checkpoint failed: $e');
      saved = false;
    }
    if (!saved) return false;
    return checkpointSession != null ? await checkpointSession!() :
        await SessionShutdown.tearDownActiveAccount(
          timeout: const Duration(seconds: 10), logContext: 'DesktopShell');
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      if (await prepareToExit()) await windowManager.destroy();
    } finally {
      _closing = false;
    }
  }

  @override
  void onScreenEvent(String eventName) {
    unawaited(
      _keepReachable().catchError((Object e) {
        AppLogger.warn('Window display-change recovery failed: $e');
      }),
    );
  }

  Future<void> _keepReachable() async {
    if (restoring ||
        await windowManager.isMaximized() ||
        await windowManager.isFullScreen()) {
      return;
    }
    final bounds = await windowManager.getBounds();
    final displays = await screenRetriever.getAllDisplays();
    final areas = displays
        .map(
          (d) => (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size),
        )
        .toList();
    final adjusted = restoreDesktopBounds(bounds, areas);
    if (adjusted == null) {
      await windowManager.center();
    } else if (adjusted != bounds) {
      await windowManager.setBounds(adjusted);
    }
  }

  void dispose() {
    _debounce?.cancel();
    _lifecycle?.dispose();
    windowManager.removeListener(this);
    screenRetriever.removeListener(this);
  }
}
