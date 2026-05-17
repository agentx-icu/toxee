import 'package:flutter/material.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/bootstrap_nodes.dart';
import '../../util/lan_bootstrap_service.dart';
import '../../util/logger.dart';
import '../../util/platform_utils.dart';
import '../../util/prefs.dart';
import '../../i18n/app_localizations.dart';
import '../widgets/app_page_route.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/section_header.dart';
import 'bootstrap_nodes_page.dart';

/// Shared bootstrap node settings section. Layout and behavior match [SettingsPage].
/// When [service] is null (e.g. login settings), test and route/scan actions that
/// require the service are hidden or use Prefs-only behavior.
class BootstrapSettingsSection extends StatefulWidget {
  const BootstrapSettingsSection({
    super.key,
    this.service,
    this.colorTheme,
  });

  /// When null, test node and "Route selection" / "Scan LAN" use Prefs-only or are hidden.
  final FfiChatService? service;

  /// Theme from [TencentCloudChatThemeWidget]. If null, Material theme colors are used.
  final dynamic colorTheme;

  @override
  State<BootstrapSettingsSection> createState() => _BootstrapSettingsSectionState();
}

class _BootstrapSettingsSectionState extends State<BootstrapSettingsSection> {
  ({String host, int port, String pubkey})? _currentBootstrapNode;
  final TextEditingController _manualHostController = TextEditingController();
  final TextEditingController _manualPortController = TextEditingController();
  final TextEditingController _manualPubkeyController = TextEditingController();
  bool _manualInputExpanded = false;
  String _bootstrapNodeMode = 'auto';

  bool _testingCurrentNode = false;
  String? _nodeTestResult;
  int? _nodeLatency;
  bool _testingManualNode = false;
  String? _manualNodeTestResult;
  int? _manualNodeLatency;

  bool _lanBootstrapServiceRunning = false;
  String? _lanBootstrapServiceIP;
  int? _lanBootstrapServicePort;
  String? _lanBootstrapServicePubkey;
  final TextEditingController _lanBootstrapPortController = TextEditingController();

  dynamic get _colorTheme => widget.colorTheme;

  @override
  void initState() {
    super.initState();
    _loadBootstrapNodeMode();
    _loadCurrentBootstrapNode();
    _loadLanBootstrapServiceState();
    Prefs.getLanBootstrapPort().then((p) {
      if (mounted) {
        _lanBootstrapPortController.text = p.toString();
      }
    });
  }

  @override
  void dispose() {
    _manualHostController.dispose();
    _manualPortController.dispose();
    _manualPubkeyController.dispose();
    _lanBootstrapPortController.dispose();
    super.dispose();
  }

  Future<void> _loadBootstrapNodeMode() async {
    var mode = await Prefs.getBootstrapNodeMode();
    if (!PlatformUtils.isDesktop && mode == 'lan') {
      await Prefs.setBootstrapNodeMode('auto');
      mode = 'auto';
    }
    if (mounted) setState(() => _bootstrapNodeMode = mode);
  }

  Future<void> _setBootstrapNodeMode(String mode) async {
    if (!PlatformUtils.isDesktop && mode == 'lan') return;
    await Prefs.setBootstrapNodeMode(mode);
    if (mounted) {
      setState(() => _bootstrapNodeMode = mode);
      if (mode == 'auto') {
        await _loadAndUseAutoNode();
      } else if (mode == 'manual') {
        await _loadCurrentBootstrapNode();
      } else if (mode == 'lan') {
        await _loadLanBootstrapServiceState();
      }
    }
  }

  Future<void> _loadAndUseAutoNode() async {
    try {
      final nodes = await BootstrapNodesService.fetchNodes();
      if (nodes.isEmpty) return;
      final onlineNode = nodes.firstWhere(
        (n) => n.status == 'ONLINE',
        orElse: () => nodes.first,
      );
      if (widget.service != null) {
        await widget.service!.addBootstrapNode(
          onlineNode.ipv4,
          onlineNode.port,
          onlineNode.publicKey,
        );
      }
      await Prefs.setCurrentBootstrapNode(
        onlineNode.ipv4,
        onlineNode.port,
        onlineNode.publicKey,
      );
      await _loadCurrentBootstrapNode();
    } catch (e, st) {
      // Previously swallowed silently. Users hit "auto mode" and saw nothing
      // happen on failure (e.g. nodes.tox.chat unreachable). Surface it.
      AppLogger.logError(
          '[BootstrapSettingsSection] _loadAndUseAutoNode failed', e, st);
      if (!mounted) return;
      // TODO(l10n): key=failedToLoadBootstrapNodes
      AppSnackBar.showError(
        context,
        'Failed to load bootstrap nodes',
      );
    }
  }

  Future<void> _loadCurrentBootstrapNode() async {
    final node = await Prefs.getCurrentBootstrapNode();
    if (mounted) {
      setState(() {
        _currentBootstrapNode = node;
        _nodeTestResult = null;
        _nodeLatency = null;
        if (node != null) {
          _manualHostController.text = node.host;
          _manualPortController.text = node.port.toString();
          _manualPubkeyController.text = node.pubkey;
        }
      });
    }
    if (_manualPortController.text.isEmpty) {
      _manualPortController.text = '33445';
    }
  }

  Future<void> _loadLanBootstrapServiceState() async {
    final running = await Prefs.getLanBootstrapServiceRunning();
    if (running) {
      final info = await LanBootstrapServiceManager.instance.getBootstrapServiceInfo();
      if (mounted) {
        setState(() {
          _lanBootstrapServiceRunning = true;
          if (info != null) {
            _lanBootstrapServiceIP = info.ip;
            _lanBootstrapServicePort = info.port;
            _lanBootstrapServicePubkey = info.pubkey;
          }
        });
      }
    } else if (mounted) {
      setState(() {
        _lanBootstrapServiceRunning = false;
        _lanBootstrapServiceIP = null;
        _lanBootstrapServicePort = null;
        _lanBootstrapServicePubkey = null;
      });
    }
    final port = await Prefs.getLanBootstrapPort();
    if (mounted) _lanBootstrapPortController.text = port.toString();
  }

  Future<void> _testCurrentNode() async {
    if (_currentBootstrapNode == null) return;
    setState(() {
      _testingCurrentNode = true;
      _nodeTestResult = null;
      _nodeLatency = null;
    });
    try {
      final start = DateTime.now();
      bool success;
      if (widget.service != null) {
        success = await widget.service!.addBootstrapNode(
          _currentBootstrapNode!.host,
          _currentBootstrapNode!.port,
          _currentBootstrapNode!.pubkey,
        );
      } else {
        // TCP probe fallback when service is not available (login settings)
        final result = await LanBootstrapServiceManager.probeBootstrapService(
          _currentBootstrapNode!.host,
          _currentBootstrapNode!.port,
        );
        success = result != null && result.isAvailable;
      }
      final latency = DateTime.now().difference(start).inMilliseconds;
      if (mounted) {
        setState(() {
          _testingCurrentNode = false;
          _nodeTestResult = success ? 'success' : 'failed';
          _nodeLatency = success ? latency : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _testingCurrentNode = false;
          _nodeTestResult = 'failed';
          _nodeLatency = null;
        });
      }
    }
  }

  Future<void> _testManualNode() async {
    final host = _manualHostController.text.trim();
    final portText = _manualPortController.text.trim();
    final pubkey = _manualPubkeyController.text.trim();
    if (host.isEmpty || portText.isEmpty || pubkey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.invalidNodeInfo),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    final port = int.tryParse(portText);
    if (port == null || port <= 0 || port > 65535) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.invalidNodeInfo),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    setState(() {
      _testingManualNode = true;
      _manualNodeTestResult = null;
      _manualNodeLatency = null;
    });
    try {
      final start = DateTime.now();
      bool success;
      if (widget.service != null) {
        success = await widget.service!.addBootstrapNode(host, port, pubkey);
      } else {
        // TCP probe fallback when service is not available (login settings)
        final result = await LanBootstrapServiceManager.probeBootstrapService(host, port);
        success = result != null && result.isAvailable;
      }
      final latency = DateTime.now().difference(start).inMilliseconds;
      if (mounted) {
        setState(() {
          _testingManualNode = false;
          _manualNodeTestResult = success ? 'success' : 'failed';
          _manualNodeLatency = success ? latency : null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? AppLocalizations.of(context)!.nodeTestSuccess
                  : AppLocalizations.of(context)!.nodeTestFailed,
            ),
            backgroundColor: success
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testingManualNode = false;
          _manualNodeTestResult = 'failed';
          _manualNodeLatency = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.nodeTestFailed}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _setManualNodeAsCurrent() async {
    if (_manualNodeTestResult != 'success') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.canOnlySelectTestedNode),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    final host = _manualHostController.text.trim();
    final portText = _manualPortController.text.trim();
    final pubkey = _manualPubkeyController.text.trim();
    if (host.isEmpty || portText.isEmpty || pubkey.isEmpty) return;
    final port = int.tryParse(portText);
    if (port == null || port <= 0 || port > 65535) return;
    try {
      await Prefs.setCurrentBootstrapNode(host, port, pubkey);
      await _loadCurrentBootstrapNode();
      if (mounted) {
        setState(() => _manualInputExpanded = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.nodeSetSuccess),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.nodeSwitchFailed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _startLanBootstrapService() async {
    final port = int.tryParse(_lanBootstrapPortController.text.trim()) ?? 33445;
    if (port <= 0 || port > 65535) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.invalidNodeInfo),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    await Prefs.setLanBootstrapPort(port);
    final success = await LanBootstrapServiceManager.instance.startLocalBootstrapService(port);
    if (mounted) {
      await _loadLanBootstrapServiceState();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? AppLocalizations.of(context)!.serviceRunning
                // TODO(l10n): key=failedToStartBootstrapService
                : 'Failed to start bootstrap service',
          ),
          backgroundColor: success
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _stopLanBootstrapService() async {
    await LanBootstrapServiceManager.instance.stopLocalBootstrapService();
    if (mounted) {
      await _loadLanBootstrapServiceState();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.serviceStopped)),
      );
    }
  }

  bool _isValidPubkey(String pubkey) {
    if (pubkey.length != 64) return false;
    return RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(pubkey);
  }

  Color _secondaryColor(BuildContext context) {
    if (_colorTheme != null && _colorTheme.secondaryColor != null) {
      return _colorTheme.secondaryColor as Color;
    }
    return Theme.of(context).colorScheme.surfaceContainerHighest;
  }

  Color _primaryColor(BuildContext context) {
    if (_colorTheme != null && _colorTheme.primaryColor != null) {
      return _colorTheme.primaryColor as Color;
    }
    return Theme.of(context).colorScheme.primary;
  }

  Color _secondaryTextColor(BuildContext context) {
    if (_colorTheme != null && _colorTheme.secondaryTextColor != null) {
      return _colorTheme.secondaryTextColor as Color;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  Color _primaryTextColor(BuildContext context) {
    if (_colorTheme != null && _colorTheme.primaryTextColor != null) {
      return _colorTheme.primaryTextColor as Color;
    }
    return Theme.of(context).colorScheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final secondaryColor = _secondaryColor(context);
    final primaryColor = _primaryColor(context);
    final secondaryTextColor = _secondaryTextColor(context);
    final primaryTextColor = _primaryTextColor(context);
    final hasService = widget.service != null;

    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: outlineVariant),
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: l10n.bootstrapNodes),
            AppSpacing.verticalSm,
            Text(
              l10n.bootstrapNodeMode,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            AppSpacing.verticalSm,
            if (PlatformUtils.isDesktop)
              _buildModeRow(context, l10n, primaryColor, secondaryTextColor, hasService)
            else
              _buildModeRowMobile(context, l10n, primaryColor, secondaryTextColor),
            AppSpacing.verticalSm,
            Divider(height: 1, color: outlineVariant),
            AppSpacing.verticalSm,
            if (_bootstrapNodeMode == 'manual' || _currentBootstrapNode != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_currentBootstrapNode != null) ...[
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: secondaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                          border: Border.all(color: outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.network_ping, size: 16, color: primaryColor),
                                AppSpacing.horizontalXs,
                                Text(
                                  l10n.currentNode,
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: secondaryTextColor,
                                      ),
                                ),
                              ],
                            ),
                            AppSpacing.verticalXs,
                            Text(
                              '${_currentBootstrapNode!.host}:${_currentBootstrapNode!.port}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: primaryTextColor,
                                    fontFamily: 'monospace',
                                  ),
                            ),
                            if (_currentBootstrapNode!.pubkey.length > 20)
                              Text(
                                '${_currentBootstrapNode!.pubkey.substring(0, 20)}...',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: secondaryTextColor,
                                      fontFamily: 'monospace',
                                    ),
                              ),
                            if (_nodeTestResult != null) ...[
                              AppSpacing.verticalSm,
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _StatusPill(
                                    label: _nodeTestResult == 'success'
                                        ? l10n.online
                                        : l10n.offline,
                                    color: _nodeTestResult == 'success'
                                        ? AppThemeConfig.successColor
                                        : Theme.of(context).colorScheme.error,
                                  ),
                                  if (_nodeLatency != null && _nodeTestResult == 'success') ...[
                                    AppSpacing.horizontalSm,
                                    Text(
                                      '${_nodeLatency}ms',
                                      // Tabular figures so latency numerics
                                      // don't reflow as digits change width.
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                            color: secondaryTextColor,
                                            fontFamily: 'monospace',
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    AppSpacing.horizontalSm,
                  ],
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_currentBootstrapNode != null)
                        OutlinedButton.icon(
                          icon: _testingCurrentNode
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.speed, size: 18),
                          label: Text(l10n.testNode),
                          onPressed: !_testingCurrentNode ? _testCurrentNode : null,
                        ),
                      if (_bootstrapNodeMode == 'auto') ...[
                        if (_currentBootstrapNode != null) AppSpacing.verticalSm,
                        OutlinedButton.icon(
                            icon: const Icon(Icons.network_check, size: 18),
                            label: Text(l10n.routeSelection),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                AppPageRoute<void>(
                                  page: BootstrapNodesPage(
                                    service: widget.service,
                                    onNodeSelected: () async {
                                      if (mounted) await _loadCurrentBootstrapNode();
                                    },
                                  ),
                                ),
                              );
                              await Future.delayed(const Duration(milliseconds: 200));
                              if (mounted) {
                                await _loadCurrentBootstrapNode();
                                setState(() {});
                              }
                            },
                          ),
                      ],
                      if (_bootstrapNodeMode == 'manual') ...[
                        AppSpacing.verticalSm,
                        OutlinedButton.icon(
                          icon: Icon(
                            _manualInputExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                          label: Text(l10n.manualNodeInput),
                          onPressed: () {
                            setState(() => _manualInputExpanded = !_manualInputExpanded);
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
            if (_bootstrapNodeMode == 'lan') ...[
              AppSpacing.verticalLg,
              const Divider(),
              AppSpacing.verticalMd,
              Text(
                l10n.startLocalBootstrapService,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (PlatformUtils.isWindows)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'On Windows, the firewall may block incoming connections; allow the app if prompted.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (PlatformUtils.isLinux)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'On Linux, network operations may require appropriate permissions or firewall rules.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              AppSpacing.verticalSm,
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lanBootstrapPortController,
                      keyboardType: TextInputType.number,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        labelText: l10n.nodePort,
                        hintText: '33445',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      ),
                    ),
                  ),
                  AppSpacing.horizontalSm,
                  ElevatedButton.icon(
                    icon: _lanBootstrapServiceRunning
                        ? const Icon(Icons.stop, size: 18)
                        : const Icon(Icons.play_arrow, size: 18),
                    label: Text(
                      _lanBootstrapServiceRunning
                          ? l10n.stopLocalBootstrapService
                          : l10n.startLocalBootstrapService,
                    ),
                    onPressed: _lanBootstrapServiceRunning
                        ? _stopLanBootstrapService
                        : _startLanBootstrapService,
                  ),
                ],
              ),
              AppSpacing.verticalSm,
              Row(
                children: [
                  Text(
                    '${l10n.bootstrapServiceStatus}: ',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    _lanBootstrapServiceRunning
                        ? l10n.serviceRunning
                        : l10n.serviceStopped,
                    style: TextStyle(
                      color: _lanBootstrapServiceRunning
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_lanBootstrapServiceRunning &&
                  _lanBootstrapServiceIP != null &&
                  _lanBootstrapServicePort != null) ...[
                AppSpacing.verticalSm,
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: secondaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                    border: Border.all(color: outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l10n.ipAddress}: $_lanBootstrapServiceIP',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: primaryTextColor,
                            ),
                      ),
                      Text(
                        '${l10n.nodePort}: $_lanBootstrapServicePort',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: primaryTextColor,
                            ),
                      ),
                      if (_lanBootstrapServicePubkey != null)
                        Text(
                          '${l10n.nodePublicKey}: ${_lanBootstrapServicePubkey!.substring(0, 16)}...',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontFamily: 'monospace',
                                color: secondaryTextColor,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
            if (_bootstrapNodeMode == 'manual')
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _manualInputExpanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppSpacing.verticalLg,
                          const Divider(),
                          AppSpacing.verticalMd,
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _manualHostController,
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: InputDecoration(
                                    labelText: l10n.nodeHost,
                                    hintText: 'example.com',
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                                  ),
                                ),
                              ),
                              AppSpacing.horizontalSm,
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _manualPortController,
                                  keyboardType: TextInputType.number,
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: InputDecoration(
                                    labelText: l10n.nodePort,
                                    hintText: '33445',
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          AppSpacing.verticalSm,
                          TextField(
                            controller: _manualPubkeyController,
                            maxLines: 2,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              labelText: l10n.nodePublicKey,
                              hintText: 'Public key (hex)',
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                              labelStyle: Theme.of(context).textTheme.bodyLarge,
                            ),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                          AppSpacing.verticalMd,
                          if (_manualNodeTestResult != null) ...[
                            Row(
                              children: [
                                _StatusPill(
                                  label: _manualNodeTestResult == 'success'
                                      ? l10n.nodeTestSuccess
                                      : l10n.nodeTestFailed,
                                  color: _manualNodeTestResult == 'success'
                                      ? AppThemeConfig.successColor
                                      : Theme.of(context).colorScheme.error,
                                ),
                                if (_manualNodeLatency != null &&
                                    _manualNodeTestResult == 'success') ...[
                                  AppSpacing.horizontalSm,
                                  Text(
                                    '${_manualNodeLatency}ms',
                                    // Tabular figures keep the latency display
                                    // from reflowing when the value updates.
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: secondaryTextColor,
                                          fontFamily: 'monospace',
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                  ),
                                ],
                              ],
                            ),
                            AppSpacing.verticalMd,
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: _testingManualNode
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.speed, size: 18),
                                  label: Text(l10n.testNode),
                                  onPressed: !_testingManualNode ? _testManualNode : null,
                                ),
                              ),
                              if (_manualNodeTestResult == 'success') ...[
                                AppSpacing.horizontalSm,
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.check_circle, size: 18),
                                    label: Text(l10n.setAsCurrentNode),
                                    onPressed: hasService
                                        ? _setManualNodeAsCurrent
                                        : () async {
                                            final host = _manualHostController.text.trim();
                                            final portText = _manualPortController.text.trim();
                                            final pubkey = _manualPubkeyController.text.trim();
                                            if (host.isEmpty ||
                                                portText.isEmpty ||
                                                pubkey.isEmpty ||
                                                !_isValidPubkey(pubkey)) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(l10n.invalidNodeInfo),
                                                  backgroundColor:
                                                      Theme.of(context).colorScheme.error,
                                                ),
                                              );
                                              return;
                                            }
                                            final port = int.tryParse(portText);
                                            if (port == null || port <= 0 || port > 65535) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(l10n.invalidNodeInfo),
                                                  backgroundColor:
                                                      Theme.of(context).colorScheme.error,
                                                ),
                                              );
                                              return;
                                            }
                                            await Prefs.setCurrentBootstrapNode(host, port, pubkey);
                                            await _loadCurrentBootstrapNode();
                                            if (mounted) {
                                              setState(() => _manualInputExpanded = false);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(l10n.nodeSetSuccess),
                                                  backgroundColor:
                                                      Theme.of(context).colorScheme.primary,
                                                ),
                                              );
                                            }
                                          },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeRow(
    BuildContext context,
    AppLocalizations l10n,
    Color primaryColor,
    Color secondaryTextColor,
    bool hasService,
  ) {
    return Row(
      children: [
        Expanded(
          child: RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'manual',
            groupValue: _bootstrapNodeMode,
            title: Text(l10n.manualMode),
            subtitle: Text(l10n.manualModeDesc, style: Theme.of(context).textTheme.labelSmall),
            onChanged: (v) {
              if (v != null) _setBootstrapNodeMode(v);
            },
          ),
        ),
        Expanded(
          child: RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'auto',
            groupValue: _bootstrapNodeMode,
            title: Text(l10n.autoMode),
            subtitle: GestureDetector(
              onTap: () async {
                final url = Uri.parse('https://nodes.tox.chat/');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: secondaryTextColor),
                  children: [
                    TextSpan(text: l10n.autoModeDescPrefix),
                    TextSpan(
                      text: 'https://nodes.tox.chat/',
                      style: TextStyle(
                        color: primaryColor,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            onChanged: (v) {
              if (v != null) _setBootstrapNodeMode(v);
            },
          ),
        ),
        Expanded(
          child: RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'lan',
            groupValue: _bootstrapNodeMode,
            title: Text(l10n.lanMode),
            subtitle: Text(l10n.lanModeDesc, style: Theme.of(context).textTheme.labelSmall),
            onChanged: (v) {
              if (v != null) _setBootstrapNodeMode(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModeRowMobile(
    BuildContext context,
    AppLocalizations l10n,
    Color primaryColor,
    Color secondaryTextColor,
  ) {
    final theme = Theme.of(context);
    final selected = _bootstrapNodeMode == 'manual' ? 'manual' : 'auto';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment<String>(
                value: 'manual',
                label: Text(l10n.manualMode),
                icon: const Icon(Icons.tune, size: 18),
              ),
              ButtonSegment<String>(
                value: 'auto',
                label: Text(l10n.autoMode),
                icon: const Icon(Icons.public, size: 18),
              ),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (set) {
              if (set.isNotEmpty) _setBootstrapNodeMode(set.first);
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return primaryColor.withValues(alpha: 0.12);
                }
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return primaryColor;
                }
                return theme.colorScheme.onSurfaceVariant;
              }),
              textStyle: WidgetStatePropertyAll(
                theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                ),
              ),
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return BorderSide(color: primaryColor.withValues(alpha: 0.4));
                }
                return BorderSide(color: theme.colorScheme.outlineVariant);
              }),
            ),
          ),
        ),
        AppSpacing.verticalSm,
        if (selected == 'manual')
          Text(
            l10n.manualModeDesc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          GestureDetector(
            onTap: () async {
              final url = Uri.parse('https://nodes.tox.chat/');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                children: [
                  TextSpan(text: l10n.autoModeDescPrefix),
                  TextSpan(
                    text: 'https://nodes.tox.chat/',
                    style: TextStyle(
                      color: primaryColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Pill-shaped status badge used for online/offline/test-result indicators in
/// the bootstrap settings UI. Background is a 10% tint of [color]; text + dot
/// are full [color]; outer shape is a Stadium pill so it reads as a status
/// chip rather than a button or list-tile leading marker.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.10),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          AppSpacing.horizontalXs,
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

