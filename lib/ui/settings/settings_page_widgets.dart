part of 'settings_page.dart';

/// Part-private alias for the shared [HoverableSettingsRow] so existing call
/// sites in this file (and `settings_page_build.dart`) keep their underscore
/// reference. The implementation lives in `_hoverable_settings_row.dart`.
class _HoverableSettingsRow extends StatelessWidget {
  const _HoverableSettingsRow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => HoverableSettingsRow(child: child);
}

class _AccountCardItem extends StatefulWidget {
  const _AccountCardItem({
    required this.account,
    required this.isCurrentAccount,
    required this.colorTheme,
    required this.onSwitch,
    required this.currentChip,
    required this.subtitle,
  });
  final Map<String, String> account;
  final bool isCurrentAccount;
  final dynamic colorTheme;
  final VoidCallback onSwitch;
  final Widget currentChip;
  final Widget subtitle;

  @override
  State<_AccountCardItem> createState() => _AccountCardItemState();
}

class _AccountCardItemState extends State<_AccountCardItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accountNickname = widget.account['nickname'] ?? '';
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    final primary = widget.colorTheme.primaryColor as Color;
    final disableAnims = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: disableAnims ? Duration.zero : AppDurations.fast,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          color: widget.isCurrentAccount
              ? primary.withValues(alpha: 0.08)
              : (_isHovered ? primary.withValues(alpha: 0.04) : null),
          border: Border.all(
            color: widget.isCurrentAccount
                ? primary.withValues(alpha: 0.4)
                : outlineVariant,
          ),
        ),
        child: Card(
          elevation: 0,
          color: Colors.transparent,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              // Non-current accounts get a neutral slate fill (20% alpha on
              // the brightness-aware secondary text token) so they read as
              // "another identity" rather than a pressed/selected primary
              // button. Only the active account keeps the primaryColor fill.
              backgroundColor: widget.isCurrentAccount
                  ? widget.colorTheme.primaryColor
                  : (Theme.of(context).brightness == Brightness.dark
                            ? AppThemeConfig.secondaryTextColorDark
                            : AppThemeConfig.secondaryTextColorLight)
                        .withValues(alpha: 0.20),
              child: Text(
                accountNickname.isNotEmpty
                    ? accountNickname[0].toUpperCase()
                    : 'A',
                style: TextStyle(
                  color: widget.isCurrentAccount
                      ? widget.colorTheme.onPrimary
                      : (Theme.of(context).brightness == Brightness.dark
                            ? AppThemeConfig.primaryTextColorDark
                            : AppThemeConfig.primaryTextColorLight),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            title: Text(
              accountNickname.isNotEmpty ? accountNickname : 'Unnamed Account',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            subtitle: widget.subtitle,
            trailing: widget.isCurrentAccount
                ? widget.currentChip
                : IconButton(
                    key: UiKeys.settingsAccountSwitchButton(
                      widget.account['toxId'] ?? '',
                    ),
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: widget.onSwitch,
                    tooltip: AppLocalizations.of(context)!.switchToThisAccount,
                  ),
          ),
        ),
      ),
    );
  }
}

extension _AccountActionButtons on _SettingsPageState {
  Widget _buildAccountActionButtons(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    OutlinedButton accountAction({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
      bool danger = false,
      bool compact = false,
    }) {
      return OutlinedButton.icon(
        key: key,
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? errorColor : null,
          side: danger ? BorderSide(color: errorColor) : null,
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppThemeConfig.buttonBorderRadius,
            ),
          ),
        ),
        onPressed: onPressed,
      );
    }

    List<Widget> buildAccountButtons({required bool compact}) {
      return [
        accountAction(
          key: UiKeys.settingsExportAccountButton,
          icon: Icons.upload_file,
          label: AppLocalizations.of(context)!.exportAccount,
          onPressed: _showExportOptions,
          compact: compact,
        ),
        accountAction(
          key: UiKeys.settingsSetPasswordButton,
          icon: Icons.lock,
          label: AppLocalizations.of(context)!.setPassword,
          onPressed: _setAccountPassword,
          compact: compact,
        ),
        accountAction(
          key: UiKeys.settingsLogoutButton,
          icon: Icons.logout,
          label: AppLocalizations.of(context)!.logOut,
          onPressed: _logout,
          danger: true,
          compact: compact,
        ),
        accountAction(
          key: UiKeys.settingsDeleteAccountButton,
          icon: Icons.delete_outline,
          label: AppLocalizations.of(context)!.deleteAccount,
          onPressed: () => _showDeleteAccountConfirmation(context),
          danger: true,
          compact: compact,
        ),
      ];
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: buildAccountButtons(compact: false),
          );
        }
        final buttons = buildAccountButtons(compact: true);
        Widget gridRow(Widget left, Widget right) => Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: right),
          ],
        );
        return Column(
          children: [
            gridRow(buttons[0], buttons[1]),
            AppSpacing.verticalSm,
            gridRow(buttons[2], buttons[3]),
          ],
        );
      },
    );
  }
}
