import 'dart:io';

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
import 'app_paths.dart';
import 'account_export_service.dart';
import 'session_password_store.dart';
import 'group_member_list_debouncer.dart';
import 'irc_app_manager.dart';
import 'logger.dart';

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
    // Capture values before tearing down
    final toxId = service?.selfId ?? '';
    final sessionPassword =
        toxId.isNotEmpty ? SessionPasswordStore.get(toxId) : null;

    // 1 & 2. Dispose session runtime (FakeUIKit + platform)
    await SessionRuntimeCoordinator.disposeRuntime();

    // 3. Clear provider registries
    ChatDataProviderRegistry.provider = null;
    ChatMessageProviderRegistry.provider = null;

    // 3.5 Clear static singleton caches to prevent cross-account data leaks
    GroupMemberListDebouncer().clear();
    IrcAppManager().resetCache();

    // 4. Dispose service
    if (service != null) {
      try {
        await service.dispose();
      } catch (e, st) {
        AppLogger.logError(
            '[AccountService] teardown: service.dispose error', e, st);
      }
    }

    // 5. Re-encrypt profile on disk
    if (reEncryptProfile &&
        sessionPassword != null &&
        sessionPassword.isNotEmpty &&
        toxId.isNotEmpty) {
      try {
        final profileDir =
            await AppPaths.getProfileDirectoryForToxId(toxId);
        final profilePath = AppPaths.profileFileInDirectory(profileDir);
        if (await File(profilePath).exists()) {
          await AccountExportService.encryptProfileFile(
              profilePath, sessionPassword);
        }
      } catch (e, st) {
        AppLogger.logError(
            '[AccountService] teardown: re-encrypt profile error', e, st);
      }
    }

    // 6. Clear session password
    if (toxId.isNotEmpty) {
      SessionPasswordStore.clear(toxId);
    }
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
    final previousAccount = await Prefs.getCurrentAccountToxId();
    FfiChatService? service;
    String? profileFile;
    bool profileWasDecrypted = false;
    bool initSucceeded = false;
    final accountPrefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final migrPrefs = await SharedPreferences.getInstance();

    try {
      await PrefsUpgrader.runAccountMigrations(migrPrefs, accountPrefix);

      await AppPaths.migrateAccountDataFromLegacy(toxId);

      final historyDirectory = await AppPaths.getAccountChatHistoryPath(toxId);
      final queueFilePath =
          await AppPaths.getAccountOfflineQueueFilePath(toxId);
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
          AppLogger.log(
              '[AccountService] Migrated profile from legacy to $profileDir');
        } else {
          throw Exception('Profile not found for account');
        }
      }

      if (password != null && password.isNotEmpty) {
        final isEncrypted =
            await AccountExportService.isProfileFileEncrypted(profileFile);
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
        preferencesService: SharedPreferencesAdapter(prefs, accountPrefix: accountPrefix),
        loggerService: AppLoggerAdapter(),
        bootstrapService: BootstrapNodesAdapter(prefs),
        historyDirectory: historyDirectory,
        queueFilePath: queueFilePath,
        fileRecvPath: fileRecvPath,
        avatarsPath: avatarsPath,
      );

      await service.init(profileDirectory: profileDir);
      await service.login(userId: 'FlutterUIKitClient', userSig: 'dummy_sig');

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
        SessionPasswordStore.set(toxId, password);
      }

      await Prefs.setCurrentAccountToxId(toxId);
      initSucceeded = true;
      return service;
    } catch (e) {
      await service?.dispose();
      await Prefs.setCurrentAccountToxId(previousAccount);
      if (password != null && password.isNotEmpty) {
        SessionPasswordStore.clear(toxId);
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
          await AccountExportService.encryptProfileFile(
            profileFile,
            password,
          );
        } catch (encryptError, encryptSt) {
          AppLogger.logError(
            '[AccountService] Failed to re-encrypt profile after init failure',
            encryptError,
            encryptSt,
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

    await Directory(historyDirectory).create(recursive: true);
    await Directory(avatarsPath).create(recursive: true);

    final accountPrefix =
        toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final svc = FfiChatService(
      preferencesService: SharedPreferencesAdapter(prefs, accountPrefix: accountPrefix),
      loggerService: AppLoggerAdapter(),
      bootstrapService: BootstrapNodesAdapter(prefs),
      historyDirectory: historyDirectory,
      queueFilePath: queueFilePath,
      fileRecvPath: fileRecvPath,
      avatarsPath: avatarsPath,
    );
    await svc.init(profileDirectory: profileDirectory);
    await svc.login(userId: 'FlutterUIKitClient', userSig: 'dummy_sig');
    return svc;
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
        final svc = FfiChatService(
          preferencesService: SharedPreferencesAdapter(prefs),
          loggerService: AppLoggerAdapter(),
          bootstrapService: BootstrapNodesAdapter(prefs),
        );
        tempDir = p.join(
            root, '.tmp_register_${DateTime.now().millisecondsSinceEpoch}');
        await Directory(tempDir).create(recursive: true);

        service = svc;
        await service.init(profileDirectory: tempDir);
        await service.login(userId: 'FlutterUIKitClient', userSig: 'dummy_sig');

        toxId = service.selfId;
        if (toxId.isEmpty) {
          await service.dispose();
          throw Exception('Failed to generate Tox ID');
        }

        finalDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final existingProfile = AppPaths.profileFileInDirectory(finalDir);
        if (await File(existingProfile).exists()) {
          await service.dispose();
          try {
            await Directory(tempDir).delete(recursive: true);
          } catch (e) {
            AppLogger.warn(
                '[AccountService] Register: failed to clean up temp dir $tempDir: $e');
          }
          if (attempt + 1 >= maxAttempts) {
            throw Exception('Could not create unique profile');
          }
          AppLogger.log(
              '[AccountService] Register: profile path collision, retrying');
          continue;
        }
        break;
      }

      // 4. Rename temp to final directory
      final profileDir = finalDir!;
      await Directory(tempDir!).rename(profileDir);

      final svc = service!;
      final tid = toxId!;

      // 5. Update profile
      await svc.updateSelfProfile(
          nickname: nickname, statusMessage: statusMessage);

      // 6. Save to Prefs
      await Prefs.setNickname(nickname);
      await Prefs.setStatusMessage(statusMessage);
      await Prefs.setCurrentAccountToxId(tid);
      await Prefs.addAccount(
        toxId: tid,
        nickname: nickname,
        statusMessage: statusMessage,
        avatarPath: null,
      );
      accountVisible = true;

      // 7. Handle password encryption if needed
      if (password.isNotEmpty) {
        await Prefs.setAccountPassword(tid, password);
        SessionPasswordStore.set(tid, password);

        // Encrypt then decrypt to verify, then re-init with account-scoped paths
        await svc.dispose();
        final profilePath = AppPaths.profileFileInDirectory(profileDir);
        await AccountExportService.encryptProfileFile(profilePath, password);
        await AccountExportService.decryptProfileFile(profilePath, password);

        final prefsForNew = await SharedPreferences.getInstance();
        final newService = await _createAccountScopedService(
          prefs: prefsForNew,
          toxId: tid,
          profileDirectory: profileDir,
        );

        return RegisterResult(
          service: newService,
          toxId: tid,
          profileDirectory: profileDir,
        );
      }

      // 8. No password: re-open with account-scoped paths, then start polling
      await svc.dispose();
      final prefsForScoped = await SharedPreferences.getInstance();
      final scopedService = await _createAccountScopedService(
        prefs: prefsForScoped,
        toxId: tid,
        profileDirectory: profileDir,
      );

      return RegisterResult(
        service: scopedService,
        toxId: tid,
        profileDirectory: profileDir,
      );
    } catch (e, st) {
      AppLogger.logError('[AccountService] Register failed', e, st);
      try {
        await service?.dispose();
      } catch (de) {
        AppLogger.warn(
            '[AccountService] Register: dispose during error rollback failed: $de');
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

      if (tempDir != null) {
        try {
          final d = Directory(tempDir);
          if (await d.exists()) {
            await d.delete(recursive: true);
          }
        } catch (de) {
          AppLogger.warn(
              '[AccountService] Register: rollback temp dir cleanup failed: $de');
        }
      }

      if (finalDir != null) {
        try {
          final d = Directory(finalDir);
          if (await d.exists()) {
            await d.delete(recursive: true);
          }
        } catch (de) {
          AppLogger.warn(
              '[AccountService] Register: rollback final dir cleanup failed: $de');
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
  /// Performs comprehensive cleanup: SDK teardown, prefs, password hash,
  /// session store, profile directory, and account data directory.
  static Future<void> deleteAccountCompletely({
    required FfiChatService service,
    required String toxId,
  }) async {
    // 1. Clear service-level data BEFORE teardown — once teardown disposes
    // the service, account-level cleanup (SQLite, file locks) can no longer
    // run. Order matters: must be called on a still-live service.
    try {
      await service.clearAllAccountData();
    } catch (e, st) {
      AppLogger.logError(
          '[AccountService] clearAllAccountData before teardown failed', e, st);
    }

    // 2. Teardown without re-encrypting (we're deleting the profile)
    await teardownCurrentSession(
        service: service, reEncryptProfile: false);

    // 3-5. Clear prefs (includes scoped keys + password hash)
    await Prefs.clearAccountData(toxId);

    // 6. Remove from account list
    await Prefs.removeAccount(toxId);

    // 7. Clear session password store
    SessionPasswordStore.clear(toxId);

    // 8. Delete profile directory
    try {
      final profileDir =
          await AppPaths.getProfileDirectoryForToxId(toxId);
      final dir = Directory(profileDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e, st) {
      AppLogger.logError(
          '[AccountService] Failed to delete profile directory', e, st);
    }

    // 9. Delete account data directory
    try {
      final accountDataRoot = await AppPaths.getAccountDataRoot(toxId);
      final dataDir = Directory(accountDataRoot);
      if (await dataDir.exists()) {
        await dataDir.delete(recursive: true);
      }
    } catch (e, st) {
      AppLogger.logError(
          '[AccountService] Failed to delete account data directory', e, st);
    }

    // 10. Clean up UIKit failed message keys
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix =
          toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
      final allKeys = prefs.getKeys().toList();
      for (final key in allKeys) {
        if (key.contains('tencent_cloud_chat_failed_messages') &&
            key.contains(prefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      AppLogger.warn(
          '[AccountService] failed to clean UIKit failed-message prefs: $e');
    }

    // 11. Clear current account ID
    await Prefs.setCurrentAccountToxId(null);
  }

  /// Delete an account from the login page (no running service).
  ///
  /// Performs the same cleanup as [deleteAccountCompletely] but skips
  /// service-level teardown since no service is running.
  static Future<void> deleteAccountWithoutService({
    required String toxId,
  }) async {
    // Clear prefs (includes scoped keys + password hash)
    await Prefs.clearAccountData(toxId);

    // Remove from account list
    await Prefs.removeAccount(toxId);

    // Clear session password store
    SessionPasswordStore.clear(toxId);

    // Delete profile directory
    try {
      final profileDir =
          await AppPaths.getProfileDirectoryForToxId(toxId);
      final dir = Directory(profileDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e, st) {
      AppLogger.logError(
          '[AccountService] Failed to delete profile directory', e, st);
    }

    // Delete account data directory
    try {
      final accountDataRoot = await AppPaths.getAccountDataRoot(toxId);
      final dataDir = Directory(accountDataRoot);
      if (await dataDir.exists()) {
        await dataDir.delete(recursive: true);
      }
    } catch (e, st) {
      AppLogger.logError(
          '[AccountService] Failed to delete account data directory', e, st);
    }

    // Clean up UIKit failed message keys
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix =
          toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
      final allKeys = prefs.getKeys().toList();
      for (final key in allKeys) {
        if (key.contains('tencent_cloud_chat_failed_messages') &&
            key.contains(prefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      AppLogger.warn(
          '[AccountService] failed to clean UIKit failed-message prefs: $e');
    }

    // Clear current account ID if we just deleted the active account, so a
    // subsequent cold start does not try to load this profile.
    final current = await Prefs.getCurrentAccountToxId();
    if (current == toxId) {
      await Prefs.setCurrentAccountToxId(null);
    }
  }
}
