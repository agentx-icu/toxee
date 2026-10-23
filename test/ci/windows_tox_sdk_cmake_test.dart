import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final policy = '$root/windows/cmake/tox_sdk.cmake';
  const reviewedSources = [
    'CMakeLists.txt',
    'tencent_cloud_chat_sdk_plugin.cpp',
    'tencent_cloud_chat_sdk_plugin.h',
    'tencent_cloud_chat_sdk_plugin_c_api.cpp',
    'include/tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_plugin_c_api.h',
  ];
  const vendorFiles = [
    'ImSDK.dll',
    'dart_native_imsdk.dll',
    'ImSDK.lib',
    'dart_native_imsdk.lib',
  ];
  late Directory fixture;

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('toxee Tox Windows SDK ');
    final sdk = Directory('${fixture.path}/vendor SDK');
    await Directory('${sdk.path}/lib').create(recursive: true);
    for (final source in reviewedSources) {
      final destination = File('${sdk.path}/$source');
      await destination.parent.create(recursive: true);
      await File(
        '$root/third_party/tencent_cloud_chat_sdk/windows/$source',
      ).copy(destination.path);
    }
    for (final name in vendorFiles.where((name) => name.endsWith('.dll'))) {
      await File('${sdk.path}/lib/$name').writeAsString('x64 vendor fixture');
    }
    for (final name in vendorFiles.where((name) => name.endsWith('.lib'))) {
      await File('${sdk.path}/lib/$name').writeAsString('unused vendor import');
    }
    await File('${sdk.path}/lib/keep.dat').writeAsString('unrelated SDK asset');
    await File(
      '${fixture.path}/unrelated.cpp',
    ).writeAsString('int unrelated() { return 0; }');
    // Compile the actual vendored plugin with only the Flutter/Windows header
    // surface it needs. No vendor import library is usable in this fixture.
    final headers = Directory('${fixture.path}/headers/flutter');
    await headers.create(recursive: true);
    await File('${fixture.path}/headers/compat.h').writeAsString(r'''
#ifndef _MSC_VER
#define __declspec(value) __attribute__((visibility("default")))
#endif
''');
    await File(
      '${fixture.path}/headers/flutter_plugin_registrar.h',
    ).writeAsString('typedef void* FlutterDesktopPluginRegistrarRef;');
    await File('${headers.path}/method_channel.h').writeAsString(r'''
#pragma once
namespace flutter {
class EncodableValue {};
template <typename T> class MethodCall {};
template <typename T> class MethodResult {};
}
''');
    await File('${headers.path}/plugin_registrar_windows.h').writeAsString(r'''
#pragma once
namespace flutter {
class Plugin { public: virtual ~Plugin() = default; };
class PluginRegistrarWindows {};
class PluginRegistrarManager {
 public:
  static PluginRegistrarManager* GetInstance() {
    static PluginRegistrarManager manager;
    return &manager;
  }
  template <typename T> T* GetRegistrar(void*) { return nullptr; }
};
}
''');
    for (final header in [
      'VersionHelpers.h',
      'flutter/standard_method_codec.h',
    ]) {
      await File('${fixture.path}/headers/$header').writeAsString('');
    }
  });

  tearDown(() async => fixture.delete(recursive: true));

  Future<ProcessResult> configure({
    String architecture = 'arm64',
    bool dependency = true,
    bool target = true,
    bool changedBundle = false,
  }) async {
    await File('${fixture.path}/CMakeLists.txt').writeAsString('''
cmake_minimum_required(VERSION 3.14)
project(tox_sdk_fixture LANGUAGES CXX)
set(FLUTTER_PLUGIN_LIST ${dependency ? 'tencent_cloud_chat_sdk' : ''})
function(apply_standard_settings target)
  target_compile_features(\${target} PUBLIC cxx_std_17)
endfunction()
include_directories("\${CMAKE_CURRENT_SOURCE_DIR}/headers")
if(MSVC)
  add_compile_options("/FI\${CMAKE_CURRENT_SOURCE_DIR}/headers/compat.h")
else()
  add_compile_options(-include "\${CMAKE_CURRENT_SOURCE_DIR}/headers/compat.h")
endif()
add_library(flutter INTERFACE)
add_library(flutter_wrapper_plugin INTERFACE)
add_library(unrelated_plugin SHARED unrelated.cpp)
${target ? 'add_subdirectory("vendor SDK")' : ''}
set(PLUGIN_BUNDLED_LIBRARIES
  \$<TARGET_FILE:unrelated_plugin>
  ${target ? '\$<TARGET_FILE:tencent_cloud_chat_sdk_plugin> \${tencent_cloud_chat_sdk_bundled_libraries}' : ''})
${changedBundle ? 'set(tencent_cloud_chat_sdk_bundled_libraries "unexpected")' : ''}
# The host fixture does not cross-compile; exercise the same policy for both
# Windows generator-platform inputs after configuring the native host compiler.
set(CMAKE_GENERATOR_PLATFORM "$architecture")
if(EXISTS "$policy")
  include("$policy")
endif()
${target ? 'file(GENERATE OUTPUT "\${CMAKE_BINARY_DIR}/sdk-links.txt" CONTENT "\$<TARGET_PROPERTY:tencent_cloud_chat_sdk_plugin,LINK_LIBRARIES>")' : ''}
install(FILES "\${PLUGIN_BUNDLED_LIBRARIES}" DESTINATION ".")
''');
    return Process.run('cmake', [
      '-S',
      fixture.path,
      '-B',
      '${fixture.path}/build',
    ]);
  }

  void expectSuccess(ProcessResult result) =>
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

  for (final architecture in ['x64', 'arm64']) {
    test(
      '$architecture builds and installs Tox SDK without vendor runtime',
      () async {
        expectSuccess(await configure(architecture: architecture));
        final links = await File(
          '${fixture.path}/build/sdk-links.txt',
        ).readAsString();
        expect(links, isNot(contains('ImSDK.lib')));
        expect(links, contains('flutter;flutter_wrapper_plugin'));
        expectSuccess(
          await Process.run('cmake', ['--build', '${fixture.path}/build']),
        );
        final installed = Directory('${fixture.path}/installed bundle');
        await installed.create();
        // Reconfiguration must also clean exactly these stale vendor files from
        // an existing install, while preserving unrelated files and plugins.
        for (final name in [...vendorFiles, 'keep-existing.dat']) {
          await File('${installed.path}/$name').writeAsString('stale fixture');
        }
        expectSuccess(
          await Process.run('cmake', [
            '--install',
            '${fixture.path}/build',
            '--prefix',
            installed.path,
          ]),
        );
        final names = installed
            .listSync()
            .map((file) => file.uri.pathSegments.last)
            .toSet();
        for (final vendor in vendorFiles) {
          expect(names, isNot(contains(vendor)));
        }
        expect(names, containsAll(['keep.dat', 'keep-existing.dat']));
        expect(
          names.any((name) => name.contains('tencent_cloud_chat_sdk_plugin')),
          isTrue,
        );
        expect(names.any((name) => name.contains('unrelated_plugin')), isTrue);
        final plugin = installed.listSync().singleWhere(
          (file) => file.uri.pathSegments.last.contains(
            'tencent_cloud_chat_sdk_plugin',
          ),
        );
        final library = DynamicLibrary.open(plugin.path);
        try {
          final register = library
              .lookupFunction<
                Void Function(Pointer<Void>),
                void Function(Pointer<Void>)
              >('TencentCloudChatSdkPluginCApiRegisterWithRegistrar');
          register(nullptr);
        } finally {
          library.close();
        }
      },
    );
  }

  test(
    'changed native plugin requires review before dropping vendor runtime',
    () async {
      await File(
        '${fixture.path}/vendor SDK/tencent_cloud_chat_sdk_plugin.cpp',
      ).writeAsString('void register_plugin() { LoadLibraryW(L"ImSDK.dll"); }');
      final result = await configure();
      expect(result.exitCode, isNot(0));
      expect(
        '${result.stdout}\n${result.stderr}'.replaceAll(RegExp(r'\s+'), ' '),
        contains('Re-review the Tox-only SDK policy'),
      );
    },
  );

  test('Windows CRLF checkout keeps the reviewed no-op plugin valid', () async {
    for (final source in reviewedSources) {
      final file = File('${fixture.path}/vendor SDK/$source');
      final contents = await file.readAsString();
      await file.writeAsString(contents.replaceAll('\n', '\r\n'));
    }
    expectSuccess(await configure());
  });

  test('changed SDK CMake requires review for newly added native code', () async {
    final cmake = File('${fixture.path}/vendor SDK/CMakeLists.txt');
    await cmake.writeAsString(
      '${await cmake.readAsString()}\n# A newly reviewed SDK build definition.\n',
    );
    final result = await configure();
    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}\n${result.stderr}'.replaceAll(RegExp(r'\s+'), ' '),
      contains('Re-review the Tox-only SDK policy'),
    );
  });

  test(
    'renamed native target fails instead of silently retaining vendor payload',
    () async {
      final result = await configure(target: false);
      expect(result.exitCode, isNot(0));
      expect(
        '${result.stdout}\n${result.stderr}',
        contains('tencent_cloud_chat_sdk_plugin'),
      );
    },
  );

  test('changed vendor bundle layout requires explicit review', () async {
    final result = await configure(changedBundle: true);
    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}\n${result.stderr}'.replaceAll(RegExp(r'\s+'), ' '),
      contains('Re-review the Tox-only SDK policy'),
    );
  });

  test(
    'removed SDK dependency leaves unrelated plugin install intact',
    () async {
      expectSuccess(await configure(dependency: false, target: false));
      expectSuccess(
        await Process.run('cmake', ['--build', '${fixture.path}/build']),
      );
      expectSuccess(
        await Process.run('cmake', [
          '--install',
          '${fixture.path}/build',
          '--prefix',
          '${fixture.path}/installed',
        ]),
      );
      expect(Directory('${fixture.path}/installed').listSync(), hasLength(1));
    },
  );
}
