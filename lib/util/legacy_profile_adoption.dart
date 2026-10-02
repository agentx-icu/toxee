import 'dart:io';

import 'package:path/path.dart' as p;

import 'account_export/encryption.dart' show isDataEncrypted;
import 'account_export/tox_file_io.dart' show extractToxIdFromProfile;
import 'app_paths.dart';
import 'logger.dart';
import 'safe_diagnostics.dart';
import 'secret_password.dart';
import 'tox_utils.dart';

/// Adopt the pre-multi-account `tox_profile.tox` as [toxId]'s per-account
/// profile when `p_<first16>/tox_profile.tox` is missing.
///
/// Split out of `AccountService.initializeServiceForAccount` (that file is at
/// its complexity pin). The legacy file is copied ONLY after proving it is this
/// account's: it used to be copied in unconditionally, so requesting any
/// account whose own profile was missing installed the legacy identity under
/// that account's directory and prefs scope — the session then ran as one
/// identity while every durable path, scoped pref and account-list row said it
/// was another.
///
/// An ENCRYPTED legacy blob is attributed with the caller's [password] (the
/// same one the native init opens the profile with), so a protected legacy
/// profile is adopted instead of refused. The copy stays ciphertext on disk;
/// nothing here decrypts. A wrong password, an encrypted blob with no password,
/// or an unreadable blob is refused — the file stays where it is and
/// `AccountReconciliation` / the import UI can still recover it.
///
/// Throws `Exception('Profile not found for account')` on every refusal, which
/// is what the caller already maps; a wrong password is deliberately NOT
/// reported as a password failure here because the file is not even proven to
/// belong to this account.
///
/// Shared Dart: covers desktop and mobile alike.
Future<void> adoptLegacyProfileForAccount({
  required String toxId,
  required String profileDir,
  required String profileFile,
  SecretPassword? password,
}) async {
  final legacyDir = await AppPaths.toxProfileDir;
  final legacyPath = p.join(legacyDir.path, 'tox_profile.tox');
  if (!await File(legacyPath).exists()) {
    throw Exception('Profile not found for account');
  }
  final legacyBytes = await File(legacyPath).readAsBytes();
  var encrypted = false;
  String legacyToxId;
  try {
    encrypted = isDataEncrypted(legacyBytes);
    final passphrase = encrypted && password != null && password.isNotEmpty
        ? password
        : null;
    if (encrypted && passphrase == null) {
      throw StateError('encrypted legacy profile and no password to open it');
    }
    legacyToxId = extractToxIdFromProfile(legacyBytes, passphrase);
  } catch (e) {
    SafeDiagnostics.logFailure(
      '[AccountService] profile_migration status=refused '
      'reason=identity_unreadable encrypted=$encrypted',
      e,
    );
    throw Exception('Profile not found for account');
  }
  if (legacyToxId.isEmpty || !compareToxIds(legacyToxId, toxId)) {
    AppLogger.warn(
      '[AccountService] profile_migration status=refused '
      'reason=identity_mismatch — the legacy profile belongs to a '
      'different account',
    );
    throw Exception('Profile not found for account');
  }
  await Directory(profileDir).create(recursive: true);
  await File(legacyPath).copy(profileFile);
  AppLogger.log(
    '[AccountService] profile_migration status=completed encrypted=$encrypted',
  );
}
