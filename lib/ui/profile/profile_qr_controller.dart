import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../util/qr_card_generator.dart';

/// Inputs that uniquely identify a QR-card render. When any of these change
/// the cached future must be invalidated.
class QrCardRenderInputs {
  const QrCardRenderInputs({
    required this.userId,
    required this.displayName,
    required this.locale,
    required this.bottomText,
    required this.primaryColor,
    required this.textColor,
    required this.avatarPath,
    required this.avatarVersion,
    required this.qrCardVersion,
  });

  final String userId;
  final String displayName;
  final Locale locale;
  final String bottomText;
  final Color primaryColor;
  final Color textColor;
  final String? avatarPath;
  final int avatarVersion;
  final int qrCardVersion;

  String cacheKey() {
    final avatarKey = (avatarPath ?? '').isNotEmpty ? avatarPath! : 'no-avatar';
    return '$displayName|${locale.languageCode}|${_colorKey(primaryColor)}'
        '|${_colorKey(textColor)}|$avatarKey|$avatarVersion|$bottomText'
        '|$qrCardVersion';
  }

  Future<String> generate() => ContactQrCardGenerator.generateTempCard(
    userId: userId,
    displayName: displayName,
    locale: locale,
    bottomText: bottomText,
    primaryColor: primaryColor,
    textColor: textColor,
    avatarPath: avatarPath,
  );

  Future<String> saveToDirectory(Directory directory) =>
      ContactQrCardGenerator.saveToDirectory(
        directory: directory,
        userId: userId,
        displayName: displayName,
        locale: locale,
        bottomText: bottomText,
        primaryColor: primaryColor,
        textColor: textColor,
        avatarPath: avatarPath,
      );

  static String _colorKey(Color c) {
    return c.toARGB32().toRadixString(16);
  }
}

/// Owns the cached QR-card future. Returns the same future if the inputs
/// haven't changed; regenerates when [QrCardRenderInputs.cacheKey] differs.
class QrCardCache {
  Future<String>? _future;
  String? _key;

  Future<String> getOrGenerate(QrCardRenderInputs inputs) {
    final key = inputs.cacheKey();
    if (_future == null || _key != key) {
      _key = key;
      _future = inputs.generate();
    }
    return _future!;
  }

  void invalidate() {
    _future = null;
    _key = null;
  }
}

/// Prompt the user for a directory and save the rendered QR card there.
/// Returns the absolute path of the written file, or null if the user
/// cancelled.
Future<String?> pickDirectoryAndSaveQr(QrCardRenderInputs inputs) async {
  final directoryPath = await FilePicker.platform.getDirectoryPath();
  if (directoryPath == null) return null;
  return inputs.saveToDirectory(Directory(directoryPath));
}

const MethodChannel _qrSaveChannel = MethodChannel('toxee/qr_save');

/// Save an existing QR image to the user's system photo gallery.
/// Returns the platform-specific URI/path reported by the native layer.
Future<String?> saveQrToGallery(String path) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return null;
  final result = await _qrSaveChannel.invokeMethod<String>(
    'saveImageToGallery',
    {'path': path},
  );
  return result;
}
