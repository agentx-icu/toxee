import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
// `TencentCloudChatConversationTotalUnreadCount` lives in its OWN file and the
// `tencent_cloud_chat_conversation.dart` barrel re-exports NOTHING, so importing
// the barrel does not bring the symbol into scope. Same import home_page.dart
// uses (:127) for the sidebar twin of this badge.
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_tatal_unread_count.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';
import '../../util/design_tokens.dart';
import '../../util/platform_utils.dart';
import '../testing/ui_keys.dart';
import '../testing/ui_keys_home.dart';

/// New entry button widget (Add Friend / Create Group / Join IRC Channel)
class NewEntryButton extends StatefulWidget {
  const NewEntryButton({
    super.key,
    required this.onAddFriend,
    required this.onCreateGroup,
    this.onJoinIrcChannel,
    this.canJoinIrc,
    this.onOpenGlobalSearch,
  });
  final Future<void> Function() onAddFriend;
  final Future<void> Function() onCreateGroup;
  final Future<void> Function()? onJoinIrcChannel;

  /// Evaluated at menu-open time to decide whether the "Join IRC Channel" entry
  /// is shown — lets the item disappear the moment the IRC app is uninstalled,
  /// without needing this widget (inside the UIKit app bar) to rebuild. When
  /// null the entry follows [onJoinIrcChannel] alone.
  final bool Function()? canJoinIrc;

  /// Opens toxee's global search overlay (`CustomSearch` with `userID`/`groupID`
  /// left null). When non-null a magnifier is rendered LEFT of the "+" — but
  /// ONLY on non-desktop platforms.
  ///
  /// WHY IT IS INSTALLED ON THE CONTACTS APP BAR TOO, not just Chats. Global
  /// `CustomSearch` is NOT a message-only surface: with no conversation scope it
  /// searches CONTACTS (friend remark / nickname / userID) and GROUPS (group
  /// name / groupID) alongside message history, and falls back to matching the
  /// conversation list (`lib/ui/search/custom_search.dart` — the contact and
  /// group filters, then the fallback). So the magnifier on the Contacts tab
  /// finds contacts, which is what a user tapping it there expects; removing it
  /// would leave Contacts with no search entry at all on touch platforms, where
  /// the Cmd/Ctrl+F shortcut does not exist. Automation is unaffected either
  /// way (the tabs are an IndexedStack and the onstage walk prunes the hidden
  /// branch).
  ///
  /// WHY THE PLATFORM GATE. The overlay had exactly two entry points: the
  /// Cmd/Ctrl+F `_OpenSearchIntent` shortcut, which `home_page.dart` registers
  /// behind `PlatformUtils.isDesktop`, and the `l3_open_global_search` test
  /// seam. So on iOS, iPadOS and Android a fully built search feature was
  /// UNREACHABLE by any real user gesture — not a narrow-shell layout quirk but
  /// a missing affordance on every touch platform (the compact conversation app
  /// bar's `defaultBuilder` renders no search item either, and the tablet /
  /// desktop builder's inline field is the FORK's own filter, a different
  /// feature). This button is that missing entry point. Desktop keeps its
  /// shortcut and is deliberately left visually unchanged.
  final VoidCallback? onOpenGlobalSearch;

  @override
  State<NewEntryButton> createState() => _NewEntryButtonState();
}

class _NewEntryButtonState extends State<NewEntryButton> {
  final GlobalKey<PopupMenuButtonState<String>> _menuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  bool _hovered = false;

  PopupMenuItem<String> _menuItem({
    required BuildContext context,
    required String value,
    required IconData icon,
    required String label,
    Key? key,
  }) {
    final theme = Theme.of(context);
    return PopupMenuItem<String>(
      key: key,
      value: value,
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(label, style: theme.textTheme.bodyLarge),
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// The magnifier that opens the global search overlay, or null when this
  /// build must not render one (desktop, or no callback wired).
  ///
  /// Sized to match the "+" circle (40x40) so the two actions line up in the
  /// app bar's fixed-height toolbar; `padding: EdgeInsets.zero` for the same
  /// reason the PopupMenuButton zeroes its own (an IconButton's default 8pt
  /// padding inflates it past the mobile contacts toolbar's height budget and
  /// produces a RenderFlex overflow).
  Widget? _buildGlobalSearchButton(
    ThemeData theme,
    TencentCloudChatLocalizations? tL10n,
  ) {
    final open = widget.onOpenGlobalSearch;
    if (open == null || PlatformUtils.isDesktop) return null;
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        key: HomeUiKeys.conversationGlobalSearchButton,
        padding: EdgeInsets.zero,
        tooltip: tL10n?.search ?? 'Search',
        icon: Icon(
          Icons.search,
          size: 22,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onPressed: open,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appL10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tL10n = TencentCloudChatLocalizations.of(context);
    final searchButton = _buildGlobalSearchButton(theme, tL10n);
    final Widget menu = _buildMenu(context, appL10n, theme, tL10n);
    if (searchButton == null) return menu;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [searchButton, menu],
    );
  }

  Widget _buildMenu(
    BuildContext context,
    AppLocalizations? appL10n,
    ThemeData theme,
    TencentCloudChatLocalizations? tL10n,
  ) {
    return PopupMenuButton<String>(
      key: _menuKey,
      // Open the menu *below* the button (anchor at the button's bottom
      // edge) instead of Flutter's default `PopupMenuPosition.over` which
      // places the first menu item on top of the button — that made the
      // pill visually disappear behind the menu the moment it opened, and
      // looked like the button "ate itself" (see sc_01.png).
      position: PopupMenuPosition.under,
      // Zero padding: PopupMenuButton defaults to EdgeInsets.all(8), which
      // inflates our 40×40 circular child to a 56×56 footprint. On the mobile
      // contacts app bar (a fixed 120pt toolbar hosting title-row + gap +
      // search) that extra 16pt pushed the column past its budget and produced
      // a RenderFlex overflow ("garbled" header). The circle already has its
      // own hit area via the InkWell.
      padding: EdgeInsets.zero,
      // Hover/long-press tooltip (also the mobile long-press label) — the
      // short localized "New" from UIKit intl (zh 新建 / etc.) rather than the
      // longer "New conversation", per the requested shorter label.
      tooltip:
          tL10n?.newChat ??
          AppLocalizations.of(context)?.newConversationTooltip ??
          'New',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      elevation: 2,
      itemBuilder: (context) => [
        _menuItem(
          context: context,
          value: 'add',
          icon: Icons.person_add_alt,
          label: tL10n?.addContact ?? 'Add Contact',
          key: UiKeys.newEntryAddContactItem,
        ),
        _menuItem(
          context: context,
          value: 'group',
          icon: Icons.group_add,
          label: tL10n?.createGroupChat ?? 'Create Group',
          key: UiKeys.newEntryCreateGroupItem,
        ),
        if (widget.onJoinIrcChannel != null &&
            (widget.canJoinIrc?.call() ?? true))
          _menuItem(
            context: context,
            value: 'irc',
            icon: Icons.chat_bubble_outline,
            label: appL10n?.joinIrcChannel ?? 'Join IRC Channel',
            key: UiKeys.newEntryJoinIrcItem,
          ),
      ],
      onSelected: (v) async {
        if (v == 'add') {
          await widget.onAddFriend();
        } else if (v == 'group') {
          await widget.onCreateGroup();
        } else if (v == 'irc' && widget.onJoinIrcChannel != null) {
          await widget.onJoinIrcChannel!();
        }
      },
      // Single gesture owner: PopupMenuButton handles the tap directly via
      // Material + InkWell. Previously an inner OutlinedButton.onPressed
      // raced with PopupMenuButton's own tap detector — two gesture owners
      // on the same surface. Visual treatment (outlined pill, primary
      // border, icon+label) is preserved.
      // Subtle circular "+" icon button (reference: Feishu compose entry).
      // The old prominent gradient "New Chat ▾" pill read as too heavy for a
      // secondary header action; a quiet outlined icon keeps the affordance
      // without dominating the toolbar. The dropdown menu is unchanged.
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            key: UiKeys.newEntryMenuButton,
            customBorder: const CircleBorder(),
            onTap: () => _menuKey.currentState?.showButtonMenu(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hovered
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent,
                border: Border.all(
                  color: _hovered
                      ? theme.colorScheme.outline
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Icon(
                Icons.add,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom-nav **Chats** glyph with the live total-unread badge overlaid.
///
/// WHY IT IS A WIDGET RATHER THAN AN INLINE `Stack`. `BottomNavigationBar`
/// renders `selected ? item.activeIcon : item.icon`
/// (flutter/src/material/bottom_navigation_bar.dart), so a badge attached only
/// to `icon` DISAPPEARS the moment the Chats tab is selected — which is exactly
/// the tab a user is standing on while they read the total. HomePage now builds
/// this for BOTH glyphs; keeping the badge in one place is what makes that
/// safe. Live-proved on iPhone (2026-08-16): the conversation store reported
/// `totalUnreadCount == 1` while neither `home_chats_unread_badge` nor its
/// parent `bottom_nav_chats_tab` Stack existed anywhere in the element tree.
///
/// The badge paints OUTSIDE the icon's box (`Positioned(top: -5, right: -6)`
/// inside `Stack(clipBehavior: Clip.none)`), which is why the automation key
/// sits on the parent Stack as well: the badge's own centre is a point its
/// parent's bounds do not contain.
///
/// Mobile parity: shared Dart, so iOS and Android render the same tree. The
/// wide/desktop shell has no bottom nav and uses `sidebar_chats_unread_badge`
/// instead (`lib/ui/settings/sidebar.dart`).
class ChatsNavIcon extends StatelessWidget {
  const ChatsNavIcon({super.key, required this.glyph});

  final IconData glyph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      key: UiKeys.bottomNavChats,
      clipBehavior: Clip.none,
      children: [
        Icon(glyph),
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
                    ? '99+'
                    : '$totalUnreadCount';
                final isLargeText = displayText.length > 2;
                return Semantics(
                  label: AppLocalizations.of(
                    context,
                  )!.unreadMessagesSemantics(totalUnreadCount),
                  container: true,
                  child: UnconstrainedBox(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: EdgeInsets.symmetric(
                        horizontal: isLargeText ? 5 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: DesignTokens.unreadBadge,
                        borderRadius: BorderRadius.circular(
                          AppThemeConfig.badgeBorderRadius,
                        ),
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: ExcludeSemantics(
                          child: Text(
                            displayText,
                            // Automation-only: the mobile bottom-nav twin of
                            // sidebar_chats_unread_badge.
                            key: UiKeys.homeChatsUnreadBadge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: DesignTokens.onUnreadBadge,
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
    );
  }
}
