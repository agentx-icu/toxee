// Bootstrap dependencies: init submodules, vendor tencent_cloud_chat_sdk, (later: apply patches, write overrides).
// Run from repo root: dart run tool/bootstrap_deps.dart
// Options: --offline-check-only (only verify existing state, no network), --force (re-vendor SDK)
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final repoRoot = _repoRoot();
  final offlineOnly = args.contains('--offline-check-only');
  final force = args.contains('--force');

  if (offlineOnly) {
    exit(_offlineCheck(repoRoot));
  }

  // 1) Submodule sync and update (or clone from .gitmodules if not yet registered)
  //    Do this first so third_party/tim2tox exists and contains the lock file.
  const submodulePaths = ['third_party/tim2tox', 'third_party/chat-uikit-flutter'];
  const submoduleUrls = {
    'third_party/tim2tox': 'https://github.com/agentx-icu/tim2tox.git',
    'third_party/chat-uikit-flutter': 'https://github.com/agentx-icu/chat-uikit-flutter.git',
  };
  int code = await _run(repoRoot, 'git', ['submodule', 'sync', '--recursive']);
  if (code != 0) {
    stderr.writeln('bootstrap_deps: git submodule sync failed');
    exit(code);
  }
  // Update only registered submodules (no path args to avoid "pathspec did not match" when not registered)
  code = await _run(repoRoot, 'git', ['submodule', 'update', '--init', '--recursive']);
  if (code != 0) {
    stdout.writeln('Submodules not yet registered in repo; will clone from .gitmodules if missing.');
  }

  // Ensure submodule dirs exist: either from update --init or clone from .gitmodules URLs
  for (final p in submodulePaths) {
    final dir = Directory('$repoRoot/$p');
    if (!dir.existsSync()) {
      final url = submoduleUrls[p];
      if (url == null) {
        stderr.writeln('bootstrap_deps: no URL for $p');
        exit(1);
      }
      stdout.writeln('Cloning $p...');
      final parts = p.split('/');
      final parentPath = parts.sublist(0, parts.length - 1).join('/');
      if (parentPath.isNotEmpty) {
        Directory('$repoRoot/$parentPath').createSync(recursive: true);
      }
      code = await _run(repoRoot, 'git', ['clone', url, p]);
      if (code != 0) {
        stderr.writeln('bootstrap_deps: git clone $p failed');
        exit(code);
      }
    }
  }

  // Pin chat-uikit-flutter to v2 branch (see .gitmodules branch = v2)
  final uikitDir = Directory('$repoRoot/third_party/chat-uikit-flutter');
  if (uikitDir.existsSync()) {
    const branch = 'v2';
    int c = await _run(repoRoot, 'git', ['-C', 'third_party/chat-uikit-flutter', 'fetch', 'origin', branch]);
    if (c == 0) {
      c = await _run(repoRoot, 'git', ['-C', 'third_party/chat-uikit-flutter', 'checkout', '-B', branch, 'FETCH_HEAD']);
      if (c == 0) {
        stdout.writeln('third_party/chat-uikit-flutter switched to branch $branch');
      }
    }
  }

  final tim2toxDir = Directory('$repoRoot/third_party/tim2tox');
  final lockFile = File('$repoRoot/third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json');
  if (!lockFile.existsSync()) {
    stderr.writeln('bootstrap_deps: missing third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json');
    stderr.writeln('  Ensure third_party/tim2tox is present (clone or use tool/verify_bootstrap_local.sh for local workspace).');
    exit(1);
  }
  final lock = jsonDecode(lockFile.readAsStringSync()) as Map<String, dynamic>;
  final version = lock['version'] as String? ?? '';
  final archiveUrl = lock['archive_url'] as String? ?? '';
  final expectedSha256 = lock['sha256'] as String?;
  if (version.isEmpty || archiveUrl.isEmpty) {
    stderr.writeln('bootstrap_deps: lock file must have version and archive_url');
    exit(1);
  }
  if (expectedSha256 == null || expectedSha256.isEmpty) {
    stderr.writeln('bootstrap_deps: lock file `${lockFile.path}` missing required `sha256` field. '
        'Compute via `shasum -a 256 <archive>` and commit.');
    exit(1);
  }

  // 2) Vendor SDK
  final sdkDir = Directory('$repoRoot/third_party/tencent_cloud_chat_sdk');
  final stateFile = File('$repoRoot/tool/vendor_state.json');
  final currentState = _readVendorState(stateFile);

  // Compute current patches digest up front: if patches changed since last apply,
  // we must re-vendor (patches mutate the SDK in-place — no clean "un-apply").
  final patchesDir = Directory('${tim2toxDir.path}/patches/tencent_cloud_chat_sdk/$version');
  final seriesFile = File('${patchesDir.path}/series');
  List<String> patchNames = const [];
  String? patchesSha256;
  if (tim2toxDir.existsSync() && seriesFile.existsSync()) {
    patchNames = seriesFile.readAsLinesSync()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('#'))
        .toList();
    patchesSha256 = _computePatchesSha256(seriesFile, patchNames, patchesDir);
  }
  final storedPatchesSha256 = currentState['patches_sha256'];
  final patchesChanged = patchesSha256 != null &&
      storedPatchesSha256 != null &&
      storedPatchesSha256.isNotEmpty &&
      storedPatchesSha256 != patchesSha256;

  final needVendor = force ||
      !sdkDir.existsSync() ||
      currentState['version'] != version ||
      currentState['sha256'] != expectedSha256 ||
      patchesChanged;

  // Hold off writing stateFile until both vendor and patch-apply have succeeded —
  // a half-written state lets `--offline-check-only` falsely pass an un-patched SDK
  // (see doc/reviews/2026-05-20-batch-6-findings.md F1/F2).
  String? vendoredSha256;
  if (needVendor) {
    // Invalidate any prior state immediately so a crash mid-vendor cannot leave
    // offline-check matching the previous successful run against the new SDK.
    if (stateFile.existsSync()) {
      try {
        stateFile.deleteSync();
      } catch (_) {}
    }
    if (sdkDir.existsSync()) sdkDir.deleteSync(recursive: true);
    sdkDir.createSync(recursive: true);
    final tempDir = Directory.systemTemp.createTempSync('toxee_sdk_');
    try {
      final archivePath = '${tempDir.path}/sdk.tar.gz';
      stdout.writeln('Downloading tencent_cloud_chat_sdk $version...');
      await _download(archiveUrl, archivePath);
      final actualSha256 = await _sha256File(archivePath);
      if (actualSha256 != expectedSha256) {
        stderr.writeln('bootstrap_deps: SHA-256 mismatch (got $actualSha256, expected $expectedSha256)');
        exit(1);
      }
      await _extractTarGz(archivePath, tempDir.path);
      // Pub tarball extracts to a single top-level dir (e.g. package/ or tencent_cloud_chat_sdk-8.7.7201/)
      final entries = tempDir.listSync().whereType<FileSystemEntity>().toList();
      if (entries.length == 1 && entries.first is Directory) {
        final inner = entries.first as Directory;
        for (final e in inner.listSync()) {
          final name = e.path.split(Platform.pathSeparator).last;
          final dest = File('${sdkDir.path}/$name');
          if (e is File) {
            e.copySync(dest.path);
          } else if (e is Directory) {
            Directory('${sdkDir.path}/$name').createSync(recursive: true);
            _copyDir(e, Directory('${sdkDir.path}/$name'));
          }
        }
      } else {
        // Flat list of files/dirs at top level
        for (final e in entries) {
          final name = e.path.split(Platform.pathSeparator).last;
          if (e is File) {
            e.copySync('${sdkDir.path}/$name');
          } else if (e is Directory) {
            final destSub = Directory('${sdkDir.path}/$name');
            destSub.createSync(recursive: true);
            _copyDir(e, destSub);
          }
        }
      }
      if (Platform.isWindows) {
        _normalizeSdkLineEndings(sdkDir);
      }
      vendoredSha256 = actualSha256;
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  }

  // 3) Apply SDK patch series via tim2tox tool (patches live in tim2tox repo: patches/tencent_cloud_chat_sdk/<version>/)
  // Carry forward prior state only if we didn't re-vendor; otherwise build a fresh map.
  final stateMap = (needVendor || !stateFile.existsSync())
      ? <String, dynamic>{}
      : (jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>);
  const appliedKey = 'patches_applied';
  const patchesShaKey = 'patches_sha256';
  if (needVendor) {
    stateMap['version'] = version;
    stateMap['sha256'] = vendoredSha256;
  }
  final bool shouldApplySdkPatches = (stateMap[appliedKey] != true ||
          (patchesSha256 != null && stateMap[patchesShaKey] != patchesSha256)) &&
      tim2toxDir.existsSync() &&
      seriesFile.existsSync();
  if (shouldApplySdkPatches) {
    if (patchNames.isNotEmpty) {
      stdout.writeln('Applying tencent_cloud_chat_sdk patches from tim2tox (${patchNames.length} patch(es))...');
      // Run tim2tox's apply_sdk_patches.dart directly (no "dart run") so it does not depend on package_config
      final scriptPath = File('${tim2toxDir.path}/tool/apply_sdk_patches.dart');
      if (!scriptPath.existsSync()) {
        stderr.writeln('bootstrap_deps: tim2tox tool/apply_sdk_patches.dart not found');
        exit(1);
      }
      final patchCode = await _run(repoRoot, 'dart', [scriptPath.path, '--sdk-dir=${sdkDir.path}'], workingDirectory: tim2toxDir.path);
      if (patchCode != 0) {
        // Mark state as partial so offline-check cannot mistake an un-patched SDK
        // for a clean ready-to-use install.
        _writeStateAtomic(stateFile, <String, dynamic>{
          if (stateMap['version'] != null) 'version': stateMap['version'],
          if (stateMap['sha256'] != null) 'sha256': stateMap['sha256'],
          'partial': true,
          'reason': 'apply_sdk_patches failed (exit $patchCode)',
        });
        stderr.writeln('bootstrap_deps: tim2tox apply_sdk_patches failed (exit $patchCode)');
        exit(patchCode);
      }
      stateMap[appliedKey] = true;
      if (patchesSha256 != null) {
        stateMap[patchesShaKey] = patchesSha256;
      }
    }
  }
  // Single authoritative state write after both vendor + patch succeed.
  if (needVendor || shouldApplySdkPatches) {
    stateMap.remove('partial');
    stateMap.remove('reason');
    _writeStateAtomic(stateFile, stateMap);
  }

  // 4) Generate pubspec_overrides.yaml so all local deps resolve under third_party/
  const uikitPackages = [
    'tencent_cloud_chat_common',
    'tencent_cloud_chat_message',
    'tencent_cloud_chat_conversation',
    'tencent_cloud_chat_contact',
    'tencent_cloud_chat_sticker',
    'tencent_cloud_chat_intl',
    'tencent_cloud_chat_text_translate',
    'tencent_cloud_chat_sound_to_text',
  ];
  final overrides = StringBuffer('# Generated by tool/bootstrap_deps.dart - do not edit.\n');
  overrides.writeln('dependency_overrides:');
  overrides.writeln('  tim2tox_dart:');
  overrides.writeln('    path: third_party/tim2tox/dart');
  overrides.writeln('  tencent_cloud_chat_sdk:');
  overrides.writeln('    path: third_party/tencent_cloud_chat_sdk');
  for (final p in uikitPackages) {
    overrides.writeln('  $p:');
    overrides.writeln('    path: third_party/chat-uikit-flutter/$p');
  }
  overrides.writeln('  record_linux: ^1.2.1');
  // integration_test (from the Flutter SDK) pins `file: 7.0.1`, while the
  // path-pinned tencent_cloud_chat_intl still asks for `^6.1.2`. The two
  // versions are API-compatible for the surfaces those packages use; pin
  // the override here so `flutter pub get` resolves cleanly when the
  // integration_test dev dependency is in pubspec.yaml.
  overrides.writeln('  file: ^7.0.1');
  // Only rewrite when content differs, so we don't bump the mtime on no-op runs
  // (Flutter build scripts gate `flutter pub get` on pubspec_overrides.yaml freshness).
  final overridesFile = File('$repoRoot/pubspec_overrides.yaml');
  final newOverrides = overrides.toString();
  if (!overridesFile.existsSync() ||
      overridesFile.readAsStringSync() != newOverrides) {
    overridesFile.writeAsStringSync(newOverrides);
  }

  stdout.writeln('Bootstrap complete.');
}

void _writeStateAtomic(File stateFile, Map<String, dynamic> contents) {
  final tmp = File('${stateFile.path}.tmp');
  tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(contents));
  // Atomic on POSIX; on Windows, File.rename overwrites silently (which is what we want).
  tmp.renameSync(stateFile.path);
}

int _offlineCheck(String repoRoot) {
  final lockFile = File('$repoRoot/third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json');
  if (!lockFile.existsSync()) {
    stderr.writeln('bootstrap_deps: offline-check: lock file missing');
    return 1;
  }
  final sdkDir = Directory('$repoRoot/third_party/tencent_cloud_chat_sdk');
  final tim2tox = Directory('$repoRoot/third_party/tim2tox');
  final uikit = Directory('$repoRoot/third_party/chat-uikit-flutter');
  if (!tim2tox.existsSync() || !uikit.existsSync()) {
    stderr.writeln('bootstrap_deps: offline-check: submodule directory missing');
    return 1;
  }
  if (!sdkDir.existsSync()) {
    stderr.writeln('bootstrap_deps: offline-check: third_party/tencent_cloud_chat_sdk missing');
    return 1;
  }
  // Verify vendor_state.json matches the lock's version + sha256.
  final stateFile = File('$repoRoot/tool/vendor_state.json');
  if (!stateFile.existsSync()) {
    stderr.writeln('bootstrap_deps: offline-check: tool/vendor_state.json missing');
    return 1;
  }
  Map<String, dynamic> lock;
  Map<String, dynamic> state;
  try {
    lock = jsonDecode(lockFile.readAsStringSync()) as Map<String, dynamic>;
    state = jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('bootstrap_deps: offline-check: failed to parse lock/state json: $e');
    return 1;
  }
  final lockVersion = lock['version']?.toString() ?? '';
  final lockSha = lock['sha256']?.toString() ?? '';
  if (lockVersion.isEmpty || lockSha.isEmpty) {
    stderr.writeln('bootstrap_deps: offline-check: lock file missing version or sha256');
    return 1;
  }
  if (state['version']?.toString() != lockVersion) {
    stderr.writeln('bootstrap_deps: offline-check: vendor_state version mismatch '
        '(state=${state['version']}, lock=$lockVersion)');
    return 1;
  }
  if (state['sha256']?.toString() != lockSha) {
    stderr.writeln('bootstrap_deps: offline-check: vendor_state sha256 does not match lock');
    return 1;
  }
  if (state['partial'] == true) {
    stderr.writeln('bootstrap_deps: offline-check: vendor_state is marked partial '
        '(${state['reason'] ?? "unknown"}); re-run `dart tool/bootstrap_deps.dart --force`.');
    return 1;
  }
  // Patches series sanity: if a series file exists, the lock must record patches_sha256
  // and it must match current content. Empty/missing patches_sha256 with a present
  // series file means a previous bootstrap predates patches sha tracking — treat as
  // integrity-suspect rather than silently passing.
  final patchesDir = Directory('${tim2tox.path}/patches/tencent_cloud_chat_sdk/$lockVersion');
  final seriesFile = File('${patchesDir.path}/series');
  final storedPatchesSha = state['patches_sha256']?.toString() ?? '';
  if (seriesFile.existsSync()) {
    final names = seriesFile.readAsLinesSync()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('#'))
        .toList();
    if (names.isNotEmpty) {
      if (storedPatchesSha.isEmpty) {
        stderr.writeln('bootstrap_deps: offline-check: vendor_state.patches_sha256 missing '
            'but patches series exists with ${names.length} patch(es); re-run '
            '`dart tool/bootstrap_deps.dart` to record the digest.');
        return 1;
      }
      final computed = _computePatchesSha256(seriesFile, names, patchesDir);
      if (computed != storedPatchesSha) {
        stderr.writeln('bootstrap_deps: offline-check: patches_sha256 in vendor_state does not match '
            'current patches content (re-run `dart tool/bootstrap_deps.dart`)');
        return 1;
      }
    }
  }
  return 0;
}

Map<String, String> _readVendorState(File f) {
  if (!f.existsSync()) return {};
  try {
    final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return {
      'version': m['version']?.toString() ?? '',
      'sha256': m['sha256']?.toString() ?? '',
      'patches_sha256': m['patches_sha256']?.toString() ?? '',
    };
  } catch (_) {
    return {};
  }
}

String _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/tool/bootstrap_deps.dart').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('bootstrap_deps: run from toxee repo root');
      exit(1);
    }
    dir = parent;
  }
}

Future<int> _run(String cwd, String executable, List<String> args, {String? workingDirectory}) async {
  final wd = workingDirectory ?? cwd;
  final r = await Process.run(executable, args, workingDirectory: wd, runInShell: false);
  if (r.stdout.toString().trim().isNotEmpty) stdout.write(r.stdout);
  if (r.stderr.toString().trim().isNotEmpty) stderr.write(r.stderr);
  return r.exitCode;
}

Future<void> _download(String url, String destPath) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final file = File(destPath).openWrite();
    await resp.pipe(file);
    await file.close();
  } finally {
    client.close();
  }
}

Future<String> _sha256File(String path) async {
  if (Platform.isWindows) {
    final r = await Process.run(
      'certutil',
      ['-hashfile', path, 'SHA256'],
      runInShell: false,
    );
    if (r.exitCode != 0) {
      throw Exception('certutil failed: ${r.stderr}');
    }
    final lines = (r.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => RegExp(r'^[A-Fa-f0-9 ]+$').hasMatch(line) && line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw Exception('certutil output did not contain a SHA-256 hash');
    }
    return lines.first.replaceAll(' ', '').toLowerCase();
  }

  try {
    final r = await Process.run('sha256sum', [path], runInShell: false);
    if (r.exitCode == 0) {
      return (r.stdout as String).split(' ').first.trim();
    }
  } on ProcessException {
    // Fall through to shasum on platforms like macOS where sha256sum is absent.
  }

  final r = await Process.run('shasum', ['-a', '256', path], runInShell: false);
  if (r.exitCode != 0) {
    throw Exception('sha256 tool failed: ${r.stderr}');
  }
  return (r.stdout as String).split(' ').first.trim();
}

String _computePatchesSha256(File seriesFile, List<String> patchNames, Directory patchesDir) {
  final tempFile = File('${Directory.systemTemp.createTempSync('toxee_patches_').path}/concat.bin');
  try {
    final sink = tempFile.openSync(mode: FileMode.write);
    try {
      sink.writeFromSync(seriesFile.readAsBytesSync());
      for (final name in patchNames) {
        final f = File('${patchesDir.path}/$name');
        if (f.existsSync()) {
          sink.writeFromSync(f.readAsBytesSync());
        }
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

String _sha256FileSync(String path) {
  if (Platform.isWindows) {
    final r = Process.runSync('certutil', ['-hashfile', path, 'SHA256'], runInShell: false);
    if (r.exitCode != 0) {
      throw Exception('certutil failed: ${r.stderr}');
    }
    final lines = (r.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => RegExp(r'^[A-Fa-f0-9 ]+$').hasMatch(line) && line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw Exception('certutil output did not contain a SHA-256 hash');
    }
    return lines.first.replaceAll(' ', '').toLowerCase();
  }
  try {
    final r = Process.runSync('sha256sum', [path], runInShell: false);
    if (r.exitCode == 0) {
      return (r.stdout as String).split(' ').first.trim();
    }
  } on ProcessException {
    // Fall through to shasum on platforms like macOS where sha256sum is absent.
  }
  final r = Process.runSync('shasum', ['-a', '256', path], runInShell: false);
  if (r.exitCode != 0) {
    throw Exception('sha256 tool failed: ${r.stderr}');
  }
  return (r.stdout as String).split(' ').first.trim();
}

Future<void> _extractTarGz(String archivePath, String destDir) async {
  final code = await Process.run('tar', ['-xzf', archivePath, '-C', destDir], runInShell: false).then((r) => r.exitCode);
  if (code != 0) throw Exception('tar extract failed');
}

void _copyDir(Directory src, Directory dest) {
  for (final e in src.listSync()) {
    final name = e.path.split(Platform.pathSeparator).last;
    final destPath = '${dest.path}/$name';
    if (e is File) {
      File(destPath).parent.createSync(recursive: true);
      e.copySync(destPath);
    } else if (e is Directory) {
      Directory(destPath).createSync(recursive: true);
      _copyDir(e, Directory(destPath));
    }
  }
}

void _normalizeSdkLineEndings(Directory sdkDir) {
  const textExtensions = {
    '.dart',
    '.yaml',
    '.yml',
    '.json',
    '.xml',
    '.gradle',
    '.kts',
    '.java',
    '.kt',
    '.m',
    '.mm',
    '.swift',
    '.h',
    '.hpp',
    '.c',
    '.cc',
    '.cpp',
    '.txt',
    '.md',
  };

  for (final entity in sdkDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final lowerPath = entity.path.toLowerCase();
    if (!textExtensions.any(lowerPath.endsWith)) continue;

    final contents = entity.readAsStringSync();
    final normalized = contents.replaceAll('\r\n', '\n');
    if (contents != normalized) {
      entity.writeAsStringSync(normalized);
    }
  }
}
