import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/native_log_bridge.dart';
import 'package:toxee/util/owned_log_sink.dart';

class ControlledBridge implements NativeLogBridge {
  NativeLogStatus configureStatus = NativeLogStatus.ok;
  NativeLogStatus appendStatus = NativeLogStatus.ok;
  NativeLogStatus releaseStatus = NativeLogStatus.ok;
  bool throwOnConfigure = false;
  bool throwOnAppend = false;
  int generation = 0;
  int configureCalls = 0;
  final released = <int>[];
  final attempted = <String>[];

  @override
  NativeLogClaim configure(String absolutePath) {
    configureCalls++;
    if (throwOnConfigure) throw StateError('synthetic configure failure');
    return (
      status: configureStatus,
      generation: configureStatus == NativeLogStatus.ok ? ++generation : 0,
    );
  }

  @override
  NativeLogStatus append(int generation, Uint8List record) {
    attempted.add(utf8.decode(record));
    if (throwOnAppend) throw StateError('synthetic unknown write outcome');
    return appendStatus;
  }

  @override
  NativeLogStatus release(int generation) {
    released.add(generation);
    return releaseStatus;
  }
}

void main() {
  test(
    'early fallback keeps 32 records and reports the exact dropped count',
    () {
      final sink = OwnedLogSink();
      final bridge = ControlledBridge();
      for (var i = 0; i < 41; i++) {
        sink.append('synthetic record $i\n');
      }
      expect(bridge.attempted, isEmpty);
      expect(sink.handoff(bridge, '/synthetic/app_1.log'), isTrue);
      expect(bridge.attempted.first, contains('buffered_records_dropped=9'));
      expect(bridge.attempted.skip(1), [
        for (var i = 0; i < 32; i++) 'synthetic record $i\n',
      ]);
      sink.close();
      expect(bridge.released, [1]);
    },
  );

  test('UTF-8 truncation includes its marker inside 64 KiB', () {
    final bytes = OwnedLogSink.boundedRecord('🙂' * 40000);
    expect(bytes.length, lessThanOrEqualTo(64 * 1024));
    final text = utf8.decode(bytes);
    expect(
      text,
      matches(
        RegExp(r'^🙂+\n\[logger omitted_bytes=[0-9]+\]\n$', unicode: true),
      ),
    );
    final omitted = int.parse(
      RegExp(r'omitted_bytes=([0-9]+)').firstMatch(text)!.group(1)!,
    );
    expect(utf8.encode(text.split('\n').first).length + omitted, 160000);
  });

  for (final status in [
    NativeLogStatus.invalid,
    NativeLogStatus.unsafePath,
    NativeLogStatus.notOwner,
    NativeLogStatus.busy,
  ]) {
    test('$status never bypasses native validation or steals an owner', () {
      final sink = OwnedLogSink();
      final bridge = ControlledBridge()
        ..configureStatus = status
        ..releaseStatus = NativeLogStatus.notOwner;
      expect(sink.handoff(bridge, '/synthetic/app_1.log'), isFalse);
      sink.append('buffer only');
      expect(bridge.attempted, isEmpty);
      expect(sink.handoff(bridge, '/synthetic/app_1.log'), isFalse);
      expect(bridge.configureCalls, 1);
      expect(bridge.released, [0]);
      expect(sink.close, throwsStateError);
      expect(bridge.released, [0]);
    });
  }

  test('BUSY from another process never grants deletion via a zero query', () {
    final sink = OwnedLogSink();
    final bridge = ControlledBridge()..configureStatus = NativeLogStatus.busy;
    expect(sink.handoff(bridge, '/synthetic/app_1.log'), isFalse);
    expect(bridge.release(0), NativeLogStatus.ok);
    expect(sink.close, throwsStateError);
    bridge.configureStatus = NativeLogStatus.ok;
    expect(sink.handoff(bridge, '/synthetic/app_1.log'), isTrue);
    expect(sink.close, returnsNormally);
  });

  test('IO_NO_OWNER only buffers until a new explicit claim succeeds', () {
    final sink = OwnedLogSink();
    final bridge = ControlledBridge()
      ..configureStatus = NativeLogStatus.ioNoOwner;
    expect(sink.handoff(bridge, '/synthetic/app_1.log'), isFalse);
    sink.append('retained only in memory');
    expect(bridge.attempted, isEmpty);
    bridge.configureStatus = NativeLogStatus.ok;
    expect(sink.handoff(bridge, '/synthetic/app_1.log'), isTrue);
    expect(bridge.attempted, ['retained only in memory']);
    sink.close();
  });

  test(
    'partial writes are not replayed and a fixed loss notice comes first',
    () {
      final sink = OwnedLogSink();
      final bridge = ControlledBridge();
      expect(sink.handoff(bridge, '/synthetic/app_1.log'), isTrue);
      bridge.appendStatus = NativeLogStatus.partialReleased;
      sink.append('uncertain original');
      sink.append('later record');
      expect(sink.ownsFile, isFalse);
      bridge.appendStatus = NativeLogStatus.ok;
      expect(sink.handoff(bridge, '/synthetic/app_1.log'), isTrue);
      expect(bridge.attempted, [
        'uncertain original',
        OwnedLogSink.lossNotice,
        'later record',
      ]);
      expect(bridge.released, [0]);
      sink.close();
    },
  );

  test(
    'an uncertain write blocks reconfiguration until release is confirmed',
    () {
      final sink = OwnedLogSink();
      final bridge = ControlledBridge();
      expect(sink.handoff(bridge, '/synthetic/app_1.log'), isTrue);
      bridge
        ..throwOnAppend = true
        ..releaseStatus = NativeLogStatus.uncertain;
      sink.append('possibly committed');
      sink.append('future buffered record');
      expect(sink.handoff(bridge, '/synthetic/app_1.log'), isFalse);
      expect(bridge.configureCalls, 1);
      expect(bridge.released, [1, 1]);
      expect(sink.close, throwsStateError);
      bridge
        ..throwOnAppend = false
        ..releaseStatus = NativeLogStatus.ok;
      expect(sink.handoff(bridge, '/synthetic/app_1.log'), isTrue);
      expect(bridge.attempted, [
        'possibly committed',
        OwnedLogSink.lossNotice,
        'future buffered record',
      ]);
      sink.close();
    },
  );

  test('configure exceptions use zero only to confirm no owner', () {
    final sink = OwnedLogSink();
    final bridge = ControlledBridge()
      ..throwOnConfigure = true
      ..releaseStatus = NativeLogStatus.notOwner;
    sink.append('early record');
    expect(sink.handoff(bridge, '/synthetic/app_1.log'), isFalse);
    expect(bridge.released, [0]);
    expect(bridge.attempted, isEmpty);
    expect(sink.close, throwsStateError);
  });

  test('close releases once, discards buffers, and prevents future writes', () {
    final sink = OwnedLogSink();
    final bridge = ControlledBridge();
    expect(sink.handoff(bridge, '/synthetic/app_1.log'), isTrue);
    sink.append('before close');
    sink.close();
    sink.append('after close');
    expect(bridge.attempted, ['before close']);
    expect(bridge.released, [1]);
    sink.close();
    expect(bridge.released, [1, 0]);
  });

  test('unrecognised ABI codes are uncertain rather than success', () {
    expect(NativeLogStatus.fromCode(-1), NativeLogStatus.uncertain);
    expect(NativeLogStatus.fromCode(9), NativeLogStatus.uncertain);
  });
}
