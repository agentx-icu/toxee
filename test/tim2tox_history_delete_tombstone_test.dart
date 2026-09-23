// GH-10 edge: a row deleted from the cache must not come back when a load
// merges the on-disk file back in before the deletion was saved.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

ChatMessage _row(String id, int sec) => ChatMessage(
      text: 'm$id',
      fromUserId: 'A' * 64,
      isSelf: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000 + sec * 1000),
      msgID: id,
    );

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tombstone_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a deleted row is not resurrected by a load before its save', () async {
    final store = MessageHistoryPersistence(historyDirectory: dir.path);
    const conv = 'c2c_peer';
    await store.saveHistory(conv, [_row('a', 1), _row('b', 2), _row('c', 3)]);
    await store.loadHistory(conv);

    // Delete in memory only (as a debounced delete would), then reload.
    final cached = store.getCachedList(conv)!;
    final removed = cached.where((m) => m.msgID == 'b').toList();
    cached.removeWhere((m) => m.msgID == 'b');
    store.noteRemovedFromCache(conv, removed);

    final loaded = await store.loadHistory(conv);
    expect(loaded.map((m) => m.msgID), ['a', 'c']);

    // Once a save lands, the file agrees and the tombstone is gone: a row
    // with that id written later is not suppressed.
    await store.saveHistory(conv, store.getCachedList(conv)!);
    await store.appendHistory(conv, _row('b', 4));
    expect(store.getHistory(conv).map((m) => m.msgID), containsAll(['a', 'b', 'c']));
  });
}
