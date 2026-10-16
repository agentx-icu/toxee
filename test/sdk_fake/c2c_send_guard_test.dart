import 'dart:io';

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

/// Records every C2C text handed to it (the friend list is
/// [debugNativeFriendIds]).
/// The real send path (armed-value consumption, offline queue) with [_friend]
/// listed offline and no native instance.
class _OfflineQueueFfi extends FfiChatService {
  _OfflineQueueFfi(Directory root)
    : super(
        historyDirectory: '${root.path}/history',
        queueFilePath: '${root.path}/offline_queue.json',
      );

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async => const [
    (userId: _friend, nickName: 'Bob', status: '', online: false),
  ];
}

class _FriendListFfi implements FfiChatService {
  final List<String> sentTo = <String>[];

  @override
  bool isSelfPeer(String peerId) => peerId.toUpperCase() == _self;

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
    debugNativeFriendIds = (_) => const [_friend];
  });

  tearDown(() {
    debugNativeFriendIds = null;
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

  test('the guard runs synchronously: the refusal happens before any await',
      () {
    // A future-returning guard would let a second send re-arm the shared
    // reply slot between the platform's arm and the transport's consume.
    expect(
      () => requireC2cFriend(ffi, _stranger),
      throwsA(isA<NotFriendSendException>()),
    );
    expect(() => requireC2cFriend(ffi, _friend), returnsNormally);
    expect(() => requireC2cFriend(ffi, _self), returnsNormally);
  });

  test('ids match exactly as before: 76-char form, no case folding', () {
    debugNativeFriendIds = (_) => const ['${_friend}00000000ABCD'];
    expect(() => requireC2cFriend(ffi, _friend), returnsNormally);
    expect(() => requireC2cFriend(ffi, '${_friend}11112222EEEE'),
        returnsNormally);
    const mixed =
        'ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD';
    debugNativeFriendIds = (_) => const [mixed];
    expect(
      () => requireC2cFriend(ffi, mixed.toLowerCase()),
      throwsA(isA<NotFriendSendException>()),
      reason: 'sendTextWithResult compares case-sensitively; admitting a '
          'lowercase key would queue under an id reconnect never drains',
    );
  });

  test(
    'overlapping sends each persist their own armed quote',
    () async {
      final root = await Directory.systemTemp.createTemp('c2c_guard_race_');
      final real = _OfflineQueueFfi(root);
      final realManager = FakeMessageManager(bus, real);
      try {
        // What Tim2ToxSdkPlatform.sendMessage does per text: arm, then call
        // the provider (which reaches FakeMessageManager.sendText) without
        // the caller serialising the two sends.
        real.armNextSendCloudCustomData('{"quote":"A"}');
        final first = realManager.sendText('c2c_$_friend', 'first');
        real.armNextSendCloudCustomData('{"quote":"B"}');
        final second = realManager.sendText('c2c_$_friend', 'second');
        final ids = [(await first).messageID, (await second).messageID];

        final rows = {
          for (final m in real.getHistory(_friend)) m.msgID: m,
        };
        expect(rows[ids[0]]?.text, 'first');
        expect(rows[ids[0]]?.cloudCustomData, '{"quote":"A"}');
        expect(rows[ids[1]]?.text, 'second');
        expect(rows[ids[1]]?.cloudCustomData, '{"quote":"B"}');
      } finally {
        realManager.dispose();
        await real.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
