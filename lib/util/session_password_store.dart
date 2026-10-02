import 'package:flutter/foundation.dart' show visibleForTesting;

import 'secret_password.dart';

export 'secret_password.dart';

/// In-memory store for the current account's profile encryption password.
/// Used to re-encrypt tox_profile.tox on logout and to open the at-rest
/// ciphertext for an export. Never persisted to disk.
///
/// Holds a [SecretPassword] — zeroable bytes, never a String — and zeroes it
/// on [clear] or when another value replaces it. [get] hands out the stored
/// instance BORROWED: a caller that needs it across an `await` takes a
/// `copy()` (a concurrent [clear] would otherwise zero it under the caller)
/// and never disposes what it did not copy.
class SessionPasswordStore {
  static String? _toxId;
  static SecretPassword? _password;

  /// Keeps an owned COPY of [password] for [toxId]; the caller keeps its own.
  /// An empty password means "no password" and clears the slot.
  static void set(String toxId, SecretPassword password) {
    // The replacement first: a disposed argument throws here, before the slot
    // has been re-pointed at [toxId] with the previous account's password.
    final next = password.isEmpty ? null : password.copy();
    final previous = _password;
    _toxId = toxId;
    _password = next;
    previous?.dispose();
  }

  /// String convenience for tests only; production converts at the UI edge.
  @visibleForTesting
  static void setText(String toxId, String password) {
    final secret = SecretPassword.fromString(password);
    try {
      set(toxId, secret);
    } finally {
      secret.dispose();
    }
  }

  /// The stored password for [toxId], BORROWED (see the class doc), or null.
  static SecretPassword? get(String toxId) {
    if (_toxId != toxId) return null;
    return _password;
  }

  static void clear([String? toxId]) {
    if (toxId == null || _toxId == toxId) {
      final previous = _password;
      _toxId = null;
      _password = null;
      previous?.dispose();
    }
  }
}
