import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'app_bootstrap_result.dart';
import 'isolated_prefs_store.dart';
import '../util/harness_environment.dart';
import '../util/lan_bootstrap_service.dart';
import '../util/logger.dart';
import '../util/platform_utils.dart';
import '../util/prefs.dart';
import '../util/prefs_upgrader.dart';

/// Prefs initialization and schema migration. Returns [AppBootstrapUpgradeRequired]
/// when stored prefs are from a newer app version.
class PrefsBootstrap {
  PrefsBootstrap._();

  /// Returns null on success; [AppBootstrapUpgradeRequired] when upgrade required.
  static Future<AppBootstrapUpgradeRequired?> initialize() async {
    final prefix = HarnessEnvironment.value(
      HarnessEnvironment.sharedPrefsPrefixKey,
    );
    if (prefix != null && prefix.isNotEmpty) {
      SharedPreferences.setPrefix(prefix);
    }
    installIsolatedStoreIfOverridden();
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    // The LAN bootstrap service is purely in-process state; if we crashed
    // mid-session, the persisted "running" flag would lie to the UI and the
    // current_bootstrap_* keys would still point at a dead LAN address. This is
    // the earliest startup point (before any FfiChatService.init reads the
    // node), and it is the single owner of that recovery — the manager hook
    // holds the one implementation (with retry-preserving failure semantics),
    // so app_bootstrap no longer calls it a second time (LAN review
    // 2026-09-15, F7).
    await LanBootstrapServiceManager.instance.recoverFromCrashedSession();
    // Mobile can't run the desktop-only LAN bootstrap daemon. Normalize a
    // persisted 'lan' mode to 'auto' here — at the earliest startup point,
    // before any FfiChatService.init() reads the mode in
    // _loadAndApplySavedBootstrapNode. Doing it globally (not just in the
    // startup gate) covers manual login, registration, and account switch too,
    // so mobile never tries to bootstrap from a stale LAN node on first connect.
    if (!PlatformUtils.isDesktop) {
      final mode = await Prefs.getBootstrapNodeMode();
      if (mode == 'lan') {
        await Prefs.setBootstrapNodeMode('auto');
        AppLogger.log(
          '[PrefsBootstrap] Downgraded persisted LAN bootstrap mode to auto on mobile',
        );
      }
    }
    try {
      await PrefsUpgrader.run(prefs);
    } on PrefsStorageNewerThanAppException catch (e) {
      AppLogger.log(
        'Prefs stored by newer app (${e.storedVersion} > ${e.currentVersion}), showing upgrade required',
      );
      return AppBootstrapUpgradeRequired(
        storedVersion: e.storedVersion,
        currentVersion: e.currentVersion,
      );
    }
    return null;
  }
}

/// Keep the prefs file under `TOXEE_APP_SUPPORT_DIR` on Windows/Linux when that
/// override is set (multi-instance harness), see [IsolatedPrefsStore]. macOS
/// keeps the platform plugin: NSUserDefaults merges per key, and the key prefix
/// already isolates the instances there.
void installIsolatedStoreIfOverridden() {
  if (!(Platform.isWindows || Platform.isLinux)) return;
  final dir = HarnessEnvironment.value(HarnessEnvironment.appSupportDirKey);
  if (dir == null || dir.isEmpty) return;
  SharedPreferencesStorePlatform.instance = IsolatedPrefsStore(
    File('$dir${Platform.pathSeparator}shared_preferences.json'),
  );
  AppLogger.log('[PrefsBootstrap] prefs store isolated under $dir');
}
