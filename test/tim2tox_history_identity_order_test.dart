// Group-review 2026-09-17 history findings, persistence layer (no FFI):
//
//   GH-4  content+time dedupe collapsed two GENUINE identical group messages
//         ("ok", "ok" 500 ms apart). Rows that both carry the NGC identity
//         alias (`gmid:<gid>|<SENDER>|<toxGroupMsgId>`) now dedupe exactly on
//         it; the content window survives only for alias-less rows.
//   GH-6  equal timestamps came back in arbitrary order after a reload
//         (`List.sort` is unstable past 32 elements).
//   GH-7  saveHistory swallowed every write failure.
//   GH-9  a duplicate's id must stay resolvable on the row that absorbed it.
//   GH-10 loadHistory replaced the cached list (losing an append that landed
//         during the load) and backup recovery never populated the cache.
//
// Targets `MessageHistoryPersistence` directly, like
// `tim2tox_history_archive_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

const _gid = 'tox_group_42';
const _sender = 'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12';

String _alias(int pseudoId) => toxGroupMessageAlias(
    groupId: _gid, senderPk: _sender, pseudoMsgId: pseudoId);

ChatMessage _groupRow(
  String msgID, {
  String text = 'ok',
  required int ms,
  int? pseudoId,
  bool isSelf = false,
}) =>
    ChatMessage(
      text: text,
      fromUserId: isSelf ? 'SELF' : _sender,
      isSelf: isSelf,
      groupId: _gid,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ms),
      msgID: msgID,
      altMsgIds: [if (pseudoId != null) _alias(pseudoId)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MessageHistoryPersistence persistence;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('t2t_history_identity_');
    persistence = MessageHistoryPersistence(historyDirectory: tempDir.path);
  });

  tearDown(() async {
    // Undo any permission change a test made so the cleanup can run.
    if (await tempDir.exists()) {
      await Process.run('chmod', ['-R', 'u+rwx', tempDir.path]);
    }
    await persistence.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('toxGroupMsgIdFromLocalCustomData (native contract)', () {
    test('parses the exact native shape and tolerates everything else', () {
      expect(toxGroupMsgIdFromLocalCustomData('{"toxGroupMsgId":4294967295}'),
          4294967295);
      expect(toxGroupMsgIdFromLocalCustomData('{"toxGroupMsgId":0}'), 0);
      // Coexists with other keys (content-kind marker merged later).
      expect(
          toxGroupMsgIdFromLocalCustomData(
              '{"toxGroupMsgId":7,"tim2toxContentKind":"action"}'),
          7);
      for (final bad in <String?>[
        null,
        '',
        'not json',
        '[1,2]',
        '{}',
        '{"toxGroupMsgId":"7"}',
        '{"toxGroupMsgId":-1}',
        '{"toxGroupMsgId":4294967296}',
        '{"toxGroupMsgId":1.5}',
        '{"toxGroupMsgId":',
      ]) {
        expect(toxGroupMsgIdFromLocalCustomData(bad), isNull, reason: '$bad');
      }
      // The content-kind parser is unaffected by the id key.
      expect(
          chatMessageContentKindFromLocalCustomData('{"toxGroupMsgId":7}'),
          ChatMessageContentKind.normal);
    });

    test('alias is case-normalized on the sender key', () {
      expect(
        toxGroupMessageAlias(groupId: 'g', senderPk: 'ab', pseudoMsgId: 9),
        'gmid:g|AB|9',
      );
    });
  });

  group('GH-4 appendHistory dedupes group rows by identity', () {
    test('two distinct aliases, same sender+text 500 ms apart -> 2 rows',
        () async {
      await persistence.appendHistory(
          _gid, _groupRow('poll_1', ms: 1700000000000, pseudoId: 101));
      await persistence.appendHistory(
          _gid, _groupRow('poll_2', ms: 1700000000500, pseudoId: 102));
      expect(persistence.getHistory(_gid).map((m) => m.msgID),
          ['poll_1', 'poll_2']);
    });

    test('same alias twice (cross-path copy) -> 1 row, both ids resolvable',
        () async {
      await persistence.appendHistory(
          _gid, _groupRow('poll_1', ms: 1700000000000, pseudoId: 101));
      // The advanced-listener copy: native id, same identity, >2 s later
      // (identity does not depend on timing).
      await persistence.appendHistory(_gid,
          _groupRow('msg_0_99_1', ms: 1700000004000, pseudoId: 101));
      final rows = persistence.getHistory(_gid);
      expect(rows, hasLength(1));
      final ids = {rows.single.msgID, ...rows.single.altMsgIds};
      expect(ids, containsAll(['poll_1', 'msg_0_99_1', _alias(101)]));
      expect(await persistence.removeMessage(_gid, 'poll_1'), isTrue);
      expect(persistence.getHistory(_gid), isEmpty);
    });

    test('alias-less rows keep the 2 s content window (legacy/conference)',
        () async {
      await persistence.appendHistory(
          _gid, _groupRow('legacy_1', ms: 1700000000000));
      await persistence.appendHistory(
          _gid, _groupRow('legacy_2', ms: 1700000000500, pseudoId: 5));
      expect(persistence.getHistory(_gid), hasLength(1),
          reason: 'one side has no identity: content fallback still applies');
    });
  });

  group('GH-9 absorbDuplicateIds', () {
    test('keeps the primary, records the duplicate ids, delete by them works',
        () async {
      final poll = _groupRow('poll_1', ms: 1700000000000, pseudoId: 101);
      await persistence.appendHistory(_gid, poll);
      final row = persistence.getHistory(_gid).single;
      await persistence.absorbDuplicateIds(
          _gid, row, _groupRow('msg_0_1_1', ms: 1700000000100, pseudoId: 101));
      final after = persistence.getHistory(_gid).single;
      expect(after.msgID, 'poll_1');
      expect(after.altMsgIds, containsAll(['msg_0_1_1', _alias(101)]));
      await persistence.flushPendingSaves();

      final reloaded =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      await reloaded.loadHistory(_gid);
      expect(reloaded.getHistory(_gid).single.altMsgIds, contains('msg_0_1_1'));
      expect(await reloaded.removeMessage(_gid, 'msg_0_1_1'), isTrue);
      await reloaded.dispose();
    });
  });

  group('GH-6 stable chronological order', () {
    test('>32 rows sharing timestamps keep arrival order across a reload',
        () async {
      // Whole-second native rows interleaved with ms self rows: 60 rows over
      // two seconds, many exact ties.
      final expected = <String>[];
      for (var i = 0; i < 60; i++) {
        final second = 1700000000000 + (i ~/ 30) * 1000;
        final row = i.isEven
            ? _groupRow('in_$i', text: 'in $i', ms: second) // .000 ties
            : _groupRow('self_$i', text: 'self $i', ms: second, isSelf: true);
        expected.add(row.msgID!);
        // ignore: unawaited_futures
        persistence.appendHistory(_gid, row);
      }
      await persistence.flushPendingSaves();

      final reloaded =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      final loaded = await reloaded.loadHistory(_gid);
      expect(loaded.map((m) => m.msgID), expected);
      expect(reloaded.getHistory(_gid).map((m) => m.msgID), expected);

      // loadHistory hands back a COPY: a caller sorting it newest-first (the
      // FfiChatService preview refresh does) must not reverse the cache.
      loaded.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      expect(reloaded.getHistory(_gid).map((m) => m.msgID), expected);
      await reloaded.dispose();
    });

    test('sortChatMessagesChronologically newest-first reverses ties', () {
      final rows = [
        for (var i = 0; i < 40; i++)
          _groupRow('r$i', ms: 1700000000000 + (i ~/ 20)),
      ];
      sortChatMessagesChronologically(rows, newestFirst: true);
      expect(rows.first.msgID, 'r39');
      expect(rows.last.msgID, 'r0');
      expect(rows.map((m) => m.msgID).take(3), ['r39', 'r38', 'r37']);
    });
  });

  group('GH-7 write failures propagate and are retried', () {
    test('unwritable history dir: saveHistory throws, callers see it',
        () async {
      await persistence.appendHistory(
          _gid, _groupRow('a', ms: 1700000000000, pseudoId: 1));
      await persistence.flushPendingSaves();

      await Process.run('chmod', ['0555', tempDir.path]);
      await expectLater(
        persistence.saveHistory(_gid, persistence.getHistory(_gid)),
        throwsA(isA<FileSystemException>()),
      );
      // An awaited append now reports the failure...
      await expectLater(
        persistence.appendHistory(
            _gid, _groupRow('b', ms: 1700000001000, pseudoId: 2)),
        throwsA(isA<FileSystemException>()),
      );
      // ...while a fire-and-forget one must not become an uncaught zone
      // error (the test would fail if it did).
      // ignore: unawaited_futures
      persistence.appendHistory(
          _gid, _groupRow('c', ms: 1700000002000, pseudoId: 3));
      await Future<void>.delayed(const Duration(milliseconds: 400));

      // updateFilePathSafely's rollback is live again.
      final target = File('${Directory.systemTemp.path}/gh7_target.bin')
        ..writeAsStringSync('x');
      addTearDown(() {
        if (target.existsSync()) target.deleteSync();
      });
      expect(
          await persistence.updateFilePathSafely(_gid, 'a', target.path),
          isFalse);
      expect(
          persistence
              .getHistory(_gid)
              .firstWhere((m) => m.msgID == 'a')
              .filePath,
          isNull,
          reason: 'failed save must roll the in-memory change back');

      // Writable again: the armed retry (1 s backoff) lands everything.
      await Process.run('chmod', ['0755', tempDir.path]);
      // Poll for the retry instead of sleeping past its backoff: a fixed wait
      // is a race under a loaded full-suite run.
      final file = File('${tempDir.path}/$_gid.json');
      List<dynamic> onDiskIds() {
        if (!file.existsSync()) return const [];
        final decoded = jsonDecode(file.readAsStringSync()) as Map;
        return (decoded['messages'] as List)
            .map((m) => (m as Map)['msgID'])
            .toList();
      }

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (onDiskIds().length < 3 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(onDiskIds(), ['a', 'b', 'c']);
    });
  });

  group('GH-10 loadHistory merges instead of replacing', () {
    test('an append that lands during the load survives and is persisted',
        () async {
      await persistence.appendHistory(
          _gid, _groupRow('old_1', text: 'o1', ms: 1700000000000));
      await persistence.appendHistory(
          _gid, _groupRow('old_2', text: 'o2', ms: 1700000001000));
      await persistence.flushPendingSaves();

      final fresh = MessageHistoryPersistence(historyDirectory: tempDir.path);
      final load = fresh.loadHistory(_gid);
      // Lands before the load's first await resumes: cache is absent, so the
      // append starts a one-row list.
      // ignore: unawaited_futures
      fresh.appendHistory(
          _gid, _groupRow('new_1', text: 'n1', ms: 1700000002000));
      final loaded = await load;
      expect(loaded.map((m) => m.msgID), ['old_1', 'old_2', 'new_1']);
      expect(fresh.getHistory(_gid).map((m) => m.msgID),
          ['old_1', 'old_2', 'new_1']);
      // `flushPendingSaves` loops until no dirty work is left (including
      // debounce timers armed while it was awaiting), so one call is enough —
      // no sleep between two flushes to outlast the 200ms debounce.
      await fresh.flushPendingSaves();
      await fresh.dispose();

      final check = MessageHistoryPersistence(historyDirectory: tempDir.path);
      expect((await check.loadHistory(_gid)).map((m) => m.msgID),
          ['old_1', 'old_2', 'new_1']);
      await check.dispose();
    });

    test('backup recovery populates the cache', () async {
      final rows = [
        _groupRow('bak_1', text: 'b1', ms: 1700000000000),
        _groupRow('bak_2', text: 'b2', ms: 1700000001000),
      ];
      File('${tempDir.path}/$_gid.json.bak').writeAsStringSync(jsonEncode({
        'conversationId': _gid,
        'version': 2,
        'lastViewTimestamp': 0,
        'messages': [for (final m in rows) m.toJson()],
      }));

      final loaded = await persistence.loadHistory(_gid);
      expect(loaded.map((m) => m.msgID), ['bak_1', 'bak_2']);
      expect(persistence.getHistory(_gid).map((m) => m.msgID),
          ['bak_1', 'bak_2'],
          reason: 'recovered rows must be the cached history');

      await persistence.appendHistory(
          _gid, _groupRow('after', text: 'a', ms: 1700000002000));
      await persistence.flushPendingSaves();
      final check = MessageHistoryPersistence(historyDirectory: tempDir.path);
      expect((await check.loadHistory(_gid)).map((m) => m.msgID),
          ['bak_1', 'bak_2', 'after'],
          reason: 'the next save must not replace the recovered history');
      await check.dispose();
    });
  });
}
