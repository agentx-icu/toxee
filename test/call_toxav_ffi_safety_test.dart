// Verifies the FFI-safety invariant of `ToxAVService` receive trampolines:
// the audio/video buffers handed to user callbacks must be Dart-owned copies,
// fully decoupled from the c-toxcore-owned source pointers (which are recycled
// after the trampoline returns).
//
// Regression scope:
//   - Previously, `_onAudioReceiveNativeTrampoline` and
//     `_onVideoReceiveNativeTrampoline` passed `Pointer.asTypedList(...)`
//     views directly to consumers. If a consumer iterated the view
//     asynchronously (e.g. inside a `compute()` isolate, or after an `await`),
//     and c-toxcore recycled the buffer in the meantime, the consumer read
//     freed/overwritten memory.
//   - This test allocates a native buffer, runs the copy helper, mutates
//     the source pointer, and asserts the copy still reflects the original
//     contents.

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart' as ffi_lib;
import 'package:tim2tox_dart/service/toxav_service.dart';

typedef _AvCallCallbackNativeForTest =
    ffi.Void Function(ffi.Uint32, ffi.Int32, ffi.Int32, ffi.Pointer<ffi.Void>);
typedef _AvCallStateCallbackNativeForTest =
    ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.Void>);
typedef _AvAudioReceiveCallbackNativeForTest =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Pointer<ffi.Int16>,
      ffi.Size,
      ffi.Uint8,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );
typedef _AvVideoReceiveCallbackNativeForTest =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Uint16,
      ffi.Uint16,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Uint8>,
      ffi.Pointer<ffi.Void>,
    );
typedef _AvBitrateCallbackNativeForTest =
    ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.Void>);
typedef _AvConferenceAudioReceiveCallbackNativeForTest =
    ffi.Void Function(
      ffi.Pointer<pkgffi.Utf8>,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Pointer<ffi.Int16>,
      ffi.Size,
      ffi.Uint8,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );

void main() {
  group('ToxAVService FFI safety — copyAudioForCallback', () {
    test('mono: copies sampleCount samples, decoupled from source pointer', () {
      const sampleCount = 960; // 20 ms @ 48 kHz
      final ptr = pkgffi.malloc<ffi.Int16>(sampleCount);
      try {
        for (var i = 0; i < sampleCount; i++) {
          ptr[i] = (i * 7) & 0x7FFF;
        }

        final copy = ToxAVService.copyAudioForCallback(ptr, sampleCount, 1);
        expect(copy.length, sampleCount);
        expect(copy[0], 0);
        expect(copy[1], 7);
        expect(copy[100], (700) & 0x7FFF);

        // Mutate source pointer; the copy must remain intact.
        for (var i = 0; i < sampleCount; i++) {
          ptr[i] = 0;
        }
        expect(copy[0], 0); // coincidence
        expect(copy[1], 7); // proves copy is decoupled
        expect(copy[100], (700) & 0x7FFF);
      } finally {
        pkgffi.malloc.free(ptr);
      }
    });

    test('stereo: copies sampleCount * channels (interleaved L/R)', () {
      const sampleCount = 480; // per-channel
      const channels = 2;
      const total = sampleCount * channels;
      final ptr = pkgffi.malloc<ffi.Int16>(total);
      try {
        // Distinguishable L/R pattern: L = +i, R = -i
        for (var i = 0; i < sampleCount; i++) {
          ptr[i * 2] = i;
          ptr[i * 2 + 1] = -i;
        }

        final copy = ToxAVService.copyAudioForCallback(
          ptr,
          sampleCount,
          channels,
        );
        expect(
          copy.length,
          total,
          reason:
              'sampleCount is per-channel; total samples = sampleCount * channels '
              '(matches libtoxav toxav_audio_receive_frame_cb contract)',
        );
        expect(copy[0], 0);
        expect(copy[1], 0);
        expect(copy[2], 1);
        expect(copy[3], -1);
        expect(copy[total - 2], sampleCount - 1);
        expect(copy[total - 1], -(sampleCount - 1));
      } finally {
        pkgffi.malloc.free(ptr);
      }
    });

    test('channels <= 0 defensively treated as mono (defends against 0)', () {
      const sampleCount = 16;
      final ptr = pkgffi.malloc<ffi.Int16>(sampleCount);
      try {
        for (var i = 0; i < sampleCount; i++) {
          ptr[i] = i + 1;
        }
        final copy = ToxAVService.copyAudioForCallback(ptr, sampleCount, 0);
        expect(copy.length, sampleCount);
        expect(copy.last, sampleCount);
      } finally {
        pkgffi.malloc.free(ptr);
      }
    });
  });

  group('ToxAVService FFI safety — copyVideoForCallback', () {
    test('I420 planes: y is w*h, u/v are (w/2)*(h/2), all decoupled', () {
      const width = 64;
      const height = 48;
      const ySize = width * height;
      const uvSize = (width ~/ 2) * (height ~/ 2);

      final yPtr = pkgffi.malloc<ffi.Uint8>(ySize);
      final uPtr = pkgffi.malloc<ffi.Uint8>(uvSize);
      final vPtr = pkgffi.malloc<ffi.Uint8>(uvSize);
      try {
        for (var i = 0; i < ySize; i++) {
          yPtr[i] = (i & 0xFF);
        }
        for (var i = 0; i < uvSize; i++) {
          uPtr[i] = (i & 0xFF) ^ 0x55;
          vPtr[i] = (i & 0xFF) ^ 0xAA;
        }

        final (yCopy, uCopy, vCopy) = ToxAVService.copyVideoForCallback(
          width,
          height,
          yPtr,
          uPtr,
          vPtr,
        );

        expect(yCopy, isA<Uint8List>());
        expect(yCopy.length, ySize);
        expect(uCopy.length, uvSize);
        expect(vCopy.length, uvSize);

        // Spot-check content against the deterministic pattern above.
        expect(yCopy[0], 0);
        expect(yCopy[1], 1);
        expect(yCopy[ySize - 1], (ySize - 1) & 0xFF);
        expect(uCopy[0], 0x55);
        expect(vCopy[0], 0xAA);
        expect(uCopy[uvSize - 1], ((uvSize - 1) & 0xFF) ^ 0x55);
        expect(vCopy[uvSize - 1], ((uvSize - 1) & 0xFF) ^ 0xAA);

        // Zero out the source pointers; copies must be unaffected.
        for (var i = 0; i < ySize; i++) {
          yPtr[i] = 0;
        }
        for (var i = 0; i < uvSize; i++) {
          uPtr[i] = 0;
          vPtr[i] = 0;
        }
        expect(yCopy[1], 1);
        expect(uCopy[0], 0x55);
        expect(vCopy[0], 0xAA);
      } finally {
        pkgffi.malloc.free(yPtr);
        pkgffi.malloc.free(uPtr);
        pkgffi.malloc.free(vPtr);
      }
    });
  });

  group('ToxAVService outbound validation', () {
    test('sendAudioFrame rejects undersized PCM before native', () async {
      final ffi = _RecordingToxAvFfi();
      final service = await _initializedService(ffi);

      final result = await service.sendAudioFrame(
        7,
        List<int>.filled(960 * 2 - 1, 1),
        960,
        2,
        48000,
      );

      expect(
        ffi.audioFrameCalls,
        isEmpty,
        reason: 'invalid PCM length must be rejected before native FFI',
      );
      expect(result, isFalse);
    });

    test('sendAudioFrame rejects unsupported channels before native', () async {
      final ffi = _RecordingToxAvFfi();
      final service = await _initializedService(ffi);

      final result = await service.sendAudioFrame(
        7,
        List<int>.filled(960 * 3, 1),
        960,
        3,
        48000,
      );

      expect(
        ffi.audioFrameCalls,
        isEmpty,
        reason: 'channels must be limited to the toxav-supported set',
      );
      expect(result, isFalse);
    });

    test(
      'sendAudioFrame rejects unsupported sampling rate before native',
      () async {
        final ffi = _RecordingToxAvFfi();
        final service = await _initializedService(ffi);

        final result = await service.sendAudioFrame(
          7,
          List<int>.filled(441 * 2, 1),
          441,
          2,
          44100,
        );

        expect(
          ffi.audioFrameCalls,
          isEmpty,
          reason: 'sampling rate must be limited to the toxav-supported set',
        );
        expect(result, isFalse);
      },
    );

    test(
      'sendAudioFrame rejects invalid frame duration before native',
      () async {
        final ffi = _RecordingToxAvFfi();
        final service = await _initializedService(ffi);

        final result = await service.sendAudioFrame(
          7,
          List<int>.filled(961, 1),
          961,
          1,
          48000,
        );

        expect(
          ffi.audioFrameCalls,
          isEmpty,
          reason: 'sampleCount must describe a toxav-supported frame duration',
        );
        expect(result, isFalse);
      },
    );

    test(
      'sendAudioFrame rejects overflow-sized sample counts before native',
      () async {
        final ffi = _RecordingToxAvFfi();
        final service = await _initializedService(ffi);

        final result = await service.sendAudioFrame(
          7,
          const <int>[1, 2],
          1 << 62,
          2,
          48000,
        );

        expect(
          ffi.audioFrameCalls,
          isEmpty,
          reason: 'sampleCount * channels must be checked without overflow',
        );
        expect(result, isFalse);
      },
    );

    test(
      'sendVideoFrame accepts odd 641x479 I420 with floor chroma sizing',
      () async {
        final ffi = _RecordingToxAvFfi();
        final service = await _initializedService(ffi);
        const width = 641;
        const height = 479;
        const chromaWidth = width ~/ 2;
        const chromaHeight = height ~/ 2;

        final result = await service.sendVideoFrame(
          7,
          width,
          height,
          _bytes(width * height),
          _bytes(chromaWidth * chromaHeight),
          _bytes(chromaWidth * chromaHeight),
        );

        expect(result, isTrue);
        expect(ffi.videoFrameCalls, hasLength(1));
        expect(
          ffi.videoFrameCalls.single,
          const _VideoFrameCall(
            friendNumber: 7,
            width: width,
            height: height,
            yStride: width,
            uStride: chromaWidth,
            vStride: chromaWidth,
          ),
        );
      },
    );

    test('sendVideoFrame accepts max uint16 width edge', () async {
      final ffi = _RecordingToxAvFfi();
      final service = await _initializedService(ffi);
      const width = 65535;
      const height = 1;

      final result = await service.sendVideoFrame(
        7,
        width,
        height,
        _bytes(width * height),
        const <int>[],
        const <int>[],
      );

      expect(result, isTrue);
      expect(ffi.videoFrameCalls, hasLength(1));
      expect(
        ffi.videoFrameCalls.single,
        const _VideoFrameCall(
          friendNumber: 7,
          width: width,
          height: height,
          yStride: width,
          uStride: width ~/ 2,
          vStride: width ~/ 2,
        ),
      );
    });

    test('sendVideoFrame accepts max uint16 height edge', () async {
      final ffi = _RecordingToxAvFfi();
      final service = await _initializedService(ffi);
      const width = 1;
      const height = 65535;

      final result = await service.sendVideoFrame(
        7,
        width,
        height,
        _bytes(width * height),
        const <int>[],
        const <int>[],
      );

      expect(result, isTrue);
      expect(ffi.videoFrameCalls, hasLength(1));
      expect(
        ffi.videoFrameCalls.single,
        const _VideoFrameCall(
          friendNumber: 7,
          width: width,
          height: height,
          yStride: width,
          uStride: 1,
          vStride: 1,
        ),
      );
    });

    test('sendVideoFrame accepts max int32 yStride edge', () async {
      final ffi = _RecordingToxAvFfi();
      final service = await _initializedService(ffi);
      const yStride = 0x7fffffff;

      final result = await service.sendVideoFrame(
        7,
        1,
        1,
        _bytes(1),
        const <int>[],
        const <int>[],
        yStride: yStride,
      );

      expect(result, isTrue);
      expect(ffi.videoFrameCalls, hasLength(1));
      expect(
        ffi.videoFrameCalls.single,
        const _VideoFrameCall(
          friendNumber: 7,
          width: 1,
          height: 1,
          yStride: yStride,
          uStride: 1,
          vStride: 1,
        ),
      );
    });

    test('sendVideoFrame rejects width beyond uint16 before native', () async {
      final ffi = _RecordingToxAvFfi();
      final service = await _initializedService(ffi);
      const width = 65536;
      const height = 1;

      final result = await service.sendVideoFrame(
        7,
        width,
        height,
        _bytes(width * height),
        const <int>[],
        const <int>[],
      );

      expect(
        ffi.videoFrameCalls,
        isEmpty,
        reason: 'width must fit the C uint16_t argument before native FFI',
      );
      expect(result, isFalse);
    });

    test('sendVideoFrame rejects height beyond uint16 before native', () async {
      final ffi = _RecordingToxAvFfi();
      final service = await _initializedService(ffi);
      const width = 1;
      const height = 65536;

      final result = await service.sendVideoFrame(
        7,
        width,
        height,
        _bytes(width * height),
        const <int>[],
        const <int>[],
      );

      expect(
        ffi.videoFrameCalls,
        isEmpty,
        reason: 'height must fit the C uint16_t argument before native FFI',
      );
      expect(result, isFalse);
    });

    test('sendVideoFrame rejects yStride beyond int32 before native', () async {
      final ffi = _RecordingToxAvFfi();
      final service = await _initializedService(ffi);

      final result = await service.sendVideoFrame(
        7,
        1,
        1,
        _bytes(1),
        const <int>[],
        const <int>[],
        yStride: 0x80000000,
      );

      expect(
        ffi.videoFrameCalls,
        isEmpty,
        reason: 'yStride must fit the C int32_t argument before native FFI',
      );
      expect(result, isFalse);
    });

    test(
      'sendVideoFrame rejects one-byte-short U plane before native',
      () async {
        final ffi = _RecordingToxAvFfi();
        final service = await _initializedService(ffi);
        const width = 640;
        const height = 480;
        const uvSize = (width ~/ 2) * (height ~/ 2);

        final result = await service.sendVideoFrame(
          7,
          width,
          height,
          _bytes(width * height),
          _bytes(uvSize - 1),
          _bytes(uvSize),
        );

        expect(
          ffi.videoFrameCalls,
          isEmpty,
          reason: 'undersized U plane must be rejected before native FFI',
        );
        expect(result, isFalse);
      },
    );

    test(
      'sendVideoFrame rejects one-byte-short V plane before native',
      () async {
        final ffi = _RecordingToxAvFfi();
        final service = await _initializedService(ffi);
        const width = 640;
        const height = 480;
        const uvSize = (width ~/ 2) * (height ~/ 2);

        final result = await service.sendVideoFrame(
          7,
          width,
          height,
          _bytes(width * height),
          _bytes(uvSize),
          _bytes(uvSize - 1),
        );

        expect(
          ffi.videoFrameCalls,
          isEmpty,
          reason: 'undersized V plane must be rejected before native FFI',
        );
        expect(result, isFalse);
      },
    );

    test(
      'sendVideoFrame rejects insufficient strided last row before native',
      () async {
        final ffi = _RecordingToxAvFfi();
        final service = await _initializedService(ffi);
        const width = 4;
        const height = 4;
        const yStride = 6;
        const requiredYSpan = yStride * (height - 1) + width;

        final result = await service.sendVideoFrame(
          7,
          width,
          height,
          _bytes(requiredYSpan - 1),
          _bytes((width ~/ 2) * (height ~/ 2)),
          _bytes((width ~/ 2) * (height ~/ 2)),
          yStride: yStride,
        );

        expect(
          ffi.videoFrameCalls,
          isEmpty,
          reason: 'plane length must cover the full strided last-row span',
        );
        expect(result, isFalse);
      },
    );
  });
}

Future<ToxAVService> _initializedService(_RecordingToxAvFfi ffi) async {
  final service = ToxAVService(ffi);
  addTearDown(service.shutdown);
  expect(await service.initialize(), isTrue);
  return service;
}

List<int> _bytes(int length) =>
    List<int>.generate(length, (index) => index & 0xFF, growable: false);

final class _RecordingToxAvFfi implements ffi_lib.Tim2ToxFfi {
  final audioFrameCalls = <_AudioFrameCall>[];
  final videoFrameCalls = <_VideoFrameCall>[];
  final callbackSetterCalls = <String>[];

  @override
  int Function() get getCurrentInstanceId =>
      () => 123;

  @override
  int Function(int) get avInitialize =>
      (_) => 1;

  @override
  void Function(int) get avShutdown => (_) {};

  @override
  bool get avIsAvailable => true;

  @override
  int Function(int, int, ffi.Pointer<ffi.Int16>, int, int, int)
  get avSendAudioFrameNative =>
      (instanceId, friendNumber, pcm, sampleCount, channels, samplingRate) {
        audioFrameCalls.add(
          _AudioFrameCall(
            friendNumber: friendNumber,
            sampleCount: sampleCount,
            channels: channels,
            samplingRate: samplingRate,
          ),
        );
        return 1;
      };

  @override
  int Function(
    int,
    int,
    int,
    int,
    ffi.Pointer<ffi.Uint8>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Pointer<ffi.Uint8>,
    int,
    int,
    int,
  )
  get avSendVideoFrameNative =>
      (
        instanceId,
        friendNumber,
        width,
        height,
        y,
        u,
        v,
        yStride,
        uStride,
        vStride,
      ) {
        videoFrameCalls.add(
          _VideoFrameCall(
            friendNumber: friendNumber,
            width: width,
            height: height,
            yStride: yStride,
            uStride: uStride,
            vStride: vStride,
          ),
        );
        return 1;
      };

  @override
  void Function(
    int,
    ffi.Pointer<ffi.NativeFunction<_AvCallCallbackNativeForTest>>,
    ffi.Pointer<ffi.Void>,
  )
  get avSetCallCallbackNative => (_, __, ___) {
    callbackSetterCalls.add('call');
  };

  @override
  void Function(
    int,
    ffi.Pointer<ffi.NativeFunction<_AvCallStateCallbackNativeForTest>>,
    ffi.Pointer<ffi.Void>,
  )
  get avSetCallStateCallbackNative => (_, __, ___) {
    callbackSetterCalls.add('call_state');
  };

  @override
  void Function(
    int,
    ffi.Pointer<ffi.NativeFunction<_AvAudioReceiveCallbackNativeForTest>>,
    ffi.Pointer<ffi.Void>,
  )
  get avSetAudioReceiveCallbackNative => (_, __, ___) {
    callbackSetterCalls.add('audio_receive');
  };

  @override
  void Function(
    int,
    ffi.Pointer<ffi.NativeFunction<_AvVideoReceiveCallbackNativeForTest>>,
    ffi.Pointer<ffi.Void>,
  )
  get avSetVideoReceiveCallbackNative => (_, __, ___) {
    callbackSetterCalls.add('video_receive');
  };

  @override
  void Function(
    int,
    ffi.Pointer<ffi.NativeFunction<_AvBitrateCallbackNativeForTest>>,
    ffi.Pointer<ffi.Void>,
  )
  get avSetAudioBitrateCallbackNative => (_, __, ___) {
    callbackSetterCalls.add('audio_bitrate');
  };

  @override
  void Function(
    int,
    ffi.Pointer<ffi.NativeFunction<_AvBitrateCallbackNativeForTest>>,
    ffi.Pointer<ffi.Void>,
  )
  get avSetVideoBitrateCallbackNative => (_, __, ___) {
    callbackSetterCalls.add('video_bitrate');
  };

  @override
  void Function(
    int,
    ffi.Pointer<
      ffi.NativeFunction<_AvConferenceAudioReceiveCallbackNativeForTest>
    >,
    ffi.Pointer<ffi.Void>,
  )
  get avConferenceSetAudioReceiveCallbackNative => (_, __, ___) {
    callbackSetterCalls.add('conference_audio_receive');
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _AudioFrameCall {
  const _AudioFrameCall({
    required this.friendNumber,
    required this.sampleCount,
    required this.channels,
    required this.samplingRate,
  });

  final int friendNumber;
  final int sampleCount;
  final int channels;
  final int samplingRate;
}

final class _VideoFrameCall {
  const _VideoFrameCall({
    required this.friendNumber,
    required this.width,
    required this.height,
    required this.yStride,
    required this.uStride,
    required this.vStride,
  });

  final int friendNumber;
  final int width;
  final int height;
  final int yStride;
  final int uStride;
  final int vStride;

  @override
  bool operator ==(Object other) {
    return other is _VideoFrameCall &&
        friendNumber == other.friendNumber &&
        width == other.width &&
        height == other.height &&
        yStride == other.yStride &&
        uStride == other.uStride &&
        vStride == other.vStride;
  }

  @override
  int get hashCode =>
      Object.hash(friendNumber, width, height, yStride, uStride, vStride);
}
