import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter/foundation.dart' show visibleForTesting;

// `open(2)` is variadic (the mode argument): the native signature carries
// an empty `VarArgs` marker so the call follows the variadic ABI (Apple
// arm64 passes variadic arguments differently). No mode is passed.
typedef _OpenNative =
    ffi.Int32 Function(
      ffi.Pointer<pkgffi.Utf8>,
      ffi.Int32,
      ffi.VarArgs<()>,
    );
typedef _Open = int Function(ffi.Pointer<pkgffi.Utf8>, int);
typedef _FdNative = ffi.Int32 Function(ffi.Int32);
typedef _Fd = int Function(int);

/// Durability of a rename: `fsync(2)` on the directory that holds the
/// renamed entry, which makes it much less likely that a power loss rolls the
/// directory back to the old file. Not a guarantee: failures are ignored,
/// Windows is not flushed, and on macOS `fsync` may leave data in the drive
/// cache (`F_FULLFSYNC` is not used). Dart has no API for it, so this
/// calls libc through FFI on macOS, Linux, iOS and Android (ported from
/// DitMesh), and does nothing on
/// Windows (NTFS journals the rename itself; there is no directory handle
/// to flush through the C runtime).
///
/// Synchronous: it blocks the calling isolate for one directory flush,
/// which is short next to the file flush that precedes every caller's
/// rename.
abstract final class PosixDirectorySync {
  /// `O_RDONLY` is 0 on every supported POSIX platform.
  static const int _readOnly = 0;

  static final ({_Open open, _Fd fsync, _Fd close})? _libc = _lookup();

  static ({_Open open, _Fd fsync, _Fd close})? _lookup() {
    if (Platform.isWindows) return null;
    try {
      final lib = ffi.DynamicLibrary.process();
      return (
        open: lib.lookupFunction<_OpenNative, _Open>('open'),
        fsync: lib.lookupFunction<_FdNative, _Fd>('fsync'),
        close: lib.lookupFunction<_FdNative, _Fd>('close'),
      );
    } on Object {
      return null;
    }
  }

  /// True when POSIX is available (not Windows).
  static bool get supported => _libc != null;

  /// Flushes the directory [path]. Best effort, never throws: false when it
  /// cannot be opened or flushed (some filesystems refuse `fsync` on a
  /// directory) and on Windows. Callers have already committed their
  /// rename; a false answer only means its durability is the OS default.
  static bool sync(String path) {
    final libc = _libc;
    if (libc == null) return false;
    final native = path.toNativeUtf8();
    try {
      final fd = libc.open(native, _readOnly);
      if (fd < 0) return false;
      try {
        return libc.fsync(fd) == 0;
      } finally {
        libc.close(fd);
      }
    } on Object {
      return false;
    } finally {
      pkgffi.malloc.free(native);
    }
  }
}

/// The directory flush the atomic writers run after their rename; a test
/// seam (a failing flush must leave the committed write in place).
@visibleForTesting
bool Function(String path) directorySync = PosixDirectorySync.sync;

/// Flushes [target]'s directory after a rename. Never throws: the rename
/// has committed, and only its durability is at stake.
void syncParentDirectory(File target) {
  try {
    directorySync(target.parent.path);
  } on Object {
    // Durability is best effort once the rename committed.
  }
}
