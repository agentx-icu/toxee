import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_id_generator.dart';

import '../account_export/test_support.dart';

typedef _TextSendCall = ({
  String? userID,
  String? groupID,
  String text,
  String? clientMessageID,
});

class _RecordingChatMessageProvider
    implements ChatMessageProviderWithSendResult {
  _RecordingChatMessageProvider(this.result);

  ChatMessageSendResult result;
  final List<_TextSendCall> calls = <_TextSendCall>[];

  @override
  Stream<List<V2TimMessage>> streamFor({String? userID, String? groupID}) =>
      const Stream<List<V2TimMessage>>.empty();

  @override
  Future<void> sendText({
    String? userID,
    String? groupID,
    required String text,
  }) async {
    throw StateError('Platform must use sendTextWithResult when available');
  }

  @override
  Future<ChatMessageSendResult> sendTextWithResult({
    String? userID,
    String? groupID,
    required String text,
    String? clientMessageID,
  }) async {
    calls.add((
      userID: userID,
      groupID: groupID,
      text: text,
      clientMessageID: clientMessageID,
    ));
    return result;
  }

  @override
  Future<void> sendImage({
    String? userID,
    String? groupID,
    required String imagePath,
    String? imageName,
  }) async {}

  @override
  Future<void> sendFile({
    String? userID,
    String? groupID,
    required String filePath,
    String? fileName,
  }) async {}

  @override
  Future<void> deleteMessages({
    String? userID,
    String? groupID,
    required List<String> msgIDs,
  }) async {}
}

class _LegacyChatMessageProvider implements ChatMessageProvider {
  final List<_TextSendCall> calls = <_TextSendCall>[];

  @override
  Stream<List<V2TimMessage>> streamFor({String? userID, String? groupID}) =>
      const Stream<List<V2TimMessage>>.empty();

  @override
  Future<void> sendText({
    String? userID,
    String? groupID,
    required String text,
  }) async {
    calls.add((
      userID: userID,
      groupID: groupID,
      text: text,
      clientMessageID: null,
    ));
  }

  @override
  Future<void> sendImage({
    String? userID,
    String? groupID,
    required String imagePath,
    String? imageName,
  }) async {}

  @override
  Future<void> sendFile({
    String? userID,
    String? groupID,
    required String filePath,
    String? fileName,
  }) async {}

  @override
  Future<void> deleteMessages({
    String? userID,
    String? groupID,
    required List<String> msgIDs,
  }) async {}
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

V2TimMessage _optimisticMessage({
  required String messageID,
  required int elemType,
  V2TimTextElem? textElem,
  V2TimMergerElem? mergerElem,
  V2TimFaceElem? faceElem,
  V2TimLocationElem? locationElem,
  V2TimCustomElem? customElem,
}) {
  return V2TimMessage(
    id: messageID,
    msgID: messageID,
    elemType: elemType,
    textElem: textElem,
    mergerElem: mergerElem,
    faceElem: faceElem,
    locationElem: locationElem,
    customElem: customElem,
    isSelf: true,
    sender: 'test-self',
  )..status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
}

void _seedMessage(String targetID, V2TimMessage message) {
  TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
    targetID: [message],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('Tim2ToxSdkPlatform text send identity', () {
    late AccountExportTestEnv env;
    late FfiChatService ffi;
    late Tim2ToxSdkPlatform platform;
    late _RecordingChatMessageProvider provider;
    late ChatMessageProvider? previousProvider;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      ffi = FfiChatService(
        historyDirectory: '${env.root.path}/history',
        queueFilePath: '${env.root.path}/offline_queue.json',
      );
      platform = Tim2ToxSdkPlatform(ffiService: ffi);
      provider = _RecordingChatMessageProvider(
        ChatMessageSendResult(messageID: 'unused', isPending: false),
      );
      previousProvider = ChatMessageProviderRegistry.provider;
      ChatMessageProviderRegistry.provider = provider;
      TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
    });

    tearDown(() async {
      ChatMessageProviderRegistry.provider = previousProvider;
      TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
      platform.dispose();
      await ffi.dispose();
      await env.dispose();
    });

    test(
      'pending result preserves optimistic identity and SENDING status',
      () async {
        const peerID = 'pending-peer';
        const messageID = 'optimistic-pending-id';
        final optimistic = _optimisticMessage(
          messageID: messageID,
          elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
          textElem: V2TimTextElem(text: 'offline text'),
        );
        provider.result = ChatMessageSendResult(
          messageID: messageID,
          isPending: true,
        );
        _seedMessage(peerID, optimistic);

        final callback = await platform.sendMessage(
          id: messageID,
          receiver: peerID,
          groupID: '',
        );

        expect(callback.code, 0);
        expect(callback.data, same(optimistic));
        expect(provider.calls.single.clientMessageID, messageID);
        expect(callback.data!.id, messageID);
        expect(callback.data!.msgID, messageID);
        expect(callback.data!.status, MessageStatus.V2TIM_MSG_STATUS_SENDING);
      },
    );

    test(
      'non-pending result preserves optimistic identity as SEND_SUCC',
      () async {
        const groupID = 'online-group';
        const messageID = 'optimistic-success-id';
        final optimistic = _optimisticMessage(
          messageID: messageID,
          elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
          textElem: V2TimTextElem(text: 'online text'),
        );
        provider.result = ChatMessageSendResult(
          messageID: messageID,
          isPending: false,
        );
        _seedMessage(groupID, optimistic);

        final callback = await platform.sendMessage(
          id: messageID,
          receiver: '',
          groupID: groupID,
        );

        expect(callback.code, 0);
        expect(callback.data, same(optimistic));
        expect(provider.calls.single.clientMessageID, messageID);
        expect(provider.calls.single.groupID, groupID);
        expect(callback.data!.id, messageID);
        expect(callback.data!.msgID, messageID);
        expect(callback.data!.status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
      },
    );

    test(
      'all text-like branches forward and reconcile the provider result',
      () async {
        final cases = <({String name, V2TimMessage message})>[
          (
            name: 'text',
            message: _optimisticMessage(
              messageID: 'client-text',
              elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
              textElem: V2TimTextElem(text: 'plain'),
            ),
          ),
          (
            name: 'merger',
            message: _optimisticMessage(
              messageID: 'client-merger',
              elemType: MessageElemType.V2TIM_ELEM_TYPE_MERGER,
              mergerElem: V2TimMergerElem(compatibleText: 'merged'),
            ),
          ),
          (
            name: 'face',
            message: _optimisticMessage(
              messageID: 'client-face',
              elemType: MessageElemType.V2TIM_ELEM_TYPE_FACE,
              faceElem: V2TimFaceElem(index: 1, data: 'face'),
            ),
          ),
          (
            name: 'location',
            message: _optimisticMessage(
              messageID: 'client-location',
              elemType: MessageElemType.V2TIM_ELEM_TYPE_LOCATION,
              locationElem: V2TimLocationElem(
                desc: 'place',
                longitude: 1,
                latitude: 2,
              ),
            ),
          ),
          (
            name: 'custom',
            message: _optimisticMessage(
              messageID: 'client-custom',
              elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
              customElem: V2TimCustomElem(data: 'custom-data'),
            ),
          ),
        ];

        for (final entry in cases) {
          final clientID = entry.message.id!;
          final providerID = 'provider-${entry.name}';
          final peerID = 'peer-${entry.name}';
          provider.calls.clear();
          provider.result = ChatMessageSendResult(
            messageID: providerID,
            isPending: false,
          );
          _seedMessage(peerID, entry.message);

          final callback = await platform.sendMessage(
            id: clientID,
            receiver: peerID,
            groupID: '',
          );

          expect(callback.code, 0, reason: entry.name);
          expect(callback.data, same(entry.message), reason: entry.name);
          expect(
            provider.calls.single.clientMessageID,
            clientID,
            reason: entry.name,
          );
          expect(callback.data!.id, providerID, reason: entry.name);
          expect(callback.data!.msgID, providerID, reason: entry.name);
        }
      },
    );

    test('legacy provider remains source-compatible', () async {
      const peerID = 'legacy-peer';
      const messageID = 'legacy-message-id';
      final legacyProvider = _LegacyChatMessageProvider();
      final optimistic = _optimisticMessage(
        messageID: messageID,
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        textElem: V2TimTextElem(text: 'legacy text'),
      );
      ChatMessageProviderRegistry.provider = legacyProvider;
      _seedMessage(peerID, optimistic);

      final callback = await platform.sendMessage(
        id: messageID,
        receiver: peerID,
        groupID: '',
      );

      expect(callback.code, 0);
      expect(legacyProvider.calls, hasLength(1));
      expect(legacyProvider.calls.single.text, 'legacy text');
      expect(callback.data, same(optimistic));
      expect(callback.data!.status, MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC);
    });

    test(
      'rapid creates across platform instances have distinct IDs',
      () async {
        final secondPlatform = Tim2ToxSdkPlatform(ffiService: ffi);
        addTearDown(secondPlatform.dispose);
        final creates =
            <Future<V2TimValueCallback<V2TimMsgCreateInfoResult>>>[];
        for (var i = 0; i < 64; i++) {
          creates.add(
            i.isEven
                ? platform.createTextMessage(text: 'same rapid text')
                : secondPlatform.createTextAtMessage(
                    text: 'same rapid text',
                    atUserList: const ['peer'],
                  ),
          );
        }

        final callbacks = await Future.wait(creates);
        final ids = callbacks.map((callback) => callback.data!.id!).toList();

        expect(callbacks.every((callback) => callback.code == 0), isTrue);
        expect(ids.toSet(), hasLength(ids.length));
        expect(
          ids.every((messageID) => MessageIdGenerator.parse(messageID) != null),
          isTrue,
        );
        expect(
          callbacks.map((callback) => callback.data!.messageInfo!.msgID),
          ids,
        );
      },
    );
  }, skip: skipReason);
}
