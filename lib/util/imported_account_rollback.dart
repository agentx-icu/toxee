import 'dart:io';

import 'app_paths.dart';
import 'prefs.dart';
import 'safe_diagnostics.dart';

/// Undoes a failed `.tox` import.
///
/// OWNERSHIP RULE — read before widening what this deletes. Both directories it
/// removes are keyed by the account's 16-char prefix
/// (`<profileRoot>/p_<first16>` and `account_data/<first16>`), and the import
/// guards only ever checked for an existing `tox_profile.tox` FILE. So a
/// directory can be present, and hold a previous account's chat history, while
/// the import still believed the slot was free. Deleting it unconditionally
/// destroyed data belonging to an account the import never touched.
///
/// [run] therefore takes the set of paths the caller actually CREATED. Anything
/// not in that set is left alone. Callers capture it with [captureOwnership]
/// BEFORE they write anything.
abstract final class ImportedAccountRollback {
  /// Snapshot which of the import's target directories do not exist yet.
  ///
  /// Call this before the first write. The result is the exact set the import
  /// will own, and the only set [run] may delete.
  static Future<ImportedAccountOwnership> captureOwnership(String toxId) async {
    final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
    final accountDataRoot = await AppPaths.getAccountDataRoot(toxId);
    return ImportedAccountOwnership(
      ownsProfileDirectory: !await Directory(profileDir).exists(),
      ownsAccountDataRoot: !await Directory(accountDataRoot).exists(),
    );
  }

  /// Roll back the prefs/registry rows unconditionally (they are keyed by the
  /// full toxId, so they are unambiguously this import's), and the directories
  /// only when [ownership] says this import created them.
  ///
  /// [ownership] defaults to "we own nothing on disk", which is the safe
  /// reading for a caller that could not capture it — prefs are still cleaned
  /// up, and a leftover directory is recoverable by
  /// `AccountReconciliation`, whereas a wrong delete is not.
  static Future<void> run({
    required String toxId,
    required String logContext,
    ImportedAccountOwnership ownership = const ImportedAccountOwnership.none(),
  }) async {
    await _attempt(
      () => Prefs.clearAccountData(toxId),
      logContext: logContext,
      stage: 'account_data_prefs',
    );
    await _attempt(
      () => Prefs.removeAccount(toxId),
      logContext: logContext,
      stage: 'account_registry',
    );
    if (ownership.ownsProfileDirectory) {
      await _attempt(
        () async {
          final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
          final dir = Directory(profileDir);
          if (await dir.exists()) await dir.delete(recursive: true);
        },
        logContext: logContext,
        stage: 'profile_directory',
      );
    }
    if (ownership.ownsAccountDataRoot) {
      await _attempt(
        () async {
          final accountDataRoot = await AppPaths.getAccountDataRoot(toxId);
          final dir = Directory(accountDataRoot);
          if (await dir.exists()) await dir.delete(recursive: true);
        },
        logContext: logContext,
        stage: 'account_data_directory',
      );
    }
  }

  static Future<void> _attempt(
    Future<void> Function() action, {
    required String logContext,
    required String stage,
  }) async {
    try {
      await action();
    } catch (error) {
      SafeDiagnostics.logFailure(
        '[$logContext] import_rollback_failed stage=$stage',
        error,
      );
    }
  }
}

/// Which on-disk directories a `.tox` import created, and may therefore delete
/// when rolling back. See [ImportedAccountRollback].
final class ImportedAccountOwnership {
  const ImportedAccountOwnership({
    required this.ownsProfileDirectory,
    required this.ownsAccountDataRoot,
  });

  /// "This import created nothing on disk" — the safe default.
  const ImportedAccountOwnership.none()
    : ownsProfileDirectory = false,
      ownsAccountDataRoot = false;

  final bool ownsProfileDirectory;
  final bool ownsAccountDataRoot;
}
