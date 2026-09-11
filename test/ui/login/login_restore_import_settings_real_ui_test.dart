// Real-UI L1 WidgetTester gates for the toxee LOGIN page RESTORE / IMPORT
// actions, the ERROR BANNER + Retry, and the SETTINGS navigation entry.
//
// WHY these are REAL-UI gates:
//   - RESTORE: we pump the REAL `LoginPage`, inject a `LoginPageController`
//     whose `restoreFromToxFile` returns `RestoreSuccess` (the documented test
//     seam — the real picker is never reached), tap the REAL
//     `UiKeys.loginPageRestoreFromToxFile` card, and assert the production
//     `_restoreFromToxFile` handler primed the nickname controller AND cached
//     the restored password so a follow-up quick-login does NOT re-prompt.
//   - IMPORT: we inject a controller that records `importAccount`, tap the REAL
//     keyed Import card, and assert the production `_importToxProfile` handler
//     invoked it (with the default-name argument it computes from l10n).
//   - ERROR BANNER: a controller returning `LoginControllerFailure` drives a
//     quick-login on a no-password account; the REAL `ErrorBanner` renders with
//     the message + a Retry button; tapping Retry re-invokes login.
//   - SETTINGS: a `NavigatorObserver` records routes; tapping the REAL AppBar
//     settings icon pushes a new route (the LoginSettingsPage).
//
// Mobile parity: login_page.dart is shared Dart; these affordances render
// identically on every target. See the header comment in lib/ui/login_page.dart.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/auth/login_use_case.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/login/login_page_controller.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

const _importCardKey = Key('login_page_import_account_card');

/// Controller that records restore + the follow-up login, mirroring the
/// existing _RestoringLoginPageController in login_page_widget_test.dart.
class _RestoringController extends LoginPageController {
  static const toxId =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  static const password = 'restored-secret';
  LoginParams? lastLoginParams;
  int restoreCalls = 0;

  @override
  Future<RestoreResult> restoreFromToxFile({
    required Future<String?> Function() requestPassword,
    required String importedAccountDefaultName,
    String? filePathOverride,
  }) async {
    restoreCalls++;
    return const RestoreSuccess(
      toxId: toxId,
      nickname: 'Recovered',
      password: password,
    );
  }

  @override
  Future<LoginControllerResult> login({
    required String nickname,
    required String statusMessage,
    String? password,
  }) async {
    lastLoginParams = LoginParams(
      nickname: nickname,
      statusMessage: statusMessage,
      password: password,
    );
    return const LoginControllerFailure('stop after recording');
  }
}

/// Controller that records importAccount; returns a failure so the page stays.
class _RecordingImportController extends LoginPageController {
  int importCalls = 0;
  String? lastImportedDefaultName;

  @override
  Future<ImportResult> importAccount({
    required Future<String?> Function() requestPassword,
    required String importedAccountDefaultName,
    String? filePathOverride,
  }) async {
    importCalls++;
    lastImportedDefaultName = importedAccountDefaultName;
    return const ImportFailure(ImportFailureKind.cancelled);
  }
}

/// Controller that fails login a controlled number of times, counting calls —
/// used for the error-banner + Retry gate.
class _FailingLoginController extends LoginPageController {
  int loginCalls = 0;

  @override
  Future<LoginControllerResult> login({
    required String nickname,
    required String statusMessage,
    String? password,
  }) async {
    loginCalls++;
    return const LoginControllerFailure('login boom');
  }
}

/// Records pushed routes so the settings-nav test can assert a push happened.
class _RouteRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

Widget _pumpableLoginPage({
  LoginPageController? loginPageController,
  List<NavigatorObserver> observers = const [],
}) {
  return MaterialApp(
    navigatorObservers: observers,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: LoginPage(loginPageController: loginPageController),
  );
}

Future<void> _pumpAndLoad(WidgetTester tester, Widget root) async {
  await tester.binding.setSurfaceSize(const Size(1024, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(root);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secureStore = <String, String>{};
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
          final args =
              (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
          switch (call.method) {
            case 'write':
              secureStore[args['key'] as String] = args['value'] as String;
              return null;
            case 'read':
              return secureStore[args['key'] as String];
            case 'delete':
              secureStore.remove(args['key'] as String);
              return null;
            case 'containsKey':
              return secureStore.containsKey(args['key'] as String);
            case 'readAll':
              return Map<String, String>.from(secureStore);
            case 'deleteAll':
              secureStore.clear();
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  Future<void> initAccounts(List<Map<String, String>> accounts) async {
    SharedPreferences.setMockInitialValues({
      'account_list': jsonEncode(accounts),
    });
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  }

  Future<void> initEmpty() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  }

  group('LoginPage restore-from-.tox', () {
    testWidgets(
      'tapping Restore primes the nickname + caches the password so the next '
      'quick-login does NOT re-prompt',
      (tester) async {
        // Seed the restored account so it is already present in the picker
        // (the production handler also reloads the list on success).
        await initAccounts([
          {
            'toxId': _RestoringController.toxId,
            'nickname': 'Recovered',
            'statusMessage': '',
          },
        ]);
        final controller = _RestoringController();
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );

        await tester.tap(find.byKey(UiKeys.loginPageRestoreFromToxFile));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          controller.restoreCalls,
          1,
          reason: 'Tapping Restore must invoke restoreFromToxFile',
        );
        // Success SnackBar names the recovered account.
        expect(find.textContaining('Recovered'), findsWidgets);

        // Tap the restored account: because the password was cached, no
        // password dialog should appear and login proceeds with that password.
        await tester.tap(
          find.byKey(UiKeys.loginPageAccountCard(_RestoringController.toxId)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason:
              'The restored password must be reused — no re-prompt on the '
              'follow-up quick-login',
        );
        expect(
          controller.lastLoginParams,
          isNotNull,
          reason: 'The restored account tap must proceed into login',
        );
        expect(controller.lastLoginParams!.nickname, 'Recovered');
        expect(
          controller.lastLoginParams!.password,
          _RestoringController.password,
          reason: 'The cached restore password must flow into login()',
        );
      },
    );
  });

  group('LoginPage import account', () {
    testWidgets(
      'tapping Import invokes importAccount with the localized default name',
      (tester) async {
        await initEmpty();
        final controller = _RecordingImportController();
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );

        expect(
          find.byKey(_importCardKey),
          findsOneWidget,
          reason: 'Import action card must be present',
        );
        await tester.tap(find.byKey(_importCardKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          controller.importCalls,
          1,
          reason: 'Tapping Import must invoke importAccount exactly once',
        );
        // The production handler passes l10n.importedAccountDefaultName.
        expect(controller.lastImportedDefaultName, isNotNull);
        expect(
          controller.lastImportedDefaultName!.isNotEmpty,
          isTrue,
          reason: 'importAccount must receive a non-empty default account name',
        );
      },
    );
  });

  group('LoginPage error banner + retry', () {
    testWidgets(
      'a login failure renders the error banner with a Retry button that '
      're-invokes login',
      (tester) async {
        const toxId =
            'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
        final controller = _FailingLoginController();
        await initAccounts([
          {'toxId': toxId, 'nickname': 'Bob', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );

        // Quick-login a no-password account -> login() -> controlled failure.
        await tester.tap(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          controller.loginCalls,
          1,
          reason: 'The first tap must invoke login once',
        );
        // The REAL ErrorBanner renders the failure message + a Retry button.
        expect(
          find.textContaining('login boom'),
          findsWidgets,
          reason: 'The error banner must carry the failure message',
        );
        final retry = find.widgetWithText(TextButton, 'Retry');
        expect(
          retry,
          findsOneWidget,
          reason: 'The error banner must expose a Retry action',
        );

        // Tapping Retry clears the error and re-invokes login (which fails
        // again, re-rendering the banner).
        await tester.tap(retry);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(controller.loginCalls, 2, reason: 'Retry must re-invoke login');
        expect(
          find.textContaining('login boom'),
          findsWidgets,
          reason: 'The banner re-renders after the retry also fails',
        );
      },
    );
  });

  group('LoginPage settings navigation', () {
    testWidgets('tapping the login settings button pushes a new route', (
      tester,
    ) async {
      await initEmpty();
      final recorder = _RouteRecorder();
      await _pumpAndLoad(tester, _pumpableLoginPage(observers: [recorder]));

      final pushedBefore = recorder.pushed.length;
      expect(find.byKey(UiKeys.loginPageSettingsButton), findsOneWidget);
      await tester.tap(find.byKey(UiKeys.loginPageSettingsButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        recorder.pushed.length,
        greaterThan(pushedBefore),
        reason:
            'Tapping the login settings button must push the LoginSettingsPage '
            'route onto the navigator',
      );
      // The most-recently pushed route is the settings page (a non-dialog
      // PageRoute). Its presence proves navigation, not just a SnackBar.
      expect(recorder.pushed.last, isA<PageRoute<dynamic>>());
    });
  });
}
