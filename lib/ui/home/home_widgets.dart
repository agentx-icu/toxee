import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';
import '../testing/ui_keys.dart';

/// New entry button widget (Add Friend / Create Group / Join IRC Channel)
class NewEntryButton extends StatefulWidget {
  const NewEntryButton({
    super.key,
    required this.onAddFriend,
    required this.onCreateGroup,
    this.onJoinIrcChannel,
    this.canJoinIrc,
  });
  final Future<void> Function() onAddFriend;
  final Future<void> Function() onCreateGroup;
  final Future<void> Function()? onJoinIrcChannel;

  /// Evaluated at menu-open time to decide whether the "Join IRC Channel" entry
  /// is shown — lets the item disappear the moment the IRC app is uninstalled,
  /// without needing this widget (inside the UIKit app bar) to rebuild. When
  /// null the entry follows [onJoinIrcChannel] alone.
  final bool Function()? canJoinIrc;

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

  @override
  Widget build(BuildContext context) {
    final appL10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tL10n = TencentCloudChatLocalizations.of(context);
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
