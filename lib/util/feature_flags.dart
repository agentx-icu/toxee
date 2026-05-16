/// App-scoped feature flags.
///
/// These are compile-time constants by design (v1). The identity-portability
/// CEO plan calls for a small, predictable surface that can be flipped per
/// release; no runtime toggle UI is needed yet. When a flag has shipped TRUE
/// across a full release without a user-reported issue, the flag and its
/// associated dead branch should be removed.
///
/// NOTE: app-scoped flags MUST live here, not in `prefs_interfaces.dart`,
/// because that file is the Tim2Tox bridge boundary and should not grow
/// app-only state. See docs/designs/identity-portability-and-multi-account.md
/// for the rationale.
class FeatureFlags {
  FeatureFlags._();

  /// Gates the first-run backup wizard shown immediately after a successful
  /// account registration. When TRUE (the default), a brand-new user cannot
  /// reach HomePage without either exporting their `.tox` file or explicitly
  /// confirming they understand that losing the device = losing the account.
  /// When FALSE, registration behavior is byte-identical to the pre-wizard
  /// release; flip back to FALSE if a user-reported issue appears.
  static const bool enableFirstRunBackupWizard = true;

  // Add new feature flags below in alphabetical order.
}
