// PBKDF2/SHA-256 password hashing + verification for toxee accounts.
//
// Extracted from `lib/util/prefs.dart` (S1 review). This file owns the PBKDF2
// parameters (150k iters, 256-bit key, HMAC-SHA-256), the legacy-SHA256
// verify-and-migrate path, the constant-time comparison, and the ORDER in which
// the stored shapes are written and deleted. The shapes themselves — the atomic
// `StoredPasswordVerifier` record and its crash-window analysis — live in
// `secure_storage_facade.dart`.
//
// Dependencies are injected so the class is unit-testable without driving the
// real Keychain/Keystore: a [FlutterSecureStorageFacade] in production, an
// in-memory or write-failure-simulating [SecureStorageFacade] in tests. The
// [LegacyPasswordStore] adapter abstracts the pre-S1 plain-text
// SharedPreferences entries we still need to read for migration.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../logger.dart';
import 'secure_storage_facade.dart';

// The storage facade, the stored shapes, the protection tri-state and the
// legacy-prefs adapters live next door; re-exported so existing importers of
// this file keep resolving them.
export 'secure_storage_facade.dart';

/// PBKDF2/SHA-256 password hashing + verification.
///
/// Stored hash format: `"pbkdf2:" + base64(PBKDF2-HMAC-SHA256(password, salt,
/// 150_000, 256 bits))`, persisted with its base64 salt as one atomic
/// [StoredPasswordVerifier] record and mirrored onto the legacy split pair for
/// older builds. Verifications use constant-time comparison to defeat timing
/// side channels.
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
  //
  // `pwdrec_` holds the atomic [StoredPasswordVerifier] and is the preferred
  // read; `pwd_` / `pwd_salt_` are the legacy split pair, still written and kept
  // in sync because an older build reads only those. Deliberately NOT spelled
  // `pwd_rec_`: call sites (e.g. `account_registration_password_failure_test`)
  // classify keys with `startsWith('pwd_') && !startsWith('pwd_salt_')` to mean
  // "the hash", and a third `pwd_`-prefixed key would be misread as one.
  static String secureRecordKey(String toxId) => 'pwdrec_$toxId';
  static String secureHashKey(String toxId) => 'pwd_$toxId';
  static String secureSaltKey(String toxId) => 'pwd_salt_$toxId';

  // Legacy plain-prefs keys, defined in `secure_storage_facade.dart` next to the
  // adapter that reads them. Mirrored here because callers reach them as
  // `PasswordVerifier.legacyHashKey` / `.legacySaltKey`.
  static String legacyHashKey(String toxId) => legacyPasswordHashKey(toxId);
  static const String legacySaltPrefix = legacyPasswordSaltPrefix;
  static String legacySaltKey(String toxId) => legacyPasswordSaltKey(toxId);

  /// Whether [toxId] is password-protected, distinguishing "not protected"
  /// from "secure storage would not answer".
  ///
  /// Resolution order is [_lookup]'s. Any shape that resolves proves the
  /// account IS protected, so there is nothing uncertain left to report even if
  /// another shape was unreadable. Going through [_lookup] also keeps the
  /// opportunistic migrations on this path: a user who never types their
  /// password again never triggers the only other migrating path
  /// (`verifyPassword`), and would keep a world-readable plain-prefs hash — or,
  /// post-A8, no crash-safe record — indefinitely.
  Future<AccountProtectionState> protectionState(String toxId) async {
    if (toxId.isEmpty) return AccountProtectionState.none;
    final found = await _lookup(toxId);
    if (found.hash != null && found.hash!.isNotEmpty) {
      return AccountProtectionState.protected;
    }
    // FAIL CLOSED: "the Keychain would not answer" must never read as `none`.
    return found.unavailable
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
  Future<String?> getPasswordHash(String toxId) async =>
      (await _lookup(toxId)).hash;

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

    // Snapshot any prior secure-storage state so we can restore it if one of
    // the writes below is REFUSED (returns false). Rollback covers the
    // in-process failure; the write ORDER below covers the out-of-process one
    // (a kill), where no rollback code runs at all.
    final priorRecord = await _secureStorage.read(secureRecordKey(toxId));
    final priorHash = await _secureStorage.read(secureHashKey(toxId));
    final priorSalt = await _secureStorage.read(secureSaltKey(toxId));

    // ORDER: atomic record FIRST, then the legacy hash, then the legacy salt.
    // Getting this backwards reintroduces A8, so the point-by-point
    // crash-window analysis lives with the format it is about — see
    // "CRASH-WINDOW ANALYSIS" on [StoredPasswordVerifier]. In short: a kill at
    // any point leaves a shape THIS build can still verify, and leaves an older
    // build reading either the new password or the previous one, never a
    // half-written pair it would reject forever.
    final recordWrote = await _secureStorage.write(
      secureRecordKey(toxId),
      StoredPasswordVerifier(hash: storedHash, salt: storedSalt).encode(),
    );
    final hashWrote = await _secureStorage.write(secureHashKey(toxId), storedHash);
    final saltWrote = await _secureStorage.write(secureSaltKey(toxId), storedSalt);
    if (!recordWrote || !hashWrote || !saltWrote) {
      // Best-effort rollback: restore the snapshot. If the restore writes
      // themselves fail we are no worse off than the partial-write state we
      // entered with, and most platforms either accept all writes or reject all
      // (MissingPluginException, sandbox denial). All THREE shapes unwind
      // together — a NEW record left beside a restored prev pair would hand the
      // two builds different passwords. The legacy plain-prefs entries are left
      // alone either way; they remain the durable fallback.
      await _restore(secureRecordKey(toxId), priorRecord);
      await _restore(secureHashKey(toxId), priorHash);
      await _restore(secureSaltKey(toxId), priorSalt);
      return false;
    }
    // Drop legacy plain-prefs entries if a prior install left them behind.
    await Future.wait([
      _legacyStore.removeLegacyHash(toxId),
      _legacyStore.removeLegacySalt(toxId),
    ]);
    return true;
  }

  /// Restore one secure-storage slot to its pre-call value — writing [prior]
  /// back, or deleting the slot when there was nothing there.
  Future<void> _restore(String key, String? prior) async {
    if (prior != null && prior.isNotEmpty) {
      await _secureStorage.write(key, prior);
    } else {
      await _secureStorage.delete(key);
    }
  }

  /// Remove the stored password for [toxId] — EVERY shape of it: the atomic
  /// record, the legacy hash/salt pair, both of those under the 64-char
  /// public-key alias, and the pre-S1 plain-prefs entries.
  ///
  /// Missing any one would leave the account still protected by a verifier the
  /// user just deleted; the alias copies in particular survive an interrupted
  /// `ShortToxIdBackfill` and are resolved by [_lookup] like canonical ones.
  ///
  /// ORDER is the reverse of [setPassword]'s — record first — so a kill
  /// mid-removal leaves both builds reporting "still protected" rather than a
  /// downgraded build silently unprotected. See [StoredPasswordVerifier].
  ///
  /// Returns true when every secure delete succeeded (and the legacy entries
  /// were also cleared); false when any was swallowed, in which case the legacy
  /// plain-prefs entries are left in place so we don't destroy the last
  /// remaining copy of the credential.
  Future<bool> removePassword(String toxId) async {
    if (toxId.isEmpty) return true;
    // `&& deleted` on the right so every delete is actually attempted —
    // short-circuiting would skip shapes after the first refusal.
    var deleted = await _secureStorage.delete(secureRecordKey(toxId));
    deleted = await _secureStorage.delete(secureHashKey(toxId)) && deleted;
    deleted = await _secureStorage.delete(secureSaltKey(toxId)) && deleted;
    final alias = _publicKeyAlias(toxId);
    if (alias != null) {
      deleted = await _secureStorage.delete(secureRecordKey(alias)) && deleted;
      deleted = await _secureStorage.delete(secureHashKey(alias)) && deleted;
      deleted = await _secureStorage.delete(secureSaltKey(alias)) && deleted;
    }
    if (!deleted) {
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

    final found = await _lookup(toxId);
    final storedHash = found.hash;
    if (storedHash == null) return false;
    final saltBase64 = found.salt;

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

    // Legacy SHA-256, salted or unsalted — migrate on success. A stored salt
    // selects the salted form; there is no fallback between them, because the
    // two formats were never both valid for one account.
    final salted = saltBase64 != null && saltBase64.isNotEmpty;
    final digest = crypto.sha256
        .convert(utf8.encode(salted ? '$saltBase64$password' : password));
    if (storedHash != digest.toString()) return false;
    if (!await setPassword(toxId, password)) {
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

  /// Resolve the verifier for [toxId] across every shape it can take, newest
  /// first, migrating older shapes forward as it goes.
  ///
  ///   1. the atomic [StoredPasswordVerifier] record (`pwdrec_<toxId>`);
  ///   2. the same record under the 64-char public-key alias — promoted to the
  ///      canonical key;
  ///   3. the legacy hash/salt pair, itself resolved through the alias and the
  ///      pre-S1 plain-prefs entries — promoted into an atomic record.
  ///
  /// Every caller goes through here, so reading a protected account once is
  /// enough to upgrade it AND to repair a pair left stale by an interrupted
  /// [setPassword]. `unavailable` is the union of the secure-storage outages
  /// hit on the way, so [protectionState] can fail closed instead of reporting
  /// "no password".
  Future<PasswordVerifierLookup> _lookup(String toxId) async {
    if (toxId.isEmpty) return const PasswordVerifierLookup();
    var unavailable = false;

    final record = await _secureStorage.readOutcome(secureRecordKey(toxId));
    unavailable = unavailable || record.unavailable;
    final parsed = StoredPasswordVerifier.decode(record.value);
    if (parsed != null) {
      await _syncLegacyPair(toxId, parsed);
      return PasswordVerifierLookup(
        hash: parsed.hash,
        salt: parsed.salt,
        unavailable: unavailable,
      );
    }

    final alias = _publicKeyAlias(toxId);
    if (alias != null) {
      final aliasRecord =
          await _secureStorage.readOutcome(secureRecordKey(alias));
      unavailable = unavailable || aliasRecord.unavailable;
      final aliasParsed = StoredPasswordVerifier.decode(aliasRecord.value);
      if (aliasParsed != null) {
        // Promote, then drop the alias copies — canonical first so a kill in
        // between never leaves the account with no readable verifier.
        if (await _secureStorage.write(
            secureRecordKey(toxId), aliasRecord.value!)) {
          await _syncLegacyPair(toxId, aliasParsed);
          await _secureStorage.delete(secureRecordKey(alias));
          await _secureStorage.delete(secureHashKey(alias));
          await _secureStorage.delete(secureSaltKey(alias));
        }
        return PasswordVerifierLookup(
          hash: aliasParsed.hash,
          salt: aliasParsed.salt,
          unavailable: unavailable,
        );
      }
    }

    // No record — the pre-A8 on-disk shape (or an install this build has never
    // read). Fall back to the split pair, which still carries the alias and
    // plain-prefs migrations.
    final hashOutcome = await _secureStorage.readOutcome(secureHashKey(toxId));
    unavailable = unavailable || hashOutcome.unavailable;
    final hash = hashOutcome.hasValue
        ? hashOutcome.value
        : await _readHashWithMigration(toxId);
    if (hash == null || hash.isEmpty) {
      return PasswordVerifierLookup(unavailable: unavailable);
    }
    final salt = await _readSaltWithMigration(toxId);
    // Upgrade to the atomic record so this account gains crash-safety without
    // waiting for the user to change their password. Only a complete PBKDF2
    // pair is promoted: a bare legacy SHA-256 hash has no salt to pair with and
    // gets rewritten wholesale by `verifyPassword`'s re-hash on next success.
    if (hash.startsWith(pbkdf2Prefix) && salt != null && salt.isNotEmpty) {
      await _secureStorage.write(secureRecordKey(toxId),
          StoredPasswordVerifier(hash: hash, salt: salt).encode());
    }
    return PasswordVerifierLookup(hash: hash, salt: salt, unavailable: unavailable);
  }

  /// Mirror an atomic record back onto the legacy `pwd_` / `pwd_salt_` pair
  /// when the two have drifted apart.
  ///
  /// This is what makes the downgrade story hold. The pair is the ONLY shape an
  /// older build understands, and every crash window in [setPassword] ends with
  /// a record newer than the pair; re-mirroring on read closes them, so any
  /// protection check or verify this build runs leaves an older build reading
  /// the same password. Writes happen only on a real mismatch.
  Future<void> _syncLegacyPair(
      String toxId, StoredPasswordVerifier record) async {
    final hash = await _secureStorage.read(secureHashKey(toxId));
    final salt = await _secureStorage.read(secureSaltKey(toxId));
    if (hash == record.hash && salt == record.salt) return;
    // Hash first, matching setPassword: an interrupted repair must never leave
    // a salt without a hash, which an old build reads as "unprotected".
    if (await _secureStorage.write(secureHashKey(toxId), record.hash)) {
      await _secureStorage.write(secureSaltKey(toxId), record.salt);
    }
  }

  /// Read ONE half of the legacy split verifier — [secureKeyFor] picks hash or
  /// salt — resolving the two older places it can still be sitting in and
  /// migrating each forward. Hash and salt deliberately share this code: a
  /// found hash paired with a missed salt fails to verify just as hard as no
  /// hash at all, so their resolution rules must not drift apart.
  ///
  ///  * ALIAS — the 64-char public-key form of a 76-char address.
  ///    `ShortToxIdBackfill` rewrites an imported account's id from the public
  ///    key to the full address and cannot move the registry row and the
  ///    credential keys in one atomic step. It moves the ROW first precisely so
  ///    the surviving mismatch is this one — row at 76, keys still at 64 —
  ///    because 64 is derivable from 76 by truncation while the reverse is not
  ///    (nospam+checksum are not recoverable). Looking under the alias makes
  ///    that window benign instead of leaving the account unverifiable.
  ///  * PLAIN PREFS — the pre-S1 location, plain text on disk.
  ///
  /// Both migrations drop the old copy ONLY once the canonical write actually
  /// persisted: a swallowed keychain failure that still deleted the source
  /// would destroy the last copy of the credential.
  Future<String?> _readLegacyHalf(
    String toxId,
    String Function(String) secureKeyFor,
    Future<String?> Function(String) readPlainPrefs,
    Future<void> Function(String) removePlainPrefs,
  ) async {
    if (toxId.isEmpty) return null;
    final secureKey = secureKeyFor(toxId);
    final fromSecure = await _secureStorage.read(secureKey);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    final alias = _publicKeyAlias(toxId);
    if (alias != null) {
      final aliased = await _secureStorage.read(secureKeyFor(alias));
      if (aliased != null && aliased.isNotEmpty) {
        if (await _secureStorage.write(secureKey, aliased)) {
          await _secureStorage.delete(secureKeyFor(alias));
        }
        return aliased;
      }
    }
    final legacy = await readPlainPrefs(toxId);
    if (legacy != null && legacy.isNotEmpty) {
      if (await _secureStorage.write(secureKey, legacy)) {
        await removePlainPrefs(toxId);
      }
      return legacy;
    }
    return null;
  }

  /// Legacy-pair hash for [toxId]. Null when no password is set.
  Future<String?> _readHashWithMigration(String toxId) => _readLegacyHalf(
      toxId,
      secureHashKey,
      _legacyStore.readLegacyHash,
      _legacyStore.removeLegacyHash);

  /// Legacy-pair salt for [toxId]. Null when no salt is stored.
  Future<String?> _readSaltWithMigration(String toxId) => _readLegacyHalf(
      toxId,
      secureSaltKey,
      _legacyStore.readLegacySalt,
      _legacyStore.removeLegacySalt);

  /// The 64-char public-key form of a 76-char Tox address, or null when [toxId]
  /// is not a full address (so there is no distinct alias to try).
  static String? _publicKeyAlias(String toxId) {
    final normalized = toxId.trim();
    if (normalized.length <= 64) return null;
    return normalized.substring(0, 64);
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
