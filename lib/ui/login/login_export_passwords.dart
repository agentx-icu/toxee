import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/secret_password.dart';
import '../settings/export_password_dialog.dart';
import '../widgets/app_snackbar.dart';
import 'login_password_gate.dart';
import 'password_prompt_dialog.dart';

/// The two independent passwords a logged-out (login page) export needs, as
/// bytes. OWNED by the receiver, which calls [dispose] once the export ran.
final class LoginExportPasswords {
  const LoginExportPasswords({
    required this.accountPassword,
    required this.exportPassword,
  });

  /// Opens the at-rest profile of a protected account; null when the account
  /// has no password (its profile is plaintext at rest).
  final SecretPassword? accountPassword;

  /// Seals the exported file; null means "write it unencrypted" — chosen
  /// explicitly by the user in the export dialog, under its warning line.
  final SecretPassword? exportPassword;

  /// Zeroes both passwords.
  void dispose() {
    accountPassword?.dispose();
    exportPassword?.dispose();
  }
}

/// Collects both passwords for exporting a saved account from the login page,
/// where there is NO live session to vouch for the user.
///
/// 1. Protected account: ask for the ACCOUNT password through the shared login
///    gate ([resolveAccountPassword]: reconciles an interrupted password
///    change, distinguishes cancel / wrong password / unreadable secure store).
///    Anything but a verified password returns null before anything is
///    exported, so no file is ever written. This step is authentication only;
///    its password is never reused as the export password.
/// 2. Always: ask for the EXPORT password in a second dialog
///    ([showExportPasswordDialog], empty allowed under a visible warning).
///
/// Contract: null = abort (cancelled at either step, wrong account password,
/// or secure store unavailable — the last two with an error snackbar). A
/// non-null result may carry `exportPassword: null` (the user chose an
/// unencrypted file) and, for an unprotected account, `accountPassword: null`.
Future<LoginExportPasswords?> promptLoginExportPasswords(
  BuildContext context, {
  required String toxId,
  required String nickname,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final gate = await resolveAccountPassword(
    toxId: toxId,
    cachedVerifiedPassword: null,
    // Runs after the gate's own awaits (reconcile, protection state).
    promptForPassword: () async {
      if (!context.mounted) return null;
      return showDialog<String>(
        context: context,
        builder: (context) => PasswordPromptDialog(
          title: l10n.enterAccountPasswordToExport(nickname),
        ),
      );
    },
  );
  // The gate's verified password is OWNED here until it is handed over in the
  // result; every abort path below zeroes it.
  final accountPassword = gate.password;
  if (!context.mounted) {
    accountPassword?.dispose();
    return null;
  }
  switch (gate.result) {
    case PasswordGateResult.cancelled:
      return null;
    case PasswordGateResult.invalid:
      AppSnackBar.showError(context, l10n.invalidPassword);
      return null;
    case PasswordGateResult.storeUnavailable:
      AppSnackBar.showError(context, l10n.secureStorageUnavailable);
      return null;
    case PasswordGateResult.notRequired:
    case PasswordGateResult.verified:
      break;
  }
  final String? exportPassword;
  try {
    exportPassword = await showExportPasswordDialog(
      context,
      allowEmpty: true,
    );
  } catch (_) {
    accountPassword?.dispose();
    rethrow;
  }
  // Cancel is checked BEFORE '' is mapped to "unencrypted".
  if (exportPassword == null) {
    accountPassword?.dispose();
    return null;
  }
  return LoginExportPasswords(
    accountPassword: accountPassword,
    // The dialog's String is converted here, once.
    exportPassword: SecretPassword.fromStringOrNull(
      exportPasswordOrNull(exportPassword),
    ),
  );
}
