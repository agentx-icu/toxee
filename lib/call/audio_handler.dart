import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart' as pcm_sound;
import 'package:record/record.dart';
import 'package:tim2tox_dart/service/toxav_service.dart';

import '../util/logger.dart';

/// Captures microphone PCM and feeds to ToxAV; plays received PCM from ToxAV.
/// Uses 48000 Hz, mono, 16-bit PCM; 960 samples (20 ms) per frame.
class AudioHandler {
  static const int sampleRate = 48000;
  static const int channels = 1;
  static const int samplesPerFrame = 960; // 20 ms at 48 kHz
  static const int bytesPerFrame = samplesPerFrame * 2; // 16-bit

  static const RecordConfig _captureConfig = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: sampleRate,
    numChannels: channels,
    echoCancel: true,
    noiseSuppress: true,
    streamBufferSize: bytesPerFrame,
  );

  static RecordConfig buildCaptureConfig() => _captureConfig;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _streamSub;
  final List<int> _buffer = [];
  ToxAVService? _avService;
  int _friendNumber = 0;
  bool _capturing = false;
  bool _zeroDataWarningLogged = false;

  /// Playback: buffer of received PCM samples (int16), fed to FlutterPcmSound.
  final List<int> _playBuffer = [];
  bool _playbackSetup = false;
  static const int _maxPlayBufferSamples = sampleRate * 2; // ~2 seconds

  /// Start capturing from microphone and sending to ToxAV.
  /// On desktop (e.g. macOS), tries [startStream] even when [hasPermission]
  /// is false so the system permission dialog can appear; then logs on failure.
  Future<void> startCapture(int friendNumber, ToxAVService avService) async {
    if (_capturing) return;
    _friendNumber = friendNumber;
    _avService = avService;
    _zeroDataWarningLogged = false;

    final hasPermission = await _recorder.hasPermission();
    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!hasPermission && !isDesktop) {
      debugPrint(
          '[AudioHandler] startCapture: microphone permission not granted');
      return;
    }
    if (!hasPermission && isDesktop) {
      debugPrint(
          '[AudioHandler] startCapture: permission reported false on desktop, '
          'attempting startStream to trigger system dialog');
    }

    try {
      final stream = await _recorder.startStream(
        buildCaptureConfig(),
      );
      _capturing = true;
      _buffer.clear();
      _streamSub = stream.listen(
        (Uint8List data) => _onRecordData(data),
        onError: (e) {
          debugPrint('[AudioHandler] stream error: $e');
          AppLogger.log('[AudioHandler] stream error: $e');
        },
      );
      AppLogger.log('[AudioHandler] capture started (microphone stream active)');
    } catch (e) {
      _capturing = false;
      debugPrint('[AudioHandler] startCapture error: $e');
      AppLogger.log('[AudioHandler] startCapture error: $e');
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        debugPrint(
            '[AudioHandler] On macOS: ensure Microphone is allowed in '
            'System Settings → Privacy & Security. Close other apps using '
            'the microphone and try again.');
        AppLogger.log(
            '[AudioHandler] On macOS: ensure Microphone is allowed in '
            'System Settings → Privacy & Security.');
      }
    }
  }

  void _onRecordData(Uint8List data) {
    if (data.isNotEmpty &&
        data.every((b) => b == 0) &&
        !_zeroDataWarningLogged) {
      _zeroDataWarningLogged = true;
      debugPrint(
          '[AudioHandler] Receiving all-zero audio; if on macOS, check '
          'entitlements (com.apple.security.device.audio-input) and that '
          'no other app is using the microphone.');
    }
    _buffer.addAll(data);
    // Safety: drop oldest data if buffer grows beyond ~2 seconds of audio
    const maxBufferBytes = sampleRate * 2 * 2;
    if (_buffer.length > maxBufferBytes) {
      _buffer.removeRange(0, _buffer.length - bytesPerFrame);
    }
    while (_buffer.length >= bytesPerFrame) {
      final frame = _buffer.sublist(0, bytesPerFrame);
      _buffer.removeRange(0, bytesPerFrame);
      final pcm = _bytesToInt16(frame);
      if (pcm.length >= samplesPerFrame && _avService != null) {
        _avService!.sendAudioFrame(
          _friendNumber,
          pcm.sublist(0, samplesPerFrame),
          samplesPerFrame,
          channels,
          sampleRate,
        );
      }
    }
  }

  /// Convert little-endian byte pairs to signed int16 PCM samples (-32768..32767).
  static List<int> _bytesToInt16(List<int> bytes) {
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    return List.generate(
        bytes.length ~/ 2, (i) => bd.getInt16(i * 2, Endian.little));
  }

  /// Called when ToxAV receives audio from the remote peer. Queues PCM for playback.
  /// Handles both mono (ch=1) and stereo (ch=2) input by downmixing to mono.
  void onAudioReceived(int friendNumber, List<int> pcm, int sampleCount, int ch,
      int samplingRate) {
    if (pcm.isEmpty || sampleCount <= 0) return;
    if (!_playbackSetup) _setupPlayback();

    List<int> samples;
    if (ch == 2 && pcm.length >= sampleCount * 2) {
      // Stereo → Mono downmix: average left + right channels
      samples = List<int>.generate(sampleCount, (i) {
        return ((pcm[i * 2] + pcm[i * 2 + 1]) ~/ 2);
      });
    } else {
      // Mono or unexpected format: take up to sampleCount samples
      samples = sampleCount > pcm.length ? pcm : pcm.sublist(0, sampleCount);
    }

    synchronized(_playBuffer, () {
      _playBuffer.addAll(samples);
      if (_playBuffer.length > _maxPlayBufferSamples) {
        _playBuffer.removeRange(0, _playBuffer.length - _maxPlayBufferSamples);
      }
    });
    pcm_sound.FlutterPcmSound.start();
  }

  /// Single-isolate marker for "this block touches a shared buffer that's
  /// also touched by the playback feed callback." Dart's single-threaded
  /// event loop means there's no actual cross-thread interleaving — but the
  /// PCM feed/drain pattern reads more clearly when the critical sections
  /// are visually delimited. Do **not** add real locking here without first
  /// converting the buffer to a typed-data circular and benchmarking; the
  /// audio path runs at 50Hz and any mutex contention shows up immediately.
  static void synchronized(Object lock, void Function() action) => action();

  void _setupPlayback() {
    if (_playbackSetup) return;
    pcm_sound.FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: channels);
    pcm_sound.FlutterPcmSound.setFeedThreshold(sampleRate ~/ 20); // ~50 ms
    pcm_sound.FlutterPcmSound.setFeedCallback(_onFeedSamples);
    // Avoid flooding logs with per-feed [PCM] messages (use none or error only).
    pcm_sound.FlutterPcmSound.setLogLevel(pcm_sound.LogLevel.none);
    _playbackSetup = true;
  }

  void _onFeedSamples(int remainingFrames) {
    List<int> toFeed = [];
    synchronized(_playBuffer, () {
      const maxSamples = 2048;
      if (_playBuffer.isNotEmpty) {
        final n =
            _playBuffer.length > maxSamples ? maxSamples : _playBuffer.length;
        toFeed = _playBuffer.sublist(0, n);
        _playBuffer.removeRange(0, n);
      }
    });
    if (toFeed.isNotEmpty) {
      pcm_sound.FlutterPcmSound.feed(pcm_sound.PcmArrayInt16.fromList(toFeed));
    }
  }

  /// Stop capture and playback.
  Future<void> stop() async {
    _capturing = false;
    await _streamSub?.cancel();
    _streamSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _buffer.clear();
    synchronized(_playBuffer, () => _playBuffer.clear());
    if (_playbackSetup) {
      await pcm_sound.FlutterPcmSound.release();
      _playbackSetup = false;
    }
  }
}
