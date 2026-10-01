import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/dark.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/light.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme_model.dart';
import 'package:tencent_cloud_chat_common/data/theme/text_style/text_style.dart';

import 'interface_style.dart';
import 'theme_controller.dart';

/// Shared application tokens, resolved from the current device appearance.
/// Explicit light/dark getters remain available to screens rendering both modes.
class AppThemeConfig {
  AppThemeConfig._();

  static Brightness get _brightness => switch (AppTheme.mode.value) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };
  static StyleGeometry get geometry => AppTheme.style.value.geometry;
  static StylePalette palette(Brightness brightness) =>
      AppTheme.style.value.palette(brightness);

  // ──────────────────────────────────────────────
  //  Light mode
  // ──────────────────────────────────────────────

  /// Primary brand color. Used for CTAs, links, focus rings.
  static Color get primaryColor => palette(_brightness).primary;

  /// Pressed/hover state for primary surfaces.
  static Color get secondaryColor => palette(_brightness).primary;

  /// Self message bubble — pale blue (sampled #E8F0FE), dark text.
  static Color get selfMessageBubbleColorLight =>
      palette(Brightness.light).sent;

  /// Self message text on the pale-blue bubble.
  static Color get selfMessageTextColorLight =>
      palette(Brightness.light).sentText;

  /// Scaffold — white.
  static Color get lightScaffoldBackground => palette(Brightness.light).canvas;

  /// Gradient anchors for startup / login splash and desktop sidebar.
  static Color get lightGradientStart => palette(Brightness.light).panel;
  static Color get lightGradientEnd => palette(Brightness.light).rail;

  /// Primary text — #1F2329.
  static Color get primaryTextColorLight => palette(Brightness.light).text;

  /// Secondary text — #646A73 (timestamps, snippets, metadata).
  static Color get secondaryTextColorLight => palette(Brightness.light).muted;

  /// Divider — hairline #E5E6EB.
  static Color get dividerColorLight => palette(Brightness.light).divider;

  // ──────────────────────────────────────────────
  //  Dark mode
  // ──────────────────────────────────────────────

  /// Brand blue holds up on the near-black dark surface.
  static Color get primaryColorDark => palette(Brightness.dark).primary;

  static Color get secondaryColorDark => palette(Brightness.dark).primary;

  /// Self bubble in dark — deep blue (sampled #15315F).
  static Color get selfMessageBubbleColorDark => palette(Brightness.dark).sent;

  /// Self bubble text — near-white.
  static Color get selfMessageTextColorDark =>
      palette(Brightness.dark).sentText;

  /// Message status / read tick in dark — recedes behind the bubble color.
  static Color get messageStatusIconColorDark => palette(Brightness.dark).muted;

  /// Others bubble in dark — lifted off the scaffold.
  static Color get othersMessageBubbleColorDark =>
      palette(Brightness.dark).received;

  /// Scaffold — near-black.
  static Color get darkScaffoldBackground => palette(Brightness.dark).canvas;

  /// Gradient anchors in dark.
  static Color get darkGradientStart => palette(Brightness.dark).canvas;
  static Color get darkGradientEnd => palette(Brightness.dark).panel;

  /// Primary text — near-white.
  static Color get primaryTextColorDark => palette(Brightness.dark).text;

  /// Secondary text.
  static Color get secondaryTextColorDark => palette(Brightness.dark).muted;

  /// Divider — hairline on dark.
  static Color get dividerColorDark => palette(Brightness.dark).divider;

  // ──────────────────────────────────────────────
  //  Semantic colors (shared across modes)
  // ──────────────────────────────────────────────

  /// Online / connected / success — green. Reserved for status, NOT brand.
  static Color get successColor => palette(_brightness).online;

  /// Error — red.
  static Color get errorColor => palette(_brightness).error;

  /// Away / idle — amber.
  static Color get statusAwayColor => palette(_brightness).warning;

  /// Busy / do-not-disturb.
  static Color get statusBusyColor => palette(_brightness).error;

  /// Connecting / syncing — neutral brand blue.
  static Color get statusConnectingColor => palette(_brightness).primary;

  /// Search keyword highlight background — light mode.
  static const Color searchHighlightColorLight = Color(0xFFFEF0A8);

  /// Search keyword highlight background — dark mode (primary @ ~30% alpha).
  static const Color searchHighlightColorDark = Color(0x4D3370FF);

  /// Drag-handle color on a bottom sheet — light mode.
  static const Color sheetHandleColorLight = Color(0xFFD0D3D9);

  /// Drag-handle color on a bottom sheet — dark mode.
  static const Color sheetHandleColorDark = Color(0xFF3A3D42);

  /// Snackbar surface — info variant (light).
  static const Color infoSnackbarBackgroundLight = Color(0xFFEFF0F2);

  /// Snackbar surface — info variant (dark).
  static const Color infoSnackbarBackgroundDark = Color(0xFF33373D);

  /// Hover overlay for an interactive row. 4% alpha of the base foreground.
  static Color hoverSurfaceFor(Color baseForeground) =>
      baseForeground.withValues(alpha: 0.04);

  /// Pre-baked hover surface on a light scaffold.
  static const Color hoverSurfaceLight = Color(0x0A1F2329);

  /// Pre-baked hover surface on a dark scaffold.
  static const Color hoverSurfaceDark = Color(0x0AFFFFFF);

  /// Lock digit width on numeric Text so values like "9 → 10" don't reflow.
  static TextStyle numericStyle(TextStyle? base, {Color? color}) =>
      (base ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      );

  // ──────────────────────────────────────────────
  //  Spacing scale (4pt grid — for any new screens)
  // ──────────────────────────────────────────────

  static const double space2 = 4.0;
  static const double space3 = 8.0;
  static const double space4 = 12.0;
  static const double space5 = 16.0;
  static const double space6 = 24.0;
  static const double space7 = 32.0;
  static const double space8 = 48.0;

  // ──────────────────────────────────────────────
  //  Border radii
  // ──────────────────────────────────────────────

  static double get cardBorderRadius => geometry.panelRadius;
  static double get buttonBorderRadius => geometry.controlRadius;
  static double get inputBorderRadius => geometry.controlRadius;
  static double get formCardBorderRadius => geometry.panelRadius;
  static const double badgeBorderRadius = 10.0;

  // ──────────────────────────────────────────────
  //  Elevation — single subtle layer
  // ──────────────────────────────────────────────

  /// Card / sheet shadow for light mode. Single soft layer.
  static const List<BoxShadow> elevationLight = [
    BoxShadow(color: Color(0x141F2329), blurRadius: 14, offset: Offset(0, 2)),
  ];

  /// Card / sheet shadow for dark mode — barely-there, mostly for shape edge.
  static const List<BoxShadow> elevationDark = [
    BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 4)),
  ];

  // ──────────────────────────────────────────────
  //  Tinted-primary card recipe
  // ──────────────────────────────────────────────

  /// Background color for a tinted-primary card: primary @ 8% alpha.
  static Color tintedPrimaryCardColor(Color primary) =>
      primary.withValues(alpha: 0.08);

  /// Border color for a tinted-primary card: primary @ 40% alpha.
  static Color tintedPrimaryCardBorderColor(Color primary) =>
      primary.withValues(alpha: 0.4);

  /// `RoundedRectangleBorder` shape for a tinted-primary card.
  static ShapeBorder tintedPrimaryCardShape(Color primary) =>
      RoundedRectangleBorder(
        side: BorderSide(color: tintedPrimaryCardBorderColor(primary)),
        borderRadius: BorderRadius.circular(cardBorderRadius),
      );

  /// Builds the TencentCloudChat UIKit theme model from the tokens above.
  ///
  /// Name kept as `createYouthfulThemeModel` for source compatibility with the
  /// existing call site.
  static TencentCloudChatThemeModel createYouthfulThemeModel({
    InterfaceStyle? style,
  }) {
    final selected = style ?? AppTheme.style.value;
    final light = selected.palette(Brightness.light);
    final dark = selected.palette(Brightness.dark);
    final geometry = selected.geometry;
    return TencentCloudChatThemeModel(
      lightTheme: LightTencentCloudChatColors(
        primaryColor: light.primary,
        secondaryColor: light.primary,
        onPrimary: light.onPrimary,
        onSecondary: light.onPrimary,
        onError: Colors.white,
        error: light.error,
        info: light.primary,
        backgroundColor: light.canvas,
        surface: light.panel,
        onSurface: light.text,
        onBackground: light.text,
        primaryTextColor: light.text,
        secondaryTextColor: light.muted,
        dividerColor: light.divider,
        tipsColor: light.error,
        // App bar — flat white, dark icons
        appBarBackgroundColor: light.canvas,
        appBarIconColor: light.text,
        // Buttons / switches
        firstButtonColor: light.primary,
        secondButtonColor: light.primary,
        switchActivatedColor: light.primary,
        // Input area
        inputAreaBackground: light.canvas,
        inputAreaIconColor: light.muted,
        inputFieldBorderColor: light.controlBorder,
        // Message bubbles — pale-blue self, gray others (no visible border)
        selfMessageBubbleColor: light.sent,
        selfMessageBubbleBorderColor: geometry.outlineWidth > 0
            ? light.controlBorder
            : light.sent,
        selfMessageTextColor: light.sentText,
        othersMessageBubbleColor: light.received,
        othersMessageBubbleBorderColor: geometry.outlineWidth > 0
            ? light.controlBorder
            : light.received,
        othersMessageTextColor: light.receivedText,
        messageStatusIconColor: light.primary,
        messageBeenChosenBackgroundColor: light.selected,
        messageTipsBackgroundColor: light.received,
        // Conversation list
        conversationItemNormalBgColor: light.panel,
        conversationItemIsPinedBgColor: light.selected,
        conversationItemShowNameTextColor: light.text,
        conversationItemLastMessageTextColor: light.muted,
        conversationItemTimeTextColor: light.muted,
        conversationItemUnreadCountBgColor: light.unread,
        conversationItemUnreadCountTextColor: light.onUnread,
        conversationItemSendingIconColor: light.primary,
        conversationItemDraftTextColor: light.error,
        conversationItemGroupAtInfoTextColor: light.error,
        conversationNoConversationTextColor: light.muted,
        conversationItemMoreActionItemNormalTextColor: light.primary,
        conversationItemMoreActionItemDeleteTextColor: light.error,
        conversationItemSwipeActionOneBgColor: light.primary,
        conversationItemSwipeActionTwoBgColor: light.error,
        // Desktop empty-page background
        desktopBackgroundColorLinearGradientOne: light.canvas,
        desktopBackgroundColorLinearGradientTwo: light.canvas,
        // Settings
        settingBackgroundColor: light.canvas,
        settingTitleColor: light.text,
        settingTabBackgroundColor: light.panel,
        settingInfoEditColor: light.primary,
        settingLogoutColor: light.error,
        // Contacts
        contactBackgroundColor: light.canvas,
        contactTabItemBackgroundColor: light.canvas,
        contactItemFriendNameColor: light.text,
        contactItemTabItemNameColor: light.muted,
        contactSearchBackgroundColor: light.received,
        contactBackButtonColor: light.text,
        contactAppBarIconColor: light.text,
        contactAgreeButtonColor: light.primary,
        contactRefuseButtonColor: light.muted,
        contactNoListColor: light.muted,
        // Group profile
        groupProfileTabBackground: light.panel,
        groupProfileTabTextColor: light.text,
        groupProfileTextColor: light.text,
        groupProfileAddMemberTextColor: light.primary,
        // Login
        loginBackgroundColor: light.canvas,
        loginCardBackground: light.panel,
        loginButtonDisableColor: light.muted,
      ),
      darkTheme: DarkTencentCloudChatColors(
        primaryColor: dark.primary,
        secondaryColor: dark.link,
        onPrimary: dark.onPrimary,
        onSecondary: dark.onPrimary,
        onError: Colors.white,
        error: dark.error,
        info: dark.link,
        backgroundColor: dark.canvas,
        surface: dark.panel,
        onSurface: dark.text,
        onBackground: dark.text,
        primaryTextColor: dark.text,
        secondaryTextColor: dark.muted,
        dividerColor: dark.divider,
        tipsColor: dark.error,
        appBarBackgroundColor: dark.canvas,
        appBarIconColor: dark.text,
        firstButtonColor: dark.primary,
        secondButtonColor: dark.primary,
        switchActivatedColor: dark.primary,
        inputAreaBackground: dark.panel,
        inputAreaIconColor: dark.muted,
        inputFieldBorderColor: dark.controlBorder,
        selfMessageBubbleColor: dark.sent,
        selfMessageBubbleBorderColor: geometry.outlineWidth > 0
            ? dark.controlBorder
            : dark.sent,
        selfMessageTextColor: dark.sentText,
        othersMessageBubbleColor: dark.received,
        othersMessageBubbleBorderColor: geometry.outlineWidth > 0
            ? dark.controlBorder
            : dark.received,
        othersMessageTextColor: dark.receivedText,
        messageStatusIconColor: dark.muted,
        messageBeenChosenBackgroundColor: dark.selected,
        messageTipsBackgroundColor: dark.panel,
        conversationItemNormalBgColor: dark.canvas,
        conversationItemIsPinedBgColor: dark.selected,
        conversationItemShowNameTextColor: dark.text,
        conversationItemLastMessageTextColor: dark.muted,
        conversationItemTimeTextColor: dark.muted,
        conversationItemUnreadCountBgColor: dark.unread,
        conversationItemUnreadCountTextColor: dark.onUnread,
        conversationItemSendingIconColor: dark.muted,
        conversationItemDraftTextColor: dark.error,
        conversationItemGroupAtInfoTextColor: dark.error,
        conversationNoConversationTextColor: dark.muted,
        conversationItemMoreActionItemNormalTextColor: dark.link,
        conversationItemMoreActionItemDeleteTextColor: dark.error,
        conversationItemSwipeActionOneBgColor: dark.primary,
        conversationItemSwipeActionTwoBgColor: dark.error,
        desktopBackgroundColorLinearGradientOne: dark.canvas,
        desktopBackgroundColorLinearGradientTwo: dark.canvas,
        settingBackgroundColor: dark.canvas,
        settingTitleColor: dark.text,
        settingTabBackgroundColor: dark.panel,
        settingInfoEditColor: dark.link,
        settingLogoutColor: dark.error,
        contactBackgroundColor: dark.canvas,
        contactTabItemBackgroundColor: dark.canvas,
        contactItemFriendNameColor: dark.text,
        contactItemTabItemNameColor: dark.muted,
        contactSearchBackgroundColor: dark.received,
        contactBackButtonColor: dark.text,
        contactAppBarIconColor: dark.text,
        contactAgreeButtonColor: dark.primary,
        contactRefuseButtonColor: dark.muted,
        contactNoListColor: dark.muted,
        groupProfileTabBackground: dark.panel,
        groupProfileTabTextColor: dark.text,
        groupProfileTextColor: dark.text,
        groupProfileAddMemberTextColor: dark.link,
        loginBackgroundColor: dark.canvas,
        loginCardBackground: dark.panel,
        loginButtonDisableColor: dark.muted,
      ),
      visualStyle: TencentCloudChatVisualStyle(
        panelRadius: geometry.panelRadius,
        controlRadius: geometry.controlRadius,
        bubbleRadius: geometry.bubbleRadius,
        bubbleTailRadius: geometry.bubbleTailRadius,
        outlineWidth: geometry.outlineWidth,
        shadowOffset: geometry.shadowOffset,
      ),
      textStyle: TencentCloudChatTextStyle(
        navigationTitle: 18,
        contactTitle: 17,
        messageBody: 15,
        messageSnippet: 15,
        buttonLabel: 15,
        standardText: 15,
        standardLargeText: 17,
        standardSmallText: 14,
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Radii / Motion tokens
// ──────────────────────────────────────────────

/// Radius tokens. Re-exports the values already defined on [AppThemeConfig]
/// where possible so we don't accidentally introduce two sources of truth.
class AppRadii {
  AppRadii._();

  /// Fully rounded ("pill" / capsule) — Stadium-equivalent radius.
  static const double pill = 999;

  /// Card surfaces — same value as [AppThemeConfig.cardBorderRadius].
  static double get card => AppThemeConfig.cardBorderRadius;

  /// Dialog surfaces.
  static const double dialog = 12;

  /// Modal bottom sheets.
  static const double sheet = 16;

  /// Buttons — same value as [AppThemeConfig.buttonBorderRadius].
  static double get button => AppThemeConfig.buttonBorderRadius;

  /// Inputs (text fields, search, etc.) — same as
  /// [AppThemeConfig.inputBorderRadius].
  static double get input => AppThemeConfig.inputBorderRadius;

  /// Small surfaces (tooltips, badges, chips' inner pills if non-stadium).
  static const double small = 6;
}

/// Motion duration tokens — keep transitions on a consistent rhythm.
class AppDurations {
  AppDurations._();

  /// Fast — for hover/press state-layer fades.
  static const Duration fast = Duration(milliseconds: 150);

  /// Medium — for most page-internal transitions (sheets, dialogs, list
  /// reorders).
  static const Duration medium = Duration(milliseconds: 250);

  /// Slow — for full-screen transitions and gentle hero-style moves.
  static const Duration slow = Duration(milliseconds: 350);
}

/// Motion curve tokens.
class AppCurves {
  AppCurves._();

  /// Entrances: decelerate into final position.
  static const Curve enter = Curves.easeOutCubic;

  /// Exits: accelerate away.
  static const Curve exit = Curves.easeInCubic;

  /// Standard / continuous transitions (e.g. an interactive drag releasing).
  static const Curve standard = Curves.easeInOutCubic;
}
