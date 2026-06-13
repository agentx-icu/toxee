import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../auth/login_use_case.dart';
import '../../util/account_export_service.dart';
import '../../util/app_paths.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';
import '../testing/l3_debug_tools.dart';

/// Result of [LoginPageController.login].
sealed class LoginControllerResult {
  const LoginControllerResult();
}

final class LoginControllerSuccess extends LoginControllerResult {
  const LoginControllerSuccess(this.service);
  final FfiChatService service;
}

final class LoginControllerFailure extends LoginControllerResult {
  const LoginControllerFailure(this.message);
  final String message;
}

/// Result of [LoginPageController.importAccount].
sealed class ImportResult {
  const ImportResult();
}

final class ImportSuccess extends ImportResult {
  const ImportSuccess();
}

/// Reason an import failed. The UI maps this to a localized message;
/// keeping a kind enum (instead of stringly-typed messages) lets the UI
/// distinguish user-initiated cancellation from genuine errors without
/// fragile string comparisons.
enum ImportFailureKind {
  noFileSelected,
  cancelled,
  accountAlreadyExists,
  generalError,
}

final class ImportFailure extends ImportResult {
  const ImportFailure(this.kind, {this.detail});
  final ImportFailureKind kind;

  /// Raw underlying error string for [ImportFailureKind.generalError]; null
  /// for cancellation / file-not-selected / duplicate-account cases.
  final String? detail;
}

/// Reason a restore failed. Mirrors [ImportFailureKind] but is scoped to the
/// .tox-only "Restore from .tox file" first-class login entry. Kept as a
/// separate enum so the UI can show restore-specific copy ("This file doesn't
/// look like a valid Tox profile") without bleeding restore strings into the
/// generic import path.
enum RestoreFailureKind {
  noFileSelected,
  cancelled,
  invalidPassword,
  accountAlreadyExists,
  notAToxProfile,
  generalError,
}

/// Result of [LoginPageController.restoreFromToxFile].
sealed class RestoreResult {
  const RestoreResult();
}

final class RestoreSuccess extends RestoreResult {
  const RestoreSuccess({
    required this.toxId,
    required this.nickname,
    this.password,
  });
  final String toxId;
  final String nickname;
  final String? password;
}

final class RestoreFailure extends RestoreResult {
  const RestoreFailure(this.kind, {this.detail});
  final RestoreFailureKind kind;
  final String? detail;
}

/// Orchestrates login and import flows for [LoginPage].
/// Keeps UI to form binding, dialogs, and navigation.
typedef ImportAccountDataFn =
    Future<Map<String, dynamic>> Function({
      required String filePath,
      String? password,
    });

typedef ImportFullBackupFn =
    Future<Map<String, dynamic>> Function({
      required String filePath,
      String? password,
    });

typedef ReadFullBackupMetadataFn =
    Future<Map<String, dynamic>> Function(String filePath);

typedef AddAccountFn =
    Future<void> Function({
      required String toxId,
      required String nickname,
      required String statusMessage,
      required bool autoLogin,
      required bool autoAcceptFriends,
      required bool notificationSoundEnabled,
    });

typedef SetAccountPasswordFn =
    Future<void> Function(String toxId, String password);

Future<void> _defaultAddAccount({
  required String toxId,
  required String nickname,
  required String statusMessage,
  required bool autoLogin,
  required bool autoAcceptFriends,
  required bool notificationSoundEnabled,
}) {
  return Prefs.addAccount(
    toxId: toxId,
    nickname: nickname,
    statusMessage: statusMessage,
    autoLogin: autoLogin,
    autoAcceptFriends: autoAcceptFriends,
    notificationSoundEnabled: notificationSoundEnabled,
  );
}

class LoginPageController {
  LoginPageController({
    LoginUseCase? loginUseCase,
    @visibleForTesting ImportAccountDataFn? importAccountDataFn,
    @visibleForTesting ImportFullBackupFn? importFullBackupFn,
    @visibleForTesting ReadFullBackupMetadataFn? readFullBackupMetadataFn,
    @visibleForTesting AddAccountFn? addAccountFn,
    @visibleForTesting SetAccountPasswordFn? setAccountPasswordFn,
  }) : _loginUseCase = loginUseCase ?? LoginUseCase(),
       _importAccountDataFn =
           importAccountDataFn ?? AccountExportService.importAccountData,
       _importFullBackupFn =
           importFullBackupFn ?? AccountExportService.importFullBackup,
       _readFullBackupMetadataFn =
           readFullBackupMetadataFn ??
           AccountExportService.readFullBackupMetadata,
       _addAccountFn = addAccountFn ?? _defaultAddAccount,
       _setAccountPasswordFn = setAccountPasswordFn ?? Prefs.setAccountPassword;

  final LoginUseCase _loginUseCase;
  final ImportAccountDataFn _importAccountDataFn;
  final ImportFullBackupFn _importFullBackupFn;
  final ReadFullBackupMetadataFn _readFullBackupMetadataFn;
  final AddAccountFn _addAccountFn;
  final SetAccountPasswordFn _setAccountPasswordFn;

  /// Runs login with the given credentials. Password must be provided when account has one.
  Future<LoginControllerResult> login({
    required String nickname,
    required String statusMessage,
    String? password,
  }) async {
    try {
      final success = await _loginUseCase.execute(
        LoginParams(
          nickname: nickname,
          statusMessage: statusMessage,
          password: password,
        ),
      );
      return LoginControllerSuccess(success.service);
    } catch (e, st) {
      AppLogger.logError('[LoginPageController] Login failed', e, st);
      final message = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      return LoginControllerFailure(message);
    }
  }

  /// Imports an account from a .tox or .zip file. Uses [requestPassword] when
  /// file is encrypted. The UI supplies an [importedAccountDefaultName] which
  /// is used when the imported backup carries no nickname.
  Future<ImportResult> importAccount({
    required Future<String?> Function() requestPassword,
    required String importedAccountDefaultName,
    @visibleForTesting String? filePathOverride,
  }) async {
    String? rollbackToxId;
    try {
      final filePath =
          filePathOverride ??
          await runL3AwareAccountImportPicker(
            pickFile: () async => (await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['tox', 'zip'],
            ))?.files.single.path,
          );
      if (filePath == null) {
        return const ImportFailure(ImportFailureKind.noFileSelected);
      }
      final isZip = filePath.toLowerCase().endsWith('.zip');

      String? password;
      Map<String, dynamic> accountData;

      if (isZip) {
        final metadata = await _readFullBackupMetadataFn(filePath);
        final toxId = metadata['toxId']!;
        rollbackToxId = toxId;
        final existingAccount = await Prefs.getAccountByToxId(toxId);
        if (existingAccount != null) {
          return const ImportFailure(ImportFailureKind.accountAlreadyExists);
        }
        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
        if (await File(profileFilePath).exists()) {
          return const ImportFailure(ImportFailureKind.accountAlreadyExists);
        }
        try {
          accountData = await _importFullBackupFn(
            filePath: filePath,
            password: password,
          );
        } catch (e) {
          // Primary check: typed exception. Fallback string check kept as a
          // defensive layer in case some lower-level error surface keeps the
          // legacy `Exception('Password required …')` message.
          if (e is PasswordRequiredException ||
              e.toString().contains('Password required') ||
              e.toString().contains('password')) {
            password = await requestPassword();
            if (password == null) {
              return const ImportFailure(ImportFailureKind.cancelled);
            }
            accountData = await _importFullBackupFn(
              filePath: filePath,
              password: password,
            );
          } else {
            rethrow;
          }
        }
      } else {
        try {
          accountData = await _importAccountDataFn(
            filePath: filePath,
            password: password,
          );
        } catch (e) {
          if (e is PasswordRequiredException ||
              e.toString().contains('Password required') ||
              e.toString().contains('password')) {
            password = await requestPassword();
            if (password == null) {
              return const ImportFailure(ImportFailureKind.cancelled);
            }
            accountData = await _importAccountDataFn(
              filePath: filePath,
              password: password,
            );
          } else {
            rethrow;
          }
        }
      }

      final toxId = accountData['toxId'] as String;
      rollbackToxId = toxId;
      final toxProfile = accountData['toxProfile'] as Uint8List?;
      final importedNickname = (accountData['nickname'] as String?) ?? '';

      if (!isZip) {
        final existingAccount = await Prefs.getAccountByToxId(toxId);
        if (existingAccount != null) {
          return const ImportFailure(ImportFailureKind.accountAlreadyExists);
        }
      }

      if (!isZip && toxProfile != null) {
        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
        if (await File(profileFilePath).exists()) {
          return const ImportFailure(ImportFailureKind.accountAlreadyExists);
        }
        await Directory(profileDir).create(recursive: true);
        await File(profileFilePath).writeAsBytes(toxProfile);
      }

      final displayNickname = importedNickname.isNotEmpty
          ? importedNickname
          : importedAccountDefaultName;
      await _addAccountFn(
        toxId: toxId,
        nickname: displayNickname,
        statusMessage: '',
        autoLogin: false,
        autoAcceptFriends: false,
        notificationSoundEnabled: true,
      );
      if (password != null && password.isNotEmpty) {
        await _setAccountPasswordFn(toxId, password);
      }
      return const ImportSuccess();
    } catch (e, st) {
      if (rollbackToxId != null) {
        await _rollbackImportedAccount(rollbackToxId);
      }
      AppLogger.logError('[LoginPageController] Import failed', e, st);
      return ImportFailure(
        ImportFailureKind.generalError,
        detail: e.toString(),
      );
    }
  }

  /// Restore an account from a single `.tox` file. This is the first-class
  /// "lose your phone, get your account back" entry point invoked from the
  /// login page top-level "Restore from .tox file" action.
  ///
  /// Unlike [importAccount], this:
  /// - filters the file picker to `.tox` only,
  /// - returns typed [RestoreFailureKind]s the UI can map to restore-specific
  ///   copy (notAToxProfile / invalidPassword vs the generic generalError),
  /// - keeps the resolved [toxId] + [nickname] in the success payload so the
  ///   caller can pre-fill the login form and chain into login without a
  ///   second file picker pass.
  ///
  /// Encrypted .tox files prompt via [requestPassword]; wrong passwords
  /// surface as [RestoreFailureKind.invalidPassword] (the caller is expected
  /// to allow retry). qTox-format files pass through the existing
  /// [AccountExportService.importAccountData] code path.
  Future<RestoreResult> restoreFromToxFile({
    required Future<String?> Function() requestPassword,
    required String importedAccountDefaultName,
    @visibleForTesting String? filePathOverride,
  }) async {
    String? filePath;
    String? rollbackToxId;
    try {
      if (filePathOverride != null) {
        filePath = filePathOverride;
      } else {
        filePath = await runL3AwareAccountImportPicker(
          pickFile: () async {
            final picked = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['tox'],
            );
            return picked?.files.single.path;
          },
        );
        if (filePath == null) {
          return const RestoreFailure(RestoreFailureKind.noFileSelected);
        }
      }
      if (!filePath.toLowerCase().endsWith('.tox')) {
        return const RestoreFailure(RestoreFailureKind.notAToxProfile);
      }

      String? password;
      Map<String, dynamic> accountData;
      try {
        accountData = await _importAccountDataFn(filePath: filePath);
      } on PasswordRequiredException {
        password = await requestPassword();
        if (password == null) {
          return const RestoreFailure(RestoreFailureKind.cancelled);
        }
        try {
          accountData = await _importAccountDataFn(
            filePath: filePath,
            password: password,
          );
        } catch (e) {
          // Decryption failure with a supplied password is virtually always
          // a wrong password (the only other failure is corruption AFTER the
          // password gate, which is exceedingly rare). Surface as
          // invalidPassword so the UI can show the retry-friendly copy.
          AppLogger.logError(
            '[LoginPageController] Restore: decrypt failed with password',
            e,
            null,
          );
          return RestoreFailure(
            RestoreFailureKind.invalidPassword,
            detail: e.toString(),
          );
        }
      } catch (e) {
        // Non-password errors at this point (e.g. corrupt header) mean the
        // file is not a valid Tox profile.
        AppLogger.logError(
          '[LoginPageController] Restore: invalid tox file',
          e,
          null,
        );
        return RestoreFailure(
          RestoreFailureKind.notAToxProfile,
          detail: e.toString(),
        );
      }

      final toxId = accountData['toxId'] as String;
      rollbackToxId = toxId;
      final toxProfile = accountData['toxProfile'] as Uint8List?;
      final importedNickname = (accountData['nickname'] as String?) ?? '';

      // Duplicate-account guard: account already registered on this device.
      final existingAccount = await Prefs.getAccountByToxId(toxId);
      if (existingAccount != null) {
        return const RestoreFailure(RestoreFailureKind.accountAlreadyExists);
      }

      if (toxProfile == null || toxProfile.isEmpty) {
        return const RestoreFailure(RestoreFailureKind.notAToxProfile);
      }

      final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
      final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
      if (await File(profileFilePath).exists()) {
        return const RestoreFailure(RestoreFailureKind.accountAlreadyExists);
      }
      await Directory(profileDir).create(recursive: true);
      await File(profileFilePath).writeAsBytes(toxProfile);

      final displayNickname = importedNickname.isNotEmpty
          ? importedNickname
          : importedAccountDefaultName;
      await _addAccountFn(
        toxId: toxId,
        nickname: displayNickname,
        statusMessage: '',
        autoLogin: false,
        autoAcceptFriends: false,
        notificationSoundEnabled: true,
      );
      if (password != null && password.isNotEmpty) {
        await _setAccountPasswordFn(toxId, password);
      }
      return RestoreSuccess(
        toxId: toxId,
        nickname: displayNickname,
        password: password,
      );
    } catch (e, st) {
      if (rollbackToxId != null) {
        await _rollbackImportedAccount(rollbackToxId);
      }
      AppLogger.logError('[LoginPageController] Restore failed', e, st);
      return RestoreFailure(
        RestoreFailureKind.generalError,
        detail: e.toString(),
      );
    }
  }

  Future<void> _rollbackImportedAccount(String toxId) async {
    try {
      await Prefs.clearAccountData(toxId);
    } catch (e) {
      AppLogger.warn(
        '[LoginPageController] rollback: clearAccountData failed for $toxId: $e',
      );
    }
    try {
      await Prefs.removeAccount(toxId);
    } catch (e) {
      AppLogger.warn(
        '[LoginPageController] rollback: removeAccount failed for $toxId: $e',
      );
    }
    try {
      final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
      final dir = Directory(profileDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      AppLogger.warn(
        '[LoginPageController] rollback: profile cleanup failed for $toxId: $e',
      );
    }
    try {
      final accountDataRoot = await AppPaths.getAccountDataRoot(toxId);
      final dir = Directory(accountDataRoot);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      AppLogger.warn(
        '[LoginPageController] rollback: account data cleanup failed for $toxId: $e',
      );
    }
  }
}
