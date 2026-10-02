/// Annex to [UiKeys] (`lib/ui/testing/ui_keys.dart`) for automation anchors
/// on settings surfaces added after `ui_keys.dart` reached its complexity pin
/// (see `ui_keys_home.dart` for why annexes exist).
///
/// Same conventions as [UiKeys]: camelCase Dart field, snake_case
/// `<surface>_<role>` key string.
library;

import 'package:flutter/foundation.dart';

/// Settings automation keys. Instantiated nowhere; use the statics directly.
class SettingsUiKeys {
  SettingsUiKeys._();

  // ---------------------------------------------------------------------
  // BackgroundSettingsSection (lib/ui/settings/background_settings_section.dart)
  // ---------------------------------------------------------------------

  /// Mobile settings index tile that opens the section.
  static const Key mobileBackgroundSection = Key(
    'settings_mobile_background_section',
  );

  /// "Hide message content in notifications" switch.
  static const Key hideNotificationContentSwitch = Key(
    'settings_hide_notification_content_switch',
  );

  /// Android: requests the battery-optimization exemption.
  static const Key backgroundRunningAllowButton = Key(
    'settings_background_running_allow_button',
  );

  // ---------------------------------------------------------------------
  // Account Management — "Import Account" (settings_page_build.dart on the
  // desktop root, settings_page_mobile_widgets.dart inside the pushed mobile
  // section). The two layouts are mutually exclusive, so they share the key.
  // The password prompts the button leads to are PasswordPromptDialog's
  // (see LoginUiKeys.passwordPrompt*).
  // ---------------------------------------------------------------------
  static const Key importAccountButton = Key('settings_import_account_button');

  // ---------------------------------------------------------------------
  // ExportPasswordDialog (lib/ui/settings/export_password_dialog.dart)
  //
  // The EXPORT password + confirmation prompt in front of every user-facing
  // export (Settings `.tox` and full backup, the login page's saved-account
  // export, the first-run backup wizard). On iOS the system save sheet after
  // it cannot be driven over the VM service, so the dialog itself must be.
  // ---------------------------------------------------------------------

  static const Key exportPasswordField = Key('settings_export_password_field');
  static const Key exportPasswordConfirmField = Key(
    'settings_export_password_confirm_field',
  );
  static const Key exportPasswordOkButton = Key(
    'settings_export_password_ok_button',
  );
  static const Key exportPasswordCancelButton = Key(
    'settings_export_password_cancel_button',
  );

  /// Shown while the export password is empty in the optional (`.tox`) mode:
  /// the file will be written UNENCRYPTED.
  static const Key exportPasswordEmptyWarning = Key(
    'settings_export_password_empty_warning',
  );
}
