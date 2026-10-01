// The login page's "Import Account" card shows TWO differently titled prompts
// for an older full backup whose profile is ciphertext under the account
// password: first the archive password, then the account password of the
// install that wrote the backup. With one shared title the user retyped the
// archive password and the import ended in a bare "Invalid password".
//
// The controller is faked: it asks for both layers through the callbacks the
// page hands it and records what the page's dialogs returned. The dialog is
// the real PasswordPromptDialog, driven through its automation keys.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/login/login_page_controller.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/ui/testing/ui_keys_login.dart';
import 'package:toxee/util/prefs.dart';

class _TwoLayerImportController extends LoginPageController {
  final List<String?> answers = [];

  @override
  Future<ImportResult> importAccount({
    required Future<String?> Function() requestPassword,
    required String importedAccountDefaultName,
    Future<String?> Function()? requestProfilePassword,
    String? filePathOverride,
  }) async {
    answers.add(await requestPassword());
    answers.add(await (requestProfilePassword ?? requestPassword)());
    return const ImportFailure(ImportFailureKind.cancelled);
  }
}

Widget _loginPage(LoginPageController controller) {
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
      isDesktopExportPlatformOverride: true,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
          switch (call.method) {
            case 'readAll':
              return <String, String>{};
            case 'containsKey':
              return false;
            default:
              return null;
          }
        });
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  testWidgets(
    'archive and account passwords are asked with distinct titles',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = _TwoLayerImportController();
      await tester.pumpWidget(_loginPage(controller));
      await _settle(tester);

      await tester.tap(find.byKey(LoginUiKeys.loginPageImportAccountCard));
      await _settle(tester);

      expect(find.text('Enter password to import account'), findsOneWidget);
      expect(
        find.text('Enter the account password of this backup'),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(LoginUiKeys.passwordPromptField),
        'zip-pw',
      );
      await tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton));
      await _settle(tester);

      expect(
        find.text('Enter the account password of this backup'),
        findsOneWidget,
      );
      expect(find.text('Enter password to import account'), findsNothing);
      await tester.enterText(
        find.byKey(LoginUiKeys.passwordPromptField),
        'acct-pw',
      );
      await tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton));
      await _settle(tester);

      expect(controller.answers, ['zip-pw', 'acct-pw']);
      expect(find.byKey(LoginUiKeys.passwordPromptField), findsNothing);
    },
  );

  testWidgets('cancelling the account-password prompt returns null', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _TwoLayerImportController();
    await tester.pumpWidget(_loginPage(controller));
    await _settle(tester);

    await tester.tap(find.byKey(LoginUiKeys.loginPageImportAccountCard));
    await _settle(tester);
    await tester.enterText(
      find.byKey(LoginUiKeys.passwordPromptField),
      'zip-pw',
    );
    await tester.tap(find.byKey(LoginUiKeys.passwordPromptOkButton));
    await _settle(tester);
    expect(
      find.text('Enter the account password of this backup'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(LoginUiKeys.passwordPromptCancelButton));
    await _settle(tester);

    expect(controller.answers, ['zip-pw', null]);
  });
}
