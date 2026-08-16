/// Annex to [UiKeys] (`lib/ui/testing/ui_keys.dart`) for automation anchors on
/// the **pre-login** surfaces — the screens reachable before an `FfiChatService`
/// exists (`LoginSettingsPage` and friends).
///
/// WHY A SEPARATE FILE. `ui_keys.dart` is pinned at its current line count in
/// `tool/.complexity_baseline.txt` (the guard is a ratchet: baselined files may
/// shrink, never grow), so new entries cannot be appended there. Splitting is
/// the repository's documented alternative to re-pinning — the same move
/// `ui_keys_fork.dart` makes for fork-owned keys. The split line here is a real
/// one: these anchors belong to screens that exist only while LOGGED OUT, which
/// is precisely the axis the pre-login bootstrap-probe coverage turns on.
///
/// Same conventions as [UiKeys]: camelCase Dart field, snake_case
/// `<surface>_<role>` key string, grouped by the widget file that owns them.
library;

import 'package:flutter/foundation.dart';

/// Pre-login automation keys. Instantiated nowhere; use the statics directly.
class LoginUiKeys {
  LoginUiKeys._();

  // ---------------------------------------------------------------------
  // LoginSettingsPage (lib/ui/login_settings_page.dart)
  //
  // The logged-out settings screen, pushed from the LoginPage's settings chip
  // (`UiKeys.loginPageSettingsButton`). It hosts GlobalSettingsSection and —
  // the reason this annex exists — BootstrapSettingsSection with `service:
  // null`, the surface a user who CANNOT CONNECT has to use to configure a
  // working bootstrap node.
  //
  // Its scrollable deliberately reuses `UiKeys.settingsScrollView` so the
  // existing settings scroll helpers work here unchanged; the two pages are
  // never mounted at the same time (this one only exists logged out), so there
  // is no duplicate-key hazard.
  // ---------------------------------------------------------------------

  /// The app-bar back affordance that pops the whole page back to the LoginPage.
  /// Distinct from `UiKeys.settingsMobileSectionBackButton`, which pops a
  /// drill-in *section* of the logged-in settings page.
  static const Key loginSettingsBackButton = Key('login_settings_back_button');
}
