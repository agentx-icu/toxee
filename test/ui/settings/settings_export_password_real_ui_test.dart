// Real-UI gate for the in-session export password (task A6): the export
// password is NOT the account password.
//
// Drives the PRODUCTION SettingsPage → export chooser → ExportPasswordDialog →
// exporter, with only the exporter itself swapped for a recorder
// (`SettingsPage.exportToxFn` / `exportFullBackupFn`, because the real
// AccountExportService needs the native library) and the desktop save
// panel short-circuited by the in-repo L3 export-save override.
//
// Pins:
//   * a PASSWORD-PROTECTED account in a live session is asked ONLY for the
//     export password (no account-password prompt), and exactly that string
//     reaches the exporter;
//   * `.tox` with an empty export password shows the warning line while the
//     field is empty and exports UNENCRYPTED (exporter gets null);
//   * the full backup refuses an empty export password inside the dialog
//     (inline error, exporter never called) and goes through once one is set.
//
// Mobile parity: SettingsPage's export handlers and the dialog are shared
// Dart; only the chooser container (sheet vs dialog) and the final save step
// fork, and neither is what this gate pins.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/ui/settings/settings_export_actions.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/ui/testing/ui_keys_settings.dart';
import 'package:toxee/util/prefs.dart';

import 'settings_account_test_support.dart';
import 'package:toxee/util/secret_password.dart';
import '../../support/secret_password_text.dart';

const _accountPassword = 'the account password';
const _accountPromptFieldKey = Key('login_quick_password_field');

final class _ExportCall {
  _ExportCall(this.toxId, this.password, this.filePath);
  final String toxId;
  final String? password;
  final String? filePath;
}

Future<void> _pumpSettings(
  WidgetTester tester,
  FfiChatService service, {
  required SettingsExportFn exportTox,
  required SettingsExportFn exportFullBackup,
}) async {
  final page = SettingsPage(
    exportToxFn: exportTox,
    exportFullBackupFn: exportFullBackup,
    service: service,
    connectionStatusStream: service.connectionStatusStream,
    autoAcceptFriends: false,
    onAutoAcceptFriendsChanged: (_) {},
    autoAcceptGroupInvites: false,
    onAutoAcceptGroupInvitesChanged: (_) {},
  );
  await tester.pumpWidget(settingsApp(page));
  await settleSettings(tester);
  await tester.ensureVisible(find.byKey(UiKeys.settingsExportAccountButton));
  await settleSettings(tester);
}

Future<void> _openExportDialog(WidgetTester tester, Key option) async {
  await tester.tap(find.byKey(UiKeys.settingsExportAccountButton));
  await settleSettings(tester);
  await tester.tap(find.byKey(option));
  await settleSettings(tester, frames: 5);
  expect(find.byKey(SettingsUiKeys.exportPasswordField), findsOneWidget);
  // Live session: NO account-password prompt in front of the export dialog.
  expect(find.byKey(_accountPromptFieldKey), findsNothing);
  expect(find.text('Choose an export password'), findsOneWidget);
}

Future<void> _enterExportPassword(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(SettingsUiKeys.exportPasswordField), value);
  await tester.enterText(
    find.byKey(SettingsUiKeys.exportPasswordConfirmField),
    value,
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late SettingsChannelMocks mocks;
  late List<_ExportCall> toxCalls;
  late List<_ExportCall> backupCalls;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('settings_export_pw_');
    mocks = SettingsChannelMocks.install(tempRoot);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Export Nick');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Export Nick');

    debugSetL3TestSurfaceEnabledForTests(true);
    toxCalls = [];
    backupCalls = [];
  });

  tearDown(() {
    mocks.teardown();
    debugResetL3FilePickerOverridesForTests();
    debugSetL3TestSurfaceEnabledForTests(null);
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Future<FfiChatService> pumpProtectedAccount(WidgetTester tester) async {
    await tester.runAsync(() async {
      expect(
        await Prefs.setAccountPassword(kSettingsToxId, SecretPassword.fromString(_accountPassword)),
        isTrue,
      );
    });
    final service = SettingsHarnessService();
    addTearDown(service.disposeStub);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpSettings(
      tester,
      service,
      exportTox:
          ({required String toxId, SecretPassword? password, String? filePath}) async {
            toxCalls.add(_ExportCall(toxId, secretText(password), filePath));
            // Stand-in for the real exporter: "plaintext" when no password.
            final out = File(filePath!);
            out.writeAsStringSync(password == null ? 'PLAIN' : 'SEALED');
            return out.path;
          },
      exportFullBackup:
          ({required String toxId, SecretPassword? password, String? filePath}) async {
            backupCalls.add(_ExportCall(toxId, secretText(password), filePath));
            return filePath!;
          },
    );
    return service;
  }

  testWidgets(
    'protected account in session: .tox asks ONLY the export password and '
    'exports with exactly that password',
    (tester) async {
      final out = p.join(tempRoot.path, 'sealed.tox');
      debugSetExportSaveFileOverridePathForTests(out);
      await pumpProtectedAccount(tester);

      await _openExportDialog(tester, UiKeys.settingsExportProfileToxOption);
      // Optional mode: the warning is up while the field is empty ...
      expect(
        find.byKey(SettingsUiKeys.exportPasswordEmptyWarning),
        findsOneWidget,
      );
      await _enterExportPassword(tester, 'a separate export pw');
      // ... and gone once a password is typed.
      expect(
        find.byKey(SettingsUiKeys.exportPasswordEmptyWarning),
        findsNothing,
      );
      await tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton));
      await settleSettings(tester);

      expect(toxCalls, hasLength(1));
      expect(toxCalls.single.toxId, kSettingsToxId);
      expect(toxCalls.single.password, 'a separate export pw');
      expect(toxCalls.single.password, isNot(_accountPassword));
      expect(toxCalls.single.filePath, out);
      expect(File(out).readAsStringSync(), 'SEALED');
      expect(backupCalls, isEmpty);
    },
  );

  testWidgets(
    'empty .tox export password: warning visible, file exported unencrypted',
    (tester) async {
      final out = p.join(tempRoot.path, 'plain.tox');
      debugSetExportSaveFileOverridePathForTests(out);
      await pumpProtectedAccount(tester);

      await _openExportDialog(tester, UiKeys.settingsExportProfileToxOption);
      expect(
        find.byKey(SettingsUiKeys.exportPasswordEmptyWarning),
        findsOneWidget,
      );
      expect(find.textContaining('UNENCRYPTED'), findsOneWidget);
      await tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton));
      await settleSettings(tester);

      expect(toxCalls, hasLength(1));
      expect(toxCalls.single.password, isNull);
      expect(File(out).readAsStringSync(), 'PLAIN');
    },
  );

  testWidgets(
    'full backup refuses an empty export password inside the dialog, then '
    'exports with the one the user sets',
    (tester) async {
      final out = p.join(tempRoot.path, 'backup.zip');
      debugSetExportSaveFileOverridePathForTests(out);
      await pumpProtectedAccount(tester);

      await _openExportDialog(tester, UiKeys.settingsExportFullBackupOption);
      // Required mode: no "export unencrypted" warning, empty is refused.
      expect(
        find.byKey(SettingsUiKeys.exportPasswordEmptyWarning),
        findsNothing,
      );
      await tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton));
      await settleSettings(tester, frames: 3);
      expect(
        find.text('A full backup needs an export password'),
        findsOneWidget,
      );
      expect(find.byKey(SettingsUiKeys.exportPasswordField), findsOneWidget);
      expect(backupCalls, isEmpty);

      await _enterExportPassword(tester, 'backup pw');
      await tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton));
      await settleSettings(tester);
      expect(backupCalls, hasLength(1));
      expect(backupCalls.single.password, 'backup pw');
      expect(backupCalls.single.filePath, out);
      expect(toxCalls, isEmpty);
    },
  );

  testWidgets('cancelling the export dialog exports nothing', (tester) async {
    debugSetExportSaveFileOverridePathForTests(
      p.join(tempRoot.path, 'never.tox'),
    );
    await pumpProtectedAccount(tester);
    await _openExportDialog(tester, UiKeys.settingsExportProfileToxOption);
    await tester.tap(find.byKey(SettingsUiKeys.exportPasswordCancelButton));
    await settleSettings(tester);
    expect(find.byKey(SettingsUiKeys.exportPasswordField), findsNothing);
    expect(toxCalls, isEmpty);
    expect(File(p.join(tempRoot.path, 'never.tox')).existsSync(), isFalse);
  });
}
