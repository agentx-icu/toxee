import 'dart:async';
import 'package:flutter/material.dart';

import '../widgets/safe_dialog_pop.dart';
import '../../util/app_spacing.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/color_base.dart';
import '../../i18n/app_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../../util/irc_app_manager.dart';
import '../../util/prefs.dart';
import '../../sdk_fake/fake_uikit_core.dart';
import '../../sdk_fake/fake_im.dart';
import '../../sdk_fake/fake_models.dart';
import '../../util/app_theme_config.dart';
import '../../util/platform_utils.dart';
import '../../util/responsive_layout.dart';
import '../testing/ui_keys.dart';
import 'irc_channel_dialog.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/loading_shimmer.dart';

class ApplicationsIrcSnapshot {
  const ApplicationsIrcSnapshot({
    required this.isInstalled,
    required this.channels,
    required this.server,
    required this.port,
    required this.useSasl,
  });

  final bool isInstalled;
  final List<String> channels;
  final String server;
  final int port;
  final bool useSasl;
}

abstract class ApplicationsIrcController {
  Stream<({String channel, int status, String? message})>
  get ircConnectionStatusStream;
  Stream<({String channel, List<String> users})> get ircUserListStream;
  Stream<({String channel, String nickname, bool joined})>
  get ircUserJoinPartStream;

  Future<ApplicationsIrcSnapshot> loadState();
  Future<void> saveConfig({
    required String server,
    required int port,
    required bool useSasl,
  });
  Future<void> install();
  Future<void> uninstall();
  Future<bool> addChannel(
    String channel, {
    String? password,
    String? customNickname,
  });
  Future<void> removeChannel(String channel);
}

class LiveApplicationsIrcController implements ApplicationsIrcController {
  LiveApplicationsIrcController(this._service, {IrcAppManager? manager})
    : _manager = manager ?? IrcAppManager();

  final FfiChatService _service;
  final IrcAppManager _manager;

  @override
  Stream<({String channel, int status, String? message})>
  get ircConnectionStatusStream => _service.ircConnectionStatusStream;

  @override
  Stream<({String channel, List<String> users})> get ircUserListStream =>
      _service.ircUserListStream;

  @override
  Stream<({String channel, String nickname, bool joined})>
  get ircUserJoinPartStream => _service.ircUserJoinPartStream;

  @override
  Future<ApplicationsIrcSnapshot> loadState() async {
    await _manager.init();
    await _manager.restoreChannelMappings(_service);
    return _snapshot();
  }

  @override
  Future<void> saveConfig({
    required String server,
    required int port,
    required bool useSasl,
  }) async {
    await Prefs.setIrcServer(server);
    await Prefs.setIrcPort(port);
    await Prefs.setIrcUseSasl(useSasl);
  }

  @override
  Future<void> install() => _manager.install(_service);

  @override
  Future<void> uninstall() async {
    final groupIds = <String>[];
    for (final channel in _manager.channels) {
      final groupId = _manager.getGroupIdForChannel(channel);
      if (groupId != null) groupIds.add(groupId);
    }

    await _manager.uninstall(_service);

    for (final groupId in groupIds) {
      _clearIrcConversation(groupId);
    }
    await FakeUIKit.instance.im?.refreshConversations();
  }

  @override
  Future<bool> addChannel(
    String channel, {
    String? password,
    String? customNickname,
  }) async {
    final groupId = await _manager.addChannel(
      channel,
      _service,
      password: password,
      customNickname: customNickname,
    );
    if (groupId != null) {
      await FakeUIKit.instance.im?.refreshConversations();
      return true;
    }
    return false;
  }

  @override
  Future<void> removeChannel(String channel) async {
    final groupId = _manager.getGroupIdForChannel(channel);
    await _manager.removeChannel(channel, _service);
    if (groupId != null) {
      _clearIrcConversation(groupId);
    }
    await FakeUIKit.instance.im?.refreshConversations();
  }

  Future<ApplicationsIrcSnapshot> _snapshot() async {
    final server = await Prefs.getIrcServer();
    final port = await Prefs.getIrcPort();
    final useSasl = await Prefs.getIrcUseSasl();
    return ApplicationsIrcSnapshot(
      isInstalled: _manager.isInstalled,
      channels: _manager.channels,
      server: server,
      port: port,
      useSasl: useSasl,
    );
  }

  void _clearIrcConversation(String groupId) {
    final conversationID = 'group_$groupId';
    FakeUIKit.instance.messageProvider?.clearMessageBuffer(conversationID);
    FakeUIKit.instance.eventBusInstance.emit(
      FakeIM.topicGroupDeleted,
      FakeGroupDeleted(groupID: groupId),
    );
  }
}

/// Applications page for extension apps
class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key, this.service, this.ircController})
    : assert(service != null || ircController != null);

  final FfiChatService? service;
  final ApplicationsIrcController? ircController;

  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  late final ApplicationsIrcController _ircController;
  bool _isInstalled = false;
  List<String> _channels = [];
  bool _isLoading = false;
  final _serverController = TextEditingController();
  final _portController = TextEditingController();
  bool _useSasl = false;

  // IRC status tracking
  final Map<String, int> _channelStatus =
      {}; // channel -> status (0=disconnected, 1=connecting, 2=connected, etc.)
  final Map<String, String?> _channelStatusMessage =
      {}; // channel -> status message
  final Map<String, List<String>> _channelUsers =
      {}; // channel -> list of users
  StreamSubscription? _connectionStatusSub;
  StreamSubscription? _userListSub;
  StreamSubscription? _userJoinPartSub;

  @override
  void initState() {
    super.initState();
    _ircController =
        widget.ircController ?? LiveApplicationsIrcController(widget.service!);
    _loadAppState();
    _setupIrcListeners();
  }

  void _setupIrcListeners() {
    // Listen to connection status updates
    _connectionStatusSub = _ircController.ircConnectionStatusStream.listen((
      event,
    ) {
      if (mounted) {
        setState(() {
          _channelStatus[event.channel] = event.status;
          _channelStatusMessage[event.channel] = event.message;
        });
      }
    });

    // Listen to user list updates
    _userListSub = _ircController.ircUserListStream.listen((event) {
      if (mounted) {
        setState(() {
          _channelUsers[event.channel] = event.users;
        });
      }
    });

    // Listen to user join/part events
    _userJoinPartSub = _ircController.ircUserJoinPartStream.listen((event) {
      if (!mounted) return;
      setState(() {
        final users = _channelUsers[event.channel] ?? [];
        if (event.joined) {
          if (!users.contains(event.nickname)) {
            users.add(event.nickname);
          }
        } else {
          users.remove(event.nickname);
        }
        _channelUsers[event.channel] = users;
      });

      // Re-check after setState — the widget may have been deactivated.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            event.joined
                ? '${event.nickname} joined ${event.channel}'
                : '${event.nickname} left ${event.channel}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  Future<void> _loadAppState() async {
    final snapshot = await _ircController.loadState();
    if (mounted) {
      _applySnapshot(snapshot);
    }
  }

  void _applySnapshot(ApplicationsIrcSnapshot snapshot) {
    setState(() {
      _isInstalled = snapshot.isInstalled;
      _channels = List<String>.of(snapshot.channels);
      _serverController.text = snapshot.server;
      _portController.text = snapshot.port.toString();
      _useSasl = snapshot.useSasl;
    });
  }

  @override
  void dispose() {
    _connectionStatusSub?.cancel();
    _userListSub?.cancel();
    _userJoinPartSub?.cancel();
    _serverController.dispose();
    _portController.dispose();
    super.dispose();
  }

  String _getStatusText(AppLocalizations appL10n, int status) {
    switch (status) {
      case 0:
        return appL10n.ircStatusDisconnected;
      case 1:
        return appL10n.ircStatusConnecting;
      case 2:
        return appL10n.ircStatusConnected;
      case 3:
        return appL10n.ircStatusAuthenticating;
      case 4:
        return appL10n.ircStatusReconnecting;
      case 5:
        return appL10n.ircStatusError;
      default:
        return appL10n.unknown;
    }
  }

  Color _getStatusColor(int status, TencentCloudChatThemeColors colorTheme) {
    switch (status) {
      case 0:
        return colorTheme.secondaryTextColor;
      case 1:
        return colorTheme.secondButtonColor;
      case 2:
        return colorTheme.primaryColor;
      case 3:
        return colorTheme.primaryColor;
      case 4:
        return colorTheme.secondButtonColor;
      case 5:
        return colorTheme.tipsColor;
      default:
        return colorTheme.secondaryTextColor;
    }
  }

  Future<void> _saveIrcConfig() async {
    final server = _serverController.text.trim();
    final portStr = _portController.text.trim();
    final port = int.tryParse(portStr) ?? 6667;

    if (server.isEmpty) {
      final appL10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appL10n.ircServerRequired)));
      return;
    }

    await _ircController.saveConfig(
      server: server,
      port: port,
      useSasl: _useSasl,
    );

    if (mounted) {
      final appL10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appL10n.ircConfigSaved)));
    }
  }

  Future<void> _handleInstall() async {
    setState(() => _isLoading = true);
    try {
      await _ircController.install();
      final snapshot = await _ircController.loadState();
      if (mounted) {
        _applySnapshot(snapshot);
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appL10n.ircAppInstalled)));
      }
    } catch (e) {
      if (mounted) {
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${appL10n.failed}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleUninstall() async {
    final appL10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appL10n.uninstallIrcApp),
        content: Text(appL10n.uninstallIrcAppConfirm),
        actions: [
          TextButton(
            onPressed: () => popDialogIfCurrent(context, false),
            child: Text(appL10n.cancel),
          ),
          TextButton(
            onPressed: () => popDialogIfCurrent(context, true),
            child: Text(appL10n.uninstall),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _ircController.uninstall();
      final snapshot = await _ircController.loadState();

      if (mounted) {
        _applySnapshot(snapshot);
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appL10n.ircAppUninstalled)));
      }
    } catch (e) {
      if (mounted) {
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${appL10n.failed}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleAddChannel() async {
    final result =
        await showDialog<
          ({String channel, String? password, String? nickname})
        >(context: context, builder: (context) => const IrcChannelDialog());

    if (result == null || result.channel.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final added = await _ircController.addChannel(
        result.channel,
        password: result.password,
        customNickname: result.nickname,
      );
      final snapshot = await _ircController.loadState();
      if (added) {
        if (mounted) {
          _applySnapshot(snapshot);
          final appL10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appL10n.ircChannelAdded(result.channel))),
          );
        }
      } else {
        if (mounted) {
          final appL10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(appL10n.ircChannelAddFailed)));
        }
      }
    } catch (e) {
      if (mounted) {
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${appL10n.failed}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleRemoveChannel(String channel) async {
    final appL10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appL10n.removeIrcChannel),
        content: Text(appL10n.removeIrcChannelConfirm(channel)),
        actions: [
          TextButton(
            onPressed: () => popDialogIfCurrent(context, false),
            child: Text(appL10n.cancel),
          ),
          TextButton(
            onPressed: () => popDialogIfCurrent(context, true),
            child: Text(appL10n.remove),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _ircController.removeChannel(channel);
      final snapshot = await _ircController.loadState();

      if (mounted) {
        _applySnapshot(snapshot);
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appL10n.ircChannelRemoved(channel))),
        );
      }
    } catch (e) {
      if (mounted) {
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${appL10n.failed}: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Returns [child] verbatim on desktop (no pull-to-refresh affordance there;
  /// the AppBar exposes a refresh button instead); wraps in [RefreshIndicator]
  /// otherwise.
  Widget _wrapWithRefresh({
    required bool isDesktop,
    required Color color,
    required Widget child,
  }) {
    if (isDesktop) return child;
    return RefreshIndicator(
      color: color,
      onRefresh: _loadAppState,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appL10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final sectionLabelStyle = theme.textTheme.titleSmall?.copyWith(
          color: colorTheme.primaryTextColor,
          fontWeight: FontWeight.w600,
        );
        // On desktop, pull-to-refresh has no affordance; expose a refresh
        // IconButton in the AppBar instead and skip the RefreshIndicator wrap.
        final isDesktop = PlatformUtils.isDesktop;
        return Scaffold(
          backgroundColor: colorTheme.surface,
          appBar: AppBar(
            title: Text(appL10n.applications),
            backgroundColor: colorTheme.appBarBackgroundColor,
            foregroundColor: colorTheme.primaryTextColor,
            elevation: 0,
            actions: [
              if (isDesktop)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadAppState,
                  tooltip: AppLocalizations.of(context)!.refresh,
                ),
            ],
          ),
          body: SafeArea(
            child: _isLoading
                ? const LoadingShimmer(itemCount: 6, itemHeight: 72)
                : _wrapWithRefresh(
                    isDesktop: isDesktop,
                    color: colorTheme.primaryColor,
                    child: _buildContent(
                      context: context,
                      theme: theme,
                      scheme: scheme,
                      colorTheme: colorTheme,
                      appL10n: appL10n,
                      sectionLabelStyle: sectionLabelStyle,
                    ),
                  ),
          ),
        );
      },
    );
  }

  /// Builds the scrollable applications grid + (when installed) the
  /// configuration / channels detail section. Wrapped in a max-width
  /// `Center` so the grid doesn't stretch on ultrawide desktops.
  Widget _buildContent({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme scheme,
    required TencentCloudChatThemeColors colorTheme,
    required AppLocalizations appL10n,
    required TextStyle? sectionLabelStyle,
  }) {
    // List of "applications" available on this device. Currently only the
    // IRC channel app; the grid scaffolding is in place for future apps.
    final apps = <_AppCardData>[
      _AppCardData(
        id: 'irc',
        icon: Icons.chat_bubble_outline,
        title: appL10n.ircChannelApp,
        description: appL10n.ircChannelAppDesc,
        isInstalled: _isInstalled,
      ),
    ];

    final columnCount = ResponsiveLayout.responsiveColumnCount(context);
    // Single-item edge case: a lone tile in a 3-column grid looks lonely.
    // Center it with a sensible max-width instead of spanning full width.
    final useCompactSingleItem = apps.length == 1;

    Widget appsSection;
    if (useCompactSingleItem) {
      appsSection = SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: _buildAppCard(
              context: context,
              theme: theme,
              scheme: scheme,
              colorTheme: colorTheme,
              appL10n: appL10n,
              data: apps.first,
            ),
          ),
        ),
      );
    } else {
      appsSection = SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnCount,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.4,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAppCard(
            context: context,
            theme: theme,
            scheme: scheme,
            colorTheme: colorTheme,
            appL10n: appL10n,
            data: apps[index],
          ),
          childCount: apps.length,
        ),
      );
    }

    return CustomScrollView(
      // ListView used `physics: default`; keep AlwaysScrollable so
      // RefreshIndicator continues to work on short content.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Top breathing room above the grid (matches the original
        // `ListView(padding: all(AppSpacing.lg))` top inset).
        const SliverPadding(padding: EdgeInsets.only(top: AppSpacing.lg)),
        // Apps grid, constrained to maxWidth=1100 and centered so the
        // grid doesn't stretch on ultrawide desktops.
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: _ConstrainedSliver(maxWidth: 1100, sliver: appsSection),
        ),
        // Configuration + channels section — only when installed.
        if (_isInstalled)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: _buildInstalledDetails(
                    context: context,
                    theme: theme,
                    scheme: scheme,
                    colorTheme: colorTheme,
                    appL10n: appL10n,
                    sectionLabelStyle: sectionLabelStyle,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Builds a single application tile suitable for grid presentation:
  /// vertical layout (icon top → title → description → action buttons),
  /// hover affordance, equal-height when used inside a `SliverGrid`.
  Widget _buildAppCard({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme scheme,
    required TencentCloudChatThemeColors colorTheme,
    required AppLocalizations appL10n,
    required _AppCardData data,
  }) {
    final secondaryText = colorTheme.secondaryTextColor;
    final installedColor = colorTheme.primaryColor;

    // Top-right status indicator: "Installed" dot vs hollow circle.
    final statusBadge = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: data.isInstalled ? installedColor : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: data.isInstalled ? installedColor : scheme.outlineVariant,
          width: 1.5,
        ),
      ),
    );

    return _HoverableAppCard(
      key: data.id == 'irc' ? UiKeys.applicationsIrcCard : null,
      borderColor: scheme.outlineVariant,
      onTap: data.isInstalled ? null : _handleInstall,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Stack(
          children: [
            // Status indicator pinned top-right (preserves the legacy
            // "is the app live?" affordance previously implicit in the
            // install/uninstall button state).
            Positioned(top: 0, right: 0, child: statusBadge),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon (48) centered at top.
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppThemeConfig.tintedPrimaryCardColor(
                      colorTheme.primaryColor,
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.button),
                    border: Border.all(
                      color: AppThemeConfig.tintedPrimaryCardBorderColor(
                        colorTheme.primaryColor,
                      ),
                    ),
                  ),
                  child: Icon(
                    data.icon,
                    color: colorTheme.primaryColor,
                    size: 24,
                  ),
                ),
                AppSpacing.verticalMd,
                Text(
                  data.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorTheme.primaryTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    data.description,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryText,
                    ),
                  ),
                ),
                AppSpacing.verticalSm,
                // Action buttons — same callbacks as before.
                if (!data.isInstalled)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: data.id == 'irc'
                          ? UiKeys.applicationsIrcInstallButton
                          : null,
                      onPressed: _handleInstall,
                      icon: const Icon(Icons.install_mobile, size: 18),
                      label: Text(appL10n.install),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorTheme.primaryColor,
                        foregroundColor: colorTheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.button),
                        ),
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: data.id == 'irc'
                              ? UiKeys.applicationsIrcUninstallButton
                              : null,
                          onPressed: _handleUninstall,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: Text(appL10n.uninstall),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorTheme.primaryColor,
                            side: BorderSide(color: scheme.outlineVariant),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadii.button,
                              ),
                            ),
                          ),
                        ),
                      ),
                      AppSpacing.horizontalSm,
                      Expanded(
                        child: FilledButton.icon(
                          key: data.id == 'irc'
                              ? UiKeys.applicationsIrcAddChannelButton
                              : null,
                          onPressed: _handleAddChannel,
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(appL10n.addIrcChannel),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorTheme.primaryColor,
                            foregroundColor: colorTheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadii.button,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Per-app detail panel — only visible when the IRC app is installed.
  /// Houses the server config form and the channel list (unchanged
  /// behavior, only the host scaffold changed from a single big card to
  /// this dedicated section beneath the grid).
  Widget _buildInstalledDetails({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme scheme,
    required TencentCloudChatThemeColors colorTheme,
    required AppLocalizations appL10n,
    required TextStyle? sectionLabelStyle,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appL10n.ircServerConfig, style: sectionLabelStyle),
            AppSpacing.verticalMd,
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: UiKeys.applicationsIrcServerField,
                    controller: _serverController,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      labelText: appL10n.ircServer,
                      hintText: 'irc.libera.chat',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.input),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    style: TextStyle(color: colorTheme.primaryTextColor),
                  ),
                ),
                AppSpacing.horizontalSm,
                Expanded(
                  flex: 1,
                  child: TextField(
                    key: UiKeys.applicationsIrcPortField,
                    controller: _portController,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      labelText: appL10n.ircPort,
                      hintText: '6667',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.input),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: colorTheme.primaryTextColor),
                  ),
                ),
              ],
            ),
            AppSpacing.verticalSm,
            SwitchListTile(
              title: Text(
                appL10n.ircUseSasl,
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                appL10n.ircUseSaslDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorTheme.secondaryTextColor,
                ),
              ),
              value: _useSasl,
              onChanged: (value) {
                setState(() {
                  _useSasl = value;
                });
              },
              contentPadding: EdgeInsets.zero,
              // Inherit the app-wide Material switchTheme (white thumb on a
              // primary track) so this toggle matches every other switch in the
              // restyled UI instead of rendering a solid-blue thumb.
            ),
            AppSpacing.verticalSm,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: UiKeys.applicationsIrcSaveConfigButton,
                onPressed: _saveIrcConfig,
                icon: const Icon(Icons.save, size: 18),
                label: Text(appL10n.save),
                style: FilledButton.styleFrom(
                  backgroundColor: colorTheme.primaryColor,
                  foregroundColor: colorTheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.button),
                  ),
                ),
              ),
            ),
            if (_channels.isNotEmpty) ...[
              AppSpacing.verticalLg,
              Divider(color: scheme.outlineVariant, height: 1),
              AppSpacing.verticalMd,
              Text(appL10n.ircChannels, style: sectionLabelStyle),
              AppSpacing.verticalSm,
              ..._channels.map(
                (channel) => Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    key: UiKeys.applicationsIrcChannelTile(channel),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(
                      channel,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorTheme.primaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: _channelStatus.containsKey(channel)
                        ? Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Row(
                              children: [
                                _AnimatedStatusDot(
                                  status: _channelStatus[channel]!,
                                  color: _getStatusColor(
                                    _channelStatus[channel]!,
                                    colorTheme,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _getStatusText(
                                    appL10n,
                                    _channelStatus[channel]!,
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: _getStatusColor(
                                      _channelStatus[channel]!,
                                      colorTheme,
                                    ),
                                  ),
                                ),
                                if (_channelStatusMessage[channel] != null) ...[
                                  AppSpacing.horizontalSm,
                                  Expanded(
                                    child: Text(
                                      _channelStatusMessage[channel]!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color:
                                                colorTheme.secondaryTextColor,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : null,
                    trailing: IconButton(
                      key: UiKeys.applicationsIrcRemoveChannelButton(channel),
                      icon: const Icon(Icons.close),
                      onPressed: () => _handleRemoveChannel(channel),
                      color: colorTheme.secondaryTextColor,
                      tooltip: appL10n.remove,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    children: [
                      if (_channelUsers.containsKey(channel) &&
                          _channelUsers[channel]!.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appL10n.ircUsersCount(
                                _channelUsers[channel]!.length,
                              ),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorTheme.primaryTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            AppSpacing.verticalSm,
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: _channelUsers[channel]!
                                  .map(
                                    (user) => Chip(
                                      label: Text(
                                        user,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  colorTheme.primaryTextColor,
                                            ),
                                      ),
                                      backgroundColor: colorTheme.surface,
                                      side: BorderSide(
                                        color: scheme.outlineVariant,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.small,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: AppSpacing.xs,
                                      ),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        )
                      else
                        Text(
                          appL10n.ircNoUsers,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorTheme.secondaryTextColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              AppSpacing.verticalLg,
              EmptyStateWidget(
                icon: Icons.forum_outlined,
                title: appL10n.noIrcChannels,
                subtitle: appL10n.joinChannelToGetStarted,
                action: FilledButton.icon(
                  onPressed: _handleAddChannel,
                  icon: const Icon(Icons.add),
                  label: Text(appL10n.addIrcChannel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Internal value type describing one grid tile in the applications grid.
class _AppCardData {
  const _AppCardData({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.isInstalled,
  });

  final String id;
  final IconData icon;
  final String title;
  final String description;
  final bool isInstalled;
}

/// Card tile with mouse-hover surface tint + tappable splash. The whole
/// card is the tap target; on desktop the cursor flips to pointer on
/// hover and the surface picks up the standard 4% hover overlay so the
/// affordance reads even without a button focus state.
class _HoverableAppCard extends StatefulWidget {
  const _HoverableAppCard({
    super.key,
    required this.child,
    required this.borderColor,
    this.onTap,
  });

  final Widget child;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  State<_HoverableAppCard> createState() => _HoverableAppCardState();
}

class _HoverableAppCardState extends State<_HoverableAppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Use the project hover-surface helper so hover tint is consistent
    // with every other interactive surface in the app.
    final hoverSurface = isDark
        ? AppThemeConfig.hoverSurfaceDark
        : AppThemeConfig.hoverSurfaceLight;
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppCurves.standard,
        decoration: BoxDecoration(
          color: _hovered ? hoverSurface : null,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Card(
          elevation: 0,
          color: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
            side: BorderSide(color: widget.borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: widget.onTap, child: widget.child),
        ),
      ),
    );
  }
}

/// Wraps a sliver in a max-width centered constraint while staying a
/// sliver itself. Centers the underlying sliver and clamps its inner
/// width so the apps grid never stretches across ultrawide desktops.
class _ConstrainedSliver extends StatelessWidget {
  const _ConstrainedSliver({required this.sliver, required this.maxWidth});

  final Widget sliver;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.crossAxisExtent;
        final clamped = available > maxWidth ? maxWidth : available;
        final inset = (available - clamped) / 2;
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          sliver: sliver,
        );
      },
    );
  }
}

/// Status dot that pulses while the channel is in a transient state
/// (connecting / authenticating / reconnecting) and holds steady otherwise.
/// Pulse duration is [AppDurations.medium] in each direction (full cycle ≈
/// 500ms), giving a gentle "this is alive" affordance.
///
/// Respects `MediaQuery.disableAnimationsOf`: when reduced motion is on the
/// pulse is suppressed and the dot is shown at full opacity — the semantic
/// (green / amber / red) still conveys state without animation.
class _AnimatedStatusDot extends StatefulWidget {
  const _AnimatedStatusDot({required this.status, required this.color});
  final int status;
  final Color color;

  @override
  State<_AnimatedStatusDot> createState() => _AnimatedStatusDotState();
}

class _AnimatedStatusDotState extends State<_AnimatedStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Half-cycle of the pulse — repeat(reverse: true) doubles this for the
      // full breath, landing near 500ms which reads as "alive, not anxious".
      duration: AppDurations.medium,
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: AppCurves.standard));
  }

  @override
  void didUpdateWidget(covariant _AnimatedStatusDot old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) {
      // Re-evaluate on next build so we can read MediaQuery for reduced motion.
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isTransient(int s) => s == 1 || s == 3 || s == 4;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_isTransient(widget.status) && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 1.0;
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
