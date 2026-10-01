// Real-UI L1 gates for the SettingsPage ACCOUNT section — the two purely
// OBSERVABLE side-effect handlers: "Copy Tox ID" and the "Auto Login" switch.
//
// What these prove (the REAL production path, not a `findsOneWidget` smoke):
//   * Copy Tox ID — tapping the REAL `UiKeys.settingsCopyToxIdButton`
//     (settings_page_build.dart) runs its real `onPressed`:
//     `Clipboard.setData(ClipboardData(text: toxId))` + a "copied" SnackBar.
//     The clipboard mock captures the EXACT text written (the resolved account
//     Tox ID), and the localized snackbar text is asserted on screen. This
//     drives the handler end-to-end through the real system clipboard channel.
//   * Auto Login switch — reading the REAL `UiKeys.settingsAutoLoginSwitch`'s
//     initial value, tapping it, and asserting (a) the Switch widget flips and
//     (b) `Prefs.getAutoLogin(toxId)` now returns the flipped value — i.e. the
//     real `_setAutoLogin` persisted to the account-scoped pref. Covered in
//     both directions (true→false and false→true).
//
// Mobile parity: both handlers are shared Dart (lib/ui/settings/), no platform
// fork — see settings_account_test_support.dart's header. These gates cover
// iOS/Android too.

library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

import 'settings_account_test_support.dart';

Future<void> _pumpSettings(WidgetTester tester, FfiChatService service) async {
  final page = SettingsPage(
    service: service,
    connectionStatusStream: service.connectionStatusStream,
    autoAcceptFriends: false,
    onAutoAcceptFriendsChanged: (_) {},
    autoAcceptGroupInvites: false,
    onAutoAcceptGroupInvitesChanged: (_) {},
  );
  await tester.pumpWidget(settingsApp(page));
  await settleSettings(tester);
  // Appearance precedes the account card. Drive the same scroll a user needs
  // before interacting with the account controls below the first viewport.
  await tester.scrollUntilVisible(
    find.byKey(UiKeys.settingsCopyToxIdButton),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await settleSettings(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late SettingsChannelMocks mocks;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'settings_account_copy_autologin_',
    );
    mocks = SettingsChannelMocks.install(tempRoot);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    // Seed a current account so the Account card renders its body (gated behind
    // `_currentNickname != null`, settings_page_build.dart) and accountKey
    // resolves.
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Copy Nick');
    await Prefs.setStatusMessage('Copy Status');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Copy Nick');
  });

  tearDown(() {
    mocks.teardown();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  testWidgets(
    'Copy Tox ID: real button copies the resolved Tox ID + shows "copied" '
    'SnackBar',
    (WidgetTester tester) async {
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettings(tester, service);

      expect(find.byKey(UiKeys.settingsCopyToxIdButton), findsOneWidget);
      // Nothing copied yet.
      expect(mocks.clipboardLog, isEmpty);

      await tester.tap(find.byKey(UiKeys.settingsCopyToxIdButton));
      await settleSettings(tester);

      // The real onPressed wrote the FULL resolved Tox ID to the system
      // clipboard (the account body renders `_currentAccountToxId ??
      // widget.service.accountKey`, both kSettingsToxId here).
      expect(
        mocks.clipboardLog,
        contains(kSettingsToxId),
        reason: 'real copy handler must Clipboard.setData the resolved Tox ID',
      );
      // The localized "copied" confirmation SnackBar surfaced.
      expect(
        find.text('ID copied to clipboard'),
        findsOneWidget,
        reason: 'copy handler must show the idCopiedToClipboard SnackBar',
      );
    },
  );

  testWidgets(
    'Auto Login switch: flips true→false and persists to Prefs.getAutoLogin',
    (WidgetTester tester) async {
      // Default getAutoLogin for an account with no stored value is `true`
      // (and the page seeds _autoLogin=true), so this exercises true→false.
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettings(tester, service);

      expect(find.byKey(UiKeys.settingsAutoLoginSwitch), findsOneWidget);
      final before = tester.widget<Switch>(
        find.byKey(UiKeys.settingsAutoLoginSwitch),
      );
      expect(before.value, isTrue, reason: 'default auto-login is on');

      await tester.tap(find.byKey(UiKeys.settingsAutoLoginSwitch));
      await settleSettings(tester);

      // The Switch widget reflects the flip.
      final after = tester.widget<Switch>(
        find.byKey(UiKeys.settingsAutoLoginSwitch),
      );
      expect(after.value, isFalse, reason: 'tapping the switch flips the UI');

      // The real `_setAutoLogin` persisted the new value under the account.
      final persisted = await Prefs.getAutoLogin(kSettingsToxId);
      expect(
        persisted,
        isFalse,
        reason: 'flip must persist to Prefs.getAutoLogin(toxId)',
      );
    },
  );

  testWidgets(
    'Auto Login switch: flips false→true and persists to Prefs.getAutoLogin',
    (WidgetTester tester) async {
      // Pre-seed auto-login OFF so the page loads with the switch off, then
      // exercise the false→true direction.
      await Prefs.setAutoLogin(false, kSettingsToxId);

      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettings(tester, service);

      // _loadAutoLogin runs in initState; settle gives it time to land.
      final before = tester.widget<Switch>(
        find.byKey(UiKeys.settingsAutoLoginSwitch),
      );
      expect(
        before.value,
        isFalse,
        reason: 'page loaded the pre-seeded auto-login=off',
      );

      await tester.tap(find.byKey(UiKeys.settingsAutoLoginSwitch));
      await settleSettings(tester);

      final after = tester.widget<Switch>(
        find.byKey(UiKeys.settingsAutoLoginSwitch),
      );
      expect(after.value, isTrue);

      final persisted = await Prefs.getAutoLogin(kSettingsToxId);
      expect(persisted, isTrue);
    },
  );
}
