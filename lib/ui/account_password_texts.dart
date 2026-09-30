// User-facing texts for the failures the savedata-at-rest work introduced.
// One place, so the login page, the settings page and the backup wizard say
// the same thing for the same cause.

import '../i18n/app_localizations.dart';
import '../util/account_export/exceptions.dart';
import '../util/account_password_change.dart';
import '../util/profile_open_failure.dart';
import '../util/safe_diagnostics.dart';

/// Reason text for `failedToSetPassword(reason)` (lower case, follows a colon).
String passwordChangeFailureText(
  AppLocalizations l10n,
  PasswordChangeOutcome outcome, {
  required bool removing,
}) {
  switch (outcome) {
    case PasswordChangeOutcome.ok:
      return '';
    case PasswordChangeOutcome.pendingChange:
      return l10n.passwordChangePending;
    case PasswordChangeOutcome.rekeyFailed:
      return l10n.passwordRekeyFailed;
    case PasswordChangeOutcome.storageFailed:
      return removing ? l10n.couldNotRemovePassword : l10n.couldNotSavePassword;
  }
}

/// The message for a failed account export (.tox or full backup).
String exportFailureText(AppLocalizations l10n, Object error) {
  if (error is SessionPasswordUnavailableException) {
    return l10n.exportRequiresLogin;
  }
  return l10n.failedToExportAccount(SafeDiagnostics.describeError(error));
}

/// The message for a login that failed with [error], when a typed cause is
/// known; null means "no special wording, use the generic one".
String? loginFailureText(AppLocalizations l10n, Object error) {
  if (error is ProfileUnopenableWithPasswordException) {
    return error.passwordChangeInFlight
        ? l10n.passwordChangeInterrupted
        : l10n.profileUnopenableWithPassword;
  }
  return null;
}
