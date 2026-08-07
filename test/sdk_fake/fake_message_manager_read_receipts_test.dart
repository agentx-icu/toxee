import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';

class _RecordingFfiChatService implements FfiChatService {
  final List<({String peerId, String msgID, String? groupID})> calls =
      <({String peerId, String msgID, String? groupID})>[];

  @override
  Future<void> markMessageAsRead(
    String peerId,
    String msgID, {
    String? groupID,
  }) async {
    calls.add((peerId: peerId, msgID: msgID, groupID: groupID));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'routes C2C receipts to userID in order and leaves groupID null',
    () async {
      final bus = FakeEventBus();
      final ffi = _RecordingFfiChatService();
      final manager = FakeMessageManager(bus, ffi);

      addTearDown(manager.dispose);
      addTearDown(bus.dispose);

      await manager.sendMessageReadReceipts(const [
        'msg-1',
        'msg-2',
      ], userID: 'user-123');

      expect(ffi.calls, <({String peerId, String msgID, String? groupID})>[
        (peerId: 'user-123', msgID: 'msg-1', groupID: null),
        (peerId: 'user-123', msgID: 'msg-2', groupID: null),
      ]);
    },
  );

  test(
    'routes group receipts to groupID in order and repeats it as groupID',
    () async {
      final bus = FakeEventBus();
      final ffi = _RecordingFfiChatService();
      final manager = FakeMessageManager(bus, ffi);

      addTearDown(manager.dispose);
      addTearDown(bus.dispose);

      await manager.sendMessageReadReceipts(const [
        'msg-a',
        'msg-b',
      ], groupID: 'group-456');

      expect(ffi.calls, <({String peerId, String msgID, String? groupID})>[
        (peerId: 'group-456', msgID: 'msg-a', groupID: 'group-456'),
        (peerId: 'group-456', msgID: 'msg-b', groupID: 'group-456'),
      ]);
    },
  );

  test('prefers groupID when both routing IDs are provided', () async {
    final bus = FakeEventBus();
    final ffi = _RecordingFfiChatService();
    final manager = FakeMessageManager(bus, ffi);

    addTearDown(manager.dispose);
    addTearDown(bus.dispose);

    await manager.sendMessageReadReceipts(
      const ['msg-mixed'],
      userID: 'user-ignored',
      groupID: 'group-preferred',
    );

    expect(ffi.calls, <({String peerId, String msgID, String? groupID})>[
      (
        peerId: 'group-preferred',
        msgID: 'msg-mixed',
        groupID: 'group-preferred',
      ),
    ]);
  });

  test('throws before calling FFI when both routing IDs are missing', () async {
    final bus = FakeEventBus();
    final ffi = _RecordingFfiChatService();
    final manager = FakeMessageManager(bus, ffi);

    addTearDown(manager.dispose);
    addTearDown(bus.dispose);

    await expectLater(
      manager.sendMessageReadReceipts(const ['msg-1', 'msg-2']),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Either userID or groupID must be provided'),
        ),
      ),
    );

    expect(ffi.calls, isEmpty);
  });
}
