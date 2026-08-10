import 'package:flutter/material.dart';

import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

/// Centralized SnackBar helper with consistent styling.
///
/// Visual choices:
/// - **Error**: `cs.errorContainer` surface, `cs.onErrorContainer` foreground,
///   prefixed with `Icons.error_outline`, 4s instead of the 3s default.
/// - **Success**: `cs.tertiaryContainer` surface, `cs.onTertiaryContainer`
///   foreground, prefixed with `Icons.check_circle_outline`. Tertiary is the
///   emerald success token in this app's Material 3 scheme.
/// - **Info**: defers to the global `snackBarTheme` (no explicit background),
///   prefixed with `Icons.info_outline`.
/// - **Neutral** (no flag): defers to the global `snackBarTheme` entirely.
///
/// ## Two entry points, one style
///
/// [show] takes a [BuildContext] and is what widgets use. [showOn] takes a
/// [ScaffoldMessengerState] directly and is what non-widget code — SDK
/// callbacks holding only a `GlobalKey<ScaffoldMessengerState>` — must use.
/// [show] is a thin wrapper over [showOn]; there is exactly one place where
/// the styling is decided ([_buildSnackBar]).
///
/// A messenger-based entry point is not a convenience: `show` resolves its
/// target with `ScaffoldMessenger.of(context)`, an ANCESTOR lookup for
/// `_ScaffoldMessengerScope`. A `ScaffoldMessenger` publishes that scope to
/// its DESCENDANTS, so `scaffoldMessengerKey.currentState!.context` can never
/// resolve its own messenger — callers holding only the key have to be able to
/// hand us the state.
///
/// ## Why the coloured variants use a transparent shell
///
/// `SnackBar.backgroundColor` is evaluated EAGERLY, at the call site, long
/// before the snackbar is mounted under the Scaffold that presents it. For the
/// two variants that need a colour from the app's `ColorScheme`, resolving it
/// eagerly means resolving it against whatever context the caller happens to
/// hold — and for the messenger entry point that is the messenger's own
/// context, which sits ABOVE `MaterialApp`'s `AnimatedTheme` (Flutter-internal
/// ordering: `MaterialApp` builds `ScaffoldMessenger` > `AnimatedTheme` >
/// `builder` > `Navigator`; treat this as the reason, not as gospel). Resolving
/// there would silently yield `ThemeData`'s default LIGHT scheme, so a dark-mode
/// error toast would come out with light-mode colours.
///
/// So error/success snackbars are a transparent, elevation-0, zero-padding
/// SnackBar shell whose content is a [Builder]; the coloured surface — including
/// the floating snackbar's default elevation and the padding Flutter would have
/// applied itself — is drawn by an inner [Material] built at the DISPLAY site,
/// which is necessarily below the app's `Theme` and `Localizations`. That is
/// correct under either widget ordering, which is why it is preferred over
/// "resolve from the messenger context".
///
/// Info/neutral snackbars deliberately keep the plain structure: they contribute
/// no colour of their own, so `SnackBar` resolves `snackBarTheme` itself, at the
/// display site, and is already correct from any messenger. Wrapping them in a
/// transparent shell would mean re-implementing `snackBarTheme` by hand.
///
/// Public API (`show`, `showError`, `showSuccess`, `showInfo`) is intentionally
/// kept stable — other agents reference these from across the app.
class AppSnackBar {
  AppSnackBar._();

  /// Errors get an extra second: they are the ones a user actually has to read.
  static const Duration _errorDuration = Duration(seconds: 4);

  /// Vertical padding Flutter's own `SnackBar` puts around single-line content
  /// (`_singleLineVerticalPadding` in `snack_bar.dart`). The coloured variants
  /// pass `padding: EdgeInsets.zero` — which suppresses BOTH the outer and the
  /// inner default padding — so they have to draw it themselves.
  static const double _contentVerticalPadding = 14;

  /// Elevation a floating `SnackBar` gets by default when `snackBarTheme`
  /// does not override it. Used for the inner surface so the transparent shell
  /// is visually indistinguishable from a normal coloured SnackBar.
  static const double _floatingElevation = 6;

  static const EdgeInsets _margin = EdgeInsets.all(AppSpacing.lg);

  /// Key on the coloured surface of an error/success toast.
  ///
  /// Public (not `@visibleForTesting`) because production code re-exports it —
  /// see `SendFailureNotifier.toastSurfaceKey`. Tests use it to assert that the
  /// colours were resolved from the app's theme at the display site rather than
  /// from a themeless context.
  static const Key toastSurfaceKey = ValueKey('app-snackbar-surface');

  /// Show a snackbar on the messenger that owns [context].
  ///
  /// Thin wrapper over [showOn]; every styling decision lives there.
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
    showOn(
      ScaffoldMessenger.of(context),
      message,
      isError: isError,
      isSuccess: isSuccess,
      isInfo: isInfo,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Show a snackbar on an explicit [messenger].
  ///
  /// For callers that hold a `GlobalKey<ScaffoldMessengerState>` instead of a
  /// [BuildContext] — SDK callbacks and anything else outside the widget tree.
  static void showOn(
    ScaffoldMessengerState messenger,
    String message, {
    bool isError = false,
    bool isSuccess = false,
    bool isInfo = false,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _present(
      messenger,
      (_) => message,
      isError: isError,
      isSuccess: isSuccess,
      isInfo: isInfo,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void showError(BuildContext context, String message) {
    show(context, message, isError: true);
  }

  /// [showError] for callers holding a [ScaffoldMessengerState].
  static void showErrorOn(ScaffoldMessengerState messenger, String message) {
    showOn(messenger, message, isError: true);
  }

  /// [showErrorOn] for copy that itself depends on the display context.
  ///
  /// [messageBuilder] runs where the toast is mounted, so
  /// `AppLocalizations.of(context)` (and anything else inherited) resolves
  /// against the app's tree rather than against whatever context the caller
  /// happens to hold. Callers that already have a plain string want
  /// [showErrorOn].
  static void showErrorOnBuilder(
    ScaffoldMessengerState messenger,
    String Function(BuildContext context) messageBuilder,
  ) {
    _present(messenger, messageBuilder, isError: true);
  }

  static void showSuccess(BuildContext context, String message) {
    show(context, message, isSuccess: true);
  }

  static void showInfo(BuildContext context, String message) {
    show(context, message, isInfo: true);
  }

  static void _present(
    ScaffoldMessengerState messenger,
    String Function(BuildContext context) messageBuilder, {
    bool isError = false,
    bool isSuccess = false,
    bool isInfo = false,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // `hideCurrentSnackBar` first: the messenger QUEUES snackbars, so without
    // it a second message would wait out the first one's duration and the user
    // would keep reading a stale toast.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        _buildSnackBar(
          messageBuilder,
          isError: isError,
          isSuccess: isSuccess,
          isInfo: isInfo,
          duration: duration,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      );
  }

  static SnackBar _buildSnackBar(
    String Function(BuildContext context) messageBuilder, {
    required bool isError,
    required bool isSuccess,
    required bool isInfo,
    required Duration duration,
    required String? actionLabel,
    required VoidCallback? onAction,
  }) {
    final effectiveDuration = isError ? _errorDuration : duration;
    // Copied into finals so they promote to non-nullable inside the closures.
    final label = actionLabel;
    final onPressed = onAction;

    if (isError || isSuccess) {
      return SnackBar(
        behavior: SnackBarBehavior.floating,
        // See the class doc: the shell is a transparent carrier, the inner
        // Material paints the surface at the display site.
        backgroundColor: Colors.transparent,
        elevation: 0,
        // `SnackBar` defaults to `Clip.hardEdge`, which would clip the child to
        // the SHELL's shape — and the shell is exactly the size of the inner
        // surface, so the inner Material's elevation shadow would be clipped
        // away entirely. Without this the coloured toast renders flat.
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        margin: _margin,
        duration: effectiveDuration,
        content: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final cs = theme.colorScheme;
            final background =
                isError ? cs.errorContainer : cs.tertiaryContainer;
            final foreground =
                isError ? cs.onErrorContainer : cs.onTertiaryContainer;
            final icon =
                isError ? Icons.error_outline : Icons.check_circle_outline;
            return Material(
              key: toastSurfaceKey,
              color: background,
              elevation: theme.snackBarTheme.elevation ?? _floatingElevation,
              borderRadius: BorderRadius.circular(AppRadii.card),
              // `Material` would otherwise install `textTheme.bodyMedium` as the
              // default text style, replacing the `contentTextStyle` a plain
              // SnackBar inherits. Re-state it so weight/size are unchanged
              // relative to the non-transparent structure.
              textStyle: _contentTextStyle(theme),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: _contentVerticalPadding,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: foreground),
                    AppSpacing.horizontalSm,
                    Expanded(
                      child: Text(
                        messageBuilder(context),
                        style: TextStyle(color: foreground),
                      ),
                    ),
                    // The action lives INSIDE the coloured surface here: the
                    // shell has zero padding and a transparent background, so
                    // SnackBar's own action slot would render it off the
                    // coloured area entirely.
                    if (label != null && onPressed != null) ...[
                      AppSpacing.horizontalSm,
                      SnackBarAction(
                        label: label,
                        onPressed: onPressed,
                        textColor: foreground,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    // Info / neutral: nothing here reads the theme, so the eager-evaluation
    // problem does not apply and `snackBarTheme` keeps owning the surface.
    final icon = isInfo ? Icons.info_outline : null;
    return SnackBar(
      content: Builder(
        builder: (context) {
          final message = messageBuilder(context);
          if (icon == null) {
            return Text(message);
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              AppSpacing.horizontalSm,
              Expanded(child: Text(message)),
            ],
          );
        },
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      margin: _margin,
      duration: effectiveDuration,
      action: label != null && onPressed != null
          ? SnackBarAction(label: label, onPressed: onPressed)
          : null,
    );
  }

  /// The text style a plain `SnackBar` would have installed for its content.
  ///
  /// Mirrors `SnackBar`'s own resolution: `snackBarTheme.contentTextStyle`
  /// falling back to the M3 default (`bodyMedium` on `onInverseSurface`).
  static TextStyle? _contentTextStyle(ThemeData theme) {
    return theme.snackBarTheme.contentTextStyle ??
        theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onInverseSurface);
  }
}
