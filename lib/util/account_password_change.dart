// Mid-session password set / change / removal as a journaled transaction.
//
// Two stores must agree: the tox profile on disk (re-keyed natively as one
// atomic step — `FfiChatService.rekeyLiveProfilePassphrase`) and the PBKDF2
// verifier in secure storage. Neither write order is safe against a kill on
// its own, so every change is bracketed by a `PasswordChangeRecord` (one
// secure-storage value) whose phase proves how far it got; the gates and
// `initializeServiceForAccount` finish or abandon a leftover record from the
// password the user then logs in with. See password_change_journal.dart.

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'account_service_test_hooks.dart';
import 'async_gate.dart';
import 'logger.dart';
import 'prefs.dart';
import 'prefs/password_change_transactions.dart';
import 'secret_passphrase_staging.dart';
import 'session_password_store.dart';

export 'prefs/password_change_transactions.dart' show PasswordChangeReconcile;
export 'secret_password.dart';

enum PasswordChangeOutcome {
  ok,

  /// An earlier change is still recorded and could not be finished in
  /// session; log out and back in resolves it. Nothing was changed.
  pendingChange,

  /// The journal / verifier could not be written. Nothing was changed.
  storageFailed,

  /// The native re-key did not reach disk; the previous passphrase is back in
  /// force and the file is unchanged. Nothing was changed.
  rekeyFailed,
}

abstract final class AccountPasswordChange {
  AccountPasswordChange._();

  /// One change at a time: two interleaved changes could each see no record,
  /// re-key the file to different passwords and promote the wrong verifier.
  static final AsyncGate _gate = AsyncGate();

  /// Set or change the password of the live session's account.
  ///
  /// 1 record{set, staged}  2 re-key + persist  3 record{set, rekeyed}
  /// 4 promote verifier + clear record  5 SessionPasswordStore.
  /// A failure at 2 clears the record (nothing changed); a failure at 4
  /// keeps a rekeyed record — the file IS under the new password and login
  /// accepts it through the record — and still reports [ok].
  ///
  /// [password] is borrowed; the store keeps its own copy. A caller that
  /// disposes it while the change is still running is a caller bug, so the
  /// transaction works on a private copy (the gate may queue it behind another
  /// change for an unbounded time).
  static Future<PasswordChangeOutcome> set(
    FfiChatService service,
    SecretPassword password,
  ) {
    final owned = password.copy();
    return _gate.run(() => _set(service, owned)).whenComplete(owned.dispose);
  }

  static Future<PasswordChangeOutcome> _set(
    FfiChatService service,
    SecretPassword password,
  ) async {
    final toxId = service.getSelfToxId();
    if (toxId == null || toxId.isEmpty || password.isEmpty) {
      return PasswordChangeOutcome.storageFailed;
    }
    final tx = Prefs.passwordChanges;
    final blocked = await _settleLeftover(tx, toxId, service);
    if (blocked != null) return blocked;

    if (!await tx.beginSet(toxId, password)) {
      return PasswordChangeOutcome.storageFailed;
    }
    if (!_rekeyLive(service, password)) {
      await tx.abort(toxId);
      return PasswordChangeOutcome.rekeyFailed;
    }
    if (!await tx.markRekeyed(toxId)) {
      AppLogger.warn(
        '[AccountPasswordChange] re-keyed but could not record the phase; the '
        'record stays staged and is resolved at the next login',
      );
    } else if (!await tx.promoteSet(toxId)) {
      AppLogger.warn(
        '[AccountPasswordChange] re-keyed but the verifier could not be '
        'promoted; the record keeps the new password accepted at login',
      );
    }
    SessionPasswordStore.set(toxId, password);
    return PasswordChangeOutcome.ok;
  }

  /// Remove the password of the live session's account.
  ///
  /// 1 record{remove, staged}  2 re-key to plaintext + persist
  /// 3 record{remove, rekeyed}  4 delete every verifier source + clear record
  /// 5 SessionPasswordStore.clear. A failure at 2 clears the record; after 2
  /// the removal is committed — the gate finishes step 4 on its own.
  static Future<PasswordChangeOutcome> remove(FfiChatService service) =>
      _gate.run(() => _remove(service));

  static Future<PasswordChangeOutcome> _remove(FfiChatService service) async {
    final toxId = service.getSelfToxId();
    if (toxId == null || toxId.isEmpty) {
      return PasswordChangeOutcome.storageFailed;
    }
    final tx = Prefs.passwordChanges;
    final blocked = await _settleLeftover(tx, toxId, service);
    if (blocked != null) return blocked;

    if (!await tx.beginRemove(toxId)) {
      return PasswordChangeOutcome.storageFailed;
    }
    if (!_rekeyLive(service, null)) {
      await tx.abort(toxId);
      return PasswordChangeOutcome.rekeyFailed;
    }
    if (!await tx.markRekeyed(toxId)) {
      AppLogger.warn(
        '[AccountPasswordChange] profile is plaintext but the phase could not '
        'be recorded; the next login with the old password finishes the removal',
      );
      return PasswordChangeOutcome.ok;
    }
    if (!await tx.completeRemove(toxId)) {
      AppLogger.warn(
        '[AccountPasswordChange] profile is plaintext but a verifier source '
        'could not be deleted; the gate finishes the removal when it can',
      );
    }
    SessionPasswordStore.clear(toxId);
    return PasswordChangeOutcome.ok;
  }

  static bool _rekeyLive(FfiChatService service, SecretPassword? password) {
    final hook = AccountPasswordChangeTestHooks.rekeyLive;
    if (hook != null) return hook(service, password);
    return service.rekeyLiveProfilePassphraseSecret(password);
  }

  /// A leftover record blocks a new change unless it can be finished right
  /// here with proof: a rekeyed `set` is promoted, a rekeyed `remove` is
  /// completed. A staged record is never touched in session — the file's key
  /// is unproven — and is resolved by the next authenticated login.
  static Future<PasswordChangeOutcome?> _settleLeftover(
    PasswordChangeTransactions tx,
    String toxId,
    FfiChatService service,
  ) async {
    final pending = await tx.pending(toxId);
    if (pending.unavailable) return PasswordChangeOutcome.storageFailed;
    final record = pending.record;
    if (record == null) return null;
    if (record.phase == PasswordChangePhase.rekeyed) {
      final settled = record.kind == PasswordChangeKind.set
          ? await tx.promoteSet(toxId)
          : await tx.completeRemove(toxId);
      if (settled) return null;
    }
    return PasswordChangeOutcome.pendingChange;
  }
}
