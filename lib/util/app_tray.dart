import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app_l10n.dart';
import 'app_theme_config.dart';
import 'logger.dart';
import 'tray_icon_renderer.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class AppTray with TrayListener {
  AppTray._();
  static final AppTray instance = AppTray._();
  bool _initialized = false;
  int _lastCount = -1;
  bool _lastOnline = false;
  String? _lastTooltip;
  final MethodChannel _channel = const MethodChannel('tray_manager');
  final String _iconId = 'tim2tox_tray_icon';
  TrayIconRenderer? _renderer;
  int _iconFileGeneration = 0;
  Future<void>? _updating;
  ({int count, bool online})? _pendingUpdate;
  bool _pendingForce = false;
  static const String _colorIconAsset = 'assets/tray/tray_color.png';
  static const String _templateIconAsset = 'assets/tray/tray_template.png';

  bool get isSupported => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  bool _trayCallWarned = false;

  /// Run one optional tray call, tolerating per-platform gaps: tray_manager's
  /// Linux backend implements no setToolTip (MissingPluginException), and an
  /// uncaught throw here previously aborted AppBootstrap.initialize BEFORE
  /// runApp — leaving a running Tox session behind a permanently blank,
  /// element-less window. The tray is cosmetic; it must never take the app
  /// down. Warn once (update() runs on every unread-count change).
  Future<void> _safeTrayCall(String label, Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      if (!_trayCallWarned) {
        _trayCallWarned = true;
        AppLogger.info('[Tray] $label unavailable on this platform '
            '(continuing without it): $e');
      }
    }
  }

  Future<void> init() async {
    if (_initialized || !isSupported) return;
    _initialized = true;
    // A tray-less desktop session — headless Linux (no X StatusNotifier / SNI
    // host) or any WM without a system-tray host — throws
    // MissingPluginException on the first tray_manager call. The tray is a
    // non-essential nicety; NEVER let its absence abort app startup (an
    // uncaught throw otherwise halts the desktop-shell bootstrap before the
    // first frame). This whole-init guard fully DISABLES the tray on a hard
    // failure (rolls back the flag + listener so later update() calls no-op);
    // the finer-grained _safeTrayCall in update() additionally tolerates a
    // per-call gap on a tray that otherwise works.
    try {
      trayManager.addListener(this);
      await _safeTrayCall('setToolTip', () => trayManager.setToolTip('Toxee'));
      await update(count: 0, online: false);
    } catch (e, st) {
      _initialized = false;
      try {
        trayManager.removeListener(this);
      } catch (_) {/* best-effort */}
      debugPrint('[AppTray] tray unavailable, disabling: $e\n$st');
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    trayManager.removeListener(this);
    _initialized = false;
  }

  /// No-op: tray always uses the app icon, not user avatar.
  void setAvatarPath(String? path) {}

  /// Pushes the unread count and connection state to the tray.
  ///
  /// Callers fire this without awaiting (unread and connection listeners,
  /// locale changes), and one render takes several async steps — six PNG
  /// encodes for a Windows .ico. Updates are therefore serialized with
  /// latest-wins semantics: a call made while one is in flight only records
  /// its state, and the running loop applies the newest state next, so an
  /// older render can never land after a newer one.
  Future<void> update({required int count, required bool online, bool force = false}) async {
    if (!_initialized) return;
    _pendingUpdate = (count: count, online: online);
    _pendingForce = _pendingForce || force;
    final running = _updating;
    if (running != null) return running;
    final done = Completer<void>();
    _updating = done.future;
    try {
      while (_pendingUpdate != null) {
        final next = _pendingUpdate!;
        final nextForce = _pendingForce;
        _pendingUpdate = null;
        _pendingForce = false;
        try {
          await _apply(next.count, next.online, nextForce);
        } catch (e, st) {
          // The tray is cosmetic: log and move on to the newest state rather
          // than dropping it (and failing a caller whose state was fine).
          AppLogger.logError('[Tray] update failed', e, st);
        }
      }
    } finally {
      _updating = null;
      done.complete();
    }
  }

  Future<void> _apply(int count, bool online, bool force) async {
    if (!_initialized) return;
    final normalized = count.clamp(0, 999);
    // The tooltip is part of the cache key so a language switch re-renders it.
    final tooltip = normalized > 0
        ? currentAppL10n().trayUnreadTooltip(normalized)
        : 'Toxee';
    if (!force &&
        _lastCount == normalized &&
        _lastOnline == online &&
        _lastTooltip == tooltip) {
      return;
    }

    final renderer = await _loadRenderer();
    if (Platform.isMacOS) {
      // Template glyph; the count goes into the status item's title.
      final bytes = await renderer.macTemplatePng(online: online);
      await _safeTrayCall('setIcon', () => _channel.invokeMethod('setIcon', {
            'id': _iconId,
            'base64Icon': base64Encode(bytes),
            'isTemplate': true,
            'iconPosition': 'left',
          }));
      final title = normalized > 0 ? (normalized > 99 ? '99+' : '$normalized') : '';
      await _safeTrayCall('setTitle', () => trayManager.setTitle(title));
    } else {
      final bytes = Platform.isWindows
          ? await renderer.windowsIco(count: normalized, online: online)
          : await renderer.linuxPng(count: normalized, online: online);
      await _safeTrayCall('setIcon', () async {
        final path = await _writeIconFile(bytes);
        await _channel.invokeMethod('setIcon', {
          'id': _iconId,
          'iconPath': path,
          'isTemplate': false,
          'iconPosition': 'left',
        });
      });
    }

    await _safeTrayCall('setToolTip', () => trayManager.setToolTip(tooltip));
    _lastCount = normalized;
    _lastOnline = online;
    _lastTooltip = tooltip;
  }

  /// Writes the icon to a file the native tray can load by path.
  ///
  /// Alternates between two names: libappindicator ignores
  /// `app_indicator_set_icon_full` with an unchanged path, so rewriting one
  /// file in place never refreshes the Linux icon. The pid keeps concurrent
  /// instances from overwriting each other's icon.
  Future<String> _writeIconFile(Uint8List bytes) async {
    final ext = Platform.isWindows ? 'ico' : 'png';
    final slot = _iconFileGeneration++ % 2;
    final file = File(
        '${Directory.systemTemp.path}/toxee_tray_${pid}_$slot.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<TrayIconRenderer> _loadRenderer() async {
    final cached = _renderer;
    if (cached != null) return cached;
    final renderer = TrayIconRenderer(
      colorIcon: Platform.isMacOS ? null : await _decodeAsset(_colorIconAsset),
      templateIcon:
          Platform.isMacOS ? await _decodeAsset(_templateIconAsset) : null,
      badgeColor: AppThemeConfig.errorColor,
    );
    _renderer = renderer;
    return renderer;
  }

  Future<ui.Image?> _decodeAsset(String asset) async {
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      AppLogger.info('[Tray] could not load $asset, using fallback art: $e');
      return null;
    }
  }

  @override
  void onTrayIconMouseDown() async {
    if (!isSupported) return;
    await windowManager.show();
    await windowManager.focus();
  }
}

