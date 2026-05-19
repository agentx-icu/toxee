import 'dart:async';

import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';
import 'fake_event_bus.dart';
import 'fake_models.dart';
import 'fake_im.dart';
import 'fake_uikit_core.dart';
import '../util/logger.dart';

/// Friend record shape used by the shared conversation-list builder. Matches the
/// `FfiChatService.getFriendList()` element record so callers can pass results
/// straight in without copying.
typedef ConvBuilderFriend = ({String userId, String nickName, bool online});

/// Single conversation-list builder used by both `FakeConversationManager.getConversationList()`
/// and `FakeIM._refreshConversationsWithFriends()`.
///
/// X5 (local-storage review 2026-05-18): previously the two callers built the
/// conversation list independently with subtly different normalization, pinned
/// checks, and group filtering. Drift between the two paths produced concrete
/// bugs (A6: pinned flag dropped on bus emit). This helper is the single source
/// of truth for the per-conversation shape — all variability lives in the
/// parameters.
///
/// Inputs:
/// - [friends]: friend records returned by FFI (already-loaded; caller decides
///   whether to merge with `Prefs.localFriends` via [mergeLocalFriendsAsOffline]).
/// - [groupIds]: candidate group IDs (typically `ffi.knownGroups`, optionally
///   merged with `Prefs.getGroups()` for the polling path).
/// - [pinned]: normalized pinned set. C2C entries are bare normalized userIDs;
///   group entries are `'group_${normalizedGid}'`. Use `Prefs.getPinned()`.
/// - [quitGroups]: group IDs that have been quit and must be filtered out.
/// - [pendingFriendIds]: friend application IDs we sent but the peer hasn't
///   accepted yet — these are filtered out unless the friend now appears in
///   the friend list (i.e. the application was accepted).
/// - [sortingMode]: when `'activity'`, C2C entries are sorted by last activity
///   timestamp (newest first); otherwise by title.
/// - [getUnreadOf]: hook so we don't depend on `FfiChatService` directly.
/// - [mergeLocalFriendsAsOffline]: when true, locally-persisted friends not in
///   the Tox friend list are added with `online: false` (used by the cold-start
///   sync read path in `getConversationList()`). When false, Tox is the sole
///   authority (used by the steady-state bus-emit path).
/// - [emitGroupType]: when true, `FakeConversation.groupType` is populated
///   (`'conference'` for `tox_conf_*`, `'group'` otherwise).
///
/// The function does not mutate any of its inputs or call into `Prefs`/`ffi`
/// outside the read-side helpers. All Prefs reads happen in parallel (batched
/// `Future.wait`) per friend/group to keep the cost O(1) round-trips.
Future<List<FakeConversation>> buildConversationsFromFriends({
  required List<ConvBuilderFriend> friends,
  required Iterable<String> groupIds,
  required Set<String> pinned,
  required Set<String> quitGroups,
  required Set<String> pendingFriendIds,
  required String sortingMode,
  required int Function(String id) getUnreadOf,
  bool mergeLocalFriendsAsOffline = false,
  bool emitGroupType = false,
}) async {
  // ---- C2C: build the normalized friend map ----
  final friendMap = <String, ConvBuilderFriend>{};
  for (final f in friends) {
    final normalized = normalizeToxId(f.userId);
    friendMap[normalized] =
        (userId: normalized, nickName: f.nickName, online: f.online);
  }

  // Optionally merge in locally-persisted friends not yet in the Tox list, so
  // cold-start renders can show offline friends with cached metadata.
  if (mergeLocalFriendsAsOffline) {
    final localFriends = await Prefs.getLocalFriends();
    for (final raw in localFriends) {
      final normalized = normalizeToxId(raw);
      if (normalized.isEmpty || friendMap.containsKey(normalized)) continue;
      final cachedNick = await Prefs.getFriendNickname(normalized);
      friendMap[normalized] = (
        userId: normalized,
        nickName: cachedNick ?? '',
        online: false,
      );
    }
  }

  // Build the normalized friend-id set used by the pending-app filter so a
  // newly-accepted friend (in the friend list AND still in pending apps) is
  // emitted instead of suppressed.
  final normalizedFriendIds = friendMap.keys.toSet();
  final normalizedPendingIds =
      pendingFriendIds.map(normalizeToxId).toSet();

  // Filter pending-but-not-yet-accepted friends.
  final emitFriends = friendMap.values.where((f) {
    final normalizedUserId = normalizeToxId(f.userId);
    if (normalizedPendingIds.contains(normalizedUserId) &&
        !normalizedFriendIds.contains(normalizedUserId)) {
      return false;
    }
    return true;
  }).toList();

  // Parallel-fetch avatar + activity for each friend so N friends collapse to
  // one batch round-trip instead of 2N sequential awaits.
  final c2cMeta = await Future.wait(emitFriends.map((f) async {
    final res = await Future.wait<Object?>([
      Prefs.getFriendAvatarPath(f.userId),
      Prefs.getFriendActivity(f.userId),
    ]);
    return (avatar: res[0] as String?, activity: res[1] as DateTime?);
  }));

  final list = <FakeConversation>[];
  final activityByC2cId = <String, DateTime?>{};
  for (int i = 0; i < emitFriends.length; i++) {
    final f = emitFriends[i];
    final normalizedUserId = normalizeToxId(f.userId);
    activityByC2cId['c2c_${f.userId}'] = c2cMeta[i].activity;
    list.add(FakeConversation(
      conversationID: 'c2c_${f.userId}',
      title: f.nickName.isNotEmpty ? f.nickName : f.userId,
      faceUrl: c2cMeta[i].avatar,
      unreadCount: getUnreadOf(f.userId),
      isGroup: false,
      isPinned: pinned.contains(normalizedUserId),
    ));
  }

  // ---- Groups: dedupe candidate set, drop quit groups, batch-fetch metadata.
  final emitGroups =
      groupIds.toSet().where((g) => !quitGroups.contains(g)).toList();
  final groupMeta = await Future.wait(emitGroups.map((gid) async {
    final res = await Future.wait<Object?>([
      Prefs.resolveGroupDisplayName(gid),
      Prefs.getGroupAvatar(gid),
    ]);
    return (name: res[0] as String, avatar: res[1] as String?);
  }));
  for (int i = 0; i < emitGroups.length; i++) {
    final gid = emitGroups[i];
    final groupPinnedKey = 'group_${normalizeToxId(gid)}';
    list.add(FakeConversation(
      conversationID: 'group_$gid',
      title: groupMeta[i].name,
      faceUrl: groupMeta[i].avatar,
      unreadCount: getUnreadOf(gid),
      isGroup: true,
      isPinned: pinned.contains(groupPinnedKey),
      groupType: emitGroupType
          ? (gid.startsWith('tox_conf_') ? 'conference' : 'group')
          : null,
    ));
  }

  // ---- Sort: pinned first, then by mode (activity-by-c2c-timestamp or title).
  list.sort((a, b) {
    final aPinned = a.isPinned ? 0 : 1;
    final bPinned = b.isPinned ? 0 : 1;
    if (aPinned != bPinned) return aPinned.compareTo(bPinned);
    if (sortingMode == 'activity') {
      final aMs = a.conversationID.startsWith('c2c_')
          ? (activityByC2cId[a.conversationID]?.millisecondsSinceEpoch ?? 0)
          : 0;
      final bMs = b.conversationID.startsWith('c2c_')
          ? (activityByC2cId[b.conversationID]?.millisecondsSinceEpoch ?? 0)
          : 0;
      final cmp = bMs.compareTo(aMs);
      if (cmp != 0) return cmp;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

  return list;
}

class FakeConversationListener {
  FakeConversationListener({
    this.onNewConversation,
    this.onConversationChanged,
    this.onTotalUnreadChanged,
  });
  final void Function(List<FakeConversation> convs)? onNewConversation;
  final void Function(List<FakeConversation> convs)? onConversationChanged;
  final void Function(int total)? onTotalUnreadChanged;
}

class FakeConversationManager {
  FakeConversationManager(this._bus, this._ffi);
  final FakeEventBus _bus;
  final FfiChatService _ffi;
  final List<FakeConversationListener> _listeners = [];
  StreamSubscription? _convSub;
  StreamSubscription? _unreadSub;
  Set<String> _pinned = {};

  /// Initialize the manager. Awaits the initial pinned-conversations read so
  /// callers (FakeUIKit.startWithFfi) can guarantee [_pinned] is populated
  /// before they hand the manager to UIKit. Previously this read was
  /// fire-and-forget, which meant the first `getConversationList()` after
  /// login could return every conversation as un-pinned until the read
  /// resolved on a later microtask (A7).
  Future<void> start() async {
    _convSub = _bus.on<FakeConversation>(FakeIM.topicConversation).listen((c) {
      for (final l in _listeners) {
        l.onNewConversation?.call([c]);
        l.onConversationChanged?.call([c]);
      }
    });
    _unreadSub = _bus.on<FakeUnreadTotal>(FakeIM.topicUnread).listen((u) {
      for (final l in _listeners) {
        l.onTotalUnreadChanged?.call(u.total);
      }
    });
    // Await once at start so the first sync read of [_pinned] in
    // getConversationList() / setPinned() sees the persisted set. Note:
    // pinned contains normalized IDs (for C2C) or 'group_${normalizedGid}'
    // (for groups) — do NOT normalize here as it would break the
    // 'group_xxx' format.
    final value = await Prefs.getPinned();
    _pinned = value.where((s) => s.isNotEmpty).toSet();
  }

  void addListener(FakeConversationListener l) {
    _listeners.add(l);
  }

  Future<List<FakeConversation>> getConversationList() async {
    AppLogger.debug('[FakeConversationManager] getConversationList: START');
    final friends = await _ffi.getFriendList();
    AppLogger.debug(
        '[FakeConversationManager] getConversationList: Retrieved ${friends.length} friends from FFI');
    // pinned contains normalized IDs (for C2C) or 'group_${normalizedGid}'
    // (for groups). Filter empty strings from legacy/corrupted data and cache
    // the result so the sync setPinned() path sees the latest set.
    final pinned = (await Prefs.getPinned())
        .where((s) => s.isNotEmpty)
        .toSet();
    _pinned = pinned;

    // Pending friend applications (requests we sent, peer hasn't accepted yet)
    // are dropped from the list unless the friend now appears in the Tox list.
    final pendingApps = await _ffi.getFriendApplications();
    final pendingFriendIds = pendingApps.map((a) => a.userId).toSet();

    final quitGroups = await Prefs.getQuitGroups();
    final sortingMode = await Prefs.getFriendListSortingMode();

    // X5: route through the shared builder so this path can never drift from
    // FakeIM._refreshConversationsWithFriends. The cold-start merge-with-local
    // is `getConversationList`-specific (sync read for the UIKit caller), so
    // it's gated on the [mergeLocalFriendsAsOffline] flag.
    final builderFriends = friends
        .map((f) => (userId: f.userId, nickName: f.nickName, online: f.online))
        .toList();
    final list = await buildConversationsFromFriends(
      friends: builderFriends,
      groupIds: _ffi.knownGroups,
      pinned: pinned,
      quitGroups: quitGroups,
      pendingFriendIds: pendingFriendIds,
      sortingMode: sortingMode,
      getUnreadOf: _ffi.getUnreadOf,
      mergeLocalFriendsAsOffline: true,
      // Sync read path historically did not set groupType — preserve that.
      emitGroupType: false,
    );
    AppLogger.log(
        '[FakeConversationManager] getConversationList: END - Returning ${list.length} conversations (${list.where((c) => !c.isGroup).length} C2C, ${list.where((c) => c.isGroup).length} groups), sort=$sortingMode');
    return list;
  }

  Future<void> setPinned(String conversationID, bool pin) async {
    AppLogger.debug(
        '[FakeConversationManager] setPinned: START - conversationID=$conversationID, pin=$pin');
    // Validate conversationID - reject empty or invalid IDs
    if (conversationID.isEmpty ||
        conversationID == 'c2c_' ||
        conversationID == 'group_') {
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Invalid conversationID, returning early');
      return;
    }

    final friends = await _ffi.getFriendList();
    String normalizedStoreKey;

    if (conversationID.startsWith('group_')) {
      final gid = conversationID.substring(6);
      // Validate group ID
      if (gid.isEmpty) {
        AppLogger.debug(
            '[FakeConversationManager] setPinned: Empty group ID, returning early');
        return;
      }
      // For groups, use 'group_${normalizedGid}' format to match getConversationList
      final normalizedGid = normalizeToxId(gid);
      normalizedStoreKey = 'group_$normalizedGid';
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Group - gid=$gid, normalizedGid=$normalizedGid, normalizedStoreKey=$normalizedStoreKey');

      final next = {..._pinned};
      if (pin) {
        next.add(normalizedStoreKey);
        AppLogger.debug(
            '[FakeConversationManager] setPinned: Adding to pinned set, new size=${next.length}');
      } else {
        next.remove(normalizedStoreKey);
        AppLogger.debug(
            '[FakeConversationManager] setPinned: Removing from pinned set, new size=${next.length}');
      }
      _pinned = next;
      await Prefs.setPinned(next.where((s) => s.isNotEmpty).toSet());
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Saved to Prefs, pinned set: ${next.toList()}');

      // Resolve display name with the same precedence as the rest of the
      // app: alias > canonical name > gid.
      final name = await Prefs.resolveGroupDisplayName(gid);
      final conv = FakeConversation(
        conversationID: conversationID,
        title: name,
        faceUrl: null,
        unreadCount: _ffi.getUnreadOf(gid),
        isGroup: true,
        isPinned: pin,
      );
      _bus.emit(FakeIM.topicConversation, conv);
      // Trigger conversation list refresh
      await FakeUIKit.instance.im?.refreshConversations();
      return;
    }

    // For C2C conversations, extract user ID and normalize
    final storeKey = conversationID.startsWith('c2c_')
        ? conversationID.substring(4)
        : conversationID;
    // Validate storeKey - reject empty keys
    if (storeKey.isEmpty) {
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Empty storeKey, returning early');
      return;
    }

    // Normalize the storeKey to ensure consistency with getConversationList
    // which uses normalized IDs when checking pinned.contains()
    normalizedStoreKey = normalizeToxId(storeKey);
    AppLogger.debug(
        '[FakeConversationManager] setPinned: C2C - storeKey=$storeKey, normalizedStoreKey=$normalizedStoreKey');

    final next = {..._pinned};
    if (pin) {
      next.add(normalizedStoreKey);
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Adding to pinned set, new size=${next.length}');
    } else {
      next.remove(normalizedStoreKey);
      AppLogger.debug(
          '[FakeConversationManager] setPinned: Removing from pinned set, new size=${next.length}');
    }
    _pinned = next;
    await Prefs.setPinned(next.where((s) => s.isNotEmpty).toSet());
    AppLogger.debug(
        '[FakeConversationManager] setPinned: Saved to Prefs, pinned set: ${next.toList()}');
    // Use normalizedStoreKey for consistency
    final id = normalizedStoreKey;
    // Validate user ID
    if (id.isEmpty) {
      return;
    }
    // Find friend by comparing normalized IDs
    final friend = friends.firstWhere(
      (f) => normalizeToxId(f.userId) == id,
      orElse: () => (userId: id, nickName: id, status: '', online: false),
    );
    final conv = FakeConversation(
      conversationID: 'c2c_$id',
      title: friend.nickName.isNotEmpty ? friend.nickName : friend.userId,
      faceUrl: null,
      unreadCount: _ffi.getUnreadOf(id),
      isGroup: false,
      isPinned: pin,
    );
    _bus.emit(FakeIM.topicConversation, conv);
    // Trigger conversation list refresh
    await FakeUIKit.instance.im?.refreshConversations();
  }

  /// Delete a conversation. A9: previously the ConversationManagerAdapter
  /// stub did nothing here, so UIKit's "delete conversation" reappeared on
  /// the next 5s poll. We now clear the underlying history (the source the
  /// poll reads from), drop the pinned flag, and force-refresh the
  /// conversation list so the UI updates immediately.
  ///
  /// Group semantics: we deliberately only clear the group's local history.
  /// Quitting the group (leaving it on the Tox side) is a separate user
  /// action and lives behind a different UI path.
  Future<void> deleteConversation(String conversationID) async {
    AppLogger.debug(
        '[FakeConversationManager] deleteConversation: START - conversationID=$conversationID');
    if (conversationID.isEmpty ||
        conversationID == 'c2c_' ||
        conversationID == 'group_') {
      AppLogger.debug(
          '[FakeConversationManager] deleteConversation: invalid conversationID, returning');
      return;
    }

    if (conversationID.startsWith('group_')) {
      final gid = conversationID.substring(6);
      if (gid.isEmpty) return;
      try {
        await _ffi.clearGroupHistory(gid);
      } catch (e, st) {
        AppLogger.logError(
            '[FakeConversationManager] deleteConversation: clearGroupHistory failed',
            e,
            st);
      }
      final pinnedKey = 'group_${normalizeToxId(gid)}';
      if (_pinned.remove(pinnedKey)) {
        await Prefs.setPinned(_pinned.where((s) => s.isNotEmpty).toSet());
      }
    } else {
      final rawId = conversationID.startsWith('c2c_')
          ? conversationID.substring(4)
          : conversationID;
      if (rawId.isEmpty) return;
      final normalizedId = normalizeToxId(rawId);
      try {
        await _ffi.clearC2CHistory(normalizedId);
      } catch (e, st) {
        AppLogger.logError(
            '[FakeConversationManager] deleteConversation: clearC2CHistory failed',
            e,
            st);
      }
      if (_pinned.remove(normalizedId)) {
        await Prefs.setPinned(_pinned.where((s) => s.isNotEmpty).toSet());
      }
    }

    // Force a refresh now so the UI updates instead of waiting for the
    // next 5s poll cycle.
    await FakeUIKit.instance.im?.refreshConversations();
    AppLogger.debug(
        '[FakeConversationManager] deleteConversation: DONE - conversationID=$conversationID');
  }

  void dispose() {
    _convSub?.cancel();
    _unreadSub?.cancel();
    _listeners.clear();
    _pinned.clear();
  }
}

class FakeMessageListener {
  FakeMessageListener({this.onRecvNewMessage, this.onTyping});
  final void Function(FakeMessage msg)? onRecvNewMessage;
  final void Function(FakeTypingEvent typing)? onTyping;
}

class FakeMessageManager {
  FakeMessageManager(this._bus, this._ffi);
  final FakeEventBus _bus;
  final FfiChatService _ffi;
  final List<FakeMessageListener> _listeners = [];
  StreamSubscription? _msgSub;
  StreamSubscription? _typingSub;

  /// In-memory local messages (e.g. call records) keyed by normalized user ID.
  /// These are merged into getHistory() results since they aren't in Tox history.
  final Map<String, List<FakeMessage>> _localMessages = {};

  /// Return the newest [count] items from an ascending list.
  /// If [count] is non-positive or larger than the list length, return all.
  static List<T> takeLatestWindow<T>(List<T> items, int count) {
    if (count <= 0 || count >= items.length) {
      return List<T>.from(items);
    }
    return List<T>.from(items.sublist(items.length - count));
  }

  void start() {
    _msgSub = _bus.on<FakeMessage>(FakeIM.topicMessage).listen((m) {
      // Update friend activity for "sort by activity" (C2C only; sender is the peer)
      if (m.conversationID.startsWith('c2c_') &&
          m.fromUser != _ffi.selfId &&
          m.fromUser.isNotEmpty) {
        Prefs.setFriendActivity(m.fromUser, DateTime.now());
      }
      for (final l in _listeners) {
        l.onRecvNewMessage?.call(m);
      }
    });
    _typingSub = _bus.on<FakeTypingEvent>(FakeIM.topicTyping).listen((t) {
      for (final l in _listeners) {
        l.onTyping?.call(t);
      }
    });
  }

  void addListener(FakeMessageListener l) {
    _listeners.add(l);
  }

  /// Add a locally generated message (e.g. call record) that should appear in
  /// history but is not stored in Tox.  [userID] is the remote peer's ID.
  void addLocalMessage(String userID, FakeMessage msg) {
    final key = normalizeToxId(userID);
    _localMessages.putIfAbsent(key, () => <FakeMessage>[]).add(msg);
    AppLogger.log(
        '[FakeMessageManager] addLocalMessage: userID=$userID, key=$key, msgID=${msg.msgID}, total=${_localMessages[key]!.length}');
  }

  Future<List<FakeMessage>> getHistory(String conversationID,
      {int count = 50}) async {
    String id;
    if (conversationID.startsWith('c2c_')) {
      id = conversationID.substring(4);
      // Don't normalize here - let FfiChatService.getHistory handle normalization
      // This ensures we use the same normalization logic as when saving history
      id = id.trim();
    } else if (conversationID.startsWith('group_')) {
      id = conversationID.substring(6);
    } else {
      id = conversationID;
    }
    AppLogger.log(
        '[FakeMessageManager] getHistory called: conversationID=$conversationID, id=$id');
    final hist = _ffi.getHistory(id);
    AppLogger.log(
        '[FakeMessageManager] getHistory returned ${hist.length} messages for id=$id');
    // Sort by timestamp ascending (oldest first, newest last) - UIKit pattern
    // DO NOT reverse here! UIKit's reverse ListView will handle the display order
    final sorted = hist
        .map((h) => FakeMessage(
              msgID: h.msgID ??
                  '${h.timestamp.millisecondsSinceEpoch}_${h.fromUserId}',
              conversationID: conversationID,
              fromUser: h.fromUserId,
              text: h.text,
              timestampMs: h.timestamp.millisecondsSinceEpoch,
              filePath: h.filePath,
              fileName: h.fileName, // Pass original file name
              mediaKind: h.mediaKind,
              isPending: h.isPending,
              isReceived: h.isReceived,
              isRead: h.isRead,
            ))
        .toList();

    // Merge in locally generated messages (e.g. call records) for this user
    final normalizedId = normalizeToxId(id);
    final localMsgs = _localMessages[normalizedId];
    if (localMsgs != null && localMsgs.isNotEmpty) {
      AppLogger.log(
          '[FakeMessageManager] getHistory: merging ${localMsgs.length} local messages for $normalizedId');
      sorted.addAll(localMsgs);
    }

    sorted.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    // Return all messages (or the newest [count] if specified)
    // UIKit will handle pagination if needed
    return takeLatestWindow(sorted, count);
  }

  Future<void> sendText(String conversationID, String text) async {
    if (conversationID.startsWith('c2c_')) {
      final uid = conversationID.substring(4);
      // Always call _ffi.sendText - it will handle offline messages by creating pending messages
      // This ensures messages are displayed in the chat window even when friend is offline
      await _ffi.sendText(uid, text);

      // Get the message from history (which includes pending messages for offline friends)
      final history = _ffi.getHistory(uid);
      final lastMsg = history.isNotEmpty ? history.last : null;

      // If message was created (either sent or pending), emit it via bus for UIKit
      if (lastMsg != null && lastMsg.text == text && lastMsg.isSelf) {
        Prefs.setFriendActivity(uid, DateTime.now());
        final msgID =
            lastMsg.msgID ?? '${DateTime.now().microsecondsSinceEpoch}';
        final msg = FakeMessage(
          msgID: msgID,
          conversationID: conversationID,
          fromUser: _ffi.selfId,
          text: text,
          timestampMs: lastMsg.timestamp.millisecondsSinceEpoch,
          isPending: lastMsg
              .isPending, // Use actual pending status from FfiChatService
          isReceived: lastMsg.isReceived,
          isRead: lastMsg.isRead,
        );
        _bus.emit(FakeIM.topicMessage, msg);
      }
    } else if (conversationID.startsWith('group_')) {
      final gid = conversationID.substring(6);
      await _ffi.sendGroupText(gid, text);
      // Don't emit local echo for group messages - Tox will echo it back via ffi.messages.listen
      // This prevents duplicate messages in the chat window
    }
  }

  Future<void> sendFile(String conversationID, String filePath) async {
    if (conversationID.startsWith('c2c_')) {
      final uid = conversationID.substring(4);
      Prefs.setFriendActivity(uid, DateTime.now());
      await _ffi.sendFile(uid, filePath);
      // Note: Local echo will be emitted by FfiChatService.sendFile via ffi.messages stream
      // No need to emit here to avoid duplicates
    } else if (conversationID.startsWith('group_')) {
      final gid = conversationID.substring(6);
      await _ffi.sendGroupFile(gid, filePath);
      // Don't emit local echo for group messages - Tox will echo it back via ffi.messages.listen
      // This prevents duplicate messages in the chat window
    }
  }

  /// Delete messages by their IDs
  /// This is called by UIKit when user deletes messages
  Future<void> deleteMessages(List<String> msgIDs) async {
    await _ffi.deleteMessages(msgIDs);
    // Emit a message deletion event to notify listeners
    // Note: We don't have a specific deletion event, but the UI should refresh
    // The FakeChatMessageProvider will handle the UI update by re-emitting the message list
  }

  /// Send message read receipts
  /// This is called by UIKit when messages are viewed
  Future<void> sendMessageReadReceipts(List<String> msgIDList,
      {String? userID, String? groupID}) async {
    try {
      if (groupID != null) {
        // For group messages, send read receipt to the group
        for (final msgID in msgIDList) {
          await _ffi.markMessageAsRead(groupID, msgID, groupID: groupID);
        }
      } else if (userID != null) {
        // For C2C messages, send read receipt to the user
        for (final msgID in msgIDList) {
          await _ffi.markMessageAsRead(userID, msgID);
        }
      } else {
        throw Exception('Either userID or groupID must be provided');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get list of users who received a group message
  /// This is called by UIKit to display message receivers
  List<String> getMessageReceivers(String msgID) {
    return _ffi.getMessageReceivers(msgID);
  }

  /// Get count of users who received a group message
  /// This is called by UIKit to display message receiver count
  int getMessageReceiverCount(String msgID) {
    return _ffi.getMessageReceiverCount(msgID);
  }

  void dispose() {
    _msgSub?.cancel();
    _typingSub?.cancel();
    _listeners.clear();
  }
}

class FakeContactListener {
  FakeContactListener({this.onFriendList, this.onFriendApps});
  final void Function(List<FakeUser> users)? onFriendList;
  final void Function(List<FakeFriendApplication> apps)? onFriendApps;
}

class FakeContactManager {
  FakeContactManager(this._bus, this._ffi);
  final FakeEventBus _bus;
  final FfiChatService _ffi;
  final List<FakeContactListener> _listeners = [];
  StreamSubscription? _friendsSub;
  StreamSubscription? _appsSub;

  void start() {
    _friendsSub = _bus.on<List<FakeUser>>(FakeIM.topicContacts).listen((list) {
      for (final l in _listeners) {
        l.onFriendList?.call(list);
      }
    });
    _appsSub = _bus
        .on<List<FakeFriendApplication>>(FakeIM.topicFriendApps)
        .listen((list) {
      for (final l in _listeners) {
        l.onFriendApps?.call(list);
      }
    });
  }

  void addListener(FakeContactListener l) {
    _listeners.add(l);
  }

  Future<List<FakeUser>> getFriendList() async {
    final friends = await _ffi.getFriendList();
    return friends
        .map((f) => FakeUser(
            userID: f.userId,
            nickName: f.nickName,
            status: f.status,
            online: f.online))
        .toList();
  }

  void dispose() {
    _friendsSub?.cancel();
    _appsSub?.cancel();
    _listeners.clear();
  }
}
