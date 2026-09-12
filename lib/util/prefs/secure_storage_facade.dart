// Where a password verifier LIVES: the platform secure-storage facade, the
// on-disk shapes a verifier can take, and the account-protection tri-state.
//
// Split out of `password_verifier.dart` (complexity-gate pin). Kept together
// because they are one idea: the facade is the only thing that knows whether the
// backend ANSWERED, `AccountProtectionState` is how that reaches the callers who
// must fail closed when it did not, and `StoredPasswordVerifier` /
// `PasswordVerifierLookup` are the shapes that travel between them.
// `password_verifier.dart` owns the CRYPTO and the ordering; this file owns the
// formats and the storage contract.

import 'dart:convert';

import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Legacy plain-prefs keys — kept ONLY for read-time migration into secure
// storage; new writes never touch them. Both forms were stored as plain text and
// would otherwise sync to iCloud on iOS / sit as world-readable XML on rooted
// Android. Mirrored as `PasswordVerifier.legacyHashKey` / `.legacySaltKey` so
// callers like `Prefs.clearAccountData` can list them for explicit cleanup.
String legacyPasswordHashKey(String toxId) => 'account_password_$toxId';
const String legacyPasswordSaltPrefix = 'account_password_salt_';
String legacyPasswordSaltKey(String toxId) =>
    '$legacyPasswordSaltPrefix$toxId';

/// Adapter for the legacy plain-text SharedPreferences password entries
/// (`account_password_<toxId>` hash and `account_password_salt_<toxId>` salt).
/// These were the pre-S1 storage location; new writes never touch them, but
/// existing installs may still have them on disk and we migrate on first read.
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
    return p.getString(legacyPasswordHashKey(toxId));
  }

  @override
  Future<String?> readLegacySalt(String toxId) async {
    final p = await _prefsProvider();
    return p.getString(legacyPasswordSaltKey(toxId));
  }

  @override
  Future<void> removeLegacyHash(String toxId) async {
    final p = await _prefsProvider();
    await p.remove(legacyPasswordHashKey(toxId));
  }

  @override
  Future<void> removeLegacySalt(String toxId) async {
    final p = await _prefsProvider();
    await p.remove(legacyPasswordSaltKey(toxId));
  }
}

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

/// The password verifier as ONE secure-storage value: the PBKDF2 hash and the
/// salt that produced it, encoded together so a single `write` either lands
/// both or neither.
///
/// WHY IT EXISTS (defect A8). The verifier used to be two independent
/// secure-storage entries (`pwd_<toxId>` and `pwd_salt_<toxId>`) written one
/// after the other. A kill, crash or backgrounded-app eviction between the two
/// writes left a hash paired with the PREVIOUS salt (or with no salt at all),
/// and PBKDF2 over the wrong salt never reproduces the stored digest — so every
/// password the user typed from then on was rejected, forever, with no repair
/// path. Storing the pair as one value removes the window: there is no
/// "between" for a single key/value write.
///
/// COMPATIBILITY. The legacy `pwd_` / `pwd_salt_` pair is still written and kept
/// in sync by [PasswordVerifier], because an older build knows nothing about
/// this key and would otherwise find no verifier where it expects one — which is
/// either "your password is gone" or, worse, "your account is now unprotected".
/// This record is the preferred read; the pair is the fallback and the
/// downgrade surface.
///
/// The encoding is JSON so the shape is self-describing and versioned. [decode]
/// is total: anything it cannot make sense of (truncated value, wrong version,
/// missing field) returns null, and the caller falls back to the legacy pair
/// rather than treating the account as unprotected.
///
/// ON-DISK SHAPES, before and after A8, for one account:
///
///     before:  pwd_<toxId>      = "pbkdf2:<base64 digest>"
///              pwd_salt_<toxId> = "<base64 salt>"
///     after:   pwdrec_<toxId>   = {"v":1,"h":"pbkdf2:<digest>","s":"<salt>"}
///              pwd_<toxId>      = "pbkdf2:<base64 digest>"   (unchanged)
///              pwd_salt_<toxId> = "<base64 salt>"            (unchanged)
///
/// Nothing was removed or re-spelled; one key was added and is written first.
///
/// CRASH-WINDOW ANALYSIS — `PasswordVerifier.setPassword` writes the record,
/// then the hash, then the salt. "prev" is the password in force before the
/// call (possibly none). For each point the process can die:
///
///   (0) before the record write — record=prev, pair=prev.
///       new build: prev works.  old build: prev works.
///   (1) after the record write, before the hash write — record=NEW, pair=prev.
///       new build: reads the record, NEW works. THIS is the A8 fix: the old
///         two-write code had no shape here that anyone could verify, and the
///         account was bricked permanently.
///       old build: reads the pair, prev works. With no prev, an old build sees
///         no verifier and reports the account UNPROTECTED — a window two
///         adjacent secure-storage writes wide that also requires downgrading
///         before the new build reads again, because
///         `PasswordVerifier._syncLegacyPair` re-mirrors the pair on the very
///         next read and every protection check performs one.
///   (2) after the hash write, before the salt write — record=NEW, hash=NEW,
///       salt=prev/absent.
///       new build: reads the record, NEW works, and the same read repairs the
///         salt.
///       old build: hash=NEW + salt=prev is the original A8 lockout, now
///         reachable only by a build that also predates the repair. Hash before
///         salt is still correct: the reverse ordering makes the same kill look
///         like "no hash", i.e. an old build silently dropping protection on a
///         first-ever password. Refusing entry beats granting it.
///   (3) after the salt write, before the pre-S1 plain-prefs cleanup —
///       record=NEW, pair=NEW, stale plain-prefs entries.
///       both builds: NEW works (secure storage outranks plain prefs).
///
/// No interruption point leaves a state in which the NEW build cannot verify a
/// password the user knows. That is the property A8 was missing.
///
/// REMOVAL runs the reverse order (record, then pair, then the alias copies),
/// so a kill mid-removal leaves record=absent/pair=present: both builds still
/// report the account protected and the user simply retries. Pair-first would
/// leave a new build protected while a downgraded one silently drops
/// protection.
final class StoredPasswordVerifier {
  const StoredPasswordVerifier({required this.hash, required this.salt});

  /// Wire version. Bump only alongside a decoder that still accepts 1.
  static const int version = 1;

  /// The stored hash, including its `pbkdf2:` prefix.
  final String hash;

  /// Base64 salt that [hash] was derived with.
  final String salt;

  String encode() => jsonEncode(<String, Object?>{
        'v': version,
        'h': hash,
        's': salt,
      });

  /// Parse a stored record, or null when [raw] is absent/unparseable/foreign.
  static StoredPasswordVerifier? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['v'] != version) return null;
    final hash = decoded['h'];
    final salt = decoded['s'];
    if (hash is! String || hash.isEmpty) return null;
    if (salt is! String || salt.isEmpty) return null;
    return StoredPasswordVerifier(hash: hash, salt: salt);
  }
}

/// What `PasswordVerifier` resolved for an account after trying every shape,
/// plus the one bit a nullable hash cannot carry: whether some shape was
/// unreadable.
///
/// [unavailable] with a null [hash] means "we do not know whether this account
/// is protected" and MUST NOT be reported as unprotected — that distinction is
/// the whole reason [SecureStorageReadOutcome] exists.
final class PasswordVerifierLookup {
  const PasswordVerifierLookup({
    this.hash,
    this.salt,
    this.unavailable = false,
  });

  /// The stored hash (PBKDF2-prefixed, or a legacy SHA-256 digest).
  final String? hash;

  /// Base64 salt that goes with [hash]; null for unsalted legacy entries.
  final String? salt;

  /// True when at least one secure-storage read was refused or absent.
  final bool unavailable;
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
