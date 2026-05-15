import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/data/contact/tencent_cloud_chat_contact_data.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_tatal_unread_count.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../../util/app_theme_config.dart';
import '../../util/prefs.dart';
import '../../i18n/app_localizations.dart';
import '../profile_page.dart';

/// 临时屏蔽 sidebar 的「应用」入口，改为 true 可恢复显示
const bool _showApplicationsEntry = false;

Widget buildSidebar({
  required BuildContext context,
  required int selectedIndex,
  required void Function(int) onTap,
  required FfiChatService service,
  required Stream<bool> connectionStatusStream,
}) {
  final scheme = Theme.of(context).colorScheme;
  return TencentCloudChatThemeWidget(
    build: (context, colorTheme, textStyle) => SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorTheme.desktopBackgroundColorLinearGradientOne,
              colorTheme.desktopBackgroundColorLinearGradientTwo,
              colorTheme.desktopBackgroundColorLinearGradientOne,
            ],
          ),
          border: Border(
            right: BorderSide(color: scheme.outlineVariant, width: 1),
          ),
        ),
        child: Column(
          children: [
            // User avatar at the top
            _UserAvatar(
              service: service,
              connectionStatusStream: connectionStatusStream,
            ),
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            AppSpacing.verticalSm,
            _SidebarItem(
              context: context,
              selected: selectedIndex == 0,
              icon: Icons.chat_bubble_outline,
              label:
                  TencentCloudChatLocalizations.of(context)?.chats ?? 'Chats',
              onTap: () => onTap(0),
              showUnreadCount: true,
            ),
            _ContactSidebarItem(
              context: context,
              selected: selectedIndex == 1,
              icon: Icons.contacts,
              label: TencentCloudChatLocalizations.of(context)?.contacts ??
                  'Contacts',
              onTap: () => onTap(1),
            ),
            if (_showApplicationsEntry)
              _SidebarItem(
                context: context,
                selected: selectedIndex == 2,
                icon: Icons.apps,
                label: AppLocalizations.of(context)?.applications ??
                    'Applications',
                onTap: () => onTap(2),
              ),
            const Spacer(),
            _SidebarItem(
              context: context,
              selected: selectedIndex == 3,
              icon: Icons.settings,
              label: TencentCloudChatLocalizations.of(context)?.settings ??
                  'Settings',
              onTap: () => onTap(3),
            ),
            AppSpacing.verticalSm,
          ],
        ),
      ),
    ),
  );
}

class _UserAvatar extends StatefulWidget {
  const _UserAvatar({
    required this.service,
    required this.connectionStatusStream,
  });

  final FfiChatService service;
  final Stream<bool> connectionStatusStream;

  @override
  State<_UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<_UserAvatar> {
  String? _nickname; // Used for avatar display
  String? _avatarPath;
  int _avatarVersion = 0;
  StreamSubscription<String>? _avatarUpdatedSubscription;
  final _nickController = TextEditingController();
  final _statusController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _avatarUpdatedSubscription =
        widget.service.avatarUpdated.listen((updatedUserId) {
      final selfId = widget.service.selfId;
      if (selfId.isEmpty) return;
      final normalizedSelf =
          selfId.length > 64 ? selfId.substring(0, 64) : selfId;
      final normalizedUpdated = updatedUserId.length > 64
          ? updatedUserId.substring(0, 64)
          : updatedUserId;
      if (updatedUserId == selfId ||
          updatedUserId == normalizedSelf ||
          normalizedUpdated == normalizedSelf) {
        _loadProfile();
      }
    });
  }

  @override
  void dispose() {
    _avatarUpdatedSubscription?.cancel();
    _nickController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final nick = await Prefs.getNickname();
    final status = await Prefs.getStatusMessage();
    final avatar = await Prefs.getAvatarPath();
    if (mounted) {
      setState(() {
        _nickname = nick;
        if (nick != null) _nickController.text = nick;
        if (status != null) _statusController.text = status;
        _avatarPath = avatar;
        _avatarVersion++;
      });
    }
  }

  void _showProfileDialog(BuildContext context) {
    // Debug: Check current connection status
    final currentStatus = widget.service.isConnected;
    showDialog(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final isWide = size.width > 900;
        final maxW = (size.width - 32).clamp(280.0, isWide ? 680.0 : 500.0);
        final maxH = (size.height - 100).clamp(400.0, 800.0);
        return Dialog(
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(AppThemeConfig.cardBorderRadius),
            child: SizedBox(
              width: maxW,
              height: maxH,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: SizedBox(
                      width: (maxW - 48).clamp(256.0, 440.0),
                      height: (maxH - 40).clamp(360.0, 760.0),
                      child: ProfilePage(
                        userId: widget.service.selfId,
                        nickName: _nickname,
                        statusMessage: _statusController.text,
                        isEditable: true,
                        online:
                            currentStatus, // Pass current status as initial value
                        connectionStatusStream: widget.connectionStatusStream,
                        onSave: (nickname, statusMessage) async {
                          await widget.service.updateSelfProfile(
                            nickname: nickname,
                            statusMessage: statusMessage,
                          );
                          await Prefs.setNickname(nickname);
                          await Prefs.setStatusMessage(statusMessage);
                          // Update local state after save
                          if (mounted) {
                            setState(() {
                              _nickname = nickname;
                              _nickController.text = nickname;
                              _statusController.text = statusMessage;
                            });
                          }
                        },
                        onAvatarChanged: (path) async {
                          if (path != null && path.isNotEmpty) {
                            await FileImage(File(path)).evict();
                          }
                          if (mounted) {
                            setState(() {
                              _avatarPath = path;
                              _avatarVersion++;
                            });
                          }
                          if (path != null && path.isNotEmpty) {
                            await Prefs.setAvatarPath(path);
                            // Update avatar in service (will send to all friends if changed)
                            await widget.service.updateAvatar(path);
                          } else {
                            // Avatar removed
                            await Prefs.setAvatarPath(null);
                            await widget.service.updateAvatar(null);
                          }
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        return InkWell(
          onTap: () => _showProfileDialog(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.lg,
              horizontal: AppSpacing.sm,
            ),
            child: StreamBuilder<bool>(
              stream: widget.connectionStatusStream,
              initialData: widget.service
                  .isConnected, // Use current connection status as initial data
              builder: (context, snapshot) {
                final isConnected = snapshot.data ?? widget.service.isConnected;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Use CircleAvatar; when no avatar, use same default as chat (UIKit)
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: colorTheme.primaryColor,
                          child: _avatarPath != null &&
                                  _avatarPath!.isNotEmpty &&
                                  File(_avatarPath!).existsSync()
                              ? ClipOval(
                                  child: Image.file(
                                    File(_avatarPath!),
                                    key: ValueKey(
                                        'sidebar-avatar-${_avatarPath!}-$_avatarVersion'),
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : ClipOval(
                                  child: Image.asset(
                                    'images/default_user_icon.png',
                                    package: 'tencent_cloud_chat_common',
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                        ),
                        // Status indicator — sits on the bottom-right edge of
                        // the avatar. Avatar radius is 28 (diameter 56); the
                        // 12px dot is offset so its center lands on the rim.
                        // Color goes through AppThemeConfig semantic tokens:
                        // emerald for connected, muted secondary for offline.
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isConnected
                                  ? AppThemeConfig.successColor
                                  : colorTheme.secondaryTextColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorTheme.backgroundColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Display nickname below avatar
                    if (_nickname != null && _nickname!.isNotEmpty) ...[
                      AppSpacing.verticalSm,
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          _nickname!,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorTheme.primaryTextColor,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      AppSpacing.verticalXs,
                      Text(
                        isConnected
                            ? (AppLocalizations.of(context)?.statusOnline ?? 'Online')
                            : (AppLocalizations.of(context)?.statusOffline ?? 'Offline'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isConnected
                              ? AppThemeConfig.successColor
                              : colorTheme.secondaryTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.context,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.showUnreadCount = false,
  });

  final BuildContext context;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showUnreadCount;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final baseColor = colorTheme.secondaryTextColor;
        final selColor = colorTheme.primaryColor;
        // Modern-messenger selection: subtle primary-tinted pill plus a
        // 3px left-edge accent bar. Hover stays restrained — outlineVariant
        // tone, no primary tint, so it doesn't read as a half-selection.
        final bg = widget.selected
            ? colorTheme.primaryColor.withValues(alpha: 0.10)
            : (_isHovered
                ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
                : Colors.transparent);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: InkWell(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
                horizontal: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  left: BorderSide(
                    color: widget.selected ? selColor : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        widget.icon,
                        size: 22,
                        color: widget.selected ? selColor : baseColor,
                      ),
                      if (widget.showUnreadCount)
                        Positioned(
                          top: -5,
                          right: -6,
                          child: UnconstrainedBox(
                            child: TencentCloudChatConversationTotalUnreadCount(
                              builder: (BuildContext _, int totalUnreadCount) {
                                if (totalUnreadCount == 0) {
                                  return Container();
                                }
                                final displayText = totalUnreadCount > 99
                                    ? "99+"
                                    : "$totalUnreadCount";
                                final isLargeText = displayText.length > 2;
                                return UnconstrainedBox(
                                  child: Container(
                                    width: isLargeText
                                        ? 26
                                        : (displayText.length == 1 ? 16 : 20),
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: colorTheme.tipsColor,
                                      shape: isLargeText
                                          ? BoxShape.rectangle
                                          : BoxShape.circle,
                                      borderRadius: isLargeText
                                          ? BorderRadius.circular(
                                              AppThemeConfig.badgeBorderRadius)
                                          : null,
                                    ),
                                    child: Center(
                                      child: Text(
                                        displayText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          height: 1.0,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  AppSpacing.verticalXs,
                  Text(
                    widget.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: widget.selected ? selColor : baseColor,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
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

class _ContactSidebarItem extends StatefulWidget {
  const _ContactSidebarItem({
    required this.context,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final BuildContext context;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ContactSidebarItem> createState() => _ContactSidebarItemState();
}

class _ContactSidebarItemState extends State<_ContactSidebarItem> {
  StreamSubscription<TencentCloudChatContactData<dynamic>>? _contactDataSub;
  int _applicationUnreadCount = 0;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    // Listen to contact data changes to get application unread count
    final contactDataStream = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatContactData<dynamic>>(
            "TencentCloudChatContactData");
    _contactDataSub = contactDataStream?.listen((data) {
      if (data.currentUpdatedFields ==
              TencentCloudChatContactDataKeys.applicationCount ||
          data.currentUpdatedFields ==
              TencentCloudChatContactDataKeys.applicationList) {
        if (mounted) {
          setState(() {
            _applicationUnreadCount = data.applicationUnreadCount;
          });
        }
      }
    });
    // Get initial count
    _applicationUnreadCount =
        TencentCloudChat.instance.dataInstance.contact.applicationUnreadCount;
  }

  @override
  void dispose() {
    _contactDataSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final baseColor = colorTheme.secondaryTextColor;
        final selColor = colorTheme.primaryColor;
        final bg = widget.selected
            ? colorTheme.primaryColor.withValues(alpha: 0.10)
            : (_isHovered
                ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
                : Colors.transparent);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: InkWell(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
                horizontal: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  left: BorderSide(
                    color: widget.selected ? selColor : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        widget.icon,
                        size: 22,
                        color: widget.selected ? selColor : baseColor,
                      ),
                      if (_applicationUnreadCount > 0)
                        Positioned(
                          top: -5,
                          right: -6,
                          child: UnconstrainedBox(
                            child: Builder(
                              builder: (context) {
                                final displayText = _applicationUnreadCount > 99
                                    ? "99+"
                                    : "$_applicationUnreadCount";
                                final isLargeText = displayText.length > 2;
                                return Container(
                                  width: isLargeText
                                      ? 26
                                      : (displayText.length == 1 ? 16 : 20),
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: colorTheme.tipsColor,
                                    shape: isLargeText
                                        ? BoxShape.rectangle
                                        : BoxShape.circle,
                                    borderRadius: isLargeText
                                        ? BorderRadius.circular(
                                            AppThemeConfig.badgeBorderRadius)
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      displayText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        height: 1.0,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  AppSpacing.verticalXs,
                  Text(
                    widget.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: widget.selected ? selColor : baseColor,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
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
