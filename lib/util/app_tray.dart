import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app_theme_config.dart';
import 'logger.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class AppTray with TrayListener {
  AppTray._();
  static final AppTray instance = AppTray._();
  bool _initialized = false;
  int _lastCount = -1;
  bool _lastOnline = false;
  final MethodChannel _channel = const MethodChannel('tray_manager');
  final String _iconId = 'tim2tox_tray_icon';
  File? _tempIconFile;
  ui.Image? _cachedAppIcon;
  ui.Image? _cachedAppIconWhite;
  static const String _appIconAsset = 'assets/app_icon.png';
  static const String _appIconWhiteAsset = 'assets/app_icon_white.png';

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

  Future<void> update({required int count, required bool online, bool force = false}) async {
    if (!_initialized) return;
    final normalized = count.clamp(0, 999);
    if (!force && _lastCount == normalized && _lastOnline == online) return;
    
    if (Platform.isMacOS) {
      // macOS: Use native title for number display (normal size)
      final bytes = await _buildIconOnlyBytes(online);
      await _safeTrayCall('setIcon', () => _setTrayIcon(bytes));
      final title = normalized > 0 ? (normalized > 99 ? '99+' : '$normalized') : '';
      await _safeTrayCall('setTitle', () => trayManager.setTitle(title));
    } else {
      // Windows/Linux: Draw number in icon image
      final bytes = await _buildTrayIconBytes(normalized, online);
      await _safeTrayCall('setIcon', () => _setTrayIcon(bytes));
    }

    final tooltip = normalized > 0 ? 'Unread: $normalized' : 'Toxee';
    await _safeTrayCall('setToolTip', () => trayManager.setToolTip(tooltip));
    _lastCount = normalized;
    _lastOnline = online;
  }

  Future<void> _setTrayIcon(Uint8List bytes) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod('setIcon', {
        'id': _iconId,
        'base64Icon': base64Encode(bytes),
        'isTemplate': false,
        'iconPosition': 'left',
      });
    } else {
      final path = await _writeTempIcon(bytes);
      await _channel.invokeMethod('setIcon', {
        'id': _iconId,
        'iconPath': path,
        'isTemplate': false,
        'iconPosition': 'left',
      });
    }
  }

  Future<String> _writeTempIcon(Uint8List bytes) async {
    _tempIconFile ??= File('${Directory.systemTemp.path}/tim2tox_tray_icon.png');
    await _tempIconFile!.writeAsBytes(bytes, flush: true);
    return _tempIconFile!.path;
  }

  Future<ui.Image?> _getAppIcon() async {
    if (_cachedAppIcon != null) return _cachedAppIcon;
    try {
      final data = await rootBundle.load(_appIconAsset);
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _cachedAppIcon = frame.image;
      return _cachedAppIcon;
    } catch (_) {
      return null;
    }
  }

  Future<ui.Image?> _getAppIconWhite() async {
    if (_cachedAppIconWhite != null) return _cachedAppIconWhite;
    try {
      final data = await rootBundle.load(_appIconWhiteAsset);
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _cachedAppIconWhite = frame.image;
      return _cachedAppIconWhite;
    } catch (_) {
      return null;
    }
  }

  void _drawAppIconOrFallback(ui.Canvas canvas, ui.RRect background, ui.Rect iconRect, double iconSize, double iconX, double iconY, {bool whiteOnTransparent = false}) {
    final appImage = _cachedAppIcon;
    if (appImage != null) {
      final src = ui.Rect.fromLTWH(0, 0, appImage.width.toDouble(), appImage.height.toDouble());
      if (whiteOnTransparent) {
        // macOS menu bar: white subject on transparent background, with subtle
        // dark outline so the shape is visible (avoids solid white blob).
        const double outlineOffset = 1.5;
        final outlineRect = ui.Rect.fromLTWH(
          iconRect.left + outlineOffset,
          iconRect.top + outlineOffset,
          iconRect.width,
          iconRect.height,
        );
        final outlinePaint = ui.Paint()
          ..colorFilter = ui.ColorFilter.mode(
            const ui.Color(0x80000000),
            ui.BlendMode.srcIn,
          );
        canvas.drawImageRect(appImage, src, outlineRect, outlinePaint);
        final whitePaint = ui.Paint()
          ..colorFilter = ui.ColorFilter.mode(
            const ui.Color(0xFFFFFFFF),
            ui.BlendMode.srcIn,
          );
        canvas.drawImageRect(appImage, src, iconRect, whitePaint);
      } else {
        canvas.save();
        canvas.clipRRect(background);
        canvas.drawImageRect(appImage, src, iconRect, ui.Paint());
        canvas.restore();
      }
    } else {
      if (whiteOnTransparent) {
        final double fontSize = iconSize * 0.5;
        final builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: ui.TextAlign.center, fontSize: fontSize),
        )..pushStyle(ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontWeight: ui.FontWeight.w900,
        ));
        builder.addText('E');
        final paragraph = builder.build()
          ..layout(ui.ParagraphConstraints(width: iconSize));
        canvas.drawParagraph(paragraph, ui.Offset(iconX, iconY + (iconSize - paragraph.height) / 2));
      } else {
        final iconBgPaint = ui.Paint()..color = const ui.Color(0xFF2E3138);
        canvas.drawRRect(background, iconBgPaint);
        final double fontSize = iconSize * 0.5;
        final builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: ui.TextAlign.center, fontSize: fontSize),
        )..pushStyle(ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontWeight: ui.FontWeight.w900,
        ));
        builder.addText('E');
        final paragraph = builder.build()
          ..layout(ui.ParagraphConstraints(width: iconSize));
        canvas.drawParagraph(paragraph, ui.Offset(iconX, iconY + (iconSize - paragraph.height) / 2));
      }
    }
  }

  /// Build icon bytes without number (for macOS native title display)
  /// On macOS menu bar: use app_icon_white.png (transparent + white) directly.
  Future<Uint8List> _buildIconOnlyBytes(bool online) async {
    const double canvasSize = 64.0;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final iconSize = canvasSize * 0.9;
    final iconX = (canvasSize - iconSize) / 2;
    final iconY = (canvasSize - iconSize) / 2;
    final iconRect = ui.Rect.fromLTWH(iconX, iconY, iconSize, iconSize);
    final background = ui.RRect.fromRectAndRadius(iconRect, const ui.Radius.circular(12.0));

    if (Platform.isMacOS) {
      await _getAppIconWhite();
      final whiteImage = _cachedAppIconWhite;
      if (whiteImage != null) {
        final src = ui.Rect.fromLTWH(0, 0, whiteImage.width.toDouble(), whiteImage.height.toDouble());
        canvas.drawImageRect(whiteImage, src, iconRect, ui.Paint());
      } else {
        _drawAppIconOrFallback(canvas, background, iconRect, iconSize, iconX, iconY, whiteOnTransparent: true);
      }
    } else {
      await _getAppIcon();
      _drawAppIconOrFallback(canvas, background, iconRect, iconSize, iconX, iconY, whiteOnTransparent: false);
    }

    // Draw online/offline status indicator
    final statusColor = online ? ui.Color(AppThemeConfig.successColor.value) : ui.Color(AppThemeConfig.errorColor.value);
    final statusPaint = ui.Paint()..color = statusColor;
    final statusSize = 8.0;
    final statusRadius = 1.5;
    final statusOffset = 8.0;
    final statusRect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        iconX + iconSize - statusOffset, 
        iconY + iconSize - statusOffset, 
        statusSize, 
        statusSize
      ),
      ui.Radius.circular(statusRadius),
    );
    canvas.drawRRect(statusRect, statusPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(canvasSize.toInt(), canvasSize.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Build tray icon bytes with number embedded (for Windows/Linux)
  /// macOS uses native title instead, so this method is only for Windows/Linux
  Future<Uint8List> _buildTrayIconBytes(int count, bool online) async {
    await _getAppIcon();

    // System tray icons MUST be square (1:1 ratio) for Windows/Linux
    const double baseIconSize = 64.0;
    final double canvasSize = count > 0 ? 128.0 : baseIconSize;

    final double totalWidth = canvasSize;
    final double height = canvasSize;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Calculate icon and number layout
    final double iconSize;
    final double iconX;
    final double iconY;
    final double cornerRadius;

    if (count > 0) {
      iconSize = canvasSize * 0.5;
      iconX = 0;
      iconY = (canvasSize - iconSize) / 2;
      cornerRadius = canvasSize * 0.1;
    } else {
      iconSize = canvasSize * 0.95;
      iconX = (canvasSize - iconSize) / 2;
      iconY = (canvasSize - iconSize) / 2;
      cornerRadius = canvasSize * 0.15;
    }

    final iconRect = ui.Rect.fromLTWH(iconX, iconY, iconSize, iconSize);
    final background = ui.RRect.fromRectAndRadius(iconRect, ui.Radius.circular(cornerRadius));

    _drawAppIconOrFallback(canvas, background, iconRect, iconSize, iconX, iconY);

    // Draw online/offline status indicator
    final statusColor = online ? ui.Color(AppThemeConfig.successColor.value) : ui.Color(AppThemeConfig.errorColor.value);
    final statusPaint = ui.Paint()..color = statusColor;
    final double statusSize = iconSize * 0.2;
    final double statusRadius = iconSize * 0.04;
    final double statusOffset = iconSize * 0.2;
    final statusRect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        iconX + iconSize - statusOffset, 
        iconY + iconSize - statusOffset, 
        statusSize, 
        statusSize
      ),
      ui.Radius.circular(statusRadius),
    );
    canvas.drawRRect(statusRect, statusPaint);

    // Draw unread count on the right side of the icon
    if (count > 0) {
      final text = count > 99 ? '99+' : '$count';
      final double fontSize = count > 99 
          ? canvasSize * 0.4
          : count > 9 
              ? canvasSize * 0.45
              : canvasSize * 0.5;
      
      final double numberAreaWidth = canvasSize - iconSize;
      final double bgWidth = numberAreaWidth;
      final double bgHeight = canvasSize;
      final double bgX = iconSize;
      final double bgY = 0;
      
      final bgPaint = ui.Paint()..color = const ui.Color(0xFF000000);
      final bgRadius = canvasSize * 0.05;
      final bgRect = ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(bgX, bgY, bgWidth, bgHeight),
        ui.Radius.circular(bgRadius),
      );
      canvas.drawRRect(bgRect, bgPaint);
      
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: ui.TextAlign.center,
          fontSize: fontSize,
          height: 1.0,
        ),
      )..pushStyle(
        ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontWeight: ui.FontWeight.w900,
          letterSpacing: 0,
        ),
      );
      builder.addText(text);
      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: bgWidth));
      final textY = (canvasSize - paragraph.height) / 2;
      final textXCentered = bgX + (bgWidth - paragraph.width) / 2;
      canvas.drawParagraph(paragraph, ui.Offset(textXCentered, textY));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(totalWidth.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  @override
  void onTrayIconMouseDown() async {
    if (!isSupported) return;
    await windowManager.show();
    await windowManager.focus();
  }
}

