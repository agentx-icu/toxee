import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:tim2tox_dart/service/toxav_service.dart';

import '../util/logger.dart';
import 'audio_devices.dart';
import 'call_media_capabilities.dart';

export 'audio_devices.dart' show PcmCaptureDevice, PcmPlaybackDevice;

/// One 20 ms mono int16 frame captured from the microphone.
typedef CapturedPcmFrameSink = void Function(Int16List frame);

/// Pull-based PCM source for the playback device (e.g. the conference mixer).
abstract interface class PcmPullSource {
  /// Up to [maxSamples] mono samples; empty when nothing is ready.
  Int16List pull(int maxSamples);
}

/// Who currently owns the single microphone + speaker pipeline.
enum AudioHandlerOwner { none, call, conference }

/// Result of [AudioHandler.startConference].
enum ConferenceAudioStart {
  /// Mic frames flow to the sink and mixed audio plays.
  captureAndPlayback,

  /// Playback only: permission denied, capture unsupported, or mic failed.
  playbackOnly,

  /// A 1:1 call owns the audio pipeline.
  refused,
}

/// Playback device lifecycle as the rest of the handler sees it.
enum _PlaybackState { released, settingUp, ready }

/// The app's single microphone + speaker pipeline.
///
/// Uses 48000 Hz, mono, 16-bit PCM; 960 samples (20 ms) per frame. Two
/// mutually exclusive owners share it ([AudioHandlerOwner]): a 1:1 ToxAV call
/// ([startCapture] / [onAudioReceived] / [stop]) and a legacy AV conference
/// ([startConference] / [kickPlayback] / [stopConference]). There is exactly
/// one recorder, so the owners must never overlap; [stop] is the 1:1 teardown
/// and deliberately leaves a conference-owned pipeline alone, so a stray 1:1
/// end event can never cut a live conference's microphone.
///
/// Concurrency model (two layers):
///  * Ownership is decided SYNCHRONOUSLY when a start/stop is requested: the
///    owner, its [claim] number and the capture/playback bookkeeping flip in
///    the same event-loop turn. A stop carrying a stale claim is a no-op, so
///    a late teardown of call A can never touch call B.
///  * Every device operation (open/close the recorder, set up/release the
///    speaker) runs on one FIFO queue. A teardown that is still awaiting the
///    recorder can therefore never interleave with the next owner opening it.
class AudioHandler {
  AudioHandler({
    PcmCaptureDevice? captureDevice,
    PcmPlaybackDevice? playbackDevice,
  }) : _captureOverride = captureDevice,
       _playback = playbackDevice ?? FlutterPcmPlaybackDevice();

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

  final PcmCaptureDevice? _captureOverride;
  // Lazy: constructing AudioRecorder touches a platform channel.
  late final PcmCaptureDevice _capture =
      _captureOverride ?? RecordPcmCaptureDevice();
  final PcmPlaybackDevice _playback;

  StreamSubscription<Uint8List>? _streamSub;
  final List<int> _buffer = [];
  CapturedPcmFrameSink? _frameSink;
  bool _capturing = false;
  bool _zeroDataWarningLogged = false;

  /// Intended owner, decided synchronously at request time (see class doc).
  AudioHandlerOwner _owner = AudioHandlerOwner.none;

  /// Claim number of the current owner; 0 while nobody owns the pipeline.
  /// Every new ownership takes a fresh number from [_claimSeq].
  int _claim = 0;
  int _claimSeq = 0;

  /// Friend whose 1:1 call owns the pipeline: only its PCM is played.
  int? _callFriendNumber;
  bool _disposed = false;

  /// Tail of the FIFO device-operation queue.
  Future<void> _deviceOps = Future<void>.value();

  /// Device truth, only touched from inside [_enqueue]d operations.
  bool _playbackDeviceOpen = false;
  bool _recorderTouched = false;

  /// Playback: buffer of received PCM samples (int16), fed to FlutterPcmSound.
  final List<int> _playBuffer = [];
  PcmPullSource? _playbackSource;
  _PlaybackState _playbackState = _PlaybackState.released;

  /// Bumped whenever playback is released, so a queued setup that belongs to
  /// an older owner is skipped.
  int _playbackGeneration = 0;

  /// Earliest retry after a failed setup (else every frame re-enqueues one).
  DateTime? _playbackRetryAt;

  /// True when the device has nothing queued and will not call back on its
  /// own: after setup, and after a feed callback that reported 0 remaining
  /// frames and got nothing. New audio must then kick [_onFeedSamples].
  bool _starved = true;

  /// Runs after each playback setup completes. The manager re-applies the
  /// call audio session here (iOS voiceChat mode / speaker / Bluetooth
  /// options that the plugin's setCategory dropped).
  Future<void> Function()? afterPlaybackSetup;
  static const int _maxPlayBufferSamples = sampleRate * 2; // ~2 seconds

  final List<void Function(AudioHandlerOwner previous)> _releaseListeners = [];

  AudioHandlerOwner get owner => _owner;
  bool get isCapturing => _capturing;

  /// Claim of the current owner (0 = none). Read it right after
  /// [startCapture] / [startConference] to scope a later [stop] /
  /// [stopConference] to exactly that ownership.
  int get claim => _claim;

  /// Called after a release of the pipeline has finished on the device queue
  /// (with the owner that was released), e.g. so a conference whose resume was
  /// refused by a transient 1:1 owner can retry.
  void addReleaseListener(void Function(AudioHandlerOwner previous) l) =>
      _releaseListeners.add(l);
  void removeReleaseListener(void Function(AudioHandlerOwner previous) l) =>
      _releaseListeners.remove(l);

  /// Start capturing from microphone and sending to ToxAV for a 1:1 call with
  /// [friendNumber]. Returns the call's [claim], or null when refused (an AV
  /// conference owns the pipeline) or superseded before the mic opened.
  /// On desktop (e.g. macOS), tries [PcmCaptureDevice.startStream] even when
  /// permission is reported false so the system permission dialog can appear.
  Future<int?> startCapture(int friendNumber, ToxAVService avService) {
    if (_disposed || _owner == AudioHandlerOwner.conference) {
      AppLogger.warn(
        '[AudioHandler] startCapture refused: '
        '${_disposed ? 'disposed' : 'an AV conference owns the mic'}',
      );
      return Future<int?>.value();
    }
    if (_owner != AudioHandlerOwner.call || _callFriendNumber != friendNumber) {
      if (_owner != AudioHandlerOwner.none) unawaited(_release());
      _claim = ++_claimSeq;
      _owner = AudioHandlerOwner.call;
      _callFriendNumber = friendNumber;
    }
    final claim = _claim;
    return _enqueue(() async {
      await _openCapture(claim, (frame) {
        unawaited(
          avService.sendAudioFrame(
            friendNumber,
            frame,
            samplesPerFrame,
            channels,
            sampleRate,
          ),
        );
      });
      return claim == _claim ? claim : null;
    });
  }

  /// Take the pipeline for a legacy AV conference: captured frames go to
  /// [onCapturedFrame] (when [captureMicrophone]), and playback pulls from
  /// [playbackSource]. Refused while a 1:1 call owns the pipeline.
  Future<ConferenceAudioStart> startConference({
    required CapturedPcmFrameSink onCapturedFrame,
    required PcmPullSource playbackSource,
    required bool captureMicrophone,
  }) {
    if (_disposed || _owner == AudioHandlerOwner.call) {
      return Future<ConferenceAudioStart>.value(ConferenceAudioStart.refused);
    }
    if (_owner == AudioHandlerOwner.conference) unawaited(_release());
    _claim = ++_claimSeq;
    _owner = AudioHandlerOwner.conference;
    final claim = _claim;
    synchronized(_playBuffer, () => _playBuffer.clear());
    _playbackSource = playbackSource;
    return _enqueue(() async {
      if (claim != _claim) return ConferenceAudioStart.refused;
      if (!captureMicrophone) return ConferenceAudioStart.playbackOnly;
      final started = await _openCapture(claim, onCapturedFrame);
      if (claim != _claim) return ConferenceAudioStart.refused;
      return started
          ? ConferenceAudioStart.captureAndPlayback
          : ConferenceAudioStart.playbackOnly;
    });
  }

  /// A conference frame was queued in the pull source: make sure the device
  /// is pulling (FlutterPcmSound stops calling back once it drained to zero).
  void kickPlayback() {
    if (_owner != AudioHandlerOwner.conference) return;
    if (!CallMediaCapabilities.supportsAudioPlayback()) return;
    _ensurePlayback();
    _kick();
  }

  void _kick() {
    if (_starved && _playbackState == _PlaybackState.ready) _onFeedSamples(0);
  }

  /// Release the pipeline if (and only if) a conference owns it — and, when
  /// [claim] is given, only if that conference ownership is still current.
  Future<void> stopConference({int? claim}) {
    if (_owner != AudioHandlerOwner.conference) return Future<void>.value();
    if (claim != null && claim != _claim) return Future<void>.value();
    return _release();
  }

  /// Runs [op] after every previously requested device operation.
  Future<T> _enqueue<T>(Future<T> Function() op) {
    final result = _deviceOps.then((_) => op());
    _deviceOps = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace st) {
        AppLogger.warn('[AudioHandler] device operation failed: $e');
      },
    );
    return result;
  }

  /// Opens the microphone for [claim]; runs on the device queue. Bails (and
  /// closes a just-opened recorder) as soon as [claim] is no longer current.
  Future<bool> _openCapture(int claim, CapturedPcmFrameSink sink) async {
    if (claim != _claim) return false;
    if (_capturing) {
      _frameSink = sink;
      return true;
    }
    _zeroDataWarningLogged = false;
    _recorderTouched = true;
    // Still on the device queue: a claim change while the platform opens the
    // mic closes it again inside openCaptureStream, never the next owner's.
    final stream = await openCaptureStream(
      _capture,
      buildCaptureConfig(),
      isCurrent: () => claim == _claim,
    );
    if (stream == null) return false;
    _frameSink = sink;
    _capturing = true;
    _buffer.clear();
    _streamSub = stream.listen(
      (Uint8List data) => _onRecordData(data),
      onError: (Object e) {
        debugPrint('[AudioHandler] stream error: $e');
        AppLogger.log('[AudioHandler] stream error: $e');
      },
    );
    AppLogger.log('[AudioHandler] capture started (microphone stream active)');
    return true;
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
      _frameSink?.call(bytesToInt16(frame));
    }
  }

  /// Convert little-endian byte pairs to signed int16 PCM samples
  /// (-32768..32767).
  @visibleForTesting
  static Int16List bytesToInt16(List<int> bytes) {
    final bd = ByteData.sublistView(Uint8List.fromList(bytes));
    final out = Int16List(bytes.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    return out;
  }

  /// Called when ToxAV receives audio from the remote peer of a 1:1 call.
  /// Queues PCM for playback. Handles both mono (ch=1) and stereo (ch=2)
  /// input by downmixing to mono. Ignored while a conference owns playback.
  void onAudioReceived(int friendNumber, List<int> pcm, int sampleCount, int ch,
      int samplingRate) {
    if (pcm.isEmpty || sampleCount <= 0) return;
    // Only a live 1:1 call plays remote PCM: a conference owns the speaker,
    // and a late frame after teardown (no owner) must not set playback up
    // again (on iOS that would re-category the audio session).
    if (_owner != AudioHandlerOwner.call) return;
    // The ToxAV receive callback is global: a second caller's leg (e.g. one
    // about to be busy-rejected) must never reach this call's speaker.
    if (friendNumber != _callFriendNumber) return;
    // Same environment gate as capture, for the PLAYBACK half. `AudioQueue`'s
    // converter chain crashes the Simulator's AudioControl thread with SIGILL
    // inside `AudioConverterNewInternal` (measured 2026-08-16, crash report
    // Runner-2026-08-16-143603.ips), which killed the app AFTER the voice-call
    // cases had already passed and took the rest of `sweep_calls_misc` with it.
    // Dropping remote PCM on the floor there keeps the call state machine —
    // the thing under test — alive; real hardware is unaffected.
    if (!CallMediaCapabilities.supportsAudioPlayback()) return;
    _ensurePlayback();

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
    _kick();
  }

  /// Single-isolate marker for "this block touches a shared buffer that's
  /// also touched by the playback feed callback." Dart's single-threaded
  /// event loop means there's no actual cross-thread interleaving — but the
  /// PCM feed/drain pattern reads more clearly when the critical sections
  /// are visually delimited. Do **not** add real locking here without first
  /// converting the buffer to a typed-data circular and benchmarking; the
  /// audio path runs at 50Hz and any mutex contention shows up immediately.
  static void synchronized(Object lock, void Function() action) => action();

  /// Sets the speaker up (once per ownership) on the device queue, after any
  /// pending release of the previous owner's speaker; feeding starts once it
  /// is [_PlaybackState.ready].
  void _ensurePlayback() {
    if (_playbackState != _PlaybackState.released) return;
    if (_playbackRetryAt?.isAfter(DateTime.now()) ?? false) return;
    _playbackState = _PlaybackState.settingUp;
    _starved = true;
    final generation = _playbackGeneration;
    unawaited(
      _enqueue(() async {
        if (generation != _playbackGeneration) return;
        _playbackDeviceOpen = true;
        try {
          await _playback.setup(sampleRate: sampleRate, channelCount: channels);
        } catch (e) {
          AppLogger.warn('[AudioHandler] playback setup failed: $e');
          // Leave it RELEASED (an unconfigured device must not be fed, and
          // marking it ready meant nothing retried): the next frame retries.
          if (generation == _playbackGeneration) {
            _playbackState = _PlaybackState.released;
            _playbackRetryAt = DateTime.now().add(const Duration(seconds: 1));
          }
          return;
        }
        _playback.setFeedThreshold(sampleRate ~/ 20); // ~50 ms
        _playback.setFeedCallback(_onFeedSamples);
        // Released while setting up: the queued release closes the device.
        if (generation != _playbackGeneration) return;
        _playbackState = _PlaybackState.ready;
        _kick();
        final after = afterPlaybackSetup;
        if (after != null) {
          unawaited(
            after().catchError((Object e) {
              AppLogger.warn('[AudioHandler] after playback setup failed: $e');
            }),
          );
        }
      }),
    );
  }

  void _onFeedSamples(int remainingFrames) {
    // A callback from a device that is being released / not yet set up for
    // the current owner must not feed it.
    if (_playbackState != _PlaybackState.ready) return;
    const maxSamples = 2048;
    final source = _playbackSource;
    if (source != null) {
      _feedOrStarve(source.pull(maxSamples), remainingFrames);
      return;
    }
    Int16List? toFeed;
    synchronized(_playBuffer, () {
      if (_playBuffer.isNotEmpty) {
        final n =
            _playBuffer.length > maxSamples ? maxSamples : _playBuffer.length;
        toFeed = Int16List.fromList(_playBuffer.sublist(0, n));
        _playBuffer.removeRange(0, n);
      }
    });
    _feedOrStarve(toFeed, remainingFrames);
  }

  void _feedOrStarve(Int16List? samples, int remainingFrames) {
    if (samples != null && samples.isNotEmpty) {
      _starved = false;
      _playback.feed(samples);
    } else if (remainingFrames == 0) {
      // Drained with nothing to give: the plugin will not call back again
      // until something is fed, so the next frame must kick.
      _starved = true;
    }
  }

  /// Stop 1:1 call capture and playback. A no-op while a conference owns the
  /// pipeline (use [stopConference]); see the class comment. With [claim]
  /// (from [startCapture]) it only stops that very call.
  Future<void> stop({int? claim}) {
    if (_owner == AudioHandlerOwner.conference) return Future<void>.value();
    if (claim != null && claim != _claim) return Future<void>.value();
    return _release();
  }

  /// Release everything regardless of owner and refuse any later start
  /// (manager dispose). Starts queued before this are released by it.
  Future<void> dispose() {
    _disposed = true;
    return _release();
  }

  /// Drops the current ownership NOW (so nothing the old owner left behind can
  /// be mistaken for the next owner's), then closes the devices on the queue.
  Future<void> _release() {
    final previous = _owner;
    _owner = AudioHandlerOwner.none;
    _claim = 0;
    _callFriendNumber = null;
    // Stop delivering right away; the queued step awaits the cancellation.
    final cancelled = _streamSub?.cancel();
    _streamSub = null;
    _capturing = false;
    _frameSink = null;
    _playbackSource = null;
    _buffer.clear();
    synchronized(_playBuffer, () => _playBuffer.clear());
    _playbackState = _PlaybackState.released;
    _playbackGeneration++;
    _playbackRetryAt = null;
    _starved = true;
    return _enqueue(() async {
      await cancelled;
      if (_recorderTouched) {
        _recorderTouched = false;
        await stopCaptureQuietly(_capture);
      }
      if (_playbackDeviceOpen) {
        _playbackDeviceOpen = false;
        try {
          await _playback.release();
        } catch (e) {
          AppLogger.warn('[AudioHandler] playback release failed: $e');
        }
      }
      if (previous == AudioHandlerOwner.none) return;
      for (final listener in List.of(_releaseListeners)) {
        listener(previous);
      }
    });
  }
}
