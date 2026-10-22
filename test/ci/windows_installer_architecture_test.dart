import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('toxee MSI architecture ');
  });
  tearDown(() async => fixture.delete(recursive: true));

  Future<ProcessResult> configure(String architecture) => Process.run('cmake', [
    '-S',
    '${Directory.current.path}/tool/ci/windows-installer',
    '-B',
    '${fixture.path}/build',
    '-DTOXEE_INSTALLER_SOURCE_DIR=${fixture.path}',
    '-DTOXEE_PACKAGE_ARCH=$architecture',
  ]);

  for (final architecture in {'AMD64': 'x64', 'ARM64': 'arm64'}.entries) {
    test(
      '${architecture.key} generates matching WiX installer architecture',
      () async {
        final result = await configure(architecture.key);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final config = await File(
          '${fixture.path}/build/CPackConfig.cmake',
        ).readAsString();
        expect(
          config,
          contains('set(CPACK_WIX_ARCHITECTURE "${architecture.value}")'),
        );
        expect(config, contains('set(CPACK_WIX_SIZEOF_VOID_P "8")'));
      },
    );
  }

  test('an unsupported installer architecture fails configuration', () async {
    final result = await configure('unexpected');
    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}\n${result.stderr}',
      contains('Unsupported Windows package architecture'),
    );
  });
}
