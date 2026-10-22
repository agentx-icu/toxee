import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  late Directory tools;
  late Directory commands;
  late File transcript;

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('toxee macos packaging ');
    tools = await Directory('${fixture.path}/tool/ci').create(recursive: true);
    commands = await Directory('${fixture.path}/bin').create();
    transcript = File('${fixture.path}/commands.log');
    for (final name in [
      'package_artifacts.sh',
      'sign_macos_bundle.sh',
      'common.sh',
    ]) {
      final copy = await File('tool/ci/$name').copy('${tools.path}/$name');
      // Match a clean checkout of these mode-100644 Git entries. A local chmod
      // must never hide an accidental direct exec of the signing helper.
      final mode = await Process.run('chmod', ['644', copy.path]);
      expect(mode.exitCode, 0);
    }
    final app = await Directory(
      '${fixture.path}/build/macos/Build/Products/Release/toxee.app/Contents',
    ).create(recursive: true);
    await File('${app.path}/fixture.txt').writeAsString('fixture bundle');
    await _command(commands, 'codesign', r'''
printf 'codesign %s\n' "$*" >> "$FIXTURE_TRANSCRIPT"
exit "${FIXTURE_SIGN_EXIT:-0}"
''');
    await _command(commands, 'pkgbuild', r'''
printf 'pkgbuild %s\n' "$*" >> "$FIXTURE_TRANSCRIPT"
for output in "$@"; do :; done
touch "$output"
''');
  });
  tearDown(() async => fixture.delete(recursive: true));

  Future<ProcessResult> package({String signExit = '0'}) => Process.run(
    'bash',
    ['${tools.path}/package_artifacts.sh', '--target', 'macos'],
    environment: {
      'PATH': '${commands.path}:${Platform.environment['PATH']}',
      'TOXEE_PACKAGE_ARCH': 'arm64',
      'RELEASE_VERSION': '1.2.3',
      'TOXEE_REQUIRE_SIGNING': '0',
      'MACOS_DEVELOPER_ID_APPLICATION_CERT': '',
      'MACOS_DEVELOPER_ID_INSTALLER_CERT': '',
      'MACOS_NOTARYTOOL_PROFILE': '',
      'FIXTURE_TRANSCRIPT': transcript.path,
      'FIXTURE_SIGN_EXIT': signExit,
    },
  );

  test(
    'macOS packaging runs a non-executable signing helper before pkgbuild',
    () async {
      final result = await package();
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final calls = await transcript.readAsLines();
      expect(calls.first, startsWith('codesign --force --sign -'));
      expect(calls[1], startsWith('codesign --verify --deep --strict'));
      expect(calls.last, startsWith('pkgbuild '));
      expect(
        await File(
          '${fixture.path}/dist/macos/toxee-1.2.3-Darwin-arm64.pkg',
        ).exists(),
        isTrue,
      );
    },
    skip: Platform.isWindows,
  );

  test('macOS packaging stops when signing fails', () async {
    final result = await package(signExit: '42');
    expect(result.exitCode, 42, reason: '${result.stdout}\n${result.stderr}');
    expect(await transcript.readAsString(), isNot(contains('pkgbuild ')));
  }, skip: Platform.isWindows);
}

Future<void> _command(Directory directory, String name, String body) async {
  final file = await File(
    '${directory.path}/$name',
  ).writeAsString('#!/usr/bin/env bash\nset -euo pipefail\n$body');
  final result = await Process.run('chmod', ['755', file.path]);
  expect(result.exitCode, 0);
}
