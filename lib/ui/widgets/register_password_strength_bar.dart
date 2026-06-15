import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/design_tokens.dart';

/// The weak→strong password-strength bar shown under the password field on the
/// register page. Extracted from `register_page.dart` so that page stays under
/// the 500-LOC complexity cap. Pure presentation: it derives the strength from
/// [password] and renders four segments.
///
/// Test keys (read by
/// `test/ui/register/register_password_strength_real_ui_test.dart`):
///   - `register_password_strength_bar` on the container
///   - `register_strength_segment_<i>` on each segment (filled iff i < strength)
///   - `register_password_strength_label` on the caption Text whose value is
///     the localized Weak/Fair/Good/Strong word (empty string for strength 0).
///     The colored segments alone are not text-matchable by widget-driving
///     automation (the fill state is a `BoxDecoration` color); this caption is a
///     real-UI-observable + accessible signal of the same weak→strong ramp.
class RegisterPasswordStrengthBar extends StatelessWidget {
  const RegisterPasswordStrengthBar({super.key, required this.password});

  final String password;

  /// Localized caption for a given [strength] (0..4): "" for empty, then
  /// Weak / Fair / Good / Strong. Static + visible so a unit test can assert the
  /// mapping directly. Returns the empty string for strength 0 so an empty
  /// password shows no caption (the bar's four empty segments already convey
  /// "nothing entered").
  static String labelFor(BuildContext context, int strength) {
    final l10n = AppLocalizations.of(context)!;
    switch (strength) {
      case 1:
        return l10n.passwordStrengthWeak;
      case 2:
        return l10n.passwordStrengthFair;
      case 3:
        return l10n.passwordStrengthGood;
      case 4:
        return l10n.passwordStrengthStrong;
      default:
        return '';
    }
  }

  /// 0 (empty) … 4 (strong). Public + visible so a unit test can assert the
  /// ramp directly without rebuilding the widget.
  static int strengthOf(String password) {
    if (password.isEmpty) return 0;
    if (password.length < 6) return 1;
    int score = 2;
    if (password.length >= 8 &&
        (RegExp(r'[A-Z]').hasMatch(password) ||
            RegExp(r'\d').hasMatch(password))) {
      score = 3;
    }
    if (password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'\d').hasMatch(password) &&
        RegExp(r'[!@#$%^&*]').hasMatch(password)) {
      score = 4;
    }
    return score;
  }

  @override
  Widget build(BuildContext context) {
    final strength = strengthOf(password);
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Decorative semantic ramp: weak → strong, sampled from the reference
    // design's status palette. Red (error) → amber (warning) → green
    // (success) for the first three rungs, with the brand blue capping
    // "Strong" so the strongest state matches the app's primary CTA accent.
    final colors = [
      DesignTokens.errorLight,
      DesignTokens.warningLight,
      DesignTokens.successLight,
      cs.primary,
    ];
    final label = labelFor(context, strength);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
      // Stable test key for the password-strength bar (real-UI gate reads its
      // per-segment fill state to assert weak→strong ramping).
      key: const Key('register_password_strength_bar'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: AnimatedContainer(
                  // Per-segment stable key: `register_strength_segment_<i>`. A
                  // segment is "filled" when its BoxDecoration.color == colors[i]
                  // (i < strength) and "empty" (outline @ alpha 0.2) otherwise.
                  // Tests count filled segments to verify the 0→4 strength ramp.
                  key: Key('register_strength_segment_$i'),
                  duration: reduceMotion ? Duration.zero : AppDurations.medium,
                  curve: AppCurves.standard,
                  height: 4,
                  margin: EdgeInsets.only(right: i < 3 ? AppSpacing.xs : 0),
                  decoration: BoxDecoration(
                    color: i < strength
                        ? colors[i]
                        : cs.outline.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          // Localized weak→strong caption. Empty string for strength 0 keeps the
          // caption invisible until the user types. Keyed so widget-driving
          // automation can read the strength word (the colored segments above are
          // not text-matchable); also an accessibility win (a screen reader can
          // announce the password strength, which the bare colored bar can't).
          // `label.isNotEmpty` <=> strength in 1..4, so `strength - 1` is a
          // valid 0..3 index into `colors`; clamp defensively all the same.
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                label,
                key: const Key('register_password_strength_label'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors[(strength - 1).clamp(0, 3).toInt()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
