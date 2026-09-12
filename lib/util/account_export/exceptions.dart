// Exceptions thrown by the account-export / account-import code path.
//
// Kept as a tiny standalone module so call sites can `import 'exceptions.dart'`
// or rely on the public re-export from `account_export_service.dart` without
// pulling in the encryption / FFI / I/O machinery.

/// Which profile-crypto operation could not find its input file.
enum ProfileCryptoOperation { encrypt, decrypt }

/// Thrown when [encryptProfileFile] / [decryptProfileFile] is handed a path
/// that does not exist.
///
/// PRIVACY: deliberately carries **no path**. The message used to interpolate
/// `profileFilePath`, which is `<profileStorageRoot>/p_<own Tox ID first 16>/
/// tox_profile.tox` — i.e. the account's own public-key prefix plus the
/// absolute local layout (including the OS user name on desktop). Diagnostics
/// reach `flutter_client.log` verbatim through
/// `AppLogger.logError` -> `_emit(LogLevel.error, 'Error: $error')`
/// (lib/util/logger.dart:360), the file users attach to bug reports.
///
/// The path is fully determined by (storage root, own Tox ID, operation), so a
/// fingerprint would add no triage signal the way it does for
/// `UnsafeBackupPathException` — [operation] is the only non-derivable bit.
/// Same reasoning as `RestoreDestinationExistsError`.
class ProfileFileMissingException implements Exception {
  const ProfileFileMissingException(this.operation);

  final ProfileCryptoOperation operation;

  @override
  String toString() =>
      'ProfileFileMissingException: profile file not found '
      '(operation=${operation.name})';
}

/// Thrown by the account-export importers when the source `.tox` file is
/// encrypted and no password was supplied. Lets callers branch on a typed
/// exception instead of fragile string-matching the message.
class PasswordRequiredException implements Exception {
  const PasswordRequiredException([
    this.message = 'Password required for encrypted .tox file',
  ]);
  final String message;
  @override
  String toString() => 'PasswordRequiredException: $message';
}

/// Thrown when an encrypted full backup fails authenticated decryption with
/// the password supplied by the user.
class InvalidBackupPasswordException implements Exception {
  const InvalidBackupPasswordException([
    this.message = 'Invalid password for encrypted full backup',
  ]);

  final String message;

  @override
  String toString() => 'InvalidBackupPasswordException: $message';
}

/// Thrown when backup metadata or payload structure is malformed or uses
/// parameters outside the exact format supported by this app.
class InvalidBackupFormatException implements Exception {
  const InvalidBackupFormatException([
    this.message = 'Invalid or unsupported full backup format',
  ]);

  final String message;

  @override
  String toString() => 'InvalidBackupFormatException: $message';
}

/// Thrown when a full backup cannot include the account's `tox_profile.tox`.
///
/// The profile IS the account: its absence used to be skipped silently, so the
/// export reported success and wrote an archive that restored into an account
/// which could never log in. Backups fail loudly instead.
///
/// PRIVACY: carries no path and no Tox ID, for the same reason as
/// [ProfileFileMissingException] — the message reaches `flutter_client.log`.
class MissingBackupProfileException implements Exception {
  const MissingBackupProfileException([
    this.message = 'the account profile could not be found on this device',
  ]);

  final String message;

  @override
  String toString() =>
      'MissingBackupProfileException: refusing to write a backup without the '
      'account identity ($message)';
}

/// Thrown when an export cannot determine whether the on-disk profile is
/// already encrypted, and therefore cannot decide whether to encrypt it.
///
/// Both guesses are harmful: assuming "already encrypted" publishes a PLAINTEXT
/// copy of a password-protected account (the profile is plaintext for the whole
/// of an authenticated session), and assuming "not encrypted" produces a
/// double-encrypted file that neither toxee nor qTox can import. So the export
/// aborts instead.
class UndeterminedProfileEncryptionException implements Exception {
  const UndeterminedProfileEncryptionException();

  @override
  String toString() =>
      'UndeterminedProfileEncryptionException: could not determine the '
      "profile's encryption state; refusing to export rather than guess";
}
