import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'bootstrap_node_ensurer.dart';
import 'irc_app_manager.dart';
import 'ios_backup_policy.dart';
import 'logger.dart';
import 'locale_controller.dart';
import '../call/bg_refresh_bridge.dart';
import '../i18n/app_localizations.dart';
import '../runtime/runtime_foreground_service.dart';
import '../runtime/session_runtime_coordinator.dart';
import '../runtime/tim_sdk_initializer.dart';

/// Orchestrates runtime assembly and service startup: SessionRuntimeCoordinator,
/// TIMManager SDK, history hook, and polling. Used from the startup gate so UI
/// code does not assemble these.
class AppBootstrapCoordinator {
  AppBootstrapCoordinator._();

  /// Initialize session runtime (FakeUIKit, platform, CallServiceManager), TIM
  /// SDK, history hook, and polling.
  /// Throws on failure so the caller can show error/retry UI.
  static Future<void> boot(FfiChatService service) async {
    final runtime = SessionRuntimeCoordinator(service: service);
    await _runCoreStartupSequence(
      initializeRuntime: runtime.ensureInitialized,
      initializeTimSdk: TimSdkInitializer.ensureInitialized,
      installHistoryHook: runtime.installHistoryHookAfterTimSdkInitialized,
      startPolling: () async {
        AppLogger.log('[AppBootstrapCoordinator] Starting polling...');
        await service.startPolling();
        AppLogger.log('[AppBootstrapCoordinator] Polling started');
      },
    );

    // Guarantee the live instance has DHT bootstrap nodes applied. init()'s
    // _loadAndApplySavedBootstrapNode only applies what was already persisted,
    // which is nothing on a brand-new account — registration never seeds a
    // node. Every startup path (auto-login, manual login, registration) funnels
    // through here, so this is the one place that closes the
    // fresh-account-can't-connect gap. Applies the saved node synchronously and
    // (in auto mode) refreshes from the live list in the background.
    await BootstrapNodeEnsurer.ensureForSession(service);

    // Restore the account's IRC channels + reconnect as part of session boot.
    // Every login/switch/registration path funnels through here, and by this
    // point the current-account toxId is set and the service's knownGroups are
    // loaded (from init()), so account-scoped IRC prefs resolve correctly. This
    // decouples IRC restore from the Applications page being built — the page
    // previously owned the only restore call, so IRC silently didn't reconnect
    // on login until the user opened that tab. Non-fatal: an IRC failure must
    // never block login.
    await _restoreIrcSession(service);

    // Android: launch the persistent foreground service so the tox polling
    // loop survives the app going into the background. No-op on other
    // platforms (the wrapper short-circuits on !Platform.isAndroid). Failures
    // here are non-fatal — the wrapper logs them; we'd rather have the
    // session running with degraded background behaviour than refuse to
    // start.
    if (Platform.isAndroid) {
      unawaited(_startAndroidForegroundService());
    }

    // iOS: now that the account is logged in and toxId is known, apply the
    // account backup policy (H8 part 1, 2026-05-19 persistence review).
    //   - file_recv: derivable received-file scratch space; should not bloat
    //     backups.
    //   - active profile root / p_<prefix>: holds the tox profile (private
    //     key). Its exclusion is awaited and a failure aborts boot so the
    //     caller can present the existing retry/error UI.
    // The chat history and offline queue are intentionally NOT excluded —
    // they are user data and remain restorable.
    if (Platform.isIOS) {
      // Only the real Tox address may identify persistent profile paths.
      // accountKey/selfId can fall back to the V2TIM `FlutterUIKitClient`
      // placeholder, which would mark the wrong p_<prefix> directory.
      final toxId = service.getSelfToxId();
      if (toxId == null || toxId.trim().isEmpty) {
        throw StateError(
          'Cannot apply iOS backup policy without the real account Tox ID',
        );
      }
      await IosPostLoginBackupExcluder(isIos: true).apply(toxId);
      _wireIosBgRefresh(service);
    }
  }

  static Future<void> _runCoreStartupSequence({
    required FutureOr<void> Function() initializeRuntime,
    required FutureOr<void> Function() initializeTimSdk,
    required FutureOr<void> Function() installHistoryHook,
    required FutureOr<void> Function() startPolling,
  }) async {
    await initializeRuntime();
    await initializeTimSdk();
    await installHistoryHook();
    await startPolling();
  }

  /// Runs the production core startup sequencer with controlled actions.
  @visibleForTesting
  static Future<void> debugRunCoreStartupSequence({
    required FutureOr<void> Function() initializeRuntime,
    required FutureOr<void> Function() initializeTimSdk,
    required FutureOr<void> Function() installHistoryHook,
    required FutureOr<void> Function() startPolling,
  }) {
    return _runCoreStartupSequence(
      initializeRuntime: initializeRuntime,
      initializeTimSdk: initializeTimSdk,
      installHistoryHook: installHistoryHook,
      startPolling: startPolling,
    );
  }

  /// Restores IRC install state + channel→group mappings for the just-booted
  /// account and reconnects live channels (when the native library is
  /// available). Idempotent w.r.t. the Applications page's own restore call.
  static Future<void> _restoreIrcSession(FfiChatService service) async {
    try {
      final manager = IrcAppManager();
      await manager.init();
      await manager.restoreChannelMappings(service);
    } catch (e, st) {
      AppLogger.logError(
        '[AppBootstrapCoordinator] IRC session restore failed (non-fatal)',
        e,
        st,
      );
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
  /// See `doc/architecture/MOBILE_BACKGROUND.md` for the broader story
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
          '[AppBootstrapCoordinator] BG refresh callback failed',
          e,
          st,
        );
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
        st,
      );
    }
  }
}
