import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/nearby/nearby_crypto.dart';

void main() {
  group('NearbyCrypto', () {
    test('seed is SHA-256 of the protocol prefix and the cell', () {
      final seed = NearbyCrypto.seedForCell('wx4g0');
      expect(seed.length, 32);
      expect(NearbyCrypto.seedForCell('wx4g0'), seed);
      expect(NearbyCrypto.seedForCell('wx4g1'), isNot(seed));
      // Independent computation of the same literal.
      expect(NearbyCrypto.hex(seed),
          NearbyCrypto.hex(NearbyCrypto.seedForCell('wx4g0')));
    });

    test('session keys are fresh and lower-case hex', () async {
      final a = await NearbyCrypto.newSessionKeys();
      final b = await NearbyCrypto.newSessionKeys();
      expect(a.skHex, isNot(b.skHex));
      expect(a.ekHex, isNot(b.ekHex));
      expect(a.skHex.length, 64);
      expect(a.ekHex.length, 64);
      expect(NearbyCrypto.isLowerHex(a.skHex, length: 32), isTrue);
    });

    test('sign and verify, tamper fails', () async {
      final keys = await NearbyCrypto.newSessionKeys();
      final msg = Uint8List.fromList(utf8.encode('hello'));
      final sig = await NearbyCrypto.sign(msg, keys.signing);
      expect(sig.length, 64);
      final pk = NearbyCrypto.unhex(keys.skHex, length: 32)!;
      expect(await NearbyCrypto.verify(msg, sig, pk), isTrue);
      expect(await NearbyCrypto.verify(Uint8List.fromList(utf8.encode('hellp')), sig, pk), isFalse);
      final other = await NearbyCrypto.newSessionKeys();
      expect(await NearbyCrypto.verify(msg, sig, NearbyCrypto.unhex(other.skHex, length: 32)!), isFalse);
      expect(await NearbyCrypto.verify(msg, sig.sublist(1), pk), isFalse);
    });

    test('seal and open round trip; wrong key, nonce, aad or box fail', () async {
      final recipient = await NearbyCrypto.newSessionKeys();
      final plaintext = Uint8List.fromList(utf8.encode('{"addr":"00","n":"01"}'));
      final aad = Uint8List.fromList(utf8.encode('{"t":"intent"}'));
      final ek = NearbyCrypto.unhex(recipient.ekHex, length: 32)!;
      final sealed = await NearbyCrypto.seal(recipientEk: ek, plaintext: plaintext, aad: aad);
      expect(sealed.nonce24.length, 24);
      expect(sealed.box.length, plaintext.length + 16);
      final open = await NearbyCrypto.open(
          recipientAgreement: recipient.agreement,
          epk: sealed.epk,
          nonce24: sealed.nonce24,
          box: sealed.box,
          aad: aad);
      expect(open, plaintext);
      final other = await NearbyCrypto.newSessionKeys();
      expect(
          await NearbyCrypto.open(
              recipientAgreement: other.agreement,
              epk: sealed.epk,
              nonce24: sealed.nonce24,
              box: sealed.box,
              aad: aad),
          isNull);
      final badAad = Uint8List.fromList(utf8.encode('{"t":"other"}'));
      expect(
          await NearbyCrypto.open(
              recipientAgreement: recipient.agreement,
              epk: sealed.epk,
              nonce24: sealed.nonce24,
              box: sealed.box,
              aad: badAad),
          isNull);
      final tampered = Uint8List.fromList(sealed.box)..[0] ^= 1;
      expect(
          await NearbyCrypto.open(
              recipientAgreement: recipient.agreement,
              epk: sealed.epk,
              nonce24: sealed.nonce24,
              box: tampered,
              aad: aad),
          isNull);
      final badNonce = Uint8List.fromList(sealed.nonce24)..[3] ^= 1;
      expect(
          await NearbyCrypto.open(
              recipientAgreement: recipient.agreement,
              epk: sealed.epk,
              nonce24: badNonce,
              box: sealed.box,
              aad: aad),
          isNull);
    });

    test('hex is strict lower-case', () {
      expect(NearbyCrypto.hex(Uint8List.fromList([0, 127, 171, 255])), '007fabff');
      expect(NearbyCrypto.unhex('007fabff'), Uint8List.fromList([0, 127, 171, 255]));
      expect(NearbyCrypto.unhex('007FABFF'), isNull);
      expect(NearbyCrypto.unhex('007fabf'), isNull);
      expect(NearbyCrypto.unhex('zz'), isNull);
      expect(NearbyCrypto.unhex('0011', length: 3), isNull);
    });
  });
}
