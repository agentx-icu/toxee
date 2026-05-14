import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';

/// New entry button widget (Add Friend / Create Group / Join IRC Channel)
class NewEntryButton extends StatefulWidget {
  const NewEntryButton({
    super.key,
    required this.onAddFriend,
    required this.onCreateGroup,
    this.onJoinIrcChannel,
  });
  final Future<void> Function() onAddFriend;
  final Future<void> Function() onCreateGroup;
  final Future<void> Function()? onJoinIrcChannel;

  @override
  State<NewEntryButton> createState() => _NewEntryButtonState();
}

class _NewEntryButtonState extends State<NewEntryButton> {
  final GlobalKey<PopupMenuButtonState<String>> _menuKey = GlobalKey<PopupMenuButtonState<String>>();

  PopupMenuItem<String> _menuItem({
    required BuildContext context,
    required String value,
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    return PopupMenuItem<String>(
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
        ),
        _menuItem(
          context: context,
          value: 'group',
          icon: Icons.group_add,
          label: tL10n?.createGroupChat ?? 'Create Group',
        ),
        if (widget.onJoinIrcChannel != null)
          _menuItem(
            context: context,
            value: 'irc',
            icon: Icons.chat_bubble_outline,
            label: appL10n?.joinIrcChannel ?? 'Join IRC Channel',
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
      child: SizedBox(
        // 44pt minimum tap target for mobile (Apple HIG / Material 48dp).
        height: 44,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            tL10n?.newChat ?? 'New',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: () => _menuKey.currentState?.showButtonMenu(),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: theme.colorScheme.primary),
            foregroundColor: theme.colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
            ),
          ),
        ),
      ),
    );
  }
}

