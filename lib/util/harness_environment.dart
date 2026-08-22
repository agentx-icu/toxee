import 'dart:io';

import 'package:flutter/foundation.dart';

/// Test-harness overrides for process-scoped paths and prompts.
///
/// Two sources, deliberately asymmetric:
///
/// * **`String.fromEnvironment` (compile time)** — honored in every build mode.
///   This is how the iOS/Android launchers pass overrides, since a sandboxed app
///   on a device cannot be handed a process environment
///   (`launch_toxee_ios_instance.sh` passes them as `--dart-define`).
/// * **`Platform.environment` (run time)** — **debug builds only**. The desktop
///   launchers (`run_toxee.sh`, `launch_*_fixture_c_pair.sh`, …) all build
///   `--debug`, so they keep working.
///
/// The run-time branch is gated because these keys redirect security-relevant
/// state: `TOXEE_APP_SUPPORT_DIR` moves the whole application-support tree —
/// including `profiles/`, which holds the Tox **private key** — and
/// `AppPaths.applicationSupport` will `create(recursive: true)` whatever path it
/// is given; `TOXEE_SHARED_PREFS_PREFIX` re-namespaces SharedPreferences
/// wholesale, which is enough to inject a prepared account/session. In a release
/// build that turned "can edit the launcher/shortcut" into "can silently
/// exfiltrate keys and history", on all three desktop platforms.
abstract final class HarnessEnvironment {
  static const appSupportDirKey = 'TOXEE_APP_SUPPORT_DIR';
  static const logDirKey = 'TOXEE_LOG_DIR';
  static const sharedPrefsPrefixKey = 'TOXEE_SHARED_PREFS_PREFIX';
  static const tccfGlobalSubdirKey = 'TOXEE_TCCF_GLOBAL_SUBDIR';
  static const disableNotificationPermissionKey =
      'TOXEE_DISABLE_NOTIFICATION_PERMISSION_PROMPT';

  /// Suppresses the first-launch call-permission prewarm
  /// (`HomePage._maybePrewarmCallPermissions`). Same rationale as the
  /// notification key: an OS permission sheet is an OS surface, so it parks
  /// above the app where synthetic input cannot reach it and it lands in any
  /// device-framebuffer capture. Never set in a product build.
  static const disableCallPermissionPrewarmKey =
      'TOXEE_DISABLE_CALL_PERMISSION_PREWARM';

  static const _appSupportDirDefine = String.fromEnvironment(appSupportDirKey);
  static const _logDirDefine = String.fromEnvironment(logDirKey);
  static const _sharedPrefsPrefixDefine = String.fromEnvironment(
    sharedPrefsPrefixKey,
  );
  static const _tccfGlobalSubdirDefine = String.fromEnvironment(
    tccfGlobalSubdirKey,
  );
  static const _disableNotificationPermissionDefine = String.fromEnvironment(
    disableNotificationPermissionKey,
  );
  static const _disableCallPermissionPrewarmDefine = String.fromEnvironment(
    disableCallPermissionPrewarmKey,
  );

  static String? value(String key) {
    // Debug-only: see the class doc for why the run-time branch is gated.
    // `kDebugMode` is a compile-time const, so in release the whole block is
    // dropped and `Platform.environment` is never consulted.
    if (kDebugMode) {
      final env = Platform.environment[key]?.trim();
      if (env != null && env.isNotEmpty) return env;
    }
    final define = switch (key) {
      appSupportDirKey => _appSupportDirDefine,
      logDirKey => _logDirDefine,
      sharedPrefsPrefixKey => _sharedPrefsPrefixDefine,
      tccfGlobalSubdirKey => _tccfGlobalSubdirDefine,
      disableNotificationPermissionKey => _disableNotificationPermissionDefine,
      disableCallPermissionPrewarmKey => _disableCallPermissionPrewarmDefine,
      _ => '',
    }.trim();
    return define.isEmpty ? null : define;
  }

  static bool boolValue(String key) {
    final raw = value(key)?.toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes';
  }
}
