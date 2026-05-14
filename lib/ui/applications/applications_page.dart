import 'dart:async';
import 'package:flutter/material.dart';
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
import 'irc_channel_dialog.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/loading_shimmer.dart';

/// Applications page for extension apps
class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({super.key, required this.service});

  final FfiChatService service;

  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  final _ircAppManager = IrcAppManager();
  bool _isInstalled = false;
  List<String> _channels = [];
  bool _isLoading = false;
  final _serverController = TextEditingController();
  final _portController = TextEditingController();
  bool _useSasl = false;
  
  // IRC status tracking
  final Map<String, int> _channelStatus = {}; // channel -> status (0=disconnected, 1=connecting, 2=connected, etc.)
  final Map<String, String?> _channelStatusMessage = {}; // channel -> status message
  final Map<String, List<String>> _channelUsers = {}; // channel -> list of users
  StreamSubscription? _connectionStatusSub;
  StreamSubscription? _userListSub;
  StreamSubscription? _userJoinPartSub;

  @override
  void initState() {
    super.initState();
    _loadAppState();
    _setupIrcListeners();
  }
  
  void _setupIrcListeners() {
    // Listen to connection status updates
    _connectionStatusSub = widget.service.ircConnectionStatusStream.listen((event) {
      if (mounted) {
        setState(() {
          _channelStatus[event.channel] = event.status;
          _channelStatusMessage[event.channel] = event.message;
        });
      }
    });
    
    // Listen to user list updates
    _userListSub = widget.service.ircUserListStream.listen((event) {
      if (mounted) {
        setState(() {
          _channelUsers[event.channel] = event.users;
        });
      }
    });
    
    // Listen to user join/part events
    _userJoinPartSub = widget.service.ircUserJoinPartStream.listen((event) {
      if (mounted) {
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
        
        // Show notification
        final appL10n = AppLocalizations.of(context)!;
        if (mounted) {
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
        }
      }
    });
  }

  Future<void> _loadAppState() async {
    await _ircAppManager.init();
    await _ircAppManager.restoreChannelMappings(widget.service);
    final server = await Prefs.getIrcServer();
    final port = await Prefs.getIrcPort();
    final useSasl = await Prefs.getIrcUseSasl();
    if (mounted) {
      setState(() {
        _isInstalled = _ircAppManager.isInstalled;
        _channels = _ircAppManager.channels;
        _serverController.text = server;
        _portController.text = port.toString();
        _useSasl = useSasl;
      });
    }
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
  
  String _getStatusText(int status) {
    switch (status) {
      case 0: return 'Disconnected';
      case 1: return 'Connecting';
      case 2: return 'Connected';
      case 3: return 'Authenticating';
      case 4: return 'Reconnecting';
      case 5: return 'Error';
      default: return 'Unknown';
    }
  }
  
  Color _getStatusColor(int status, TencentCloudChatThemeColors colorTheme) {
    switch (status) {
      case 0: return colorTheme.secondaryTextColor;
      case 1: return colorTheme.secondButtonColor;
      case 2: return colorTheme.primaryColor;
      case 3: return colorTheme.primaryColor;
      case 4: return colorTheme.secondButtonColor;
      case 5: return colorTheme.tipsColor;
      default: return colorTheme.secondaryTextColor;
    }
  }

  Future<void> _saveIrcConfig() async {
    final server = _serverController.text.trim();
    final portStr = _portController.text.trim();
    final port = int.tryParse(portStr) ?? 6667;
    
    if (server.isEmpty) {
      final appL10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appL10n.ircServerRequired)),
      );
      return;
    }
    
    await Prefs.setIrcServer(server);
    await Prefs.setIrcPort(port);
    await Prefs.setIrcUseSasl(_useSasl);
    
    if (mounted) {
      final appL10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appL10n.ircConfigSaved)),
      );
    }
  }

  Future<void> _handleInstall() async {
    setState(() => _isLoading = true);
    try {
      await _ircAppManager.install(widget.service);
      if (mounted) {
        setState(() {
          _isInstalled = true;
        });
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appL10n.ircAppInstalled),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${appL10n.failed}: $e'),
          ),
        );
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
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appL10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appL10n.uninstall),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      // Get all group IDs before uninstalling (uninstall clears the mappings)
      final groupIds = <String>[];
      for (final channel in _channels) {
        final groupId = _ircAppManager.getGroupIdForChannel(channel);
        if (groupId != null) {
          groupIds.add(groupId);
        }
      }
      
      // Uninstall the app (this will quit all groups)
      await _ircAppManager.uninstall(widget.service);
      
      if (mounted) {
        setState(() {
          _isInstalled = false;
          _channels = [];
        });
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appL10n.ircAppUninstalled),
          ),
        );
        
        // Clear message buffers and emit deletion events for all IRC groups
        for (final groupId in groupIds) {
          final conversationID = 'group_$groupId';
          FakeUIKit.instance.messageProvider?.clearMessageBuffer(conversationID);
          // Emit group deletion event to remove from conversation list
          FakeUIKit.instance.eventBusInstance.emit(
            FakeIM.topicGroupDeleted,
            FakeGroupDeleted(groupID: groupId),
          );
        }
        // Refresh conversations to ensure consistency
        await FakeUIKit.instance.im?.refreshConversations();
      }
    } catch (e) {
      if (mounted) {
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${appL10n.failed}: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleAddChannel() async {
    final result = await showDialog<({String channel, String? password, String? nickname})>(
      context: context,
      builder: (context) => const IrcChannelDialog(),
    );

    if (result == null || result.channel.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final groupId = await _ircAppManager.addChannel(
        result.channel,
        widget.service,
        password: result.password,
        customNickname: result.nickname,
      );
      if (groupId != null) {
        if (mounted) {
          setState(() {
            _channels = _ircAppManager.channels;
          });
          final appL10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appL10n.ircChannelAdded(result.channel)),
            ),
          );
          // Refresh conversations to show the new group
          await FakeUIKit.instance.im?.refreshConversations();
        }
      } else {
        if (mounted) {
          final appL10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appL10n.ircChannelAddFailed),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${appL10n.failed}: $e'),
          ),
        );
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
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appL10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appL10n.remove),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      // Get group ID BEFORE removing channel (removeChannel clears the mapping)
      final groupId = _ircAppManager.getGroupIdForChannel(channel);
      
      // Remove the channel
      await _ircAppManager.removeChannel(channel, widget.service);
      
      if (mounted) {
        setState(() {
          _channels = _ircAppManager.channels;
        });
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appL10n.ircChannelRemoved(channel)),
          ),
        );
        
        // Clear message buffer and emit deletion event if group ID exists
        if (groupId != null) {
          // Clear message buffer for the removed group
          final conversationID = 'group_$groupId';
          FakeUIKit.instance.messageProvider?.clearMessageBuffer(conversationID);
          // Emit group deletion event to remove from conversation list
          // This must be done to immediately remove it from the UI
          FakeUIKit.instance.eventBusInstance.emit(
            FakeIM.topicGroupDeleted,
            FakeGroupDeleted(groupID: groupId),
          );
        }
        // Refresh conversations to ensure consistency
        await FakeUIKit.instance.im?.refreshConversations();
      }
    } catch (e) {
      if (mounted) {
        final appL10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${appL10n.failed}: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
        return Scaffold(
          backgroundColor: colorTheme.surface,
          appBar: AppBar(
            title: Text(appL10n.applications),
            backgroundColor: colorTheme.appBarBackgroundColor,
            foregroundColor: colorTheme.primaryTextColor,
            elevation: 0,
          ),
          body: SafeArea(
            child: _isLoading
              ? const LoadingShimmer(itemCount: 6, itemHeight: 72)
              : RefreshIndicator(
                  color: colorTheme.primaryColor,
                  onRefresh: _loadAppState,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                    // IRC Channel App Card
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: colorTheme.primaryColor.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                                    border: Border.all(
                                      color: colorTheme.primaryColor.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_outline,
                                    color: colorTheme.primaryColor,
                                    size: 24,
                                  ),
                                ),
                                AppSpacing.horizontalMd,
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        appL10n.ircChannelApp,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          color: colorTheme.primaryTextColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        appL10n.ircChannelAppDesc,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorTheme.secondaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            AppSpacing.verticalLg,
                            if (!_isInstalled)
                              ElevatedButton.icon(
                                onPressed: _handleInstall,
                                icon: const Icon(Icons.install_mobile),
                                label: Text(appL10n.install),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorTheme.primaryColor,
                                  foregroundColor: colorTheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                                  ),
                                ),
                              )
                            else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _handleUninstall,
                                      icon: const Icon(Icons.delete_outline),
                                      label: Text(appL10n.uninstall),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: colorTheme.primaryColor,
                                        side: BorderSide(color: scheme.outlineVariant),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                                        ),
                                      ),
                                    ),
                                  ),
                                  AppSpacing.horizontalSm,
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _handleAddChannel,
                                      icon: const Icon(Icons.add),
                                      label: Text(appL10n.addIrcChannel),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: colorTheme.primaryColor,
                                        foregroundColor: colorTheme.onPrimary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // IRC Server Configuration
                              AppSpacing.verticalLg,
                              Divider(color: scheme.outlineVariant, height: 1),
                              AppSpacing.verticalMd,
                              Text(
                                appL10n.ircServerConfig,
                                style: sectionLabelStyle,
                              ),
                              AppSpacing.verticalMd,
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _serverController,
                                      textAlignVertical: TextAlignVertical.center,
                                      decoration: InputDecoration(
                                        labelText: appL10n.ircServer,
                                        hintText: 'irc.libera.chat',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                                      ),
                                      style: TextStyle(color: colorTheme.primaryTextColor),
                                    ),
                                  ),
                                  AppSpacing.horizontalSm,
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: _portController,
                                      textAlignVertical: TextAlignVertical.center,
                                      decoration: InputDecoration(
                                        labelText: appL10n.ircPort,
                                        hintText: '6667',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                                      ),
                                      keyboardType: TextInputType.number,
                                      style: TextStyle(color: colorTheme.primaryTextColor),
                                    ),
                                  ),
                                ],
                              ),
                              AppSpacing.verticalSm,
                              SwitchListTile(
                                title: Text(appL10n.ircUseSasl, style: theme.textTheme.bodyMedium),
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
                                activeColor: colorTheme.primaryColor,
                              ),
                              AppSpacing.verticalSm,
                              ElevatedButton.icon(
                                onPressed: _saveIrcConfig,
                                icon: const Icon(Icons.save, size: 18),
                                label: Text(appL10n.save),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorTheme.primaryColor,
                                  foregroundColor: colorTheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                                  ),
                                ),
                              ),
                              if (_channels.isNotEmpty) ...[
                                AppSpacing.verticalLg,
                                Divider(color: scheme.outlineVariant, height: 1),
                                AppSpacing.verticalMd,
                                Text(
                                  appL10n.ircChannels,
                                  style: sectionLabelStyle,
                                ),
                                AppSpacing.verticalSm,
                                ..._channels.map((channel) => Container(
                                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
                                        border: Border.all(color: scheme.outlineVariant),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: ExpansionTile(
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
                                                      color: _getStatusColor(_channelStatus[channel]!, colorTheme),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      _getStatusText(_channelStatus[channel]!),
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: _getStatusColor(_channelStatus[channel]!, colorTheme),
                                                      ),
                                                    ),
                                                    if (_channelStatusMessage[channel] != null) ...[
                                                      AppSpacing.horizontalSm,
                                                      Expanded(
                                                        child: Text(
                                                          _channelStatusMessage[channel]!,
                                                          style: theme.textTheme.bodySmall?.copyWith(
                                                            color: colorTheme.secondaryTextColor,
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
                                          // User list
                                          if (_channelUsers.containsKey(channel) && _channelUsers[channel]!.isNotEmpty)
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Users (${_channelUsers[channel]!.length})',
                                                  style: theme.textTheme.labelLarge?.copyWith(
                                                    color: colorTheme.primaryTextColor,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                AppSpacing.verticalSm,
                                                Wrap(
                                                  spacing: AppSpacing.sm,
                                                  runSpacing: AppSpacing.xs,
                                                  children: _channelUsers[channel]!.map((user) => Chip(
                                                    label: Text(
                                                      user,
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: colorTheme.primaryTextColor,
                                                      ),
                                                    ),
                                                    backgroundColor: colorTheme.surface,
                                                    side: BorderSide(color: scheme.outlineVariant),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(AppThemeConfig.badgeBorderRadius),
                                                    ),
                                                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  )).toList(),
                                                ),
                                              ],
                                            )
                                          else
                                            Text(
                                              'No users',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: colorTheme.secondaryTextColor,
                                              ),
                                            ),
                                        ],
                                      ),
                                    )),
                              ] else ...[
                                AppSpacing.verticalLg,
                                const EmptyStateWidget(
                                  icon: Icons.forum_outlined,
                                  title: 'No IRC channels',
                                  subtitle: 'Join a channel to get started',
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        );
      },
    );
  }
}

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
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedStatusDot old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.status == 1 || widget.status == 3 || widget.status == 4) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

