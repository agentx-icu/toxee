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
}
