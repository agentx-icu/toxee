import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';
import 'package:toxee/util/prefs.dart';

import '../account_export/test_support.dart';

class _BridgeFfiChatService extends FfiChatService {
  _BridgeFfiChatService(Directory root)
    : super(
        historyDirectory: '${root.path}/history',
        queueFilePath: '${root.path}/offline_queue.json',
      );

  final StreamController<ChatMessage> _sentMessages =
      StreamController<ChatMessage>.broadcast(sync: true);
  final Map<String, String> _peerByMessageID = <String, String>{};
  final List<String?> c2cClientMessageIDs = <String?>[];
  final List<String?> groupClientMessageIDs = <String?>[];
  int _generatedSequence = 0;

  @override
  Stream<ChatMessage> get messages => _sentMessages.stream;

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async => const [];

  @override
  Future<List<({String userId, String wording})>>
  getFriendApplications() async => const [];

  @override
  int getUnreadOf(String peerId) => 0;

  @override
  (String?, String?) findUserIDAndGroupIDFromMsgID(String msgID) =>
      (_peerByMessageID[msgID], null);

  @override
  Future<ChatMessage> sendTextWithResult(
    String peerId,
    String text, {
    String? cloudCustomData,
    String? clientMessageID,
  }) async {
    c2cClientMessageIDs.add(clientMessageID);
    final messageID = clientMessageID != null && clientMessageID.isNotEmpty
        ? clientMessageID
        : 'generated-c2c-${_generatedSequence++}';
    final normalizedPeerID = normalizeToxId(peerId);
    final message = ChatMessage(
      text: text,
      fromUserId: 'test-self',
      isSelf: true,
      timestamp: DateTime.now(),
      isPending: true,
      msgID: messageID,
      cloudCustomData: cloudCustomData,
    );
    _peerByMessageID[messageID] = normalizedPeerID;
    addLocalMessage(normalizedPeerID, message);
    _sentMessages.add(message);
    return message;
  }

  @override
  Future<ChatMessage> sendGroupTextWithResult(
    String groupId,
    String text, {
    String? clientMessageID,
  }) async {
    groupClientMessageIDs.add(clientMessageID);
    final messageID = clientMessageID != null && clientMessageID.isNotEmpty
        ? clientMessageID
        : 'generated-group-${_generatedSequence++}';
    final message = ChatMessage(
      text: text,
      fromUserId: 'test-self',
      isSelf: true,
      timestamp: DateTime.now(),
      groupId: groupId,
      isPending: true,
      msgID: messageID,
    );
    addLocalMessage(groupId, message);
    _sentMessages.add(message);
    return message;
  }

  void emitDeliveredC2C({
    required String peerID,
    required String text,
    required String messageID,
  }) {
    final normalizedPeerID = normalizeToxId(peerID);
    final message = ChatMessage(
      text: text,
      fromUserId: 'test-self',
      isSelf: true,
      timestamp: DateTime.now(),
      isPending: false,
      isReceived: true,
      msgID: messageID,
    );
    _peerByMessageID[messageID] = normalizedPeerID;
    addLocalMessage(normalizedPeerID, message);
    _sentMessages.add(message);
  }

  @override
  Future<void> dispose() async {
    await _sentMessages.close();
    await super.dispose();
  }
}

bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void _setAudioChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (MethodCall call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (MethodCall call) async => null,
  );
}

void _clearAudioChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ChatMessageSendResult rejects an empty message ID', () {
    expect(
      () => ChatMessageSendResult(messageID: '', isPending: false),
      throwsArgumentError,
    );
  });

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('provider-neutral text send identity bridge', () {
    late AccountExportTestEnv env;
    late _BridgeFfiChatService ffi;
    Tim2ToxSdkPlatform? platform;
    V2TimAdvancedMsgListener? advancedListener;
    ChatMessageProvider? previousProvider;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      _setAudioChannelMocks();
      try {
        FakeUIKit.instance.dispose();
      } catch (_) {}
      ffi = _BridgeFfiChatService(env.root);
      await FakeUIKit.instance.startWithFfi(ffi);
      platform = null;
      advancedListener = null;
      previousProvider = ChatMessageProviderRegistry.provider;
      TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
    });

    tearDown(() async {
      if (platform != null && advancedListener != null) {
        await platform!.removeAdvancedMsgListener(listener: advancedListener);
      }
      platform?.dispose();
      ChatMessageProviderRegistry.provider = previousProvider;
      TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
      try {
        FakeUIKit.instance.dispose();
      } catch (_) {}
      await ffi.dispose();
      _clearAudioChannelMocks();
      await env.dispose();
    });

    test('C2C forwards distinct caller IDs and emits once per send', () async {
      const peerID =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      const firstID = 'provider-c2c-1';
      const secondID = 'provider-c2c-2';
      const flushID = 'provider-c2c-flush';
      final bus = FakeUIKit.instance.eventBusInstance;
      final events = <FakeMessage>[];
      final eventsFlushed = Completer<void>();
      final subscription = bus.on<FakeMessage>(FakeIM.topicMessage).listen((
        event,
      ) {
        if (event.msgID == flushID) {
          if (!eventsFlushed.isCompleted) {
            eventsFlushed.complete();
          }
          return;
        }
        events.add(event);
      });
      addTearDown(subscription.cancel);
      final provider = FakeUIKit.instance.messageProvider!;

      final first = await provider.sendTextWithResult(
        userID: peerID,
        text: 'same text',
        clientMessageID: firstID,
      );
      final second = await provider.sendTextWithResult(
        userID: peerID,
        text: 'same text',
        clientMessageID: secondID,
      );

      bus.emit(
        FakeIM.topicMessage,
        FakeMessage(
          msgID: flushID,
          conversationID: 'c2c_$peerID',
          fromUser: '',
          text: '',
          timestampMs: 0,
        ),
      );
      await eventsFlushed.future;
      await subscription.cancel();
      final sentEvents = events
          .where((event) => event.msgID == firstID || event.msgID == secondID)
          .toList();

      expect(ffi.c2cClientMessageIDs, [firstID, secondID]);
      expect(first.messageID, firstID);
      expect(second.messageID, secondID);
      expect(first.isPending, isTrue);
      expect(second.isPending, isTrue);
      expect(sentEvents.map((event) => event.msgID), [firstID, secondID]);
      expect(await Prefs.getFriendActivity(peerID), isNotNull);
    });

    test(
      'group forwards caller ID and returns the bridge pending state',
      () async {
        const groupID = 'provider-group';
        const messageID = 'provider-group-1';
        const flushID = 'provider-group-flush';
        final bus = FakeUIKit.instance.eventBusInstance;
        final events = <FakeMessage>[];
        final eventsFlushed = Completer<void>();
        final subscription = bus.on<FakeMessage>(FakeIM.topicMessage).listen((
          event,
        ) {
          if (event.msgID == flushID) {
            if (!eventsFlushed.isCompleted) {
              eventsFlushed.complete();
            }
            return;
          }
          events.add(event);
        });
        addTearDown(subscription.cancel);
        final provider = FakeUIKit.instance.messageProvider!;

        final result = await provider.sendTextWithResult(
          groupID: groupID,
          text: 'group text',
          clientMessageID: messageID,
        );

        bus.emit(
          FakeIM.topicMessage,
          FakeMessage(
            msgID: flushID,
            conversationID: 'group_$groupID',
            fromUser: '',
            text: '',
            timestampMs: 0,
          ),
        );
        await eventsFlushed.future;
        await subscription.cancel();
        final sentEvents = events
            .where((event) => event.msgID == messageID)
            .toList();

        expect(ffi.groupClientMessageIDs, [messageID]);
        expect(result.messageID, messageID);
        expect(result.isPending, isTrue);
        expect(sentEvents, hasLength(1));
        expect(sentEvents.single.conversationID, 'group_$groupID');
      },
    );

    test(
      'offline C2C row transitions from SENDING to SEND_SUCC in place',
      () async {
        const peerID =
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
        const messageID = 'cross-layer-offline-c2c';
        const text = 'one optimistic row';
        final messageData = TencentCloudChat.instance.dataInstance.messageData;
        final pendingProjection = Completer<V2TimMessage>();
        final deliveredModified = Completer<V2TimMessage>();
        var pendingModifiedCount = 0;
        final optimistic = V2TimMessage(
          id: messageID,
          msgID: messageID,
          userID: peerID,
          sender: 'test-self',
          isSelf: true,
          elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
          textElem: V2TimTextElem(text: text),
        )..status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
        messageData.messageListMap = {
          peerID: [optimistic],
        };

        platform = Tim2ToxSdkPlatform(ffiService: ffi);
        ChatMessageProviderRegistry.provider =
            FakeUIKit.instance.messageProvider;
        advancedListener = V2TimAdvancedMsgListener(
          onRecvNewMessage: (message) {
            messageData.onReceiveNewMessage(message);
          },
          onRecvMessageModified: (message) {
            messageData.onReceiveMessageModified(message);
            if (message.msgID == messageID) {
              if (message.status == MessageStatus.V2TIM_MSG_STATUS_SENDING) {
                pendingModifiedCount++;
                if (pendingModifiedCount == 2 &&
                    !pendingProjection.isCompleted) {
                  pendingProjection.complete(message);
                }
              } else if (message.status ==
                      MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC &&
                  !deliveredModified.isCompleted) {
                deliveredModified.complete(message);
              }
            }
          },
        );
        await platform!.addAdvancedMsgListener(listener: advancedListener!);

        final sendResult = await platform!.sendMessage(
          id: messageID,
          receiver: peerID,
          groupID: '',
        );
        await pendingProjection.future;

        expect(sendResult.code, 0);
        expect(sendResult.data, same(optimistic));
        expect(pendingModifiedCount, greaterThanOrEqualTo(2));
        final pendingRows = messageData.getMessageList(key: peerID);
        expect(pendingRows, hasLength(1));
        expect(pendingRows.single.id, messageID);
        expect(pendingRows.single.msgID, messageID);
        expect(
          pendingRows.single.status,
          MessageStatus.V2TIM_MSG_STATUS_SENDING,
        );

        ffi.emitDeliveredC2C(peerID: peerID, text: text, messageID: messageID);
        await deliveredModified.future;

        final deliveredRows = messageData.getMessageList(key: peerID);
        expect(deliveredRows, hasLength(1));
        expect(deliveredRows.single.id, messageID);
        expect(deliveredRows.single.msgID, messageID);
        expect(
          deliveredRows.single.status,
          MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
        );
      },
    );
  }, skip: skipReason);
}
