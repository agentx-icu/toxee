import 'dart:io';
import 'package:flutter/services.dart';
import 'prefs.dart';

/// macOS holds security-scoped grants through asynchronous/native transfers.
abstract final class DownloadDirectoryAccess {
  static const _channel = MethodChannel('toxee/download_directory');

  static Future<String> select(
    String path, {
    MethodChannel channel = _channel,
    bool? isMacOS,
  }) async {
    final selected = (isMacOS ?? Platform.isMacOS)
        ? await channel.invokeMethod<String>('retain', {'path': path})
        : path;
    if (selected == null) {
      throw StateError('Downloads folder access was denied');
    }
    await Prefs.setDownloadsDirectory(selected);
    return selected;
  }

  /// False means a stale/denied grant was removed so receives use the default.
  static Future<bool> restore({
    MethodChannel channel = _channel,
    bool? isMacOS,
  }) async {
    if (!(isMacOS ?? Platform.isMacOS)) return true;
    final path = await Prefs.getDownloadsDirectory();
    if (path == null || path.isEmpty) return true;
    try {
      final resolved = await channel.invokeMethod<String>('restore', {
        'path': path,
      });
      if (resolved == null) {
        throw StateError('Downloads folder access was denied');
      }
      await Prefs.setDownloadsDirectory(resolved);
      return true;
    } catch (_) {
      await Prefs.setDownloadsDirectory(null);
      return false;
    }
  }
}
