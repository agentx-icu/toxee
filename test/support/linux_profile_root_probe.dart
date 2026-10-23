// Invoked only by tool/ci/test_linux_profile_paths.py in a real Linux process.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real Linux environment preserves profile roots and account bytes',
    () async {
      expect(Platform.isLinux, isTrue);
      SharedPreferences.setMockInitialValues({});
      final fixture = Platform.environment['TOXEE_PATH_PROBE_ROOT']!;
      final expected = Platform.environment['TOXEE_PATH_PROBE_EXPECTED']!;
      final fallback = p.join(fixture, 'platform-support');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => fallback,
      );
      final previous = Directory.current;
      Directory.current = p.join(fixture, 'cwd');
      try {
        expect(await AppPaths.getProfileStorageRoot(), expected);
        expect(await AppPaths.getProfileStorageRoot(), expected);
        expect(
          await File(p.join(expected, 'account.tox')).readAsString(),
          'existing-private-account-fixture',
        );
        expect(
          Directory(p.join('relative-data', 'toxee')).existsSync(),
          isFalse,
        );
        final retainedLegacy =
            Platform.environment['TOXEE_PATH_PROBE_RETAINED_LEGACY'];
        if (retainedLegacy != null) {
          expect(
            await File(p.join(retainedLegacy, 'account.tox')).readAsString(),
            'legacy-account-fixture',
          );
        }
        final custom = p.join(fixture, 'user-selected-profiles');
        await Prefs.setProfileStorageRoot(custom);
        expect(await AppPaths.getProfileStorageRoot(), custom);
      } finally {
        Directory.current = previous;
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
      }
    },
  );
}
