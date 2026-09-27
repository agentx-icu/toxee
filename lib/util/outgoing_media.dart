import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';

import 'app_l10n.dart';
import 'app_paths.dart';
import 'gallery_saver.dart';
import 'logger.dart';
import 'prefs.dart';

/// A photo / video that had to be converted before sending could not be.
/// The send stops: sending the original would deliver exactly the format the
/// conversion exists to avoid.
class MediaConversionException implements Exception {
  const MediaConversionException(this.detail);

  final String detail;

  @override
  String toString() => currentAppL10n().mediaConversionFailed;
}

/// Converts outgoing media that desktop peers may not display (checklist M2):
/// iPhones (and Android phones set to "high efficiency") shoot HEIC photos,
/// which Windows / Linux often cannot show. Tox sends the file as is — there
/// is no server to convert it — so the sender does, into JPEG (without GPS).
///
/// The result lives in the account's own storage
/// (`account_data/<prefix>/outgoing_media`), not a temp dir: the sender's
/// bubble and a queued offline send read it by path later.
class OutgoingMedia {
  OutgoingMedia._();

  static const MethodChannel _channel = MethodChannel('toxee/media_transcode');

  static Future<String> Function(String accountKey) outputRoot =
      _defaultOutputRoot;

  static Future<String> _defaultOutputRoot(String accountKey) async =>
      p.join(await AppPaths.getAccountDataRoot(accountKey), 'outgoing_media');

  /// Platforms with a converter. The others (Windows, Linux) do not produce
  /// HEIC themselves; a HEIC file there goes out unchanged.
  static bool Function() hasConverter = () =>
      Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

  /// Routes the UIKit's own media sends (desktop paste, drag and drop)
  /// through [prepare] too, before their message is created, so the chat
  /// shows the converted file. [onFailure] tells the user why a send stopped.
  static void installForUiKit({required void Function(String) onFailure}) {
    TencentCloudChatMessageSeparateDataProvider.outgoingMediaPreparer = (
      path,
    ) async {
      try {
        final account = await Prefs.getCurrentAccountToxId() ?? '';
        return await prepare(path, accountKey: account);
      } on MediaConversionException catch (e) {
        onFailure(e.toString());
        return null;
      }
    };
  }

  /// The path to send for [path]: [path] itself, or a converted copy.
  /// Throws [MediaConversionException] when a needed conversion fails.
  static Future<String> prepare(
    String path, {
    required String accountKey,
  }) async {
    final mime = GallerySaver.sniffMimeType(await _head(path));
    if (mime != 'image/heic' || !hasConverter()) return path;
    if (accountKey.isEmpty) {
      throw const MediaConversionException('no account');
    }
    String? part;
    try {
      final dir = Directory(await outputRoot(accountKey));
      await dir.create(recursive: true);
      final target = await _reserve(dir, p.basenameWithoutExtension(path));
      part = '$target.part';
      await _channel.invokeMethod<void>('heicToJpeg', {
        'source': path,
        'target': part,
      });
      await File(part).rename(target);
      return target;
    } on PlatformException catch (e) {
      if (part != null) await _delete(part);
      if (e.code == 'UNSUPPORTED') return path; // Android before 9
      AppLogger.warn('[OutgoingMedia] HEIC conversion failed: ${e.message}');
      throw MediaConversionException(e.message ?? e.code);
    } catch (e) {
      // Includes a missing channel: this platform should have a converter.
      if (part != null) await _delete(part);
      AppLogger.warn('[OutgoingMedia] HEIC conversion failed: $e');
      throw MediaConversionException('$e');
    }
  }

  /// A target name no other conversion uses, reserved by creating its
  /// `.part` file exclusively: two sends of one photo at once get two names.
  static Future<String> _reserve(Directory dir, String stem) async {
    final safeStem = stem.isEmpty ? 'media' : stem;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var n = 0; ; n++) {
      final candidate = p.join(dir.path, '${safeStem}_${stamp}_$n.jpg');
      if (File(candidate).existsSync()) continue;
      try {
        await File('$candidate.part').create(exclusive: true);
        return candidate;
      } on FileSystemException {
        // Taken meanwhile: try the next name. Anything else (permissions,
        // a full disk) is a storage failure for the caller.
        // (It may already be renamed to its final name.)
        if (File('$candidate.part').existsSync() ||
            File(candidate).existsSync()) {
          continue;
        }
        rethrow;
      }
    }
  }

  static Future<List<int>> _head(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      return await file.read(64);
    } catch (_) {
      return const [];
    } finally {
      await file?.close();
    }
  }

  static Future<void> _delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
