import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../async_gate.dart';
import '../tox_utils.dart';
import 'atomic_file_write.dart';
import 'restore_transaction.dart';

// Durable journal for a full-backup restore: the state model and its on-disk
// store. Split out of `restore_transaction.dart` (complexity-gate pin); the
// transaction itself stays there.
//
// The journal is what makes a restore recoverable across a crash — it records
// which commits have happened so `recoverPendingRestore` can decide between
// finishing and rolling back. `RestoreTransactionState` lives with the
// transaction because the transaction defines the ordering.

final class RestoreTransactionJournal {
  const RestoreTransactionJournal({
    required this.transactionId,
    required this.toxId,
    required this.state,
    required this.profileStageDir,
    required this.profileFinalDir,
    required this.accountDataStageDir,
    required this.accountDataFinalDir,
    required this.hasProfile,
    this.rollbackRequested = false,
    this.priorBlackListCaptured = false,
    this.priorBlackList = const <String>[],
    this.priorFailedQueueCaptured = false,
    this.priorFailedQueue,
  });

  final String transactionId;
  final String toxId;
  final RestoreTransactionState state;
  final String profileStageDir;
  final String profileFinalDir;
  final String accountDataStageDir;
  final String accountDataFinalDir;
  final bool hasProfile;

  /// The FULL-id-keyed preferences as they were BEFORE this transaction wrote
  /// anything: `black_list_<toxId>` and the failed-message queue.
  ///
  /// They are not reached by `clearScopedKeysForAccount`, which matches the
  /// `_<first16>` suffix, so rollback handles them by name - and used to CLEAR
  /// them unconditionally. Both families can outlive an account whose registry
  /// row and directories are already gone, which is a shape `_preflight`
  /// accepts, so a restore that failed during staging deleted a block list and
  /// pending messages it never created. A boolean "did I create these" was not
  /// enough either: the restore OVERWRITES both during metadata application, so
  /// by rollback time the originals are gone whether or not we then clear them.
  /// Keeping the values is the only version of this that loses nothing.
  ///
  /// The two families are captured INDEPENDENTLY. One flag for both meant a
  /// blacklist that could not be read (a malformed value) also threw away an
  /// otherwise perfectly readable queue: nothing was captured, the restore
  /// overwrote the queue anyway, and rollback then had nothing to put back.
  ///
  /// A `...Captured` flag is false for a journal written before these fields
  /// existed, or for a family whose read failed. Ownership is then UNKNOWN, and
  /// unknown ownership must not authorize deletion: rollback leaves that family
  /// exactly as it finds it.
  /// Set durably BEFORE a rollback runs, so recovery cannot mistake a rollback
  /// that failed partway for a restore that succeeded.
  ///
  /// Without it: after the account row is published, a finalize failure triggers
  /// a rollback; if a directory delete then throws before the committed payload
  /// is gone, the row and the payload both survive - and recovery reads exactly
  /// that as "this transaction committed", clears the journal, and takes the only
  /// snapshots of the user's blocked peers and pending messages with it.
  final bool rollbackRequested;

  final bool priorBlackListCaptured;
  final List<String> priorBlackList;
  final bool priorFailedQueueCaptured;
  final String? priorFailedQueue;

  /// Sentinel for "this field was not passed", so a copy can set
  /// [priorFailedQueue] back to null.
  ///
  /// `?? this.priorFailedQueue` cannot express that: a capture taken on a
  /// journal that already holds a queue would record "there was nothing here"
  /// as the stale earlier value - the one shape this whole snapshot exists to
  /// get right.
  static const Object _unchanged = Object();

  RestoreTransactionJournal copyWith({
    RestoreTransactionState? state,
    bool? rollbackRequested,
    bool? priorBlackListCaptured,
    List<String>? priorBlackList,
    bool? priorFailedQueueCaptured,
    Object? priorFailedQueue = _unchanged,
  }) {
    return RestoreTransactionJournal(
      transactionId: transactionId,
      toxId: toxId,
      state: state ?? this.state,
      profileStageDir: profileStageDir,
      profileFinalDir: profileFinalDir,
      accountDataStageDir: accountDataStageDir,
      accountDataFinalDir: accountDataFinalDir,
      hasProfile: hasProfile,
      rollbackRequested: rollbackRequested ?? this.rollbackRequested,
      priorBlackListCaptured:
          priorBlackListCaptured ?? this.priorBlackListCaptured,
      priorBlackList: priorBlackList ?? this.priorBlackList,
      priorFailedQueueCaptured:
          priorFailedQueueCaptured ?? this.priorFailedQueueCaptured,
      priorFailedQueue: identical(priorFailedQueue, _unchanged)
          ? this.priorFailedQueue
          : priorFailedQueue as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'transactionId': transactionId,
    'toxId': toxId,
    'state': state.name,
    'profileStageDir': profileStageDir,
    'profileFinalDir': profileFinalDir,
    'accountDataStageDir': accountDataStageDir,
    'accountDataFinalDir': accountDataFinalDir,
    'hasProfile': hasProfile,
    'rollbackRequested': rollbackRequested,
    'priorBlackListCaptured': priorBlackListCaptured,
    'priorBlackList': priorBlackList,
    'priorFailedQueueCaptured': priorFailedQueueCaptured,
    if (priorFailedQueue != null) 'priorFailedQueue': priorFailedQueue,
  };

  static RestoreTransactionJournal fromJson(Map<String, dynamic> json) {
    final rawState = json['state'] as String?;
    final state = RestoreTransactionState.values.firstWhere(
      (value) => value.name == rawState,
      orElse: () =>
          throw StateError('Unknown restore journal state: $rawState'),
    );
    return RestoreTransactionJournal(
      transactionId: json['transactionId'] as String,
      toxId: json['toxId'] as String,
      state: state,
      profileStageDir: json['profileStageDir'] as String,
      profileFinalDir: json['profileFinalDir'] as String,
      accountDataStageDir: json['accountDataStageDir'] as String,
      accountDataFinalDir: json['accountDataFinalDir'] as String,
      hasProfile: json['hasProfile'] as bool? ?? true,
      // Absent in journals written before these fields existed: ownership is
      // unknown, and rollback must then not touch either family. Defaulting the
      // other way (assuming we own them) is what caused the data loss in the
      // first place, and it would reappear exactly once, during the upgrade.
      rollbackRequested: json['rollbackRequested'] as bool? ?? false,
      priorBlackListCaptured: json['priorBlackListCaptured'] as bool? ?? false,
      priorFailedQueueCaptured:
          json['priorFailedQueueCaptured'] as bool? ?? false,
      priorBlackList:
          (json['priorBlackList'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString())
              .toList(growable: false),
      priorFailedQueue: json['priorFailedQueue'] as String?,
    );
  }
}

/// Refusal to record a restore while another account's restore is unresolved.
///
/// Same rule, and the same reason, as `ToxImportInFlightException`: the journal
/// is a singleton and it is the only description of what a half-applied restore
/// changed. Overwriting it discards another account's snapshot of its own
/// blocked-peer list and failed-message queue, which is exactly the data that
/// snapshot exists to protect.
final class RestoreInFlightException implements Exception {
  const RestoreInFlightException();

  @override
  String toString() => 'RestoreInFlightException: another full-backup restore '
      'is recorded as unresolved and must be recovered first';
}

abstract final class RestoreTransactionJournalStore {
  RestoreTransactionJournalStore._();

  static const _fileName = 'account_export_restore_journal.json';

  /// Serializes read-modify-write on the singleton journal.
  ///
  /// The checks below (does a record exist, does it belong to this account) are
  /// read-then-act pairs, and the actors are not coordinated: a deletion
  /// discarding account A's journal can interleave with a restore publishing
  /// account B's, so A's ownership check passes against A's record and its clear
  /// then deletes B's. Not re-entrant - everything inside uses the `Unguarded`
  /// bodies.
  static final AsyncGate _gate = AsyncGate();

  static Future<RestoreTransactionJournal?> read() => _gate.run(_readUnguarded);

  static Future<RestoreTransactionJournal?> _readUnguarded() async {
    final file = await _journalFile();
    if (!await file.exists()) return null;
    final decoded = json.decode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Restore journal is not a JSON object');
    }
    return RestoreTransactionJournal.fromJson(decoded);
  }

  /// Publish [journal], refusing to overwrite an UNRESOLVED record for another
  /// account.
  ///
  /// A rollback that could not verify its preference writes deliberately keeps
  /// its journal so the next start retries. Nothing stopped the next import from
  /// overwriting that record, and then the snapshot it was keeping - the only
  /// copy of the originals it had failed to restore - was gone for good.
  static Future<void> write(RestoreTransactionJournal journal) =>
      _gate.run(() => _writeUnguarded(journal));

  static Future<void> _writeUnguarded(RestoreTransactionJournal journal) async {
    final existing = await _readUnguarded();
    if (existing != null &&
        (!compareToxIds(existing.toxId, journal.toxId) ||
            existing.transactionId != journal.transactionId)) {
      // Same account is NOT enough. A rollback that could not verify its
      // preference writes keeps its journal so the next start retries; a RETRY
      // of that same account carries a new transaction id, and admitting it
      // overwrote the retained snapshot - the only surviving copy of the
      // originals that rollback had just failed to put back. Advancing an
      // existing transaction through its states keeps its id and is unaffected.
      throw const RestoreInFlightException();
    }
    final file = await _journalFile();
    final bytes = utf8.encode(jsonEncode(journal.toJson()));
    await writeBytesAtomically(file, bytes);
  }

  static Future<void> clear() => _gate.run(_clearUnguarded);

  /// Clear only when the record names [toxId]. See [clear] for the unchecked
  /// form, which is correct only where the caller has just written the record it
  /// is clearing.
  static Future<void> clearIfOwnedBy(String toxId) =>
      _gate.run(() async {
        final existing = await _readUnguarded();
        if (existing == null || !compareToxIds(existing.toxId, toxId)) return;
        await _clearUnguarded();
      });

  /// Admit a NEW transaction for [journal]'s account, CARRYING FORWARD the
  /// snapshot of any record it replaces.
  ///
  /// The transaction-id fence protects a journal that a failed rollback kept for
  /// retry. Without a way past it, a rollback whose preference writes can never
  /// verify keeps that journal forever and every later restore is refused - and
  /// the same rollback already removed the account row, so the account cannot
  /// even be selected for the deletion path that discards journals.
  ///
  /// Moving the old record to a side file was the first attempt and was worse:
  /// nothing reads those files, so a SINGLE temporary write refusal would have
  /// removed a recoverable snapshot from startup recovery permanently, and the
  /// files outlived account deletion carrying a blocked-peer list and message
  /// payloads with them. Carrying the snapshot into the new record instead needs
  /// no new files, no lifecycle and no cleanup: the retained values predate both
  /// transactions, so they are the ones the user actually wants back, and the
  /// new transaction's own rollback restores them.
  ///
  /// Returns the journal as written. Refuses a record belonging to ANOTHER
  /// account - that snapshot is not ours to carry or discard.
  static Future<RestoreTransactionJournal> admitCarryingForward(
    RestoreTransactionJournal journal,
  ) =>
      _gate.run(() async {
        final existing = await _readUnguarded();
        if (existing == null) {
          await _writeUnguarded(journal);
          return journal;
        }
        if (!compareToxIds(existing.toxId, journal.toxId)) {
          throw const RestoreInFlightException();
        }
        // EXACT id, not `compareToxIds`. That comparator accepts the 64- and
        // 76-char forms of one identity, and addresses that differ only in
        // nospam - but `black_list_<toxId>` and the modern failed-queue key use
        // the id VERBATIM. Carrying a snapshot taken under one spelling into a
        // record that names another would have the rollback write those values
        // into keys nothing reads, while the namespace they came from loses its
        // recovery information entirely. Same account, different namespace: the
        // new transaction starts from its own capture.
        final sameNamespace = existing.toxId == journal.toxId;
        // A different SPELLING of the same account, holding a snapshot nobody
        // has recovered yet, is refused rather than replaced. Skipping the carry
        // (because the keys would be wrong) and overwriting anyway destroys the
        // only surviving copy of those originals - the namespace they belong to
        // then has no record at all. Refusing costs the user a retry with the
        // spelling the archive actually carries, which is the same spelling that
        // produced the record, so the ordinary retry path still works.
        if (!sameNamespace &&
            (existing.priorBlackListCaptured ||
                existing.priorFailedQueueCaptured)) {
          throw const RestoreInFlightException();
        }
        // Per FAMILY, not both-or-neither. The families are captured
        // independently (an unreadable block list must not discard a good queue
        // snapshot), so an `||` that carried both whenever EITHER was captured
        // would overwrite a newly successful capture with `Captured: false` -
        // and the next failed rollback would then leave that family's
        // overwritten values in place.
        final carryBlackList = sameNamespace && existing.priorBlackListCaptured;
        final carryQueue = sameNamespace && existing.priorFailedQueueCaptured;
        // One atomic write replaces the old record with one that contains its
        // snapshot, so there is no window in which neither holds it.
        final carried = (carryBlackList || carryQueue)
            ? journal.copyWith(
                priorBlackListCaptured:
                    carryBlackList ? true : journal.priorBlackListCaptured,
                priorBlackList: carryBlackList
                    ? existing.priorBlackList
                    : journal.priorBlackList,
                priorFailedQueueCaptured:
                    carryQueue ? true : journal.priorFailedQueueCaptured,
                priorFailedQueue: carryQueue
                    ? existing.priorFailedQueue
                    : journal.priorFailedQueue,
              )
            : journal;
        final file = await _journalFile();
        await writeBytesAtomically(
          file,
          utf8.encode(jsonEncode(carried.toJson())),
        );
        return carried;
      });

  static Future<void> _clearUnguarded() async {
    final file = await _journalFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<File> _journalFile() async {
    final root = await AppPaths.applicationSupportPath;
    return File(p.join(root, _fileName));
  }
}
