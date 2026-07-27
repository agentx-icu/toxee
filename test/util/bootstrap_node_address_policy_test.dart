import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/bootstrap_nodes.dart';
import 'package:toxee/util/lan_bootstrap_service.dart';

void main() {
  group('BootstrapNode preferred host', () {
    test('prefers a trimmed IPv4 or hostname', () {
      final node = BootstrapNode(
        ipv4: ' tox.example.com ',
        ipv6: '2001:db8::20',
        port: 33445,
        publicKey: 'A' * 64,
        status: 'ONLINE',
      );

      expect(node.preferredHost, 'tox.example.com');
      expect(node.formattedEndpoint, 'tox.example.com:33445');
    });

    test('falls back to IPv6 and brackets its endpoint', () {
      final node = BootstrapNode(
        ipv4: '',
        ipv6: ' 2001:db8::20 ',
        port: 33445,
        publicKey: 'A' * 64,
        status: 'ONLINE',
      );

      expect(node.preferredHost, '2001:db8::20');
      expect(node.formattedEndpoint, '[2001:db8::20]:33445');
    });

    test('returns null when neither address is usable', () {
      final node = BootstrapNode(
        ipv4: 'NONE',
        ipv6: '-',
        port: 33445,
        publicKey: 'A' * 64,
        status: 'ONLINE',
      );

      expect(node.preferredHost, isNull);
      expect(node.formattedEndpoint, isNull);
    });
  });

  group('LAN address policy', () {
    const virtualIpv4 = LanAddressCandidate(
      interfaceName: 'docker0',
      address: '192.168.99.1',
      type: InternetAddressType.IPv4,
    );
    const wifiIpv4 = LanAddressCandidate(
      interfaceName: 'en0',
      address: '192.168.1.20',
      type: InternetAddressType.IPv4,
    );
    const ethernetIpv4 = LanAddressCandidate(
      interfaceName: 'en1',
      address: '10.0.0.8',
      type: InternetAddressType.IPv4,
    );
    const ulaIpv6 = LanAddressCandidate(
      interfaceName: 'en0',
      address: 'fd00::20',
      type: InternetAddressType.IPv6,
    );

    test('filters virtual interfaces and is stable across input order', () {
      final forward = LanBootstrapServiceManager.selectPreferredAddress([
        virtualIpv4,
        ethernetIpv4,
        wifiIpv4,
      ]);
      final reverse = LanBootstrapServiceManager.selectPreferredAddress(
        [wifiIpv4, ethernetIpv4, virtualIpv4].reversed,
      );

      expect(forward, '192.168.1.20');
      expect(reverse, forward);
    });

    test('prefers physical IPv4 before IPv6', () {
      expect(
        LanBootstrapServiceManager.selectPreferredAddress([ulaIpv6, wifiIpv4]),
        wifiIpv4.address,
      );
    });

    test('falls back to ULA then global IPv6', () {
      const global = LanAddressCandidate(
        interfaceName: 'en1',
        address: '2001:4860::20',
        type: InternetAddressType.IPv6,
      );

      expect(
        LanBootstrapServiceManager.selectPreferredAddress([global, ulaIpv6]),
        ulaIpv6.address,
      );
      expect(
        LanBootstrapServiceManager.selectPreferredAddress([global]),
        global.address,
      );
    });

    test('excludes loopback and IPv6 link-local addresses', () {
      const loopback = LanAddressCandidate(
        interfaceName: 'lo0',
        address: '::1',
        type: InternetAddressType.IPv6,
        isLoopback: true,
      );
      const linkLocal = LanAddressCandidate(
        interfaceName: 'en0',
        address: 'fe80::1',
        type: InternetAddressType.IPv6,
      );

      expect(
        LanBootstrapServiceManager.selectPreferredAddress([
          loopback,
          linkLocal,
        ]),
        isNull,
      );
    });

    test('uses APIPA only as the final fallback', () {
      const apipa = LanAddressCandidate(
        interfaceName: 'en0',
        address: '169.254.10.20',
        type: InternetAddressType.IPv4,
      );

      expect(
        LanBootstrapServiceManager.selectPreferredAddress([apipa, ulaIpv6]),
        ulaIpv6.address,
      );
      expect(
        LanBootstrapServiceManager.selectPreferredAddress([apipa]),
        apipa.address,
      );
    });
  });
}
