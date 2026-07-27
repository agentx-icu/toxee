import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'account_deletion_journal.dart';
export 'account_deletion_journal.dart';

import 'app_paths.dart';
import 'prefs.dart';
import 'privacy_cleanup.dart';
import 'tox_utils.dart';

abstract final class AccountDeletionTestHooks {
  AccountDeletionTestHooks._();

  @visibleForTesting
  static Future<void> Function(String path, AccountDeletionStage stage)?
  deleteDirectory;

  @visibleForTesting
  static Future<bool> Function(String toxId)? removePassword;

  @visibleForTesting
  static Future<void> Function(String toxId)? clearPrefsData;

  @visibleForTesting
  static Future<void> Function(String toxId)? removeAccount;

  @visibleForTesting
  static Future<void> Function(String? toxId)? setCurrentAccountToxId;

  @visibleForTesting
  static Future<void> Function(String toxId)? cleanupPrivacyResidue;

  @visibleForTesting
  static void reset() {
    deleteDirectory = null;
    removePassword = null;
    clearPrefsData = null;
    removeAccount = null;
    setCurrentAccountToxId = null;
    cleanupPrivacyResidue = null;
  }
}

abstract final class AccountDeletionCoordinator {
  AccountDeletionCoordinator._();

  static Future<AccountDeletionResult> deleteAccount({
    required String toxId,
    Future<void> Function()? serviceCleanup,
  }) async {
    final existingTombstone = await AccountDeletionJournalStore.read(toxId);
    late AccountDeletionTombstone tombstone;
    if (existingTombstone == null) {
      final current = await Prefs.getCurrentAccountToxId();
      tombstone = AccountDeletionTombstone.initial(
        toxId: toxId,
        deletedCurrentAccount: current != null && compareToxIds(current, toxId),
      );
    } else {
      tombstone = existingTombstone;
    }
    try {
      await AccountDeletionJournalStore.write(tombstone);
    } catch (e, st) {
      return _pending(toxId, AccountDeletionStage.tombstone, e, st, tombstone);
    }

    Future<AccountDeletionResult?> runStage(
      AccountDeletionStage stage,
      AccountDeletionState nextState,
      Future<void> Function() action,
    ) async {
      if (tombstone.state.hasCompleted(nextState)) return null;
      try {
        await action();
        final completedTombstone = tombstone.markCompleted(nextState);
        await AccountDeletionJournalStore.write(completedTombstone);
        tombstone = completedTombstone;
        return null;
      } catch (e, st) {
        return _pending(toxId, stage, e, st, tombstone);
      }
    }

    final serviceResult = await runStage(
      AccountDeletionStage.serviceData,
      AccountDeletionState.serviceDataCleared,
      serviceCleanup ?? () async {},
    );
    if (serviceResult != null) return serviceResult;

    final passwordResult = await runStage(
      AccountDeletionStage.securePassword,
      AccountDeletionState.securePasswordCleared,
      () async {
        final removed =
            await (AccountDeletionTestHooks.removePassword?.call(toxId) ??
                Prefs.removeAccountPassword(toxId));
        if (!removed) {
          throw StateError('secure password deletion failed');
        }
      },
    );
    if (passwordResult != null) return passwordResult;

    final prefsResult = await runStage(
      AccountDeletionStage.prefsData,
      AccountDeletionState.prefsDataCleared,
      () async {
        final hook = AccountDeletionTestHooks.clearPrefsData;
        if (hook != null) {
          await hook(toxId);
        } else {
          await Prefs.clearAccountDataAfterPasswordRemoved(
            toxId,
            clearCurrentAccountPointer: false,
          );
        }
      },
    );
    if (prefsResult != null) return prefsResult;

    final profileResult = await runStage(
      AccountDeletionStage.profileDirectory,
      AccountDeletionState.profileDirectoryDeleted,
      () async {
        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        await _deleteDirectory(
          profileDir,
          AccountDeletionStage.profileDirectory,
        );
      },
    );
    if (profileResult != null) return profileResult;

    final dataResult = await runStage(
      AccountDeletionStage.accountDataDirectory,
      AccountDeletionState.accountDataDirectoryDeleted,
      () async {
        final roots = await _accountDataRootsForDeletion(toxId);
        for (final dataDir in roots) {
          await _deleteDirectory(
            dataDir,
            AccountDeletionStage.accountDataDirectory,
          );
        }
      },
    );
    if (dataResult != null) return dataResult;

    final currentResult = await runStage(
      AccountDeletionStage.currentAccount,
      AccountDeletionState.currentAccountCleared,
      () async {
        final current = await Prefs.getCurrentAccountToxId();
        if (current != null && compareToxIds(current, toxId)) {
          final hook = AccountDeletionTestHooks.setCurrentAccountToxId;
          if (hook != null) {
            await hook(null);
          } else {
            await Prefs.setCurrentAccountToxId(null);
          }
        }
      },
    );
    if (currentResult != null) return currentResult;

    final privacyResult = await runStage(
      AccountDeletionStage.privacyResidue,
      AccountDeletionState.privacyResidueCleared,
      () async {
        final hook = AccountDeletionTestHooks.cleanupPrivacyResidue;
        if (hook != null) {
          await hook(toxId);
        } else {
          await AccountPrivacyCleanup.purgeDeletedAccountResidue(
            toxId: toxId,
            deletedCurrentAccount: tombstone.deletedCurrentAccount,
          );
        }
      },
    );
    if (privacyResult != null) return privacyResult;

    final registryResult = await runStage(
      AccountDeletionStage.accountRegistry,
      AccountDeletionState.accountRegistryRemoved,
      () async {
        final hook = AccountDeletionTestHooks.removeAccount;
        if (hook != null) {
          await hook(toxId);
        } else {
          await Prefs.removeAccount(toxId);
        }
      },
    );
    if (registryResult != null) return registryResult;

    try {
      await AccountDeletionJournalStore.clear(toxId);
    } catch (e, st) {
      return _pending(
        toxId,
        AccountDeletionStage.tombstoneClear,
        e,
        st,
        tombstone,
      );
    }
    return AccountDeletionResult.completed(toxId);
  }

  static Future<List<AccountDeletionResult>> recoverPendingDeletions() async {
    final tombstones = await AccountDeletionJournalStore.readAll();
    final results = <AccountDeletionResult>[];
    for (final tombstone in tombstones) {
      results.add(await deleteAccount(toxId: tombstone.toxId));
    }
    return results;
  }

  static Future<void> throwIfDeleting(String toxId) async {
    if (await AccountDeletionJournalStore.hasPendingForToxId(toxId)) {
      throw AccountDeletionInProgressException(toxId);
    }
  }

  static Future<void> _deleteDirectory(
    String path,
    AccountDeletionStage stage,
  ) async {
    final hook = AccountDeletionTestHooks.deleteDirectory;
    if (hook != null) {
      await hook(path, stage);
      return;
    }
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<List<String>> _accountDataRootsForDeletion(String toxId) async {
    final roots = <String>{
      p.normalize(p.absolute(await AppPaths.getAccountDataRoot(toxId))),
    };
    try {
      roots.add(
        p.normalize(
          p.absolute(await AppPaths.getAccountScratchDataRoot(toxId)),
        ),
      );
    } on ArgumentError {
      // Legacy short IDs have no full-ID scratch root.
    }
    return roots.toList(growable: false);
  }

  static Future<AccountDeletionResult> _pending(
    String toxId,
    AccountDeletionStage stage,
    Object cause,
    StackTrace stackTrace,
    AccountDeletionTombstone tombstone,
  ) async {
    final failure = AccountDeletionFailure(
      toxId: toxId,
      stage: stage,
      cause: cause,
      stackTrace: stackTrace,
    );
    try {
      await AccountDeletionJournalStore.write(tombstone.markFailure(failure));
    } catch (_) {}
    return AccountDeletionResult.pending(toxId: toxId, failure: failure);
  }
}
