part of 'call_conference_bridge.dart';

// The per-conference media object and the native-ownership helpers of
// [CallConferenceBridge], split out along the "who owns the native group AV"
// seam: a group stays registered (owned) until `disableConferenceAudio`
// actually succeeds, whether its owner is a live session or the bridge itself
// retrying for an abandoned one.

/// The live media of the one conference that owns the audio pipeline.
class _ConferenceMedia implements PcmPullSource {
  _ConferenceMedia(
    this.groupId,
    this.displayName,
    this.owner,
    this.mixer, {
    required this.micWanted,
    this.onStateChanged,
  });

  final String groupId;
  final String displayName;
  final AvConferenceSessionOwner owner;
  final ConferenceAudioMixer mixer;

  /// Microphone permission was granted at join (resume retries capture).
  final bool micWanted;
  final AvConferenceMediaStateCallback? onStateChanged;
  bool micMuted = false;
  bool deafened = false;
  bool stopped = false;

  /// Its owner released the callback; the queued stop has not run yet. No
  /// frame is sent or played meanwhile.
  bool releasing = false;
  bool suspended = false;

  /// A resume was refused because a 1:1 call held the pipeline: retried when
  /// that owner releases it (see `_onAudioReleased`).
  bool resumePending = false;

  /// [AudioHandler.claim] of this media's pipeline ownership, so its stop can
  /// never release a newer session's microphone.
  int? audioClaim;
  AvConferenceMediaState state = AvConferenceMediaState.full;

  bool get silent => stopped || releasing || suspended;

  void report(AvConferenceMediaState next) {
    if (state == next) return;
    state = next;
    onStateChanged?.call(next);
  }

  @override
  Int16List pull(int maxSamples) =>
      deafened ? Int16List(0) : mixer.pull(maxSamples);
}

void _dropFrame(
  String groupId,
  int conferenceNumber,
  int peerNumber,
  List<int> pcm,
  int sampleCount,
  int channels,
  int sampleRate,
) {}

extension _ConferenceNativeOwnership on CallConferenceBridge {
  Future<ConferenceAudioStart> _startAudio(
    ConferenceAvBackend backend,
    _ConferenceMedia media,
  ) {
    final start = _audio.startConference(
      onCapturedFrame: (frame) => _sendCaptured(backend, media, frame),
      playbackSource: media,
      captureMicrophone: media.micWanted,
    );
    // Claimed synchronously by startConference (null when refused).
    media.audioClaim = _audio.owner == AudioHandlerOwner.conference
        ? _audio.claim
        : null;
    return start;
  }

  /// Releases exactly [media]'s pipeline ownership (none when its start was
  /// refused), never a newer owner's.
  Future<void> _stopAudioOf(_ConferenceMedia media) {
    final claim = media.audioClaim;
    media.audioClaim = null;
    if (claim == null) return Future<void>.value();
    return _audio.stopConference(claim: claim);
  }

  Future<bool> _disableNative(
    ConferenceAvBackend backend,
    String groupId,
    AvConferenceSessionOwner owner,
  ) async {
    bool disabled;
    try {
      disabled = await backend.disableConferenceAudio(groupId);
    } catch (e) {
      AppLogger.warn('[CallConferenceBridge] native disable threw: $e');
      disabled = false;
    }
    if (disabled) _registry.unregister(groupId, owner);
    return disabled;
  }

  /// Native disable for a group nobody in the UI owns any more: on failure the
  /// bridge keeps the native ownership and retries (bounded) in background.
  Future<void> _releaseNative(
    ConferenceAvBackend backend,
    String groupId,
    AvConferenceSessionOwner owner,
  ) async {
    if (await _disableNative(backend, groupId, owner)) return;
    _adoptOrphan(groupId, owner);
  }

  /// [owner] gave up on [groupId] but the native group AV is still enabled:
  /// keep it registered (frames dropped) under `_orphanOwner` and retry the
  /// disable with bounded backoff. A re-join adopts it; dispose disables it.
  void _adoptOrphan(String groupId, AvConferenceSessionOwner owner) {
    final backend = _backend;
    if (_disposed || backend == null) return;
    if (!_registry.transfer(groupId, owner, _orphanOwner, _dropFrame)) return;
    AppLogger.warn(
      '[CallConferenceBridge] native disable failed; retrying in background',
    );
    _retrier.start(
      groupId,
      () => _disposed
          ? Future<bool>.value(false)
          : _disableNative(backend, groupId, _orphanOwner),
      (disabled) {
        if (!disabled) {
          AppLogger.error(
            '[CallConferenceBridge] native conference disable still failing '
            'after retries; kept for re-join / logout',
          );
        }
      },
    );
  }

  /// Logout: one synchronous native disable per registered group (live,
  /// joining or abandoned). Must be dispatched before ToxAV is shut down.
  List<Future<void>> _disableAllNativeNow() {
    final backend = _backend;
    if (backend == null) return const <Future<void>>[];
    return <Future<void>>[
      for (final groupId in _registry.groupIds)
        Future<bool>.sync(() => backend.disableConferenceAudio(groupId))
            .then<void>((disabled) {
              if (!disabled) {
                AppLogger.warn(
                  '[CallConferenceBridge] native disable at logout failed',
                );
              }
            })
            .catchError((Object e) {
              AppLogger.warn('[CallConferenceBridge] logout disable: $e');
            }),
    ];
  }
}
