import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/navigation/active_conversation_binding.dart';
import 'package:toxee/sdk_fake/uikit_data_facade.dart';

/// Pins the BIND half of the compact-shell active-conversation contract
/// (iPhone, 2026-08-23): every non-row way into a chat must leave the app in
/// the same state as a conversation-row tap — active peer set (unread zeroed,
/// conversation marked viewed) and `currentConversation` bound (notification
/// suppression for the open chat).
final String _peer = 'A' * 64;

class _StubService extends FfiChatService {
  _StubService() : super();

  final List<String?> activePeers = <String?>[];

  @override
  void setActivePeer(String? conversationId) {
    activePeers.add(conversationId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // V2TimConversation construction reaches into the SDK native binding; point
  // it at the tim2tox lib the stub's super() loads (same as the notification
  // suppression test).
  setNativeLibraryName('tim2tox_ffi');
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());
  late _StubService service;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async => null);
    service = _StubService();
    UikitDataFacade.currentConversation = null;
  });

  tearDown(() {
    UikitDataFacade.currentConversation = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null);
  });

  test('a peer with no conversation row resolves to a minimal C2C target', () {
    final target = resolveConversationTarget(peerId: _peer);
    expect(target.conversationID, 'c2c_$_peer');
    expect(target.type, ConversationType.V2TIM_C2C);
    expect(target.userID, _peer);
    expect(target.groupID, isNull);
    expect(target.unreadCount, 0);
  });

  test('a group target resolves to the group conversation id', () {
    final target = resolveConversationTarget(groupId: 'tox_7');
    expect(target.conversationID, 'group_tox_7');
    expect(target.type, ConversationType.V2TIM_GROUP);
    expect(target.groupID, 'tox_7');
    expect(target.userID, isNull);
  });

  test('binding sets the active peer AND the current conversation', () {
    expect(UikitDataFacade.currentConversation, isNull);
    bindActiveConversation(service: service, peerId: _peer);
    expect(service.activePeers, ['c2c_$_peer']);
    expect(UikitDataFacade.currentConversation?.conversationID, 'c2c_$_peer');

    bindActiveConversation(service: service, groupId: 'tox_7');
    expect(service.activePeers.last, 'group_tox_7');
    expect(UikitDataFacade.currentConversation?.conversationID, 'group_tox_7');
  });
}
