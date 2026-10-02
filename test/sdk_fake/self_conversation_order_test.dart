// An untouched note-to-self conversation has no activity: it must not sort
// above conversations that do. The provider used to give every message-less
// row the current time as its UIKit orderkey, so the empty notebook outranked
// populated, unpinned chats in the final UIKit list (review finding).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tim2tox_dart/interfaces/draft_preferences_service.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';
import 'package:toxee/sdk_fake/fake_provider.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';
import 'package:toxee/util/prefs.dart';

const _selfKey =
    'ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB';
const _friendKey =
    'CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCD';

class _Service implements FfiChatService {
  final ChatMessage _bobNote = ChatMessage(
    text: 'recent note from Bob',
    fromUserId: _friendKey,
    isSelf: false,
    timestamp: DateTime.utc(2025),
    groupId: null,
    msgID: 'bob_note',
  );

  @override
  String get selfId => 'FlutterUIKitClient';

  @override
  String? get selfPublicKey => _selfKey;

  @override
  bool isSelfPeer(String id) =>
      id.replaceFirst('c2c_', '').toUpperCase() == _selfKey;

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
      getFriendList() async =>
          [(userId: _friendKey, nickName: 'Bob', status: '', online: false)];

  @override
  Future<List<({String userId, String wording})>>
      getFriendApplications() async => const [];

  @override
  Set<String> get knownGroups => const <String>{};

  @override
  int getUnreadOf(String id) => 0;

  @override
  Map<String, ChatMessage> get lastMessages => {_friendKey: _bobNote};

  @override
  List<ChatMessage> getHistory(String id) =>
      id == _friendKey ? [_bobNote] : const [];

  @override
  Future<ConversationDraft?> loadConversationDraft(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an empty self conversation does not outrank a chat with activity',
      () async {
    FakeUIKit.instance.dispose();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    await Prefs.setNickname('Ann');
    await Prefs.setFriendActivity(_friendKey, DateTime.utc(2025));
    await Prefs.setFriendListSortingMode('activity');
    final service = _Service();
    FakeUIKit.instance.conversationManager =
        FakeConversationManager(FakeUIKit.instance.eventBusInstance, service);
    final provider = FakeChatDataProvider(ffiService: service);
    addTearDown(() {
      provider.dispose();
      FakeUIKit.instance.dispose();
    });

    final mapped = await provider.getInitialConversations();
    final self = mapped.singleWhere((c) => c.conversationID == 'c2c_$_selfKey');
    expect(self.showName, 'Ann');
    expect(self.orderkey ?? 0, 0, reason: 'no activity, no "now" orderkey');

    final data = TencentCloudChat.instance.dataInstance.conversation;
    data.buildConversationList(mapped, 'self order test');
    expect(data.conversationList.first.conversationID, 'c2c_$_friendKey');
  });
}
