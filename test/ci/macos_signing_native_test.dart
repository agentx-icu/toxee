import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Run on macOS with Xcode command-line tools. SDKROOT may select a specific SDK
// for this command without changing xcode-select or the host configuration.
void main() {
  for (final architecture in ['x86_64', 'arm64']) {
    for (final frameworkExecutableKey in [true, false]) {
      test(
        'signs unsigned $architecture nested code (framework executable key: $frameworkExecutableKey)',
        () async {
          final fixture = await Directory.systemTemp.createTemp(
            'toxee native signing ',
          );
          addTearDown(() => fixture.delete(recursive: true));
          final ci = await Directory(
            '${fixture.path}/tool/ci',
          ).create(recursive: true);
          await File(
            'tool/ci/sign_macos_bundle.sh',
          ).copy('${ci.path}/sign_macos_bundle.sh');
          final runner = await Directory(
            '${fixture.path}/macos/Runner',
          ).create(recursive: true);
          await File(
            'macos/Runner/Release.entitlements',
          ).copy('${runner.path}/Release.entitlements');
          final source = await File(
            '${fixture.path}/fixture.c',
          ).writeAsString('int main(void) { return 0; }\n');
          final app = '${fixture.path}/Fixture App.app';
          await _plist('$app/Contents/Info.plist', executable: 'Main');
          // Create the main executable first: signing it directly makes
          // codesign inspect the whole enclosing bundle, including unsigned
          // siblings that the original file-order loop had not reached.
          await _compile(source, '$app/Contents/MacOS/Main', architecture);
          final library = '$app/Contents/MacOS/libfixture.dylib';
          await _compile(source, library, architecture, library: true);
          final framework = '$app/Contents/Frameworks/Nested.framework';
          await _plist(
            '$framework/Versions/A/Resources/Info.plist',
            executable: frameworkExecutableKey ? 'Nested' : null,
            framework: true,
          );
          await _compile(
            source,
            '$framework/Versions/A/Nested',
            architecture,
            library: true,
          );
          await _compile(
            source,
            '$framework/Versions/A/Libraries/libnested.dylib',
            architecture,
            library: true,
          );
          await Link('$framework/Versions/Current').create('A');
          await Link(
            '$framework/Resources',
          ).create('Versions/Current/Resources');
          await Link('$framework/Nested').create('Versions/Current/Nested');
          final helper = '$app/Contents/Helpers/Helper.app';
          await _plist('$helper/Contents/Info.plist', executable: 'Helper');
          await _compile(source, '$helper/Contents/MacOS/Helper', architecture);
          await _compile(
            source,
            '$helper/Contents/MacOS/libhelper.dylib',
            architecture,
            library: true,
          );
          final looseTool = '$app/Contents/Helpers/loose-tool';
          await _compile(source, looseTool, architecture);
          // arm64 links normally acquire an ad-hoc signature automatically.
          // Remove it so both architectures exercise genuinely unsigned code.
          for (final entity in Directory(
            '$app/Contents',
          ).listSync(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            final kind = await Process.run('file', ['-b', entity.path]);
            if ('${kind.stdout}'.contains('Mach-O')) {
              await _run('codesign', ['--remove-signature', entity.path]);
            }
          }
          final unsigned = await Process.run('codesign', ['--verify', library]);
          expect(
            unsigned.exitCode,
            isNot(0),
            reason: 'fixture must start unsigned',
          );
          await _run('bash', ['${ci.path}/sign_macos_bundle.sh', app]);
          await _run('codesign', ['--verify', '--deep', '--strict', app]);
          await _run('codesign', ['--verify', '--strict', library]);
          await _run('codesign', ['--verify', '--strict', looseTool]);
        },
        skip: !Platform.isMacOS,
      );
    }
  }
}

Future<void> _compile(
  File source,
  String output,
  String architecture, {
  bool library = false,
}) async {
  await File(output).parent.create(recursive: true);
  await _run('xcrun', [
    'clang',
    '-arch',
    architecture,
    if (library) '-dynamiclib',
    source.path,
    '-o',
    output,
  ]);
}

Future<void> _plist(
  String path, {
  required String? executable,
  bool framework = false,
}) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.toxee.signing-fixture</string>
<key>CFBundleName</key><string>Fixture</string>
<key>CFBundleVersion</key><string>1.0</string>
<key>CFBundlePackageType</key><string>${framework ? 'FMWK' : 'APPL'}</string>
${executable == null ? '' : '<key>CFBundleExecutable</key><string>$executable</string>'}
</dict></plist>
''');
}

Future<void> _run(String command, List<String> arguments) async {
  final result = await Process.run(command, arguments);
  expect(
    result.exitCode,
    0,
    reason: '$command $arguments\n${result.stdout}\n${result.stderr}',
  );
}
