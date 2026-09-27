import 'dart:convert';

import 'package:flutter/services.dart';

import '../../util/logger.dart';
import 'master_detail_transition.dart';

/// Brings the user back to the conversation they had open when the OS
/// reclaimed the app in the background (checklist B6).
///
/// The open conversation is kept in Flutter's restoration data, which the OS
/// hands back only after a SYSTEM kill (Android saved instance state, iOS
/// state restoration) — never after the user swiped the app away or
/// rebooted, when starting on the conversation list is what they expect.
///
/// Two phases, so nothing can erase the saved marker before it is used:
/// [readSaved] first (the restore decision), then [save] snapshots of the UI.
class OpenChatRestoration {
  OpenChatRestoration({RestorationManager? manager})
    : _manager = manager ?? ServicesBinding.instance.restorationManager;

  static const key = 'toxee.openChat';

  final RestorationManager _manager;
  RestorationBucket? _bucket;
  String? _written;

  /// The conversation saved before a system kill, for [account] only; null
  /// after a normal launch or when restoration is unavailable.
  Future<ChatTarget?> readSaved(String account) async {
    try {
      _bucket = await _manager.rootBucket;
    } catch (e) {
      AppLogger.warn('[OpenChatRestoration] no restoration data: $e');
      return null;
    }
    final raw = _bucket?.read<String>(key);
    _written = raw;
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['account'] != account) return null;
      final target = ChatTarget(
        userID: json['userID'] as String?,
        groupID: json['groupID'] as String?,
      );
      return target.isValid ? target : null;
    } catch (_) {
      return null;
    }
  }

  /// Records [target] (null: no conversation on screen) for [account] and
  /// hands it to the engine at once: the OS reads the engine's copy when it
  /// saves state, possibly after the last frame.
  void save(String account, ChatTarget? target) {
    final bucket = _bucket;
    if (bucket == null) return;
    final raw = target == null || !target.isValid
        ? null
        : jsonEncode({
            'account': account,
            'userID': target.userID,
            'groupID': target.groupID,
          });
    if (raw == _written) return;
    _written = raw;
    if (raw == null) {
      bucket.remove<String>(key);
    } else {
      bucket.write<String>(key, raw);
    }
    _manager.flushData();
  }
}
