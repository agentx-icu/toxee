// Registering an account must leave Home as the ONLY route.
//
// Found on an API 36 foldable emulator: after "Register new account" -> first-
// run backup wizard, the Chats header showed a back arrow that returned to the
// login page with the new session still running. RegisterPage is pushed over
// the login page (StartupGate's child) and handed over to Home with
// pushReplacement, which kept the login route underneath.
//
// Drives the REAL RegisterPage submit with its PRODUCTION default
// `navigateToHome` (only the Home page itself is swapped for a stand-in, since
// the real one needs a live session), from a route pushed over a root —
// exactly login -> register.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/register_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/prefs.dart';

/// Never touched beyond being passed around: `implements` (not `extends`)
/// avoids FfiChatService's constructor, which opens the native library.
class _FakeService implements FfiChatService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async => null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null);
  });

  testWidgets('after registering, Home is the only route (login removed)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeService();
    FfiChatService? homeFor;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (loginContext) => Scaffold(
            body: Column(
              children: [
                const Text('login root'),
                ElevatedButton(
                  onPressed: () => Navigator.of(loginContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RegisterPage(
                        registerAccount:
                            ({
                              required nickname,
                              required statusMessage,
                              required password,
                            }) async => RegisterResult(
                              service: service,
                              toxId: 'A' * 76,
                              profileDirectory: '/tmp/unused',
                            ),
                        bootSession: (_) async {},
                        teardownSession:
                            ({
                              required FfiChatService service,
                              bool reEncryptProfile = true,
                            }) async {},
                        showFirstRunBackupWizard:
                            ({
                              required context,
                              required toxId,
                              required nickname,
                            }) async {},
                        // navigateToHome: NOT injected — the production default.
                        homePageBuilder: (s) {
                          homeFor = s;
                          return const Scaffold(body: Text('home'));
                        },
                      ),
                    ),
                  ),
                  child: const Text('open register'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open register'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(UiKeys.registerPageNicknameField),
      'Alice',
    );
    await tester.pump();
    await tester.tap(
      find.text(lookupAppLocalizations(const Locale('en')).register),
    );
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(identical(homeFor, service), isTrue);
    expect(find.text('login root', skipOffstage: false), findsNothing);
    expect(find.byType(RegisterPage, skipOffstage: false), findsNothing);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse, reason: 'no back arrow, no back');
  });
}
