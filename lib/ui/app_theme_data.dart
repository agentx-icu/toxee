/// The app's Material [ThemeData] builders.
///
/// Split out of `lib/main.dart` (which sat exactly at its
/// `tool/.complexity_baseline.txt` pin) along a real seam: nothing here knows
/// about startup, routing or the widget tree — it is the pure
/// design-tokens -> ThemeData mapping, and `main.dart` is now small enough to
/// leave the complexity baseline entirely.
library;

import 'package:flutter/material.dart';

import '../util/app_component_themes.dart';
import '../util/design_tokens.dart';

// ──────────────────────────────────────────────
//  Theme builders
// ──────────────────────────────────────────────
//
// Both light and dark trees share the same text hierarchy + component-level
// theming surface; the only differences are brightness, color seed, and
// scaffold background. Component themes are sourced from [AppComponentThemes]
// so each surface (AppBar, Button, Card, Dialog, Sheet, Input, etc.) gets
// the same radius/padding/elevation rhythm in both modes.

ThemeData buildLightTheme() {
  // Explicit color scheme (not seed-generated) so toxee's Material pages get
  // the exact sampled surfaces/text/dividers instead of tonal approximations.
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: DesignTokens.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: DesignTokens.primary,
        onPrimary: DesignTokens.onPrimary,
        secondary: DesignTokens.primary,
        onSecondary: Colors.white,
        surface: DesignTokens.scaffoldLight,
        onSurface: DesignTokens.textPrimaryLight,
        onSurfaceVariant: DesignTokens.textSecondaryLight,
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFFAFBFC),
        surfaceContainer: const Color(0xFFF7F8FA),
        surfaceContainerHigh: DesignTokens.hoverLight,
        surfaceContainerHighest: DesignTokens.inputFieldLight,
        outline: DesignTokens.inputBorderLight,
        outlineVariant: DesignTokens.dividerLight,
        error: DesignTokens.errorLight,
        onError: Colors.white,
        inverseSurface: const Color(0xFF2E3033),
        onInverseSurface: Colors.white,
        inversePrimary: DesignTokens.primaryHover,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: DesignTokens.scaffoldLight,
  );
  return _applyAppTheming(base);
}

ThemeData buildDarkTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: DesignTokens.primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: DesignTokens.primary,
        onPrimary: DesignTokens.onPrimary,
        secondary: DesignTokens.primary,
        onSecondary: Colors.white,
        surface: DesignTokens.scaffoldDark,
        onSurface: DesignTokens.textPrimaryDark,
        onSurfaceVariant: DesignTokens.textSecondaryDark,
        surfaceContainerLowest: const Color(0xFF151515),
        surfaceContainerLow: DesignTokens.listPanelDark,
        surfaceContainer: const Color(0xFF202022),
        surfaceContainerHigh: DesignTokens.cardDark,
        surfaceContainerHighest: DesignTokens.inputFieldDark,
        outline: DesignTokens.inputBorderDark,
        outlineVariant: DesignTokens.dividerDark,
        error: DesignTokens.errorDark,
        onError: Colors.white,
        inverseSurface: const Color(0xFFE6E8EB),
        onInverseSurface: DesignTokens.textPrimaryLight,
        inversePrimary: DesignTokens.primary,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: DesignTokens.scaffoldDark,
  );
  return _applyAppTheming(base);
}

/// Apply the toxee text hierarchy + component themes on top of a brightness-
/// seeded [ThemeData]. Component themes are merged with the prior manual
/// overrides via `copyWith` so any explicit value on the existing AppBar /
/// Card / Button / Input themes still wins. (`scrolledUnderElevation: 1` from
/// the AppBar component theme is preserved because the prior config didn't
/// set it; `elevation: 1` from the prior Card config is preserved because the
/// `.copyWith(elevation: 1)` chain applies after the new base.)
ThemeData _applyAppTheming(ThemeData base) {
  final cs = base.colorScheme;
  final brightness = base.brightness;
  return base.copyWith(
    // Inter-style hierarchy: titles use weight + tight tracking for
    // presence, body sits at 15-16pt for comfortable reading, small labels
    // gain positive tracking for legibility. We `merge` onto the base text
    // theme so M3's brightness-aware colors (onSurface for titles/body,
    // onSurfaceVariant for labels) are preserved while we override only
    // font size/weight/tracking/leading.
    textTheme: base.textTheme.merge(
      const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.35,
        ),
        titleSmall: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.4,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5),
        bodyMedium: TextStyle(fontSize: 15, height: 1.5),
        bodySmall: TextStyle(fontSize: 13, letterSpacing: 0.1, height: 1.45),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
        labelSmall: TextStyle(
          // 12pt floor for Material 3 (bottom-nav labels use
          // labelSmall — anything below 12 fails the legibility
          // bar on small phone screens).
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
        ),
      ),
    ),
    // Component themes: the base values come from [AppComponentThemes];
    // any prior manual overrides are reapplied via `copyWith` so existing
    // behavior (e.g. Card elevation: 1, AppBar centerTitle: false) wins.
    appBarTheme: AppComponentThemes.appBarTheme(
      cs,
      brightness,
    ).copyWith(centerTitle: false),
    elevatedButtonTheme: AppComponentThemes.elevatedButtonTheme(cs),
    filledButtonTheme: AppComponentThemes.filledButtonTheme(cs),
    outlinedButtonTheme: AppComponentThemes.outlinedButtonTheme(cs),
    textButtonTheme: AppComponentThemes.textButtonTheme(cs),
    dialogTheme: AppComponentThemes.dialogTheme(cs),
    bottomSheetTheme: AppComponentThemes.bottomSheetTheme(cs),
    inputDecorationTheme: AppComponentThemes.inputDecorationTheme(
      cs,
      brightness,
    ),
    // Flat cards (elevation 0) — the reference design separates surfaces with
    // background tone + hairline, not shadow.
    cardTheme: AppComponentThemes.cardTheme(cs),
    chipTheme: AppComponentThemes.chipTheme(cs, brightness),
    snackBarTheme: AppComponentThemes.snackBarTheme(cs),
    dividerTheme: AppComponentThemes.dividerTheme(cs),
    tabBarTheme: AppComponentThemes.tabBarTheme(cs),
    switchTheme: AppComponentThemes.switchTheme(cs),
    checkboxTheme: AppComponentThemes.checkboxTheme(cs),
    radioTheme: AppComponentThemes.radioTheme(cs),
    tooltipTheme: AppComponentThemes.tooltipTheme(cs),
    listTileTheme: AppComponentThemes.listTileTheme(cs),
    // Thin scrollbars across the app. We deliberately leave thumbVisibility
    // unset (rather than always-on) because some UIKit-owned Scrollables
    // don't have a tightly-bound ScrollController, and forcing the
    // Scrollbar to paint there floods the log with "ScrollController has
    // no ScrollPosition attached" assertions on every frame.
    scrollbarTheme: ScrollbarThemeData(
      trackVisibility: WidgetStateProperty.all(false),
      thickness: WidgetStateProperty.all(6.0),
      radius: const Radius.circular(3.0),
    ),
  );
}