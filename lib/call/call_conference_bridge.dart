import 'dart:async';
import 'dart:typed_data';

import '../util/logger.dart';
import 'audio_handler.dart';
import 'av_conference_session_bridge.dart';
import 'conference_audio_callback_registry.dart';
import 'conference_audio_mixer.dart';
import 'conference_av_backend.dart';

export 'conference_av_backend.dart';

part 'call_conference_media.dart';

/// Bridges [AvConferenceSessionController] to ToxAV + the shared audio
/// pipeline: joining a legacy AV conference enables the native group AV,
/// opens the microphone into `toxav_group_send_audio`, and mixes the peers'
/// decoded frames into the speaker.
///
/// There is ONE microphone ([AudioHandler]), so at most one conference has
/// media at a time and never while a 1:1 call is ringing or connected
/// ([AvConferenceEnableResult.busy]); symmetrically the manager refuses 1:1
/// calls while [hasActiveSession].
///
/// Lifecycle model: every media transition — the commit half of [enable],
/// [disable], a released callback's stop, [suspendForInterruption] and
/// [resumeAfterInterruption] — runs on ONE serial queue ([_serialize]), so a
/// stop can never interleave with the next start. [dispose] is the exception:
/// it must not wait behind a queued operation (logout), so it invalidates
/// synchronously ([_disposed]) and every queued step re-checks that after
/// each await. Native group AV stays owned by the registry until a
/// `disableConferenceAudio` actually succeeds (see [clearReceiveCallback]).
class CallConferenceBridge implements AvConferenceSessionBridge {
  CallConferenceBridge({
    required Future<ConferenceAvBackend?> Function() resolveBackend,
    required AudioHandler audio,
    required bool Function() isOneToOneCallActive,
    required Future<bool> Function() requestMicrophone,
    ConferenceMediaHooks hooks = const ConferenceMediaHooks(),
    ConferenceAudioMixer Function()? createMixer,
    List<Duration>? disableRetryDelays,
  }) : _resolveBackend = resolveBackend,
       _audio = audio,
       _isOneToOneCallActive = isOneToOneCallActive,
       _requestMicrophone = requestMicrophone,
       _hooks = hooks,
       _createMixer = createMixer ?? ConferenceAudioMixer.new,
       _retrier = ConferenceDisableRetrier(delays: disableRetryDelays) {
    _audio.addReleaseListener(_onAudioReleased);
  }

  final Future<ConferenceAvBackend?> Function() _resolveBackend;
  final AudioHandler _audio;
  final bool Function() _isOneToOneCallActive;
  final Future<bool> Function() _requestMicrophone;
  final ConferenceMediaHooks _hooks;
  final ConferenceAudioMixer Function() _createMixer;
  final ConferenceDisableRetrier _retrier;

  /// Registry owner for groups whose session owner gave up while the native
  /// disable still has to succeed ([clearReceiveCallback]).
  final AvConferenceSessionOwner _orphanOwner = AvConferenceSessionOwner();

  ConferenceAvBackend? _backend;
  _ConferenceMedia? _media;
  Future<void> _lifecycle = Future<void>.value();

  /// Set by [dispose] (logout): no platform hooks may run after it, and an
  /// in-flight [enable] must not bring media back.
  bool _disposed = false;
  Future<void>? _disposing;
  late final ConferenceAudioCallbackRegistry _registry =
      ConferenceAudioCallbackRegistry(
        installNativeCallback: (callback) {
          _backend?.setConferenceAudioReceiveCallback(callback);
        },
      );

  /// True while a conference owns the audio pipeline (poll boost, busy).
  bool get hasActiveSession => _media != null;

  /// TEST SEAM: the owner's platform hooks, so a test can drive a teardown's
  /// hook ordering without a native backend. (Not `@visibleForTesting`: it is
  /// re-exported by `CallServiceManager`'s own test seam, which lives in lib.)
  ConferenceMediaHooks get debugHooks => _hooks;

  /// Group whose media is live, for diagnostics.
  String? get activeGroupId => _media?.groupId;

  /// Frames forwarded to ToxAV since the session started (observability).
  int get sentFrameCount => _sentFrameCount;
  int _sentFrameCount = 0;

  AvConferenceEnableResult? _busyFor(String groupId) {
    if (_isOneToOneCallActive()) return AvConferenceEnableResult.busy;
    final media = _media;
    if (media != null && media.groupId != groupId) {
      return AvConferenceEnableResult.busyOtherConference;
    }
    return null;
  }

  @override
  Future<AvConferenceEnableResult> enable({
    required String groupId,
    required String displayName,
    required AvConferenceSessionOwner owner,
    required AvConferenceAudioFrameCallback onAudioFrame,
    AvConferenceMediaStateCallback? onMediaStateChanged,
  }) async {
    if (_disposed) return AvConferenceEnableResult.failed;
    final busyBefore = _busyFor(groupId);
    if (busyBefore != null) return busyBefore;
    final backend = _backend ??= await _resolveBackend();
    if (backend == null || !backend.isAvailable) {
      return AvConferenceEnableResult.failed;
    }
    // Ask before touching the native side: the OS dialog can take a while
    // and nothing should be flowing while it is up. Deliberately OUTSIDE the
    // lifecycle queue: a pending OS prompt must not block other transitions.
    final micGranted = await _requestMicrophone();
    return _serialize(
      () => _commitEnable(
        backend,
        groupId: groupId,
        displayName: displayName,
        owner: owner,
        micGranted: micGranted,
        onAudioFrame: onAudioFrame,
        onMediaStateChanged: onMediaStateChanged,
      ),
    );
  }

  /// Runs [op] after every previously requested lifecycle transition.
  Future<T> _serialize<T>(Future<T> Function() op) {
    final result = _lifecycle.then((_) => op());
    _lifecycle = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace st) {
        AppLogger.warn('[CallConferenceBridge] lifecycle step failed: $e');
      },
    );
    return result;
  }

  Future<AvConferenceEnableResult> _commitEnable(
    ConferenceAvBackend backend, {
    required String groupId,
    required String displayName,
    required AvConferenceSessionOwner owner,
    required bool micGranted,
    required AvConferenceAudioFrameCallback onAudioFrame,
    AvConferenceMediaStateCallback? onMediaStateChanged,
  }) async {
    if (_disposed) return AvConferenceEnableResult.failed;
    final busyAfterPrompt = _busyFor(groupId);
    if (busyAfterPrompt != null) return busyAfterPrompt;
    // Re-join while the native side is still enabled: from an abandoned
    // session (adopt it, its disable retry is moot) or from this very owner
    // after a failed disable (re-register below).
    if (_registry.isOwner(groupId, _orphanOwner)) {
      _retrier.cancel(groupId);
      _registry.unregister(groupId, _orphanOwner);
    } else if (_registry.isOwner(groupId, owner)) {
      _registry.unregister(groupId, owner);
    }
    final media = _ConferenceMedia(
      groupId,
      displayName,
      owner,
      _createMixer(),
      micWanted: micGranted,
      onStateChanged: onMediaStateChanged,
    );
    final registered = _registry.register(groupId, owner, (
      gid,
      conferenceNumber,
      peerNumber,
      pcm,
      sampleCount,
      channels,
      sampleRate,
    ) {
      _onFrame(media, peerNumber, pcm, sampleCount, channels, sampleRate);
      onAudioFrame(
        gid,
        conferenceNumber,
        peerNumber,
        pcm,
        sampleCount,
        channels,
        sampleRate,
      );
    });
    if (!registered) return AvConferenceEnableResult.failed;
    var enabled = false;
    try {
      enabled = await backend.enableConferenceAudio(groupId);
    } finally {
      if (!enabled) _registry.unregister(groupId, owner);
    }
    if (!enabled) return AvConferenceEnableResult.failed;
    // dispose() already disabled every registered group natively; only undo
    // what it did not see.
    if (_disposed) {
      if (_registry.isOwner(groupId, owner)) {
        await _releaseNative(backend, groupId, owner);
      }
      return AvConferenceEnableResult.failed;
    }
    if (_media != null || _isOneToOneCallActive()) {
      // Lost a race with another conference / an answered 1:1 call.
      await _releaseNative(backend, groupId, owner);
      return _media != null
          ? AvConferenceEnableResult.busyOtherConference
          : AvConferenceEnableResult.busy;
    }
    _media = media;
    _sentFrameCount = 0;
    await _runHook(() => _hooks.onMediaStarted?.call(displayName));
    // Checked right before starting audio: nothing may reopen the mic after
    // logout (dispose stopped `media` and disabled the group natively).
    if (_disposed || media.stopped) return AvConferenceEnableResult.failed;
    final start = await _startAudio(backend, media);
    if (_disposed || media.stopped) {
      // Torn down (logout) while the pipeline was starting: release exactly
      // this ownership; a newer one is untouched.
      await _stopAudioOf(media);
      return AvConferenceEnableResult.failed;
    }
    if (start == ConferenceAudioStart.refused) {
      await _stopMedia(media);
      await _releaseNative(backend, groupId, owner);
      return AvConferenceEnableResult.busy;
    }
    AppLogger.info(
      '[CallConferenceBridge] conference media started capture=${start.name}',
    );
    media.state = start == ConferenceAudioStart.captureAndPlayback
        ? AvConferenceMediaState.full
        : AvConferenceMediaState.listenOnly;
    return start == ConferenceAudioStart.captureAndPlayback
        ? AvConferenceEnableResult.enabled
        : AvConferenceEnableResult.enabledReceiveOnly;
  }

  void _sendCaptured(
    ConferenceAvBackend backend,
    _ConferenceMedia media,
    Int16List frame,
  ) {
    if (media.silent || media.micMuted || !identical(_media, media)) return;
    _sentFrameCount++;
    unawaited(
      backend.sendConferenceAudioFrame(
        media.groupId,
        frame,
        AudioHandler.samplesPerFrame,
        AudioHandler.channels,
        AudioHandler.sampleRate,
      ),
    );
  }

  void _onFrame(
    _ConferenceMedia media,
    int peerNumber,
    List<int> pcm,
    int sampleCount,
    int channels,
    int sampleRate,
  ) {
    if (media.silent || media.deafened || !identical(_media, media)) return;
    media.mixer.push(
      peerNumber: peerNumber,
      pcm: pcm,
      sampleCount: sampleCount,
      channels: channels,
      sampleRate: sampleRate,
    );
    _audio.kickPlayback();
  }

  /// Stops local media, then disables the group natively. The owner keeps
  /// the native ownership (registry entry) when that fails, so it can retry —
  /// or hand it over with [clearReceiveCallback].
  @override
  Future<bool> disable({
    required String groupId,
    required AvConferenceSessionOwner owner,
  }) {
    return _serialize(() async {
      if (_disposed || !_registry.isOwner(groupId, owner)) return false;
      // Local media first and unconditionally: whatever the native side says,
      // the microphone must never outlive the session UI.
      final media = _media;
      if (media != null && identical(media.owner, owner)) {
        await _stopMedia(media);
      }
      final backend = _backend;
      if (backend == null) return true;
      if (!backend.isAvailable) return false;
      return _disableNative(backend, groupId, owner);
    });
  }


  @override
  Future<bool> setMicMuted({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required bool muted,
  }) async {
    final media = _media;
    if (!_registry.isOwner(groupId, owner) ||
        media == null ||
        !identical(media.owner, owner)) {
      return false;
    }
    media.micMuted = muted;
    return true;
  }

  @override
  Future<bool> setDeafened({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required bool deafened,
  }) async {
    final media = _media;
    final backend = _backend;
    if (!_registry.isOwner(groupId, owner) ||
        media == null ||
        !identical(media.owner, owner) ||
        backend == null) {
      return false;
    }
    // Native mute drops frames before the FFI copy; the Dart flag covers
    // frames already queued in the mixer.
    final applied = await backend.muteConferenceAudio(groupId, deafened);
    if (!applied) return false;
    media.deafened = deafened;
    if (deafened) media.mixer.clear();
    return true;
  }

  /// The owner is done with [groupId]: frames stop reaching it now, its media
  /// is stopped on the lifecycle queue (so the stop and its platform hook run
  /// before any re-join's start, and only ever touch THIS media), and a group
  /// whose native disable has not succeeded is adopted for background retry
  /// instead of being forgotten while still enabled natively.
  @override
  void clearReceiveCallback({
    required String groupId,
    required AvConferenceSessionOwner owner,
  }) {
    _adoptOrphan(groupId, owner);
    _registry.unregister(groupId, owner);
    final media = _media;
    if (media == null || !identical(media.owner, owner)) return;
    media.releasing = true;
    media.mixer.clear();
    unawaited(_serialize(() => _stopMedia(media)));
  }

  Future<void> _stopMedia(_ConferenceMedia media) async {
    if (media.stopped) return;
    media.stopped = true;
    media.mixer.clear();
    if (identical(_media, media)) _media = null;
    await _stopAudioOf(media);
    // Not after dispose: the manager then does the platform teardown itself
    // (see CallServiceManager.dispose).
    await _runHook(() => _hooks.onMediaStopped?.call());
    AppLogger.info('[CallConferenceBridge] conference media stopped');
  }

  bool _isLive(_ConferenceMedia media) =>
      !_disposed &&
      !media.stopped &&
      !media.releasing &&
      identical(_media, media);

  /// OS audio interruption began (iOS AVAudioSession interruption, Android
  /// audio-focus loss): release the mic and speaker, keep the conference
  /// joined natively so [resumeAfterInterruption] can pick it back up.
  Future<void> suspendForInterruption() => _serialize(() async {
    final media = _media;
    if (media == null || !_isLive(media)) return;
    // The OS took audio again: a resume waiting for a 1:1 owner is moot.
    media.resumePending = false;
    if (media.suspended) return;
    media.suspended = true;
    media.mixer.clear();
    media.report(AvConferenceMediaState.interrupted);
    await _stopAudioOf(media);
  });

  /// The OS handed audio back: re-activate the session and reopen capture
  /// and playback; listen-only when the mic cannot be reopened.
  Future<void> resumeAfterInterruption() => _serialize(_resume);

  Future<void> _resume() async {
    final media = _media;
    final backend = _backend;
    if (media == null || backend == null || !_isLive(media)) return;
    if (!media.suspended) return;
    media.resumePending = false;
    await _runHook(() => _hooks.onMediaStarted?.call(media.displayName));
    if (!_isLive(media)) return;
    // Stays `suspended` (nothing sent/played) until the pipeline is back.
    final start = await _startAudio(backend, media);
    if (!_isLive(media)) {
      await _stopAudioOf(media);
      return;
    }
    if (start == ConferenceAudioStart.refused) {
      // A 1:1 call holds the pipeline right now: retry once it lets go
      // (_onAudioReleased) instead of staying silent forever.
      media.resumePending = true;
      media.report(AvConferenceMediaState.interrupted);
      return;
    }
    media.suspended = false;
    media.report(
      start == ConferenceAudioStart.captureAndPlayback
          ? AvConferenceMediaState.full
          : AvConferenceMediaState.listenOnly,
    );
  }

  void _onAudioReleased(AudioHandlerOwner previous) {
    final media = _media;
    if (previous != AudioHandlerOwner.call || media == null) return;
    if (!media.resumePending || !_isLive(media)) return;
    unawaited(_serialize(_resume));
  }

  Future<void> _runHook(Future<void>? Function() hook) async {
    if (_disposed) return;
    try {
      await hook();
    } catch (e, st) {
      AppLogger.warn('[CallConferenceBridge] media hook failed: $e\n$st');
    }
  }

  /// Manager teardown (logout). Does not queue behind in-flight transitions:
  /// invalidates them, then — synchronously, before the manager shuts ToxAV
  /// down — disables every natively enabled group (live, abandoned or still
  /// joining), and stops this bridge's audio ownership. Platform hooks are
  /// NOT run; the manager restores the platform state itself.
  Future<void> dispose() {
    final existing = _disposing;
    if (existing != null) return existing;
    _disposed = true;
    _audio.removeReleaseListener(_onAudioReleased);
    _retrier.cancelAll();
    final pending = _disableAllNativeNow().toList();
    _registry.clear();
    final media = _media;
    if (media != null) {
      media.stopped = true;
      media.mixer.clear();
      _media = null;
      pending.add(_stopAudioOf(media));
    }
    return _disposing = Future.wait(pending).then<void>((_) {});
  }
}
