// Regression test for tim2tox FfiChatService.deleteMessages.
//
// S7 from the 2026-05-18 local-storage review: `deleteMessages` was matching
// by a reconstructed two-component ID `'${ts}_${fromUserId}'` while
// `_appendHistory` writes a three-component msgID
// `'${ts}_${sequence}_${from}'`. The format mismatch meant matches never
// succeeded — UIKit's "delete message" silently did nothing.
//
// This test seeds three messages with distinct msgIDs, asks `deleteMessages`
// to drop the middle one, and asserts both the in-memory history and the
// `MessageHistoryPersistence` cache reflect the deletion (so a subsequent
// read does not repopulate stale data).
//
// FFI dependency: `FfiChatService`'s constructor opens the tim2tox FFI
// library. The test is skipped when the library is not loadable in this
// environment (matches the pattern in account_export_roundtrip_test.dart).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('FfiChatService.deleteMessages', skip: skipReason, () {
    late Directory tempRoot;
    late MessageHistoryPersistence persistence;
    late FfiChatService service;

    const conversationId =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    setUp(() async {
      tempRoot = await Directory.systemTemp
          .createTemp('tim2tox_delete_messages_test_');
      persistence = MessageHistoryPersistence(
          historyDirectory: p.join(tempRoot.path, 'history'));
      service = FfiChatService(messageHistoryPersistence: persistence);
    });

    tearDown(() async {
      try {
        await tempRoot.delete(recursive: true);
      } catch (_) {}
    });

    test(
        'deletes message matched by stored msgID and updates persistence cache',
        () async {
      // Three messages with distinct three-component msgIDs, like
      // `_appendHistory` writes (timestamp_sequence_fromUserId).
      final now = DateTime.now();
      final messages = <ChatMessage>[
        ChatMessage(
          text: 'first',
          fromUserId: 'peer1',
          isSelf: false,
          timestamp: now,
          msgID: '${now.millisecondsSinceEpoch}_1_peer1',
        ),
        ChatMessage(
          text: 'second',
          fromUserId: 'peer1',
          isSelf: false,
          timestamp: now.add(const Duration(milliseconds: 10)),
          msgID:
              '${now.add(const Duration(milliseconds: 10)).millisecondsSinceEpoch}_2_peer1',
        ),
        ChatMessage(
          text: 'third',
          fromUserId: 'peer1',
          isSelf: false,
          timestamp: now.add(const Duration(milliseconds: 20)),
          msgID:
              '${now.add(const Duration(milliseconds: 20)).millisecondsSinceEpoch}_3_peer1',
        ),
      ];
      // Seed via appendHistory so both the service's internal map and the
      // persistence cache see the messages (matches the production write path).
      for (final msg in messages) {
        await persistence.appendHistory(conversationId, msg);
      }
      // Warm the service's `_historyById` view so it pulls from the
      // persistence cache (lazy sync on first access).
      expect(service.getHistory(conversationId).length, 3);

      // Delete the middle message by its stored msgID.
      final targetMsgID = messages[1].msgID!;
      final deleted = await service.deleteMessages([targetMsgID]);
      expect(deleted, 1,
          reason:
              'deleteMessages should match by msg.msgID, not the reconstructed two-component ID');

      // Service view (which reads from the persistence cache) must reflect
      // the deletion — this is the cache-staleness fix.
      final survivors = service.getHistory(conversationId);
      expect(survivors.map((m) => m.text), ['first', 'third']);

      // Persistence cache must also reflect it, so later reads from any
      // collaborator that touches the persistence directly stay consistent.
      final cacheSurvivors = persistence.getHistory(conversationId);
      expect(cacheSurvivors.map((m) => m.text), ['first', 'third']);
    });

    test('falls back to legacy two-component reconstruction when msgID is null',
        () async {
      // Pre-msgID record (no msgID set). Match should still succeed via the
      // legacy `${timestamp}_${fromUserId}` reconstruction.
      final ts = DateTime.now();
      final legacy = ChatMessage(
        text: 'legacy',
        fromUserId: 'peerLegacy',
        isSelf: false,
        timestamp: ts,
      );
      await persistence.appendHistory(conversationId, legacy);
      expect(service.getHistory(conversationId).length, 1);

      final legacyId = '${ts.millisecondsSinceEpoch}_peerLegacy';
      final deleted = await service.deleteMessages([legacyId]);
      expect(deleted, 1);
      expect(service.getHistory(conversationId), isEmpty);
    });

    test('returns 0 when no msgIDs match', () async {
      final ts = DateTime.now();
      await persistence.appendHistory(
        conversationId,
        ChatMessage(
          text: 'only',
          fromUserId: 'peer1',
          isSelf: false,
          timestamp: ts,
          msgID: '${ts.millisecondsSinceEpoch}_1_peer1',
        ),
      );
      final deleted = await service.deleteMessages(['no_such_msg_id']);
      expect(deleted, 0);
      expect(service.getHistory(conversationId).length, 1);
    });

    test('a rejected message deletion retains its row for retry', () async {
      final time = DateTime.now();
      for (final id in ['keep', 'delete']) {
        await persistence.appendHistory(
          conversationId,
          ChatMessage(
            text: id,
            fromUserId: conversationId,
            isSelf: false,
            timestamp: time,
            msgID: id,
          ),
        );
      }
      final historyDir = p.join(tempRoot.path, 'history');
      final obstruction = Directory(
        p.join(historyDir, '$conversationId.json.tmp'),
      );
      await obstruction.create();
      try {
        await expectLater(
          service.deleteMessages(['delete']),
          throwsA(isA<FileSystemException>()),
        );
        expect(service.getHistory(conversationId).map((row) => row.msgID),
            orderedEquals(['keep', 'delete']));
      } finally {
        await obstruction.delete();
      }
      expect(await service.deleteMessages(['delete']), 1);
      final reopened = MessageHistoryPersistence(historyDirectory: historyDir);
      addTearDown(reopened.dispose);
      expect(
        (await reopened.loadHistory(conversationId)).map((row) => row.msgID),
        orderedEquals(['keep']),
      );
    });

    for (final isGroup in [false, true]) {
      test('a refused ${isGroup ? 'group' : 'C2C'} history clear propagates',
          () async {
        await persistence.appendHistory(
          conversationId,
          ChatMessage(
            text: 'message still on disk',
            fromUserId: conversationId,
            isSelf: false,
            timestamp: DateTime.now(),
            msgID: 'retained',
            groupId: isGroup ? conversationId : null,
          ),
        );
        final historyDir = p.join(tempRoot.path, 'history');
        final archive = File(p.join(historyDir, '$conversationId.archive.jsonl'));
        await archive.writeAsString('archive');
        Future<void> clear() => isGroup
            ? service.clearGroupHistory(conversationId)
            : service.clearC2CHistory(conversationId);
        expect((await Process.run('chmod', ['500', historyDir])).exitCode, 0);
        try {
          await expectLater(clear(), throwsA(isA<FileSystemException>()));
          expect(await archive.exists(), isTrue);
        } finally {
          expect((await Process.run('chmod', ['700', historyDir])).exitCode, 0);
        }
        await clear();
        expect(service.getHistory(conversationId), isEmpty);
        expect(await archive.exists(), isFalse);
      }, skip: Platform.isWindows);
    }
  });
}
