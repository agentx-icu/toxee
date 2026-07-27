import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'account_export/atomic_file_write.dart';
import 'app_paths.dart';
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
    return 'Account deletion failed at ${stage.name} for $toxId: $cause';
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
      return 'AccountDeletionResult.completed($toxId)';
    }
    return 'AccountDeletionResult.pending($pendingFailure)';
  }
}

final class AccountDeletionInProgressException implements Exception {
  const AccountDeletionInProgressException(this.toxId);

  final String toxId;

  @override
  String toString() {
    return 'Account $toxId is being deleted; cleanup is pending and will retry.';
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
      failureDescription: failure.cause.toString(),
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

  static Future<List<AccountDeletionTombstone>> readAll() async {
    final dir = await _directory();
    if (!await dir.exists()) return const <AccountDeletionTombstone>[];
    final tombstones = <AccountDeletionTombstone>[];
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final decoded = json.decode(await entry.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Account deletion tombstone is not an object',
        );
      }
      tombstones.add(AccountDeletionTombstone.fromJson(decoded));
    }
    return tombstones;
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
      final decoded = json.decode(await entry.readAsString());
      if (decoded is! Map<String, dynamic>) continue;
      final tombstone = AccountDeletionTombstone.fromJson(decoded);
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
