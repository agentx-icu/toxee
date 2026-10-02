import 'dart:async';

import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';
import 'fake_event_bus.dart';
import 'fake_models.dart';
import 'conversation_list_builder.dart';
export 'conversation_list_builder.dart'
    show ConvBuilderFriend, SelfConversationInput, buildConversationsFromFriends;
import 'fake_im.dart';
import 'self_conversation.dart';
import 'fake_uikit_core.dart';
import 'uikit_data_facade.dart';
import '../util/logger.dart';

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
      '[FakeConversationManager] getConversationList: Retrieved ${friends.length} friends from FFI',
    );
    // pinned contains normalized IDs (for C2C) or 'group_${normalizedGid}'
    // (for groups). Filter empty strings from legacy/corrupted data and cache
    // the result so the sync setPinned() path sees the latest set.
    final pinned = (await Prefs.getPinned()).where((s) => s.isNotEmpty).toSet();
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
      emitGroupType: true,
      getGroupActivityMs: (gid) =>
          _ffi.lastMessages[gid]?.timestamp.millisecondsSinceEpoch,
      getGroupType: (gid) => UikitDataFacade.getGroupInfo(gid).groupType,
      self: await resolveSelfConversation(_ffi),
    );
    AppLogger.log(
      '[FakeConversationManager] getConversationList: END - Returning ${list.length} conversations (${list.where((c) => !c.isGroup).length} C2C, ${list.where((c) => c.isGroup).length} groups), sort=$sortingMode',
    );
    return list;
  }

  Future<void> setPinned(String conversationID, bool pin) async {
    AppLogger.debug(
      '[FakeConversationManager] setPinned: START - conversationID=$conversationID, pin=$pin',
    );
    // Validate conversationID - reject empty or invalid IDs
    if (conversationID.isEmpty ||
        conversationID == 'c2c_' ||
        conversationID == 'group_') {
      AppLogger.debug(
        '[FakeConversationManager] setPinned: Invalid conversationID, returning early',
      );
      return;
    }

    final friends = await _ffi.getFriendList();
    String normalizedStoreKey;

    if (conversationID.startsWith('group_')) {
      final gid = conversationID.substring(6);
      // Validate group ID
      if (gid.isEmpty) {
        AppLogger.debug(
          '[FakeConversationManager] setPinned: Empty group ID, returning early',
        );
        return;
      }
      // For groups, use 'group_${normalizedGid}' format to match getConversationList
      final normalizedGid = normalizeToxId(gid);
      normalizedStoreKey = 'group_$normalizedGid';
      AppLogger.debug(
        '[FakeConversationManager] setPinned: Group - gid=$gid, normalizedGid=$normalizedGid, normalizedStoreKey=$normalizedStoreKey',
      );

      final next = {..._pinned};
      if (pin) {
        next.add(normalizedStoreKey);
        AppLogger.debug(
          '[FakeConversationManager] setPinned: Adding to pinned set, new size=${next.length}',
        );
      } else {
        next.remove(normalizedStoreKey);
        AppLogger.debug(
          '[FakeConversationManager] setPinned: Removing from pinned set, new size=${next.length}',
        );
      }
      _pinned = next;
      await Prefs.setPinned(next.where((s) => s.isNotEmpty).toSet());
      AppLogger.debug(
        '[FakeConversationManager] setPinned: Saved to Prefs, pinned set: ${next.toList()}',
      );

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
        groupType: resolveFakeConversationGroupType(
          groupId: gid,
          authoritativeGroupType: UikitDataFacade.getGroupInfo(gid).groupType,
        ),
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
        '[FakeConversationManager] setPinned: Empty storeKey, returning early',
      );
      return;
    }

    // Normalize the storeKey to ensure consistency with getConversationList
    // which uses normalized IDs when checking pinned.contains()
    normalizedStoreKey = normalizeToxId(storeKey);
    AppLogger.debug(
      '[FakeConversationManager] setPinned: C2C - storeKey=$storeKey, normalizedStoreKey=$normalizedStoreKey',
    );

    final next = {..._pinned};
    if (pin) {
      next.add(normalizedStoreKey);
      AppLogger.debug(
        '[FakeConversationManager] setPinned: Adding to pinned set, new size=${next.length}',
      );
    } else {
      next.remove(normalizedStoreKey);
      AppLogger.debug(
        '[FakeConversationManager] setPinned: Removing from pinned set, new size=${next.length}',
      );
    }
    _pinned = next;
    await Prefs.setPinned(next.where((s) => s.isNotEmpty).toSet());
    AppLogger.debug(
      '[FakeConversationManager] setPinned: Saved to Prefs, pinned set: ${next.toList()}',
    );
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
      '[FakeConversationManager] deleteConversation: START - conversationID=$conversationID',
    );
    if (conversationID.isEmpty ||
        conversationID == 'c2c_' ||
        conversationID == 'group_') {
      AppLogger.debug(
        '[FakeConversationManager] deleteConversation: invalid conversationID, returning',
      );
      return;
    }
    if (isSelfConversationId(_ffi, conversationID)) {
      // The user's local notebook is never deleted (Tim2ToxSdkPlatform refuses
      // it too); history is cleared only through the explicit clear action.
      AppLogger.log('[FakeConversationManager] deleteConversation: refused for the self conversation');
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
          st,
        );
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
          st,
        );
      }
      if (_pinned.remove(normalizedId)) {
        await Prefs.setPinned(_pinned.where((s) => s.isNotEmpty).toSet());
      }
    }

    // Force a refresh now so the UI updates instead of waiting for the
    // next 5s poll cycle.
    await FakeUIKit.instance.im?.refreshConversations();
    FakeUIKit.instance.messageProvider?.clearMessageBuffer(conversationID);
    AppLogger.debug(
      '[FakeConversationManager] deleteConversation: DONE - conversationID=$conversationID',
    );
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
      '[FakeMessageManager] addLocalMessage: total=${_localMessages[key]!.length}',
    );
  }

  Future<List<FakeMessage>> getHistory(
    String conversationID, {
    int count = 50,
  }) async {
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
    AppLogger.log('[FakeMessageManager] getHistory called');
    final hist = _ffi.getHistory(id);
    AppLogger.log(
      '[FakeMessageManager] getHistory returned ${hist.length} messages',
    );
    // Sort by timestamp ascending (oldest first, newest last) - UIKit pattern
    // DO NOT reverse here! UIKit's reverse ListView will handle the display order
    final sorted = hist
        .map(
          (h) => FakeMessage(
            msgID:
                h.msgID ??
                '${h.timestamp.millisecondsSinceEpoch}_${h.fromUserId}',
            conversationID: conversationID,
            fromUser: h.fromUserId,
            text: h.text,
            timestampMs: h.timestamp.millisecondsSinceEpoch,
            filePath: h.filePath,
            fileName: h.fileName, // Pass original file name
            fileSize: h.fileSize,
            mediaKind: h.mediaKind,
            cloudCustomData: h.cloudCustomData,
            isPending: h.isPending,
            isReceived: h.isReceived,
            isRead: h.isRead,
          ),
        )
        .toList();

    // Merge in locally generated messages (e.g. call records) for this user
    final normalizedId = normalizeToxId(id);
    final localMsgs = _localMessages[normalizedId];
    if (localMsgs != null && localMsgs.isNotEmpty) {
      AppLogger.log(
        '[FakeMessageManager] getHistory: merging ${localMsgs.length} local messages',
      );
      sorted.addAll(localMsgs);
    }

    sorted.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    // Return all messages (or the newest [count] if specified)
    // UIKit will handle pagination if needed
    return takeLatestWindow(sorted, count);
  }

  Future<ChatMessageSendResult> sendText(
    String conversationID,
    String text, {
    String? clientMessageID,
  }) async {
    if (conversationID.startsWith('c2c_')) {
      final uid = conversationID.substring(4);
      // Always call _ffi.sendText - it will handle offline messages by creating pending messages
      // This ensures messages are displayed in the chat window even when friend is offline
      final sent = await _ffi.sendTextWithResult(
        uid,
        text,
        clientMessageID: clientMessageID,
      );
      await Prefs.setFriendActivity(uid, DateTime.now());
      final messageID = sent.msgID;
      if (messageID == null || messageID.isEmpty) {
        throw StateError(
          'FfiChatService.sendText returned an empty message ID',
        );
      }
      return ChatMessageSendResult(
        messageID: messageID,
        isPending: sent.isPending,
      );
    }
    if (conversationID.startsWith('group_')) {
      final gid = conversationID.substring(6);
      final sent = await _ffi.sendGroupTextWithResult(
        gid,
        text,
        clientMessageID: clientMessageID,
      );
      final messageID = sent.msgID;
      if (messageID == null || messageID.isEmpty) {
        throw StateError(
          'FfiChatService.sendGroupText returned an empty message ID',
        );
      }
      return ChatMessageSendResult(
        messageID: messageID,
        isPending: sent.isPending,
      );
    }
    throw ArgumentError.value(
      conversationID,
      'conversationID',
      'must start with c2c_ or group_',
    );
  }

  /// Returns the identity of the echo `FfiChatService.sendFile` emitted on
  /// `ffi.messages` (like [sendText]); null when there is none (group path).
  Future<ChatMessageSendResult?> sendFile(
    String conversationID,
    String filePath,
  ) async {
    if (conversationID.startsWith('c2c_')) {
      final uid = conversationID.substring(4);
      await Prefs.setFriendActivity(uid, DateTime.now());
      final sent = await _ffi.sendFile(uid, filePath);
      final messageID = sent?.msgID;
      if (messageID == null || messageID.isEmpty) return null;
      return ChatMessageSendResult(messageID: messageID, isPending: sent!.isPending);
    } else if (conversationID.startsWith('group_')) {
      await _ffi.sendGroupFile(conversationID.substring(6), filePath);
    }
    return null;
  }

  /// Delete messages by their IDs (called by UIKit when the user deletes).
  Future<void> deleteMessages(List<String> msgIDs) async {
    await _ffi.deleteMessages(msgIDs);
  }

  /// Send message read receipts
  /// This is called by UIKit when messages are viewed
  Future<void> sendMessageReadReceipts(
    List<String> msgIDList, {
    String? userID,
    String? groupID,
  }) async {
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
        .map(
          (f) => FakeUser(
            userID: f.userId,
            nickName: f.nickName,
            status: f.status,
            online: f.online,
          ),
        )
        .toList();
  }

  void dispose() {
    _friendsSub?.cancel();
    _appsSub?.cancel();
    _listeners.clear();
  }
}
