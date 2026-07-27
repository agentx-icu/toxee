import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
import '../util/account_export_service.dart';
import '../util/account_service.dart';
import '../util/app_bootstrap_coordinator.dart';
import '../util/app_paths.dart';
import '../util/logger.dart';
import '../util/placeholder_account_migration.dart';
import '../util/prefs.dart';

import 'startup_outcome.dart';
import 'startup_step.dart';

/// Encapsulates startup policy: user check, service init, bootstrap, connection.
/// Ownership and cleanup of [FfiChatService] are handled here; the widget only
/// reacts to [StartupOutcome] and (for [StartupWaitForConnection]) sets up
/// timeout and connection listener.
class StartupSessionUseCase {
  /// Runs the startup flow. Reports steps via [onStepChanged].
  /// When already connected, calls [loadFriends] then returns [StartupOpenHome].
  /// When not connected, returns [StartupWaitForConnection]; the widget must
  /// wait for connection, call [loadFriends], then navigate.
  Future<StartupOutcome> execute({
    required void Function(StartupStep) onStepChanged,
    required Future<void> Function(FfiChatService) loadFriends,
  }) async {
    FfiChatService? service;
    try {
      onStepChanged(StartupStep.checkingUserInfo);
      await AccountService.recoverPendingAccountDeletions();
      final nick = await Prefs.getNickname();
      final statusMsg = await Prefs.getStatusMessage();
      final autoLogin = await Prefs.getAutoLogin();

      if (nick == null || nick.trim().isEmpty) {
        return const StartupShowLogin();
      }
      if (!autoLogin) {
        return const StartupShowLogin();
      }

      onStepChanged(StartupStep.initializingService);

      // Bootstrap mode normalization (mobile 'lan' → 'auto') happens once at
      // startup in PrefsBootstrap.initialize, before any init() reads it.
      // Applying nodes to the live instance is handled centrally by
      // AppBootstrapCoordinator.boot → BootstrapNodeEnsurer.ensureForSession,
      // which every startup path shares.

      // Migrate any account that was historically stored under the V2TIM
      // login placeholder (`FlutterUIKitClient`) before we look up the
      // account record by nickname — otherwise the lookup would return the
      // placeholder-keyed record and propagate the wrong toxId into the
      // session paths. Idempotent and safe to call when nothing needs
      // migrating (returns null and exits in microseconds).
      //
      // TODO(codex-review-3): this trigger only fires in the auto-login path
      // and only after the `nickname/autoLogin` early returns above. The
      // manual login path in `LoginUseCase` never invokes the migration, so
      // a user whose account is encrypted and who toggles off auto-login can
      // stay stuck under the `FlutterUIKitClient` namespace indefinitely.
      // Also, the migration's `_discoverRealToxId()` opens a discovery
      // FfiChatService without a password, which can't unlock encrypted
      // profile blobs. Long-term fix: thread the live `FfiChatService`'s
      // already-resolved `getSelfToxId()` into the migration so encrypted
      // profiles migrate post-login instead of via a separate probe. See
      // `LoginUseCase` for the matching stub.
      await PlaceholderAccountMigration.migrateIfNeeded();

      Map<String, String>? account;
      try {
        account = await Prefs.getUniqueAccountByNickname(nick);
      } on StateError {
        return const StartupShowLogin();
      }
      final toxIdForStartup = account?['toxId'];

      if (toxIdForStartup != null && toxIdForStartup.isNotEmpty) {
        // S40 Bug 3: an encrypted profile cannot auto-login. There is no
        // cross-process password cache (SessionPasswordStore is in-memory and
        // empty on cold start), so initializeServiceForAccount(password: null)
        // below would hand FFI an undecryptable blob and throw — surfacing a
        // generic StartupShowError. Detect it up front and route to the login
        // page instead, where tapping the account prompts for the password
        // (LoginPage._quickLogin → LoginUseCase → init WITH the password →
        // decrypt). Fail-open: a probe error must never block the normal init
        // path (the probe is advisory).
        try {
          final profilePath = await AppPaths.resolveToxProfilePath(
            toxIdForStartup,
          );
          if (profilePath != null &&
              await AccountExportService.isProfileFileEncrypted(profilePath)) {
            return const StartupShowLogin();
          }
        } catch (probeError, probeSt) {
          AppLogger.logError(
            '[StartupSessionUseCase] encrypted-profile probe failed; '
            'continuing with init',
            probeError,
            probeSt,
          );
        }

        service = await AccountService.initializeServiceForAccount(
          toxId: toxIdForStartup,
          nickname: nick,
          statusMessage: statusMsg ?? '',
          startPolling: false,
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        // CR-10: mirror LoginUseCase's legacy branch — construct the adapter
        // without a prefix, then inject the 16-char Tox-ID prefix once login
        // resolves selfId so account-scoped prefs (manual bootstrap node,
        // nickname, etc.) resolve to per-account keys instead of global ones.
        final legacyPrefsAdapter = SharedPreferencesAdapter(prefs);
        final legacyService = FfiChatService(
          preferencesService: legacyPrefsAdapter,
          loggerService: AppLoggerAdapter(),
          bootstrapService: BootstrapNodesAdapter(prefs),
        );
        // Assign the outer `service` BEFORE init/login so the catch below
        // tears the session down on any failure here. Deferring this to the
        // end leaked the already-initialized Tox instance when login (or a
        // later step) threw — the catch's `if (service != null)` guard saw
        // null and skipped teardownCurrentSession.
        service = legacyService;
        await legacyService.init();
        await legacyService.login(
          userId: 'FlutterUIKitClient',
          userSig: 'dummy_sig',
        );
        // See LoginUseCase: `selfId` returns the V2TIM login `userId`
        // placeholder, not the Tox identity. Use `getSelfToxId()` for any
        // toxId-keyed persistence (account record, pointer, prefs prefix,
        // file paths). Storing the placeholder here was the source of
        // `FlutterUIKitClient` showing as the User ID across the UI.
        final toxId = legacyService.getSelfToxId();
        if (toxId == null || toxId.isEmpty) {
          throw StateError(
            'StartupSessionUseCase: getSelfToxId() returned null after '
            'login — refusing to persist an account record under a '
            'placeholder identity. The caller should surface this so the '
            'user can retry rather than silently end up with a corrupted '
            'account_list entry.',
          );
        }
        legacyService.installScratchFileService(
          await AccountService.createScratchStorageForAccount(toxId),
        );
        legacyPrefsAdapter.setAccountPrefix(
          toxId.substring(0, toxId.length >= 16 ? 16 : toxId.length),
        );
        // Apply the profile BEFORE persisting the account pointer/record.
        // updateSelfProfile only needs the prefix (set above); persisting the
        // current-account pointer + account record first meant a throw here
        // left a registered, half-initialized account that the next cold
        // start would auto-resolve to (teardownCurrentSession does not revert
        // these prefs). Ordering the durable writes last keeps the failure
        // path clean — nothing is persisted unless the profile applied.
        await legacyService.updateSelfProfile(
          nickname: nick,
          statusMessage: statusMsg ?? '',
        );
        await Prefs.setCurrentAccountToxId(toxId);
        await Prefs.addAccount(
          toxId: toxId,
          nickname: nick,
          statusMessage: statusMsg ?? '',
          updateLastLogin: false,
        );
      }

      final currentService = service;

      onStepChanged(StartupStep.loggingIn);
      await AppBootstrapCoordinator.boot(currentService);

      try {
        // `selfId` is the V2TIM login placeholder — touching the account
        // record under that string is a silent no-op because `account_list`
        // is keyed by the real Tox ID. Resolve the real ID from the FFI;
        // fall back to the placeholder only if discovery failed (in which
        // case the touch was always going to be a no-op anyway).
        final touchId = currentService.getSelfToxId() ?? currentService.selfId;
        await Prefs.touchAccountLoginTime(touchId);
      } catch (_) {}

      onStepChanged(StartupStep.connecting);

      if (currentService.isConnected) {
        onStepChanged(StartupStep.loadingFriends);
        await loadFriends(currentService);
        onStepChanged(StartupStep.completed);
        return StartupOpenHome(currentService);
      }

      return StartupWaitForConnection(currentService);
    } catch (e) {
      if (service != null) {
        try {
          await AccountService.teardownCurrentSession(
            service: service,
            reEncryptProfile: true,
          );
        } catch (cleanupError, cleanupSt) {
          AppLogger.logError(
            '[StartupSessionUseCase] cleanup after startup failure',
            cleanupError,
            cleanupSt,
          );
        }
      }
      return StartupShowError(e.toString());
    }
  }
}
