import 'package:flutter/material.dart';

/// Design tokens for the toxee visual restyle — a clean enterprise-chat
/// aesthetic matched pixel-for-pixel from the provided reference screenshots.
///
/// This is the single source of truth for the restyle palette.
///
/// Usage:
/// - **toxee pages** (`lib/**`): use these constants, or
///   `Theme.of(context).colorScheme` (seeded from [primary]). For a value that
///   differs light/dark, pick with [resolve] or `Theme.of(context).brightness`.
/// - **UIKit** (`third_party/chat-uikit-flutter/**`) cannot import this file; it
///   reads `colorTheme.<slot>`, whose values are wired from these tokens in
///   `app_theme_config.dart → createYouthfulThemeModel()`.
///
/// Color values are sampled directly from the reference images, so they are
/// authoritative — prefer a token here over inventing a new hex at a call site.
class DesignTokens {
  DesignTokens._();

  // ── Brand / accent (mode-independent) ──
  /// Primary brand blue. Active tab sampled #3068F0; canonical brand blue.
  static const Color primary = Color(0xFF3370FF);
  static const Color primaryPressed = Color(0xFF245BDB);
  static const Color primaryHover = Color(0xFF5089FB);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Subtle primary tint for selected/active fills.
  static const Color primaryTintLight = Color(0xFFEBF1FF);
  static const Color primaryTintDark = Color(0xFF22304F);

  /// Link / @mention text.
  static const Color linkLight = Color(0xFF3370FF);
  static const Color linkDark = Color(0xFF6BA0FF);

  // ── Text ──
  static const Color textPrimaryLight = Color(0xFF1F2329);
  static const Color textSecondaryLight = Color(0xFF646A73);
  static const Color textTertiaryLight = Color(0xFF8F959E);
  static const Color textDisabledLight = Color(0xFFBBBFC4);
  static const Color textPrimaryDark = Color(0xFFE6E8EB);
  static const Color textSecondaryDark = Color(0xFF9AA0A6);
  static const Color textTertiaryDark = Color(0xFF6B7178);
  static const Color textDisabledDark = Color(0xFF55585C);

  // ── Surfaces (light) ──
  static const Color scaffoldLight = Color(0xFFFFFFFF);
  static const Color railLight = Color(0xFFE4E8F5); // periwinkle (sampled #E4E8F5)
  static const Color listPanelLight = Color(0xFFFFFFFF);
  static const Color chatBgLight = Color(0xFFFFFFFF);
  static const Color selectedLight = Color(0xFFE5ECF4); // selected conv row
  static const Color pinnedLight = Color(0xFFF2F6FF);
  static const Color hoverLight = Color(0xFFF2F3F5);
  static const Color inputFieldLight = Color(0xFFF2F3F5);
  static const Color cardLight = Color(0xFFFFFFFF);

  // ── Surfaces (dark) ──
  static const Color scaffoldDark = Color(0xFF1A1A1A); // sampled (list/header/tabbar)
  static const Color railDark = Color(0xFF29303C); // blue-charcoal (sampled)
  static const Color listPanelDark = Color(0xFF1C1C1E);
  static const Color desktopChatDark = Color(0xFF151515); // sampled desktop chat
  static const Color chatBgDark = Color(0xFF1A1A1A);
  static const Color selectedDark = Color(0xFF21314A); // blue-tinted (sampled #202938)
  static const Color hoverDark = Color(0xFF26262A);
  static const Color inputAreaDark = Color(0xFF262626); // sampled toolbar #292929
  static const Color inputFieldDark = Color(0xFF2E2E2E);
  static const Color cardDark = Color(0xFF232427);

  // ── Message bubbles ──
  static const Color selfBubbleLight = Color(0xFFD1E3FF); // Feishu sent blue (sampled #D1E3FF)
  static const Color selfBubbleTextLight = Color(0xFF1F2329);
  static const Color otherBubbleLight = Color(0xFFF3F4F6); // gray (sampled)
  static const Color otherBubbleTextLight = Color(0xFF1F2329);
  static const Color selfBubbleDark = Color(0xFF123062); // Feishu sent blue dark (sampled #123062)
  static const Color selfBubbleTextDark = Color(0xFFE6E8EB);
  static const Color otherBubbleDark = Color(0xFF262626); // Feishu received dark (sampled #262626)
  static const Color otherBubbleTextDark = Color(0xFFE6E8EB);
  static const double bubbleRadius = 12.0;

  // ── Semantic ──
  static const Color unreadBadge = Color(0xFFF54A45); // sampled #F04840/#E85850
  static const Color onUnreadBadge = Color(0xFFFFFFFF);
  static const Color online = Color(0xFF2BB344);
  static const Color readRing = Color(0xFF18B880); // sampled teal ring
  static const Color botTagBgLight = Color(0xFFFFF1D6);
  static const Color botTagTextLight = Color(0xFFB7791F);
  static const Color botTagBgDark = Color(0xFF3A3320);
  static const Color botTagTextDark = Color(0xFFE0A857);
  static const Color allTagBgLight = Color(0xFFE1EAFF);
  static const Color allTagTextLight = Color(0xFF3370FF);
  static const Color allTagBgDark = Color(0xFF22304F);
  static const Color allTagTextDark = Color(0xFF6BA0FF);
  static const Color successLight = Color(0xFF2BB344);
  static const Color successDark = Color(0xFF3DCB5E);
  static const Color warningLight = Color(0xFFFF8800);
  static const Color warningDark = Color(0xFFFF9D2E);
  static const Color errorLight = Color(0xFFF54A45);
  static const Color errorDark = Color(0xFFFF6159);

  // ── Lines ──
  static const Color dividerLight = Color(0xFFE5E6EB);
  static const Color hairlineLight = Color(0xFFEFF0F2);
  static const Color inputBorderLight = Color(0xFFDEE0E3);
  static const Color dividerDark = Color(0xFF2E3033);
  static const Color hairlineDark = Color(0xFF262829);
  static const Color inputBorderDark = Color(0xFF3A3D42);

  // ── Radii / metrics ──
  static const double cardRadius = 12.0;
  static const double buttonRadius = 8.0;
  static const double inputRadius = 8.0;
  static const double pillRadius = 6.0;
  static const double titleBarHeight = 48.0;

  /// Avatar-shape rule: person → circle, group/bot → rounded square
  /// (squircle, radius ≈ 28% of size).
  static double avatarRadius(double size, {required bool isGroup}) =>
      isGroup ? size * 0.28 : size / 2;

  /// Pick a light/dark value by [brightness].
  static Color resolve(Brightness brightness, Color light, Color dark) =>
      brightness == Brightness.dark ? dark : light;
}
