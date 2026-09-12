part of 'settings_page.dart';

extension _MobileSettingsWidgets on _SettingsPageState {
  void _pushMobileSettingsSection(String title, Widget child) {
    Navigator.of(context).push<void>(
      AppPageRoute<void>(
        page: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: UiKeys.settingsMobileSectionBackButton,
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(title),
          ),
          body: SafeArea(
            child: ListView(
              key: UiKeys.settingsMobileSectionScrollView,
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [child],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileAccountInfoCard(BuildContext context, dynamic colorTheme) {
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    final toxId = _currentAccountToxId ?? widget.service.accountKey;
    Future<void> copyToxId() async {
      await Clipboard.setData(ClipboardData(text: toxId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.idCopiedToClipboard),
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _autoLoginNotifier,
      builder: (context, autoLogin, _) => Card(
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
              AppSpacing.verticalMd,
              Text(
                AppLocalizations.of(context)!.userId,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorTheme.secondaryTextColor,
                ),
              ),
              AppSpacing.verticalXs,
              // Tox IDs are hex — force LTR so an RTL locale does not visually
              // flip the characters (same reasoning as the desktop row in
              // settings_page_build.dart).
              //
              // Copy is wired through `SelectableText.onTap`, NOT through an
              // ancestor `GestureDetector(onLongPress:)`. That wrapper used to be
              // here and was DEAD CODE on every touch device. Gesture-arena
              // finding, against the pinned Flutter 3.41 SDK:
              //   * `SelectableText.build` always wraps its `EditableText` in
              //     `TextSelectionGestureDetectorBuilder.buildGestureDetector`
              //     (material/selectable_text.dart:810), and that builder passes
              //     `onSingleLongTapStart` as a non-null tear-off unconditionally
              //     (widgets/text_selection.dart:3385), so
              //     `TextSelectionGestureDetector` ALWAYS registers a
              //     `LongPressGestureRecognizer` restricted to
              //     `PointerDeviceKind.touch`
              //     (widgets/text_selection.dart:3668-3686). This is NOT forked on
              //     `TargetPlatform`, and it still happens when
              //     `enableInteractiveSelection` is false — in that case the
              //     handler merely early-returns while the recognizer stays in the
              //     arena, so "just disable selection" does not free the gesture.
              //   * `RenderEditable.hitTestSelf` returns true
              //     (rendering/editable.dart:1984), so an ancestor
              //     `GestureDetector` IS on the hit-test path and does enter the
              //     same arena. But hit-test entries are dispatched deepest-first,
              //     so the SelectableText's recognizer starts its
              //     `kLongPressTimeout` deadline timer first; equal-duration
              //     timers fire in scheduling order, the inner recognizer calls
              //     `resolve(GestureDisposition.accepted)` first, and the arena
              //     rejects every other member. The ancestor `onLongPress` never
              //     ran.
              // `onTap` is the hook SelectableText documents for exactly this
              // ("To make SelectableText react to touch events, use callback
              // onTap", material/selectable_text.dart:131) and it is dispatched
              // from the widget's OWN winning recognizer, so it cannot be starved.
              //
              // Trade-off, deliberate: long press now keeps its native
              // select-word behaviour (which is what it actually did before — it
              // never copied), and the text stays selectable so a partial copy via
              // the system context menu still works. Tap-to-copy is also the more
              // discoverable affordance and makes the automation contract uniform:
              // `tap(key: settings_copy_tox_id_button)` — what the MCP drivers and
              // test/mcp/S31, S100 send — now copies on mobile exactly as it does
              // on the desktop `IconButton` that carries the same key.
              Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(
                  toxId,
                  key: UiKeys.settingsCopyToxIdButton,
                  onTap: copyToxId,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
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
                      value: autoLogin,
                      onChanged: (value) => unawaited(_setAutoLogin(value)),
                    ),
                  ],
                ),
              ),
              const Divider(height: AppSpacing.xl),
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
            ],
          ),
        ),
      ),
    );
  }

  // Moved here from `settings_page.dart` (complexity-gate pin): this is the
  // mobile account-management card, which belongs with the other mobile
  // widgets. Still an extension member, so every `_state` reference works
  // unchanged.
  Widget _buildMobileAccountManagementCard(
    BuildContext context,
    dynamic colorTheme,
  ) {
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;
    return Card(
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
            SectionHeader(
              title: AppLocalizations.of(context)!.accountManagement,
            ),
            AppSpacing.verticalMd,
            _buildAccountActionButtons(context),
            AppSpacing.verticalLg,
            Divider(height: 1, color: outlineVariant),
            AppSpacing.verticalMd,
            ..._accountList.map((account) {
              final accountToxId = account['toxId'] ?? '';
              final currentId =
                  _currentAccountToxId ?? widget.service.accountKey;
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
                ),
                subtitle: Text(
                  '${AppLocalizations.of(context)!.lastLogin}: ${_formatLastLoginTime(account['lastLoginTime'], context)}',
                ),
              );
            }),
            AppSpacing.verticalMd,
            OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: Text(AppLocalizations.of(context)!.importAccount),
              onPressed: _importInProgress ? null : _importAccount,
            ),
            // Only shown when there IS unclaimed pre-multi-account data. The
            // automatic migration requires provable ownership, which an
            // encrypted legacy profile cannot supply, so without this door that
            // user's history sits on disk with nothing pointing at it.
            if (_hasUnclaimedLegacyData) ...[
              AppSpacing.verticalSm,
              OutlinedButton.icon(
                key: const Key('settings_recover_legacy_data_button'),
                icon: const Icon(Icons.restore, size: 18),
                label: Text(
                  AppLocalizations.of(context)!.recoverLegacyDataAction,
                ),
                onPressed: _legacyRecoveryInProgress
                    ? null
                    : _recoverLegacyData,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Claim the pre-multi-account global data for the CURRENT account, on the
  /// user's explicit instruction. The data is merged at the next sign-in.
  ///
  /// The automatic path requires proof of ownership (the legacy profile's
  /// identity, or byte-identity with this account's own profile) because
  /// "whoever asks first" would hand one person's history to an unrelated local
  /// account. Neither proof is available when the legacy profile is encrypted —
  /// the passphrase is not in scope at claim time — so this is the door for that
  /// case. The user being logged into the account and asking IS the
  /// authorization; the claim is still recorded, so it stays exclusive.
  Future<void> _recoverLegacyData() async {
    final l10n = AppLocalizations.of(context)!;
    final toxId = widget.service.getSelfToxId();
    if (toxId == null || toxId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.recoverLegacyDataAction),
        content: Text(l10n.recoverLegacyDataConfirm),
        actions: [
          TextButton(
            onPressed: () => popDialogIfCurrent(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('settings_recover_legacy_data_confirm'),
            onPressed: () => popDialogIfCurrent(ctx, true),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _legacyRecoveryInProgress = true);
    try {
      // RECORD THE CLAIM ONLY — do not copy now.
      //
      // The running service has already loaded the chat history and the offline
      // queue into its own caches. Copying files underneath it means the next
      // write snapshots the stale in-memory state and overwrites what was just
      // recovered — e.g. a recovered queue replaced by the still-empty runtime
      // one on the next offline send.
      //
      // `initializeServiceForAccount` already performs the copy at the right
      // moment: it calls `migrateAccountDataFromLegacy` BEFORE `service.init()`,
      // so the caches load from the merged files. Claiming here and letting the
      // next sign-in do the copy needs no cache coordination at all.
      final granted = await LegacyAccountDataClaim.claimByUserRequest(toxId);
      if (!mounted) return;
      if (!granted) {
        AppSnackBar.showSuccess(context, l10n.recoverLegacyDataUnavailable);
        return;
      }
      // SIGN OUT IMMEDIATELY, closing the live-write interval.
      //
      // The merge happens at the next sign-in (before the caches load), but
      // leaving this session running means an offline send in the meantime
      // creates the destination queue — and the merge then has to reconcile two
      // queues rather than install one. Ending the session here removes that
      // interval entirely, and it is what the user has to do anyway.
      // Not `_logout()`: that asks for confirmation a second time, and
      // cancelling it would leave the claim committed with the session still
      // writing. See `_performLogout`.
      AppSnackBar.showSuccess(context, l10n.recoverLegacyDataClaimed);
      await _performLogout();
    } catch (e) {
      SafeDiagnostics.logFailure('[SettingsPage] legacy data recovery', e);
      if (mounted) {
        AppSnackBar.showError(context, l10n.recoverLegacyDataUnavailable);
      }
    } finally {
      if (mounted) {
        setState(() => _legacyRecoveryInProgress = false);
      }
      await _refreshUnclaimedLegacyData();
    }
  }

  Future<void> _refreshUnclaimedLegacyData() async {
    final has = await LegacyAccountDataClaim.hasUnclaimedLegacyData();
    if (!mounted) return;
    if (has != _hasUnclaimedLegacyData) {
      setState(() => _hasUnclaimedLegacyData = has);
    }
  }

}
