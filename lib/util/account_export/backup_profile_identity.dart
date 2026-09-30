// Identity extraction from a backup's `tox_profile.tox`, which may be
// ciphertext: a full backup written before native savedata encryption of a
// protected account that was not live stored the file as it was on disk —
// encrypted under the ACCOUNT password, which is independent of the archive
// password. New archives always carry plaintext (see exportFullBackup).

import 'dart:typed_data';

import '../tox_utils.dart';
import 'encryption.dart';
import 'exceptions.dart';
import 'ffi_constants.dart';
import 'restore_test_hooks.dart';
import 'tox_file_io.dart';

/// The tox id of [toxProfile]. Encrypted bytes need [profilePassword]:
/// without it [BackupProfilePasswordRequiredException] is thrown BEFORE any
/// restore write, so the caller can prompt; a password that does not open the
/// profile surfaces as [InvalidBackupPasswordException].
String extractBackupProfileToxId(Uint8List toxProfile, String? profilePassword) {
  final testExtractor = FullBackupRestoreTestHooks.profileIdentityExtractor;
  if (testExtractor != null) return testExtractor(toxProfile);
  if (!isBackupProfileEncrypted(toxProfile)) {
    return extractToxIdFromProfile(toxProfile);
  }
  if (profilePassword == null || profilePassword.isEmpty) {
    throw const BackupProfilePasswordRequiredException();
  }
  try {
    return extractToxIdFromProfile(toxProfile, profilePassword);
  } catch (_) {
    throw const InvalidBackupPasswordException(
      'The account password did not open the profile in this backup',
    );
  }
}

bool isBackupProfileEncrypted(Uint8List toxProfile) {
  if (toxProfile.length < toxPassEncryptionExtraLength) return false;
  try {
    return isDataEncrypted(toxProfile);
  } catch (_) {
    return false;
  }
}

void requireBackupProfileMatchesMetadata({
  required String metadataToxId,
  required Uint8List toxProfile,
  required String? profilePassword,
}) {
  final profileToxId = extractBackupProfileToxId(toxProfile, profilePassword);
  if (!compareToxIds(metadataToxId, profileToxId)) {
    throw StateError('Backup metadata toxId does not match tox_profile.tox');
  }
}
