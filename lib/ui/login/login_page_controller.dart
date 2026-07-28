import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../auth/login_use_case.dart';
import '../../util/account_export_service.dart';
import '../../util/app_paths.dart';
import '../../util/imported_account_rollback.dart';
import '../../util/prefs.dart';
import '../../util/safe_diagnostics.dart';
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
  invalidPassword,
  accountAlreadyExists,
  generalError,
}

final class ImportFailure extends ImportResult {
  const ImportFailure(this.kind, {this.detail});
  final ImportFailureKind kind;

  /// Sanitized runtime-type detail for [ImportFailureKind.generalError]; null
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
    Future<Map<String, dynamic>> Function(String filePath, {String? password});

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
    Future<bool> Function(String toxId, String password);

typedef EncryptProfileFileFn =
    Future<bool> Function(String profileFilePath, String password);

typedef FinalizeFullBackupImportFn =
    Future<void> Function({required String toxId});

typedef RollbackFullBackupImportFn = Future<void> Function({String? toxId});
typedef RollbackImportedAccountFn =
    Future<void> Function({required String toxId, required String logContext});

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

Future<bool> _defaultEncryptProfileFile(
  String profileFilePath,
  String password,
) async {
  await AccountExportService.encryptProfileFile(profileFilePath, password);
  return true;
}

Future<void> _defaultRollbackImportedAccount({
  required String toxId,
  required String logContext,
}) {
  return ImportedAccountRollback.run(toxId: toxId, logContext: logContext);
}

class LoginPageController {
  LoginPageController({
    LoginUseCase? loginUseCase,
    @visibleForTesting ImportAccountDataFn? importAccountDataFn,
    @visibleForTesting ImportFullBackupFn? importFullBackupFn,
    @visibleForTesting ReadFullBackupMetadataFn? readFullBackupMetadataFn,
    @visibleForTesting AddAccountFn? addAccountFn,
    @visibleForTesting SetAccountPasswordFn? setAccountPasswordFn,
    @visibleForTesting EncryptProfileFileFn? encryptProfileFileFn,
    @visibleForTesting FinalizeFullBackupImportFn? finalizeFullBackupImportFn,
    @visibleForTesting RollbackFullBackupImportFn? rollbackFullBackupImportFn,
    @visibleForTesting RollbackImportedAccountFn? rollbackImportedAccountFn,
  }) : _loginUseCase = loginUseCase ?? LoginUseCase(),
       _importAccountDataFn =
           importAccountDataFn ?? AccountExportService.importAccountData,
       _importFullBackupFn =
           importFullBackupFn ?? AccountExportService.importFullBackup,
       _readFullBackupMetadataFn =
           readFullBackupMetadataFn ??
           AccountExportService.readFullBackupMetadata,
       _addAccountFn = addAccountFn ?? _defaultAddAccount,
       _setAccountPasswordFn = setAccountPasswordFn ?? Prefs.setAccountPassword,
       _encryptProfileFileFn =
           encryptProfileFileFn ?? _defaultEncryptProfileFile,
       _finalizeFullBackupImportFn =
           finalizeFullBackupImportFn ??
           AccountExportService.finalizeFullBackupImport,
       _rollbackFullBackupImportFn =
           rollbackFullBackupImportFn ??
           AccountExportService.rollbackPendingFullBackupRestore,
       _rollbackImportedAccountFn =
           rollbackImportedAccountFn ?? _defaultRollbackImportedAccount;

  final LoginUseCase _loginUseCase;
  final ImportAccountDataFn _importAccountDataFn;
  final ImportFullBackupFn _importFullBackupFn;
  final ReadFullBackupMetadataFn _readFullBackupMetadataFn;
  final AddAccountFn _addAccountFn;
  final SetAccountPasswordFn _setAccountPasswordFn;
  final EncryptProfileFileFn _encryptProfileFileFn;
  final FinalizeFullBackupImportFn _finalizeFullBackupImportFn;
  final RollbackFullBackupImportFn _rollbackFullBackupImportFn;
  final RollbackImportedAccountFn _rollbackImportedAccountFn;

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
    } catch (e) {
      SafeDiagnostics.logFailure('[LoginPageController] Login failed', e);
      return LoginControllerFailure(SafeDiagnostics.describeError(e));
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
    bool rollbackFullBackup = false;
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
        Map<String, dynamic> metadata;
        try {
          metadata = await _readFullBackupMetadataFn(
            filePath,
            password: password,
          );
        } on PasswordRequiredException {
          password = await requestPassword();
          if (password == null) {
            return const ImportFailure(ImportFailureKind.cancelled);
          }
          if (password.isEmpty) {
            return const ImportFailure(ImportFailureKind.invalidPassword);
          }
          metadata = await _readFullBackupMetadataFn(
            filePath,
            password: password,
          );
        }
        final toxId = metadata['toxId']!;
        final existingAccount = await Prefs.getAccountByToxId(toxId);
        if (existingAccount != null) {
          return const ImportFailure(ImportFailureKind.accountAlreadyExists);
        }
        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
        if (await File(profileFilePath).exists()) {
          return const ImportFailure(ImportFailureKind.accountAlreadyExists);
        }
        rollbackToxId = toxId;
        rollbackFullBackup = true;
        accountData = await _importFullBackupFn(
          filePath: filePath,
          password: password,
        );
      } else {
        try {
          accountData = await _importAccountDataFn(
            filePath: filePath,
            password: password,
          );
        } catch (e) {
          if (e is PasswordRequiredException) {
            password = await requestPassword();
            if (password == null) {
              return const ImportFailure(ImportFailureKind.cancelled);
            }
            try {
              accountData = await _importAccountDataFn(
                filePath: filePath,
                password: password,
              );
            } catch (e) {
              SafeDiagnostics.logFailure(
                '[LoginPageController] Import: decrypt failed with password',
                e,
              );
              return const ImportFailure(ImportFailureKind.invalidPassword);
            }
          } else {
            rethrow;
          }
        }
      }

      final toxId = accountData['toxId'] as String;
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
        rollbackToxId = toxId;
        await Directory(profileDir).create(recursive: true);
        await File(profileFilePath).writeAsBytes(toxProfile);
        if (password != null && password.isNotEmpty) {
          final encrypted = await _encryptProfileFileFn(
            profileFilePath,
            password,
          );
          if (!encrypted) {
            throw StateError('Failed to encrypt imported account profile');
          }
        }
      }

      final displayNickname = importedNickname.isNotEmpty
          ? importedNickname
          : importedAccountDefaultName;
      rollbackToxId ??= toxId;
      await _addAccountFn(
        toxId: toxId,
        nickname: displayNickname,
        statusMessage: '',
        autoLogin: false,
        autoAcceptFriends: false,
        notificationSoundEnabled: true,
      );
      if (isZip) {
        await _finalizeFullBackupImportFn(toxId: toxId);
      }
      if (!isZip && password != null && password.isNotEmpty) {
        final persisted = await _setAccountPasswordFn(toxId, password);
        if (!persisted) {
          throw StateError('Failed to persist imported account password');
        }
      }
      return const ImportSuccess();
    } on InvalidBackupPasswordException catch (e) {
      SafeDiagnostics.logFailure(
        '[LoginPageController] Full-backup password rejected',
        e,
      );
      return const ImportFailure(ImportFailureKind.invalidPassword);
    } catch (e) {
      if (rollbackToxId != null) {
        try {
          if (rollbackFullBackup) {
            await _rollbackFullBackupImportFn(toxId: rollbackToxId);
          } else {
            await _rollbackImportedAccountFn(
              toxId: rollbackToxId,
              logContext: 'LoginPageController',
            );
          }
        } catch (rollbackError) {
          SafeDiagnostics.logFailure(
            '[LoginPageController] Import rollback failed',
            rollbackError,
          );
        }
      }
      SafeDiagnostics.logFailure('[LoginPageController] Import failed', e);
      return ImportFailure(
        ImportFailureKind.generalError,
        detail: SafeDiagnostics.describeError(e),
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
          SafeDiagnostics.logFailure(
            '[LoginPageController] Restore: decrypt failed with password',
            e,
          );
          return const RestoreFailure(RestoreFailureKind.invalidPassword);
        }
      } catch (e) {
        // Non-password errors at this point (e.g. corrupt header) mean the
        // file is not a valid Tox profile.
        SafeDiagnostics.logFailure(
          '[LoginPageController] Restore: invalid tox file',
          e,
        );
        return RestoreFailure(
          RestoreFailureKind.notAToxProfile,
          detail: SafeDiagnostics.describeError(e),
        );
      }

      final toxId = accountData['toxId'] as String;
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
      rollbackToxId = toxId;
      await Directory(profileDir).create(recursive: true);
      await File(profileFilePath).writeAsBytes(toxProfile);
      if (password != null && password.isNotEmpty) {
        final encrypted = await _encryptProfileFileFn(
          profileFilePath,
          password,
        );
        if (!encrypted) {
          throw StateError('Failed to encrypt imported account profile');
        }
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
        final persisted = await _setAccountPasswordFn(toxId, password);
        if (!persisted) {
          throw StateError('Failed to persist imported account password');
        }
      }
      return RestoreSuccess(
        toxId: toxId,
        nickname: displayNickname,
        password: password,
      );
    } catch (e) {
      if (rollbackToxId != null) {
        try {
          await _rollbackImportedAccountFn(
            toxId: rollbackToxId,
            logContext: 'LoginPageController',
          );
        } catch (rollbackError) {
          SafeDiagnostics.logFailure(
            '[LoginPageController] Restore rollback failed',
            rollbackError,
          );
        }
      }
      SafeDiagnostics.logFailure('[LoginPageController] Restore failed', e);
      return RestoreFailure(
        RestoreFailureKind.generalError,
        detail: SafeDiagnostics.describeError(e),
      );
    }
  }
}
