// Native buffers for Tox profile crypto and parsing.
//
// Every buffer that holds profile bytes (plaintext savedata carries the Tox
// secret key), ciphertext or a passphrase is zero-filled before it is freed:
// `malloc.free` only returns the block to the allocator, so the bytes would
// otherwise sit in reusable heap (and in any core dump) until overwritten.
// The Dart-heap copies the callers keep are the GC's and cannot be wiped
// reliably.

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

/// Allocator for the buffers below; a test swaps in a recording one.
@visibleForTesting
ffi.Allocator nativeBufferAllocator = pkgffi.malloc;

/// The Tim2Tox binding the profile helpers call. Tests only replace it (a
/// fake binding); production never assigns it.
Tim2ToxFfi Function() profileCryptoFfi = Tim2ToxFfi.open;

/// [length] bytes (at least one) from [nativeBufferAllocator].
ffi.Pointer<ffi.Uint8> allocNativeBytes(int length) =>
    nativeBufferAllocator<ffi.Uint8>(length < 1 ? 1 : length);

/// Zeroes the first [length] bytes of [ptr], then frees it.
void wipeAndFreeNative(ffi.Pointer<ffi.Uint8> ptr, int length) {
  if (length > 0) ptr.asTypedList(length).fillRange(0, length, 0);
  nativeBufferAllocator.free(ptr);
}
