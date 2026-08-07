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

abstract interface class AvConferenceSessionBridge {
  Future<bool> enable({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required AvConferenceAudioFrameCallback onAudioFrame,
  });

  Future<bool> disable({
    required String groupId,
    required AvConferenceSessionOwner owner,
  });

  Future<bool> setMuted({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required bool muted,
  });

  void clearReceiveCallback({
    required String groupId,
    required AvConferenceSessionOwner owner,
  });
}
