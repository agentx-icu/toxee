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
            borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
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
