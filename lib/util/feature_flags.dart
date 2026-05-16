/// App-scoped feature flags.
///
/// Flags are intentionally `const bool` so the Dart compiler can tree-shake
/// the disabled branches at build time. Toggling a flag requires a code change
/// + rebuild, not a runtime config — this is by design for the identity
/// portability rollout (per the CEO plan, item "Phased delivery").
///
/// App-scoped flags MUST live here, not in `prefs_interfaces.dart`, because
/// that file is the Tim2Tox bridge boundary and should not grow app-only
/// state. See docs/designs/identity-portability-and-multi-account.md for the
/// rationale.
///
/// Add new flags below in **alphabetical order** so concurrent PRs don't
/// collide on the same neighbouring lines.
class FeatureFlags {
  FeatureFlags._();

  /// First-run backup wizard + restore-on-new-device flow polish (PR 1).
  ///
  /// When TRUE (the default), a brand-new user cannot reach HomePage without
  /// either exporting their `.tox` file or explicitly confirming they
  /// understand that losing the device = losing the account. When FALSE,
  /// registration behavior is byte-identical to the pre-wizard release; flip
  /// back to FALSE if a user-reported issue appears.
  ///
  /// Default per CEO plan: **TRUE on merge** (UI change, low risk).
  static const bool enableFirstRunBackupWizard = true;

  /// QR + LAN cross-device pairing (PR 2).
  ///
  /// Default per CEO plan: **FALSE on merge, FLIP TRUE after one release of
  /// canary + manual smoke on three platforms.** UI affordance hidden when
  /// off.
  ///
  /// Scope reminder: this is a *convenience* feature for the both-devices-in-
  /// the-same-room case, NOT a device-loss recovery path. Device loss is
  /// covered solely by `.tox` export + restore (`enableFirstRunBackupWizard`).
  static const bool enableQRPairing = false;
}
