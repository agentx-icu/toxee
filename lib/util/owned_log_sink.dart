import 'dart:convert';
import 'dart:typed_data';

import 'native_log_bridge.dart';

/// Ownership applies to the whole file family, including the native writers.
/// A fallback is bounded memory, never another writer to an uncertain path.
final class OwnedLogSink {
  static const maximumRecordBytes = 64 * 1024;
  static const maximumPendingRecords = 32;
  static const lossNotice = 'origin=logger record_lost=1 replay=omitted\n';

  NativeLogBridge? _bridge;
  int _generation = 0;
  bool _owned = false;
  bool _closed = false;
  bool _claimRefused = false;
  final _pending = <Uint8List>[];
  int _dropped = 0;

  bool get ownsFile => _owned;

  void begin() {
    if (_closed && !_confirmRelease()) {
      throw StateError('Native log closure could not be confirmed');
    }
    _closed = false;
  }

  /// Returns false when no owner could be established. No pending data is
  /// replayed until configure explicitly grants a fresh nonzero generation.
  bool handoff(NativeLogBridge bridge, String absolutePath) {
    if (_owned && !_closed) return identical(_bridge, bridge);
    if (_bridge != null && !_confirmRelease()) return false;
    _bridge = bridge;
    _closed = false;
    NativeLogClaim claim;
    try {
      claim = bridge.configure(absolutePath);
    } catch (_) {
      _confirmRelease();
      return false;
    }
    if (claim.status != NativeLogStatus.ok || claim.generation == 0) {
      // A failed configure cannot grant ownership. Even IO_NO_OWNER is not a
      // licence for Dart to bypass native path/link validation with file IO.
      _generation = 0;
      _claimRefused = switch (claim.status) {
        NativeLogStatus.invalid ||
        NativeLogStatus.unsafePath ||
        NativeLogStatus.notOwner ||
        NativeLogStatus.busy => true,
        _ => _claimRefused,
      };
      if (claim.status == NativeLogStatus.partialReleased) _noticeLoss();
      if (claim.status == NativeLogStatus.uncertain ||
          claim.status == NativeLogStatus.ok) {
        _confirmRelease();
      }
      return false;
    }
    _generation = claim.generation;
    _claimRefused = false;
    _owned = true;
    if (_dropped != 0) {
      final dropped = _dropped;
      _dropped = 0;
      append('origin=logger buffered_records_dropped=$dropped\n');
    }
    while (_owned && _pending.isNotEmpty) {
      // Remove before calling native. A partially committed record is never
      // replayed, including when an FFI call throws after entering native.
      _appendOwned(_pending.removeAt(0));
    }
    return _owned;
  }

  void append(String record) {
    if (_closed) return;
    final bytes = boundedRecord(record);
    if (_owned) {
      _appendOwned(bytes);
    } else {
      _buffer(bytes);
    }
  }

  void _buffer(Uint8List record) {
    if (_pending.length < maximumPendingRecords) {
      _pending.add(record);
    } else {
      _dropped++;
    }
  }

  void _appendOwned(Uint8List bytes) {
    NativeLogStatus result;
    try {
      result = _bridge!.append(_generation, bytes);
    } catch (_) {
      result = NativeLogStatus.uncertain;
    }
    if (result == NativeLogStatus.ok || result == NativeLogStatus.truncated) {
      return;
    }
    _owned = false;
    if (result == NativeLogStatus.partialReleased) {
      _generation = 0;
    } else if (result == NativeLogStatus.uncertain) {
      _confirmRelease();
    }
    // Record absence rather than repeat the possibly committed original.
    _noticeLoss();
  }

  void _noticeLoss() {
    if (_pending.length == maximumPendingRecords) {
      _pending.removeLast();
      _dropped++;
    }
    _pending.insert(0, Uint8List.fromList(utf8.encode(lossNotice)));
  }

  bool _confirmRelease() {
    final bridge = _bridge;
    if (bridge == null) return true;
    try {
      if (bridge.release(_generation) != NativeLogStatus.ok) return false;
      _owned = false;
      _generation = 0;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A caller deleting logs must stop if close cannot confirm the fd is gone.
  /// Failed closure retains the generation so the next attempt can confirm it.
  void close() {
    _closed = true;
    // A zero-generation query only describes this process. BUSY may represent
    // another process holding the family lock; it is never deletion consent.
    if (_claimRefused) {
      throw StateError('Native log ownership was refused; deletion is unsafe');
    }
    if (!_confirmRelease()) {
      throw StateError('Native log closure could not be confirmed');
    }
    _pending.clear();
    _dropped = 0;
  }

  /// Discards in-memory state after releasing only this process's fd.
  /// This deliberately grants no consent to delete a refused/foreign family.
  void discardMemory() {
    if (!_confirmRelease()) {
      throw StateError('Native log closure could not be confirmed');
    }
    _closed = true;
    _pending.clear();
    _dropped = 0;
  }

  /// The marker is part of the byte budget and the prefix ends between UTF-8
  /// code points. No fragment of a multibyte value reaches either sink.
  static Uint8List boundedRecord(String record) {
    final bytes = utf8.encode(record);
    if (bytes.length <= maximumRecordBytes) return bytes;
    var cut = maximumRecordBytes - 64;
    List<int> marker;
    while (true) {
      while (cut > 0 && (bytes[cut] & 0xc0) == 0x80) {
        cut--;
      }
      marker = utf8.encode('\n[logger omitted_bytes=${bytes.length - cut}]\n');
      final available = maximumRecordBytes - marker.length;
      if (cut <= available) break;
      cut = available;
    }
    return Uint8List.fromList([...bytes.take(cut), ...marker]);
  }
}
