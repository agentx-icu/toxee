import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/interfaces/draft_preferences_service.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/sdk_fake/fake_provider.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FakeChatDataProvider? provider;

  setUp(() async {
    FakeUIKit.instance.dispose();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
  });

  tearDown(() {
    provider?.dispose();
    FakeUIKit.instance.dispose();
  });

  test('cold conversation mapping restores persisted draft preview', () async {
    const conversationID =
        'c2c_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final ffi = _DraftRestartFfi(
      conversationID: conversationID,
      draft: const ConversationDraft(
        conversationID: conversationID,
        text: 'restart preview',
        timestamp: 321,
      ),
    );
    final manager = FakeConversationManager(
      FakeUIKit.instance.eventBusInstance,
      ffi,
    );
    await manager.start();
    FakeUIKit.instance.conversationManager = manager;
    final dataProvider = FakeChatDataProvider(ffiService: ffi);
    provider = dataProvider;

    final conversations = await dataProvider.getInitialConversations();
    final restored = conversations.singleWhere(
      (conversation) => conversation.conversationID == conversationID,
    );

    expect(restored.draftText, 'restart preview');
    expect(restored.draftTimestamp, 321);
    expect(ffi.loadedConversationIDs, contains(conversationID));

    // A live metadata refresh must merge with the cold row instead of doing a
    // second persistence read that could race a later explicit draft clear.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final coldDraftLoadCount = ffi.loadedConversationIDs.length;
    final refreshedFuture = dataProvider.conversationStream.firstWhere(
      (list) => list.any(
        (conversation) =>
            conversation.conversationID == conversationID &&
            conversation.showName == 'Live Refresh',
      ),
    );
    FakeUIKit.instance.eventBusInstance.emit(
      FakeIM.topicConversation,
      FakeConversation(
        conversationID: conversationID,
        title: 'Live Refresh',
        faceUrl: null,
        unreadCount: 1,
      ),
    );
    final refreshed = (await refreshedFuture).singleWhere(
      (conversation) => conversation.conversationID == conversationID,
    );

    expect(refreshed.draftText, 'restart preview');
    expect(refreshed.draftTimestamp, 321);
    expect(ffi.loadedConversationIDs, hasLength(coldDraftLoadCount));
  });
}

class _DraftRestartFfi implements FfiChatService {
  _DraftRestartFfi({required this.conversationID, required this.draft});

  final String conversationID;
  final ConversationDraft draft;
  final List<String> loadedConversationIDs = <String>[];

  String get _friendID => conversationID.substring(4);

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async =>
      <({String userId, String nickName, String status, bool online})>[
        (
          userId: _friendID,
          nickName: 'Restart Friend',
          status: '',
          online: false,
        ),
      ];

  @override
  Future<List<({String userId, String wording})>>
  getFriendApplications() async => const [];

  @override
  int getUnreadOf(String peerId) => 0;

  @override
  Set<String> get knownGroups => const <String>{};

  @override
  Map<String, ChatMessage> get lastMessages => const <String, ChatMessage>{};

  @override
  List<ChatMessage> getHistory(String peerId) => const <ChatMessage>[];

  @override
  Future<ConversationDraft?> loadConversationDraft(
    String requestedConversationID,
  ) async {
    loadedConversationIDs.add(requestedConversationID);
    return requestedConversationID == conversationID ? draft : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
