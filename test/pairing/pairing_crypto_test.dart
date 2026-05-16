import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/pairing/pairing_crypto.dart';

void main() {
  group('PairingCrypto', () {
    test('generates fresh ephemeral keypairs', () async {
      final a = await PairingCrypto.generateEphemeral();
      final b = await PairingCrypto.generateEphemeral();
      final aPub = (await a.extractPublicKey()).bytes;
      final bPub = (await b.extractPublicKey()).bytes;
      expect(aPub.length, PairingCrypto.publicKeyLength);
      expect(bPub.length, PairingCrypto.publicKeyLength);
      // Different keypairs MUST produce different pubkeys. If they didn't,
      // we'd have a critical RNG failure that breaks security entirely.
      expect(aPub, isNot(equals(bPub)));
    });

    test('X25519 ECDH yields identical shared secret on both sides', () async {
      final alice = await PairingCrypto.generateEphemeral();
      final bob = await PairingCrypto.generateEphemeral();
      final alicePub = (await alice.extractPublicKey()).bytes;
      final bobPub = (await bob.extractPublicKey()).bytes;

      final aliceSecret = await PairingCrypto.deriveSharedSecret(
        ourKeyPair: alice,
        theirPublicKey: bobPub,
      );
      final bobSecret = await PairingCrypto.deriveSharedSecret(
        ourKeyPair: bob,
        theirPublicKey: alicePub,
      );
      expect(aliceSecret, equals(bobSecret));
    });

    test('deriveSessionKeys returns identical (transitKey, sas) on both sides',
        () async {
      final alice = await PairingCrypto.generateEphemeral();
      final bob = await PairingCrypto.generateEphemeral();
      final alicePub = (await alice.extractPublicKey()).bytes;
      final bobPub = (await bob.extractPublicKey()).bytes;
      final nonce = PairingCrypto.generateNonce();

      final aliceShared = await PairingCrypto.deriveSharedSecret(
        ourKeyPair: alice, theirPublicKey: bobPub);
      final bobShared = await PairingCrypto.deriveSharedSecret(
        ourKeyPair: bob, theirPublicKey: alicePub);

      final aliceKeys = await PairingCrypto.deriveSessionKeys(
        sharedSecret: aliceShared,
        nonce: nonce,
        ourPublicKey: alicePub,
        theirPublicKey: bobPub,
      );
      final bobKeys = await PairingCrypto.deriveSessionKeys(
        sharedSecret: bobShared,
        nonce: nonce,
        ourPublicKey: bobPub,
        theirPublicKey: alicePub,
      );
      expect(aliceKeys.transitKey, equals(bobKeys.transitKey));
      expect(aliceKeys.sas, equals(bobKeys.sas));
      // SAS shape: exactly 6 ASCII decimal digits.
      expect(aliceKeys.sas.length, PairingCrypto.sasDigits);
      expect(RegExp(r'^[0-9]{6}$').hasMatch(aliceKeys.sas), isTrue);
    });

    test('SAS depends on both pubkeys (not just shared secret)', () async {
      // This is the MITM-defeat invariant. We construct two scenarios with
      // the *same* (sharedSecret, nonce) but different "their" pubkeys, and
      // assert the SAS differs.
      final alice = await PairingCrypto.generateEphemeral();
      final bob = await PairingCrypto.generateEphemeral();
      final eve = await PairingCrypto.generateEphemeral();
      final alicePub = (await alice.extractPublicKey()).bytes;
      final bobPub = (await bob.extractPublicKey()).bytes;
      final evePub = (await eve.extractPublicKey()).bytes;

      final shared = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        shared[i] = i;
      }
      final nonce = Uint8List(16);

      final realKeys = await PairingCrypto.deriveSessionKeys(
        sharedSecret: shared,
        nonce: nonce,
        ourPublicKey: alicePub,
        theirPublicKey: bobPub,
      );
      final mitmKeys = await PairingCrypto.deriveSessionKeys(
        sharedSecret: shared,
        nonce: nonce,
        ourPublicKey: alicePub,
        theirPublicKey: evePub,
      );
      expect(realKeys.sas, isNot(equals(mitmKeys.sas)),
          reason: 'SAS must change when peer pubkey changes — this is the '
              'MITM-defeat property.');
    });

    test('AEAD encrypt/decrypt roundtrips', () async {
      final key = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        key[i] = i * 7 % 256;
      }
      final plain = Uint8List.fromList(List<int>.generate(2048, (i) => i % 256));
      final cipher = await PairingCrypto.aeadEncrypt(
        transitKey: key, plaintext: plain);
      final back = await PairingCrypto.aeadDecrypt(
        transitKey: key, blob: cipher);
      expect(back, equals(plain));
    });

    test('AEAD decrypt rejects tampered ciphertext', () async {
      final key = Uint8List(32)..fillRange(0, 32, 0xAB);
      final plain = Uint8List.fromList(List<int>.generate(128, (i) => i));
      final cipher = await PairingCrypto.aeadEncrypt(
        transitKey: key, plaintext: plain);
      // Flip a bit in the ciphertext (not the nonce). AEAD MUST reject.
      cipher[cipher.length - 1] ^= 0x01;
      await expectLater(
        () => PairingCrypto.aeadDecrypt(transitKey: key, blob: cipher),
        throwsA(anything),
      );
    });

    test('AEAD decrypt rejects truncated blob', () async {
      final key = Uint8List(32);
      await expectLater(
        () => PairingCrypto.aeadDecrypt(transitKey: key, blob: Uint8List(4)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
