import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
import '../util/account_export_service.dart';
import '../util/account_service.dart';
import '../util/app_bootstrap_coordinator.dart';
import '../util/app_paths.dart';
import '../util/default_avatar_installer.dart';
import '../util/placeholder_account_migration.dart';
import '../util/prefs.dart';
import '../util/safe_diagnostics.dart';

import 'startup_outcome.dart';
import 'startup_step.dart';

typedef StartupInitializeServiceFn =
    Future<FfiChatService> Function({
      required String toxId,
      String? nickname,
      String? statusMessage,
      String? password,
      bool startPolling,
    });
typedef StartupTeardownSessionFn =
    Future<void> Function({FfiChatService? service, bool reEncryptProfile});

/// Encapsulates startup policy: user check, service init, bootstrap, connection.
/// Failures before a ready outcome are cleaned up here. A ready outcome transfers
/// its service and uncommitted activation lease to the widget, which owns
/// navigation-time commit or teardown and rollback.
class StartupSessionUseCase {
  StartupSessionUseCase({
    Future<void> Function(FfiChatService service)? bootSession,
    StartupInitializeServiceFn? initializeServiceForAccount,
    StartupTeardownSessionFn? teardownSession,
  }) : _bootSession = bootSession ?? AppBootstrapCoordinator.boot,
       _initializeServiceForAccount =
           initializeServiceForAccount ??
           AccountService.initializeServiceForAccount,
       _teardownSession =
           teardownSession ?? AccountService.teardownCurrentSession;

  final Future<void> Function(FfiChatService service) _bootSession;
  final StartupInitializeServiceFn _initializeServiceForAccount;
  final StartupTeardownSessionFn _teardownSession;

  /// Runs the startup flow. Reports steps via [onStepChanged].
  /// When already connected, calls [loadFriends] then returns [StartupOpenHome].
  /// When not connected, returns [StartupWaitForConnection]; the widget must
  /// wait for connection, call [loadFriends], then navigate.
  Future<StartupOutcome> execute({
    required void Function(StartupStep) onStepChanged,
    required Future<void> Function(FfiChatService) loadFriends,
  }) async {
    FfiChatService? service;
    AccountActivationTransaction? activation;
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
        } catch (probeError) {
          SafeDiagnostics.logFailure(
            '[StartupSessionUseCase] encrypted-profile probe failed; '
            'continuing with init',
            probeError,
          );
        }

        activation = await AccountActivationTransaction.begin();
        service = await _initializeServiceForAccount(
          toxId: toxIdForStartup,
          nickname: nick,
          statusMessage: statusMsg ?? '',
          startPolling: false,
        );
      } else {
        activation = await AccountActivationTransaction.begin();
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
        // Legacy path bypasses AccountService.initializeServiceForAccount,
        // so apply the same self-avatar guarantee here (see that method).
        await DefaultAvatarInstaller.ensureSelfAvatar(toxId: toxId);
      }

      final currentService = service;

      onStepChanged(StartupStep.loggingIn);
      await _bootSession(currentService);

      onStepChanged(StartupStep.connecting);

      if (currentService.isConnected) {
        onStepChanged(StartupStep.loadingFriends);
        await loadFriends(currentService);
        onStepChanged(StartupStep.completed);
        final readyActivation = activation;
        activation = null;
        return StartupOpenHome(currentService, readyActivation);
      }

      final waitingActivation = activation;
      activation = null;
      return StartupWaitForConnection(currentService, waitingActivation);
    } catch (e) {
      if (service != null) {
        try {
          await _teardownSession(service: service, reEncryptProfile: true);
        } catch (cleanupError) {
          SafeDiagnostics.logFailure(
            '[StartupSessionUseCase] cleanup after startup failure',
            cleanupError,
          );
        }
      }
      final pendingActivation = activation;
      if (pendingActivation != null) {
        try {
          await pendingActivation.rollback();
        } catch (rollbackError) {
          SafeDiagnostics.logFailure(
            '[StartupSessionUseCase] current-account rollback after startup failure',
            rollbackError,
          );
        }
      }
      SafeDiagnostics.logFailure('[StartupSessionUseCase] startup failed', e);
      return StartupShowError(SafeDiagnostics.describeError(e));
    }
  }
}
