import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart' as pcm_sound;
import 'package:record/record.dart';

import '../util/logger.dart';
import 'call_media_capabilities.dart';

/// Opens [device] with [config]. Returns null when this platform cannot
/// capture, permission is denied (mobile), the platform throws, or
/// [isCurrent] turned false meanwhile — in that last case the just-opened
/// recorder is stopped again before returning. On desktop (e.g. macOS) it
/// tries `startStream` even when permission is reported false so the system
/// permission dialog can appear.
Future<Stream<Uint8List>?> openCaptureStream(
  PcmCaptureDevice device,
  RecordConfig config, {
  required bool Function() isCurrent,
}) async {
  // Receive-only audio where local capture would ABORT the process. The iOS
  // Simulator's AVAudioEngine input node raises SIGABRT from inside
  // AudioToolbox (see CallMediaCapabilities.supportsAudioCapture for the
  // measured stack), which no `try/catch` below can intercept — the app dies
  // the moment a call is answered. Same rule the camera-less platforms
  // already follow for video: connect the call, render the remote stream,
  // just do not open a local capture that cannot work here.
  if (!CallMediaCapabilities.supportsAudioCapture()) {
    AppLogger.log(
      '[AudioHandler] startCapture skipped: this platform cannot open a '
      'microphone stream (iOS Simulator AVAudioEngine aborts); the call '
      'continues receive-only',
    );
    return null;
  }
  final hasPermission = await device.hasPermission();
  if (!isCurrent()) return null;
  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (!hasPermission && !isDesktop) {
    debugPrint('[AudioHandler] startCapture: microphone permission not granted');
    return null;
  }
  if (!hasPermission && isDesktop) {
    debugPrint(
      '[AudioHandler] startCapture: permission reported false on desktop, '
      'attempting startStream to trigger system dialog',
    );
  }
  try {
    final stream = await device.startStream(config);
    if (!isCurrent()) {
      // Torn down while the platform was opening the mic: release it.
      await stopCaptureQuietly(device);
      return null;
    }
    return stream;
  } catch (e) {
    debugPrint('[AudioHandler] startCapture error: $e');
    AppLogger.log('[AudioHandler] startCapture error: $e');
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      AppLogger.log(
        '[AudioHandler] On macOS: ensure Microphone is allowed in System '
        'Settings → Privacy & Security. Close other apps using the '
        'microphone and try again.',
      );
    }
    return null;
  }
}

/// `device.stop()` that only logs a failure (teardown must not throw).
Future<void> stopCaptureQuietly(PcmCaptureDevice device) async {
  try {
    await device.stop();
  } catch (e) {
    AppLogger.warn('[AudioHandler] recorder.stop failed during stop: $e');
  }
}

/// Seam over `record`'s [AudioRecorder] so tests can inject a fake mic.
abstract interface class PcmCaptureDevice {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startStream(RecordConfig config);
  Future<void> stop();
}

/// Seam over the static `FlutterPcmSound` API so tests can inject a fake
/// speaker.
///
/// Deliberately no `start()`: flutter_pcm_sound 3.3.3's `start()` consults a
/// static `_needsStart` that `feed()` clears and only a native
/// `OnFeedSamples(0)` sets again — neither `release()` nor `setup()` resets
/// it and native sends no final zero event on cleanup, so after a teardown
/// mid-playback `start()` returns false forever. `AudioHandler` tracks
/// starvation itself instead (see its `_starved`).
abstract interface class PcmPlaybackDevice {
  /// Completes when the native side is configured (iOS: after it has set the
  /// AVAudioSession category — see `AudioHandler.afterPlaybackSetup`).
  Future<void> setup({required int sampleRate, required int channelCount});
  void setFeedThreshold(int frames);
  void setFeedCallback(void Function(int remainingFrames)? callback);
  void feed(Int16List samples);
  Future<void> release();
}

/// [PcmCaptureDevice] over the `record` plugin.
class RecordPcmCaptureDevice implements PcmCaptureDevice {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      _recorder.startStream(config);

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }
}

/// [PcmPlaybackDevice] over the static `FlutterPcmSound` API.
class FlutterPcmPlaybackDevice implements PcmPlaybackDevice {
  @override
  Future<void> setup({required int sampleRate, required int channelCount}) {
    // Avoid flooding logs with per-feed [PCM] messages.
    unawaited(pcm_sound.FlutterPcmSound.setLogLevel(pcm_sound.LogLevel.none));
    // iOS: the plugin calls AVAudioSession.setCategory with THIS category on
    // every setup. The default (`playback`) would silently replace the call
    // session's playAndRecord and kill the microphone mid-call. It still
    // drops mode/options (voiceChat, speaker, Bluetooth), which is why
    // AudioHandler.afterPlaybackSetup re-applies the call session. Background
    // audio: without it the plugin discards samples while the app is
    // inactive, i.e. a locked phone goes silent. No-op off iOS.
    return pcm_sound.FlutterPcmSound.setup(
      sampleRate: sampleRate,
      channelCount: channelCount,
      iosAudioCategory: pcm_sound.IosAudioCategory.playAndRecord,
      iosAllowBackgroundAudio: true,
    );
  }

  @override
  void setFeedThreshold(int frames) =>
      unawaited(pcm_sound.FlutterPcmSound.setFeedThreshold(frames));

  @override
  void setFeedCallback(void Function(int remainingFrames)? callback) =>
      pcm_sound.FlutterPcmSound.setFeedCallback(callback);

  @override
  void feed(Int16List samples) => unawaited(
    pcm_sound.FlutterPcmSound.feed(pcm_sound.PcmArrayInt16.fromList(samples)),
  );

  @override
  Future<void> release() => pcm_sound.FlutterPcmSound.release();
}
