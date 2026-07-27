// Full-backup `.zip` import / export.
//
// Contains:
//   - exportFullBackup — bundle tox_profile.tox + chat_history/ +
//     offline_message_queue.json + avatars/ + metadata.json into one zip.
//   - readFullBackupMetadata — read just enough of a zip to learn the
//     account's toxId + nickname (used for collision checks before any
//     disk writes happen).
//   - importFullBackup — restore a backup zip onto disk.
//
// The .tox single-file path lives in tox_file_io.dart; this module
// delegates to importAccountData when given a .tox extension.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../logger.dart';
import '../mobile_export_policy.dart';
import '../prefs.dart';
import '../tox_utils.dart';
import 'atomic_file_write.dart';
import 'full_backup_crypto.dart';
import 'restore_transaction.dart';
import 'tox_file_io.dart';

/// Current full-backup metadata schema version. Bump when the on-disk
/// `metadata.json` layout or scoped-prefs key set changes in a
/// non-backward-compatible way. Backups without `formatVersion` are treated
/// as v1 for legacy compatibility (older toxee builds shipped without it).
const int _kBackupFormatVersion = fullBackupEncryptedFormatVersion;
final RegExp _backupToxIdPattern = RegExp(
  r'^[A-Fa-f0-9]{64}([A-Fa-f0-9]{12})?$',
);

String? _metadataToxId(Map<String, dynamic> metadata) {
  final rawToxId = metadata['toxId'];
  if (rawToxId == null) return null;
  if (rawToxId is! String || !_backupToxIdPattern.hasMatch(rawToxId.trim())) {
    throw FormatException('Invalid backup metadata toxId: $rawToxId');
  }
  return rawToxId.trim();
}

String _extractProfileToxId(Uint8List toxProfile) {
  final testExtractor = FullBackupRestoreTestHooks.profileIdentityExtractor;
  if (testExtractor != null) return testExtractor(toxProfile);
  return extractToxIdFromProfile(toxProfile);
}

void _requireProfileMatchesMetadata({
  required String metadataToxId,
  required Uint8List toxProfile,
}) {
  final profileToxId = _extractProfileToxId(toxProfile);
  if (!compareToxIds(metadataToxId, profileToxId)) {
    throw StateError('Backup metadata toxId does not match tox_profile.tox');
  }
}

/// Export a comprehensive .zip backup containing:
/// - `tox_profile.tox` (the Tox identity/profile, optionally encrypted)
/// - `chat_history/` (all JSON chat history files)
/// - `offline_message_queue.json`
/// - `avatars/` (per-account avatars)
/// - `metadata.json` (scoped prefs: pinned, muted, groups, friend metadata, etc.)
///
/// Archive-internal relative path (entry names and `@account_data/` metadata
/// values): ALWAYS '/'-separated regardless of host OS. `p.relative` returns
/// '\'-separated paths on Windows, and the import side
/// (safeBackupRestorePath) rightly REJECTS backslashes as unsafe — so a
/// Windows-exported backup would silently drop its nested chat history /
/// avatar entries on restore. Portability is the whole point of the format.
String _archiveRelative(String absPath, {required String from}) =>
    p.url.joinAll(p.split(p.relative(absPath, from: from)));

/// Returns the path to the exported .zip file.
Future<String> exportFullBackup({
  required String toxId,
  String? password,
  String? filePath,
}) async {
  if (toxId.isEmpty) {
    throw ArgumentError('toxId cannot be empty');
  }
  requireFullBackupExportPassword(password);

  final normalizedToxId = toxId.trim();
  final account = await Prefs.getAccountByToxId(normalizedToxId);
  final nickname = account?['nickname'] ?? '';

  final archive = Archive();

  // 1. Add tox_profile.tox (try primary and fallback paths)
  final resolvedToxPath = await AppPaths.resolveToxProfilePath(normalizedToxId);
  if (resolvedToxPath != null) {
    final profileData = await File(resolvedToxPath).readAsBytes();
    archive.addFile(
      ArchiveFile('tox_profile.tox', profileData.length, profileData),
    );
  }

  // 2. Add chat_history/ directory
  try {
    final historyDir = await AppPaths.getAccountChatHistoryPath(
      normalizedToxId,
    );
    final historyDirectory = Directory(historyDir);
    if (await historyDirectory.exists()) {
      await for (final entity in historyDirectory.list(recursive: true)) {
        if (entity is File) {
          final relativePath = _archiveRelative(entity.path, from: historyDir);
          final data = await entity.readAsBytes();
          archive.addFile(
            ArchiveFile('chat_history/$relativePath', data.length, data),
          );
        }
      }
    }
  } catch (e) {
    AppLogger.logError('Full backup: Error adding chat_history', e, null);
  }

  // 3. Add offline_message_queue.json
  try {
    final queuePath = await AppPaths.getAccountOfflineQueueFilePath(
      normalizedToxId,
    );
    final queueFile = File(queuePath);
    if (await queueFile.exists()) {
      final data = await queueFile.readAsBytes();
      archive.addFile(
        ArchiveFile('offline_message_queue.json', data.length, data),
      );
    }
  } catch (e) {
    AppLogger.logError('Full backup: Error adding offline queue', e, null);
  }

  // 3.5 Add avatars/ directory
  try {
    final avatarsDir = await AppPaths.getAccountAvatarsPath(normalizedToxId);
    final avatarsDirectory = Directory(avatarsDir);
    if (await avatarsDirectory.exists()) {
      await for (final entity in avatarsDirectory.list(recursive: true)) {
        if (entity is File) {
          final relativePath = _archiveRelative(entity.path, from: avatarsDir);
          final data = await entity.readAsBytes();
          archive.addFile(
            ArchiveFile('avatars/$relativePath', data.length, data),
          );
        }
      }
    }
  } catch (e) {
    AppLogger.logError('Full backup: Error adding avatars', e, null);
  }

  // 4. Add metadata.json (scoped prefs)
  try {
    final scopedPrefs = await Prefs.exportScopedPrefsForAccount(
      normalizedToxId,
    );

    // 4a. Discover missing friend_avatar_path entries from avatars directory.
    // Avatar files may exist on disk but have no corresponding pref key
    // (e.g. migrated from global dir, or pref was never saved).
    final avatarsDir = await AppPaths.getAccountAvatarsPath(normalizedToxId);
    final avatarsDirectory = Directory(avatarsDir);
    if (await avatarsDirectory.exists()) {
      await for (final entity in avatarsDirectory.list()) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          // Match the friend avatar naming used by FriendAssetCleanup and the
          // receive path: friend_<id>_avatar_<timestamp>.<ext>. Older backups
          // may also have friend_<id>_avatar or friend_<id>_avatar.<ext>.
          final match = RegExp(
            r'^friend_([A-Fa-f0-9]{64}(?:[A-Fa-f0-9]{12})?)_avatar(?:[_\.].*)?$',
          ).firstMatch(fileName);
          if (match != null) {
            final friendId = normalizeToxId(match.group(1)!);
            final pathKey = 'friend_avatar_path_$friendId';
            if (!scopedPrefs.containsKey(pathKey)) {
              // Add discovered avatar path
              scopedPrefs[pathKey] = entity.path;
            }
          }
        }
      }
    }

    // 4b. Convert absolute avatar paths to relative paths for portability.
    // On import, these will be converted back to the target machine's paths.
    final accountDataRoot = await AppPaths.getAccountDataRoot(normalizedToxId);
    final accountAvatarsDir = await AppPaths.getAccountAvatarsPath(
      normalizedToxId,
    );
    for (final key in scopedPrefs.keys.toList()) {
      if (key.contains('avatar_path') && scopedPrefs[key] is String) {
        final absPath = scopedPrefs[key] as String;
        if (absPath.startsWith(accountDataRoot)) {
          // Path is under per-account data root — convert directly
          scopedPrefs[key] =
              '@account_data/${_archiveRelative(absPath, from: accountDataRoot)}';
        } else {
          // Path may be in the global avatars dir or elsewhere.
          // If the same filename exists in per-account avatars dir, normalize it.
          final fileName = p.basename(absPath);
          final accountPath = p.join(accountAvatarsDir, fileName);
          if (await File(accountPath).exists()) {
            scopedPrefs[key] = '@account_data/avatars/$fileName';
          } else {
            // Not portable: the file lives outside the account data we
            // archive, so its absolute path would dangle (or point at a
            // foreign location) on any other machine. Drop the pref so the
            // avatar falls back to default on restore instead.
            scopedPrefs.remove(key);
          }
        }
      }
    }

    // Also include account info. `formatVersion` lets a future schema bump
    // detect and refuse incompatible backups instead of silently importing
    // mis-shaped scoped prefs.
    final metadata = <String, dynamic>{
      'formatVersion': _kBackupFormatVersion,
      'toxId': normalizedToxId,
      'nickname': nickname,
      'statusMessage': account?['statusMessage'] ?? '',
      'exportDate': DateTime.now().toIso8601String(),
      'scopedPrefs': scopedPrefs,
    };
    final metadataJson = const JsonEncoder.withIndent('  ').convert(metadata);
    final metadataBytes = utf8.encode(metadataJson);
    archive.addFile(
      ArchiveFile('metadata.json', metadataBytes.length, metadataBytes),
    );
  } catch (e) {
    AppLogger.logError('Full backup: Error adding metadata', e, null);
  }

  // 5. Encrypt the plaintext archive, then encode the outer archive to ZIP.
  final encryptedArchive = await encryptFullBackupArchive(
    plaintextArchive: archive,
    password: password!,
  );
  final zipData = ZipEncoder().encode(encryptedArchive);
  // Defensive guard: surface a clean error if encoding produced nothing,
  // so callers don't silently write a zero-byte backup file.
  // ignore: unnecessary_null_comparison
  if (zipData == null || zipData.isEmpty) {
    throw Exception('Export produced empty archive');
  }

  // 6. Determine file path
  String finalFilePath;
  if (filePath != null) {
    finalFilePath = filePath;
    if (!finalFilePath.toLowerCase().endsWith('.zip')) {
      finalFilePath = '$finalFilePath.zip';
    }
  } else {
    final downloadsDir = await AppPaths.getDownloadsPath();
    finalFilePath = p.join(downloadsDir, buildFullBackupExportFileName());
  }

  // 7. Write to file atomically.
  final exportFile = File(finalFilePath);
  await writeBytesAtomically(exportFile, zipData);
  AppLogger.log(
    'Full backup exported: $finalFilePath (${zipData.length} bytes)',
  );
  return finalFilePath;
}

/// Reads toxId and nickname from a .zip backup without writing to disk.
/// Use this to check account collisions before calling [importFullBackup].
/// Throws if file is not a valid zip or toxId cannot be determined.
Future<Map<String, String>> readFullBackupMetadata(
  String filePath, {
  String? password,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw Exception('File not found: $filePath');
  }
  final ext = p.extension(filePath).toLowerCase();
  if (ext != '.zip') {
    throw Exception('Not a .zip file: $filePath');
  }
  final fileData = await file.readAsBytes();
  if (fileData.isEmpty) {
    throw Exception('File is empty');
  }
  final outerArchive = ZipDecoder().decodeBytes(fileData);
  final archive = await openFullBackupArchive(
    outerArchive: outerArchive,
    password: password,
  );

  String? toxId;
  String nickname = '';

  final metadataFile = archive.findFile('metadata.json');
  if (metadataFile != null) {
    final metadata = readArchiveMetadata(archive);
    toxId = _metadataToxId(metadata);
    nickname = metadata['nickname'] as String? ?? '';
  }

  final profileFile = archive.findFile('tox_profile.tox');
  if (profileFile != null) {
    final toxProfile = Uint8List.fromList(profileFile.content as List<int>);
    if (toxId == null || toxId.isEmpty) {
      try {
        toxId = _extractProfileToxId(toxProfile);
      } catch (e) {
        AppLogger.logError(
          'readFullBackupMetadata: Error extracting toxId',
          e,
          null,
        );
      }
    } else {
      _requireProfileMatchesMetadata(
        metadataToxId: toxId,
        toxProfile: toxProfile,
      );
    }
  }

  if (toxId == null || toxId.isEmpty) {
    throw Exception('Could not determine Tox ID from backup');
  }
  return {'toxId': toxId, 'nickname': nickname};
}

/// Import a full backup from a .zip file.
///
/// Detects format: .tox files use the legacy [importAccountData] path;
/// .zip files are extracted and all components are restored.
///
/// Returns a map with `toxId`, `nickname`, and optionally `toxProfile`.
/// Call [readFullBackupMetadata] first and check for account collision
/// before calling this.
Future<Map<String, dynamic>> importFullBackup({
  required String filePath,
  String? password,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw Exception('File not found: $filePath');
  }

  // Check file extension
  final ext = p.extension(filePath).toLowerCase();
  if (ext == '.tox') {
    // Legacy .tox import
    return importAccountData(filePath: filePath, password: password);
  }

  // ZIP import
  final fileData = await file.readAsBytes();
  if (fileData.isEmpty) {
    throw Exception('File is empty');
  }

  final outerArchive = ZipDecoder().decodeBytes(fileData);
  final archive = await openFullBackupArchive(
    outerArchive: outerArchive,
    password: password,
  );

  // 1. Find and extract metadata.json
  Map<String, dynamic> metadata = {};
  String? toxId;
  String nickname = '';

  final metadataFile = archive.findFile('metadata.json');
  if (metadataFile != null) {
    metadata = readArchiveMetadata(archive);
    // Refuse backups produced by a newer toxee schema. Missing field is
    // treated as v1 (legacy backups predating the version field).
    final version = backupFormatVersion(metadata);
    if (version > _kBackupFormatVersion) {
      AppLogger.warn(
        '[full_backup] import refused: backup formatVersion=$version exceeds supported=$_kBackupFormatVersion',
      );
      throw Exception(
        'Backup format version $version is newer than this app supports '
        '($_kBackupFormatVersion). Upgrade the app to import this backup.',
      );
    }
    toxId = _metadataToxId(metadata);
    nickname = metadata['nickname'] as String? ?? '';
  }

  // 2. Extract tox_profile.tox and get toxId if not in metadata
  Uint8List? toxProfile;
  final profileFile = archive.findFile('tox_profile.tox');
  if (profileFile != null) {
    toxProfile = Uint8List.fromList(profileFile.content as List<int>);

    if (toxId == null || toxId.isEmpty) {
      // Extract toxId from profile
      try {
        toxId = _extractProfileToxId(toxProfile);
      } catch (e) {
        AppLogger.logError(
          'Full backup import: Error extracting toxId',
          e,
          null,
        );
      }
    } else {
      _requireProfileMatchesMetadata(
        metadataToxId: toxId,
        toxProfile: toxProfile,
      );
    }
  }

  if (toxId == null || toxId.isEmpty) {
    throw Exception('Could not determine Tox ID from backup');
  }

  return FullBackupRestoreTransaction.restore(
    FullBackupRestoreInput(
      toxId: toxId,
      nickname: nickname,
      archive: archive,
      metadata: metadata,
      toxProfile: toxProfile,
    ),
  );
}

Future<void> finalizeFullBackupImport({required String toxId}) {
  return FullBackupRestoreTransaction.finalizePendingRestore(toxId: toxId);
}

Future<void> rollbackPendingFullBackupRestore({String? toxId}) {
  return FullBackupRestoreTransaction.rollbackPendingRestore(toxId: toxId);
}

Future<void> recoverPendingFullBackupRestore() {
  return FullBackupRestoreTransaction.recoverPendingRestore();
}
