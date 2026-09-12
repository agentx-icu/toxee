import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:toxee/util/account_export/restore_transaction.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import 'test_support.dart';

// What this file pins, in one paragraph.
//
// A full-backup restore journals a SNAPSHOT of the two FULL-id-keyed preference
// families — the blocked-peer list and the failed-message queue — taken before
// its first write, so that a rollback can put the user's own values back. A
// rollback whose preference writes do not read back KEEPS that journal on
// purpose, so the next start retries; and because that retained record is then
// the only surviving copy of the originals, the store refuses to overwrite a
// record carrying a different transaction id.
//
// That fence, on its own, is a trap with no exit. A rollback that can NEVER
// verify keeps the journal forever, every later restore is refused, and the
// same rollback has already removed the account row — so the account cannot
// even be selected for the deletion path that discards journals. The way out is
// `admitCarryingForward`: the new transaction is admitted and the retained
// snapshot is CARRIED INTO its record in one atomic write, because those
// retained values predate both transactions and are the ones the user actually
// wants back. A record belonging to a DIFFERENT account is still refused.
//
// The end-to-end test at the bottom is the one that matters: it drives two real
// restores with a real, unverifiable rollback in between, and asserts that the
// second restore's rollback hands back the values that were on disk before the
// FIRST restore ever ran.

// A 76-char Tox ID whose FIRST 16 chars differ from its LAST 16. Load-bearing:
// `black_list_<fullToxId>` and the modern failed-message key end with the LAST
// chars of the id while the generic account sweep matches the `_<first16>`
// suffix. A self-repeating id would be swept by accident and the carried
// snapshot would look preserved for the wrong reason.
const _toxId =
    'AA11BB22CC33DD44EE55FF6677889900112233445566778899AABBCCDDEEFF010123456789AB';

// A second account, used only to prove one account's restore cannot consume
// another's retained snapshot.
const _otherToxId =
    'CC99DD88EE77FF66554433221100AABBCCDDEEFF001122334455667788990123FEDCBA987654';

const _nickname = 'Carry Forward';

// The values that were on disk BEFORE any restore started: the user's real
// blocked peers and real pending messages. Getting these back is the whole
// point of the snapshot.
const _priorBlockedPeers = <String>{'prior-peer-one', 'prior-peer-two'};
const _priorFailedQueue = '{"pending":"prior-queue-payload"}';

// What the archive carries, and what a SECOND transaction would capture for
// itself after the first restore had already overwritten the originals.
// Deliberately different from the prior values, so nothing can pass by looking
// alike.
const _archiveBlockedPeers = <String>['archive-peer'];
const _archiveFailedQueue = '{"pending":"archive-queue-payload"}';

// `SharedPreferences` prefixes every key it writes to the platform store. The
// store-level keys below are what the refusing store matches on; they are
// asserted to exist after a real write through `Prefs`, so a rename of either
// key builder makes this file go red instead of quietly refusing nothing.
const _prefsKeyPrefix = 'flutter.';

String _blackListStoreKey(String toxId) => '${_prefsKeyPrefix}black_list_$toxId';

String _failedQueueStoreKey(String toxId) =>
    '${_prefsKeyPrefix}tencent_cloud_chat_failed_messages_$toxId';

void main() {
  group('restore journal carry-forward', () {
    late AccountExportTestEnv env;
    late SharedPreferencesStorePlatform realStore;
    late _WriteRefusingPrefsStore refusingStore;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      realStore = SharedPreferencesStorePlatform.instance;
      refusingStore = _WriteRefusingPrefsStore(realStore);
      SharedPreferencesStorePlatform.instance = refusingStore;
      FullBackupRestoreTestHooks.reset();
      FullBackupRestoreTestHooks.profileIdentityExtractor =
          (Uint8List profileBytes) => _toxId;
    });

    tearDown(() async {
      FullBackupRestoreTestHooks.reset();
      SharedPreferencesStorePlatform.instance = realStore;
      await env.dispose();
    });

    // Prevents: the user's real blocked peers and real pending messages being
    // replaced by the wreckage of the restore that destroyed them. Once a
    // rollback has failed to put the originals back, the on-disk values are the
    // ARCHIVE's, so the next transaction's own capture snapshots those. If the
    // retained snapshot were not carried into the new record, the new
    // transaction's rollback would faithfully "restore" the archive's values and
    // the originals would be gone with no error anywhere.
    test('a retained record for the same account hands its snapshot to the '
        'new transaction', () async {
      await RestoreTransactionJournalStore.write(
        _journal(
          _toxId,
          transactionId: 'retained-transaction',
          priorBlackList: _priorBlockedPeers.toList(),
          priorFailedQueue: _priorFailedQueue,
        ),
      );

      final admitted = await RestoreTransactionJournalStore.admitCarryingForward(
        _journal(
          _toxId,
          transactionId: 'new-transaction',
          priorBlackList: _archiveBlockedPeers,
          priorFailedQueue: _archiveFailedQueue,
        ),
      );

      // The new transaction owns the record...
      expect(admitted.transactionId, 'new-transaction');
      // ...but not the snapshot: the values that predate BOTH transactions win.
      expect(admitted.priorBlackListCaptured, isTrue);
      expect(admitted.priorBlackList, _priorBlockedPeers.toList());
      expect(admitted.priorFailedQueueCaptured, isTrue);
      expect(admitted.priorFailedQueue, _priorFailedQueue);

      // And it is on disk that way — an in-memory carry that never lands is no
      // use to the next process, which is the only reader that matters.
      final onDisk = await RestoreTransactionJournalStore.read();
      expect(onDisk!.transactionId, 'new-transaction');
      expect(onDisk.priorBlackList, _priorBlockedPeers.toList());
      expect(onDisk.priorFailedQueue, _priorFailedQueue);
    });

    // Prevents: one account's restore consuming another account's recovery
    // data. Carrying a snapshot forward is only defensible between transactions
    // for the SAME account, where the retained values are that account's own
    // originals. Another account's snapshot is neither ours to adopt (it names
    // peers and messages of an identity we are not restoring) nor ours to
    // discard (it is that account's only copy).
    test('a retained record for another account is refused and left intact',
        () async {
      await RestoreTransactionJournalStore.write(
        _journal(
          _otherToxId,
          transactionId: 'other-account-transaction',
          priorBlackList: _priorBlockedPeers.toList(),
          priorFailedQueue: _priorFailedQueue,
        ),
      );

      await expectLater(
        () => RestoreTransactionJournalStore.admitCarryingForward(
          _journal(
            _toxId,
            transactionId: 'new-transaction',
            priorBlackList: _archiveBlockedPeers,
            priorFailedQueue: _archiveFailedQueue,
          ),
        ),
        throwsA(isA<RestoreInFlightException>()),
      );

      // A refusal that half-wrote first would be worse than no refusal: the
      // survivor has to be the other account's record, complete.
      final survivor = await RestoreTransactionJournalStore.read();
      expect(survivor, isNotNull);
      expect(survivor!.toxId, _otherToxId);
      expect(survivor.transactionId, 'other-account-transaction');
      expect(survivor.priorBlackList, _priorBlockedPeers.toList());
      expect(survivor.priorFailedQueue, _priorFailedQueue);
    });

    // Prevents: the carry-forward path corrupting the ordinary restore. Almost
    // every restore starts with no journal at all, and that record must describe
    // what THIS transaction found on disk. A carry-forward that invented or
    // dropped values here would misdescribe the starting state of every normal
    // import, and its rollback would write those wrong values back.
    test('with no record on disk the new transaction is written unchanged',
        () async {
      expect(await RestoreTransactionJournalStore.read(), isNull);

      final admitted = await RestoreTransactionJournalStore.admitCarryingForward(
        _journal(
          _toxId,
          transactionId: 'new-transaction',
          priorBlackList: _priorBlockedPeers.toList(),
          priorFailedQueue: _priorFailedQueue,
        ),
      );

      expect(admitted.transactionId, 'new-transaction');
      expect(admitted.priorBlackList, _priorBlockedPeers.toList());
      expect(admitted.priorFailedQueue, _priorFailedQueue);

      final onDisk = await RestoreTransactionJournalStore.read();
      expect(onDisk!.toxId, _toxId);
      expect(onDisk.transactionId, 'new-transaction');
      expect(onDisk.priorBlackListCaptured, isTrue);
      expect(onDisk.priorBlackList, _priorBlockedPeers.toList());
      expect(onDisk.priorFailedQueueCaptured, isTrue);
      expect(onDisk.priorFailedQueue, _priorFailedQueue);
    });

    // Prevents: "we captured nothing" being carried forward as though it meant
    // "there was nothing there". A journal written by a build that predates the
    // capture (or by a transaction whose reads failed) says only that ownership
    // is UNKNOWN. Copying its empty values over a good capture would tell the
    // new transaction's rollback that the account started with no blocked peers
    // and no pending messages — so the rollback would clear two families it was
    // supposed to put back, turning an upgrade into data loss.
    test('a retained record that captured nothing does not overwrite the new '
        'capture', () async {
      await _writeLegacyJournalFile(_legacyJournalJson(_toxId));
      // The premise: this record admits to knowing nothing, which is exactly
      // what makes copying it dangerous.
      final legacy = await RestoreTransactionJournalStore.read();
      expect(legacy!.priorBlackListCaptured, isFalse);
      expect(legacy.priorFailedQueueCaptured, isFalse);

      final admitted = await RestoreTransactionJournalStore.admitCarryingForward(
        _journal(
          _toxId,
          transactionId: 'new-transaction',
          priorBlackList: _priorBlockedPeers.toList(),
          priorFailedQueue: _priorFailedQueue,
        ),
      );

      expect(admitted.priorBlackListCaptured, isTrue);
      expect(admitted.priorBlackList, _priorBlockedPeers.toList());
      expect(admitted.priorFailedQueueCaptured, isTrue);
      expect(admitted.priorFailedQueue, _priorFailedQueue);

      final onDisk = await RestoreTransactionJournalStore.read();
      expect(onDisk!.priorBlackListCaptured, isTrue);
      expect(onDisk.priorBlackList, _priorBlockedPeers.toList());
      expect(onDisk.priorFailedQueueCaptured, isTrue);
      expect(onDisk.priorFailedQueue, _priorFailedQueue);
    });

    // The next two are the precondition of the end-to-end test below, pinned one
    // family at a time.
    //
    // Prevents: half of the rollback's verification being dropped in a refactor.
    // `restorePriorFullIdPrefs` compares TWO independently written families
    // against a reloaded store, and either mismatch alone has to keep the
    // journal. If the block-list comparison went away, a rollback whose block
    // list never landed would report success, the journal would be cleared, and
    // the only copy of the user's blocked peers would go with it — silently,
    // because the value in the `SharedPreferences` cache still looks right.
    // (The end-to-end test refuses both families at once, so it cannot tell
    // which comparison is doing the work; these two can.)
    test('a rollback whose block-list write alone does not land keeps the '
        'journal', () async {
      await _seedPriorFullIdPrefs();
      final zipPath = await _writeBackup(env);
      FullBackupRestoreTestHooks.crashAt =
          FullBackupRestoreFailurePoint.afterScopedPrefsApply;

      await expectLater(
        () => AccountExportService.importFullBackup(filePath: zipPath),
        throwsA(isA<FullBackupRestoreCrashSimulation>()),
      );

      refusingStore.refuseWritesTo(<String>{_blackListStoreKey(_toxId)});
      await AccountExportService.recoverPendingFullBackupRestore();
      await (await SharedPreferences.getInstance()).reload();

      // Exactly one family failed to land: the queue came back, the block list
      // is still the archive's. So only the block-list comparison can be the
      // reason the rollback reports failure.
      expect(await Prefs.exportFailedMessageQueue(_toxId), _priorFailedQueue);
      expect(await Prefs.getBlackList(_toxId), _archiveBlockedPeers.toSet());

      final retained = await RestoreTransactionJournalStore.read();
      expect(retained, isNotNull,
          reason: 'the block list never landed, so the next start must still '
              'have a record to retry from');
      expect(retained!.priorBlackList.toSet(), _priorBlockedPeers);
      expect(retained.priorFailedQueue, _priorFailedQueue);
    });

    // Prevents: the same loss through the other family. The queue's read-back is
    // the only check that covers it — `clearFailedMessageQueue`'s result speaks
    // for the removals, not for the value written back — so dropping this
    // comparison would clear the journal while the user's pending messages were
    // never rewritten, and they exist nowhere else at that moment.
    test('a rollback whose queue write alone does not land keeps the journal',
        () async {
      await _seedPriorFullIdPrefs();
      final zipPath = await _writeBackup(env);
      FullBackupRestoreTestHooks.crashAt =
          FullBackupRestoreFailurePoint.afterScopedPrefsApply;

      await expectLater(
        () => AccountExportService.importFullBackup(filePath: zipPath),
        throwsA(isA<FullBackupRestoreCrashSimulation>()),
      );

      refusingStore.refuseWritesTo(<String>{_failedQueueStoreKey(_toxId)});
      await AccountExportService.recoverPendingFullBackupRestore();
      await (await SharedPreferences.getInstance()).reload();

      // Mirror image: the block list came back, the queue was removed and could
      // not be rewritten, so only the queue comparison can fail the rollback.
      expect(await Prefs.getBlackList(_toxId), _priorBlockedPeers);
      expect(await Prefs.exportFailedMessageQueue(_toxId), isNull);

      final retained = await RestoreTransactionJournalStore.read();
      expect(retained, isNotNull,
          reason: 'the queue never landed, so the next start must still have a '
              'record to retry from');
      expect(retained!.priorFailedQueue, _priorFailedQueue);
      expect(retained.priorBlackList.toSet(), _priorBlockedPeers);
    });

    // Prevents: the wedge, and the data loss hiding behind it. This is the whole
    // chain on the real code path, with no hand-written journal anywhere.
    //
    // A user with blocked peers and pending messages imports a backup; it fails;
    // the rollback's preference writes do not read back, so it keeps the journal
    // for a retry it can never win — and it has already removed the account row,
    // so the account cannot be deleted to clear the journal either. Without
    // carry-forward, EVERY later restore of that account is refused
    // (`RestoreInFlightException`) and the user is locked out for good. With a
    // carry-forward that took the new transaction's own capture instead of the
    // retained one, the restore is admitted but its rollback hands back the
    // ARCHIVE's blocked peers and an empty queue — the wreckage of the first
    // restore — and the originals are gone silently.
    //
    // So: two real restores, and the second one's rollback must produce the
    // values that were on disk before the first restore ever ran.
    test('a second restore is admitted and its rollback returns the '
        'pre-first-restore values', () async {
      await _seedPriorFullIdPrefs();
      final zipPath = await _writeBackup(env);
      FullBackupRestoreTestHooks.crashAt =
          FullBackupRestoreFailurePoint.afterScopedPrefsApply;

      // 1. The first restore overwrites both families with the archive's values
      //    and then fails.
      await expectLater(
        () => AccountExportService.importFullBackup(filePath: zipPath),
        throwsA(isA<FullBackupRestoreCrashSimulation>()),
      );
      expect(await Prefs.getBlackList(_toxId), _archiveBlockedPeers.toSet());
      expect(await Prefs.exportFailedMessageQueue(_toxId), _archiveFailedQueue);

      // 2. The rollback runs while the preference store refuses to persist the
      //    two full-id-keyed families, which is the failure the verification in
      //    `restorePriorFullIdPrefs` exists to catch: the write is accepted by
      //    the in-memory cache, never lands, and no caller is told.
      refusingStore.refuseWritesTo(<String>{
        _blackListStoreKey(_toxId),
        _failedQueueStoreKey(_toxId),
      });
      await AccountExportService.recoverPendingFullBackupRestore();
      await (await SharedPreferences.getInstance()).reload();

      // The rollback could not put the originals back — the block list is still
      // the archive's and the queue is gone entirely. The retained journal is at
      // this moment the ONLY copy of what the user had.
      expect(await Prefs.getBlackList(_toxId), _archiveBlockedPeers.toSet());
      expect(await Prefs.exportFailedMessageQueue(_toxId), isNull);
      final retained = await RestoreTransactionJournalStore.read();
      expect(retained, isNotNull,
          reason: 'a rollback that could not verify must keep its journal');
      expect(retained!.priorBlackList.toSet(), _priorBlockedPeers);
      expect(retained.priorFailedQueue, _priorFailedQueue);

      // 3. The user tries again. Refusals are still in force, so the recovery
      //    at the head of this restore fails to verify exactly as before and the
      //    retained record is still on disk when the new transaction asks to be
      //    admitted. Reaching the crash point proves it WAS admitted; a
      //    `RestoreInFlightException` here is the permanent lockout.
      await expectLater(
        () => AccountExportService.importFullBackup(filePath: zipPath),
        throwsA(isA<FullBackupRestoreCrashSimulation>()),
      );

      final carried = await RestoreTransactionJournalStore.read();
      expect(carried, isNotNull);
      expect(carried!.transactionId, isNot(retained.transactionId),
          reason: 'the second transaction owns the record now');
      expect(carried.priorBlackList.toSet(), _priorBlockedPeers,
          reason: 'the second transaction captured the archive values it found; '
              'the record must hold the originals instead');
      expect(carried.priorFailedQueue, _priorFailedQueue);

      // 4. The store accepts writes again, and the second restore rolls back.
      refusingStore.refuseWritesTo(const <String>{});
      await AccountExportService.recoverPendingFullBackupRestore();
      await (await SharedPreferences.getInstance()).reload();

      // What the user is left with: their own blocked peers and their own
      // pending messages, from before the first import.
      expect(await Prefs.getBlackList(_toxId), _priorBlockedPeers);
      expect(await Prefs.exportFailedMessageQueue(_toxId), _priorFailedQueue);
      // And the journal is finally released; still holding it would mean the
      // rollback believed it had failed again, which is a different bug wearing
      // the same green assertions above.
      expect(await RestoreTransactionJournalStore.read(), isNull);
    });
  });
}

/// A preferences store that can be told to DROP writes to specific keys.
///
/// It models the failure `restorePriorFullIdPrefs` verifies against: the
/// platform store does not accept the write, `SharedPreferences` has already
/// updated its own cache, and neither `setBlackList` nor
/// `importFailedMessageQueue` passes a refusal back to the caller. Only writes
/// are dropped — removals and reads go to the real store — so everything the
/// rollback does apart from putting these two families back behaves normally.
class _WriteRefusingPrefsStore extends SharedPreferencesStorePlatform {
  _WriteRefusingPrefsStore(this._inner);

  final SharedPreferencesStorePlatform _inner;
  Set<String> _refused = const <String>{};

  void refuseWritesTo(Set<String> storeKeys) {
    _refused = storeKeys;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (_refused.contains(key)) return false;
    return _inner.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) => _inner.remove(key);

  @override
  Future<bool> clear() => _inner.clear();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _inner.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAll() => _inner.getAll();

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) =>
      _inner.getAllWithParameters(parameters);
}

RestoreTransactionJournal _journal(
  String toxId, {
  required String transactionId,
  required List<String> priorBlackList,
  required String? priorFailedQueue,
}) {
  // Deliberately non-existent: these cases are about which record and which
  // snapshot survive, so there is no directory work to do.
  final stem = p.join(
    Directory.systemTemp.path,
    'toxee_carry_forward_${toxId.substring(0, 16)}',
  );
  return RestoreTransactionJournal(
    transactionId: transactionId,
    toxId: toxId,
    state: RestoreTransactionState.staged,
    profileStageDir: '${stem}_profile_stage',
    profileFinalDir: '${stem}_profile_final',
    accountDataStageDir: '${stem}_data_stage',
    accountDataFinalDir: '${stem}_data_final',
    hasProfile: false,
    priorBlackListCaptured: true,
    priorBlackList: priorBlackList,
    priorFailedQueueCaptured: true,
    priorFailedQueue: priorFailedQueue,
  );
}

/// The on-disk shape of a journal written before the capture fields existed.
/// Built as raw JSON on purpose: going through the store would serialize
/// today's fields and the "captured nothing" case could not be expressed.
Map<String, dynamic> _legacyJournalJson(String toxId) => <String, dynamic>{
      'version': 1,
      'transactionId': 'legacy-transaction',
      'toxId': toxId,
      'state': RestoreTransactionState.staged.name,
      'profileStageDir': '/nonexistent/profile_stage',
      'profileFinalDir': '/nonexistent/profile_final',
      'accountDataStageDir': '/nonexistent/data_stage',
      'accountDataFinalDir': '/nonexistent/data_final',
      'hasProfile': false,
    };

Future<void> _writeLegacyJournalFile(Map<String, dynamic> payload) async {
  final root = await AppPaths.applicationSupportPath;
  final file = File(p.join(root, 'account_export_restore_journal.json'));
  await file.writeAsString(jsonEncode(payload), flush: true);
}

/// Put a block list and a pending-message queue on disk with no registry row and
/// no account directories — the shape that passes `_preflight`, and the state
/// whose only surviving copy ends up inside the journal.
Future<void> _seedPriorFullIdPrefs() async {
  await Prefs.setBlackList(_priorBlockedPeers, _toxId);
  await Prefs.importFailedMessageQueue(_toxId, _priorFailedQueue);
  expect(await Prefs.getBlackList(_toxId), _priorBlockedPeers);
  expect(await Prefs.exportFailedMessageQueue(_toxId), _priorFailedQueue);
  // Both families must be invisible to the scoped sweep, or the restore would
  // be rejected at pre-flight and none of this could happen.
  expect(await Prefs.exportScopedPrefsForAccount(_toxId), isEmpty);
  // The keys the refusing store matches on have to be the ones `Prefs` actually
  // wrote. If either builder is renamed, the refusal would silently stop
  // refusing and the end-to-end test would pass while exercising nothing.
  final stored = await SharedPreferencesStorePlatform.instance.getAll();
  expect(stored.keys, contains(_blackListStoreKey(_toxId)));
  expect(stored.keys, contains(_failedQueueStoreKey(_toxId)));
}

Future<String> _writeBackup(AccountExportTestEnv env) async {
  final archive = Archive();
  final metadata = <String, dynamic>{
    'formatVersion': 1,
    'toxId': _toxId,
    'nickname': _nickname,
    'statusMessage': '',
    'exportDate': DateTime.now().toIso8601String(),
    'scopedPrefs': <String, dynamic>{
      'pinned_peers': <String>['peer-a'],
    },
    'blockedPeers': _archiveBlockedPeers,
    'failedMessageQueue': _archiveFailedQueue,
  };
  final metadataBytes = utf8.encode(jsonEncode(metadata));
  archive.addFile(
    ArchiveFile(
      'metadata.json',
      metadataBytes.length,
      Uint8List.fromList(metadataBytes),
    ),
  );
  final profileBytes = utf8.encode('profile-$_toxId');
  archive.addFile(
    ArchiveFile(
      'tox_profile.tox',
      profileBytes.length,
      Uint8List.fromList(profileBytes),
    ),
  );
  final historyBytes = utf8.encode('{"message":"carry-forward-history"}');
  archive.addFile(
    ArchiveFile(
      'chat_history/conversation.json',
      historyBytes.length,
      Uint8List.fromList(historyBytes),
    ),
  );
  final zipPath = p.join(env.extras, 'carry_forward.zip');
  await File(zipPath).writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return zipPath;
}
