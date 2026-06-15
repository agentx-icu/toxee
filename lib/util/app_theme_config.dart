import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/dark.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/light.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme_model.dart';
import 'package:tencent_cloud_chat_common/data/theme/text_style/text_style.dart';

import 'design_tokens.dart';

/// Centralized theme tokens for toxee.
///
/// Direction: clean enterprise-chat aesthetic matched from the reference
/// screenshots — blue (#3370FF) primary, white / near-black surfaces, pale-blue
/// self bubble, gray other bubble, periwinkle selection, hairline dividers,
/// 12px cards / 8px buttons. All color values delegate to [DesignTokens] (the
/// single sampled palette source) so existing page code that imports
/// `AppThemeConfig.*` inherits the new look without per-page edits.
class AppThemeConfig {
  AppThemeConfig._();

  // ──────────────────────────────────────────────
  //  Light mode
  // ──────────────────────────────────────────────

  /// Primary brand color. Used for CTAs, links, focus rings.
  static const Color primaryColor = DesignTokens.primary;

  /// Pressed/hover state for primary surfaces.
  static const Color secondaryColor = DesignTokens.primaryPressed;

  /// Self message bubble — pale blue (sampled #E8F0FE), dark text.
  static const Color selfMessageBubbleColorLight = DesignTokens.selfBubbleLight;

  /// Self message text on the pale-blue bubble.
  static const Color selfMessageTextColorLight = DesignTokens.selfBubbleTextLight;

  /// Scaffold — white.
  static const Color lightScaffoldBackground = DesignTokens.scaffoldLight;

  /// Gradient anchors for startup / login splash and desktop sidebar.
  static const Color lightGradientStart = Color(0xFFFFFFFF);
  static const Color lightGradientEnd = DesignTokens.railLight;

  /// Primary text — #1F2329.
  static const Color primaryTextColorLight = DesignTokens.textPrimaryLight;

  /// Secondary text — #646A73 (timestamps, snippets, metadata).
  static const Color secondaryTextColorLight = DesignTokens.textSecondaryLight;

  /// Divider — hairline #E5E6EB.
  static const Color dividerColorLight = DesignTokens.dividerLight;

  // ──────────────────────────────────────────────
  //  Dark mode
  // ──────────────────────────────────────────────

  /// Brand blue holds up on the near-black dark surface.
  static const Color primaryColorDark = DesignTokens.primary;

  static const Color secondaryColorDark = DesignTokens.primaryHover;

  /// Self bubble in dark — deep blue (sampled #15315F).
  static const Color selfMessageBubbleColorDark = DesignTokens.selfBubbleDark;

  /// Self bubble text — near-white.
  static const Color selfMessageTextColorDark = DesignTokens.selfBubbleTextDark;

  /// Message status / read tick in dark — recedes behind the bubble color.
  static const Color messageStatusIconColorDark = DesignTokens.textTertiaryDark;

  /// Others bubble in dark — lifted off the scaffold.
  static const Color othersMessageBubbleColorDark = DesignTokens.otherBubbleDark;

  /// Scaffold — near-black.
  static const Color darkScaffoldBackground = DesignTokens.scaffoldDark;

  /// Gradient anchors in dark.
  static const Color darkGradientStart = DesignTokens.scaffoldDark;
  static const Color darkGradientEnd = DesignTokens.listPanelDark;

  /// Primary text — near-white.
  static const Color primaryTextColorDark = DesignTokens.textPrimaryDark;

  /// Secondary text.
  static const Color secondaryTextColorDark = DesignTokens.textSecondaryDark;

  /// Divider — hairline on dark.
  static const Color dividerColorDark = DesignTokens.dividerDark;

  // ──────────────────────────────────────────────
  //  Semantic colors (shared across modes)
  // ──────────────────────────────────────────────

  /// Online / connected / success — green. Reserved for status, NOT brand.
  static const Color successColor = DesignTokens.online;

  /// Error — red.
  static const Color errorColor = DesignTokens.errorLight;

  /// Away / idle — amber.
  static const Color statusAwayColor = DesignTokens.warningLight;

  /// Busy / do-not-disturb.
  static const Color statusBusyColor = DesignTokens.errorLight;

  /// Connecting / syncing — neutral brand blue.
  static const Color statusConnectingColor = DesignTokens.primary;

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

  static const double cardBorderRadius = 12.0;
  static const double buttonBorderRadius = 8.0;
  static const double inputBorderRadius = 8.0;
  static const double formCardBorderRadius = 12.0;
  static const double badgeBorderRadius = 10.0;

  // ──────────────────────────────────────────────
  //  Elevation — single subtle layer
  // ──────────────────────────────────────────────

  /// Card / sheet shadow for light mode. Single soft layer.
  static const List<BoxShadow> elevationLight = [
    BoxShadow(
      color: Color(0x141F2329),
      blurRadius: 14,
      offset: Offset(0, 2),
    ),
  ];

  /// Card / sheet shadow for dark mode — barely-there, mostly for shape edge.
  static const List<BoxShadow> elevationDark = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 18,
      offset: Offset(0, 4),
    ),
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
  static TencentCloudChatThemeModel createYouthfulThemeModel() {
    return TencentCloudChatThemeModel(
      lightTheme: LightTencentCloudChatColors(
        primaryColor: DesignTokens.primary,
        secondaryColor: DesignTokens.primaryPressed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onError: Colors.white,
        error: DesignTokens.errorLight,
        info: DesignTokens.primary,
        backgroundColor: DesignTokens.scaffoldLight,
        surface: DesignTokens.cardLight,
        onSurface: DesignTokens.textPrimaryLight,
        onBackground: DesignTokens.textPrimaryLight,
        primaryTextColor: DesignTokens.textPrimaryLight,
        secondaryTextColor: DesignTokens.textSecondaryLight,
        dividerColor: DesignTokens.dividerLight,
        tipsColor: DesignTokens.errorLight,
        // App bar — flat white, dark icons
        appBarBackgroundColor: DesignTokens.scaffoldLight,
        appBarIconColor: DesignTokens.textPrimaryLight,
        // Buttons / switches
        firstButtonColor: DesignTokens.primary,
        secondButtonColor: DesignTokens.primary,
        switchActivatedColor: DesignTokens.primary,
        // Input area
        inputAreaBackground: DesignTokens.scaffoldLight,
        inputAreaIconColor: DesignTokens.textSecondaryLight,
        inputFieldBorderColor: DesignTokens.inputBorderLight,
        // Message bubbles — pale-blue self, gray others (no visible border)
        selfMessageBubbleColor: DesignTokens.selfBubbleLight,
        selfMessageBubbleBorderColor: DesignTokens.selfBubbleLight,
        selfMessageTextColor: DesignTokens.selfBubbleTextLight,
        othersMessageBubbleColor: DesignTokens.otherBubbleLight,
        othersMessageBubbleBorderColor: DesignTokens.otherBubbleLight,
        othersMessageTextColor: DesignTokens.textPrimaryLight,
        messageStatusIconColor: DesignTokens.primary,
        messageBeenChosenBackgroundColor: DesignTokens.selectedLight,
        messageTipsBackgroundColor: DesignTokens.hoverLight,
        // Conversation list
        conversationItemNormalBgColor: DesignTokens.listPanelLight,
        conversationItemIsPinedBgColor: DesignTokens.pinnedLight,
        conversationItemShowNameTextColor: DesignTokens.textPrimaryLight,
        conversationItemLastMessageTextColor: DesignTokens.textTertiaryLight,
        conversationItemTimeTextColor: DesignTokens.textTertiaryLight,
        conversationItemUnreadCountBgColor: DesignTokens.unreadBadge,
        conversationItemUnreadCountTextColor: DesignTokens.onUnreadBadge,
        conversationItemSendingIconColor: DesignTokens.primary,
        conversationItemDraftTextColor: DesignTokens.errorLight,
        conversationItemGroupAtInfoTextColor: DesignTokens.errorLight,
        conversationNoConversationTextColor: DesignTokens.textTertiaryLight,
        conversationItemMoreActionItemNormalTextColor: DesignTokens.primary,
        conversationItemMoreActionItemDeleteTextColor: DesignTokens.errorLight,
        conversationItemSwipeActionOneBgColor: DesignTokens.primary,
        conversationItemSwipeActionTwoBgColor: DesignTokens.errorLight,
        // Desktop empty-page background
        desktopBackgroundColorLinearGradientOne: DesignTokens.chatBgLight,
        desktopBackgroundColorLinearGradientTwo: DesignTokens.chatBgLight,
        // Settings
        settingBackgroundColor: const Color(0xFFF5F6F8),
        settingTitleColor: DesignTokens.textPrimaryLight,
        settingTabBackgroundColor: DesignTokens.cardLight,
        settingInfoEditColor: DesignTokens.primary,
        settingLogoutColor: DesignTokens.errorLight,
        // Contacts
        contactBackgroundColor: DesignTokens.scaffoldLight,
        contactTabItemBackgroundColor: DesignTokens.scaffoldLight,
        contactItemFriendNameColor: DesignTokens.textPrimaryLight,
        contactItemTabItemNameColor: DesignTokens.textSecondaryLight,
        contactSearchBackgroundColor: DesignTokens.inputFieldLight,
        contactBackButtonColor: DesignTokens.textPrimaryLight,
        contactAppBarIconColor: DesignTokens.textPrimaryLight,
        contactAgreeButtonColor: DesignTokens.primary,
        contactRefuseButtonColor: DesignTokens.textSecondaryLight,
        contactNoListColor: DesignTokens.textTertiaryLight,
        // Group profile
        groupProfileTabBackground: DesignTokens.cardLight,
        groupProfileTabTextColor: DesignTokens.textPrimaryLight,
        groupProfileTextColor: DesignTokens.textPrimaryLight,
        groupProfileAddMemberTextColor: DesignTokens.primary,
        // Login
        loginBackgroundColor: DesignTokens.scaffoldLight,
        loginCardBackground: DesignTokens.cardLight,
        loginButtonDisableColor: DesignTokens.textDisabledLight,
      ),
      darkTheme: DarkTencentCloudChatColors(
        primaryColor: DesignTokens.primary,
        secondaryColor: DesignTokens.primaryHover,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onError: Colors.white,
        error: DesignTokens.errorDark,
        info: DesignTokens.linkDark,
        backgroundColor: DesignTokens.scaffoldDark,
        surface: DesignTokens.cardDark,
        onSurface: DesignTokens.textPrimaryDark,
        onBackground: DesignTokens.textPrimaryDark,
        primaryTextColor: DesignTokens.textPrimaryDark,
        secondaryTextColor: DesignTokens.textSecondaryDark,
        dividerColor: DesignTokens.dividerDark,
        tipsColor: DesignTokens.errorDark,
        appBarBackgroundColor: DesignTokens.scaffoldDark,
        appBarIconColor: DesignTokens.textPrimaryDark,
        firstButtonColor: DesignTokens.primary,
        secondButtonColor: DesignTokens.primary,
        switchActivatedColor: DesignTokens.primary,
        inputAreaBackground: DesignTokens.inputAreaDark,
        inputAreaIconColor: DesignTokens.textSecondaryDark,
        inputFieldBorderColor: DesignTokens.inputBorderDark,
        selfMessageBubbleColor: DesignTokens.selfBubbleDark,
        selfMessageBubbleBorderColor: DesignTokens.selfBubbleDark,
        selfMessageTextColor: DesignTokens.selfBubbleTextDark,
        othersMessageBubbleColor: DesignTokens.otherBubbleDark,
        othersMessageBubbleBorderColor: DesignTokens.otherBubbleDark,
        othersMessageTextColor: DesignTokens.textPrimaryDark,
        messageStatusIconColor: DesignTokens.textTertiaryDark,
        messageBeenChosenBackgroundColor: DesignTokens.selectedDark,
        messageTipsBackgroundColor: DesignTokens.cardDark,
        conversationItemNormalBgColor: DesignTokens.scaffoldDark,
        conversationItemIsPinedBgColor: DesignTokens.selectedDark,
        conversationItemShowNameTextColor: DesignTokens.textPrimaryDark,
        conversationItemLastMessageTextColor: DesignTokens.textTertiaryDark,
        conversationItemTimeTextColor: DesignTokens.textTertiaryDark,
        conversationItemUnreadCountBgColor: DesignTokens.unreadBadge,
        conversationItemUnreadCountTextColor: DesignTokens.onUnreadBadge,
        conversationItemSendingIconColor: DesignTokens.textTertiaryDark,
        conversationItemDraftTextColor: DesignTokens.errorDark,
        conversationItemGroupAtInfoTextColor: DesignTokens.errorDark,
        conversationNoConversationTextColor: DesignTokens.textTertiaryDark,
        conversationItemMoreActionItemNormalTextColor: DesignTokens.linkDark,
        conversationItemMoreActionItemDeleteTextColor: DesignTokens.errorDark,
        conversationItemSwipeActionOneBgColor: DesignTokens.primary,
        conversationItemSwipeActionTwoBgColor: DesignTokens.errorDark,
        desktopBackgroundColorLinearGradientOne: DesignTokens.desktopChatDark,
        desktopBackgroundColorLinearGradientTwo: DesignTokens.desktopChatDark,
        settingBackgroundColor: DesignTokens.scaffoldDark,
        settingTitleColor: DesignTokens.textPrimaryDark,
        settingTabBackgroundColor: DesignTokens.cardDark,
        settingInfoEditColor: DesignTokens.linkDark,
        settingLogoutColor: DesignTokens.errorDark,
        contactBackgroundColor: DesignTokens.scaffoldDark,
        contactTabItemBackgroundColor: DesignTokens.scaffoldDark,
        contactItemFriendNameColor: DesignTokens.textPrimaryDark,
        contactItemTabItemNameColor: DesignTokens.textSecondaryDark,
        contactSearchBackgroundColor: DesignTokens.inputFieldDark,
        contactBackButtonColor: DesignTokens.textPrimaryDark,
        contactAppBarIconColor: DesignTokens.textPrimaryDark,
        contactAgreeButtonColor: DesignTokens.primary,
        contactRefuseButtonColor: DesignTokens.textSecondaryDark,
        contactNoListColor: DesignTokens.textTertiaryDark,
        groupProfileTabBackground: DesignTokens.cardDark,
        groupProfileTabTextColor: DesignTokens.textPrimaryDark,
        groupProfileTextColor: DesignTokens.textPrimaryDark,
        groupProfileAddMemberTextColor: DesignTokens.linkDark,
        loginBackgroundColor: DesignTokens.scaffoldDark,
        loginCardBackground: DesignTokens.cardDark,
        loginButtonDisableColor: DesignTokens.textDisabledDark,
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
