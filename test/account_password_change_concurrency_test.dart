// Two password changes issued at once must not separate the file's key from
// the verifier: AccountPasswordChange serialises them, so the second sees the
// first's completed state and the final verifier matches the last re-key.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/account_password_change.dart';
import 'package:toxee/util/account_service_test_hooks.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';

import 'ui/settings/settings_account_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};
  final rekeys = <String?>[];

  setUp(() async {
    secureStore.clear();
    rekeys.clear();
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    AccountPasswordChangeTestHooks.rekeyLive = (_, password) {
      rekeys.add(password);
      return true;
    };
  });

  tearDown(() {
    AccountPasswordChangeTestHooks.reset();
    SessionPasswordStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('interleaved set() calls run one after the other', () async {
    final service = SettingsHarnessService();
    addTearDown(service.disposeStub);
    final results = await Future.wait([
      AccountPasswordChange.set(service, 'first'),
      AccountPasswordChange.set(service, 'second'),
      AccountPasswordChange.remove(service),
      AccountPasswordChange.set(service, 'third'),
    ]);
    expect(results, everyElement(PasswordChangeOutcome.ok));
    expect(rekeys, ['first', 'second', null, 'third'],
        reason: 'each change re-keyed the file in program order');
    expect(await Prefs.verifyAccountPassword(kSettingsToxId, 'third'), isTrue);
    expect(await Prefs.verifyAccountPassword(kSettingsToxId, 'second'), isFalse);
    expect((await Prefs.passwordChanges.pending(kSettingsToxId)).record, isNull,
        reason: 'no recovery record survives a completed sequence');
    expect(SessionPasswordStore.get(kSettingsToxId), 'third');
  });
}
