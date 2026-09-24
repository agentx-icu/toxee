// Deleted history must stay deleted, and history that is only queued must not
// be thrown away with the file that still holds it.
//
// Three defects from the 2026-09-22 data-safety review, all in
// `MessageHistoryPersistence` (shared Dart — desktop and mobile alike):
//
//   1. `clearHistory(keepArchive: true)` deleted the main file FIRST and then
//      swallowed a failed archive drain. The rows pushed out of the memory
//      window live in the main file until the archive accepts them, so that
//      lost them outright — nothing else drains `_pendingArchive` for a
//      conversation with no cached list.
//   2. Deleting a row that is in memory left its ARCHIVED copy behind (a crash
//      between the archive append and the main-file rewrite leaves the row in
//      both files), so once the delete tombstone cleared it came back.
//   3. `openSession(ownerKey: null)` kept the PREVIOUS session's owner, so the
//      next account's init — which runs before login can reveal its Tox ID —
//      read the previous account's owner-bound default directory.
//
// Targets the store directly (no FFI, no platform plugins), like
// `tim2tox_history_archive_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

const _peer = 'tox_peer';
const _ownerA =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _ownerB =
    'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

ChatMessage _row(int i) => ChatMessage(
      text: 'm$i',
      fromUserId: 'PEER',
      isSelf: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 1000),
      msgID: 'id_$i',
    );

File _mainFile(Directory dir) => File(p.join(dir.path, '$_peer.json'));
File _archiveFile(Directory dir) =>
    File(p.join(dir.path, '$_peer.archive.jsonl'));

/// Fills the window to exactly [_maxMessagesInMemory] rows and gets them on
/// disk, so a later overflow has a main file that still holds what it drops.
Future<void> _fillWindow(MessageHistoryPersistence store, int count) async {
  for (var i = 0; i < count; i++) {
    // Fire and forget, exactly as the product appends.
    // ignore: unawaited_futures
    store.appendHistory(_peer, _row(i));
  }
  await store.flushPendingSaves();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('t2t_history_safety_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('clearHistory(keepArchive: true) with an unwritable archive', () {
    test('keeps the main file, propagates, and still owes the write',
        () async {
      final store = MessageHistoryPersistence(historyDirectory: tempDir.path);
      await _fillWindow(store, 1000);
      expect(await _mainFile(tempDir).exists(), isTrue);

      // Block the archive: a directory where the append expects a file.
      await Directory(_archiveFile(tempDir).path).create();

      // Overflow: four rows leave memory for the archive, the immediate save
      // fails on the drain, so the main file still holds all 1000 rows.
      for (var i = 1000; i < 1004; i++) {
        // ignore: unawaited_futures
        store.appendHistory(_peer, _row(i));
      }
      await expectLater(store.flushPendingSaves(), throwsA(anything));
      final beforeClear = await _mainFile(tempDir).readAsString();
      expect(beforeClear, contains('"id_0"'),
          reason: 'the rows now queued for the archive are still in this file');

      // The delete of the last in-memory row. It must NOT delete the only
      // copy of the queued rows, and must not report success.
      await expectLater(
        store.clearHistory(_peer, keepArchive: true),
        throwsA(anything),
      );
      expect(await _mainFile(tempDir).exists(), isTrue,
          reason: 'the file holding the undrained rows must survive');
      expect(await _mainFile(tempDir).readAsString(), contains('"id_0"'));

      // The work is still owed — a flush cannot report everything durable.
      await expectLater(store.flushPendingSaves(), throwsA(anything));

      // Once the archive is writable, the same flush drains it.
      await Directory(_archiveFile(tempDir).path).delete();
      await store.flushPendingSaves();
      final archived = await _archiveFile(tempDir).readAsString();
      expect(archived, contains('"id_0"'));
      expect(archived, contains('"id_3"'));
      await store.dispose();
    });
  });

  group('deleting a row that exists in BOTH files', () {
    test('removeMessage also removes the archived copy', () async {
      final store = MessageHistoryPersistence(historyDirectory: tempDir.path);
      final row = _row(7);
      // appendHistory (not saveHistory): the row has to be IN MEMORY, which is
      // the case the archive sweep used to skip.
      await store.appendHistory(_peer, row);
      await store.flushPendingSaves();
      expect(store.getHistory(_peer).map((m) => m.msgID), <String>['id_7']);
      // The crash shape: the row was appended to the archive and the main-file
      // rewrite never landed, so it is in both.
      await _archiveFile(tempDir)
          .writeAsString('${jsonEncode(row.toJson())}\n', flush: true);

      expect(await store.removeMessage(_peer, 'id_7'), isTrue);
      await store.flushPendingSaves();
      await store.dispose();

      // The next launch: no tombstones, nothing cached — only the files.
      final reopened =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      expect(await reopened.loadArchivedHistory(_peer), isEmpty,
          reason: 'the archived copy of a deleted row must not come back');
      expect(await reopened.loadHistory(_peer), isEmpty);
      await reopened.dispose();
    });
  });

  group('openSession owner boundary', () {
    test('a session with no owner does not inherit the previous one',
        () async {
      final a = MessageHistoryPersistence(appSupportRootOverride: tempDir.path)
        ..openSession(ownerKey: _ownerA);
      await a.saveHistory(_peer, <ChatMessage>[_row(1)]);
      await a.dispose();

      // Account B's service init: the store is reused / rebuilt and opened
      // BEFORE login can answer getSelfToxId(), so the owner is unknown.
      await a.openSession();
      expect(await a.loadHistory(_peer), isEmpty,
          reason: 'an unknown owner must not read the previous owner\'s rows');
      await a.saveHistory(_peer, <ChatMessage>[_row(2)]);
      await a.flushPendingSaves();

      final ownedByA =
          File(p.join(tempDir.path, 'chat_history', '$_peer.json'));
      expect(await ownedByA.readAsString(), contains('"id_1"'));
      expect(await ownedByA.readAsString(), isNot(contains('"id_2"')),
          reason: 'the ownerless session must not write into A\'s directory');
      await a.dispose();

      // And once B's identity IS known, it gets its own directory.
      final b = MessageHistoryPersistence(appSupportRootOverride: tempDir.path)
        ..openSession(ownerKey: _ownerB);
      expect(await b.loadHistory(_peer), isEmpty);
      await b.dispose();
    });
  });
}
