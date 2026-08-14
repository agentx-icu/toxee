import 'dart:io';

List<String> readPatchNames(File seriesFile) {
  return seriesFile
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
}

String? firstMissingPatch(List<String> patchNames, Directory patchesDir) {
  for (final name in patchNames) {
    if (!File('${patchesDir.path}/$name').existsSync()) {
      return name;
    }
  }
  return null;
}

String? expectedPatchSeriesIntegrityError(
  File seriesFile,
  List<String> patchNames,
  String storedPatchesSha256, {
  required String diagnosticPrefix,
}) {
  if (seriesFile.existsSync() && patchNames.isEmpty) {
    return '$diagnosticPrefix: patch series is empty or comment-only; '
        'refusing to treat it as valid';
  }
  if (storedPatchesSha256.isEmpty) {
    return null;
  }
  if (!seriesFile.existsSync()) {
    return '$diagnosticPrefix: patch series is missing while '
        'vendor_state.patches_sha256 records expected patches';
  }
  return null;
}

String computePatchesSha256(
  File seriesFile,
  List<String> patchNames,
  Directory patchesDir,
) {
  final tempFile = File(
    '${Directory.systemTemp.createTempSync('toxee_patches_').path}/concat.bin',
  );
  try {
    final sink = tempFile.openSync(mode: FileMode.write);
    try {
      sink.writeFromSync(seriesFile.readAsBytesSync());
      for (final name in patchNames) {
        final patchFile = File('${patchesDir.path}/$name');
        sink.writeFromSync(patchFile.readAsBytesSync());
      }
    } finally {
      sink.closeSync();
    }
    return _sha256FileSync(tempFile.path);
  } finally {
    try {
      tempFile.parent.deleteSync(recursive: true);
    } catch (_) {}
  }
}

String? offlinePatchIntegrityError(
  Directory tim2toxDir,
  String version,
  String storedPatchesSha256,
) {
  final patchesDir = Directory(
    '${tim2toxDir.path}/patches/tencent_cloud_chat_sdk/$version',
  );
  final seriesFile = File('${patchesDir.path}/series');
  final patchNames = seriesFile.existsSync()
      ? readPatchNames(seriesFile)
      : const <String>[];
  final expectedSeriesError = expectedPatchSeriesIntegrityError(
    seriesFile,
    patchNames,
    storedPatchesSha256,
    diagnosticPrefix: 'bootstrap_deps: offline-check',
  );
  if (expectedSeriesError != null) {
    return expectedSeriesError;
  }
  if (!seriesFile.existsSync()) {
    return null;
  }

  final missingPatch = firstMissingPatch(patchNames, patchesDir);
  if (missingPatch != null) {
    return 'bootstrap_deps: offline-check: patch series declares missing patch: $missingPatch';
  }
  if (storedPatchesSha256.isEmpty) {
    return 'bootstrap_deps: offline-check: vendor_state.patches_sha256 missing '
        'but patches series exists with ${patchNames.length} patch(es); re-run '
        '`dart tool/bootstrap_deps.dart` to record the digest.';
  }
  final computedSha256 = computePatchesSha256(
    seriesFile,
    patchNames,
    patchesDir,
  );
  if (computedSha256 != storedPatchesSha256) {
    return 'bootstrap_deps: offline-check: patches_sha256 in vendor_state does not match '
        'current patches content (re-run `dart tool/bootstrap_deps.dart`)';
  }
  return null;
}

Future<String> sha256File(String path) async {
  if (Platform.isWindows) {
    final result = await Process.run('certutil', [
      '-hashfile',
      path,
      'SHA256',
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw Exception('certutil failed: ${result.stderr}');
    }
    final lines = (result.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where(
          (line) =>
              RegExp(r'^[A-Fa-f0-9 ]+$').hasMatch(line) && line.isNotEmpty,
        )
        .toList();
    if (lines.isEmpty) {
      throw Exception('certutil output did not contain a SHA-256 hash');
    }
    return lines.first.replaceAll(' ', '').toLowerCase();
  }

  try {
    final result = await Process.run('sha256sum', [path], runInShell: false);
    if (result.exitCode == 0) {
      return (result.stdout as String).split(' ').first.trim();
    }
  } on ProcessException {
    // Fall through to shasum on platforms like macOS where sha256sum is absent.
  }

  final result = await Process.run('shasum', [
    '-a',
    '256',
    path,
  ], runInShell: false);
  if (result.exitCode != 0) {
    throw Exception('sha256 tool failed: ${result.stderr}');
  }
  return (result.stdout as String).split(' ').first.trim();
}

String _sha256FileSync(String path) {
  if (Platform.isWindows) {
    final result = Process.runSync('certutil', [
      '-hashfile',
      path,
      'SHA256',
    ], runInShell: false);
    if (result.exitCode != 0) {
      throw Exception('certutil failed: ${result.stderr}');
    }
    final lines = (result.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where(
          (line) =>
              RegExp(r'^[A-Fa-f0-9 ]+$').hasMatch(line) && line.isNotEmpty,
        )
        .toList();
    if (lines.isEmpty) {
      throw Exception('certutil output did not contain a SHA-256 hash');
    }
    return lines.first.replaceAll(' ', '').toLowerCase();
  }
  try {
    final result = Process.runSync('sha256sum', [path], runInShell: false);
    if (result.exitCode == 0) {
      return (result.stdout as String).split(' ').first.trim();
    }
  } on ProcessException {
    // Fall through to shasum on platforms like macOS where sha256sum is absent.
  }
  final result = Process.runSync('shasum', [
    '-a',
    '256',
    path,
  ], runInShell: false);
  if (result.exitCode != 0) {
    throw Exception('sha256 tool failed: ${result.stderr}');
  }
  return (result.stdout as String).split(' ').first.trim();
}
