import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

/// Centralized SnackBar helper with consistent styling.
///
/// Visual choices:
/// - **Error**: `cs.errorContainer` background, `cs.onErrorContainer`
///   foreground, prefixed with `Icons.error_outline`.
/// - **Success**: `cs.tertiaryContainer` background, `cs.onTertiaryContainer`
///   foreground, prefixed with `Icons.check_circle_outline`. Tertiary is the
///   emerald success token in this app's Material 3 scheme.
/// - **Info**: defers to the global `snackBarTheme` (no explicit background),
///   prefixed with `Icons.info_outline`.
/// - **Neutral** (no flag): defers to the global `snackBarTheme` entirely.
///
/// Public API (`show`, `showError`, `showSuccess`, `showInfo`) is intentionally
/// kept stable — other agents reference these from across the app.
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
    final cs = Theme.of(context).colorScheme;

    Color? backgroundColor;
    Color? foregroundColor;
    IconData? icon;
    if (isError) {
      backgroundColor = cs.errorContainer;
      foregroundColor = cs.onErrorContainer;
      icon = Icons.error_outline;
    } else if (isSuccess) {
      // Tertiary = emerald success token in our M3 scheme. Container pair is
      // designer-friendly and theme-driven (no hardcoded hex).
      backgroundColor = cs.tertiaryContainer;
      foregroundColor = cs.onTertiaryContainer;
      icon = Icons.check_circle_outline;
    } else if (isInfo) {
      // Let the global snackBarTheme own the surface; we only contribute the
      // icon affordance so info messages are still scannable at a glance.
      icon = Icons.info_outline;
    }

    final content = icon == null
        ? Text(message, style: TextStyle(color: foregroundColor))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foregroundColor),
              AppSpacing.horizontalSm,
              Expanded(
                child: Text(message, style: TextStyle(color: foregroundColor)),
              ),
            ],
          );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: content,
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          margin: const EdgeInsets.all(AppSpacing.lg),
          duration: isError ? const Duration(seconds: 4) : duration,
          action: actionLabel != null && onAction != null
              ? SnackBarAction(
                  label: actionLabel,
                  onPressed: onAction,
                  textColor: foregroundColor,
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
