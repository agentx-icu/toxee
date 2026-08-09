// Unit gates for HarnessEnvironment, which had ZERO test coverage while being
// the seam that redirects the application-support tree (including `profiles/`,
// where the Tox private key lives), the SharedPreferences namespace, the log
// directory, and the notification-permission prompt.
//
// Scope note (honest): the release-mode gate added to `value()` — run-time
// `Platform.environment` is consulted only under `kDebugMode` — cannot be
// exercised in-process. `flutter test` always runs in debug, and
// `Platform.environment` is read-only from Dart, so neither branch can be
// flipped from here. What IS gated below is everything that a rename or a
// parsing change would silently break.

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/harness_environment.dart';

void main() {
  group('HarnessEnvironment key constants (launcher contract)', () {
    // These exact strings are hardcoded in the shell/PowerShell launchers
    // (tool/mcp_test/launch_*_fixture_c_pair.sh, launch_toxee_instance.sh,
    // launch_toxee_ios_instance.sh, run_toxee*.sh) and in the iOS/Android
    // --dart-define invocations. Renaming the Dart constant without updating
    // every launcher fails silently: the override is simply ignored and two
    // instances quietly share one profile store.
    test('are the exact strings the launchers pass', () {
      expect(HarnessEnvironment.appSupportDirKey, 'TOXEE_APP_SUPPORT_DIR');
      expect(HarnessEnvironment.logDirKey, 'TOXEE_LOG_DIR');
      expect(
        HarnessEnvironment.sharedPrefsPrefixKey,
        'TOXEE_SHARED_PREFS_PREFIX',
      );
      expect(
        HarnessEnvironment.tccfGlobalSubdirKey,
        'TOXEE_TCCF_GLOBAL_SUBDIR',
      );
      expect(
        HarnessEnvironment.disableNotificationPermissionKey,
        'TOXEE_DISABLE_NOTIFICATION_PERMISSION_PROMPT',
      );
    });
  });

  group('HarnessEnvironment.value', () {
    test('returns null for a key that is neither a known define nor set', () {
      expect(HarnessEnvironment.value('TOXEE_NOT_A_REAL_KEY_12345'), isNull);
    });

    test('returns null for known keys when no override is supplied', () {
      // No --dart-define is passed to `flutter test`, and the test runner does
      // not export these, so every known key must resolve to null rather than
      // to an empty string. Callers branch on `!= null && isNotEmpty`; a bare
      // '' leaking through here would make AppPaths treat "" as an override.
      for (final key in const [
        HarnessEnvironment.appSupportDirKey,
        HarnessEnvironment.logDirKey,
        HarnessEnvironment.sharedPrefsPrefixKey,
        HarnessEnvironment.tccfGlobalSubdirKey,
        HarnessEnvironment.disableNotificationPermissionKey,
      ]) {
        expect(
          HarnessEnvironment.value(key),
          isNull,
          reason: '$key must be null, not "", when unset',
        );
      }
    });
  });

  group('HarnessEnvironment.boolValue', () {
    test('is false for unset keys', () {
      expect(HarnessEnvironment.boolValue('TOXEE_NOT_A_REAL_KEY_12345'), isFalse);
      expect(
        HarnessEnvironment.boolValue(
          HarnessEnvironment.disableNotificationPermissionKey,
        ),
        isFalse,
      );
    });

    test('never throws on an arbitrary key', () {
      expect(() => HarnessEnvironment.boolValue(''), returnsNormally);
    });
  });
}
