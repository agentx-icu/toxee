import 'dart:convert';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'prefs.dart';
import 'app_paths.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'logger.dart';

/// Thrown by [AccountExportService.importAccountData] and
/// [AccountExportService.importFullBackup] when the source file is encrypted
/// and no password was supplied. Lets callers branch on a typed exception
/// instead of fragile string-matching the message.
class PasswordRequiredException implements Exception {
  const PasswordRequiredException([this.message = 'Password required for encrypted .tox file']);
  final String message;
  @override
  String toString() => 'PasswordRequiredException: $message';
}

/// Account export/import service for .tox file format (compatible with qTox)
class AccountExportService {
  // TOX_PASS_ENCRYPTION_EXTRA_LENGTH constant (80 bytes)
  static const int _toxPassEncryptionExtraLength = 80;

  /// Export account data to a .tox file
  /// 
  /// [toxId] - The Tox ID of the account to export
  /// [password] - Optional password for encryption. If provided, data will be encrypted using Tox standard encryption.
  /// [filePath] - Optional file path. If not provided, will use default naming: {nickname}_{toxId前8位}.tox
  /// 
  /// Returns the path to the exported file
  static Future<String> exportAccountData({
    required String toxId,
    String? password,
    String? filePath,
  }) async {
    if (toxId.isEmpty) {
      throw ArgumentError('toxId cannot be empty');
    }

    // Normalize toxId (trim whitespace, ensure consistent format)
    final normalizedToxId = toxId.trim();
    AppLogger.log(
        '[AccountExportService] Export: Looking for account with toxId: "$normalizedToxId" (length: ${normalizedToxId.length})');

    // Get account info - Prefs.getAccountByToxId now handles normalization
    var account = await Prefs.getAccountByToxId(normalizedToxId);
    
    // If not found, try to get from account list and find by partial match
    if (account == null) {
      AppLogger.log(
          '[AccountExportService] Export: Account not found by getAccountByToxId, checking account list manually...');
      final allAccounts = await Prefs.getAccountList();
      AppLogger.log(
          '[AccountExportService] Export: Found ${allAccounts.length} accounts in list');
      for (final acc in allAccounts) {
        final accToxId = acc['toxId']?.trim() ?? '';
        AppLogger.log(
            '[AccountExportService] Export: Checking account: toxId="$accToxId" (length: ${accToxId.length}), nickname="${acc['nickname']}"');
        // Try exact match
        if (accToxId == normalizedToxId) {
          account = acc;
          AppLogger.log(
              '[AccountExportService] Export: Found account by exact match');
          break;
        }
        // Try case-insensitive match
        if (accToxId.toLowerCase() == normalizedToxId.toLowerCase()) {
          account = acc;
          AppLogger.log(
              '[AccountExportService] Export: Found account by case-insensitive match');
          break;
        }
        // Try partial match (first 64 chars, as toxId might be longer)
        if (accToxId.length >= 64 && normalizedToxId.length >= 64) {
          if (accToxId.substring(0, 64) == normalizedToxId.substring(0, 64)) {
            account = acc;
            AppLogger.log(
                '[AccountExportService] Export: Found account by partial match (first 64 chars)');
            break;
          }
        }
      }
    }
    
    // If still not found, try to create account data from current session
    if (account == null) {
      AppLogger.log(
          '[AccountExportService] Export: Account still not found, attempting to create from current session data...');
      // Try to get nickname and status from Prefs (backward compatibility)
      final nickname = await Prefs.getNickname();
      final statusMessage = await Prefs.getStatusMessage();

      if (nickname != null && nickname.isNotEmpty) {
        // Create account data from current session
        account = {
          'toxId': normalizedToxId,
          'nickname': nickname,
          'statusMessage': statusMessage ?? '',
          'autoLogin': 'true',
          'autoAcceptFriends': 'false',
          'notificationSoundEnabled': 'true',
          'lastLoginTime': DateTime.now().toIso8601String(),
        };
        AppLogger.log(
            '[AccountExportService] Export: Created account data from current session: nickname="$nickname"');
      } else {
        // Last resort: create minimal account data
        account = {
          'toxId': normalizedToxId,
          'nickname': 'Exported Account',
          'statusMessage': '',
          'autoLogin': 'true',
          'autoAcceptFriends': 'false',
          'notificationSoundEnabled': 'true',
          'lastLoginTime': DateTime.now().toIso8601String(),
        };
        AppLogger.log(
            '[AccountExportService] Export: Created minimal account data');
      }
    } else {
      AppLogger.log(
          '[AccountExportService] Export: Found account: nickname="${account['nickname']}"');
    }
    
    final nickname = account['nickname'] ?? '';
    final toxIdPrefix = normalizedToxId.length >= 8 ? normalizedToxId.substring(0, 8) : normalizedToxId;

    // Read tox profile file (try primary and fallback paths)
    Uint8List toxProfileData;
    try {
      final resolvedPath = await AppPaths.resolveToxProfilePath(normalizedToxId);
      if (resolvedPath == null) {
        final primaryDir = await AppPaths.getProfileDirectoryForToxId(normalizedToxId);
        final primaryPath = AppPaths.profileFileInDirectory(primaryDir);
        throw Exception(
          'Tox profile file not found. Tried: $primaryPath and fallback locations. '
          'Ensure this account has been used at least once on this device, or restore from a full backup.',
        );
      }
      final toxProfileFile = File(resolvedPath);
      toxProfileData = await toxProfileFile.readAsBytes();
      if (toxProfileData.isEmpty) {
        throw Exception('Tox profile file is empty');
      }
      AppLogger.log(
          '[AccountExportService] Export: Read tox profile from $resolvedPath: ${toxProfileData.length} bytes');
    } catch (e, stackTrace) {
      AppLogger.logError('Export: Error reading tox profile file', e, stackTrace);
      rethrow;
    }

    // Encrypt if password is provided
    Uint8List finalData;
    if (password != null && password.isNotEmpty) {
      AppLogger.log('[AccountExportService] Export: Encrypting with password...');
      try {
        final ffiLib = Tim2ToxFfi.open();
        final passwordBytes = utf8.encode(password);
        final plaintextPtr = pkgffi.malloc<ffi.Uint8>(toxProfileData.length);
        final ciphertextPtr = pkgffi.malloc<ffi.Uint8>(toxProfileData.length + _toxPassEncryptionExtraLength);
        final passwordPtr = pkgffi.malloc<ffi.Uint8>(passwordBytes.length);
        
        try {
          // Copy data to native memory
          plaintextPtr.asTypedList(toxProfileData.length).setAll(0, toxProfileData);
          passwordPtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
          
          // Encrypt
          final encryptedLen = ffiLib.passEncryptNative(
            plaintextPtr,
            toxProfileData.length,
            passwordPtr,
            passwordBytes.length,
            ciphertextPtr,
            toxProfileData.length + _toxPassEncryptionExtraLength,
          );
          
          if (encryptedLen < 0) {
            throw Exception('Encryption failed');
          }
          
          finalData = Uint8List.sublistView(ciphertextPtr.asTypedList(encryptedLen));
          AppLogger.log(
              '[AccountExportService] Export: Encrypted to ${finalData.length} bytes');
        } finally {
          pkgffi.malloc.free(plaintextPtr);
          pkgffi.malloc.free(ciphertextPtr);
          pkgffi.malloc.free(passwordPtr);
        }
      } catch (e, stackTrace) {
        AppLogger.logError('Export: Encryption error', e, stackTrace);
        rethrow;
      }
    } else {
      finalData = toxProfileData;
      AppLogger.log(
          '[AccountExportService] Export: No encryption, using plain profile');
    }

    // Determine file path
    String finalFilePath;
    if (filePath != null) {
      finalFilePath = filePath;
      // Ensure .tox extension
      if (!finalFilePath.toLowerCase().endsWith('.tox')) {
        finalFilePath = '$finalFilePath.tox';
      }
    } else {
      // Use default naming: {nickname}_{toxId前8位}.tox
      final safeNickname = _sanitizeFileName(nickname.isEmpty ? 'account' : nickname);
      final fileName = '${safeNickname}_$toxIdPrefix.tox';
      
      // Save to Downloads directory
      final downloadsDir = await AppPaths.getDownloadsPath();
      finalFilePath = p.join(downloadsDir, fileName);
    }

    // Write to file
    try {
      final exportFile = File(finalFilePath);
      
      // Ensure parent directory exists
      final parentDir = exportFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      
      await exportFile.writeAsBytes(finalData);
      AppLogger.log(
          '[AccountExportService] Account export successful: $finalFilePath (${finalData.length} bytes)');
      return finalFilePath;
    } catch (e, stackTrace) {
      AppLogger.logError('Error writing export file: Target path: $finalFilePath', e, stackTrace);
      rethrow;
    }
  }

  /// Import account data from a .tox file
  /// 
  /// [filePath] - Path to the .tox file
  /// [password] - Password if the file is encrypted
  /// 
  /// Returns a map with 'toxId' and 'toxProfile' (decrypted Uint8List)
  static Future<Map<String, dynamic>> importAccountData({
    required String filePath,
    String? password,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    // Read file as binary
    final fileData = await file.readAsBytes();
    if (fileData.isEmpty) {
      throw Exception('File is empty');
    }

    AppLogger.log(
        '[AccountExportService] Import: Read file: ${fileData.length} bytes');

    // Check if encrypted
    bool isEncrypted = false;
    if (fileData.length >= _toxPassEncryptionExtraLength) {
      try {
        final ffiLib = Tim2ToxFfi.open();
        final dataPtr = pkgffi.malloc<ffi.Uint8>(_toxPassEncryptionExtraLength);
        try {
          dataPtr.asTypedList(_toxPassEncryptionExtraLength).setAll(0, fileData.take(_toxPassEncryptionExtraLength).toList());
          final result = ffiLib.isDataEncryptedNative(dataPtr, _toxPassEncryptionExtraLength);
          isEncrypted = result == 1;
        } finally {
          pkgffi.malloc.free(dataPtr);
        }
      } catch (e, stackTrace) {
        AppLogger.logError('Import: Error checking encryption', e, stackTrace);
        // Continue, assume not encrypted
      }
    }

    AppLogger.log(
        '[AccountExportService] Import: File is ${isEncrypted ? "encrypted" : "not encrypted"}');

    // Decrypt if encrypted
    Uint8List decryptedData;
    if (isEncrypted) {
      if (password == null || password.isEmpty) {
        throw const PasswordRequiredException();
      }

      try {
        final ffiLib = Tim2ToxFfi.open();
        final ciphertextPtr = pkgffi.malloc<ffi.Uint8>(fileData.length);
        final plaintextPtr = pkgffi.malloc<ffi.Uint8>(fileData.length - _toxPassEncryptionExtraLength);
        final passwordBytes = utf8.encode(password);
        final passwordPtr = pkgffi.malloc<ffi.Uint8>(passwordBytes.length);
        
        try {
          // Copy data to native memory
          ciphertextPtr.asTypedList(fileData.length).setAll(0, fileData);
          passwordPtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
          
          // Decrypt
          final decryptedLen = ffiLib.passDecryptNative(
            ciphertextPtr,
            fileData.length,
            passwordPtr,
            passwordBytes.length,
            plaintextPtr,
            fileData.length - _toxPassEncryptionExtraLength,
          );
          
          if (decryptedLen < 0) {
            throw Exception('Decryption failed - incorrect password or corrupted file');
          }
          
          decryptedData = Uint8List.sublistView(plaintextPtr.asTypedList(decryptedLen));
          AppLogger.log(
              '[AccountExportService] Import: Decrypted to ${decryptedData.length} bytes');
        } finally {
          pkgffi.malloc.free(ciphertextPtr);
          pkgffi.malloc.free(plaintextPtr);
          pkgffi.malloc.free(passwordPtr);
        }
      } catch (e, stackTrace) {
        AppLogger.logError('Import: Decryption error', e, stackTrace);
        rethrow;
      }
    } else {
      decryptedData = fileData;
    }

    // Extract toxId from profile
    String toxId;
    try {
      final ffiLib = Tim2ToxFfi.open();
      final profilePtr = pkgffi.malloc<ffi.Uint8>(decryptedData.length);
      final toxIdBuffer = pkgffi.malloc<ffi.Int8>(128); // 64 hex chars + null terminator
      
      ffi.Pointer<ffi.Uint8>? passphrasePtr;
      try {
        profilePtr.asTypedList(decryptedData.length).setAll(0, decryptedData);
        
        if (isEncrypted && password != null) {
          final passwordBytes = utf8.encode(password);
          passphrasePtr = pkgffi.malloc<ffi.Uint8>(passwordBytes.length);
          passphrasePtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
        }
        
        final toxIdLen = ffiLib.extractToxIdFromProfileNative(
          profilePtr,
          decryptedData.length,
          passphrasePtr ?? ffi.Pointer<ffi.Uint8>.fromAddress(0),
          isEncrypted && password != null ? utf8.encode(password).length : 0,
          toxIdBuffer,
          128,
        );
        
        if (toxIdLen < 0) {
          throw Exception('Failed to extract Tox ID from profile');
        }
        
        toxId = toxIdBuffer.cast<pkgffi.Utf8>().toDartString(length: toxIdLen);
        AppLogger.log('[AccountExportService] Import: Extracted toxId: $toxId');
        
        if (passphrasePtr != null) {
          pkgffi.malloc.free(passphrasePtr);
        }
      } finally {
        pkgffi.malloc.free(profilePtr);
        pkgffi.malloc.free(toxIdBuffer);
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Import: Error extracting toxId', e, stackTrace);
      rethrow;
    }

    return {
      'toxId': toxId,
      'toxProfile': decryptedData,
    };
  }

  /// Check if a profile file (tox_profile.tox) is encrypted.
  static Future<bool> isProfileFileEncrypted(String profileFilePath) async {
    final file = File(profileFilePath);
    if (!await file.exists()) return false;
    final data = await file.readAsBytes();
    if (data.length < _toxPassEncryptionExtraLength) return false;
    try {
      final ffiLib = Tim2ToxFfi.open();
      final dataPtr = pkgffi.malloc<ffi.Uint8>(_toxPassEncryptionExtraLength);
      try {
        dataPtr.asTypedList(_toxPassEncryptionExtraLength).setAll(0, data.take(_toxPassEncryptionExtraLength).toList());
        return ffiLib.isDataEncryptedNative(dataPtr, _toxPassEncryptionExtraLength) == 1;
      } finally {
        pkgffi.malloc.free(dataPtr);
      }
    } catch (e) {
      return false;
    }
  }

  /// Encrypt a profile file in place (plain -> encrypted). Used after register or on logout.
  static Future<void> encryptProfileFile(String profileFilePath, String password) async {
    if (password.isEmpty) return;
    final file = File(profileFilePath);
    if (!await file.exists()) {
      throw Exception('Profile file not found: $profileFilePath');
    }
    final plainData = await file.readAsBytes();
    if (plainData.isEmpty) throw Exception('Profile file is empty');
    final ffiLib = Tim2ToxFfi.open();
    final plaintextPtr = pkgffi.malloc<ffi.Uint8>(plainData.length);
    final ciphertextPtr = pkgffi.malloc<ffi.Uint8>(plainData.length + _toxPassEncryptionExtraLength);
    final passwordBytes = utf8.encode(password);
    final passwordPtr = pkgffi.malloc<ffi.Uint8>(passwordBytes.length);
    try {
      plaintextPtr.asTypedList(plainData.length).setAll(0, plainData);
      passwordPtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
      final encryptedLen = ffiLib.passEncryptNative(
        plaintextPtr,
        plainData.length,
        passwordPtr,
        passwordBytes.length,
        ciphertextPtr,
        plainData.length + _toxPassEncryptionExtraLength,
      );
      if (encryptedLen < 0) throw Exception('Encryption failed');
      final encrypted = Uint8List.sublistView(ciphertextPtr.asTypedList(encryptedLen));
      await file.writeAsBytes(encrypted);
    } finally {
      pkgffi.malloc.free(plaintextPtr);
      pkgffi.malloc.free(ciphertextPtr);
      pkgffi.malloc.free(passwordPtr);
    }
  }

  /// Decrypt a profile file in place (encrypted -> plain). Used before init when account has password.
  static Future<void> decryptProfileFile(String profileFilePath, String password) async {
    if (password.isEmpty) throw ArgumentError('Password required to decrypt');
    final file = File(profileFilePath);
    if (!await file.exists()) {
      throw Exception('Profile file not found: $profileFilePath');
    }
    final fileData = await file.readAsBytes();
    if (fileData.isEmpty) throw Exception('Profile file is empty');
    final isEncrypted = await isProfileFileEncrypted(profileFilePath);
    if (!isEncrypted) return; // already plain
    final ffiLib = Tim2ToxFfi.open();
    final ciphertextPtr = pkgffi.malloc<ffi.Uint8>(fileData.length);
    final plaintextPtr = pkgffi.malloc<ffi.Uint8>(fileData.length - _toxPassEncryptionExtraLength);
    final passwordBytes = utf8.encode(password);
    final passwordPtr = pkgffi.malloc<ffi.Uint8>(passwordBytes.length);
    try {
      ciphertextPtr.asTypedList(fileData.length).setAll(0, fileData);
      passwordPtr.asTypedList(passwordBytes.length).setAll(0, passwordBytes);
      final decryptedLen = ffiLib.passDecryptNative(
        ciphertextPtr,
        fileData.length,
        passwordPtr,
        passwordBytes.length,
        plaintextPtr,
        fileData.length - _toxPassEncryptionExtraLength,
      );
      if (decryptedLen < 0) throw Exception('Decryption failed - incorrect password or corrupted file');
      final decrypted = Uint8List.sublistView(plaintextPtr.asTypedList(decryptedLen));
      await file.writeAsBytes(decrypted);
    } finally {
      pkgffi.malloc.free(ciphertextPtr);
      pkgffi.malloc.free(plaintextPtr);
      pkgffi.malloc.free(passwordPtr);
    }
  }

  /// Sanitize file name (remove invalid characters)
  static String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  // ---------------------------------------------------------------------------
  // Full backup (.zip) — profile + chat history + metadata
  // ---------------------------------------------------------------------------

  /// Export a comprehensive .zip backup containing:
  /// - `tox_profile.tox` (the Tox identity/profile, optionally encrypted)
  /// - `chat_history/` (all JSON chat history files)
  /// - `offline_message_queue.json`
  /// - `metadata.json` (scoped prefs: pinned, muted, groups, friend metadata, etc.)
  ///
  /// Returns the path to the exported .zip file.
  static Future<String> exportFullBackup({
    required String toxId,
    String? password,
    String? filePath,
  }) async {
    if (toxId.isEmpty) {
      throw ArgumentError('toxId cannot be empty');
    }

    final normalizedToxId = toxId.trim();
    final account = await Prefs.getAccountByToxId(normalizedToxId);
    final nickname = account?['nickname'] ?? '';

    final archive = Archive();

    // 1. Add tox_profile.tox (try primary and fallback paths)
    final resolvedToxPath = await AppPaths.resolveToxProfilePath(normalizedToxId);
    if (resolvedToxPath != null) {
      final profileData = await File(resolvedToxPath).readAsBytes();
      archive.addFile(ArchiveFile('tox_profile.tox', profileData.length,
          profileData));
    }

    // 2. Add chat_history/ directory
    try {
      final historyDir = await AppPaths.getAccountChatHistoryPath(normalizedToxId);
      final historyDirectory = Directory(historyDir);
      if (await historyDirectory.exists()) {
        await for (final entity in historyDirectory.list(recursive: true)) {
          if (entity is File) {
            final relativePath = p.relative(entity.path, from: historyDir);
            final data = await entity.readAsBytes();
            archive.addFile(ArchiveFile(
                'chat_history/$relativePath', data.length, data));
          }
        }
      }
    } catch (e) {
      AppLogger.logError('Full backup: Error adding chat_history', e, null);
    }

    // 3. Add offline_message_queue.json
    try {
      final queuePath = await AppPaths.getAccountOfflineQueueFilePath(normalizedToxId);
      final queueFile = File(queuePath);
      if (await queueFile.exists()) {
        final data = await queueFile.readAsBytes();
        archive.addFile(ArchiveFile(
            'offline_message_queue.json', data.length, data));
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
            final relativePath = p.relative(entity.path, from: avatarsDir);
            final data = await entity.readAsBytes();
            archive.addFile(ArchiveFile(
                'avatars/$relativePath', data.length, data));
          }
        }
      }
    } catch (e) {
      AppLogger.logError('Full backup: Error adding avatars', e, null);
    }

    // 4. Add metadata.json (scoped prefs)
    try {
      final scopedPrefs = await Prefs.exportScopedPrefsForAccount(normalizedToxId);

      // 4a. Discover missing friend_avatar_path entries from avatars directory.
      // Avatar files may exist on disk but have no corresponding pref key
      // (e.g. migrated from global dir, or pref was never saved).
      final avatarsDir = await AppPaths.getAccountAvatarsPath(normalizedToxId);
      final avatarsDirectory = Directory(avatarsDir);
      if (await avatarsDirectory.exists()) {
        await for (final entity in avatarsDirectory.list()) {
          if (entity is File) {
            final fileName = p.basename(entity.path);
            // Match pattern: friend_<friendId>_avatar
            final match = RegExp(r'^friend_([A-Fa-f0-9]{64})_avatar$').firstMatch(fileName);
            if (match != null) {
              final friendId = match.group(1)!;
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
      final accountAvatarsDir = await AppPaths.getAccountAvatarsPath(normalizedToxId);
      for (final key in scopedPrefs.keys.toList()) {
        if (key.contains('avatar_path') && scopedPrefs[key] is String) {
          final absPath = scopedPrefs[key] as String;
          if (absPath.startsWith(accountDataRoot)) {
            // Path is under per-account data root — convert directly
            scopedPrefs[key] = '@account_data/${p.relative(absPath, from: accountDataRoot)}';
          } else {
            // Path may be in the global avatars dir or elsewhere.
            // If the same filename exists in per-account avatars dir, normalize it.
            final fileName = p.basename(absPath);
            final accountPath = p.join(accountAvatarsDir, fileName);
            if (await File(accountPath).exists()) {
              scopedPrefs[key] = '@account_data/avatars/$fileName';
            }
          }
        }
      }

      // Also include account info
      final metadata = <String, dynamic>{
        'toxId': normalizedToxId,
        'nickname': nickname,
        'statusMessage': account?['statusMessage'] ?? '',
        'exportDate': DateTime.now().toIso8601String(),
        'scopedPrefs': scopedPrefs,
      };
      final metadataJson = const JsonEncoder.withIndent('  ').convert(metadata);
      final metadataBytes = utf8.encode(metadataJson);
      archive.addFile(ArchiveFile(
          'metadata.json', metadataBytes.length, metadataBytes));
    } catch (e) {
      AppLogger.logError('Full backup: Error adding metadata', e, null);
    }

    // 5. Encode archive to ZIP
    final zipData = ZipEncoder().encode(archive);
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
      final safeNickname = _sanitizeFileName(nickname.isEmpty ? 'account' : nickname);
      final toxIdPrefix = normalizedToxId.length >= 8
          ? normalizedToxId.substring(0, 8)
          : normalizedToxId;
      final fileName = '${safeNickname}_${toxIdPrefix}_backup.zip';
      final downloadsDir = await AppPaths.getDownloadsPath();
      finalFilePath = p.join(downloadsDir, fileName);
    }

    // 7. Write to file
    final exportFile = File(finalFilePath);
    final parentDir = exportFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }
    await exportFile.writeAsBytes(zipData);
    AppLogger.log('Full backup exported: $finalFilePath (${zipData.length} bytes)');
    return finalFilePath;
  }

  /// Reads toxId and nickname from a .zip backup without writing to disk.
  /// Use this to check account collisions before calling [importFullBackup].
  /// Throws if file is not a valid zip or toxId cannot be determined.
  static Future<Map<String, String>> readFullBackupMetadata(String filePath) async {
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
    final archive = ZipDecoder().decodeBytes(fileData);

    String? toxId;
    String nickname = '';

    final metadataFile = archive.findFile('metadata.json');
    if (metadataFile != null) {
      final metadataJson = utf8.decode(metadataFile.content as List<int>);
      final metadata = json.decode(metadataJson) as Map<String, dynamic>;
      toxId = metadata['toxId'] as String?;
      nickname = metadata['nickname'] as String? ?? '';
    }

    final profileFile = archive.findFile('tox_profile.tox');
    if (profileFile != null && (toxId == null || toxId.isEmpty)) {
      final toxProfile = Uint8List.fromList(profileFile.content as List<int>);
      try {
        final ffiLib = Tim2ToxFfi.open();
        final profilePtr = pkgffi.malloc<ffi.Uint8>(toxProfile.length);
        final toxIdBuffer = pkgffi.malloc<ffi.Int8>(128);
        try {
          profilePtr.asTypedList(toxProfile.length).setAll(0, toxProfile);
          final toxIdLen = ffiLib.extractToxIdFromProfileNative(
            profilePtr,
            toxProfile.length,
            ffi.Pointer<ffi.Uint8>.fromAddress(0),
            0,
            toxIdBuffer,
            128,
          );
          if (toxIdLen > 0) {
            toxId = toxIdBuffer
                .cast<pkgffi.Utf8>()
                .toDartString(length: toxIdLen);
          }
        } finally {
          pkgffi.malloc.free(profilePtr);
          pkgffi.malloc.free(toxIdBuffer);
        }
      } catch (e) {
        AppLogger.logError('readFullBackupMetadata: Error extracting toxId', e, null);
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
  /// Returns a map with 'toxId', 'nickname', and optionally 'toxProfile'.
  /// Call [readFullBackupMetadata] first and check for account collision before calling this.
  static Future<Map<String, dynamic>> importFullBackup({
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

    final archive = ZipDecoder().decodeBytes(fileData);

    // 1. Find and extract metadata.json
    Map<String, dynamic> metadata = {};
    String? toxId;
    String nickname = '';

    final metadataFile = archive.findFile('metadata.json');
    if (metadataFile != null) {
      final metadataJson = utf8.decode(metadataFile.content as List<int>);
      metadata = json.decode(metadataJson) as Map<String, dynamic>;
      toxId = metadata['toxId'] as String?;
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
          final ffiLib = Tim2ToxFfi.open();
          final profilePtr = pkgffi.malloc<ffi.Uint8>(toxProfile.length);
          final toxIdBuffer = pkgffi.malloc<ffi.Int8>(128);
          try {
            profilePtr
                .asTypedList(toxProfile.length)
                .setAll(0, toxProfile);
            final toxIdLen = ffiLib.extractToxIdFromProfileNative(
              profilePtr,
              toxProfile.length,
              ffi.Pointer<ffi.Uint8>.fromAddress(0),
              0,
              toxIdBuffer,
              128,
            );
            if (toxIdLen > 0) {
              toxId = toxIdBuffer
                  .cast<pkgffi.Utf8>()
                  .toDartString(length: toxIdLen);
            }
          } finally {
            pkgffi.malloc.free(profilePtr);
            pkgffi.malloc.free(toxIdBuffer);
          }
        } catch (e) {
          AppLogger.logError('Full backup import: Error extracting toxId', e, null);
        }
      }
    }

    if (toxId == null || toxId.isEmpty) {
      throw Exception('Could not determine Tox ID from backup');
    }

    // 3. Write tox_profile.tox to per-account directory
    if (toxProfile != null) {
      final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
      await Directory(profileDir).create(recursive: true);
      final profileFilePath = AppPaths.profileFileInDirectory(profileDir);
      await File(profileFilePath).writeAsBytes(toxProfile);
    }

    // 4. Restore chat_history/
    for (final entry in archive.files) {
      if (entry.name.startsWith('chat_history/') && !entry.isFile) continue;
      if (entry.name.startsWith('chat_history/') && entry.isFile) {
        final relativePath = entry.name.substring('chat_history/'.length);
        if (relativePath.isEmpty) continue;
        final historyDir = await AppPaths.getAccountChatHistoryPath(toxId);
        final targetPath = p.join(historyDir, relativePath);
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(entry.content as List<int>);
      }
    }

    // 4.5 Restore avatars/
    for (final entry in archive.files) {
      if (entry.name.startsWith('avatars/') && !entry.isFile) continue;
      if (entry.name.startsWith('avatars/') && entry.isFile) {
        final relativePath = entry.name.substring('avatars/'.length);
        if (relativePath.isEmpty) continue;
        final avatarsDir = await AppPaths.getAccountAvatarsPath(toxId);
        final targetPath = p.join(avatarsDir, relativePath);
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(entry.content as List<int>);
      }
    }

    // 5. Restore offline_message_queue.json
    final queueFile = archive.findFile('offline_message_queue.json');
    if (queueFile != null) {
      final queuePath = await AppPaths.getAccountOfflineQueueFilePath(toxId);
      final targetFile = File(queuePath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(queueFile.content as List<int>);
    }

    // 6. Restore scoped prefs from metadata
    final scopedPrefs = metadata['scopedPrefs'] as Map<String, dynamic>?;
    if (scopedPrefs != null && scopedPrefs.isNotEmpty) {
      // Convert relative avatar paths back to absolute paths for this machine
      final accountDataRoot = await AppPaths.getAccountDataRoot(toxId);
      for (final key in scopedPrefs.keys.toList()) {
        if (key.contains('avatar_path') && scopedPrefs[key] is String) {
          final val = scopedPrefs[key] as String;
          if (val.startsWith('@account_data/')) {
            final relPath = val.substring('@account_data/'.length);
            scopedPrefs[key] = p.join(accountDataRoot, relPath);
          }
        }
      }
      await Prefs.importScopedPrefsForAccount(toxId, scopedPrefs);
    }

    return {
      'toxId': toxId,
      'nickname': nickname,
      'toxProfile': toxProfile,
    };
  }
}
