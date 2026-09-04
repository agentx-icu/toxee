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
              AppSpacing.horizontalXs,
              // The switch affordance. It used to be a bare, dimmed chevron
              // (or, after a successful probe, a SECOND paper plane right
              // next to the "test" one), which read as "open details" rather
              // than "connect through this node". A labelled button with a
              // swap glyph states the intent; it is disabled — with the
              // reason as its tooltip — for offline nodes, mirroring the
              // row-tap rule, and turns filled once the probe succeeded so
              // the verified node is the obvious one to pick.
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                child: _SwitchNodeButton(
                  key: ValueKey('bootstrap_node_switch_${node.publicKey}'),
                  enabled: isOnline,
                  verified: isTestedSuccess,
                  // Phone widths: icon-only, the label lives in the tooltip,
                  // so the monospace endpoint title keeps its room.
                  compact: MediaQuery.sizeOf(context).width < 480,
                  label: appL10n.switchNode,
                  disabledReason: appL10n.canOnlySelectOnlineNode,
                  onPressed: onSelect,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Switch to this node" action for one [_BootstrapNodeCard] row.
class _SwitchNodeButton extends StatelessWidget {
  const _SwitchNodeButton({
    super.key,
    required this.enabled,
    required this.verified,
    required this.compact,
    required this.label,
    required this.disabledReason,
    required this.onPressed,
  });

  final bool enabled;

  /// The node answered a probe: render filled instead of tonal.
  final bool verified;
  final bool compact;
  final String label;
  final String disabledReason;
  final VoidCallback onPressed;

  static const IconData _glyph = Icons.swap_horiz;

  @override
  Widget build(BuildContext context) {
    final tooltip = enabled ? label : disabledReason;
    final VoidCallback? onTap = enabled ? onPressed : null;
    if (compact) {
      return verified
          ? IconButton.filled(
              icon: const Icon(_glyph),
              tooltip: tooltip,
              onPressed: onTap,
            )
          : IconButton.filledTonal(
              icon: const Icon(_glyph),
              tooltip: tooltip,
              onPressed: onTap,
            );
    }
    const style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(
        EdgeInsetsDirectional.fromSTEB(12, 0, 16, 0),
      ),
    );
    const icon = Icon(_glyph, size: 18);
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Tooltip(
      message: tooltip,
      child: verified
          ? FilledButton.icon(
              onPressed: onTap,
              style: style,
              icon: icon,
              label: text,
            )
          : FilledButton.tonalIcon(
              onPressed: onTap,
              style: style,
              icon: icon,
              label: text,
            ),
    );
  }
}
