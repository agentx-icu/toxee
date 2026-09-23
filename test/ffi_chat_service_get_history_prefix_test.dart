// FfiChatService.getHistory must read a `c2c_`-prefixed id from the same key
// the persistence layer uses, and must never move or clear that history.
//
// It used to cut any id over 64 chars to its first 64 before normalizing, so
// `c2c_<pk>` became `c2c_` + 60 hex chars. That normalized to a different key,
// read empty, and a "migration" branch then saved the real history under the
// wrong key and cleared the real conversation.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';
import 'package:tim2tox_dart/utils/offline_message_queue_persistence.dart';

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

  const pk = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const toxId = '${pk}0123456789ab';

  late Directory tempRoot;
  late MessageHistoryPersistence persistence;
  late FfiChatService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('ffi_get_history_prefix_');
    persistence =
        MessageHistoryPersistence(historyDirectory: '${tempRoot.path}/history');
    service = FfiChatService(
      messageHistoryPersistence: persistence,
      offlineMessageQueuePersistence: OfflineMessageQueuePersistence(
        queueFilePath: '${tempRoot.path}/offline_queue.json',
      ),
    );
    await persistence.saveHistory(pk, [
      ChatMessage(
        text: 'hello',
        fromUserId: pk,
        isSelf: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        msgID: 'm1',
      ),
    ]);
    // saveHistory writes the file; reads are served from the loaded cache.
    await persistence.loadHistory(pk);
  });

  tearDown(() async {
    await service.dispose();
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  for (final id in ['c2c_$pk', 'c2c_$toxId', toxId, pk]) {
    test('getHistory("${id.substring(0, 8)}…", ${id.length} chars) reads the '
        'conversation and leaves it in place', () async {
      expect(service.getHistory(id).map((m) => m.msgID), ['m1']);
      await persistence.flushPendingSaves();
      expect(persistence.getHistory(pk).map((m) => m.msgID), ['m1']);
      expect(
          persistence.getHistory(pk.substring(0, 60)), isEmpty,
          reason: 'nothing may be copied to a truncated key');
    }, skip: skipReason);
  }
}
