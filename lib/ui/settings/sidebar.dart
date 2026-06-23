import 'dart:async';

// ignore: directives_ordering
import '../widgets/safe_dialog_pop.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/data/contact/tencent_cloud_chat_contact_data.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_tatal_unread_count.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../../util/ffi_chat_service_account_key.dart';
import '../../sdk_fake/uikit_data_facade.dart';
import '../../util/app_theme_config.dart';
import '../../util/design_tokens.dart';
import '../../util/prefs.dart';
import '../../util/responsive_layout.dart';
import '../../i18n/app_localizations.dart';
import '../profile_page.dart';
import '../testing/ui_keys.dart';

/// 临时屏蔽 sidebar 的「应用」入口，改为 true 可恢复显示
const bool _showApplicationsEntry = false;

/// Opens the current user's profile.
///
/// Phone/large-phone: pushes a fullscreen `MaterialPageRoute` with a back
/// action — gives SafeArea, native pop gesture, and avoids keyboard occlusion
/// on the dialog form fields. Desktop/tablet: routes through `showDialog`
/// with the existing close-button affordance.
///
/// Shared between the desktop `_UserAvatar` tap and the mobile drawer header
/// tap so both entry points present identically. `nickName` and
/// `statusMessage` seed the form; `onProfileSaved` and `onAvatarChanged` let
/// the caller propagate updates back into its own state (e.g. drawer header
/// avatar refresh, sidebar nickname refresh).
///
/// Returns a `Future` because the displayed User ID must be the real Tox ID
/// from `Prefs.getCurrentAccountToxId()` rather than UIKit's
/// `FlutterUIKitClient` placeholder (`service.selfId`); callers that
/// fire-and-forget should wrap with `unawaited(...)`.
Future<void> showSelfProfile(
  BuildContext context,
  FfiChatService service,
  Stream<bool> connectionStatusStream, {
  String? nickName,
  String? statusMessage,
  Future<void> Function(String nickname, String statusMessage)? onProfileSaved,
  ValueChanged<String?>? onAvatarChanged,
}) async {
  final initialOnline = service.isConnected;

  // The visible User ID must be the real Tox ID, not UIKit's
  // `FlutterUIKitClient` placeholder that `service.selfId` returns at the
  // UIKit boundary. Fall back to `service.selfId` only if Prefs hasn't been
  // populated yet (login race — rare).
  final storedToxId = await Prefs.getCurrentAccountToxId();
  final resolvedUserId = (storedToxId != null && storedToxId.isNotEmpty)
      ? storedToxId
      : service.accountKey;

  if (!context.mounted) return;

  ProfilePage buildProfile() => ProfilePage(
    userId: resolvedUserId,
    nickName: nickName,
    statusMessage: statusMessage,
    isEditable: true,
    online: initialOnline,
    connectionStatusStream: connectionStatusStream,
    onSave: (newNickname, newStatusMessage) async {
      await service.updateSelfProfile(
        nickname: newNickname,
        statusMessage: newStatusMessage,
      );
      await Prefs.setNickname(newNickname);
      await Prefs.setStatusMessage(newStatusMessage);
      // Mirror into account_list so AccountSwitcher / cold-start auto-login
      // don't re-apply the stale nickname/statusMessage on next switch.
      await Prefs.addAccount(
        toxId: resolvedUserId,
        nickname: newNickname,
        statusMessage: newStatusMessage,
        updateLastLogin: false,
      );
      if (onProfileSaved != null) {
        await onProfileSaved(newNickname, newStatusMessage);
      }
    },
    onAvatarChanged: (path) async {
      if (path != null && path.isNotEmpty) {
        await FileImage(File(path)).evict();
        await Prefs.setAvatarPath(path);
        await service.updateAvatar(path);
      } else {
        await Prefs.setAvatarPath(null);
        await service.updateAvatar(null);
      }
      // Same reason as onSave: account_list must track per-account avatar
      // or AccountSwitcher will restore the stale path on switch. Stored
      // as '' for "no avatar" — isNotEmpty check on read normalizes back.
      await Prefs.addAccount(
        toxId: resolvedUserId,
        avatarPath: path ?? '',
        updateLastLogin: false,
      );
      onAvatarChanged?.call(path);
    },
  );

  if (ResponsiveLayout.shouldShowBottomNav(context)) {
    final title =
        TencentCloudChatLocalizations.of(context)?.profile ?? 'Profile';
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (routeContext) => Scaffold(
            appBar: AppBar(
              title: Text(title),
              leading: IconButton(
                key: UiKeys.profileCloseButton,
                icon: const Icon(Icons.close),
                tooltip: AppLocalizations.of(routeContext)?.close ?? 'Close',
                onPressed: () => Navigator.of(routeContext).maybePop(),
              ),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: buildProfile(),
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  unawaited(
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final isWide = size.width > 900;
        // Wide screens get a dialog wide enough to host the 2-column profile
        // layout (form + QR card side-by-side); narrow screens keep the
        // single-column dialog at ~480.
        final maxW = (size.width - 32).clamp(280.0, isWide ? 880.0 : 500.0);
        final maxH = (size.height - 100).clamp(400.0, 800.0);
        return Dialog(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
            // `ConstrainedBox` (vs `SizedBox`) so the dialog hugs the profile
            // content when it's shorter than `maxH` — the previous fixed-height
            // `SizedBox` left ~300px of empty space below the form on normal
            // desktop windows. The `Stack` sizes to its largest non-Positioned
            // child (the profile content), and the close-button `Positioned`
            // still overlays correctly. Content taller than `maxH` scrolls via
            // `ProfileLayout`'s internal `SingleChildScrollView`.
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    // Inner width caps the profile column at the dialog's
                    // ceiling minus padding; no fixed `height:` so the column
                    // collapses to its intrinsic size when content is shorter
                    // than the dialog ceiling.
                    child: SizedBox(
                      width: (maxW - 48).clamp(256.0, 840.0),
                      child: buildProfile(),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      key: UiKeys.profileCloseButton,
                      icon: const Icon(Icons.close),
                      tooltip:
                          AppLocalizations.of(dialogContext)?.close ?? 'Close',
                      onPressed: () => popDialogIfCurrent(dialogContext),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Widget buildSidebar({
  required BuildContext context,
  required int selectedIndex,
  required void Function(int) onTap,
  required FfiChatService service,
  required Stream<bool> connectionStatusStream,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // Reference-design rail: flat single-tone surface (no gradient), with a
  // hairline divider on the trailing edge. Person avatar stays circular.
  final railColor = isDark ? DesignTokens.railDark : DesignTokens.railLight;
  final dividerColor = isDark
      ? DesignTokens.dividerDark
      : DesignTokens.dividerLight;
  return TencentCloudChatThemeWidget(
    build: (context, colorTheme, textStyle) => SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: railColor,
          border: Border(right: BorderSide(color: dividerColor, width: 1)),
        ),
        child: Column(
          children: [
            // macOS frameless window: the native traffic lights overlay the
            // top-left of the rail. Reserve the space INSIDE this coloured
            // container so the rail background fills behind the lights (no
            // seam / mismatched top strip) and the avatar sits clear of them.
            if (Platform.isMacOS)
              const SizedBox(
                height: ResponsiveLayout.macTitleBarReservedHeight,
              ),
            // User avatar at the top
            _UserAvatar(
              service: service,
              connectionStatusStream: connectionStatusStream,
            ),
            AppSpacing.verticalMd,
            _SidebarItem(
              key: UiKeys.sidebarChats,
              context: context,
              selected: selectedIndex == 0,
              icon: Icons.chat_bubble_outline,
              label:
                  TencentCloudChatLocalizations.of(context)?.chats ?? 'Chats',
              onTap: () => onTap(0),
              showUnreadCount: true,
            ),
            _ContactSidebarItem(
              key: UiKeys.sidebarContacts,
              context: context,
              selected: selectedIndex == 1,
              icon: Icons.contacts,
              label:
                  TencentCloudChatLocalizations.of(context)?.contacts ??
                  'Contacts',
              onTap: () => onTap(1),
            ),
            if (_showApplicationsEntry)
              _SidebarItem(
                key: UiKeys.sidebarApplications,
                context: context,
                selected: selectedIndex == 2,
                icon: Icons.apps,
                label:
                    AppLocalizations.of(context)?.applications ??
                    'Applications',
                onTap: () => onTap(2),
              ),
            const Spacer(),
            _SidebarItem(
              key: UiKeys.sidebarSettings,
              context: context,
              selected: selectedIndex == 3,
              icon: Icons.settings,
              label:
                  TencentCloudChatLocalizations.of(context)?.settings ??
                  'Settings',
              onTap: () => onTap(3),
            ),
            AppSpacing.verticalLg,
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
  // Cached existence check — refreshed on every avatar load so the build()
  // path doesn't call `File.existsSync` every frame.
  bool _avatarFileExists = false;
  int _avatarVersion = 0;
  StreamSubscription<String>? _avatarUpdatedSubscription;
  final _nickController = TextEditingController();
  final _statusController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _avatarUpdatedSubscription = widget.service.avatarUpdated.listen((
      updatedUserId,
    ) {
      final selfId = widget.service.selfId;
      if (selfId.isEmpty) return;
      final normalizedSelf = selfId.length > 64
          ? selfId.substring(0, 64)
          : selfId;
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
    final exists =
        avatar != null && avatar.isNotEmpty && await File(avatar).exists();
    if (mounted) {
      setState(() {
        _nickname = nick;
        if (nick != null) _nickController.text = nick;
        if (status != null) _statusController.text = status;
        _avatarPath = avatar;
        _avatarFileExists = exists;
        _avatarVersion++;
      });
    }
  }

  void _openProfile(BuildContext context) {
    // `showSelfProfile` is async because it resolves the real Tox ID from
    // Prefs before opening the dialog; the tap handler is fire-and-forget.
    unawaited(
      showSelfProfile(
        context,
        widget.service,
        widget.connectionStatusStream,
        nickName: _nickname,
        statusMessage: _statusController.text,
        onProfileSaved: (nickname, statusMessage) async {
          if (mounted) {
            setState(() {
              _nickname = nickname;
              _nickController.text = nickname;
              _statusController.text = statusMessage;
            });
          }
        },
        onAvatarChanged: (path) async {
          // Re-check existence on the new path so the avatar existence cache
          // stays accurate.
          final exists =
              path != null && path.isNotEmpty && await File(path).exists();
          if (mounted) {
            setState(() {
              _avatarPath = path;
              _avatarFileExists = exists;
              _avatarVersion++;
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Tooltip(
            message: _nickname ?? '',
            child: InkWell(
              key: UiKeys.sidebarUserAvatar,
              onTap: () => _openProfile(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                child: StreamBuilder<bool>(
                  stream: widget.connectionStatusStream,
                  initialData: widget
                      .service
                      .isConnected, // Use current connection status as initial data
                  builder: (context, snapshot) {
                    final isConnected =
                        snapshot.data ?? widget.service.isConnected;
                    return Row(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            // Use CircleAvatar; when no avatar, use same default as chat (UIKit)
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: colorTheme.primaryColor,
                              child:
                                  _avatarPath != null &&
                                      _avatarPath!.isNotEmpty &&
                                      _avatarFileExists
                                  ? ClipOval(
                                      child: Image.file(
                                        File(_avatarPath!),
                                        key: ValueKey(
                                          'sidebar-avatar-${_avatarPath!}-$_avatarVersion',
                                        ),
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        // 44pt × 3× DPR = 132px raster — caps the
                                        // decoded buffer instead of decoding the
                                        // source avatar file at full resolution.
                                        cacheWidth: 132,
                                        cacheHeight: 132,
                                      ),
                                    )
                                  : ClipOval(
                                      child: Image.asset(
                                        'images/default_user_icon.png',
                                        package: 'tencent_cloud_chat_common',
                                        width: 44,
                                        height: 44,
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
                                width: 10,
                                height: 10,
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
                        const SizedBox(width: 14),
                        if (_nickname != null && _nickname!.isNotEmpty)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _nickname!,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorTheme.primaryTextColor,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isConnected
                                      ? (AppLocalizations.of(
                                              context,
                                            )?.statusOnline ??
                                            'Online')
                                      : (AppLocalizations.of(
                                              context,
                                            )?.statusOffline ??
                                            'Offline'),
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
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    super.key,
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
    final isDark = theme.brightness == Brightness.dark;
    final disableAnims = MediaQuery.disableAnimationsOf(context);
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        // Reference-design rail item: idle icon/label use the secondary text
        // tone; the active tab switches to the brand blue. Both come from
        // DesignTokens (toxee owns this widget) for an exact palette match.
        final baseColor = isDark
            ? DesignTokens.textSecondaryDark
            : DesignTokens.textSecondaryLight;
        const selColor = DesignTokens.primary;
        // Modern-messenger selection: subtle primary-tinted fill plus a
        // 3px left-edge accent bar. Hover stays restrained — onSurface tone,
        // no primary tint, so it doesn't read as a half-selection.
        final bg = widget.selected
            ? (isDark
                  ? DesignTokens.primaryTintDark
                  : DesignTokens.primaryTintLight)
            : (_isHovered
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
                  : Colors.transparent);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: disableAnims ? Duration.zero : AppDurations.fast,
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 18,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          widget.icon,
                          size: 23,
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
                                    return const SizedBox.shrink();
                                  }
                                  final displayText = totalUnreadCount > 99
                                      ? "99+"
                                      : "$totalUnreadCount";
                                  // Constraint-based sizing instead of fixed
                                  // pixel widths — matches the bottom-nav
                                  // badge in home_page.dart and lets text
                                  // scale gracefully.
                                  return Semantics(
                                    label:
                                        AppLocalizations.of(
                                          context,
                                        )?.unreadMessagesSemantics(
                                          totalUnreadCount,
                                        ) ??
                                        'Unread messages: $totalUnreadCount',
                                    container: true,
                                    child: ExcludeSemantics(
                                      child: UnconstrainedBox(
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            minWidth: 16,
                                          ),
                                          height: 16,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.xs,
                                          ),
                                          decoration: BoxDecoration(
                                            color: DesignTokens.unreadBadge,
                                            borderRadius: BorderRadius.circular(
                                              AppThemeConfig.badgeBorderRadius,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              displayText,
                                              // Automation-only: present only
                                              // while totalUnreadCount > 0; its
                                              // data is the rendered count.
                                              key: UiKeys
                                                  .sidebarChatsUnreadBadge,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: DesignTokens
                                                        .onUnreadBadge,
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.0,
                                                    fontSize: 10,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
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
                    const SizedBox(width: 14),
                    Text(
                      widget.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: widget.selected ? selColor : baseColor,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
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
    super.key,
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
  bool get _disableAnims => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    // Listen to contact data changes to get application unread count
    final contactDataStream = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatContactData<dynamic>>(
          "TencentCloudChatContactData",
        );
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
    _applicationUnreadCount = UikitDataFacade.applicationUnreadCount;
  }

  @override
  void dispose() {
    _contactDataSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final baseColor = isDark
            ? DesignTokens.textSecondaryDark
            : DesignTokens.textSecondaryLight;
        const selColor = DesignTokens.primary;
        final bg = widget.selected
            ? (isDark
                  ? DesignTokens.primaryTintDark
                  : DesignTokens.primaryTintLight)
            : (_isHovered
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
                  : Colors.transparent);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: _disableAnims ? Duration.zero : AppDurations.fast,
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 18,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          widget.icon,
                          size: 23,
                          color: widget.selected ? selColor : baseColor,
                        ),
                        if (_applicationUnreadCount > 0)
                          Positioned(
                            top: -5,
                            right: -6,
                            child: UnconstrainedBox(
                              child: Builder(
                                builder: (context) {
                                  final displayText =
                                      _applicationUnreadCount > 99
                                      ? "99+"
                                      : "$_applicationUnreadCount";
                                  return Semantics(
                                    label:
                                        AppLocalizations.of(
                                          context,
                                        )?.unreadMessagesSemantics(
                                          _applicationUnreadCount,
                                        ) ??
                                        'Unread messages: $_applicationUnreadCount',
                                    container: true,
                                    child: ExcludeSemantics(
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                        ),
                                        height: 16,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs,
                                        ),
                                        decoration: BoxDecoration(
                                          color: DesignTokens.unreadBadge,
                                          borderRadius: BorderRadius.circular(
                                            AppThemeConfig.badgeBorderRadius,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            displayText,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: DesignTokens
                                                      .onUnreadBadge,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.0,
                                                  fontSize: 10,
                                                ),
                                            textAlign: TextAlign.center,
                                          ),
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
                    const SizedBox(width: 14),
                    Text(
                      widget.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: widget.selected ? selColor : baseColor,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
