// The toxee conversation producer (FakeChatDataProvider._mapConv) must emit
// an explicit groupAtInfoList for every group row: UIKit merges updates as
// `incoming.groupAtInfoList ?? existing.groupAtInfoList`, so the old null
// (whenever nothing was unread) kept "[@me]" on the row until restart. The
// entry it does emit must point at the mentioning row, not the placeholder
// seq '0' that could never be resolved to a message.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tim2tox_dart/interfaces/draft_preferences_service.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform_converters.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/sdk_fake/fake_provider.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';
import 'package:toxee/util/prefs.dart';

const _gid = 'tox_mention_1';
const _convId = 'group_$_gid';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FakeChatDataProvider? provider;

  setUp(() async {
    await FakeUIKit.instance.dispose();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    await Prefs.setCurrentAccountToxId('group_at_info_test_account');
  });

  tearDown(() {
    provider?.dispose();
    provider = null;
    FakeUIKit.instance.dispose();
  });

  Future<V2TimConversation> emitAndMap(
    FakeChatDataProvider dataProvider, {
    required String title,
    required int unread,
  }) async {
    final mapped = dataProvider.conversationStream.firstWhere(
      (list) => list.any((c) => c.conversationID == _convId && c.showName == title),
    );
    FakeUIKit.instance.eventBusInstance.emit(
      FakeIM.topicConversation,
      FakeConversation(
        conversationID: _convId,
        title: title,
        faceUrl: null,
        unreadCount: unread,
        isGroup: true,
      ),
    );
    return (await mapped).singleWhere((c) => c.conversationID == _convId);
  }

  test('marker points at the mention row, then clears to an empty list', () async {
    final ffi = _MentionFfi();
    final dataProvider = FakeChatDataProvider(ffiService: ffi);
    provider = dataProvider;

    final unread = await emitAndMap(dataProvider, title: 'unread', unread: 2);
    final info = unread.groupAtInfoList!.single!;
    expect(info.atType, 1);
    expect(
      chatMessagesForGroupAtSeqs(ffi.rows, [int.parse(info.seq)])
          .single
          .msgID,
      'm_mention',
    );

    ffi.read = true; // the chat was opened
    final read = await emitAndMap(dataProvider, title: 'read', unread: 0);
    expect(read.groupAtInfoList, isNotNull,
        reason: 'null means "unchanged" to the UIKit merge');
    expect(read.groupAtInfoList, isEmpty);
  });
}

class _MentionFfi implements FfiChatService {
  bool read = false;

  final List<ChatMessage> rows = [
    ChatMessage(
      text: '@Ann look',
      fromUserId: 'PEER',
      isSelf: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      groupId: _gid,
      msgID: 'm_mention',
    ),
    ChatMessage(
      text: 'newest',
      fromUserId: 'PEER',
      isSelf: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000001000),
      groupId: _gid,
      msgID: 'm_newest',
    ),
  ];

  @override
  bool hasUnreadMention(String groupId) => !read;

  @override
  int getUnreadOf(String peerId) => read ? 0 : 2;

  @override
  List<ChatMessage> getHistory(String peerId) =>
      peerId == _gid ? rows : const <ChatMessage>[];

  @override
  List<ChatMessage> unreadMentionRows(String groupId) => read
      ? const <ChatMessage>[]
      : rows.where((m) => m.text.contains('@Ann')).toList();

  @override
  Map<String, ChatMessage> get lastMessages => const <String, ChatMessage>{};

  @override
  Set<String> get knownGroups => const <String>{_gid};

  @override
  Future<ConversationDraft?> loadConversationDraft(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
