// Real-UI L1 gates for the SettingsPage ACCOUNT section — Set / Change password
// dialog.
//
// What these prove (the REAL production path, driving the REAL PBKDF2 + secure
// storage, NOT a re-implemented handler):
//   * Tapping the REAL `UiKeys.settingsSetPasswordButton` runs the production
//     `_setAccountPassword`, which reads `Prefs.hasAccountPassword` and opens
//     `_showSetPasswordDialog(hasPassword)`. The dialog title is "Set Password"
//     when the account has none and "Change Password" when it does — BOTH are
//     covered by seeding `Prefs.setAccountPassword` up front.
//   * SAME password in both fields → tapping Save runs the real
//     `AccountService.setAccountPassword(service, pwd)` →
//     `Prefs.setAccountPassword` → `PasswordVerifier.setPassword`, which runs
//     PBKDF2-HMAC-SHA256 (150k iters via package:cryptography) and persists the
//     hash+salt to (mocked, in-memory) secure storage. The gate asserts the
//     REAL observable side effects: the "Password set successfully" SnackBar
//     AND `Prefs.hasAccountPassword(toxId)` now true AND
//     `Prefs.verifyAccountPassword(toxId, pwd)` accepts the password.
//   * MISMATCHED fields → tapping Save shows the "Passwords do not match"
//     SnackBar, the dialog STAYS open (the save button's own guard returns
//     before popping), and NO password is persisted.
//
// CRITICAL HARNESS NOTE (the FakeAsync/PBKDF2 trap): the real password set/verify
// runs PBKDF2 (150k iters) via package:cryptography, whose async work the
// testWidgets FakeAsync zone does NOT drive — a naive `tester.tap` + pump would
// HANG for the full timeout. Every password-touching interaction here runs
// inside `tester.runAsync(...)`, where `tester.pump()` advances the REAL event
// loop; we pump in 50ms real steps until the effect lands (dialog open /
// snackbar / Prefs change).
//
// Mobile parity: `_setAccountPassword` + `_showSetPasswordDialog` +
// `AccountService.setAccountPassword` + `PasswordVerifier` are all shared Dart;
// no platform fork. These gates cover iOS/Android too. (flutter_secure_storage
// is mocked in-memory so the write actually persists in the test env, where the
// real keychain channel would throw MissingPluginException.)

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

const _newField = Key('settings_set_password_new_field');
const _confirmField = Key('settings_set_password_confirm_field');
const _saveButton = Key('settings_set_password_save_button');

/// Pump the REAL event loop in 50ms steps (up to [maxMs]) until [ready] is
/// satisfied. MUST be called inside `tester.runAsync` so the PBKDF2 / Prefs
/// futures actually progress. Returns when [ready] is true (or after the
/// budget elapses, leaving the assertion to fail with context).
Future<void> _pumpRealUntil(
  WidgetTester tester,
  bool Function() ready, {
  int maxMs = 8000,
}) async {
  var elapsed = 0;
  while (elapsed < maxMs) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 50));
    // Yield to the real microtask/timer queue (runAsync zone).
    await Future<void>.delayed(const Duration(milliseconds: 50));
    elapsed += 50;
  }
  // Final pump so the latest frame is built for the caller's assertions.
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpSettings(
  WidgetTester tester,
  FfiChatService service,
) async {
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
  await tester.ensureVisible(find.byKey(UiKeys.settingsSetPasswordButton));
  await settleSettings(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late SettingsChannelMocks mocks;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'settings_account_password_',
    );
    mocks = SettingsChannelMocks.install(tempRoot);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Pwd Nick');
    await Prefs.setStatusMessage('Pwd Status');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Pwd Nick');
  });

  tearDown(() async {
    // Clean any password the test set so the in-memory secure store + Prefs
    // don't leak across tests.
    await Prefs.removeAccountPassword(kSettingsToxId);
    mocks.teardown();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  testWidgets(
    'Set Password (no existing): matching fields persist + success SnackBar',
    (WidgetTester tester) async {
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettings(tester, service);

      // No password yet.
      expect(await Prefs.hasAccountPassword(kSettingsToxId), isFalse);
      expect(find.byKey(UiKeys.settingsSetPasswordButton), findsOneWidget);
      // Baseline "Set Password" count BEFORE opening — the account card's
      // button label is the localized "Set Password" string, so the dialog
      // title must STRICTLY increase this count (a non-vacuous delta).
      final setPwdBefore = find.text('Set Password').evaluate().length;

      await tester.runAsync(() async {
        // Open the dialog (the handler reads hasAccountPassword first — async).
        await tester.tap(find.byKey(UiKeys.settingsSetPasswordButton));
        await _pumpRealUntil(
          tester,
          () => find.byKey(_saveButton).evaluate().isNotEmpty,
        );

        // No existing password → the dialog adds its OWN "Set Password" title
        // on top of the persistent button label (count strictly increases).
        expect(
          find.text('Set Password').evaluate().length,
          greaterThan(setPwdBefore),
          reason: 'opening the set-password dialog surfaces its title',
        );
        expect(find.byKey(_newField), findsOneWidget);
        expect(find.byKey(_confirmField), findsOneWidget);

        // Same value in both fields.
        await tester.enterText(find.byKey(_newField), 'hunter2-secret');
        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byKey(_confirmField), 'hunter2-secret');
        await tester.pump(const Duration(milliseconds: 50));

        // Save → real AccountService.setAccountPassword → PBKDF2 (150k iters).
        await tester.tap(find.byKey(_saveButton));
        // Wait for the dialog to close (pop) AND the password to land in Prefs.
        await _pumpRealUntil(
          tester,
          () => find.byKey(_saveButton).evaluate().isEmpty,
        );
        await _pumpRealUntil(
          tester,
          () =>
              find.text('Password set successfully').evaluate().isNotEmpty,
        );
      });

      // The real success SnackBar surfaced.
      expect(
        find.text('Password set successfully'),
        findsOneWidget,
        reason: 'matching-password save must show the success SnackBar',
      );

      // The REAL durable verifier accepted the write.
      await tester.runAsync(() async {
        expect(
          await Prefs.hasAccountPassword(kSettingsToxId),
          isTrue,
          reason: 'PBKDF2 hash+salt persisted to (mocked) secure storage',
        );
        expect(
          await Prefs.verifyAccountPassword(kSettingsToxId, 'hunter2-secret'),
          isTrue,
          reason: 'the persisted PBKDF2 verifier accepts the chosen password',
        );
        expect(
          await Prefs.verifyAccountPassword(kSettingsToxId, 'wrong-password'),
          isFalse,
          reason: 'a different password must NOT verify',
        );
      });
    },
  );

  testWidgets(
    'Change Password (existing): dialog title reflects the existing password',
    (WidgetTester tester) async {
      // Seed an existing password so the dialog opens in CHANGE mode. This
      // write itself runs PBKDF2 → do it in runAsync.
      await tester.runAsync(() async {
        final ok = await Prefs.setAccountPassword(kSettingsToxId, 'old-pass-1');
        expect(ok, isTrue, reason: 'seed password persisted to secure store');
      });

      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettings(tester, service);
      expect(await Prefs.hasAccountPassword(kSettingsToxId), isTrue);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(UiKeys.settingsSetPasswordButton));
        await _pumpRealUntil(
          tester,
          () => find.byKey(_saveButton).evaluate().isNotEmpty,
        );
      });

      // Existing password → the dialog title is "Change Password". (Note: the
      // account card's Set-Password BUTTON label is the localized "Set
      // Password" string and is ALWAYS present regardless of dialog mode — so
      // we assert the change-mode TITLE appeared, not the absence of "Set
      // Password" which would false-fail on the persistent button label.)
      expect(
        find.text('Change Password'),
        findsOneWidget,
        reason: 'existing-password account opens the dialog in change mode',
      );

      // Drive a real change to a new value and assert it persisted.
      await tester.runAsync(() async {
        await tester.enterText(find.byKey(_newField), 'brand-new-pass');
        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byKey(_confirmField), 'brand-new-pass');
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(_saveButton));
        await _pumpRealUntil(
          tester,
          () =>
              find.text('Password set successfully').evaluate().isNotEmpty,
        );
        expect(
          await Prefs.verifyAccountPassword(kSettingsToxId, 'brand-new-pass'),
          isTrue,
          reason: 'change-password persisted the NEW password',
        );
        expect(
          await Prefs.verifyAccountPassword(kSettingsToxId, 'old-pass-1'),
          isFalse,
          reason: 'the old password no longer verifies after change',
        );
      });
    },
  );

  testWidgets(
    'Mismatched fields: "do not match" SnackBar, dialog stays, nothing saved',
    (WidgetTester tester) async {
      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettings(tester, service);
      expect(await Prefs.hasAccountPassword(kSettingsToxId), isFalse);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(UiKeys.settingsSetPasswordButton));
        await _pumpRealUntil(
          tester,
          () => find.byKey(_saveButton).evaluate().isNotEmpty,
        );

        // Deliberately different values.
        await tester.enterText(find.byKey(_newField), 'alpha-one');
        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byKey(_confirmField), 'beta-two');
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.byKey(_saveButton));
        // The guard returns synchronously (no pop, no PBKDF2). Give the
        // SnackBar a couple frames to mount.
        await _pumpRealUntil(
          tester,
          () => find.text('Passwords do not match').evaluate().isNotEmpty,
        );
      });

      // Mismatch SnackBar shown.
      expect(
        find.text('Passwords do not match'),
        findsOneWidget,
        reason: 'mismatched fields must show the passwordsDoNotMatch SnackBar',
      );
      // Dialog is STILL open (save button + fields remain): the guard returned
      // before Navigator.pop.
      expect(
        find.byKey(_saveButton),
        findsOneWidget,
        reason: 'mismatch must NOT dismiss the dialog',
      );
      expect(find.byKey(_newField), findsOneWidget);

      // Nothing was persisted.
      expect(
        await Prefs.hasAccountPassword(kSettingsToxId),
        isFalse,
        reason: 'mismatch must not persist any password',
      );
    },
  );
}
