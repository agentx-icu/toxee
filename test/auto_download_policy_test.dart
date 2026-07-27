import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/adapters/shared_prefs_adapter.dart';
import 'package:toxee/util/auto_download_policy.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('auto-download default policy', () {
    test('Android defaults to 5 MB', () {
      expect(defaultAutoDownloadSizeLimitMb(isMobile: true), 5);
    });

    test('iOS defaults to 5 MB', () {
      expect(defaultAutoDownloadSizeLimitMb(isMobile: true), 5);
    });

    test('desktop defaults to 30 MB', () {
      expect(defaultAutoDownloadSizeLimitMb(isMobile: false), 30);
    });
  });

  test(
    'Prefs and adapter use the desktop default when the key is absent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await Prefs.initialize(preferences);
      final adapter = SharedPreferencesAdapter(preferences, instanceId: 0);

      expect(await Prefs.getAutoDownloadSizeLimit(), 30);
      expect(await adapter.getAutoDownloadSizeLimit(), 30);
    },
  );

  for (final platformName in const ['Android', 'iOS']) {
    test(
      'Prefs and adapter use the 5 MB $platformName default when absent',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        await Prefs.initialize(preferences);
        final adapter = SharedPreferencesAdapter(
          preferences,
          instanceId: 0,
          isMobileOverride: true,
        );

        expect(await Prefs.getAutoDownloadSizeLimit(isMobileOverride: true), 5);
        expect(await adapter.getAutoDownloadSizeLimit(), 5);
      },
    );
  }

  for (final storedLimitMb in const [-7, 0, 137]) {
    test(
      'Prefs and adapter preserve stored $storedLimitMb unchanged',
      () async {
        SharedPreferences.setMockInitialValues({
          'auto_download_size_limit': storedLimitMb,
        });
        final preferences = await SharedPreferences.getInstance();
        await Prefs.initialize(preferences);
        final adapter = SharedPreferencesAdapter(
          preferences,
          instanceId: 0,
          isMobileOverride: true,
        );

        expect(
          await Prefs.getAutoDownloadSizeLimit(isMobileOverride: true),
          storedLimitMb,
        );
        expect(await adapter.getAutoDownloadSizeLimit(), storedLimitMb);
      },
    );
  }
}
