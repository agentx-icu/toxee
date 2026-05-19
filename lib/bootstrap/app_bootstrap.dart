import 'dart:async';
import 'dart:io';

import '../util/account_reconciliation.dart';
import '../util/app_paths.dart';
import 'app_bootstrap_result.dart';
import 'app_runtime_bootstrap.dart';
import 'desktop_shell_bootstrap.dart';
import 'logging_bootstrap.dart';
import 'prefs_bootstrap.dart';

/// Application startup orchestration. [initialize] runs logging, prefs, runtime,
/// and desktop shell (if applicable), then returns a result for the caller to
/// run the appropriate app.
class AppBootstrap {
  AppBootstrap._();

  static Future<AppBootstrapResult> initialize() async {
    await LoggingBootstrap.initialize();
    final prefsResult = await PrefsBootstrap.initialize();
    if (prefsResult != null) {
      return prefsResult;
    }
    // After Prefs is initialized, repair any orphaned per-account profile
    // directories left behind by a partially-completed import (A2). Safe
    // to run on every cold start; no-op when nothing is orphaned.
    await AccountReconciliation.reconcileOrphanedProfiles();
    await AppRuntimeBootstrap.initialize();
    await DesktopShellBootstrap.initializeIfNeeded();
    // iOS: keep received-file scratch space out of iCloud / iTunes backups.
    // file_recv holds derivable / re-transferable content; Apple's review
    // guidelines forbid letting it be backed up. markExcludedFromBackup is
    // a no-op on every other platform. The global file_recv path is used
    // here (per-account dirs are marked when their AccountService boots).
    if (Platform.isIOS) {
      unawaited(() async {
        final path = await AppPaths.fileRecvPath;
        await AppPaths.markExcludedFromBackup(path);
      }());
    }
    return const AppBootstrapSuccess();
  }
}

