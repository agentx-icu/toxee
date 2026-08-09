import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/register_page.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/prefs.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('register flow boots the returned session before navigation',
      (tester) async {
    // Defence in depth behind the `skip: !_ffiAvailable()` below. A bare
    // `return` here would report a silent PASS if the two ever disagreed, so
    // report a real SKIP instead.
    if (!_ffiAvailable()) {
      markTestSkipped('libtim2tox_ffi is not loadable in this environment');
      return;
    }
    await _initEmptyPrefs();
    final service = _StubFfiChatService();
    var bootCalls = 0;

    await tester.pumpWidget(
      _wrap(
        RegisterPage(
          registerAccount: ({
            required nickname,
            required statusMessage,
            required password,
          }) async {
            return RegisterResult(
              service: service,
              toxId: 'a' * 64,
              profileDirectory: '/tmp/profile',
            );
          },
          bootSession: (_) async {
            bootCalls++;
          },
          showFirstRunBackupWizard: ({
            required context,
            required toxId,
            required nickname,
          }) async {},
          navigateToHome: (context, service) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Alice');
    await tester.enterText(find.byType(TextFormField).at(1), 'Hello');
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(bootCalls, 1,
        reason:
            'RegisterPage must route a brand-new session through the same boot path as login.');
  }, skip: !_ffiAvailable());
}
