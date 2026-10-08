import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/c2c_send_guard.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';

const String _self =
    '1111111111111111111111111111111111111111111111111111111111111111';
const String _friend =
    '2222222222222222222222222222222222222222222222222222222222222222';
const String _stranger =
    '3333333333333333333333333333333333333333333333333333333333333333';

/// Lists [_friend] (offline) and records every C2C text handed to it.
class _FriendListFfi implements FfiChatService {
  final List<String> sentTo = <String>[];

  @override
  bool isSelfPeer(String peerId) => peerId.toUpperCase() == _self;

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async => const [
    (userId: _friend, nickName: 'Bob', status: '', online: false),
  ];

  @override
  Future<ChatMessage> sendTextWithResult(
    String peerId,
    String text, {
    String? cloudCustomData,
    String? clientMessageID,
  }) async {
    sentTo.add(peerId);
    return ChatMessage(
      text: text,
      fromUserId: _self,
      isSelf: true,
      timestamp: DateTime(2026, 10, 8),
      isPending: true,
      msgID: 'msg-${sentTo.length}',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A C2C text to someone who is not (or no longer) a friend would sit in
/// Tim2Tox's durable queue forever: it is refused before it is queued.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeEventBus bus;
  late _FriendListFfi ffi;
  late FakeMessageManager manager;

  setUp(() {
    // A send records the friend's last activity in preferences.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    bus = FakeEventBus();
    ffi = _FriendListFfi();
    manager = FakeMessageManager(bus, ffi);
  });

  tearDown(() {
    manager.dispose();
    bus.dispose();
  });

  test('a non-friend is refused and nothing reaches the transport', () async {
    await expectLater(
      manager.sendText('c2c_$_stranger', 'CQ'),
      throwsA(
        isA<NotFriendSendException>().having(
          (e) => e.toString(),
          'text',
          contains('not in your friend list'),
        ),
      ),
    );
    expect(ffi.sentTo, isEmpty);
  });

  test('an offline friend is sent to', () async {
    await manager.sendText('c2c_${_friend.toLowerCase()}', 'CQ');
    expect(ffi.sentTo, [_friend.toLowerCase()]);
  });

  test('the note to self needs no friend', () async {
    await manager.sendText('c2c_$_self', 'note');
    expect(ffi.sentTo, [_self]);
  });

  test('a failure notice to a non-friend is dropped, not thrown', () async {
    await sendFailureNotice(manager, 'c2c_$_stranger', 'offline');
    await sendFailureNotice(null, 'c2c_$_friend', 'offline');
    expect(ffi.sentTo, isEmpty);
  });
}
