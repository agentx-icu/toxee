import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/audio_handler.dart';
import 'package:toxee/call/call_video_transform.dart';
import 'package:toxee/call/call_media_capabilities.dart';
import 'package:toxee/call/video_handler.dart';
import 'package:camera/camera.dart';
import 'package:record/record.dart';

void main() {
  test('mobile capture prefers the front camera for the initial preview', () {
    const cameras = <CameraDescription>[
      CameraDescription(
        name: 'rear',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
      CameraDescription(
        name: 'selfie',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      ),
    ];

    expect(preferredInitialMobileCamera(cameras), cameras[1]);
  });

  test(
    'mobile capture falls back to the first camera when no front lens exists',
    () {
      const cameras = <CameraDescription>[
        CameraDescription(
          name: 'external',
          lensDirection: CameraLensDirection.external,
          sensorOrientation: 0,
        ),
        CameraDescription(
          name: 'rear',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
      ];

      expect(preferredInitialMobileCamera(cameras), cameras.first);
    },
  );

  test('camera switch prefers the opposite lens direction', () {
    const rearWide = CameraDescription(
      name: 'rear-wide',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    );
    const rearTele = CameraDescription(
      name: 'rear-tele',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    );
    const selfie = CameraDescription(
      name: 'selfie',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    );
    const cameras = [rearWide, rearTele, selfie];

    expect(nextMobileCamera(cameras, rearWide), selfie);
    expect(nextMobileCamera(cameras, selfie), rearWide);
  });

  test('camera switch uses deterministic next-device fallback', () {
    const first = CameraDescription(
      name: 'external-a',
      lensDirection: CameraLensDirection.external,
      sensorOrientation: 0,
    );
    const second = CameraDescription(
      name: 'external-b',
      lensDirection: CameraLensDirection.external,
      sensorOrientation: 0,
    );

    expect(nextMobileCamera(const [first, second], first), second);
    expect(nextMobileCamera(const [first, second], second), first);
  });

  test('a new call session re-applies the front-camera preference', () {
    const rear = CameraDescription(
      name: 'rear',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    );
    const selfie = CameraDescription(
      name: 'selfie',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    );
    const cameras = [rear, selfie];
    final selection = MobileCameraSelectionController();

    expect(selection.cameraForStart(cameras), selfie);
    selection.select(rear);
    expect(selection.cameraForStart(cameras), rear);

    selection.resetForNextCall();
    expect(selection.cameraForStart(cameras), selfie);
  });

  test('camera switch is exposed only by the mobile camera backend', () {
    expect(
      CallMediaCapabilities.supportsCameraSwitch(
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      CallMediaCapabilities.supportsCameraSwitch(platform: TargetPlatform.iOS),
      isTrue,
    );
    expect(
      CallMediaCapabilities.supportsCameraSwitch(
        platform: TargetPlatform.macOS,
      ),
      isFalse,
    );
  });

  test('uses explicit mono 48kHz PCM capture config for calls', () {
    final RecordConfig config = AudioHandler.buildCaptureConfig();

    expect(config.encoder, AudioEncoder.pcm16bits);
    expect(config.sampleRate, AudioHandler.sampleRate);
    expect(config.numChannels, AudioHandler.channels);
    expect(config.streamBufferSize, AudioHandler.bytesPerFrame);
    expect(config.echoCancel, isTrue);
    expect(config.noiseSuppress, isTrue);
  });

  test(
    'normalizes Android-style strided YUV420 planes into contiguous I420',
    () {
      final frame = VideoFrameNormalizer.normalizeYuv420(
        width: 4,
        height: 2,
        planes: const <VideoPlaneData>[
          VideoPlaneData(
            bytes: <int>[1, 2, 3, 4, 99, 98, 5, 6, 7, 8, 97, 96],
            bytesPerRow: 6,
            bytesPerPixel: 1,
          ),
          VideoPlaneData(
            bytes: <int>[10, 0, 20, 0],
            bytesPerRow: 4,
            bytesPerPixel: 2,
          ),
          VideoPlaneData(
            bytes: <int>[30, 0, 40, 0],
            bytesPerRow: 4,
            bytesPerPixel: 2,
          ),
        ],
      );

      expect(frame.y, Uint8List.fromList(const <int>[1, 2, 3, 4, 5, 6, 7, 8]));
      expect(frame.u, Uint8List.fromList(const <int>[10, 20]));
      expect(frame.v, Uint8List.fromList(const <int>[30, 40]));
    },
  );

  test('normalizes iOS bi-planar YUV420 into contiguous I420', () {
    final frame = VideoFrameNormalizer.normalizeYuv420(
      width: 4,
      height: 2,
      planes: const <VideoPlaneData>[
        VideoPlaneData(
          bytes: <int>[1, 2, 3, 4, 5, 6, 7, 8],
          bytesPerRow: 4,
          bytesPerPixel: 1,
        ),
        VideoPlaneData(
          bytes: <int>[10, 30, 20, 40],
          bytesPerRow: 4,
          bytesPerPixel: 2,
        ),
      ],
    );

    expect(frame.y, Uint8List.fromList(const <int>[1, 2, 3, 4, 5, 6, 7, 8]));
    expect(frame.u, Uint8List.fromList(const <int>[10, 20]));
    expect(frame.v, Uint8List.fromList(const <int>[30, 40]));
  });

  test('video capture is supported exactly where a camera backend exists', () {
    // package:camera covers Android/iOS, camera_macos covers macOS.
    for (final p in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      expect(
        CallMediaCapabilities.supportsVideoCapture(platform: p),
        isTrue,
        reason: '$p has a camera plugin backend',
      );
    }
    // Windows/Linux have no camera plugin implementation — video entry
    // points must be hidden there (voice stays available).
    for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
      expect(
        CallMediaCapabilities.supportsVideoCapture(platform: p),
        isFalse,
        reason: '$p has no camera capture backend',
      );
    }
  });

  test('hides speaker toggle until audio route switching is implemented', () {
    expect(
      CallMediaCapabilities.supportsSpeakerToggle(
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
    expect(
      CallMediaCapabilities.supportsSpeakerToggle(platform: TargetPlatform.iOS),
      isFalse,
    );
  });

  test('rotates outgoing Android frames upright using camera orientation', () {
    final transform = OutgoingVideoTransform.compute(
      platform: TargetPlatform.android,
      deviceOrientation: DeviceOrientation.portraitUp,
      camera: const CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    );

    expect(transform.quarterTurns, 1);
    expect(transform.shouldMirror, isFalse);
  });

  test('rotates I420 frame data when quarter turns are applied', () {
    final rotated = I420FrameTransformer.apply(
      y: Uint8List.fromList(const <int>[1, 2, 3, 4]),
      u: Uint8List.fromList(const <int>[5]),
      v: Uint8List.fromList(const <int>[6]),
      width: 2,
      height: 2,
      quarterTurns: 1,
    );

    expect(rotated.width, 2);
    expect(rotated.height, 2);
    expect(rotated.y, Uint8List.fromList(const <int>[3, 1, 4, 2]));
    expect(rotated.u, Uint8List.fromList(const <int>[5]));
    expect(rotated.v, Uint8List.fromList(const <int>[6]));
  });
}
