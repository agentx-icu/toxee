// Real-UI gates for the PHONE settings shell — the `ResponsiveLayout.isMobile`
// branch of the production `SettingsPage` (`_buildMobileSettingsIndex`,
// `_pushMobileSettingsSection`, `_openMobileProfile`) plus the phone/desktop
// presentation fork inside `showSelfProfile`.
//
// Why this file exists: `_isDesktopPlatform()` reads `dart:io` `Platform.*`,
// which `debugDefaultTargetPlatformOverride` does NOT affect, so before
// `ResponsiveLayout.debugIsDesktopPlatformOverride` existed `isMobile` was
// hard-false in every widget test on the desktop CI host and the entire phone
// settings surface (a drill-down index of section pages instead of one long
// list) was unreachable from `flutter test` no matter how small the viewport.
// Every test here sets the override to `() => false` in `setUp` and clears it
// in `tearDown` (it is process-global).
//
// What is driven, in order, all on REAL production controls:
//   * the real section `ListTile` -> real `_pushMobileSettingsSection` route ->
//     real `UiKeys.settingsMobileSectionBackButton` -> route pops;
//   * the real `UiKeys.settingsAutoLoginSwitch` INSIDE that pushed section ->
//     asserted against `Prefs.getAutoLogin(toxId)` (real persistence, not a
//     widget-only flip);
//   * the real profile `ListTile` -> real `_openMobileProfile` ->
//     `showSelfProfile`, whose presentation forks on
//     `ResponsiveLayout.shouldShowBottomNav` (viewport WIDTH < 720):
//       - portrait phone 390x844  -> fullscreen `MaterialPageRoute` (AppBar +
//         `UiKeys.profileCloseButton`), NO `AppDialog`;
//       - landscape phone 844x390 -> `showDialog` + `AppDialog`, NO AppBar.
//     The landscape case is the deliberately counter-intuitive combination:
//     shortestSide 390 keeps the device in the MOBILE tier (the drill-down
//     index still renders) while width 844 >= 720 puts the layout in the
//     sidebar/dialog tier. Both facts are asserted through rendered widgets,
//     not through boolean helpers.
//
// Mobile parity: `SettingsPage`, `showSelfProfile` and `ProfilePage` are shared
// Dart (`lib/ui/settings/`, `lib/ui/profile/`) with no per-OS fork — only the
// width fork above — so these gates cover iOS and Android.
//
// Harness: reuses `test/ui/settings/settings_account_test_support.dart` (the
// stub `FfiChatService`, the full l10n delegate set, the channel mocks and the
// bounded `settleSettings` pump). `pumpAndSettle` is NOT used: the profile QR
// section holds a perpetual `CircularProgressIndicator`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/ui/widgets/app_dialog.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/responsive_layout.dart';

import '../settings/settings_account_test_support.dart';

/// iPhone-class portrait phone: shortestSide 390 (< 600 mobile breakpoint) and
/// width 390 (< 720 large-phone breakpoint) -> bottom-nav tier.
const Size _portraitPhone = Size(390, 844);

/// The SAME phone rotated. shortestSide is still 390 (still the mobile tier and
/// still the drill-down settings index) but width 844 crosses BOTH the 720
/// large-phone breakpoint and the 800 master-detail breakpoint.
const Size _landscapePhone = Size(844, 390);

/// Section-tile leading icons (settings_page.dart `_buildMobileSettingsIndex`).
/// Matched by icon rather than by localized label so the gate does not break on
/// a copy change.
const IconData _accountInfoTileIcon = Icons.badge_outlined;

/// Trailing icon of the profile card at the top of the mobile index.
const IconData _profileCardIcon = Icons.edit_outlined;

/// The mobile index renders exactly five drill-down section tiles (account
/// info, account management, appearance, general, bootstrap nodes), each with a
/// trailing chevron. The desktop branch renders none.
const int _sectionTileCount = 5;

void _usePhoneSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpSettings(WidgetTester tester, FfiChatService service) async {
  await tester.pumpWidget(
    settingsApp(
      SettingsPage(
        service: service,
        connectionStatusStream: service.connectionStatusStream,
        autoAcceptFriends: false,
        onAutoAcceptFriendsChanged: (_) {},
        autoAcceptGroupInvites: false,
        onAutoAcceptGroupInvitesChanged: (_) {},
      ),
    ),
  );
  await settleSettings(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late SettingsChannelMocks mocks;

  setUp(() async {
    // THE seam: without this every `ResponsiveLayout.isMobile` call returns
    // false on the desktop test host and `SettingsPage` renders its desktop
    // list, making every assertion below unreachable.
    ResponsiveLayout.debugIsDesktopPlatformOverride = () => false;

    tempRoot = await Directory.systemTemp.createTemp('settings_mobile_index_');
    mocks = SettingsChannelMocks.install(tempRoot);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Phone Nick');
    await Prefs.setStatusMessage('Phone Status');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Phone Nick');
  });

  tearDown(() {
    // Process-global: leaving it set would silently flip every later suite in
    // the same runner process into the mobile branch.
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
    mocks.teardown();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  testWidgets(
    'portrait phone: settings renders the drill-down index; the section tile '
    'pushes the account-info page and its back button pops it',
    (WidgetTester tester) async {
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);
      _usePhoneSurface(tester, _portraitPhone);

      await _pumpSettings(tester, service);

      // Branch discriminator: the mobile index shows five chevroned section
      // tiles and NO inline auto-login switch. The desktop branch is the exact
      // inverse (inline switch, no section tiles), so these two assertions
      // together prove `_buildMobileSettingsIndex` is what rendered.
      expect(
        find.byIcon(Icons.chevron_right),
        findsNWidgets(_sectionTileCount),
        reason: 'phone settings must render the drill-down section tiles',
      );
      expect(
        find.byKey(UiKeys.settingsAutoLoginSwitch),
        findsNothing,
        reason:
            'on phone the auto-login switch lives one level down, not on the '
            'index (it is inline only in the desktop list)',
      );
      expect(
        find.byKey(UiKeys.settingsMobileSectionBackButton),
        findsNothing,
        reason: 'no section page is pushed yet',
      );

      // REAL TAP on the production "Account info" ListTile -> its onTap runs
      // `_pushMobileSettingsSection(...)`.
      await tester.tap(find.widgetWithIcon(ListTile, _accountInfoTileIcon));
      await settleSettings(tester);

      expect(
        find.byKey(UiKeys.settingsMobileSectionBackButton),
        findsOneWidget,
        reason: 'the tap must push the section Scaffold with its back button',
      );
      expect(
        find.byKey(UiKeys.settingsAutoLoginSwitch),
        findsOneWidget,
        reason: 'the pushed page must carry the account-info card content',
      );
      // The pushed card shows the REAL resolved account id, not a placeholder.
      expect(
        tester
            .widget<SelectableText>(find.byKey(UiKeys.settingsCopyToxIdButton))
            .data,
        kSettingsToxId,
        reason: 'the section page must render the resolved account Tox ID',
      );

      // REAL TAP on the production back button -> Navigator.maybePop().
      await tester.tap(find.byKey(UiKeys.settingsMobileSectionBackButton));
      await settleSettings(tester);

      expect(
        find.byKey(UiKeys.settingsMobileSectionBackButton),
        findsNothing,
        reason: 'back must pop the section route',
      );
      expect(
        find.byKey(UiKeys.settingsAutoLoginSwitch),
        findsNothing,
        reason: 'the popped section content must unmount',
      );
      expect(
        find.byIcon(Icons.chevron_right),
        findsNWidgets(_sectionTileCount),
        reason: 'the index is restored underneath',
      );
    },
  );

  testWidgets(
    'portrait phone: the auto-login switch inside the pushed section persists '
    'to Prefs',
    (WidgetTester tester) async {
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);
      _usePhoneSurface(tester, _portraitPhone);

      await _pumpSettings(tester, service);
      await tester.tap(find.widgetWithIcon(ListTile, _accountInfoTileIcon));
      await settleSettings(tester);

      final switchFinder = find.byKey(UiKeys.settingsAutoLoginSwitch);
      expect(
        tester.widget<Switch>(switchFinder).value,
        isTrue,
        reason: 'auto-login defaults to on for a freshly seeded account',
      );

      await tester.ensureVisible(switchFinder);
      await settleSettings(tester);
      await tester.tap(switchFinder);
      await settleSettings(tester);

      expect(
        tester.widget<Switch>(switchFinder).value,
        isFalse,
        reason: 'the real Switch must reflect the flip',
      );
      expect(
        await Prefs.getAutoLogin(kSettingsToxId),
        isFalse,
        reason:
            'the phone drill-down path must reach the same `_setAutoLogin` '
            'persistence the desktop list uses',
      );
    },
  );

  testWidgets(
    'portrait phone: the profile card opens the FULLSCREEN profile route (no '
    'dialog) and its close button pops it',
    (WidgetTester tester) async {
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);
      _usePhoneSurface(tester, _portraitPhone);

      await _pumpSettings(tester, service);

      expect(
        find.byKey(UiKeys.profileToxIdSelectableText),
        findsNothing,
        reason: 'no profile is open before the tap',
      );

      // REAL TAP on the production profile card -> `_openMobileProfile` ->
      // `showSelfProfile` (resolves the Tox ID from Prefs, then routes).
      await tester.tap(find.widgetWithIcon(ListTile, _profileCardIcon));
      await settleSettings(tester);

      // Width 390 < 720 -> `shouldShowBottomNav` -> the fullscreen route fork.
      expect(
        find.byType(AppDialog),
        findsNothing,
        reason: 'a phone-width viewport must NOT get the desktop dialog fork',
      );
      expect(
        find.byType(AppBar),
        findsOneWidget,
        reason:
            'the fullscreen route supplies the only AppBar in the tree (the '
            'harness Scaffold has none)',
      );
      expect(
        find.byKey(UiKeys.profileCloseButton),
        findsOneWidget,
        reason: 'the fullscreen route renders the close affordance',
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(UiKeys.profileToxIdSelectableText),
            )
            .data,
        kSettingsToxId,
        reason: 'the opened profile must show the resolved account Tox ID',
      );

      // REAL TAP on the route's close button -> Navigator.maybePop().
      await tester.tap(find.byKey(UiKeys.profileCloseButton));
      await settleSettings(tester);

      expect(
        find.byKey(UiKeys.profileToxIdSelectableText),
        findsNothing,
        reason: 'closing must pop the profile route',
      );
      expect(
        find.byIcon(Icons.chevron_right),
        findsNWidgets(_sectionTileCount),
        reason: 'the settings index is back in front',
      );
    },
  );

  testWidgets(
    'landscape phone: still the mobile settings index, but the profile card '
    'opens the DIALOG fork (width 844 >= 720)',
    (WidgetTester tester) async {
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);
      _usePhoneSurface(tester, _landscapePhone);

      await _pumpSettings(tester, service);

      // Premise, proven by a rendered widget rather than a boolean helper:
      // shortestSide is still 390, so the device is still in the MOBILE tier
      // and the drill-down index (not the desktop list) is what renders.
      expect(
        find.byIcon(Icons.chevron_right),
        findsNWidgets(_sectionTileCount),
        reason:
            'a rotated phone keeps the mobile settings index (device class is '
            'shortestSide-based)',
      );
      expect(
        find.byKey(UiKeys.settingsAutoLoginSwitch),
        findsNothing,
        reason: 'still the drill-down branch, not the desktop inline list',
      );

      await tester.tap(find.widgetWithIcon(ListTile, _profileCardIcon));
      await settleSettings(tester);

      // ...yet `showSelfProfile` forks on WIDTH: 844 >= 720 -> dialog.
      expect(
        find.byType(AppDialog),
        findsOneWidget,
        reason:
            'width 844 clears the 720 large-phone breakpoint, so the '
            'width-based `shouldShowBottomNav` fork picks the dialog even on a '
            'phone-class device',
      );
      expect(
        find.byType(AppBar),
        findsNothing,
        reason: 'the fullscreen-route fork must NOT have been taken',
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(UiKeys.profileToxIdSelectableText),
            )
            .data,
        kSettingsToxId,
        reason: 'the dialog fork must show the same resolved Tox ID',
      );

      // The dialog's close button carries the same automation key; tapping it
      // runs `popDialogIfCurrent`.
      await tester.tap(find.byKey(UiKeys.profileCloseButton));
      await settleSettings(tester);

      expect(
        find.byType(AppDialog),
        findsNothing,
        reason: 'closing must dismiss the dialog',
      );
      expect(find.byKey(UiKeys.profileToxIdSelectableText), findsNothing);
    },
  );
}
