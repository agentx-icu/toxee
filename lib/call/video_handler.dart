import 'dart:async';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:camera_macos/camera_macos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tim2tox_dart/service/toxav_service.dart';

import '../util/logger.dart';
import 'call_camera_switch_controller.dart';
import 'call_codec_profile.dart';
import 'call_video_transform.dart';

class VideoPlaneData {
  final List<int> bytes;
  final int bytesPerRow;
  final int bytesPerPixel;

  const VideoPlaneData({
    required this.bytes,
    required this.bytesPerRow,
    int? bytesPerPixel,
  }) : bytesPerPixel = bytesPerPixel ?? 1;
}

class NormalizedVideoFrame {
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;

  const NormalizedVideoFrame({
    required this.y,
    required this.u,
    required this.v,
  });
}

class VideoFrameNormalizer {
  const VideoFrameNormalizer._();

  static NormalizedVideoFrame normalizeYuv420({
    required int width,
    required int height,
    required List<VideoPlaneData> planes,
  }) {
    if (planes.length == 3) {
      final uvWidth = width ~/ 2;
      final uvHeight = height ~/ 2;
      return NormalizedVideoFrame(
        y: _compactPlane(plane: planes[0], width: width, height: height),
        u: _compactPlane(plane: planes[1], width: uvWidth, height: uvHeight),
        v: _compactPlane(plane: planes[2], width: uvWidth, height: uvHeight),
      );
    }

    if (planes.length == 2) {
      final uvWidth = width ~/ 2;
      final uvHeight = height ~/ 2;
      final y = _compactPlane(plane: planes[0], width: width, height: height);
      final uvPlane = planes[1];
      final u = Uint8List(uvWidth * uvHeight);
      final v = Uint8List(uvWidth * uvHeight);
      var index = 0;

      for (var row = 0; row < uvHeight; row++) {
        final rowStart = row * uvPlane.bytesPerRow;
        for (var col = 0; col < uvWidth; col++) {
          final offset = rowStart + (col * 2);
          if (offset + 1 >= uvPlane.bytes.length) {
            throw RangeError(
              'UV plane buffer is too small for $width x $height frame',
            );
          }
          u[index] = uvPlane.bytes[offset];
          v[index] = uvPlane.bytes[offset + 1];
          index++;
        }
      }

      return NormalizedVideoFrame(y: y, u: u, v: v);
    }

    throw UnsupportedError(
      'Unsupported YUV420 plane layout: ${planes.length} planes',
    );
  }

  static Uint8List _compactPlane({
    required VideoPlaneData plane,
    required int width,
    required int height,
  }) {
    final output = Uint8List(width * height);
    final pixelStride = plane.bytesPerPixel <= 0 ? 1 : plane.bytesPerPixel;
    var index = 0;

    for (var row = 0; row < height; row++) {
      final rowStart = row * plane.bytesPerRow;
      for (var col = 0; col < width; col++) {
        final offset = rowStart + (col * pixelStride);
        if (offset >= plane.bytes.length) {
          throw RangeError(
            'Plane buffer is too small for $width x $height plane',
          );
        }
        output[index++] = plane.bytes[offset];
      }
    }

    return output;
  }
}

/// Data class to pass YUV420 frame data to an Isolate via compute().
class _Yuv420Frame {
  final int width;
  final int height;
  final List<int> y;
  final List<int> u;
  final List<int> v;

  _Yuv420Frame(this.width, this.height, this.y, this.u, this.v);
}

/// Top-level function: convert YUV420 to RGBA in an Isolate.
/// Must be top-level (not a closure/method) for compute() to work.
Uint8List _convertYuv420ToRgba(_Yuv420Frame frame) {
  final width = frame.width;
  final height = frame.height;
  final y = frame.y;
  final u = frame.u;
  final v = frame.v;
  final uvWidth = width ~/ 2;
  final rgba = Uint8List(width * height * 4);

  for (int row = 0; row < height; row++) {
    final rowOffset = row * width;
    final uvRowOffset = (row ~/ 2) * uvWidth;
    for (int col = 0; col < width; col++) {
      final yVal = y[rowOffset + col].toDouble();
      final uvCol = col ~/ 2;
      final uVal = u[uvRowOffset + uvCol].toDouble() - 128;
      final vVal = v[uvRowOffset + uvCol].toDouble() - 128;
      final r = (yVal + 1.402 * vVal).clamp(0.0, 255.0).toInt();
      final g = (yVal - 0.344 * uVal - 0.714 * vVal).clamp(0.0, 255.0).toInt();
      final b = (yVal + 1.772 * uVal).clamp(0.0, 255.0).toInt();
      final i = (rowOffset + col) * 4;
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

/// Chooses a selfie-friendly initial camera while preserving a deterministic
/// fallback for devices that expose only rear or external lenses.
CameraDescription preferredInitialMobileCamera(
  List<CameraDescription> cameras,
) {
  if (cameras.isEmpty) {
    throw ArgumentError.value(cameras, 'cameras', 'must not be empty');
  }
  return cameras.firstWhere(
    (camera) => camera.lensDirection == CameraLensDirection.front,
    orElse: () => cameras.first,
  );
}

/// Chooses the next mobile camera, preferring a front/back lens transition
/// over cycling between multiple lenses facing the same direction.
CameraDescription nextMobileCamera(
  List<CameraDescription> cameras,
  CameraDescription current,
) {
  if (cameras.isEmpty) {
    throw ArgumentError.value(cameras, 'cameras', 'must not be empty');
  }

  final oppositeDirection = switch (current.lensDirection) {
    CameraLensDirection.front => CameraLensDirection.back,
    CameraLensDirection.back => CameraLensDirection.front,
    CameraLensDirection.external => null,
  };
  if (oppositeDirection != null) {
    for (final camera in cameras) {
      if (camera.lensDirection == oppositeDirection) return camera;
    }
  }

  final currentIndex = cameras.indexOf(current);
  if (currentIndex < 0) return cameras.first;
  return cameras[(currentIndex + 1) % cameras.length];
}

/// Tracks the selected mobile camera within one call session.
///
/// Temporary capture stops keep the current selection. A completed call
/// resets the controller so the next call prefers the front camera again.
class MobileCameraSelectionController {
  CameraDescription? _selected;

  CameraDescription cameraForStart(List<CameraDescription> cameras) {
    if (cameras.isEmpty) {
      throw ArgumentError.value(cameras, 'cameras', 'must not be empty');
    }

    final selected = _selected;
    if (selected != null) {
      final selectedIndex = cameras.indexOf(selected);
      if (selectedIndex >= 0) return cameras[selectedIndex];
    }

    final initial = preferredInitialMobileCamera(cameras);
    _selected = initial;
    return initial;
  }

  void select(CameraDescription camera) {
    _selected = camera;
  }

  void resetForNextCall() {
    _selected = null;
  }
}

/// Video capture (camera → YUV420 → ToxAV) and receive (YUV420 → display).
/// Extends ChangeNotifier so UI can react to camera initialization.
///
/// Lifecycle invariants:
///   - [startCapture] and [stop] must not race. Concurrent calls are
///     serialized via [_startFuture] / [_stopFuture]; a `stop` issued mid-init
///     waits for init to settle before tearing down, and a `startCapture`
///     issued before the previous `stop` finishes waits for it to complete.
///   - After [dispose] (or [disposeAsync]), [_disposed] is `true` and all
///     mutating operations short-circuit; [notifyListeners] is suppressed so
///     a late-arriving `notifyListeners` from in-flight stop work cannot
///     throw against the disposed listenable.
class VideoHandler extends ChangeNotifier {
  ToxAVService? _avService;
  int _friendNumber = 0;
  bool _capturing = false;
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  final MobileCameraSelectionController _mobileCameraSelection =
      MobileCameraSelectionController();
  final CallCameraSwitchController _cameraSwitchController =
      CallCameraSwitchController();

  /// macOS-only: when using camera_macos (official camera plugin has no macOS impl).
  bool _usingMacOSCamera = false;
  int? _macosTextureId;

  /// Throttle: skip frames to reduce CPU/bandwidth usage. Derived from
  /// [_codecProfile.videoFps] so an adaptive bitrate downgrade can also
  /// drop frame rate, not just bit rate.
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);
  CallCodecProfile _codecProfile = CallCodecProfile.defaultProfile;
  Duration get _minFrameInterval => _codecProfile.minFrameInterval;

  /// Update the codec profile in response to a peer-suggested bitrate
  /// change (forwarded by `CallServiceManager` from the ToxAV bitrate
  /// callbacks). Hot-swapping is safe — the throttle picks up the new
  /// interval on the next frame.
  void setCodecProfile(CallCodecProfile profile) {
    _codecProfile = profile;
  }

  /// Guard against overlapping compute() calls.
  bool _converting = false;

  /// Set once `dispose` or `disposeAsync` has been called. Suppresses any
  /// subsequent `notifyListeners` so in-flight `stop()` work cannot throw
  /// against an already-disposed [ChangeNotifier].
  bool _disposed = false;

  /// Future tracking an in-flight `startCapture` body. `stop()` waits on
  /// this so it doesn't tear down camera state mid-init.
  Future<void>? _startFuture;

  /// Future tracking an in-flight `_doStop` body. `startCapture` waits on
  /// this so it doesn't race a previous teardown.
  Future<void>? _stopFuture;

  /// Whether the handler has been disposed.
  @visibleForTesting
  bool get isDisposed => _disposed;

  bool get isCapturing => _capturing;

  /// Latest remote frame as RGB for display. UI can listen and show via RawImage.
  final ValueNotifier<ui.Image?> remoteImage = ValueNotifier<ui.Image?>(null);

  /// Whether the local camera preview is ready.
  bool get isLocalPreviewReady =>
      (_controller != null && _controller!.value.isInitialized) ||
      (_usingMacOSCamera && _macosTextureId != null);

  /// Start camera capture and send YUV420 frames to ToxAV.
  /// On macOS uses [camera_macos] (official camera plugin has no macOS impl);
  /// that triggers the system camera permission dialog and provides the stream.
  ///
  /// If a previous [stop] is still tearing down, this waits for it to complete
  /// before initializing a fresh camera session. After [dispose] this is a
  /// no-op.
  Future<void> startCapture(int friendNumber, ToxAVService avService) async {
    if (_disposed) return;
    // Wait for any in-flight stop so we don't initialize against a
    // half-torn-down camera session.
    final pending = _stopFuture;
    if (pending != null) {
      try {
        await pending;
      } catch (e) {
        AppLogger.warn(
          '[VideoHandler] awaiting in-flight stop before startCapture failed: $e',
        );
      }
    }
    if (_disposed || _capturing) return;
    final future = _doStartCapture(friendNumber, avService);
    _startFuture = future;
    try {
      await future;
    } finally {
      if (identical(_startFuture, future)) _startFuture = null;
    }
  }

  Future<void> _doStartCapture(int friendNumber, ToxAVService avService) async {
    _friendNumber = friendNumber;
    _avService = avService;
    _capturing = true;

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        final devices = await CameraMacOS.instance.listDevices(
          deviceType: CameraMacOSDeviceType.video,
        );
        if (devices.isEmpty) {
          _capturing = false;
          notifyListeners();
          debugPrint(
            '[VideoHandler] startCapture macOS: no video devices. '
            'Allow Camera in System Settings → Privacy & Security.',
          );
          AppLogger.log(
            '[VideoHandler] startCapture macOS: no video devices (check Camera permission)',
          );
          return;
        }
        final deviceId = devices.first.deviceId;
        final args = await CameraMacOS.instance.initialize(
          deviceId: deviceId,
          cameraMacOSMode: CameraMacOSMode.video,
        );
        if (args == null) {
          throw StateError('camera_macos initialize returned null');
        }
        final textureId = args.textureId;
        if (textureId == null) {
          throw StateError('camera_macos initialize returned null textureId');
        }
        _macosTextureId = textureId;
        _usingMacOSCamera = true;
        notifyListeners();
        await CameraMacOS.instance.startImageStream(
          (CameraImageData? data) {
            if (data != null) _onMacOSCameraImage(data);
          },
          onError: (e) {
            debugPrint('[VideoHandler] macOS image stream error: $e');
            AppLogger.log('[VideoHandler] macOS image stream error: $e');
          },
        );
        AppLogger.log(
          '[VideoHandler] macOS capture started (camera_macos stream active)',
        );
      } catch (e) {
        _capturing = false;
        _usingMacOSCamera = false;
        _macosTextureId = null;
        // Tear down native camera session so later capture attempts don't fail with device in-use.
        try {
          await CameraMacOS.instance.stopImageStream();
        } catch (e) {
          AppLogger.warn(
            '[VideoHandler] stopImageStream during error recovery failed: $e',
          );
        }
        try {
          await CameraMacOS.instance.destroy();
        } catch (e) {
          AppLogger.warn(
            '[VideoHandler] camera destroy during error recovery failed: $e',
          );
        }
        notifyListeners();
        debugPrint('[VideoHandler] startCapture macOS camera_macos error: $e');
        AppLogger.log(
          '[VideoHandler] startCapture macOS camera_macos error: $e',
        );
        debugPrint(
          '[VideoHandler] On macOS: ensure Camera is allowed in '
          'System Settings → Privacy & Security.',
        );
        AppLogger.log(
          '[VideoHandler] On macOS: ensure Camera is allowed in '
          'System Settings → Privacy & Security.',
        );
      }
      return;
    }

    try {
      _cameras ??= await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _capturing = false;
        notifyListeners();
        debugPrint(
          '[VideoHandler] startCapture: no cameras available. '
          'On macOS: allow Camera in System Settings → Privacy & Security, '
          'and close other apps using the camera.',
        );
        return;
      }
      final camera = _mobileCameraSelection.cameraForStart(_cameras!);
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      notifyListeners();
      await _controller!.startImageStream(_onCameraImage);
      AppLogger.log('[VideoHandler] capture started (camera stream active)');
    } on MissingPluginException catch (e) {
      _capturing = false;
      notifyListeners();
      debugPrint(
        '[VideoHandler] startCapture: camera plugin not implemented on this '
        'platform, local preview disabled: $e',
      );
      AppLogger.log(
        '[VideoHandler] startCapture: camera plugin not implemented: $e',
      );
    } catch (e) {
      _capturing = false;
      notifyListeners();
      debugPrint('[VideoHandler] startCapture error: $e');
      AppLogger.log('[VideoHandler] startCapture error: $e');
    }
  }

  /// Handles frames from camera_macos (ARGB8888) on macOS; converts to YUV and sends.
  void _onMacOSCameraImage(CameraImageData data) {
    if (!_capturing || _avService == null) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameTime) < _minFrameInterval) return;
    _lastFrameTime = now;

    try {
      final converted = RgbToYuv420.argb8888ToYuv420(
        argb: data.bytes,
        width: data.width,
        height: data.height,
        bytesPerRow: data.bytesPerRow,
      );
      const quarterTurns = 0;
      final transformedFrame = I420FrameTransformer.apply(
        y: converted.y,
        u: converted.u,
        v: converted.v,
        width: data.width,
        height: data.height,
        quarterTurns: quarterTurns,
      );
      _avService!.sendVideoFrame(
        _friendNumber,
        transformedFrame.width,
        transformedFrame.height,
        transformedFrame.y,
        transformedFrame.u,
        transformedFrame.v,
        yStride: transformedFrame.width,
        uStride: transformedFrame.width ~/ 2,
        vStride: transformedFrame.width ~/ 2,
      );
    } catch (e) {
      debugPrint('[VideoHandler] _onMacOSCameraImage error: $e');
    }
  }

  void _onCameraImage(CameraImage image) {
    final controller = _controller;
    if (!_capturing || _avService == null || controller == null) return;

    // Frame rate throttle
    final now = DateTime.now();
    if (now.difference(_lastFrameTime) < _minFrameInterval) return;
    _lastFrameTime = now;

    try {
      NormalizedVideoFrame normalized;
      final int width = image.width;
      final int height = image.height;

      if (image.format.group == ImageFormatGroup.bgra8888 &&
          image.planes.isNotEmpty) {
        final plane = image.planes[0];
        final converted = RgbToYuv420.bgra8888ToYuv420(
          bgra: plane.bytes,
          width: width,
          height: height,
          bytesPerRow: plane.bytesPerRow,
        );
        normalized = NormalizedVideoFrame(
          y: converted.y,
          u: converted.u,
          v: converted.v,
        );
      } else if (image.format.group == ImageFormatGroup.yuv420 &&
          image.planes.length >= 2) {
        final planes = image.planes.asMap().entries.map((entry) {
          final plane = entry.value;
          final isBiPlanarUv = image.planes.length == 2 && entry.key == 1;
          return VideoPlaneData(
            bytes: plane.bytes,
            bytesPerRow: plane.bytesPerRow,
            bytesPerPixel: plane.bytesPerPixel ?? (isBiPlanarUv ? 2 : 1),
          );
        }).toList();
        normalized = VideoFrameNormalizer.normalizeYuv420(
          width: width,
          height: height,
          planes: planes,
        );
      } else {
        return;
      }

      final deviceOrientation = controller.value.deviceOrientation;
      final outgoingTransform = OutgoingVideoTransform.compute(
        platform: defaultTargetPlatform,
        deviceOrientation: deviceOrientation,
        camera: controller.description,
      );
      final transformedFrame = I420FrameTransformer.apply(
        y: normalized.y,
        u: normalized.u,
        v: normalized.v,
        width: width,
        height: height,
        quarterTurns: outgoingTransform.quarterTurns,
      );
      _avService!.sendVideoFrame(
        _friendNumber,
        transformedFrame.width,
        transformedFrame.height,
        transformedFrame.y,
        transformedFrame.u,
        transformedFrame.v,
        yStride: transformedFrame.width,
        uStride: transformedFrame.width ~/ 2,
        vStride: transformedFrame.width ~/ 2,
      );
    } catch (e) {
      debugPrint('[VideoHandler] normalize/send frame error: $e');
    }
  }

  /// Called when ToxAV receives a video frame (YUV420).
  /// Converts to RGBA in an Isolate via compute(), then updates [remoteImage].
  void onVideoReceived(
    int friendNumber,
    int width,
    int height,
    List<int> y,
    List<int> u,
    List<int> v,
  ) {
    if (width <= 0 || height <= 0 || y.length < width * height) return;
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    if (u.length < uvWidth * uvHeight || v.length < uvWidth * uvHeight) return;

    // Skip if a previous conversion is still running
    if (_converting) return;
    _converting = true;

    final frame = _Yuv420Frame(width, height, y, u, v);
    compute(_convertYuv420ToRgba, frame)
        .then((rgba) {
          _converting = false;
          ui.decodeImageFromPixels(
            rgba,
            width,
            height,
            ui.PixelFormat.rgba8888,
            (ui.Image image) {
              final previous = remoteImage.value;
              remoteImage.value = image;
              previous?.dispose();
            },
            rowBytes: width * 4,
          );
        })
        .catchError((e) {
          _converting = false;
          debugPrint('[VideoHandler] compute error: $e');
        });
  }

  /// Local camera preview widget.
  Widget? get localPreview {
    if (_usingMacOSCamera && _macosTextureId != null) {
      return Texture(textureId: _macosTextureId!);
    }
    if (_controller == null || !_controller!.value.isInitialized) return null;
    return CameraPreview(_controller!);
  }

  /// Stop capture and release camera resources.
  ///
  /// Coalesces concurrent calls onto the in-flight future and waits for any
  /// in-flight [startCapture] to settle before tearing down, so a `stop`
  /// issued mid-init reliably releases the camera handle.
  Future<void> stop() async {
    final inFlight = _stopFuture;
    if (inFlight != null) return inFlight;
    // Let any in-flight start finish before tearing down. Otherwise stop's
    // teardown can race with the start path that's still attaching the
    // image stream / writing _controller.
    final pendingStart = _startFuture;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (e) {
        AppLogger.warn(
          '[VideoHandler] awaiting in-flight start before stop failed: $e',
        );
      }
    }
    final future = _doStop();
    _stopFuture = future;
    try {
      await future;
    } finally {
      if (identical(_stopFuture, future)) _stopFuture = null;
    }
  }

  Future<void> _doStop() async {
    _capturing = false;
    if (_usingMacOSCamera) {
      try {
        await CameraMacOS.instance.stopImageStream();
        await CameraMacOS.instance.destroy();
      } catch (e) {
        AppLogger.warn('[VideoHandler] macOS camera teardown failed: $e');
      }
      _usingMacOSCamera = false;
      _macosTextureId = null;
    }
    try {
      await _controller?.stopImageStream();
      await _controller?.dispose();
    } catch (e) {
      AppLogger.warn('[VideoHandler] camera controller teardown failed: $e');
    }
    _controller = null;
    final previous = remoteImage.value;
    remoteImage.value = null;
    previous?.dispose();
    notifyListeners();
  }

  Future<void> switchCamera({required bool Function() canSwitch}) {
    return _cameraSwitchController.switchCamera(
      canSwitch: () => !_disposed && canSwitch(),
      prepareSwitch: () async {
        // Re-fetch devices so cameras attached during the call are included.
        try {
          final fresh = await availableCameras();
          if (fresh.isNotEmpty) _cameras = fresh;
        } catch (e) {
          debugPrint('[VideoHandler] switchCamera availableCameras error: $e');
        }
      },
      performSwitch: (canRestart) async {
        if (!_capturing) return;

        final cameras = _cameras;
        if (cameras == null || cameras.length < 2) return;
        final current =
            _controller?.description ??
            _mobileCameraSelection.cameraForStart(cameras);
        final next = nextMobileCamera(cameras, current);
        final avService = _avService;
        if (avService == null) return;

        await stop();
        if (!canRestart()) return;

        _mobileCameraSelection.select(next);
        await startCapture(_friendNumber, avService);
        if (!canRestart()) await stop();
      },
    );
  }

  /// Marks a hard call-session boundary without disturbing temporary capture
  /// stops inside the current call.
  void resetCameraSelectionForNextCall() {
    _mobileCameraSelection.resetForNextCall();
  }

  /// Async-safe disposal: awaits any in-flight start/stop before disposing.
  /// Prefer this in lifecycle owners that can await (e.g. `CallServiceManager`
  /// teardown). The sync [dispose] override is retained for compatibility with
  /// the [ChangeNotifier] contract.
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    final pendingStart = _startFuture;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (e) {
        AppLogger.warn(
          '[VideoHandler] awaiting in-flight start before disposeAsync failed: $e',
        );
      }
    }
    await stop();
    super.dispose();
  }

  @override
  void notifyListeners() {
    // Silently no-op after dispose so an in-flight `_doStop()` that completes
    // *after* `dispose()` does not throw against the disposed listenable.
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return; // Idempotent — super.dispose() throws on re-entry.
    _disposed = true;
    // Kick off teardown; the [notifyListeners] override above keeps the
    // in-flight stop from throwing on this now-disposed notifier.
    unawaited(stop());
    super.dispose();
  }
}
