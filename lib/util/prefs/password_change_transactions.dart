// Journal-aware view of an account's password: what the gate should report,
// what a typed password verifies against, and how an interrupted change is
// finished or abandoned. See `password_change_journal.dart` for the record
// and the phases it proves.

import '../logger.dart';
import 'password_change_journal.dart';
import 'password_verifier.dart';

export 'password_change_journal.dart';

/// What `reconcileAfterLogin` did with a pending record.
enum PasswordChangeReconcile { none, promoted, abandoned, removalCompleted, left }

class PasswordChangeTransactions {
  PasswordChangeTransactions({
    required PasswordVerifier verifier,
    required PasswordChangeJournal journal,
  })  : _verifier = verifier,
        _journal = journal;

  final PasswordVerifier _verifier;
  final PasswordChangeJournal _journal;

  PasswordVerifier get verifier => _verifier;

  Future<PasswordChangeReadOutcome> pending(String toxId) => _journal.read(toxId);

  /// The gate's answer. A record keeps the account CLOSED whatever the
  /// primary slot says: a `set` may already key the file; a staged `remove`
  /// has changed nothing yet; a rekeyed `remove` is reported `unknown` until
  /// [reconcileForGate] has provably deleted every verifier source.
  Future<AccountProtectionState> protectionState(String toxId) async {
    final journal = await _journal.read(toxId);
    if (journal.unavailable) return AccountProtectionState.unknown;
    final record = journal.record;
    if (record != null) {
      if (record.kind == PasswordChangeKind.set) {
        return AccountProtectionState.protected;
      }
      return record.phase == PasswordChangePhase.staged
          ? AccountProtectionState.protected
          : AccountProtectionState.unknown;
    }
    return _verifier.protectionState(toxId);
  }

  Future<bool> hasPassword(String toxId) async =>
      (await protectionState(toxId)) != AccountProtectionState.none;

  /// The primary verifier, or — while a `set` is in flight — the recorded
  /// new one, so the password that may already key the file is accepted.
  Future<bool> verifyPassword(String toxId, String password) async {
    if (await _verifier.verifyPassword(toxId, password)) return true;
    final record = (await _journal.read(toxId)).record;
    if (record == null || record.kind != PasswordChangeKind.set) return false;
    return _verifier.matchesPbkdf2(password, record.hash!, record.salt);
  }

  // ---- transaction steps (the caller sequences them; see AccountPasswordChange)

  Future<bool> beginSet(String toxId, String newPassword) async {
    final derived = await _verifier.deriveVerifier(newPassword);
    return _journal.write(
      toxId,
      PasswordChangeRecord(
        kind: PasswordChangeKind.set,
        phase: PasswordChangePhase.staged,
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
        hash: derived.hash,
        salt: derived.salt,
      ),
    );
  }

  Future<bool> beginRemove(String toxId) => _journal.write(
        toxId,
        PasswordChangeRecord(
          kind: PasswordChangeKind.remove,
          phase: PasswordChangePhase.staged,
          startedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  /// Records that the profile on disk now carries the change (re-key done).
  Future<bool> markRekeyed(String toxId) async {
    final record = (await _journal.read(toxId)).record;
    if (record == null) return false;
    return _journal.write(toxId, record.withPhase(PasswordChangePhase.rekeyed));
  }

  /// Makes the recorded new verifier primary and closes the record. Only for
  /// a `set` whose re-key is proven (phase rekeyed) — or, from
  /// [reconcileAfterLogin], proven by a successful login with that password.
  Future<bool> promoteSet(String toxId, {bool proven = false}) async {
    final record = (await _journal.read(toxId)).record;
    if (record == null || record.kind != PasswordChangeKind.set) return false;
    if (!proven && record.phase != PasswordChangePhase.rekeyed) return false;
    if (!await _verifier.writePrimaryVerifier(toxId, record.hash!, record.salt!)) {
      return false;
    }
    if (!await _journal.clear(toxId)) {
      AppLogger.warn(
        '[PasswordChange] promoted verifier but the journal record could not be '
        'cleared; it stays as a rekeyed record and is re-promoted on reconcile',
      );
    }
    return true;
  }

  /// Deletes every verifier source and closes the record; false leaves the
  /// record (and the gate closed) for a later attempt.
  Future<bool> completeRemove(String toxId) async {
    if (!await _verifier.removePassword(toxId)) return false;
    return _journal.clear(toxId);
  }

  Future<bool> abort(String toxId) => _journal.clear(toxId);

  /// Everything password-related for an account that is being deleted: every
  /// verifier source AND the journal record (which carries a verifier of its
  /// own). True only when all of it is gone.
  Future<bool> removeAllCredentials(String toxId) async {
    final verifierGone = await _verifier.removePassword(toxId);
    final journalGone = await _journal.clear(toxId);
    return verifierGone && journalGone;
  }

  /// Called by the startup and login gates BEFORE reading the state: the one
  /// case decidable without the password — a rekeyed `remove` (the file is
  /// plaintext by proof, the user asked for that) — is finished here.
  Future<void> reconcileForGate(String toxId) async {
    final record = (await _journal.read(toxId)).record;
    if (record == null ||
        record.kind != PasswordChangeKind.remove ||
        record.phase != PasswordChangePhase.rekeyed) {
      return;
    }
    if (!await completeRemove(toxId)) {
      AppLogger.warn(
        '[PasswordChange] rekeyed removal could not delete every verifier '
        'source; the account stays gated until it can',
      );
    }
  }

  /// After a session was opened with [typedPassword] (so the profile provably
  /// carries it). [rekeyLive] re-keys the live session and persists (null =>
  /// plaintext); it is needed only to finish an interrupted removal.
  Future<PasswordChangeReconcile> reconcileAfterLogin(
    String toxId,
    String typedPassword, {
    required Future<bool> Function(String? password) rekeyLive,
  }) async {
    final record = (await _journal.read(toxId)).record;
    if (record == null) return PasswordChangeReconcile.none;
    if (record.kind == PasswordChangeKind.set) {
      final isNew = await _verifier.matchesPbkdf2(typedPassword, record.hash!, record.salt);
      if (isNew) {
        return await promoteSet(toxId, proven: true)
            ? PasswordChangeReconcile.promoted
            : PasswordChangeReconcile.left;
      }
      // Opened with the previous password: the file never took the new one.
      if (record.phase == PasswordChangePhase.staged) {
        return await _journal.clear(toxId)
            ? PasswordChangeReconcile.abandoned
            : PasswordChangeReconcile.left;
      }
      AppLogger.warn(
        '[PasswordChange] rekeyed set record but the session opened with the '
        'previous password; leaving the record for a later login',
      );
      return PasswordChangeReconcile.left;
    }
    // A removal the user asked for: the session is running (and the file is
    // encrypted again, InitSDK re-encrypts a plaintext profile it opens under
    // a passphrase), so finish it exactly as the live path would.
    if (!await rekeyLive(null)) return PasswordChangeReconcile.left;
    if (!await markRekeyed(toxId)) return PasswordChangeReconcile.left;
    return await completeRemove(toxId)
        ? PasswordChangeReconcile.removalCompleted
        : PasswordChangeReconcile.left;
  }
}
