import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import '../call/call_state_notifier.dart';
import '../call/call_service_manager.dart';
import '../util/group_member_last_seen_cache.dart';
import 'fake_event_bus.dart';
import 'fake_im.dart';
import 'fake_managers.dart';
import 'fake_models.dart';
import 'fake_msg_provider.dart';
import 'uikit_data_facade.dart';
import '../util/logger.dart';

class FakeUIKit {
  FakeUIKit._internal();
  static final FakeUIKit instance = FakeUIKit._internal();

  final FakeEventBus eventBusInstance = FakeEventBus();
  FakeIM? _im;
  FakeConversationManager? conversationManager;
  FakeMessageManager? messageManager;
  FakeContactManager? contactManager;
  FakeChatMessageProvider? messageProvider;
  CallStateNotifier? callStateNotifier;
  CallServiceManager? callServiceManager;
  bool _started = false;

  /// Fires when call system (callStateNotifier + callServiceManager) becomes available.
  /// Used by MaterialApp builder to add CallOverlay to the widget tree after login.
  final ValueNotifier<bool> callSystemReady = ValueNotifier(false);

  /// Check if FakeUIKit has been started
  bool get isStarted => _started;

  Future<void> startWithFfi(FfiChatService service) async {
    if (_started) return;
    _im = FakeIM(service, eventBusInstance)..start();
    // FakeConversationManager.start() is async: it awaits the initial pinned
    // read from Prefs so the first getConversationList() does not race the
    // fire-and-forget read (A7). We await it here so the platform/UIKit
    // bridge — installed immediately after this method returns — never sees
    // an empty pinned set when it asks for conversations.
    final convMgr = FakeConversationManager(eventBusInstance, service);
    conversationManager = convMgr;
    await convMgr.start();
    messageManager = FakeMessageManager(eventBusInstance, service)..start();
    contactManager = FakeContactManager(eventBusInstance, service)..start();
    // Group-member last-seen cache subscribes to the message bus so new
    // group messages live-update the per-group recency map without a
    // full history re-scan.
    GroupMemberLastSeenCache.instance.attach(eventBusInstance);
    ensureOwnedMessageProvider(service);
    callStateNotifier = CallStateNotifier();
    callServiceManager = CallServiceManager(service, callStateNotifier!);

    // Wire up call record insertion: when a call ends, insert a call record
    // message into the corresponding chat conversation.
    callServiceManager!.onCallRecordNeeded =
        (remoteUserID, isVideo, isOutgoing, durationSeconds, endReason) {
      _insertCallRecord(service, remoteUserID, isVideo, isOutgoing,
          durationSeconds, endReason);
    };

    _started = true;
    // Never set callSystemReady synchronously: ValueListenableBuilder in MaterialApp.builder
    // would be notified during build (initState -> ensureInitialized -> startWithFfi). Defer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      callSystemReady.value = true;
    });
  }

  FakeIM? get im => _im;

  /// Return the session-owned message provider, creating it when startup or a
  /// defensive fallback reaches this point before normal provider wiring.
  FakeChatMessageProvider ensureOwnedMessageProvider(FfiChatService service) {
    return messageProvider ??= FakeChatMessageProvider(ffiService: service);
  }

  /// Adopt an already-created fallback so [dispose] owns its subscriptions and
  /// stream controllers just like a provider created during [startWithFfi].
  FakeChatMessageProvider adoptOwnedMessageProvider(
    FakeChatMessageProvider provider,
  ) {
    final owned = messageProvider;
    if (owned != null && !identical(owned, provider)) {
      throw StateError('FakeUIKit already owns a different message provider');
    }
    messageProvider = provider;
    return provider;
  }

  /// Insert a call record custom message into the chat conversation.
  ///
  /// Recognized `endReason` values and their mapping to UIKit's CallingMessage
  /// `actionType` (UIKit only parses 1/2/4/5 — anything else regresses to
  /// "outgoing call invite"):
  ///   - 'hangup'        -> 1 (call ended normally, with duration)
  ///   - 'network_error' -> 1 (call ended because the transport / reconnect
  ///                           grace expired; treated like a hangup so UIKit
  ///                           renders "abnormal end" with duration rather
  ///                           than a call invite)
  ///   - 'cancel'        -> 2 (caller cancelled before callee picked up)
  ///   - 'reject'        -> 4 (callee rejected)
  ///   - 'timeout'       -> 5 (no answer)
  /// Any other / unknown value falls through to actionType 1 — but the inner
  /// signaling `cmd` and `call_end` are only set to the "ended" shape for
  /// reasons listed in `isEnded` below, so unknown reasons still render as an
  /// invite. Extend `isEnded` when adding a new "call ran and then died"
  /// reason.
  void _insertCallRecord(
    FfiChatService service,
    String remoteUserID,
    bool isVideo,
    bool isOutgoing,
    int durationSeconds,
    String endReason,
  ) {
    final selfId = service.selfId;
    final callerID = isOutgoing ? selfId : remoteUserID;
    final calleeID = isOutgoing ? remoteUserID : selfId;

    AppLogger.info(
        '[FakeUIKit] _insertCallRecord: endReason=$endReason, remoteUserID=$remoteUserID, '
        'selfId=$selfId, isVideo=$isVideo, isOutgoing=$isOutgoing, duration=$durationSeconds');

    // Determine actionType matching CallingMessage protocol
    int actionType;
    switch (endReason) {
      case 'cancel':
        actionType = 2;
        break;
      case 'reject':
        actionType = 4;
        break;
      case 'timeout':
        actionType = 5;
        break;
      case 'network_error':
        // Call ended due to transport / reconnect grace expiring — same shape
        // as a normal hangup so UIKit shows "call ended" instead of an invite.
        actionType = 1;
        break;
      default: // 'hangup'
        actionType = 1;
        break;
    }

    // Reasons that mean "the call ran and then ended" — these produce a
    // 'hangup' cmd and a `call_end` duration so UIKit renders an ended-call
    // bubble. Anything else is treated as a fresh invite by the inner JSON.
    final isEnded = endReason == 'hangup' || endReason == 'network_error';

    // Build inner signaling JSON (matches CallingMessage._fromJSON expectations)
    final signalingData = <String, dynamic>{
      'businessID': 'av_call',
      'call_type': isVideo ? 2 : 1,
      'data': {
        'cmd': isEnded ? 'hangup' : (isVideo ? 'videoCall' : 'audioCall'),
        'inviter': callerID,
      },
    };
    if (isEnded && durationSeconds > 0) {
      signalingData['call_end'] = durationSeconds;
    }

    // Build outer JSON (customElem.data structure)
    final callRecordJson = jsonEncode({
      'data': jsonEncode(signalingData),
      'actionType': actionType,
      'timeout': 30,
      'inviter': callerID,
      'inviteeList': [calleeID],
      'inviteID': 'call_${DateTime.now().millisecondsSinceEpoch}',
      'groupID': '',
    });

    final msgID = 'call_record_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();

    // Store call record as ChatMessage in FfiChatService so it's returned by
    // getHistory() — the REAL path UIKit uses to load messages via
    // Tim2ToxSdkPlatform.getHistoryMessageListV2().
    final chatMsg = ChatMessage(
      text: callRecordJson,
      fromUserId: selfId,
      isSelf: true,
      timestamp: now,
      mediaKind: 'call_record',
      msgID: msgID,
      isReceived: true,
      isRead: true,
    );
    service.addLocalMessage(remoteUserID, chatMsg);
    AppLogger.info(
        '[FakeUIKit] Call record stored in FfiChatService: msgID=$msgID, remoteUserID=$remoteUserID, actionType=$actionType');

    // Also emit via event bus for real-time delivery if chat page is already open.
    // Find the correct conversation key from the message provider to match _ctrls.
    String conversationID = 'c2c_$remoteUserID';
    final provider = messageProvider;
    if (provider != null) {
      final matchedConvID = provider.findConversationForUser(remoteUserID);
      if (matchedConvID != null) conversationID = matchedConvID;
    }
    final fakeMsg = FakeMessage(
      msgID: msgID,
      conversationID: conversationID,
      fromUser: selfId,
      text: callRecordJson,
      timestampMs: now.millisecondsSinceEpoch,
      mediaKind: 'call_record',
    );
    eventBusInstance.emit(FakeIM.topicMessage, fakeMsg);
    AppLogger.info(
        '[FakeUIKit] Call record emitted via event bus: msgID=$msgID, convID=$conversationID');

    // Also inject into UIKit message data so currently-open chat list updates
    // immediately even when external stream controllers are not attached.
    _injectCallRecordIntoMessageData(
      remoteUserID: remoteUserID,
      selfID: selfId,
      msgID: msgID,
      timestampMs: now.millisecondsSinceEpoch,
      callRecordJson: callRecordJson,
    );
  }

  void _injectCallRecordIntoMessageData({
    required String remoteUserID,
    required String selfID,
    required String msgID,
    required int timestampMs,
    required String callRecordJson,
  }) {
    try {
      final msg =
          V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
      msg.msgID = msgID;
      msg.id = msgID;
      msg.timestamp = timestampMs ~/ 1000;
      msg.userID = remoteUserID;
      msg.sender = selfID;
      msg.isSelf = true;
      msg.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
      msg.customElem =
          V2TimCustomElem(data: callRecordJson, desc: '', extension: '');
      UikitDataFacade.onReceiveNewMessage(msg);
      AppLogger.info(
          '[FakeUIKit] Call record injected into messageData: msgID=$msgID, userID=$remoteUserID');
    } catch (e) {
      AppLogger.error(
          '[FakeUIKit] Call record messageData injection failed: $e');
    }
  }

  void dispose() {
    callServiceManager?.dispose();
    callServiceManager = null;
    callStateNotifier?.dispose();
    callStateNotifier = null;
    GroupMemberLastSeenCache.instance.clear();
    _im?.dispose();
    _im = null;
    conversationManager?.dispose();
    messageManager?.dispose();
    contactManager?.dispose();
    final ownedMessageProvider = messageProvider;
    ownedMessageProvider?.dispose();
    if (identical(ChatMessageProviderRegistry.provider, ownedMessageProvider)) {
      ChatMessageProviderRegistry.provider = null;
    }
    messageProvider = null;
    eventBusInstance.dispose();
    _started = false;
    callSystemReady.value = false;
    // Clear TencentCloudChat.dataInstance (singleton) so next login/account does not see previous account's data
    UikitDataFacade.clearAll(reason: 'FakeUIKit.dispose');
  }
}
