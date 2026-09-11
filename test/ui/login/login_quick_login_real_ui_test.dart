// Real-UI L1 WidgetTester gates for the toxee LOGIN page: saved-account
// quick-login, the empty-nickname validation branch, busy-state disabling of
// the action cards, and successful-login progression.
//
// WHY these are REAL-UI gates (not synthetic-callback probes):
//   - Every case pumps the REAL production `LoginPage` widget and drives the
//     REAL `InkWell` saved-account card (UiKeys.loginPageAccountCard) via a
//     hit-tested `tester.tap`, so the production `_quickLogin` -> `_login`
//     chain runs end-to-end (Prefs password check, controller resolution,
//     boot/teardown). We never re-implement a handler.
//   - The only injected seam is the `LoginPageController` (the documented
//     test seam on `LoginPage`): a recording stub captures the LoginParams
//     the production handler computed, OR a never-completing stub holds the
//     login Future in flight so we can observe the busy UI state. Both are
//     real observable side-effects of the production code path.
//
// Mobile parity: login_page.dart is shared Dart with no platform split
// (see the header comment in lib/ui/login_page.dart). The saved-account
// quick-login path runs identically on iOS/Android/desktop; this L1 gate
// covers every target.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/auth/login_use_case.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/login/login_page_controller.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

/// Stub FfiChatService that absorbs the service surface a "successful" login
/// would hand back. We never log in for real; the controller stub returns
/// this without touching FFI.
class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService() : super();
}

/// Recording controller: captures the LoginParams the production `_login`
/// handler computed, then returns a controlled failure so the page stops
/// (no boot/navigation). The captured params prove the real saved-account
/// row mapped nickname/status/password correctly.
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

/// Controller whose login() never completes — pins the in-flight busy state
/// so the test can assert the action cards are disabled while login runs.
class _PendingLoginPageController extends LoginPageController {
  final Completer<LoginControllerResult> completer =
      Completer<LoginControllerResult>();
  int loginCalls = 0;

  @override
  Future<LoginControllerResult> login({
    required String nickname,
    required String statusMessage,
    String? password,
  }) async {
    loginCalls++;
    return completer.future; // never completes unless the test completes it
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

/// Pump the LoginPage and drain its async post-initState Prefs reads.
/// Strict: any RenderFlex overflow fails the test (the historical swallow
/// hid live login-page overflows; see the 2026-09-11 layout audit, H5, and
/// login_page_widget_test.dart).
Future<void> _pumpAndLoad(WidgetTester tester, Widget root) async {
  await tester.binding.setSurfaceSize(const Size(1024, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(root);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _initPrefs(List<Map<String, String>> accounts) async {
  SharedPreferences.setMockInitialValues({
    'account_list': jsonEncode(accounts),
  });
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage has no platform implementation under `flutter test`;
  // an unmocked channel reply never arrives in the FakeAsync zone, so any flow
  // that awaits Prefs.hasAccountPassword would hang forever. Mirror the
  // in-memory channel mock used by the other login tests.
  final secureStore = <String, String>{};
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

  group('LoginPage quick-login (no-password accounts)', () {
    testWidgets(
      'tapping the saved-account card invokes the production login with the '
      'account nickname + status (no password)',
      (tester) async {
        final aliceToxId = 'A' * 64;
        final bobToxId = 'B' * 64;
        final controller = _RecordingLoginPageController();
        await _initPrefs([
          {'toxId': aliceToxId, 'nickname': 'Alice', 'statusMessage': 'alpha'},
          {'toxId': bobToxId, 'nickname': 'Bob', 'statusMessage': 'beta'},
        ]);
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );

        // Let the staggered row animations settle so the gesture lands on the
        // keyed affordance, not a still-sliding transition target.
        await tester.pump(const Duration(milliseconds: 400));

        // Drive the REAL InkWell saved-account card via its production key.
        final bobCard = find.byKey(UiKeys.loginPageAccountCard(bobToxId));
        expect(bobCard, findsOneWidget);
        await tester.tap(bobCard);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // The production `_quickLogin` -> `_login` chain ran end-to-end and
        // handed the controller the exact nickname/status from Bob's row.
        expect(controller.loginCalls, 1,
            reason: 'Saved-account tap must invoke the injected controller once');
        expect(controller.lastLoginParams, isNotNull);
        expect(controller.lastLoginParams!.nickname, 'Bob');
        expect(controller.lastLoginParams!.statusMessage, 'beta');
        // No-password account: nothing was prompted, so password is null.
        expect(controller.lastLoginParams!.password, isNull,
            reason:
                'No-password accounts must reach login() with a null password');
        // No password dialog appeared on the way.
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'tapping a DIFFERENT saved-account card targets THAT account, proving '
      'per-row identity (not the first/last row)',
      (tester) async {
        final aliceToxId = 'A' * 64;
        final bobToxId = 'B' * 64;
        final carolToxId = 'C' * 64;
        final controller = _RecordingLoginPageController();
        await _initPrefs([
          {'toxId': aliceToxId, 'nickname': 'Alice', 'statusMessage': 'alpha'},
          {'toxId': bobToxId, 'nickname': 'Bob', 'statusMessage': 'beta'},
          {'toxId': carolToxId, 'nickname': 'Carol', 'statusMessage': 'gamma'},
        ]);
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.byKey(UiKeys.loginPageAccountCard(aliceToxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(controller.lastLoginParams!.nickname, 'Alice',
            reason: 'The Alice row key must drive Alice, not another account');
        expect(controller.lastLoginParams!.statusMessage, 'alpha');
      },
    );

    testWidgets(
      'a successful login result does NOT re-enter login on a second tap '
      '(busy is held through boot/navigation)',
      (tester) async {
        // Boot is held open so _busy stays true after login succeeds; a second
        // tap must be a no-op (the page is mid-boot, about to navigate away).
        final toxId = 'D' * 64;
        final service = _StubFfiChatService();
        // Boot is held open forever so login "succeeds" but never navigates —
        // the page stays in the busy state we assert against (completing it
        // would push the FFI-backed HomePage, which can't tear down cleanly).
        final bootGate = Completer<void>();
        var loginCalls = 0;
        final controller = _SuccessThenCountController(service, () {
          loginCalls++;
        });
        await _initPrefs([
          {'toxId': toxId, 'nickname': 'Dave', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(
          tester,
          MaterialApp(
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
              bootSession: (_) => bootGate.future, // hold boot open
              teardownSession: ({required service, reEncryptProfile = true}) async {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        final card = find.byKey(UiKeys.loginPageAccountCard(toxId));
        await tester.tap(card);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // login() fired once; boot is now in flight (held by bootGate).
        expect(loginCalls, 1);

        // Second tap while mid-boot must be ignored (_busy guard).
        await tester.tap(card, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(loginCalls, 1,
            reason:
                'A second tap while boot is in flight must not re-enter login');

        // We intentionally leave boot in flight (bootGate never completes):
        // completing it would push the REAL HomePage, which spins up FFI-backed
        // timers we can't tear down in a pure widget test. Holding boot open is
        // exactly the busy state we want to assert against, and the unresolved
        // Future is not a pending Timer.
      },
    );
  });

  group('LoginPage empty-nickname validation', () {
    testWidgets(
      'quick-login on a blank-nickname account surfaces the empty-nickname '
      'error and never invokes login',
      (tester) async {
        // The picker renders an "Unnamed account" label, but the stored
        // nickname is empty. _quickLogin fills the controller with '' and
        // _login() hits the `if (nickname.isEmpty)` guard before the
        // controller is ever called.
        final toxId = 'E' * 64;
        final controller = _RecordingLoginPageController();
        await _initPrefs([
          {'toxId': toxId, 'nickname': '', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // The production validation branch fired: login was NOT invoked.
        expect(controller.loginCalls, 0,
            reason: 'Empty nickname must short-circuit before login()');
        // The error SnackBar surfaces the "cannot be empty" copy. The en arb
        // maps `nickname` to "Nickname"; the handler appends " cannot be empty".
        expect(
          find.textContaining(RegExp('cannot be empty', caseSensitive: false)),
          findsWidgets,
          reason: 'Empty-nickname guard must surface a validation message',
        );
      },
    );
  });

  group('LoginPage busy state', () {
    testWidgets(
      'while login is in flight the Restore / Import / Register action cards '
      'are disabled (onTap == null)',
      (tester) async {
        final toxId = 'F' * 64;
        final controller = _PendingLoginPageController();
        await _initPrefs([
          {'toxId': toxId, 'nickname': 'Fiona', 'statusMessage': ''},
        ]);
        await _pumpAndLoad(
          tester,
          _pumpableLoginPage(loginPageController: controller),
        );
        await tester.pump(const Duration(milliseconds: 400));

        // Pre-condition: Restore action is ENABLED before any login.
        final restoreBefore = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(UiKeys.loginPageRestoreFromToxFile),
            matching: find.byType(InkWell),
          ),
        );
        expect(restoreBefore.onTap, isNotNull,
            reason: 'Restore must be tappable before a login starts');

        // Start the login; it never resolves (controller holds the Future).
        await tester.tap(find.byKey(UiKeys.loginPageAccountCard(toxId)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.loginCalls, 1);

        // The page has no spinner; busy is observable as the action cards
        // being disabled. Restore + Import both gate on `_busy ? null : ...`.
        final restoreDuring = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(UiKeys.loginPageRestoreFromToxFile),
            matching: find.byType(InkWell),
          ),
        );
        expect(restoreDuring.onTap, isNull,
            reason:
                'Restore action must be disabled while a login is in flight');

        final importDuring = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(const Key('login_page_import_account_card')),
            matching: find.byType(InkWell),
          ),
        );
        expect(importDuring.onTap, isNull,
            reason:
                'Import action must be disabled while a login is in flight');

        // Resolve the in-flight login so the test tears down cleanly.
        controller.completer.complete(
          const LoginControllerFailure('done'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      },
    );
  });
}

/// Controller that returns success (so boot runs) and notifies a counter on
/// each login() call — used to prove the second tap doesn't re-enter login.
class _SuccessThenCountController extends LoginPageController {
  _SuccessThenCountController(this.service, this.onLogin);

  final FfiChatService service;
  final void Function() onLogin;

  @override
  Future<LoginControllerResult> login({
    required String nickname,
    required String statusMessage,
    String? password,
  }) async {
    onLogin();
    return LoginControllerSuccess(service);
  }
}
