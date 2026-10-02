// SecretPassword (zeroable bytes for account passwords), the session store
// that holds it, and the byte paths of the PBKDF2 verifier. The last group
// pins that moving from `deriveKeyFromPassword(String)` to `deriveKey` over
// the UTF-8 bytes changed no stored verifier: an account set up before this
// change must still verify after it.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/prefs/password_verifier.dart';
import 'package:toxee/util/session_password_store.dart';

class _MemorySecureStorage extends SecureStorageFacade {
  final Map<String, String> entries = <String, String>{};

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<bool> write(String key, String value) async {
    entries[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    entries.remove(key);
    return true;
  }
}

class _NoLegacyStore implements LegacyPasswordStore {
  @override
  Future<String?> readLegacyHash(String toxId) async => null;
  @override
  Future<String?> readLegacySalt(String toxId) async => null;
  @override
  Future<void> removeLegacyHash(String toxId) async {}
  @override
  Future<void> removeLegacySalt(String toxId) async {}
}

const _toxId =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA000000000000';

void main() {
  group('SecretPassword', () {
    test('holds the UTF-8 bytes and zeroes them on dispose', () {
      final secret = SecretPassword.fromString('pä\u0000ss');
      Uint8List? leaked;
      secret.withBytes((bytes) {
        expect(bytes, utf8.encode('pä\u0000ss'));
        leaked = bytes; // a misbehaving caller retaining the view
      });
      secret.dispose();
      expect(leaked, everyElement(0));
      expect(secret.isDisposed, isTrue);
      expect(() => secret.withBytes((b) => b), throwsStateError);
      expect(() => secret.isEmpty, throwsStateError);
      expect(() => secret.copy(), throwsStateError);
      secret.dispose(); // idempotent
    });

    test('a copy has its own lifetime', () {
      final original = SecretPassword.fromString('pw');
      final copy = original.copy();
      original.dispose();
      expect(copy.withBytes(utf8.decode), 'pw');
      copy.dispose();
    });

    test('fromBytes copies the caller buffer', () {
      final buffer = Uint8List.fromList(utf8.encode('pw'));
      final secret = SecretPassword.fromBytes(buffer);
      secret.dispose();
      expect(buffer, utf8.encode('pw'));
    });

    test('identity equality and a redacted toString', () {
      final a = SecretPassword.fromString('same');
      final b = SecretPassword.fromString('same');
      expect(a == b, isFalse);
      expect(a == a, isTrue);
      expect(a.toString(), isNot(contains('same')));
      expect('$a', 'SecretPassword(redacted)');
    });

    test('use / useOrNull dispose after the body completes or throws', () async {
      SecretPassword? seen;
      final result = await SecretPassword.use('pw', (p) async {
        seen = p;
        return p.withBytes(utf8.decode);
      });
      expect(result, 'pw');
      expect(seen!.isDisposed, isTrue);

      await expectLater(
        SecretPassword.use('pw', (p) async {
          seen = p;
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(seen!.isDisposed, isTrue);

      expect(await SecretPassword.useOrNull(null, (p) async => p), isNull);
    });

    test('hasValue treats null and empty as no password', () {
      SecretPassword? none;
      expect(none.hasValue, isFalse);
      expect(SecretPassword.fromString('').hasValue, isFalse);
      expect(SecretPassword.fromString('x').hasValue, isTrue);
    });
  });

  group('SessionPasswordStore', () {
    tearDown(SessionPasswordStore.clear);

    test('keeps its own copy and zeroes it on clear', () {
      final caller = SecretPassword.fromString('pw');
      SessionPasswordStore.set(_toxId, caller);
      caller.dispose(); // the caller's copy dies; the store's must not
      final stored = SessionPasswordStore.get(_toxId)!;
      expect(stored.withBytes(utf8.decode), 'pw');
      SessionPasswordStore.clear(_toxId);
      expect(stored.isDisposed, isTrue);
      expect(SessionPasswordStore.get(_toxId), isNull);
    });

    test('replacing the value zeroes the previous one', () {
      SessionPasswordStore.setText(_toxId, 'first');
      final first = SessionPasswordStore.get(_toxId)!;
      SessionPasswordStore.setText(_toxId, 'second');
      expect(first.isDisposed, isTrue);
      expect(SessionPasswordStore.get(_toxId)!.withBytes(utf8.decode), 'second');
    });

    test('a disposed argument does not re-point the slot', () {
      SessionPasswordStore.setText(_toxId, 'kept');
      final dead = SecretPassword.fromString('other')..dispose();
      expect(() => SessionPasswordStore.set('another-id', dead), throwsStateError);
      expect(SessionPasswordStore.get('another-id'), isNull);
      expect(SessionPasswordStore.get(_toxId)!.withBytes(utf8.decode), 'kept');
    });

    test('an empty password clears the slot', () {
      SessionPasswordStore.setText(_toxId, 'pw');
      SessionPasswordStore.setText(_toxId, '');
      expect(SessionPasswordStore.get(_toxId), isNull);
    });
  });

  group('PasswordVerifier byte paths', () {
    late _MemorySecureStorage storage;
    late PasswordVerifier verifier;

    setUp(() {
      storage = _MemorySecureStorage();
      verifier = PasswordVerifier(
        secureStorage: storage,
        legacyStore: _NoLegacyStore(),
      );
    });

    test('the stored verifier equals the String-API PBKDF2 output', () async {
      const text = 'pä\u{1F511}ss';
      final secret = SecretPassword.fromString(text);
      expect(await verifier.setPassword(_toxId, secret), isTrue);
      final storedHash = storage.entries[PasswordVerifier.secureHashKey(_toxId)]!;
      final salt = base64Decode(
        storage.entries[PasswordVerifier.secureSaltKey(_toxId)]!,
      );
      // What the verifier computed before it took bytes.
      final legacyKey = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: PasswordVerifier.pbkdf2Iterations,
        bits: PasswordVerifier.pbkdf2Bits,
      ).deriveKeyFromPassword(password: text, nonce: salt);
      expect(
        storedHash,
        '${PasswordVerifier.pbkdf2Prefix}'
        '${base64Encode(await legacyKey.extractBytes())}',
      );
      // The caller's bytes are borrowed: still intact after the derivation.
      expect(secret.withBytes(utf8.decode), text);
      expect(await verifier.verifyPassword(_toxId, secret), isTrue);
      expect(
        await verifier.verifyPassword(_toxId, SecretPassword.fromString('nope')),
        isFalse,
      );
    });

    test('a derivation survives the caller disposing mid-flight', () async {
      final secret = SecretPassword.fromString('pw');
      final pending = verifier.deriveVerifier(secret);
      secret.dispose(); // the KDF runs on its own private copy
      final derived = await pending;
      expect(
        await verifier.matchesPbkdf2(
          SecretPassword.fromString('pw'),
          derived.hash,
          derived.salt,
        ),
        isTrue,
      );
    });
  });
}
