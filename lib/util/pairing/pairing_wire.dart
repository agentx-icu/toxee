import 'dart:async';
import 'dart:typed_data';

/// Wire framing for the pairing TCP socket.
///
/// The protocol is deliberately tiny — one (length, payload) frame at a time,
/// big-endian uint32 length prefix — because the handshake transfers only
/// three messages:
///
///   1. Client → Host: 32-byte X25519 public key.
///   2. Host  → Client: AEAD-encrypted `.tox` blob.
///   3. Either side closes the socket (clean EOF).
///
/// We use length-prefixed frames so the host can stream the AEAD blob in
/// chunks if it ever exceeds a single TCP write, and so the receiver doesn't
/// have to guess at "is this the whole message yet" based on socket idle.
class PairingFrame {
  PairingFrame._();

  /// Max payload size we'll accept on a single frame. Anything bigger than a
  /// few MB is suspicious for an identity transfer and we'd rather fail loud
  /// than tie up memory.
  static const int maxPayloadBytes = 16 * 1024 * 1024;

  /// Encode a single frame: 4-byte big-endian length, then payload.
  static Uint8List encode(Uint8List payload) {
    if (payload.length > maxPayloadBytes) {
      throw ArgumentError(
          'Pairing frame payload exceeds max ($maxPayloadBytes bytes)');
    }
    final out = Uint8List(4 + payload.length);
    final view = ByteData.view(out.buffer);
    view.setUint32(0, payload.length, Endian.big);
    out.setRange(4, 4 + payload.length, payload);
    return out;
  }
}

/// Streaming length-prefixed frame reader. Feed it raw socket bytes via
/// [feed]; it emits one [Uint8List] per complete frame on its stream.
///
/// Closing the underlying socket should be followed by [close] so any
/// trailing partial frame raises a clean error rather than hanging.
class PairingFrameReader {
  PairingFrameReader();

  final _builder = BytesBuilder(copy: false);
  final _controller = StreamController<Uint8List>();
  bool _closed = false;

  Stream<Uint8List> get frames => _controller.stream;

  void feed(List<int> chunk) {
    if (_closed) return;
    _builder.add(chunk);
    while (true) {
      final buf = _builder.toBytes();
      if (buf.length < 4) {
        // Not enough for a length header yet.
        _builder.clear();
        _builder.add(buf);
        return;
      }
      final view = ByteData.view(buf.buffer, buf.offsetInBytes, buf.length);
      final len = view.getUint32(0, Endian.big);
      if (len > PairingFrame.maxPayloadBytes) {
        _controller.addError(FormatException(
            'Pairing frame oversized: $len bytes (max '
            '${PairingFrame.maxPayloadBytes})'));
        _closed = true;
        unawaited(_controller.close());
        return;
      }
      if (buf.length < 4 + len) {
        // Wait for more bytes.
        _builder.clear();
        _builder.add(buf);
        return;
      }
      final payload = Uint8List(len)..setRange(0, len, buf, 4);
      _controller.add(payload);
      final remaining = buf.sublist(4 + len);
      _builder.clear();
      if (remaining.isNotEmpty) {
        _builder.add(remaining);
      } else {
        return;
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final remaining = _builder.toBytes();
    if (remaining.isNotEmpty) {
      _controller.addError(const FormatException(
          'Pairing connection closed mid-frame'));
    }
    await _controller.close();
  }
}
