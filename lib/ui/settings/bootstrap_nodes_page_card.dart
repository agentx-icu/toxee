part of 'bootstrap_nodes_page.dart';

/// One row of the bootstrap-node list.
///
/// Split out of `bootstrap_nodes_page.dart` along a real seam: the page owns
/// LOADING and PROBING (network, verdicts, the `_nodeTest*` state maps), while
/// this owns nothing but the rendering of one node plus two callbacks. It was
/// a ~120-line closure nested four levels deep inside the page's `build`, where
/// the three-way test-result tone (success / inconclusive / failed) was hard to
/// read against the surrounding list plumbing.
class _BootstrapNodeCard extends StatelessWidget {
  const _BootstrapNodeCard({
    required this.node,
    required this.isTesting,
    required this.testResult,
    required this.isTestedSuccess,
    required this.isTestConclusive,
    required this.colorTheme,
    required this.onTest,
    required this.onSelect,
  });

  final BootstrapNode node;
  final bool isTesting;

  /// The result label to show, or null when this node has not been probed.
  final String? testResult;

  /// Probed AND the node answered.
  final bool isTestedSuccess;

  /// Whether the probe produced a verdict about the NODE. False for a UDP-less
  /// device or a probe that could not start — see
  /// `_BootstrapNodesPageState._nodeTestConclusive`.
  final bool isTestConclusive;

  final dynamic colorTheme;
  final VoidCallback onTest;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appL10n = AppLocalizations.of(context)!;
    final endpoint = node.formattedEndpoint ?? '';
    final isOnline = node.status == 'ONLINE';

    // Inconclusive (UDP-less device / probe unavailable) must NOT render as the
    // red error tone: nothing about this node failed, we simply could not look.
    final isInconclusive = testResult != null && !isTestConclusive;
    final resultIcon = isTestedSuccess
        ? Icons.send_outlined
        : (isInconclusive ? Icons.info_outline : Icons.error_outline);
    final resultColor = isTestedSuccess
        ? AppThemeConfig.successColor
        : (isInconclusive
              ? theme.colorScheme.secondary
              : theme.colorScheme.error);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
      ),
      child: InkWell(
        onTap: isOnline ? onSelect : null,
        child: ListTile(
          leading: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline
                  ? AppThemeConfig.successColor
                  : theme.colorScheme.error,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            endpoint,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorTheme.primaryTextColor,
              fontFamily: 'monospace',
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (node.location != null)
                Text(node.location!, style: theme.textTheme.bodySmall),
              if (node.maintainer != null)
                Text(
                  appL10n.maintainer(node.maintainer!),
                  style: theme.textTheme.bodySmall,
                ),
              if (node.lastPing != null)
                Text(
                  appL10n.lastPing(node.lastPing.toString()),
                  style: theme.textTheme.bodySmall,
                ),
              if (testResult != null) ...[
                AppSpacing.verticalXs,
                Row(
                  children: [
                    Icon(resultIcon, size: 14, color: resultColor),
                    AppSpacing.horizontalXs,
                    Text(
                      testResult!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: resultColor,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: isTesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                onPressed: isTesting ? null : onTest,
                tooltip: appL10n.testNode,
              ),
              if (isOnline)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(
                    isTestedSuccess ? Icons.send_outlined : Icons.chevron_right,
                    size: 20,
                    color: isTestedSuccess
                        ? AppThemeConfig.successColor
                        : theme.iconTheme.color?.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
