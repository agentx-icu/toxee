// Exceptions thrown by the account-export / account-import code path.
//
// Kept as a tiny standalone module so call sites can `import 'exceptions.dart'`
// or rely on the public re-export from `account_export_service.dart` without
// pulling in the encryption / FFI / I/O machinery.

/// Thrown by the account-export importers when the source `.tox` file is
/// encrypted and no password was supplied. Lets callers branch on a typed
/// exception instead of fragile string-matching the message.
class PasswordRequiredException implements Exception {
  const PasswordRequiredException(
      [this.message = 'Password required for encrypted .tox file']);
  final String message;
  @override
  String toString() => 'PasswordRequiredException: $message';
}
