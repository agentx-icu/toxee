// Regression tests for an auto-login bypass on half-migrated pre-S1 accounts.
//
// An imported account first lands in the registry under its 64-char public key,
// and `ShortToxIdBackfill` later re-keys it to the 76-char address. It cannot
// move the registry row and the credential keys atomically, so it moves the ROW
// first and explicitly continues past a FAILED key migration
// (`lib/util/short_tox_id_backfill.dart`: "the credential stays under the
// public-key alias, which PasswordVerifier resolves"). The surviving mismatch is
// therefore: row at 76 chars, credential still at 64.
//
// That promise only held for SECURE storage. The hash and salt readers consulted
// the 64-char alias in secure storage but read the LEGACY plain-prefs store under
// the canonical id only. A pre-S1 install whose credential is still
// `account_password_<64char>` — and whose backfill rewrote the row but died
// before, or was refused by, `migrateAccountPasswordKeys` — had its row at 76 and
// its only hash at legacy-64. Secure storage ANSWERED (with nothing), so
// `protectionState` returned `none` rather than `unknown`, and the auto-login gate
// opened an account whose password was still sitting on disk. Fail-OPEN.
//
// All state is driven through the real `Prefs` facade over an in-memory
// `plugins.it_nomads.com/flutter_secure_storage` MethodChannel mock plus
// `SharedPreferences` mock values, so the key spellings under test are the ones
// production reads and writes.

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/prefs/password_verifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A real alias relationship: the 76-char address is `publicKey || nospam ||
  // checksum`, so its first 64 chars ARE the public key the imported account was
  // originally registered under. Only truncation is recoverable — nospam and
  // checksum cannot be derived — which is why the backfill leaves the mismatch
  // in this direction.
  const publicKey = '9C4E2A7F0B1D3568E70A2C4E6810B2D4'
      'F6089A1C3E5709B1D3F5072A4C6E8009';
  const address = '${publicKey}4B7E1A229C3D';

  // A different account entirely; its public key shares no prefix with the one
  // above.
  const otherPublicKey = '1A3C5E709B1D3F5072A4C6E8009B1D33'
      'F9A7C1D2E4B6058A1C3E5079B2D4F608';
  const otherAddress = '${otherPublicKey}5C8D2E117A4F';

  const password = 'pre-s1-password';
  const wrongPassword = 'not-the-password';

  // Any base64 text works as a legacy salt: the pre-S1 salted-SHA-256 format is
  // `sha256(saltBase64 + password)` over the salt's *string* form.
  final legacySalt = base64Encode(List<int>.generate(32, (i) => (i * 7) % 256));
  final legacyHash =
      crypto.sha256.convert(utf8.encode('$legacySalt$password')).toString();

  final secureStore = <String, String>{};
  // Secure-storage keys whose `write` the platform refuses, reproducing a
  // Keychain/Keystore that answers with a PlatformException (sandboxed macOS
  // without the entitlement, a locked Keystore).
  final refusedWrites = <String>{};
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  late SharedPreferences prefs;

  setUp(() async {
    secureStore.clear();
    refusedWrites.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'write':
          final key = args['key'] as String;
          if (refusedWrites.contains(key)) {
            throw PlatformException(
              code: 'Keychain',
              message: 'write refused for $key',
            );
          }
          secureStore[key] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args['key'] as String];
        case 'delete':
          secureStore.remove(args['key'] as String);
          return null;
        case 'containsKey':
          return secureStore.containsKey(args['key'] as String);
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
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

  /// The exact on-disk shape of the bug: the pre-S1 plain-prefs credential under
  /// the 64-char public key, nothing in secure storage, nothing under the
  /// 76-char address the registry row now names.
  Future<void> seedLegacyAliasCredential(
    String alias, {
    required String hash,
    String? salt,
  }) async {
    await prefs.setString(PasswordVerifier.legacyHashKey(alias), hash);
    if (salt != null) {
      await prefs.setString(PasswordVerifier.legacySaltKey(alias), salt);
    }
  }

  test('a half-migrated pre-S1 account still reads as password-protected',
      () async {
    // Prevents: auto-login silently opening a password-protected account. With
    // the row at 76 chars and the only credential at legacy-64, secure storage
    // answers with nothing, so the state resolved to `none` — an affirmative
    // "this account has no password" — and the startup gate let the session
    // through without ever prompting.
    expect(address.length, 76,
        reason: 'the alias relationship under test only exists for a real '
            '76-char Tox address');
    expect(publicKey.length, 64,
        reason: 'and its 64-char public-key prefix');
    await seedLegacyAliasCredential(publicKey,
        hash: legacyHash, salt: legacySalt);

    expect(await Prefs.accountProtectionState(address),
        AccountProtectionState.protected,
        reason: 'the credential is reachable under the 64-char alias, so the '
            'account IS protected; `none` here is the auth bypass');
    expect(await Prefs.hasAccountPassword(address), isTrue,
        reason: 'every gate that calls hasAccountPassword must demand a '
            'password for this account');
  });

  test('the real owner can still open a half-migrated pre-S1 account',
      () async {
    // Prevents the opposite failure of the same fix: flagging the account
    // protected while no password can satisfy the check would lock its owner out
    // of their own profile permanently, with no recovery path in the app — the
    // credential they type is correct, it is just being looked for in the wrong
    // namespace.
    await seedLegacyAliasCredential(publicKey,
        hash: legacyHash, salt: legacySalt);

    expect(await Prefs.verifyAccountPassword(address, wrongPassword), isFalse,
        reason: 'a wrong password must not open it through the alias either');
    expect(await Prefs.verifyAccountPassword(address, password), isTrue,
        reason: 'the owner\'s real password must resolve hash AND salt under '
            'the alias');
    expect(await Prefs.verifyAccountPassword(address, wrongPassword), isFalse,
        reason: 'and must still be rejected after the verify migrated the '
            'credential forward');
  });

  test('a legacy alias hash with no salt fails closed, it does not open',
      () async {
    // Prevents: the salt half of the lookup being left behind. A hash found
    // under the alias, paired with a salt nobody looked for, verifies against
    // nothing — and the dangerous shape of "verifies against nothing" is a
    // thrown exception or an accidental success on the unsalted comparison
    // path, either of which the login gate would mishandle. It must be a plain
    // `false`, with the account still reported protected so the user is asked
    // again rather than waved through.
    //
    // Shape 1: a plain-prefs entry already in PBKDF2 form. The hash bytes are
    // irrelevant — without a salt the comparison cannot even be attempted.
    await seedLegacyAliasCredential(publicKey,
        hash: '${PasswordVerifier.pbkdf2Prefix}${base64Encode(
          List<int>.filled(32, 0),
        )}');

    expect(await Prefs.verifyAccountPassword(address, password), isFalse,
        reason: 'a PBKDF2 hash with no salt must refuse, not throw');
    expect(await Prefs.accountProtectionState(address),
        AccountProtectionState.protected,
        reason: 'the account is still protected — refusing to verify must not '
            'downgrade it to unprotected');

    // Shape 2: the pre-S1 salted SHA-256 hash, its salt entry missing. This one
    // falls through to the unsalted-SHA-256 comparison, which cannot match a
    // salted digest, so it also lands on `false`.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    secureStore.clear();
    await seedLegacyAliasCredential(publicKey, hash: legacyHash);

    expect(await Prefs.verifyAccountPassword(address, password), isFalse,
        reason: 'a salted legacy digest with no salt must refuse, not match '
            'through the unsalted branch');
    expect(await Prefs.accountProtectionState(address),
        AccountProtectionState.protected);
  });

  test('a different account\'s legacy entry does not protect this one',
      () async {
    // Prevents the over-broad fix: an alias lookup loose enough to answer from
    // some OTHER account's credential would demand a password the user of THIS
    // account has never set, and no password they can type would open it. Only
    // the exact 64-char prefix of this address may be consulted.
    await seedLegacyAliasCredential(otherPublicKey,
        hash: legacyHash, salt: legacySalt);

    expect(await Prefs.accountProtectionState(address),
        AccountProtectionState.none,
        reason: 'an unrelated 64-char key is not this address\'s alias');
    expect(await Prefs.accountProtectionState(otherAddress),
        AccountProtectionState.protected,
        reason: 'setup check: the seeded entry really is a live credential, '
            'just not this account\'s');
  });

  test('a resolved legacy alias credential is lifted to the canonical secure '
      'key', () async {
    // Prevents: the world-readable copy outliving the fix. The pre-S1 entry is
    // plain text in SharedPreferences — iCloud-synced XML on iOS, readable on a
    // rooted Android — so a lookup that merely READS it leaves the credential
    // exposed indefinitely, and leaves the next lookup depending on the alias
    // fallback forever instead of converging on the canonical key.
    await seedLegacyAliasCredential(publicKey,
        hash: legacyHash, salt: legacySalt);

    expect(await Prefs.getAccountPasswordHash(address), legacyHash);

    expect(secureStore[PasswordVerifier.secureHashKey(address)], legacyHash,
        reason: 'the hash must land under the 76-char canonical secure key');
    expect(prefs.getString(PasswordVerifier.legacyHashKey(publicKey)), isNull,
        reason: 'and the plain-text alias copy must be gone once the secure '
            'write persisted');

    // The salt is migrated by its own reader, so the credential must still be
    // usable end-to-end after the hash moved on its own.
    expect(await Prefs.verifyAccountPassword(address, password), isTrue,
        reason: 'migrating the hash alone must not orphan the salt');
    expect(prefs.getString(PasswordVerifier.legacySaltKey(publicKey)), isNull,
        reason: 'the plain-text alias salt must be cleaned up too');
    expect(
        secureStore[PasswordVerifier.secureHashKey(address)]
            ?.startsWith(PasswordVerifier.pbkdf2Prefix),
        isTrue,
        reason: 'a successful legacy verify also upgrades the stored hash to '
            'PBKDF2');
  });

  test('a refused secure write leaves the legacy alias credential on disk',
      () async {
    // Prevents data loss in the other direction: deleting the only copy of the
    // credential after a silently swallowed Keychain write would make the
    // account unopenable by anyone — the user's password would verify against
    // nothing on the next launch. The legacy entry may only be dropped once the
    // secure write actually persisted.
    refusedWrites.add(PasswordVerifier.secureHashKey(address));
    await seedLegacyAliasCredential(publicKey,
        hash: legacyHash, salt: legacySalt);

    expect(await Prefs.accountProtectionState(address),
        AccountProtectionState.protected,
        reason: 'the credential is still found even when it cannot be moved');
    expect(secureStore.containsKey(PasswordVerifier.secureHashKey(address)),
        isFalse,
        reason: 'setup check: the refused write really did not persist');
    expect(prefs.getString(PasswordVerifier.legacyHashKey(publicKey)),
        legacyHash,
        reason: 'so the only remaining copy must survive, byte-identical');
    expect(await Prefs.verifyAccountPassword(address, password), isTrue,
        reason: 'and the account must remain openable by its owner across the '
            'failed migration');
  });
}
