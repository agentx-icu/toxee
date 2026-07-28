import 'dart:io';

import 'app_paths.dart';
import 'prefs.dart';
import 'safe_diagnostics.dart';

abstract final class ImportedAccountRollback {
  static Future<void> run({
    required String toxId,
    required String logContext,
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
    await _attempt(
      () async {
        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final dir = Directory(profileDir);
        if (await dir.exists()) await dir.delete(recursive: true);
      },
      logContext: logContext,
      stage: 'profile_directory',
    );
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
