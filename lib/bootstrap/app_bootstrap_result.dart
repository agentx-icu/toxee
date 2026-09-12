/// Result of [AppBootstrap.initialize].
sealed class AppBootstrapResult {
  const AppBootstrapResult();
}

/// Bootstrap completed successfully; run the app.
class AppBootstrapSuccess extends AppBootstrapResult {
  const AppBootstrapSuccess();
}

/// Stored prefs were created by a newer app version; show upgrade required UI.
class AppBootstrapUpgradeRequired extends AppBootstrapResult {
  const AppBootstrapUpgradeRequired({
    required this.storedVersion,
    required this.currentVersion,
  });

  final int storedVersion;
  final int currentVersion;
}

/// A journalled account recovery could not be completed, so no account may be
/// exposed — but the app must still start, into a screen that says so.
///
/// WHY THIS EXISTS: recovery of a pending full-backup restore / account deletion
/// runs before anything can touch an account, and it is deliberately
/// FAIL-CLOSED — `app_bootstrap_recovery_order_test.dart` pins that a failure
/// there stops account reconciliation. But the failure used to propagate out of
/// `AppBootstrap.initialize()`, which `main()` awaits BEFORE `runApp`, so a
/// journal that could not be parsed (a truncated write is exactly what these
/// journals exist to survive) left the user with a black screen, no message and
/// no way in.
///
/// Fail-closed is about not exposing a half-restored account. It is not about
/// refusing to render. This result keeps the former and drops the latter.
class AppBootstrapRecoveryBlocked extends AppBootstrapResult {
  const AppBootstrapRecoveryBlocked({required this.detail});

  /// Sanitized description of what could not be recovered.
  ///
  /// Never a path or a Tox ID: this reaches the screen AND the log, and the
  /// journal paths embed the account's public-key prefix plus the absolute
  /// application-support layout. Same rule as `RestoreDestinationExistsError`.
  final String detail;
}
