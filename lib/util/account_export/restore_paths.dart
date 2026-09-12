import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../prefs.dart';
import '../tox_utils.dart';
import 'restore_metadata_sections.dart';
import 'restore_transaction_journal.dart';

// The staging and final directory layout of a full-backup restore, split out of
// `restore_transaction.dart` (complexity-gate pin).
//
// Staging directories are siblings of the real ones and carry the transaction
// id, so a crash leaves them identifiable and a concurrent transaction cannot
// collide with them.

final class RestorePaths {
  const RestorePaths({
    required this.transactionId,
    required this.profileStageDir,
    required this.profileFinalDir,
    required this.accountDataStageDir,
    required this.accountDataFinalDir,
  });

  final String transactionId;
  final String profileStageDir;
  final String profileFinalDir;
  final String accountDataStageDir;
  final String accountDataFinalDir;

  static Future<RestorePaths> resolve(String toxId) async {
    final profileFinalDir = await AppPaths.getProfileDirectoryForToxId(toxId);
    final accountDataFinalDir = await AppPaths.getAccountDataRoot(toxId);
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final transactionId = DateTime.now().microsecondsSinceEpoch.toString();
    return RestorePaths(
      transactionId: transactionId,
      profileFinalDir: profileFinalDir,
      accountDataFinalDir: accountDataFinalDir,
      profileStageDir: p.join(
        p.dirname(profileFinalDir),
        '.full_backup_restore_profile_${prefix}_$transactionId',
      ),
      accountDataStageDir: p.join(
        p.dirname(accountDataFinalDir),
        '.full_backup_restore_data_${prefix}_$transactionId',
      ),
    );
  }
}

/// Remove a restore directory if it is there. Lives here with the layout it
/// operates on; both the rollback and the deletion-time discard use it.
Future<void> deleteRestoreDirectory(String path) async {
  final dir = Directory(path);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

Future<void> rollbackRestoreTransaction(
  RestoreTransactionJournal journal,
) async {
  await deleteRestoreDirectory(journal.profileStageDir);
  await deleteRestoreDirectory(journal.accountDataStageDir);
  await deleteRestoreDirectory(journal.profileFinalDir);
  await deleteRestoreDirectory(journal.accountDataFinalDir);
  await Prefs.clearScopedKeysForAccount(journal.toxId);
  // The blocked-peer list is keyed by the full Tox ID, so
  // `clearScopedKeysForAccount` (which matches the `_<first16>` suffix) does
  // not reach it. Without this, a rolled-back restore left the block list of
  // an account that no longer exists.
  // ... and the failed-message queue, written under a FULL-id key by
  // `restoreFailedMessageQueue`, which that sweep cannot reach either. Both
  // are put back to their PRE-TRANSACTION values rather than cleared: they
  // outlive an account whose row and directories are gone (a shape
  // `_preflight` accepts) and the restore overwrites them on the way in, so
  // clearing deleted a block list and pending messages the restore never
  // created. Restoring an empty snapshot still leaves nothing behind for the
  // next importer, which is the invariant the clearing was there for.
  final prefsRestored = await restorePriorFullIdPrefs(journal);
  await Prefs.removeAccount(journal.toxId);
  // Only once the restore is known to have landed. Clearing on a failed write
  // discards the journal's snapshot, which is the only copy of the values it
  // just failed to put back.
  if (prefsRestored) await RestoreTransactionJournalStore.clear();
}

Future<void> discardRestoreForDeletedAccount(String toxId) async {
  final journal = await RestoreTransactionJournalStore.read();
  if (journal == null || !compareToxIds(journal.toxId, toxId)) return;
  await deleteRestoreDirectory(journal.profileStageDir);
  await deleteRestoreDirectory(journal.accountDataStageDir);
  // Ownership is re-checked inside the clear. Reading, deciding and deleting
  // are three steps, and a restore for ANOTHER account can publish its journal
  // in between - after which an unchecked clear would delete that restore's
  // only recovery record instead of the one this deletion looked at.
  await RestoreTransactionJournalStore.clearIfOwnedBy(toxId);
}

/// Whether the restore's payload is fully in its FINAL location.
///
/// The predicate recovery uses to tell "this transaction finished its writes"
/// from "it died partway", so it lives with the layout it inspects.
Future<bool> restoreDataCommitted(RestoreTransactionJournal journal) async {
  if (journal.hasProfile) {
    final profilePath = AppPaths.profileFileInDirectory(
      journal.profileFinalDir,
    );
    if (!await File(profilePath).exists()) return false;
  }
  return Directory(journal.accountDataFinalDir).exists();
}
