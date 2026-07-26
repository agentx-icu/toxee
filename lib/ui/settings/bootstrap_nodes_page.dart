import 'dart:async';
import 'package:flutter/material.dart';

import '../widgets/safe_dialog_pop.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/bootstrap_nodes.dart';
import '../../util/platform_utils.dart';
import '../../util/prefs.dart';
import '../../util/responsive_layout.dart';
import '../../i18n/app_localizations.dart';
import '../../ui/widgets/empty_state_widget.dart';
import '../../ui/widgets/loading_shimmer.dart';
import '../../ui/widgets/stagger_list_item.dart';

class BootstrapNodesPage extends StatefulWidget {
  const BootstrapNodesPage({
    super.key,
    this.service,
    this.onNodeSelected,
    this.fetchNodes,
  });
  final FfiChatService? service;
  final VoidCallback? onNodeSelected;
  final Future<List<BootstrapNode>> Function()? fetchNodes;

  @override
  State<BootstrapNodesPage> createState() => _BootstrapNodesPageState();
}

class _BootstrapNodesPageState extends State<BootstrapNodesPage> {
  List<BootstrapNode> _nodes = [];
  bool _loading = true;
  String? _error;
  final Map<String, bool> _testingNodes = {};
  final Map<String, String?> _testResults = {};
  final Map<String, bool> _nodeTestSuccess = {}; // Track test success status

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  Future<void> _loadNodes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nodes =
          await (widget.fetchNodes ?? BootstrapNodesService.fetchNodes)();
      if (!mounted) return;
      setState(() {
        _nodes = nodes.where((node) => node.preferredHost != null).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _testNode(BootstrapNode node) async {
    final host = node.preferredHost;
    if (host == null) return;
    // Capture all l10n strings before any async gap so the catch block
    // doesn't need to re-fetch from a potentially-disposed context.
    final appL10n = AppLocalizations.of(context)!;
    final successLabel = appL10n.nodeTestSuccess;
    final failedLabel = appL10n.nodeTestFailed;
    final unavailableLabel = appL10n.nodeTestUnavailableBeforeLogin;
    setState(() {
      _testingNodes[node.publicKey] = true;
      _testResults[node.publicKey] = null;
      _nodeTestSuccess[node.publicKey] = false;
    });
    try {
      bool success;
      if (widget.service != null) {
        success = await widget.service!.tryBootstrapNode(
          host,
          node.port,
          node.publicKey,
        );
      } else {
        // Pre-login: no FFI session yet. TCP probe to a UDP Tox port lies,
        // so surface "test unavailable" rather than a misleading green check.
        setState(() {
          _testResults[node.publicKey] = unavailableLabel;
          _nodeTestSuccess[node.publicKey] = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _testResults[node.publicKey] = success ? successLabel : failedLabel;
        _nodeTestSuccess[node.publicKey] = success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResults[node.publicKey] = appL10n.error(e.toString());
        _nodeTestSuccess[node.publicKey] = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _testingNodes[node.publicKey] = false;
        });
      }
    }
  }

  Future<void> _selectNode(BootstrapNode node) async {
    final host = node.preferredHost;
    final endpoint = node.formattedEndpoint;
    if (host == null || endpoint == null) return;
    // Only allow selecting nodes that are online
    final isOnline = node.status == 'ONLINE';
    final isTestedSuccess = _nodeTestSuccess[node.publicKey] ?? false;
    final hasBeenTested = _testResults[node.publicKey] != null;

    final appL10n = AppLocalizations.of(context)!;

    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appL10n.canOnlySelectOnlineNode),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Show warning if node hasn't been tested or test failed, but allow selection
    String confirmMessage = appL10n.switchNodeConfirm(endpoint);
    if (!hasBeenTested) {
      confirmMessage =
          '${appL10n.switchNodeConfirm(endpoint)}\n\n${appL10n.nodeNotTestedWarning}';
    } else if (!isTestedSuccess) {
      confirmMessage =
          '${appL10n.switchNodeConfirm(endpoint)}\n\n${appL10n.nodeTestFailedWarning}';
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appL10n.switchNode),
        content: Text(confirmMessage),
        actions: [
          TextButton(
            onPressed: () => popDialogIfCurrent(context, false),
            child: Text(appL10n.cancel),
          ),
          TextButton(
            onPressed: () => popDialogIfCurrent(context, true),
            child: Text(appL10n.ok),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Capture context-dependent values once before any further async gap so
    // the snackbar / navigator paths below don't read context after disposal.
    final errorColor = Theme.of(context).colorScheme.error;

    if (widget.service != null) {
      // Capture a NavigatorState before the async gap. `Navigator.of(context)`
      // after an `await` can throw if the widget was popped from underneath
      // (back-gesture during the bootstrap call), which would otherwise leave
      // the modal-barrier progress dialog orphaned.
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      final messenger = ScaffoldMessenger.of(context);
      bool dialogShown = false;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        ),
      );
      dialogShown = true;

      void dismissDialog() {
        if (dialogShown) {
          dialogShown = false;
          if (rootNavigator.canPop()) rootNavigator.pop();
        }
      }

      try {
        final success = await widget.service!.addBootstrapNode(
          host,
          node.port,
          node.publicKey,
        );

        if (!success) {
          dismissDialog();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                appL10n.nodeSwitchFailed('Failed to add bootstrap node'),
              ),
              backgroundColor: errorColor,
            ),
          );
          return;
        }

        await Prefs.setCurrentBootstrapNode(host, node.port, node.publicKey);
        dismissDialog();

        messenger.showSnackBar(SnackBar(content: Text(appL10n.nodeSwitched)));
        widget.onNodeSelected?.call();
        await Future.delayed(const Duration(milliseconds: 100));
        if (rootNavigator.canPop()) rootNavigator.pop();
      } catch (e) {
        dismissDialog();
        messenger.showSnackBar(
          SnackBar(
            content: Text(appL10n.nodeSwitchFailed(e.toString())),
            backgroundColor: errorColor,
          ),
        );
      }
    } else {
      // Prefs-only save when service is not available (login settings)
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      try {
        await Prefs.setCurrentBootstrapNode(host, node.port, node.publicKey);
        messenger.showSnackBar(SnackBar(content: Text(appL10n.nodeSwitched)));
        widget.onNodeSelected?.call();
        await Future.delayed(const Duration(milliseconds: 100));
        if (navigator.canPop()) navigator.pop();
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(appL10n.nodeSwitchFailed(e.toString())),
            backgroundColor: errorColor,
          ),
        );
      }
    }
  }

  /// Returns [child] verbatim on desktop (no pull-to-refresh affordance there;
  /// the AppBar already exposes a refresh IconButton); wraps in
  /// [RefreshIndicator] otherwise.
  Widget _wrapWithRefresh({
    required bool isDesktop,
    required Color color,
    required Widget child,
  }) {
    if (isDesktop) return child;
    return RefreshIndicator(color: color, onRefresh: _loadNodes, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final appL10n = AppLocalizations.of(context)!;
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Scaffold(
        appBar: AppBar(
          title: Text(appL10n.bootstrapNodesTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadNodes,
              tooltip: appL10n.refresh,
            ),
            SizedBox(
              width: ResponsiveLayout.responsiveHorizontalPadding(context),
            ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const LoadingShimmer(itemCount: 5, itemHeight: 56)
              : _error != null
              ? EmptyStateWidget(
                  icon: Icons.cloud_off,
                  // TODO(l10n): key=failedToLoadNodes
                  title: 'Failed to load nodes',
                  subtitle: _error,
                  action: ElevatedButton(
                    onPressed: _loadNodes,
                    child: Text(appL10n.retry),
                  ),
                )
              : _nodes.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.dns_outlined,
                  // TODO(l10n): key=noBootstrapNodes
                  title: 'No bootstrap nodes',
                  action: ElevatedButton(
                    onPressed: _loadNodes,
                    child: Text(appL10n.retry),
                  ),
                )
              : _wrapWithRefresh(
                  isDesktop: PlatformUtils.isDesktop,
                  color: Theme.of(context).colorScheme.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _nodes.length,
                    itemBuilder: (context, index) {
                      final node = _nodes[index];
                      final endpoint = node.formattedEndpoint ?? '';
                      final isOnline = node.status == 'ONLINE';
                      final isTesting = _testingNodes[node.publicKey] ?? false;
                      final testResult = _testResults[node.publicKey];
                      final isTestedSuccess =
                          _nodeTestSuccess[node.publicKey] ?? false;
                      final outlineVariant = Theme.of(
                        context,
                      ).colorScheme.outlineVariant;
                      final statusColor = isOnline
                          ? AppThemeConfig.successColor
                          : Theme.of(context).colorScheme.error;
                      // Stagger entrance for first 10 rows only; respect
                      // reduced-motion preference (no-op when disabled).
                      final disableAnims = MediaQuery.disableAnimationsOf(
                        context,
                      );
                      final card = Card(
                        elevation: 0,
                        clipBehavior: Clip.antiAlias,
                        margin: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: outlineVariant),
                          borderRadius: BorderRadius.circular(
                            AppThemeConfig.cardBorderRadius,
                          ),
                        ),
                        child: InkWell(
                          onTap: isOnline ? () => _selectNode(node) : null,
                          child: ListTile(
                            leading: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(
                              endpoint,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorTheme.primaryTextColor,
                                    fontFamily: 'monospace',
                                  ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (node.location != null)
                                  Text(
                                    node.location!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                if (node.maintainer != null)
                                  Text(
                                    AppLocalizations.of(
                                      context,
                                    )!.maintainer(node.maintainer!),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                if (node.lastPing != null)
                                  Text(
                                    appL10n.lastPing(node.lastPing.toString()),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                if (testResult != null) ...[
                                  AppSpacing.verticalXs,
                                  Row(
                                    children: [
                                      Icon(
                                        isTestedSuccess
                                            ? Icons.send_outlined
                                            : Icons.error_outline,
                                        size: 14,
                                        color: isTestedSuccess
                                            ? AppThemeConfig.successColor
                                            : Theme.of(
                                                context,
                                              ).colorScheme.error,
                                      ),
                                      AppSpacing.horizontalXs,
                                      Text(
                                        testResult,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: isTestedSuccess
                                                  ? AppThemeConfig.successColor
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.error,
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
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.send_outlined),
                                  onPressed: isTesting
                                      ? null
                                      : () => _testNode(node),
                                  tooltip: appL10n.testNode,
                                ),
                                if (isOnline)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: AppSpacing.sm,
                                    ),
                                    child: Icon(
                                      isTestedSuccess
                                          ? Icons.send_outlined
                                          : Icons.chevron_right,
                                      size: 20,
                                      color: isTestedSuccess
                                          ? AppThemeConfig.successColor
                                          : Theme.of(context).iconTheme.color
                                                ?.withValues(alpha: 0.4),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (disableAnims || index >= 10) return card;
                      return StaggeredListItem(
                        index: index,
                        staggerDelay: const Duration(milliseconds: 40),
                        child: card,
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
