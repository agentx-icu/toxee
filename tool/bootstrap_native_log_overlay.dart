import 'dart:convert';
import 'dart:io';

import 'bootstrap_patch_integrity.dart';

void main(List<String> args) {
  ensureNativeLogOverlay(
    Directory.current.path,
    checkOnly: args.contains('--check-only'),
  );
}

// App-owned changes to the ignored native checkout must be reproducible from a
// fresh bootstrap. Do not repair drift by resetting or overwriting user files.
void ensureNativeLogOverlay(String repoRoot, {bool checkOnly = false}) {
  final source = Directory('$repoRoot/third_party/tim2tox');
  final overlays = Directory('$repoRoot/tool/native_log_overlays');
  final manifestFile = File('${overlays.path}/manifest.json');
  final patch = File('${overlays.path}/bounded-logging.patch');
  if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw StateError('Native log overlay: checkout must be a real directory');
  }
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final revision = manifest['revision'] as String;
  if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(revision)) {
    throw StateError('Native log overlay: invalid pinned revision');
  }
  final head = _git(source, ['rev-parse', 'HEAD']).trim();
  if (head != revision) {
    throw StateError(
      'Native log overlay: unsupported checkout $head; expected $revision',
    );
  }
  if (_digest(patch) != manifest['patch_sha256']) {
    throw StateError('Native log overlay: patch SHA-256 mismatch');
  }
  final entries = (manifest['files'] as List).cast<Map<String, dynamic>>();
  if (entries.isEmpty) {
    throw StateError('Native log overlay: empty file inventory');
  }
  var allBefore = true;
  var allAfter = true;
  final paths = <String>{};
  for (final entry in entries) {
    final path = entry['path'] as String;
    final segments = path.split('/');
    if (segments.any(
          (s) =>
              !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(s) ||
              s == '.' ||
              s == '..',
        ) ||
        !paths.add(path)) {
      throw StateError('Native log overlay: invalid or duplicate path');
    }
    final file = File('${source.path}/$path');
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    final root =
        '${source.resolveSymbolicLinksSync()}${Platform.pathSeparator}';
    if (type == FileSystemEntityType.notFound) {
      // A new pinned header is allowed only in an existing internal directory.
      if (entry['before_sha256'] != null ||
          !file.parent.resolveSymbolicLinksSync().startsWith(root)) {
        throw StateError('Native log overlay: missing or unsafe target');
      }
      allAfter = false;
    } else {
      if (type != FileSystemEntityType.file ||
          !file.resolveSymbolicLinksSync().startsWith(root)) {
        throw StateError(
          'Native log overlay: target must be an internal regular file',
        );
      }
      final digest = _digest(file);
      allBefore = allBefore && digest == entry['before_sha256'];
      allAfter = allAfter && digest == entry['after_sha256'];
    }
  }

  // A patch must touch exactly the inventoried paths, including after a review
  // changes the manifest. git apply --check guarantees no partial application.
  final touched = _git(source, [
    'apply',
    '--numstat',
    patch.absolute.path,
  ]).trim().split('\n').map((line) => line.split('\t').last).toSet();
  if (touched.length != paths.length || !touched.containsAll(paths)) {
    throw StateError(
      'Native log overlay: patch paths differ from file inventory',
    );
  }
  if (allAfter) return;
  if (!allBefore) {
    throw StateError(
      'Native log overlay: source drift or partial application; '
      'preserve local changes and review the pinned overlay',
    );
  }
  if (checkOnly) {
    throw StateError('Native log overlay: not applied; run bootstrap');
  }
  final args = ['apply', '--unidiff-zero', '--ignore-space-change'];
  _git(source, [...args, '--check', patch.absolute.path]);
  _git(source, [...args, patch.absolute.path]);
  // Re-read the entire inventory; a successful git exit alone is insufficient.
  ensureNativeLogOverlay(repoRoot, checkOnly: true);
  stdout.writeln('Native log overlay: verified bounded single-owner logging');
}

String _git(Directory source, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: source.path);
  if (result.exitCode != 0) {
    throw StateError(
      'Native log overlay: git ${args.first} failed: ${result.stderr}',
    );
  }
  return result.stdout as String;
}

String _digest(File file) {
  // Windows Git checkouts may use CRLF. Check the exact UTF-8 source with only
  // that checkout transformation normalised; no whitespace/content is ignored.
  final directory = Directory.systemTemp.createTempSync(
    'toxee_native_log_hash_',
  );
  try {
    final normalised = File('${directory.path}/source');
    normalised.writeAsStringSync(
      file.readAsStringSync().replaceAll('\r\n', '\n'),
    );
    return computePatchesSha256(normalised, const [], directory);
  } finally {
    directory.deleteSync(recursive: true);
  }
}
