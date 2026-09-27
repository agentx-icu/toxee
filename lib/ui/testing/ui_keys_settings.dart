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
}
