import 'package:flutter/material.dart';

import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

/// Hoverable row used to wrap title/description + trailing widget pairs in
/// settings sections. Shows a subtle primary-tinted overlay on pointer hover,
/// honours `MediaQuery.disableAnimationsOf` for reduced-motion users, and
/// applies the canonical inset.
///
/// Lives in `lib/ui/settings/` so all settings-section files share one
/// implementation instead of carrying their own copy.
class HoverableSettingsRow extends StatefulWidget {
  const HoverableSettingsRow({super.key, required this.child});
  final Widget child;

  @override
  State<HoverableSettingsRow> createState() => _HoverableSettingsRowState();
}

class _HoverableSettingsRowState extends State<HoverableSettingsRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hoverColor = scheme.primary.withValues(alpha: 0.08);
    final disableAnims = MediaQuery.disableAnimationsOf(context);
    // One screen-reader node per row (checklist I5): a switch is read with
    // its title and description ("Auto Login, …, switch, on") instead of as
    // an unnamed switch. Every row holds a single control.
    return MergeSemantics(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: disableAnims ? Duration.zero : AppDurations.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
