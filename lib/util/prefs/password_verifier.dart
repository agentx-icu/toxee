// PBKDF2/SHA-256 password hashing + verification for toxee accounts.
//
// Extracted from `lib/util/prefs.dart` (S1 review). The class owns the wire
// format ("pbkdf2:" + base64(hash) stored alongside a base64 salt in secure
// storage), the PBKDF2 parameters (150k iters, 256-bit key, HMAC-SHA-256),
// the legacy-SHA256 verify-and-migrate path, and the constant-time hash
// comparison.
//
// Dependencies are injected so the class is unit-testable without driving
// the real Keychain/Keystore. Pass in a [FlutterSecureStorageFacade] in
// production (wraps [FlutterSecureStorage]) and a custom
// [SecureStorageFacade] (in-memory or write-failure-simulating) in tests.
// The [LegacyPasswordStore] adapter abstracts the pre-S1 plain-text
// SharedPreferences entries we still need to read for migration.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logger.dart';

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

/// Adapter for the legacy plain-text SharedPreferences password entries
/// (`account_password_<toxId>` hash and `account_password_salt_<toxId>` salt).
/// These were the pre-S1 storage location; new writes never touch them, but
/// existing installs may still have them on disk and we migrate on first
/// read.
abstract class LegacyPasswordStore {
  Future<String?> readLegacyHash(String toxId);
  Future<String?> readLegacySalt(String toxId);
  Future<void> removeLegacyHash(String toxId);
  Future<void> removeLegacySalt(String toxId);
}

/// Default [LegacyPasswordStore] backed by the app's [SharedPreferences]
/// instance. Production callers use this; tests inject an in-memory fake.
class SharedPreferencesLegacyPasswordStore implements LegacyPasswordStore {
  SharedPreferencesLegacyPasswordStore(this._prefsProvider);

  final Future<SharedPreferences> Function() _prefsProvider;

  @override
  Future<String?> readLegacyHash(String toxId) async {
    final p = await _prefsProvider();
    return p.getString(PasswordVerifier.legacyHashKey(toxId));
  }

  @override
  Future<String?> readLegacySalt(String toxId) async {
    final p = await _prefsProvider();
    return p.getString(PasswordVerifier.legacySaltKey(toxId));
  }

  @override
  Future<void> removeLegacyHash(String toxId) async {
    final p = await _prefsProvider();
    await p.remove(PasswordVerifier.legacyHashKey(toxId));
  }

  @override
  Future<void> removeLegacySalt(String toxId) async {
    final p = await _prefsProvider();
    await p.remove(PasswordVerifier.legacySaltKey(toxId));
  }
}

/// PBKDF2/SHA-256 password hashing + verification.
///
/// Stored hash format: `"pbkdf2:" + base64(PBKDF2-HMAC-SHA256(password, salt,
/// 150_000, 256 bits))`. The salt is stored separately as base64 under a
/// parallel secure-storage key. Verifications use constant-time comparison
/// to defeat timing side channels.
///
/// Legacy entries (raw SHA-256 of `salt + password`, or unsalted SHA-256)
/// are accepted on read for backward compatibility; on a successful legacy
/// verify the password is silently re-hashed with PBKDF2 and persisted
/// (`setPassword`), so subsequent verifies use the modern format.
class PasswordVerifier {
  PasswordVerifier({
    required SecureStorageFacade secureStorage,
    required LegacyPasswordStore legacyStore,
  })  : _secureStorage = secureStorage,
        _legacyStore = legacyStore;

  final SecureStorageFacade _secureStorage;
  final LegacyPasswordStore _legacyStore;

  // Wire format / KDF parameters. Changing any of these breaks every stored
  // password — they MUST stay byte-identical to the values used before the
  // extraction (`lib/util/prefs.dart` S1 review).
  static const String pbkdf2Prefix = 'pbkdf2:';
  static const int pbkdf2Iterations = 150000;
  static const int pbkdf2Bits = 256;
  static const int _saltBytes = 32;

  // Secure-storage keys (Keychain on iOS/macOS, Keystore on Android,
  // libsecret/DPAPI on Linux/Windows). flutter_secure_storage defaults to
  // kSecAttrAccessibleWhenUnlocked (non-iCloud-synced) on Apple platforms.
  static String secureHashKey(String toxId) => 'pwd_$toxId';
  static String secureSaltKey(String toxId) => 'pwd_salt_$toxId';

  // Legacy SharedPreferences keys — kept ONLY for read-time migration into
  // secure storage; new writes never touch these. Both forms were stored
  // as plain text and would otherwise sync to iCloud on iOS / sit as
  // world-readable XML on rooted Android. Exposed so callers like
  // `Prefs.clearAccountData` can list them for explicit cleanup.
  static String legacyHashKey(String toxId) => 'account_password_$toxId';
  static const String legacySaltPrefix = 'account_password_salt_';
  static String legacySaltKey(String toxId) => '$legacySaltPrefix$toxId';

  /// Whether [toxId] is password-protected, distinguishing "not protected"
  /// from "secure storage would not answer".
  ///
  /// Resolution order mirrors [_readHashWithMigration]: secure storage first,
  /// then the legacy plain-prefs entry. A legacy hash is authoritative even
  /// when secure storage is unavailable — it proves the account IS protected,
  /// so there is nothing uncertain left to report.
  Future<AccountProtectionState> protectionState(String toxId) async {
    if (toxId.isEmpty) return AccountProtectionState.none;
    final secure = await _secureStorage.readOutcome(secureHashKey(toxId));
    if (secure.hasValue) return AccountProtectionState.protected;
    final legacy = await _legacyStore.readLegacyHash(toxId);
    if (legacy != null && legacy.isNotEmpty) {
      return AccountProtectionState.protected;
    }
    return secure.unavailable
        ? AccountProtectionState.unknown
        : AccountProtectionState.none;
  }

  /// Check if [toxId] has a password set (either in secure storage or
  /// migratable legacy plain prefs).
  ///
  /// FAIL-CLOSED: [AccountProtectionState.unknown] reports `true`. Every
  /// caller of this method uses it to decide whether to demand a password, so
  /// an unreadable Keychain must mean "ask" rather than "let them in". Callers
  /// that can render a better error should read [protectionState] directly.
  Future<bool> hasPassword(String toxId) async {
    return (await protectionState(toxId)) != AccountProtectionState.none;
  }

  /// Get the raw stored password hash for [toxId] (PBKDF2-prefixed or legacy
  /// SHA256). Returns null if no password is set. Migrates legacy plain-prefs
  /// values into secure storage on first read.
  Future<String?> getPasswordHash(String toxId) =>
      _readHashWithMigration(toxId);

  /// Store [password] for [toxId] (PBKDF2 hash + new random salt in secure
  /// storage). Empty password short-circuits to [removePassword]. Throws
  /// [ArgumentError] when [toxId] is empty.
  ///
  /// Returns true when both the hash and salt were persisted to secure
  /// storage; false when either secure write was swallowed (in which case
  /// the legacy plain-prefs entries are intentionally left intact so a
  /// subsequent attempt can recover). The empty-password short-circuit
  /// (which removes any existing password) returns true on full cleanup.
  Future<bool> setPassword(String toxId, String password) async {
    if (toxId.isEmpty) {
      throw ArgumentError('toxId cannot be empty');
    }
    if (password.isEmpty) {
      return removePassword(toxId);
    }
    final salt = List<int>.generate(_saltBytes, (_) => Random.secure().nextInt(256));
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: pbkdf2Iterations,
      bits: pbkdf2Bits,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final hashBytes = await secretKey.extractBytes();
    final storedHash = '$pbkdf2Prefix${base64Encode(hashBytes)}';
    final storedSalt = base64Encode(salt);

    // Snapshot any prior secure-storage state so we can restore it if one
    // of the two writes below fails. Without this, a partial success
    // (hash persisted but salt write swallowed, or vice versa) leaves the
    // pair desynchronized: verifyPassword would then mix new-hash + legacy-
    // salt (or old-hash + new-salt) and the password would be permanently
    // unverifiable. This is the closest we can get to atomicity with the
    // flutter_secure_storage API surface (no transactions).
    final priorHash = await _secureStorage.read(secureHashKey(toxId));
    final priorSalt = await _secureStorage.read(secureSaltKey(toxId));

    final hashWrote = await _secureStorage.write(secureHashKey(toxId), storedHash);
    final saltWrote = await _secureStorage.write(secureSaltKey(toxId), storedSalt);
    if (!hashWrote || !saltWrote) {
      // Best-effort rollback: restore the snapshot. If the restore writes
      // themselves fail, we're no worse off than the partial-write state
      // we entered with — but most platforms either accept all writes or
      // reject all (MissingPluginException, sandbox denial), so a
      // restorable rollback is typical. Don't touch the legacy plain-prefs
      // entries either way; they remain the durable fallback.
      if (priorHash != null && priorHash.isNotEmpty) {
        await _secureStorage.write(secureHashKey(toxId), priorHash);
      } else {
        await _secureStorage.delete(secureHashKey(toxId));
      }
      if (priorSalt != null && priorSalt.isNotEmpty) {
        await _secureStorage.write(secureSaltKey(toxId), priorSalt);
      } else {
        await _secureStorage.delete(secureSaltKey(toxId));
      }
      return false;
    }
    // Drop legacy plain-prefs entries if a prior install left them behind.
    await Future.wait([
      _legacyStore.removeLegacyHash(toxId),
      _legacyStore.removeLegacySalt(toxId),
    ]);
    return true;
  }

  /// Remove the stored password for [toxId] from secure storage and any
  /// remaining legacy plain-prefs entries.
  ///
  /// Returns true when both secure deletes succeeded (and the legacy
  /// entries were also cleared); false when either secure delete was
  /// swallowed, in which case the legacy entries are left in place so we
  /// don't destroy the last remaining copy of the credential.
  Future<bool> removePassword(String toxId) async {
    if (toxId.isEmpty) return true;
    final hashDeleted = await _secureStorage.delete(secureHashKey(toxId));
    final saltDeleted = await _secureStorage.delete(secureSaltKey(toxId));
    if (!hashDeleted || !saltDeleted) {
      return false;
    }
    await Future.wait([
      _legacyStore.removeLegacyHash(toxId),
      _legacyStore.removeLegacySalt(toxId),
    ]);
    return true;
  }

  /// Verify [password] against the stored hash for [toxId].
  ///
  /// Supports PBKDF2 (new) and legacy SHA-256 (salted and unsalted); on a
  /// successful legacy verify, the password is re-hashed with PBKDF2 and
  /// the new format is persisted before returning true.
  Future<bool> verifyPassword(String toxId, String password) async {
    if (toxId.isEmpty || password.isEmpty) return false;

    final storedHash = await _readHashWithMigration(toxId);
    if (storedHash == null) return false;
    final saltBase64 = await _readSaltWithMigration(toxId);

    if (storedHash.startsWith(pbkdf2Prefix)) {
      if (saltBase64 == null) return false;
      List<int> salt;
      try {
        salt = base64Decode(saltBase64);
      } catch (_) {
        return false;
      }
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: pbkdf2Iterations,
        bits: pbkdf2Bits,
      );
      final secretKey = await pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final hashBytes = await secretKey.extractBytes();
      final expected = base64Encode(hashBytes);
      final actual = storedHash.substring(pbkdf2Prefix.length);
      return constantTimeEquals(actual, expected);
    }

    // Legacy SHA-256 (salted or unsalted) — migrate on success.
    if (saltBase64 != null && saltBase64.isNotEmpty) {
      final bytes = utf8.encode('$saltBase64$password');
      final hash = crypto.sha256.convert(bytes);
      if (storedHash == hash.toString()) {
        final migrated = await setPassword(toxId, password);
        if (!migrated) {
          // Verify still succeeded; the legacy hash remains valid for the
          // next attempt. Surface the failure for diagnosability.
          AppLogger.warn(
            '[PasswordVerifier] PBKDF2 migration after legacy salted-SHA256 '
            'verify failed for toxId=$toxId (secure storage unavailable); '
            'legacy entry retained.',
          );
        }
        return true;
      }
      return false;
    }
    final bytes = utf8.encode(password);
    final hash = crypto.sha256.convert(bytes);
    if (storedHash == hash.toString()) {
      final migrated = await setPassword(toxId, password);
      if (!migrated) {
        AppLogger.warn(
          '[PasswordVerifier] PBKDF2 migration after legacy unsalted-SHA256 '
          'verify failed for toxId=$toxId (secure storage unavailable); '
          'legacy entry retained.',
        );
      }
      return true;
    }
    return false;
  }

  /// Read PBKDF2 hash from secure storage, migrating any legacy plain-prefs
  /// value into the secure store on first hit. Returns null when no password
  /// is set for the account.
  Future<String?> _readHashWithMigration(String toxId) async {
    if (toxId.isEmpty) return null;
    final secureKey = secureHashKey(toxId);
    final fromSecure = await _secureStorage.read(secureKey);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    // Migrate from legacy SharedPreferences (S1: was plain-text on disk).
    // Only remove the legacy entry once the secure write actually persisted —
    // a swallowed keychain failure here would lose the user's password hash.
    final legacy = await _legacyStore.readLegacyHash(toxId);
    if (legacy != null && legacy.isNotEmpty) {
      final wrote = await _secureStorage.write(secureKey, legacy);
      if (wrote) {
        await _legacyStore.removeLegacyHash(toxId);
      }
      return legacy;
    }
    return null;
  }

  /// Read salt from secure storage, migrating from legacy plain prefs when
  /// present. Returns null when no salt is stored.
  Future<String?> _readSaltWithMigration(String toxId) async {
    if (toxId.isEmpty) return null;
    final secureKey = secureSaltKey(toxId);
    final fromSecure = await _secureStorage.read(secureKey);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    final legacy = await _legacyStore.readLegacySalt(toxId);
    if (legacy != null && legacy.isNotEmpty) {
      // Only drop the legacy salt once the secure write actually persisted —
      // losing the salt while keeping the hash makes the password unverifiable.
      final wrote = await _secureStorage.write(secureKey, legacy);
      if (wrote) {
        await _legacyStore.removeLegacySalt(toxId);
      }
      return legacy;
    }
    return null;
  }
}

/// Length-invariant XOR-accumulation equality. Used only for password-hash
/// comparison to defeat timing side channels — never short-circuits on a
/// mismatched byte. Returns false up-front on length mismatch (length is
/// not the secret).
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var x = 0;
  for (var i = 0; i < a.length; i++) {
    x |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return x == 0;
}
