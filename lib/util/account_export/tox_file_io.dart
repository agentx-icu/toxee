// Reads and writes `.tox` files (compatible with qTox) plus the
// extract-toxId-from-profile helper that bridges raw savedata bytes into
// a Tox public key hex string.
//
// This module owns the import / export entry points that operate on a
// single .tox file. It does NOT own the .zip full-backup flow — that lives
// in full_backup.dart.

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

import '../app_paths.dart';
import '../logger.dart';
import '../prefs.dart';
import '../session_password_store.dart';
import 'atomic_file_write.dart';
import 'encryption.dart';
import 'exceptions.dart';
import 'ffi_constants.dart';

const String _exportStageSuffix = '.new';

/// Sanitize file name (remove characters illegal on common filesystems).
String sanitizeFileName(String fileName) {
  return fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
}

/// Export account data to a .tox file.
///
/// [toxId] - The Tox ID of the account to export
/// [password] - Optional password for encryption. If provided, data will be
///   encrypted using Tox standard encryption.
/// [filePath] - Optional file path. If not provided, will use default
///   naming: `{nickname}_{toxId前8位}.tox`.
///
/// Returns the absolute path to the exported file.
/// [accountPassword]: the password that opens the profile at rest when the
/// account is protected — the login page passes the one it just verified; a
/// live session's is taken from [SessionPasswordStore] when omitted.
/// Both passwords are borrowed: the caller keeps and disposes them.
Future<String> exportAccountData({
  required String toxId,
  SecretPassword? password,
  String? filePath,
  SecretPassword? accountPassword,
}) async {
  if (toxId.isEmpty) {
    throw ArgumentError('toxId cannot be empty');
  }

  // Normalize toxId (trim whitespace, ensure consistent format)
  final normalizedToxId = toxId.trim();
  AppLogger.log(
    '[AccountExportService] Export: Account lookup started: '
    'identifierLength=${normalizedToxId.length}',
  );

  // Get account info - Prefs.getAccountByToxId now handles normalization
  var account = await Prefs.getAccountByToxId(normalizedToxId);

  // If not found, try to get from account list and find by partial match
  if (account == null) {
    AppLogger.log(
      '[AccountExportService] Export: Primary account lookup found=false',
    );
    final allAccounts = await Prefs.getAccountList();
    AppLogger.log(
      '[AccountExportService] Export: Account candidate count=${allAccounts.length}',
    );
    for (final acc in allAccounts) {
      final accToxId = acc['toxId']?.trim() ?? '';
      AppLogger.log(
        '[AccountExportService] Export: Checking account candidate: '
        'identifierLength=${accToxId.length}',
      );
      // Try exact match
      if (accToxId == normalizedToxId) {
        account = acc;
        AppLogger.log(
          '[AccountExportService] Export: Found account by exact match',
        );
        break;
      }
      // Try case-insensitive match
      if (accToxId.toLowerCase() == normalizedToxId.toLowerCase()) {
        account = acc;
        AppLogger.log(
          '[AccountExportService] Export: Found account by case-insensitive match',
        );
        break;
      }
      // Try partial match (first 64 chars, as toxId might be longer)
      if (accToxId.length >= 64 && normalizedToxId.length >= 64) {
        if (accToxId.substring(0, 64) == normalizedToxId.substring(0, 64)) {
          account = acc;
          AppLogger.log(
            '[AccountExportService] Export: Found account by partial match (first 64 chars)',
          );
          break;
        }
      }
    }
  }

  // If still not found, try to create account data from current session
  if (account == null) {
    AppLogger.log(
      '[AccountExportService] Export: Account lookup found=false; '
      'usingCurrentSession=true',
    );
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
        '[AccountExportService] Export: Created account data from current '
        'session: hasNickname=true, '
        'hasStatusMessage=${statusMessage?.isNotEmpty ?? false}',
      );
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
        '[AccountExportService] Export: Created minimal account data',
      );
    }
  } else {
    AppLogger.log('[AccountExportService] Export: Account lookup found=true');
  }

  final nickname = account['nickname'] ?? '';
  final toxIdPrefix = normalizedToxId.length >= 8
      ? normalizedToxId.substring(0, 8)
      : normalizedToxId;

  // Read tox profile file (try primary and fallback paths)
  Uint8List toxProfileData;
  try {
    final resolvedPath = await AppPaths.resolveToxProfilePath(normalizedToxId);
    if (resolvedPath == null) {
      throw Exception(
        'Tox profile file not found. '
        'Ensure this account has been used at least once on this device, or restore from a full backup.',
      );
    }
    final toxProfileFile = File(resolvedPath);
    toxProfileData = await toxProfileFile.readAsBytes();
    if (toxProfileData.isEmpty) {
      throw Exception('Tox profile file is empty');
    }
    AppLogger.log(
      '[AccountExportService] Export: Read profile: '
      'byteCount=${toxProfileData.length}',
    );
  } catch (error) {
    AppLogger.error(
      '[AccountExportService] Export: Profile read succeeded=false; '
      'errorType=${error.runtimeType}',
    );
    if (error is FileSystemException) {
      throw const FileSystemException('Unable to read account profile data');
    }
    rethrow;
  }

  // Encrypt if a password is supplied AND the bytes are not already encrypted.
  //
  // The profile's encryption state depends on when the export runs: it is
  // plaintext for the whole of an authenticated session and ciphertext once
  // `teardownCurrentSession` has re-encrypted it. Encrypting unconditionally
  // therefore produced a DOUBLE-encrypted `.tox` whenever the source was
  // already ciphertext — a file that needs two passphrase rounds and so is
  // neither importable by toxee nor readable by qTox, despite the export
  // reporting success. Only ever produce the single-layer format.
  toxProfileData = await plaintextProfileForExport(
    toxProfileData,
    toxId: normalizedToxId,
    accountPassword: accountPassword,
  );

  Uint8List finalData;
  if (password != null && password.isNotEmpty) {
    {
      AppLogger.log('[AccountExportService] Export: Encryption requested=true');
      try {
        finalData = passEncrypt(toxProfileData, password);
        AppLogger.log(
          '[AccountExportService] Export: Encryption succeeded=true; '
          'byteCount=${finalData.length}',
        );
      } catch (error) {
        AppLogger.error(
          '[AccountExportService] Export: Encryption succeeded=false; '
          'errorType=${error.runtimeType}',
        );
        rethrow;
      }
    }
  } else {
    finalData = toxProfileData;
    AppLogger.log('[AccountExportService] Export: Encryption requested=false');
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
    final safeNickname = sanitizeFileName(
      nickname.isEmpty ? 'account' : nickname,
    );
    final fileName = '${safeNickname}_$toxIdPrefix.tox';

    // Save to Downloads directory — under a name nothing uses yet. On iOS
    // this directory is visible in the Files app and a cancelled mobile export
    // deliberately leaves its copy here (the user is told so); the next export
    // must not silently replace that snapshot with a newer one.
    final downloadsDir = await AppPaths.getDownloadsPath();
    finalFilePath = p.join(downloadsDir, fileName);
    for (
      var n = 2;
      await FileSystemEntity.type(finalFilePath) !=
          FileSystemEntityType.notFound;
      n++
    ) {
      finalFilePath = p.join(downloadsDir, '${safeNickname}_$toxIdPrefix ($n).tox');
    }
  }

  // Write to file
  try {
    final exportFile = File(finalFilePath);

    // Ensure parent directory exists
    final parentDir = exportFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    await writeBytesAtomically(
      exportFile,
      finalData,
      tempSuffix: _exportStageSuffix,
    );
    AppLogger.log(
      '[AccountExportService] Export: Write succeeded=true; '
      'byteCount=${finalData.length}',
    );
    return finalFilePath;
  } catch (error) {
    AppLogger.error(
      '[AccountExportService] Export: Write succeeded=false; '
      'errorType=${error.runtimeType}',
    );
    if (error is FileSystemException) {
      throw const FileSystemException('Unable to write account export data');
    }
    rethrow;
  }
}

/// Import account data from a .tox file.
///
/// [filePath] - Path to the .tox file
/// [password] - Password if the file is encrypted
///
/// Returns a map with `toxId` (64-char public key hex) and `toxProfile`
/// (the decrypted Tox savedata blob as Uint8List).
///
/// Throws [PasswordRequiredException] if the file is encrypted but no
/// password was provided.
Future<Map<String, dynamic>> importAccountData({
  required String filePath,
  SecretPassword? password,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw Exception('Account data file not found');
  }

  // Read file as binary
  Uint8List fileData;
  try {
    fileData = await file.readAsBytes();
  } catch (error) {
    if (error is FileSystemException) {
      throw const FileSystemException('Unable to read account data');
    }
    rethrow;
  }
  if (fileData.isEmpty) {
    throw Exception('File is empty');
  }

  AppLogger.log(
    '[AccountExportService] Import: Read file: byteCount=${fileData.length}',
  );

  // Check if encrypted
  bool isEncrypted = false;
  if (fileData.length >= toxPassEncryptionExtraLength) {
    try {
      isEncrypted = isDataEncrypted(fileData);
    } catch (error) {
      AppLogger.warn(
        '[AccountExportService] Import: Encryption check succeeded=false; '
        'errorType=${error.runtimeType}',
      );
      // Continue, assume not encrypted
    }
  }

  AppLogger.log('[AccountExportService] Import: Encrypted=$isEncrypted');

  // Decrypt if encrypted
  Uint8List decryptedData;
  if (isEncrypted) {
    if (password == null || password.isEmpty) {
      throw const PasswordRequiredException();
    }

    try {
      decryptedData = passDecrypt(fileData, password);
      AppLogger.log(
        '[AccountExportService] Import: Decryption succeeded=true; '
        'byteCount=${decryptedData.length}',
      );
    } catch (error) {
      AppLogger.error(
        '[AccountExportService] Import: Decryption succeeded=false; '
        'errorType=${error.runtimeType}',
      );
      rethrow;
    }
  } else {
    decryptedData = fileData;
  }

  // Extract toxId from profile
  final toxId = _extractToxIdFromProfile(
    decryptedData,
    isEncrypted ? password : null,
  );
  AppLogger.log(
    '[AccountExportService] Import: Identifier extraction succeeded=true; '
    'identifierLength=${toxId.length}',
  );

  return {'toxId': toxId, 'toxProfile': decryptedData};
}

/// Extract the 64-char public-key hex Tox ID from a profile blob.
///
/// [profileData] is the (already-decrypted) tox savedata blob.
/// [passphrase] is forwarded to the FFI extractor for the path where the
/// caller wants the extractor to perform decryption — in practice the
/// importers in this file have already decrypted, so they pass null.
/// The profile as PLAINTEXT. At rest, a protected account's file is
/// ciphertext under the account password (native savedata encryption), so an
/// export opens it with that password — [accountPassword], or the live
/// session's — BEFORE applying whatever export password the user chose. It
/// never exports ciphertext under a password the user did not pick.
Future<Uint8List> plaintextProfileForExport(
  Uint8List data, {
  required String toxId,
  SecretPassword? accountPassword,
}) async {
  final bool encrypted;
  try {
    encrypted = isDataEncrypted(data);
  } catch (error) {
    AppLogger.error(
      '[AccountExportService] Export: aborted — cannot determine whether the '
      'profile is encrypted at rest (errorType=${error.runtimeType})',
    );
    throw const UndeterminedProfileEncryptionException();
  }
  if (!encrypted) return data;
  // The session's value is borrowed and used synchronously (no await between
  // get and decrypt), so a concurrent clear cannot zero it mid-use.
  final opener = accountPassword.hasValue
      ? accountPassword
      : SessionPasswordStore.get(toxId);
  if (opener == null || opener.isEmpty) {
    throw const SessionPasswordUnavailableException();
  }
  return passDecrypt(data, opener);
}

String extractToxIdFromProfile(
  Uint8List profileData, [
  SecretPassword? passphrase,
]) => _extractToxIdFromProfile(profileData, passphrase);

String _extractToxIdFromProfile(
  Uint8List profileData,
  SecretPassword? passphrase,
) {
  try {
    final ffiLib = Tim2ToxFfi.open();
    final profilePtr = pkgffi.malloc<ffi.Uint8>(profileData.length);
    final toxIdBuffer = pkgffi.malloc<ffi.Int8>(
      128,
    ); // 64 hex chars + null terminator

    // Allocated up front so the `finally` can always wipe and release it.
    // It used to be freed only on the success path, so any throw — including
    // the `toxIdLen < 0` one a few lines below — leaked a native buffer holding
    // the user's passphrase in cleartext, for the process's lifetime.
    final passphraseLen = passphrase?.length ?? 0;
    final passphrasePtr = passphraseLen == 0
        ? ffi.Pointer<ffi.Uint8>.fromAddress(0)
        : pkgffi.malloc<ffi.Uint8>(passphraseLen);
    try {
      profilePtr.asTypedList(profileData.length).setAll(0, profileData);
      if (passphraseLen > 0) {
        passphrase!.withBytes(
          (bytes) => passphrasePtr.asTypedList(passphraseLen).setAll(0, bytes),
        );
      }

      final toxIdLen = ffiLib.extractToxIdFromProfileNative(
        profilePtr,
        profileData.length,
        passphrasePtr,
        passphraseLen,
        toxIdBuffer,
        128,
      );

      if (toxIdLen < 0) {
        throw Exception('Failed to extract Tox ID from profile');
      }

      return toxIdBuffer.cast<pkgffi.Utf8>().toDartString(length: toxIdLen);
    } finally {
      // Zero before releasing: `malloc.free` only returns the block to the
      // allocator, so the passphrase would otherwise sit in reusable heap (and
      // in any core dump) until something happened to overwrite it.
      if (passphraseLen > 0) {
        passphrasePtr.asTypedList(passphraseLen).fillRange(0, passphraseLen, 0);
        pkgffi.malloc.free(passphrasePtr);
      }
      pkgffi.malloc.free(profilePtr);
      pkgffi.malloc.free(toxIdBuffer);
    }
  } catch (error) {
    AppLogger.error(
      '[AccountExportService] Import: Identifier extraction succeeded=false; '
      'errorType=${error.runtimeType}',
    );
    rethrow;
  }
}
