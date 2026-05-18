// Tests for the Tier-2 performance fixes in
// `third_party/tim2tox/dart/lib/utils/message_history_persistence.dart`.
//
//   * P3 — `loadAllHistories` runs file loads in parallel batches and still
//     surfaces every conversation it finds on disk.
//   * P2 — `appendHistory` debounces successive disk writes inside a 200ms
//     window but still persists every message to disk eventually.
//
// These tests use a temp directory as the persistence root so they exercise
// the real file-system code path without depending on any platform plugins
// (no `path_provider`, no FFI). All work happens on the Dart VM via
// `flutter_test`'s `TestWidgetsFlutterBinding`.

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
}) {
  return ChatMessage(
    text: text,
    fromUserId: fromUserId,
    isSelf: false,
    timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
    msgID: msgID ?? '${tsMs}_$fromUserId',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessageHistoryPersistence — P3 parallel loadAllHistories', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mhp_p3_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('loads N conversations and returns them all', () async {
      // Seed 40 conversation files (> the 16-batch boundary so we exercise
      // multiple parallel batches).
      const conversationCount = 40;
      for (var i = 0; i < conversationCount; i++) {
        final id = 'peer_$i';
        final file = File('${tempDir.path}/$id.json');
        final data = {
          'conversationId': id,
          'version': 1,
          'lastViewTimestamp': 0,
          'messages': [
            _msg(
              fromUserId: id,
              text: 'hello from $id',
              tsMs: 1000 + i,
              msgID: 'm_$i',
            ).toJson(),
          ],
        };
        await file.writeAsString(jsonEncode(data));
      }

      final persistence =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      final result = await persistence.loadAllHistories();
      // loadHistory issues an unawaited save-back when pending messages get
      // flipped to failed; allow those to complete before tearDown so the
      // tmp-file rename doesn't race the recursive directory delete.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(result.length, conversationCount);
      for (var i = 0; i < conversationCount; i++) {
        final id = 'peer_$i';
        final loaded = result[id];
        expect(loaded, isNotNull, reason: 'missing $id');
        expect(loaded!.length, 1);
        expect(loaded.first.text, 'hello from $id');
      }
    });

    test('returns empty map when directory is empty', () async {
      final persistence =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      final result = await persistence.loadAllHistories();
      expect(result, isEmpty);
    });

    test('per-file errors do not abort the rest of the load', () async {
      // Two good files surrounding one corrupt file.
      await File('${tempDir.path}/good_a.json').writeAsString(jsonEncode({
        'conversationId': 'good_a',
        'version': 1,
        'lastViewTimestamp': 0,
        'messages': [
          _msg(fromUserId: 'good_a', text: 'a', tsMs: 1).toJson(),
        ],
      }));
      await File('${tempDir.path}/broken.json')
          .writeAsString('not valid json {{{');
      await File('${tempDir.path}/good_b.json').writeAsString(jsonEncode({
        'conversationId': 'good_b',
        'version': 1,
        'lastViewTimestamp': 0,
        'messages': [
          _msg(fromUserId: 'good_b', text: 'b', tsMs: 2).toJson(),
        ],
      }));

      final persistence =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      final result = await persistence.loadAllHistories();
      // Wait for unawaited save-back from loadHistory to settle so the tmp
      // rename doesn't race the recursive directory delete in tearDown.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The good files come back; the broken one is silently skipped.
      expect(result.containsKey('good_a'), isTrue);
      expect(result.containsKey('good_b'), isTrue);
    });
  });

  group('MessageHistoryPersistence — P2 debounced appendHistory', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mhp_p2_');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    Future<List<ChatMessage>> _readFromDisk(
      MessageHistoryPersistence persistence,
      String id,
    ) async {
      // Spin up a fresh instance so we read the on-disk state rather than
      // the in-memory cache the producer holds. We don't await any pending
      // saves on the consumer side — that's what we're trying to verify.
      final reader = MessageHistoryPersistence(historyDirectory: tempDir.path);
      return reader.loadHistory(id);
    }

    test(
        '10 rapid appends to the same conversation coalesce but every '
        'message lands on disk after the debounce window',
        () async {
      final persistence =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      const id = 'rapid_peer';

      // Fire 10 appends back-to-back. None await; this is the realistic
      // "hot sender" / "image batch" pattern.
      final futures = <Future<void>>[];
      for (var i = 0; i < 10; i++) {
        futures.add(persistence.appendHistory(
          id,
          _msg(
            fromUserId: id,
            text: 'msg $i',
            tsMs: 100 + i,
            msgID: 'msgid_$i',
          ),
        ));
      }

      // Give the 200ms debounce timer a chance to fire and the resulting
      // saveHistory to complete. 300ms is comfortably above the window.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await Future.wait(futures);

      // Force-flush belt-and-braces in case the test host was slow.
      await persistence.flushPendingSaves();

      final loaded = await _readFromDisk(persistence, id);
      expect(loaded.length, 10);
      for (var i = 0; i < 10; i++) {
        expect(
          loaded.any((m) => m.msgID == 'msgid_$i' && m.text == 'msg $i'),
          isTrue,
          reason: 'message msgid_$i missing from disk',
        );
      }
      persistence.dispose();
    });

    test('flushPendingSaves forces an immediate write', () async {
      final persistence =
          MessageHistoryPersistence(historyDirectory: tempDir.path);
      const id = 'flush_peer';

      // Append one message and immediately flush — without flushPendingSaves
      // the debounced write would still be sitting in a 200ms timer.
      unawaited(persistence.appendHistory(
        id,
        _msg(fromUserId: id, text: 'urgent', tsMs: 1, msgID: 'urgent_id'),
      ));

      await persistence.flushPendingSaves();

      final loaded = await _readFromDisk(persistence, id);
      expect(loaded.length, 1);
      expect(loaded.first.text, 'urgent');
      persistence.dispose();
    });
  });
}
