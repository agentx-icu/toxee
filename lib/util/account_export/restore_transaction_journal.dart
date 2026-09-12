import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_paths.dart';
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
  });

  final String transactionId;
  final String toxId;
  final RestoreTransactionState state;
  final String profileStageDir;
  final String profileFinalDir;
  final String accountDataStageDir;
  final String accountDataFinalDir;
  final bool hasProfile;

  RestoreTransactionJournal copyWith({RestoreTransactionState? state}) {
    return RestoreTransactionJournal(
      transactionId: transactionId,
      toxId: toxId,
      state: state ?? this.state,
      profileStageDir: profileStageDir,
      profileFinalDir: profileFinalDir,
      accountDataStageDir: accountDataStageDir,
      accountDataFinalDir: accountDataFinalDir,
      hasProfile: hasProfile,
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
    );
  }
}

abstract final class RestoreTransactionJournalStore {
  RestoreTransactionJournalStore._();

  static const _fileName = 'account_export_restore_journal.json';

  static Future<RestoreTransactionJournal?> read() async {
    final file = await _journalFile();
    if (!await file.exists()) return null;
    final decoded = json.decode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Restore journal is not a JSON object');
    }
    return RestoreTransactionJournal.fromJson(decoded);
  }

  static Future<void> write(RestoreTransactionJournal journal) async {
    final file = await _journalFile();
    final bytes = utf8.encode(jsonEncode(journal.toJson()));
    await writeBytesAtomically(file, bytes);
  }

  static Future<void> clear() async {
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
