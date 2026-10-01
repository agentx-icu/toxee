// Real-UI L1 gate for the SettingsPage ACCOUNT section — Export-account chooser,
// the .zip (Full Backup) branch.
//
// The existing settings_export_chooser_real_ui_test.dart covers the .tox tile
// (S105 A2: chooser pops 'tox'). This gate covers the SIBLING .zip tile that
// test asserts is PRESENT but never drives:
//   * Tapping the REAL `UiKeys.settingsExportAccountButton` opens the REAL
//     chooser with both keyed option tiles.
//   * Tapping the REAL `UiKeys.settingsExportFullBackupOption` (.zip) runs its
//     production onTap `Navigator.of(ctx).pop('zip')` (settings_page.dart): the
//     chooser is DISMISSED (both tiles gone), and a NavigatorObserver reading
//     the chooser route's pop result proves the EXACT routed value is 'zip'
//     (the full-backup branch, not 'tox').
//
// Out of scope (same as the .tox gate): the terminal save step inside
// `_exportFullBackup` opens a native NSSavePanel on desktop (S43 territory). We
// arm the in-repo L3 export-save override so any save step is short-circuited
// before the native picker can run; this gate owns the CHOOSER surface + routed
// value only.
//
// Surface: desktop (the `showDialog` Dialog branch). The mobile bottom-sheet
// container renders the same two keyed tiles, so A1/A2 hold there too.
//
// Mobile parity: `_showExportOptions`, both tiles, and `_exportFullBackup` are
// shared Dart; only the chooser container forks. The native save panel is
// platform-specific and deliberately not driven here.

library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

import 'settings_account_test_support.dart';

Future<void> _pumpSettings(
  WidgetTester tester,
  FfiChatService service, {
  List<NavigatorObserver> observers = const [],
}) async {
  final page = SettingsPage(
    service: service,
    connectionStatusStream: service.connectionStatusStream,
    autoAcceptFriends: false,
    onAutoAcceptFriendsChanged: (_) {},
    autoAcceptGroupInvites: false,
    onAutoAcceptGroupInvitesChanged: (_) {},
  );
  await tester.pumpWidget(settingsApp(page, navigatorObservers: observers));
  await settleSettings(tester);
  await tester.ensureVisible(find.byKey(UiKeys.settingsExportAccountButton));
  await settleSettings(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late SettingsChannelMocks mocks;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'settings_account_export_zip_',
    );
    mocks = SettingsChannelMocks.install(tempRoot);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Zip Nick');
    await Prefs.setStatusMessage('Zip Status');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Zip Nick');
  });

  tearDown(() {
    mocks.teardown();
    debugResetL3FilePickerOverridesForTests();
    debugSetL3TestSurfaceEnabledForTests(null);
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  testWidgets(
    'tapping the real .zip tile dismisses the chooser (native picker bypassed)',
    (WidgetTester tester) async {
      // Arm the L3 export-save override so IF the 'zip' pop reaches the save
      // step, the native NSSavePanel is short-circuited.
      debugSetL3TestSurfaceEnabledForTests(true);
      final overridePath = p.join(tempRoot.path, 'export_probe.zip');
      debugSetExportSaveFileOverridePathForTests(overridePath);

      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettings(tester, service);

      await tester.tap(find.byKey(UiKeys.settingsExportAccountButton));
      await settleSettings(tester);
      expect(find.byKey(UiKeys.settingsExportProfileToxOption), findsOneWidget);
      expect(find.byKey(UiKeys.settingsExportFullBackupOption), findsOneWidget);
      // The .zip tile label is unique to the chooser.
      expect(find.text('Full Backup (.zip)'), findsOneWidget);

      // Drive the REAL .zip tile: production onTap is
      // `Navigator.of(ctx).pop('zip')` (settings_page.dart).
      await tester.tap(find.byKey(UiKeys.settingsExportFullBackupOption));
      await settleSettings(tester);

      // Chooser dismissed — both tiles gone — so the real tile onTap ran
      // Navigator.pop(...) and `_showExportOptions`'s await returned.
      expect(
        find.byKey(UiKeys.settingsExportFullBackupOption),
        findsNothing,
        reason: 'Full Backup (.zip) tile gone → real pop ran',
      );
      expect(
        find.byKey(UiKeys.settingsExportProfileToxOption),
        findsNothing,
        reason: 'Profile (.tox) tile gone → chooser dismissed',
      );
      // The bypass seam stayed armed (the native picker never blocked).
      expect(debugCurrentExportSaveFileOverridePath, overridePath);
    },
  );

  testWidgets(
    "the real chooser route pops exactly 'zip' from the Full Backup tile",
    (WidgetTester tester) async {
      // Suppress the post-pop native save step.
      debugSetL3TestSurfaceEnabledForTests(true);
      debugSetExportSaveFileOverridePathForTests(
        p.join(tempRoot.path, 'direct_probe.zip'),
      );

      final service = SettingsHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Object? choiceResult;
      var sawChoiceResult = false;
      final observer = FirstDialogResultObserver(
        onRouteResult: (value) {
          sawChoiceResult = true;
          choiceResult = value;
        },
      );

      await _pumpSettings(tester, service, observers: [observer]);

      await tester.tap(find.byKey(UiKeys.settingsExportAccountButton));
      await settleSettings(tester);
      expect(find.byKey(UiKeys.settingsExportFullBackupOption), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.settingsExportFullBackupOption));
      await settleSettings(tester);

      // The chooser route's `popped` future resolved to 'zip'.
      expect(
        sawChoiceResult,
        isTrue,
        reason: 'chooser route was pushed and later popped',
      );
      expect(
        choiceResult,
        'zip',
        reason: "real .zip tile routes Navigator.pop('zip')",
      );
    },
  );
}
