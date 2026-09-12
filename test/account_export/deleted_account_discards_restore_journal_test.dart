import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/account_deletion.dart';
import 'package:toxee/util/account_export/restore_transaction.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import 'test_support.dart';

// Why this file exists, in one paragraph.
//
// A full-backup restore is journalled, and the journal carries a SNAPSHOT of
// the two preference families keyed by the FULL Tox ID — the blocked-peer list
// and the failed-message queue — taken before the restore overwrites them, so
// that a rollback can put the user's originals back. That snapshot is also a
// way to bring deleted data back to life: a restore whose finalization fails
// can leave its journal on disk next to an already-published account row, the
// user can then DELETE that account, and the next startup's recovery rolls the
// restore back — writing the snapshotted block list and pending messages for an
// account the user just erased. Deletion therefore has to DISCARD the journal
// (drop it, without restoring anything) before it starts erasing.
//
// These tests assert on what the user can observe after the fact — prefs
// content, the journal file, the staging directories — rather than on how the
// discard is implemented, so that a later refactor of the deletion stages
// cannot quietly retire the guarantee.

// 76-char Tox IDs whose first 16 chars differ from their last 16. That is
// load-bearing: `black_list_<fullToxId>` ends with the LAST chars of the id,
// while the generic account sweep matches the `_<first16>` suffix, so a
// self-repeating test id would be swept by accident and these tests would pass
// for the wrong reason.
const _deletedToxId =
    'AA11BB22CC33DD44EE55FF6677889900112233445566778899AABBCCDDEEFF010123456789AB';
const _otherToxId =
    'CC99DD88EE77FF66554433221100AABBCCDDEEFF001122334455667788990123FEDCBA987654';

// What the journal snapshotted before the restore overwrote it: the user's real
// blocked peers and real pending messages. Resurrecting these after a deletion
// is the regression.
const _snapshotBlockedPeers = <String>['blocked-peer-one', 'blocked-peer-two'];
const _snapshotFailedQueue = '{"pending":"snapshotted-queue-payload"}';

void main() {
  group('account deletion and a pending full-backup restore journal', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      AccountDeletionTestHooks.reset();
      FullBackupRestoreTestHooks.reset();
      // Only the two secure-storage stages are stubbed. Everything else — the
      // prefs sweep, the privacy residue sweep, the directory deletes — runs
      // for real, because those are exactly the steps whose erasure the journal
      // would undo.
      AccountDeletionTestHooks.removePassword = (_) async => true;
      AccountDeletionTestHooks.purgeSecureSecrets = (_) async => true;
    });

    tearDown(() async {
      AccountDeletionTestHooks.reset();
      FullBackupRestoreTestHooks.reset();
      await env.dispose();
    });

    // Prevents: deleted data coming back. The user blocks two peers, has a
    // message fail, imports a backup whose finalization dies, then deletes the
    // account to be rid of all of it. On the next launch, recovery rolls the
    // dead restore back and writes the snapshotted blocked peers and pending
    // messages onto disk again — for an account that no longer exists and that
    // the user explicitly erased. "Delete" has to mean the data stays gone
    // across the next startup, not just until it.
    test('a deleted account is not repopulated by restore recovery', () async {
      await _seedAccount(_deletedToxId, nickname: 'Deleted');
      await _seedFullIdPrefs(_deletedToxId);
      await _writeJournalWithSnapshot(_deletedToxId);

      final result = await AccountDeletionCoordinator.deleteAccount(
        toxId: _deletedToxId,
      );
      expect(result.completed, isTrue, reason: result.toString());

      // Sanity: the deletion really did erase both families, so the assertions
      // after recovery are testing that they STAY erased rather than an
      // accident of a deletion that never reached them.
      expect(await Prefs.getBlackList(_deletedToxId), isEmpty);
      expect(await Prefs.exportFailedMessageQueue(_deletedToxId), isNull);

      await AccountExportService.recoverPendingFullBackupRestore();

      expect(await Prefs.getBlackList(_deletedToxId), isEmpty);
      expect(await Prefs.exportFailedMessageQueue(_deletedToxId), isNull);
      expect(await Prefs.getAccountByToxId(_deletedToxId), isNull);
    });

    // Prevents: the resurrection above being deferred rather than prevented. If
    // the journal outlives the deletion, every subsequent launch re-runs
    // recovery against it, so the data comes back the first time the user opens
    // the app after an upgrade, a crash, or a second deletion attempt — long
    // after the deletion "succeeded" and any chance of connecting the two.
    test('deleting an account leaves no restore journal behind', () async {
      await _seedAccount(_deletedToxId, nickname: 'Deleted');
      await _writeJournalWithSnapshot(_deletedToxId);
      expect(await RestoreTransactionJournalStore.read(), isNotNull);

      await AccountDeletionCoordinator.deleteAccount(toxId: _deletedToxId);

      expect(await RestoreTransactionJournalStore.read(), isNull);
    });

    // Prevents: fixing one resurrection by causing another. The discard must be
    // ownership-checked. A blanket "delete the journal on any deletion" would
    // silently drop a DIFFERENT account's in-flight restore — and that journal
    // is the only copy of that account's pre-restore blocked peers and pending
    // messages, so throwing it away destroys live data belonging to an account
    // the user never touched.
    test('deleting one account leaves another account\'s restore journal '
        'and staging intact', () async {
      await _seedAccount(_deletedToxId, nickname: 'Deleted');
      await _seedAccount(_otherToxId, nickname: 'Other');
      final otherStaging = await _writeJournalWithSnapshot(_otherToxId);

      await AccountDeletionCoordinator.deleteAccount(toxId: _deletedToxId);

      final survivor = await RestoreTransactionJournalStore.read();
      expect(survivor, isNotNull);
      expect(survivor!.toxId, _otherToxId);
      expect(survivor.priorBlackListCaptured, isTrue);
      expect(survivor.priorBlackList, _snapshotBlockedPeers);
      expect(survivor.priorFailedQueueCaptured, isTrue);
      expect(survivor.priorFailedQueue, _snapshotFailedQueue);
      for (final dir in otherStaging) {
        expect(await Directory(dir).exists(), isTrue);
      }
    });

    // Prevents: deleted content surviving on disk under a name nothing else
    // knows. The staging directories hold the unpacked backup — the profile and
    // the whole chat history — and they live under hidden
    // `.full_backup_restore_*` names that only the journal records. Dropping
    // the journal without deleting them orphans a full copy of the account's
    // messages on a machine whose owner just asked for that account to be
    // erased, with nothing left that could ever find it again.
    test('the discarded journal takes its staging directories with it',
        () async {
      await _seedAccount(_deletedToxId, nickname: 'Deleted');
      final staging = await _writeJournalWithSnapshot(_deletedToxId);
      for (final dir in staging) {
        expect(await Directory(dir).exists(), isTrue);
      }

      await AccountDeletionCoordinator.deleteAccount(toxId: _deletedToxId);

      for (final dir in staging) {
        expect(await Directory(dir).exists(), isFalse);
      }
    });
  });
}

/// A registered account with a profile and an account-data directory: the shape
/// a failed finalize leaves behind, i.e. a published registry row alongside a
/// journal that is still on disk.
Future<void> _seedAccount(String toxId, {required String nickname}) async {
  await Prefs.addAccount(
    toxId: toxId,
    nickname: nickname,
    statusMessage: '',
  );
  final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
  await Directory(profileDir).create(recursive: true);
  await File(
    AppPaths.profileFileInDirectory(profileDir),
  ).writeAsString('profile-$toxId', flush: true);
  final dataRoot = await AppPaths.getAccountDataRoot(toxId);
  await Directory(p.join(dataRoot, 'chat_history')).create(recursive: true);
  await File(
    p.join(dataRoot, 'chat_history', 'conversation.json'),
  ).writeAsString('{"message":"erase me"}', flush: true);
}

/// The two FULL-id-keyed families as the user had them before the restore.
Future<void> _seedFullIdPrefs(String toxId) async {
  await Prefs.setBlackList(_snapshotBlockedPeers.toSet(), toxId);
  await Prefs.importFailedMessageQueue(toxId, _snapshotFailedQueue);
  expect(await Prefs.getBlackList(toxId), _snapshotBlockedPeers.toSet());
  expect(await Prefs.exportFailedMessageQueue(toxId), _snapshotFailedQueue);
}

/// Write a journal for [toxId] carrying a captured snapshot, and materialize
/// the staging directories it names. Returns those staging paths.
///
/// The state is [RestoreTransactionState.accountRegistryVisible] on purpose:
/// that is the window where the account row is already published (so the user
/// can see and delete the account) while the journal is still on disk.
Future<List<String>> _writeJournalWithSnapshot(String toxId) async {
  final profileFinalDir = await AppPaths.getProfileDirectoryForToxId(toxId);
  final accountDataFinalDir = await AppPaths.getAccountDataRoot(toxId);
  final prefix = toxId.substring(0, 16);
  final profileStageDir = p.join(
    p.dirname(profileFinalDir),
    '.full_backup_restore_profile_${prefix}_journal_test',
  );
  final accountDataStageDir = p.join(
    p.dirname(accountDataFinalDir),
    '.full_backup_restore_data_${prefix}_journal_test',
  );
  await Directory(profileStageDir).create(recursive: true);
  await File(
    p.join(profileStageDir, 'tox_profile.tox'),
  ).writeAsString('staged-profile-$toxId', flush: true);
  await Directory(
    p.join(accountDataStageDir, 'chat_history'),
  ).create(recursive: true);
  await File(
    p.join(accountDataStageDir, 'chat_history', 'conversation.json'),
  ).writeAsString('{"message":"staged history"}', flush: true);

  await RestoreTransactionJournalStore.write(
    RestoreTransactionJournal(
      transactionId: 'deleted-account-journal-test',
      toxId: toxId,
      state: RestoreTransactionState.accountRegistryVisible,
      profileStageDir: profileStageDir,
      profileFinalDir: profileFinalDir,
      accountDataStageDir: accountDataStageDir,
      accountDataFinalDir: accountDataFinalDir,
      hasProfile: true,
      priorBlackListCaptured: true,
      priorBlackList: _snapshotBlockedPeers,
      priorFailedQueueCaptured: true,
      priorFailedQueue: _snapshotFailedQueue,
    ),
  );
  return <String>[profileStageDir, accountDataStageDir];
}
