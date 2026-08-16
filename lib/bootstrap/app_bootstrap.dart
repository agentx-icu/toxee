import 'dart:async';
import 'dart:io';

import '../call/call_media_capabilities.dart';
import '../notifications/notification_service.dart';
import '../util/account_export_service.dart';
import '../util/account_reconciliation.dart';
import '../util/account_scratch_storage.dart';
import '../util/account_service.dart';
import '../util/app_paths.dart';
import '../util/lan_bootstrap_service.dart';
import '../util/logger.dart';
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
    await cleanupScratchAtColdStart();
    // Fail closed: journaled restore recovery must finish before account
    // reconciliation or any later auto-login path can expose partial state.
    await recoverPendingRestoreBeforeAccountExposure();
    // If the previous run crashed while the LAN bootstrap service was active,
    // the running-flag plus pre-LAN snapshot may still be on disk while no
    // native instance exists. Restore the prior bootstrap node and clear the
    // stale flag so the user is not stuck pointing at a dead LAN address.
    try {
      await LanBootstrapServiceManager.instance.recoverFromCrashedSession();
    } catch (e, st) {
      AppLogger.logError(
        '[AppBootstrap] LAN bootstrap crash recovery failed; continuing',
        e,
        st,
      );
    }
    await AppRuntimeBootstrap.initialize();
    // Learn whether this DEVICE actually has a camera before anything can offer
    // a video call, so a camera-less device never raises a camera permission
    // sheet it cannot resolve (that modal covers the app and blocks even VOICE
    // calls). Backgrounded: inconclusive until it resolves means "platform
    // default", which is the old behaviour. See
    // CallMediaCapabilities.refreshCaptureDevices.
    unawaited(CallMediaCapabilities.refreshCaptureDevices());
    await DesktopShellBootstrap.initializeIfNeeded();
    // OS-level notifications. Lazy-safe — the service no-ops on unsupported
    // platforms and the V2TimAdvancedMsgListener that actually drives
    // showMessageNotification() is registered later (HomePage, after the
    // session is fully bootstrapped) so historical messages loaded during
    // the session-warmup phase don't trigger banners.
    try {
      await NotificationService.instance.init();
    } catch (e, st) {
      // Don't let a notification-init failure block app startup.
      AppLogger.logError(
        '[AppBootstrap] NotificationService.init failed; continuing',
        e,
        st,
      );
    }
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

  /// Best-effort cold-start cleanup. Storage maintenance must never prevent
  /// the login flow from starting.
  static Future<void> cleanupScratchAtColdStart({
    Future<void> Function()? cleanup,
  }) async {
    try {
      await (cleanup ?? AccountScratchStorage.cleanupExpiredAtStartup)();
    } catch (e, st) {
      AppLogger.logError(
        '[AppBootstrap] scratch cleanup failed; continuing',
        e,
        st,
      );
    }
  }

  static Future<void> recoverPendingRestoreBeforeAccountExposure({
    Future<void> Function()? recoverPendingRestore,
    Future<void> Function()? recoverPendingDeletions,
    Future<void> Function()? reconcileAccounts,
  }) async {
    final recover =
        recoverPendingRestore ??
        AccountExportService.recoverPendingFullBackupRestore;
    final reconcile =
        reconcileAccounts ??
        () async {
          await AccountReconciliation.reconcileOrphanedProfiles();
        };
    final recoverDeletions =
        recoverPendingDeletions ??
        () async {
          await AccountService.recoverPendingAccountDeletions();
        };

    await recover();
    await recoverDeletions();
    await reconcile();
  }
}
