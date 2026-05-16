import 'dart:io';

import 'pairing_url.dart';

/// LAN address discovery helpers used by the pairing host page.
///
/// We pick the first non-loopback IPv4 interface in a private/link-local
/// range. Multi-homed hosts (e.g. Tailscale + WiFi) will have multiple
/// candidates — for v1 we just pick the first that matches and let the user
/// decide if pairing succeeds. If pairing fails (wrong subnet), the client
/// surfaces the LAN-unreachable error and the user can try again.
class PairingLan {
  PairingLan._();

  /// Return the first LAN IPv4 address found, or null if nothing matches.
  ///
  /// Loopback `127.0.0.1` is intentionally excluded for production callers
  /// (passing it to a QR would only work in a single-process test). For
  /// loopback in tests, just construct the host directly with `127.0.0.1`.
  static Future<String?> findLanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: true,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          // We want a private/link-local IPv4 — i.e. something a peer on the
          // same WiFi/Ethernet can actually reach. The same predicate the
          // URL decoder enforces.
          if (PairingUrl.isPrivateOrLinkLocalIPv4(ip) && ip != '127.0.0.1') {
            return ip;
          }
        }
      }
    } catch (_) {
      // Some platforms (notably web) reject NetworkInterface.list(). Caller
      // handles the null and surfaces a "no LAN available" UI state.
    }
    return null;
  }
}
