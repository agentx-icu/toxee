import 'package:path/path.dart' as p;

import 'qtox_harness_common.dart';
import 'qtox_harness_scratch.dart';

enum QtoxArtifactShape { appBundle, executable }

class QtoxArtifactSelection {
  QtoxArtifactSelection._({
    required this.sourcePath,
    required this.selection,
    required this.shape,
    required this.appExecutableName,
  });

  factory QtoxArtifactSelection.app(
    String path, {
    String executableName = 'qtox',
  }) {
    return QtoxArtifactSelection._(
      sourcePath: p.normalize(p.absolute(path)),
      selection: 'app',
      shape: QtoxArtifactShape.appBundle,
      appExecutableName: _validatedExecutableName(executableName),
    );
  }

  factory QtoxArtifactSelection.executable(String path) {
    return QtoxArtifactSelection._(
      sourcePath: p.normalize(p.absolute(path)),
      selection: 'executable',
      shape: QtoxArtifactShape.executable,
      appExecutableName: 'qtox',
    );
  }

  factory QtoxArtifactSelection.officialArtifact(
    String path, {
    String executableName = 'qtox',
  }) {
    final normalized = p.normalize(p.absolute(path));
    final isApp = normalized.toLowerCase().endsWith('.app');
    return QtoxArtifactSelection._(
      sourcePath: normalized,
      selection: 'official-artifact',
      shape: isApp ? QtoxArtifactShape.appBundle : QtoxArtifactShape.executable,
      appExecutableName: _validatedExecutableName(executableName),
    );
  }

  final String sourcePath;
  final String selection;
  final QtoxArtifactShape shape;
  final String appExecutableName;

  String stagedArtifactPath(QtoxScratchLayout layout) {
    return layout.guardPath(
      p.join(
        layout.stagingRoot,
        shape == QtoxArtifactShape.appBundle ? 'qTox.app' : 'qtox',
      ),
    );
  }

  String stagedExecutablePath(QtoxScratchLayout layout) {
    final artifact = stagedArtifactPath(layout);
    if (shape == QtoxArtifactShape.executable) {
      return artifact;
    }
    return layout.guardPath(
      p.join(artifact, 'Contents', 'MacOS', appExecutableName),
    );
  }

  Map<String, Object> toJson(QtoxScratchLayout layout) => <String, Object>{
    'selection': selection,
    'shape': shape.name,
    'sourcePath': sourcePath,
    'stagedArtifactPath': stagedArtifactPath(layout),
    'stagedExecutablePath': stagedExecutablePath(layout),
  };

  static String _validatedExecutableName(String value) {
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
      throw QtoxHarnessException('unsafe app executable name: $value');
    }
    return value;
  }
}

class QtoxBootstrapConfig {
  QtoxBootstrapConfig({
    required String publicKey,
    this.ipv4 = '127.0.0.1',
    this.ipv6 = '::1',
    this.udpPort = 33445,
    List<int> tcpPorts = const <int>[33445],
  }) : publicKey = _validatedPublicKey(publicKey),
       tcpPorts = List<int>.unmodifiable(tcpPorts) {
    if (ipv4 != '127.0.0.1' || ipv6 != '::1') {
      throw QtoxHarnessException(
        'the disposable harness accepts loopback bootstrap addresses only',
      );
    }
    _validatePort(udpPort, 'UDP');
    if (tcpPorts.isEmpty) {
      throw QtoxHarnessException('at least one TCP bootstrap port is required');
    }
    for (final port in tcpPorts) {
      _validatePort(port, 'TCP');
    }
  }

  final String publicKey;
  final String ipv4;
  final String ipv6;
  final int udpPort;
  final List<int> tcpPorts;

  Map<String, Object> get metadata => <String, Object>{
    'addresses': 'loopback-only',
    'udpPort': udpPort,
    'tcpPorts': tcpPorts,
    'publicKey': 'configured',
  };

  Map<String, Object> get qtoxJson => <String, Object>{
    'nodes': <Object>[
      <String, Object>{
        'ipv4': ipv4,
        'ipv6': ipv6,
        'port': udpPort,
        'tcp_ports': tcpPorts,
        'public_key': publicKey,
        'maintainer': 'toxee qTox compatibility harness',
        'status_udp': true,
        'status_tcp': true,
      },
    ],
  };

  static String _validatedPublicKey(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-F0-9]{64}$').hasMatch(normalized)) {
      throw QtoxHarnessException(
        'bootstrap public key must be exactly 64 hexadecimal characters',
      );
    }
    return normalized;
  }

  static void _validatePort(int value, String label) {
    if (value < 1 || value > 65535) {
      throw QtoxHarnessException('$label port is outside 1..65535: $value');
    }
  }
}
