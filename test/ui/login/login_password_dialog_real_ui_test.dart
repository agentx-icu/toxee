// Real-UI L1 WidgetTester gates for the toxee LOGIN page quick-login PASSWORD
// dialog (`_showPasswordDialog`, invoked from `_quickLogin` when a saved
// account is password-protected).
//
// WHY these are REAL-UI gates:
//   - We pump the REAL production `LoginPage`, seed a password-protected
//     account into Prefs (the real PBKDF2 hash + salt is written through the
//     in-memory flutter_secure_storage mock by Prefs.setAccountPassword), and
//     tap the REAL saved-account `InkWell`. That drives the production
//     `_quickLogin`, which calls `Prefs.hasAccountPassword` (true) and shows
//     the REAL AlertDialog.
//   - We assert on the REAL dialog widgets: the obscured password field, the
//     visibility-toggle IconButton, and that toggling it flips `obscureText`
//     on the live TextField.
//   - Wrong password -> the production `Prefs.verifyAccountPassword` returns
//     false -> the "Invalid password" error surfaces and login is NEVER
//     invoked. Correct password -> verification passes and the injected
//     recording controller is invoked with that password.
//
// CRYPTO NOTE: `Prefs.setAccountPassword` / `verifyAccountPassword` run
// PBKDF2-HMAC-SHA256 at 150k iterations via `package:cryptography`. That work
// schedules real microtasks/timers which the `testWidgets` FakeAsync zone does
// not drive, so any flow that touches the KDF must run inside
// `tester.runAsync()` (the real event loop). We therefore drive every
// password interaction through `_runRealAsync`, then `pump()` to flush the
// resulting setState into the tree.
//
// Mobile parity: login_page.dart is shared Dart; the password dialog renders
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

class _RecordingLoginPageController extends LoginPageController {
  LoginParams? lastLoginParams;
  int loginCalls = 0;

  @override
  Future<LoginControllerResult> login({
    required String nickname,
    required String statusMessage,
    String? password,
  }) async {
    loginCalls++;
    lastLoginParams = LoginParams(
      nickname: nickname,
      statusMessage: statusMessage,
      password: password,
    );
    return const LoginControllerFailure('stop after recording');
  }
}

Widget _pumpableLoginPage({LoginPageController? loginPageController}) {
  return MaterialApp(
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
  final originalOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = originalOnError);
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().contains('A RenderFlex overflowed')) {
      return;
    }
    final fallback = originalOnError;
    if (fallback != null) fallback(details);
  };
  await tester.pumpWidget(root);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 250));
}

/// Run [action] on the REAL event loop (so PBKDF2's async work completes),
/// then settle the resulting frames. `runAsync` returns once [action]'s Future
/// resolves; the trailing pumps flush any `setState` the production handler
/// scheduled (error banner, dialog dismissal, etc.).
Future<void> _runRealAsync(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  await tester.runAsync(action);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

/// Drive a fire-and-forget production handler (triggered by [trigger]) that
/// performs PBKDF2 work, then waits — on the REAL event loop — until
/// [isDone] reports the effect landed (or a bounded number of real-time pump
/// cycles elapse). This is the only reliable way to let a multi-stage
/// `_quickLogin` -> verify(PBKDF2) -> `_login` -> controller chain finish:
/// each stage hops the real event loop, so we must yield wall-clock time
/// AND pump frames repeatedly, not just once.
Future<void> _tapAndAwait(
  WidgetTester tester, {
  required Finder trigger,
  required bool Function() isDone,
}) async {
  await tester.runAsync(() async {
    await tester.tap(trigger);
    // Up to ~3s of real time, pumping a frame each 50ms so both the async
    // crypto futures and the resulting setState/navigation frames advance.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (isDone()) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  // Final settle outside runAsync to flush any last frame.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
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

  /// Seed a single password-protected account on the REAL event loop. Prefs
  /// must be initialized before pumping; the PBKDF2 write runs inside
  /// `tester.runAsync` so the KDF actually completes.
  Future<void> seedProtectedAccount(
    WidgetTester tester, {
    required String toxId,
    required String nickname,
    required String password,
  }) async {
    SharedPreferences.setMockInitialValues({
      'account_list': jsonEncode([
        {'toxId': toxId, 'nickname': nickname, 'statusMessage': ''},
      ]),
    });
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      final ok = await Prefs.setAccountPassword(toxId, password);
      expect(
        ok,
        isTrue,
        reason: 'precondition: the account password must persist to the mock',
      );
      expect(
        await Prefs.hasAccountPassword(toxId),
        isTrue,
        reason: 'precondition: hasAccountPassword must report true',
      );
    });
  }

  /// Tap the saved-account card on the REAL event loop so the production
  /// `_quickLogin` -> `Prefs.hasAccountPassword` (PBKDF2-adjacent) chain runs
  /// and the password dialog mounts.
  Future<void> openQuickLoginDialog(WidgetTester tester, String toxId) async {
    await tester.pump(const Duration(milliseconds: 400)); // settle row stagger
    await _runRealAsync(tester, () async {
      await tester.tap(find.byKey(UiKeys.loginPageAccountCard(toxId)));
      // Let _quickLogin's async hasAccountPassword resolve + the dialog route
      // push. Pumps inside runAsync drive both the real future and the frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    });
  }

  group('LoginPage quick-login password dialog', () {
    testWidgets(
      'a password-protected saved account opens the REAL password dialog with '
      'an obscured field and a visibility toggle',
      (tester) async {
        const toxId =
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
        await seedProtectedAccount(
          tester,
          toxId: toxId,
          nickname: 'Secured',
          password: 's3cret-pw',
        );
        await _pumpAndLoad(tester, _pumpableLoginPage());
        await openQuickLoginDialog(tester, toxId);

        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'A password-protected account must prompt before logging in',
        );
        final fieldFinder = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        expect(fieldFinder, findsOneWidget);
        expect(
          tester.widget<TextField>(fieldFinder).obscureText,
          isTrue,
          reason: 'Password field must start obscured',
        );
        final passwordField = tester.widget<TextField>(fieldFinder);
        expect(passwordField.autofillHints, contains(AutofillHints.password));
        expect(passwordField.textInputAction, TextInputAction.done);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byIcon(Icons.visibility_off),
          ),
          findsOneWidget,
          reason: 'Visibility toggle must render in its hidden state initially',
        );
      },
    );

    testWidgets(
      'tapping the visibility toggle flips obscureText on the live field',
      (tester) async {
        const toxId =
            'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
        await seedProtectedAccount(
          tester,
          toxId: toxId,
          nickname: 'Secured',
          password: 's3cret-pw',
        );
        await _pumpAndLoad(tester, _pumpableLoginPage());
        await openQuickLoginDialog(tester, toxId);

        final fieldFinder = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(fieldFinder).obscureText, isTrue);

        // Toggling visibility is a pure synchronous setState (no crypto), so it
        // is safe to do outside runAsync.
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byIcon(Icons.visibility_off),
          ),
        );
        await tester.pump();

        expect(
          tester.widget<TextField>(fieldFinder).obscureText,
          isFalse,
          reason: 'Toggling visibility must reveal the password',
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byIcon(Icons.visibility),
          ),
          findsOneWidget,
          reason: 'Icon must switch to the shown state after toggling',
        );
      },
    );

    testWidgets(
      'a WRONG password surfaces "Invalid password" and never invokes login',
      (tester) async {
        const toxId =
            'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
        final controller = _RecordingLoginPageController();
        await seedProtectedAccount(
          tester,
          toxId: toxId,
          nickname: 'Secured',
          password: 'correct-pw',
        );
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );
        await openQuickLoginDialog(tester, toxId);

        // Type the WRONG password, then confirm via OK on the real event loop
        // so verifyAccountPassword's PBKDF2 completes.
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'wrong-pw',
        );
        await tester.pump();
        // OK -> verifyAccountPassword(PBKDF2) returns false -> error banner +
        // SnackBar. Wait until the invalid-password copy lands.
        await _tapAndAwait(
          tester,
          trigger: find.widgetWithText(TextButton, 'OK'),
          isDone: () => find
              .textContaining(RegExp('Invalid password', caseSensitive: false))
              .evaluate()
              .isNotEmpty,
        );

        expect(
          controller.loginCalls,
          0,
          reason: 'A wrong password must NOT proceed into login',
        );
        expect(
          find.textContaining(RegExp('Invalid password', caseSensitive: false)),
          findsWidgets,
          reason: 'Wrong password must surface the invalid-password message',
        );
      },
    );

    testWidgets(
      'the CORRECT password verifies and proceeds into login with that password',
      (tester) async {
        const toxId =
            'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
        final controller = _RecordingLoginPageController();
        await seedProtectedAccount(
          tester,
          toxId: toxId,
          nickname: 'Secured',
          password: 'correct-pw',
        );
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );
        await openQuickLoginDialog(tester, toxId);

        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'correct-pw',
        );
        await tester.pump();
        // OK -> verify(PBKDF2) passes -> _quickLogin caches the password and
        // chains into _login -> the recording controller. Wait until login
        // actually fired so all the real-async hops have drained.
        await _tapAndAwait(
          tester,
          trigger: find.widgetWithText(TextButton, 'OK'),
          isDone: () => controller.loginCalls >= 1,
        );

        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason: 'Dialog must dismiss after a correct password',
        );
        expect(
          controller.loginCalls,
          1,
          reason: 'A correct password must proceed into login exactly once',
        );
        expect(controller.lastLoginParams!.nickname, 'Secured');
        expect(
          controller.lastLoginParams!.password,
          'correct-pw',
          reason:
              'The verified password must be forwarded to login() so it is '
              'not re-prompted by the use case',
        );
      },
    );

    testWidgets(
      'cancelling the password dialog aborts without invoking login',
      (tester) async {
        const toxId =
            'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';
        final controller = _RecordingLoginPageController();
        await seedProtectedAccount(
          tester,
          toxId: toxId,
          nickname: 'Secured',
          password: 'correct-pw',
        );
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );
        await openQuickLoginDialog(tester, toxId);

        // Cancel is a synchronous Navigator.pop(null) — no crypto.
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byType(AlertDialog), findsNothing);
        expect(
          controller.loginCalls,
          0,
          reason: 'Cancelling the password prompt must not log in',
        );
      },
    );
  });
}
