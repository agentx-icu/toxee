import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../prefs.dart';
import '../tox_utils.dart';
import 'atomic_file_write.dart';
import 'backup_path_safety.dart';

enum RestoreTransactionState {
  staged,
  profileCommitted,
  accountDataCommitted,
  scopedPrefsApplied,
  accountRegistryVisible,
}

enum FullBackupRestoreFailurePoint {
  afterStaging,
  afterProfileCommit,
  afterAccountDataCommit,
  afterScopedPrefsApply,
  afterAccountRegistryVisible,
}

final class FullBackupRestoreCrashSimulation implements Exception {
  const FullBackupRestoreCrashSimulation(this.point);

  final FullBackupRestoreFailurePoint point;

  @override
  String toString() => 'FullBackupRestoreCrashSimulation: ${point.name}';
}

abstract final class FullBackupRestoreTestHooks {
  FullBackupRestoreTestHooks._();

  @visibleForTesting
  static FullBackupRestoreFailurePoint? crashAt;

  static String Function(Uint8List profileBytes)? profileIdentityExtractor;

  @visibleForTesting
  static void reset() {
    crashAt = null;
    profileIdentityExtractor = null;
  }

  static void maybeCrash(FullBackupRestoreFailurePoint point) {
    if (crashAt == point) {
      throw FullBackupRestoreCrashSimulation(point);
    }
  }
}

final class FullBackupRestoreInput {
  const FullBackupRestoreInput({
    required this.toxId,
    required this.nickname,
    required this.archive,
    required this.metadata,
    required this.toxProfile,
  });

  final String toxId;
  final String nickname;
  final Archive archive;
  final Map<String, dynamic> metadata;
  final Uint8List? toxProfile;
}

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

abstract final class FullBackupRestoreTransaction {
  FullBackupRestoreTransaction._();

  static Future<Map<String, dynamic>> restore(
    FullBackupRestoreInput input,
  ) async {
    await recoverPendingRestore();
    final paths = await _RestorePaths.resolve(input.toxId);
    _validateArchivePaths(input.archive, paths);
    final scopedPrefs = _portableScopedPrefs(input.metadata, paths);
    await _preflight(input.toxId, paths);

    var journal = RestoreTransactionJournal(
      transactionId: paths.transactionId,
      toxId: input.toxId,
      state: RestoreTransactionState.staged,
      profileStageDir: paths.profileStageDir,
      profileFinalDir: paths.profileFinalDir,
      accountDataStageDir: paths.accountDataStageDir,
      accountDataFinalDir: paths.accountDataFinalDir,
      hasProfile: input.toxProfile != null,
    );
    await RestoreTransactionJournalStore.write(journal);

    try {
      await _stagePayload(input, paths);
      FullBackupRestoreTestHooks.maybeCrash(
        FullBackupRestoreFailurePoint.afterStaging,
      );

      if (input.toxProfile != null) {
        await _renameDirectory(paths.profileStageDir, paths.profileFinalDir);
      }
      journal = journal.copyWith(
        state: RestoreTransactionState.profileCommitted,
      );
      await RestoreTransactionJournalStore.write(journal);
      FullBackupRestoreTestHooks.maybeCrash(
        FullBackupRestoreFailurePoint.afterProfileCommit,
      );

      await _renameDirectory(
        paths.accountDataStageDir,
        paths.accountDataFinalDir,
      );
      journal = journal.copyWith(
        state: RestoreTransactionState.accountDataCommitted,
      );
      await RestoreTransactionJournalStore.write(journal);
      FullBackupRestoreTestHooks.maybeCrash(
        FullBackupRestoreFailurePoint.afterAccountDataCommit,
      );

      if (scopedPrefs.isNotEmpty) {
        await Prefs.importScopedPrefsForAccount(input.toxId, scopedPrefs);
      }
      journal = journal.copyWith(
        state: RestoreTransactionState.scopedPrefsApplied,
      );
      await RestoreTransactionJournalStore.write(journal);
      FullBackupRestoreTestHooks.maybeCrash(
        FullBackupRestoreFailurePoint.afterScopedPrefsApply,
      );

      return <String, dynamic>{
        'toxId': input.toxId,
        'nickname': input.nickname,
        'toxProfile': input.toxProfile,
      };
    } catch (e) {
      if (e is FullBackupRestoreCrashSimulation) rethrow;
      await rollbackPendingRestore(toxId: input.toxId);
      rethrow;
    }
  }

  static Future<void> finalizePendingRestore({required String toxId}) async {
    var journal = await RestoreTransactionJournalStore.read();
    if (journal == null) return;
    if (!compareToxIds(journal.toxId, toxId)) {
      throw StateError('Pending restore belongs to a different account');
    }
    if (!await _dataCommitted(journal)) {
      throw StateError('Cannot finalize incomplete full-backup restore');
    }
    if (await Prefs.getAccountByToxId(toxId) == null) {
      throw StateError('Cannot finalize before account registry is visible');
    }
    journal = journal.copyWith(
      state: RestoreTransactionState.accountRegistryVisible,
    );
    await RestoreTransactionJournalStore.write(journal);
    FullBackupRestoreTestHooks.maybeCrash(
      FullBackupRestoreFailurePoint.afterAccountRegistryVisible,
    );
    await RestoreTransactionJournalStore.clear();
  }

  static Future<void> rollbackPendingRestore({String? toxId}) async {
    final journal = await RestoreTransactionJournalStore.read();
    if (journal == null) return;
    if (toxId != null && !compareToxIds(journal.toxId, toxId)) {
      throw StateError('Pending restore belongs to a different account');
    }
    await _rollback(journal);
  }

  static Future<void> recoverPendingRestore() async {
    final journal = await RestoreTransactionJournalStore.read();
    if (journal == null) return;
    final accountVisible = await Prefs.getAccountByToxId(journal.toxId) != null;
    if (accountVisible && await _dataCommitted(journal)) {
      await RestoreTransactionJournalStore.clear();
      return;
    }
    await _rollback(journal);
  }

  static Future<void> _preflight(String toxId, _RestorePaths paths) async {
    if (await Prefs.getAccountByToxId(toxId) != null) {
      throw StateError('Account already exists');
    }
    if ((await Prefs.exportScopedPrefsForAccount(toxId)).isNotEmpty) {
      throw StateError('Account scoped preferences already exist');
    }
    for (final path in <String>[
      paths.profileFinalDir,
      paths.accountDataFinalDir,
      paths.profileStageDir,
      paths.accountDataStageDir,
    ]) {
      if (await Directory(path).exists()) {
        throw StateError('Restore destination already exists: $path');
      }
    }
  }

  static Future<void> _stagePayload(
    FullBackupRestoreInput input,
    _RestorePaths paths,
  ) async {
    if (input.toxProfile != null) {
      await Directory(paths.profileStageDir).create(recursive: true);
      final profileFile = File(
        AppPaths.profileFileInDirectory(paths.profileStageDir),
      );
      await profileFile.writeAsBytes(input.toxProfile!, flush: true);
    }
    await Directory(paths.accountDataStageDir).create(recursive: true);

    for (final entry in input.archive.files) {
      if (!entry.isFile) continue;
      if (entry.name.startsWith('chat_history/')) {
        final relativePath = entry.name.substring('chat_history/'.length);
        if (relativePath.isEmpty) continue;
        final targetPath = safeBackupRestorePath(
          baseDir: p.join(paths.accountDataStageDir, 'chat_history'),
          relativePath: relativePath,
        );
        await _writeEntry(File(targetPath), entry);
      } else if (entry.name.startsWith('avatars/')) {
        final relativePath = entry.name.substring('avatars/'.length);
        if (relativePath.isEmpty) continue;
        final targetPath = safeBackupRestorePath(
          baseDir: p.join(paths.accountDataStageDir, 'avatars'),
          relativePath: relativePath,
        );
        await _writeEntry(File(targetPath), entry);
      }
    }

    final queueFile = input.archive.findFile('offline_message_queue.json');
    if (queueFile != null) {
      await _writeEntry(
        File(p.join(paths.accountDataStageDir, 'offline_message_queue.json')),
        queueFile,
      );
    }
  }

  static Map<String, dynamic> _portableScopedPrefs(
    Map<String, dynamic> metadata,
    _RestorePaths paths,
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
              baseDir: paths.accountDataFinalDir,
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

  static void _validateArchivePaths(Archive archive, _RestorePaths paths) {
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      if (entry.name.startsWith('chat_history/')) {
        final relativePath = entry.name.substring('chat_history/'.length);
        if (relativePath.isNotEmpty) {
          safeBackupRestorePath(
            baseDir: p.join(paths.accountDataFinalDir, 'chat_history'),
            relativePath: relativePath,
          );
        }
      } else if (entry.name.startsWith('avatars/')) {
        final relativePath = entry.name.substring('avatars/'.length);
        if (relativePath.isNotEmpty) {
          safeBackupRestorePath(
            baseDir: p.join(paths.accountDataFinalDir, 'avatars'),
            relativePath: relativePath,
          );
        }
      }
    }
  }

  static Future<void> _renameDirectory(
    String source,
    String destination,
  ) async {
    // Atomicity is per root only: staging lives under this destination's
    // parent so this rename is same-filesystem, while cross-root consistency is
    // provided by the durable journal and recovery path.
    if (await Directory(destination).exists()) {
      throw StateError('Restore destination already exists: $destination');
    }
    await Directory(p.dirname(destination)).create(recursive: true);
    await Directory(source).rename(destination);
  }

  static Future<void> _writeEntry(File targetFile, ArchiveFile entry) async {
    await targetFile.parent.create(recursive: true);
    final bytes = Uint8List.fromList(entry.content as List<int>);
    await targetFile.writeAsBytes(bytes, flush: true);
  }

  static Future<bool> _dataCommitted(RestoreTransactionJournal journal) async {
    if (journal.hasProfile) {
      final profilePath = AppPaths.profileFileInDirectory(
        journal.profileFinalDir,
      );
      if (!await File(profilePath).exists()) return false;
    }
    return Directory(journal.accountDataFinalDir).exists();
  }

  static Future<void> _rollback(RestoreTransactionJournal journal) async {
    await _deleteDirectory(journal.profileStageDir);
    await _deleteDirectory(journal.accountDataStageDir);
    await _deleteDirectory(journal.profileFinalDir);
    await _deleteDirectory(journal.accountDataFinalDir);
    await Prefs.clearScopedKeysForAccount(journal.toxId);
    await Prefs.removeAccount(journal.toxId);
    await RestoreTransactionJournalStore.clear();
  }

  static Future<void> _deleteDirectory(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

final class _RestorePaths {
  const _RestorePaths({
    required this.transactionId,
    required this.profileStageDir,
    required this.profileFinalDir,
    required this.accountDataStageDir,
    required this.accountDataFinalDir,
  });

  final String transactionId;
  final String profileStageDir;
  final String profileFinalDir;
  final String accountDataStageDir;
  final String accountDataFinalDir;

  static Future<_RestorePaths> resolve(String toxId) async {
    final profileFinalDir = await AppPaths.getProfileDirectoryForToxId(toxId);
    final accountDataFinalDir = await AppPaths.getAccountDataRoot(toxId);
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final transactionId = DateTime.now().microsecondsSinceEpoch.toString();
    return _RestorePaths(
      transactionId: transactionId,
      profileFinalDir: profileFinalDir,
      accountDataFinalDir: accountDataFinalDir,
      profileStageDir: p.join(
        p.dirname(profileFinalDir),
        '.full_backup_restore_profile_${prefix}_$transactionId',
      ),
      accountDataStageDir: p.join(
        p.dirname(accountDataFinalDir),
        '.full_backup_restore_data_${prefix}_$transactionId',
      ),
    );
  }
}
