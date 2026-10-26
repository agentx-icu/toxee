import 'dart:typed_data';

import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

/// The C ABI's closed status set. An unrecognised value is uncertain ownership.
enum NativeLogStatus {
  ok,
  truncated,
  invalid,
  unsafePath,
  ioNoOwner,
  notOwner,
  partialReleased,
  busy,
  uncertain;

  static NativeLogStatus fromCode(int code) =>
      code >= 0 && code < values.length ? values[code] : uncertain;
}

typedef NativeLogClaim = ({NativeLogStatus status, int generation});

/// Synchronous because native writes and Dart writes must have one order.
abstract interface class NativeLogBridge {
  NativeLogClaim configure(String absolutePath);
  NativeLogStatus append(int generation, Uint8List record);
  NativeLogStatus release(int generation);
}

final class Tim2ToxLogBridge implements NativeLogBridge {
  Tim2ToxLogBridge(this._ffi);

  final Tim2ToxFfi _ffi;

  @override
  NativeLogClaim configure(String absolutePath) {
    final result = _ffi.configureLogOwned(absolutePath);
    return (
      status: NativeLogStatus.fromCode(result.status),
      generation: result.generation,
    );
  }

  @override
  NativeLogStatus append(int generation, Uint8List record) =>
      NativeLogStatus.fromCode(_ffi.appendLogOwned(generation, record));

  @override
  NativeLogStatus release(int generation) =>
      NativeLogStatus.fromCode(_ffi.releaseLogOwned(generation));
}
