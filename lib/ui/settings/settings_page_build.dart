part of 'settings_page.dart';

extension _SettingsPageBuild on _SettingsPageState {
  List<Widget> _buildSettingsChildren(BuildContext context, dynamic colorTheme) {
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    // Stagger top-level settings sections (Account / Global / Bootstrap) for
    // a subtle entrance. Respects reduced-motion via MediaQuery.
    final disableAnims = MediaQuery.disableAnimationsOf(context);
    Widget wrap(int index, Widget child) {
      if (disableAnims) return child;
      return StaggeredListItem(
        index: index,
        staggerDelay: const Duration(milliseconds: 50),
        child: child,
      );
    }
    return [
      wrap(0, Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: outlineVariant),
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: AppLocalizations.of(context)!.accountInfo),
              AppSpacing.verticalSm,
              if (_currentNickname != null) ...[
                Row(
                  children: [
                    CircleAvatar(
                      key: ValueKey('settings-avatar-$_avatarPath'),
                      radius: 20,
                      backgroundColor: colorTheme.primaryColor,
                      child: _avatarPath != null && _avatarPath!.isNotEmpty && File(_avatarPath!).existsSync()
                          ? ClipOval(
                              child: Image.file(
                                File(_avatarPath!),
                                key: ValueKey('settings-avatar-img-$_avatarPath'),
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Text(
                              (_currentNickname!.isNotEmpty ? _currentNickname![0] : 'U').toUpperCase(),
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: colorTheme.onPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                    ),
                    AppSpacing.horizontalMd,
                    Expanded(
                      child: Text(
                        _currentNickname!,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                AppSpacing.verticalMd,
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(AppLocalizations.of(context)!.exportAccount),
                      onPressed: _showExportOptions,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.lock, size: 18),
                      label: Text(AppLocalizations.of(context)!.setPassword),
                      onPressed: _setAccountPassword,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.logout, size: 18),
                      label: Text(AppLocalizations.of(context)!.logOut),
                      onPressed: _logout,
                    ),
                  ],
                ),
                AppSpacing.verticalLg,
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppThemeConfig.errorColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
                    border: Border.all(color: AppThemeConfig.errorColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppThemeConfig.errorColor, size: 20),
                          AppSpacing.horizontalSm,
                          Text(
                            AppLocalizations.of(context)!.deleteAccount,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: AppThemeConfig.errorColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      AppSpacing.verticalMd,
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: Text(AppLocalizations.of(context)!.deleteAccount),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppThemeConfig.errorColor,
                          side: const BorderSide(color: AppThemeConfig.errorColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                          ),
                        ),
                        onPressed: () => _showDeleteAccountConfirmation(context),
                      ),
                    ],
                  ),
                ),
                AppSpacing.verticalLg,
                Divider(height: 1, color: outlineVariant),
                AppSpacing.verticalMd,
                _HoverableSettingsRow(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.autoLogin,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            AppSpacing.verticalXs,
                            Text(
                              AppLocalizations.of(context)!.autoLoginDesc,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorTheme.secondaryTextColor,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _autoLogin,
                        onChanged: (value) => _setAutoLogin(value),
                      ),
                    ],
                  ),
                ),
                AppSpacing.verticalLg,
                Divider(height: 1, color: outlineVariant),
                AppSpacing.verticalMd,
                _HoverableSettingsRow(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.autoAcceptFriendRequests,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            AppSpacing.verticalXs,
                            Text(
                              AppLocalizations.of(context)!.autoAcceptFriendRequestsDesc,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorTheme.secondaryTextColor,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: widget.autoAcceptFriends,
                        onChanged: widget.onAutoAcceptFriendsChanged,
                      ),
                    ],
                  ),
                ),
                AppSpacing.verticalLg,
                Divider(height: 1, color: outlineVariant),
                AppSpacing.verticalMd,
                _HoverableSettingsRow(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.autoAcceptGroupInvites,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            AppSpacing.verticalXs,
                            Text(
                              AppLocalizations.of(context)!.autoAcceptGroupInvitesDesc,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorTheme.secondaryTextColor,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: widget.autoAcceptGroupInvites,
                        onChanged: widget.onAutoAcceptGroupInvitesChanged,
                      ),
                    ],
                  ),
                ),
                AppSpacing.verticalLg,
                Divider(height: 1, color: outlineVariant),
                AppSpacing.verticalMd,
                SectionHeader(title: AppLocalizations.of(context)!.accountManagement),
                AppSpacing.verticalSm,
                if (_accountList.isNotEmpty) ...[
                  Text(
                    AppLocalizations.of(context)!.localAccounts,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  AppSpacing.verticalSm,
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _accountListExpanded
                        ? _accountList.length
                        : (_accountList.length > _SettingsPageState._accountListPreviewCount
                            ? _SettingsPageState._accountListPreviewCount
                            : _accountList.length),
                    itemBuilder: (context, index) {
                      final account = _accountList[index];
                      final accountToxId = account['toxId'] ?? '';
                      final lastLogin = account['lastLoginTime'];
                      // Use Prefs current Tox ID; widget.service.selfId is UIKit placeholder (e.g. FlutterUIKitClient)
                      final currentId = _currentAccountToxId ?? widget.service.selfId;
                      final isCurrentAccount = compareToxIds(accountToxId, currentId);
                      return _AccountCardItem(
                        account: account,
                        isCurrentAccount: isCurrentAccount,
                        colorTheme: colorTheme,
                        onSwitch: () => _switchAccount(account),
                        currentChip: Chip(
                          label: Text(AppLocalizations.of(context)!.current),
                          backgroundColor: colorTheme.primaryColor,
                          labelStyle: TextStyle(color: colorTheme.onPrimary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppThemeConfig.badgeBorderRadius),
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${AppLocalizations.of(context)!.userId}: ${_getToxIdPrefix(accountToxId)}...',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '${AppLocalizations.of(context)!.lastLogin}: ${_formatLastLoginTime(lastLogin, context)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_accountList.length > _SettingsPageState._accountListPreviewCount) ...[
                    AppSpacing.verticalSm,
                    InkWell(
                      onTap: () => _settingsSetState(() => _accountListExpanded = !_accountListExpanded),
                      borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _accountListExpanded ? Icons.expand_less : Icons.expand_more,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            AppSpacing.horizontalXs,
                            Text(
                              _accountListExpanded
                                  ? AppLocalizations.of(context)!.showLess
                                  : AppLocalizations.of(context)!.showMore(_accountList.length - _SettingsPageState._accountListPreviewCount),
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  AppSpacing.verticalMd,
                ],
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.download, size: 18),
                      label: Text(AppLocalizations.of(context)!.importAccount),
                      onPressed: _importAccount,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      )),
      AppSpacing.verticalMd,
      wrap(1, GlobalSettingsSection(
        colorTheme: colorTheme,
        toxId: widget.service.selfId,
      )),
      AppSpacing.verticalMd,
      wrap(2, BootstrapSettingsSection(
        service: widget.service,
        colorTheme: colorTheme,
      )),
    ];
  }
}
