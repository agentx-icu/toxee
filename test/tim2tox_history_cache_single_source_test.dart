// X4 — Single source of truth for the tim2tox in-memory message history cache.
//
// Background: prior to this fix, `FfiChatService` held its own
// `_historyByIdInternal` map and lazily merged from
// `MessageHistoryPersistence._historyById`. Mutations through one path
// (e.g. `_handleFileDone` rewriting `list[i] = updated`) only ever updated
// one of the two — the other could drift indefinitely. The fix made the
// persistence layer the sole owner; FfiChatService now reaches in through
// typed accessors.
//
// These tests pin the new invariant: writes via `appendHistory` are
// observable via `getHistory` / `cache` / `getCachedList`, index mutations
// via `replaceInCache` are observable through every other accessor,
// `clearHistory` purges both memory and disk, and there is no path that
// produces a "cleared in one place, still present in another" state.
//
// The tests target `MessageHistoryPersistence` directly (no FFI, no
// platform plugins) because that class IS the authoritative cache after
// the X4 consolidation. Pairing with `message_history_persistence_perf_test.dart`,
// which exercises the same class for the P2/P3 perf invariants.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

ChatMessage _msg({
  required String fromUserId,
  required String text,
  required int tsMs,
  String? msgID,
  String? filePath,
  bool isPending = false,
}) {
  return ChatMessage(
    text: text,
    fromUserId: fromUserId,
    isSelf: false,
    timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
    msgID: msgID ?? '${tsMs}_$fromUserId',
    filePath: filePath,
    isPending: isPending,
  );
}

Future<void> _flush(MessageHistoryPersistence p) async {
  // `flushPendingSaves` cancels the P2 debounce timers and awaits the writes
  // itself (it loops until no dirty work is left), so waiting on it waits for
  // the work rather than sleeping past the 200ms debounce window.
  await p.flushPendingSaves();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('X4 — MessageHistoryPersistence is the single source of truth', () {
    late Directory tempDir;
    late MessageHistoryPersistence persistence;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mhp_x4_');
      persistence =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
    });

    tearDown(() async {
      // Some tests fire-and-forget appendHistory futures; give the
      // write-lock queue a moment to drain before we tear down the temp
      // directory, otherwise lingering writes can race a delete and
      // surface as flake.
      try {
        await persistence.flushPendingSaves();
      } catch (_) {}
      await persistence.dispose();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test(
        'append → getHistory / cache / getCachedList all see the same message',
        () async {
      const peer = 'peer_alice';
      final m = _msg(
        fromUserId: peer,
        text: 'hello world',
        tsMs: 1000,
        msgID: 'm1',
      );

      await persistence.appendHistory(peer, m);
      await _flush(persistence);

      // Three different read paths, one consistent view.
      final viaGetHistory = persistence.getHistory(peer);
      final viaCache = persistence.cache[peer];
      final viaCachedList = persistence.getCachedList(peer);

      expect(viaGetHistory, hasLength(1));
      expect(viaGetHistory.first.msgID, 'm1');

      expect(viaCache, isNotNull);
      expect(viaCache!.first.msgID, 'm1');

      expect(viaCachedList, isNotNull);
      expect(viaCachedList!.first.msgID, 'm1');

      // `getCachedList` returns the real mutable list; `getHistory` /
      // `cache.values` are defensive copies / unmodifiable wrappers.
      expect(identical(viaCachedList, viaCache),
          isTrue, reason: 'cache values are the same list refs');
    });

    test(
        'replaceInCache via persistence is visible through getHistory and cache',
        () async {
      const peer = 'peer_bob';
      final original = _msg(
        fromUserId: peer,
        text: 'pending file',
        tsMs: 2000,
        msgID: 'm_file',
        filePath: '/tmp/receiving_x',
        isPending: true,
      );
      await persistence.appendHistory(peer, original);
      await _flush(persistence);

      // Simulate the `_handleFileDone` mutate-by-index pattern via the
      // typed accessor (which is the X4 replacement for FfiChatService's
      // old `history[index] = updatedMsg` on its private map).
      final cached = persistence.getCachedList(peer)!;
      final idx =
          cached.indexWhere((msg) => msg.msgID == 'm_file');
      expect(idx, isNonNegative);

      final finalized = ChatMessage(
        text: original.text,
        fromUserId: original.fromUserId,
        isSelf: original.isSelf,
        timestamp: original.timestamp,
        groupId: original.groupId,
        filePath: '/final/path/x',
        msgID: original.msgID,
      );
      persistence.replaceInCache(peer, idx, finalized);

      // All read paths see the new path; no stale pending message.
      final viaGetHistory = persistence.getHistory(peer);
      expect(viaGetHistory.single.filePath, '/final/path/x');
      expect(viaGetHistory.single.isPending, isFalse);

      final viaCache = persistence.cache[peer]!;
      expect(viaCache.single.filePath, '/final/path/x');

      // Persistence to disk still works: an explicit save lands the new
      // state, and reloading shows the finalized message.
      await persistence.saveHistory(peer, viaCache);
      final reloaded =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      try {
        final fromDisk = await reloaded.loadHistory(peer);
        expect(fromDisk.single.filePath, '/final/path/x');
        // loadHistory marks the conversation dirty when it normalizes the
        // loaded list (e.g. flipping any stranded pending flag); the write
        // itself is deferred. `flushPendingSaves` drains that dirty set and
        // awaits the writes, so no sleep is needed before the temp-dir
        // cleanup in tearDown.
        await reloaded.flushPendingSaves();
      } finally {
        reloaded.dispose();
      }
    });

    test(
        'replaceInCache is a no-op for unknown ids and out-of-range indices',
        () async {
      // Nothing in cache yet — should not throw.
      persistence.replaceInCache(
        'never_existed',
        0,
        _msg(fromUserId: 'x', text: 't', tsMs: 0),
      );
      expect(persistence.getHistory('never_existed'), isEmpty);

      // Add one message, then try to replace at index 5 / -1.
      const peer = 'peer_oor';
      await persistence.appendHistory(
        peer,
        _msg(fromUserId: peer, text: 'only', tsMs: 5000, msgID: 'a'),
      );
      await _flush(persistence);

      final updated =
          _msg(fromUserId: peer, text: 'should not appear', tsMs: 5001);
      persistence.replaceInCache(peer, 5, updated);
      persistence.replaceInCache(peer, -1, updated);

      final messages = persistence.getHistory(peer);
      expect(messages, hasLength(1));
      expect(messages.single.text, 'only');
    });

    test('clearHistory purges memory AND on-disk file (no split-brain)',
        () async {
      // Regression for the original X4 drift: previously, an inner-state
      // clear on FfiChatService didn't propagate to the persistence cache
      // (or vice versa), so subsequent reads could resurrect a "cleared"
      // history. After the consolidation, there's only one cache; the
      // invariant we assert is "after clearHistory completes, neither
      // memory nor disk has any record of that conversation."
      const peer = 'peer_clear';
      await persistence.appendHistory(
        peer,
        _msg(fromUserId: peer, text: 'present', tsMs: 9000, msgID: 'c1'),
      );
      await _flush(persistence);

      expect(persistence.getHistory(peer), hasLength(1));
      expect(persistence.getCachedList(peer), isNotNull);
      expect(persistence.cache.containsKey(peer), isTrue);

      await persistence.clearHistory(peer);

      // Memory: every accessor returns "empty".
      expect(persistence.getHistory(peer), isEmpty);
      expect(persistence.getCachedList(peer), isNull);
      expect(persistence.cache.containsKey(peer), isFalse);

      // Disk: no JSON file on disk for this peer.
      final files = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(files, isEmpty,
          reason: 'clearHistory should leave no JSON behind on disk');

      // Cold reload from disk shows nothing — confirming no resurrection.
      final reloaded =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      try {
        final fromDisk = await reloaded.loadHistory(peer);
        expect(fromDisk, isEmpty);
      } finally {
        reloaded.dispose();
      }
    });

    test('removeCachedHistory drops the cache entry without touching disk',
        () async {
      // The X4 accessor used by `FfiChatService.dispose` /
      // `clearC2CHistory`'s eager pre-clear step.
      const peer = 'peer_remove';
      await persistence.appendHistory(
        peer,
        _msg(fromUserId: peer, text: 'on-disk', tsMs: 10000, msgID: 'r1'),
      );
      await _flush(persistence);

      // File is on disk before the in-memory remove.
      final beforeFiles = tempDir.listSync().whereType<File>().toList();
      expect(beforeFiles, isNotEmpty);

      persistence.removeCachedHistory(peer);

      // Memory cache: empty.
      expect(persistence.getCachedList(peer), isNull);
      expect(persistence.cache.containsKey(peer), isFalse);

      // Disk: file still there.
      final afterFiles = tempDir.listSync().whereType<File>().toList();
      expect(afterFiles.map((f) => f.path),
          containsAll(beforeFiles.map((f) => f.path)));

      // Loading from disk repopulates the cache.
      final reloaded = await persistence.loadHistory(peer);
      expect(reloaded, hasLength(1));
      expect(persistence.getCachedList(peer), isNotNull);
    });

    test('1000-message in-memory cap is preserved (X4 invariant)', () async {
      // FfiChatService used to apply this cap in its own _appendHistory
      // before delegating to persistence; the consolidation moved the cap
      // into `MessageHistoryPersistence.appendHistory`. Make sure we
      // didn't lose it during the refactor.
      //
      // We assert against the synchronous post-call list length: the
      // in-memory mutation (including the truncation) is synchronous
      // inside `appendHistory`, so the cap check passes regardless of
      // whether the queued disk writes have flushed. We don't await the
      // disk side because each truncation triggers an immediate
      // `saveHistory(1000 messages)` that takes the write lock — 1050
      // such writes serialized would exceed the 30s test budget.
      const peer = 'peer_cap';
      // 1001 messages: enough to trigger exactly one truncation save.
      // Larger N just buys more I/O without exercising new code paths.
      final futures = <Future<void>>[];
      for (var i = 0; i < 1001; i++) {
        futures.add(persistence.appendHistory(
          peer,
          _msg(
            fromUserId: peer,
            text: 'msg $i',
            tsMs: 100000 + i,
            msgID: 'cap_$i',
          ),
        ));
      }

      final cached = persistence.getCachedList(peer)!;
      expect(cached.length, lessThanOrEqualTo(1000));
      // After truncation, the most-recent message wins (it's a FIFO trim
      // at the head of the list).
      expect(cached.last.msgID, 'cap_1000');

      // Drain the queued futures so tearDown's tempDir.delete doesn't
      // race the truncation save.
      await Future.wait(futures, eagerError: false).catchError((_) => <void>[]);
    });

    test('clearAllCached wipes memory without deleting disk files',
        () async {
      // Models the per-account FfiChatService.dispose() pathway, which
      // drops in-memory state without nuking the on-disk JSON (the
      // account stays restorable on next login).
      for (var i = 0; i < 3; i++) {
        final peer = 'multi_$i';
        await persistence.appendHistory(
          peer,
          _msg(
            fromUserId: peer,
            text: 'm',
            tsMs: 200000 + i,
            msgID: 'multi_$i',
          ),
        );
      }
      await _flush(persistence);

      expect(persistence.cache.length, 3);
      // Count only the conversation JSONs (debounced saves can leave .tmp
      // / .bak siblings depending on timing).
      List<File> jsonFiles() => tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      final filesBefore = jsonFiles();
      expect(filesBefore, hasLength(3));

      persistence.clearAllCached();

      expect(persistence.cache, isEmpty);
      final filesAfter = jsonFiles();
      expect(filesAfter.map((f) => f.path),
          unorderedEquals(filesBefore.map((f) => f.path)));
    });
  });

  group('X4 — regression: clearHistory never leaves split-brain state',
      () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mhp_x4_rg_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test(
        'simulated FfiChatService.clearC2CHistory equivalent never produces '
        'a state where one cache view sees the conversation and another does '
        'not (a single source of truth means a single answer)', () async {
      final persistence =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      addTearDown(persistence.dispose);

      // Seed two conversations: the one we clear, and a control that
      // must survive untouched.
      const target = 'target_peer';
      const survivor = 'survivor_peer';
      await persistence.appendHistory(
        target,
        _msg(fromUserId: target, text: 't1', tsMs: 1, msgID: 't1'),
      );
      await persistence.appendHistory(
        target,
        _msg(fromUserId: target, text: 't2', tsMs: 2, msgID: 't2'),
      );
      await persistence.appendHistory(
        survivor,
        _msg(fromUserId: survivor, text: 's1', tsMs: 3, msgID: 's1'),
      );
      await _flush(persistence);

      // Mimic FfiChatService.clearC2CHistory's "eager remove cache + then
      // disk clear" pattern using the X4 accessors.
      persistence.removeCachedHistory(target);
      await persistence.clearHistory(target);

      // Every accessor agrees on `target` being gone:
      expect(persistence.getHistory(target), isEmpty);
      expect(persistence.getCachedList(target), isNull);
      expect(persistence.cache.containsKey(target), isFalse);

      // And `survivor` is untouched in every accessor:
      expect(persistence.getHistory(survivor), hasLength(1));
      expect(persistence.getCachedList(survivor)!.single.msgID, 's1');
      expect(persistence.cache[survivor]!.single.msgID, 's1');

      // Disk reflects the same single source of truth.
      final files = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(files, hasLength(1));
      final decoded = jsonDecode(await files.single.readAsString())
          as Map<String, dynamic>;
      final msgs = (decoded['messages'] as List).cast<Map<String, dynamic>>();
      expect(msgs, hasLength(1));
      expect(msgs.single['msgID'], 's1');
    });
  });
}
