import 'dart:async';
import 'dart:io';

import 'package:tencent_cloud_chat_common/widgets/avatar/tencent_cloud_chat_avatar.dart';

import '../call/call_media_capabilities.dart';
import '../notifications/notification_service.dart';
import '../util/account_export_service.dart';
import '../util/account_deletion_journal.dart';
import '../util/account_export/tox_import_journal.dart';
import '../util/placeholder_identity_discovery.dart';
import '../util/account_reconciliation.dart';
import '../util/account_scratch_storage.dart';
import '../util/account_service.dart';
import '../util/app_paths.dart';
import '../util/lan_bootstrap_service.dart';
import '../util/logger.dart';
import '../util/safe_diagnostics.dart';
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
    // BEFORE the preferences guard and the recovery phase, because it must not
    // depend on either. A decrypted profile copy stranded by a kill is a
    // plaintext private key; placed after them, a failed preferences upgrade
    // (which returns early) or an unreadable journal (which raises the blocked
    // screen) meant it survived every subsequent start. Nothing else removes it:
    // account deletion does not know these directories exist, and discovery may
    // never run again.
    await _sweepStrandedScratchCopies();
    final prefsResult = await PrefsBootstrap.initialize();
    if (prefsResult != null) {
      return prefsResult;
    }
    await cleanupScratchAtColdStart();
    // Fail closed: journaled restore recovery must finish before account
    // reconciliation or any later auto-login path can expose partial state.
    //
    // "Fail closed" means no account is exposed — NOT that the app refuses to
    // render. This used to throw straight past `runApp` in `main()`, so an
    // unparseable journal (a truncated write is precisely what these journals
    // exist to survive) produced a black screen with no message and no way in.
    // Convert it into a blocking recovery screen instead, which preserves the
    // guarantee the recovery-order test pins while leaving the user something
    // actionable.
    try {
      await recoverPendingRestoreBeforeAccountExposure();
    } catch (e, st) {
      // Sanitize at the LOG too, not just on the screen. `AppLogger.logError`
      // interpolates the error verbatim, and these are filesystem and JSON
      // exceptions: the former carry journal paths (which embed the account's
      // public-key prefix and the absolute app-support layout), the latter can
      // carry journal contents. The stack is kept — it has no payload.
      final detail = SafeDiagnostics.describeError(e);
      AppLogger.logError(
        '[AppBootstrap] account recovery could not be completed; refusing to '
        'expose any account: $detail',
        null,
        st,
      );
      return AppBootstrapRecoveryBlocked(detail: detail);
    }
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
    // Every "no avatar" contact, group member and friend request renders
    // through the UIKit avatar widget, whose bundled placeholder is a stock
    // photo of a hand holding a phone — off-brand next to toxee's own default
    // (assets/avatars/default_user.png, installed for the self account) and
    // misleading as an identity. Point the widget at toxee's neutral contact
    // placeholder instead; it is the same silhouette in a slate tint so a
    // contact without an avatar is still distinguishable from self.
    TencentCloudChatAvatar.defaultAvatarAsset =
        'assets/avatars/default_contact.png';
    TencentCloudChatAvatar.defaultAvatarAssetPackage = null;
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

  /// Never lets a cleanup failure stop the app: a stranded copy is a problem,
  /// an app that will not start is a bigger one.
  static Future<void> _sweepStrandedScratchCopies() async {
    try {
      await sweepPlaceholderDiscoveryScratch();
    } catch (e, st) {
      AppLogger.logError(
        '[AppBootstrap] stranded scratch sweep failed; continuing',
        e,
        st,
      );
    }
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
        () async {
          // Both journalled import paths, before anything can expose an
          // account. The `.zip` restore has had a journal since its own review;
          // the single-file `.tox` path is journalled too now (it wrote the same
          // durable state in the same order with only an in-process catch,
          // which a kill does not run).
          await AccountExportService.recoverPendingFullBackupRestore();
          await ToxImportJournal.recoverPendingImport();
        };
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
    // A deletion record we could neither parse NOR attribute to an account means
    // some account may be half-deleted with nothing gating it. There is no safe
    // guess, so refuse to expose any account — the caller turns this into the
    // blocking recovery screen. Attributable corruption does not reach here:
    // `_quarantine` rebuilds the tombstone from the filename.
    final unattributable = AccountDeletionJournalStore.unattributableQuarantine;
    if (unattributable.isNotEmpty) {
      throw StateError(
        'unattributable account deletion record(s): ${unattributable.length}',
      );
    }
    // Same reasoning for an interrupted `.tox` import whose rollback could not be
    // established: a half-imported profile may still be on disk, and
    // `reconcile()` below would publish it as an account.
    final unresolvedImports = ToxImportJournal.unresolved;
    if (unresolvedImports.isNotEmpty) {
      throw StateError(
        'unresolved interrupted account import(s): ${unresolvedImports.length}',
      );
    }
    // An UNREADABLE import journal names no account, so blocking the whole app
    // would be a dead end — the user's existing accounts are fine and they could
    // do nothing about it. Skip only orphan adoption, so no leftover profile from
    // that interrupted import gets published as an account, and let everything
    // else start. The journal file stays on disk, so this holds across restarts
    // until an import completes or is verifiably rolled back.
    if (ToxImportJournal.hasUnreadableJournal) {
      AppLogger.warn(
        '[AppBootstrap] an interrupted account import cannot be attributed; '
        'skipping orphaned-profile adoption this run',
      );
      return;
    }
    await reconcile();
  }
}
