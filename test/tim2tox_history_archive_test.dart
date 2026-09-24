// History older than the in-memory window must survive on disk.
//
// `MessageHistoryPersistence` keeps the newest 1000 rows of a conversation in
// memory. It used to save the FULL list exactly once when the window
// overflowed and then truncate; every later save serialized the truncated
// list over that file, so anything older than the newest 1000 rows was
// destroyed (an active group crosses 1000 in days, and Tox has no server to
// backfill from). Overflow rows now move to an append-only per-conversation
// archive that paging, delete and clear all know about.
//
// Targets `MessageHistoryPersistence` directly (no FFI, no platform plugins),
// like `tim2tox_history_cache_single_source_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

const _group = 'tox_7';

ChatMessage _msg(int i, {String? text}) => ChatMessage(
      text: text ?? 'm$i',
      fromUserId: 'PEER',
      isSelf: false,
      groupId: _group,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 1000),
      msgID: 'id_$i',
    );

Future<void> _flush(MessageHistoryPersistence p) async {
  await p.flushPendingSaves();
}

Future<void> _appendRange(
    MessageHistoryPersistence p, int from, int toExclusive) async {
  final appends = <Future<void>>[];
  for (var i = from; i < toExclusive; i++) {
    // Deliberately not awaited one by one: that is how the product appends.
    // They are awaited together below — `appendHistory`'s future completes
    // when its debounced save lands, so this waits for the WORK instead of
    // sleeping past the debounce window.
    appends.add(p.appendHistory(_group, _msg(i)));
  }
  await Future.wait(appends);
  await _flush(p);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MessageHistoryPersistence persistence;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('t2t_history_archive_');
    persistence = MessageHistoryPersistence(historyDirectory: tempDir.path);
  });

  tearDown(() async {
    await persistence.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File mainFile() => File('${tempDir.path}/$_group.json');
  File archiveFile() => File('${tempDir.path}/$_group.archive.jsonl');

  test('rows past the memory window stay on disk across later saves',
      () async {
    await _appendRange(persistence, 0, 1005);
    // The regression needed a SECOND save after the truncating one.
    await _appendRange(persistence, 1005, 1010);

    expect(persistence.getHistory(_group).length, 1000);
    expect(persistence.getHistory(_group).first.msgID, 'id_10');

    final archived = await persistence.loadArchivedHistory(_group);
    expect(archived.map((m) => m.msgID).toList(),
        [for (var i = 0; i < 10; i++) 'id_$i']);

    // Nothing is in both places, nothing is missing.
    final mainJson = jsonDecode(await mainFile().readAsString()) as Map;
    final onDisk = <String>{
      for (final m in mainJson['messages'] as List) (m as Map)['msgID'] as String,
      for (final m in archived) m.msgID!,
    };
    expect(onDisk.length, 1010);
  });

  test('a fresh instance sees the archive after a restart', () async {
    await _appendRange(persistence, 0, 1003);
    await persistence.dispose();

    persistence = MessageHistoryPersistence(historyDirectory: tempDir.path);
    final loaded = await persistence.loadAllHistories();
    expect(loaded.keys, [_group],
        reason: 'the archive must not be loaded as a conversation file');
    expect(loaded[_group]!.length, 1000);
    expect(await persistence.hasArchivedHistory(_group), isTrue);
    expect((await persistence.loadArchivedHistory(_group)).length, 3);
  });

  test('a torn archive line costs that line, not the archive', () async {
    await _appendRange(persistence, 0, 1003);
    await archiveFile()
        .writeAsString('{"text":"half-writ', mode: FileMode.append);
    await persistence.dispose();

    persistence = MessageHistoryPersistence(historyDirectory: tempDir.path);
    await persistence.loadAllHistories();
    expect((await persistence.loadArchivedHistory(_group)).length, 3);
  });

  test('rows still in memory are not returned twice (crash between the '
      'archive append and the main-file rewrite)', () async {
    await _appendRange(persistence, 0, 1003);
    // Simulate the crash window: id_500 is in the main file AND the archive.
    await archiveFile().writeAsString('${jsonEncode(_msg(500).toJson())}\n',
        mode: FileMode.append);
    await persistence.dispose();

    persistence = MessageHistoryPersistence(historyDirectory: tempDir.path);
    await persistence.loadAllHistories();
    final archived = await persistence.loadArchivedHistory(_group);
    expect(archived.map((m) => m.msgID), isNot(contains('id_500')));
    expect(archived.length, 3);
  });

  test('deleting an archived row rewrites only the archive', () async {
    await _appendRange(persistence, 0, 1003);
    expect(await persistence.removeArchivedMessages(_group, {'id_1'}), 1);
    expect((await persistence.loadArchivedHistory(_group)).map((m) => m.msgID),
        ['id_0', 'id_2']);
    expect(persistence.getHistory(_group).length, 1000);
  });

  test('clearHistory drops the archive; keepArchive keeps it', () async {
    await _appendRange(persistence, 0, 1003);
    await persistence.clearHistory(_group, keepArchive: true);
    expect(await archiveFile().exists(), isTrue);
    expect(await mainFile().exists(), isFalse);

    await persistence.clearHistory(_group);
    expect(await archiveFile().exists(), isFalse);
    expect(await persistence.hasArchivedHistory(_group), isFalse);
  });
}
