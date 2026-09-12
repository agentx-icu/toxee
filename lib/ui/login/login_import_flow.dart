part of '../login_page.dart';

// The account-import entry point on the login page, split out of
// `login_page.dart` (complexity-gate pin). It is one flow: pick a file, hand it
// to `LoginPageController`, then translate the typed outcome into what the user
// sees - including the one outcome that has to refresh the account list before
// pointing at it.

extension _LoginImportFlow on _LoginPageState {
  Future<void> _importToxProfile() async {
    if (_importInProgress) return;
    _importInProgress = true;
    try {
      final l10n = AppLocalizations.of(context)!;
      final result = await _loginController.importAccount(
        requestPassword: () => _showPasswordDialog(l10n.enterPasswordToImport),
        importedAccountDefaultName: l10n.importedAccountDefaultName,
      );
      if (!mounted) return;
      switch (result) {
        case ImportSuccess():
          await _loadAccountList();
          if (!mounted) return;
          setState(() => _error = null);
          AppSnackBar.showSuccess(
            context,
            AppLocalizations.of(context)!.accountImportedSuccessfully,
          );
          break;
        case ImportFailure(:final kind, :final detail):
          final localized = AppLocalizations.of(context)!;
          final message = switch (kind) {
            ImportFailureKind.noFileSelected => localized.importNoFileSelected,
            ImportFailureKind.cancelled => localized.importCancelled,
            ImportFailureKind.invalidPassword => localized.invalidPassword,
            ImportFailureKind.accountAlreadyExists =>
              localized.accountAlreadyExists,
            ImportFailureKind.mayRemainImported =>
              localized.importMayHaveCompleted,
            ImportFailureKind.generalError => localized.failedToImport(
              detail ?? '',
            ),
          };
          // That message sends the user to the account list, and the account WAS
          // published before the failure - a stale picker would not show it.
          if (kind == ImportFailureKind.mayRemainImported) {
            await _loadAccountList();
            if (!mounted) break;
          }
          setState(() => _error = message);
          // Suppress the toast for user-initiated cancellation paths; surface
          // it for genuine failures.
          if (kind != ImportFailureKind.noFileSelected &&
              kind != ImportFailureKind.cancelled) {
            AppSnackBar.showError(context, message);
          }
          break;
      }
    } finally {
      _importInProgress = false;
    }
  }
}
