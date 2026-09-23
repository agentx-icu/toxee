import 'package:flutter/foundation.dart';

import 'av_conference_session.dart';
import 'av_conference_session_bridge.dart';

export 'av_conference_session.dart';

class AvConferenceSessionController extends ChangeNotifier {
  AvConferenceSessionController({
    required String groupId,
    required String displayName,
    required AvConferenceSessionBridge bridge,
  }) : _bridge = bridge,
       _session = AvConferenceSession(
         groupId: groupId,
         displayName: displayName,
         lifecycle: AvConferenceSessionLifecycle.idle,
         failure: null,
         isMuted: false,
         receivedFrameCount: 0,
       );

  final AvConferenceSessionBridge _bridge;
  final AvConferenceSessionOwner _owner = AvConferenceSessionOwner();
  AvConferenceSession _session;
  bool _disposed = false;
  bool _disposeRequested = false;
  bool _ownsBackend = false;
  int _joinGeneration = 0;

  /// Latest bridge media state pushed while still joining (an interruption
  /// can land between the native enable and `active`); applied on activation.
  AvConferenceMediaState? _joinMediaState;
  Future<bool>? _joining;
  Future<bool>? _disabling;
  Future<void>? _closing;

  AvConferenceSession get session => _session;

  Future<bool> join() async {
    if (_session.lifecycle == AvConferenceSessionLifecycle.disposed ||
        _closing != null ||
        _disabling != null) {
      return false;
    }
    if (_session.lifecycle == AvConferenceSessionLifecycle.active) {
      return true;
    }
    final inFlight = _joining;
    if (inFlight != null) {
      return inFlight;
    }

    _disposeRequested = false;
    final generation = ++_joinGeneration;
    final future = _doJoin(generation);
    _joining = future;
    try {
      return await future;
    } finally {
      if (identical(_joining, future)) {
        _joining = null;
      }
    }
  }

  Future<bool> _doJoin(int generation) async {
    _joinMediaState = null;
    _setSession(
      _session.copyWith(
        lifecycle: AvConferenceSessionLifecycle.joining,
        failure: null,
      ),
    );
    final AvConferenceEnableResult result;
    try {
      result = await _bridge.enable(
        groupId: _session.groupId,
        displayName: _session.displayName,
        owner: _owner,
        onAudioFrame: _handleAudioFrame,
        onMediaStateChanged: _handleMediaState,
      );
    } catch (_) {
      if (_isJoinCurrent(generation)) {
        _setSession(
          _session.copyWith(
            lifecycle: AvConferenceSessionLifecycle.failed,
            failure: AvConferenceSessionFailure.join,
          ),
        );
      }
      return false;
    }
    final enabled =
        result == AvConferenceEnableResult.enabled ||
        result == AvConferenceEnableResult.enabledReceiveOnly;
    if (enabled) {
      _ownsBackend = true;
    }
    if (!_isJoinCurrent(generation)) {
      if (enabled) {
        await _rollbackEnabledJoin();
      }
      return false;
    }
    if (!enabled) {
      _setSession(
        _session.copyWith(
          lifecycle: AvConferenceSessionLifecycle.failed,
          failure: switch (result) {
            AvConferenceEnableResult.busy => AvConferenceSessionFailure.busy,
            AvConferenceEnableResult.busyOtherConference =>
              AvConferenceSessionFailure.busyOtherConference,
            _ => AvConferenceSessionFailure.join,
          },
        ),
      );
      return false;
    }
    _setSession(
      _session.copyWith(
        micAvailable: result == AvConferenceEnableResult.enabled,
        isInterrupted: false,
      ),
    );
    if (_session.isMuted || _session.isDeafened) {
      final bool muted;
      try {
        muted =
            (!_session.isMuted ||
                await _bridge.setMicMuted(
                  groupId: _session.groupId,
                  owner: _owner,
                  muted: true,
                )) &&
            (!_session.isDeafened ||
                await _bridge.setDeafened(
                  groupId: _session.groupId,
                  owner: _owner,
                  deafened: true,
                ));
      } catch (_) {
        await _rollbackEnabledJoin();
        if (_isJoinCurrent(generation)) {
          _setSession(
            _session.copyWith(
              lifecycle: AvConferenceSessionLifecycle.failed,
              failure: AvConferenceSessionFailure.mute,
            ),
          );
        }
        return false;
      }
      if (!_isJoinCurrent(generation)) {
        await _rollbackEnabledJoin();
        return false;
      }
      if (!muted) {
        await _rollbackEnabledJoin();
        if (_isJoinCurrent(generation)) {
          _setSession(
            _session.copyWith(
              lifecycle: AvConferenceSessionLifecycle.failed,
              failure: AvConferenceSessionFailure.mute,
            ),
          );
        }
        return false;
      }
    }
    if (!_isJoinCurrent(generation)) {
      await _rollbackEnabledJoin();
      return false;
    }
    _setSession(
      _session.copyWith(
        lifecycle: AvConferenceSessionLifecycle.active,
        failure: null,
      ),
    );
    final pushed = _joinMediaState;
    _joinMediaState = null;
    if (pushed != null) _handleMediaState(pushed);
    return true;
  }

  Future<void> leave() {
    return _close(markDisposed: false);
  }

  Future<void> disposeSession() {
    return _close(markDisposed: true);
  }

  Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      return join();
    }
    if (_session.lifecycle == AvConferenceSessionLifecycle.disposed ||
        _session.lifecycle == AvConferenceSessionLifecycle.left) {
      return false;
    }
    if (_session.lifecycle == AvConferenceSessionLifecycle.disabled) {
      return true;
    }
    if (_closing != null) {
      return false;
    }
    final inFlight = _disabling;
    if (inFlight != null) {
      return inFlight;
    }
    _joinGeneration += 1;
    final future = _doDisable();
    _disabling = future;
    try {
      return await future;
    } finally {
      if (identical(_disabling, future)) {
        _disabling = null;
      }
    }
  }

  Future<bool> _doDisable() async {
    final joining = _joining;
    if (joining != null) {
      await joining;
    }
    if (_ownsBackend) {
      var disabled = false;
      try {
        disabled = await _bridge.disable(
          groupId: _session.groupId,
          owner: _owner,
        );
      } catch (_) {
        disabled = false;
      }
      // A failed native disable keeps ownership + registration so a retry (or
      // the final leave handing it to the bridge) can still disable natively.
      if (disabled) {
        _ownsBackend = false;
        _releaseReceiveCallback();
      }
      if (!disabled) {
        _setSession(
          _session.copyWith(
            lifecycle: AvConferenceSessionLifecycle.failed,
            failure: AvConferenceSessionFailure.disable,
          ),
        );
        return false;
      }
    }
    _setSession(
      _session.copyWith(
        lifecycle: AvConferenceSessionLifecycle.disabled,
        failure: null,
      ),
    );
    return true;
  }

  Future<bool> setMuted(bool muted) async {
    if (_session.lifecycle == AvConferenceSessionLifecycle.disposed ||
        _session.lifecycle == AvConferenceSessionLifecycle.left) {
      return false;
    }
    if (_session.isMuted == muted) {
      return true;
    }
    if (_session.lifecycle != AvConferenceSessionLifecycle.active) {
      _setSession(_session.copyWith(isMuted: muted));
      return true;
    }
    final bool applied;
    try {
      applied = await _bridge.setMicMuted(
        groupId: _session.groupId,
        owner: _owner,
        muted: muted,
      );
    } catch (_) {
      await _teardownFailedActiveSession();
      _setSession(
        _session.copyWith(
          lifecycle: AvConferenceSessionLifecycle.failed,
          failure: AvConferenceSessionFailure.mute,
        ),
      );
      return false;
    }
    if (!applied) {
      await _teardownFailedActiveSession();
      _setSession(
        _session.copyWith(
          lifecycle: AvConferenceSessionLifecycle.failed,
          failure: AvConferenceSessionFailure.mute,
        ),
      );
      return false;
    }
    _setSession(_session.copyWith(isMuted: muted, failure: null));
    return true;
  }

  Future<bool> toggleMuted() {
    return setMuted(!_session.isMuted);
  }

  /// Stop / resume PLAYING the other participants. Unlike [setMuted] a
  /// failure here leaves the session up: the mic path is unaffected.
  Future<bool> setDeafened(bool deafened) async {
    if (_session.lifecycle == AvConferenceSessionLifecycle.disposed ||
        _session.lifecycle == AvConferenceSessionLifecycle.left) {
      return false;
    }
    if (_session.isDeafened == deafened) {
      return true;
    }
    if (_session.lifecycle != AvConferenceSessionLifecycle.active) {
      _setSession(_session.copyWith(isDeafened: deafened));
      return true;
    }
    bool applied;
    try {
      applied = await _bridge.setDeafened(
        groupId: _session.groupId,
        owner: _owner,
        deafened: deafened,
      );
    } catch (_) {
      applied = false;
    }
    if (applied) {
      _setSession(_session.copyWith(isDeafened: deafened));
    }
    return applied;
  }

  Future<bool> toggleDeafened() {
    return setDeafened(!_session.isDeafened);
  }

  void _handleMediaState(AvConferenceMediaState state) {
    if (_session.lifecycle == AvConferenceSessionLifecycle.joining) {
      _joinMediaState = state;
      return;
    }
    if (_session.lifecycle != AvConferenceSessionLifecycle.active) return;
    _setSession(
      _session.copyWith(
        isInterrupted: state == AvConferenceMediaState.interrupted,
        micAvailable: state == AvConferenceMediaState.interrupted
            ? null
            : state == AvConferenceMediaState.full,
      ),
    );
  }

  void _handleAudioFrame(
    String groupId,
    int conferenceNumber,
    int peerNumber,
    List<int> pcm,
    int sampleCount,
    int channels,
    int sampleRate,
  ) {
    if (groupId != _session.groupId ||
        _session.lifecycle != AvConferenceSessionLifecycle.active) {
      return;
    }
    _setSession(
      _session.copyWith(receivedFrameCount: _session.receivedFrameCount + 1),
    );
  }

  Future<void> _close({required bool markDisposed}) {
    _joinGeneration += 1;
    if (markDisposed) {
      _disposeRequested = true;
    }
    final inFlight = _closing;
    if (inFlight != null) {
      return inFlight;
    }
    if (_session.lifecycle == AvConferenceSessionLifecycle.disposed) {
      return Future<void>.value();
    }
    if (_session.lifecycle == AvConferenceSessionLifecycle.left) {
      if (_disposeRequested) {
        _setSession(
          _session.copyWith(
            lifecycle: AvConferenceSessionLifecycle.disposed,
            failure: null,
          ),
        );
      }
      return Future<void>.value();
    }

    _setSession(
      _session.copyWith(
        lifecycle: AvConferenceSessionLifecycle.closing,
        failure: null,
      ),
    );

    final future = _doClose();
    _closing = future;
    return future.whenComplete(() {
      _closing = null;
    });
  }

  Future<void> _doClose() async {
    final joining = _joining;
    if (joining != null) {
      await joining;
    }
    final disabling = _disabling;
    if (disabling != null) {
      await disabling;
    }
    var disableFailed = false;
    if (_ownsBackend) {
      try {
        final disabled = await _bridge.disable(
          groupId: _session.groupId,
          owner: _owner,
        );
        disableFailed = !disabled;
      } catch (_) {
        disableFailed = true;
      } finally {
        // Final release: on a failed disable the bridge adopts the still
        // enabled group and keeps retrying (clearReceiveCallback).
        _ownsBackend = false;
        _releaseReceiveCallback();
      }
    }
    _setSession(
      _session.copyWith(
        lifecycle: disableFailed
            ? AvConferenceSessionLifecycle.failed
            : _disposeRequested
            ? AvConferenceSessionLifecycle.disposed
            : AvConferenceSessionLifecycle.left,
        failure: disableFailed ? AvConferenceSessionFailure.disable : null,
      ),
    );
  }

  bool _isJoinCurrent(int generation) {
    return generation == _joinGeneration &&
        _closing == null &&
        _disabling == null &&
        !_disposeRequested &&
        _session.lifecycle == AvConferenceSessionLifecycle.joining;
  }

  Future<void> _rollbackEnabledJoin() async {
    if (!_ownsBackend) return;
    try {
      await _bridge.disable(groupId: _session.groupId, owner: _owner);
    } catch (_) {
    } finally {
      _ownsBackend = false;
      _releaseReceiveCallback();
    }
  }

  /// Same hand-off as [_rollbackEnabledJoin]: the bridge adopts a group whose
  /// disable failed (clearReceiveCallback) instead of it being dropped.
  Future<void> _teardownFailedActiveSession() async {
    if (_ownsBackend) return _rollbackEnabledJoin();
    _releaseReceiveCallback();
  }

  void _releaseReceiveCallback() {
    _bridge.clearReceiveCallback(groupId: _session.groupId, owner: _owner);
  }

  void _setSession(AvConferenceSession next) {
    _session = next;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
