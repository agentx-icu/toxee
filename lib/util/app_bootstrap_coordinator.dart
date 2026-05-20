import 'dart:async';
import 'dart:io';

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'app_paths.dart';
import 'logger.dart';
import 'locale_controller.dart';
import '../call/bg_refresh_bridge.dart';
import '../i18n/app_localizations.dart';
import '../runtime/runtime_foreground_service.dart';
import '../runtime/session_runtime_coordinator.dart';
import '../runtime/tim_sdk_initializer.dart';

/// Orchestrates runtime assembly and service startup: SessionRuntimeCoordinator,
/// TIMManager SDK, and polling. Used from the startup gate so UI code does not assemble these.
class AppBootstrapCoordinator {
  AppBootstrapCoordinator._();

  /// Initialize session runtime (FakeUIKit, platform, CallServiceManager), TIM SDK, and start polling.
  /// Throws on failure so the caller can show error/retry UI.
  static Future<void> boot(FfiChatService service) async {
    await SessionRuntimeCoordinator(service: service).ensureInitialized();
    await TimSdkInitializer.ensureInitialized();

    AppLogger.log('[AppBootstrapCoordinator] Starting polling...');
    await service.startPolling();
    AppLogger.log('[AppBootstrapCoordinator] Polling started');

    // Android: launch the persistent foreground service so the tox polling
    // loop survives the app going into the background. No-op on other
    // platforms (the wrapper short-circuits on !Platform.isAndroid). Failures
    // here are non-fatal — the wrapper logs them; we'd rather have the
    // session running with degraded background behaviour than refuse to
    // start.
    if (Platform.isAndroid) {
      unawaited(_startAndroidForegroundService());
    }

    // iOS: now that the account is logged in and toxId is known, mark the
    // regenerable / private-key directories excluded from iCloud / iTunes
    // backup (H8 part 1, 2026-05-19 persistence review).
    //   - file_recv: derivable received-file scratch space; should not bloat
    //     backups.
    //   - tim2tox/: holds the tox profile (private key). Excluded so it
    //     never leaves the device through iCloud. The chat history directory
    //     is intentionally NOT excluded — that's the user's irreplaceable
    //     data and must remain restorable.
    if (Platform.isIOS) {
      final toxId = service.selfId;
      if (toxId.isNotEmpty) {
        unawaited(_markIosPostLoginExclusions(toxId));
      }
      _wireIosBgRefresh(service);
    }
  }

  /// On iOS, whenever the OS grants us a BGAppRefreshTask window, the
  /// `BgRefreshBridge` invokes the registered callback. We use that callback
  /// to give the polling loop a brief CPU slice. `startPolling` is idempotent
  /// — calling it a second time after first init is cheap and just keeps the
  /// loop warm during the short refresh window. The callback returns quickly
  /// so the native watchdog can mark the BG task complete well within
  /// Apple's 30-sec budget.
  ///
  /// See `doc/architecture/MOBILE_BACKGROUND.en.md` for the broader story
  /// and the PushKit limitation.
  static void _wireIosBgRefresh(FfiChatService service) {
    BgRefreshBridge.instance.onRefresh = () async {
      try {
        AppLogger.log('[AppBootstrapCoordinator] BG refresh window opened');
        await service.startPolling();
        // No active wait — startPolling kicks the native polling loop, which
        // runs on its own thread; iOS's BG window keeps the process alive
        // for ~25 sec while that thread drains pending events.
      } catch (e, st) {
        AppLogger.logError(
            '[AppBootstrapCoordinator] BG refresh callback failed', e, st);
      }
    };
  }

  /// Resolves localized strings via the user's currently-selected locale
  /// (no [BuildContext] needed) and asks the native side to bring the
  /// foreground service up in dataSync mode.
  static Future<void> _startAndroidForegroundService() async {
    try {
      final l10n = lookupAppLocalizations(AppLocale.locale.value);
      await RuntimeForegroundService.instance.start(
        title: l10n.runtimeForegroundTitle,
        body: l10n.runtimeForegroundBody,
        settingsLabel: l10n.runtimeForegroundSettingsLabel,
      );
    } catch (e, st) {
      AppLogger.logError(
          '[AppBootstrapCoordinator] foreground service start failed '
          '(non-fatal — background polling may be killed by the OS)',
          e,
          st);
    }
  }

  static Future<void> _markIosPostLoginExclusions(String toxId) async {
    try {
      final fileRecv = await AppPaths.getAccountFileRecvPath(toxId);
      await AppPaths.markExcludedFromBackup(fileRecv);
      final profileDir = (await AppPaths.toxProfileDir).path;
      await AppPaths.markExcludedFromBackup(profileDir);
      // Avatar cache is fully regenerable from peers / self profile —
      // excluding it from iCloud backup keeps the user's backup size down
      // without losing any unrecoverable data.
      final avatarsDir = await AppPaths.getAccountAvatarsPath(toxId);
      await AppPaths.markExcludedFromBackup(avatarsDir);
    } catch (e, st) {
      AppLogger.logError(
          '[AppBootstrapCoordinator] iOS backup-exclusion marking failed '
          '(non-fatal)',
          e,
          st);
    }
  }
}
