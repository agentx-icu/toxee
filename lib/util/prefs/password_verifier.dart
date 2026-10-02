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
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../logger.dart';
import '../secret_password.dart';
import 'legacy_password_store.dart';
import 'secure_storage_facade.dart';

// The storage facade, the protection tri-state and the legacy store live next
// door; re-exported so existing importers of this file keep resolving them.
export 'legacy_password_store.dart';
export 'secure_storage_facade.dart';

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
    // Read the legacy entry through the migrating reader so this call keeps
    // performing the opportunistic "lift the plain-prefs hash into secure
    // storage" step that `hasPassword` used to do via `_readHashWithMigration`.
    // Dropping it would have left pre-S1 installs with a world-readable hash on
    // disk until the user happened to VERIFY a password (the only other path
    // that migrates) — which a user who never types their password again never
    // does.
    //
    // Migration only removes the legacy entry when the secure write actually
    // persisted, so an unavailable store cannot lose the hash here.
    // `_readHashWithMigration` covers the legacy plain-prefs entry AND the
    // 64-char public-key alias. Both must count as "protected" here, or a
    // half-migrated account would read as unprotected and the auto-login gate
    // would wave it through.
    final legacy = await _readHashWithMigration(toxId);
    if (legacy != null && legacy.isNotEmpty) {
      return AccountProtectionState.protected;
    }
    // The alias read above cannot tell "no hash" from "could not read" (a
    // locked iPhone); ask again with the outcome, or a verifier still under
    // the alias would pass the gate as "none" (B9).
    final alias = _publicKeyAlias(toxId);
    final aliasUnreadable = alias != null &&
        (await _secureStorage.readOutcome(secureHashKey(alias))).unavailable;
    return secure.unavailable || aliasUnreadable
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
  Future<bool> setPassword(String toxId, SecretPassword password) async {
    if (toxId.isEmpty) {
      throw ArgumentError('toxId cannot be empty');
    }
    if (password.isEmpty) {
      return removePassword(toxId);
    }
    final derived = await deriveVerifier(password);
    return writePrimaryVerifier(toxId, derived.hash, derived.salt);
  }

  /// [setPassword] for a String; tests only (production converts at the edge).
  @visibleForTesting
  Future<bool> setPasswordText(String toxId, String password) =>
      SecretPassword.use(password, (secret) => setPassword(toxId, secret));

  /// A fresh salt and the PBKDF2 hash of [password] over it, in the stored
  /// wire format. Pure: nothing is written.
  Future<({String hash, String salt})> deriveVerifier(
    SecretPassword password,
  ) async {
    final salt = List<int>.generate(_saltBytes, (_) => Random.secure().nextInt(256));
    final hashBytes = await _pbkdf2(password, salt);
    return (hash: '$pbkdf2Prefix${base64Encode(hashBytes)}', salt: base64Encode(salt));
  }

  /// PBKDF2-HMAC-SHA256 of [password]'s UTF-8 bytes over [salt]. Byte-identical
  /// to `deriveKeyFromPassword`, which is `utf8.encode` + `deriveKey`.
  ///
  /// The KDF runs on a PRIVATE copy taken synchronously, zeroed when the
  /// derivation ends: the caller's buffer is borrowed, and a concurrent
  /// dispose() of it must neither corrupt a running derivation nor be undone
  /// by a copy that outlives the call. (HMAC's own padded key blocks inside
  /// package:cryptography are beyond reach.)
  static Future<List<int>> _pbkdf2(SecretPassword password, List<int> salt) async {
    final key = SecretKeyData(
      password.withBytes(Uint8List.fromList),
      overwriteWhenDestroyed: true,
    );
    try {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: pbkdf2Iterations,
        bits: pbkdf2Bits,
      );
      final derived = await pbkdf2.deriveKey(secretKey: key, nonce: salt);
      return await derived.extractBytes();
    } finally {
      key.destroy();
    }
  }

  /// Installs an already-derived verifier as the primary one (both keys, the
  /// prior pair restored when either write fails) and retires the legacy
  /// entries. This is the promote step of a journaled password change, which
  /// must reuse the EXACT hash/salt it recorded rather than derive again.
  Future<bool> writePrimaryVerifier(String toxId, String storedHash, String storedSalt) async {

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
  /// Returns true only when every source (secure pair, alias pair, legacy
  /// entries) is gone; false when any delete was swallowed.
  Future<bool> removePassword(String toxId) async {
    if (toxId.isEmpty) return true;
    // Every source, and ALL of them decide the result: the secure pair, the
    // 64-char public-key alias pair (`ShortToxIdBackfill` re-keys a verifier
    // from the public key to the full address, and an interrupted migration
    // leaves the alias copy behind, which `_lookup` would migrate back and
    // reinstate a revoked password) and both legacy plain-prefs entries. A
    // partial removal returns false so nobody concludes "unprotected" while
    // some source could still gate — or half-gate — the account.
    var ok = await _secureStorage.delete(secureHashKey(toxId));
    ok = await _secureStorage.delete(secureSaltKey(toxId)) && ok;
    final alias = _publicKeyAlias(toxId);
    if (alias != null) {
      ok = await _secureStorage.delete(secureHashKey(alias)) && ok;
      ok = await _secureStorage.delete(secureSaltKey(alias)) && ok;
      ok = await _removeLegacyQuietly(alias) && ok;
    }
    return await _removeLegacyQuietly(toxId) && ok;
  }

  Future<bool> _removeLegacyQuietly(String toxId) async {
    try {
      await _legacyStore.removeLegacyHash(toxId);
      await _legacyStore.removeLegacySalt(toxId);
      return true;
    } catch (e) {
      AppLogger.warn('[PasswordVerifier] legacy entry removal failed: $e');
      return false;
    }
  }

  /// Constant-time check of [password] against a stored PBKDF2 verifier
  /// (modern wire format only; the legacy formats are [verifyPassword]'s job).
  Future<bool> matchesPbkdf2(
    SecretPassword password,
    String storedHash,
    String? saltBase64,
  ) async {
    if (!storedHash.startsWith(pbkdf2Prefix) || saltBase64 == null) return false;
    List<int> salt;
    try {
      salt = base64Decode(saltBase64);
    } catch (_) {
      return false;
    }
    final hashBytes = await _pbkdf2(password, salt);
    return constantTimeEquals(
      storedHash.substring(pbkdf2Prefix.length),
      base64Encode(hashBytes),
    );
  }

  /// Verify [password] against the stored hash for [toxId].
  ///
  /// Supports PBKDF2 (new) and legacy SHA-256 (salted and unsalted); on a
  /// successful legacy verify, the password is re-hashed with PBKDF2 and
  /// the new format is persisted before returning true.
  Future<bool> verifyPassword(String toxId, SecretPassword password) async {
    if (toxId.isEmpty || password.isEmpty) return false;

    final storedHash = await _readHashWithMigration(toxId);
    if (storedHash == null) return false;
    final saltBase64 = await _readSaltWithMigration(toxId);

    if (storedHash.startsWith(pbkdf2Prefix)) {
      return matchesPbkdf2(password, storedHash, saltBase64);
    }

    // Legacy SHA-256 (salted or unsalted) — migrate on success.
    final salted = saltBase64 != null && saltBase64.isNotEmpty;
    if (storedHash != _legacySha256(salted ? saltBase64 : '', password)) {
      return false;
    }
    final migrated = await setPassword(toxId, password);
    if (!migrated) {
      // Verify still succeeded; the legacy hash remains valid for the next
      // attempt. Surface the failure for diagnosability.
      AppLogger.warn(
        '[PasswordVerifier] PBKDF2 migration after legacy '
        '${salted ? 'salted' : 'unsalted'}-SHA256 verify failed for '
        'toxId=$toxId (secure storage unavailable); legacy entry retained.',
      );
    }
    return true;
  }

  /// [verifyPassword] for a String; tests only.
  @visibleForTesting
  Future<bool> verifyPasswordText(String toxId, String password) =>
      SecretPassword.use(password, (secret) => verifyPassword(toxId, secret));

  /// Hex SHA-256 of `utf8(saltPrefix) + passwordBytes` — byte-identical to
  /// the legacy `sha256(utf8.encode('$salt$password'))` — over a buffer that
  /// is zeroed before returning.
  static String _legacySha256(String saltPrefix, SecretPassword password) {
    final saltBytes = utf8.encode(saltPrefix);
    final input = password.withBytes((bytes) {
      final joined = Uint8List(saltBytes.length + bytes.length);
      joined.setAll(0, saltBytes);
      joined.setAll(saltBytes.length, bytes);
      return joined;
    });
    try {
      return crypto.sha256.convert(input).toString();
    } finally {
      input.fillRange(0, input.length, 0);
    }
  }

  /// Read PBKDF2 hash from secure storage, migrating any legacy plain-prefs
  /// value into the secure store on first hit. Returns null when no password
  /// is set for the account.
  Future<String?> _readHashWithMigration(String toxId) async {
    if (toxId.isEmpty) return null;
    final secureKey = secureHashKey(toxId);
    final fromSecure = await _secureStorage.read(secureKey);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    // Alias: the 64-char public-key form of a 76-char address.
    //
    // `ShortToxIdBackfill` rewrites an imported account's id from the 64-char
    // public key to the 76-char address, and it cannot move the registry row and
    // the credential keys in one atomic step. It now moves the ROW first
    // precisely so the surviving mismatch is this one — row at 76, keys still at
    // 64 — because 64 is derivable from 76 by truncation while the reverse is
    // not (nospam+checksum are not recoverable). Looking under the alias makes
    // that window benign instead of leaving the account unverifiable.
    final alias = await _readAliasHash(toxId);
    if (alias != null) return alias;
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
    // And the LEGACY store under the alias. Looking for the alias only in
    // secure storage left a fail-OPEN gap: a pre-S1 install whose credential is
    // still `account_password_<64char>`, and whose `ShortToxIdBackfill` rewrote
    // the registry row but did not finish `migrateAccountPasswordKeys`, has its
    // row at 76 and its only hash at legacy-64. Secure storage answers (with
    // nothing), so `protectionState` reports `none` rather than `unknown` and
    // the auto-login gate opens an account whose password is still on disk.
    // `short_tox_id_backfill.dart` justifies continuing past a failed key
    // migration with "the credential stays under the alias, which
    // PasswordVerifier resolves" - true for secure entries, and now true here.
    final aliasId = _publicKeyAlias(toxId);
    if (aliasId != null) {
      final aliasLegacy = await _legacyStore.readLegacyHash(aliasId);
      if (aliasLegacy != null && aliasLegacy.isNotEmpty) {
        if (await _secureStorage.write(secureKey, aliasLegacy)) {
          await _legacyStore.removeLegacyHash(aliasId);
        }
        return aliasLegacy;
      }
    }
    return null;
  }

  /// The 64-char public-key form of a 76-char Tox address, or null when [toxId]
  /// is not a full address (so there is no distinct alias to try).
  static String? _publicKeyAlias(String toxId) {
    final normalized = toxId.trim();
    if (normalized.length <= 64) return null;
    return normalized.substring(0, 64);
  }

  /// Hash stored under the public-key alias, migrated to the canonical key.
  ///
  /// Migration is opportunistic and only removes the alias entry once the
  /// canonical write actually persisted — the same rule the legacy plain-prefs
  /// migration follows, for the same reason.
  Future<String?> _readAliasHash(String toxId) async {
    final alias = _publicKeyAlias(toxId);
    if (alias == null) return null;
    final value = await _secureStorage.read(secureHashKey(alias));
    if (value == null || value.isEmpty) return null;
    if (await _secureStorage.write(secureHashKey(toxId), value)) {
      await _secureStorage.delete(secureHashKey(alias));
    }
    return value;
  }

  /// Salt stored under the public-key alias. See [_readAliasHash].
  Future<String?> _readAliasSalt(String toxId) async {
    final alias = _publicKeyAlias(toxId);
    if (alias == null) return null;
    final value = await _secureStorage.read(secureSaltKey(alias));
    if (value == null || value.isEmpty) return null;
    if (await _secureStorage.write(secureSaltKey(toxId), value)) {
      await _secureStorage.delete(secureSaltKey(alias));
    }
    return value;
  }

  /// Read salt from secure storage, migrating from legacy plain prefs when
  /// present. Returns null when no salt is stored.
  Future<String?> _readSaltWithMigration(String toxId) async {
    if (toxId.isEmpty) return null;
    final secureKey = secureSaltKey(toxId);
    final fromSecure = await _secureStorage.read(secureKey);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    // Salt must follow the hash through the alias, or a half-migrated account
    // would pair a found hash with a missing salt and fail to verify.
    final alias = await _readAliasSalt(toxId);
    if (alias != null) return alias;
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
    // The salt follows the hash through the LEGACY alias too, for the same
    // reason it follows it through the secure one: a hash found under the alias
    // and a salt that was not looked for there verify against nothing.
    final aliasId = _publicKeyAlias(toxId);
    if (aliasId != null) {
      final aliasLegacy = await _legacyStore.readLegacySalt(aliasId);
      if (aliasLegacy != null && aliasLegacy.isNotEmpty) {
        if (await _secureStorage.write(secureKey, aliasLegacy)) {
          await _legacyStore.removeLegacySalt(aliasId);
        }
        return aliasLegacy;
      }
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
