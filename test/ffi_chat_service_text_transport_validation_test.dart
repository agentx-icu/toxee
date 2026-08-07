import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';
import 'package:tim2tox_dart/utils/offline_message_queue_persistence.dart';

class _TextTransportService extends FfiChatService {
  _TextTransportService({
    required MessageHistoryPersistence historyPersistence,
    required OfflineMessageQueuePersistence queuePersistence,
    required List<
      ({String userId, String nickName, String status, bool online})
    >
    friends,
  }) : _friends = friends,
       super(
         messageHistoryPersistence: historyPersistence,
         offlineMessageQueuePersistence: queuePersistence,
       );

  final List<({String userId, String nickName, String status, bool online})>
  _friends;

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async => _friends;

  List<ChatMessage> historyFor(String id) => getHistory(id);

  List<OfflineMessageItem> queueFor(String id) =>
      offlineMessageQueuePersistence.getMessages(id);
}

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

String _asciiPayload(int length) => 'a' * length;

const int _qtoxFragmentBytes = 1322;

String _emojiBoundaryPayload({required int asciiPrefixBytes}) =>
    '${'a' * asciiPrefixBytes}🙂';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('FfiChatService text transport validation', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'ffi_chat_service_text_transport_validation_test_',
      );
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    _TextTransportService service({
      required List<
        ({String userId, String nickName, String status, bool online})
      >
      friends,
    }) {
      return _TextTransportService(
        historyPersistence: MessageHistoryPersistence(
          historyDirectory: '${tempRoot.path}/history',
        ),
        queuePersistence: OfflineMessageQueuePersistence(
          queueFilePath: '${tempRoot.path}/offline_queue.json',
        ),
        friends: friends,
      );
    }

    test(
      'C2C online long text reaches native transport without false success',
      () async {
        const peerId =
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
        final chat = service(
          friends: const [
            (userId: peerId, nickName: 'peer', status: '', online: true),
          ],
        );
        addTearDown(() async => chat.dispose());

        final emitted = <ChatMessage>[];
        final sub = chat.messages.listen(emitted.add);
        addTearDown(sub.cancel);

        final payload = _asciiPayload(_qtoxFragmentBytes + 1);
        expect(utf8.encode(payload).length, _qtoxFragmentBytes + 1);

        await expectLater(
          chat.sendTextWithResult(peerId, payload),
          throwsA(isA<StateError>()),
        );

        // Native return 0 must not create a logical send even though the
        // payload itself is valid and is fragmented below this API.
        expect(chat.historyFor(peerId), isEmpty);
        expect(chat.queueFor(peerId), isEmpty);
        expect(emitted, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'C2C offline long text stays one logical pending message',
      () async {
        const peerId =
            'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
        final chat = service(
          friends: const [
            (userId: peerId, nickName: 'peer', status: '', online: false),
          ],
        );
        addTearDown(() async => chat.dispose());

        final emitted = <ChatMessage>[];
        final sub = chat.messages.listen(emitted.add);
        addTearDown(sub.cancel);

        final payload = _asciiPayload(_qtoxFragmentBytes + 1);
        expect(utf8.encode(payload).length, _qtoxFragmentBytes + 1);

        final pending = await chat.sendTextWithResult(peerId, payload);
        await Future<void>.delayed(Duration.zero);
        final history = chat.historyFor(peerId);
        final queue = chat.queueFor(peerId);

        expect(pending.text, payload);
        expect(pending.isPending, isTrue);
        expect(history, hasLength(1));
        expect(queue, hasLength(1));
        expect(emitted, hasLength(1));
        expect(history.single.msgID, pending.msgID);
        expect(queue.single.msgID, pending.msgID);
        expect(queue.single.text, payload);
        expect(emitted.single.msgID, pending.msgID);
      },
      skip: skipReason,
    );

    test(
      'group online long text reaches native transport without false success',
      () async {
        const groupId = 'validation-group-online';
        final chat = service(friends: const []);
        addTearDown(() async => chat.dispose());
        chat.debugSetConnected(true);

        final emitted = <ChatMessage>[];
        final sub = chat.messages.listen(emitted.add);
        addTearDown(sub.cancel);

        final payload = _asciiPayload(_qtoxFragmentBytes + 1);
        expect(utf8.encode(payload).length, _qtoxFragmentBytes + 1);

        await expectLater(
          chat.sendGroupTextWithResult(groupId, payload),
          throwsA(isA<StateError>()),
        );

        // Native return 0 must not create a logical send even though the
        // payload itself is valid and is fragmented below this API.
        expect(chat.historyFor(groupId), isEmpty);
        expect(chat.queueFor('group:$groupId'), isEmpty);
        expect(emitted, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'group offline long text stays one logical pending message',
      () async {
        const groupId = 'validation-group-offline';
        final chat = service(friends: const []);
        addTearDown(() async => chat.dispose());
        chat.debugSetConnected(false);

        final emitted = <ChatMessage>[];
        final sub = chat.messages.listen(emitted.add);
        addTearDown(sub.cancel);

        final payload = _asciiPayload(_qtoxFragmentBytes + 1);
        expect(utf8.encode(payload).length, _qtoxFragmentBytes + 1);

        final pending = await chat.sendGroupTextWithResult(groupId, payload);
        await Future<void>.delayed(Duration.zero);
        final history = chat.historyFor(groupId);
        final queue = chat.queueFor('group:$groupId');

        expect(pending.text, payload);
        expect(pending.isPending, isTrue);
        expect(history, hasLength(1));
        expect(queue, hasLength(1));
        expect(emitted, hasLength(1));
        expect(history.single.msgID, pending.msgID);
        expect(queue.single.msgID, pending.msgID);
        expect(queue.single.text, payload);
        expect(emitted.single.msgID, pending.msgID);
      },
      skip: skipReason,
    );

    test(
      'emoji crossing the 1322-byte boundary reaches native transport',
      () async {
        const peerId =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        final chat = service(
          friends: const [
            (userId: peerId, nickName: 'peer', status: '', online: true),
          ],
        );
        addTearDown(() async => chat.dispose());

        final emitted = <ChatMessage>[];
        final sub = chat.messages.listen(emitted.add);
        addTearDown(sub.cancel);

        final payload = _emojiBoundaryPayload(
          asciiPrefixBytes: _qtoxFragmentBytes - 1,
        );
        expect(payload.length, _qtoxFragmentBytes + 1);
        expect(utf8.encode(payload).length, _qtoxFragmentBytes + 3);
        expect(
          utf8.encode(payload.substring(_qtoxFragmentBytes - 1)).length,
          4,
        );

        await expectLater(
          chat.sendTextWithResult(peerId, payload),
          throwsA(isA<StateError>()),
        );

        expect(chat.historyFor(peerId), isEmpty);
        expect(chat.queueFor(peerId), isEmpty);
        expect(emitted, isEmpty);
      },
      skip: skipReason,
    );

    test('rejects embedded NUL text without side effects', () async {
      const peerId =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final chat = service(
        friends: const [
          (userId: peerId, nickName: 'peer', status: '', online: true),
        ],
      );
      addTearDown(() async => chat.dispose());

      final emitted = <ChatMessage>[];
      final sub = chat.messages.listen(emitted.add);
      addTearDown(sub.cancel);

      const payload = 'nul\u0000byte';
      expect(payload.codeUnits, contains(0));

      await expectLater(
        chat.sendTextWithResult(peerId, payload),
        throwsA(isA<ArgumentError>()),
      );

      expect(chat.historyFor(peerId), isEmpty);
      expect(chat.queueFor(peerId), isEmpty);
      expect(emitted, isEmpty);
    }, skip: skipReason);

    test(
      'surfaces native return 0 for C2C and group without false success',
      () async {
        const peerId =
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
        const groupId = 'validation-group-native-zero';

        final c2c = service(
          friends: const [
            (userId: peerId, nickName: 'peer', status: '', online: true),
          ],
        );
        addTearDown(() async => c2c.dispose());
        final c2cEmitted = <ChatMessage>[];
        final c2cSub = c2c.messages.listen(c2cEmitted.add);
        addTearDown(c2cSub.cancel);

        await expectLater(
          c2c.sendTextWithResult(peerId, 'native-zero'),
          throwsA(isA<StateError>()),
        );

        expect(c2c.historyFor(peerId), isEmpty);
        expect(c2c.queueFor(peerId), isEmpty);
        expect(c2cEmitted, isEmpty);

        final group = service(friends: const []);
        addTearDown(() async => group.dispose());
        group.debugSetConnected(true);
        final groupEmitted = <ChatMessage>[];
        final groupSub = group.messages.listen(groupEmitted.add);
        addTearDown(groupSub.cancel);

        await expectLater(
          group.sendGroupTextWithResult(groupId, 'native-zero'),
          throwsA(isA<StateError>()),
        );

        expect(group.historyFor(groupId), isEmpty);
        expect(group.queueFor('group:$groupId'), isEmpty);
        expect(groupEmitted, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'keeps C2C queued text pending when retry gets native return 0',
      () async {
        const peerId =
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
        final chat = service(
          friends: const [
            (userId: peerId, nickName: 'peer', status: '', online: false),
          ],
        );
        addTearDown(() async => chat.dispose());

        final pending = await chat.sendTextWithResult(
          peerId,
          'retry-native-zero',
          clientMessageID: 'retry-c2c-id',
        );
        expect(pending.isPending, isTrue);
        expect(chat.queueFor(peerId), hasLength(1));

        await chat.retryPendingC2cMessages(peerId);

        expect(chat.queueFor(peerId), hasLength(1));
        expect(chat.historyFor(peerId), hasLength(1));
        expect(chat.historyFor(peerId).single.isPending, isTrue);
      },
      skip: skipReason,
    );

    test(
      'keeps group queued text pending when retry gets native return 0',
      () async {
        const groupId = 'validation-group-retry-native-zero';
        final chat = service(friends: const []);
        addTearDown(() async => chat.dispose());
        chat.debugSetConnected(false);

        final pending = await chat.sendGroupTextWithResult(
          groupId,
          'retry-native-zero',
          clientMessageID: 'retry-group-id',
        );
        expect(pending.isPending, isTrue);
        expect(chat.queueFor('group:$groupId'), hasLength(1));

        chat.debugSetConnected(true);
        await chat.retryPendingGroupMessages(groupId);

        expect(chat.queueFor('group:$groupId'), hasLength(1));
        expect(chat.historyFor(groupId), hasLength(1));
        expect(chat.historyFor(groupId).single.isPending, isTrue);
      },
      skip: skipReason,
    );
  });
}
