import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_camera.dart';

import 'app_paths.dart';
import 'logger.dart';

/// A photo / video taken for a chat whose app process was reclaimed while the
/// system camera was in front (checklist M9), waiting for its account's user
/// to send or discard it.
class RecoveredCapture {
  const RecoveredCapture({
    required this.accountKey,
    required this.userId,
    required this.path,
    required this.isVideo,
    required this.capturedAt,
    this.sourcePath,
  });

  final String accountKey;
  final String userId;

  /// The staged file in the account's own storage.
  final String path;
  final bool isVideo;
  final DateTime capturedAt;

  /// Where the picker left it, until the move into [path] has happened.
  final String? sourcePath;

  Map<String, Object> toJson() => {
    'accountKey': accountKey,
    'userId': userId,
    'path': path,
    'isVideo': isVideo,
    'capturedAt': capturedAt.millisecondsSinceEpoch,
    if (sourcePath != null) 'sourcePath': sourcePath!,
  };

  static RecoveredCapture? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['capturedAt'];
    final values = [json['accountKey'], json['userId'], json['path']];
    if (values.any((v) => v is! String || v.isEmpty) || at is! int) {
      return null;
    }
    final source = json['sourcePath'];
    return RecoveredCapture(
      accountKey: json['accountKey'] as String,
      userId: json['userId'] as String,
      path: json['path'] as String,
      isVideo: json['isVideo'] == true,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(at),
      sourcePath: source is String && source.isNotEmpty ? source : null,
    );
  }
}

/// Android can reclaim toxee while the system camera is in front; the result
/// then reaches a new process where nothing awaits it. This keeps it:
///
/// 1. [remember] the chat right before the camera opens; [forget] when the
///    pick returns (sent, cancelled or failed).
/// 2. After a session is ready, [stage] collects the picker's lost result
///    (which clears the picker's own record) and moves it — with the account
///    and chat it was taken for — into that account's storage
///    (`account_data/<prefix>/captures`, so deleting the account deletes it
///    too). The record is written before the file moves, and the move is a
///    rename, so a reclaim at any point leaves something [pendingFor] can
///    finish.
/// 3. [pendingFor] offers it to the same account only, never another;
///    [resolve] ends it. A sent file stays: the send (or its offline queue)
///    reads it by path.
///
/// Staging, resolving and purging run one at a time, so a logout cannot slip
/// between a staging and its record.
class CameraCaptureRecovery {
  CameraCaptureRecovery._();

  static const _targetKey = 'camera_capture_target';

  /// A camera left open longer than this no longer points at a live intent.
  static const targetTtl = Duration(hours: 1);

  /// An unanswered recovered capture is dropped after this.
  static const pendingTtl = Duration(days: 1);

  static Future<String> Function(String accountKey) capturesRoot =
      _defaultCapturesRoot;

  static Future<String> _defaultCapturesRoot(String accountKey) async =>
      p.join(await AppPaths.getAccountDataRoot(accountKey), 'captures');

  static Future<void> _tail = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  static Future<void> remember({
    required String accountKey,
    required String userId,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _targetKey,
      jsonEncode({
        'accountKey': accountKey,
        'userId': userId,
        'at': (now ?? DateTime.now()).millisecondsSinceEpoch,
      }),
    );
  }

  static Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_targetKey);
  }

  /// Moves a lost camera result (from [retrieve], which clears the picker's
  /// copy) into the owning account's storage. Without a fresh target the
  /// result has no known destination and is deleted.
  static Future<void> stage({
    Future<LostCameraCapture?> Function() retrieve =
        TencentCloudChatMessageCamera.retrieveLostCapture,
    DateTime? now,
  }) => _serialized(() => _stage(retrieve, now ?? DateTime.now()));

  static Future<void> _stage(
    Future<LostCameraCapture?> Function() retrieve,
    DateTime now,
  ) async {
    // Everything that can be prepared is prepared BEFORE retrieve(): that
    // call clears the picker's record, so only the record write may follow.
    final prefs = await SharedPreferences.getInstance();
    final target = _readTarget(prefs.getString(_targetKey));
    final fresh = target != null && now.difference(target.at) <= targetTtl;
    Directory? dir;
    RecoveredCapture? previous;
    if (fresh) {
      dir = Directory(await capturesRoot(target.accountKey));
      await dir.create(recursive: true);
      previous = await _readRecord(dir, target.accountKey);
    }
    final LostCameraCapture? lost;
    try {
      lost = await retrieve();
    } catch (e) {
      AppLogger.warn('[CameraCaptureRecovery] retrieve failed: $e');
      return;
    }
    if (lost == null) {
      // The camera returned normally, or the capture never happened.
      if (target != null) await forget();
      return;
    }
    final source = lost.path;
    if (lost.error != null || source == null) {
      AppLogger.warn('[CameraCaptureRecovery] lost capture: ${lost.error}');
      await forget();
      return;
    }
    if (!fresh || dir == null) {
      AppLogger.warn('[CameraCaptureRecovery] no chat for a lost capture');
      await _delete(source);
      await forget();
      return;
    }
    final capture = RecoveredCapture(
      accountKey: target.accountKey,
      userId: target.userId,
      path: _freshPath(dir, now, p.basename(source)),
      isVideo: lost.isVideo,
      capturedAt: now,
      sourcePath: source,
    );
    // Record first: from here on the capture is findable whatever happens.
    await _writeRecord(dir, capture);
    await forget();
    // One pending capture per account: the newer one replaces it.
    if (previous != null && previous.path != capture.path) {
      await _delete(previous.path);
    }
    await _finishMove(dir, capture);
  }

  /// A staged file name no other capture in [dir] uses (the directory can be
  /// shared by accounts with the same storage prefix).
  static String _freshPath(Directory dir, DateTime now, String name) {
    for (var n = 0; ; n++) {
      final candidate = p.join(dir.path, '${now.millisecondsSinceEpoch}_${n}_$name');
      if (!File(candidate).existsSync()) return candidate;
    }
  }

  /// Moves the file from the picker's cache into the staged path (a rename:
  /// same partition, nothing half-copied) and drops the source from the
  /// record. Idempotent, so an interrupted staging can be finished later.
  /// Null only when neither file exists any more; a failed move returns
  /// [capture] unchanged for the next attempt.
  static Future<RecoveredCapture?> _finishMove(
    Directory dir,
    RecoveredCapture capture,
  ) async {
    final source = capture.sourcePath;
    if (source == null) return capture;
    try {
      if (!File(capture.path).existsSync()) {
        if (!File(source).existsSync()) return null;
        try {
          await File(source).rename(capture.path);
        } on FileSystemException {
          // Different file systems: copy beside it, then rename, so a copy
          // cut short never looks like the finished file.
          final part = '${capture.path}.part';
          await File(source).copy(part);
          await File(part).rename(capture.path);
          await _delete(source);
        }
      }
      final moved = RecoveredCapture(
        accountKey: capture.accountKey,
        userId: capture.userId,
        path: capture.path,
        isVideo: capture.isVideo,
        capturedAt: capture.capturedAt,
      );
      await _writeRecord(dir, moved);
      return moved;
    } catch (e) {
      AppLogger.warn('[CameraCaptureRecovery] staging move failed: $e');
      return capture;
    }
  }

  /// The capture [accountKey] still has to answer, if any. Expired or lost
  /// ones are deleted here.
  static Future<RecoveredCapture?> pendingFor(
    String accountKey, {
    DateTime? now,
  }) => _serialized(() async {
    if (accountKey.isEmpty) return null;
    final dir = Directory(await capturesRoot(accountKey));
    final record = await _readRecord(dir, accountKey);
    if (record == null) return null;
    if ((now ?? DateTime.now()).difference(record.capturedAt) > pendingTtl) {
      await _drop(dir, record);
      return null;
    }
    final moved = await _finishMove(dir, record);
    if (moved == null) {
      await _drop(dir, record); // both files gone: nothing left to offer
      return null;
    }
    // A move that failed this time stays recorded for the next start.
    return File(moved.path).existsSync() ? moved : null;
  });

  /// Ends [capture]: a sent file stays (the send reads it by path); a
  /// discarded one is deleted.
  static Future<void> resolve(RecoveredCapture capture, {required bool sent}) =>
      _serialized(() async {
        final dir = Directory(await capturesRoot(capture.accountKey));
        final record = await _readRecord(dir, capture.accountKey);
        if (record == null || record.path != capture.path) return;
        if (sent) {
          await _delete(_recordPath(dir, capture.accountKey));
        } else {
          await _drop(dir, record);
        }
      });

  /// Drops [accountKey]'s unanswered capture (logout). Never throws.
  static Future<void> purge(String accountKey) => _serialized(() async {
    if (accountKey.isEmpty) return;
    try {
      final dir = Directory(await capturesRoot(accountKey));
      final record = await _readRecord(dir, accountKey);
      if (record != null) await _drop(dir, record);
    } catch (e) {
      AppLogger.warn('[CameraCaptureRecovery] purge failed: $e');
    }
  });

  static ({String accountKey, String userId, DateTime at})? _readTarget(
    String? raw,
  ) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final account = json['accountKey'], user = json['userId'];
      final at = json['at'];
      if (account is! String || user is! String || at is! int) return null;
      if (account.isEmpty || user.isEmpty) return null;
      return (
        accountKey: account,
        userId: user,
        at: DateTime.fromMillisecondsSinceEpoch(at),
      );
    } on FormatException {
      return null;
    }
  }

  /// One record per full account key: two accounts can share a storage
  /// prefix, and neither may touch the other's capture.
  static String _recordPath(Directory dir, String accountKey) =>
      p.join(dir.path, 'pending_${accountKey.toUpperCase()}.json');

  static Future<RecoveredCapture?> _readRecord(
    Directory dir,
    String accountKey,
  ) async {
    final file = File(_recordPath(dir, accountKey));
    if (!await file.exists()) return null;
    try {
      final record = RecoveredCapture.fromJson(
        jsonDecode(await file.readAsString()),
      );
      return record?.accountKey == accountKey ? record : null;
    } on FormatException {
      return null;
    }
  }

  /// Write-then-rename so a reclaim mid-write never leaves half a record.
  static Future<void> _writeRecord(Directory dir, RecoveredCapture c) async {
    final path = _recordPath(dir, c.accountKey);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(jsonEncode(c.toJson()), flush: true);
    await tmp.rename(path);
  }

  static Future<void> _drop(Directory dir, RecoveredCapture record) async {
    await _delete(record.path);
    final source = record.sourcePath;
    if (source != null) await _delete(source);
    await _delete(_recordPath(dir, record.accountKey));
  }

  static Future<void> _delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.warn('[CameraCaptureRecovery] delete failed: $e');
    }
  }
}
