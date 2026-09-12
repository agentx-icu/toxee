import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/account_export/restore_transaction.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import 'test_support.dart';

// What this file pins, in one paragraph.
//
// The restore journal is a SINGLETON file, and it is the only copy of two
// preference families keyed by the FULL Tox ID — the blocked-peer list and the
// failed-message queue — as they were before a full-backup restore started
// overwriting them. Everything here guards that copy against the three ways it
// was reachable by an account that did not own it: a second restore
// overwriting an unresolved record, an account deletion clearing a record it
// had merely read a moment earlier, and a rollback that "put the queue back"
// while leaving a second, legacy-keyed copy of the ARCHIVE's queue on disk for
// the runtime to merge back in.
//
// The assertions are on what a user can observe afterwards — which messages
// are pending, which recovery record is still on disk — not on the store's
// bookkeeping, so a later refactor of how ownership is recorded cannot quietly
// retire the guarantee.

// Two 76-char Tox IDs whose FIRST 16 chars differ from their LAST 16. That is
// load-bearing twice over: the full-id-keyed families end with the last chars
// of the id while the generic account sweep matches the `_<first16>` suffix,
// and the failed-message queue's two key shapes are derived from the two ends
// of the id — a self-repeating test id would make them the same key and the
// legacy-key test below would pass for the wrong reason.
const _toxIdA =
    'AA11BB22CC33DD44EE55FF6677889900112233445566778899AABBCCDDEEFF010123456789AB';
const _toxIdB =
    'CC99DD88EE77FF66554433221100AABBCCDDEEFF001122334455667788990123FEDCBA987654';

// The snapshot a journal carries: the user's real blocked peers and real
// pending messages, captured before the restore overwrote them.
const _snapshotBlockedPeers = <String>['blocked-peer-one', 'blocked-peer-two'];
const _snapshotFailedQueue = '{"pending":"snapshotted-queue-payload"}';

// What the archive being rolled back carried. Deliberately different from the
// snapshot, so no assertion can pass just because the two look alike.
const _archiveFailedQueue = '{"pending":"archive-queue-payload"}';

// The base of both failed-message-queue key shapes. Spelled out because the key
// builders are private to `Prefs` and no public API writes the legacy shape —
// the archive-era code that created it is gone, but its keys are still on
// users' disks. If this literal ever stops matching `Prefs._kFailedMessagesBase`
// the legacy-key test goes green while guarding nothing, so it is asserted
// against a real write through `Prefs` before it is used.
const _failedMessagesBase = 'tencent_cloud_chat_failed_messages';

String _modernFailedMessagesKey(String toxId) =>
    '${_failedMessagesBase}_$toxId';

String _legacyFailedMessagesKey(String toxId) =>
    '${_failedMessagesBase}_${toxId.substring(0, 16)}';

void main() {
  group('restore journal ownership', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      FullBackupRestoreTestHooks.reset();
    });

    tearDown(() async {
      FullBackupRestoreTestHooks.reset();
      await env.dispose();
    });

    // Prevents: one user's unsent messages and blocked peers being destroyed by
    // a restore they have nothing to do with. A rollback that could not verify
    // its preference writes KEEPS its journal on purpose, so the next start can
    // retry putting the originals back — that record is at that moment the only
    // copy of them left. Letting the next restore overwrite it turns "we will
    // retry" into "they are gone", with no error and nothing left to retry
    // from.
    test('a second account cannot overwrite an unresolved restore record',
        () async {
      await _writeJournal(_toxIdA, state: RestoreTransactionState.staged);

      await expectLater(
        () => RestoreTransactionJournalStore.write(
          _journal(_toxIdB, state: RestoreTransactionState.staged),
        ),
        throwsA(isA<RestoreInFlightException>()),
      );

      // The refusal is worthless if it half-wrote first: the surviving record
      // must still be A's, and must still carry A's snapshot in full.
      final survivor = await RestoreTransactionJournalStore.read();
      expect(survivor, isNotNull);
      expect(survivor!.toxId, _toxIdA);
      expect(survivor.priorBlackListCaptured, isTrue);
      expect(survivor.priorBlackList, _snapshotBlockedPeers);
      expect(survivor.priorFailedQueueCaptured, isTrue);
      expect(survivor.priorFailedQueue, _snapshotFailedQueue);
    });

    // Prevents: the refusal above being over-broad and wedging the account it
    // is protecting. A restore advances its own journal through five states,
    // rewriting the same record each time; if "a record exists" were enough to
    // refuse, the owning restore could never record that it had committed —
    // and recovery would then roll back work that had actually landed, deleting
    // the profile and chat history it just published.
    test('the owning account may advance its own restore record', () async {
      await _writeJournal(_toxIdA, state: RestoreTransactionState.staged);

      await RestoreTransactionJournalStore.write(
        _journal(_toxIdA, state: RestoreTransactionState.accountDataCommitted),
      );

      final current = await RestoreTransactionJournalStore.read();
      expect(current!.toxId, _toxIdA);
      expect(current.state, RestoreTransactionState.accountDataCommitted);
      expect(current.priorFailedQueue, _snapshotFailedQueue);
    });

    // Prevents: an account deletion erasing a DIFFERENT account's recovery
    // record. The deletion of one account must not be able to reach the pending
    // restore of another — that record is the only copy of the other account's
    // pre-restore blocked peers and pending messages, and the user never
    // touched that account.
    test('clearing on behalf of one account leaves another account\'s record',
        () async {
      await _writeJournal(_toxIdA, state: RestoreTransactionState.staged);

      await RestoreTransactionJournalStore.clearIfOwnedBy(_toxIdB);

      final survivor = await RestoreTransactionJournalStore.read();
      expect(survivor, isNotNull);
      expect(survivor!.toxId, _toxIdA);
      expect(survivor.priorFailedQueue, _snapshotFailedQueue);

      // ...and the ownership check must not be so strict that nobody can ever
      // clean up: the owner itself still gets to drop its own record, or every
      // later start re-runs recovery against a restore that is already
      // resolved.
      await RestoreTransactionJournalStore.clearIfOwnedBy(_toxIdA);
      expect(await RestoreTransactionJournalStore.read(), isNull);
    });

    // Prevents: the same destruction arriving through the deletion flow rather
    // than the store. `discardForDeletedAccount` drops a journal outright
    // (deleting an account must not resurrect its data), so if it ever stopped
    // re-checking ownership it would silently throw away an unrelated
    // account's only recovery record.
    test('discarding for a deleted account spares an unrelated record',
        () async {
      await _writeJournal(_toxIdB, state: RestoreTransactionState.staged);

      await FullBackupRestoreTransaction.discardForDeletedAccount(_toxIdA);

      final survivor = await RestoreTransactionJournalStore.read();
      expect(survivor, isNotNull);
      expect(survivor!.toxId, _toxIdB);
      expect(survivor.priorBlackList, _snapshotBlockedPeers);
      expect(survivor.priorFailedQueue, _snapshotFailedQueue);
    });

    // Prevents: the interleaving that ownership-at-read cannot catch. A
    // deletion reads the journal, sees its own account and commits to dropping
    // it, then spends time deleting staging directories. If a restore for a
    // different account resolves that record and publishes its own in that
    // window, an unchecked clear at the end deletes the NEW record — the live
    // restore's only copy of a third party's blocked peers and pending
    // messages — while the deletion reports success.
    //
    // The window is reconstructed step by step rather than raced: the steps
    // below are exactly the deletion's read / other-party-publishes / clear
    // sequence, ordered deterministically so the test cannot pass or fail by
    // timing. What it asserts is that the final clear re-decides ownership
    // against the record actually on disk.
    test('a clear decided before another account published does not fire',
        () async {
      await _writeJournal(_toxIdA, state: RestoreTransactionState.staged);

      // 1. The deletion of A reads the record and concludes it owns it.
      final observed = await RestoreTransactionJournalStore.read();
      expect(observed!.toxId, _toxIdA);

      // 2. Meanwhile A's restore is resolved and B's restore publishes its own
      //    record into the same singleton slot.
      await RestoreTransactionJournalStore.clear();
      await RestoreTransactionJournalStore.write(
        _journal(_toxIdB, state: RestoreTransactionState.accountDataCommitted),
      );

      // 3. The deletion now acts on the decision it made in step 1.
      await RestoreTransactionJournalStore.clearIfOwnedBy(_toxIdA);

      // B's record must still be there, and still be a COMPLETE one — a
      // truncated or emptied record would leave recovery with a restore it
      // cannot finish and a snapshot it cannot put back.
      final survivor = await RestoreTransactionJournalStore.read();
      expect(survivor, isNotNull);
      expect(survivor!.toxId, _toxIdB);
      expect(survivor.state, RestoreTransactionState.accountDataCommitted);
      expect(survivor.priorBlackListCaptured, isTrue);
      expect(survivor.priorBlackList, _snapshotBlockedPeers);
      expect(survivor.priorFailedQueueCaptured, isTrue);
      expect(survivor.priorFailedQueue, _snapshotFailedQueue);
    });

    // Prevents: a rolled-back archive's messages coming back to life alongside
    // the user's own. The failed-message queue is stored under two key shapes,
    // and only one of them is written on the way in — so a restore that
    // imported a queue could leave an archive-created LEGACY copy that the
    // rollback's read-back never looks at, because it is satisfied by the
    // modern key it just rewrote. The user is left with their own pending
    // messages plus a stranger's, which the runtime merges and then tries to
    // send.
    test('rollback leaves no legacy-keyed copy of the archive queue behind',
        () async {
      final prefs = await SharedPreferences.getInstance();

      // The user's own pending messages, written the way the app writes them.
      await Prefs.importFailedMessageQueue(_toxIdA, _snapshotFailedQueue);
      // The key spelling this test depends on has to be the real one, or the
      // legacy assertion below is checking a key nothing ever uses.
      expect(
        prefs.getString(_modernFailedMessagesKey(_toxIdA)),
        _snapshotFailedQueue,
      );
      expect(_legacyFailedMessagesKey(_toxIdA),
          isNot(_modernFailedMessagesKey(_toxIdA)));

      // The restore overwrites the modern key with the archive's queue, and the
      // archive's own data also lands under the legacy shape. Written directly:
      // no public API writes that shape any more, but the on-disk state it
      // produces is still reachable and is what the rollback has to clean up.
      await Prefs.importFailedMessageQueue(_toxIdA, _archiveFailedQueue);
      await prefs.setString(
        _legacyFailedMessagesKey(_toxIdA),
        _archiveFailedQueue,
      );

      await _writeJournal(_toxIdA, state: RestoreTransactionState.staged);

      await AccountExportService.recoverPendingFullBackupRestore();

      await (await SharedPreferences.getInstance()).reload();

      // What the account's pending queue actually is now: the user's own, and
      // nothing else. `exportFailedMessageQueue` answers with the modern key
      // first, so it alone cannot tell the difference — the legacy key has to
      // be gone as well, or the runtime merges the archive's messages back in.
      expect(await Prefs.exportFailedMessageQueue(_toxIdA),
          _snapshotFailedQueue);
      expect(
        (await SharedPreferences.getInstance())
            .getString(_legacyFailedMessagesKey(_toxIdA)),
        isNull,
      );
      expect(await Prefs.getBlackList(_toxIdA), _snapshotBlockedPeers.toSet());
      // The rollback must have been able to verify its writes and let the
      // journal go; a kept journal means it decided it had FAILED, which is a
      // different bug wearing the same green assertions above.
      expect(await RestoreTransactionJournalStore.read(), isNull);
    });

    // Prevents: the test above passing for the wrong reason. If a rolled-back
    // restore stopped clearing the queue at all, the legacy key would still
    // have to disappear by some other route for that test to be green — but a
    // user who had NOTHING pending before the restore would then be left
    // retrying the archive's messages forever. An empty snapshot has to mean
    // an empty queue afterwards, under both key shapes.
    test('rollback with an empty snapshot leaves neither key shape behind',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await Prefs.importFailedMessageQueue(_toxIdA, _archiveFailedQueue);
      await prefs.setString(
        _legacyFailedMessagesKey(_toxIdA),
        _archiveFailedQueue,
      );

      await _writeJournal(
        _toxIdA,
        state: RestoreTransactionState.staged,
        priorFailedQueue: null,
        priorBlackList: const <String>[],
      );

      await AccountExportService.recoverPendingFullBackupRestore();

      await (await SharedPreferences.getInstance()).reload();

      expect(await Prefs.exportFailedMessageQueue(_toxIdA), isNull);
      expect(
        (await SharedPreferences.getInstance())
            .getString(_legacyFailedMessagesKey(_toxIdA)),
        isNull,
      );
      expect(
        (await SharedPreferences.getInstance())
            .getString(_modernFailedMessagesKey(_toxIdA)),
        isNull,
      );
      expect(await RestoreTransactionJournalStore.read(), isNull);
    });
  });
}

RestoreTransactionJournal _journal(
  String toxId, {
  required RestoreTransactionState state,
  Object? priorFailedQueue = _unset,
  List<String> priorBlackList = _snapshotBlockedPeers,
}) {
  // Deliberately non-existent: these tests are about who owns the RECORD, so
  // the rollback's directory work has nothing to find and nothing to do.
  final stem = p.join(
    Directory.systemTemp.path,
    'toxee_journal_ownership_${toxId.substring(0, 16)}',
  );
  return RestoreTransactionJournal(
    transactionId: 'journal-ownership-${toxId.substring(0, 8)}',
    toxId: toxId,
    state: state,
    profileStageDir: '${stem}_profile_stage',
    profileFinalDir: '${stem}_profile_final',
    accountDataStageDir: '${stem}_data_stage',
    accountDataFinalDir: '${stem}_data_final',
    hasProfile: false,
    priorBlackListCaptured: true,
    priorBlackList: priorBlackList,
    priorFailedQueueCaptured: true,
    priorFailedQueue: identical(priorFailedQueue, _unset)
        ? _snapshotFailedQueue
        : priorFailedQueue as String?,
  );
}

const Object _unset = Object();

/// Publish a journal for [toxId] the way the restore does — through the store,
/// so the file on disk is exactly the shape the code under test reads back.
Future<void> _writeJournal(
  String toxId, {
  required RestoreTransactionState state,
  Object? priorFailedQueue = _unset,
  List<String> priorBlackList = _snapshotBlockedPeers,
}) async {
  await RestoreTransactionJournalStore.write(
    _journal(
      toxId,
      state: state,
      priorFailedQueue: priorFailedQueue,
      priorBlackList: priorBlackList,
    ),
  );
  // The store is a singleton file; make sure the test is looking at the record
  // it thinks it wrote.
  final file = File(
    p.join(
      await AppPaths.applicationSupportPath,
      'account_export_restore_journal.json',
    ),
  );
  expect(
    (jsonDecode(await file.readAsString()) as Map<String, dynamic>)['toxId'],
    toxId,
  );
}
