import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_viewer/tencent_cloud_chat_message_viewer.dart';

import 'logger.dart';

/// Saves images and videos to the system photo library (Android MediaStore,
/// iOS Photos) through the native `toxee/qr_save` channel (checklist M3).
///
/// Received files often have no extension, or the sender's, so the type
/// comes from the file's first bytes; the extension is only a fallback.
class GallerySaver {
  GallerySaver._();

  static const MethodChannel _channel = MethodChannel('toxee/qr_save');

  /// Routes the chat media viewer's Save to the photo library on phones.
  static void install({bool? isMobile}) {
    if (!(isMobile ?? (Platform.isAndroid || Platform.isIOS))) return;
    MessageViewerMediaSaver.defaultGallerySaver = saveMessageMedia;
  }

  /// Saves [path] as [mimeType]; returns the native uri / path. Throws a
  /// [PlatformException] when the library refuses it (e.g. permission).
  static Future<String?> saveFile(
    String path, {
    String mimeType = 'image/png',
    String? displayName,
  }) {
    return _channel.invokeMethod<String>('saveImageToGallery', {
      'path': path,
      'mimeType': mimeType,
      if (displayName != null) 'displayName': displayName,
    });
  }

  /// [MessageViewerGallerySaver]: null when the file is not an image / video
  /// the library takes (the save dialog handles it then).
  static Future<MessageViewerMediaSaveResult?> saveMessageMedia({
    required String path,
    required MessageViewerMediaKind kind,
    required String fileName,
  }) async {
    final mimeType = await mimeTypeOf(path, kind, isIOS: Platform.isIOS);
    if (mimeType == null) return null;
    try {
      await saveFile(
        path,
        mimeType: mimeType,
        displayName: withExtension(fileName, mimeType),
      );
      return MessageViewerMediaSaveResult.saved;
    } catch (e) {
      AppLogger.warn('[GallerySaver] $mimeType not saved: $e');
      return MessageViewerMediaSaveResult.failed;
    }
  }

  /// The library MIME type for [path] if its content is a [kind] the photo
  /// library accepts on this platform, else null.
  static Future<String?> mimeTypeOf(
    String path,
    MessageViewerMediaKind kind, {
    required bool isIOS,
  }) async {
    final mime = sniffMimeType(await _head(path)) ?? _byExtension(path);
    if (mime == null) return null;
    final isVideo = mime.startsWith('video/');
    if (isVideo != (kind == MessageViewerMediaKind.video)) return null;
    // Photos imports neither WebM nor Matroska.
    if (isIOS && (mime == 'video/webm' || mime == 'video/x-matroska')) {
      return null;
    }
    return mime;
  }

  /// Magic-byte sniffing for the formats a photo library stores.
  static String? sniffMimeType(List<int> b) {
    bool at(int offset, List<int> sig) {
      if (b.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    String ascii(int from, int to) =>
        b.length < to ? '' : String.fromCharCodes(b.sublist(from, to));

    if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (ascii(0, 4) == 'GIF8') return 'image/gif';
    if (ascii(0, 4) == 'RIFF' && ascii(8, 12) == 'WEBP') return 'image/webp';
    if (ascii(0, 2) == 'BM') return 'image/bmp';
    if (at(0, const [0x1A, 0x45, 0xDF, 0xA3])) {
      // The EBML header's DocType names WebM; the head read covers it.
      return String.fromCharCodes(b).contains('webm')
          ? 'video/webm'
          : 'video/x-matroska';
    }
    if (ascii(4, 8) == 'ftyp') {
      final brand = ascii(8, 12);
      const heif = {'heic', 'heix', 'hevc', 'heim', 'heis', 'mif1', 'msf1'};
      if (heif.contains(brand)) return 'image/heic';
      if (brand == 'avif') return 'image/avif';
      if (brand == 'qt  ') return 'video/quicktime';
      if (brand.startsWith('3g')) return 'video/3gpp';
      if (brand == 'M4V ') return 'video/x-m4v';
      return 'video/mp4';
    }
    return null;
  }

  static const _extensions = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/bmp': 'bmp',
    'image/heic': 'heic',
    'image/avif': 'avif',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/3gpp': '3gp',
    'video/x-m4v': 'm4v',
    'video/webm': 'webm',
    'video/x-matroska': 'mkv',
  };

  /// [fileName] ending in an extension that matches [mimeType]; the library
  /// (and the apps that open the item later) go by the name.
  static String withExtension(String fileName, String mimeType) {
    final ext = _extensions[mimeType];
    if (ext == null) return fileName;
    final lower = fileName.toLowerCase();
    final same = _extensions.entries
        .where((e) => e.key == mimeType)
        .map((e) => '.${e.value}')
        .followedBy([
          if (mimeType == 'image/jpeg') '.jpeg',
          if (mimeType == 'image/heic') '.heif',
        ]);
    if (same.any(lower.endsWith)) return fileName;
    return '$fileName.$ext';
  }

  static String? _byExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot < path.lastIndexOf(Platform.pathSeparator)) return null;
    final ext = path.substring(dot + 1).toLowerCase();
    if (ext == 'jpeg') return 'image/jpeg';
    if (ext == 'heif') return 'image/heic';
    for (final e in _extensions.entries) {
      if (e.value == ext) return e.key;
    }
    return null;
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
}
