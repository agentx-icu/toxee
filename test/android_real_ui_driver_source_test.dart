import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android real-UI shell uses the shared mobile navigation path', () {
    final source = File(
      'tool/mcp_test/drive_real_ui_pair_shell.dart',
    ).readAsStringSync();
    const startMarker = 'Future<bool> _dismissBackupWizardIfPresent';
    final start = source.indexOf(startMarker);

    expect(start, greaterThanOrEqualTo(0));

    final mobileShellRecovery = source.substring(start);
    expect(mobileShellRecovery, contains('inst.isMobileShell'));
    expect(
      mobileShellRecovery,
      isNot(contains('inst.isIos')),
      reason:
          'Android and iOS use the same bottom-navigation shell; only desktop '
          'should follow the sidebar/coordinate recovery path.',
    );
  });

  test('Android real-UI settings uses the shared mobile navigation path', () {
    final source = File(
      'tool/mcp_test/drive_real_ui_pair_settings.dart',
    ).readAsStringSync();
    const startMarker = 'Future<void> _openSettings';
    const endMarker = 'Future<bool> _settingsIsWide';
    final start = source.indexOf(startMarker);
    final end = source.indexOf(endMarker, start + startMarker.length);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final openSettings = source.substring(start, end);
    expect(openSettings, contains('inst.isMobileShell'));
    expect(openSettings, isNot(contains('inst.isIos')));
  });

  test('Android settings helpers use the shared mobile path', () {
    const path = 'tool/mcp_test/drive_real_ui_pair_settings.dart';
    final source = File(path).readAsStringSync();
    expect(source, contains('inst.isMobileShell'), reason: path);
    expect(source, isNot(contains('inst.isIos')), reason: path);

    final accountManagementStart = source.indexOf(
      'Future<bool> _openMobileAccountManagement',
    );
    final accountManagementEnd = source.indexOf(
      'Future<bool> _openMobileSettingsSection',
      accountManagementStart,
    );
    final accountManagement = source.substring(
      accountManagementStart,
      accountManagementEnd,
    );
    expect(
      accountManagement,
      contains("_openMobileSettingsSection(inst, 'Account Management')"),
    );
  });

  test('Android real-UI profile uses the compact settings entry', () {
    final source = File(
      'tool/mcp_test/drive_real_ui_pair_profile.dart',
    ).readAsStringSync();
    const startMarker = 'Future<bool> _openSelfProfile';
    const endMarker = '/// Dismiss the self-profile overlay';
    final start = source.indexOf(startMarker);
    final end = source.indexOf(endMarker, start + startMarker.length);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final openSelfProfile = source.substring(start, end);
    expect(openSelfProfile, contains('inst.isMobileShell'));
    expect(openSelfProfile, contains("_tryTapText(inst, 'Profile')"));
  });

  test(
    'P1 home-tab selector picks bottom navigation by LAYOUT, not platform',
    () {
      final p1 = File(
        'tool/mcp_test/drive_real_ui_pair_p1_single.dart',
      ).readAsStringSync();
      final start = p1.indexOf('Future<bool> _p1SelectHomeTab');
      final end = p1.indexOf('Future<bool> _p1OpenLanguageSettings', start);
      final selector = p1.substring(start, end);
      // The selector must resolve the bottom-nav twin from the LIVE layout
      // (`_homeShellHasBottomNav` resolves the real `home_bottom_nav` key), NOT
      // from `Inst.isMobileShell` — that is `isIos || isAndroid`, which an iPad
      // satisfies while still rendering the WIDE sidebar shell, so the old
      // platform test aimed every tab tap at a `bottom_nav_*` id that iPadOS
      // never builds (live iPad red: zh_locale_page_walk, contactsOpened=false).
      expect(selector, contains('_homeShellHasBottomNav(inst)'));
      expect(selector, isNot(contains('inst.isMobileShell')));
      expect(selector, contains('bottom_nav_chats_tab'));
      expect(selector, contains('bottom_nav_contacts_tab'));
      expect(selector, contains('bottom_nav_settings_tab'));
    },
  );

  test('Group profile opener is single-fire on onstage avatars', () {
    final source = File(
      'tool/mcp_test/drive_real_ui_pair_group_profile.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _openGroupProfile');
    final end = source.indexOf('Future<bool> _waitGroupShowName', start);
    final opener = source.substring(start, end);
    expect(opener, contains("keyCenter('message_header_profile_avatar')"));
    expect(opener, contains("tapKeyCenter('message_header_profile_avatar'"));
    expect(opener, contains("tapKey('message_header_profile_avatar')"));
    expect(opener, contains("tryTapKey('message_header_profile_avatar'"));
    final home = File('lib/ui/home_page.dart').readAsStringSync();
    expect(home, contains('Future<void> _popOverlayRoutes() async'));
    expect(home, contains('await _popOverlayRoutes()'));
    expect(home, contains('WidgetsBinding.instance.endOfFrame'));
  });

  test('Group profile builder restore is owner guarded', () {
    final source = File(
      'lib/ui/group/group_builder_override.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('static GroupProfileBuilderOverrideHandle? _activeOwner'),
    );
    expect(source, contains('_activeOwner = this'));
    expect(source, contains('identical(_activeOwner, this)'));
    expect(source, contains('_activeOwner = null'));
  });

  test(
    'Contact and conversation builders preserve the active HomePage owner',
    () {
      final contact = File(
        'lib/ui/contact/contact_builder_override.dart',
      ).readAsStringSync();
      expect(
        contact,
        contains('static ContactBuilderOverrideHandle? _activeOwner'),
      );
      expect(contact, contains('_activeOwner = handle'));
      expect(contact, contains('identical(_activeOwner, this)'));

      final home = File('lib/ui/home_page_bootstrap.dart').readAsStringSync();
      expect(home, contains('final conversationBuilderOwner = Object()'));
      expect(home, contains('_activeConversationBuilderOwner'));
      expect(home, contains('_activeConversationBuilderOwner'));
    },
  );

  test('Fork group profile body exposes its mobile list viewport', () {
    final source = File(
      'third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/group_profile_widgets/tencent_cloud_chat_group_profile_body.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Widget defaultBuilder(BuildContext context) {',
      source.indexOf('class TencentCloudChatGroupProfileBodyState'),
    );
    final end = source.indexOf(
      'class TencentCloudChatGroupProfileAvatar',
      start,
    );
    final body = source.substring(start, end);
    expect(body, contains('LayoutBuilder'));
    expect(body, contains('constraints.hasBoundedHeight'));
    expect(body, contains('MediaQuery.sizeOf(context).height'));
    expect(body, contains('height: height'));
    expect(body, contains('SizedBox'));
    expect(body, contains("key: const ValueKey('group_profile_scroll_view')"));
    expect(
      body,
      contains("key: const ValueKey('group_profile_scroll_anchor')"),
    );
  });

  test('Mobile settings logout pops pushed sections before teardown', () {
    final source = File(
      'lib/ui/settings/settings_page.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _logout() async');
    final end = source.indexOf('/// Used by settings_page_build.dart', start);
    final logout = source.substring(start, end);
    final teardown = logout.indexOf('_teardownSession');
    expect(logout, contains('final homeRoute = ModalRoute.of(context);'));
    expect(
      logout,
      contains('final navigator = Navigator.of(context, rootNavigator: true);'),
    );
    expect(logout, contains('navigator.popUntil'));
    expect(logout, contains('identical(route, homeRoute)'));
    expect(
      logout.indexOf('final homeRoute'),
      lessThan(logout.indexOf('showDialog')),
    );
    expect(
      logout.indexOf('final navigator'),
      lessThan(logout.indexOf('showDialog')),
    );
    expect(logout.indexOf('popUntil'), lessThan(teardown));
  });

  test('Optimized settings sweep follows the active layout', () {
    final source = File(
      'tool/mcp_test/drive_real_ui_pair_optimized.dart',
    ).readAsStringSync();
    const startMarker = 'Future<int> runSingleAppOptimizedSweep';
    const endMarker = 'Future<int> runC2cOptimizedSweep';
    final start = source.indexOf(startMarker);
    final end = source.indexOf(endMarker, start + startMarker.length);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final optimized = source.substring(start, end);
    expect(optimized, contains('a.isMobileShell'));
    expect(optimized, contains('runIosSettingsMainSweep'));
    expect(optimized, contains('runSettingsSweep2'));
  });

  test('Profile QR copy reports an honest platform skip', () {
    final profile = File(
      'tool/mcp_test/drive_real_ui_pair_profile.dart',
    ).readAsStringSync();
    expect(profile, contains('Future<bool?> _profileQrCopy'));
    expect(profile, contains('inst.isMobileShell || inst.isLinux'));
    expect(profile, contains('unexpectedSkipped'));

    final driver = File(
      'tool/mcp_test/drive_real_ui_pair.dart',
    ).readAsStringSync();
    const startMarker = "if (scenario == 'profile_qr_copy')";
    const endMarker = "if (scenario == 'profile_avatar_picker_opens')";
    final start = driver.indexOf(startMarker);
    final end = driver.indexOf(endMarker, start + startMarker.length);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final dispatch = driver.substring(start, end);
    expect(dispatch, contains('null => 75'));
  });

  test('Android chat readiness recognizes the compact route', () {
    final message = File(
      'tool/mcp_test/drive_real_ui_pair_message_call.dart',
    ).readAsStringSync();
    const readyStart = 'Future<bool> _chatSurfaceReady';
    const readyEnd = '/// Whether ANY of';
    final readyBegin = message.indexOf(readyStart);
    final readyFinish = message.indexOf(
      readyEnd,
      readyBegin + readyStart.length,
    );
    expect(readyBegin, greaterThanOrEqualTo(0));
    expect(readyFinish, greaterThan(readyBegin));

    final ready = message.substring(readyBegin, readyFinish);
    expect(ready, contains('inst.isAndroid'));
    expect(ready, contains("inst.keyCenter('chat_input_text_field')"));
    expect(ready, contains('currentConversation == conversationId'));

    final chat = File(
      'tool/mcp_test/drive_real_ui_pair_chat.dart',
    ).readAsStringSync();
    const ensureStart = 'Future<bool> _ensureChatOpen';
    const ensureEnd = '/// The ORDERED list of message entries';
    final ensureBegin = chat.indexOf(ensureStart);
    final ensureFinish = chat.indexOf(
      ensureEnd,
      ensureBegin + ensureStart.length,
    );
    expect(ensureBegin, greaterThanOrEqualTo(0));
    expect(ensureFinish, greaterThan(ensureBegin));

    final ensure = chat.substring(ensureBegin, ensureFinish);
    expect(ensure, contains('inst.isMobileShell'));
    expect(ensure, contains('openChatViaL3'));
  });

  test('Android login settings uses mobile section navigation', () {
    final source = File(
      'tool/mcp_test/drive_real_ui_pair_login.dart',
    ).readAsStringSync();

    expect(source, contains('if (inst.isMobileShell)'));
    expect(source, contains('!inst.isMobileShell'));
    expect(source, contains('final onScreen = inst.isMobileShell'));
    expect(source, contains('_openMobileAccountManagement(inst)'));
    // Keep the separately justified iOS retry policy scoped to iOS until it is
    // independently validated on Android.
    expect(source, contains('(_isWindowsRealUi || inst.isMobileShell)'));
  });

  test('Android group chat opening validates the compact route identity', () {
    final source = File(
      'tool/mcp_test/drive_real_ui_pair_group.dart',
    ).readAsStringSync();
    const startMarker = 'Future<bool> _openAndroidGroupChatViaL3';
    const endMarker = 'class _CreatedGroup';
    final start = source.indexOf(startMarker);
    final end = source.indexOf(endMarker, start + startMarker.length);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final groupSource = source.substring(start, end);
    expect(groupSource, contains('inst.isMobileShell'));
    expect(groupSource, contains("result['conversationId']"));
    expect(groupSource, contains('expectedConversationId'));
    expect(groupSource, contains("keyCenter('chat_input_text_field')"));
    expect(groupSource, contains('Future<void> openGroupChat'));
  });

  test('Android P1 and app-entry boundaries use mobile-safe paths', () {
    // The OS-input primitives (setClipboard / osa* and their synthetic
    // substitutes) moved out of drive_real_ui_pair_inst.dart into the
    // `InstOsInput` extension part on 2026-08-16, when that file had to make
    // room for the `_l3TestGated` recovery. Same library, same members — only
    // the file changed, so this test follows them there.
    final inst = File(
      'tool/mcp_test/drive_real_ui_pair_inst_os_input.dart',
    ).readAsStringSync();
    const clipboardStart = 'Future<void> setClipboard';
    final clipboardBegin = inst.indexOf(clipboardStart);
    final clipboardEnd = inst.indexOf(
      'Future<void> osaClear',
      clipboardBegin + clipboardStart.length,
    );
    expect(clipboardBegin, greaterThanOrEqualTo(0));
    expect(clipboardEnd, greaterThan(clipboardBegin));
    // The guard widened from `_isHeadlessRealUi || isAndroid` to
    // `_usesSyntheticInput || isAndroid`. `_usesSyntheticInput` is
    // `isIos || _isHeadlessRealUi`, so iOS now takes the in-app
    // `l3_set_clipboard` seam too — previously it fell through to the host
    // `pbcopy` and depended on Simulator<->host pasteboard sync. `isAndroid`
    // is retained because `_isHeadlessRealUi` reads the GLOBAL platform while
    // `isAndroid` is per-instance (a heterogeneous pair can carry an Android
    // peer under a macOS global).
    expect(
      inst.substring(clipboardBegin, clipboardEnd),
      contains('_usesSyntheticInput || isAndroid'),
    );

    final p1 = File(
      'tool/mcp_test/drive_real_ui_pair_p1_single.dart',
    ).readAsStringSync();
    expect(p1, contains('Future<bool> _p1OpenLanguageSettings'));
    expect(p1, contains("_openMobileSettingsSection(inst, 'Appearance')"));
    expect(p1, contains('Future<void> _p1LeaveLanguageSettings'));
    final renameStart = p1.indexOf('Future<bool> _p1ConferenceRenameLeave');
    final renameEnd = p1.indexOf(
      'Future<bool> _p1SettingsSwitchAccountEntry',
      renameStart,
    );
    final renameFlow = p1.substring(renameStart, renameEnd);
    expect(RegExp(r'openGroupChat\(').allMatches(renameFlow), hasLength(1));
    expect(renameFlow, contains('tapAt(28, 52)'));

    final p1Extra = File(
      'tool/mcp_test/drive_real_ui_pair_p1_extra.dart',
    ).readAsStringSync();
    expect(p1Extra, contains('Future<bool?> _p1eKeyboardGlobalSearchShortcut'));
    expect(p1Extra, contains('platform-hidden'));
    expect(p1Extra, contains('unexpectedSkipped'));

    final appEntry = File(
      'tool/mcp_test/drive_real_ui_pair_app_entry_extra.dart',
    ).readAsStringSync();
    expect(appEntry, contains('Future<bool?> _aeeAddFriendPasteClipboard'));
    expect(appEntry, contains('Future<bool?> _aeeIrcJoinChannelLoopbackLive'));
    expect(appEntry, contains('inst.isAndroid'));
    expect(appEntry, contains('add_friend_paste_clipboard'));
    expect(appEntry, contains('unexpectedSkipped'));
  });

  test('Mobile settings index navigation uses stable keys', () {
    final keys = File('lib/ui/testing/ui_keys.dart').readAsStringSync();
    for (final key in [
      'settingsMobileProfileTile',
      'settingsMobileAccountInfoSection',
      'settingsMobileAccountManagementSection',
      'settingsMobileAppearanceSection',
      'settingsMobileGeneralSection',
      'settingsMobileBootstrapSection',
    ]) {
      expect(keys, contains(key));
    }

    final settings = File(
      'lib/ui/settings/settings_page.dart',
    ).readAsStringSync();
    expect(settings, contains('UiKeys.settingsMobileProfileTile'));
    expect(settings, contains('UiKeys.settingsMobileAppearanceSection'));
    expect(settings, contains('UiKeys.settingsMobileGeneralSection'));

    final driver = File(
      'tool/mcp_test/drive_real_ui_pair_settings.dart',
    ).readAsStringSync();
    expect(driver, contains('settings_mobile_appearance_section'));
    expect(driver, contains('settings_mobile_account_management_section'));

    final profile = File(
      'tool/mcp_test/drive_real_ui_pair_profile.dart',
    ).readAsStringSync();
    expect(profile, contains('settings_mobile_profile_tile'));
  });

  test('Compact mobile account deletion uses account management settings', () {
    final p1 = File(
      'tool/mcp_test/drive_real_ui_pair_p1_single.dart',
    ).readAsStringSync();
    final deleteStart = p1.indexOf('Future<bool> _p1AccountDeleteFullFlow');
    final deleteEnd = p1.indexOf('Future<bool> _p1EnsureCleanEnd', deleteStart);
    expect(deleteStart, greaterThanOrEqualTo(0));
    expect(deleteEnd, greaterThan(deleteStart));
    final deleteFlow = p1.substring(deleteStart, deleteEnd);
    expect(deleteFlow, contains('compactMobile'));
    expect(deleteFlow, contains('_openMobileAccountManagement(inst)'));

    final accountConf = File(
      'tool/mcp_test/drive_real_ui_pair_account_conf_extra.dart',
    ).readAsStringSync();
    final cancelStart = accountConf.indexOf(
      'Future<bool> _aceSettingsDeleteAccountCancel',
    );
    final cancelEnd = accountConf.indexOf(
      'Future<bool> _aceConferenceProfileIdSurface',
      cancelStart,
    );
    expect(cancelStart, greaterThanOrEqualTo(0));
    expect(cancelEnd, greaterThan(cancelStart));
    final cancelFlow = accountConf.substring(cancelStart, cancelEnd);
    expect(cancelFlow, contains('compactMobile'));
    expect(cancelFlow, contains('_openMobileAccountManagement(inst)'));
  });

  test('Account and conference sweeps preserve mobile-only route evidence', () {
    final p1 = File(
      'tool/mcp_test/drive_real_ui_pair_p1_single.dart',
    ).readAsStringSync();
    final p1SwitchStart = p1.indexOf(
      'Future<bool> _p1SettingsSwitchAccountEntry',
    );
    final p1SwitchEnd = p1.indexOf(
      'Future<bool> _p1AccountCardManagementMenu',
      p1SwitchStart,
    );
    final p1Switch = p1.substring(p1SwitchStart, p1SwitchEnd);
    expect(p1Switch, contains('compactMobile'));
    expect(p1Switch, contains('_openMobileAccountManagement(inst)'));

    final accountConf = File(
      'tool/mcp_test/drive_real_ui_pair_account_conf_extra.dart',
    ).readAsStringSync();
    final accountSwitchStart = accountConf.indexOf(
      'Future<bool> _aceSettingsSwitchAccountCancel',
    );
    final accountSwitchEnd = accountConf.indexOf(
      'Future<bool> _aceLoginAccountDeleteCancel',
      accountSwitchStart,
    );
    final accountSwitch = accountConf.substring(
      accountSwitchStart,
      accountSwitchEnd,
    );
    expect(accountSwitch, contains('compactMobile'));
    expect(accountSwitch, contains('_openMobileAccountManagement(inst)'));
    expect(
      accountConf,
      contains('Future<bool?> _aceConferenceSearchResultOpens'),
    );
    expect(accountConf, contains('conference_search_result_opens'));

    final group = File(
      'tool/mcp_test/drive_real_ui_pair_group2.dart',
    ).readAsStringSync();
    final profileScrollStart = group.indexOf(
      'Future<({double x, double y})?> _scrollProfileButtonIntoBand',
    );
    final profileScrollEnd = group.indexOf(
      'Future<String?> _memberRowKeyFor',
      profileScrollStart,
    );
    final profileScroll = group.substring(profileScrollStart, profileScrollEnd);
    expect(profileScroll, contains('inst.isMobileShell'));
    expect(profileScroll, contains('_viewHeight(inst, key)'));
    expect(profileScroll, contains("dragBy('group_profile_scroll_view'"));
    expect(profileScroll, contains('dy: -420'));
    expect(profileScroll, contains('steps: 16'));
    expect(profileScroll, contains('key_not_found'));

    final leaveStart = group.indexOf(
      'Future<bool> _groupLeaveViaProfileConfirm',
    );
    final leaveEnd = group.indexOf(
      'Future<String> _confCreateDialogSurface',
      leaveStart,
    );
    final leaveFlow = group.substring(leaveStart, leaveEnd);
    expect(leaveFlow, contains('leaveCenter == null'));
    expect(
      RegExp(r'_openGroupProfileClean\(inst, gid\)').allMatches(leaveFlow),
      hasLength(greaterThan(1)),
    );
    expect(group, contains('inst.forceHomeRoot(tab: \'chats\')'));
    expect(leaveFlow, contains('offscreenLeaveTapped'));
    expect(leaveFlow, contains('inst.tapKey('));

    final genericGroup = File(
      'tool/mcp_test/drive_real_ui_pair_group.dart',
    ).readAsStringSync();
    final createStart = genericGroup.indexOf(
      'Future<_CreatedGroup> _createGroupViaUI',
    );
    final createEnd = genericGroup.indexOf(
      'Future<void> _inviteToGroupViaUI',
      createStart,
    );
    final createFlow = genericGroup.substring(createStart, createEnd);
    expect(createFlow, contains('inst.isMobileShell'));
    expect(
      createFlow,
      contains("_revealDialogKey(inst, 'add_group_create_name_input')"),
    );
    // The submit is prepared through `_prepareDialogSubmit` (hide the soft
    // keyboard first — a key-addressed tap with the iOS keyboard up dismissed
    // the dialog without creating, live iPhone 2026-08-23), not revealed by the
    // barrier-dragging `_revealDialogKey`.
    expect(
      createFlow,
      contains("_prepareDialogSubmit(inst, 'add_group_create_submit_button')"),
    );
    expect(
      createFlow,
      isNot(
        contains("_revealDialogKey(inst, 'add_group_create_submit_button')"),
      ),
    );

    final accountDeep = File(
      'tool/mcp_test/drive_real_ui_pair_high_value_extra.dart',
    ).readAsStringSync();
    final primaryActive = accountDeep.indexOf('final primaryActiveBefore');
    final firstLogout = accountDeep.indexOf(
      '_logoutToLoginPage(inst)',
      primaryActive,
    );
    final beforeLogout = accountDeep.substring(primaryActive, firstLogout);
    expect(beforeLogout, contains('returnToChatsHome(inst, rounds: 4)'));
    expect(beforeLogout, contains('inst.isMobileShell'));
    // Was `inst.osaOpenSettingsShortcut()` — a Cmd+Ctrl+, chord, which is a
    // no-op on iOS and, on Android, only ever resolved to `forceHomeRoot`
    // anyway. Nothing in this case tests a keyboard chord, so the mobile
    // branch now calls the deterministic navigation seam DIRECTLY. Pinning
    // the seam (not the chord) is what keeps this case honest on a shell
    // that has no keyboard at all.
    // (Only the CALL is pinned, not the absence of the old name — the driver
    // comment still cites `osaOpenSettingsShortcut` to explain the swap, and
    // that rationale is worth keeping.)
    expect(beforeLogout, contains("forceHomeRoot(tab: 'settings')"));

    // `Inst` now spans two part files (the OS-input primitives moved to the
    // InstOsInput extension — see the note above), and this block pins members
    // from BOTH. Concatenate them so the assertions stay about the CLASS rather
    // than about which file a member happens to sit in.
    final instSource =
        File('tool/mcp_test/drive_real_ui_pair_inst.dart').readAsStringSync() +
        File(
          'tool/mcp_test/drive_real_ui_pair_inst_os_input.dart',
        ).readAsStringSync();
    final settingsShortcutStart = instSource.indexOf(
      'Future<void> osaOpenSettingsShortcut',
    );
    final settingsShortcutEnd = instSource.indexOf(
      'Future<void> setClipboard',
      settingsShortcutStart,
    );
    final settingsShortcut = instSource.substring(
      settingsShortcutStart,
      settingsShortcutEnd,
    );
    expect(settingsShortcut, contains('waitState'));
    expect(settingsShortcut, contains("s['homeShellTab'] == 'settings'"));
    expect(instSource, contains('navToolsUnavailable = true'));
    final focusTypeStart = instSource.indexOf('Future<bool> focusType');
    final focusTypeEnd = instSource.indexOf(
      'Future<void> focusTypeSynthetic',
      focusTypeStart,
    );
    final focusType = instSource.substring(focusTypeStart, focusTypeEnd);
    expect(focusType, contains("getTextValue', {'key': key}"));
    expect(focusType, contains("enterText', {'key': key, 'text': text}"));

    final shellSource = File(
      'tool/mcp_test/drive_real_ui_pair_shell.dart',
    ).readAsStringSync();
    expect(shellSource, contains('navToolsUnavailable && !inst.isMobileShell'));
    expect(shellSource, contains('inst.tryTapContactDetailBack()'));
    expect(
      shellSource.indexOf('inst.tryTapContactDetailBack()'),
      lessThan(shellSource.indexOf("_tryTapText(inst, 'Back')")),
    );

    // The mark -> retry -> unmark recovery is no longer inlined in
    // forceHomeRoot: it was hoisted into `_l3TestGated` (2026-08-16) so the
    // OTHER test-gated seams get it too. A real-UI account is a PRODUCT account,
    // and a swallowed `non_test_account` on a STATE seam is worse than a loud
    // failure — an unbound `l3_clear_active_conversation` leaves the active peer
    // bound, and `getC2CUnreadCount` then reports 0 for it forever, making every
    // unread assertion downstream unfalsifiable.
    final gatedStart = instSource.indexOf(
      'Future<Map<String, dynamic>> _l3TestGated',
    );
    final gatedEnd = instSource.indexOf(
      'Future<void> clearActiveConversation',
      gatedStart,
    );
    final gated = instSource.substring(gatedStart, gatedEnd);
    expect(gated, contains("r['error'] == 'non_test_account'"));
    expect(gated, contains('final marked = await markAccountTest()'));
    expect(gated, contains('if (marked) await unmarkAccountTest()'));

    final forceHomeStart = instSource.indexOf('Future<void> forceHomeRoot');
    final forceHomeEnd = instSource.indexOf(
      'Future<bool> openAddFriendDialogViaL3',
      forceHomeStart,
    );
    final forceHome = instSource.substring(forceHomeStart, forceHomeEnd);
    expect(forceHome, contains("_l3TestGated('l3_force_home_root'"));
    expect(forceHome, contains('navToolsUnavailable = true'));
    expect(forceHome, contains("_l3TestGated('l3_pop_to_root')"));
    // The seam whose silent refusal produced a VACUOUS unread baseline.
    final clearStart = instSource.indexOf(
      'Future<void> clearActiveConversation',
    );
    final clearEnd = instSource.indexOf(
      'Future<void> forceHomeRoot',
      clearStart,
    );
    expect(
      instSource.substring(clearStart, clearEnd),
      contains("_l3TestGated('l3_clear_active_conversation')"),
    );

    final l3Tools = File(
      'lib/ui/testing/l3_debug_tools.dart',
    ).readAsStringSync();
    final composerSetStart = l3Tools.indexOf(
      'MCPCallEntry _l3ComposerSetTextEntry',
    );
    final composerSetEnd = l3Tools.indexOf(
      'MCPCallEntry _l3RegisterAccountEntry',
      composerSetStart,
    );
    final composerSet = l3Tools.substring(composerSetStart, composerSetEnd);
    expect(composerSet, contains('debugRealUiDesktopComposerSetText'));
    expect(composerSet, contains('debugRealUiMobileComposerSetText'));
    final forceRootStart = l3Tools.indexOf(
      'MCPCallEntry _l3ForceHomeRootEntry',
    );
    final forceRootEnd = l3Tools.indexOf(
      'MCPCallEntry _l3OpenGlobalSearchEntry',
      forceRootStart,
    );
    final forceRoot = l3Tools.substring(forceRootStart, forceRootEnd);
    final popCall = forceRoot.indexOf('_l3PopToRootInvoker');
    final shellCall = forceRoot.indexOf('_l3HomeShellApplier');
    expect(popCall, greaterThanOrEqualTo(0));
    expect(shellCall, greaterThan(popCall));
    expect(forceRoot, contains('await popToRoot()'));

    final isolationStart = accountDeep.indexOf(
      'Future<bool> _hveAccountMultiAccountStateIsolation',
    );
    final isolationEnd = accountDeep.indexOf(
      'const _groupConfDeepExtraCases',
      isolationStart,
    );
    final isolation = accountDeep.substring(isolationStart, isolationEnd);
    expect(isolation, contains('final marked = await inst.markAccountTest()'));
    expect(isolation, contains('if (marked) await inst.unmarkAccountTest()'));
    expect(isolation, contains('inst.isAndroid'));
    expect(isolation, contains("_homeShellTab(inst) == 'chats'"));
    expect(isolation, contains("keyCenter('chat_input_text_field')"));

    final homeBootstrap = File(
      'lib/ui/home_page_bootstrap.dart',
    ).readAsStringSync();
    expect(
      homeBootstrap,
      contains('final homeRoute = ModalRoute.of(context);'),
    );
    expect(homeBootstrap, contains('final navigator = Navigator.of(context);'));
    expect(homeBootstrap, contains('!navigator.mounted'));
    expect(homeBootstrap, contains('!homeRoute.isActive'));
    expect(homeBootstrap, contains('navigator.popUntil'));
    expect(homeBootstrap, contains('on Object catch (e, st)'));
    expect(homeBootstrap, contains('attempt < 12'));
    expect(homeBootstrap, contains('!_debugLocked'));
    expect(homeBootstrap, contains('homeRoute.isCurrent'));
    expect(homeBootstrap, contains('WidgetsBinding.instance.endOfFrame'));
    expect(homeBootstrap, contains('milliseconds: 100'));
    expect(homeBootstrap, contains('AppLogger.logError'));
    expect(homeBootstrap, contains('final openAddGroupDialogInvoker'));
    expect(homeBootstrap, contains('currentL3OpenAddGroupDialogInvoker'));
    expect(homeBootstrap, contains('final popToRootInvoker'));
    expect(homeBootstrap, contains('currentL3PopToRootInvoker'));
    expect(homeBootstrap, contains('final openGroupProfileInvoker'));
    expect(homeBootstrap, contains('currentL3OpenGroupProfileInvoker'));
  });
}
