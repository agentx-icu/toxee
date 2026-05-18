// Session-scoped cache of per-group "userID → last-message-timestamp (seconds)"
// maps. Used by GroupMemberListWrapper to sort members by recency without
// re-scanning the entire group history on every member-list mount.
//
// The cache subscribes to the FakeIM message bus once and updates entries
// in place when new group messages arrive, so we never re-scan after the
// first lazy build.
import 'dart:async';

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../sdk_fake/fake_event_bus.dart';
import '../sdk_fake/fake_im.dart';
import '../sdk_fake/fake_models.dart';

class GroupMemberLastSeenCache {
  GroupMemberLastSeenCache._();
  static final GroupMemberLastSeenCache instance = GroupMemberLastSeenCache._();

  final Map<String, Map<String, int>> _byGroup = {};
  StreamSubscription<FakeMessage>? _msgSub;

  /// Wire the cache to a FakeEventBus so new messages live-update the map.
  /// Safe to call multiple times — re-subscribes only if the previous sub
  /// was cancelled.
  void attach(FakeEventBus bus) {
    _msgSub ??= bus.on<FakeMessage>(FakeIM.topicMessage).listen((m) {
      if (!m.conversationID.startsWith('group_')) return;
      final gid = m.conversationID.substring(6);
      final map = _byGroup[gid];
      if (map == null) return; // Not yet built — next read will lazy-build.
      final sec = m.timestampMs ~/ 1000;
      final prev = map[m.fromUser];
      if (prev == null || sec > prev) {
        map[m.fromUser] = sec;
      }
    });
  }

  /// Get the sender→last-seen map for [groupID]. Builds lazily on first
  /// access by scanning the persistence layer's history, then keeps the
  /// result up to date via the message-bus subscription.
  Map<String, int> getOrBuild(String groupID, FfiChatService ffi) {
    final cached = _byGroup[groupID];
    if (cached != null) return cached;
    final map = <String, int>{};
    try {
      final messages = ffi.messageHistoryPersistence.getHistory(groupID);
      for (final msg in messages) {
        final sec = msg.timestamp.millisecondsSinceEpoch ~/ 1000;
        final prev = map[msg.fromUserId];
        if (prev == null || sec > prev) {
          map[msg.fromUserId] = sec;
        }
      }
    } catch (_) {
      // Defensive: if history isn't loaded yet, return an empty map and
      // let live messages populate it. Next getOrBuild call will retry.
      return map;
    }
    _byGroup[groupID] = map;
    return map;
  }

  /// Drop the cached map for [groupID] so the next read rebuilds from
  /// persistence. Useful after a bulk import or clear-history operation.
  void invalidate(String groupID) {
    _byGroup.remove(groupID);
  }

  /// Tear down on logout / dispose.
  void clear() {
    _byGroup.clear();
    _msgSub?.cancel();
    _msgSub = null;
  }
}
