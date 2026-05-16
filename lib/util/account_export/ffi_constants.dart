// Constants shared across the account-export FFI wrappers.
//
// Kept tiny on purpose so it can be imported by both encryption.dart and
// tox_file_io.dart without introducing a cyclic dependency.

/// Tox's `TOX_PASS_ENCRYPTION_EXTRA_LENGTH` — the constant overhead, in
/// bytes, added to a plaintext when it is encrypted with a passphrase.
/// Mirrored from the C header (`#define TOX_PASS_ENCRYPTION_EXTRA_LENGTH 80`).
const int toxPassEncryptionExtraLength = 80;
