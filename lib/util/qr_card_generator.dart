import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_theme_config.dart';

class ContactQrCardGenerator {
  // ──────────────────────────────────────────────
  //  Exported PNG palette — locked to a light brand
  //  composition regardless of the runtime theme.
  //
  //  The card is rendered to a PNG that lives outside
  //  the app (saved to disk, shared, exported), so it
  //  must read consistently on any background. These
  //  constants are pinned to the same values used by
  //  AppThemeConfig where the brand intent matches.
  // ──────────────────────────────────────────────

  /// Card surface — always pure white so the QR is high-contrast in any host.
  static const Color _kCardBg = Colors.white;
  /// Soft drop-shadow tint under the card.
  static const Color _kCardShadow = Colors.black12;
  /// Avatar ring stroke on top of a photo avatar (white @ 90%).
  static const Color _kAvatarRing = Color(0xE6FFFFFF);
  /// Foreground for the initial letter inside the accent-filled avatar circle.
  static const Color _kAvatarInitialFg = Colors.white;
  /// Fallback body-text color in [_drawText] when callers don't override.
  static const Color _kDefaultTextColor = Colors.black87;

  /// Outer card radius (custom for the exported card — slightly more rounded
  /// than [AppRadii.card] to read as a "card" in shared previews/galleries).
  static const double _kCardRadius = 36;

  static const Color _defaultPrimary = AppThemeConfig.primaryColor;
  static const Color _defaultText = AppThemeConfig.primaryTextColorLight;

  static Future<Uint8List> _renderBytes({
    required String userId,
    required String displayName,
    required Locale locale,
    required String bottomText,
    Color primaryColor = _defaultPrimary,
    Color textColor = _defaultText,
    String? avatarPath,
  }) async {
    const double width = 640;
    const double height = 860;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final bgPaint = ui.Paint()..color = _kCardBg;
    final shadowPaint = ui.Paint()
      ..color = _kCardShadow
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    const rect = ui.Rect.fromLTWH(0, 0, width, height);
    final rrect = ui.RRect.fromRectAndRadius(
        rect, const ui.Radius.circular(_kCardRadius));
    canvas.drawRRect(rrect.shift(const ui.Offset(0, 4)), shadowPaint);
    canvas.drawRRect(rrect, bgPaint);

    final accentPaint = ui.Paint()..color = primaryColor;
    const avatarCenter = ui.Offset(width / 2, 110);
    final avatarImage = await _loadAvatarImage(avatarPath);
    if (avatarImage != null) {
      final avatarRect = ui.Rect.fromCircle(center: avatarCenter, radius: 60);
      canvas.save();
      final path = ui.Path()..addOval(avatarRect);
      canvas.clipPath(path);
      paintImage(canvas: canvas, rect: avatarRect, image: avatarImage, fit: BoxFit.cover);
      canvas.restore();
      // Draw thin border
      canvas.drawCircle(avatarCenter, 60, ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = _kAvatarRing);
    } else {
      canvas.drawCircle(avatarCenter, 60, accentPaint);
      final displayInitial = displayName.trim().isNotEmpty ? displayName.trim()[0].toUpperCase() : '?';
      _drawText(
        canvas: canvas,
        text: displayInitial,
        offset: ui.Offset(avatarCenter.dx - 60, avatarCenter.dy - 38),
        width: 120,
        fontSize: 56,
        color: _kAvatarInitialFg,
        weight: FontWeight.bold,
        align: TextAlign.center,
      );
    }

    final nameColor = textColor.computeLuminance() > 0.6 ? AppThemeConfig.primaryTextColorLight : textColor;

    _drawText(
      canvas: canvas,
      text: displayName,
      offset: const ui.Offset(60, 205),
      width: width - 120,
      fontSize: 30,
      color: nameColor,
      weight: FontWeight.w600,
      align: TextAlign.center,
    );

    final qrPainter = QrPainter(
      data: userId,
      version: QrVersions.auto,
      gapless: true,
    );
    final qrImage = await qrPainter.toImage(380);
    final qrRect = ui.Rect.fromCenter(
        center: const ui.Offset(width / 2, 480),
        width: 380,
        height: 380);
    paintImage(canvas: canvas, rect: qrRect, image: qrImage);

    _drawText(
      canvas: canvas,
      text: bottomText,
      offset: const ui.Offset(60, 750),
      width: width - 120,
      fontSize: 20,
      color: primaryColor,
      weight: FontWeight.w600,
      align: TextAlign.center,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to encode QR card image');
    }
    return byteData.buffer.asUint8List();
  }

  static void _drawText({
    required ui.Canvas canvas,
    required String text,
    required ui.Offset offset,
    required double width,
    double fontSize = 24,
    Color color = _kDefaultTextColor,
    FontWeight weight = FontWeight.w500,
    TextAlign align = TextAlign.left,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: align,
        fontSize: fontSize,
        fontWeight: weight,
      ),
    )..pushStyle(ui.TextStyle(color: color));
    builder.addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    canvas.drawParagraph(paragraph, offset);
  }

  static Future<String> generateTempCard({
    required String userId,
    required String displayName,
    required Locale locale,
    required String bottomText,
    Color primaryColor = _defaultPrimary,
    Color textColor = _defaultText,
    String? avatarPath,
  }) async {
    final bytes = await _renderBytes(
      userId: userId,
      displayName: displayName,
      locale: locale,
      bottomText: bottomText,
      primaryColor: primaryColor,
      textColor: textColor,
      avatarPath: avatarPath,
    );
    // Use application support directory instead of temporary directory
    // This ensures the file persists and is accessible
    final dir = await getApplicationSupportDirectory();
    final shortId = userId.length > 10 ? userId.substring(0, 10) : userId;
    // Use a more unique filename to avoid conflicts
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${dir.path}/qr_card_${shortId}_$timestamp.png';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    // Clean up old QR card files (keep only the latest 5)
    _cleanupOldQrCards(dir, shortId);
    return file.path;
  }

  static void _cleanupOldQrCards(Directory dir, String shortId) {
    try {
      final files = dir.listSync()
          .whereType<File>()
          .where((f) => f.path.contains('qr_card_$shortId'))
          .toList();
      if (files.length > 5) {
        // Sort by modification time, oldest first
        files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        // Delete oldest files, keep only the latest 5
        for (var i = 0; i < files.length - 5; i++) {
          files[i].deleteSync();
        }
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  static Future<String> saveToDirectory({
    required Directory directory,
    required String userId,
    required String displayName,
    required Locale locale,
    required String bottomText,
    Color primaryColor = _defaultPrimary,
    Color textColor = _defaultText,
    String? avatarPath,
  }) async {
    final bytes = await _renderBytes(
      userId: userId,
      displayName: displayName,
      locale: locale,
      bottomText: bottomText,
      primaryColor: primaryColor,
      textColor: textColor,
      avatarPath: avatarPath,
    );
    final shortId = userId.length > 10 ? userId.substring(0, 10) : userId;
    final file = File('${directory.path}/qr_card_$shortId.png');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<ui.Image?> _loadAvatarImage(String? path) async {
    if (path == null || path.isEmpty) return null;
    final completer = Completer<ui.Image>();
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      ui.decodeImageFromList(
        bytes,
        (image) => completer.complete(image),
      );
      return await completer.future;
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      return null;
    }
  }
}

