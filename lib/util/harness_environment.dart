import 'dart:io';

abstract final class HarnessEnvironment {
  static const appSupportDirKey = 'TOXEE_APP_SUPPORT_DIR';
  static const logDirKey = 'TOXEE_LOG_DIR';
  static const sharedPrefsPrefixKey = 'TOXEE_SHARED_PREFS_PREFIX';
  static const tccfGlobalSubdirKey = 'TOXEE_TCCF_GLOBAL_SUBDIR';
  static const disableNotificationPermissionKey =
      'TOXEE_DISABLE_NOTIFICATION_PERMISSION_PROMPT';

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

  static String? value(String key) {
    final env = Platform.environment[key]?.trim();
    if (env != null && env.isNotEmpty) return env;
    final define = switch (key) {
      appSupportDirKey => _appSupportDirDefine,
      logDirKey => _logDirDefine,
      sharedPrefsPrefixKey => _sharedPrefsPrefixDefine,
      tccfGlobalSubdirKey => _tccfGlobalSubdirDefine,
      disableNotificationPermissionKey => _disableNotificationPermissionDefine,
      _ => '',
    }.trim();
    return define.isEmpty ? null : define;
  }

  static bool boolValue(String key) {
    final raw = value(key)?.toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes';
  }
}
