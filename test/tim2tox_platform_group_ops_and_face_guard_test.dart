// Tim2ToxSdkPlatform (Codex review 3):
//
// * #1  setGroupMemberInfo / muteGroupMember / inviteUserToGroup (and the
//       older kick / set-role) must reach the NATIVE group adapter, never the
//       routed facade — which dispatches back to this platform when it is
//       installed. Both entry points (the platform itself, and the facade the
//       UIKit calls) must complete instead of recursing.
// * #14 a `__face__:` envelope over one Tox message is refused (8001) like the
//       custom / location envelopes, instead of arriving split and unparseable.
//
// FFI dependency: FfiChatService opens the tim2tox FFI library in its
// constructor. Skipped when the library is not loadable here.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

class _RecordingProvider implements ChatMessageProvider {
  final List<String> sentTexts = [];

  @override
  Stream<List<V2TimMessage>> streamFor({String? userID, String? groupID}) =>
      const Stream<List<V2TimMessage>>.empty();

  @override
  Future<void> sendText({
    String? userID,
    String? groupID,
    required String text,
  }) async {
    sentTexts.add(text);
  }

  @override
  Future<void> sendImage({
    String? userID,
    String? groupID,
    required String imagePath,
    String? imageName,
  }) async =>
      throw StateError('unexpected image send');

  @override
  Future<void> sendFile({
    String? userID,
    String? groupID,
    required String filePath,
    String? fileName,
  }) async =>
      throw StateError('unexpected file send');

  @override
  Future<void> deleteMessages({
    String? userID,
    String? groupID,
    required List<String> msgIDs,
  }) async {}
}

V2TimMessage _faceMessage(String id, String data) {
  final message = V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_FACE);
  message.id = id;
  message.msgID = id;
  message.faceElem = V2TimFaceElem(index: 1, data: data);
  message.timestamp = 100;
  message.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
  return message;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late FfiChatService service;
  late Tim2ToxSdkPlatform platform;
  late TencentCloudChatSdkPlatform previousPlatform;

  setUpAll(() {
    // As the app does (binary replacement): V2TimMessage() reads the server
    // time through the native bindings.
    setNativeLibraryName('tim2tox_ffi');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ChatMessageProviderRegistry.provider = null;
    TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
    if (skipReason != null) return;
    previousPlatform = TencentCloudChatSdkPlatform.instance;
    service = FfiChatService();
    platform = Tim2ToxSdkPlatform(ffiService: service);
    // Installed, as in the app: the routed facade now dispatches here.
    TencentCloudChatSdkPlatform.instance = platform;
  });

  tearDown(() {
    ChatMessageProviderRegistry.provider = null;
    TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
    if (skipReason != null) return;
    platform.dispose();
    NativeLibraryManager.customCallbackHandler = null;
    TencentCloudChatSdkPlatform.instance = previousPlatform;
  });

  group('group member operations reach the native adapter (#1)',
      skip: skipReason, () {
    // No SDK login in a unit test: the native adapter answers "sdk not init"
    // at once. A route through the facade would instead call back into the
    // platform without end (stack overflow / never completing).
    const timeout = Duration(seconds: 5);
    const gid = 'tox_1';
    const uid =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

    test('platform entry points complete', () async {
      expect((await platform
                  .setGroupMemberInfo(groupID: gid, userID: uid, nameCard: 'n')
                  .timeout(timeout))
              .code,
          isNot(0));
      expect((await platform
                  .muteGroupMember(groupID: gid, userID: uid, seconds: 60)
                  .timeout(timeout))
              .code,
          isNot(0));
      final invite = await platform
          .inviteUserToGroup(groupID: gid, userList: [uid]).timeout(timeout);
      expect(invite.code, isNot(0));
      expect((await platform
                  .kickGroupMember(groupID: gid, memberList: [uid])
                  .timeout(timeout))
              .code,
          isNot(0));
      expect((await platform
                  .setGroupMemberRole(groupID: gid, userID: uid, role: 300)
                  .timeout(timeout))
              .code,
          isNot(0));
    });

    test('the routed facade reaches the platform and completes', () async {
      final facade = V2TIMGroupManager();
      expect(TencentCloudChatSdkPlatform.instance.isPlatformRouted, isTrue);
      expect((await facade
                  .setGroupMemberInfo(groupID: gid, userID: uid, nameCard: 'n')
                  .timeout(timeout))
              .code,
          isNot(0));
      expect((await facade
                  .muteGroupMember(groupID: gid, userID: uid, seconds: 60)
                  .timeout(timeout))
              .code,
          isNot(0));
      expect((await facade
                  .inviteUserToGroup(groupID: gid, userList: [uid])
                  .timeout(timeout))
              .code,
          isNot(0));
      expect((await facade
                  .kickGroupMember(groupID: gid, memberList: [uid])
                  .timeout(timeout))
              .code,
          isNot(0));
      expect((await facade
                  .setGroupMemberRole(
                      groupID: gid,
                      userID: uid,
                      role: GroupMemberRoleTypeEnum.V2TIM_GROUP_MEMBER_ROLE_ADMIN)
                  .timeout(timeout))
              .code,
          isNot(0));
    });
  });

  group('face envelope size guard (#14)', skip: skipReason, () {
    test('an oversized face message is refused before the wire', () async {
      final provider = _RecordingProvider();
      ChatMessageProviderRegistry.provider = provider;
      // Multi-byte UTF-8: under the limit in UTF-16 units, over it in bytes.
      final message = _faceMessage('face-big', '表' * 500);
      TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
        'peer-a': [message],
      };

      final result = await platform.sendMessage(
        id: 'face-big',
        receiver: 'peer-a',
        groupID: '',
      );

      expect(result.code, 8001);
      expect(result.desc, contains('Face message too large'));
      expect(provider.sentTexts, isEmpty,
          reason: 'a split envelope must never reach the wire');
    });

    test('a face message within one Tox message is sent', () async {
      final provider = _RecordingProvider();
      ChatMessageProviderRegistry.provider = provider;
      final message = _faceMessage('face-small', 'smile');
      TencentCloudChat.instance.dataInstance.messageData.messageListMap = {
        'peer-a': [message],
      };

      await platform.sendMessage(
        id: 'face-small',
        receiver: 'peer-a',
        groupID: '',
      );

      expect(provider.sentTexts, hasLength(1));
      expect(provider.sentTexts.single, startsWith('__face__:'));
    });
  });
}
