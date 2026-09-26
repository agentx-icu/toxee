// Regression test for X10 — backup file cleanup after a successful save.
//
// Before the fix, `MessageHistoryPersistence.saveHistory` left the `.bak`
// safety-net file behind after every successful atomic rename. The comment
// claimed "we keep backups and clean them up on next successful write" but
// the actual cleanup was commented out, so `.bak` files accumulated on disk
// until `cleanupTempFiles` swept them (only files older than 7 days).
//
// The fix deletes the `.bak` after `tempFile.rename` succeeds and the
// completer settles, wrapped in its own try/catch so a delete failure can
// never turn a successful save into a failed one.
//
// This test runs entirely on the Dart VM and uses a temp directory as the
// persistence root, so it doesn't depend on `path_provider` or the FFI lib.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

ChatMessage _msg(int i) => ChatMessage(
      text: 'msg $i',
      fromUserId: 'peer',
      isSelf: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(100 + i),
      msgID: 'm_$i',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessageHistoryPersistence backup cleanup (X10)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mhp_bak_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('second successful save deletes the .bak from the first save',
        () async {
      final persistence =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      const id = 'peer_cleanup';

      // First save: writes the .json from scratch. No .bak yet because the
      // file didn't exist when this save started.
      await persistence.saveHistory(id, [_msg(0)]);

      // Second save: creates a .bak (copy of existing .json), writes new
      // tmp, renames over .json. Before X10, the .bak survived; after X10,
      // it's removed once the rename + completer succeed.
      await persistence.saveHistory(id, [_msg(0), _msg(1)]);

      // The post-complete delete runs off the save's completer. Poll for it
      // with a generous deadline instead of sleeping a fixed 20ms: if it
      // never runs, the poll simply expires and the expectation below still
      // reports the surviving `.bak`.
      List<String> listing() =>
          tempDir.listSync().map((e) => p.basename(e.path)).toList();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (listing().any((n) => n.endsWith('.bak')) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final entries = listing();
      final bakFiles = entries.where((n) => n.endsWith('.bak')).toList();
      expect(
        bakFiles,
        isEmpty,
        reason:
            'no `.bak` files should remain after a successful save (X10); '
            'directory listing: $entries',
      );

      // Sanity: the final history file is intact.
      final jsonFiles = entries.where((n) => n.endsWith('.json')).toList();
      expect(jsonFiles.length, 1);

      await persistence.dispose();
    });
  });
}
