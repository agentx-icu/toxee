import 'dart:async';
import 'dart:io';
import 'package:tencent_cloud_chat_common/external/chat_data_provider.dart';
import 'package:tim2tox_dart/utils/tim2tox_failed_message_persistence.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimConversationListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_file_elem.dart';
import 'package:tencent_cloud_chat_sdk/enum/image_types.dart';
import 'package:tencent_cloud_chat_sdk/enum/group_type.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';
import 'fake_uikit_core.dart';
import 'fake_im.dart';
import 'fake_models.dart';
import 'uikit_data_facade.dart';
import 'c2c_recv_opt_cache.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';

V2TimConversation mergeExternalConversationUpdate({
  V2TimConversation? existing,
  required V2TimConversation refreshed,
}) {
  if (existing == null) return refreshed;

  // Display fields: treat EMPTY strings as absent, not just null. Sparse/minimal
  // native emits (the recvOpt mute push, post-send / pin / draft notifies built
  // without a cached snapshot) fill these with "" placeholders, which must not
  // clobber known values.
  if (refreshed.faceUrl == null || refreshed.faceUrl!.isEmpty) {
    refreshed.faceUrl = existing.faceUrl;
  }
  if (refreshed.showName == null || refreshed.showName!.isEmpty) {
    refreshed.showName = existing.showName;
  }
  refreshed.lastMessage ??= existing.lastMessage;
  // Scalars: sparse emits carry 0/false placeholders here too, but per-field
  // ownership is ambiguous (the pin notify legitimately owns isPinned while the
  // mute push does not), so keep null-coalescing. A placeholder that slips
  // through is transient: the ~5s FakeConversation rebuild restores the real
  // values from Prefs/FfiChatService.
  refreshed.orderkey ??= existing.orderkey;
  refreshed.unreadCount ??= existing.unreadCount;
  refreshed.isPinned ??= existing.isPinned;
  return refreshed;
}

class FakeChatDataProvider implements ChatDataProvider {
  final _convCtrl = StreamController<List<V2TimConversation>>.broadcast();
  final _unreadCtrl = StreamController<int>.broadcast();
  final Map<String, V2TimConversation> _convMap = {};

  /// Conversation IDs that were explicitly deleted via the SDK (deleteConversationList).
  /// FakeIM's periodic refresh re-emits ALL friends as FakeConversation events every 5 s;
  /// without this set, deleted conversations would reappear in _convMap shortly after deletion.
  final Set<String> _sdkDeletedConvIds = {};

  /// Remove a conversation ID from the deleted set so it can be re-added.
  /// Used when a group is re-created with the same ID after being quit/deleted.
  void unblockConversation(String conversationID) {
    _sdkDeletedConvIds.remove(conversationID);
  }

  StreamSubscription? _convSub;
  StreamSubscription? _unreadSub;
  StreamSubscription? _messageSub;
  StreamSubscription? _friendDeletedSub;
  StreamSubscription? _groupDeletedSub;
  V2TimConversationListener? _sdkConvListener;
  FfiChatService?
      _ffiService; // Reference to FfiChatService for getting last message timestamps
  Timer? _convFlushTimer;
  static const _convFlushDelay = Duration(milliseconds: 50);

  FakeChatDataProvider({FfiChatService? ffiService})
      : _ffiService = ffiService {
    // Seed initial from current conversation manager if available
    () async {
      try {
        final mgr = FakeUIKit.instance.conversationManager;
        if (mgr != null) {
          final list = await mgr.getConversationList();
          // Get quit groups to filter them out
          final quitGroups = await Prefs.getQuitGroups();
          // Hydrate the C2C recvOpt projection cache from Prefs (the durable
          // backing store) BEFORE _mapConv reads it, so a mute set in a previous
          // session is reflected on restart. Prefs is persistence only; the cache
          // is the runtime source of truth _mapConv reads.
          final selfToxId = await Prefs.getCurrentAccountToxId();
          for (final c in list) {
            // Skip group conversations that have been quit
            if (c.isGroup) {
              final gid = c.conversationID.replaceFirst('group_', '');
              if (quitGroups.contains(gid)) {
                continue;
              }
            } else {
              await C2CRecvOptCache.hydrateFromPrefs(
                  c.conversationID.replaceFirst('c2c_', ''), selfToxId);
            }
            _convMap[c.conversationID] = await _mapConv(c);
          }
          if (_convMap.isNotEmpty) {
            final initialList = _convMap.values.toList();
            // Sort conversations: pinned first, then by last message timestamp (newest first)
            initialList.sort((a, b) {
              // First, sort by pinned status (pinned conversations first)
              final aPinned = a.isPinned ?? false;
              final bPinned = b.isPinned ?? false;
              if (aPinned != bPinned) {
                return aPinned ? -1 : 1;
              }
              // Then, sort by last message timestamp (newest first)
              final aTime = a.lastMessage?.timestamp ?? 0;
              final bTime = b.lastMessage?.timestamp ?? 0;
              return bTime.compareTo(aTime);
            });
            _convCtrl.add(initialList);
            _updateTotalUnreadCount(initialList);
          }
        }
      } catch (e, st) {
        AppLogger.logError(
            '[FakeChatDataProvider] error seeding initial conversations', e, st);
      }
    }();
    _convSub = FakeUIKit.instance.eventBusInstance
        .on<FakeConversation>(FakeIM.topicConversation)
        .listen((c) async {
      // Skip conversations that were explicitly deleted via the SDK.
      // FakeIM's periodic refresh re-emits ALL friends every 5s; without this check,
      // deleted conversations would reappear in the conversation list.
      if (_sdkDeletedConvIds.contains(c.conversationID)) {
        return;
      }
      // For group conversations, check if the group has been quit
      if (c.isGroup) {
        final gid = c.conversationID.replaceFirst('group_', '');
        // Check if this group is in the quit groups list
        final quitGroups = await Prefs.getQuitGroups();
        if (quitGroups.contains(gid)) {
          // Remove from map if it exists (in case it was added before quitting)
          if (_convMap.containsKey(c.conversationID)) {
            _convMap.remove(c.conversationID);
            _scheduleConvListEmit();
          }
          // Also remove from UIKit's conversation list to ensure UI updates
          // This is important because buildConversationList only adds/updates, it doesn't remove
          UikitDataFacade.removeConversation([c.conversationID]);
          AppLogger.debug(
              '[FakeChatDataProvider] Removed quit group conversation ${c.conversationID} from UIKit conversation list via FakeConversation event');
          return; // Skip adding this conversation
        }
        // Always get the latest group name from Prefs to ensure we have the latest
        final latestName = await Prefs.getGroupName(gid);
        if (latestName != null &&
            latestName.isNotEmpty &&
            latestName != c.title) {
          // Update the title with the latest name from Prefs
          c = FakeConversation(
            conversationID: c.conversationID,
            title: latestName,
            faceUrl: c.faceUrl,
            unreadCount: c.unreadCount,
            isGroup: c.isGroup,
            isPinned: c.isPinned,
          );
        }
      }
      // Lazily hydrate this peer's persisted mute state before _mapConv reads
      // the projection cache — a C2C conversation that only appears AFTER the
      // provider seed (e.g. the peer comes online later) would otherwise hit a
      // cache miss and render as un-muted until the next explicit mute action.
      if (!c.isGroup) {
        final peer = c.conversationID.replaceFirst('c2c_', '');
        if (C2CRecvOptCache.needsHydration(peer)) {
          final selfToxId = await Prefs.getCurrentAccountToxId();
          await C2CRecvOptCache.hydrateFromPrefs(peer, selfToxId);
        }
      }
      final newConv = await _mapConv(c);
      _convMap[c.conversationID] = mergeExternalConversationUpdate(
        existing: _convMap[c.conversationID],
        refreshed: newConv,
      );
      _scheduleConvListEmit();
    });
    // Use total from FakeIM (from ffi.getUnreadOf) so sidebar updates when new message arrives
    _unreadSub = FakeUIKit.instance.eventBusInstance
        .on<FakeUnreadTotal>(FakeIM.topicUnread)
        .listen((u) {
      _unreadCtrl.add(u.total);
    });

    // Listen for new messages to update conversation lastMessage
    _messageSub = FakeUIKit.instance.eventBusInstance
        .on<FakeMessage>(FakeIM.topicMessage)
        .listen((msg) async {
      // R-3 / U-1 / U-2: never let raw control-signal payloads
      // (`__revoke__:`, `__face__:`, `__custom__:`, `__location__:`) end
      // up as the visible "last message" preview in the conversation
      // list. `__revoke__:` is dropped entirely; the others fall through
      // (FakeChatMessageProvider's routing layer has already rewritten
      // the bubble text by the time we read FfiChatService.lastMessages,
      // but we still mask out the raw-JSON preview here for messages
      // that arrive through this listener directly).
      if ((msg.mediaKind == null || msg.mediaKind!.isEmpty) &&
          msg.text.isNotEmpty &&
          msg.text.startsWith('__')) {
        if (msg.text.startsWith('__revoke__:')) {
          return; // Swallow revoke signals.
        }
      }
      // When a new message arrives for a previously-deleted conversation, allow it to
      // be recreated (e.g. friend was re-added, or a new message from re-joined group).
      // Remove from _sdkDeletedConvIds so the conversation can reappear.
      _sdkDeletedConvIds.remove(msg.conversationID);
      // When a new message arrives, update the corresponding conversation's lastMessage
      // CRITICAL: Even if conversation doesn't exist in _convMap, we should still process it
      // This is especially important for failed messages that need to appear in the conversation list
      final peerId = msg.conversationID.startsWith('c2c_')
          ? msg.conversationID.substring(4)
          : (msg.conversationID.startsWith('group_')
              ? msg.conversationID.substring(6)
              : msg.conversationID);
      // Use a microtask to ensure _lastByPeer has been updated in FfiChatService
      // This ensures that when we access lastMessages, the message has already been added
      await Future.microtask(() async {
        // CRITICAL: First check if message is in failed persistence list
        // This must be done BEFORE building lastMessage, so we know if we should use FakeMessage directly
        bool isFailedMessage = false;
        try {
          final userID = msg.conversationID.startsWith('c2c_') ? peerId : null;
          final groupID =
              msg.conversationID.startsWith('group_') ? peerId : null;
          final currentToxId = await Prefs.getCurrentAccountToxId();
          final failedMessagesData =
              await Tim2ToxFailedMessagePersistence.loadFailedMessages(
            userID: userID,
            groupID: groupID,
            accountToxId: currentToxId,
          );

          // Check if this message is in the failed list
          for (final failedMsgData in failedMessagesData) {
            final failedMsgID = failedMsgData['msgID'] as String?;
            final failedID = failedMsgData['id'] as String?;

            if ((failedMsgID != null && failedMsgID == msg.msgID) ||
                (failedID != null && failedID == msg.msgID)) {
              // Message is in failed list
              isFailedMessage = true;
              break;
            }
          }
        } catch (e) {
          AppLogger.warn(
              '[FakeChatDataProvider] failed-message check threw, continuing with normal mapping: $e');
        }

        // Try to get the message from lastMessages first
        final lastMsg = _ffiService?.lastMessages[peerId];

        V2TimMessage lastMessage;
        // CRITICAL: If message is failed, always build from FakeMessage directly
        // This ensures we have the correct text and status, even if lastMessages doesn't contain it
        if (isFailedMessage || lastMsg == null) {
          // Build from FakeMessage directly (for failed messages or when lastMsg is null)
          // Check if fromUser matches selfId to determine isSelf
          final isSelf = _ffiService?.selfId == msg.fromUser;
          // Create a temporary ChatMessage-like object from FakeMessage
          final tempChatMsg = ChatMessage(
            text: msg.text,
            fromUserId: msg.fromUser,
            isSelf: isSelf,
            timestamp: DateTime.fromMillisecondsSinceEpoch(msg.timestampMs),
            groupId: msg.conversationID.startsWith('group_') ? peerId : null,
            msgID: msg.msgID,
            filePath: msg.filePath,
            mediaKind: msg.mediaKind,
          );
          lastMessage = _chatMessageToV2TimMessage(
              tempChatMsg, peerId, msg.conversationID.startsWith('group_'));
          // Set failed status if message is in failed list
          if (isFailedMessage) {
            lastMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
          }
        } else {
          // Use the message from lastMessages (preferred, as it has all fields including isSelf)
          lastMessage = _chatMessageToV2TimMessage(
              lastMsg, peerId, msg.conversationID.startsWith('group_'));
          // Still check if it's in failed list (in case lastMessages has it but it's actually failed)
          if (isFailedMessage) {
            lastMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
          }
        }

        // If conversation doesn't exist, create it (especially important for failed messages)
        if (!_convMap.containsKey(msg.conversationID)) {
          // Load conversation title and avatar
          String? title;
          String? faceUrl;
          if (msg.conversationID.startsWith('c2c_')) {
            title =
                peerId; // Use peerId as title (friend name can be loaded later if needed)
            faceUrl = await Prefs.getFriendAvatarPath(peerId);
          } else if (msg.conversationID.startsWith('group_')) {
            title = await Prefs.getGroupName(peerId) ?? peerId;
            faceUrl = await Prefs.getGroupAvatar(peerId);
          } else {
            title = peerId;
          }

          // New conv for incoming message: unread at least 1 from FfiChatService
          final newConvUnread = _ffiService?.getUnreadOf(peerId) ?? 1;
          final newConv = FakeConversation(
            conversationID: msg.conversationID,
            title: title,
            faceUrl: faceUrl,
            unreadCount: newConvUnread,
            isGroup: msg.conversationID.startsWith('group_'),
            isPinned: false,
          );
          _convMap[msg.conversationID] = await _mapConv(newConv);
        }

        // Load avatar path for conversation
        String? faceUrl = _convMap[msg.conversationID]?.faceUrl;
        if (faceUrl == null) {
          if (msg.conversationID.startsWith('c2c_')) {
            faceUrl = await Prefs.getFriendAvatarPath(peerId);
          } else if (msg.conversationID.startsWith('group_')) {
            final groupId = msg.conversationID.substring(6);
            faceUrl = await Prefs.getGroupAvatar(groupId);
          }
        }
        // Use FfiChatService unread so sidebar and conversation list show correct count when new message arrives
        final unread = _ffiService?.getUnreadOf(peerId) ??
            _convMap[msg.conversationID]?.unreadCount ??
            0;
        final conv = FakeConversation(
          conversationID: msg.conversationID,
          title: _convMap[msg.conversationID]?.showName ?? peerId,
          faceUrl: faceUrl,
          unreadCount: unread,
          isGroup: msg.conversationID.startsWith('group_'),
          isPinned: _convMap[msg.conversationID]?.isPinned ?? false,
        );
        // CRITICAL: Pass lastMessage to _mapConv to ensure it's preserved
        // This ensures that failed messages are not overridden by _mapConv's logic
        final updatedConv =
            await _mapConv(conv, overrideLastMessage: lastMessage);
        _convMap[msg.conversationID] = updatedConv;
        _scheduleConvListEmit();
      });
    });

    // Listen for friend deletion events
    _friendDeletedSub = FakeUIKit.instance.eventBusInstance
        .on<FakeFriendDeleted>(FakeIM.topicFriendDeleted)
        .listen((event) {
      // Remove conversation from map and mark as SDK-deleted to prevent re-add by FakeIM refresh
      final convId = 'c2c_${event.userID}';
      _convMap.remove(convId);
      _sdkDeletedConvIds.add(convId);
      _scheduleConvListEmit();

      // Also remove from UIKit's conversation list to ensure UI updates.
      // buildConversationList only adds/updates; it doesn't remove, so we need explicit removal.
      UikitDataFacade.removeConversation([convId]);
      AppLogger.debug(
          '[FakeChatDataProvider] Removed conversation $convId from UIKit conversation list via FakeFriendDeleted event');
    });

    // Listen for group deletion events
    _groupDeletedSub = FakeUIKit.instance.eventBusInstance
        .on<FakeGroupDeleted>(FakeIM.topicGroupDeleted)
        .listen((event) {
      // Remove conversation from map and mark as SDK-deleted to prevent re-add by FakeIM refresh
      final convId = 'group_${event.groupID}';
      _convMap.remove(convId);
      _sdkDeletedConvIds.add(convId);
      _scheduleConvListEmit();

      // Also remove from UIKit's conversation list to ensure UI updates
      // buildConversationList only adds/updates, it doesn't remove, so we need to explicitly remove
      UikitDataFacade.removeConversation([convId]);
      AppLogger.debug(
          '[FakeChatDataProvider] Removed conversation $convId from UIKit conversation list via FakeGroupDeleted event');
    });

    // Listen for SDK conversation deletion events (fired by C++ OnConversationDeleted)
    // This ensures _convMap stays in sync when deleteConversationList is called.
    // Deferred slightly to ensure SDK is fully initialized.
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        final listener = V2TimConversationListener(
          onConversationChanged: (List<V2TimConversation> conversationList) {
            for (final conv in conversationList) {
              final cid = conv.conversationID;
              // Project a C2C recvOpt change (e.g. a real-UI mute, delivered via
              // the native SetC2CReceiveMessageOpt -> UpdateC2CReceiveOptAndNotify
              // -> OnConversationChanged push) into the synchronous cache and
              // persist it. This is the authoritative recvOpt event and is handled
              // even when no local conversation row exists yet (mute can be set
              // from the friend profile before any message).
              if (cid.startsWith('c2c_') && conv.recvOpt != null) {
                final peer = cid.substring(4);
                final opt = conv.recvOpt!;
                if (C2CRecvOptCache.optFor(peer) != opt) {
                  // SYNCHRONOUS cache write first — _shouldSuppress must see the
                  // new opt immediately (a message can arrive in the gap an
                  // async-only write would leave). Durable persist follows.
                  C2CRecvOptCache.setLocal(peer, opt);
                  unawaited(Prefs.getCurrentAccountToxId().then(
                    (toxId) => C2CRecvOptCache.setAndPersist(peer, opt, toxId),
                  ));
                }
              }
              if (_convMap.containsKey(cid)) {
                // MERGE, not replace: the native push can be sparse (recvOpt-only),
                // so preserve the existing showName/faceUrl/lastMessage/orderkey/
                // unreadCount/isPinned instead of clobbering them with placeholders.
                _convMap[cid] = mergeExternalConversationUpdate(
                  existing: _convMap[cid],
                  refreshed: conv,
                );
              }
            }
            _scheduleConvListEmit();
          },
          onConversationDeleted: (List<String> conversationIDList) {
            for (final convId in conversationIDList) {
              _convMap.remove(convId);
              _sdkDeletedConvIds.add(convId);
              AppLogger.debug(
                  '[FakeChatDataProvider] Removed conversation $convId from _convMap via onConversationDeleted');
            }
            _scheduleConvListEmit();
          },
        );
        _sdkConvListener = listener;
        TencentCloudChat.instance.chatSDKInstance.manager
            .getConversationManager()
            .addConversationListener(listener: listener);
        AppLogger.debug(
            '[FakeChatDataProvider] Registered onConversationDeleted listener');
      } catch (e) {
        AppLogger.debug(
            '[FakeChatDataProvider] Failed to register conversation listener: $e');
      }
    });
  }

  void _updateTotalUnreadCount(List<V2TimConversation> conversations) {
    if (_unreadCtrl.isClosed) return;
    // Calculate total unread count from conversation list
    int total = 0;
    for (final conv in conversations) {
      total += conv.unreadCount ?? 0;
    }
    // Emit total unread count immediately to keep sidebar in sync
    _unreadCtrl.add(total);
  }

  /// Emit current _convMap to conversationStream (and unread). Used after debounce.
  void _emitConvList() {
    if (_convCtrl.isClosed) return;
    final updatedList = _convMap.values.toList();
    updatedList.sort((a, b) {
      final aPinned = a.isPinned ?? false;
      final bPinned = b.isPinned ?? false;
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      final aTime = a.lastMessage?.timestamp ?? 0;
      final bTime = b.lastMessage?.timestamp ?? 0;
      return bTime.compareTo(aTime);
    });
    _convCtrl.add(updatedList);
    _updateTotalUnreadCount(updatedList);
  }

  /// Schedule a single emit after a short delay. Batches multiple conversation updates
  /// (e.g. 11 FakeConversation events per 5s refresh) into one stream emission and one
  /// buildConversationList log instead of 11.
  void _scheduleConvListEmit() {
    if (_convCtrl.isClosed) return;
    _convFlushTimer?.cancel();
    _convFlushTimer = Timer(_convFlushDelay, () {
      _convFlushTimer = null;
      if (_convCtrl.isClosed) return;
      _emitConvList();
    });
  }

  Future<V2TimConversation> _mapConv(FakeConversation c,
      {V2TimMessage? overrideLastMessage}) async {
    final conv = V2TimConversation(conversationID: c.conversationID);
    conv.type =
        c.isGroup ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C;
    if (c.isGroup) {
      conv.groupID = c.conversationID.replaceFirst('group_', '');
      // Map Tox group type to UIKit GroupType for call button visibility:
      // "conference" → AVChatRoom (calls not supported), "group" → Work (calls supported)
      conv.groupType =
          (c.groupType == 'conference') ? GroupType.AVChatRoom : GroupType.Work;
    } else {
      conv.userID = c.conversationID.replaceFirst('c2c_', '');
    }
    // Use the title from FakeConversation, which should already have the latest name
    // The title is set in _refreshGroups() from Prefs.getGroupName()
    conv.showName = c.title;
    conv.faceUrl = c.faceUrl; // Set faceUrl from FakeConversation
    conv.unreadCount = c.unreadCount;
    conv.isPinned = c.isPinned;
    // recvOpt is the per-peer DND/mute state (0 = V2TIM_RECEIVE_MESSAGE,
    // 2 = V2TIM_RECEIVE_NOT_NOTIFY/mute). Read it SYNCHRONOUSLY from the
    // C2CRecvOptCache projection of the native receive-opt map (NOT Prefs — Prefs
    // is only the durable backing store, hydrated into the cache at session
    // start). A real-UI mute flows through the binary-replacement binding and
    // updates this cache via the native OnConversationChanged push. _mapConv was
    // previously hardcoded to 0, which wiped the mute on every ~5s rebuild, so
    // _shouldSuppress (and l3_dump_state, and the profile toggle which reads this
    // same conversation.recvOpt) all saw 0 and the mute never took effect.
    // Group DND now persists locally too (Tox has no native group recv-opt):
    // read it from the account-scoped Prefs key the group-profile switch writes
    // via setGroupReceiveMessageOpt. This is the conversation cache the
    // notification suppressor reads (UikitDataFacade.conversationList), so
    // without this projection a muted group would still ring. C2C stays on the
    // synchronous C2CRecvOptCache (native-push backed).
    if (c.isGroup) {
      final gid = conv.groupID ?? c.conversationID.replaceFirst('group_', '');
      final accountToxId = await Prefs.getCurrentAccountToxId();
      conv.recvOpt = await Prefs.getGroupReceiveMessageOpt(gid, accountToxId);
    } else {
      conv.recvOpt = C2CRecvOptCache.optFor(
          conv.userID ?? c.conversationID.replaceFirst('c2c_', ''));
    }
    // Set orderkey for sorting: pinned conversations get higher orderkey
    // Use timestamp as base, add large offset for pinned conversations
    // UIKit sorts by orderkey descending (higher value = first)
    // Get last message timestamp from FfiChatService
    int baseTimestamp = DateTime.now().millisecondsSinceEpoch;
    V2TimMessage? lastMessage;

    // CRITICAL: If overrideLastMessage is provided, use it (this preserves failed messages)
    if (overrideLastMessage != null) {
      lastMessage = overrideLastMessage;
      baseTimestamp =
          (lastMessage.timestamp ?? 0) * 1000; // Convert to milliseconds
    } else {
      // Check failed messages persistence first, as failed messages might be newer than lastMessages
      final conversationId = c.conversationID;
      final peerId = conversationId.startsWith('c2c_')
          ? conversationId.substring(4)
          : (conversationId.startsWith('group_')
              ? conversationId.substring(6)
              : conversationId);
      final userID = conversationId.startsWith('c2c_') ? peerId : null;
      final groupID = conversationId.startsWith('group_') ? peerId : null;

      V2TimMessage? failedLastMessage;
      int failedTimestampMs = 0; // Store in milliseconds for comparison
      try {
        final currentToxId = await Prefs.getCurrentAccountToxId();
        final failedMessagesData =
            await Tim2ToxFailedMessagePersistence.loadFailedMessages(
          userID: userID,
          groupID: groupID,
          accountToxId: currentToxId,
        );

        // Find the latest failed message (by timestamp)
        for (final failedMsgData in failedMessagesData) {
          // CRITICAL: timestamp in persistence is in SECONDS (from V2TimMessage.timestamp)
          // We need to convert to milliseconds for comparison with lastMsgTimestamp
          final failedMsgTimestampSeconds =
              failedMsgData['timestamp'] as int? ?? 0;
          final failedMsgTimestampMs =
              failedMsgTimestampSeconds * 1000; // Convert to milliseconds

          if (failedMsgTimestampMs > failedTimestampMs) {
            failedTimestampMs = failedMsgTimestampMs;
            final failedMsgID = failedMsgData['msgID'] as String?;
            final failedID = failedMsgData['id'] as String?;
            final failedText = failedMsgData['text'] as String? ?? '';
            final failedElemType = failedMsgData['elemType'] as int? ??
                MessageElemType.V2TIM_ELEM_TYPE_TEXT;

            // Create a V2TimMessage from failed message data
            failedLastMessage = V2TimMessage(elemType: failedElemType);
            failedLastMessage.msgID = failedMsgID;
            failedLastMessage.id = failedID ?? failedMsgID;
            failedLastMessage.timestamp =
                failedMsgTimestampSeconds; // Keep in seconds for V2TimMessage
            failedLastMessage.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
            failedLastMessage.isSelf =
                true; // Failed messages are always self-sent
            if (failedText.isNotEmpty) {
              failedLastMessage.textElem = V2TimTextElem(text: failedText);
            }
            if (userID != null) {
              failedLastMessage.userID = userID;
            }
            if (groupID != null) {
              failedLastMessage.groupID = groupID;
            }
          }
        }
      } catch (e) {
        AppLogger.warn(
            '[FakeChatDataProvider] failed-message loading for conversation row threw: $e');
      }

      // Get message from lastMessages (keyed by normalized peer id)
      V2TimMessage? lastMsgFromService;
      int lastMsgTimestampMs = 0;
      if (_ffiService != null) {
        var lastMsg = _ffiService!.lastMessages[peerId];
        // Fallback: if lastMessages has no entry (e.g. loadAllHistories used wrong key),
        // get latest from getHistory so conversation list still shows last message/time.
        if (lastMsg == null) {
          final history = _ffiService!.getHistory(peerId);
          if (history.isNotEmpty) {
            final sorted = List<ChatMessage>.from(history)
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
            lastMsg = sorted.first;
          }
        }
        if (lastMsg != null) {
          lastMsgTimestampMs = lastMsg.timestamp.millisecondsSinceEpoch;
          lastMsgFromService =
              _chatMessageToV2TimMessage(lastMsg, peerId, c.isGroup);
        }
      }

      // Use the message with the latest timestamp (failed message or lastMessages message)
      if (failedLastMessage != null &&
          failedTimestampMs >= lastMsgTimestampMs) {
        lastMessage = failedLastMessage;
        baseTimestamp = failedTimestampMs;
      } else if (lastMsgFromService != null) {
        lastMessage = lastMsgFromService;
        baseTimestamp = lastMsgTimestampMs;
      }
    }
    // Set lastMessage field
    conv.lastMessage = lastMessage;
    if (c.isPinned) {
      // Pinned conversations: use very large number (Int64.max - timestamp)
      // This ensures they appear first, and among pinned ones, newer messages appear first
      conv.orderkey =
          9223372036854775807 - baseTimestamp; // Int64.max - timestamp
    } else {
      // Non-pinned conversations: use timestamp directly (newer = higher = first)
      conv.orderkey = baseTimestamp;
    }
    return conv;
  }

  /// Convert ChatMessage to V2TimMessage for use in conversation.lastMessage
  /// Note: This method does NOT check failed persistence - that should be done by the caller
  /// if the message might be failed (e.g., in FakeMessage listener)
  V2TimMessage _chatMessageToV2TimMessage(
      ChatMessage chatMsg, String peerId, bool isGroup) {
    // Determine element type based on mediaKind
    int elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
    if (chatMsg.mediaKind != null) {
      switch (chatMsg.mediaKind) {
        case 'image':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
          break;
        case 'video':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
          break;
        case 'audio':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_SOUND;
          break;
        case 'file':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_FILE;
          break;
        case 'call_record':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_CUSTOM;
          break;
        default:
          elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
      }
    }

    final msg = V2TimMessage(elemType: elemType);
    msg.msgID = chatMsg.msgID;
    msg.userID = chatMsg.fromUserId;
    msg.sender = chatMsg
        .fromUserId; // Set sender to avoid null check error in getShowName
    msg.groupID = isGroup ? peerId : null;
    msg.timestamp = chatMsg.timestamp.millisecondsSinceEpoch ~/ 1000;
    msg.isSelf = chatMsg.isSelf;

    // Call record: custom elem with JSON data; session list summary via getMessageSummary/handleCustomMessage
    if (chatMsg.mediaKind == 'call_record') {
      msg.customElem =
          V2TimCustomElem(data: chatMsg.text, desc: '', extension: '');
      final callLabel = TencentCloudChatIntl().localization?.call ?? 'Call';
      msg.textElem = V2TimTextElem(
          text: '[$callLabel]'); // Fallback if summary reads textElem
      return msg;
    }

    // Set appropriate element based on media type
    if (chatMsg.filePath != null && chatMsg.mediaKind != null) {
      final file = File(chatMsg.filePath!);
      final fileName = chatMsg.filePath!.split('/').last;

      switch (chatMsg.mediaKind) {
        case 'image':
          // Generate UUID from msgID for download identification
          final imageUuid = (chatMsg.msgID ?? msg.msgID ?? '')
              .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final imagePath = chatMsg.filePath;
          final imageUrl = imagePath; // Use local path as URL for Tox protocol
          int? fileSize;
          try {
            if (file.existsSync()) {
              fileSize = file.lengthSync();
            }
          } catch (e) {
            AppLogger.warn(
                '[FakeChatDataProvider] file size lookup for image attachment failed: $e');
          }

          // Create imageList with both thumb and origin images
          // UIKit may request either THUMB (1) or ORIGIN (0), so we need both
          // This is required for downloadMessage to work properly
          final imageList = [
            V2TimImage(
              uuid: imageUuid,
              type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB,
              size: fileSize,
              url: imageUrl,
              localUrl: imagePath,
            ),
            V2TimImage(
              uuid: imageUuid,
              type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN,
              size: fileSize,
              url: imageUrl,
              localUrl: imagePath,
            ),
          ];

          msg.imageElem = V2TimImageElem(
            path: chatMsg.filePath,
            imageList: imageList,
          );
          if (chatMsg.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: chatMsg.text);
          } else {
            msg.textElem = V2TimTextElem(text: fileName);
          }
          break;
        case 'file':
          // Generate UUID from msgID for download identification
          final fileUuid = (chatMsg.msgID ?? msg.msgID ?? '')
              .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final fileUrl =
              chatMsg.filePath; // Use local path as URL for Tox protocol

          msg.fileElem = V2TimFileElem(
            path: chatMsg.filePath,
            fileName: fileName,
            UUID: fileUuid, // Required for downloadMessage
            url: fileUrl, // Required for downloadMessage
            fileSize: file.existsSync() ? file.lengthSync() : null,
            localUrl: chatMsg.filePath,
          );
          if (chatMsg.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: chatMsg.text);
          } else {
            msg.textElem = V2TimTextElem(text: fileName);
          }
          break;
        case 'video':
        case 'audio':
          msg.fileElem = V2TimFileElem(
            path: chatMsg.filePath,
            fileName: fileName,
            fileSize: file.existsSync() ? file.lengthSync() : null,
          );
          if (chatMsg.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: chatMsg.text);
          } else {
            msg.textElem = V2TimTextElem(text: fileName);
          }
          break;
        default:
          if (chatMsg.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: chatMsg.text);
          } else if (chatMsg.filePath != null) {
            msg.textElem = V2TimTextElem(text: fileName);
          }
      }
    } else {
      // Text message
      if (chatMsg.text.isNotEmpty) {
        // U-1 / U-2: keep raw control-signal payloads out of the
        // conversation-list "last message" preview. The full rewrite (with
        // customElem.data carrying the original JSON) happens on the
        // V2TimAdvancedMsgListener path in tim2tox_sdk_platform; here we
        // only need a friendly preview string.
        String previewText = chatMsg.text;
        if (previewText.startsWith('__face__:')) {
          previewText = '[Sticker]';
        } else if (previewText.startsWith('__custom__:')) {
          previewText = '[Custom Message]';
        } else if (previewText.startsWith('__location__:')) {
          previewText = '[Location]';
        }
        msg.textElem = V2TimTextElem(text: previewText);
      }
    }

    return msg;
  }

  @override
  Stream<List<V2TimConversation>> get conversationStream => _convCtrl.stream;

  @override
  Future<List<V2TimConversation>> getInitialConversations() async {
    // If _convMap is already populated, return it
    if (_convMap.isNotEmpty) {
      final list = _convMap.values.toList();
      // Sort conversations: pinned first, then by last message timestamp (newest first)
      list.sort((a, b) {
        final aPinned = a.isPinned ?? false;
        final bPinned = b.isPinned ?? false;
        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }
        final aTime = a.lastMessage?.timestamp ?? 0;
        final bTime = b.lastMessage?.timestamp ?? 0;
        return bTime.compareTo(aTime);
      });
      return list;
    }

    // If _convMap is empty, actively fetch from conversation manager
    // This handles the case where getInitialConversations is called before
    // FakeIM has finished initializing and emitting conversations
    try {
      final mgr = FakeUIKit.instance.conversationManager;
      if (mgr != null) {
        final list = await mgr.getConversationList();
        // Get quit groups to filter them out
        final quitGroups = await Prefs.getQuitGroups();

        // First, remove any conversations from _convMap that are for quit groups
        final convIdsToRemove = <String>[];
        for (final convId in _convMap.keys) {
          if (convId.startsWith('group_')) {
            final gid = convId.replaceFirst('group_', '');
            if (quitGroups.contains(gid)) {
              convIdsToRemove.add(convId);
            }
          }
        }
        for (final convId in convIdsToRemove) {
          _convMap.remove(convId);
        }

        final convList = <V2TimConversation>[];
        for (final c in list) {
          // Skip group conversations that have been quit
          if (c.isGroup) {
            final gid = c.conversationID.replaceFirst('group_', '');
            if (quitGroups.contains(gid)) {
              continue;
            }
          } else {
            // Lazily hydrate persisted mute state on cache miss before _mapConv
            // reads the projection (see the FakeConversation listener rationale).
            final peer = c.conversationID.replaceFirst('c2c_', '');
            if (C2CRecvOptCache.needsHydration(peer)) {
              final selfToxId = await Prefs.getCurrentAccountToxId();
              await C2CRecvOptCache.hydrateFromPrefs(peer, selfToxId);
            }
          }
          final mappedConv = await _mapConv(c);
          _convMap[c.conversationID] = mappedConv;
          convList.add(mappedConv);
        }
        // Sort conversations: pinned first, then by last message timestamp (newest first)
        convList.sort((a, b) {
          final aPinned = a.isPinned ?? false;
          final bPinned = b.isPinned ?? false;
          if (aPinned != bPinned) {
            return aPinned ? -1 : 1;
          }
          final aTime = a.lastMessage?.timestamp ?? 0;
          final bTime = b.lastMessage?.timestamp ?? 0;
          return bTime.compareTo(aTime);
        });
        // Emit to stream so UI gets updated (always emit, even if empty, to ensure UI updates)
        _convCtrl.add(convList);
        _updateTotalUnreadCount(convList);
        return convList;
      }
    } catch (e) {
      // Error fetching conversations - return empty list
      // The stream will update once FakeIM finishes initializing
    }

    // Fallback: return empty list if all else fails
    // The stream will update once conversations are available
    return [];
  }

  @override
  Stream<int> get totalUnreadStream => _unreadCtrl.stream;

  void dispose() {
    _convFlushTimer?.cancel();
    _convFlushTimer = null;
    _convSub?.cancel();
    _unreadSub?.cancel();
    _messageSub?.cancel();
    _friendDeletedSub?.cancel();
    _groupDeletedSub?.cancel();
    final listener = _sdkConvListener;
    if (listener != null) {
      try {
        TencentCloudChat.instance.chatSDKInstance.manager
            .getConversationManager()
            .removeConversationListener(listener: listener);
      } catch (e) {
        AppLogger.debug(
            '[FakeChatDataProvider] removeConversationListener threw on dispose: $e');
      }
      _sdkConvListener = null;
    }
    _convCtrl.close();
    _unreadCtrl.close();
  }
}
