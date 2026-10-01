import 'package:flutter/material.dart';

import 'app_theme_config.dart';
import 'interface_style.dart';

/// Component-level Material theme builders.
///
/// Phase 1 of the multi-agent UI polish pass. These pure functions take a
/// [ColorScheme] (and where it matters, a [Brightness]) and return
/// component-theme objects ready to be plugged into [ThemeData]. They
/// codify the visual rhythm — radius, padding, typography weight, elevation,
/// outline width — that the rest of the app should inherit instead of
/// re-stating per call site.
///
/// Aesthetic constraint: colors come from the [ColorScheme] (which is
/// produced from [AppThemeConfig.primaryColor] / [AppThemeConfig.primaryColorDark]
/// via `colorSchemeSeed`). This file MUST NOT introduce new hex literals.
class AppComponentThemes {
  AppComponentThemes._();

  // ──────────────────────────────────────────────
  //  Top app bar — flat, surface bg, semibold title
  // ──────────────────────────────────────────────

  static AppBarTheme appBarTheme(ColorScheme cs, Brightness brightness) {
    return AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(size: 22, color: cs.onSurface),
      actionsIconTheme: IconThemeData(size: 22, color: cs.onSurface),
    );
  }

  // ──────────────────────────────────────────────
  //  Buttons — 10px radius, 44pt min hit, 15pt semibold
  // ──────────────────────────────────────────────

  static const _buttonPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 12,
  );
  static const _buttonMinSize = Size(0, 44);
  static const _buttonTextStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static RoundedRectangleBorder _buttonShape(
    StyleGeometry geometry,
    Color outline,
  ) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(geometry.controlRadius),
    side: geometry.outlineWidth > 0
        ? BorderSide(color: outline, width: geometry.outlineWidth)
        : BorderSide.none,
  );

  static ElevatedButtonThemeData elevatedButtonTheme(
    ColorScheme cs, {
    StyleGeometry? geometry,
  }) {
    geometry ??= AppThemeConfig.geometry;
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: _buttonShape(geometry, cs.outline),
        padding: _buttonPadding,
        minimumSize: _buttonMinSize,
        textStyle: _buttonTextStyle,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  static FilledButtonThemeData filledButtonTheme(
    ColorScheme cs, {
    StyleGeometry? geometry,
  }) {
    geometry ??= AppThemeConfig.geometry;
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: _buttonShape(geometry, cs.outline),
        padding: _buttonPadding,
        minimumSize: _buttonMinSize,
        textStyle: _buttonTextStyle,
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButtonTheme(
    ColorScheme cs, {
    StyleGeometry? geometry,
  }) {
    geometry ??= AppThemeConfig.geometry;
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: _buttonShape(geometry, cs.outline),
        padding: _buttonPadding,
        minimumSize: _buttonMinSize,
        textStyle: _buttonTextStyle,
        side: BorderSide(width: 1.5, color: cs.outline),
      ),
    );
  }

  static TextButtonThemeData textButtonTheme(
    ColorScheme cs, {
    StyleGeometry? geometry,
  }) {
    geometry ??= AppThemeConfig.geometry;
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(geometry.controlRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: _buttonMinSize,
        textStyle: _buttonTextStyle,
        foregroundColor: cs.primary,
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Surfaces — dialogs, sheets, cards, snackbars
  // ──────────────────────────────────────────────

  static DialogThemeData dialogTheme(
    ColorScheme cs, {
    StyleGeometry? geometry,
  }) {
    geometry ??= AppThemeConfig.geometry;
    return DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(geometry.panelRadius),
      ),
      backgroundColor: cs.surface,
      surfaceTintColor: cs.surfaceTint,
      elevation: 6,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
        letterSpacing: -0.2,
      ),
    );
  }

  static BottomSheetThemeData bottomSheetTheme(
    ColorScheme cs, {
    StyleGeometry? geometry,
  }) {
    geometry ??= AppThemeConfig.geometry;
    return BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(geometry.panelRadius),
        ),
      ),
      backgroundColor: cs.surface,
      modalBackgroundColor: cs.surface,
      surfaceTintColor: cs.surfaceTint,
      showDragHandle: true,
      dragHandleColor: cs.onSurfaceVariant,
      clipBehavior: Clip.antiAlias,
    );
  }

  static CardThemeData cardTheme(ColorScheme cs, {StyleGeometry? geometry}) {
    geometry ??= AppThemeConfig.geometry;
    return CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(geometry.panelRadius),
        side: geometry.outlineWidth > 0
            ? BorderSide(color: cs.outline, width: geometry.outlineWidth)
            : BorderSide.none,
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
    );
  }

  static SnackBarThemeData snackBarTheme(
    ColorScheme cs, {
    StyleGeometry? geometry,
  }) {
    geometry ??= AppThemeConfig.geometry;
    return SnackBarThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(geometry.controlRadius),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: TextStyle(
        color: cs.onInverseSurface,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      actionTextColor: cs.inversePrimary,
    );
  }

  // ──────────────────────────────────────────────
  //  Inputs — filled, no border by default, 2px focus ring
  // ──────────────────────────────────────────────

  static InputDecorationTheme inputDecorationTheme(
    ColorScheme cs,
    Brightness brightness, {
    StyleGeometry? geometry,
  }) {
    geometry ??= AppThemeConfig.geometry;
    final radius = BorderRadius.circular(geometry.controlRadius);
    OutlineInputBorder unset() =>
        OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none);
    OutlineInputBorder ring(Color color) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(width: 2, color: color),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: unset(),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: cs.outline,
          width: geometry.outlineWidth > 0 ? geometry.outlineWidth : 1,
        ),
      ),
      disabledBorder: unset(),
      focusedBorder: ring(cs.primary),
      errorBorder: ring(cs.error),
      focusedErrorBorder: ring(cs.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  // ──────────────────────────────────────────────
  //  Chips — stadium, surface-variant bg, dark gets outline
  // ──────────────────────────────────────────────

  static ChipThemeData chipTheme(ColorScheme cs, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ChipThemeData(
      shape: StadiumBorder(
        side: isDark
            ? BorderSide(width: 1, color: cs.outlineVariant)
            : BorderSide.none,
      ),
      backgroundColor: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: cs.onSurface,
      ),
      side: isDark
          ? BorderSide(width: 1, color: cs.outlineVariant)
          : BorderSide.none,
    );
  }

  // ──────────────────────────────────────────────
  //  Dividers, tab bar, selection controls
  // ──────────────────────────────────────────────

  static DividerThemeData dividerTheme(ColorScheme cs) {
    return DividerThemeData(space: 0, thickness: 1, color: cs.outlineVariant);
  }

  static TabBarThemeData tabBarTheme(ColorScheme cs) {
    return TabBarThemeData(
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(width: 2, color: cs.primary),
      ),
      dividerColor: cs.outlineVariant,
    );
  }

  static SwitchThemeData switchTheme(ColorScheme cs) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.onPrimary;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.primary;
        return null;
      }),
    );
  }

  static CheckboxThemeData checkboxTheme(ColorScheme cs) {
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.primary;
        return null;
      }),
      checkColor: WidgetStateProperty.all(cs.onPrimary),
    );
  }

  static RadioThemeData radioTheme(ColorScheme cs) {
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.primary;
        return cs.onSurfaceVariant;
      }),
    );
  }

  // ──────────────────────────────────────────────
  //  Tooltips, list tiles
  // ──────────────────────────────────────────────

  static TooltipThemeData tooltipTheme(ColorScheme cs) {
    return TooltipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.inverseSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      textStyle: TextStyle(
        color: cs.onInverseSurface,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  static ListTileThemeData listTileTheme(ColorScheme cs) {
    return const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 12,
      dense: false,
    );
  }
}
