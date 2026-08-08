import 'package:flutter/foundation.dart';

import 'av_conference_session_bridge.dart';

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

enum AvConferenceSessionFailure { join, mute, disable }

const Object _kFailureUnchanged = Object();

class AvConferenceSession {
  const AvConferenceSession({
    required this.groupId,
    required this.displayName,
    required this.lifecycle,
    required this.failure,
    required this.isMuted,
    required this.receivedFrameCount,
  });

  final String groupId;
  final String displayName;
  final AvConferenceSessionLifecycle lifecycle;
  final AvConferenceSessionFailure? failure;
  final bool isMuted;
  final int receivedFrameCount;

  AvConferenceSession copyWith({
    AvConferenceSessionLifecycle? lifecycle,
    Object? failure = _kFailureUnchanged,
    bool? isMuted,
    int? receivedFrameCount,
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
    );
  }
}

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
    _setSession(
      _session.copyWith(
        lifecycle: AvConferenceSessionLifecycle.joining,
        failure: null,
      ),
    );
    final bool enabled;
    try {
      enabled = await _bridge.enable(
        groupId: _session.groupId,
        owner: _owner,
        onAudioFrame: _handleAudioFrame,
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
          failure: AvConferenceSessionFailure.join,
        ),
      );
      return false;
    }
    if (_session.isMuted) {
      final bool muted;
      try {
        muted = await _bridge.setMuted(
          groupId: _session.groupId,
          owner: _owner,
          muted: true,
        );
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
      } finally {
        _releaseReceiveCallback();
        if (disabled) {
          _ownsBackend = false;
        }
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
      applied = await _bridge.setMuted(
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
    if (!_ownsBackend) {
      return;
    }
    try {
      await _bridge.disable(groupId: _session.groupId, owner: _owner);
    } catch (_) {
    } finally {
      _ownsBackend = false;
      _releaseReceiveCallback();
    }
  }

  Future<void> _teardownFailedActiveSession() async {
    if (_ownsBackend) {
      try {
        await _bridge.disable(groupId: _session.groupId, owner: _owner);
      } catch (_) {
        _ownsBackend = false;
      } finally {
        _ownsBackend = false;
      }
    }
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
