import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bootstrap_patch_integrity.dart';
import '../../tool/bootstrap_uikit_overlay.dart';

void main() {
  final appRoot = Directory.current;
  late Directory fixture;
  late Directory source;
  late File manifestFile;
  late Map<String, dynamic> manifest;
  late List<Map<String, dynamic>> entries;

  String git(List<String> args, {Directory? cwd}) {
    final result = Process.runSync(
      'git',
      args,
      workingDirectory: (cwd ?? source).path,
      environment: {'GIT_ALLOW_PROTOCOL': 'file'},
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
  }

  void commitFixture(String message, {Directory? cwd}) {
    git([
      '-c',
      'user.name=Overlay fixture',
      '-c',
      'user.email=fixture@invalid',
      '-c',
      'commit.gpgsign=false',
      'commit',
      '-qm',
      message,
    ], cwd: cwd);
  }

  File target(int index) => File('${source.path}/${entries[index]['path']}');
  void saveManifest() => manifestFile.writeAsStringSync(jsonEncode(manifest));
  String digest(File file) => computePatchesSha256(file, const [], file.parent);

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('toxee_uikit_overlay_test_');
    source = Directory('${fixture.path}/third_party/chat-uikit-flutter')
      ..createSync(recursive: true);
    final overlay = Directory('${fixture.path}/tool/uikit_overlays')
      ..createSync(recursive: true);
    manifestFile = File('${overlay.path}/manifest.json');
    manifest =
        jsonDecode(
              File(
                '${appRoot.path}/tool/uikit_overlays/manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    entries = (manifest['files'] as List).cast<Map<String, dynamic>>();
    for (final entry in entries) {
      // Always obtain the real pinned pre-overlay bytes, even after the app's
      // ignored dependency checkout has already had the overlay applied.
      final original = Process.runSync('git', [
        '-C',
        '${appRoot.path}/third_party/chat-uikit-flutter',
        'show',
        '${manifest['revision']}:${entry['path']}',
      ], stdoutEncoding: utf8);
      expect(original.exitCode, 0);
      final file = File('${source.path}/${entry['path']}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(original.stdout as String);
    }
    git(['init', '-q']);
    git(['config', 'core.autocrlf', 'false']);
    final hooks = Directory('${fixture.path}/empty-hooks')..createSync();
    git(['config', 'core.hooksPath', hooks.path]);
    git(['add', '.']);
    commitFixture('pinned sources');
    manifest['revision'] = git(['rev-parse', 'HEAD']).trim();
    saveManifest();
    File(
      '${appRoot.path}/tool/uikit_overlays/motion-and-paste.patch',
    ).copySync('${overlay.path}/motion-and-paste.patch');
  });
  tearDown(() => fixture.deleteSync(recursive: true));

  test('offline check refuses pristine files without changing their bytes', () {
    final before = target(0).readAsBytesSync();
    expect(
      () => ensureUIKitOverlay(fixture.path, checkOnly: true),
      throwsStateError,
    );
    expect(target(0).readAsBytesSync(), before);
  });

  test('real patch applies, verifies every output and is idempotent', () {
    ensureUIKitOverlay(fixture.path);
    final after = target(0).readAsBytesSync();
    for (var index = 0; index < entries.length; index++) {
      expect(digest(target(index)), entries[index]['after_sha256']);
    }
    ensureUIKitOverlay(fixture.path);
    ensureUIKitOverlay(fixture.path, checkOnly: true);
    expect(target(0).readAsBytesSync(), after);
  });

  void verifyPinnedBootstrap({required bool hasGitlink}) {
    final pinned = manifest['revision'] as String;
    git(['switch', '-C', 'v2']);
    final upstream = Directory('${fixture.path}/uikit-upstream.git');
    git(['clone', '--bare', '.', upstream.path]);
    final upstreamUrl = Uri.directory(upstream.path).toString();
    git(['remote', 'add', 'origin', upstreamUrl]);
    git(['init', '-q'], cwd: fixture);
    File('${fixture.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
    git(['add', 'pubspec.yaml'], cwd: fixture);
    if (hasGitlink) {
      git([
        'submodule',
        'add',
        '-b',
        'v2',
        upstreamUrl,
        'third_party/chat-uikit-flutter',
      ], cwd: fixture);
    }
    commitFixture('bootstrap fixture root', cwd: fixture);

    // A miniature native checkout with a valid overlay and pre-vendored SDK
    // lets the real bootstrap complete without external dependencies.
    final native = Directory('${fixture.path}/third_party/tim2tox');
    git(['clone', upstreamUrl, native.path], cwd: fixture);
    final nativeOverlay = Directory('${fixture.path}/tool/native_log_overlays')
      ..createSync();
    manifestFile.copySync('${nativeOverlay.path}/manifest.json');
    File(
      '${manifestFile.parent.path}/motion-and-paste.patch',
    ).copySync('${nativeOverlay.path}/bounded-logging.patch');
    File('${native.path}/tool/tencent_cloud_chat_sdk.lock.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': '0.0.0',
          'archive_url': 'https://example.invalid/unused.tar.gz',
          'sha256': 'fixture',
        }),
      );
    File(
      '${fixture.path}/tool/vendor_state.json',
    ).writeAsStringSync(jsonEncode({'version': '0.0.0', 'sha256': 'fixture'}));
    Directory(
      '${fixture.path}/third_party/tencent_cloud_chat_sdk',
    ).createSync();
    for (final script in [
      'bootstrap_deps.dart',
      'bootstrap_overrides.dart',
      'bootstrap_native_log_overlay.dart',
      'bootstrap_patch_integrity.dart',
      'bootstrap_uikit_overlay.dart',
    ]) {
      File(
        '${appRoot.path}/tool/$script',
      ).copySync('${fixture.path}/tool/$script');
    }

    File(
      '${source.path}/unrelated.txt',
    ).writeAsStringSync('new upstream commit\n');
    git(['add', 'unrelated.txt']);
    commitFixture('advance v2');
    git(['push', upstreamUrl, 'v2']);
    git(['checkout', '--detach', pinned]);
    if (!hasGitlink) source.renameSync('${fixture.path}/uikit-seed');

    final result = Process.runSync(
      'dart',
      ['tool/bootstrap_deps.dart'],
      workingDirectory: fixture.path,
      environment: {
        'GIT_ALLOW_PROTOCOL': 'file',
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'url.$upstreamUrl.insteadOf',
        'GIT_CONFIG_VALUE_0':
            'https://github.com/agentx-icu/chat-uikit-flutter.git',
      },
    );
    final output = '${result.stdout}\n${result.stderr}';
    expect(git(['rev-parse', 'HEAD']).trim(), pinned, reason: output);
    expect(result.exitCode, 0, reason: output);
    for (var index = 0; index < entries.length; index++) {
      expect(digest(target(index)), entries[index]['after_sha256']);
    }
  }

  test('bootstrap preserves the gitlink after upstream v2 advances', () {
    verifyPinnedBootstrap(hasGitlink: true);
  });

  test('a UIKit fallback clone checks out the overlay pin', () {
    verifyPinnedBootstrap(hasGitlink: false);
  });

  test('user source drift is rejected without overwriting either target', () {
    target(
      0,
    ).writeAsStringSync('${target(0).readAsStringSync()}\n// local edit\n');
    final before = [
      for (var i = 0; i < entries.length; i++) target(i).readAsBytesSync(),
    ];
    expect(() => ensureUIKitOverlay(fixture.path), throwsStateError);
    for (var i = 0; i < entries.length; i++) {
      expect(target(i).readAsBytesSync(), before[i]);
    }
  });

  test(
    'partial application is rejected without completing or resetting it',
    () {
      ensureUIKitOverlay(fixture.path);
      target(0).writeAsStringSync(git(['show', 'HEAD:${entries[0]['path']}']));
      final other = target(1).readAsBytesSync();
      expect(() => ensureUIKitOverlay(fixture.path), throwsStateError);
      expect(digest(target(0)), entries[0]['before_sha256']);
      expect(target(1).readAsBytesSync(), other);
    },
  );

  test('tampered patch cannot pass even for already applied sources', () {
    ensureUIKitOverlay(fixture.path);
    final patch = File(
      '${fixture.path}/tool/uikit_overlays/motion-and-paste.patch',
    );
    patch.writeAsStringSync('${patch.readAsStringSync()}\n# tampered\n');
    expect(
      () => ensureUIKitOverlay(fixture.path, checkOnly: true),
      throwsStateError,
    );
  });

  test('different upstream revision fails before modifying sources', () {
    manifest['revision'] = List.filled(40, '0').join();
    saveManifest();
    expect(() => ensureUIKitOverlay(fixture.path), throwsStateError);
    expect(digest(target(0)), entries[0]['before_sha256']);
  });

  test('a patch outside the declared inventory cannot be applied', () {
    final patch = File(
      '${fixture.path}/tool/uikit_overlays/motion-and-paste.patch',
    );
    patch.writeAsStringSync(
      '${patch.readAsStringSync()}'
      '--- /dev/null\n+++ b/uninventoried.txt\n@@ -0,0 +1 @@\n+unexpected\n',
    );
    manifest['patch_sha256'] = digest(patch);
    saveManifest();
    expect(() => ensureUIKitOverlay(fixture.path), throwsStateError);
    expect(File('${source.path}/uninventoried.txt').existsSync(), isFalse);
    expect(digest(target(0)), entries[0]['before_sha256']);
  });

  test('CRLF checkouts apply the same source-verified patch', () {
    for (var i = 0; i < entries.length; i++) {
      target(i).writeAsStringSync(
        target(i).readAsStringSync().replaceAll('\n', '\r\n'),
      );
    }
    ensureUIKitOverlay(fixture.path);
    ensureUIKitOverlay(fixture.path, checkOnly: true);
  });
}
