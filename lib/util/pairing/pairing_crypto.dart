import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Cryptographic primitives for the QR + LAN cross-device pairing handshake
/// (PR 2 of the identity-portability plan).
///
/// Handshake (spec recap from `docs/designs/identity-portability-and-multi-account.md`):
///
///   1. Device A generates a fresh X25519 ephemeral on every QR display.
///      Process restart invalidates all prior ephemerals (we do not persist
///      them anywhere).
///   2. QR carries Device A's ephemeral public key + LAN address + a 16-byte
///      nonce, plus a version field. Encoding/decoding lives in
///      `pairing_url.dart`.
///   3. Device B opens a TCP socket to Device A and sends its own X25519
///      ephemeral pubkey. Both sides compute the X25519 shared secret.
///   4. Both sides run `HKDF-SHA256(shared_secret, salt=nonce,
///      info="toxee-pair-v1")` to derive a 32-byte ChaCha20-Poly1305 AEAD
///      transit key.
///   5. Both sides separately derive a 6-digit decimal SAS from
///      `HKDF-SHA256(transit_key || sorted(pubA, pubB), salt=nonce,
///      info="toxee-pair-sas-v1")` — the SAS being a function of BOTH
///      pubkeys is what defeats active MITM (an attacker who substitutes
///      either pubkey changes the SAS).
///   6. User taps "the codes match" on BOTH devices.
///   7. Device A AEAD-encrypts the `.tox` blob with the transit key and
///      streams it. **AEAD wraps unconditionally**, regardless of whether
///      the account password is set — the account password is an inner
///      layer only. This is the iteration-2 bug fix; do not regress it.
class PairingCrypto {
  PairingCrypto._();

  /// HKDF info string for the AEAD transit key derivation.
  static const String transitInfo = 'toxee-pair-v1';

  /// HKDF info string for the SAS (Short Authentication String) derivation.
  static const String sasInfo = 'toxee-pair-sas-v1';

  /// Length of the X25519 public key in bytes.
  static const int publicKeyLength = 32;

  /// Length of the AEAD transit key in bytes (ChaCha20-Poly1305 uses 256-bit
  /// keys).
  static const int transitKeyLength = 32;

  /// Length of the session nonce, in bytes. Used as HKDF salt.
  static const int nonceLength = 16;

  /// Length of the SAS in decimal digits.
  static const int sasDigits = 6;

  /// AEAD nonce length (96 bits for ChaCha20-Poly1305 standard, per RFC 7539).
  static const int aeadNonceLength = 12;

  static final X25519 _x25519 = X25519();
  static final Hkdf _hkdfTransit = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: transitKeyLength,
  );
  // SAS is derived as a longer HKDF block then reduced modulo 10^digits, which
  // is uniform enough for a 6-digit code (bias is well below 2^-32).
  static final Hkdf _hkdfSas = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 8,
  );
  static final Chacha20 _aead = Chacha20.poly1305Aead();

  /// Generate a fresh X25519 ephemeral key pair. Callers MUST generate a new
  /// keypair for each pairing session (e.g. each time a QR is displayed) and
  /// destroy the previous one. Process restart implicitly invalidates all
  /// in-flight ephemerals because we never persist them.
  static Future<SimpleKeyPair> generateEphemeral() => _x25519.newKeyPair();

  /// Derive a fresh 16-byte nonce using a cryptographically-secure RNG.
  /// The nonce is included in the QR payload and used as HKDF salt so a
  /// passive observer can't link two sessions even if they reuse the same
  /// ephemeral (we never reuse the ephemeral, but defense in depth).
  static Uint8List generateNonce({Random? random}) {
    final rng = random ?? Random.secure();
    final out = Uint8List(nonceLength);
    for (var i = 0; i < out.length; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  /// Run the X25519 ECDH and return the raw 32-byte shared secret.
  ///
  /// [ourKeyPair] is the local ephemeral keypair, [theirPublicKey] is the
  /// peer's 32-byte X25519 public key as transmitted on the wire.
  static Future<Uint8List> deriveSharedSecret({
    required SimpleKeyPair ourKeyPair,
    required List<int> theirPublicKey,
  }) async {
    if (theirPublicKey.length != publicKeyLength) {
      throw ArgumentError(
          'Peer public key must be $publicKeyLength bytes, got ${theirPublicKey.length}');
    }
    final remote = SimplePublicKey(
      List<int>.from(theirPublicKey),
      type: KeyPairType.x25519,
    );
    final secret = await _x25519.sharedSecretKey(
      keyPair: ourKeyPair,
      remotePublicKey: remote,
    );
    final bytes = await secret.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Derive both the AEAD transit key and the user-visible SAS from a single
  /// X25519 shared secret + the session nonce + both ephemeral pubkeys.
  ///
  /// Both sides compute identical (transitKey, sas) pairs because:
  ///   - The X25519 ECDH yields the same shared secret on both sides.
  ///   - The pubkeys are sorted lexicographically before being fed into the
  ///     SAS HKDF, so order-independence is built in.
  ///
  /// SAS is decimal so users can read it aloud cleanly even with a small
  /// modulo bias (which for `2^64 mod 10^6 ≈ 2.4e10` is < 2^-32 — beneath
  /// the threshold where it matters for a 6-digit human verification code).
  static Future<PairingSessionKeys> deriveSessionKeys({
    required Uint8List sharedSecret,
    required Uint8List nonce,
    required List<int> ourPublicKey,
    required List<int> theirPublicKey,
  }) async {
    if (nonce.length != nonceLength) {
      throw ArgumentError(
          'Nonce must be $nonceLength bytes, got ${nonce.length}');
    }
    if (ourPublicKey.length != publicKeyLength ||
        theirPublicKey.length != publicKeyLength) {
      throw ArgumentError('Public keys must be $publicKeyLength bytes');
    }

    // (a) AEAD transit key — HKDF over the raw shared secret.
    final secretKey = SecretKey(sharedSecret);
    final transitDerived = await _hkdfTransit.deriveKey(
      secretKey: secretKey,
      nonce: nonce,
      info: _info(transitInfo),
    );
    final transitBytes =
        Uint8List.fromList(await transitDerived.extractBytes());

    // (b) SAS — HKDF over (transit_key || sorted(pubA, pubB)). Sorting makes
    // it order-independent (defeats trivial reflection attacks) AND the SAS
    // being a function of BOTH pubkeys is what stops an active MITM: if an
    // attacker substitutes either pubkey on the wire, both sides will see
    // different SAS digits.
    final sortedPubs = _sortConcatenate(ourPublicKey, theirPublicKey);
    final sasInput = Uint8List(transitBytes.length + sortedPubs.length)
      ..setRange(0, transitBytes.length, transitBytes)
      ..setRange(transitBytes.length, transitBytes.length + sortedPubs.length,
          sortedPubs);
    final sasDerived = await _hkdfSas.deriveKey(
      secretKey: SecretKey(sasInput),
      nonce: nonce,
      info: _info(sasInfo),
    );
    final sasBytes = await sasDerived.extractBytes();
    final sas = _bytesToSasCode(sasBytes);

    return PairingSessionKeys(
      transitKey: transitBytes,
      sas: sas,
    );
  }

  /// AEAD-encrypt [plaintext] with [transitKey] and a freshly generated
  /// 12-byte nonce. The returned blob is laid out as `nonce || ciphertext ||
  /// mac` so the receiver can decrypt without out-of-band data.
  ///
  /// [associatedData] is optional AEAD AAD — pass non-empty if you want to
  /// bind the ciphertext to a specific context (e.g. version byte). The
  /// handshake currently uses empty AAD because the SAS already authenticates
  /// the channel; AAD is exposed so future versions can layer in a context
  /// string without breaking back-compat.
  static Future<Uint8List> aeadEncrypt({
    required Uint8List transitKey,
    required List<int> plaintext,
    List<int> associatedData = const <int>[],
    Random? random,
  }) async {
    if (transitKey.length != transitKeyLength) {
      throw ArgumentError('Transit key must be $transitKeyLength bytes');
    }
    final rng = random ?? Random.secure();
    final nonce = Uint8List(aeadNonceLength);
    for (var i = 0; i < nonce.length; i++) {
      nonce[i] = rng.nextInt(256);
    }
    final box = await _aead.encrypt(
      plaintext,
      secretKey: SecretKey(transitKey),
      nonce: nonce,
      aad: associatedData,
    );
    final mac = box.mac.bytes;
    final out = Uint8List(nonce.length + box.cipherText.length + mac.length)
      ..setRange(0, nonce.length, nonce)
      ..setRange(nonce.length, nonce.length + box.cipherText.length,
          box.cipherText)
      ..setRange(nonce.length + box.cipherText.length, nonce.length +
          box.cipherText.length + mac.length, mac);
    return out;
  }

  /// AEAD-decrypt a blob produced by [aeadEncrypt]. Throws on tampering or
  /// truncation. On decryption failure callers MUST abort the session without
  /// writing any partial plaintext.
  static Future<Uint8List> aeadDecrypt({
    required Uint8List transitKey,
    required Uint8List blob,
    List<int> associatedData = const <int>[],
  }) async {
    if (transitKey.length != transitKeyLength) {
      throw ArgumentError('Transit key must be $transitKeyLength bytes');
    }
    final macLength = _aead.macAlgorithm.macLength;
    final minLen = aeadNonceLength + macLength;
    if (blob.length < minLen) {
      throw const FormatException('AEAD blob is too short to be valid');
    }
    final nonce = blob.sublist(0, aeadNonceLength);
    final cipher = blob.sublist(aeadNonceLength, blob.length - macLength);
    final macBytes = blob.sublist(blob.length - macLength);
    final box = SecretBox(cipher, nonce: nonce, mac: Mac(macBytes));
    final plain = await _aead.decrypt(
      box,
      secretKey: SecretKey(transitKey),
      aad: associatedData,
    );
    return Uint8List.fromList(plain);
  }

  // --- helpers ---------------------------------------------------------------

  static List<int> _info(String s) => s.codeUnits;

  static Uint8List _sortConcatenate(List<int> a, List<int> b) {
    // Lex compare the two 32-byte pubkeys; concatenate smaller first so the
    // SAS is order-independent.
    final cmp = _lexCompare(a, b);
    final first = cmp <= 0 ? a : b;
    final second = cmp <= 0 ? b : a;
    return Uint8List(first.length + second.length)
      ..setRange(0, first.length, first)
      ..setRange(first.length, first.length + second.length, second);
  }

  static int _lexCompare(List<int> a, List<int> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final d = a[i] - b[i];
      if (d != 0) return d;
    }
    return a.length - b.length;
  }

  static String _bytesToSasCode(List<int> bytes) {
    // Read first 8 bytes big-endian as an unsigned int, modulo 10^digits.
    // 8 bytes (2^64) is comfortably larger than 10^6 so the modulo bias is
    // negligible for a human-readable code.
    var value = 0;
    final take = bytes.length < 8 ? bytes.length : 8;
    for (var i = 0; i < take; i++) {
      // Avoid overflow on web JS bitops: use multiplication + addition.
      value = value * 256 + bytes[i];
    }
    // Modulo 10^sasDigits.
    var modulus = 1;
    for (var i = 0; i < sasDigits; i++) {
      modulus *= 10;
    }
    final reduced = value % modulus;
    return reduced.toString().padLeft(sasDigits, '0');
  }
}

/// Outputs of [PairingCrypto.deriveSessionKeys] — the AEAD transit key and the
/// user-visible Short Authentication String.
class PairingSessionKeys {
  PairingSessionKeys({required this.transitKey, required this.sas});
  final Uint8List transitKey;

  /// 6-digit decimal SAS shown to both users for verification.
  final String sas;
}
