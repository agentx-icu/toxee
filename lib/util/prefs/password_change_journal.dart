// Durable record of an in-flight account password change.
//
// A password change touches two stores that cannot be updated atomically
// together: the tox profile on disk (re-keyed natively, one atomic rename) and
// the PBKDF2 verifier in secure storage. A kill between the two leaves a file
// whose key no verifier describes, and the account can never be opened again.
// This journal is written BEFORE the first of those writes and removed after
// the last, as ONE secure-storage value (a single write, so a kill cannot
// leave half a record). Its `phase` is the proof of how far the change got:
//
//   set/remove, staged  -> nothing on disk or in the verifier has changed yet
//   set,        rekeyed -> the profile is under the NEW password; the verifier
//                          may or may not be promoted yet
//   remove,     rekeyed -> the profile is plaintext; the verifier may or may
//                          not be deleted yet
//
// `PasswordChangeTransactions` turns those facts into the gate / verify /
// reconcile decisions.

import 'dart:convert';

import 'secure_storage_facade.dart';

enum PasswordChangeKind { set, remove }

enum PasswordChangePhase { staged, rekeyed }

final class PasswordChangeRecord {
  const PasswordChangeRecord({
    required this.kind,
    required this.phase,
    required this.startedAtMs,
    this.hash,
    this.salt,
  });

  final PasswordChangeKind kind;
  final PasswordChangePhase phase;
  final int startedAtMs;

  /// The NEW password's verifier (same wire format as the primary slot), only
  /// for [PasswordChangeKind.set].
  final String? hash;
  final String? salt;

  PasswordChangeRecord withPhase(PasswordChangePhase next) =>
      PasswordChangeRecord(
        kind: kind,
        phase: next,
        startedAtMs: startedAtMs,
        hash: hash,
        salt: salt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': 1,
        'kind': kind.name,
        'phase': phase.name,
        'startedAtMs': startedAtMs,
        if (hash != null) 'hash': hash,
        if (salt != null) 'salt': salt,
      };

  /// null when [raw] is not a record this build understands. Callers treat
  /// that like an unreadable store: closed, never open.
  static PasswordChangeRecord? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final kind = PasswordChangeKind.values
          .where((k) => k.name == json['kind'])
          .firstOrNull;
      final phase = PasswordChangePhase.values
          .where((p) => p.name == json['phase'])
          .firstOrNull;
      if (kind == null || phase == null) return null;
      final hash = json['hash'] as String?;
      final salt = json['salt'] as String?;
      if (kind == PasswordChangeKind.set &&
          (hash == null || hash.isEmpty || salt == null || salt.isEmpty)) {
        return null;
      }
      return PasswordChangeRecord(
        kind: kind,
        phase: phase,
        startedAtMs: (json['startedAtMs'] as num?)?.toInt() ?? 0,
        hash: hash,
        salt: salt,
      );
    } catch (_) {
      return null;
    }
  }
}

/// What a journal read found. [unavailable] covers both "secure storage could
/// not answer" and "the value is not a record we understand" — callers must
/// treat both as a possible in-flight change (fail closed).
final class PasswordChangeReadOutcome {
  const PasswordChangeReadOutcome.absent()
      : record = null,
        unavailable = false;
  const PasswordChangeReadOutcome.found(PasswordChangeRecord this.record)
      : unavailable = false;
  const PasswordChangeReadOutcome.unavailable()
      : record = null,
        unavailable = true;

  final PasswordChangeRecord? record;
  final bool unavailable;
}

class PasswordChangeJournal {
  PasswordChangeJournal(this._secureStorage);

  final SecureStorageFacade _secureStorage;

  static String key(String toxId) => 'pwd_txn_$toxId';

  Future<PasswordChangeReadOutcome> read(String toxId) async {
    if (toxId.isEmpty) return const PasswordChangeReadOutcome.absent();
    final outcome = await _secureStorage.readOutcome(key(toxId));
    if (outcome.unavailable) {
      return const PasswordChangeReadOutcome.unavailable();
    }
    if (!outcome.hasValue) return const PasswordChangeReadOutcome.absent();
    final record = PasswordChangeRecord.tryParse(outcome.value!);
    return record == null
        ? const PasswordChangeReadOutcome.unavailable()
        : PasswordChangeReadOutcome.found(record);
  }

  Future<bool> write(String toxId, PasswordChangeRecord record) =>
      _secureStorage.write(key(toxId), jsonEncode(record.toJson()));

  Future<bool> clear(String toxId) => _secureStorage.delete(key(toxId));
}
