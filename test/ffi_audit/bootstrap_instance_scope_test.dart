import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart' as ffi_lib;

void main() {
  ffi_lib.Tim2ToxFfi? library;

  setUpAll(() {
    try {
      library = ffi_lib.Tim2ToxFfi.open();
    } on Object {
      library = null;
    }
  });

  test(
    'exact DHT ID query targets the requested handle, treats zero as default, and preserves the ambient current instance',
    () {
      final lib = library;
      if (lib == null) {
        markTestSkipped('tim2tox FFI library is not loadable');
        return;
      }

      final instances = _NativeInstances.create(lib, count: 2);
      try {
        final first = instances.handles[0];
        final second = instances.handles[1];

        expect(lib.setCurrentInstance(first), 1);
        final firstDhtId = _readAmbientDhtId(lib);
        expect(firstDhtId, hasLength(64));

        expect(lib.setCurrentInstance(second), 1);
        final secondDhtId = _readAmbientDhtId(lib);
        expect(secondDhtId, hasLength(64));
        expect(secondDhtId, isNot(firstDhtId));

        expect(lib.setCurrentInstance(0), 1);
        final defaultDhtId = _readAmbientDhtId(lib);
        expect(
          defaultDhtId,
          isNot(firstDhtId),
          reason: 'the untouched default must be distinct from the test handle',
        );

        expect(lib.setCurrentInstance(first), 1);
        expect(
          _readExactDhtId(lib, second),
          secondDhtId,
          reason: 'an exact nonzero query must read the requested instance',
        );
        expect(
          lib.getCurrentInstanceId(),
          first,
          reason:
              'an exact query must not replace the ambient current instance',
        );

        expect(
          _readExactDhtId(lib, 0),
          defaultDhtId,
          reason:
              'instance ID zero must mean the default instance, not ambient',
        );
        expect(
          lib.getCurrentInstanceId(),
          first,
          reason:
              'the default-instance query must also preserve ambient current',
        );
      } finally {
        instances.dispose();
      }
    },
  );

  test(
    'exact initialized-state query targets the requested instance and treats zero as the untouched default',
    () {
      final lib = library;
      if (lib == null) {
        markTestSkipped('tim2tox FFI library is not loadable');
        return;
      }

      final instances = _NativeInstances.create(lib, count: 2);
      try {
        final first = instances.handles[0];
        final second = instances.handles[1];
        expect(lib.setCurrentInstance(first), 1);

        expect(
          lib.isInstanceInitialized(second),
          1,
          reason: 'the requested initialized test instance must report true',
        );
        expect(
          lib.getCurrentInstanceId(),
          first,
          reason: 'an initialized-state query must preserve ambient current',
        );
        expect(
          lib.isInstanceInitialized(0),
          0,
          reason:
              'zero must inspect the untouched default, not ambient current',
        );
        expect(lib.getCurrentInstanceId(), first);
      } finally {
        instances.dispose();
      }
    },
  );

  test(
    'uninit marks only the actual current nonzero test instance as uninitialized',
    () {
      final lib = library;
      if (lib == null) {
        markTestSkipped('tim2tox FFI library is not loadable');
        return;
      }

      final instances = _NativeInstances.create(lib, count: 2);
      try {
        final current = instances.handles[0];
        final other = instances.handles[1];
        expect(lib.setCurrentInstance(current), 1);
        expect(lib.isInstanceInitialized(current), 1);
        expect(lib.isInstanceInitialized(other), 1);
        final defaultStateBefore = lib.isInstanceInitialized(0);

        lib.uninit();

        expect(
          lib.isInstanceInitialized(current),
          0,
          reason: 'uninit must mark the manager it actually uninitialized',
        );
        expect(
          lib.isInstanceInitialized(other),
          1,
          reason: 'uninit must not alter a different disposable test instance',
        );
        expect(
          lib.isInstanceInitialized(0),
          defaultStateBefore,
          reason:
              'uninit of a nonzero test instance must not alter default state',
        );
        expect(
          lib.getCurrentInstanceId(),
          current,
          reason: 'uninit must not silently switch the ambient instance',
        );
      } finally {
        instances.dispose();
      }
    },
  );
}

String? _readAmbientDhtId(ffi_lib.Tim2ToxFfi lib) {
  final buffer = pkgffi.malloc.allocate<ffi.Int8>(65);
  try {
    final length = lib.getDhtIdNative(buffer, 65);
    if (length <= 0) {
      return null;
    }
    if (length > 64) {
      throw StateError('native DHT ID length exceeds its 64-byte contract');
    }
    return buffer.cast<pkgffi.Utf8>().toDartString(length: length);
  } finally {
    pkgffi.malloc.free(buffer);
  }
}

String? _readExactDhtId(ffi_lib.Tim2ToxFfi lib, int instanceId) {
  final buffer = pkgffi.malloc.allocate<ffi.Int8>(65);
  try {
    final length = lib.getDhtIdForInstanceNative(instanceId, buffer, 65);
    if (length <= 0) {
      return null;
    }
    if (length > 64) {
      throw StateError('native DHT ID length exceeds its 64-byte contract');
    }
    return buffer.cast<pkgffi.Utf8>().toDartString(length: length);
  } finally {
    pkgffi.malloc.free(buffer);
  }
}

class _NativeInstances {
  _NativeInstances._({
    required this.lib,
    required this.previousCurrent,
    required this.handles,
    required this.directories,
  });

  final ffi_lib.Tim2ToxFfi lib;
  final int previousCurrent;
  final List<int> handles;
  final List<Directory> directories;

  static _NativeInstances create(ffi_lib.Tim2ToxFfi lib, {required int count}) {
    final previousCurrent = lib.getCurrentInstanceId();
    final handles = <int>[];
    final directories = <Directory>[];

    try {
      for (var index = 0; index < count; index++) {
        final directory = Directory.systemTemp.createTempSync(
          'tim2tox_bootstrap_scope_',
        );
        directories.add(directory);
        final path = directory.path.toNativeUtf8();
        try {
          final handle = lib.createTestInstanceExNative(path, 0, 0);
          if (handle == 0) {
            throw StateError('failed to create native test instance $index');
          }
          handles.add(handle);
        } finally {
          pkgffi.malloc.free(path);
        }
      }
      return _NativeInstances._(
        lib: lib,
        previousCurrent: previousCurrent,
        handles: handles,
        directories: directories,
      );
    } on Object {
      _restoreAndDestroy(lib, previousCurrent, handles);
      _deleteDirectories(directories);
      rethrow;
    }
  }

  void dispose() {
    _restoreAndDestroy(lib, previousCurrent, handles);
    _deleteDirectories(directories);
  }
}

void _restoreAndDestroy(
  ffi_lib.Tim2ToxFfi lib,
  int previousCurrent,
  List<int> handles,
) {
  lib.setCurrentInstance(previousCurrent);
  for (final handle in handles.reversed) {
    lib.destroyTestInstance(handle);
  }
  lib.setCurrentInstance(previousCurrent);
}

void _deleteDirectories(List<Directory> directories) {
  for (final directory in directories.reversed) {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}
