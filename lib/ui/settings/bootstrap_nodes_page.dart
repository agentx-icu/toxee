import 'dart:async';
import 'package:flutter/material.dart';

import '../widgets/safe_dialog_pop.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/bootstrap_node_probe.dart';
import '../../util/bootstrap_nodes.dart';
import '../../util/logger.dart';
import '../../util/platform_utils.dart';
import '../../util/prefs.dart';
import '../../util/responsive_layout.dart';
import '../../i18n/app_localizations.dart';
import '../../ui/widgets/empty_state_widget.dart';
import '../../ui/widgets/loading_shimmer.dart';
import '../../ui/widgets/stagger_list_item.dart';

part 'bootstrap_nodes_page_card.dart';

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

  /// Whether the last probe produced a verdict ABOUT THE NODE.
  ///
  /// `false` for `udpUnavailable` and for a caught [BootstrapProbeUnavailable]:
  /// in both cases the probe never ran against the node, so `_nodeTestSuccess`
  /// being `false` means "unknown", NOT "the node failed". Without this
  /// distinction `_selectNode` told a TCP-only user that every node they tested
  /// "did not respond" — exactly the lie [BootstrapProbeVerdict.udpUnavailable]
  /// documents must never be rendered.
  final Map<String, bool> _nodeTestConclusive = {};

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  @override
  void dispose() {
    // Hand back the ephemeral probe Tox instance when the page goes away, so a
    // pre-login probe can never outlive the screen that asked for it.
    unawaited(BootstrapNodeProbe.shutdown());
    super.dispose();
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
    final udpLabel = appL10n.nodeTestUdpUnavailable;
    final unavailableLabel = appL10n.nodeTestUnavailable;
    setState(() {
      _testingNodes[node.publicKey] = true;
      _testResults[node.publicKey] = null;
      _nodeTestSuccess[node.publicKey] = false;
      _nodeTestConclusive[node.publicKey] = false;
    });
    try {
      // A real DHT reachability probe, session or not: pre-login the probe
      // stands up its own isolated, short-lived Tox instance. This page is
      // reachable from the LOGIN page, which is precisely where a user who
      // cannot connect needs to try nodes out.
      final verdict = await BootstrapNodeProbe.probe(
        host: host,
        port: node.port,
        publicKey: node.publicKey,
        service: widget.service,
      );
      final success = verdict == BootstrapProbeVerdict.reachable;
      // UDP-less device: the probe proved nothing about this node, so show the
      // constraint rather than a red cross the node did not earn.
      final udpless = verdict == BootstrapProbeVerdict.udpUnavailable;
      if (!mounted) return;
      setState(() {
        _testResults[node.publicKey] = udpless
            ? udpLabel
            : (success ? successLabel : failedLabel);
        _nodeTestSuccess[node.publicKey] = success;
        _nodeTestConclusive[node.publicKey] = !udpless;
      });
    } on BootstrapProbeUnavailable catch (e, st) {
      // The probe itself could not run. Reporting that as a node failure would
      // blame the user's node for our defect — see the exception's doc comment.
      AppLogger.logError('[BootstrapNodesPage] node probe unavailable', e, st);
      if (!mounted) return;
      setState(() {
        _testResults[node.publicKey] = unavailableLabel;
        _nodeTestSuccess[node.publicKey] = false;
        _nodeTestConclusive[node.publicKey] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResults[node.publicKey] = appL10n.error(e.toString());
        _nodeTestSuccess[node.publicKey] = false;
        _nodeTestConclusive[node.publicKey] = false;
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
    // "Tested" is not the same as "we learned something": a UDP-less device (or
    // a probe that failed to start) leaves a result label but no verdict.
    final isConclusive = _nodeTestConclusive[node.publicKey] ?? false;

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

    // Show warning if node hasn't been tested or test failed, but allow
    // selection. THREE outcomes, not two — collapsing the inconclusive case
    // into "did not respond" is the lie this branch exists to avoid.
    String confirmMessage = appL10n.switchNodeConfirm(endpoint);
    if (!hasBeenTested) {
      confirmMessage =
          '${appL10n.switchNodeConfirm(endpoint)}\n\n${appL10n.nodeNotTestedWarning}';
    } else if (!isConclusive) {
      confirmMessage =
          '${appL10n.switchNodeConfirm(endpoint)}\n\n${appL10n.nodeTestInconclusiveWarning}';
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
                  title: appL10n.failedToLoadBootstrapNodes,
                  subtitle: _error,
                  action: ElevatedButton(
                    onPressed: _loadNodes,
                    child: Text(appL10n.retry),
                  ),
                )
              : _nodes.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.dns_outlined,
                  title: appL10n.noBootstrapNodes,
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
                      final card = _BootstrapNodeCard(
                        node: node,
                        isTesting: _testingNodes[node.publicKey] ?? false,
                        testResult: _testResults[node.publicKey],
                        isTestedSuccess:
                            _nodeTestSuccess[node.publicKey] ?? false,
                        isTestConclusive:
                            _nodeTestConclusive[node.publicKey] ?? false,
                        colorTheme: colorTheme,
                        onTest: () => _testNode(node),
                        onSelect: () => _selectNode(node),
                      );
                      // Stagger entrance for first 10 rows only; respect the
                      // reduced-motion preference (no-op when disabled).
                      if (MediaQuery.disableAnimationsOf(context) ||
                          index >= 10) {
                        return card;
                      }
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
