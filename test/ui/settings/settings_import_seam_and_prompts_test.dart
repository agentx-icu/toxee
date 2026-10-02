// Settings → Account Management → "Import Account", driven the way the real-UI
// harness drives it: the REAL button, the DEFAULT picker (bypassed only by the
// L3 override, exactly like the login page's import), and the shared
// PasswordPromptDialog through its automation keys.
//
// Three gates:
//   1. the picker seam — `_pickSettingsImportFile` used to call the native
//      picker directly, so on macOS the tap opened an NSOpenPanel the harness
//      could not dismiss (and `_importInProgress` stayed true);
//   2. the same button inside the pushed MOBILE account-management section;
//   3. (FFI) an OLDER full backup whose tox_profile.tox is ciphertext under the
//      account password: two prompts with DISTINCT titles, a wrong account
//      password writes nothing, the right one restores the profile still
//      encrypted with the password installed as the verifier.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/ui/testing/ui_keys_login.dart';
import 'package:toxee/ui/testing/ui_keys_settings.dart';
import 'package:toxee/util/account_export/encryption.dart';
import 'package:toxee/util/account_export/full_backup_crypto.dart';
import 'package:toxee/util/account_export/restore_transaction_journal.dart';
import 'package:toxee/util/account_export_service.dart'
    show PasswordRequiredException;
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/responsive_layout.dart';

import '../../account_export/test_support.dart';
import '../../account_export/tox_profile_factory.dart';
import 'settings_account_test_support.dart';
import 'package:toxee/util/secret_password.dart';
import '../../support/secret_password_text.dart';

const _archivePassword = 'zip-pw';
const _profilePassword = 'acct-pw';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  SettingsImportAccountDataFn? importAccountDataFn,
  Size surface = const Size(1280, 1400),
  // The desktop root lists Appearance first, so the account section sits
  // below the fold: scroll the button in (a tap off-surface hits nothing).
  bool ensureImportVisible = true,
}) async {
  final service = SettingsHarnessService();
  addTearDown(service.disposeStub);
  // physicalSize (not just the surface) so MediaQuery reports the size the
  // responsive layout switches on.
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    settingsApp(
      SettingsPage(
        service: service,
        connectionStatusStream: service.connectionStatusStream,
        autoAcceptFriends: false,
        onAutoAcceptFriendsChanged: (_) {},
        autoAcceptGroupInvites: false,
        onAutoAcceptGroupInvitesChanged: (_) {},
        // No pickImportFileFn: the DEFAULT picker is under test.
        importAccountDataFn: importAccountDataFn,
        addImportedAccountFn:
            ({
              required String toxId,
              required String nickname,
              required String statusMessage,
              required bool autoLogin,
              required bool autoAcceptFriends,
              required bool notificationSoundEnabled,
            }) => Prefs.addAccount(
              toxId: toxId,
              nickname: nickname,
              statusMessage: statusMessage,
              autoLogin: autoLogin,
            ),
      ),
    ),
  );
  await settleSettings(tester);
  if (ensureImportVisible) {
    await tester.ensureVisible(_importButton());
    await settleSettings(tester);
  }
}

Finder _importButton() => find.byKey(SettingsUiKeys.importAccountButton);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxIterations = 100,
}) async {
  for (var i = 0; i < maxIterations && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'condition not met in time');
}

/// Real file / FFI work completes on the real event loop, not on the fake
/// clock: yield to it between pumps (same pattern as the import-transaction
/// gate).
Future<void> _pumpRealUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxIterations = 600,
}) async {
  for (var i = 0; i < maxIterations && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'condition not met in time');
}

Future<void> _answerPrompt(WidgetTester tester, String password) async {
  await tester.enterText(find.byKey(LoginUiKeys.passwordPromptField), password);
  await tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton));
  await tester.pump();
}

/// What an older toxee wrote for a protected account that was not the live
/// session: the profile as it was on disk — encrypted under the ACCOUNT
/// password — inside the archive encrypted under the ARCHIVE password.
Future<String> _writeLegacyArchive(
  AccountExportTestEnv env,
  ToxProfileFixture fixture,
) async {
  final plain = Archive()
    ..addFile(
      ArchiveFile.noCompress(
        'tox_profile.tox',
        0,
        passEncrypt(fixture.savedata, SecretPassword.fromString(_profilePassword)),
      ),
    )
    ..addFile(
      ArchiveFile.noCompress(
        'metadata.json',
        0,
        utf8.encode(
          jsonEncode({
            'formatVersion': fullBackupEncryptedFormatVersion,
            'toxId': fixture.toxId,
            'nickname': 'Old install',
          }),
        ),
      ),
    );
  final encrypted = await encryptFullBackupArchive(
    plaintextArchive: plain,
    password: SecretPassword.fromString(_archivePassword),
  );
  final path = p.join(env.extras, 'old_backup.zip');
  await File(path).writeAsBytes(ZipEncoder().encode(encrypted));
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountExportTestEnv env;
  final secureStore = <String, String>{};
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );
  var nativePickerCalls = 0;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    secureStore.clear();
    nativePickerCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, (
      MethodCall call,
    ) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'write':
          if (key != null) secureStore[key] = args['value'] as String;
          return null;
        case 'read':
          return key == null ? null : secureStore[key];
        case 'delete':
          if (key != null) secureStore.remove(key);
          return null;
        case 'containsKey':
          return key != null && secureStore.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
          return null;
        default:
          return null;
      }
    });
    // The native picker must never be reached while the override is armed.
    messenger.setMockMethodCallHandler(filePickerChannel, (
      MethodCall call,
    ) async {
      nativePickerCalls++;
      return null;
    });
    debugSetL3TestSurfaceEnabledForTests(true);
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Current Account');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Current Account');
  });

  tearDown(() async {
    debugResetL3FilePickerOverridesForTests();
    debugSetL3TestSurfaceEnabledForTests(null);
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    messenger.setMockMethodCallHandler(filePickerChannel, null);
    await env.dispose();
  });

  testWidgets(
    'the real Import Account button honours the L3 picker override and '
    'prompts through the keyed password dialog',
    (tester) async {
      const overridePath = '/picked/by/override/backup.tox';
      debugSetAccountImportPickFileOverridePathForTests(overridePath);
      final importedPaths = <String>[];
      final importedPasswords = <String?>[];
      await _pumpSettings(
        tester,
        importAccountDataFn:
            ({required String filePath, SecretPassword? password}) async {
              importedPaths.add(filePath);
              importedPasswords.add(secretText(password));
              if (password == null) {
                throw const PasswordRequiredException('encrypted');
              }
              throw StateError('stop here: the prompt is what is under test');
            },
      );

      await tester.tap(_importButton());
      await _pumpUntil(
        tester,
        () => find.byKey(LoginUiKeys.passwordPromptField).evaluate().isNotEmpty,
      );
      expect(nativePickerCalls, 0, reason: 'override bypasses the picker');
      expect(importedPaths, [overridePath]);
      expect(find.text('Enter password to import account'), findsOneWidget);
      expect(find.byKey(LoginUiKeys.passwordPromptOkButton), findsOneWidget);
      expect(
        find.byKey(LoginUiKeys.passwordPromptCancelButton),
        findsOneWidget,
      );

      await _answerPrompt(tester, 'typed-pw');
      await _pumpUntil(tester, () => importedPasswords.length == 2);
      expect(importedPaths, [overridePath, overridePath]);
      expect(importedPasswords, [null, 'typed-pw']);
      // A failed retry of a `.tox` import is reported as a rejected password
      // and the button is re-armed.
      await _pumpUntil(
        tester,
        () => find.text('Invalid password').evaluate().isNotEmpty,
      );
      await _pumpUntil(
        tester,
        () => tester.widget<OutlinedButton>(_importButton()).onPressed != null,
      );
    },
  );

  testWidgets(
    'mobile: the button inside the pushed Account Management section is the '
    'same keyed control on the same seam',
    (tester) async {
      ResponsiveLayout.debugIsDesktopPlatformOverride = () => false;
      const overridePath = '/picked/by/override/mobile.tox';
      debugSetAccountImportPickFileOverridePathForTests(overridePath);
      final importedPaths = <String>[];
      await _pumpSettings(
        tester,
        surface: const Size(390, 844),
        ensureImportVisible: false,
        importAccountDataFn:
            ({required String filePath, SecretPassword? password}) async {
              importedPaths.add(filePath);
              throw const PasswordRequiredException('encrypted');
            },
      );
      expect(_importButton(), findsNothing, reason: 'lives in the section');

      await tester.ensureVisible(
        find.byKey(UiKeys.settingsMobileAccountManagementSection),
      );
      await tester.tap(
        find.byKey(UiKeys.settingsMobileAccountManagementSection),
      );
      await _pumpUntil(tester, () => _importButton().evaluate().isNotEmpty);
      await tester.ensureVisible(_importButton());
      await settleSettings(tester);
      await tester.tap(_importButton());
      await _pumpUntil(
        tester,
        () => find.byKey(LoginUiKeys.passwordPromptField).evaluate().isNotEmpty,
      );
      expect(nativePickerCalls, 0);
      expect(importedPaths, [overridePath]);

      await tester.tap(find.byKey(LoginUiKeys.passwordPromptCancelButton));
      await _pumpUntil(
        tester,
        () => find.byKey(LoginUiKeys.passwordPromptField).evaluate().isEmpty,
      );
      expect(importedPaths, [overridePath], reason: 'cancel imports nothing');
    },
  );

  testWidgets(
    'an older encrypted-profile backup: two distinct prompts, a wrong account '
    'password writes nothing, the right one restores the profile encrypted',
    (tester) async {
      final fixture = ToxProfileFixture.create()!;
      // Real file + FFI work runs on the real event loop: everything that
      // awaits it lives inside runAsync (fake-async timers would never fire).
      final zipPath = (await tester.runAsync(
        () => _writeLegacyArchive(env, fixture),
      ))!;
      debugSetAccountImportPickFileOverridePathForTests(zipPath);
      await _pumpSettings(tester);
      final profileDir = (await tester.runAsync(
        () => AppPaths.getProfileDirectoryForToxId(fixture.toxId),
      ))!;
      final profileFile = File(AppPaths.profileFileInDirectory(profileDir));
      const archiveTitle = 'Enter password to import account';
      const accountTitle = 'Enter the account password of this backup';

      await tester.runAsync(() async {
        // Wrong account password: rejected BEFORE any restore write.
        await tester.tap(_importButton());
        await _pumpRealUntil(
          tester,
          () => find.text(archiveTitle).evaluate().isNotEmpty,
        );
        await _answerPrompt(tester, _archivePassword);
        await _pumpRealUntil(
          tester,
          () => find.text(accountTitle).evaluate().isNotEmpty,
        );
        expect(find.text(archiveTitle), findsNothing);
        await _answerPrompt(tester, 'not the account password');
        await _pumpRealUntil(
          tester,
          () => find.text('Invalid password').evaluate().isNotEmpty,
        );
        expect(await profileFile.exists(), isFalse);
        expect(await RestoreTransactionJournalStore.read(), isNull);
        expect(await Prefs.hasAccountPassword(fixture.toxId), isFalse);
        expect(await Prefs.getAccountByToxId(fixture.toxId), isNull);
        await _pumpRealUntil(
          tester,
          () =>
              tester.widget<OutlinedButton>(_importButton()).onPressed != null,
        );

        // Right account password: restored, still ciphertext, gated.
        await tester.tap(_importButton());
        await _pumpRealUntil(
          tester,
          () => find.text(archiveTitle).evaluate().isNotEmpty,
        );
        await _answerPrompt(tester, _archivePassword);
        await _pumpRealUntil(
          tester,
          () => find.text(accountTitle).evaluate().isNotEmpty,
        );
        await _answerPrompt(tester, _profilePassword);
        await _pumpRealUntil(
          tester,
          () =>
              find.text('Account imported successfully').evaluate().isNotEmpty,
        );

        final onDisk = await profileFile.readAsBytes();
        expect(isDataEncrypted(onDisk), isTrue, reason: 'stays ciphertext');
        expect(passDecrypt(onDisk, SecretPassword.fromString(_profilePassword)), fixture.savedata);
        expect(
          await Prefs.verifyAccountPassword(fixture.toxId, SecretPassword.fromString(_profilePassword)),
          isTrue,
          reason: 'the password that opened the backup gates the account',
        );
        expect(await Prefs.getAccountByToxId(fixture.toxId), isNotNull);
        expect(await RestoreTransactionJournalStore.read(), isNull);
      });
      expect(nativePickerCalls, 0);
    },
    // tim2tox FFI library not loadable in this environment => skipped.
    skip: !_ffiAvailable(),
  );
}
