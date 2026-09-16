import 'dart:io';

import '../lan_bootstrap_service.dart';
import 'pairing_url.dart';

/// LAN address discovery helpers used by the pairing host page.
///
/// A multi-homed host (e.g. Tailscale + WiFi) has several candidates. We share
/// [LanBootstrapServiceManager.selectPreferredAddress] so pairing applies the
/// SAME policy as the LAN bootstrap service: real RFC1918 LAN addresses rank
/// first and virtual/VPN interfaces (docker/tun/utun/wg) are filtered out. Only
/// when no such address exists do we fall back to a CGNAT / other private
/// address (100.64/10 Tailscale, which the URL decoder deliberately accepts as
/// a valid pair target), instead of letting a VPN endpoint win over WiFi (LAN
/// review 2026-09-15, F9).
class PairingLan {
  PairingLan._();

  /// Return the preferred LAN IPv4 address, or null if nothing matches.
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
      final candidates = interfaces
          .expand(
            (iface) => iface.addresses.map(
              (addr) => LanAddressCandidate(
                interfaceName: iface.name,
                address: addr.address,
                type: addr.type,
                isLoopback: addr.isLoopback,
              ),
            ),
          )
          .toList();

      // Preferred: a real RFC1918 LAN address, virtual/VPN interfaces removed.
      final preferred = LanBootstrapServiceManager.selectPreferredAddress(
        candidates,
      );
      if (preferred != null &&
          preferred != '127.0.0.1' &&
          PairingUrl.isPrivateOrLinkLocalIPv4(preferred)) {
        return preferred;
      }

      // Fallback: the first pairable address the URL decoder accepts (covers
      // CGNAT / Tailscale, which selectPreferredAddress filters out).
      for (final candidate in candidates) {
        final ip = candidate.address;
        if (PairingUrl.isPrivateOrLinkLocalIPv4(ip) && ip != '127.0.0.1') {
          return ip;
        }
      }
    } catch (_) {
      // Some platforms (notably web) reject NetworkInterface.list(). Caller
      // handles the null and surfaces a "no LAN available" UI state.
    }
    return null;
  }
}
