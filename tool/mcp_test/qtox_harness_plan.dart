import 'dart:convert';

import 'package:path/path.dart' as p;

import 'qtox_harness_common.dart';
import 'qtox_harness_config.dart';
import 'qtox_harness_scratch.dart';

class QtoxHarnessPlan {
  QtoxHarnessPlan({
    required this.layout,
    required this.artifact,
    required this.bootstrap,
    required this.profileName,
  });

  final QtoxScratchLayout layout;
  final QtoxArtifactSelection artifact;
  final QtoxBootstrapConfig bootstrap;
  final String? profileName;

  String get executablePath => artifact.stagedExecutablePath(layout);
  String get workingDirectory => p.dirname(executablePath);
  String get qtoxLogPath =>
      layout.guardPath(p.join(workingDirectory, 'qtox.log'));

  List<String> get arguments => <String>[
    '-D',
    layout.portableRoot,
    '-I',
    'on',
    '-U',
    'on',
    '-L',
    'on',
    '-P',
    'none',
    if (profileName == null) ...<String>['-l'] else ...<String>[
      '-p',
      profileName!,
    ],
  ];

  Map<String, String> get environment => <String, String>{
    'HOME': layout.homeRoot,
    'TMPDIR': layout.tempRoot,
    'XDG_CONFIG_HOME': layout.guardPath(p.join(layout.xdgRoot, 'config')),
    'XDG_DATA_HOME': layout.guardPath(p.join(layout.xdgRoot, 'data')),
    'XDG_CACHE_HOME': layout.guardPath(p.join(layout.xdgRoot, 'cache')),
    'XDG_RUNTIME_DIR': layout.guardPath(p.join(layout.xdgRoot, 'runtime')),
    'QTOX_SCREENSHOT': qtoxDefaultScreenshotName,
    'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': qtoxHarnessSchemaVersion,
    'mode': 'plan-only',
    'liveExecution': false,
    'artifact': artifact.toJson(layout),
    'scratch': <String, Object>{
      'root': layout.scratchRoot,
      'allowedParent': layout.allowedScratchRoot,
      'resetPolicy': 'owned-marker-required',
      'home': layout.homeRoot,
      'portableProfileRoot': layout.portableRoot,
    },
    'configuration': <String, Object?>{
      'qtoxIni': layout.qtoxIniPath,
      'bootstrapNodes': layout.bootstrapNodesPath,
      'profileMode': profileName == null ? 'login-screen' : 'named-profile',
      'profileName': profileName,
      'network': <String, Object>{
        'ipv6': true,
        'udp': true,
        'lanDiscovery': true,
        'proxy': 'none',
        'bootstrap': bootstrap.metadata,
      },
    },
    'launch': <String, Object>{
      'executable': executablePath,
      'arguments': arguments,
      'workingDirectory': workingDirectory,
      'environment': environment,
      'inheritParentEnvironment': false,
    },
    'artifacts': <String, Object>{
      'stderr': layout.stderrPath,
      'qtoxLog': qtoxLogPath,
      'sigusr1Screenshot': layout.screenshotPath,
      'instanceMetadata': layout.instanceMetadataPath,
      'contentPolicy': 'retain raw files; record and emit metadata only',
    },
    'teardown': <String, Object>{
      'signal': 'SIGTERM',
      'graceSeconds': 5,
      'scratchRetention': 'keep for evidence; next prepare resets it',
    },
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
