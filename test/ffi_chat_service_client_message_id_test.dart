import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';
import 'package:tim2tox_dart/utils/offline_message_queue_persistence.dart';

class _OfflineFfiChatService extends FfiChatService {
  _OfflineFfiChatService({
    required MessageHistoryPersistence historyPersistence,
    required OfflineMessageQueuePersistence queuePersistence,
  }) : super(
         messageHistoryPersistence: historyPersistence,
         offlineMessageQueuePersistence: queuePersistence,
       );

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async => const [];
}

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('FfiChatService client message identity', () {
    late Directory tempRoot;
    late _OfflineFfiChatService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'ffi_client_message_id_test_',
      );
      service = _OfflineFfiChatService(
        historyPersistence: MessageHistoryPersistence(
          historyDirectory: '${tempRoot.path}/history',
        ),
        queuePersistence: OfflineMessageQueuePersistence(
          queueFilePath: '${tempRoot.path}/offline_queue.json',
        ),
      );
    });

    tearDown(() async {
      await service.dispose();
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test(
      'offline C2C sends return distinct pending messages with caller IDs',
      () async {
        const peerId =
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
        const text = 'same text';
        const firstId = 'client-c2c-1';
        const secondId = 'client-c2c-2';
        const cloudCustomData = '{"messageReply":{"messageID":"quoted"}}';
        final streamedMessages = service.messages.take(2).toList();

        final first = await service.sendTextWithResult(
          peerId,
          text,
          cloudCustomData: cloudCustomData,
          clientMessageID: firstId,
        );
        final second = await service.sendTextWithResult(
          peerId,
          text,
          clientMessageID: secondId,
        );

        final history = service.getHistory(peerId);
        final queue = service.offlineMessageQueuePersistence.getMessages(
          peerId,
        );
        final emitted = await streamedMessages;

        expect(history, hasLength(2));
        expect(queue, hasLength(2));
        expect(history.map((message) => message.msgID), [firstId, secondId]);
        expect(queue.map((item) => item.msgID), [firstId, secondId]);
        expect(queue[0].cloudCustomData, cloudCustomData);
        expect(queue[1].cloudCustomData, isNull);
        expect(first.msgID, firstId);
        expect(second.msgID, secondId);
        expect(first.isPending, isTrue);
        expect(second.isPending, isTrue);
        expect(first.cloudCustomData, cloudCustomData);
        expect(identical(first, history[0]), isTrue);
        expect(identical(second, history[1]), isTrue);
        expect(identical(first, emitted[0]), isTrue);
        expect(identical(second, emitted[1]), isTrue);

        final reloadedQueue = await OfflineMessageQueuePersistence(
          queueFilePath: '${tempRoot.path}/offline_queue.json',
        ).loadQueue();
        expect(reloadedQueue[peerId]?[0].cloudCustomData, cloudCustomData);
      },
      skip: skipReason,
    );

    test(
      'disconnected group sends return pending messages and preserve generated fallback IDs',
      () async {
        const groupId = 'client-message-id-group';
        const explicitId = 'client-group-1';
        const cloudCustomData = '{"messageReply":{"messageID":"group-quoted"}}';
        service.debugSetConnected(false);
        service.armNextSendCloudCustomData(cloudCustomData);
        final streamedMessages = service.messages.take(2).toList();

        final explicit = await service.sendGroupTextWithResult(
          groupId,
          'group text',
          clientMessageID: explicitId,
        );
        final generated = await service.sendGroupTextWithResult(
          groupId,
          'group text',
          clientMessageID: '',
        );

        final history = service.getHistory(groupId);
        final queue = service.offlineMessageQueuePersistence.getMessages(
          'group:$groupId',
        );
        final emitted = await streamedMessages;

        expect(history, hasLength(2));
        expect(queue, hasLength(2));
        expect(explicit.msgID, explicitId);
        expect(generated.msgID, isNotEmpty);
        expect(generated.msgID, isNot(explicitId));
        expect(queue[0].msgID, explicit.msgID);
        expect(queue[1].msgID, generated.msgID);
        expect(queue[0].cloudCustomData, cloudCustomData);
        expect(queue[1].cloudCustomData, isNull);
        expect(explicit.isPending, isTrue);
        expect(generated.isPending, isTrue);
        expect(explicit.cloudCustomData, cloudCustomData);
        expect(identical(explicit, history[0]), isTrue);
        expect(identical(generated, history[1]), isTrue);
        expect(identical(explicit, emitted[0]), isTrue);
        expect(identical(generated, emitted[1]), isTrue);

        final reloadedQueue = await OfflineMessageQueuePersistence(
          queueFilePath: '${tempRoot.path}/offline_queue.json',
        ).loadQueue();
        expect(
          reloadedQueue['group:$groupId']?[0].cloudCustomData,
          cloudCustomData,
        );
      },
      skip: skipReason,
    );

    test(
      'legacy queue JSON without cloudCustomData remains readable',
      () async {
        final queueFile = File('${tempRoot.path}/legacy_queue.json');
        await queueFile.writeAsString(
          '{"peer":[{"kind":"text","text":"legacy","filePath":null,'
          '"fileName":null,"timestamp":"2026-01-01T00:00:00.000Z",'
          '"msgID":"legacy-id"}]}',
        );

        final loaded = await OfflineMessageQueuePersistence(
          queueFilePath: queueFile.path,
        ).loadQueue();

        expect(loaded['peer'], hasLength(1));
        expect(loaded['peer']?.single.cloudCustomData, isNull);
      },
    );
  });
}
