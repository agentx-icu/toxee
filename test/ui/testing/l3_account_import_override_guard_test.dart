// Guard rule of `l3_set_account_import_pick_path`: allowed for a test/seed
// account OR when no account is active at all (fresh install / signed-out
// login page — nothing to protect), refused while a live non-test account is
// active, while its teardown is still running, or while a non-test
// current-account pointer is set with no session yet.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';
import 'package:toxee/util/active_session.dart';
import 'package:toxee/util/prefs.dart';

import '../settings/settings_account_test_support.dart';

const _realToxId =
    '1111111111111111111111111111111111111111111111111111111111111111'
    '22222222BBBB';
const _seedToxId =
    '3333333333333333333333333333333333333333333333333333333333333333'
    '44444444CCCC';

Future<Map<String, dynamic>> _setPath(String path) =>
    debugL3SetAccountImportPickPathForTests({'path': path});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    ActiveSession.reset();
    debugSetL3TestSurfaceEnabledForTests(true);
    debugResetL3FilePickerOverridesForTests();
  });

  tearDown(() {
    ActiveSession.reset();
    debugResetL3FilePickerOverridesForTests();
    debugSetL3TestSurfaceEnabledForTests(null);
  });

  test('fresh install (no session, no pointer): allowed', () async {
    final result = await _setPath('/tmp/fresh.tox');
    expect(result['ok'], isTrue, reason: '$result');
    expect(debugCurrentAccountImportPickOverridePath, '/tmp/fresh.tox');
  });

  test('signed-out login page (pointer cleared by sign-out): allowed',
      () async {
    await Prefs.addAccount(toxId: _realToxId, nickname: 'Real');
    await Prefs.setCurrentAccountToxId(null);
    final result = await _setPath('/tmp/after-logout.tox');
    expect(result['ok'], isTrue, reason: '$result');
  });

  test('test/seed account active: allowed', () async {
    await Prefs.addL3SeedToxId(_seedToxId);
    await Prefs.setCurrentAccountToxId(_seedToxId);
    final service = SettingsHarnessService();
    addTearDown(service.disposeStub);
    ActiveSession.set(service);
    final result = await _setPath('/tmp/seed.tox');
    expect(result['ok'], isTrue, reason: '$result');
  });

  test('live non-test account: refused', () async {
    await Prefs.setCurrentAccountToxId(_realToxId);
    final service = SettingsHarnessService();
    addTearDown(service.disposeStub);
    ActiveSession.set(service);
    final result = await _setPath('/tmp/real.tox');
    expect(result['ok'], isFalse);
    expect(result['error'], 'non_test_account');
    expect(debugCurrentAccountImportPickOverridePath, isNull);
  });

  test('non-test pointer set but no session yet (booting): refused',
      () async {
    await Prefs.setCurrentAccountToxId(_realToxId);
    final result = await _setPath('/tmp/booting.tox');
    expect(result['ok'], isFalse);
    expect(result['error'], 'non_test_account');
  });

  test('teardown still in flight: refused', () async {
    await Prefs.setCurrentAccountToxId(null);
    final release = Completer<void>();
    final teardown = ActiveSession.trackTeardown(release.future);
    final result = await _setPath('/tmp/teardown.tox');
    expect(result['ok'], isFalse);
    expect(result['error'], 'non_test_account');
    release.complete();
    await teardown;
    expect((await _setPath('/tmp/after-teardown.tox'))['ok'], isTrue);
  });
}
