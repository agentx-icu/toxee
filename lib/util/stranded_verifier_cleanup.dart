import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'async_gate.dart';
import 'logger.dart';
import 'prefs.dart';

/// Durable retry for a password verifier a failed registration could not
/// remove.
///
/// `rollbackFailedRegistration` deletes the pre-publish verifier (hash + salt
/// under the full Tox ID and its public-key alias) and the password-change
/// journal record of the identity it is undoing. Secure storage can refuse the
/// delete (the facade reports that as `false`), and the rollback must still
/// finish: the identity's only private key is in the directory the same
/// rollback deletes, so the stray verifier gates nothing — but it would sit in
/// the Keychain / Keystore forever. So the Tox ID is recorded here, in a
/// SharedPreferences-backed list, and the removal is retried on every start
/// ([retryPending], from `AppBootstrap.recoverPendingRestoreBeforeAccountExposure`)
/// until it succeeds.
///
/// Shared Dart: covers desktop and mobile alike.
abstract final class StrandedVerifierCleanup {
  StrandedVerifierCleanup._();

  /// SharedPreferences key of the string list of stranded Tox IDs.
  @visibleForTesting
  static const String prefsKey = 'stranded_password_verifiers';

  /// Pending-list mutations run one after another: two concurrent
  /// read-modify-writes would otherwise overwrite each other's entry. An
  /// [AsyncGate], not a `_tail.then(body)` chain — chaining onto a finished
  /// future from another zone stalls inside a widget test (see [AsyncGate]).
  static final AsyncGate _gate = AsyncGate();

  /// Tox IDs whose verifier removal is still owed.
  static Future<Set<String>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(prefsKey)?.toSet() ?? <String>{};
  }

  /// Remember that [toxId]'s verifier / journal delete was refused. Idempotent;
  /// ignores an empty id. Never throws and logs a refused write: the caller is
  /// already unwinding and still has pointer / directory cleanup to finish.
  static Future<void> record(String toxId) async {
    final id = toxId.trim();
    if (id.isEmpty) return;
    try {
      await _gate.run(() async {
        final prefs = await SharedPreferences.getInstance();
        final ids = prefs.getStringList(prefsKey)?.toSet() ?? <String>{};
        if (!ids.add(id)) return;
        if (!await prefs.setStringList(prefsKey, ids.toList())) {
          AppLogger.warn(
            '[StrandedVerifierCleanup] preferences refused to record the '
            'stranded verifier for $id; it will not be retried',
          );
        }
      });
    } catch (e, st) {
      AppLogger.logError(
        '[StrandedVerifierCleanup] could not record stranded verifier',
        e,
        st,
      );
    }
  }

  /// Retry every pending removal. A record is dropped only once BOTH the
  /// verifier and the journal record are gone; a still-refusing store keeps
  /// it for the next start.
  ///
  /// The verifier is deleted only when the identity is provably ABSENT from
  /// `account_list` ([Prefs.accountRegistryPresence]): a recorded id that is
  /// a published account keeps its verifier and loses the record, and an
  /// unreadable registry defers the whole decision to a later start — this
  /// housekeeping must never be able to revoke a live account's password
  /// gate.
  ///
  /// Returns the number of records cleared. Never throws.
  static Future<int> retryPending() async {
    var cleared = 0;
    try {
      cleared = await _gate.run(() async {
        final ids = await pending();
        if (ids.isEmpty) return 0;
        final remaining = ids.toSet();
        var removedCount = 0;
        for (final toxId in ids) {
          switch (await Prefs.accountRegistryPresence(toxId)) {
            case AccountRegistryPresence.present:
              AppLogger.warn(
                '[StrandedVerifierCleanup] $toxId is a published account; '
                'leaving its verifier and dropping the stranded record',
              );
              remaining.remove(toxId);
              continue;
            case AccountRegistryPresence.unknown:
              AppLogger.warn(
                '[StrandedVerifierCleanup] account_list is unreadable; '
                'deferring the verifier removal for $toxId',
              );
              continue;
            case AccountRegistryPresence.absent:
              break;
          }
          final removed = await Prefs.removeAccountPassword(toxId);
          final journalCleared = await Prefs.passwordChanges.abort(toxId);
          if (removed && journalCleared) {
            remaining.remove(toxId);
            removedCount++;
            AppLogger.log(
              '[StrandedVerifierCleanup] removed stranded verifier for $toxId',
            );
          } else {
            AppLogger.warn(
              '[StrandedVerifierCleanup] secure storage still refuses the '
              'delete for $toxId removed=$removed '
              'journalCleared=$journalCleared; retrying on the next start',
            );
          }
        }
        if (remaining.length != ids.length) {
          final prefs = await SharedPreferences.getInstance();
          final written = remaining.isEmpty
              ? await prefs.remove(prefsKey)
              : await prefs.setStringList(prefsKey, remaining.toList());
          if (!written) {
            AppLogger.warn(
              '[StrandedVerifierCleanup] preferences refused to update the '
              'stranded list; cleared entries will be retried (harmlessly)',
            );
          }
        }
        return removedCount;
      });
    } catch (e, st) {
      AppLogger.logError(
        '[StrandedVerifierCleanup] retryPending failed',
        e,
        st,
      );
    }
    return cleared;
  }
}
