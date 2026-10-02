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

  // ---------------------------------------------------------------------
  // LoginPage (lib/ui/login_page.dart)
  // ---------------------------------------------------------------------

  /// The "Import Account" action card (`.tox` or full-backup `.zip`). The
  /// string predates this constant and is referenced by the real-UI harness,
  /// so it is kept verbatim.
  static const Key loginPageImportAccountCard = Key(
    'login_page_import_account_card',
  );

  // ---------------------------------------------------------------------
  // PasswordPromptDialog (lib/ui/login/password_prompt_dialog.dart)
  //
  // One dialog for every single-password prompt: the saved-account gate, the
  // `.tox` restore, and BOTH layers of a full-backup import (archive password,
  // then — for an older backup whose profile is ciphertext — the account
  // password). The Settings import flow reuses the same widget, so these keys
  // are valid logged in as well; only one prompt is ever open at a time.
  // ---------------------------------------------------------------------

  /// The password field. Historical string (the dialog began as the quick-login
  /// gate), kept because the harness types into it by this name.
  static const Key passwordPromptField = Key('login_quick_password_field');
  static const Key passwordPromptOkButton = Key('password_prompt_ok_button');
  static const Key passwordPromptCancelButton = Key(
    'password_prompt_cancel_button',
  );
}
