// Regression tests for A8: the password verifier was TWO secure-storage
// entries written one after the other.
//
// `pwd_<toxId>` held the PBKDF2 hash and `pwd_salt_<toxId>` held the salt it was
// derived with, and `setPassword` wrote them in sequence. A kill between the two
// writes — a crash, a force-quit, or the OS evicting a backgrounded app, which
// mobile does routinely — left the new hash paired with the PREVIOUS salt.
// PBKDF2 over the wrong salt never reproduces the stored digest, so from that
// moment EVERY password the user typed was rejected. The account stayed
// password-protected, could not be opened, and nothing in the app repaired it.
//
// The fix writes the pair as one atomic `pwdrec_<toxId>` record FIRST, then
// mirrors it onto the legacy pair so a downgraded build still finds a verifier
// it understands. These tests pin the resulting behaviour at each interruption
// point, in both directions of the version skew.
//
// HOW THE KILL IS SIMULATED. `TestDefaultBinaryMessenger`'s mock handler turns
// every thrown object into a `PlatformException` on the caller's side, which
// `FlutterSecureStorageFacade` swallows into `write -> false` — that is a
// REFUSED write, and it runs `setPassword`'s rollback. A kill runs nothing. So
// the kill is simulated by having the mock handler return a future that never
// completes at the chosen write: the in-flight `setPassword` is abandoned
// exactly where the process would have died, nothing after it executes, and the
// store is left holding precisely the on-disk shape a kill produces. A fresh
// `PasswordVerifier` over the same store is then the next app launch.

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/prefs/password_verifier.dart';

/// In-memory [LegacyPasswordStore]; the pre-S1 plain-prefs entries without a
/// SharedPreferences channel.
class _FakeLegacyStore implements LegacyPasswordStore {
  final Map<String, String> hashes = <String, String>{};
  final Map<String, String> salts = <String, String>{};

  @override
  Future<String?> readLegacyHash(String toxId) async => hashes[toxId];

  @override
  Future<String?> readLegacySalt(String toxId) async => salts[toxId];

  @override
  Future<void> removeLegacyHash(String toxId) async => hashes.remove(toxId);

  @override
  Future<void> removeLegacySalt(String toxId) async => salts.remove(toxId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  // The "disk". Survives across `PasswordVerifier` instances, which is what
  // makes "kill the app, launch it again" expressible.
  final store = <String, String>{};
  late _FakeLegacyStore legacy;

  /// When non-null, the 1-based write ordinal at which the process "dies":
  /// that write and every later one never returns.
  int? killAtWrite;
  var writeCount = 0;

  /// Keys written, in order — so the tests can assert that the atomic record
  /// really does go first.
  final writes = <String>[];

  /// Completed by the mock handler the instant the kill point is reached, so a
  /// test can wait for the exact pre-kill shape instead of racing the (slow,
  /// 150k-iteration) PBKDF2 derivation that precedes the writes.
  var killReached = Completer<void>();

  /// When true, every read reports the backend as absent — the
  /// `MissingPluginException` a locked Keychain / entitlement-less sandbox
  /// produces, which the facade maps to `SecureStorageReadOutcome.unavailable`.
  var readsUnavailable = false;

  /// Verify [password] the way a build that predates A8 does: read the two
  /// legacy keys, derive PBKDF2 with the stored salt, compare. Nothing here
  /// knows `pwdrec_` exists. This is the downgrade oracle.
  Future<bool> verifyAsOldBuild(String toxId, String password) async {
    final storedHash = store[PasswordVerifier.secureHashKey(toxId)];
    final storedSalt = store[PasswordVerifier.secureSaltKey(toxId)];
    if (storedHash == null || storedSalt == null) return false;
    if (!storedHash.startsWith(PasswordVerifier.pbkdf2Prefix)) return false;
    final derived = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: PasswordVerifier.pbkdf2Iterations,
      bits: PasswordVerifier.pbkdf2Bits,
    ).deriveKeyFromPassword(
      password: password,
      nonce: base64Decode(storedSalt),
    );
    final expected = base64Encode(await derived.extractBytes());
    return storedHash.substring(PasswordVerifier.pbkdf2Prefix.length) ==
        expected;
  }

  /// What an old build concludes about protection: a hash key, nothing else.
  bool protectedAsOldBuild(String toxId) =>
      (store[PasswordVerifier.secureHashKey(toxId)] ?? '').isNotEmpty;

  /// A fresh verifier over the same store — i.e. the next app launch.
  PasswordVerifier newLaunch() => PasswordVerifier(
        secureStorage: FlutterSecureStorageFacade(const FlutterSecureStorage()),
        legacyStore: legacy,
      );

  setUp(() {
    store.clear();
    legacy = _FakeLegacyStore();
    killAtWrite = null;
    writeCount = 0;
    writes.clear();
    readsUnavailable = false;
    killReached = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'write':
          writeCount++;
          if (killAtWrite != null && writeCount >= killAtWrite!) {
            // The process is gone. This write never lands and nothing after it
            // in `setPassword` — including its rollback — ever runs.
            if (!killReached.isCompleted) killReached.complete();
            return Completer<Object?>().future;
          }
          writes.add(args['key'] as String);
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          if (readsUnavailable) throw MissingPluginException('no keychain');
          return store[args['key'] as String];
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'containsKey':
          return store.containsKey(args['key'] as String);
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  final toxId = 'A' * 76;
  final publicKey = 'A' * 64;

  /// Run [action] as a process that dies at the [ordinal]-th secure-storage
  /// write (1-based, counted from this call). Returns once the store holds
  /// exactly the shape that kill leaves: the abandoned future is parked in the
  /// platform channel forever and issues no further writes.
  Future<void> killDuring(int ordinal, Future<void> Function() action) async {
    writeCount = 0;
    writes.clear();
    killReached = Completer<void>();
    killAtWrite = ordinal;
    unawaited(action().then((_) {}, onError: (_) {}));
    await killReached.future;
    killAtWrite = null;
  }

  group('A8 — a kill between verifier writes', () {
    test(
        'killed after the atomic record, before the legacy pair: the new '
        'password still verifies on the next launch', () async {
      // PREVENTS: the account being bricked. Before the fix this exact kill
      // left hash=new + salt=old, and every password — old, new, any — was
      // rejected from then on, permanently and with no repair path.
      final v = newLaunch();
      expect(await v.setPassword(toxId, 'old-password'), isTrue);

      // Survive write #1 (the atomic record), die on write #2 (the legacy hash).
      final recordBefore = store[PasswordVerifier.secureRecordKey(toxId)];
      await killDuring(2, () => v.setPassword(toxId, 'new-password'));

      // The shape a kill leaves: new record, previous pair.
      expect(writes, [PasswordVerifier.secureRecordKey(toxId)],
          reason: 'the atomic record must be the FIRST thing written — that '
              'ordering is what makes this crash window survivable');
      expect(store[PasswordVerifier.secureRecordKey(toxId)],
          isNot(equals(recordBefore)),
          reason: "the record on disk is the new password's");
      expect(
        await verifyAsOldBuild(toxId, 'old-password'),
        isTrue,
        reason: 'the pair still belongs to the previous password, whole — a '
            'downgraded build is never handed a half-written pair',
      );

      final next = newLaunch();
      expect(
        await next.verifyPassword(toxId, 'new-password'),
        isTrue,
        reason: 'THE DEFECT: this used to fail forever',
      );
      expect(
        await verifyAsOldBuild(toxId, 'new-password'),
        isTrue,
        reason: 'that same read must re-mirror the pair, so a build downgraded '
            'afterwards agrees on which password is current',
      );
    });

    test(
        'killed before anything lands: the PREVIOUS password still opens the '
        'account', () async {
      // PREVENTS: a failed password CHANGE locking the user out. A change that
      // does not complete must leave the credential the user still knows
      // working — half-applying it is the same lockout in a different costume.
      final v = newLaunch();
      expect(await v.setPassword(toxId, 'old-password'), isTrue);

      await killDuring(1, () => v.setPassword(toxId, 'new-password'));
      expect(writes, isEmpty, reason: 'nothing reached disk');

      final next = newLaunch();
      expect(await next.verifyPassword(toxId, 'old-password'), isTrue);
      expect(
        await next.verifyPassword(toxId, 'new-password'),
        isFalse,
        reason: 'a password that never reached disk must not open the account',
      );
      expect(await verifyAsOldBuild(toxId, 'old-password'), isTrue);
    });

    test(
        'killed after the record on a FIRST-ever password: the new build is '
        'protected, and one read restores protection for an old build',
        () async {
      // PREVENTS: silent loss of protection across a downgrade. The window
      // where an old build sees no verifier at all must be closed by the new
      // build's next read, not left for the user to discover.
      final v = newLaunch();
      await killDuring(2, () => v.setPassword(toxId, 'first-password'));

      expect(protectedAsOldBuild(toxId), isFalse,
          reason: 'the raw post-kill shape: record only, no pair yet');

      final next = newLaunch();
      expect(
        await next.protectionState(toxId),
        AccountProtectionState.protected,
        reason: 'this build reads the record and demands a password',
      );
      expect(protectedAsOldBuild(toxId), isTrue,
          reason: 'and that read repaired the pair, so a downgrade no longer '
              'walks straight into an unprotected account');
      expect(await verifyAsOldBuild(toxId, 'first-password'), isTrue);
    });
  });

  group('A8 — the shapes on disk', () {
    test('a completed set writes BOTH the record and the legacy pair',
        () async {
      // PREVENTS: shipping a one-way format change. A user who rolls back to an
      // older build must still find the verifier where that build looks, or
      // their account is either unopenable or unprotected.
      expect(await newLaunch().setPassword(toxId, 'pw'), isTrue);
      expect(store[PasswordVerifier.secureRecordKey(toxId)], isNotNull);
      expect(store[PasswordVerifier.secureHashKey(toxId)], isNotNull);
      expect(store[PasswordVerifier.secureSaltKey(toxId)], isNotNull);
      expect(await verifyAsOldBuild(toxId, 'pw'), isTrue);
    });

    test('a verifier written by the OLD format still verifies, and is '
        'upgraded in place', () async {
      // PREVENTS: the upgrade path breaking. Every existing install has only
      // the legacy pair; if the new build required its own record it would lock
      // out every user who already had a password.
      expect(await newLaunch().setPassword(toxId, 'legacy-pw'), isTrue);
      // Reduce the account to exactly what an old build leaves behind.
      store.remove(PasswordVerifier.secureRecordKey(toxId));

      final next = newLaunch();
      expect(await next.verifyPassword(toxId, 'legacy-pw'), isTrue);
      expect(
        store[PasswordVerifier.secureRecordKey(toxId)],
        isNotNull,
        reason: 'reading the account must also upgrade it, so it gains '
            'crash-safety without waiting for a password change',
      );
      expect(await newLaunch().verifyPassword(toxId, 'legacy-pw'), isTrue);
    });

    test('removal leaves no shape behind', () async {
      // PREVENTS: a "removed" password still guarding the account. The verifier
      // now exists in five places (record, pair, both under the public-key
      // alias, plain prefs); missing any one of them leaves the user locked out
      // of an account they explicitly unprotected.
      expect(await newLaunch().setPassword(toxId, 'pw'), isTrue);
      // Alias copies: what an interrupted `ShortToxIdBackfill` leaves — keys
      // still under the 64-char public key while the registry row moved to 76.
      store[PasswordVerifier.secureRecordKey(publicKey)] =
          store[PasswordVerifier.secureRecordKey(toxId)]!;
      store[PasswordVerifier.secureHashKey(publicKey)] =
          store[PasswordVerifier.secureHashKey(toxId)]!;
      store[PasswordVerifier.secureSaltKey(publicKey)] =
          store[PasswordVerifier.secureSaltKey(toxId)]!;
      legacy.hashes[toxId] = 'stale-plain-prefs-hash';
      legacy.salts[toxId] = 'stale-plain-prefs-salt';

      expect(await newLaunch().removePassword(toxId), isTrue);

      expect(store, isEmpty,
          reason: 'no secure-storage key may survive, canonical or aliased');
      expect(legacy.hashes, isEmpty);
      expect(legacy.salts, isEmpty);
      expect(
        await newLaunch().protectionState(toxId),
        AccountProtectionState.none,
        reason: 'the account must read as unprotected afterwards',
      );
      expect(protectedAsOldBuild(toxId), isFalse);
    });

    test('a 64-char public key and the 76-char address resolve to the same '
        'verifier', () async {
      // PREVENTS: regressing the alias behaviour. `ShortToxIdBackfill` moves the
      // registry row before the credential keys; during that window the account
      // is addressed by 76 chars while its verifier sits under 64, and the two
      // must still meet.
      expect(await newLaunch().setPassword(publicKey, 'aliased-pw'), isTrue);

      final next = newLaunch();
      expect(await next.verifyPassword(toxId, 'aliased-pw'), isTrue);
      expect(
        store[PasswordVerifier.secureRecordKey(toxId)],
        isNotNull,
        reason: 'the record is promoted to the canonical key',
      );
      expect(store.containsKey(PasswordVerifier.secureRecordKey(publicKey)),
          isFalse);
      expect(await verifyAsOldBuild(toxId, 'aliased-pw'), isTrue,
          reason: 'and the pair follows it, for an old build');
    });
  });

  group('A8 — fail-closed is preserved', () {
    test('a secure-storage outage reports unknown, never none', () async {
      // PREVENTS: an unreadable Keychain reading as "this account has no
      // password". Every gate — manual login, account switch, delete, export —
      // keys off this, and `none` would wave all of them through.
      expect(await newLaunch().setPassword(toxId, 'pw'), isTrue);

      readsUnavailable = true;
      final blind = newLaunch();
      expect(await blind.protectionState(toxId), AccountProtectionState.unknown);
      expect(await blind.hasPassword(toxId), isTrue,
          reason: 'hasPassword must fail closed on unknown');
    });

    test('an outage on an account that never had a password also reports '
        'unknown', () async {
      // PREVENTS: the same hole reached from the other side — "no key found"
      // and "could not look" are different answers and only one of them is safe
      // to act on.
      readsUnavailable = true;
      expect(await newLaunch().protectionState(toxId),
          AccountProtectionState.unknown);
    });

    test('an unparseable record falls back to the legacy pair instead of '
        'reading as unprotected', () async {
      // PREVENTS: a truncated or foreign value in the new key silently
      // downgrading a protected account to unprotected.
      expect(await newLaunch().setPassword(toxId, 'pw'), isTrue);
      store[PasswordVerifier.secureRecordKey(toxId)] = '{"v":1,"h":';

      final next = newLaunch();
      expect(
          await next.protectionState(toxId), AccountProtectionState.protected);
      expect(await next.verifyPassword(toxId, 'pw'), isTrue);
    });
  });
}
