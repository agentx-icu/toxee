import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../async_gate.dart';
import '../imported_account_rollback.dart';
import '../prefs.dart';
import '../safe_diagnostics.dart';
import '../tox_utils.dart';
import 'atomic_file_write.dart';

/// How far a `.tox` import got before the process stopped.
///
/// The full-backup `.zip` path has had a journal since its own review; the
/// single-file `.tox` path never did, and it writes the same three things in the
/// same order. Its only recovery was an in-process `catch`, which a kill does not
/// run — and mobile kills backgrounded apps as a matter of course.
enum ToxImportStage {
  /// The profile file has been written but is not yet protected or published.
  ///
  /// A kill here used to leave an UNPROTECTED profile on disk that
  /// `AccountReconciliation` would then register as a usable account, even
  /// though the user had supplied a password for it.
  profileWritten,

  /// The profile is encrypted (or needed no encryption), but no registry row
  /// exists yet.
  ///
  /// A kill here used to leave an invisible encrypted orphan: reconciliation
  /// skips profiles whose identity it cannot extract, and a re-import was
  /// refused because the profile file already existed. Unreachable and
  /// un-retryable.
  profileProtected,

  /// The registry row is published but the password verifier is not stored.
  ///
  /// A kill here used to leave ciphertext with NO verifier — so the account
  /// showed up in the picker, was reported unprotected, and could never be
  /// opened.
  accountPublished,
}

/// Durable record of an in-flight `.tox` import.
final class ToxImportJournalEntry {
  const ToxImportJournalEntry({
    required this.toxId,
    required this.stage,
    required this.expectsPassword,
    required this.ownership,
  });

  final String toxId;
  final ToxImportStage stage;

  /// Whether the user supplied a password, i.e. whether a verifier is still owed
  /// at [ToxImportStage.accountPublished].
  final bool expectsPassword;

  /// What this import created on disk, so recovery deletes only that. Same rule
  /// as [ImportedAccountRollback].
  final ImportedAccountOwnership ownership;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'toxId': toxId,
    'stage': stage.name,
    'expectsPassword': expectsPassword,
    'ownsProfileDirectory': ownership.ownsProfileDirectory,
    'ownsAccountDataRoot': ownership.ownsAccountDataRoot,
    'ownsProfileFile': ownership.ownsProfileFile,
  };

  static ToxImportJournalEntry? fromJson(Map<String, dynamic> json) {
    final rawStage = json['stage'];
    final toxId = json['toxId'];
    if (toxId is! String || toxId.isEmpty || rawStage is! String) return null;
    ToxImportStage? stage;
    for (final candidate in ToxImportStage.values) {
      if (candidate.name == rawStage) stage = candidate;
    }
    if (stage == null) return null;
    return ToxImportJournalEntry(
      toxId: toxId,
      stage: stage,
      expectsPassword: json['expectsPassword'] as bool? ?? false,
      ownership: ImportedAccountOwnership(
        ownsProfileDirectory: json['ownsProfileDirectory'] as bool? ?? false,
        ownsAccountDataRoot: json['ownsAccountDataRoot'] as bool? ?? false,
        ownsProfileFile: json['ownsProfileFile'] as bool? ?? false,
      ),
    );
  }
}

/// Refusal to record a `.tox` import while another one is still on record.
///
/// The journal is a singleton, so overwriting it would erase the only
/// description of an import that has not been recovered yet: the earlier
/// account's leftover profile would then be adopted by reconciliation (without
/// the password the user supplied for it) or stay an un-retryable orphan. There
/// are three entry points (Settings import, login-page import, login-page
/// restore) guarded by three independent per-widget booleans, so "only one at a
/// time" cannot be assumed - it has to be enforced here, on the durable record.
final class ToxImportInFlightException implements Exception {
  const ToxImportInFlightException({this.identified = true});

  /// False when a record exists but cannot be parsed, so not even the account it
  /// belongs to is known.
  final bool identified;

  @override
  String toString() => identified
      ? 'ToxImportInFlightException: another .tox import is recorded as in '
            'flight and has not been recovered yet'
      : 'ToxImportInFlightException: an unreadable import record is present; it '
            'must be recovered before another import can start';
}

/// On-disk store plus recovery for the `.tox` import journal.
///
/// One entry at a time: an import is a user-driven, foreground operation, and
/// both entry points already refuse to start a second one while the first is in
/// flight.
abstract final class ToxImportJournal {
  ToxImportJournal._();

  static const _fileName = 'account_tox_import_journal.json';

  /// Serializes admission, so the ownership checks below cannot be raced.
  ///
  /// Checking the record and then writing it is a read-modify-write, and two
  /// imports that interleave inside it both see "no record" and both publish -
  /// which is the very overwrite the checks exist to prevent. The entry points
  /// are guarded only by per-widget booleans that know nothing about each other,
  /// so the exclusion has to live here.
  ///
  /// NOT re-entrant (see [AsyncGate]): everything inside runs the `Unguarded`
  /// bodies.
  static final AsyncGate _gate = AsyncGate();

  static Future<File> _file() async {
    final root = await AppPaths.applicationSupportPath;
    return File(p.join(root, _fileName));
  }

  /// Record (or advance) the in-flight import.
  ///
  /// Throws [ToxImportInFlightException] rather than overwriting a record that
  /// belongs to a DIFFERENT account, or one that cannot be read at all. An
  /// overwrite loses the only pointer to the earlier import's leftovers, and the
  /// clear that follows this import's success would then leave them behind for
  /// reconciliation to adopt. Refusing costs the user a retry after a restart
  /// (where recovery runs); overwriting costs them an account they cannot open.
  static Future<void> write(ToxImportJournalEntry entry) =>
      _gate.run(() => _writeUnguarded(entry));

  static Future<void> _writeUnguarded(ToxImportJournalEntry entry) async {
    final file = await _file();
    final existing = await read();
    if (existing == null && await file.exists()) {
      throw const ToxImportInFlightException(identified: false);
    }
    if (existing != null) {
      if (!compareToxIds(existing.toxId, entry.toxId)) {
        throw const ToxImportInFlightException();
      }
      // Same account, but is this the SAME attempt advancing, or a new one?
      // [ToxImportStage.profileWritten] is the discriminator: every entry point
      // writes it exactly once, first, so a record that already exists plus an
      // incoming first stage means a fresh attempt on top of an unrecovered one.
      //
      // Admitting it was not cosmetic. The retry adopts the earlier attempt's
      // record, and clearing that record on success discards the only pointer to
      // what the earlier one left behind - typically a HALF-WRITTEN password
      // verifier, whose surviving PBKDF2 hash without its salt makes every
      // password for that account fail forever. The retry has to wait for the
      // restart that rolls the first attempt back.
      if (entry.stage == ToxImportStage.profileWritten) {
        throw const ToxImportInFlightException();
      }
    }
    await writeBytesAtomically(
      file,
      utf8.encode(jsonEncode(entry.toJson())),
    );
  }

  /// Clear the journal once [toxId]'s import is complete.
  ///
  /// Ownership-checked: it deletes the record only when the record NAMES
  /// [toxId]. An unchecked clear let one import delete another's record - the
  /// second import finishes, wipes the file, and the first one's half-written
  /// account becomes invisible to recovery. An unreadable record is kept for the
  /// same reason it is kept everywhere else: it is the only remaining evidence.
  static Future<void> clear({required String toxId}) =>
      _gate.run(() => _clearUnguarded(toxId));

  static Future<void> _clearUnguarded(String toxId) async {
    final file = await _file();
    if (!await file.exists()) return;
    final existing = await read();
    if (existing == null) {
      SafeDiagnostics.logFailure(
        '[ToxImportJournal] refusing to clear an unreadable import record',
        StateError('unreadable journal'),
      );
      return;
    }
    if (!compareToxIds(existing.toxId, toxId)) {
      SafeDiagnostics.logFailure(
        '[ToxImportJournal] refusing to clear a record that belongs to another '
        'import',
        StateError('journal owned by another import'),
      );
      return;
    }
    await file.delete();
  }

  /// The in-flight entry, or null when there is none or it cannot be read.
  ///
  /// An unreadable entry is treated as absent and removed: unlike a deletion
  /// tombstone it gates nothing, so the safe reading is "no import was in
  /// flight" — the worst case is a leftover profile that the user can delete or
  /// re-import over.
  static Future<ToxImportJournalEntry?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) throw const FormatException('');
      final entry = ToxImportJournalEntry.fromJson(decoded);
      if (entry == null) throw const FormatException('');
      return entry;
    } catch (e) {
      // Unreadable: we cannot tell WHICH account was being imported, so we
      // cannot roll it back.
      //
      // LEAVE THE FILE IN PLACE. Renaming it aside left only an in-memory
      // marker, so the next cold start forgot the problem entirely and
      // reconciliation proceeded over whatever half-import is on disk. The file
      // IS the durable marker — re-reading one small file per boot is the price
      // of not losing the warning. It is removed when an import completes or is
      // successfully rolled back.
      SafeDiagnostics.logFailure(
        '[ToxImportJournal] unreadable import journal; an interrupted import '
        'cannot be attributed, so orphan adoption stays disabled',
        e,
      );
      _unreadable = true;
      return null;
    }
  }

  /// Finish or undo a `.tox` import left in flight by a previous process.
  ///
  /// Rolls back rather than completing: the import needs the user's password to
  /// finish (to encrypt the profile, or to store the verifier), and that is not
  /// available at startup. Undoing returns the device to a state where the user
  /// can simply import the file again — which is the outcome they can act on,
  /// unlike an orphan that blocks re-import.
  ///
  /// Safe to call on every cold start. Runs BEFORE account reconciliation, so a
  /// half-written profile is never registered as an account.
  static Future<void> recoverPendingImport() async {
    final entry = await read();
    if (entry == null) return;
    SafeDiagnostics.logFailure(
      '[ToxImportJournal] rolling back an interrupted .tox import '
      '(stage=${entry.stage.name})',
      StateError('interrupted at ${entry.stage.name}'),
    );
    // An account row may exist (stage `accountPublished`); the rollback removes
    // it along with the prefs, and deletes only the on-disk state this import
    // created.
    await ImportedAccountRollback.run(
      toxId: entry.toxId,
      logContext: 'ToxImportJournal',
      ownership: entry.ownership,
    );
    // The verifier is keyed by the full toxId and is not part of the ownership
    // set, so clear it explicitly: leaving one behind would make a later import
    // of the same file demand a password for an account that no longer exists.
    await Prefs.removeAccountPassword(entry.toxId);

    if (!await clearIfRolledBack(toxId: entry.toxId)) {
      _unresolved.add(entry.toxId);
    }
  }

  /// Clear the journal ONLY once the rollback is verified on disk.
  ///
  /// `ImportedAccountRollback.run` is best-effort: it logs individual deletion
  /// failures and returns normally. Clearing on that basis left a profile we
  /// failed to delete for the reconciliation pass that follows, which would
  /// publish it as an account — complete with the plaintext-or-unverifiable state
  /// the rollback existed to remove. Every caller that rolls an import back must
  /// come through here, including the in-process failure handlers: an exception
  /// path can fail to clean up exactly as a crash-recovery path can.
  ///
  /// The registry read goes through a RELOADED store. `SharedPreferences`
  /// updates its own cache before the platform write completes and the registry
  /// write discards the returned bool, so a refused removal would otherwise read
  /// back as gone.
  ///
  /// The verifier is CHECKED here, not passed in. It used to be a parameter
  /// defaulting to `true`, and every production caller omitted it: their
  /// rollback goes through `Prefs.clearAccountData`, which drops
  /// `removeAccountPassword`'s return value, so a secure-store cleanup that
  /// silently failed still cleared the journal - and a later plaintext re-import
  /// inherited a verifier it cannot satisfy, i.e. an account nobody can open.
  /// `AccountProtectionState.unknown` (secure storage unreachable) is NOT
  /// treated as removed, because "we could not look" is not "it is gone".
  ///
  /// Returns whether the journal was cleared. `false` means state survives and
  /// the record must be kept for the next attempt.
  static Future<bool> clearIfRolledBack({required String toxId}) =>
      _gate.run(() => _clearIfRolledBackUnguarded(toxId));

  static Future<bool> _clearIfRolledBackUnguarded(String toxId) async {
    final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
    final profileGone =
        !await File(AppPaths.profileFileInDirectory(profileDir)).exists();
    final rowGone = await Prefs.accountRowGoneOnDisk(toxId);
    final protection = await Prefs.accountProtectionState(toxId);
    final verifierGone = protection == AccountProtectionState.none;
    if (profileGone && rowGone && verifierGone) {
      await _clearUnguarded(toxId);
      return true;
    }
    SafeDiagnostics.logFailure(
      '[ToxImportJournal] rollback incomplete '
      '(profileGone=$profileGone rowGone=$rowGone '
      'protection=${protection.name}); keeping the journal for retry',
      StateError('incomplete rollback'),
    );
    return false;
  }

  /// Imports whose rollback could not be established during this process.
  ///
  /// Non-empty means some half-imported account may still be on disk, so
  /// startup must not go on to reconcile and expose accounts. See
  /// `AppBootstrap.recoverPendingRestoreBeforeAccountExposure`.
  static Set<String> get unresolved => Set.unmodifiable(_unresolved);
  static final Set<String> _unresolved = <String>{};

  /// True when an import journal exists but cannot be parsed.
  ///
  /// Deliberately SEPARATE from [unresolved], because the safe response differs.
  /// An unresolved-but-identified import means a specific account may be
  /// half-created, and blocking is proportionate. An UNREADABLE journal names no
  /// account, so blocking the whole app would be a dead end for the user — their
  /// existing accounts are fine. Instead, orphan adoption
  /// (`AccountReconciliation`) is skipped, so no leftover profile is published as
  /// an account, and everything else proceeds.
  static bool get hasUnreadableJournal => _unreadable;
  static bool _unreadable = false;

  @visibleForTesting
  static void resetUnresolved() {
    _unresolved.clear();
    _unreadable = false;
    _gate.reset();
  }

  /// Whether [toxId] is the account an interrupted import was creating.
  ///
  /// Lets a caller tell "this profile is a leftover from my own interrupted
  /// attempt" from "this account genuinely already exists".
  static Future<bool> isPendingFor(String toxId) async {
    final entry = await read();
    if (entry == null) return false;
    return compareToxIds(entry.toxId, toxId);
  }
}

/// Advance the journal to [stage] for an in-flight import.
///
/// A one-line helper so the three call sites in each import path stay readable:
/// journalling is bookkeeping around the real work, and it should not bury it.
Future<void> markToxImportStage({
  required String toxId,
  required ToxImportStage stage,
  required bool expectsPassword,
  required ImportedAccountOwnership ownership,
}) {
  return ToxImportJournal.write(
    ToxImportJournalEntry(
      toxId: toxId,
      stage: stage,
      expectsPassword: expectsPassword,
      ownership: ownership,
    ),
  );
}
