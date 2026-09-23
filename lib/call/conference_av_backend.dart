import 'dart:async';

import 'package:tim2tox_dart/service/toxav_service.dart';

import 'av_conference_session_bridge.dart';

/// The slice of ToxAV the legacy AV conference media path needs.
abstract interface class ConferenceAvBackend {
  bool get isAvailable;
  Future<bool> enableConferenceAudio(String groupId);
  Future<bool> disableConferenceAudio(String groupId);

  /// Receive-side drop of the peers' audio (native `muted_av_conferences_`).
  Future<bool> muteConferenceAudio(String groupId, bool mute);
  Future<bool> sendConferenceAudioFrame(
    String groupId,
    List<int> pcm,
    int sampleCount,
    int channels,
    int samplingRate,
  );
  void setConferenceAudioReceiveCallback(
    AvConferenceAudioFrameCallback? callback,
  );
}

/// [ConferenceAvBackend] over the real [ToxAVService].
class ToxAvConferenceBackend implements ConferenceAvBackend {
  ToxAvConferenceBackend(this._av);

  final ToxAVService _av;

  @override
  bool get isAvailable => _av.isAvailable;

  @override
  Future<bool> enableConferenceAudio(String groupId) =>
      _av.enableConferenceAudio(groupId);

  @override
  Future<bool> disableConferenceAudio(String groupId) =>
      _av.disableConferenceAudio(groupId);

  @override
  Future<bool> muteConferenceAudio(String groupId, bool mute) =>
      _av.muteConferenceAudio(groupId, mute);

  @override
  Future<bool> sendConferenceAudioFrame(
    String groupId,
    List<int> pcm,
    int sampleCount,
    int channels,
    int samplingRate,
  ) => _av.sendConferenceAudioFrame(
    groupId,
    pcm,
    sampleCount,
    channels,
    samplingRate,
  );

  @override
  void setConferenceAudioReceiveCallback(
    AvConferenceAudioFrameCallback? callback,
  ) => _av.setConferenceAudioReceiveCallback(callback);
}

/// Platform side effects of a conference's media lifetime, supplied by
/// `CallServiceManager`: audio session, Android foreground elevation, and the
/// AV poll boost.
class ConferenceMediaHooks {
  const ConferenceMediaHooks({this.onMediaStarted, this.onMediaStopped});

  final Future<void> Function(String displayName)? onMediaStarted;
  final Future<void> Function()? onMediaStopped;
}

/// Bounded background retry of a native conference disable whose owner has
/// already gone (session page closed, join rolled back): the native group AV
/// (`toxav_groupchat_disable_av`) must not stay enabled just because one
/// attempt failed. One retry chain per group; [cancel] when the group is
/// re-joined or the bridge is disposed.
class ConferenceDisableRetrier {
  ConferenceDisableRetrier({List<Duration>? delays})
    : delays = delays ?? _defaultDelays;

  static const List<Duration> _defaultDelays = <Duration>[
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  final List<Duration> delays;
  final Map<String, Object> _chains = <String, Object>{};
  final Map<String, Timer> _timers = <String, Timer>{};

  bool isPending(String groupId) => _chains.containsKey(groupId);

  /// Retries [attempt] after each of [delays]; [onDone] gets the final
  /// outcome (true = disabled) unless the chain was cancelled first.
  void start(
    String groupId,
    Future<bool> Function() attempt,
    void Function(bool disabled) onDone,
  ) {
    cancel(groupId);
    if (delays.isEmpty) {
      onDone(false);
      return;
    }
    final chain = Object();
    _chains[groupId] = chain;
    Future<void> run(int next) async {
      bool disabled;
      try {
        disabled = await attempt();
      } catch (_) {
        disabled = false;
      }
      if (!identical(_chains[groupId], chain)) return;
      if (disabled || next >= delays.length) {
        _chains.remove(groupId);
        _timers.remove(groupId);
        onDone(disabled);
        return;
      }
      _timers[groupId] = Timer(delays[next], () => unawaited(run(next + 1)));
    }

    _timers[groupId] = Timer(delays.first, () => unawaited(run(1)));
  }

  void cancel(String groupId) {
    _chains.remove(groupId);
    _timers.remove(groupId)?.cancel();
  }

  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _chains.clear();
  }
}
