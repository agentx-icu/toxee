import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/login/login_page_controller.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

const _importCardKey = Key('login_page_import_account_card');
const _exportOptionKey = Key('login_account_management_export_option');
const _savedToxId = 'A';

class _PendingAccountOperationController extends LoginPageController {
  final List<Completer<RestoreResult>> restoreAttempts = [];
  final List<Completer<ImportResult>> importAttempts = [];

  @override
  Future<RestoreResult> restoreFromToxFile({
    required Future<String?> Function() requestPassword,
    required String importedAccountDefaultName,
    String? filePathOverride,
  }) {
    final attempt = Completer<RestoreResult>();
    restoreAttempts.add(attempt);
    return attempt.future;
  }

  @override
  Future<ImportResult> importAccount({
    required Future<String?> Function() requestPassword,
    required String importedAccountDefaultName,
    String? filePathOverride,
  }) {
    final attempt = Completer<ImportResult>();
    importAttempts.add(attempt);
    return attempt.future;
  }
}

Widget _loginPage({
  LoginPageController? controller,
  Future<String> Function({required String toxId, String? password})?
  exportAccount,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: LoginPage(
      loginPageController: controller,
      exportAccount: exportAccount,
      isDesktopExportPlatformOverride: true,
    ),
  );
}

Future<void> _pumpLoginPage(WidgetTester tester, Widget page) async {
  await tester.binding.setSurfaceSize(const Size(1024, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(page);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _initPrefs({bool withSavedAccount = false}) async {
  SharedPreferences.setMockInitialValues({
    if (withSavedAccount)
      'account_list': jsonEncode([
        {'toxId': _savedToxId, 'nickname': 'Alice', 'statusMessage': ''},
      ]),
  });
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

Future<void> _openExportMenu(WidgetTester tester) async {
  await tester.longPress(find.byKey(UiKeys.loginPageAccountCard(_savedToxId)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'restore is single-flight while pending and can retry after failure',
    (tester) async {
      await _initPrefs();
      final controller = _PendingAccountOperationController();
      await _pumpLoginPage(tester, _loginPage(controller: controller));

      final restore = find.byKey(UiKeys.loginPageRestoreFromToxFile);
      await tester.tap(restore);
      await tester.tap(restore);
      await tester.pump();

      expect(controller.restoreAttempts, hasLength(1));

      controller.restoreAttempts.single.complete(
        const RestoreFailure(RestoreFailureKind.cancelled),
      );
      await tester.pump();

      await tester.tap(restore);
      await tester.pump();
      expect(controller.restoreAttempts, hasLength(2));

      controller.restoreAttempts.last.complete(
        const RestoreFailure(RestoreFailureKind.cancelled),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'import is single-flight while pending and can retry after failure',
    (tester) async {
      await _initPrefs();
      final controller = _PendingAccountOperationController();
      await _pumpLoginPage(tester, _loginPage(controller: controller));

      final import = find.byKey(_importCardKey);
      await tester.tap(import);
      await tester.tap(import);
      await tester.pump();

      expect(controller.importAttempts, hasLength(1));

      controller.importAttempts.single.complete(
        const ImportFailure(ImportFailureKind.cancelled),
      );
      await tester.pump();

      await tester.tap(import);
      await tester.pump();
      expect(controller.importAttempts, hasLength(2));

      controller.importAttempts.last.complete(
        const ImportFailure(ImportFailureKind.cancelled),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'saved-account export is single-flight and can retry after an error',
    (tester) async {
      await _initPrefs(withSavedAccount: true);
      final exportAttempts = <Completer<String>>[];
      await _pumpLoginPage(
        tester,
        _loginPage(
          exportAccount: ({required String toxId, String? password}) {
            final attempt = Completer<String>();
            exportAttempts.add(attempt);
            return attempt.future;
          },
        ),
      );

      await _openExportMenu(tester);
      await tester.tap(find.byKey(_exportOptionKey));
      await tester.pump(const Duration(milliseconds: 300));

      await _openExportMenu(tester);
      await tester.tap(find.byKey(_exportOptionKey));
      await tester.pump(const Duration(milliseconds: 300));
      expect(exportAttempts, hasLength(1));

      exportAttempts.single.completeError(Exception('export failed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await _openExportMenu(tester);
      await tester.tap(find.byKey(_exportOptionKey));
      await tester.pump();
      expect(exportAttempts, hasLength(2));

      exportAttempts.last.complete('/tmp/alice.tox');
      await tester.pump();
    },
  );
}
