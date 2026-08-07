import 'av_conference_session_bridge.dart';

typedef ConferenceAudioNativeCallbackInstaller =
    void Function(AvConferenceAudioFrameCallback? callback);

/// Owns one native conference callback while routing frames to group owners.
class ConferenceAudioCallbackRegistry {
  ConferenceAudioCallbackRegistry({
    required ConferenceAudioNativeCallbackInstaller installNativeCallback,
  }) : _installNativeCallback = installNativeCallback;

  final ConferenceAudioNativeCallbackInstaller _installNativeCallback;
  final Map<String, _ConferenceAudioRegistration> _registrations = {};

  bool register(
    String groupId,
    AvConferenceSessionOwner owner,
    AvConferenceAudioFrameCallback callback,
  ) {
    if (_registrations.containsKey(groupId)) {
      return false;
    }
    final wasEmpty = _registrations.isEmpty;
    _registrations[groupId] = _ConferenceAudioRegistration(owner, callback);
    if (wasEmpty) {
      _installNativeCallback(_dispatch);
    }
    return true;
  }

  bool unregister(String groupId, AvConferenceSessionOwner owner) {
    final registration = _registrations[groupId];
    if (registration == null || !identical(registration.owner, owner)) {
      return false;
    }
    _registrations.remove(groupId);
    if (_registrations.isEmpty) {
      _installNativeCallback(null);
    }
    return true;
  }

  bool isOwner(String groupId, AvConferenceSessionOwner owner) {
    return identical(_registrations[groupId]?.owner, owner);
  }

  void clear() {
    if (_registrations.isEmpty) return;
    _registrations.clear();
    _installNativeCallback(null);
  }

  void _dispatch(
    String groupId,
    int conferenceNumber,
    int peerNumber,
    List<int> pcm,
    int sampleCount,
    int channels,
    int sampleRate,
  ) {
    _registrations[groupId]?.callback.call(
      groupId,
      conferenceNumber,
      peerNumber,
      pcm,
      sampleCount,
      channels,
      sampleRate,
    );
  }
}

final class _ConferenceAudioRegistration {
  const _ConferenceAudioRegistration(this.owner, this.callback);

  final AvConferenceSessionOwner owner;
  final AvConferenceAudioFrameCallback callback;
}
