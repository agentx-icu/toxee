part of 'settings_page.dart';

extension _MobileSettingsIndex on _SettingsPageState {
  Widget _buildMobileSettingsIndex(BuildContext context, dynamic colorTheme) {
    final appL10n = AppLocalizations.of(context)!;
    final tL10n = TencentCloudChatLocalizations.of(context);
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;

    Widget sectionTile({
      required Key key,
      required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
    }) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: outlineVariant),
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        ),
        child: ListTile(
          key: key,
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
    }

    // Mobile counterpart of the desktop sidebar avatar: the same shared
    // widget, so phone and desktop show the same fallback for one account.
    Widget avatar() {
      return UserAvatarCircle(
        size: 56,
        initial: UserAvatarCircle.initialFor(_currentNickname),
        backgroundColor: colorTheme.primaryColor,
        foregroundColor: colorTheme.onPrimary,
        avatarPath: _avatarPath,
        avatarFileExists:
            _avatarPath != null &&
            _avatarPath!.isNotEmpty &&
            File(_avatarPath!).existsSync(),
      );
    }

    return ListView(
      key: UiKeys.settingsScrollView,
      controller: widget.scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: outlineVariant),
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
          ),
          child: ListTile(
            key: UiKeys.settingsMobileProfileTile,
            contentPadding: const EdgeInsets.all(AppSpacing.md),
            leading: avatar(),
            title: Text(_currentNickname ?? appL10n.profile),
            subtitle: Text(appL10n.profile),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _openMobileProfile,
          ),
        ),
        AppSpacing.verticalMd,
        sectionTile(
          key: UiKeys.settingsMobileAccountInfoSection,
          icon: Icons.badge_outlined,
          title: appL10n.accountInfo,
          onTap: () => _pushMobileSettingsSection(
            appL10n.accountInfo,
            _buildMobileAccountInfoCard(context, colorTheme),
          ),
        ),
        sectionTile(
          key: UiKeys.settingsMobileAccountManagementSection,
          icon: Icons.manage_accounts_outlined,
          title: appL10n.accountManagement,
          onTap: () => _pushMobileSettingsSection(
            appL10n.accountManagement,
            _buildMobileAccountManagementCard(context, colorTheme),
          ),
        ),
        sectionTile(
          key: UiKeys.settingsMobileAppearanceSection,
          icon: Icons.palette_outlined,
          title: tL10n?.appearance ?? appL10n.appearance,
          onTap: () => _pushMobileSettingsSection(
            tL10n?.appearance ?? appL10n.appearance,
            GlobalSettingsSection(
              colorTheme: colorTheme,
              toxId: widget.service.accountKey,
              view: GlobalSettingsView.appearance,
              onDownloadsConfigChanged: () {
                AppLogger.debug('[Settings] downloads config changed');
              },
            ),
          ),
        ),
        // "General" holds notification sound, downloads directory, and
        // auto-download size limit — moved off the Appearance page (which now
        // only carries theme + language) so each page stays focused on mobile.
        sectionTile(
          key: UiKeys.settingsMobileGeneralSection,
          icon: Icons.tune,
          title: appL10n.general,
          onTap: () => _pushMobileSettingsSection(
            appL10n.general,
            GlobalSettingsSection(
              colorTheme: colorTheme,
              toxId: widget.service.accountKey,
              view: GlobalSettingsView.general,
              onDownloadsConfigChanged: () {
                AppLogger.debug('[Settings] downloads config changed');
              },
            ),
          ),
        ),
        sectionTile(
          key: SettingsUiKeys.mobileBackgroundSection,
          icon: Icons.notifications_paused_outlined,
          title: appL10n.backgroundSettingsTitle,
          onTap: () => _pushMobileSettingsSection(
            appL10n.backgroundSettingsTitle,
            const BackgroundSettingsSection(),
          ),
        ),
        sectionTile(
          key: UiKeys.settingsMobileBootstrapSection,
          icon: Icons.hub_outlined,
          title: appL10n.bootstrapNodes,
          onTap: () => _pushMobileSettingsSection(
            appL10n.bootstrapNodes,
            BootstrapSettingsSection(
              service: widget.service,
              colorTheme: colorTheme,
            ),
          ),
        ),
      ],
    );
  }
}
