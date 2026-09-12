// Regression tests for a revoked password coming back to life.
//
// An imported account first lands in the registry under its 64-char public key
// (`tim2tox_ffi_extract_tox_id_from_profile` can only return
// `tox_self_get_public_key()`), and `ShortToxIdBackfill` later re-keys it to the
// 76-char address, carrying the password verifier's secure-storage entries with
// it. That move is not atomic, and its source delete can also be swallowed, so
// an install can sit indefinitely with the verifier duplicated: canonical
// entries under the 76-char id AND an ALIAS copy under the 64-char prefix.
// `PasswordVerifier` resolves the alias copy exactly like a canonical one, and a
// lookup MIGRATES it back into the canonical slot.
//
// That is what made removal a lie. `removePassword` deleted only the canonical
// entries and returned true, the UI told the user their password was gone, and
// the very next lookup promoted the alias copy back into the canonical slot —
// the account was protected again by a credential the user had already revoked,
// with no way to discover that from the app. The tests below pin the revocation
// as DURABLE: every assertion about "no longer protected" is made AFTER a
// lookup, because the lookup is the step that used to resurrect it.
//
// All state is driven through the real `Prefs` facade over an in-memory
// `plugins.it_nomads.com/flutter_secure_storage` MethodChannel mock, so the key
// spellings under test are the ones production writes.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/prefs/password_verifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A real alias relationship: the 76-char address is `publicKey || nospam ||
  // checksum`, so its first 64 chars ARE the public key the imported account
  // was originally registered under.
  const publicKey = '3F9A7C1D2E4B6058A1C3E5079B2D4F6801A3C5E709B1D3F5072A4C6E'
      '8009B1D3';
  const address = '${publicKey}4B7E1A229C3D';

  // A second account whose public key differs from the first — cleanup must not
  // reach it.
  const otherPublicKey = 'B2D4F6081A3C5E709B1D3F5072A4C6E8009B1D33F9A7C1D2E4B6058'
      'A1C3E5079';
  const otherAddress = '${otherPublicKey}5C8D2E117A4F';

  const password = 'the-one-the-user-revoked';

  final secureStore = <String, String>{};
  // Secure-storage keys whose `delete` the platform refuses, reproducing a
  // Keychain/Keystore that answers with a PlatformException.
  final refusedDeletes = <String>{};
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    secureStore.clear();
    refusedDeletes.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'write':
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args['key'] as String];
        case 'delete':
          final key = args['key'] as String;
          if (refusedDeletes.contains(key)) {
            throw PlatformException(
              code: 'Keychain',
              message: 'delete refused for $key',
            );
          }
          secureStore.remove(key);
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

  /// Real PBKDF2 verifier for [toxId], written through the production path.
  Future<void> setVerifier(String toxId) async {
    expect(await Prefs.setAccountPassword(toxId, password), isTrue,
        reason: 'test setup must actually persist a verifier');
  }

  /// Write a verifier under the 64-char public-key alias of [address], using
  /// the same key spellings production uses.
  void writeAliasVerifier(
    String address, {
    required String hash,
    required String salt,
  }) {
    final alias = address.substring(0, 64);
    secureStore[PasswordVerifier.secureHashKey(alias)] = hash;
    secureStore[PasswordVerifier.secureSaltKey(alias)] = salt;
  }

  /// Duplicate [address]'s canonical verifier onto its alias — the on-disk
  /// shape an interrupted `ShortToxIdBackfill` leaves behind (registry row
  /// already at 76 chars, credential keys still readable at 64).
  void duplicateOntoAlias(String address) {
    writeAliasVerifier(
      address,
      hash: secureStore[PasswordVerifier.secureHashKey(address)]!,
      salt: secureStore[PasswordVerifier.secureSaltKey(address)]!,
    );
  }

  void removeCanonicalVerifier(String address) {
    secureStore.remove(PasswordVerifier.secureHashKey(address));
    secureStore.remove(PasswordVerifier.secureSaltKey(address));
  }

  test('a revoked password is not resurrected by the 64-char alias copy',
      () async {
    // Prevents: the user removes their password, the app confirms it, and the
    // next protection check silently promotes the leftover alias verifier back
    // into the canonical slot — so the account is locked again by a credential
    // the user believes no longer exists, and nothing in the UI can say so.
    await setVerifier(address);
    duplicateOntoAlias(address);

    expect(await Prefs.removeAccountPassword(address), isTrue);

    // The lookup is the resurrection step, so it has to happen BEFORE the
    // assertions — otherwise the test would pass against the broken build.
    expect(await Prefs.getAccountPasswordHash(address), isNull,
        reason: 'a lookup after removal must not find an alias copy to migrate '
            'back into the canonical slot');
    expect(await Prefs.accountProtectionState(address),
        AccountProtectionState.none,
        reason: 'the account must read as unprotected after the lookup, not '
            'just before it');
    expect(await Prefs.verifyAccountPassword(address, password), isFalse,
        reason: 'the revoked password must no longer open the account');
  });

  test('the alias entries are erased from the store, not merely shadowed',
      () async {
    // Prevents: a removal that only hides the alias copy behind the canonical
    // slot. The revoked credential would still be on disk, still resolvable by
    // any code path holding the account's older 64-char id (a stale registry
    // row, a pointer the backfill did not reach), and one more half-finished
    // backfill away from being authoritative again.
    await setVerifier(address);
    duplicateOntoAlias(address);
    final prefs = await SharedPreferences.getInstance();
    // Pre-S1 installs also carry plain-text prefs entries, and the backfill
    // moves those too, so the alias can own a legacy pair as well.
    await prefs.setString(
        PasswordVerifier.legacyHashKey(publicKey), 'legacy-alias-hash');
    await prefs.setString(
        PasswordVerifier.legacySaltKey(publicKey), 'legacy-alias-salt');

    expect(await Prefs.removeAccountPassword(address), isTrue);
    // Force the migrating reader to run; it must find nothing to promote.
    expect(await Prefs.getAccountPasswordHash(address), isNull);

    expect(secureStore.containsKey(PasswordVerifier.secureHashKey(publicKey)),
        isFalse,
        reason: 'the alias hash must be gone from secure storage itself');
    expect(secureStore.containsKey(PasswordVerifier.secureSaltKey(publicKey)),
        isFalse,
        reason: 'and so must its salt, or a later alias hash would still '
            'verify');
    expect(prefs.getString(PasswordVerifier.legacyHashKey(publicKey)), isNull,
        reason: 'the alias legacy plain-prefs hash is the same credential in '
            'the clear');
    expect(prefs.getString(PasswordVerifier.legacySaltKey(publicKey)), isNull);
    expect(await Prefs.accountProtectionState(publicKey),
        AccountProtectionState.none,
        reason: 'even a caller still using the old 64-char id must see an '
            'unprotected account');
  });

  test('cleanup stays inside the account being revoked', () async {
    // Prevents the opposite failure: an alias sweep broad enough to strip a
    // DIFFERENT account's verifier, silently unprotecting an account whose
    // owner never asked for it. Only the exact 64-char prefix of the revoked
    // address may be touched.
    await setVerifier(address);
    duplicateOntoAlias(address);
    await setVerifier(otherAddress);
    duplicateOntoAlias(otherAddress);
    final otherEntries = <String, String>{
      for (final key in <String>[
        PasswordVerifier.secureHashKey(otherAddress),
        PasswordVerifier.secureSaltKey(otherAddress),
        PasswordVerifier.secureHashKey(otherPublicKey),
        PasswordVerifier.secureSaltKey(otherPublicKey),
      ])
        key: secureStore[key]!,
    };

    expect(await Prefs.removeAccountPassword(address), isTrue);
    expect(await Prefs.getAccountPasswordHash(address), isNull);

    for (final entry in otherEntries.entries) {
      expect(secureStore[entry.key], entry.value,
          reason: 'revoking one account must leave ${entry.key} byte-identical');
    }
    expect(await Prefs.accountProtectionState(otherAddress),
        AccountProtectionState.protected,
        reason: 'the untouched account must still demand its password');
  });

  test('a refused canonical delete reports failure and keeps the account locked',
      () async {
    // Prevents the fail-OPEN inversion of the fix: if the alias cleanup were
    // allowed to decide the result, a Keychain that refused the canonical
    // delete would still report success. The user would be told the password
    // was removed while the canonical verifier — the one every lookup finds
    // first — is still on disk, and the next launch would demand a password
    // they were told no longer exists.
    await setVerifier(address);
    duplicateOntoAlias(address);
    refusedDeletes.add(PasswordVerifier.secureHashKey(address));

    expect(await Prefs.removeAccountPassword(address), isFalse,
        reason: 'the canonical delete alone decides the return value');
    expect(await Prefs.accountProtectionState(address),
        AccountProtectionState.protected,
        reason: 'and the account stays protected — the safe direction to fail');
    expect(secureStore.containsKey(PasswordVerifier.secureHashKey(address)),
        isTrue,
        reason: 'the canonical verifier the refusal preserved is still there');
  });

  test('an alias-only leftover is revoked too', () async {
    // Prevents the fully-interrupted-backfill shape: the registry row was
    // rewritten to 76 chars but the credential keys never moved, so the ONLY
    // verifier on disk is the alias copy. Removing the password addresses the
    // 76-char id, finds nothing canonical to delete — and unless the alias is
    // cleaned too, the next lookup migrates it forward and the account is
    // protected again by the revoked password.
    await setVerifier(address);
    final hash = secureStore[PasswordVerifier.secureHashKey(address)]!;
    final salt = secureStore[PasswordVerifier.secureSaltKey(address)]!;

    void stageAliasOnly() {
      writeAliasVerifier(address, hash: hash, salt: salt);
      removeCanonicalVerifier(address);
    }

    stageAliasOnly();
    expect(await Prefs.accountProtectionState(address),
        AccountProtectionState.protected,
        reason: 'setup check: the alias copy alone protects the account');
    // That check migrated part of the alias forward, so re-stage the state a
    // killed backfill actually leaves: keys at 64, nothing at 76.
    stageAliasOnly();

    expect(await Prefs.removeAccountPassword(address), isTrue,
        reason: 'deleting absent canonical keys is not a failure');

    expect(await Prefs.getAccountPasswordHash(address), isNull);
    expect(await Prefs.accountProtectionState(address),
        AccountProtectionState.none);
    expect(await Prefs.verifyAccountPassword(address, password), isFalse,
        reason: 'the revoked password must not open the account through the '
            'alias either');
  });
}
