// Public façade for the account-export / account-import flow.
//
// All implementation lives in sibling files (encryption.dart,
// tox_file_io.dart, full_backup.dart); this class is intentionally a thin
// static delegating shim so the surface stays identical for every existing
// caller of package:toxee/util/account_export_service.dart.
//
// New code should depend on these static methods exactly as before — the
// split only changes WHERE the bodies live, not WHAT they do.

import 'encryption.dart' as enc;
import 'exceptions.dart';
import 'full_backup.dart' as backup;
import 'tox_file_io.dart' as tox;

export 'exceptions.dart' show PasswordRequiredException;

/// Account export/import service for .tox file format (compatible with qTox).
class AccountExportService {
  /// Export account data to a .tox file. See [tox.exportAccountData].
  static Future<String> exportAccountData({
    required String toxId,
    String? password,
    String? filePath,
  }) =>
      tox.exportAccountData(
          toxId: toxId, password: password, filePath: filePath);

  /// Import account data from a .tox file. Throws
  /// [PasswordRequiredException] if the file is encrypted and no password
  /// was supplied. See [tox.importAccountData].
  static Future<Map<String, dynamic>> importAccountData({
    required String filePath,
    String? password,
  }) =>
      tox.importAccountData(filePath: filePath, password: password);

  /// Check if a profile file (tox_profile.tox) is encrypted.
  static Future<bool> isProfileFileEncrypted(String profileFilePath) =>
      enc.isProfileFileEncrypted(profileFilePath);

  /// Encrypt a profile file in place (plain -> encrypted). Used after
  /// register or on logout.
  static Future<void> encryptProfileFile(
          String profileFilePath, String password) =>
      enc.encryptProfileFile(profileFilePath, password);

  /// Decrypt a profile file in place (encrypted -> plain). Used before
  /// init when an account has a password.
  static Future<void> decryptProfileFile(
          String profileFilePath, String password) =>
      enc.decryptProfileFile(profileFilePath, password);

  /// Export a comprehensive .zip backup. See [backup.exportFullBackup].
  static Future<String> exportFullBackup({
    required String toxId,
    String? password,
    String? filePath,
  }) =>
      backup.exportFullBackup(
          toxId: toxId, password: password, filePath: filePath);

  /// Read toxId and nickname from a .zip backup without writing to disk.
  /// See [backup.readFullBackupMetadata].
  static Future<Map<String, String>> readFullBackupMetadata(String filePath) =>
      backup.readFullBackupMetadata(filePath);

  /// Import a full backup from a .zip (or .tox). See [backup.importFullBackup].
  static Future<Map<String, dynamic>> importFullBackup({
    required String filePath,
    String? password,
  }) =>
      backup.importFullBackup(filePath: filePath, password: password);
}
