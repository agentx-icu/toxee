import 'package:flutter/material.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import 'call_ui_shell.dart';

// Same on-dark palette as call_ui_components.dart (slate-200 / slate-400);
// duplicated rather than exported because every call file keeps its own copy.
const Color _kCallForeground = Color(0xFFE2E8F0);
const Color _kCallMutedForeground = Color(0xFF94A3B8);

/// Combined rendered height of the card's two text lines under the ambient
/// text scaler (each font size scaled on its own, times its style's line
/// height). [CallFloatingWidget] derives the card height from this so the
/// lines fit at any accessibility text scale, linear or not. The trailing
/// +1 is sub-pixel slack: the card is a fixed-height box, so an estimate
/// that merely equals the laid-out height can still overflow by a fraction.
double callCompactCardTextHeight(BuildContext context) {
  final textTheme = Theme.of(context).textTheme;
  return 1 + CallSceneShell.scaledLineHeight(
        context,
        textTheme.bodyMedium,
        14,
        1.43,
        fontSize: 13,
      ) +
      CallSceneShell.scaledLineHeight(
        context,
        textTheme.bodySmall,
        12,
        1.33,
        fontSize: 11,
      );
}

/// Compact card for floating call window: title, subtitle, optional leading, hang-up action.
class CallCompactCard extends StatelessWidget {
  const CallCompactCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.thumbnail,
    required this.onHangUp,
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? thumbnail;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, AppSpacing.horizontalSm],
          if (thumbnail != null && leading == null) ...[
            thumbnail!,
            AppSpacing.horizontalSm,
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                    color: _kCallForeground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
                    color: _kCallMutedForeground,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Compact end-call button — matches the destructive dock-button feel
          // but sized down for the floating widget footprint. The InkWell IS
          // the 44×44 hit target (accessibility minimum); the 36-px red circle
          // is painted inside it.
          SizedBox(
            width: 44,
            height: 44,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onHangUp,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppThemeConfig.errorColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
