import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/pairing/pairing_url.dart';

void main() {
  group('PairingUrl', () {
    test('encode/decode roundtrip preserves all fields', () {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final nonce = Uint8List.fromList(List<int>.generate(16, (i) => i * 3));
      final invite = PairingInvite(
        publicKey: key,
        ipAddress: '192.168.1.42',
        port: 51000,
        nonce: nonce,
      );
      final url = PairingUrl.encode(invite);
      expect(url, startsWith('tox://pair?'));
      final back = PairingUrl.decode(url)!;
      expect(back.publicKey, equals(key));
      expect(back.nonce, equals(nonce));
      expect(back.ipAddress, '192.168.1.42');
      expect(back.port, 51000);
      expect(back.version, PairingInvite.currentVersion);
    });

    test('decode returns null for non-tox-pair URLs', () {
      // Plain http URL — scanner should treat this as "user scanned the wrong
      // QR" and silently move on, not throw.
      expect(PairingUrl.decode('https://example.com/foo'), isNull);
      expect(PairingUrl.decode('not even a url'), isNull);
    });

    test('decode rejects unknown protocol version', () {
      final key = Uint8List(32);
      final nonce = Uint8List(16);
      final url = PairingUrl.encode(PairingInvite(
        publicKey: key,
        ipAddress: '10.0.0.1',
        port: 4444,
        nonce: nonce,
        version: 999,
      ));
      expect(() => PairingUrl.decode(url), throwsA(isA<FormatException>()));
    });

    test('decode rejects public IPv4 (anti-MITM trickery)', () {
      // Crafted by hand because PairingUrl.encode doesn't validate the IP on
      // the way out — that's intentional, so callers can encode loopback /
      // pre-computed addresses; the validator runs on the receiving side.
      const url =
          'tox://pair?key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&addr=8.8.8.8:4444&n=AAAAAAAAAAAAAAAAAAAAAA&v=1';
      expect(() => PairingUrl.decode(url), throwsA(isA<FormatException>()));
    });

    test('decode rejects malformed base64', () {
      const url =
          'tox://pair?key=!!!not-base64!!!&addr=192.168.1.1:4444&n=AAAAAAAAAAAAAAAAAAAAAA&v=1';
      expect(() => PairingUrl.decode(url), throwsA(isA<FormatException>()));
    });

    test('decode rejects key with wrong length', () {
      const url = 'tox://pair?key=YWJj&addr=192.168.1.1:4444&n=AAAAAAAAAAAAAAAAAAAAAA&v=1';
      expect(() => PairingUrl.decode(url), throwsA(isA<FormatException>()));
    });

    test('decode rejects missing required param', () {
      const url = 'tox://pair?addr=192.168.1.1:4444&n=AAAAAAAAAAAAAAAAAAAAAA&v=1';
      expect(() => PairingUrl.decode(url), throwsA(isA<FormatException>()));
    });

    group('isPrivateOrLinkLocalIPv4', () {
      test('accepts RFC1918 ranges', () {
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('10.0.0.1'), isTrue);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('172.16.5.5'), isTrue);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('172.31.0.1'), isTrue);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('192.168.1.1'), isTrue);
      });

      test('accepts link-local 169.254.0.0/16', () {
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('169.254.1.2'), isTrue);
      });

      test('accepts loopback (needed for tests)', () {
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('127.0.0.1'), isTrue);
      });

      test('accepts CGNAT 100.64.0.0/10 (Tailscale-friendly)', () {
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('100.64.1.1'), isTrue);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('100.127.1.1'), isTrue);
      });

      test('rejects public IPs', () {
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('8.8.8.8'), isFalse);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('1.1.1.1'), isFalse);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('172.32.0.1'), isFalse);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('192.169.0.1'), isFalse);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('100.128.1.1'), isFalse);
      });

      test('rejects garbage', () {
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('not.an.ip'), isFalse);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4('999.999.999.999'), isFalse);
        expect(PairingUrl.isPrivateOrLinkLocalIPv4(''), isFalse);
      });
    });
  });
}
