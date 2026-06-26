import 'package:shared_preferences/shared_preferences.dart';

import 'app_bootstrap_result.dart';
import '../util/logger.dart';
import '../util/harness_environment.dart';
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
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    // The LAN bootstrap service is purely in-process state; if we crashed
    // mid-session, the persisted "running" flag would lie to the UI and the
    // current_bootstrap_* keys would still point at a dead LAN address.
    // Reset both so first init() lands the user on a reachable public node.
    final wasRunning = await Prefs.getLanBootstrapServiceRunning();
    await Prefs.setLanBootstrapServiceRunning(false);
    if (wasRunning) {
      final priorNode = await Prefs.getPreLanBootstrapNode();
      if (priorNode != null) {
        await Prefs.setCurrentBootstrapNode(
          priorNode.host,
          priorNode.port,
          priorNode.pubkey,
        );
        await Prefs.clearPreLanBootstrapNode();
        AppLogger.log(
          '[PrefsBootstrap] LAN service was running at last shutdown — restored '
          'pre-LAN bootstrap node ${priorNode.host}:${priorNode.port}',
        );
      }
    }
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
