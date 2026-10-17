part of 'settings_page.dart';

/// The Location master switch and the "visible to people nearby" switch
/// (doc/plans/LOCATION_AND_NEARBY_PLAN.md §4.5). Built only when the page
/// was given [SettingsPage.locationEnabled]; both default off. Shared by the
/// desktop column and the mobile account card — the two differ only in
/// their divider style.
extension _SettingsLocationRows on _SettingsPageState {
  List<Widget> _buildLocationToggleRows(
    BuildContext context, {
    required bool mobile,
    required Color outlineVariant,
  }) {
    final locationEnabled = widget.locationEnabled;
    if (locationEnabled == null) return const <Widget>[];
    final colorTheme = TencentCloudChat.instance.dataInstance.theme.colorTheme;
    final l10n = AppLocalizations.of(context)!;
    final nearbyVisible = widget.nearbyVisible ?? false;

    Widget divider() => mobile
        ? const Divider(height: AppSpacing.xl)
        : Divider(height: 1, color: outlineVariant);

    Widget row({
      required Key key,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) {
      return _HoverableSettingsRow(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  AppSpacing.verticalXs,
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorTheme.secondaryTextColor,
                        ),
                  ),
                ],
              ),
            ),
            Switch(key: key, value: value, onChanged: onChanged),
          ],
        ),
      );
    }

    return <Widget>[
      if (mobile) divider() else ...[
        AppSpacing.verticalLg,
        divider(),
        AppSpacing.verticalMd,
      ],
      row(
        key: NearbyUiKeys.settingsLocationSwitch,
        title: l10n.locationServices,
        subtitle: l10n.locationServicesDesc,
        value: locationEnabled,
        onChanged: widget.onLocationEnabledChanged,
      ),
      if (mobile) divider() else ...[
        AppSpacing.verticalLg,
        divider(),
        AppSpacing.verticalMd,
      ],
      row(
        key: NearbyUiKeys.settingsNearbyVisibleSwitch,
        title: l10n.nearbyVisible,
        subtitle: l10n.nearbyVisibleDesc,
        value: locationEnabled && nearbyVisible,
        // Disabled (greyed) while the master is off.
        onChanged: locationEnabled ? widget.onNearbyVisibleChanged : null,
      ),
      if (widget.onOpenNearby != null) ...[
        AppSpacing.verticalSm,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: locationEnabled && nearbyVisible ? widget.onOpenNearby : null,
            icon: const Icon(Icons.near_me_outlined),
            label: Text(l10n.peopleNearby),
          ),
        ),
      ],
    ];
  }
}
