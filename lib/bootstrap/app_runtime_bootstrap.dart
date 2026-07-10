import 'package:flutter/material.dart';

import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme.dart';

import '../util/app_theme_config.dart';
import '../util/locale_controller.dart';
import '../util/logger.dart';
import '../util/theme_controller.dart';

/// Theme, locale, and UIKit theme initialization.
class AppRuntimeBootstrap {
  AppRuntimeBootstrap._();

  static Future<void> initialize() async {
    AppLogger.log('Initializing theme and locale...');
    await AppTheme.initFromPrefs();
    await AppLocale.initFromPrefs();
    // Resolve ThemeMode.system against the actual OS brightness so the UIKit
    // colorTheme matches the Material app from the very first frame. The old
    // `== dark ? dark : light` collapsed system→light, so a system-dark device
    // started with a light UIKit app bar on a dark Material scaffold (desync).
    // `_syncUIKitThemeBrightness` later re-applies the same resolution, but
    // getting it right at startup avoids an initial mismatched flash.
    final mode = AppTheme.mode.value;
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    TencentCloudChatTheme.init(
      themeModel: AppThemeConfig.createYouthfulThemeModel(),
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
    AppLogger.log('Theme and locale initialized');
  }
}
