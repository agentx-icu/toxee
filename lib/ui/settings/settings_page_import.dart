part of 'settings_page.dart';

// The Settings account-import transaction, split out of `settings_page.dart`
// (complexity-gate pin).
//
// It is one flow with three durable steps and a rollback, which is why it is
// long: a `.tox` import writes the profile, protects it, then publishes the
// account row, journalling each step so a kill is recoverable; a `.zip` import
// hands the same job to `FullBackupRestoreTransaction`. The failure path has to
// distinguish "this import wrote something that must be undone" from "this
// import was refused before it wrote anything" - undoing the latter deletes the
// EXISTING account's password and scoped preferences.

extension _SettingsImportFlow on _SettingsPageState {
  Future<void> _importAccount() async {
    if (_importInProgress) return;
    setState(() => _importInProgress = true);
    String? rollbackToxId;
    var rollbackFullBackup = false;
    // Set when the rollback refused to half-undo a published restore: the
    // account may remain, so say so instead of reporting a plain failure.
    var rollbackDeclined = false;
    var rollbackImportedAccount = false;
    // What this import creates on disk. The rollback may only delete that; the
    // target directories are keyed by the account's 16-char prefix, so one can
    // already hold a previous account's data. See ImportedAccountRollback.
    var ownership = const ImportedAccountOwnership.none();
    // Whether a `.tox` journal entry was written, so the failure path clears it.
    var journalledToxImport = false;
    final l10n = AppLocalizations.of(context)!;
    try {
      // Show file picker for .tox and .zip files
      final filePath = await _pickImportFileFn();
      if (filePath == null) return;
      final isZip = filePath.toLowerCase().endsWith('.zip');

      // No pre-read here on purpose. This used to slurp the ENTIRE picked file
      // into memory to test `length >= 80` and then do nothing with it — a
      // hundreds-of-megabytes allocation for a full-backup .zip, on the UI
      // isolate, discarded immediately. The importers below already detect
      // encryption themselves and raise PasswordRequiredException, which is
      // what actually drives the password prompt.
      String? password;

      // Import account data (will check encryption and prompt for password if needed)
      Map<String, dynamic> accountData;

      if (isZip) {
        // ZIP: check account collision before any disk writes (importFullBackup writes profile/history/avatars/prefs).
        Map<String, String> metadata;
        try {
          metadata = await AccountExportService.readFullBackupMetadata(
            filePath,
            password: password,
          );
        } on PasswordRequiredException {
          if (!mounted) return;
          password = await _showPasswordDialog(l10n.enterPasswordToImport);
          if (password == null || !mounted) return;
          if (password.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.invalidPassword),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
            return;
          }
          metadata = await AccountExportService.readFullBackupMetadata(
            filePath,
            password: password,
          );
        }
        final metaToxId = metadata['toxId']!;
        final existingAccount = await Prefs.getAccountByToxId(metaToxId);
        final profileDir = await AppPaths.getProfileDirectoryForToxId(
          metaToxId,
        );
        final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
        if (existingAccount != null || await File(profileFilePath).exists()) {
          await _showAccountAlreadyExistsDialog(l10n);
          return;
        }
        // Arm the rollback only now that the guards have passed. Arming it
        // before them meant an exception thrown DURING those checks ran
        // `rollbackPendingFullBackupRestore`, which — if an unfinished restore
        // journal for this same account was on disk — deleted its committed
        // profile and account-data directories. Matches the ordering in
        // LoginPageController.importAccount.
        // ARMED ONLY AFTER the restore returns. Anything that throws before
        // that - a missing source file, an unsupported inner format version, a
        // refused admission because another transaction for this account is
        // committed and waiting - wrote nothing HERE, and the rollback matches
        // on account id alone, so running it deleted the live owner's profile,
        // history and journal. Exempting individual exception types was the
        // first attempt and kept missing new ones; there is nothing to undo
        // until there is something to undo. Everything before this point is the
        // service's own to clean up, inside its transaction.
        accountData = await AccountExportService.importFullBackup(
          filePath: filePath,
          password: password,
        );
        rollbackToxId = metaToxId;
        rollbackFullBackup = true;
      } else {
        try {
          accountData = await _importAccountDataFn(
            filePath: filePath,
            password: password,
          );
        } on PasswordRequiredException {
          if (!mounted) return;
          password = await _showPasswordDialog(l10n.enterPasswordToImport);
          if (password == null || !mounted) return;
          try {
            accountData = await _importAccountDataFn(
              filePath: filePath,
              password: password,
            );
          } catch (e) {
            SafeDiagnostics.logFailure(
              '[SettingsPage] Import password rejected',
              e,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.invalidPassword),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
            return;
          }
        }
      }

      final toxId = accountData['toxId'] as String;
      rollbackToxId = toxId;
      final toxProfile = accountData['toxProfile'] as Uint8List?;
      final importedNickname = (accountData['nickname'] as String?) ?? '';
      final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
      final profileFilePath = AppPaths.profileFileInDirectory(profileDir);

      // Collision check for .tox path only (ZIP already checked above)
      if (!isZip) {
        final existingAccount = await Prefs.getAccountByToxId(toxId);
        if (existingAccount != null || await File(profileFilePath).exists()) {
          await _showAccountAlreadyExistsDialog(l10n);
          return;
        }
      }

      // For .tox imports, write profile; .zip imports already wrote it in importFullBackup
      if (!isZip && toxProfile != null) {
        // Ownership is captured BEFORE anything is written - it records what was
        // already on disk - but the rollback is ARMED only once the journal
        // write has succeeded. Arming first meant an ordinary I/O failure of
        // that very write ran a rollback for an import that had created nothing,
        // deleting the password verifier and scoped preferences of whatever is
        // already under this id. The exception guard in the catch only covered
        // a REFUSED admission; a failed one took the destructive path.
        ownership = await ImportedAccountRollback.captureOwnership(toxId);
        // JOURNALLED — the third `.tox` entry point, same crash windows as the
        // other two (plaintext before encryption, ciphertext before the
        // verifier). An in-process catch does not survive a kill.
        await markToxImportStage(
          toxId: toxId,
          stage: ToxImportStage.profileWritten,
          expectsPassword: password != null && password.isNotEmpty,
          ownership: ownership,
        );
        journalledToxImport = true;
        rollbackImportedAccount = true;
        await Directory(profileDir).create(recursive: true);
        final toxProfileFile = File(profileFilePath);
        await toxProfileFile.writeAsBytes(toxProfile);
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

      // Add/update account (.zip may contain nickname, .tox does not)
      // Uniquified: a `.tox` file carries no nickname, so every such import
      // wants the same constant and the second one used to fail inside
      // addAccount. See ImportedAccountName.
      final displayNickname = await ImportedAccountName.allocate(
        preferred: importedNickname.isNotEmpty
            ? importedNickname
            : l10n.importedAccount,
        toxId: toxId,
      );
      if (!isZip) rollbackImportedAccount = true;
      await _addImportedAccountFn(
        toxId: toxId,
        nickname: displayNickname,
        // Carried from a `.zip` backup's metadata when present; a `.tox` file
        // genuinely has no status message. Restore used to always pass '',
        // which the next login then pushed to Tox, erasing what the backup had
        // preserved.
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
        await AccountExportService.finalizeFullBackupImport(toxId: toxId);
      }
      // After the finalize so a restored self avatar is adopted, not
      // shadowed by a fresh default (see LoginPageController).
      await DefaultAvatarInstaller.ensureSelfAvatar(toxId: toxId);

      // Only .tox import passwords are account passwords. Full-backup .zip
      // passwords decrypt the archive and must not silently become the
      // restored account's login password.
      if (!isZip && password != null && password.isNotEmpty) {
        final persisted = await _setImportedAccountPasswordFn(toxId, password);
        if (!persisted) {
          throw StateError('Failed to persist imported account password');
        }
      }

      // Complete: nothing left for cold-start recovery to undo.
      if (journalledToxImport) await ToxImportJournal.clear(toxId: toxId);

      // Reload account list
      await _loadAccountList();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.accountImportedSuccessfully),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } on InvalidBackupPasswordException catch (e) {
      SafeDiagnostics.logFailure(
        '[SettingsPage] Full-backup password rejected',
        e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.invalidPassword),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      // A REFUSED admission wrote nothing, so there is nothing to roll back -
      // and running the rollback anyway is destructive: `rollbackImportedAccount`
      // and `ownership` are armed just before the journal write, so
      // `ImportedAccountRollback.run` would delete the password and scoped
      // preferences of the account that is ALREADY on disk under this id.
      // BOTH refusals. `RestoreInFlightException` is the `.zip` path's version
      // of the same thing - another restore of this account is committed and
      // waiting to publish - and it likewise means this attempt wrote nothing.
      // Rolling back on it deleted the LIVE owner's profile and history.
      final admissionRefused =
          e is ToxImportInFlightException ||
          AccountExportService.isRestoreAdmissionRefusal(e);
      if (!admissionRefused &&
          rollbackToxId != null &&
          (rollbackFullBackup || rollbackImportedAccount)) {
        try {
          if (rollbackFullBackup) {
            await AccountExportService.rollbackPendingFullBackupRestore(
              toxId: rollbackToxId,
            );
          } else {
            await ImportedAccountRollback.run(
              toxId: rollbackToxId,
              logContext: 'SettingsPage',
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
          // The rollback declined to half-undo the transaction, so the account
          // may still be there and startup recovery will finish it. Reporting
          // only the original failure left the user believing nothing happened.
          rollbackDeclined = true;
          SafeDiagnostics.logFailure(
            '[SettingsPage] Import rollback failed',
            rollbackError,
          );
        }
      }
      SafeDiagnostics.logFailure('[SettingsPage] Import account failed', e);
      // A refused journal write (another import still on record, or one that
      // cannot be read) is fixed by a restart, which rolls that import back.
      final message = rollbackDeclined
          ? l10n.importMayHaveCompleted
          : e is ToxImportInFlightException
          ? l10n.importBlockedByPendingImport
          : l10n.failedToImportAccount(SafeDiagnostics.describeError(e));
      if (rollbackDeclined) await _loadAccountList();
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.importAccount),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => popDialogIfCurrent(context),
                child: Text(l10n.ok),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _importInProgress = false);
      } else {
        _importInProgress = false;
      }
    }
  }
}
