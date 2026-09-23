// Loading history must never be the thing that destroys it.
//
// Tox has no server: a conversation's JSON file is the only copy. Two load
// paths used to turn a damaged file into permanent loss — an unparseable
// file (or a single undecodable row) loaded as an EMPTY conversation, and
// the next append then rewrote the file with one row, replacing the backup
// slot on the way. A third made every cold start rewrite every file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

const _group = 'tox_3';

ChatMessage _msg(int i) => ChatMessage(
      text: 'm$i',
      fromUserId: 'PEER',
      isSelf: false,
      groupId: _group,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 1000),
      msgID: 'id_$i',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('t2t_history_resilience_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File mainFile() => File('${tempDir.path}/$_group.json');

  Future<void> seed(int count) async {
    final p = MessageHistoryPersistence(historyDirectory: tempDir.path);
    await p.saveHistory(_group, [for (var i = 0; i < count; i++) _msg(i)]);
    await p.dispose();
  }

  List<File> preserved() => tempDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('$_group.json.'))
      .where((f) => !f.path.endsWith('.bak') && !f.path.endsWith('.tmp'))
      .toList();

  test('a clean cold start does not rewrite history files', () async {
    await seed(20);
    final before = await mainFile().readAsBytes();
    final mtimeBefore = (await mainFile().stat()).modified;
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    final p = MessageHistoryPersistence(historyDirectory: tempDir.path);
    final loaded = await p.loadAllHistories();
    expect(loaded[_group]!.length, 20);
    await p.dispose();

    expect((await mainFile().stat()).modified, mtimeBefore);
    expect(await mainFile().readAsBytes(), before);
  });

  test('a truncated file is preserved, not overwritten by the next append',
      () async {
    await seed(50);
    final original = await mainFile().readAsString();
    final torn = original.substring(0, original.length ~/ 2);
    await mainFile().writeAsString(torn);

    final p = MessageHistoryPersistence(historyDirectory: tempDir.path);
    await p.loadAllHistories();
    await p.appendHistory(_group, _msg(999));
    await p.flushPendingSaves();
    await p.dispose();

    final kept = preserved();
    expect(kept, hasLength(1),
        reason: 'the unreadable file must survive under another name');
    expect(await kept.single.readAsString(), torn);
  });

  test('one undecodable row costs that row, not the conversation', () async {
    await seed(100);
    final data = jsonDecode(await mainFile().readAsString()) as Map;
    ((data['messages'] as List)[40] as Map)['text'] = null; // hard cast fails
    await mainFile().writeAsString(jsonEncode(data));

    final p = MessageHistoryPersistence(historyDirectory: tempDir.path);
    final loaded = await p.loadAllHistories();
    await p.dispose();

    expect(loaded[_group]!.length, 99);
    expect(loaded[_group]!.map((m) => m.msgID), isNot(contains('id_40')));
    expect(preserved(), hasLength(1),
        reason: 'the original bytes are kept for recovery');
  });

  test('a file from a newer schema is set aside, not loaded and stripped',
      () async {
    await seed(5);
    final data = jsonDecode(await mainFile().readAsString()) as Map;
    data['version'] = 99;
    await mainFile().writeAsString(jsonEncode(data));

    final p = MessageHistoryPersistence(historyDirectory: tempDir.path);
    final loaded = await p.loadAllHistories();
    await p.dispose();

    expect(loaded.containsKey(_group), isFalse);
    expect(preserved(), hasLength(1));
  });
}
