import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  late String compatibility;

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('toxee WinRT fixture ');
    final cmake = await File('windows/CMakeLists.txt').readAsString();
    final start = cmake.indexOf('# C++/WinRT vs. MSVC');
    final end = cmake.indexOf('# === Installation ===', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    compatibility = cmake.substring(start, end);
  });

  tearDown(() async => fixture.delete(recursive: true));

  Future<ProcessResult> configure({
    bool notifications = true,
    bool targetExists = true,
  }) async {
    await File('${fixture.path}/notification.cpp').writeAsString(r'''
#include <coroutine>
#if defined(_MSVC_LANG)
static_assert(_MSVC_LANG >= 202002L, "notifications require standard coroutines");
#else
static_assert(__cplusplus >= 202002L, "notifications require standard coroutines");
#endif
int notification_fixture() { return 0; }
''');
    await File('${fixture.path}/unrelated.cpp').writeAsString(r'''
#if defined(_MSVC_LANG)
static_assert(_MSVC_LANG == 201703L, "unrelated plugins must remain C++17");
#else
static_assert(__cplusplus == 201703L, "unrelated plugins must remain C++17");
#endif
int unrelated_fixture() { return 0; }
''');
    await File('${fixture.path}/CMakeLists.txt').writeAsString('''
cmake_minimum_required(VERSION 3.14)
project(notification_compatibility LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(FLUTTER_PLUGIN_LIST)
set(FLUTTER_FFI_PLUGIN_LIST ${notifications ? 'flutter_local_notifications_windows' : ''})
add_library(unrelated_plugin STATIC unrelated.cpp)
${targetExists ? 'add_library(flutter_local_notifications_windows STATIC notification.cpp)' : ''}
$compatibility
''');
    return Process.run('cmake', [
      '-S',
      fixture.path,
      '-B',
      '${fixture.path}/build',
    ]);
  }

  test(
    'notification FFI target builds with standard coroutines only',
    () async {
      final configured = await configure();
      expect(
        configured.exitCode,
        0,
        reason: '${configured.stdout}\n${configured.stderr}',
      );
      final built = await Process.run('cmake', [
        '--build',
        '${fixture.path}/build',
        '--config',
        'Release',
      ]);
      expect(built.exitCode, 0, reason: '${built.stdout}\n${built.stderr}');
    },
  );

  test(
    'notification target rename fails with an actionable configure error',
    () async {
      final configured = await configure(targetExists: false);
      expect(configured.exitCode, isNot(0));
      expect(
        '${configured.stdout}\n${configured.stderr}',
        contains('flutter_local_notifications_windows'),
      );
    },
  );

  test(
    'removed notification dependency does not require a notification target',
    () async {
      final configured = await configure(
        notifications: false,
        targetExists: false,
      );
      expect(
        configured.exitCode,
        0,
        reason: '${configured.stdout}\n${configured.stderr}',
      );
    },
  );

  test(
    'notification compatibility expires when its reviewed artifact changes',
    () async {
      final lock = await File('pubspec.lock').readAsString();
      final entry = RegExp(
        r'^  flutter_local_notifications_windows:\n([\s\S]*?)(?=^  \w+:|\z)',
        multiLine: true,
      ).firstMatch(lock)?.group(1);
      expect(entry, isNotNull);
      expect(
        entry,
        contains('version: "1.0.3"'),
        reason:
            'Re-read the new plugin CMake and remove this override if fixed.',
      );
      expect(entry, contains('source: hosted'));
      expect(entry, contains('url: "https://pub.dev"'));
      expect(
        entry,
        contains(
          '8d658f0d367c48bd420e7cf2d26655e2d1130147bca1eea917e576ca76668aaf',
        ),
      );
    },
  );
}
