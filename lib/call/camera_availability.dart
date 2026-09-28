import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Why the camera is not delivering frames right now, as iOS reports it
/// (checklist V5), or null while it works. See `ToxeeCameraMultitasking` in
/// ios/Runner/AppDelegate.swift. Other platforms never report anything.
enum CameraUnavailableReason {
  /// Other apps share the screen (Split View / Slide Over / Stage Manager)
  /// and this iPad cannot keep the camera running meanwhile.
  multitasking,

  /// Another app holds the camera, or the system is under pressure.
  other,
}

class CameraAvailability {
  CameraAvailability._();

  static const MethodChannel _channel = MethodChannel(
    'toxee/camera_interruption',
  );

  /// AVCaptureSession.InterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps.
  static const _multitaskingReason = 4;

  static final ValueNotifier<CameraUnavailableReason?> unavailable =
      ValueNotifier(null);

  static bool _listening = false;

  /// Starts listening for the native reports. Idempotent.
  static void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'changed') return;
      final args = call.arguments as Map<Object?, Object?>? ?? const {};
      apply(
        unavailable: args['unavailable'] == true,
        reason: args['reason'] is int ? args['reason']! as int : 0,
      );
    });
  }

  @visibleForTesting
  static void apply({required bool unavailable, required int reason}) {
    CameraAvailability.unavailable.value = !unavailable
        ? null
        : reason == _multitaskingReason
        ? CameraUnavailableReason.multitasking
        : CameraUnavailableReason.other;
  }
}
