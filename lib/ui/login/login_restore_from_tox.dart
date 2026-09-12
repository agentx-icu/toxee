part of 'login_page_controller.dart';

// The `.tox` single-file restore flow, split out of `login_page_controller.dart`
// (complexity-gate pin).
//
// A `part` + extension rather than a separate library: the flow drives the
// controller's private injected seams (`_importAccountDataFn`,
// `_encryptProfileFileFn`, ...), which an extension in another library cannot
// see. It still reads as `controller.restoreFromToxFile(...)` at every call site.
extension LoginRestoreFromTox on LoginPageController {
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
  /// Implementation of `LoginPageController.restoreFromToxFile`.
  ///
  /// Named separately because an extension method is resolved STATICALLY:
  /// if this were called `restoreFromToxFile`, a subclass override (the
  /// widget tests inject one) would be bypassed and the real file picker
  /// would run. The instance method on the class delegates here, so
  /// overriding still works.
  Future<RestoreResult> restoreFromToxFileImpl({
    required Future<String?> Function() requestPassword,
    required String importedAccountDefaultName,
    @visibleForTesting String? filePathOverride,
  }) async {
    String? filePath;
    String? rollbackToxId;
    // See importAccount: the rollback may only delete directories THIS restore
    // created.
    var ownership = const ImportedAccountOwnership.none();
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
      // Ownership records what was on disk BEFORE this attempt, so it is
      // captured first; the rollback itself is armed only once the journal write
      // below has succeeded. Arming first meant a failure of that write ran a
      // rollback for an attempt that had written nothing.
      ownership = await ImportedAccountRollback.captureOwnership(toxId);
      // JOURNALLED from here. Everything below writes durable state, and a
      // process death between any two steps used to leave an unrecoverable
      // shape: an unprotected profile that reconciliation would register, an
      // encrypted orphan that blocked re-import, or ciphertext with no verifier.
      // The in-process `catch` cannot help — a kill does not run it, and mobile
      // kills backgrounded apps routinely. See `ToxImportJournal`.
      final expectsPassword = password != null && password.isNotEmpty;
      await markToxImportStage(
        toxId: toxId,
        stage: ToxImportStage.profileWritten,
        expectsPassword: expectsPassword,
        ownership: ownership,
      );
      rollbackToxId = toxId;
      await Directory(profileDir).create(recursive: true);
      await File(profileFilePath).writeAsBytes(toxProfile);
      if (expectsPassword) {
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
        expectsPassword: expectsPassword,
        ownership: ownership,
      );

      // See importAccount: uniquified so a second .tox restore cannot collide.
      final displayNickname = await ImportedAccountName.allocate(
        preferred: importedNickname.isNotEmpty
            ? importedNickname
            : importedAccountDefaultName,
        toxId: toxId,
      );
      await _addAccountFn(
        toxId: toxId,
        nickname: displayNickname,
        statusMessage: '',
        autoLogin: false,
        autoAcceptFriends: false,
        notificationSoundEnabled: true,
      );
      await markToxImportStage(
        toxId: toxId,
        stage: ToxImportStage.accountPublished,
        expectsPassword: expectsPassword,
        ownership: ownership,
      );
      await DefaultAvatarInstaller.ensureSelfAvatar(toxId: toxId);
      if (expectsPassword) {
        final persisted = await _setAccountPasswordFn(toxId, password);
        if (!persisted) {
          throw StateError('Failed to persist imported account password');
        }
      }
      // Complete: the profile is on disk, protected if it needed to be, the row
      // is published and the verifier is stored. Nothing left to recover.
      await ToxImportJournal.clear(toxId: toxId);
      return RestoreSuccess(
        toxId: toxId,
        nickname: displayNickname,
        password: password,
      );
    } on ToxImportInFlightException catch (e) {
      // Nothing written yet (see the twin handler in importAccount), so no
      // rollback. Carried on `generalError` + `detail` for the same reason: a
      // new RestoreFailureKind would ripple through the shared enum and the
      // login page's exhaustive switch.
      SafeDiagnostics.logFailure('[LoginPageController] Restore blocked', e);
      return RestoreFailure(
        RestoreFailureKind.generalError,
        detail: lookupAppLocalizations(
          AppLocale.locale.value,
        ).importBlockedByPendingImport,
      );
    } catch (e) {
      if (rollbackToxId != null) {
        try {
          await _rollbackImportedAccountFn(
            toxId: rollbackToxId,
            logContext: 'LoginPageController',
            ownership: ownership,
          );
          // The in-process rollback already undid everything the journal
          // describes, so drop it — leaving it would make the next cold start
          // roll back an account that no longer exists.
          // VERIFIED clear — see the note in `importAccount`'s handler.
          await ToxImportJournal.clearIfRolledBack(toxId: rollbackToxId);
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
