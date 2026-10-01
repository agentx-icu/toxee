import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';

import 'locale_controller.dart';
import 'app_theme_config.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme.dart';
import 'theme_controller.dart';

/// Shared "apply appearance everywhere" helpers.
///
/// The app renders through TWO theme/locale systems at once: the app-level
/// MaterialApp (driven by [AppTheme] / [AppLocale]) and the embedded
/// TencentCloudChat UIKit surfaces (conversation list / chat panel), which
/// follow their own controller ([TencentCloudChat.controller] brightness,
/// [TencentCloudChatIntl] locale). Changing only one side produces a
/// mixed-theme / mixed-locale UI.
///
/// These functions are the single source of truth for switching both sides
/// together. Callers: the Settings page rows
/// (`global_settings_section.dart`) and the L3 harness setter
/// (`l3_set_setting{themeMode|languageCode}` in `l3_debug_tools.dart`) used
/// by the product-screenshot pipeline.

/// Apply [mode] to the app theme AND the UIKit brightness in one step.
///
/// For [ThemeMode.system] the UIKit side needs a concrete [Brightness]; pass
/// the widget-tree value (`MediaQuery.platformBrightnessOf(context)`) when a
/// context is available — headless callers fall back to the
/// [PlatformDispatcher] value, which is the same source one hop earlier.
Future<void> applyThemeModeEverywhere(
  ThemeMode mode, {
  Brightness? platformBrightness,
}) async {
  await AppTheme.set(mode);
  final resolved = switch (mode) {
    ThemeMode.dark => Brightness.dark,
    ThemeMode.light => Brightness.light,
    ThemeMode.system =>
      platformBrightness ??
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };
  TencentCloudChat.controller.setBrightnessMode(resolved);
}

/// Apply [locale] to the app localizations AND the UIKit intl controller.
Future<void> applyLocaleEverywhere(Locale locale) async {
  await AppLocale.set(locale);
  TencentCloudChatIntl().setLocale(locale);
}

/// Refresh both UIKit palette and brightness without recreating chat state.
void syncUIKitAppearance({Brightness? platformBrightness}) {
  final resolved = switch (AppTheme.mode.value) {
    ThemeMode.dark => Brightness.dark,
    ThemeMode.light => Brightness.light,
    ThemeMode.system =>
      platformBrightness ??
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };
  TencentCloudChatTheme.init(
    brightness: resolved,
    themeModel: AppThemeConfig.createYouthfulThemeModel(),
  );
}
