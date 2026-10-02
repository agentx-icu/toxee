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
Future<Future<String?>> _openDialog(WidgetTester tester) async {
  late Future<String?> result;
  await tester.pumpWidget(
    settingsApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => result = showExportPasswordDialog(context, _title),
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
    expect(
      {
        SettingsUiKeys.exportPasswordField,
        SettingsUiKeys.exportPasswordConfirmField,
        SettingsUiKeys.exportPasswordOkButton,
        SettingsUiKeys.exportPasswordCancelButton,
      },
      hasLength(4),
    );
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
}
