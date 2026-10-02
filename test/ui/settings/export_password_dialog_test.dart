// Widget gate for ExportPasswordDialog — the password + confirmation prompt in
// front of the settings exports (`.tox` and full backup).
//
// WHY: real-UI drivers address this dialog purely by key (marionette
// `tap(key:)` / `enterText(key:)`). It had no anchors until the 2026-10-01
// iOS at-rest verification needed to drive it on a simulator, where there is
// no synthetic tap at all. These tests pin the four anchors as a wire contract
// and prove the REAL widget's behaviour behind them: matching passwords pop
// the password through the OK anchor, a mismatch keeps the dialog open with
// the error snackbar, and the Cancel anchor pops null.
//
// Mobile parity: shared Dart; the dialog renders identically on every target.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/settings/export_password_dialog.dart';
import 'package:toxee/ui/testing/ui_keys_settings.dart';

import 'settings_account_test_support.dart';

const _title = 'Export title probe';

/// Pumps a host page and opens the REAL dialog through
/// [showExportPasswordDialog]; returns the dialog's pop future.
Future<Future<String?>> _openDialog(
  WidgetTester tester, {
  bool allowEmpty = true,
}) async {
  late Future<String?> result;
  await tester.pumpWidget(
    settingsApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => result = showExportPasswordDialog(
            context,
            title: _title,
            allowEmpty: allowEmpty,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text(_title), findsOneWidget);
  return result;
}

void main() {
  test('anchors keep their automation strings and are distinct', () {
    expect(
      SettingsUiKeys.exportPasswordField,
      const Key('settings_export_password_field'),
    );
    expect(
      SettingsUiKeys.exportPasswordConfirmField,
      const Key('settings_export_password_confirm_field'),
    );
    expect(
      SettingsUiKeys.exportPasswordOkButton,
      const Key('settings_export_password_ok_button'),
    );
    expect(
      SettingsUiKeys.exportPasswordCancelButton,
      const Key('settings_export_password_cancel_button'),
    );
    // A driver picks OK vs Cancel, and field vs confirm field, purely by key.
    expect({
      SettingsUiKeys.exportPasswordField,
      SettingsUiKeys.exportPasswordConfirmField,
      SettingsUiKeys.exportPasswordOkButton,
      SettingsUiKeys.exportPasswordCancelButton,
    }, hasLength(4));
  });

  testWidgets('the real dialog renders all four anchors', (tester) async {
    await _openDialog(tester);
    expect(find.byKey(SettingsUiKeys.exportPasswordField), findsOneWidget);
    expect(
      find.byKey(SettingsUiKeys.exportPasswordConfirmField),
      findsOneWidget,
    );
    expect(find.byKey(SettingsUiKeys.exportPasswordOkButton), findsOneWidget);
    expect(
      find.byKey(SettingsUiKeys.exportPasswordCancelButton),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(
      find.byKey(SettingsUiKeys.exportPasswordField),
    );
    final confirm = tester.widget<TextField>(
      find.byKey(SettingsUiKeys.exportPasswordConfirmField),
    );
    expect(field.obscureText, isTrue);
    expect(confirm.obscureText, isTrue);
  });

  testWidgets('matching passwords pop the password via the OK anchor', (
    tester,
  ) async {
    final result = await _openDialog(tester);
    await tester.enterText(
      find.byKey(SettingsUiKeys.exportPasswordField),
      'export pw 1',
    );
    await tester.enterText(
      find.byKey(SettingsUiKeys.exportPasswordConfirmField),
      'export pw 1',
    );
    await tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
    expect(await result, 'export pw 1');
  });

  testWidgets('a mismatch keeps the dialog open and shows the error', (
    tester,
  ) async {
    await _openDialog(tester);
    await tester.enterText(
      find.byKey(SettingsUiKeys.exportPasswordField),
      'export pw 1',
    );
    await tester.enterText(
      find.byKey(SettingsUiKeys.exportPasswordConfirmField),
      'export pw 2',
    );
    await tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton));
    await tester.pump();
    expect(find.text(_title), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('the Cancel anchor pops null', (tester) async {
    final result = await _openDialog(tester);
    await tester.tap(find.byKey(SettingsUiKeys.exportPasswordCancelButton));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
    expect(await result, isNull);
  });

  test('the empty-password warning anchor keeps its automation string', () {
    expect(
      SettingsUiKeys.exportPasswordEmptyWarning,
      const Key('settings_export_password_empty_warning'),
    );
  });

  testWidgets('optional mode: warning while empty; empty pops "" (plaintext)', (
    tester,
  ) async {
    final result = await _openDialog(tester);
    expect(find.text('Export password'), findsOneWidget);
    expect(find.textContaining('separate from your account'), findsOneWidget);
    expect(
      find.byKey(SettingsUiKeys.exportPasswordEmptyWarning),
      findsOneWidget,
    );
    // The pinned confirm button names the consequence while empty.
    expect(
      find.descendant(
        of: find.byKey(SettingsUiKeys.exportPasswordOkButton),
        matching: find.text('Export unencrypted'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(SettingsUiKeys.exportPasswordField), 'x');
    await tester.pump();
    expect(find.byKey(SettingsUiKeys.exportPasswordEmptyWarning), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(SettingsUiKeys.exportPasswordOkButton),
        matching: find.text('OK'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(SettingsUiKeys.exportPasswordField), '');
    await tester.pump();
    expect(
      find.byKey(SettingsUiKeys.exportPasswordEmptyWarning),
      findsOneWidget,
    );
    await tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton));
    await tester.pumpAndSettle();
    expect(await result, '');
    expect(exportPasswordOrNull(''), isNull);
    expect(exportPasswordOrNull('pw'), 'pw');
  });

  testWidgets('required mode: empty is refused inline, dialog stays open', (
    tester,
  ) async {
    final result = await _openDialog(tester, allowEmpty: false);
    expect(find.byKey(SettingsUiKeys.exportPasswordEmptyWarning), findsNothing);
    await tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton));
    await tester.pump();
    expect(find.text(_title), findsOneWidget);
    expect(find.text('A full backup needs an export password'), findsOneWidget);
    await tester.enterText(
      find.byKey(SettingsUiKeys.exportPasswordField),
      'backup pw',
    );
    await tester.pump();
    expect(find.text('A full backup needs an export password'), findsNothing);
    await tester.enterText(
      find.byKey(SettingsUiKeys.exportPasswordConfirmField),
      'backup pw',
    );
    await tester.tap(find.byKey(SettingsUiKeys.exportPasswordOkButton));
    await tester.pumpAndSettle();
    expect(await result, 'backup pw');
  });

  testWidgets('landscape phone with the keyboard up: fields stay reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.reset);
    await _openDialog(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(SettingsUiKeys.exportPasswordConfirmField),
    );
    await tester.ensureVisible(
      find.byKey(SettingsUiKeys.exportPasswordOkButton),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Even with the warning scrolled away, the hit-testable confirm button
    // itself says "Export unencrypted" while the password is empty.
    expect(
      find
          .descendant(
            of: find.byKey(SettingsUiKeys.exportPasswordOkButton),
            matching: find.text('Export unencrypted'),
          )
          .hitTestable(),
      findsOneWidget,
    );
  });
}
