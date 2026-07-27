import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
import '../util/account_service.dart';
import '../util/placeholder_account_migration.dart';
import '../util/prefs.dart';

/// Input parameters for [LoginUseCase.execute].
class LoginParams {
  const LoginParams({
    required this.nickname,
    required this.statusMessage,
    this.password,
  });

  final String nickname;
  final String statusMessage;
  final String? password;
}

/// Result of a successful login.
class LoginSuccess {
  const LoginSuccess({required this.service});

  final FfiChatService service;
}

/// Encapsulates login business logic: account resolution, service initialization,
/// TIMManager SDK init, and prefs persistence. UI only validates form and navigates.
class LoginUseCase {
  LoginUseCase();

  /// Performs login. Returns [LoginSuccess] or throws.
  /// Caller is responsible for password prompt when account has password.
  Future<LoginSuccess> execute(LoginParams params) async {
    final nickname = params.nickname.trim();
    final statusMessage = params.statusMessage.trim();

    if (nickname.isEmpty) {
      throw Exception('Nickname cannot be empty');
    }

    // TODO(codex-review-3): manual login path also needs the placeholder
    // migration trigger — auto-login path runs it from `StartupSessionUseCase`
    // before any account lookup, but a user who toggles off auto-login and
    // logs in manually never runs it. Calling it here pre-lookup mirrors the
    // auto-login ordering so the nickname resolves to the migrated record.
    // Current limitation: `_discoverRealToxId()` opens an unauthenticated
    // discovery service, so encrypted profiles cannot be decrypted at this
    // point. The proper fix is to invoke a post-login variant that takes the
    // live, already-decrypted `FfiChatService` and reads its
    // `getSelfToxId()` — see `placeholder_account_migration.dart`. For now
    // this is a best-effort pre-lookup call that no-ops on encrypted state.
    await PlaceholderAccountMigration.migrateIfNeeded();

    final account = await Prefs.getUniqueAccountByNickname(nickname);
    if (account == null) {
      final savedNickname = await Prefs.getNickname();
      if (savedNickname == null || savedNickname.trim().isEmpty) {
        throw Exception('User not found; please register');
      }
      if (savedNickname.trim() != nickname) {
        throw Exception('Nickname does not match');
      }
    }

    final toxIdForLogin = account?['toxId'];
    if (toxIdForLogin != null && toxIdForLogin.isNotEmpty) {
      await AccountService.throwIfAccountDeleting(toxIdForLogin);
      final hasPassword = await Prefs.hasAccountPassword(toxIdForLogin);
      if (hasPassword) {
        final password = params.password ?? '';
        if (password.isEmpty) {
          throw Exception('Password required');
        }
        final ok = await Prefs.verifyAccountPassword(toxIdForLogin, password);
        if (!ok) {
          throw Exception('Invalid password');
        }
      }

      final service = await AccountService.initializeServiceForAccount(
        toxId: toxIdForLogin,
        nickname: nickname,
        statusMessage: statusMessage,
        password: params.password,
        startPolling:
            false, // caller (e.g. login page) will call AppBootstrapCoordinator.boot(service) before navigating to HomePage
      );

      await Prefs.setNickname(nickname);
      await Prefs.setStatusMessage(statusMessage);

      final avatarForAccount = account != null
          ? (account['avatarPath'] ?? '')
          : '';
      // Use toxIdForLogin (existing account key) so we update the list entry instead of
      // being treated as a new account; service.selfId may differ in format (e.g. 76 vs 64 chars).
      // Skip the lastLoginTime bump here; the caller is responsible for
      // calling Prefs.touchAccountLoginTime() once AppBootstrapCoordinator.boot
      // has actually succeeded — otherwise a failed boot would still surface
      // this account as "recently logged in" in the picker.
      await Prefs.addAccount(
        toxId: toxIdForLogin,
        nickname: nickname,
        statusMessage: statusMessage,
        avatarPath: avatarForAccount.isNotEmpty ? avatarForAccount : null,
        updateLastLogin: false,
      );

      return LoginSuccess(service: service);
    }

    // Legacy account without toxId. The per-account preferences adapter is
    // constructed without a prefix and gets the 16-char Tox-ID prefix injected
    // via `setAccountPrefix` once `service.login()` resolves selfId, so manual
    // bootstrap-node settings actually take effect on this code path —
    // `BootstrapNodesAdapter` only implements the three-field BootstrapService
    // API and the legacy path otherwise loses `bootstrap_node_mode` plumbing.
    final prefs = await SharedPreferences.getInstance();
    final legacyPrefsAdapter = SharedPreferencesAdapter(prefs);
    final legacyService = FfiChatService(
      preferencesService: legacyPrefsAdapter,
      loggerService: AppLoggerAdapter(),
      bootstrapService: BootstrapNodesAdapter(prefs),
    );
    await legacyService.init();
    await legacyService.login(
      userId: 'FlutterUIKitClient',
      userSig: 'dummy_sig',
    );
    // `selfId` returns the V2TIM login `userId` we just passed in (the
    // `FlutterUIKitClient` placeholder), NOT the Tox identity. For any
    // toxId-keyed persistence (account record, current-account pointer,
    // per-account-prefs prefix, file paths) we must use the 76-char Tox
    // address from `getSelfToxId()` instead — historically toxee stored the
    // placeholder here, corrupting account_list entries to the literal
    // string "FlutterUIKitClient".
    final toxId = legacyService.getSelfToxId();
    if (toxId == null || toxId.isEmpty) {
      throw StateError(
        'LoginUseCase: getSelfToxId() returned null after login — the '
        'Tox FFI did not produce a self address. Refusing to persist an '
        'account record under a placeholder identity.',
      );
    }
    legacyService.installScratchFileService(
      await AccountService.createScratchStorageForAccount(toxId),
    );
    legacyPrefsAdapter.setAccountPrefix(
      toxId.substring(0, toxId.length >= 16 ? 16 : toxId.length),
    );
    // Apply the profile BEFORE persisting any durable prefs (mirrors the
    // StartupSessionUseCase auto-login path). updateSelfProfile only needs the
    // account prefix set above; persisting the nickname / current-account
    // pointer / account record first meant a throw here left a registered,
    // half-initialized account that the next cold start would auto-resolve to
    // (teardown does not revert these prefs). Ordering the durable writes last
    // keeps the failure path clean — nothing is persisted unless the profile
    // applied.
    await legacyService.updateSelfProfile(
      nickname: nickname,
      statusMessage: statusMessage,
    );
    await Prefs.setNickname(nickname);
    await Prefs.setStatusMessage(statusMessage);
    await Prefs.setCurrentAccountToxId(toxId);
    // Same rationale as the StartupSessionUseCase path — defer lastLoginTime
    // until the caller has booted the full app coordinator successfully.
    await Prefs.addAccount(
      toxId: toxId,
      nickname: nickname,
      statusMessage: statusMessage,
      updateLastLogin: false,
    );
    // Caller (e.g. login page) must call AppBootstrapCoordinator.boot(service) before navigating to HomePage
    return LoginSuccess(service: legacyService);
  }
}
