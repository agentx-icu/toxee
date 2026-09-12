import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../async_gate.dart';
import '../prefs.dart';
import '../tox_utils.dart';
import 'backup_path_safety.dart';
import 'restore_metadata_sections.dart';
import 'restore_paths.dart';
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
/// prefix>`, and [RestorePaths.resolve] reuses that prefix for the staging
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

  /// Serializes whole restore WORKFLOWS. The journal store's own gate protects
  /// each read or write, not a transaction's ownership across the steps between
  /// them: two restores of one account could both pass recovery and preflight,
  /// the second replacing the first's journal mid-staging, and the first's catch
  /// would then roll back the SECOND transaction. NOT re-entrant - everything
  /// inside uses the `Unguarded` bodies.
  static final AsyncGate _transactionGate = AsyncGate();

  /// The transaction whose CALLER still owns it: `restore` has returned with the
  /// data committed and that caller has yet to publish the account row and
  /// finalize. The gate releases when `restore` returns, so without this a
  /// queued restore ran recovery, saw a committed journal with no account row,
  /// and deleted the first caller's profile and history. Process-local: a cold
  /// start has no owner and must still resolve whatever it finds.
  static String? _ownedTransactionId;

  /// For tests that abandon a transaction mid-flight.
  @visibleForTesting
  static void resetOwnership() => _ownedTransactionId = null;

  static Future<Map<String, dynamic>> restore(FullBackupRestoreInput input) =>
      _transactionGate.run(() => _restoreUnguarded(input));

  static Future<Map<String, dynamic>> _restoreUnguarded(
    FullBackupRestoreInput input,
  ) async {
    if (_ownedTransactionId != null) {
      // Ownership means something only while the journal it names is still on
      // disk. A caller that finished (or whose journal was resolved some other
      // way) must not leave every later restore in this process refused - that
      // would turn one abandoned transaction into a permanent outage.
      final current = await RestoreTransactionJournalStore.read();
      if (current != null && current.transactionId == _ownedTransactionId) {
        // Committed, waiting to publish: our recovery would undo it.
        throw const RestoreInFlightException();
      }
      _ownedTransactionId = null;
    }
    await _recoverPendingRestoreUnguarded();
    final paths = await RestorePaths.resolve(input.toxId);
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
    // A journal that SURVIVED recovery belongs to a rollback this process could
    // not verify. Admitting this transaction CARRIES its snapshot forward, so
    // the fence still protects those originals while the user is not locked out
    // of restoring ever again. See `admitCarryingForward`.
    journal = await RestoreTransactionJournalStore.admitCarryingForward(journal);

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

      // Ownership passes to the CALLER here: it still has to publish the
      // account row and finalize, and until it does, nothing else may recover
      // or replace this transaction. Released by finalize and by rollback.
      _ownedTransactionId = journal.transactionId;
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
      await _rollbackPendingRestoreUnguarded(
        toxId: input.toxId,
        transactionId: journal.transactionId,
      );
      rethrow;
    }
  }

  static Future<void> finalizePendingRestore({required String toxId}) =>
      _transactionGate.run(() => _finalizePendingRestoreUnguarded(toxId));

  static Future<void> _finalizePendingRestoreUnguarded(String toxId) async {
    var journal = await RestoreTransactionJournalStore.read();
    if (journal == null) {
      _ownedTransactionId = null;
      return;
    }
    if (!compareToxIds(journal.toxId, toxId)) {
      throw StateError('Pending restore belongs to a different account');
    }
    if (!await restoreDataCommitted(journal)) {
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
    _ownedTransactionId = null;
  }


  /// [transactionId], when given, is the caller's OWN transaction: matching only
  /// the account would destroy whichever transaction holds the journal now. The
  /// UI paths pass no id - "undo whatever is pending here" is what they mean.
  static Future<void> rollbackPendingRestore({
    String? toxId,
    String? transactionId,
  }) =>
      _transactionGate.run(
        () => _rollbackPendingRestoreUnguarded(
          toxId: toxId,
          transactionId: transactionId,
        ),
      );

  static Future<void> _rollbackPendingRestoreUnguarded({
    String? toxId,
    String? transactionId,
  }) async {
    final journal = await RestoreTransactionJournalStore.read();
    if (journal == null) return;
    if (toxId != null && !compareToxIds(journal.toxId, toxId)) {
      throw StateError('Pending restore belongs to a different account');
    }
    if (transactionId != null && journal.transactionId != transactionId) {
      // Someone else's transaction now holds the journal; undoing it would
      // destroy work that is still in flight.
      return;
    }
    try {
      await rollbackRestoreTransaction(journal);
    } finally {
      // Released even when the rollback THREW: both UI callers swallow that and
      // walk away, so holding ownership past it left recovery skipping the
      // journal and every later restore refused, permanently. The journal is
      // deliberately kept, for recovery to retry.
      if (journal.transactionId == _ownedTransactionId) {
        _ownedTransactionId = null;
      }
    }
  }

  static Future<void> recoverPendingRestore() =>
      _transactionGate.run(_recoverPendingRestoreUnguarded);

  static Future<void> _recoverPendingRestoreUnguarded() async {
    final journal = await RestoreTransactionJournalStore.read();
    if (journal == null) return;
    if (journal.transactionId == _ownedTransactionId) {
      // Its caller is alive and mid-publication; only that caller may finish or
      // undo it. A cold start clears `_ownedTransactionId` by construction.
      return;
    }
    final accountVisible = await Prefs.getAccountByToxId(journal.toxId) != null;
    if (accountVisible && await restoreDataCommitted(journal)) {
      await RestoreTransactionJournalStore.clear();
      return;
    }
    await rollbackRestoreTransaction(journal);
  }

  static Future<void> _preflight(String toxId, RestorePaths paths) async {
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
    RestorePaths paths,
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

  static void _validateArchivePaths(Archive archive, RestorePaths paths) {
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
  static Future<void> discardForDeletedAccount(String toxId) =>
      _transactionGate.run(() => discardRestoreForDeletedAccount(toxId));


}
