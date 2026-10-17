import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Cryptography of the nearby protocol (`toxee/nearby/v1`, plan §3.4):
///
/// * a per-session **Ed25519** signing key (`sk`) and **X25519** encryption
///   key (`ek`), both fresh every time nearby starts;
/// * presence and intent records are signed with the Ed25519 key over their
///   canonical bytes;
/// * an intent's `box` is XChaCha20-Poly1305 with
///   `key = HKDF-SHA256(ikm = X25519(epk_sk, to), salt = n24, info)`, the
///   24-byte nonce `n24` and the canonical intent header as associated data;
/// * hex is strictly lower-case everywhere on the wire.
class NearbyCrypto {
  NearbyCrypto._();

  static const String protocolId = 'toxee/nearby/v1';
  static const String seedPrefix = 'toxee/nearby/v1|';
  static const String intentInfo = 'toxee/nearby/v1/intent';
  static const int nonceBytes = 24;
  static const int keyBytes = 32;
  static const int signatureBytes = 64;
  static const int macBytes = 16;

  static final Ed25519 _ed25519 = Ed25519();
  static final X25519 _x25519 = X25519();
  static final Xchacha20 _aead = Xchacha20.poly1305Aead();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: keyBytes);

  /// `SHA-256("toxee/nearby/v1|" + cell)` — the rendezvous seed of a cell.
  static Uint8List seedForCell(String cell) => Uint8List.fromList(
      crypto.sha256.convert(utf8.encode('$seedPrefix$cell')).bytes);

  static Future<NearbySessionKeys> newSessionKeys() async {
    final sign = await _ed25519.newKeyPair();
    final agree = await _x25519.newKeyPair();
    final sk = await sign.extractPublicKey();
    final ek = await agree.extractPublicKey();
    return NearbySessionKeys._(
      signing: sign,
      agreement: agree,
      skHex: hex(Uint8List.fromList(sk.bytes)),
      ekHex: hex(Uint8List.fromList(ek.bytes)),
    );
  }

  static Future<Uint8List> sign(Uint8List message, SimpleKeyPair key) async {
    final signature = await _ed25519.sign(message, keyPair: key);
    return Uint8List.fromList(signature.bytes);
  }

  static Future<bool> verify(
      Uint8List message, Uint8List signature, Uint8List publicKey) async {
    if (signature.length != signatureBytes || publicKey.length != keyBytes) {
      return false;
    }
    try {
      return await _ed25519.verify(
        message,
        signature: Signature(signature,
            publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
      );
    } catch (_) {
      return false;
    }
  }

  /// Sender side of an intent: ephemeral X25519 key, HKDF, AEAD.
  static Future<SealedIntent> seal({
    required Uint8List recipientEk,
    required Uint8List plaintext,
    required Uint8List aad,
    Uint8List? nonce24,
    SimpleKeyPair? ephemeral,
  }) async {
    final eph = ephemeral ?? await _x25519.newKeyPair();
    final epk = Uint8List.fromList((await eph.extractPublicKey()).bytes);
    final n24 = nonce24 ?? _randomBytes(nonceBytes);
    final key = await _deriveKey(eph, recipientEk, n24);
    final box = await _aead.encrypt(plaintext,
        secretKey: key, nonce: n24, aad: aad);
    return SealedIntent(
      epk: epk,
      nonce24: n24,
      box: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
    );
  }

  /// Receiver side; null when the box does not authenticate.
  static Future<Uint8List?> open({
    required SimpleKeyPair recipientAgreement,
    required Uint8List epk,
    required Uint8List nonce24,
    required Uint8List box,
    required Uint8List aad,
  }) async {
    if (epk.length != keyBytes ||
        nonce24.length != nonceBytes ||
        box.length < macBytes) {
      return null;
    }
    try {
      final shared = await _x25519.sharedSecretKey(
        keyPair: recipientAgreement,
        remotePublicKey: SimplePublicKey(epk, type: KeyPairType.x25519),
      );
      final key = await _hkdf.deriveKey(
          secretKey: shared, nonce: nonce24, info: utf8.encode(intentInfo));
      final cipherText = box.sublist(0, box.length - macBytes);
      final mac = Mac(box.sublist(box.length - macBytes));
      final clear = await _aead.decrypt(
        SecretBox(cipherText, nonce: nonce24, mac: mac),
        secretKey: key,
        aad: aad,
      );
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }

  static Future<SecretKey> _deriveKey(
      SimpleKeyPair ephemeral, Uint8List recipientEk, Uint8List n24) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(recipientEk, type: KeyPairType.x25519),
    );
    return _hkdf.deriveKey(
        secretKey: shared, nonce: n24, info: utf8.encode(intentInfo));
  }

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(SecretKeyData.random(length: n).bytes);

  /// Random bytes for nonces (`n` in an intent, 16 bytes) and nicks.
  static Uint8List randomBytes(int n) => _randomBytes(n);

  /// A fresh X25519 keypair (the ephemeral key of one intent).
  static Future<SimpleKeyPair> newEphemeral() => _x25519.newKeyPair();

  static Future<Uint8List> publicKeyBytes(SimpleKeyPair keyPair) async =>
      Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

  // --- hex (strictly lower-case on the wire) ----------------------------------

  static const String _digits = '0123456789abcdef';

  static String hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(_digits[b >> 4]);
      sb.write(_digits[b & 0x0f]);
    }
    return sb.toString();
  }

  /// Null unless [s] is lower-case hex of exactly [length] bytes (or any
  /// even length when [length] is null).
  static Uint8List? unhex(String s, {int? length}) {
    if (s.length.isOdd) return null;
    if (length != null && s.length != length * 2) return null;
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final hi = _nibble(s.codeUnitAt(2 * i));
      final lo = _nibble(s.codeUnitAt(2 * i + 1));
      if (hi < 0 || lo < 0) return null;
      out[i] = (hi << 4) | lo;
    }
    return out;
  }

  static bool isLowerHex(String s, {int? length}) =>
      unhex(s, length: length) != null;

  static int _nibble(int unit) {
    if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
    if (unit >= 0x61 && unit <= 0x66) return unit - 0x61 + 10;
    return -1; // upper case is NOT canonical
  }
}

/// The two ephemeral keys of one nearby session.
class NearbySessionKeys {
  NearbySessionKeys._({
    required this.signing,
    required this.agreement,
    required this.skHex,
    required this.ekHex,
  });

  final SimpleKeyPair signing;
  final SimpleKeyPair agreement;

  /// Ed25519 public key, lower-case hex (the `sk` of records).
  final String skHex;

  /// X25519 public key, lower-case hex (the `ek` of records).
  final String ekHex;
}

class SealedIntent {
  const SealedIntent(
      {required this.epk, required this.nonce24, required this.box});
  final Uint8List epk;
  final Uint8List nonce24;

  /// ciphertext ‖ 16-byte Poly1305 tag.
  final Uint8List box;
}
