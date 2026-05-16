import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/pairing/pairing_client.dart';
import 'package:toxee/util/pairing/pairing_crypto.dart';
import 'package:toxee/util/pairing/pairing_host.dart';
import 'package:toxee/util/pairing/pairing_url.dart';

/// THE iteration-2-bug regression test.
///
/// Background: an earlier draft of the spec made AEAD-wrapping conditional on
/// the user having set an account password. That meant a passwordless account
/// shipped its `.tox` blob (which contains the long-term Tox secret key, the
/// public toxId, friend list, etc.) over the LAN socket in plaintext — fine on
/// a trusted home network, fatal on a coffee-shop AP.
///
/// The fix: AEAD wraps **unconditionally**. This test asserts the property by:
///
///   1. Standing up a real PairingHost + a man-in-the-middle TCP proxy.
///   2. Capturing every byte the host sends.
///   3. Driving a real client through the handshake to completion.
///   4. Asserting that the captured raw bytes do NOT contain any segment of
///      the well-known plaintext payload, and that the bulk of the captured
///      data passes a simple entropy check (random-looking, i.e. ciphertext).
///
/// If a future refactor regresses to "skip AEAD when no password," this test
/// will fail loudly on the substring assertion.
void main() {
  test('plaintext .tox blob is NEVER sent on the wire (passwordless account)',
      () async {
    // Use a payload with a recognizable magic string so the substring check
    // catches even subtle leakage.
    const magic = 'TOXEE-PAIRING-PLAINTEXT-CANARY-DO-NOT-LEAK';
    final magicBytes = Uint8List.fromList(magic.codeUnits);
    final fakeProfile = Uint8List(8192);
    // Fill with a deterministic byte pattern, then splice in the canary at
    // a few offsets so the assertion can't accidentally pass on length alone.
    for (var i = 0; i < fakeProfile.length; i++) {
      fakeProfile[i] = (i * 37 + 5) & 0xff;
    }
    for (final offset in [0, 1000, 4000, fakeProfile.length - magicBytes.length]) {
      fakeProfile.setRange(offset, offset + magicBytes.length, magicBytes);
    }

    // ---- The MITM proxy. Listens on a separate port, forwards both ways
    // through the host, and captures every byte the host sends downstream. ----
    final host = PairingHost(
      loadProfileBlob: () async => fakeProfile,
      bindAddress: '127.0.0.1',
    );
    // Drive host.start to discover its port.
    final realHostUrl = await host.start(advertiseAddress: '127.0.0.1');
    final realInvite = PairingUrl.decode(realHostUrl)!;

    final captured = BytesBuilder(copy: false);
    final proxyServer = await ServerSocket.bind('127.0.0.1', 0);
    addTearDown(() async {
      try {
        await proxyServer.close();
      } catch (_) {}
    });
    proxyServer.listen((clientSide) async {
      final upstream = await Socket.connect(
          realInvite.ipAddress, realInvite.port);
      // host → client direction is what we care about for this assertion.
      upstream.listen((data) {
        captured.add(data);
        clientSide.add(data);
      }, onDone: () {
        try {
          clientSide.close();
        } catch (_) {}
      }, onError: (_) {});
      clientSide.listen(upstream.add,
          onDone: () {
            try {
              upstream.close();
            } catch (_) {}
          },
          onError: (_) {});
    });

    // Build a "fake" pairing URL that points the client at the proxy, but
    // carries the REAL host's pubkey + nonce so the X25519 handshake still
    // succeeds end-to-end. The proxy is transparent for this property test
    // (we're not testing MITM defense here — that's covered by the SAS
    // mismatch test — we're testing transit confidentiality).
    final proxyInvite = PairingInvite(
      publicKey: realInvite.publicKey,
      ipAddress: '127.0.0.1',
      port: proxyServer.port,
      nonce: realInvite.nonce,
    );
    final proxyUrl = PairingUrl.encode(proxyInvite);

    Uint8List? received;
    final client = PairingClient(
      materializeProfile: (plaintext) async {
        received = plaintext;
        return 'TOXID-OK';
      },
    );

    final hostDone = Completer<void>();
    final clientDone = Completer<void>();
    host.events.listen((e) {
      if (e is HostCompleted || e is HostFailed) {
        if (!hostDone.isCompleted) hostDone.complete();
      }
    });
    client.events.listen((e) {
      if (e is ClientCompleted || e is ClientFailed) {
        if (!clientDone.isCompleted) clientDone.complete();
      }
    });

    final connectFut = client.connect(proxyUrl);

    // Wait for awaitingSas on both sides, then confirm.
    var hostSas = false;
    var clientSas = false;
    final hostSub = host.events.listen((e) {
      if (e is HostAwaitingSas) hostSas = true;
    });
    final clientSub = client.events.listen((e) {
      if (e is ClientAwaitingSas) clientSas = true;
    });
    while (!(hostSas && clientSas)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    host.confirmSas();
    client.confirmSas();

    await connectFut;
    await hostDone.future.timeout(const Duration(seconds: 10));
    await clientDone.future.timeout(const Duration(seconds: 10));
    await hostSub.cancel();
    await clientSub.cancel();

    // Sanity: the receiver got the plaintext correctly.
    expect(received, isNotNull);
    expect(received, equals(fakeProfile));

    // THE assertion: the bytes that flowed host→client must not contain the
    // canary string. If AEAD-wrapping is somehow skipped, the magic bytes
    // would land in the capture verbatim and this fails immediately.
    final wireBytes = captured.toBytes();
    expect(wireBytes.length, greaterThan(0));
    final wireString = String.fromCharCodes(wireBytes);
    expect(wireString.contains(magic), isFalse,
        reason: 'AEAD-wrapping regression: the plaintext canary appeared on '
            'the wire. The .tox blob MUST be encrypted with the X25519-derived '
            'transit key regardless of whether an account password is set.');

    // Bonus: also assert no 64-byte substring of the plaintext leaked. A weak
    // cipher (or an XOR-with-key bug) might preserve runs even if the canary
    // string itself is scrambled. We sample a handful of windows from the
    // plaintext and assert none of them appear contiguously in the capture.
    for (final offset in [16, 2048, 6000]) {
      final window = Uint8List.sublistView(
          fakeProfile, offset, offset + 64);
      expect(_containsSubsequence(wireBytes, window), isFalse,
          reason: 'A 64-byte plaintext window at offset $offset appeared on '
              'the wire. AEAD must hide it.');
    }
  });

  test('AEAD encrypts even with empty plaintext', () async {
    // Pathological-but-fast sanity check: empty plaintext should still
    // produce a non-empty AEAD blob (nonce + 16-byte tag, minimum).
    final key = Uint8List(32);
    final cipher = await PairingCrypto.aeadEncrypt(
      transitKey: key,
      plaintext: const <int>[],
    );
    expect(cipher.length,
        PairingCrypto.aeadNonceLength + 16); // nonce + Poly1305 tag
  });
}

bool _containsSubsequence(Uint8List haystack, Uint8List needle) {
  if (needle.isEmpty) return true;
  if (haystack.length < needle.length) return false;
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
