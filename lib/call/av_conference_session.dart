/// Immutable state of one legacy AV conference session (see
/// `AvConferenceSessionController`).
library;

enum AvConferenceSessionLifecycle {
  idle,
  joining,
  active,
  disabled,
  failed,
  closing,
  left,
  disposed,
}

enum AvConferenceSessionFailure {
  join,
  mute,
  disable,

  /// The audio pipeline is taken by a 1:1 call.
  busy,

  /// Another AV conference already has the audio pipeline.
  busyOtherConference,
}

const Object _kFailureUnchanged = Object();

class AvConferenceSession {
  const AvConferenceSession({
    required this.groupId,
    required this.displayName,
    required this.lifecycle,
    required this.failure,
    required this.isMuted,
    required this.receivedFrameCount,
    this.isDeafened = false,
    this.micAvailable = true,
    this.isInterrupted = false,
  });

  final String groupId;
  final String displayName;
  final AvConferenceSessionLifecycle lifecycle;
  final AvConferenceSessionFailure? failure;
  /// Local microphone is NOT being sent to the conference.
  final bool isMuted;
  final int receivedFrameCount;

  /// The other participants are NOT being played.
  final bool isDeafened;

  /// False when the session joined listen-only (no microphone).
  final bool micAvailable;

  /// An OS audio interruption has suspended the media (still joined).
  final bool isInterrupted;

  AvConferenceSession copyWith({
    AvConferenceSessionLifecycle? lifecycle,
    Object? failure = _kFailureUnchanged,
    bool? isMuted,
    int? receivedFrameCount,
    bool? isDeafened,
    bool? micAvailable,
    bool? isInterrupted,
  }) {
    return AvConferenceSession(
      groupId: groupId,
      displayName: displayName,
      lifecycle: lifecycle ?? this.lifecycle,
      failure: identical(failure, _kFailureUnchanged)
          ? this.failure
          : failure as AvConferenceSessionFailure?,
      isMuted: isMuted ?? this.isMuted,
      receivedFrameCount: receivedFrameCount ?? this.receivedFrameCount,
      isDeafened: isDeafened ?? this.isDeafened,
      micAvailable: micAvailable ?? this.micAvailable,
      isInterrupted: isInterrupted ?? this.isInterrupted,
    );
  }
}
