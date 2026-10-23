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

  String git(List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: source.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout as String;
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
    git([
      '-c',
      'user.name=Overlay fixture',
      '-c',
      'user.email=fixture@invalid',
      '-c',
      'commit.gpgsign=false',
      'commit',
      '-qm',
      'pinned sources',
    ]);
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
