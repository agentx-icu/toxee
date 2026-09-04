import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../runtime/session_runtime_coordinator.dart';
import 'package:tencent_cloud_chat_common/external/chat_data_provider.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import '../adapters/shared_prefs_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/bootstrap_adapter.dart';
import 'prefs.dart';
import 'prefs_upgrader.dart';
import 'account_deletion.dart';
import 'account_scratch_storage.dart';
import 'app_paths.dart';
import 'account_export_service.dart';
import 'default_avatar_installer.dart';
import 'session_password_store.dart';
import 'group_member_list_debouncer.dart';
import 'irc_app_manager.dart';
import 'logger.dart';
import 'safe_diagnostics.dart';
import 'short_tox_id_backfill.dart';

/// Result from [AccountService.registerNewAccount].
class RegisterResult {
  final FfiChatService service;
  final String toxId;
  final String profileDirectory;

  RegisterResult({
    required this.service,
    required this.toxId,
    required this.profileDirectory,
  });
}

enum AccountTeardownStage {
  runtimeDisposal,
  providerRegistryCleanup,
  singletonCacheCleanup,
  ircSessionShutdown,
  serviceDisposal,
  profileReEncryption,
  sessionPasswordClear,
}

final class AccountTeardownFailure implements Exception {
  const AccountTeardownFailure({
    required this.toxId,
    required this.stage,
    required this.cause,
    required this.stackTrace,
  });

  final String toxId;
  final AccountTeardownStage stage;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'Account teardown failed stage=${stage.name} '
        '${SafeDiagnostics.describeError(cause)}';
  }
}

/// Guards the durable active-account mirror while a session is initialized and
/// booted. Initialization may publish the candidate account before the runtime
/// is ready; callers commit only after full boot succeeds.
final class AccountActivationTransaction {
  AccountActivationTransaction._({
    required String? previousToxId,
    required String? previousNickname,
    required String? previousStatusMessage,
    required String? previousAvatarPath,
  }) : _previousToxId = previousToxId,
       _previousNickname = previousNickname,
       _previousStatusMessage = previousStatusMessage,
       _previousAvatarPath = previousAvatarPath;

  final String? _previousToxId;
  final String? _previousNickname;
  final String? _previousStatusMessage;
  final String? _previousAvatarPath;
  bool _committed = false;
  bool _rolledBack = false;

  static Future<AccountActivationTransaction> begin() async {
    final snapshot = await Future.wait<String?>([
      Prefs.getCurrentAccountToxId(),
      Prefs.getNickname(),
      Prefs.getStatusMessage(),
      Prefs.getAvatarPath(),
    ]);
    return AccountActivationTransaction._(
      previousToxId: snapshot[0],
      previousNickname: snapshot[1],
      previousStatusMessage: snapshot[2],
      previousAvatarPath: snapshot[3],
    );
  }

  void commit() {
    _committed = true;
  }

  Future<void> rollback() async {
    if (_committed || _rolledBack) return;
    await Prefs.setCurrentAccountToxId(_previousToxId);
    await Prefs.setNickname(_previousNickname ?? '');
    await Prefs.setStatusMessage(_previousStatusMessage ?? '');
    await Prefs.setAvatarPath(_previousAvatarPath);
    _rolledBack = true;
  }
}

abstract final class AccountTeardownTestHooks {
  AccountTeardownTestHooks._();

  @visibleForTesting
  static Future<void> Function(FfiChatService service)? shutdownIrcSession;

  @visibleForTesting
  static Future<void> Function(FfiChatService service)? disposeService;

  @visibleForTesting
  static Future<void> Function(String profilePath, String password)?
  encryptProfileFile;

  @visibleForTesting
  static void reset() {
    shutdownIrcSession = null;
    disposeService = null;
    encryptProfileFile = null;
  }
}

abstract final class AccountRegistrationTestHooks {
  AccountRegistrationTestHooks._();

  @visibleForTesting
  static Future<void> Function(FfiChatService service)? disposeService;

  @visibleForTesting
  static Future<void> Function(String profilePath, String password)?
  encryptProfileFile;

  @visibleForTesting
  static void reset() {
    disposeService = null;
    encryptProfileFile = null;
  }
}

/// Calculate text length where Chinese characters count as 1, and
/// letters/numbers/other characters count as 0.5.
double calculateTextLength(String text) {
  double length = 0;
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    if (char.codeUnitAt(0) >= 0x4E00 && char.codeUnitAt(0) <= 0x9FFF) {
      length += 1.0;
    } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
      length += 0.5;
    } else {
      length += 0.5;
    }
  }
  return length;
}

/// Centralized account lifecycle management.
///
/// Eliminates duplication across LoginPage, RegisterPage, AccountSwitcher,
/// SettingsPage, and main.dart by providing reusable static methods for
/// session teardown, service initialization, account registration, and
/// account deletion.
class AccountService {
  // ---------------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------------

  /// Teardown the current SDK session.
  ///
  /// Replaces the identical ~15-line teardown blocks previously duplicated in
  /// `SettingsPage._logout()`, `AccountSwitcher.switchAccount()`, and
  /// `SettingsPage._deleteAccount()`.
  ///
  /// Steps:
  /// 1. Dispose [Tim2ToxSdkPlatform] and reset to default MethodChannel.
  /// 2. Clear provider registries.
  /// 3. Dispose [FakeUIKit] singleton.
  /// 4. Dispose [FfiChatService].
  /// 5. Re-encrypt profile if the session had a password (skipped when
  ///    [reEncryptProfile] is `false`, e.g. during account deletion).
  /// 6. Clear [SessionPasswordStore].
  static Future<void> teardownCurrentSession({
    FfiChatService? service,
    bool reEncryptProfile = true,
  }) async {
    // Capture values before tearing down. `getSelfToxId()` returns the
    // real 76-char Tox address used as the toxId-keyed primary key in
    // `SessionPasswordStore`, profile paths, and `AppPaths`. `selfId`
    // here would return the V2TIM login placeholder
    // (`FlutterUIKitClient`) — which would look up the wrong (or empty)
    // password slot, point at the wrong profile directory, and clear a
    // namespace nothing was ever stored in. When `getSelfToxId()` is
    // null (very early teardown / pre-login), fall through to empty so
    // every subsequent guard skips silently rather than acting on
    // a placeholder.
    final toxId = service?.getSelfToxId() ?? '';
    final sessionPassword = toxId.isNotEmpty
        ? SessionPasswordStore.get(toxId)
        : null;

    AccountTeardownFailure? firstFailure;
    Future<bool> runStep(
      AccountTeardownStage stage,
      Future<void> Function() operation,
    ) async {
      try {
        await operation();
        return true;
      } catch (e, st) {
        SafeDiagnostics.logFailure(
          '[AccountService] teardown_failed stage=${stage.name}',
          e,
        );
        firstFailure ??= AccountTeardownFailure(
          toxId: toxId,
          stage: stage,
          cause: e,
          stackTrace: st,
        );
        return false;
      }
    }

    // Every teardown stage is mandatory and best-effort. A failure is recorded
    // but cannot prevent later stages from releasing their account-owned state.
    await runStep(
      AccountTeardownStage.runtimeDisposal,
      SessionRuntimeCoordinator.disposeRuntime,
    );

    await runStep(AccountTeardownStage.providerRegistryCleanup, () async {
      ChatDataProviderRegistry.provider = null;
      ChatMessageProviderRegistry.provider = null;
    });

    await runStep(AccountTeardownStage.singletonCacheCleanup, () async {
      GroupMemberListDebouncer().clear();
    });
    // IRC: tear down the LIVE native connections (threads/sockets) for the
    // account being logged out, not just the Dart cache — otherwise the old
    // account's IRC sockets keep running and can forward inbound IRC into the
    // NEXT account's Tox instance (cross-account bleed). Runs while `service` is
    // still alive (before dispose below). Falls back to a plain cache reset when
    // there is no live service to drive the native teardown.
    await runStep(AccountTeardownStage.ircSessionShutdown, () async {
      if (service != null) {
        final shutdownIrcSession = AccountTeardownTestHooks.shutdownIrcSession;
        if (shutdownIrcSession != null) {
          await shutdownIrcSession(service);
        } else {
          await IrcAppManager().shutdownSession(service);
        }
      } else {
        IrcAppManager().resetCache();
      }
    });

    // 4. Dispose service
    if (service != null) {
      await runStep(AccountTeardownStage.serviceDisposal, () async {
        final disposeService = AccountTeardownTestHooks.disposeService;
        if (disposeService != null) {
          await disposeService(service);
        } else {
          await service.dispose();
        }
      });
    }

    // 5. Re-encrypt profile on disk
    var profileReadyForPasswordClear = true;
    if (reEncryptProfile &&
        sessionPassword != null &&
        sessionPassword.isNotEmpty &&
        toxId.isNotEmpty) {
      profileReadyForPasswordClear = await runStep(
        AccountTeardownStage.profileReEncryption,
        () async {
          final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
          final profilePath = AppPaths.profileFileInDirectory(profileDir);
          if (await File(profilePath).exists()) {
            final encryptProfileFile =
                AccountTeardownTestHooks.encryptProfileFile ??
                AccountExportService.encryptProfileFile;
            await encryptProfileFile(profilePath, sessionPassword);
          }
        },
      );
    }

    // 6. Clear session password only after the profile is safely encrypted.
    // Retaining it after an encryption failure preserves in-process recovery.
    if (toxId.isNotEmpty && profileReadyForPasswordClear) {
      await runStep(AccountTeardownStage.sessionPasswordClear, () async {
        SessionPasswordStore.clear(toxId);
      });
    }

    final failure = firstFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, failure.stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // Live-session password updates
  // ---------------------------------------------------------------------------
  //
  // The on-disk profile is plaintext during an active session
  // (initializeServiceForAccount decrypts it before init); teardownCurrentSession
  // re-encrypts it on logout using the password in SessionPasswordStore. So any
  // mid-session password change MUST update SessionPasswordStore, or logout will
  // encrypt with the wrong (stale) password — or skip encryption — leaving the
  // on-disk encryption state out of sync with the verifier and breaking the next
  // launch. These two helpers own that contract so callers (the Settings page)
  // can't get it wrong. Both derive the canonical toxId from the live service
  // (getSelfToxId) — never the accountKey placeholder fallback, which must not
  // key durable password state.

  /// Set or change the account password mid-session. Writes the durable
  /// verifier (Prefs) AND updates the in-memory [SessionPasswordStore] so
  /// [teardownCurrentSession] re-encrypts the profile with the NEW password on
  /// logout. Returns whether the verifier write succeeded; the session store is
  /// only updated when it did (a failed verifier write must not arm logout to
  /// encrypt under a password the user can't later verify).
  static Future<bool> setAccountPassword(
    FfiChatService service,
    String password,
  ) async {
    final toxId = service.getSelfToxId();
    if (toxId == null || toxId.isEmpty) return false;
    final ok = await Prefs.setAccountPassword(toxId, password);
    if (ok) {
      SessionPasswordStore.set(toxId, password);
    }
    return ok;
  }

  /// Remove the account password mid-session. Removes the durable verifier
  /// (Prefs) AND clears the in-memory [SessionPasswordStore], so
  /// [teardownCurrentSession] does NOT re-encrypt the profile the user just
  /// chose to leave unprotected. Without the clear, logout re-encrypts with the
  /// now-removed password while the verifier is gone → next launch shows no
  /// password prompt and hands FFI an undecryptable blob (silent startup
  /// failure). Returns whether the verifier removal succeeded; the session
  /// password is retained when durable removal fails.
  static Future<bool> removeAccountPassword(FfiChatService service) async {
    final toxId = service.getSelfToxId();
    if (toxId == null || toxId.isEmpty) return false;
    final ok = await Prefs.removeAccountPassword(toxId);
    if (ok) {
      SessionPasswordStore.clear(toxId);
    }
    return ok;
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initialize [FfiChatService] for an existing account.
  ///
  /// Replaces the identical ~25-line service-init blocks previously duplicated
  /// in `LoginPage._login()`, `AccountSwitcher.switchAccount()`, and the
  /// startup gate in `main.dart`.
  ///
  /// Returns the fully-initialized, logged-in service with polling started.
  ///
  /// Set [startPolling] to `false` if the caller wants to control polling
  /// manually (e.g. the startup gate in main.dart which waits for connection).
  static Future<FfiChatService> initializeServiceForAccount({
    required String toxId,
    String? nickname,
    String? statusMessage,
    String? password,
    bool startPolling = true,
  }) async {
    await throwIfAccountDeleting(toxId);
    final previousAccount = await Prefs.getCurrentAccountToxId();
    // Snapshot the global nickname/statusMessage/avatarPath so we can roll
    // them back alongside `currentAccountToxId` if init fails. `_UserAvatar`
    // and other UI surfaces read these globals — if we updated the
    // current-account pointer but didn't restore the labels on rollback, the
    // sidebar would show the new (failed) account's identity over the
    // previously-active account's profile.
    final previousNickname = await Prefs.getNickname();
    final previousStatusMessage = await Prefs.getStatusMessage();
    final previousAvatarPath = await Prefs.getAvatarPath();
    FfiChatService? service;
    String? profileFile;
    bool profileWasDecrypted = false;
    bool initSucceeded = false;
    // Hoisted so the catch path can clear the post-backfill session-password
    // cache too — see the catch block below for why this matters.
    String? canonicalToxId;
    final accountPrefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final migrPrefs = await SharedPreferences.getInstance();

    try {
      await PrefsUpgrader.runAccountMigrations(migrPrefs, accountPrefix);

      await AppPaths.migrateAccountDataFromLegacy(toxId);

      final historyDirectory = await AppPaths.getAccountChatHistoryPath(toxId);
      final queueFilePath = await AppPaths.getAccountOfflineQueueFilePath(
        toxId,
      );
      final fileRecvPath = await AppPaths.getAccountFileRecvPath(toxId);
      final avatarsPath = await AppPaths.getAccountAvatarsPath(toxId);
      await Directory(historyDirectory).create(recursive: true);
      await Directory(avatarsPath).create(recursive: true);

      final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
      profileFile = AppPaths.profileFileInDirectory(profileDir);
      if (!await File(profileFile).exists()) {
        final legacyDir = await AppPaths.toxProfileDir;
        final legacyPath = p.join(legacyDir.path, 'tox_profile.tox');
        if (await File(legacyPath).exists()) {
          await Directory(profileDir).create(recursive: true);
          await File(legacyPath).copy(profileFile);
          AppLogger.log('[AccountService] profile_migration status=completed');
        } else {
          throw Exception('Profile not found for account');
        }
      }

      if (password != null && password.isNotEmpty) {
        final isEncrypted = await AccountExportService.isProfileFileEncrypted(
          profileFile,
        );
        if (isEncrypted) {
          await AccountExportService.decryptProfileFile(profileFile, password);
          // Only mark as decrypted if we actually performed the decrypt — the
          // finally re-encrypt path uses this flag to decide whether to restore
          // on-disk encryption, and must not encrypt a profile that was already
          // plaintext.
          profileWasDecrypted = true;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      service = FfiChatService(
        preferencesService: SharedPreferencesAdapter(
          prefs,
          accountPrefix: accountPrefix,
        ),
        loggerService: AppLoggerAdapter(),
        bootstrapService: BootstrapNodesAdapter(prefs),
        historyDirectory: historyDirectory,
        queueFilePath: queueFilePath,
        fileRecvPath: fileRecvPath,
        avatarsPath: avatarsPath,
      );

      await service.init(profileDirectory: profileDir);
      await service.login(userId: 'FlutterUIKitClient', userSig: 'dummy_sig');

      // F12 backfill: imported accounts land in account_list with a
      // 64-char public key (from `tox_self_get_public_key`); once we're
      // logged in, Tim2Tox has the full 76-char address available. Rewrite
      // `account_list` + `current_account_tox_id` + password keys so every
      // downstream caller (Prefs.setCurrentAccountToxId / addAccount /
      // getAccountByToxId, the ProfilePage SelectableText, "Copy full ID"
      // clipboard action, sidebar) sees the complete nospam+checksum form.
      // Idempotent and safe to call on every login. The 16-char scoped-prefs
      // / on-disk prefix is identical between 64 and 76 representations
      // (the long form is `public_key || nospam || checksum`), so no scoped
      // state needs re-keying.
      canonicalToxId =
          await ShortToxIdBackfill.backfillIfNeeded(
            service: service,
            persistedToxId: toxId,
          ) ??
          toxId;
      // Local non-nullable handle: Dart flow analysis won't promote the
      // outer `canonicalToxId` across awaits, but the value is known
      // non-null at this point and the catch path reads the outer var.
      final activeToxId = canonicalToxId;
      service.installScratchFileService(
        await _scratchStorageForAccount(activeToxId),
      );

      if (nickname != null) {
        await service.updateSelfProfile(
          nickname: nickname,
          statusMessage: statusMessage ?? '',
        );
      }

      if (startPolling) {
        await service.startPolling();
      }

      if (password != null && password.isNotEmpty) {
        // Key the live session password under the canonical (post-backfill)
        // toxId — `ShortToxIdBackfill` moves the durable password keys to
        // the long form, so the session cache must agree or `verifyPassword`
        // on next login would see a stale short-form cache hit.
        SessionPasswordStore.set(activeToxId, password);
      }

      await Prefs.setCurrentAccountToxId(activeToxId);
      // Switch the user-facing nickname/status to the new account's record
      // so the sidebar `_UserAvatar` (which reads `Prefs.getNickname()` /
      // `Prefs.getStatusMessage()`) reflects the active account immediately.
      // Without this, the global pref keeps the previous account's label and
      // the UI looks unchanged after a successful switch — the bug the
      // 2026-05-28 import-then-switch repro surfaced. Only update when the
      // caller actually passed a nickname; null means "don't touch labels"
      // (e.g. resume flows that already have the right value cached).
      if (nickname != null) {
        await Prefs.setNickname(nickname);
        await Prefs.setStatusMessage(statusMessage ?? '');
      }
      // Make sure the account has a self avatar and that both stores agree
      // on it: the account_list row (what `Prefs.getAvatarPath()` and every
      // toxee surface — sidebar, settings, profile, QR card — read) and the
      // service-scoped `self_avatar_path_<prefix>` key (what Tim2Tox reads
      // for message bubbles and the avatar push to friends). Only
      // `register()` installs the bundled default; recovered, imported,
      // restored and legacy-login accounts never got one and showed a
      // stock-photo / initial / silhouette mix across the UI. This is the
      // single activation choke point (auto-login, manual login, account
      // switch, L3 boot), so no account can stay in that state. Never
      // throws; on failure the stores keep whatever they had.
      await DefaultAvatarInstaller.ensureSelfAvatar(toxId: activeToxId);
      initSucceeded = true;
      return service;
    } catch (e) {
      await service?.dispose();
      await Prefs.setCurrentAccountToxId(previousAccount);
      // Mirror the success path: if we set nickname/status/avatar above,
      // undo them. We always restore here because we may have failed AFTER
      // the setCurrentAccountToxId line, leaving partially-applied state.
      await Prefs.setNickname(previousNickname ?? '');
      await Prefs.setStatusMessage(previousStatusMessage ?? '');
      await Prefs.setAvatarPath(previousAvatarPath);
      if (password != null && password.isNotEmpty) {
        // We don't know whether ShortToxIdBackfill ran successfully (the
        // throw could be from before or after it), so clear both keys
        // defensively. SessionPasswordStore.clear is a no-op when the key
        // is absent. The canonical (post-backfill) toxId is hoisted above
        // the try so it's reachable here — without this, a throw after
        // `SessionPasswordStore.set(canonicalToxId, ...)` would strand a
        // stale 76-char entry in memory while we only cleared the 64-char
        // input arg, leaking the password across the failed attempt.
        SessionPasswordStore.clear(toxId);
        if (canonicalToxId != null && canonicalToxId != toxId) {
          SessionPasswordStore.clear(canonicalToxId);
        }
      }
      rethrow;
    } finally {
      // Re-encrypt the on-disk profile if we decrypted it but didn't succeed.
      // try/finally (vs catch-rethrow) guarantees this runs even on a future
      // early-return path that bypasses the catch. On the success path the
      // session owns the running profile and the file is re-encrypted later
      // by teardownCurrentSession, so we skip it here.
      if (!initSucceeded &&
          profileWasDecrypted &&
          profileFile != null &&
          password != null &&
          password.isNotEmpty) {
        try {
          await AccountExportService.encryptProfileFile(profileFile, password);
        } catch (encryptError) {
          SafeDiagnostics.logFailure(
            '[AccountService] initialization_rollback_failed '
            'stage=profile_reencryption',
            encryptError,
          );
        }
      }
    }
  }

  /// Creates an [FfiChatService] with account-scoped paths (history, queue,
  /// fileRecv, avatars). Caller must call [FfiChatService.startPolling] if needed.
  static Future<FfiChatService> _createAccountScopedService({
    required SharedPreferences prefs,
    required String toxId,
    required String profileDirectory,
  }) async {
    await AppPaths.migrateAccountDataFromLegacy(toxId);
    final historyDirectory = await AppPaths.getAccountChatHistoryPath(toxId);
    final queueFilePath = await AppPaths.getAccountOfflineQueueFilePath(toxId);
    final fileRecvPath = await AppPaths.getAccountFileRecvPath(toxId);
    final avatarsPath = await AppPaths.getAccountAvatarsPath(toxId);
    final scratchStorage = await _scratchStorageForAccount(toxId);

    await Directory(historyDirectory).create(recursive: true);
    await Directory(avatarsPath).create(recursive: true);

    final accountPrefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final svc = FfiChatService(
      preferencesService: SharedPreferencesAdapter(
        prefs,
        accountPrefix: accountPrefix,
      ),
      loggerService: AppLoggerAdapter(),
      bootstrapService: BootstrapNodesAdapter(prefs),
      historyDirectory: historyDirectory,
      queueFilePath: queueFilePath,
      fileRecvPath: fileRecvPath,
      avatarsPath: avatarsPath,
      scratchFileService: scratchStorage,
    );
    try {
      await svc.init(profileDirectory: profileDirectory);
      await svc.login(userId: 'FlutterUIKitClient', userSig: 'dummy_sig');
      return svc;
    } catch (_) {
      try {
        await svc.dispose();
      } catch (disposeError) {
        SafeDiagnostics.logFailure(
          '[AccountService] registration_rollback_failed '
          'stage=scoped_service_disposal',
          disposeError,
        );
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Register a new account.
  ///
  /// Replaces the ~80-line registration blocks duplicated in
  /// `LoginPage._register()` and `RegisterPage._submitRegister()`.
  ///
  /// Returns a [RegisterResult] with the initialized service, toxId, and
  /// profile directory.
  static Future<RegisterResult> registerNewAccount({
    required String nickname,
    String statusMessage = '',
    String password = '',
    @visibleForTesting
    Future<void> Function(String profileFilePath, String password)?
    encryptProfileFileOverride,
  }) async {
    // 1. Validate uniqueness
    final existingAccount = await Prefs.getAccountByNickname(nickname);
    if (existingAccount != null) {
      throw Exception('Account with this nickname already exists');
    }
    final savedNickname = await Prefs.getNickname();
    if (savedNickname != null &&
        savedNickname.trim().isNotEmpty &&
        savedNickname.trim() == nickname) {
      throw Exception('Account with this nickname already exists');
    }

    final previousAccount = await Prefs.getCurrentAccountToxId();
    final previousNickname = await Prefs.getNickname();
    final previousStatusMessage = await Prefs.getStatusMessage();
    final previousAvatarPath = await Prefs.getAvatarPath();

    const maxAttempts = 2;
    String? tempDir;
    FfiChatService? service;
    String? toxId;
    String? finalDir;
    bool accountVisible = false;

    try {
      // 2. Clear current account so init() loads empty state
      await Prefs.setCurrentAccountToxId(null);

      // 3. Create temp directory, init service, get toxId
      final prefs = await SharedPreferences.getInstance();
      final root = await AppPaths.getProfileStorageRoot();
      await Directory(root).create(recursive: true);

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        // This bootstrap-only instance has no Tox ID yet and is disposed before
        // any message/media helper can run. The live account-scoped service is
        // reopened through _createAccountScopedService once the ID is known.
        final svc = FfiChatService(
          preferencesService: SharedPreferencesAdapter(prefs),
          loggerService: AppLoggerAdapter(),
          bootstrapService: BootstrapNodesAdapter(prefs),
          scratchFileService:
              AccountScratchStorage.unavailableUntilAccountKnown(),
        );
        tempDir = p.join(
          root,
          '.tmp_register_${DateTime.now().millisecondsSinceEpoch}',
        );
        await Directory(tempDir).create(recursive: true);

        service = svc;
        await service.init(profileDirectory: tempDir);
        await service.login(userId: 'FlutterUIKitClient', userSig: 'dummy_sig');

        // The register flow PERSISTS the toxId as the primary key of the
        // new account_list entry, profile directory, and per-account
        // prefs prefix — so it must be fail-closed: if the FFI didn't
        // give us a real Tox address, abort rather than fall back to
        // `selfId` (which is the V2TIM login placeholder and would
        // re-create the original "FlutterUIKitClient" account-list
        // corruption this whole migration story was about). Use
        // `getSelfToxId()` directly here, not the `accountKey`
        // extension, because the extension's `selfId` fallback is fine
        // for UI/display reads but not for first-time writes.
        final realToxId = service.getSelfToxId();
        if (realToxId == null || realToxId.isEmpty) {
          await service.dispose();
          throw Exception('Failed to generate Tox ID');
        }
        toxId = realToxId;

        finalDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final existingProfile = AppPaths.profileFileInDirectory(finalDir);
        if (await File(existingProfile).exists()) {
          await service.dispose();
          try {
            await Directory(tempDir).delete(recursive: true);
          } catch (e) {
            SafeDiagnostics.logFailure(
              '[AccountService] registration_rollback_failed '
              'stage=collision_temp_directory_cleanup',
              e,
            );
          }
          if (attempt + 1 >= maxAttempts) {
            throw Exception('Could not create unique profile');
          }
          AppLogger.log(
            '[AccountService] Register: profile path collision, retrying',
          );
          continue;
        }
        break;
      }

      // 4. Rename temp to final directory
      final profileDir = finalDir!;
      await Directory(tempDir!).rename(profileDir);

      final svc = service!;
      final tid = toxId!;
      // Installing the bundled default avatar must never block registration:
      // a missing/corrupt asset (e.g. assets/avatars not bundled) should
      // degrade to "no avatar" rather than abort account creation entirely.
      String? defaultAvatarPath;
      try {
        defaultAvatarPath =
            await DefaultAvatarInstaller.installDefaultUserAvatar(toxId: tid);
      } catch (e) {
        SafeDiagnostics.logFailure(
          '[AccountService] registration_optional_step_failed '
          'stage=default_avatar_install continuation=true',
          e,
        );
        defaultAvatarPath = null;
      }

      // 5. Update profile
      await svc.updateSelfProfile(
        nickname: nickname,
        statusMessage: statusMessage,
      );

      // 6. Save to Prefs
      await Prefs.setNickname(nickname);
      await Prefs.setStatusMessage(statusMessage);
      await Prefs.setCurrentAccountToxId(tid);
      await Prefs.addAccount(
        toxId: tid,
        nickname: nickname,
        statusMessage: statusMessage,
        avatarPath: defaultAvatarPath,
      );
      accountVisible = true;
      await Prefs.setAvatarPath(defaultAvatarPath);

      // 7. Handle password encryption if needed
      if (password.isNotEmpty) {
        final passwordPersisted = await Prefs.setAccountPassword(tid, password);
        if (!passwordPersisted) {
          throw StateError('Failed to persist account password verifier');
        }
        SessionPasswordStore.set(tid, password);

        // Encrypt then decrypt to verify, then re-init with account-scoped paths
        await svc.dispose();
        service = null;
        final profilePath = AppPaths.profileFileInDirectory(profileDir);
        final encryptProfileFile =
            encryptProfileFileOverride ??
            AccountRegistrationTestHooks.encryptProfileFile ??
            AccountExportService.encryptProfileFile;
        await encryptProfileFile(profilePath, password);
        await AccountExportService.decryptProfileFile(profilePath, password);

        final prefsForNew = await SharedPreferences.getInstance();
        final newService = await _createAccountScopedService(
          prefs: prefsForNew,
          toxId: tid,
          profileDirectory: profileDir,
        );
        service = newService;
        // The `updateSelfProfile` above ran on the now-disposed temp service;
        // its in-memory `tox_self_set_name` did NOT survive the dispose+reopen
        // (the on-disk profile predates it). Re-apply on the LIVE scoped
        // instance, or the running Tox keeps an empty name and friends receive
        // an empty `friend_name` (display falls back to the raw tox-id).
        await newService.updateSelfProfile(
          nickname: nickname,
          statusMessage: statusMessage,
        );

        return RegisterResult(
          service: newService,
          toxId: tid,
          profileDirectory: profileDir,
        );
      }

      // 8. No password: re-open with account-scoped paths, then start polling
      await svc.dispose();
      service = null;
      final prefsForScoped = await SharedPreferences.getInstance();
      final scopedService = await _createAccountScopedService(
        prefs: prefsForScoped,
        toxId: tid,
        profileDirectory: profileDir,
      );
      service = scopedService;
      // See the password branch above: set the name on the live scoped instance
      // (the pre-dispose temp service's name set is lost on reopen).
      await scopedService.updateSelfProfile(
        nickname: nickname,
        statusMessage: statusMessage,
      );

      return RegisterResult(
        service: scopedService,
        toxId: tid,
        profileDirectory: profileDir,
      );
    } catch (e) {
      SafeDiagnostics.logFailure(
        '[AccountService] registration_failed stage=transaction',
        e,
      );
      try {
        if (service != null) {
          final disposeService = AccountRegistrationTestHooks.disposeService;
          if (disposeService != null) {
            await disposeService(service);
          } else {
            await service.dispose();
          }
        }
      } catch (de) {
        SafeDiagnostics.logFailure(
          '[AccountService] registration_rollback_failed '
          'stage=service_disposal',
          de,
        );
      }

      if (toxId != null && toxId.isNotEmpty) {
        SessionPasswordStore.clear(toxId);
      }

      if (accountVisible && toxId != null && toxId.isNotEmpty) {
        await Prefs.clearAccountData(toxId);
        await Prefs.removeAccount(toxId);
      }

      await Prefs.setCurrentAccountToxId(previousAccount);
      await Prefs.setNickname(previousNickname ?? '');
      await Prefs.setStatusMessage(previousStatusMessage ?? '');
      await Prefs.setAvatarPath(previousAvatarPath);

      if (tempDir != null) {
        try {
          final d = Directory(tempDir);
          if (await d.exists()) {
            await d.delete(recursive: true);
          }
        } catch (de) {
          SafeDiagnostics.logFailure(
            '[AccountService] registration_rollback_failed '
            'stage=temp_directory_cleanup',
            de,
          );
        }
      }

      if (finalDir != null) {
        try {
          final d = Directory(finalDir);
          if (await d.exists()) {
            await d.delete(recursive: true);
          }
        } catch (de) {
          SafeDiagnostics.logFailure(
            '[AccountService] registration_rollback_failed '
            'stage=profile_directory_cleanup',
            de,
          );
        }
      }

      if (toxId != null && toxId.isNotEmpty) {
        try {
          await _deleteAccountDataRoots(toxId);
        } catch (de) {
          SafeDiagnostics.logFailure(
            '[AccountService] registration_rollback_failed '
            'stage=account_data_cleanup',
            de,
          );
        }
      }

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Account deletion
  // ---------------------------------------------------------------------------

  /// Completely delete an account with a running service.
  ///
  /// A durable tombstone is written before the service or filesystem is touched.
  /// Failures leave the tombstone pending for cold-start retry, and account-list
  /// visibility is removed only after password, prefs, profile, and account-data
  /// cleanup all succeed.
  static Future<AccountDeletionResult> deleteAccountCompletely({
    required FfiChatService service,
    required String toxId,
  }) async {
    final result = await AccountDeletionCoordinator.deleteAccount(
      toxId: toxId,
      serviceCleanup: () async {
        await service.clearAllAccountData();
        await teardownCurrentSession(service: service, reEncryptProfile: false);
        SessionPasswordStore.clear(toxId);
      },
    );
    _throwIfDeletionPending(result);
    return result;
  }

  /// Delete an account from the login page (no running service).
  ///
  /// Performs the same cleanup as [deleteAccountCompletely] but skips
  /// service-level teardown since no service is running.
  static Future<AccountDeletionResult> deleteAccountWithoutService({
    required String toxId,
  }) async {
    final result = await AccountDeletionCoordinator.deleteAccount(toxId: toxId);
    if (result.completed) {
      SessionPasswordStore.clear(toxId);
    }
    _throwIfDeletionPending(result);
    return result;
  }

  static Future<List<AccountDeletionResult>> recoverPendingAccountDeletions() {
    return AccountDeletionCoordinator.recoverPendingDeletions();
  }

  static Future<void> throwIfAccountDeleting(String toxId) {
    return AccountDeletionCoordinator.throwIfDeleting(toxId);
  }

  static Future<AccountScratchStorage> createScratchStorageForAccount(
    String toxId,
  ) {
    return _scratchStorageForAccount(toxId);
  }

  static void _throwIfDeletionPending(AccountDeletionResult result) {
    final failure = result.failure;
    if (failure != null) throw failure;
  }

  static Future<AccountScratchStorage> _scratchStorageForAccount(
    String toxId,
  ) async {
    final storage = AccountScratchStorage(
      accountToxId: toxId,
      accountDataRoot: await AppPaths.getAccountScratchDataRoot(toxId),
    );
    await Directory(storage.scratchRoot).create(recursive: true);
    await AppPaths.markExcludedFromBackup(storage.scratchRoot);
    return storage;
  }

  static Future<void> _deleteAccountDataRoots(String toxId) async {
    final roots = <String>{
      p.normalize(p.absolute(await AppPaths.getAccountDataRoot(toxId))),
    };
    try {
      roots.add(
        p.normalize(
          p.absolute(await AppPaths.getAccountScratchDataRoot(toxId)),
        ),
      );
    } on ArgumentError {
      // Legacy short IDs have no full-ID scratch root.
    }
    for (final root in roots) {
      final directory = Directory(root);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }
}
