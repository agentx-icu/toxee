// Exceptions thrown by the account-export / account-import code path.
//
// Kept as a tiny standalone module so call sites can `import 'exceptions.dart'`
// or rely on the public re-export from `account_export_service.dart` without
// pulling in the encryption / FFI / I/O machinery.

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
