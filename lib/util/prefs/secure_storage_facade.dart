// The platform secure-storage facade and the account-protection tri-state.
//
// Split out of `password_verifier.dart` (complexity-gate pin). Kept together
// because they are one idea: the facade is the only thing that knows whether the
// backend ANSWERED, and `AccountProtectionState` is how that reaches the callers
// who must fail closed when it did not.

import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Narrow read/write/delete facade over the platform secure-storage backend.
///
/// Production code uses [FlutterSecureStorageFacade], which wraps
/// [FlutterSecureStorage] and swallows [MissingPluginException] /
/// [PlatformException] (sandboxed macOS, test env without a mock, etc.).
/// Tests inject in-memory implementations so write-failure paths can be
/// exercised without driving a real Keychain.
///
/// Contract:
/// * [read] returns null on a missing key or a swallowed failure. It is
///   deliberately lossy and MUST NOT be used to decide whether an account is
///   password-protected — use [readOutcome] for that (see
///   [SecureStorageReadOutcome]).
/// * [write] returns true when the value was actually persisted, false
///   when the underlying call was swallowed. Callers that perform a
///   migration MUST gate the legacy `remove(...)` on this return value —
///   deleting the legacy entry after a silent write failure is data loss.
/// * [delete] returns true when the delete actually executed against
///   secure storage, false when it was swallowed.
abstract class SecureStorageFacade {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
  Future<bool> delete(String key);

  /// [read] plus the one bit [read] throws away: whether the backend answered
  /// at all.
  ///
  /// Why this exists: the swallow-to-null behaviour below collapses "this
  /// account has no password" and "the Keychain/Keystore refused to answer"
  /// into the same value. `hasPassword` then reported `false` for a
  /// password-protected account whenever secure storage was momentarily
  /// unavailable, and every caller that gates on it — manual login, account
  /// switch, delete, export — skipped its password prompt entirely. An
  /// authentication decision must fail CLOSED, which is impossible without
  /// this distinction.
  ///
  /// The default implementation preserves the historical (lossy) behaviour —
  /// "the backend answered, and this is what it said" — so an in-memory double
  /// that `extends SecureStorageFacade` needs no change. Only a backend that
  /// can actually be unavailable overrides it. A double that `implements` the
  /// interface must supply its own, which is the intended friction: reporting
  /// availability is now part of the contract.
  Future<SecureStorageReadOutcome> readOutcome(String key) async {
    return SecureStorageReadOutcome.answered(await read(key));
  }
}

/// Result of a [SecureStorageFacade.readOutcome] call.
///
/// [unavailable] means the backend refused or was absent, so [value] carries
/// no information. It is NOT "the key is missing" — that is
/// `answered(null)`.
final class SecureStorageReadOutcome {
  const SecureStorageReadOutcome.answered(this.value) : unavailable = false;
  const SecureStorageReadOutcome.unavailable()
      : value = null,
        unavailable = true;

  final String? value;
  final bool unavailable;

  bool get hasValue => value != null && value!.isNotEmpty;
}

/// Whether an account is password-protected, including the third state the
/// old boolean could not express.
enum AccountProtectionState {
  /// No verifier in secure storage and none in the legacy plain-prefs store.
  none,

  /// A verifier exists; the account requires a password.
  protected,

  /// Secure storage could not be consulted. Callers MUST treat this as
  /// "possibly protected" and refuse to grant access, never as [none].
  unknown,
}

/// Production [SecureStorageFacade] backed by a [FlutterSecureStorage].
/// Reproduces the inline swallow behavior that used to live on
/// `PasswordVerifier`: [MissingPluginException] (e.g. unit-test env without
/// a mock) and [PlatformException] (e.g. sandboxed macOS without the
/// keychain entitlement) degrade to null/false instead of crashing.
class FlutterSecureStorageFacade implements SecureStorageFacade {
  FlutterSecureStorageFacade(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    return (await readOutcome(key)).value;
  }

  @override
  Future<SecureStorageReadOutcome> readOutcome(String key) async {
    try {
      return SecureStorageReadOutcome.answered(await _storage.read(key: key));
    } on MissingPluginException {
      return const SecureStorageReadOutcome.unavailable();
    } on PlatformException {
      return const SecureStorageReadOutcome.unavailable();
    }
  }

  @override
  Future<bool> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> delete(String key) async {
    try {
      await _storage.delete(key: key);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
