import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../util/logger.dart';
import '../util/serialized_async_tail.dart';

/// Plays a ringtone (generated tone) when there is an incoming call. Stops when call is accepted/rejected.
///
/// Android rings natively (`playIncomingRingtone`, honours the ringer mode).
/// iOS only rings here when CallKit could not be used (e.g. where CallKit is
/// not allowed). On screen it rings natively: a looped system alert sound
/// that honours the silent switch (A9); off screen it rings through the
/// audioplayers loop, which keeps a backgrounded app alive (see [start]).
/// Desktop plays the tone with audioplayers.
class RingtonePlayer {
  static const MethodChannel _callAudioChannel =
      MethodChannel('toxee/call_audio');

  RingtonePlayer({
    @visibleForTesting
    Future<void> Function(String wavPath, double volume)? playLoop,
    @visibleForTesting Future<void> Function(double volume)? setLoopVolume,
    @visibleForTesting Future<void> Function()? stopLoop,
    @visibleForTesting Future<String?> Function()? createWav,
    @visibleForTesting bool? isIOS,
    @visibleForTesting bool? isAndroid,
  }) : _createWav = createWav ?? _createRingtoneWav,
       _isIOS = isIOS ?? Platform.isIOS,
       _isAndroid = isAndroid ?? Platform.isAndroid {
    _playLoop = playLoop ?? _audioplayersLoop;
    _setLoopVolume = setLoopVolume ?? _player.setVolume;
    _stopLoop = stopLoop ?? _player.stop;
  }

  final AudioPlayer _player = AudioPlayer();
  late final Future<void> Function(String wavPath, double volume) _playLoop;
  late final Future<void> Function(double volume) _setLoopVolume;
  late final Future<void> Function() _stopLoop;
  final Future<String?> Function() _createWav;
  final bool _isIOS;
  final bool _isAndroid;
  String? _tempWavPath;

  /// The native ringer (Android; iOS on screen) is sounding.
  bool _nativeRinging = false;

  /// The audioplayers loop is playing (possibly muted, see [start]).
  bool _loopPlaying = false;

  /// A ring was asked for and not stopped since.
  bool _active = false;

  /// start / stop / the background hand-over run one at a time, in order:
  /// each sees the state the previous one left, so a stop that lands while a
  /// start is still awaiting stops exactly what that start began, and a
  /// restart cannot revive an older start.
  final SerializedAsyncTail _ops = SerializedAsyncTail(
    logError: (e, _) => AppLogger.warn('[RingtonePlayer] $e'),
  );

  /// iOS, ringing natively: hands over to the loop when the app leaves the
  /// screen.
  AppLifecycleListener? _lifecycle;

  /// Start playing ringtone in loop (incoming call).
  ///
  /// iOS on screen: the native ringer sounds (silent switch honoured), while
  /// the audioplayers loop runs MUTED beside it — iOS will not let audio
  /// start once the app is in the background, but a loop already playing
  /// keeps the app alive there. Leaving the screen stops the native ringer
  /// and unmutes the loop (which, like before A9, ignores the silent switch).
  Future<void> start() => _ops.enqueue(_start);

  /// Stop ringtone. Safe at any time; runs after a start still in progress.
  Future<void> stop() => _ops.enqueue(() async {
    _active = false;
    await _stopAll();
  });

  Future<void> _start() async {
    if (_active) return;
    _active = true;
    try {
      final nativeFirst = _isAndroid || (_isIOS && _onScreen());
      if (_isIOS && nativeFirst) {
        // Before any await: a hide during the start must not be missed.
        _lifecycle = AppLifecycleListener(
          onHide: () => unawaited(_ops.enqueue(_handOverToLoop)),
        );
      }
      if (nativeFirst) {
        try {
          if (_isIOS) _tempWavPath ??= await _createWav();
          final handled = await _callAudioChannel.invokeMethod<bool>(
                'playIncomingRingtone',
                _isIOS ? {'path': _tempWavPath} : null,
              ) ??
              false;
          if (handled) {
            _nativeRinging = true;
            if (!_isIOS) return;
            try {
              await _startLoop(muted: true);
            } catch (e) {
              // The native ring still sounds; only the background keep-alive
              // is missing.
              AppLogger.warn('[RingtonePlayer] muted companion loop failed: $e');
            }
            return;
          }
        } on MissingPluginException {
          // Fall through to the pure-Dart fallback in tests or unsupported
          // host environments.
        }
      }
      await _startLoop(muted: false);
    } catch (e) {
      _active = false; // a later start may try again
      await _stopAll();
      // Best-effort: no asset / platform plugin missing — surface as warn so
      // a silent failure to ring is at least visible in logs.
      AppLogger.warn('[RingtonePlayer] start failed (no asset or platform error): $e');
    }
  }

  static bool _onScreen() {
    final state = SchedulerBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  Future<void> _startLoop({required bool muted}) async {
    _tempWavPath ??= await _createWav();
    if (_tempWavPath == null) return;
    await _playLoop(_tempWavPath!, muted ? 0 : 1);
    _loopPlaying = true;
  }

  Future<void> _audioplayersLoop(String wavPath, double volume) async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(volume);
    await _player.setSource(DeviceFileSource(wavPath));
    await _player.resume();
  }

  /// The app left the screen while ringing natively (iOS). Queued behind
  /// the start, so the loop it unmutes is fully started.
  Future<void> _handOverToLoop() async {
    _lifecycle?.dispose();
    _lifecycle = null;
    if (!_active) return;
    await _stopNative();
    try {
      if (_loopPlaying) {
        await _setLoopVolume(1);
      } else {
        await _startLoop(muted: false); // best effort: may be too late
      }
    } catch (e) {
      AppLogger.warn('[RingtonePlayer] background ringer failed: $e');
    }
  }

  /// Flags are cleared whatever the platform answers, so a transient failure
  /// can never strand the player "ringing" and block the next [start].
  Future<void> _stopAll() async {
    _lifecycle?.dispose();
    _lifecycle = null;
    await _stopNative();
    if (_loopPlaying) {
      try {
        await _stopLoop();
      } catch (e) {
        AppLogger.warn('[RingtonePlayer] stop failed: $e');
      } finally {
        _loopPlaying = false;
      }
    }
  }

  Future<void> _stopNative() async {
    if (!_nativeRinging) return;
    try {
      await _callAudioChannel.invokeMethod<void>('stopIncomingRingtone');
    } on MissingPluginException {
      // Plugin absent (tests / unsupported hosts).
    } catch (e) {
      AppLogger.warn('[RingtonePlayer] native stop failed: $e');
    } finally {
      _nativeRinging = false;
    }
  }

  /// Release native AudioPlayer resources and clean up temp file.
  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (e) {
      AppLogger.warn('[RingtonePlayer] dispose AudioPlayer failed: $e');
    }
    if (_tempWavPath != null) {
      try {
        final file = File(_tempWavPath!);
        if (await file.exists()) await file.delete();
      } catch (e) {
        AppLogger.warn('[RingtonePlayer] temp wav cleanup failed: $e');
      }
      _tempWavPath = null;
    }
  }

  /// Create a short WAV file (440 Hz beep, 0.4s on, looped by audioplayers).
  static Future<String?> _createRingtoneWav() async {
    const sampleRate = 44100;
    const durationSec = 0.4;
    const freq = 440.0;
    final numSamples = (sampleRate * durationSec).round();
    final bytes = ByteData(44 + numSamples * 2);
    int pos = 0;
    void writeU32(int v) {
      bytes.setUint32(pos, v, Endian.little);
      pos += 4;
    }
    void writeU16(int v) {
      bytes.setUint16(pos, v, Endian.little);
      pos += 2;
    }
    // "RIFF"
    bytes.setUint8(pos, 0x52); pos++;
    bytes.setUint8(pos, 0x49); pos++;
    bytes.setUint8(pos, 0x46); pos++;
    bytes.setUint8(pos, 0x46); pos++;
    writeU32(36 + numSamples * 2);
    // "WAVE"
    bytes.setUint8(pos, 0x57); pos++;
    bytes.setUint8(pos, 0x41); pos++;
    bytes.setUint8(pos, 0x56); pos++;
    bytes.setUint8(pos, 0x45); pos++;
    // "fmt "
    bytes.setUint8(pos, 0x66); pos++;
    bytes.setUint8(pos, 0x6d); pos++;
    bytes.setUint8(pos, 0x74); pos++;
    bytes.setUint8(pos, 0x20); pos++;
    writeU32(16);
    writeU16(1); // PCM
    writeU16(1); // mono
    writeU32(sampleRate);
    writeU32(sampleRate * 2); // byte rate
    writeU16(2); // block align
    writeU16(16); // bits per sample
    // "data"
    bytes.setUint8(pos, 0x64); pos++;
    bytes.setUint8(pos, 0x61); pos++;
    bytes.setUint8(pos, 0x74); pos++;
    bytes.setUint8(pos, 0x61); pos++;
    writeU32(numSamples * 2);
    const step = 2 * math.pi * freq / sampleRate;
    for (int i = 0; i < numSamples; i++) {
      final sample = (0.3 * math.sin(step * i) * 32767).round().clamp(-32768, 32767);
      bytes.setInt16(pos, sample, Endian.little);
      pos += 2;
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(
        dir.path, 'ringtone_${DateTime.now().millisecondsSinceEpoch}.wav'));
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  }
}
