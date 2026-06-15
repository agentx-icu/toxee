part of 'settings_page.dart';

extension _SettingsPageBuild on _SettingsPageState {
  List<Widget> _buildSettingsChildren(
    BuildContext context,
    dynamic colorTheme,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final outlineVariant = scheme.outlineVariant;
    // Brightness-aware destructive tint: errorLight (#F54A45) in light mode,
    // errorDark (#FF6159) in dark — resolved from the color scheme so logout /
    // delete keep ≥4.5:1 contrast on both the white and near-black settings
    // cards (the prior const AppThemeConfig.errorColor was light-only).
    final errorColor = scheme.error;
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
      wrap(
        0,
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: outlineVariant),
            borderRadius: BorderRadius.circular(
              AppThemeConfig.cardBorderRadius,
            ),
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
                        child:
                            _avatarPath != null &&
                                _avatarPath!.isNotEmpty &&
                                File(_avatarPath!).existsSync()
                            ? ClipOval(
                                child: Image.file(
                                  File(_avatarPath!),
                                  key: ValueKey(
                                    'settings-avatar-img-$_avatarPath',
                                  ),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Text(
                                (_currentNickname!.isNotEmpty
                                        ? _currentNickname![0]
                                        : 'U')
                                    .toUpperCase(),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
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
                  // Prominent Tox ID row: pushes the truncated ID and a copy
                  // affordance above the action buttons so new users can grab
                  // their ID without expanding the account card below.
                  _HoverableSettingsRow(
                    child: Builder(
                      builder: (context) {
                        final toxId =
                            _currentAccountToxId ?? widget.service.accountKey;
                        return Row(
                          children: [
                            Icon(
                              Icons.fingerprint,
                              size: 18,
                              color: colorTheme.secondaryTextColor,
                            ),
                            AppSpacing.horizontalSm,
                            Text(
                              '${AppLocalizations.of(context)!.userId}:',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorTheme.secondaryTextColor,
                                  ),
                            ),
                            AppSpacing.horizontalSm,
                            // Tox IDs are hex — always render LTR so RTL UI does
                            // not visually flip the chars. Show the full ID when
                            // the row has room; Flutter's `TextOverflow.ellipsis`
                            // truncates it on narrow widths.
                            Expanded(
                              child: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  toxId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontFamily: 'monospace',
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ),
                            ),
                            IconButton(
                              key: UiKeys.settingsCopyToxIdButton,
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              tooltip: AppLocalizations.of(
                                context,
                              )!.copyFullToxId,
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: toxId),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.idCopiedToClipboard,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  AppSpacing.verticalMd,
                  // All four account actions on one row. The destructive ones
                  // (Log Out / Delete Account) keep the error-tinted styling so
                  // their intent stays distinguishable from the neutral
                  // Export / Set Password buttons even without a divider or a
                  // dedicated "danger zone" box.
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        key: UiKeys.settingsExportAccountButton,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: Text(
                          AppLocalizations.of(context)!.exportAccount,
                        ),
                        onPressed: _showExportOptions,
                      ),
                      OutlinedButton.icon(
                        key: UiKeys.settingsSetPasswordButton,
                        icon: const Icon(Icons.lock, size: 18),
                        label: Text(AppLocalizations.of(context)!.setPassword),
                        onPressed: _setAccountPassword,
                      ),
                      OutlinedButton.icon(
                        key: UiKeys.settingsLogoutButton,
                        icon: const Icon(Icons.logout, size: 18),
                        label: Text(AppLocalizations.of(context)!.logOut),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: errorColor,
                          side: BorderSide(color: errorColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppThemeConfig.buttonBorderRadius,
                            ),
                          ),
                        ),
                        onPressed: _logout,
                      ),
                      OutlinedButton.icon(
                        key: UiKeys.settingsDeleteAccountButton,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(
                          AppLocalizations.of(context)!.deleteAccount,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: errorColor,
                          side: BorderSide(color: errorColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppThemeConfig.buttonBorderRadius,
                            ),
                          ),
                        ),
                        onPressed: () =>
                            _showDeleteAccountConfirmation(context),
                      ),
                    ],
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
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colorTheme.secondaryTextColor,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          key: UiKeys.settingsAutoLoginSwitch,
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
                                AppLocalizations.of(
                                  context,
                                )!.autoAcceptFriendRequests,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              AppSpacing.verticalXs,
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.autoAcceptFriendRequestsDesc,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
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
                                AppLocalizations.of(
                                  context,
                                )!.autoAcceptGroupInvites,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              AppSpacing.verticalXs,
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.autoAcceptGroupInvitesDesc,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
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
                  SectionHeader(
                    title: AppLocalizations.of(context)!.accountManagement,
                  ),
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
                          : (_accountList.length >
                                    _SettingsPageState._accountListPreviewCount
                                ? _SettingsPageState._accountListPreviewCount
                                : _accountList.length),
                      itemBuilder: (context, index) {
                        final account = _accountList[index];
                        final accountToxId = account['toxId'] ?? '';
                        final lastLogin = account['lastLoginTime'];
                        // Use Prefs current Tox ID; widget.service.selfId is UIKit placeholder (e.g. FlutterUIKitClient)
                        final currentId =
                            _currentAccountToxId ?? widget.service.accountKey;
                        final isCurrentAccount = compareToxIds(
                          accountToxId,
                          currentId,
                        );
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
                              borderRadius: BorderRadius.circular(
                                AppThemeConfig.badgeBorderRadius,
                              ),
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${AppLocalizations.of(context)!.userId}: $accountToxId',
                                      // Show the full Tox ID; `Flexible` +
                                      // ellipsis means Flutter only truncates
                                      // when the row actually runs out of room.
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      // Tabular figures so the hex characters
                                      // don't reflow as digits change width.
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ),
                                  // Copy the full (untruncated) Tox ID. The
                                  // visible prefix-with-ellipsis was previously
                                  // a dead end for users who needed the full id.
                                  IconButton(
                                    icon: const Icon(
                                      Icons.copy_outlined,
                                      size: 16,
                                    ),
                                    tooltip: AppLocalizations.of(
                                      context,
                                    )!.copyFullToxId,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: accountToxId),
                                      );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.idCopiedToClipboard,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              Text(
                                '${AppLocalizations.of(context)!.lastLogin}: ${_formatLastLoginTime(lastLogin, context)}',
                                // Tabular figures keep the relative-time digits
                                // ("3 days ago") from jittering on update.
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (_accountList.length >
                        _SettingsPageState._accountListPreviewCount) ...[
                      AppSpacing.verticalSm,
                      InkWell(
                        onTap: () => _settingsSetState(
                          () => _accountListExpanded = !_accountListExpanded,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppThemeConfig.inputBorderRadius,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                            horizontal: AppSpacing.md,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _accountListExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              AppSpacing.horizontalXs,
                              Text(
                                _accountListExpanded
                                    ? AppLocalizations.of(context)!.showLess
                                    : AppLocalizations.of(context)!.showMore(
                                        _accountList.length -
                                            _SettingsPageState
                                                ._accountListPreviewCount,
                                      ),
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
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
                        label: Text(
                          AppLocalizations.of(context)!.importAccount,
                        ),
                        onPressed: _importAccount,
                      ),
                    ],
                  ),
                  if (FeatureFlags.enableQRPairing) ...[
                    AppSpacing.verticalLg,
                    Divider(height: 1, color: outlineVariant),
                    AppSpacing.verticalMd,
                    SectionHeader(
                      title: AppLocalizations.of(context)!.devicesSectionTitle,
                    ),
                    AppSpacing.verticalSm,
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code, size: 18),
                          label: Text(
                            AppLocalizations.of(
                              context,
                            )!.pairThisAccountToAnotherDevice,
                          ),
                          onPressed: _startPairingAsHost,
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
      AppSpacing.verticalMd,
      wrap(
        1,
        GlobalSettingsSection(
          colorTheme: colorTheme,
          toxId: widget.service.accountKey,
          onDownloadsConfigChanged: () {
            // FfiChatService re-reads Prefs.getDownloadsDirectory() on every
            // file save (see _getDownloadsDirectory in ffi_chat_service.dart),
            // so no cached state needs invalidation; the hook is wired so a
            // future cached-config implementation can act on it.
            AppLogger.debug('[Settings] downloads config changed');
          },
        ),
      ),
      AppSpacing.verticalMd,
      wrap(
        2,
        BootstrapSettingsSection(
          service: widget.service,
          colorTheme: colorTheme,
        ),
      ),
    ];
  }
}
