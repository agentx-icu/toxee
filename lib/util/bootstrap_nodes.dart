import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'logger.dart';

String formatBootstrapEndpoint(String host, int port) {
  final trimmedHost = host.trim();
  return trimmedHost.contains(':')
      ? '[$trimmedHost]:$port'
      : '$trimmedHost:$port';
}

class BootstrapNode {
  final String ipv4;
  final String? ipv6;
  final int port;
  final String publicKey;
  final String? maintainer;
  final String? location;
  final String status; // "ONLINE" or "OFFLINE"
  final int? lastPing; // seconds ago
  final List<int>? tcpPorts;

  BootstrapNode({
    required this.ipv4,
    this.ipv6,
    required this.port,
    required this.publicKey,
    this.maintainer,
    this.location,
    required this.status,
    this.lastPing,
    this.tcpPorts,
  });

  String? get preferredHost {
    final ipv4Host = _usableHost(ipv4);
    if (ipv4Host != null) return ipv4Host;
    return _usableHost(ipv6);
  }

  String? get formattedEndpoint {
    final host = preferredHost;
    if (host == null) return null;
    return formatBootstrapEndpoint(host, port);
  }

  static String? _usableHost(String? value) {
    final host = value?.trim();
    if (host == null ||
        host.isEmpty ||
        host == '-' ||
        host.toUpperCase() == 'NONE') {
      return null;
    }
    return host;
  }

  factory BootstrapNode.fromJson(Map<String, dynamic> json) {
    final ipv4 = json['ipv4'] as String? ?? '';
    final ipv6 = json['ipv6'] as String?;
    // Handle "NONE" as null for IPv4/IPv6
    final ipv4Final = (ipv4 == 'NONE' || ipv4.isEmpty) ? '' : ipv4;
    final ipv6Final =
        (ipv6 == 'NONE' || ipv6 == '-' || ipv6 == null || ipv6.isEmpty)
        ? null
        : ipv6;
    final port = json['port'] as int? ?? 33445;
    final publicKey = json['public_key'] as String? ?? '';
    final maintainer = json['maintainer'] as String?;
    final location = json['location'] as String?;

    // Determine status from status_udp and status_tcp
    final statusUdp = json['status_udp'] as bool? ?? false;
    final statusTcp = json['status_tcp'] as bool? ?? false;
    final status = (statusUdp || statusTcp) ? 'ONLINE' : 'OFFLINE';

    // last_ping is a timestamp, calculate seconds ago
    final lastPingTimestamp = json['last_ping'] as int?;
    int? lastPing;
    if (lastPingTimestamp != null && lastPingTimestamp > 0) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      lastPing = now - lastPingTimestamp;
    }

    // tcp_ports is an array in the API
    final tcpPortsList = json['tcp_ports'] as List<dynamic>?;
    List<int>? tcpPorts;
    if (tcpPortsList != null && tcpPortsList.isNotEmpty) {
      tcpPorts = tcpPortsList.map((e) => (e as num).toInt()).toList();
    }

    return BootstrapNode(
      ipv4: ipv4Final,
      ipv6: ipv6Final,
      port: port,
      publicKey: publicKey,
      maintainer: maintainer,
      location: location,
      status: status,
      lastPing: lastPing,
      tcpPorts: tcpPorts,
    );
  }

  Map<String, dynamic> toJson() => {
    'ipv4': ipv4,
    'ipv6': ipv6,
    'port': port,
    'public_key': publicKey,
    'maintainer': maintainer,
    'location': location,
    'status': status,
    'last_ping': lastPing,
    'tcp_ports': tcpPorts?.join(','),
  };
}

class BootstrapNodesService {
  static const String _apiUrl = 'https://nodes.tox.chat/json';
  static const Duration _fetchTimeout = Duration(seconds: 8);

  /// Tox DHT public keys are 64 hex chars (32 bytes). Reject malformed
  /// publicKey fields from the remote node list — they would only ever
  /// produce a bootstrap failure at best, and at worst could be a vector
  /// for a downgrade injection.
  static final RegExp _pubKeyPattern = RegExp(r'^[0-9A-Fa-f]{64}$');
  static bool _isValidPubKey(String pubKey) => _pubKeyPattern.hasMatch(pubKey);

  /// True iff the most recent [fetchNodes] call returned the hardcoded
  /// fallback list (because the HTTP fetch failed or returned no nodes).
  /// The UI can read this to surface a "showing offline node list" hint
  /// instead of silently behaving as if the live list was loaded.
  static bool lastFetchUsedFallback = false;

  static Future<List<BootstrapNode>> fetchNodes() async {
    try {
      final response = await http
          .get(Uri.parse(_apiUrl))
          .timeout(_fetchTimeout);
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        final nodesJson = jsonData['nodes'] as List<dynamic>? ?? [];
        if (nodesJson.isEmpty) {
          AppLogger.warn(
            '[BootstrapNodesService] fetchNodes: empty list from $_apiUrl, using fallback',
          );
          lastFetchUsedFallback = true;
          return _getFallbackNodes();
        }
        final rawNodes = nodesJson
            .map((n) => BootstrapNode.fromJson(n as Map<String, dynamic>))
            .toList();
        final nodes = rawNodes
            .where((n) => _isValidPubKey(n.publicKey))
            .toList();
        final dropped = rawNodes.length - nodes.length;
        if (dropped > 0) {
          AppLogger.warn(
            '[BootstrapNodesService] fetchNodes: dropped $dropped node(s) with invalid public_key',
          );
        }
        if (nodes.isEmpty) {
          AppLogger.warn(
            '[BootstrapNodesService] fetchNodes: no nodes survived publicKey validation, using fallback',
          );
          lastFetchUsedFallback = true;
          return _getFallbackNodes();
        }
        lastFetchUsedFallback = false;
        return nodes;
      }
      AppLogger.warn(
        '[BootstrapNodesService] fetchNodes: HTTP ${response.statusCode} from $_apiUrl, using fallback',
      );
    } on TimeoutException catch (_) {
      AppLogger.warn(
        '[BootstrapNodesService] fetchNodes: timed out after ${_fetchTimeout.inSeconds}s, using fallback',
      );
    } catch (e) {
      AppLogger.warn(
        '[BootstrapNodesService] fetchNodes failed ($e), using fallback',
      );
    }
    lastFetchUsedFallback = true;
    return _getFallbackNodes();
  }

  /// The built-in, hardcoded public bootstrap nodes. Used as the offline
  /// fallback when [fetchNodes] can't reach nodes.tox.chat, and as the
  /// immediate first-run seed so a brand-new account has DHT entry points
  /// without waiting on an HTTP round-trip.
  static List<BootstrapNode> get fallbackNodes => _getFallbackNodes();

  static List<BootstrapNode> _getFallbackNodes() {
    // Fallback nodes from the codebase
    return [
      BootstrapNode(
        ipv4: '144.217.167.73',
        port: 33445,
        publicKey:
            '7E5668E0EE09E19F320AD47902419331FFEE147BB3606769CFBE921A2A2FD34C',
        location: 'Canada',
        status: 'ONLINE',
        tcpPorts: [3389, 33445],
      ),
      BootstrapNode(
        ipv4: 'tox.abilinski.com',
        port: 33445,
        publicKey:
            '10C00EB250C3233E343E2AEBA07115A5C28920E9C8D29492F6D00B29049EDC7E',
        location: 'Canada',
        status: 'ONLINE',
      ),
      BootstrapNode(
        ipv4: '139.162.110.188',
        ipv6: '2400:8902::f03c:93ff:fe69:bf77',
        port: 33445,
        publicKey:
            'F76A11284547163889DDC89A7738CF271797BF5E5E220643E97AD3C7E7903D55',
        location: 'Canada',
        status: 'ONLINE',
        tcpPorts: [33445, 443, 3389],
      ),
      BootstrapNode(
        ipv4: '172.105.109.31',
        ipv6: '2600:3c04::f03c:92ff:fe30:5df',
        port: 33445,
        publicKey:
            'D46E97CF995DC1820B92B7D899E152A217D36ABE22730FEA4B6BF1BFC06C617C',
        location: 'Canada',
        status: 'ONLINE',
        tcpPorts: [33445],
      ),
      BootstrapNode(
        ipv4: 'tox.kurnevsky.net',
        ipv6: 'tox.kurnevsky.net',
        port: 33445,
        publicKey:
            '82EF82BA33445A1F91A7DB27189ECFC0C013E06E3DA71F588ED692BED625EC23',
        location: 'Netherlands',
        status: 'ONLINE',
      ),
      BootstrapNode(
        ipv4: '45.32.184.23',
        ipv6: '2a05:f480:1400:3c56:5400:5ff:fe56:d8ff',
        port: 33445,
        publicKey:
            '81C916A3605724106C2E7487DC72FF2F9EB662EB34C85C0C692D8312B442635C',
        location: 'Netherlands',
        status: 'ONLINE',
        tcpPorts: [33445, 3389],
      ),
      BootstrapNode(
        ipv4: 'tox1.mf-net.eu',
        ipv6: 'tox1.mf-net.eu',
        port: 33445,
        publicKey:
            'B3E5FA80DC8EBD1149AD2AB35ED8B85BD546DEDE261CA593234C619249419506',
        location: 'Germany',
        status: 'ONLINE',
        tcpPorts: [3389, 33445],
      ),
      BootstrapNode(
        ipv4: 'tox2.mf-net.eu',
        ipv6: 'tox2.mf-net.eu',
        port: 33445,
        publicKey:
            '70EA214FDE161E7432530605213F18F7427DC773E276B3E317A07531F548545F',
        location: 'Germany',
        status: 'ONLINE',
        tcpPorts: [33445, 3389],
      ),
      BootstrapNode(
        ipv4: '188.225.9.167',
        ipv6: '209:dead:ded:4991:49f3:b6c0:9869:3019',
        port: 33445,
        publicKey:
            '1911341A83E02503AB1FD6561BD64AF3A9D6C3F12B5FBB656976B2E678644A67',
        location: 'Russian Federation',
        status: 'ONLINE',
        tcpPorts: [3389, 33445],
      ),
      BootstrapNode(
        ipv4: '3.0.24.15',
        port: 33445,
        publicKey:
            'E20ABCF38CDBFFD7D04B29C956B33F7B27A3BB7AF0618101617B036E4AEA402D',
        location: 'Singapore',
        status: 'ONLINE',
        tcpPorts: [33445],
      ),
      BootstrapNode(
        ipv4: '104.225.141.59',
        port: 43334,
        publicKey:
            '933BA20B2E258B4C0D475B6DECE90C7E827FE83EFA9655414E7841251B19A72C',
        location: 'United States',
        status: 'ONLINE',
        tcpPorts: [3389, 33445],
      ),
    ];
  }
}
