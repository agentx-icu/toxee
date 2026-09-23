typedef AvConferenceAudioFrameCallback =
    void Function(
      String groupId,
      int conferenceNumber,
      int peerNumber,
      List<int> pcm,
      int sampleCount,
      int channels,
      int sampleRate,
    );

final class AvConferenceSessionOwner {
  AvConferenceSessionOwner();
}

/// Live media condition of a joined conference, pushed by the bridge after
/// [AvConferenceSessionBridge.enable] returned (e.g. an OS audio
/// interruption, or a resume that could not reopen the microphone).
enum AvConferenceMediaState {
  /// Microphone sent and participants played.
  full,

  /// Participants played; the microphone is unavailable.
  listenOnly,

  /// Suspended by an OS audio interruption (phone call, Siri, audio focus
  /// loss): nothing is sent or played until the OS hands audio back.
  interrupted,
}

typedef AvConferenceMediaStateCallback =
    void Function(AvConferenceMediaState state);

/// Outcome of [AvConferenceSessionBridge.enable].
enum AvConferenceEnableResult {
  /// Joined: microphone frames are sent and peers are played.
  enabled,

  /// Joined listen-only: the microphone could not be opened (permission
  /// denied, no capture backend on this platform, or the device failed).
  enabledReceiveOnly,

  /// The backend refused (no ToxAV, not an AV conference, duplicate owner).
  failed,

  /// The single audio pipeline is taken by a 1:1 call.
  busy,

  /// Another AV conference already has the microphone and speaker.
  busyOtherConference,
}

abstract interface class AvConferenceSessionBridge {
  Future<AvConferenceEnableResult> enable({
    required String groupId,
    required String displayName,
    required AvConferenceSessionOwner owner,
    required AvConferenceAudioFrameCallback onAudioFrame,
    AvConferenceMediaStateCallback? onMediaStateChanged,
  });

  Future<bool> disable({
    required String groupId,
    required AvConferenceSessionOwner owner,
  });

  /// Stop (true) or resume (false) SENDING the local microphone.
  Future<bool> setMicMuted({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required bool muted,
  });

  /// Stop (true) or resume (false) PLAYING the other participants.
  Future<bool> setDeafened({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required bool deafened,
  });

  void clearReceiveCallback({
    required String groupId,
    required AvConferenceSessionOwner owner,
  });
}
