import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'logger.dart';

/// A file picked for a chat whose process Android reclaimed while the
/// document picker was in front (checklist M9), as the native side kept it
/// (android/.../LostFilePickChannel.kt).
@immutable
class LostFilePick {
  const LostFilePick({
    required this.path,
    required this.name,
    required this.accountKey,
    required this.userId,
    required this.pickedAt,
    this.error,
  });

  /// The copy in the app cache (a missing file when [error] is set).
  final String path;
  final String name;
  final String accountKey;
  final String userId;
  final DateTime pickedAt;
  final String? error;

  static LostFilePick? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'], name = raw['name'];
    final account = raw['account'], peer = raw['peer'], at = raw['at'];
    if (path is! String || path.isEmpty) return null;
    return LostFilePick(
      path: path,
      name: name is String && name.isNotEmpty ? name : 'file',
      accountKey: account is String ? account : '',
      userId: peer is String ? peer : '',
      pickedAt: DateTime.fromMillisecondsSinceEpoch(at is int ? at : 0),
      error: raw['status'] == 'ready'
          ? null
          : (raw['error'] as String?) ?? 'copy ${raw['status']}',
    );
  }
}

/// The Dart end of the native lost-pick keeper. Android only; a no-op
/// elsewhere (iOS pickers run in-process, desktop pickers are not reclaimed).
class LostFilePickChannel {
  LostFilePickChannel._();

  static const _channel = MethodChannel('toxee/lost_file_pick');

  @visibleForTesting
  static bool Function() isSupported = () => Platform.isAndroid;

  /// Right before the picker opens for [userId]'s chat.
  static Future<void> arm({
    required String accountKey,
    required String userId,
  }) => _call('arm', {'account': accountKey, 'peer': userId});

  /// After the pick returned in this process, whatever the outcome.
  static Future<void> disarm() => _call('disarm');

  /// Every lost pick, oldest first; waits for copies in progress. Each stays
  /// until [ack]ed.
  static Future<List<LostFilePick>> peek() async {
    if (!isSupported()) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('peek');
      return [...?raw?.map(LostFilePick.fromMap).whereType<LostFilePick>()];
    } catch (e) {
      AppLogger.warn('[LostFilePick] peek failed: $e');
      return const [];
    }
  }

  /// The pick at [path] is recorded (or dropped): the native side forgets it.
  static Future<void> ack(String path) => _call('ack', {'path': path});

  static Future<void> _call(String method, [Map<String, Object?>? args]) async {
    if (!isSupported()) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      AppLogger.warn('[LostFilePick] $method failed: $e');
    }
  }
}
