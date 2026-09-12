import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../prefs.dart';
import '../safe_diagnostics.dart';
import '../tox_utils.dart';
import 'backup_path_safety.dart';
import 'restore_metadata_sections.dart';
import 'restore_transaction_journal.dart';

// The durable journal (model + on-disk store) lives in its own file; re-exported
// so existing importers of this one keep resolving it.
export 'restore_transaction_journal.dart';

enum RestoreTransactionState {
  staged,
  profileCommitted,
  accountDataCommitted,
  scopedPrefsApplied,
  accountRegistryVisible,
}

enum FullBackupRestoreFailurePoint {
  afterStaging,
  afterProfileCommit,
  afterAccountDataCommit,
  afterScopedPrefsApply,
  afterAccountRegistryVisible,
}

/// Which of the four directories a restore has to claim was already occupied.
enum RestoreDestinationKind {
  /// `<profileStorageRoot>/p_<prefix>` — the committed profile directory.
  profileFinal,

  /// `<appSupport>/account_data/<prefix>` — the committed account data root.
  accountDataFinal,

  /// The `.full_backup_restore_profile_*` staging sibling of [profileFinal].
  profileStage,

  /// The `.full_backup_restore_data_*` staging sibling of [accountDataFinal].
  accountDataStage,
}

/// Thrown when a full-backup restore would have to overwrite a directory that
/// already exists (pre-flight) or that appeared between pre-flight and the
/// commit rename (TOCTOU defence in depth).
///
/// PRIVACY — read this before "improving" the message by adding the path back.
/// All four destinations are derived from the account's own identity:
/// `AppPaths.getProfileDirectoryForToxId` and `AppPaths.getAccountDataRoot`
/// name them `p_<first 16 hex chars of the Tox ID>` / `account_data/<same
/// prefix>`, and [_RestorePaths.resolve] reuses that prefix for the staging
/// directories. Interpolating one publishes the account's public-key prefix
/// *and* the absolute application-support layout (which contains the OS user
/// name on desktop). It would not stay local either: an aborted restore
/// propagates out of [FullBackupRestoreTransaction.restore] to handlers that
/// call `AppLogger.logError(..., error)`, which writes `Error: $error`
/// verbatim into `flutter_client.log` — the file users attach to bug reports.
/// This is the same leak class as the redacted `UnsafeBackupPathException` in
/// `backup_path_safety.dart`; both are pinned by
/// `test/util/account_privacy_boundary_source_test.dart`.
///
/// [kind] is kept because it is the only thing a maintainer cannot re-derive
/// from the code, and it distinguishes all four collision sites. No path
/// fingerprint is carried: unlike an attacker-chosen archive entry name, these
/// paths are fully determined by (application-support root, own Tox ID prefix,
/// transaction id), so a digest of one would add no triage signal.
///
/// Extends [StateError] on purpose. Every other restore abort in this file is a
/// `StateError` and callers/tests catch it as one
/// (`test/account_export/full_backup_restore_transaction_test.dart` asserts
/// `isA<StateError>()`), so redacting the message must not change which
/// handlers fire.
final class RestoreDestinationExistsError extends StateError {
  RestoreDestinationExistsError(this.kind)
    : super('Restore destination already exists (kind=${kind.name})');

  /// Which destination was occupied.
  final RestoreDestinationKind kind;
}

final class FullBackupRestoreCrashSimulation implements Exception {
  const FullBackupRestoreCrashSimulation(this.point);

  final FullBackupRestoreFailurePoint point;

  @override
  String toString() => 'FullBackupRestoreCrashSimulation: ${point.name}';
}

abstract final class FullBackupRestoreTestHooks {
  FullBackupRestoreTestHooks._();

  @visibleForTesting
  static FullBackupRestoreFailurePoint? crashAt;

  static String Function(Uint8List profileBytes)? profileIdentityExtractor;

  @visibleForTesting
  static void reset() {
    crashAt = null;
    profileIdentityExtractor = null;
  }

  static void maybeCrash(FullBackupRestoreFailurePoint point) {
    if (crashAt == point) {
      throw FullBackupRestoreCrashSimulation(point);
    }
  }
}

final class FullBackupRestoreInput {
  const FullBackupRestoreInput({
    required this.toxId,
    required this.nickname,
    required this.archive,
    required this.metadata,
    required this.toxProfile,
  });

  final String toxId;
  final String nickname;
  final Archive archive;
  final Map<String, dynamic> metadata;
  final Uint8List? toxProfile;
}

abstract final class FullBackupRestoreTransaction {
  FullBackupRestoreTransaction._();

  static Future<Map<String, dynamic>> restore(
    FullBackupRestoreInput input,
  ) async {
    await recoverPendingRestore();
    // A journal that SURVIVED recovery is one this process cannot resolve, and
    // the transaction-id fence would then refuse every later restore forever.
    // See `RestoreTransactionJournalStore.archiveUnresolved`.
    if (await RestoreTransactionJournalStore.archiveUnresolved() != null) {
      SafeDiagnostics.logFailure(
        '[RestoreTransaction] an earlier restore could not be undone; its '
        'record was archived so a new one can start',
        StateError('unresolved restore journal archived'),
      );
    }
    final paths = await _RestorePaths.resolve(input.toxId);
    _validateArchivePaths(input.archive, paths);
    final scopedPrefs = portableScopedPrefs(
      input.metadata,
      paths.accountDataFinalDir,
    );
    await _preflight(input.toxId, paths);

    var journal = RestoreTransactionJournal(
      transactionId: paths.transactionId,
      toxId: input.toxId,
      state: RestoreTransactionState.staged,
      profileStageDir: paths.profileStageDir,
      profileFinalDir: paths.profileFinalDir,
      accountDataStageDir: paths.accountDataStageDir,
      accountDataFinalDir: paths.accountDataFinalDir,
      hasProfile: input.toxProfile != null,
    );
    // Captured BEFORE anything is written: the restore overwrites both families
    // during metadata application, so this snapshot is the only copy of what was
    // there. See the field docs on the journal.
    journal = await captureFullIdPrefs(journal);
    await RestoreTransactionJournalStore.write(journal);

    try {
      await _stagePayload(input, paths);
      FullBackupRestoreTestHooks.maybeCrash(
        FullBackupRestoreFailurePoint.afterStaging,
      );

      if (input.toxProfile != null) {
        await _renameDirectory(
          paths.profileStageDir,
          paths.profileFinalDir,
          destinationKind: RestoreDestinationKind.profileFinal,
        );
      }
      journal = journal.copyWith(
        state: RestoreTransactionState.profileCommitted,
      );
      await RestoreTransactionJournalStore.write(journal);
      FullBackupRestoreTestHooks.maybeCrash(
        FullBackupRestoreFailurePoint.afterProfileCommit,
      );

      await _renameDirectory(
        paths.accountDataStageDir,
        paths.accountDataFinalDir,
        destinationKind: RestoreDestinationKind.accountDataFinal,
      );
      journal = journal.copyWith(
        state: RestoreTransactionState.accountDataCommitted,
      );
      await RestoreTransactionJournalStore.write(journal);
      FullBackupRestoreTestHooks.maybeCrash(
        FullBackupRestoreFailurePoint.afterAccountDataCommit,
      );

      if (scopedPrefs.isNotEmpty) {
        await Prefs.importScopedPrefsForAccount(input.toxId, scopedPrefs);
      }
      // The blocked-peer list travels OUTSIDE scopedPrefs because its key is
      // scoped by the full Tox ID, which the `_<first16>` suffix export/import
      // does not see. Restoring it here (inside the journalled window) means a
      // rollback takes it with everything else.
      await restoreBlockedPeers(input.toxId, input.metadata);
      await restoreFailedMessageQueue(input.toxId, input.metadata);
      journal = journal.copyWith(
        state: RestoreTransactionState.scopedPrefsApplied,
      );
      await RestoreTransactionJournalStore.write(journal);
      FullBackupRestoreTestHooks.maybeCrash(
        FullBackupRestoreFailurePoint.afterScopedPrefsApply,
      );

      return <String, dynamic>{
        'toxId': input.toxId,
        'nickname': input.nickname,
        // Carried through so the caller can persist it on the account row. The
        // export has always written `statusMessage` into metadata, but restore
        // dropped it and both import UIs then created the row with '' — so the
        // next login pushed an EMPTY status to Tox, overwriting what the backup
        // had preserved.
        'statusMessage': input.metadata['statusMessage'] as String? ?? '',
        'toxProfile': input.toxProfile,
      };
    } catch (e) {
      if (e is FullBackupRestoreCrashSimulation) rethrow;
      await rollbackPendingRestore(toxId: input.toxId);
      rethrow;
    }
  }

  static Future<void> finalizePendingRestore({required String toxId}) async {
    var journal = await RestoreTransactionJournalStore.read();
    if (journal == null) return;
    if (!compareToxIds(journal.toxId, toxId)) {
      throw StateError('Pending restore belongs to a different account');
    }
    if (!await _dataCommitted(journal)) {
      throw StateError('Cannot finalize incomplete full-backup restore');
    }
    if (await Prefs.getAccountByToxId(toxId) == null) {
      throw StateError('Cannot finalize before account registry is visible');
    }
    journal = journal.copyWith(
      state: RestoreTransactionState.accountRegistryVisible,
    );
    await RestoreTransactionJournalStore.write(journal);
    FullBackupRestoreTestHooks.maybeCrash(
      FullBackupRestoreFailurePoint.afterAccountRegistryVisible,
    );
    await RestoreTransactionJournalStore.clear();
  }

  static Future<void> rollbackPendingRestore({String? toxId}) async {
    final journal = await RestoreTransactionJournalStore.read();
    if (journal == null) return;
    if (toxId != null && !compareToxIds(journal.toxId, toxId)) {
      throw StateError('Pending restore belongs to a different account');
    }
    await _rollback(journal);
  }

  static Future<void> recoverPendingRestore() async {
    final journal = await RestoreTransactionJournalStore.read();
    if (journal == null) return;
    final accountVisible = await Prefs.getAccountByToxId(journal.toxId) != null;
    if (accountVisible && await _dataCommitted(journal)) {
      await RestoreTransactionJournalStore.clear();
      return;
    }
    await _rollback(journal);
  }

  static Future<void> _preflight(String toxId, _RestorePaths paths) async {
    if (await Prefs.getAccountByToxId(toxId) != null) {
      throw StateError('Account already exists');
    }
    if ((await Prefs.exportScopedPrefsForAccount(toxId)).isNotEmpty) {
      throw StateError('Account scoped preferences already exist');
    }
    for (final destination in <({RestoreDestinationKind kind, String dir})>[
      (kind: RestoreDestinationKind.profileFinal, dir: paths.profileFinalDir),
      (
        kind: RestoreDestinationKind.accountDataFinal,
        dir: paths.accountDataFinalDir,
      ),
      (kind: RestoreDestinationKind.profileStage, dir: paths.profileStageDir),
      (
        kind: RestoreDestinationKind.accountDataStage,
        dir: paths.accountDataStageDir,
      ),
    ]) {
      if (await Directory(destination.dir).exists()) {
        throw RestoreDestinationExistsError(destination.kind);
      }
    }
  }

  static Future<void> _stagePayload(
    FullBackupRestoreInput input,
    _RestorePaths paths,
  ) async {
    if (input.toxProfile != null) {
      await Directory(paths.profileStageDir).create(recursive: true);
      final profileFile = File(
        AppPaths.profileFileInDirectory(paths.profileStageDir),
      );
      await profileFile.writeAsBytes(input.toxProfile!, flush: true);
    }
    await Directory(paths.accountDataStageDir).create(recursive: true);

    for (final entry in input.archive.files) {
      if (!entry.isFile) continue;
      if (entry.name.startsWith('chat_history/')) {
        final relativePath = entry.name.substring('chat_history/'.length);
        if (relativePath.isEmpty) continue;
        final targetPath = safeBackupRestorePath(
          baseDir: p.join(paths.accountDataStageDir, 'chat_history'),
          relativePath: relativePath,
        );
        await _writeEntry(File(targetPath), entry);
      } else if (entry.name.startsWith('avatars/')) {
        final relativePath = entry.name.substring('avatars/'.length);
        if (relativePath.isEmpty) continue;
        final targetPath = safeBackupRestorePath(
          baseDir: p.join(paths.accountDataStageDir, 'avatars'),
          relativePath: relativePath,
        );
        await _writeEntry(File(targetPath), entry);
      }
    }

    final queueFile = input.archive.findFile('offline_message_queue.json');
    if (queueFile != null) {
      await _writeEntry(
        File(p.join(paths.accountDataStageDir, 'offline_message_queue.json')),
        queueFile,
      );
    }
  }

  static void _validateArchivePaths(Archive archive, _RestorePaths paths) {
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      if (entry.name.startsWith('chat_history/')) {
        final relativePath = entry.name.substring('chat_history/'.length);
        if (relativePath.isNotEmpty) {
          safeBackupRestorePath(
            baseDir: p.join(paths.accountDataFinalDir, 'chat_history'),
            relativePath: relativePath,
          );
        }
      } else if (entry.name.startsWith('avatars/')) {
        final relativePath = entry.name.substring('avatars/'.length);
        if (relativePath.isNotEmpty) {
          safeBackupRestorePath(
            baseDir: p.join(paths.accountDataFinalDir, 'avatars'),
            relativePath: relativePath,
          );
        }
      }
    }
  }

  static Future<void> _renameDirectory(
    String source,
    String destination, {
    required RestoreDestinationKind destinationKind,
  }) async {
    // Atomicity is per root only: staging lives under this destination's
    // parent so this rename is same-filesystem, while cross-root consistency is
    // provided by the durable journal and recovery path.
    if (await Directory(destination).exists()) {
      throw RestoreDestinationExistsError(destinationKind);
    }
    await Directory(p.dirname(destination)).create(recursive: true);
    await Directory(source).rename(destination);
  }

  static Future<void> _writeEntry(File targetFile, ArchiveFile entry) async {
    await targetFile.parent.create(recursive: true);
    final bytes = Uint8List.fromList(entry.content as List<int>);
    await targetFile.writeAsBytes(bytes, flush: true);
  }

  static Future<bool> _dataCommitted(RestoreTransactionJournal journal) async {
    if (journal.hasProfile) {
      final profilePath = AppPaths.profileFileInDirectory(
        journal.profileFinalDir,
      );
      if (!await File(profilePath).exists()) return false;
    }
    return Directory(journal.accountDataFinalDir).exists();
  }

  static Future<void> _rollback(RestoreTransactionJournal journal) async {
    await _deleteDirectory(journal.profileStageDir);
    await _deleteDirectory(journal.accountDataStageDir);
    await _deleteDirectory(journal.profileFinalDir);
    await _deleteDirectory(journal.accountDataFinalDir);
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

  /// Drop a pending restore journal that names [toxId] because the account is
  /// being DELETED.
  ///
  /// Not a rollback: a rollback would put the snapshotted block list and
  /// failed-message queue BACK, and doing that after a deletion resurrects the
  /// data the user just asked to be erased. (A finalize that failed can leave a
  /// journal alongside a published row, so the account is deletable with the
  /// journal still on disk, and the next startup would then act on it.) The
  /// staging directories are removed because nothing else knows about them; the
  /// final directories belong to the account and the deletion flow erases those.
  static Future<void> discardForDeletedAccount(String toxId) async {
    final journal = await RestoreTransactionJournalStore.read();
    if (journal == null || !compareToxIds(journal.toxId, toxId)) return;
    await _deleteDirectory(journal.profileStageDir);
    await _deleteDirectory(journal.accountDataStageDir);
    // Ownership is re-checked inside the clear. Reading, deciding and deleting
    // are three steps, and a restore for ANOTHER account can publish its journal
    // in between - after which an unchecked clear would delete that restore's
    // only recovery record instead of the one this deletion looked at.
    await RestoreTransactionJournalStore.clearIfOwnedBy(toxId);
  }

  static Future<void> _deleteDirectory(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

final class _RestorePaths {
  const _RestorePaths({
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

  static Future<_RestorePaths> resolve(String toxId) async {
    final profileFinalDir = await AppPaths.getProfileDirectoryForToxId(toxId);
    final accountDataFinalDir = await AppPaths.getAccountDataRoot(toxId);
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final transactionId = DateTime.now().microsecondsSinceEpoch.toString();
    return _RestorePaths(
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
