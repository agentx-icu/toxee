import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/interfaces/draft_preferences_service.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/sdk_fake/fake_provider.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';
import 'package:toxee/util/prefs.dart';

/// A deleted friend / conversation leaves a tombstone in the provider so the
/// 5 s rebuild cannot resurrect it. Two product paths must lift it again:
/// an inbound message persisted by the binary-replacement hook (which is
/// silent on `FfiChatService.messages`), and the friend being re-added.
/// Windows real-UI `read_receipt_double_tick` on a reused pair: persistence
/// unread 1 while the sidebar entry stayed at 0 for good.
const _peer =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _conv = 'c2c_$_peer';

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

  Future<void> tombstone(FakeChatDataProvider p) async {
    final bus = FakeUIKit.instance.eventBusInstance;
    bus.emit(FakeIM.topicFriendDeleted, FakeFriendDeleted(userID: _peer));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // The periodic rebuild re-emits the friend: it must stay hidden.
    bus.emit(
      FakeIM.topicConversation,
      FakeConversation(
        conversationID: _conv,
        title: 'Peer',
        faceUrl: null,
        unreadCount: 1,
      ),
    );
    final leaked = await p.conversationStream
        .firstWhere((l) => l.any((c) => c.conversationID == _conv))
        .timeout(const Duration(milliseconds: 400), onTimeout: () => const []);
    expect(leaked, isEmpty, reason: 'tombstone must block the rebuild');
  }

  test('hook-persisted inbound lifts the tombstone with the persisted unread',
      () async {
    final ffi = _TombstoneFfi();
    final p = FakeChatDataProvider(ffiService: ffi);
    provider = p;
    await tombstone(p);

    ffi.unread = 1; // the row is already in persistence when the hook fires
    final restoredFuture = p.conversationStream.firstWhere(
      (l) => l.any((c) => c.conversationID == _conv && c.unreadCount == 1),
    );
    await p.noteInboundMessagePersisted(
      FakeMessage(
        msgID: 'msg_1',
        conversationID: _conv,
        fromUser: _peer,
        text: 'hello',
        timestampMs: 1000,
      ),
    );
    final restored = await restoredFuture.timeout(const Duration(seconds: 3));
    expect(restored.where((c) => c.conversationID == _conv), hasLength(1));
    expect(ffi.refreshedCacheFor, contains(_conv),
        reason: 'the hook bypassed _appendHistory: preview cache refreshed');
  });

  test('friend re-add lifts the tombstone for the periodic rebuild', () async {
    final ffi = _TombstoneFfi();
    final p = FakeChatDataProvider(ffiService: ffi);
    provider = p;
    await tombstone(p);

    final bus = FakeUIKit.instance.eventBusInstance;
    bus.emit(FakeIM.topicFriendAdded, FakeFriendAdded(userID: _peer));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final restoredFuture = p.conversationStream.firstWhere(
      (l) => l.any((c) => c.conversationID == _conv),
    );
    bus.emit(
      FakeIM.topicConversation,
      FakeConversation(
        conversationID: _conv,
        title: 'Peer',
        faceUrl: null,
        unreadCount: 0,
      ),
    );
    final restored = await restoredFuture.timeout(const Duration(seconds: 3));
    expect(restored.where((c) => c.conversationID == _conv), hasLength(1));
  });
}

class _TombstoneFfi implements FfiChatService {
  int unread = 0;
  final List<String> refreshedCacheFor = <String>[];

  @override
  String get selfId => 'SELF';

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async =>
      <({String userId, String nickName, String status, bool online})>[
        (userId: _peer, nickName: 'Peer', status: '', online: false),
      ];

  @override
  Future<List<({String userId, String wording})>>
  getFriendApplications() async => const [];

  @override
  int getUnreadOf(String peerId) => unread;

  @override
  Set<String> get knownGroups => const <String>{};

  @override
  Map<String, ChatMessage> get lastMessages => const <String, ChatMessage>{};

  @override
  List<ChatMessage> getHistory(String peerId) => const <ChatMessage>[];

  @override
  void refreshConversationCacheFromHistory(String conversationId) {
    refreshedCacheFor.add(conversationId);
  }

  @override
  Future<ConversationDraft?> loadConversationDraft(
    String requestedConversationID,
  ) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
