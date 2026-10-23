import 'dart:convert';
import 'dart:io';

import 'bootstrap_patch_integrity.dart';

// App-owned changes to the ignored UIKit checkout must be reproducible from a
// fresh bootstrap. Do not repair drift by resetting or overwriting user files.
void ensureUIKitOverlay(String repoRoot, {bool checkOnly = false}) {
  final source = Directory('$repoRoot/third_party/chat-uikit-flutter');
  final overlays = Directory('$repoRoot/tool/uikit_overlays');
  final manifestFile = File('${overlays.path}/manifest.json');
  final patch = File('${overlays.path}/motion-and-paste.patch');
  if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw StateError('UIKit overlay: checkout must be a real directory');
  }
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final revision = manifest['revision'] as String;
  if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(revision)) {
    throw StateError('UIKit overlay: invalid pinned revision');
  }
  final head = _git(source, ['rev-parse', 'HEAD']).trim();
  if (head != revision) {
    throw StateError(
      'UIKit overlay: unsupported checkout $head; expected $revision',
    );
  }
  if (_digest(patch) != manifest['patch_sha256']) {
    throw StateError('UIKit overlay: patch SHA-256 mismatch');
  }
  final entries = (manifest['files'] as List).cast<Map<String, dynamic>>();
  if (entries.isEmpty) throw StateError('UIKit overlay: empty file inventory');
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
      throw StateError('UIKit overlay: invalid or duplicate path');
    }
    final file = File('${source.path}/$path');
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !file.resolveSymbolicLinksSync().startsWith(
          '${source.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
        )) {
      throw StateError(
        'UIKit overlay: target must be an internal regular file',
      );
    }
    final digest = _digest(file);
    allBefore = allBefore && digest == entry['before_sha256'];
    allAfter = allAfter && digest == entry['after_sha256'];
  }
  // A patch must touch exactly the inventoried paths, including after a review
  // changes the manifest. git apply --check guarantees no partial application.
  final touched = _git(source, [
    'apply',
    '--numstat',
    patch.absolute.path,
  ]).trim().split('\n').map((line) => line.split('\t').last).toSet();
  if (touched.length != paths.length || !touched.containsAll(paths)) {
    throw StateError('UIKit overlay: patch paths differ from file inventory');
  }
  if (allAfter) return;
  if (!allBefore) {
    throw StateError(
      'UIKit overlay: source drift or partial application; '
      'preserve local changes and review the pinned overlay',
    );
  }
  if (checkOnly) throw StateError('UIKit overlay: not applied; run bootstrap');
  final args = ['apply', '--unidiff-zero', '--ignore-space-change'];
  _git(source, [...args, '--check', patch.absolute.path]);
  _git(source, [...args, patch.absolute.path]);
  // Re-read the entire inventory; a successful git exit alone is insufficient.
  ensureUIKitOverlay(repoRoot, checkOnly: true);
  stdout.writeln('UIKit overlay: verified reduced-motion and paste fixes');
}

String _git(Directory source, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: source.path);
  if (result.exitCode != 0) {
    throw StateError(
      'UIKit overlay: git ${args.first} failed: ${result.stderr}',
    );
  }
  return result.stdout as String;
}

String _digest(File file) {
  // Windows Git checkouts may use CRLF. Check the exact UTF-8 source with only
  // that checkout transformation normalised; no whitespace/content is ignored.
  final directory = Directory.systemTemp.createTempSync('toxee_uikit_hash_');
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
