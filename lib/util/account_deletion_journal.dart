import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'account_export/atomic_file_write.dart';
import 'app_paths.dart';
import 'logger.dart';
import 'safe_diagnostics.dart';
import 'tox_utils.dart';

enum AccountDeletionStage {
  tombstone,
  serviceData,
  securePassword,
  prefsData,
  profileDirectory,
  accountDataDirectory,
  currentAccount,
  privacyResidue,
  accountRegistry,
  tombstoneClear,
}

enum AccountDeletionState {
  tombstoned,
  serviceDataCleared,
  securePasswordCleared,
  prefsDataCleared,
  profileDirectoryDeleted,
  accountDataDirectoryDeleted,
  currentAccountCleared,
  privacyResidueCleared,
  accountRegistryRemoved,
}

extension AccountDeletionStateOrdering on AccountDeletionState {
  int get deletionOrder => switch (this) {
    AccountDeletionState.tombstoned => 0,
    AccountDeletionState.serviceDataCleared => 1,
    AccountDeletionState.securePasswordCleared => 2,
    AccountDeletionState.prefsDataCleared => 3,
    AccountDeletionState.profileDirectoryDeleted => 4,
    AccountDeletionState.accountDataDirectoryDeleted => 5,
    AccountDeletionState.currentAccountCleared => 6,
    AccountDeletionState.privacyResidueCleared => 7,
    AccountDeletionState.accountRegistryRemoved => 8,
  };

  bool hasCompleted(AccountDeletionState completedState) {
    return deletionOrder >= completedState.deletionOrder;
  }
}

final class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure({
    required this.toxId,
    required this.stage,
    required this.cause,
    required this.stackTrace,
  });

  final String toxId;
  final AccountDeletionStage stage;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'Account deletion failed stage=${stage.name} '
        '${SafeDiagnostics.describeError(cause)}';
  }
}

final class AccountDeletionResult {
  const AccountDeletionResult._({required this.toxId, this.failure});

  const AccountDeletionResult.completed(String toxId) : this._(toxId: toxId);

  const AccountDeletionResult.pending({
    required String toxId,
    required AccountDeletionFailure failure,
  }) : this._(toxId: toxId, failure: failure);

  final String toxId;
  final AccountDeletionFailure? failure;

  bool get completed => failure == null;
  bool get isPending => failure != null;

  @override
  String toString() {
    final pendingFailure = failure;
    if (pendingFailure == null) {
      return 'AccountDeletionResult(completed=true)';
    }
    return 'AccountDeletionResult(completed=false '
        'stage=${pendingFailure.stage.name} '
        '${SafeDiagnostics.describeError(pendingFailure.cause)})';
  }
}

final class AccountDeletionInProgressException implements Exception {
  const AccountDeletionInProgressException(this.toxId);

  final String toxId;

  @override
  String toString() {
    return 'Account deletion in progress status=pending';
  }
}

final class AccountDeletionTombstone {
  const AccountDeletionTombstone({
    required this.toxId,
    required this.state,
    required this.requestedAt,
    required this.updatedAt,
    required this.deletedCurrentAccount,
    this.failureStage,
    this.failureDescription,
  });

  factory AccountDeletionTombstone.initial({
    required String toxId,
    bool deletedCurrentAccount = false,
  }) {
    final now = DateTime.now().toUtc();
    return AccountDeletionTombstone(
      toxId: toxId,
      state: AccountDeletionState.tombstoned,
      requestedAt: now,
      updatedAt: now,
      deletedCurrentAccount: deletedCurrentAccount,
    );
  }

  final String toxId;
  final AccountDeletionState state;
  final DateTime requestedAt;
  final DateTime updatedAt;
  final bool deletedCurrentAccount;
  final AccountDeletionStage? failureStage;
  final String? failureDescription;

  AccountDeletionTombstone markCompleted(AccountDeletionState nextState) {
    return AccountDeletionTombstone(
      toxId: toxId,
      state: nextState,
      requestedAt: requestedAt,
      updatedAt: DateTime.now().toUtc(),
      deletedCurrentAccount: deletedCurrentAccount,
    );
  }

  AccountDeletionTombstone markFailure(AccountDeletionFailure failure) {
    return AccountDeletionTombstone(
      toxId: toxId,
      state: state,
      requestedAt: requestedAt,
      updatedAt: DateTime.now().toUtc(),
      deletedCurrentAccount: deletedCurrentAccount,
      failureStage: failure.stage,
      failureDescription: SafeDiagnostics.describeError(failure.cause),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'toxId': toxId,
    'state': state.name,
    'requestedAt': requestedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedCurrentAccount': deletedCurrentAccount,
    if (failureStage != null) 'failureStage': failureStage!.name,
    if (failureDescription != null) 'failureDescription': failureDescription,
  };

  static AccountDeletionTombstone fromJson(Map<String, dynamic> json) {
    final rawState = json['state'] as String?;
    final state = AccountDeletionState.values.firstWhere(
      (value) => value.name == rawState,
      orElse: () =>
          throw StateError('Unknown account deletion state: $rawState'),
    );
    final rawFailureStage = json['failureStage'] as String?;
    return AccountDeletionTombstone(
      toxId: json['toxId'] as String,
      state: state,
      requestedAt: DateTime.parse(json['requestedAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedCurrentAccount: json['deletedCurrentAccount'] as bool? ?? false,
      failureStage: rawFailureStage == null
          ? null
          : AccountDeletionStage.values.firstWhere(
              (value) => value.name == rawFailureStage,
              orElse: () => AccountDeletionStage.tombstone,
            ),
      failureDescription: json['failureDescription'] as String?,
    );
  }
}

abstract final class AccountDeletionJournalStore {
  AccountDeletionJournalStore._();

  static const _directoryName = 'account_deletion_tombstones';

  static Future<AccountDeletionTombstone?> read(String toxId) async {
    final tombstones = await readAll();
    for (final tombstone in tombstones) {
      if (compareToxIds(tombstone.toxId, toxId)) return tombstone;
    }
    return null;
  }

  /// Every readable tombstone.
  ///
  /// UNREADABLE FILES ARE QUARANTINED, NOT FATAL. This used to abort the whole
  /// scan on the first file it could not parse, and that scan sits on three hot
  /// paths: cold-start recovery, `throwIfDeleting` (every login and every
  /// account switch), and `clear`. So one stray or truncated `.json` in this
  /// directory blocked deletion recovery, blocked every login, and — because
  /// cold-start recovery runs before `runApp` — left a black screen.
  ///
  /// A tombstone we cannot parse tells us nothing about which account it names,
  /// so it cannot gate anything: keeping it would block every account forever
  /// rather than the one it was about. It is renamed to `.corrupt` (preserved,
  /// not deleted — it is the only record that a deletion was in progress) and
  /// reported through [quarantined] so the caller can surface it.
  static Future<List<AccountDeletionTombstone>> readAll() async {
    final dir = await _directory();
    if (!await dir.exists()) return const <AccountDeletionTombstone>[];
    final tombstones = <AccountDeletionTombstone>[];
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final decoded = json.decode(await entry.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(
            'Account deletion tombstone is not an object',
          );
        }
        tombstones.add(AccountDeletionTombstone.fromJson(decoded));
      } catch (e) {
        // A rebuilt tombstone must join THIS scan's results. The directory
        // listing is already in flight, so it would otherwise be invisible until
        // the next scan — and `hasPendingForToxId` answers from this call, which
        // is precisely the gate we are rebuilding.
        final rebuilt = await _quarantine(entry, e);
        if (rebuilt != null) tombstones.add(rebuilt);
      }
    }
    return tombstones;
  }

  /// Quarantined files whose account could NOT be identified, by basename.
  ///
  /// This is the only genuinely unsafe case: an unreadable record that we cannot
  /// attribute means an account somewhere may be half-deleted and nothing gates
  /// it. Startup consults this and refuses to expose any account rather than
  /// guess — see `AppBootstrap.recoverPendingRestoreBeforeAccountExposure`.
  ///
  /// Attributable corruption does NOT land here: [_quarantine] rebuilds a
  /// minimal tombstone from the filename, so the gate survives.
  static Set<String> get unattributableQuarantine =>
      Set.unmodifiable(_unattributable);
  static final Set<String> _unattributable = <String>{};

  @visibleForTesting
  static void resetQuarantineState() => _unattributable.clear();

  /// Filenames are `<sanitized toxId>.json` (see [_fileForTombstone]), and the
  /// sanitizer only rewrites characters a hex Tox ID does not contain — so for
  /// any tombstone this code wrote, the basename IS the account id.
  static final RegExp _toxIdFileName = RegExp(r'^[A-Fa-f0-9]{16,76}$');

  /// Move an unparseable tombstone aside, and REPLACE the gate it was providing.
  ///
  /// Renaming alone was not enough. `hasPendingForToxId` is what stops a
  /// half-deleted account being opened, and it answers from these files — so
  /// dropping a corrupt `<toxId>.json` made that account readable again from
  /// this startup onward, even though its deletion may have stopped after the
  /// password was removed but before the profile was. The bytes survived; the
  /// usable record did not.
  ///
  /// The filename still identifies the account, so a minimal tombstone is
  /// written in its place. Re-running the deletion from stage 0 is safe: every
  /// stage is idempotent (delete-if-exists, remove-if-present).
  ///
  /// When the name cannot be attributed, the account is unknown and no gate can
  /// be rebuilt — that is recorded in [unattributableQuarantine] for startup to
  /// refuse on.
  /// Returns the rebuilt tombstone when the account could be identified, so the
  /// caller can include it in the scan it is already performing.
  static Future<AccountDeletionTombstone?> _quarantine(
    File entry,
    Object cause,
  ) async {
    final name = p.basename(entry.path);
    final candidate = name.endsWith('.json')
        ? name.substring(0, name.length - '.json'.length)
        : '';
    final attributable = _toxIdFileName.hasMatch(candidate);
    SafeDiagnostics.logFailure(
      '[AccountDeletionJournalStore] unreadable tombstone '
      '(attributable=$attributable)',
      cause,
    );
    var renamed = false;
    try {
      await entry.rename('${entry.path}.corrupt');
      renamed = true;
    } catch (renameError) {
      SafeDiagnostics.logFailure(
        '[AccountDeletionJournalStore] could not move the unreadable tombstone '
        'aside',
        renameError,
      );
    }
    if (!attributable) {
      _unattributable.add(name);
      return null;
    }
    // Rebuild the gate. If the rename failed the original is still in place and
    // writing now would clobber the corrupt bytes we are trying to preserve, so
    // only do this once it is safely aside.
    if (!renamed) return null;
    final rebuilt = AccountDeletionTombstone.initial(toxId: candidate);
    try {
      await write(rebuilt);
      AppLogger.warn(
        '[AccountDeletionJournalStore] rebuilt a minimal tombstone from the '
        'filename so the deletion gate survives; recovery will re-run the '
        'stages (all idempotent)',
      );
      return rebuilt;
    } catch (writeError) {
      // Could not rebuild it either. Treat as unattributable: something must
      // refuse to expose accounts rather than proceed with no gate at all.
      _unattributable.add(name);
      SafeDiagnostics.logFailure(
        '[AccountDeletionJournalStore] could not rebuild the tombstone; '
        'startup will refuse to expose any account',
        writeError,
      );
      return null;
    }
  }

  static Future<bool> hasPendingForToxId(String toxId) async {
    return (await read(toxId)) != null;
  }

  static Future<void> write(AccountDeletionTombstone tombstone) async {
    final file = await _fileForTombstone(tombstone.toxId);
    await writeBytesAtomically(
      file,
      utf8.encode(jsonEncode(tombstone.toJson())),
    );
  }

  static Future<void> clear(String toxId) async {
    final dir = await _directory();
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      // Same policy as `readAll`: a file we cannot parse must not abort the
      // sweep, or one bad file would keep a COMPLETED deletion's tombstone
      // alive forever and re-run its stages on every cold start.
      AccountDeletionTombstone tombstone;
      try {
        final decoded = json.decode(await entry.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        tombstone = AccountDeletionTombstone.fromJson(decoded);
      } catch (e) {
        // The rebuilt tombstone (if any) is deliberately ignored here: `clear`
        // is removing records for [toxId], and a record it could not read is not
        // one it can claim to have cleared.
        await _quarantine(entry, e);
        continue;
      }
      if (compareToxIds(tombstone.toxId, toxId)) {
        await entry.delete();
      }
    }
  }

  static Future<Directory> _directory() async {
    final root = await AppPaths.applicationSupportPath;
    return Directory(p.join(root, _directoryName));
  }

  static Future<File> _fileForTombstone(String toxId) async {
    final dir = await _directory();
    final safeName = toxId.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(dir.path, '$safeName.json'));
  }
}
