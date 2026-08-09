// Real-UI L1 gate for the RegisterPage SUBMIT flow: the busy spinner, the
// error banner (retry + dismiss), the back button, and — when the tim2tox
// native lib is available — the full happy-path ordering with argument
// assertions.
//
// HERMETIC tests (no native lib): busy spinner, error banner retry/dismiss,
// back-button pop. These never construct an `FfiChatService`:
//   * the spinner test holds `registerAccount`'s Future open (never completes),
//   * the error-banner test makes `registerAccount` throw,
//   * the back-button test never submits.
//
// FFI-GATED test (skips when the native lib can't load): the happy-path submit
// returns a `RegisterResult(service: _StubFfiChatService())`, and constructing
// any `FfiChatService` subclass opens the tim2tox dylib (`Tim2ToxFfi.open`) in
// its `super()` constructor — exactly like the existing
// register_page_widget_test.dart. We still drive the REAL widget (real typing,
// real button tap) and assert the production `_register()` invoked the injected
// `registerAccount` with the entered nickname/status/password, then `bootSession`
// → `showFirstRunBackupWizard` → `navigateToHome` IN ORDER.
//
// Mobile parity: register_page.dart is shared Dart, so these gates cover iOS /
// Android / desktop identically.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/register_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/prefs.dart';

Widget _wrap(Widget child, {NavigatorObserver? observer}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    navigatorObservers: observer != null ? [observer] : const [],
    home: child,
  );
}

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService() : super();
}

bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _initEmptyPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

// Records the relative order of lifecycle callbacks as the page drives them.
class _OrderLog {
  final List<String> events = [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  // HapticFeedback.lightImpact() (success + failure paths) flows through the
  // JSON platform channel; mock it so the call never throws.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  late String registerLabel;

  setUpAll(() {
    registerLabel = lookupAppLocalizations(const Locale('en')).register;
  });

  setUp(() {
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(platformChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  // ---------------------------------------------------------------------------
  // 9. Busy spinner (HERMETIC) — hold the register Future open.
  // ---------------------------------------------------------------------------
  testWidgets('submit shows the busy spinner and disables the button while in-flight',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A Completer we never complete -> `_register` parks on `await
    // _registerAccount(...)` with `_busy == true`, so the spinner stays up and
    // the button stays disabled. No FfiChatService is ever constructed.
    final gate = Completer<RegisterResult>();

    await tester.pumpWidget(
      _wrap(
        RegisterPage(
          registerAccount: ({
            required nickname,
            required statusMessage,
            required password,
          }) =>
              gate.future,
          bootSession: (_) async {},
          teardownSession: ({required FfiChatService service, bool reEncryptProfile = true}) async {},
          showFirstRunBackupWizard: ({required context, required toxId, required nickname}) async {},
          navigateToHome: (context, service) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.registerPageNicknameField), 'Alice');
    await tester.pump();

    // Before submit: the button shows the "Register" label, no spinner.
    expect(find.text(registerLabel), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byKey(UiKeys.registerPageRegisterButton));
    await tester.pump(); // run validate() + setState(_busy = true)

    // In-flight: spinner up, label gone, button disabled.
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'While registration is in-flight, the button must show a spinner.');
    expect(find.text(registerLabel), findsNothing,
        reason: 'The "Register" label is replaced by the spinner while busy.');
    expect(
      tester.widget<FilledButton>(find.byKey(UiKeys.registerPageRegisterButton)).onPressed,
      isNull,
      reason: 'The register button must be disabled while busy.',
    );

    // Release the gate so the widget can finish + dispose cleanly.
    gate.completeError(Exception('aborted by test'));
    await tester.pumpAndSettle();
  });

  // ---------------------------------------------------------------------------
  // 10. Error banner (HERMETIC) — registerAccount throws -> banner + retry + dismiss.
  // ---------------------------------------------------------------------------
  testWidgets('a failed registration renders the error banner with working Retry + Dismiss',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var registerCalls = 0;

    await tester.pumpWidget(
      _wrap(
        RegisterPage(
          registerAccount: ({
            required nickname,
            required statusMessage,
            required password,
          }) async {
            registerCalls++;
            throw Exception('boom: register failed');
          },
          bootSession: (_) async {},
          teardownSession: ({required FfiChatService service, bool reEncryptProfile = true}) async {},
          showFirstRunBackupWizard: ({required context, required toxId, required nickname}) async {},
          navigateToHome: (context, service) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Valid form: nickname present, password/confirm left empty (the confirm
    // validator only fires when the password is non-empty), so validation
    // passes and the page reaches registerAccount, which throws.
    await tester.enterText(find.byKey(UiKeys.registerPageNicknameField), 'Alice');
    await tester.pump();

    await tester.tap(find.byKey(UiKeys.registerPageRegisterButton));
    await tester.pump(); // validate + setState(_busy)
    await tester.pump(const Duration(milliseconds: 100)); // throw + catch + setState(_error)

    expect(registerCalls, 1,
        reason: 'A valid form must reach registerAccount exactly once.');

    // The error banner renders the thrown message (Exception prefix stripped).
    expect(find.text('boom: register failed'), findsOneWidget,
        reason: 'The error banner must surface the failure message.');
    // ErrorBanner ships a hardcoded "Retry" TextButton + an Icons.close dismiss.
    final retry = find.widgetWithText(TextButton, 'Retry');
    final dismiss = find.widgetWithIcon(IconButton, Icons.close);
    expect(retry, findsOneWidget, reason: 'The error banner must offer Retry.');
    expect(dismiss, findsOneWidget, reason: 'The error banner must offer Dismiss.');

    // Retry -> clears the error and re-invokes registerAccount (which throws
    // again, so the banner returns). Proves Retry re-runs the real _register().
    await tester.tap(retry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(registerCalls, 2,
        reason: 'Tapping Retry must re-invoke registerAccount.');
    expect(find.text('boom: register failed'), findsOneWidget,
        reason: 'A second failure must re-render the banner.');

    // Dismiss -> banner gone, no further registerAccount call.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pump();
    expect(find.text('boom: register failed'), findsNothing,
        reason: 'Tapping Dismiss must remove the error banner.');
    expect(registerCalls, 2,
        reason: 'Dismiss must not trigger another registration.');
  });

  // ---------------------------------------------------------------------------
  // 11. Back button (HERMETIC) — NavigatorObserver records the pop.
  // ---------------------------------------------------------------------------
  testWidgets('tapping the AppBar back button pops the RegisterPage route',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final observer = _RecordingNavigatorObserver();

    // Host the RegisterPage behind a push so there is a route to pop back to.
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RegisterPage(
                      registerAccount: ({
                        required nickname,
                        required statusMessage,
                        required password,
                      }) async {
                        throw Exception('unused');
                      },
                      bootSession: (_) async {},
                      teardownSession: ({required FfiChatService service, bool reEncryptProfile = true}) async {},
                      showFirstRunBackupWizard: ({required context, required toxId, required nickname}) async {},
                      navigateToHome: (context, service) async {},
                    ),
                  ),
                ),
                child: const Text('open register'),
              ),
            ),
          ),
        ),
        observer: observer,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open register'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('register_back_button')), findsOneWidget,
        reason: 'The RegisterPage must be on top with its back button visible.');
    observer.popped = 0; // ignore the push bookkeeping

    await tester.tap(find.byKey(const Key('register_back_button')));
    await tester.pumpAndSettle();

    expect(observer.popped, greaterThanOrEqualTo(1),
        reason: 'The back button must pop the RegisterPage route.');
    expect(find.text('open register'), findsOneWidget,
        reason: 'After popping, the host page is shown again.');
    expect(find.byKey(const Key('register_back_button')), findsNothing,
        reason: 'The RegisterPage is gone after the pop.');
  });

  // ---------------------------------------------------------------------------
  // 8. Happy-path submit (FFI-GATED) — args + boot/wizard/navigate ordering.
  // ---------------------------------------------------------------------------
  testWidgets(
    'valid submit invokes registerAccount with the entered values then boots, '
    'shows the backup wizard, and navigates IN ORDER',
    (tester) async {
      // Defence in depth behind the `skip: !_ffiAvailable()` below. A bare
      // `return` here would report a silent PASS if the two ever disagreed, so
      // report a real SKIP instead.
      if (!_ffiAvailable()) {
        markTestSkipped('libtim2tox_ffi is not loadable in this environment');
        return;
      }
      await _initEmptyPrefs();
      await tester.binding.setSurfaceSize(const Size(1280, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final log = _OrderLog();
      final service = _StubFfiChatService();

      String? capturedNickname;
      String? capturedStatus;
      String? capturedPassword;
      FfiChatService? bootedService;
      FfiChatService? navigatedService;
      String? wizardToxId;

      await tester.pumpWidget(
        _wrap(
          RegisterPage(
            registerAccount: ({
              required nickname,
              required statusMessage,
              required password,
            }) async {
              log.events.add('register');
              capturedNickname = nickname;
              capturedStatus = statusMessage;
              capturedPassword = password;
              return RegisterResult(
                service: service,
                toxId: 'a' * 64,
                profileDirectory: '/tmp/profile',
              );
            },
            bootSession: (s) async {
              log.events.add('boot');
              bootedService = s;
            },
            teardownSession: ({required FfiChatService service, bool reEncryptProfile = true}) async {},
            showFirstRunBackupWizard: ({required context, required toxId, required nickname}) async {
              log.events.add('wizard');
              wizardToxId = toxId;
            },
            navigateToHome: (context, s) async {
              log.events.add('navigate');
              navigatedService = s;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter a full, valid form: nickname, status, matching passwords.
      await tester.enterText(find.byKey(UiKeys.registerPageNicknameField), 'Alice');
      await tester.enterText(find.byKey(const Key('register_status_field')), 'Hello world');
      await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'Secret1!');
      await tester.enterText(find.byKey(UiKeys.registerPageConfirmPasswordField), 'Secret1!');
      await tester.pump();

      await tester.tap(find.byKey(UiKeys.registerPageRegisterButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Args: the production `_register()` trims nickname/status and forwards the
      // raw password to the injected registerAccount.
      expect(capturedNickname, 'Alice',
          reason: 'registerAccount must receive the entered (trimmed) nickname.');
      expect(capturedStatus, 'Hello world',
          reason: 'registerAccount must receive the entered (trimmed) status message.');
      expect(capturedPassword, 'Secret1!',
          reason: 'registerAccount must receive the entered password verbatim.');

      // Ordering: register -> boot -> wizard -> navigate. The existing widget
      // test only checks boot-before-navigate; this asserts the full sequence.
      expect(log.events, equals(['register', 'boot', 'wizard', 'navigate']),
          reason: 'The page must boot the returned session, show the first-run '
              'backup wizard, then navigate — in that order.');

      // The same returned service threads through boot and navigation.
      expect(identical(bootedService, service), isTrue,
          reason: 'bootSession must receive the RegisterResult.service.');
      expect(identical(navigatedService, service), isTrue,
          reason: 'navigateToHome must receive the same RegisterResult.service.');
      expect(wizardToxId, 'a' * 64,
          reason: 'The backup wizard must receive the registered toxId.');
    },
    skip: !_ffiAvailable(),
  );
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int popped = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped++;
    super.didPop(route, previousRoute);
  }
}
