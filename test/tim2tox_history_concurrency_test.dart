// One concurrency model per conversation in MessageHistoryPersistence
// (Codex review 3, 2026-09-19): load, save, delete, archive and clear of a
// conversation run under one FIFO lock, every operation carries the
// epoch + generation it was called under, and dispose ends a session rather
// than the object. Each test pins one race or loss that review found.
//
// Targets MessageHistoryPersistence directly (no FFI, no platform plugins).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

const _peer = 'c2c_peer';
const _group = 'tox_9';

ChatMessage _row(String id, int sec, {List<String> alt = const []}) =>
    ChatMessage(
      text: 'm$id',
      fromUserId: 'A' * 64,
      isSelf: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000 + sec * 1000),
      msgID: id,
      altMsgIds: alt,
    );

ChatMessage _groupRow(int i) => ChatMessage(
      text: 'g$i',
      fromUserId: 'PEER',
      isSelf: false,
      groupId: _group,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 1000),
      msgID: 'id_$i',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('t2t_history_conc_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File mainFile(String id) => File(p.join(dir.path, '$id.json'));

  Future<List<String?>> reloadIds(String conv) async {
    final fresh = MessageHistoryPersistence(historyDirectory: dir.path);
    final rows = await fresh.loadHistory(conv);
    await fresh.dispose();
    return rows.map((m) => m.msgID).toList();
  }

  group('deletes are durable', () {
    test('removing the sole row persists; a restart does not bring it back',
        () async {
      final store = MessageHistoryPersistence(historyDirectory: dir.path);
      await store.saveHistory(_peer, [_row('only', 1)]);
      await store.loadHistory(_peer);

      expect(await store.removeMessage(_peer, 'only'), isTrue);
      await store.flushPendingSaves();

      expect(await reloadIds('peer'), isEmpty);
      final json = jsonDecode(await mainFile('peer').readAsString()) as Map;
      expect(json['messages'], isEmpty);
      await store.dispose();
    });

    test('a stale file is filtered by tombstones even when the cache is empty',
        () async {
      final store = MessageHistoryPersistence(historyDirectory: dir.path);
      await store.saveHistory(_peer, [_row('only', 1)]);
      await store.loadHistory(_peer);
      // Delete in memory only, as a caller whose save has not landed yet.
      final cached = store.getCachedList(_peer)!;
      final removed = List<ChatMessage>.from(cached);
      cached.clear();
      store.noteRemovedFromCache(_peer, removed);

      expect(await store.loadHistory(_peer), isEmpty);
      expect(store.getHistory(_peer), isEmpty);
      await store.flushPendingSaves();
      expect(await reloadIds('peer'), isEmpty);
      await store.dispose();
    });

    test('an empty list that is NOT a delete never overwrites a file',
        () async {
      final writer = MessageHistoryPersistence(historyDirectory: dir.path);
      await writer.saveHistory(_peer, [_row('a', 1)]);
      await writer.dispose();

      // A fresh store has not loaded the conversation: [] means "unknown".
      final other = MessageHistoryPersistence(historyDirectory: dir.path);
      other.ensureCachedList(_peer);
      await other.saveHistory(_peer, const []);
      expect(await reloadIds('peer'), ['a']);
      await other.dispose();
    });
  });

  test('reload merges cross-path copies that share only an alias (#5)',
      () async {
    const alias = 'gmid:tox_9|PEER|7';
    await mainFile('peer').writeAsString(jsonEncode({
      'conversationId': 'peer',
      'version': 2,
      'lastViewTimestamp': 0,
      'messages': [
        _row('poll_7', 1, alt: [alias]).toJson(),
        (_row('msg_native_7', 1, alt: [alias])).copyWith(isRead: true).toJson(),
      ],
    }));
    final store = MessageHistoryPersistence(historyDirectory: dir.path);
    final rows = await store.loadHistory(_peer);
    expect(rows, hasLength(1));
    final ids = {rows.single.msgID, ...rows.single.altMsgIds};
    expect(ids, containsAll(['poll_7', 'msg_native_7', alias]));
    expect(rows.single.isRead, isTrue);
    await store.dispose();
  });

  group('load / save / clear ordering', () {
    test('a load queued behind a delete save does not reinstall the row (#10)',
        () async {
      final store = MessageHistoryPersistence(historyDirectory: dir.path);
      await store.saveHistory(_peer, [_row('a', 1), _row('b', 2)]);
      await store.loadHistory(_peer);
      final cached = store.getCachedList(_peer)!;
      final b = cached.where((m) => m.msgID == 'b').toList();
      cached.removeWhere((m) => m.msgID == 'b');
      store.noteRemovedFromCache(_peer, b);

      final save = store.saveHistory(_peer, cached);
      final load = store.loadHistory(_peer);
      await save;
      expect((await load).map((m) => m.msgID), ['a']);
      expect(await reloadIds('peer'), ['a']);
      await store.dispose();
    });

    test('a load in flight across clearHistory installs nothing (pre #3)',
        () async {
      final store = MessageHistoryPersistence(historyDirectory: dir.path);
      await store.saveHistory(_peer, [_row('a', 1)]);
      await store.dispose();

      final fresh = MessageHistoryPersistence(historyDirectory: dir.path);
      final load = fresh.loadHistory(_peer);
      final clear = fresh.clearHistory(_peer);
      await Future.wait([load, clear]);
      await fresh.flushPendingSaves();
      expect(fresh.getHistory(_peer), isEmpty);
      expect(await mainFile('peer').exists(), isFalse);
      await fresh.dispose();
    });

    test('clearAllHistories during loads and saves leaves nothing behind (#8)',
        () async {
      final seed = MessageHistoryPersistence(historyDirectory: dir.path);
      for (var i = 0; i < 5; i++) {
        await seed.saveHistory('peer$i', [_row('r$i', i)]);
      }
      await seed.dispose();

      final store = MessageHistoryPersistence(historyDirectory: dir.path);
      final loads = [for (var i = 0; i < 5; i++) store.loadHistory('peer$i')];
      unawaited(store.saveHistory('peer0', [_row('late', 9)]));
      store.noteRemovedFromCache('peer1', [_row('r1', 1)]);
      await store.clearAllHistories();
      await Future.wait(loads);
      await store.flushPendingSaves();

      expect(store.getConversationIds(), isEmpty);
      expect(await dir.exists(), isFalse,
          reason: 'no pre-clear write may recreate the directory');

      // Work queued after the clear is a new conversation and is kept.
      await store.appendHistory('peer7', _row('new', 20));
      await store.flushPendingSaves();
      expect(await reloadIds('peer7'), ['new']);
      await store.dispose();
    });
  });

  test('flush reports a write it could not make and keeps the retry (#7)',
      () async {
    // A regular FILE where the history directory should be: every write
    // fails until it is removed.
    final blocker = File(p.join(dir.path, 'history'));
    await blocker.writeAsString('not a directory');
    final unhandled = <Object>[];
    // Created OUTSIDE the guarded zone so its result reaches this await.
    final done = Completer<
        ({Object? flushError, List<String?> cached, bool landedByRetry})>();
    runZonedGuarded(() async {
      try {
        final store = MessageHistoryPersistence(historyDirectory: blocker.path);
        // Fire-and-forget, the way native callback paths append (#19).
        unawaited(store.appendHistory(_peer, _row('keep', 1)));
        Object? flushError;
        try {
          await store.flushPendingSaves();
        } catch (e) {
          flushError = e;
        }
        final cached = store.getHistory(_peer).map((m) => m.msgID).toList();

        // Disk comes back: the armed retry (1 s backoff) writes the row.
        // Poll for the write instead of sleeping past the backoff — a fixed
        // wait is a race on a loaded CI host, and it is the RETRY that must
        // land the row (dispose below would flush it too, which is why the
        // poll has to succeed first).
        await blocker.delete();
        final written = File(p.join(blocker.path, 'peer.json'));
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!written.existsSync() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        // Sampled BEFORE dispose. dispose() flushes too, so a file checked
        // afterwards exists either way — the assertion passed whether or not
        // the automatic retry ever fired, which is the one thing this test is
        // for.
        final landedByRetry = written.existsSync();
        await store.dispose();
        done.complete((
          flushError: flushError,
          cached: cached,
          landedByRetry: landedByRetry,
        ));
      } catch (e, st) {
        done.completeError(e, st);
      }
    }, (e, _) => unhandled.add(e));
    final result = await done.future;
    expect(result.flushError, isA<HistoryFlushException>());
    expect(result.cached, ['keep']);
    expect(result.landedByRetry, isTrue,
        reason: 'the ARMED RETRY must write the row once the disk comes back, '
            'without waiting for dispose to flush it');
    expect(await File(p.join(blocker.path, 'peer.json')).exists(), isTrue);
    expect(unhandled, isEmpty, reason: 'no unhandled async error may escape');
  });

  group('session reuse (#23)', () {
    test('dispose then openSession restores debounce and drops old state',
        () async {
      final store = MessageHistoryPersistence(historyDirectory: dir.path);
      await store.appendHistory(_peer, _row('a', 1));
      store.noteRemovedFromCache(_peer, [_row('ghost', 0)]);
      await store.dispose();
      expect(store.getConversationIds(), isEmpty);

      // A straggler from the closed session must not write a one-row list.
      await store.appendHistory(_peer, _row('late', 2));
      expect(await reloadIds('peer'), ['a']);

      await store.openSession();
      await store.loadHistory(_peer);
      unawaited(store.appendHistory(_peer, _row('b', 3)));
      // Debounced (not synchronous) again: nothing on disk yet...
      expect(await reloadIds('peer'), ['a']);
      // ...and it lands. Awaiting the flush instead of sleeping past the
      // 200ms debounce keeps this deterministic under a loaded full run.
      await store.flushPendingSaves();
      expect(await reloadIds('peer'), ['a', 'b']);
      await store.dispose();
    });

    test('the default directory is bound to its owner (pre #4)', () async {
      const ownerA =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      const ownerB =
          'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
      final a = MessageHistoryPersistence(appSupportRootOverride: dir.path)
        ..openSession(ownerKey: '${ownerA}0102030405AB');
      await a.saveHistory(_peer, [_row('from_a', 1)]);
      await a.dispose();

      final b = MessageHistoryPersistence(appSupportRootOverride: dir.path)
        ..openSession(ownerKey: ownerB);
      expect(await b.loadHistory(_peer), isEmpty,
          reason: 'B must not read A\'s history for the same peer');
      await b.saveHistory(_peer, [_row('from_b', 2)]);
      await b.dispose();

      final shared = File(p.join(dir.path, 'chat_history', 'peer.json'));
      final isolated =
          File(p.join(dir.path, 'chat_history_$ownerB', 'peer.json'));
      expect(await shared.readAsString(), contains('from_a'));
      expect(await shared.readAsString(), isNot(contains('from_b')));
      expect(await isolated.readAsString(), contains('from_b'));

      final a2 = MessageHistoryPersistence(appSupportRootOverride: dir.path)
        ..openSession(ownerKey: ownerA);
      expect((await a2.loadHistory(_peer)).map((m) => m.msgID), ['from_a']);
      await a2.dispose();
    });
  });

  group('archive (#6 #9 #21 #22)', () {
    Future<void> fill(MessageHistoryPersistence s, int n) async {
      for (var i = 0; i < n; i++) {
        unawaited(s.appendHistory(_group, _groupRow(i)));
      }
      await s.flushPendingSaves();
    }

    test('archive-only rows and conversations are deletable', () async {
      final store = MessageHistoryPersistence(historyDirectory: dir.path);
      await fill(store, 1004);
      // Drop the in-memory window: only the archive (4 rows) remains.
      await store.clearHistory(_group, keepArchive: true);
      expect(store.getConversationIds(), isNot(contains(_group)));
      expect(await store.getArchivedConversationIds(), contains(_group));

      expect(await store.removeArchivedMessagesEverywhere({'id_1'}), 1);
      expect(await store.removeMessage(_group, 'id_2'), isTrue);
      expect((await store.loadArchivedHistory(_group)).map((m) => m.msgID),
          ['id_0', 'id_3']);
      await store.dispose();
    });

    test('an archive read racing an overflow drain never duplicates a row',
        () async {
      final store = MessageHistoryPersistence(historyDirectory: dir.path);
      await fill(store, 1000);
      final reads = <Future<List<ChatMessage>>>[];
      for (var i = 1000; i < 1010; i++) {
        unawaited(store.appendHistory(_group, _groupRow(i)));
        reads.add(store.loadArchivedHistory(_group));
      }
      for (final rows in await Future.wait(reads)) {
        final ids = rows.map((m) => m.msgID).toList();
        expect(ids.toSet().length, ids.length);
      }
      await store.flushPendingSaves();
      expect((await store.loadArchivedHistory(_group)).length, 10);
      await store.dispose();
    });
  });
}
