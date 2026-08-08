import 'dart:io';

import 'package:path/path.dart' as p;

import 'qtox_harness_common.dart';
import 'qtox_harness_config.dart';
import 'qtox_harness_plan.dart';
import 'qtox_harness_scratch.dart';

class QtoxHarnessPreparer {
  const QtoxHarnessPreparer({
    required this.layout,
    required this.artifact,
    required this.bootstrap,
    required this.plan,
    required this.guard,
    required this.metadata,
  });

  final QtoxScratchLayout layout;
  final QtoxArtifactSelection artifact;
  final QtoxBootstrapConfig bootstrap;
  final QtoxHarnessPlan plan;
  final QtoxScratchGuard guard;
  final QtoxMetadataStore metadata;

  Future<void> prepare(Future<bool> Function() teardown) async {
    guard.validateBoundary();
    if (Directory(layout.scratchRoot).existsSync()) {
      await guard.requireOwnerMarker();
      await teardown();
      await Directory(layout.scratchRoot).delete(recursive: true);
    }

    for (final directory in <String>[
      layout.scratchRoot,
      layout.homeRoot,
      layout.picturesRoot,
      layout.tempRoot,
      p.join(layout.xdgRoot, 'config'),
      p.join(layout.xdgRoot, 'data'),
      p.join(layout.xdgRoot, 'cache'),
      p.join(layout.xdgRoot, 'runtime'),
      layout.stagingRoot,
      layout.portableRoot,
      layout.artifactsRoot,
    ]) {
      await Directory(layout.guardPath(directory)).create(recursive: true);
    }
    await guard.writeOwnerMarker();
    await _stageArtifact();
    await File(layout.qtoxIniPath).writeAsString(_qtoxIni);
    await writeQtoxJson(layout.bootstrapNodesPath, bootstrap.qtoxJson);
    await metadata.write(phase: 'prepared');
  }

  Future<void> requirePreparedArtifact() async {
    final executable = File(plan.executablePath);
    if (!executable.existsSync()) {
      throw QtoxHarnessException(
        'staged qTox executable is missing: ${plan.executablePath}',
      );
    }
    final resolved = await executable.resolveSymbolicLinks();
    layout.guardPath(resolved);
    if ((executable.statSync().mode & 0x49) == 0) {
      throw QtoxHarnessException('staged qTox executable is not executable');
    }
  }

  Future<void> _stageArtifact() async {
    final sourceType = FileSystemEntity.typeSync(
      artifact.sourcePath,
      followLinks: true,
    );
    final destination = artifact.stagedArtifactPath(layout);
    if (artifact.shape == QtoxArtifactShape.appBundle) {
      if (sourceType != FileSystemEntityType.directory ||
          !artifact.sourcePath.toLowerCase().endsWith('.app')) {
        throw QtoxHarnessException(
          'qTox app path must be an existing .app directory',
        );
      }
      final result = await Process.run('/usr/bin/ditto', <String>[
        artifact.sourcePath,
        destination,
      ]);
      if (result.exitCode != 0) {
        throw QtoxHarnessException('failed to stage qTox.app');
      }
    } else {
      await _stageExecutable(sourceType, destination);
    }
    await requirePreparedArtifact();
  }

  Future<void> _stageExecutable(
    FileSystemEntityType sourceType,
    String destination,
  ) async {
    if (sourceType != FileSystemEntityType.file) {
      throw QtoxHarnessException(
        'qTox executable path must be an existing file; extract archives first',
      );
    }
    final source = File(artifact.sourcePath);
    final mode = source.statSync().mode & 0x1ff;
    if ((mode & 0x49) == 0) {
      throw QtoxHarnessException('provided qTox executable is not executable');
    }
    await source.copy(destination);
    final chmod = await Process.run('/bin/chmod', <String>[
      mode.toRadixString(8),
      destination,
    ]);
    if (chmod.exitCode != 0) {
      throw QtoxHarnessException('failed to preserve executable permissions');
    }
  }

  static const _qtoxIni = '''
[Login]
autoLogin=false

[General]
autostartInTray=false
checkUpdates=false
closeToTray=false
showSystemTray=false

[Advanced]
enableDebug=true
enableIPv6=true
enableLanDiscovery=true
forceTCP=false
makeToxPortable=true

[GUI]
minimizeToTray=false
showWindow=true
''';
}
