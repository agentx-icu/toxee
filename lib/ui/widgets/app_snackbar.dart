import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

/// Centralized SnackBar helper with consistent styling.
class AppSnackBar {
  AppSnackBar._();

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isSuccess = false,
    bool isInfo = false,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    Color? backgroundColor;
    Color? foregroundColor;
    if (isError) {
      backgroundColor = AppThemeConfig.errorColor;
      foregroundColor = Colors.white;
    } else if (isSuccess) {
      // Success uses the dedicated success token (emerald) — was previously
      // using the primary brand color, which conflated "this happened" with
      // "this is the brand action".
      backgroundColor = AppThemeConfig.successColor;
      foregroundColor = Colors.white;
    } else if (isInfo) {
      // Brightness-aware solid surface for informational messages. Previous
      // implementation used a low-alpha slate tint, which disappeared on the
      // slate-900 dark scaffold; the dedicated dark token keeps the chip
      // legible against any background.
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final infoBg = isDark
          ? AppThemeConfig.infoSnackbarBackgroundDark
          : AppThemeConfig.infoSnackbarBackgroundLight;
      backgroundColor = infoBg;
      foregroundColor = Theme.of(context).colorScheme.onSurface;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(color: foregroundColor),
          ),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          margin: const EdgeInsets.all(AppSpacing.lg),
          duration: isError ? const Duration(seconds: 4) : duration,
          action: actionLabel != null && onAction != null
              ? SnackBarAction(
                  label: actionLabel,
                  onPressed: onAction,
                  textColor: foregroundColor ?? Colors.white,
                )
              : null,
        ),
      );
  }

  static void showError(BuildContext context, String message) {
    show(context, message, isError: true);
  }

  static void showSuccess(BuildContext context, String message) {
    show(context, message, isSuccess: true);
  }

  static void showInfo(BuildContext context, String message) {
    show(context, message, isInfo: true);
  }
}
