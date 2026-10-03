import 'logger.dart';
import 'prefs.dart';

/// The node a running LAN bootstrap service publishes
/// (`LanBootstrapServiceManager.getBootstrapServiceInfo`).
typedef LanBootstrapNode = ({String ip, int port, String pubkey});

/// Leaving LAN mode with no pre-LAN snapshot to restore: clear
/// `current_bootstrap_*` ONLY when it is the node the LAN service published,
/// i.e. when LAN mode itself installed it.
///
/// "No snapshot" alone used to be taken as that proof, and it is not one:
/// the snapshot only exists while a started service is running, so switching
/// manual -> LAN -> manual without pressing Start, or starting, stopping and
/// THEN leaving LAN mode, reached the same branch and deleted the user's own
/// manual/auto node. [lanNode] must be read BEFORE the service is stopped
/// (stop forgets it); null means no service ran in this process, so nothing
/// of LAN's is current and nothing is cleared.
Future<void> clearCurrentNodeIfLanOwned(LanBootstrapNode? lanNode) async {
  if (lanNode == null) return;
  final current = await Prefs.getCurrentBootstrapNode();
  if (current == null) return;
  if (current.host == lanNode.ip &&
      current.port == lanNode.port &&
      current.pubkey.toUpperCase() == lanNode.pubkey.toUpperCase()) {
    await Prefs.clearCurrentBootstrapNode();
  }
}

/// Crash-recovery for the LAN bootstrap service; see
/// `LanBootstrapServiceManager.recoverFromCrashedSession`.
///
/// Ordering is the point: the running flag is cleared BEFORE the snapshot is
/// consumed. The old order (restore, drop snapshot, clear flag) left a window
/// where a crash after the snapshot was gone but before the flag was cleared
/// sent the NEXT start down the "running, no snapshot" branch, which deletes
/// the current node — the very node this recovery had just restored. With the
/// flag cleared first, a crash leaves at worst a stale snapshot behind, which
/// the not-running branch below sweeps (a snapshot only means something while
/// a service is running; the current node already holds what it saved).
///
/// Runs on the cold-start path before `runApp`, so no write failure may escape:
/// a preferences store that refuses a write (the isolated desktop store can
/// fail a rename) is logged and left for the next start to retry.
/// [clearSnapshot] is a seam for that failure in tests.
Future<void> recoverLanBootstrapCrash({
  required bool serviceAlive,
  required Future<void> Function(String host, int port, String pubkey)
  setCurrentNode,
  Future<void> Function() clearSnapshot = Prefs.clearPreLanBootstrapNode,
}) async {
  if (serviceAlive) return;
  final priorNode = await Prefs.getPreLanBootstrapNode();
  if (!await Prefs.getLanBootstrapServiceRunning()) {
    if (priorNode != null) await _dropSnapshot(clearSnapshot);
    return;
  }
  AppLogger.warn(
    '[LanBootstrapService] Detected stale LAN-running flag with no live instance — recovering',
  );
  try {
    if (priorNode != null) {
      await setCurrentNode(priorNode.host, priorNode.port, priorNode.pubkey);
    } else {
      // No snapshot while the flag says running: there was no node before LAN
      // mode, so current_bootstrap_* can only be the dead LAN node the crashed
      // run set. Clear it so this session does not apply a dead node.
      await Prefs.clearCurrentBootstrapNode();
    }
  } catch (e, st) {
    // Snapshot and flag are left as they were, so the next start retries.
    AppLogger.logError(
      '[LanBootstrapService] recovery: failed to restore the bootstrap node',
      e,
      st,
    );
    return;
  }
  try {
    await Prefs.setLanBootstrapServiceRunning(false);
  } catch (e, st) {
    // Keep the snapshot: "running with no snapshot" is the state that makes
    // the next start delete the current node.
    AppLogger.logError(
      '[LanBootstrapService] recovery: failed to clear the running flag',
      e,
      st,
    );
    return;
  }
  if (priorNode != null) await _dropSnapshot(clearSnapshot);
}

/// A leftover snapshot is harmless while the flag is clear (see above), so a
/// failure to drop it is logged, never thrown.
Future<void> _dropSnapshot(Future<void> Function() clearSnapshot) async {
  try {
    await clearSnapshot();
  } catch (e, st) {
    AppLogger.logError(
      '[LanBootstrapService] recovery: failed to drop the pre-LAN snapshot',
      e,
      st,
    );
  }
}
