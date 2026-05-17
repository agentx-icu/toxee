import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/dark.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/light.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme_model.dart';
import 'package:tencent_cloud_chat_common/data/theme/text_style/text_style.dart';

/// Centralized theme tokens for toxee.
///
/// Direction: modern messenger (Telegram / Linear inspired) — messenger blue
/// primary, emerald reserved for online/success, neutral slate scale, hairline
/// borders, gently softened radii. Solves the "too WeChat-ish" + "typography
/// hierarchy unclear" feedback by replacing the WeChat green/gray palette and
/// pushing visual rhythm through the spacing/elevation scale below + the text
/// theme defined in `main.dart`.
class AppThemeConfig {
  AppThemeConfig._();

  // ──────────────────────────────────────────────
  //  Light mode — slate neutrals + messenger blue
  // ──────────────────────────────────────────────

  /// Primary brand color — Tailwind blue-600. Used for CTAs, links, focus rings.
  static const Color primaryColor = Color(0xFF2563EB);

  /// Pressed/hover state for primary surfaces.
  static const Color secondaryColor = Color(0xFF1D4ED8);

  /// Soft tint background for self message bubble.
  /// Replaces the saturated WeChat green; sits comfortably against the white
  /// scaffold and keeps "this is me" recognition without shouting.
  static const Color selfMessageBubbleColorLight = Color(0xFFDBEAFE);

  /// Self message text on the blue-tinted bubble (slate-900, AAA contrast).
  static const Color selfMessageTextColorLight = Color(0xFF0F172A);

  /// Scaffold — slate-50. Calmer than the WeChat gray, lets surfaces breathe.
  static const Color lightScaffoldBackground = Color(0xFFF8FAFC);

  /// Gradient anchors for startup / login splash and desktop sidebar.
  static const Color lightGradientStart = Color(0xFFFFFFFF);
  static const Color lightGradientEnd = Color(0xFFE4ECFC);

  /// Primary text — slate-900.
  static const Color primaryTextColorLight = Color(0xFF0F172A);

  /// Secondary text — slate-500 (timestamps, snippets, metadata).
  static const Color secondaryTextColorLight = Color(0xFF64748B);

  /// Divider — slate-200 with a cool tint to harmonize with the blue accent.
  static const Color dividerColorLight = Color(0xFFE4ECFC);

  // ──────────────────────────────────────────────
  //  Dark mode — slate-900 base, soft-blue primary
  // ──────────────────────────────────────────────

  /// Lighter blue for dark mode (blue-500). Reads cleanly on slate-900 surface
  /// without the over-saturation of the light-mode primary.
  static const Color primaryColorDark = Color(0xFF3B82F6);

  static const Color secondaryColorDark = Color(0xFF60A5FA);

  /// Self bubble in dark — desaturated blue, mirrors light mode tinting logic.
  static const Color selfMessageBubbleColorDark = Color(0xFF1E3A8A);

  /// Self bubble text — near-white slate (avoids harsh pure white).
  static const Color selfMessageTextColorDark = Color(0xFFE2E8F0);

  /// Message status / read tick in dark — slate-400 neutral so it sits behind
  /// the bubble color, not on top of it.
  static const Color messageStatusIconColorDark = Color(0xFF94A3B8);

  /// Others bubble in dark — surface elevation 1.
  static const Color othersMessageBubbleColorDark = Color(0xFF1E293B);

  /// Scaffold — slate-900.
  static const Color darkScaffoldBackground = Color(0xFF0F172A);

  /// Gradient anchors in dark — slate-900 → slate-800.
  static const Color darkGradientStart = Color(0xFF0F172A);
  static const Color darkGradientEnd = Color(0xFF1E293B);

  /// Primary text — slate-200 (softer than pure white, no glare).
  static const Color primaryTextColorDark = Color(0xFFE2E8F0);

  /// Secondary text — slate-400.
  static const Color secondaryTextColorDark = Color(0xFF94A3B8);

  /// Divider — slate-800. Hairline-feel on dark.
  static const Color dividerColorDark = Color(0xFF1E293B);

  // ──────────────────────────────────────────────
  //  Semantic colors (shared across modes)
  // ──────────────────────────────────────────────

  /// Online / connected / success — emerald. Reserved for status, NOT brand.
  /// Keeps the "green = good" instinct from chat apps without making the whole
  /// app green like WeChat.
  static const Color successColor = Color(0xFF059669);

  /// Error — red-600. Slightly desaturated vs the WeChat red.
  static const Color errorColor = Color(0xFFDC2626);

  /// Away / idle — amber. Use for "user hasn't been active for X minutes".
  static const Color statusAwayColor = Color(0xFFF59E0B); // amber-500
  /// Busy / do-not-disturb — slate red distinct from errorColor (which is
  /// reserved for genuine error states).
  static const Color statusBusyColor = Color(0xFFEF4444); // red-500
  /// Connecting / syncing — pulses on a neutral blue. Distinct from primary
  /// CTA color (slightly lighter / desaturated).
  static const Color statusConnectingColor = Color(0xFF3B82F6); // blue-500

  /// Search keyword highlight background — light mode (yellow-200, gentle).
  static const Color searchHighlightColorLight = Color(0xFFFEF08A);
  /// Search keyword highlight background — dark mode (primary @ 30% alpha,
  /// stays on-brand and visible against slate surfaces).
  static const Color searchHighlightColorDark = Color(0x4D3B82F6);

  /// Drag-handle color on a bottom sheet — light mode (slate-300).
  static const Color sheetHandleColorLight = Color(0xFFCBD5E1);
  /// Drag-handle color on a bottom sheet — dark mode (slate-700).
  static const Color sheetHandleColorDark = Color(0xFF334155);

  /// Snackbar surface — info variant (light): slate-100 panel.
  static const Color infoSnackbarBackgroundLight = Color(0xFFE2E8F0);
  /// Snackbar surface — info variant (dark): slate-700 panel for legibility
  /// against the slate-900 scaffold (instead of low-alpha slate which
  /// disappears in dark mode).
  static const Color infoSnackbarBackgroundDark = Color(0xFF334155);

  /// Hover overlay for an interactive row. Uses 4% alpha of the base color
  /// (Material 3 state-layer spec). Pair with InkWell or MouseRegion to keep
  /// hover surfaces visually consistent across the app.
  static Color hoverSurfaceFor(Color baseForeground) =>
      baseForeground.withValues(alpha: 0.04);

  /// Pre-baked hover surface on a light scaffold — slate-900 @ 4%.
  static const Color hoverSurfaceLight = Color(0x0A0F172A);
  /// Pre-baked hover surface on a dark scaffold — white @ 4%.
  static const Color hoverSurfaceDark = Color(0x0AFFFFFF);

  /// Lock digit width on numeric Text so values like "9 → 10", "9:59 → 10:00",
  /// "999 KB → 1.0 MB" don't reflow. Pair with any base TextStyle (typically
  /// from Theme.of(context).textTheme).
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
  //  Border radii — gently looser than WeChat clone
  // ──────────────────────────────────────────────

  static const double cardBorderRadius = 14.0;
  static const double buttonBorderRadius = 10.0;
  static const double inputBorderRadius = 10.0;
  static const double formCardBorderRadius = 16.0;
  static const double badgeBorderRadius = 10.0;

  // ──────────────────────────────────────────────
  //  Elevation — single subtle layer
  // ──────────────────────────────────────────────

  /// Card / sheet shadow for light mode. Single soft layer; avoids the "flat
  /// then deep" jump that hurt the old look.
  static const List<BoxShadow> elevationLight = [
    BoxShadow(
      color: Color(0x140F172A), // slate-900 @ 8%
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
  //
  // Shared decoration for the "subtle primary-tinted card" pattern used to
  // emphasize a canonical action (e.g. the create-account path on the login
  // screen, the primary action card on the upgrade-required screen, the
  // primary option in add-group). Centralizing the alphas keeps every tinted
  // card visually consistent — change them here, not at each call site.

  /// Background color for a tinted-primary card: primary @ 8% alpha.
  static Color tintedPrimaryCardColor(Color primary) =>
      primary.withValues(alpha: 0.08);

  /// Border color for a tinted-primary card: primary @ 40% alpha.
  static Color tintedPrimaryCardBorderColor(Color primary) =>
      primary.withValues(alpha: 0.4);

  /// `RoundedRectangleBorder` shape for a tinted-primary card — pairs the 40%
  /// alpha border with the standard [cardBorderRadius].
  static ShapeBorder tintedPrimaryCardShape(Color primary) =>
      RoundedRectangleBorder(
        side: BorderSide(color: tintedPrimaryCardBorderColor(primary)),
        borderRadius: BorderRadius.circular(cardBorderRadius),
      );

  /// Builds the TencentCloudChat UIKit theme model from the tokens above.
  ///
  /// Name kept as `createYouthfulThemeModel` for source compatibility with the
  /// existing call site; the actual aesthetic is modern-messenger.
  static TencentCloudChatThemeModel createYouthfulThemeModel() {
    return TencentCloudChatThemeModel(
      lightTheme: LightTencentCloudChatColors(
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        secondButtonColor: primaryColor,
        primaryTextColor: primaryTextColorLight,
        backgroundColor: const Color(0xFFFFFFFF),
        surface: lightScaffoldBackground,
        secondaryTextColor: secondaryTextColorLight,
        dividerColor: dividerColorLight,
        tipsColor: errorColor,
        othersMessageBubbleBorderColor: dividerColorLight,
        contactItemTabItemNameColor: secondaryTextColorLight,
        appBarBackgroundColor: lightScaffoldBackground,
        appBarIconColor: primaryTextColorLight,
        firstButtonColor: primaryColor,
        switchActivatedColor: primaryColor,
        contactBackButtonColor: primaryColor,
        contactAppBarIconColor: primaryColor,
        contactAgreeButtonColor: primaryColor,
        settingInfoEditColor: primaryColor,
        groupProfileAddMemberTextColor: primaryColor,
        conversationItemSendingIconColor: primaryColor,
        conversationItemMoreActionItemNormalTextColor: primaryColor,
        conversationItemSwipeActionOneBgColor: primaryColor,
        conversationItemNormalBgColor: lightScaffoldBackground,
        conversationItemIsPinedBgColor: const Color(0xFFEFF6FF), // blue-50
        conversationItemShowNameTextColor: primaryTextColorLight,
        conversationItemLastMessageTextColor: secondaryTextColorLight,
        conversationItemTimeTextColor: secondaryTextColorLight,
        conversationNoConversationTextColor: secondaryTextColorLight,
        messageStatusIconColor: primaryColor,
        // Message bubbles — soft blue self, white others, hairline divider
        selfMessageBubbleColor: selfMessageBubbleColorLight,
        selfMessageTextColor: selfMessageTextColorLight,
        othersMessageBubbleColor: Colors.white,
        othersMessageTextColor: primaryTextColorLight,
        // Desktop gradient (empty page, sidebar)
        desktopBackgroundColorLinearGradientOne: lightGradientStart,
        desktopBackgroundColorLinearGradientTwo: lightGradientEnd,
        // Settings
        settingBackgroundColor: lightScaffoldBackground,
        settingTitleColor: primaryTextColorLight,
        settingTabBackgroundColor: lightScaffoldBackground,
        // Contacts
        contactTabItemBackgroundColor: lightScaffoldBackground,
        contactItemFriendNameColor: primaryTextColorLight,
        contactSearchBackgroundColor: const Color(0xFFFFFFFF),
        contactBackgroundColor: lightScaffoldBackground,
      ),
      darkTheme: DarkTencentCloudChatColors(
        primaryColor: primaryColorDark,
        secondaryColor: secondaryColorDark,
        onPrimary: const Color(0xFF0F172A),
        onSecondary: const Color(0xFF0F172A),
        secondButtonColor: primaryColorDark,
        primaryTextColor: primaryTextColorDark,
        backgroundColor: darkScaffoldBackground,
        surface: othersMessageBubbleColorDark,
        secondaryTextColor: secondaryTextColorDark,
        dividerColor: dividerColorDark,
        tipsColor: errorColor,
        othersMessageBubbleBorderColor: dividerColorDark,
        contactItemTabItemNameColor: secondaryTextColorDark,
        appBarBackgroundColor: darkScaffoldBackground,
        appBarIconColor: primaryTextColorDark,
        firstButtonColor: primaryColorDark,
        switchActivatedColor: primaryColorDark,
        contactBackButtonColor: primaryColorDark,
        contactAppBarIconColor: primaryColorDark,
        contactAgreeButtonColor: primaryColorDark,
        settingInfoEditColor: primaryColorDark,
        groupProfileAddMemberTextColor: primaryColorDark,
        conversationItemSendingIconColor: primaryColorDark,
        conversationItemMoreActionItemNormalTextColor: primaryColorDark,
        conversationItemSwipeActionOneBgColor: primaryColorDark,
        conversationItemNormalBgColor: darkScaffoldBackground,
        conversationItemIsPinedBgColor: const Color(0xFF1E293B),
        conversationItemShowNameTextColor: primaryTextColorDark,
        conversationItemLastMessageTextColor: secondaryTextColorDark,
        conversationItemTimeTextColor: secondaryTextColorDark,
        conversationNoConversationTextColor: secondaryTextColorDark,
        messageStatusIconColor: messageStatusIconColorDark,
        // Message bubbles — deep blue self, slate-800 others
        selfMessageBubbleColor: selfMessageBubbleColorDark,
        selfMessageTextColor: selfMessageTextColorDark,
        othersMessageBubbleColor: othersMessageBubbleColorDark,
        othersMessageTextColor: primaryTextColorDark,
        // Desktop gradient
        desktopBackgroundColorLinearGradientOne: darkGradientStart,
        desktopBackgroundColorLinearGradientTwo: darkGradientEnd,
        // Settings
        settingBackgroundColor: darkScaffoldBackground,
        settingTitleColor: primaryTextColorDark,
        settingTabBackgroundColor: darkScaffoldBackground,
        // Contacts
        contactTabItemBackgroundColor: othersMessageBubbleColorDark,
        contactItemFriendNameColor: primaryTextColorDark,
        contactSearchBackgroundColor: othersMessageBubbleColorDark,
        contactBackgroundColor: darkScaffoldBackground,
      ),
      textStyle: TencentCloudChatTextStyle(
        // Sizes-only API. Hierarchy comes from these + the Material textTheme
        // in main.dart (which controls weights and tracking).
        //
        // Floor raised for `messageSnippet` (14→15) and `standardSmallText`
        // (13→14): iOS auto-zooms any TextField with computed font size below
        // 16pt, and these tokens sit next to inputs in the conversation /
        // contact rows. Bumping them shrinks the trigger surface for that
        // zoom while still keeping the snippet visibly secondary to body text.
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
//  Radii / Motion tokens (Phase 1 component theme tokens)
// ──────────────────────────────────────────────
//
// New canonical names for radii + motion. Existing radii in [AppThemeConfig]
// stay where they are (other code already imports them); [AppRadii] re-exports
// them so future code can use one consistent name surface.

/// Radius tokens. Re-exports the values already defined on [AppThemeConfig]
/// where possible so we don't accidentally introduce two sources of truth.
class AppRadii {
  AppRadii._();

  /// Fully rounded ("pill" / capsule) — Stadium-equivalent radius.
  static const double pill = 999;

  /// Card surfaces — same value as [AppThemeConfig.cardBorderRadius].
  static double get card => AppThemeConfig.cardBorderRadius;

  /// Dialog surfaces — slightly tighter than the form-card.
  static const double dialog = 16;

  /// Modal bottom sheets — matches [dialog] for visual consistency.
  static const double sheet = 16;

  /// Buttons — same value as [AppThemeConfig.buttonBorderRadius].
  static double get button => AppThemeConfig.buttonBorderRadius;

  /// Inputs (text fields, search, etc.) — same value as
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
