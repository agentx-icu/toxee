import 'package:flutter/material.dart';

import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme.dart';

import '../util/app_theme_config.dart';
import '../util/locale_controller.dart';
import '../util/logger.dart';
import '../util/responsive_layout.dart';
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
    // Before any UIKit widget builds: UIKit picks its phone or desktop
    // builders from this, and toxee's shell decides the layout.
    TencentCloudChatScreenAdapter.mobileScreenTypeResolver =
        uikitMobileScreenType;
    AppLogger.log('Theme and locale initialized');
  }

  /// The UIKit screen type on iOS / Android, derived from toxee's own layout
  /// decision. UIKit's fallback rule calls any window wider than tall
  /// "desktop"; in a short split-screen pane, a pop-up window or a landscape
  /// phone under the master-detail breakpoint toxee still shows the phone
  /// shell, and UIKit's desktop builders there drop the pushed chat's back
  /// button and the conversation app bar's title row, "+" and search entry.
  /// So: phone shell => phone builders. With master-detail on screen UIKit
  /// keeps its own rule (null).
  @visibleForTesting
  static DeviceScreenType? uikitMobileScreenType(BuildContext context) =>
      ResponsiveLayout.shouldShowMasterDetail(context)
      ? null
      : DeviceScreenType.mobile;
}
