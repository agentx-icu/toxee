// Regression test for X8 — BinaryReplacementHistoryHook generation guard.
//
// Static `_persistence` and `_selfId` in BinaryReplacementHistoryHook mean a
// logout+login sequence replaces them globally. Before the fix, an in-flight
// `saveMessage` from session A that crossed an await point past the re-init
// would land in session B's persistence under session B's selfId. The
// generation counter added by X8 captures the session at entry and aborts
// the write if it has changed.
//
// FFI dependency: `V2TimMessage`'s constructor reaches into
// `TIMManager.instance.getServerTime()`, which calls into the native SDK
// binding. The test is skipped when the tim2tox FFI library is not loadable
// (mirrors the pattern used in `tim2tox_delete_messages_test.dart`).
//
// What we assert:
//   * `initialize` bumps the generation counter.
//   * A message captured by session A whose `appendHistory` resolves after
//     session B's `initialize` is either written to session A's persistence
//     (latency was tiny enough that the await completed before the second
//     init landed) OR is silently dropped — but is **never** written to
//     session B's persistence.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/utils/binary_replacement_history_hook.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

bool _ffiAvailable() {
  try {
    // Route the SDK's native binding to libtim2tox_ffi (the binary-replacement
    // scheme toxee installs at startup). Without this, V2TimMessage's
    // constructor crashes trying to load `libdart_native_imsdk`.
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

V2TimMessage _textMessage({
  required String msgID,
  required String userID,
  required String sender,
  required String text,
}) {
  final msg = V2TimMessage(
    msgID: msgID,
    userID: userID,
    sender: sender,
    elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
  msg.textElem = V2TimTextElem(text: text);
  return msg;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('BinaryReplacementHistoryHook generation guard (X8)',
      skip: skipReason, () {
    late Directory tempRoot;
    late MessageHistoryPersistence persistenceA;
    late MessageHistoryPersistence persistenceB;

    const selfA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const selfB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const peer = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('hook_gen_');
      persistenceA = MessageHistoryPersistence(
          historyDirectory: p.join(tempRoot.path, 'a'));
      persistenceB = MessageHistoryPersistence(
          historyDirectory: p.join(tempRoot.path, 'b'));
    });

    tearDown(() async {
      try {
        persistenceA.dispose();
      } catch (_) {}
      try {
        persistenceB.dispose();
      } catch (_) {}
      try {
        await tempRoot.delete(recursive: true);
      } catch (_) {}
    });

    test('initialize bumps the generation counter', () {
      final before = BinaryReplacementHistoryHook.generation;
      BinaryReplacementHistoryHook.initialize(persistenceA, selfA);
      final after = BinaryReplacementHistoryHook.generation;
      expect(after, greaterThan(before));
    });

    test(
        'message captured by session A is never written to session B '
        'when initialize runs again between saveMessage entry and completion',
        () async {
      // Session A.
      BinaryReplacementHistoryHook.initialize(persistenceA, selfA);

      final m = _textMessage(
        msgID: 'genA_msg_1',
        userID: peer,
        sender: peer,
        text: 'sent under session A',
      );

      // Kick off the save but DON'T await yet. The first synchronous chunk
      // captures `_persistence` and `_selfId` from session A.
      final saveFuture = BinaryReplacementHistoryHook.saveMessage(m);

      // Re-init as session B before the debounced disk save completes.
      // This is the cross-session race the generation guard is designed to
      // catch.
      BinaryReplacementHistoryHook.initialize(persistenceB, selfB);

      // Drain the in-flight save plus any debounced timers on either
      // persistence so we don't shut the test down with pending writes.
      await saveFuture;
      await persistenceA.flushPendingSaves();
      await persistenceB.flushPendingSaves();

      final inA = persistenceA.getHistory(peer);
      final inB = persistenceB.getHistory(peer);

      // The invariant under test: NEVER write under session B.
      expect(
        inB.any((msg) => msg.msgID == 'genA_msg_1'),
        isFalse,
        reason:
            'message captured under session A must not land in session B',
      );

      // Acceptable outcomes: written to A (race lost — captured persistence
      // resolved before next init landed in saveMessage's check) OR dropped
      // (race won — generation guard tripped). Both protect the user.
      final landedInA = inA.any((msg) => msg.msgID == 'genA_msg_1');
      // Sanity: even if dropped, no exception leaked out.
      expect(landedInA || inA.isEmpty, isTrue);
    });

    // #17: a message buffered while session A's selfId was still unknown
    // must never be replayed into session B after a re-initialize.
    test('re-initialize for a new session drops the selfId buffer', () async {
      await BinaryReplacementHistoryHook.uninstallStandalone();
      BinaryReplacementHistoryHook.initialize(persistenceA, '');
      await BinaryReplacementHistoryHook.saveMessage(_textMessage(
        msgID: 'buffered_under_a',
        userID: peer,
        sender: peer,
        text: 'arrived before A knew its selfId',
      ));
      expect(BinaryReplacementHistoryHook.pendingSelfIdBufferLength, 1);

      BinaryReplacementHistoryHook.initialize(persistenceB, '');
      expect(BinaryReplacementHistoryHook.pendingSelfIdBufferLength, 0);
      BinaryReplacementHistoryHook.updateSelfId(selfB);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await persistenceB.flushPendingSaves();
      expect(persistenceB.getHistory(peer), isEmpty);
      expect(persistenceA.getHistory(peer), isEmpty);
      await BinaryReplacementHistoryHook.uninstallStandalone();
    });

    test('a same-session re-initialize keeps its own buffered messages',
        () async {
      await BinaryReplacementHistoryHook.uninstallStandalone();
      BinaryReplacementHistoryHook.initialize(persistenceA, '');
      await BinaryReplacementHistoryHook.saveMessage(_textMessage(
        msgID: 'buffered_same_session',
        userID: peer,
        sender: peer,
        text: 'still session A',
      ));
      BinaryReplacementHistoryHook.initialize(persistenceA, '');
      BinaryReplacementHistoryHook.updateSelfId(selfA);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await persistenceA.flushPendingSaves();
      expect(persistenceA.getHistory(peer).map((m) => m.msgID),
          ['buffered_same_session']);
      await BinaryReplacementHistoryHook.uninstallStandalone();
    });

    // #18: callbacks capturing the previous session's services must not
    // survive a re-initialize for another session.
    test('re-initialize for a new session drops the previous callbacks',
        () async {
      await BinaryReplacementHistoryHook.uninstallStandalone();
      Future<void> applierA({
        required String text,
        required String fromUserId,
        String? groupId,
        bool isSelf = false,
      }) async {}
      Future<void> applierB({
        required String text,
        required String fromUserId,
        String? groupId,
        bool isSelf = false,
      }) async {}

      BinaryReplacementHistoryHook.applyInboundControlSignal = applierA;
      BinaryReplacementHistoryHook.initialize(persistenceA, selfA);
      BinaryReplacementHistoryHook.isBlockedPredicate = (_) => true;
      BinaryReplacementHistoryHook.onInboundMessagePersisted = (_, __) {};

      // Session B without an uninstall, and no applier installed for it.
      BinaryReplacementHistoryHook.initialize(persistenceB, selfB);
      expect(BinaryReplacementHistoryHook.isBlockedPredicate, isNull);
      expect(BinaryReplacementHistoryHook.onInboundMessagePersisted, isNull);
      expect(BinaryReplacementHistoryHook.applyInboundControlSignal, isNull);

      // Session C whose platform installed its applier first (the product
      // order): that applier is kept.
      BinaryReplacementHistoryHook.applyInboundControlSignal = applierB;
      BinaryReplacementHistoryHook.initialize(persistenceA, selfA);
      expect(BinaryReplacementHistoryHook.applyInboundControlSignal,
          equals(applierB));
      await BinaryReplacementHistoryHook.uninstallStandalone();
    });
  });
}
