part of '../login_page.dart';

class _LoginActionCard extends StatelessWidget {
  const _LoginActionCard({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _PressableScale(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: isPrimary ? AppThemeConfig.tintedPrimaryCardColor(color) : null,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isPrimary
                ? AppThemeConfig.tintedPrimaryCardBorderColor(color)
                : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                AppSpacing.horizontalMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: isPrimary ? FontWeight.w600 : null,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                AppSpacing.horizontalSm,
                Icon(
                  _trailingChevron(context),
                  size: 20,
                  color: Theme.of(
                    context,
                  ).iconTheme.color?.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
