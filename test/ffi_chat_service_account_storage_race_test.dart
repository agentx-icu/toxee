// Two data-safety defects on `FfiChatService`, from the 2026-09-22 review.
//
//   * `installAccountStorage` recorded the binding only AFTER the rebinds and
//     the reload. Two concurrent calls therefore both passed the "not
//     installed" check, interleaved their rebinds, and a caller could return
//     success on a service pointing at the OTHER account's files.
//   * `deleteMessages` excluded the ids it had matched in memory from the
//     archive sweep, so the archived copy a crash can leave behind (the row is
//     appended to the archive before the main file is rewritten) survived the
//     delete and reappeared once the tombstone cleared.
//
// Shared Dart, so both fixes cover desktop and mobile alike. Needs the FFI
// library only because `FfiChatService`'s constructor opens it; nothing here
// initializes Tox.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

const _conversationId =
    'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

ChatMessage _message(String text, {required String id}) => ChatMessage(
  text: text,
  fromUserId: 'PEER',
  isSelf: false,
  timestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
  msgID: id,
);

String _historyTextIn(Directory dir) {
  if (!dir.existsSync()) return '';
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => f.readAsStringSync())
      .join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('t2t_storage_race_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  Directory accountDir(String name) {
    final dir = Directory(p.join(tempRoot.path, name, 'chat_history'));
    dir.createSync(recursive: true);
    return dir;
  }

  String queuePathFor(String name) =>
      p.join(tempRoot.path, name, 'offline_message_queue.json');

  group('installAccountStorage races', () {
    test('a competing install for another account cannot win half of it', () async {
      final service = FfiChatService();
      addTearDown(service.dispose);
      final dirA = accountDir('a');
      final dirB = accountDir('b');

      // Both calls are started before either has finished — the shape the
      // defect needed (two logins racing on one service object).
      final first = service.installAccountStorage(
        historyDirectory: dirA.path,
        queueFilePath: queuePathFor('a'),
      );
      final second = service.installAccountStorage(
        historyDirectory: dirB.path,
        queueFilePath: queuePathFor('b'),
      );

      await expectLater(second, throwsStateError);
      await first;

      // The service is wholly account A's: writes land there and nothing was
      // created under B.
      await service.messageHistoryPersistence.saveHistory(_conversationId, [
        _message('belongs-to-a', id: 'm1'),
      ]);
      await service.messageHistoryPersistence.flushPendingSaves();
      expect(_historyTextIn(dirA), contains('belongs-to-a'));
      expect(_historyTextIn(dirB), isEmpty);
    }, skip: skipReason);

    test('a concurrent install for the SAME account waits for it', () async {
      final dirA = accountDir('a');
      // Pre-existing history the install's reload must have picked up before
      // either caller is told the storage is installed.
      await File(p.join(dirA.path, '$_conversationId.json')).writeAsString(
        jsonEncode({
          'conversationId': _conversationId,
          'version': 2,
          'lastViewTimestamp': 0,
          'messages': [_message('already-on-disk', id: 'm0').toJson()],
        }),
      );

      final service = FfiChatService();
      addTearDown(service.dispose);
      final first = service.installAccountStorage(
        historyDirectory: dirA.path,
        queueFilePath: queuePathFor('a'),
      );
      final second = service.installAccountStorage(
        historyDirectory: dirA.path,
        queueFilePath: queuePathFor('a'),
      );

      await second;
      // The second caller returning means the reload has run — it used to
      // return immediately on the claim alone, before the stores were bound.
      expect(
        service.messageHistoryPersistence
            .getHistory(_conversationId)
            .map((m) => m.text),
        contains('already-on-disk'),
      );
      await first;
    }, skip: skipReason);
  });

  group('deleteMessages and the archive', () {
    test('an archived duplicate of a deleted row does not survive', () async {
      final dir = accountDir('a');
      final service = FfiChatService(
        historyDirectory: dir.path,
        queueFilePath: queuePathFor('a'),
      );
      addTearDown(service.dispose);

      final row = _message('deleted-by-the-user', id: 'm7');
      await service.messageHistoryPersistence.appendHistory(
        _conversationId,
        row,
      );
      await service.messageHistoryPersistence.flushPendingSaves();
      // The crash shape: the row reached the archive, the main-file rewrite
      // that would have dropped it from the window never landed.
      final archive = File(p.join(dir.path, '$_conversationId.archive.jsonl'));
      await archive.writeAsString('${jsonEncode(row.toJson())}\n', flush: true);

      final deleted = await service.deleteMessages(<String>['m7']);
      expect(deleted, 1, reason: 'one logical message, not one per copy');
      expect(
        await service.messageHistoryPersistence.loadArchivedHistory(
          _conversationId,
        ),
        isEmpty,
      );
      // And it is gone from disk, not just hidden by the delete tombstone.
      expect(
        archive.existsSync() ? archive.readAsStringSync() : '',
        isNot(contains('deleted-by-the-user')),
      );
    }, skip: skipReason);
  });
}
