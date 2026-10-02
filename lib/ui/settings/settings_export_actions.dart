import '../../util/account_export_service.dart';
import '../../util/secret_password.dart';

/// Writes one in-session settings export. [password] is the EXPORT password
/// the user chose in `ExportPasswordDialog` (null = unencrypted `.tox`). No
/// account password is passed: in a live session the at-rest profile is
/// opened with the session password (`SessionPasswordStore`, see
/// `plaintextProfileForExport`), so the user is never asked for it here.
/// [password] is bytes, borrowed for the call; the settings page zeroes it
/// once the export flow ends.
///
/// `SettingsPage.exportToxFn` / `exportFullBackupFn` take this shape so a
/// widget test can drive the REAL page → chooser → export-password dialog →
/// exporter and observe exactly which password reached the exporter.
typedef SettingsExportFn =
    Future<String> Function({
      required String toxId,
      SecretPassword? password,
      String? filePath,
    });

/// The settings `.tox` export (in session).
Future<String> exportToxFromSettings({
  required String toxId,
  SecretPassword? password,
  String? filePath,
}) => AccountExportService.exportAccountData(
  toxId: toxId,
  password: password,
  filePath: filePath,
);

/// The settings full-backup export (in session). The service itself refuses an
/// empty password (`requireFullBackupExportPassword`); the dialog refuses it
/// first, in `allowEmpty: false` mode.
Future<String> exportFullBackupFromSettings({
  required String toxId,
  SecretPassword? password,
  String? filePath,
}) => AccountExportService.exportFullBackup(
  toxId: toxId,
  password: password,
  filePath: filePath,
);
