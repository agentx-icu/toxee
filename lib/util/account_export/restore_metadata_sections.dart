import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prefs.dart';
import '../safe_diagnostics.dart';
import 'backup_path_safety.dart';
import 'restore_transaction_journal.dart';

// Backup-metadata sections: the per-account state a full backup carries OUTSIDE
// the scoped-prefs blob, plus the portability rewriting of avatar paths.
//
// Split out of `restore_transaction.dart` (complexity-gate pin). Grouped
// together because they share one reason to exist: `exportScopedPrefsForAccount`
// only sweeps keys ending in `_<first16>`, so anything keyed by the FULL Tox ID
// is invisible to it and has to be carried — and restored — by hand.

Map<String, dynamic> portableScopedPrefs(
  Map<String, dynamic> metadata,
  String accountDataFinalDir,
) {
  final raw = metadata['scopedPrefs'];
  if (raw is! Map) return <String, dynamic>{};
  final scopedPrefs = Map<String, dynamic>.from(raw);
  for (final key in scopedPrefs.keys.toList()) {
    final value = scopedPrefs[key];
    if (key.contains('avatar_path') && value is String) {
      if (value.startsWith('@account_data/')) {
        final relativePath = value.substring('@account_data/'.length);
        try {
          scopedPrefs[key] = safeBackupRestorePath(
            baseDir: accountDataFinalDir,
            relativePath: relativePath,
          );
        } catch (_) {
          scopedPrefs.remove(key);
        }
      } else {
        scopedPrefs.remove(key);
      }
    }
  }
  return scopedPrefs;
}

/// Restore the blocked-peer list from the backup metadata.
///
/// Best-effort: a malformed `blockedPeers` section must not abort an otherwise
/// good restore, and an absent one is the normal case for older backups (and
/// for an account that blocked nobody).
Future<void> restoreBlockedPeers(
  String toxId,
  Map<String, dynamic> metadata,
) async {
  final raw = metadata['blockedPeers'];
  if (raw is! List || raw.isEmpty) return;
  final peers = raw.whereType<String>().where((e) => e.isNotEmpty).toSet();
  if (peers.isEmpty) return;
  await Prefs.setBlackList(peers, toxId);
}

/// Restore the pending failed-message queue from the backup metadata.
///
/// Best effort, and absent from older backups (and from accounts with nothing
/// pending), so a missing section is the normal case.
Future<void> restoreFailedMessageQueue(
  String toxId,
  Map<String, dynamic> metadata,
) async {
  final raw = metadata['failedMessageQueue'];
  if (raw is! String || raw.isEmpty) return;
  await Prefs.importFailedMessageQueue(toxId, raw);
}

/// Snapshot the FULL-id-keyed preference families into [journal].
///
/// Each family is captured on its own: a read that fails leaves THAT family
/// uncaptured, and rollback then leaves it exactly as it finds it. Capturing
/// them together meant an unreadable block list also discarded a perfectly good
/// queue snapshot - and the restore overwrites the queue regardless, so that
/// queue was then gone for good.
Future<RestoreTransactionJournal> captureFullIdPrefs(
  RestoreTransactionJournal journal,
) async {
  var captured = journal;
  try {
    captured = captured.copyWith(
      priorBlackListCaptured: true,
      priorBlackList: (await Prefs.getBlackList(journal.toxId)).toList(
        growable: false,
      ),
    );
  } catch (e) {
    SafeDiagnostics.logFailure(
      '[RestoreTransaction] could not snapshot the blocked-peer list; rollback '
      'will leave it exactly as it finds it',
      e,
    );
  }
  try {
    captured = captured.copyWith(
      priorFailedQueueCaptured: true,
      priorFailedQueue: await Prefs.exportFailedMessageQueue(journal.toxId),
    );
  } catch (e) {
    SafeDiagnostics.logFailure(
      '[RestoreTransaction] could not snapshot the failed-message queue; '
      'rollback will leave it exactly as it finds it',
      e,
    );
  }
  return captured;
}

/// Put the captured families back, and report whether they actually landed.
///
/// The writes are VERIFIED against a reloaded store rather than trusted.
/// `SharedPreferences` updates its own cache before the platform write
/// completes, and neither `setBlackList` nor `importFailedMessageQueue` reports
/// a refusal, so an unverified rollback would clear the journal - destroying the
/// only copy of the originals it had just failed to restore.
///
/// An uncaptured family is skipped, not cleared: see the journal's field docs.
Future<bool> restorePriorFullIdPrefs(RestoreTransactionJournal journal) async {
  if (journal.priorBlackListCaptured) {
    await Prefs.setBlackList(journal.priorBlackList.toSet(), journal.toxId);
  }
  var queueCleared = true;
  final priorQueue = journal.priorFailedQueue;
  if (journal.priorFailedQueueCaptured) {
    // CLEAR BOTH KEY SHAPES FIRST. The queue lives under a modern full-id key
    // and a legacy 16-char one; `importFailedMessageQueue` writes only the
    // modern shape while `clearFailedMessageQueue` removes both. Writing the
    // prior value straight over the modern key therefore left an archive-created
    // LEGACY queue in place - invisible to the read-back below, which checks the
    // modern key first and is satisfied - and the runtime later merged it, so
    // the rolled-back archive's messages came back alongside the originals.
    // The RESULT matters. `clearFailedMessageQueue` reports whether every
    // removal took, and it is the only signal that covers the LEGACY key shape:
    // the read-back below goes through `exportFailedMessageQueue`, which returns
    // the modern value without ever inspecting the legacy one. A legacy removal
    // that silently failed therefore read back as success, the journal was
    // cleared, and the runtime later merged the archive's messages back in.
    queueCleared = await Prefs.clearFailedMessageQueue(journal.toxId);
    if (priorQueue != null && priorQueue.isNotEmpty) {
      await Prefs.importFailedMessageQueue(journal.toxId, priorQueue);
    }
  }

  await (await SharedPreferences.getInstance()).reload();
  var ok = queueCleared;
  if (journal.priorBlackListCaptured) {
    final now = await Prefs.getBlackList(journal.toxId);
    if (!const SetEquality<String>().equals(
      now,
      journal.priorBlackList.toSet(),
    )) {
      ok = false;
    }
  }
  if (journal.priorFailedQueueCaptured) {
    final now = await Prefs.exportFailedMessageQueue(journal.toxId);
    if ((now ?? '') != (priorQueue ?? '')) ok = false;
  }
  if (!ok) {
    SafeDiagnostics.logFailure(
      '[RestoreTransaction] the pre-transaction preferences did not read back '
      'after rollback; keeping the journal so the next start retries',
      StateError('prior full-id prefs not restored'),
    );
  }
  return ok;
}
