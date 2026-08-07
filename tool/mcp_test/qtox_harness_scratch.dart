import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'qtox_harness_common.dart';

class QtoxScratchLayout {
  QtoxScratchLayout._({
    required this.repositoryRoot,
    required this.allowedScratchRoot,
    required this.scratchRoot,
  });

  factory QtoxScratchLayout.fromRepository({
    required String repositoryRoot,
    String? scratchRoot,
  }) {
    final repositoryDirectory = Directory(
      p.normalize(p.absolute(repositoryRoot)),
    );
    if (!repositoryDirectory.existsSync()) {
      throw QtoxHarnessException(
        'repository root does not exist: ${repositoryDirectory.path}',
      );
    }
    final repository = repositoryDirectory.resolveSymbolicLinksSync();
    final allowed = p.join(repository, 'build', 'qtox_external_peer');
    final requested = p.normalize(
      p.absolute(scratchRoot ?? p.join(allowed, 'default')),
    );
    if (!p.isWithin(allowed, requested)) {
      throw QtoxHarnessException(
        'scratch root must be a child of $allowed: $requested',
      );
    }
    return QtoxScratchLayout._(
      repositoryRoot: repository,
      allowedScratchRoot: allowed,
      scratchRoot: requested,
    );
  }

  final String repositoryRoot;
  final String allowedScratchRoot;
  final String scratchRoot;

  String get markerPath => guardPath(p.join(scratchRoot, '.qtox_owner.json'));
  String get homeRoot => guardPath(p.join(scratchRoot, 'home'));
  String get picturesRoot => guardPath(p.join(homeRoot, 'Pictures'));
  String get tempRoot => guardPath(p.join(scratchRoot, 'tmp'));
  String get xdgRoot => guardPath(p.join(scratchRoot, 'xdg'));
  String get stagingRoot => guardPath(p.join(scratchRoot, 'staged'));
  String get portableRoot => guardPath(p.join(scratchRoot, 'profile'));
  String get artifactsRoot => guardPath(p.join(scratchRoot, 'artifacts'));
  String get qtoxIniPath => guardPath(p.join(portableRoot, 'qtox.ini'));
  String get bootstrapNodesPath =>
      guardPath(p.join(portableRoot, 'bootstrapNodes.json'));
  String get stderrPath => guardPath(p.join(artifactsRoot, 'qtox.stderr.log'));
  String get screenshotPath =>
      guardPath(p.join(picturesRoot, qtoxDefaultScreenshotName));
  String get instanceMetadataPath =>
      guardPath(p.join(scratchRoot, 'qtox_instance.json'));

  String guardPath(String candidate) {
    final normalized = p.normalize(p.absolute(candidate));
    if (!p.equals(normalized, scratchRoot) &&
        !p.isWithin(scratchRoot, normalized)) {
      throw QtoxHarnessException(
        'writable path escapes scratch root: $normalized',
      );
    }
    return normalized;
  }
}

class QtoxScratchGuard {
  const QtoxScratchGuard(this.layout);

  final QtoxScratchLayout layout;

  void validateBoundary() {
    var current = layout.repositoryRoot;
    final relative = p.relative(
      layout.scratchRoot,
      from: layout.repositoryRoot,
    );
    for (final component in p.split(relative)) {
      current = p.join(current, component);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw QtoxHarnessException(
          'scratch boundary contains a symbolic link: $current',
        );
      }
      if (type == FileSystemEntityType.notFound) {
        break;
      }
    }
  }

  Future<void> requireOwnerMarker() async {
    validateBoundary();
    rejectSymlinksTo(layout.markerPath);
    final marker = File(layout.markerPath);
    if (!marker.existsSync()) {
      throw QtoxHarnessException(
        'refusing to use unowned scratch root: ${layout.scratchRoot}',
      );
    }
    final decoded = jsonDecode(await marker.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['owner'] != qtoxHarnessOwner ||
        decoded['schemaVersion'] != qtoxHarnessSchemaVersion ||
        decoded['scratchRoot'] != layout.scratchRoot) {
      throw QtoxHarnessException('scratch ownership marker is invalid');
    }
  }

  Future<void> writeOwnerMarker() async {
    await writeQtoxJson(layout.markerPath, <String, Object>{
      'schemaVersion': qtoxHarnessSchemaVersion,
      'owner': qtoxHarnessOwner,
      'scratchRoot': layout.scratchRoot,
    });
  }

  void rejectSymlinksTo(String candidate) {
    final target = layout.guardPath(candidate);
    var current = layout.scratchRoot;
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      _throwSymlink(current);
    }
    for (final component in p.split(p.relative(target, from: current))) {
      current = p.join(current, component);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        _throwSymlink(current);
      }
      if (type == FileSystemEntityType.notFound) {
        return;
      }
    }
  }

  Never _throwSymlink(String path) {
    throw QtoxHarnessException(
      'writable scratch path contains a symbolic link: $path',
    );
  }
}

class QtoxMetadataStore {
  const QtoxMetadataStore({
    required this.layout,
    required this.guard,
    required this.qtoxLogPath,
  });

  final QtoxScratchLayout layout;
  final QtoxScratchGuard guard;
  final String qtoxLogPath;

  Future<Map<String, dynamic>> read() async {
    guard.validateBoundary();
    guard.rejectSymlinksTo(layout.instanceMetadataPath);
    final file = File(layout.instanceMetadataPath);
    if (!file.existsSync()) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['owner'] != qtoxHarnessOwner) {
      throw QtoxHarnessException('qTox instance metadata is invalid');
    }
    return decoded;
  }

  Future<void> write({
    required String phase,
    int? pid,
    String? processIdentity,
    int? exitCode,
  }) async {
    guard.validateBoundary();
    guard.rejectSymlinksTo(layout.instanceMetadataPath);
    await writeQtoxJson(layout.instanceMetadataPath, <String, Object?>{
      'schemaVersion': qtoxHarnessSchemaVersion,
      'owner': qtoxHarnessOwner,
      'phase': phase,
      if (pid != null) 'pid': pid,
      if (processIdentity != null) 'processIdentity': processIdentity,
      if (exitCode != null) 'exitCode': exitCode,
      'artifacts': <String, Object>{
        'stderr': _artifact(layout.stderrPath),
        'qtoxLog': _artifact(qtoxLogPath),
        'sigusr1Screenshot': _artifact(layout.screenshotPath),
      },
    });
  }

  static Map<String, Object> _artifact(String path) {
    final file = File(path);
    return <String, Object>{
      'path': path,
      'exists': file.existsSync(),
      'bytes': file.existsSync() ? file.lengthSync() : 0,
    };
  }
}
