// Bootstrap cold-start gates for PrefsBootstrap.
//
// Existing LAN tests cover LanBootstrapServiceManager.recoverFromCrashedSession.
// These tests cover the earlier cold-start PrefsBootstrap.initialize() path
// that runs before any session/service is created.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/bootstrap/app_bootstrap_result.dart';
import 'package:toxee/bootstrap/prefs_bootstrap.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/prefs_upgrader.dart';

Future<void> _freshPrefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'PrefsBootstrap clears stale LAN-running flag and restores pre-LAN node',
    () async {
      await _freshPrefs();
      await Prefs.setLanBootstrapServiceRunning(true);
      await Prefs.setPreLanBootstrapNode('203.0.113.7', 33445, 'PRELANKEY');
      await Prefs.setCurrentBootstrapNode('192.168.1.50', 40000, 'DEADLANKEY');

      final result = await PrefsBootstrap.initialize();

      expect(result, isNull);
      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
      expect(await Prefs.getPreLanBootstrapNode(), isNull);
      final current = await Prefs.getCurrentBootstrapNode();
      expect(current?.host, '203.0.113.7');
      expect(current?.port, 33445);
      expect(current?.pubkey, 'PRELANKEY');
    },
  );

  test(
    'PrefsBootstrap returns upgrade-required result for newer prefs schema',
    () async {
      await _freshPrefs({
        'prefs_schema_version': currentGlobalPrefsVersion + 1,
      });

      final result = await PrefsBootstrap.initialize();

      expect(result, isA<AppBootstrapUpgradeRequired>());
      final upgrade = result!;
      expect(upgrade.storedVersion, currentGlobalPrefsVersion + 1);
      expect(upgrade.currentVersion, currentGlobalPrefsVersion);
    },
  );
}
