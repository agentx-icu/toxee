import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  const MediaConversionException(this.detail, {this.isVideo = false});

  final String detail;
  final bool isVideo;

  @override
  String toString() => isVideo
      ? currentAppL10n().videoConversionFailed
      : currentAppL10n().mediaConversionFailed;
}

/// The user cancelled a conversion: the send stops, nothing to report.
class MediaConversionCancelled extends MediaConversionException {
  const MediaConversionCancelled() : super('cancelled', isVideo: true);
}

/// A running video conversion, for a progress UI.
class MediaTranscodeHandle {
  MediaTranscodeHandle._(this.id);

  final String id;

  /// 0..1.
  final ValueNotifier<double> progress = ValueNotifier(0);

  bool _cancelled = false;

  /// Stops the conversion; the send then stops too — even if the native side
  /// had already finished when the tap landed.
  Future<void> cancel() {
    _cancelled = true;
    return OutgoingMedia._channel.invokeMethod<void>('cancelTranscode', {
      'id': id,
    });
  }
}

/// Shows [handle]'s progress until [done] completes (either way).
typedef MediaTranscodePresenter =
    void Function(MediaTranscodeHandle handle, Future<void> done);

/// Converts outgoing media that desktop peers may not display (checklist M2).
/// Tox sends the file as is — there is no server to convert it — so the
/// sender does:
///
/// - HEIC photos (iPhones; Android phones set to "high efficiency") become
///   JPEG without GPS.
/// - HEVC videos (iPhones) become H.264 MP4 — Windows without the HEVC
///   extension and most Linux desktops cannot play HEVC. Only on iOS / macOS
///   for now; Android follows (Media3).
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

  /// Platforms with a photo converter. The others (Windows, Linux) do not
  /// produce HEIC themselves; a HEIC file there goes out unchanged.
  static bool Function() hasConverter = () =>
      Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

  /// Platforms with a video converter.
  static bool Function() hasVideoConverter = () =>
      Platform.isIOS || Platform.isMacOS;

  /// The signed-in account, for UIKit sends (they do not carry one).
  static Future<String?> Function() currentAccount =
      Prefs.getCurrentAccountToxId;

  /// Installed by the app to show a video conversion's progress.
  static MediaTranscodePresenter? presenter;

  static final Map<String, MediaTranscodeHandle> _running = {};
  static int _nextId = 0;
  static bool _listening = false;

  /// Routes the UIKit's own media sends (desktop paste, drag and drop)
  /// through [prepare] too, before their message is created, so the chat
  /// shows the converted file. [onFailure] tells the user why a send stopped.
  static void installForUiKit({required void Function(String) onFailure}) {
    TencentCloudChatMessageSeparateDataProvider.outgoingMediaPreparer = (
      path,
    ) async {
      try {
        final account = await currentAccount() ?? '';
        return await prepare(path, accountKey: account);
      } on MediaConversionCancelled {
        return null;
      } on MediaConversionException catch (e) {
        onFailure(e.toString());
        return null;
      }
    };
  }

  /// The path to send for [path]: [path] itself, or a converted copy.
  /// Throws [MediaConversionException] when a needed conversion fails, and
  /// [MediaConversionCancelled] when the user cancelled it.
  static Future<String> prepare(
    String path, {
    required String accountKey,
  }) async {
    final mime = GallerySaver.sniffMimeType(await _head(path));
    if (mime == 'image/heic' && hasConverter()) {
      return _convert(path, accountKey, 'jpg', isVideo: false);
    }
    // By content, as the name may lack an extension; the native side needs
    // one to open the file, so it is passed along.
    const containers = {
      'video/mp4': 'mp4',
      'video/quicktime': 'mov',
      'video/x-m4v': 'm4v',
    };
    final containerExt = containers[mime];
    if (containerExt != null && hasVideoConverter()) {
      final String? codec;
      try {
        codec = await _channel.invokeMethod<String>('probeVideo', {
          'source': path,
          'ext': containerExt,
        });
      } catch (e) {
        throw MediaConversionException('probe: $e', isVideo: true);
      }
      // 'hvc1' / 'hev1': HEVC. Anything else (H.264, or a file AVFoundation
      // cannot read at all) goes as it is.
      if (codec == 'hvc1' || codec == 'hev1') {
        return _convert(
          path,
          accountKey,
          'mp4',
          isVideo: true,
          sourceExt: containerExt,
        );
      }
    }
    return path;
  }

  static Future<String> _convert(
    String path,
    String accountKey,
    String ext, {
    required bool isVideo,
    String? sourceExt,
  }) async {
    if (accountKey.isEmpty) {
      throw MediaConversionException('no account', isVideo: isVideo);
    }
    String? part;
    MediaTranscodeHandle? handle;
    final done = Completer<void>();
    try {
      final dir = Directory(await outputRoot(accountKey));
      await dir.create(recursive: true);
      final target = await _reserve(dir, p.basenameWithoutExtension(path), ext);
      part = '$target.part';
      if (isVideo) {
        handle = _start();
        presenter?.call(handle, done.future);
        await _channel.invokeMethod<void>('transcodeToH264', {
          'id': handle.id,
          'source': path,
          'ext': sourceExt,
          'target': part,
        });
        if (handle._cancelled) {
          throw PlatformException(code: 'CANCELLED');
        }
      } else {
        await _channel.invokeMethod<void>('heicToJpeg', {
          'source': path,
          'target': part,
        });
      }
      await File(part).rename(target);
      return target;
    } on PlatformException catch (e) {
      if (part != null) await _delete(part);
      if (e.code == 'CANCELLED') throw const MediaConversionCancelled();
      if (e.code == 'UNSUPPORTED') return path; // Android before 9
      AppLogger.warn('[OutgoingMedia] conversion failed: ${e.message}');
      throw MediaConversionException(e.message ?? e.code, isVideo: isVideo);
    } catch (e) {
      // Includes a missing channel: this platform should have a converter.
      if (part != null) await _delete(part);
      AppLogger.warn('[OutgoingMedia] conversion failed: $e');
      throw MediaConversionException('$e', isVideo: isVideo);
    } finally {
      if (handle != null) _running.remove(handle.id);
      done.complete();
    }
  }

  static MediaTranscodeHandle _start() {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'progress') return;
        final args = call.arguments as Map<Object?, Object?>;
        final value = args['progress'];
        _running[args['id']]?.progress.value = value is num
            ? value.toDouble().clamp(0, 1)
            : 0;
      });
    }
    final handle = MediaTranscodeHandle._('t${_nextId++}');
    _running[handle.id] = handle;
    return handle;
  }

  /// A target name no other conversion uses, reserved by creating its
  /// `.part` file exclusively: two sends of one file at once get two names.
  static Future<String> _reserve(Directory dir, String stem, String ext) async {
    final safeStem = stem.isEmpty ? 'media' : stem;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var n = 0; ; n++) {
      final candidate = p.join(dir.path, '${safeStem}_${stamp}_$n.$ext');
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
