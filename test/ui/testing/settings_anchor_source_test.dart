import 'dart:io';

void _expectContains(String source, String needle, String label) {
  if (!source.contains(needle)) {
    throw StateError('Missing $label: $needle');
  }
}

void main() {
  final uiKeys = File('lib/ui/testing/ui_keys.dart').readAsStringSync();
  final settingsBuild = File(
    'lib/ui/settings/settings_page_build.dart',
  ).readAsStringSync();
  final settingsPage = File(
    'lib/ui/settings/settings_page.dart',
  ).readAsStringSync();
  final settingsWidgets = File(
    'lib/ui/settings/settings_page_widgets.dart',
  ).readAsStringSync();

  _expectContains(
    uiKeys,
    'static const Key settingsCopyToxIdButton = Key('
    "'settings_copy_tox_id_button'",
    'UiKeys.settingsCopyToxIdButton',
  );
  _expectContains(
    uiKeys,
    "static const Key settingsSetPasswordButton = Key(\n"
    "    'settings_set_password_button'",
    'UiKeys.settingsSetPasswordButton',
  );
  _expectContains(
    uiKeys,
    "static const Key settingsAccountSwitchConfirmButton = Key(\n"
    "    'settings_account_switch_confirm_button'",
    'UiKeys.settingsAccountSwitchConfirmButton',
  );
  _expectContains(
    uiKeys,
    "static const Key settingsAccountSwitchCancelButton = Key(\n"
    "    'settings_account_switch_cancel_button'",
    'UiKeys.settingsAccountSwitchCancelButton',
  );
  _expectContains(
    uiKeys,
    "static const Key settingsLogoutButton = Key('settings_logout_button')",
    'UiKeys.settingsLogoutButton',
  );
  _expectContains(
    uiKeys,
    "static const Key settingsLogoutConfirmButton = Key(\n"
    "    'settings_logout_confirm_button'",
    'UiKeys.settingsLogoutConfirmButton',
  );
  _expectContains(
    settingsBuild,
    'key: UiKeys.settingsCopyToxIdButton',
    'settings copy button attachment',
  );
  _expectContains(
    settingsWidgets,
    'key: UiKeys.settingsSetPasswordButton',
    'settings set-password button attachment',
  );
  _expectContains(
    settingsWidgets,
    'key: UiKeys.settingsLogoutButton',
    'settings logout button attachment',
  );
  _expectContains(
    settingsPage,
    'key: UiKeys.settingsAccountSwitchCancelButton',
    'settings account-switch cancel attachment',
  );
  _expectContains(
    settingsPage,
    'key: UiKeys.settingsAccountSwitchConfirmButton',
    'settings account-switch confirm attachment',
  );
  _expectContains(
    settingsPage,
    'key: UiKeys.settingsLogoutConfirmButton',
    'settings logout confirm attachment',
  );
}
