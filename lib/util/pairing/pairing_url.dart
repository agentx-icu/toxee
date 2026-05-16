import 'dart:convert';
import 'dart:typed_data';

/// QR-encoded pairing invitation. Lives in the URL Device A puts on the QR
/// code:
///
///   `tox://pair?key=<base64url-pubkey>&addr=<ip:port>&n=<base64url-nonce>&v=1`
///
/// Lives in [decodePairingUrl] / [encodePairingUrl]. The version field is
/// mandatory and validated; unknown versions are rejected so we don't have
/// to ship a permissive parser today that backs us into a corner tomorrow.
class PairingInvite {
  PairingInvite({
    required this.publicKey,
    required this.ipAddress,
    required this.port,
    required this.nonce,
    this.version = currentVersion,
  });

  /// Wire-protocol version. Bumped any time the handshake or QR layout
  /// changes incompatibly.
  static const int currentVersion = 1;

  /// Device A's 32-byte X25519 ephemeral public key.
  final Uint8List publicKey;

  /// LAN IPv4 address (RFC1918 or link-local only — validated on decode).
  final String ipAddress;
  final int port;

  /// Session nonce (16 bytes); used as HKDF salt.
  final Uint8List nonce;

  final int version;
}

class PairingUrl {
  PairingUrl._();

  static const String scheme = 'tox';
  static const String host = 'pair';

  /// Encode a [PairingInvite] as a `tox://pair?...` URL fit for a QR code.
  static String encode(PairingInvite invite) {
    final keyB64 = base64UrlEncode(invite.publicKey);
    final nonceB64 = base64UrlEncode(invite.nonce);
    final addr = '${invite.ipAddress}:${invite.port}';
    final params = <String, String>{
      'key': keyB64,
      'addr': addr,
      'n': nonceB64,
      'v': '${invite.version}',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$scheme://$host?$query';
  }

  /// Parse a pairing URL and validate every field. Returns null if the URL is
  /// syntactically invalid; throws [FormatException] for semantically invalid
  /// inputs (unknown version, wrong scheme/host, public IP, malformed base64).
  ///
  /// Splitting the contract this way means scanner UI can blindly call
  /// [decode] in a try/catch and surface the FormatException message to the
  /// user, while silent failures (e.g. user scanned a non-toxee QR) return
  /// null and the scanner just keeps looking.
  static PairingInvite? decode(String url) {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return null;
    }
    if (uri.scheme.toLowerCase() != scheme || uri.host.toLowerCase() != host) {
      // Not addressed to us at all — let the scanner keep scanning.
      return null;
    }

    final versionRaw = uri.queryParameters['v'];
    if (versionRaw == null) {
      throw const FormatException('Pairing URL missing version (v=)');
    }
    final version = int.tryParse(versionRaw);
    if (version == null) {
      throw FormatException('Pairing URL has malformed version: $versionRaw');
    }
    if (version != PairingInvite.currentVersion) {
      throw FormatException(
          'Unsupported pairing protocol version: $version (this app speaks '
          'v${PairingInvite.currentVersion}). Update both devices to the '
          'same toxee build.');
    }

    final keyB64 = uri.queryParameters['key'];
    final nonceB64 = uri.queryParameters['n'];
    final addr = uri.queryParameters['addr'];
    if (keyB64 == null || nonceB64 == null || addr == null) {
      throw const FormatException(
          'Pairing URL is missing required parameter (key, n, addr)');
    }

    final Uint8List key;
    final Uint8List nonce;
    try {
      key = Uint8List.fromList(base64Url.decode(_padBase64(keyB64)));
      nonce = Uint8List.fromList(base64Url.decode(_padBase64(nonceB64)));
    } on FormatException {
      throw const FormatException('Pairing URL has malformed base64 payload');
    }

    if (key.length != 32) {
      throw FormatException(
          'Pairing URL public key has wrong length: ${key.length} (expected 32)');
    }
    if (nonce.length != 16) {
      throw FormatException(
          'Pairing URL nonce has wrong length: ${nonce.length} (expected 16)');
    }

    final addrParts = addr.split(':');
    if (addrParts.length != 2) {
      throw FormatException(
          'Pairing URL addr must be "ip:port", got: $addr');
    }
    final ip = addrParts[0];
    final port = int.tryParse(addrParts[1]);
    if (port == null || port <= 0 || port > 65535) {
      throw FormatException('Pairing URL has invalid port: ${addrParts[1]}');
    }

    if (!isPrivateOrLinkLocalIPv4(ip)) {
      // Defense against social-engineering a user into scanning a QR that
      // points to an attacker's public-internet box. Pairing is LAN-only by
      // design (per CEO plan: "Stays P2P (LAN-only). No external relay.").
      throw FormatException(
          'Pairing URL points to a non-LAN address: $ip. Pairing is restricted '
          'to private/link-local IPv4 addresses.');
    }

    return PairingInvite(
      publicKey: key,
      ipAddress: ip,
      port: port,
      nonce: nonce,
      version: version,
    );
  }

  /// Return true iff [ip] parses as IPv4 in a private (RFC 1918) or
  /// link-local (RFC 3927) range. We deliberately accept loopback for the
  /// integration tests that run both sides in the same process.
  ///
  /// IPv6 is intentionally out of scope for v1: link-local IPv6 (`fe80::/10`)
  /// needs a zone-id (`%en0`) for sockets to actually work on most OSes and
  /// the UX cost of getting that right isn't worth shipping for v1. CEO plan
  /// LAN reachability fallback covers this case ("use Export → Import via
  /// file instead.").
  static bool isPrivateOrLinkLocalIPv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return false;
      octets.add(v);
    }
    // 10.0.0.0/8
    if (octets[0] == 10) return true;
    // 172.16.0.0/12
    if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
    // 192.168.0.0/16
    if (octets[0] == 192 && octets[1] == 168) return true;
    // 169.254.0.0/16 (link-local)
    if (octets[0] == 169 && octets[1] == 254) return true;
    // 127.0.0.0/8 (loopback) — needed for the in-process integration test
    // that runs host + client over loopback.
    if (octets[0] == 127) return true;
    // CGNAT 100.64.0.0/10 — common with Tailscale and other mesh VPNs that
    // users may reasonably want to pair across. Treated as "private" here.
    if (octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127) return true;
    return false;
  }

  /// base64Url decode in Dart is strict about padding; QR-encoded URLs often
  /// drop trailing `=` to save scan area, so re-pad before decode.
  static String _padBase64(String input) {
    final pad = (4 - input.length % 4) % 4;
    return input + ('=' * pad);
  }
}
