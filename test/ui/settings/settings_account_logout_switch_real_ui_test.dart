// Real-UI L1 gates for the SettingsPage ACCOUNT section — Logout (+ confirm)
// and Account-switch (confirm / cancel).
//
// These two handlers terminate in heavy static flows that cannot run
// hermetically (AccountService.teardownCurrentSession disposes a real FFI
// session; AccountSwitcher.switchAccount boots the target account's FFI). The
// production SettingsPage therefore exposes two injectable seams —
// `teardownSession` and `switchAccountFn` (settings_page.dart, mirroring
// LoginPage's bootSession/teardownSession) — bound to the real services in
// production and to recording stubs here. We drive the REAL dialogs and assert
// the REAL handler fired (or did NOT, on cancel) plus the REAL observable side
// effects (Prefs mutation, navigation).
//
// Logout:
//   * Tap `UiKeys.settingsLogoutButton` → the real confirm dialog opens.
//   * Tap Cancel → still on Settings (the teardown seam did NOT fire, no
//     navigation).
//   * Re-open → tap `UiKeys.settingsLogoutConfirmButton` → the real `_logout`
//     runs: the injected teardown seam fires with the page's service,
//     `Prefs.setCurrentAccountToxId(null)` clears the active account, and the
//     app navigates to LoginPage (Settings is gone).
//
// Account switch:
//   * Seed a SECOND local account so its card renders the swap-to-this-account
//     button. Tap it → the real confirm dialog opens.
//   * Tap `UiKeys.settingsAccountSwitchCancelButton` → dialog dismissed, the
//     switch seam did NOT fire.
//   * Re-open → tap `UiKeys.settingsAccountSwitchConfirmButton` → the real
//     `_switchAccount` runs and the injected switch seam fires with the target
//     Tox ID.
//
// Mobile parity: `_logout`, `_switchAccount`, and both seams are shared Dart in
// lib/ui/settings/ with no platform fork — these gates cover iOS/Android too.

library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

import 'settings_account_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late SettingsChannelMocks mocks;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'settings_account_logout_switch_',
    );
    mocks = SettingsChannelMocks.install(tempRoot);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Primary Nick');
    await Prefs.setStatusMessage('Primary Status');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Primary Nick');
  });

  tearDown(() {
    mocks.teardown();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  // --------------------------------------------------------------------------
  // Logout
  // --------------------------------------------------------------------------

  testWidgets('Logout: Cancel keeps Settings (teardown seam does NOT fire)', (
    WidgetTester tester,
  ) async {
    final service = SettingsHarnessService();
    addTearDown(service.disposeStub);

    var teardownCalls = 0;
    final page = SettingsPage(
      service: service,
      connectionStatusStream: service.connectionStatusStream,
      autoAcceptFriends: false,
      onAutoAcceptFriendsChanged: (_) {},
      autoAcceptGroupInvites: false,
      onAutoAcceptGroupInvitesChanged: (_) {},
      teardownSession: ({required service, reEncryptProfile = true}) async {
        teardownCalls += 1;
      },
    );

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(settingsApp(page));
    await settleSettings(tester);

    await tester.tap(find.byKey(UiKeys.settingsLogoutButton));
    await settleSettings(tester);
    // The confirm dialog is open (its confirm button is present).
    expect(find.byKey(UiKeys.settingsLogoutConfirmButton), findsOneWidget);
    expect(find.text('Are you sure you want to log out?'), findsOneWidget);

    // Cancel.
    await tester.tap(find.text('Cancel'));
    await settleSettings(tester);

    // Dialog gone, still on Settings, teardown never invoked.
    expect(find.byKey(UiKeys.settingsLogoutConfirmButton), findsNothing);
    expect(find.byKey(UiKeys.settingsLogoutButton), findsOneWidget);
    expect(teardownCalls, 0, reason: 'cancel must not tear down the session');
    // Active account pointer untouched.
    expect(await Prefs.getCurrentAccountToxId(), kSettingsToxId);
  });

  testWidgets(
    'Logout: Confirm fires teardown seam + clears current account + navigates '
    'to LoginPage',
    (WidgetTester tester) async {
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      var teardownCalls = 0;
      FfiChatService? teardownService;
      final page = SettingsPage(
        service: service,
        connectionStatusStream: service.connectionStatusStream,
        autoAcceptFriends: false,
        onAutoAcceptFriendsChanged: (_) {},
        autoAcceptGroupInvites: false,
        onAutoAcceptGroupInvitesChanged: (_) {},
        teardownSession: ({required service, reEncryptProfile = true}) async {
          teardownCalls += 1;
          teardownService = service;
        },
      );

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // The settings account body only needs `_currentNickname != null` (the
      // global nickname pref) to render — NOT the account_list. Remove the
      // seeded account_list entry so the destination LoginPage renders its
      // empty first-run state (no saved-account cards) instead of a card whose
      // userId-prefix Row overflows by a few px at this fixed test width (a
      // pre-existing LoginPage layout quirk, out of this gate's scope). The
      // logout HANDLER under test is unaffected.
      await Prefs.removeAccount(kSettingsToxId);

      await tester.pumpWidget(settingsApp(page));
      await settleSettings(tester);

      expect(await Prefs.getCurrentAccountToxId(), kSettingsToxId);

      await tester.tap(find.byKey(UiKeys.settingsLogoutButton));
      await settleSettings(tester);
      expect(find.byKey(UiKeys.settingsLogoutConfirmButton), findsOneWidget);

      // Confirm logout.
      await tester.tap(find.byKey(UiKeys.settingsLogoutConfirmButton));
      await settleSettings(tester);

      // The real `_logout` ran: teardown seam fired with the page's service.
      expect(
        teardownCalls,
        1,
        reason: 'confirm must invoke the teardown seam exactly once',
      );
      expect(
        teardownService,
        same(service),
        reason: 'teardown must receive the page service',
      );
      // Active account cleared.
      expect(
        await Prefs.getCurrentAccountToxId(),
        isNull,
        reason: 'logout must clear the current account pointer',
      );
      // Navigated to LoginPage (pushAndRemoveUntil → Settings is gone).
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byKey(UiKeys.settingsLogoutButton), findsNothing);
    },
  );

  testWidgets(
    'Logout: a DOUBLE-FIRED confirm pops once — the popDialogIfCurrent guard '
    'prevents the empty-Navigator blank',
    (WidgetTester tester) async {
      // Regression gate for the flutter_skill_double_tap_blank hazard. The real
      // UI harness (flutter_skill `tap`) and a fast real double-click both fire
      // a dialog button's onPressed TWICE. On the logout confirm
      // (`Navigator.pop(true)`) the first pop closes the dialog and an unguarded
      // second pop unwinds the page under it — here SettingsPage is the home
      // route, so the Navigator empties and the window blanks, and `_logout`'s
      // trailing `if (!mounted) return` then skips `pushAndRemoveUntil(LoginPage)`
      // (teardown never even runs). `popDialogIfCurrent` makes the second pop a
      // no-op, so logout proceeds exactly once.
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      var teardownCalls = 0;
      final page = SettingsPage(
        service: service,
        connectionStatusStream: service.connectionStatusStream,
        autoAcceptFriends: false,
        onAutoAcceptFriendsChanged: (_) {},
        autoAcceptGroupInvites: false,
        onAutoAcceptGroupInvitesChanged: (_) {},
        teardownSession: ({required service, reEncryptProfile = true}) async {
          teardownCalls += 1;
        },
      );

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Clean LoginPage destination (see the single-tap confirm test).
      await Prefs.removeAccount(kSettingsToxId);

      await tester.pumpWidget(settingsApp(page));
      await settleSettings(tester);

      await tester.tap(find.byKey(UiKeys.settingsLogoutButton));
      await settleSettings(tester);
      expect(find.byKey(UiKeys.settingsLogoutConfirmButton), findsOneWidget);

      // Fire the confirm callback twice back-to-back, before any frame settles —
      // exactly what flutter_skill's synthetic-pointer + direct
      // `_tryInvokeCallback` pair does on a single key-tap.
      final confirm = tester.widget<TextButton>(
        find.byKey(UiKeys.settingsLogoutConfirmButton),
      );
      confirm.onPressed!();
      confirm.onPressed!();
      await settleSettings(tester);

      expect(
        teardownCalls,
        1,
        reason: 'the double-fire must still log out EXACTLY once',
      );
      expect(
        find.byType(LoginPage),
        findsOneWidget,
        reason:
            'the guarded second pop is a no-op, so logout navigates to LoginPage '
            'instead of emptying the Navigator (blank)',
      );
      expect(find.byKey(UiKeys.settingsLogoutButton), findsNothing);
      expect(
        await Prefs.getCurrentAccountToxId(),
        isNull,
        reason: 'logout still cleared the active account exactly once',
      );
    },
  );

  // --------------------------------------------------------------------------
  // Account switch
  // --------------------------------------------------------------------------

  testWidgets(
    'Account switch: Cancel dismisses the dialog (switch seam does NOT fire)',
    (WidgetTester tester) async {
      // Seed a second account so its card renders the switch-to button.
      await Prefs.addAccount(
        toxId: kSettingsOtherToxId,
        nickname: 'Other Nick',
      );

      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      var switchCalls = 0;
      final page = SettingsPage(
        service: service,
        connectionStatusStream: service.connectionStatusStream,
        autoAcceptFriends: false,
        onAutoAcceptFriendsChanged: (_) {},
        autoAcceptGroupInvites: false,
        onAutoAcceptGroupInvitesChanged: (_) {},
        switchAccountFn:
            ({required context, required targetToxId, currentService}) async {
              switchCalls += 1;
            },
      );

      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(settingsApp(page));
      await settleSettings(tester);

      // The "Other Nick" card renders a swap-to-this-account IconButton; tap it.
      final swapButton = find.widgetWithIcon(IconButton, Icons.swap_horiz);
      expect(
        swapButton,
        findsOneWidget,
        reason: 'the non-current account card shows the switch button',
      );
      await tester.tap(swapButton);
      await settleSettings(tester);

      // The switch confirm dialog opened.
      expect(
        find.byKey(UiKeys.settingsAccountSwitchConfirmButton),
        findsOneWidget,
      );
      expect(
        find.byKey(UiKeys.settingsAccountSwitchCancelButton),
        findsOneWidget,
      );

      // Cancel.
      await tester.tap(find.byKey(UiKeys.settingsAccountSwitchCancelButton));
      await settleSettings(tester);

      expect(
        find.byKey(UiKeys.settingsAccountSwitchConfirmButton),
        findsNothing,
        reason: 'cancel dismisses the switch dialog',
      );
      expect(switchCalls, 0, reason: 'cancel must not switch accounts');
    },
  );

  testWidgets(
    'Account switch: Confirm fires the switch seam with the target Tox ID',
    (WidgetTester tester) async {
      await Prefs.addAccount(
        toxId: kSettingsOtherToxId,
        nickname: 'Other Nick',
      );

      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      var switchCalls = 0;
      String? switchedTarget;
      FfiChatService? switchedCurrent;
      final page = SettingsPage(
        service: service,
        connectionStatusStream: service.connectionStatusStream,
        autoAcceptFriends: false,
        onAutoAcceptFriendsChanged: (_) {},
        autoAcceptGroupInvites: false,
        onAutoAcceptGroupInvitesChanged: (_) {},
        switchAccountFn:
            ({required context, required targetToxId, currentService}) async {
              switchCalls += 1;
              switchedTarget = targetToxId;
              switchedCurrent = currentService;
            },
      );

      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(settingsApp(page));
      await settleSettings(tester);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.swap_horiz));
      await settleSettings(tester);
      expect(
        find.byKey(UiKeys.settingsAccountSwitchConfirmButton),
        findsOneWidget,
      );

      // Confirm switch.
      await tester.tap(find.byKey(UiKeys.settingsAccountSwitchConfirmButton));
      await settleSettings(tester);

      expect(
        switchCalls,
        1,
        reason: 'confirm must invoke the switch seam exactly once',
      );
      expect(
        switchedTarget,
        kSettingsOtherToxId,
        reason: 'switch must target the OTHER account toxId',
      );
      expect(
        switchedCurrent,
        same(service),
        reason: 'switch must pass the current page service',
      );
    },
  );

  testWidgets(
    'Account switch: a second row tap is ignored while switch is pending',
    (WidgetTester tester) async {
      await Prefs.addAccount(
        toxId: kSettingsOtherToxId,
        nickname: 'Other Nick',
      );
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);
      final releaseSwitch = Completer<void>();
      var switchCalls = 0;
      final page = SettingsPage(
        service: service,
        connectionStatusStream: service.connectionStatusStream,
        autoAcceptFriends: false,
        onAutoAcceptFriendsChanged: (_) {},
        autoAcceptGroupInvites: false,
        onAutoAcceptGroupInvitesChanged: (_) {},
        switchAccountFn:
            ({required context, required targetToxId, currentService}) async {
              switchCalls++;
              await releaseSwitch.future;
            },
      );

      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(settingsApp(page));
      await settleSettings(tester);

      final swapButton = find.widgetWithIcon(IconButton, Icons.swap_horiz);
      await tester.tap(swapButton);
      await settleSettings(tester);
      await tester.tap(find.byKey(UiKeys.settingsAccountSwitchConfirmButton));
      await tester.pumpAndSettle();
      expect(switchCalls, 1);
      expect(
        find.byKey(UiKeys.settingsAccountSwitchConfirmButton),
        findsNothing,
      );

      await tester.tap(swapButton);
      await tester.pumpAndSettle();
      expect(switchCalls, 1);
      expect(
        find.byKey(UiKeys.settingsAccountSwitchConfirmButton),
        findsNothing,
      );

      releaseSwitch.complete();
      await settleSettings(tester);
    },
  );
}
