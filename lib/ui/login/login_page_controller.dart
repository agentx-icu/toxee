import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../auth/login_use_case.dart';
import '../../i18n/app_localizations.dart';
import '../../util/account_export_service.dart';
import '../../util/app_paths.dart';
import '../../util/default_avatar_installer.dart';
import '../../util/account_export/restore_transaction_journal.dart';
import '../../util/account_export/tox_import_journal.dart';
import '../../util/imported_account_name.dart';
import '../../util/imported_account_rollback.dart';
import '../../util/locale_controller.dart';
import '../../util/prefs.dart';
import '../../util/safe_diagnostics.dart';
import '../testing/l3_debug_tools.dart';
import 'login_controller_results.dart';

export 'login_controller_results.dart';

part 'login_restore_from_tox.dart';

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
    Future<void> Function({
      required String toxId,
      required String logContext,
      ImportedAccountOwnership ownership,
    });

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
  ImportedAccountOwnership ownership = const ImportedAccountOwnership.none(),
}) {
  return ImportedAccountRollback.run(
    toxId: toxId,
    logContext: logContext,
    ownership: ownership,
  );
}

class LoginPageController {
  /// Restore an account from a single `.tox` file.
  ///
  /// An INSTANCE method that delegates, not an extension method. The body lives
  /// in `login_restore_from_tox.dart` (this file had grown past the complexity
  /// gate's pin), but extension methods are resolved statically — so exposing it
  /// as one would bypass subclass overrides, and the widget tests inject exactly
  /// such an override to avoid driving the real file picker. Keeping a virtual
  /// entry point preserves that.
  Future<RestoreResult> restoreFromToxFile({
    required Future<String?> Function() requestPassword,
    required String importedAccountDefaultName,
    @visibleForTesting String? filePathOverride,
  }) {
    return restoreFromToxFileImpl(
      requestPassword: requestPassword,
      importedAccountDefaultName: importedAccountDefaultName,
      filePathOverride: filePathOverride,
    );
  }
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
       // `Prefs.addAccount` satisfies `AddAccountFn` directly (its extra
       // named params are optional), so no forwarding wrapper is needed.
       _addAccountFn = addAccountFn ?? Prefs.addAccount,
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
    // Set when the rollback refused to half-undo a published restore: the
    // account may remain, so say so instead of reporting a plain failure.
    var rollbackDeclined = false;
    // What this import creates on disk, captured before the first write. See
    // ImportedAccountRollback: the target directories are keyed by the 16-char
    // prefix, so one can already hold a previous account's data.
    var ownership = const ImportedAccountOwnership.none();
    // Whether this import wrote a `.tox` journal entry, so the failure path
    // clears it (the in-process rollback has already undone what it describes).
    var journalledToxImport = false;
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
        // Armed only AFTER the restore returns; see the note at the matching
        // point in `settings_page_import.dart`. A failure before this wrote
        // nothing here, and the rollback matches on account id alone.
        accountData = await _importFullBackupFn(
          filePath: filePath,
          password: password,
        );
        rollbackToxId = toxId;
        rollbackFullBackup = true;
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
        // Ownership is captured before any write (it records what was already
        // there); the rollback is ARMED only after the journal write succeeds.
        // Arming first let an I/O failure of that write trigger a rollback for
        // an import that created nothing, deleting the verifier and scoped
        // preferences of whatever already lives under this id.
        ownership = await ImportedAccountRollback.captureOwnership(toxId);
        // JOURNALLED — same three windows as the dedicated restore flow. An
        // in-process catch cannot cover a kill, and this is the other `.tox`
        // entry point, so it needs the same record.
        await markToxImportStage(
          toxId: toxId,
          stage: ToxImportStage.profileWritten,
          expectsPassword: password != null && password.isNotEmpty,
          ownership: ownership,
        );
        rollbackToxId = toxId;
        journalledToxImport = true;
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
        await markToxImportStage(
          toxId: toxId,
          stage: ToxImportStage.profileProtected,
          expectsPassword: password != null && password.isNotEmpty,
          ownership: ownership,
        );
      }

      // Allocate a name no OTHER account holds. `.tox` files carry no nickname,
      // so every such import wants the same constant default and the second one
      // used to die inside addAccount with an opaque error. See
      // ImportedAccountName.
      final displayNickname = await ImportedAccountName.allocate(
        preferred: importedNickname.isNotEmpty
            ? importedNickname
            : importedAccountDefaultName,
        toxId: toxId,
      );
      rollbackToxId ??= toxId;
      // A `.zip` backup carries the account's status message in its metadata.
      // It was being exported and then dropped on restore, so both import UIs
      // created the row with '' and the next login pushed that empty status to
      // Tox — overwriting exactly what the backup had preserved. `.tox` files
      // genuinely have none, hence the fallback.
      await _addAccountFn(
        toxId: toxId,
        nickname: displayNickname,
        statusMessage: (accountData['statusMessage'] as String?) ?? '',
        autoLogin: false,
        autoAcceptFriends: false,
        notificationSoundEnabled: true,
      );
      if (journalledToxImport) {
        await markToxImportStage(
          toxId: toxId,
          stage: ToxImportStage.accountPublished,
          expectsPassword: password != null && password.isNotEmpty,
          ownership: ownership,
        );
      }
      if (isZip) {
        await _finalizeFullBackupImportFn(toxId: toxId);
      }
      // After the .zip finalize so a restored self avatar is adopted, not
      // shadowed by a fresh default; the picker then has an avatar pre-login.
      await DefaultAvatarInstaller.ensureSelfAvatar(toxId: toxId);
      if (!isZip && password != null && password.isNotEmpty) {
        final persisted = await _setAccountPasswordFn(toxId, password);
        if (!persisted) {
          throw StateError('Failed to persist imported account password');
        }
      }
      // Complete: nothing left for cold-start recovery to undo.
      if (journalledToxImport) await ToxImportJournal.clear(toxId: toxId);
      return const ImportSuccess();
    } on InvalidBackupPasswordException catch (e) {
      SafeDiagnostics.logFailure(
        '[LoginPageController] Full-backup password rejected',
        e,
      );
      return const ImportFailure(ImportFailureKind.invalidPassword);
    } on ToxImportInFlightException catch (e) {
      // Refused BEFORE this import writes anything - the journal entry is its
      // first durable step - so there is nothing to roll back here.
      //
      // ONE message for both `identified` cases: whether the stale record names
      // another account or cannot be parsed at all, the user's move is the same
      // (restart, which runs `recoverPendingImport`, then import again), and the
      // difference is only meaningful to a log reader.
      //
      // The kind stays `generalError`: a dedicated kind would mean editing the
      // shared result enum and every exhaustive switch over it for copy that the
      // `detail` field already carries. Localized here rather than in the UI
      // because the controller has no BuildContext - same pattern as
      // CallServiceManager's notification strings.
      SafeDiagnostics.logFailure('[LoginPageController] Import blocked', e);
      return ImportFailure(
        ImportFailureKind.generalError,
        detail: lookupAppLocalizations(
          AppLocale.locale.value,
        ).importBlockedByPendingImport,
      );
    } catch (e) {
      // A refused admission - either journal's - wrote nothing, and rolling back
      // on it destroys the LIVE owner's data: the rollback matches on account id
      // alone, so it undoes whichever transaction currently holds that account.
      final admissionRefused =
          e is ToxImportInFlightException || e is RestoreInFlightException;
      if (!admissionRefused && rollbackToxId != null) {
        try {
          if (rollbackFullBackup) {
            await _rollbackFullBackupImportFn(toxId: rollbackToxId);
          } else {
            await _rollbackImportedAccountFn(
              toxId: rollbackToxId,
              logContext: 'LoginPageController',
              ownership: ownership,
            );
            // VERIFIED clear. The rollback above is best-effort, so dropping
            // the journal unconditionally could discard the record of a cleanup
            // that failed — and the next startup would then reconcile over the
            // leftover instead of retrying.
            if (journalledToxImport) {
              await ToxImportJournal.clearIfRolledBack(toxId: rollbackToxId);
            }
          }
        } catch (rollbackError) {
          rollbackDeclined = true;
          SafeDiagnostics.logFailure(
            '[LoginPageController] Import rollback failed',
            rollbackError,
          );
        }
      }
      SafeDiagnostics.logFailure('[LoginPageController] Import failed', e);
      return ImportFailure(
        ImportFailureKind.generalError,
        detail: rollbackDeclined
            ? lookupAppLocalizations(
                AppLocale.locale.value,
              ).importMayHaveCompleted
            : SafeDiagnostics.describeError(e),
      );
    }
  }


}
