part of 'call_service_manager.dart';

// Native ToxAV (qTox-interop) incoming calls, ToxAV call-state routing and the
// asynchronous half of the logout teardown of [CallServiceManager].
//
// Split out along the "native leg" seam: everything here reasons about ToxAV
// friend numbers (which may be unresolved, or the Tox `UINT32_MAX` "no such
// friend" sentinel) rather than signaling invite IDs.

extension _CallNativeHandling on CallServiceManager {
  /// Called when ToxAV receives an incoming call directly (e.g. from qTox).
  Future<void> _onIncomingCall(
    int friendNumber,
    bool audioEnabled,
    bool videoEnabled,
  ) async {
    AppLogger.info(
      '[CallServiceManager] native incoming friendNumber=$friendNumber '
      'audio=$audioEnabled video=$videoEnabled state=${_callState.state}',
    );
    if (_disposed) return;
    // A different caller while the pipeline is claimed: decline as busy.
    if (_isBusyForNewCall && !_isActiveCallPeer(friendNumber)) {
      await _rejectNativeIncomingAsBusy(friendNumber, videoEnabled);
      return;
    }
    // Same peer (its ToxAV leg of the ringing signaling call) / ended banner.
    if (_callState.state != CallUIState.idle) {
      debugPrint(
        '[CallServiceManager] _onIncomingCall: ignored (not idle), '
        'friendNumber=$friendNumber',
      );
      return;
    }
    final token = ++_nativeIncomingSeq;
    _pendingNativeIncoming[friendNumber] = token;

    // Reverse-lookup user ID from friend number (may return null).
    String remoteUserID = 'Tox Contact';
    final userId = _avService?.getUserIdByFriendNumber(friendNumber);
    if (userId != null && userId.isNotEmpty) remoteUserID = userId;

    final nickname = await _resolveNickname(remoteUserID);
    // Everything checked above may have changed during the lookup: the caller
    // hung up (its FINISHED/ERROR dropped the token, see _onCallState), a
    // newer incoming call from it superseded this one, the manager was
    // disposed, or a conference / another call claimed the pipeline.
    if (_pendingNativeIncoming[friendNumber] != token) {
      AppLogger.info(
        '[CallServiceManager] native incoming friendNumber=$friendNumber '
        'ended or superseded during caller lookup — not ringing',
      );
      return;
    }
    _pendingNativeIncoming.remove(friendNumber);
    if (_disposed) return;
    if (_isBusyForNewCall || _callState.state != CallUIState.idle) {
      // Its own signaling invite surfaced meanwhile: this is that call's leg.
      if (_isActiveCallPeer(friendNumber)) return;
      if (_isBusyForNewCall) {
        await _rejectNativeIncomingAsBusy(friendNumber, videoEnabled);
      }
      return;
    }

    final inviteID = 'native_av_$friendNumber';
    _nativeCallFriendNumbers[inviteID] = friendNumber;
    _callRecordEmitted = false;

    debugPrint(
      '[CallServiceManager] _onIncomingCall: friendNumber=$friendNumber, '
      'inviteID=$inviteID, remoteUserID=$remoteUserID, nickname=$nickname, '
      'audio=$audioEnabled, video=$videoEnabled',
    );

    _callState.startRinging(
      mode: videoEnabled ? CallMode.video : CallMode.audio,
      direction: CallDirection.incoming,
      inviteID: inviteID,
      remoteUserID: remoteUserID,
      remoteNickname: nickname,
    );
    if (videoEnabled && !CallMediaCapabilities.supportsVideoCapture()) {
      // Receive-only video on camera-less platforms: remote renders, local
      // camera is never advertised as on.
      _callState.disableLocalVideo();
    }
    _showAndroidIncomingCallSurface(
      callId: inviteID,
      displayName: nickname ?? remoteUserID,
      isVideo: videoEnabled,
    );
    final callKitHandled = await _callKitReportRinging(
      callId: inviteID,
      displayName: nickname ?? remoteUserID,
      hasVideo: videoEnabled,
      incoming: true,
    );
    if (!callKitHandled &&
        _callState.state == CallUIState.ringing &&
        _callState.inviteID == inviteID) {
      unawaited(_ringtone.start());
    }
  }

  /// Whether a ToxAV call-state event for [friendNumber] belongs to the call
  /// on screen. When that call's friend number is not resolvable (friend not
  /// known when the invite arrived) the peer IDENTITY decides, so the real
  /// leg is neither discarded (it used to be compared with `UINT32_MAX`) nor
  /// confused with another caller's.
  bool _isCallStateForActiveCall(int friendNumber) {
    final active = _getActiveFriendNumber();
    if (active != null) return active == friendNumber;
    if (_callState.state == CallUIState.idle) return false;
    final remote = _callState.remoteUserID;
    final userId = _avService?.getUserIdByFriendNumber(friendNumber);
    return remote != null &&
        userId != null &&
        userId.isNotEmpty &&
        compareToxIds(remote, userId);
  }

  /// Remember that WE ended [inviteID]'s ToxAV leg, so its terminal event can
  /// be told apart from a newer call's. Call before the call state is cleared
  /// ([_getActiveFriendNumber] reads it).
  void _markAvLegEnded(String inviteID) {
    final friendNumber = _getActiveFriendNumber();
    if (friendNumber == null) return;
    _endedAvLegs[friendNumber] = (invite: inviteID, at: DateTime.now());
  }

  /// A FINISHED/ERROR for a leg this manager already ended, arriving after a
  /// redial to the same friend put a DIFFERENT call on screen.
  ///
  /// toxcore reports call state per friend with no leg identity, and the
  /// bridge serialises AV teardowns per friend before the next leg starts, so
  /// the pending terminal always precedes the new leg's own. The mark expires
  /// so a terminal that never arrives cannot swallow a later real one.
  bool _isStaleAvTerminal(int friendNumber) {
    final ended = _endedAvLegs.remove(friendNumber);
    if (ended == null) return false;
    if (DateTime.now().difference(ended.at) > const Duration(seconds: 10)) {
      return false;
    }
    final current = _callState.inviteID;
    if (current == null || current == ended.invite) return false;
    AppLogger.info(
      '[CallServiceManager] stale ToxAV terminal for friend=$friendNumber '
      '(leg ${ended.invite} ended; $current is on screen) — ignored',
    );
    return true;
  }

  /// Logout: end every native (qTox-style) call leg now — the FFI call runs
  /// synchronously, before ToxAV is shut down.
  void _endNativeCallsNow() {
    final av = _avService;
    if (av != null) {
      for (final friendNumber in _nativeCallFriendNumbers.values.toSet()) {
        unawaited(
          Future<bool>.sync(
            () => av.endCall(friendNumber),
          ).catchError((Object _) => false),
        );
      }
    }
    _nativeCallFriendNumbers.clear();
  }

  /// Android: the session teardown stops RuntimeForegroundService outright
  /// right after this manager is disposed (session_runtime_teardown.dart,
  /// stage `foreground_service`). A `restoreFromCall` here would be a
  /// `startForegroundService` racing that `stopService` — the service is torn
  /// down before it can call `startForeground` (a
  /// ForegroundServiceDidNotStartInTime crash) or is revived after logout. So
  /// the elevation is only forgotten; the stop supersedes it.
  void _dropForegroundElevationForLogout() {
    _foregroundElevated = false;
    _foregroundUsesCamera = null;
  }

  /// Awaited half of [CallServiceManager.dispose]: media first, then the
  /// platform audio session. iOS: `CallAudioPlatform.dispose` only cancels the
  /// event stream — a call or conference live at logout would leave the
  /// AVAudioSession (and Android's audio focus / MODE_IN_COMMUNICATION)
  /// active, so it is deactivated here, once.
  ///
  /// Every step is bounded: logout awaits this future, and a platform channel
  /// that never answers (e.g. an iOS deactivate stuck behind the system) must
  /// not hang logout or an account switch. Nothing native waits on it: the
  /// native disables and call ends were dispatched synchronously in dispose().
  Future<void> _finishDispose(List<Future<void>?> media) async {
    const stepTimeout = Duration(seconds: 5);
    Future<void> step(String what, Future<void>? Function() op) async {
      try {
        await op()?.timeout(stepTimeout);
      } catch (e) {
        AppLogger.warn('[CallServiceManager] dispose $what failed: $e');
      }
    }

    for (final teardown in media) {
      await step('media', () => teardown);
    }
    await step('platform teardown', _queuePlatformTeardown);
    await step('audio platform', _callAudioPlatform.dispose);
  }

  /// Releases proximity + the audio session ON the platform-effects queue,
  /// i.e. behind any activation still in flight. A sync step that was already
  /// past its `_disposed` check would otherwise re-activate the session after
  /// the teardown deactivated it — the bounded wait above means the two can
  /// overlap. Steps queued but not started abort on `_disposed`, so nothing
  /// can activate after this one.
  Future<void> _queuePlatformTeardown() {
    final next = (_pendingSync ?? Future<void>.value())
        .catchError((Object e, StackTrace st) {
          AppLogger.warn(
            '[CallServiceManager] platform-effects sync failed before '
            'teardown: $e',
          );
        })
        .then((_) async {
          await _callAudioPlatform.setProximityMonitoring(false);
          if (_callAudioPlatform.isSessionActive) {
            await _callAudioPlatform.deactivateSession();
          }
        });
    _pendingSync = next;
    return next;
  }
}
