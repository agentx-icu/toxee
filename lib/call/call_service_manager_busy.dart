part of 'call_service_manager.dart';

// Busy arbitration and legacy-AV-conference wiring for [CallServiceManager].
//
// Split out along the "one audio pipeline, several claimants" seam: a 1:1
// call and an AV conference share the single microphone (AudioHandler), so
// every new claimant — an incoming signaling invite, an incoming native ToxAV
// call, an outgoing call, a conference join — goes through [_isBusyForNewCall]
// here, and a refused incoming call is rejected with a busy reason instead of
// overwriting the call on screen.

/// Whether a NEW call (or conference join) must be refused because the audio
/// pipeline is already claimed. `ended` is not busy: that is the 2 s
/// "call ended" banner, the pipeline is already released.
@visibleForTesting
bool isCallPipelineBusy({
  required CallUIState state,
  required bool conferenceActive,
}) {
  return conferenceActive ||
      state == CallUIState.ringing ||
      state == CallUIState.inCall ||
      state == CallUIState.reconnecting;
}

/// Whether the ToxAV loop must run at the fast AV cadence: any 1:1 call from
/// ringing to hang-up, or any conference with live media (its per-peer frames
/// sit in a 64-frame drop-oldest native queue drained only by av_iterate).
@visibleForTesting
bool shouldBoostAvPoll({
  required CallUIState state,
  required bool conferenceActive,
}) {
  return isCallPipelineBusy(state: state, conferenceActive: conferenceActive);
}

/// Simultaneous calls ("glare": A calls B while B calls A). Exactly one side
/// yields — the one whose Tox public key sorts higher — by cancelling its own
/// outgoing call and letting the peer's invite ring; the other side declines
/// the loser's (about to be cancelled) invite. Both sides evaluate this with
/// swapped arguments, so the answers are complementary.
///
/// [selfToxId] must be the account's REAL Tox identity
/// (`FfiChatService.getSelfToxId()`), never the V2TIM login alias `selfId`,
/// which integrators pass as a constant placeholder (toxee:
/// `FlutterUIKitClient`) — both peers would then compare the same string and
/// neither would yield. Either identity missing or not a 64/76-hex Tox ID →
/// never yield (deterministic plain busy on both sides).
@visibleForTesting
bool callGlareYields({required String? selfToxId, required String peerId}) {
  final self = _glarePublicKey(selfToxId);
  final peer = _glarePublicKey(peerId);
  if (self == null || peer == null || self == peer) return false;
  return self.compareTo(peer) > 0;
}

final RegExp _toxIdentityPattern = RegExp(
  r'^[0-9a-fA-F]{64}(?:[0-9a-fA-F]{12})?$',
);

String? _glarePublicKey(String? id) {
  final trimmed = id?.trim() ?? '';
  if (!_toxIdentityPattern.hasMatch(trimmed)) return null;
  return toToxPublicKey(trimmed);
}

/// Dedupe for busy-reject records. One call ATTEMPT arrives as up to two
/// incoming events — its signaling invite and the caller's ToxAV leg — which
/// must yield one missed-call record; a RETRY is a new invite ID (and a new
/// leg) and must yield another. Records are therefore keyed by invite ID,
/// and the ID-less native leg is correlated with the same caller's attempt
/// within [correlationWindow] that has no leg yet (either arrival order).
@visibleForTesting
class BusyRejectLedger {
  BusyRejectLedger({
    this.correlationWindow = const Duration(seconds: 10),
    this.retention = const Duration(minutes: 2),
  });

  final Duration correlationWindow;
  final Duration retention;
  final List<_BusyAttempt> _attempts = <_BusyAttempt>[];

  /// True when this event starts a new attempt (record it). [inviteId] is the
  /// signaling invite ID, or null for a native ToxAV leg.
  bool claim({required String peerKey, String? inviteId, required DateTime now}) {
    _attempts.removeWhere((a) => now.difference(a.at) > retention);
    _BusyAttempt? correlate(bool Function(_BusyAttempt a) open) {
      for (final a in _attempts.reversed) {
        if (a.peerKey == peerKey &&
            now.difference(a.at) <= correlationWindow &&
            open(a)) {
          return a;
        }
      }
      return null;
    }

    if (inviteId != null) {
      if (_attempts.any((a) => a.inviteId == inviteId)) return false;
      final legOnly = correlate((a) => a.inviteId == null);
      if (legOnly != null) {
        legOnly.inviteId = inviteId;
        return false;
      }
      _attempts.add(_BusyAttempt(peerKey, now, inviteId: inviteId));
      return true;
    }
    final attempt = correlate((a) => !a.hasNativeLeg);
    if (attempt != null) {
      attempt.hasNativeLeg = true;
      return false;
    }
    _attempts.add(_BusyAttempt(peerKey, now, hasNativeLeg: true));
    return true;
  }
}

/// Test seams for the arbitration this part file implements: the private
/// wiring (`onBeforeOutgoingCall`, the conference hooks, the foreground-service
/// elevation) is only reachable through [CallServiceManager.initialize], which
/// needs the real adapter + platform channels.
@visibleForTesting
extension CallServiceManagerArbitrationDebug on CallServiceManager {
  /// The adapter's outgoing-call preflight.
  Future<bool> debugPreflightOutgoingCall(String userID, String type) =>
      _preflightOutgoingCall(userID, type);

  /// The adapter's outgoing-call-setup failure callback.
  void debugOnCallSetupFailed(
    CallSetupFailureReason reason,
    List<String> userids,
  ) => _onCallSetupFailed(reason, userids);

  /// Whether the Android foreground service is elevated to `phoneCall`.
  bool get debugForegroundElevatedForCall => _foregroundElevated;

  /// The conference media hooks this manager installs on its bridge.
  ConferenceMediaHooks get debugConferenceHooks => conferenceBridge.debugHooks;
}

class _BusyAttempt {
  _BusyAttempt(this.peerKey, this.at, {this.inviteId, this.hasNativeLeg = false});

  final String peerKey;
  final DateTime at;
  String? inviteId;
  bool hasNativeLeg;
}

extension _CallBusyHandling on CallServiceManager {
  /// Busy-aware call callbacks, shared by [CallServiceManager.initialize] and
  /// the test seam so tests exercise the production wiring.
  void _wireCallCallbacks() {
    _callBridge!.onCallStateChanged = _onCallStateChanged;
    _callBridge!.isBusyForInvitation = _shouldRejectInvitationAsBusy;
    _callBridge!.onInvitationRejectedBusy = _onInvitationRejectedBusy;
    _avService!.setCallCallback(_onIncomingCall);
    _avService!.setCallStateCallback(_onCallState);
  }

  /// [CallBridgeService.isBusyForInvitation].
  bool _shouldRejectInvitationAsBusy(CallInfo invitation) {
    // A redelivery of the invite already on screen is not a second call;
    // rejecting it as line_busy would kill the live call.
    if (invitation.inviteID == _callState.inviteID) return false;
    if (!_isBusyForNewCall) return false;
    if (_isGlareWith(invitation.inviter) &&
        callGlareYields(
          selfToxId: _chatService.getSelfToxId(),
          peerId: invitation.inviter,
        )) {
      AppLogger.info(
        '[CallServiceManager] call glare: yielding outgoing to the peer',
      );
      // Synchronously ends our outgoing ring (state -> ended) before the
      // bridge surfaces the peer's invite as ringing.
      unawaited(hangUp());
      return false;
    }
    return true;
  }

  /// We are ringing OUT to [peerId] while [peerId]'s invite arrives.
  bool _isGlareWith(String peerId) {
    final remote = _callState.remoteUserID;
    return _callState.state == CallUIState.ringing &&
        _callState.direction == CallDirection.outgoing &&
        remote != null &&
        compareToxIds(remote, peerId);
  }

  /// [AudioHandler.afterPlaybackSetup]: flutter_pcm_sound's iOS setup
  /// re-categorises AVAudioSession and drops the voiceChat mode and route
  /// options, so re-apply the live call/conference session. iOS only:
  /// Android's session is not touched by the plugin.
  Future<void> _reapplyIosCallSession() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    await _callAudioPlatform.reapplySession();
  }

  /// OS audio interruptions for a live conference (1:1 calls are handled by
  /// `_mediaInterruption` in `_onAudioPlatformEvent`).
  void _routeInterruptionToConference(CallAudioEvent event) {
    if (!conferenceBridge.hasActiveSession) return;
    switch (event.kind) {
      case CallAudioEventKind.interruptionBegan:
      case CallAudioEventKind.focusLost:
        unawaited(conferenceBridge.suspendForInterruption());
      case CallAudioEventKind.interruptionEnded:
      case CallAudioEventKind.focusGained:
        if (shouldResumeInterruptedCallMedia(
          event: event,
          hasActiveMediaCall: true,
        )) {
          unawaited(conferenceBridge.resumeAfterInterruption());
        }
      default:
        break;
    }
  }

  bool get _isBusyForNewCall => isCallPipelineBusy(
    state: _callState.state,
    conferenceActive: conferenceBridge.hasActiveSession,
  );

  /// True while the 1:1 side owns (or is about to own) the audio pipeline:
  /// a live call, or an outgoing call the preflight approved whose invite has
  /// not surfaced yet. Deliberately NOT part of [_isBusyForNewCall]: a bare
  /// reservation must not busy-reject an incoming invite, or a simultaneous
  /// A↔B call would be refused on both sides instead of going through glare.
  bool get _isOneToOneClaimed =>
      isCallPipelineBusy(state: _callState.state, conferenceActive: false) ||
      _hasOutgoingClaim;

  /// A preflight-approved outgoing call that has not started ringing yet.
  /// Self-expiring: the adapter can abandon a setup without any callback
  /// (a stale-generation cancel), and a stuck reservation would refuse every
  /// later call and conference join for the rest of the session.
  bool get _hasOutgoingClaim {
    final claim = _outgoingClaim;
    if (claim == null) return false;
    if (DateTime.now().difference(claim.at) <= const Duration(seconds: 20)) {
      return true;
    }
    _outgoingClaim = null;
    return false;
  }

  /// Whether an outgoing call to [userID] may take the pipeline, emitting the
  /// user-facing refusal when it may not. Called twice by the preflight: the
  /// OS permission sheet between the two is unbounded in time.
  bool _canClaimOutgoingCall(String userID) {
    if (_isBusyForNewCall) {
      _emitBusyNotice();
      return false;
    }
    if (!_hasOutgoingClaim) return true;
    // A second tap on the call button before the first invite surfaced is a
    // duplicate, not a busy line: suppress it silently, exactly like the
    // duplicate-outgoing-ring check in the preflight.
    if (!compareToxIds(_outgoingClaim!.user, userID)) _emitBusyNotice();
    return false;
  }

  void _emitBusyNotice() {
    _emitLocalizedUiNotice(
      (l10n) => conferenceBridge.hasActiveSession
          ? l10n.callBusyInConference
          : l10n.callBusyInCall,
    );
  }

  /// True when [friendNumber] is the peer of the call on screen (its ToxAV
  /// leg arriving after the signaling invite must stay ignored, not rejected).
  bool _isActiveCallPeer(int friendNumber) {
    if (_getActiveFriendNumber() == friendNumber) return true;
    final remote = _callState.remoteUserID;
    final userId = _avService?.getUserIdByFriendNumber(friendNumber);
    return remote != null &&
        userId != null &&
        userId.isNotEmpty &&
        compareToxIds(remote, userId);
  }

  CallConferenceBridge _createConferenceBridge() {
    return CallConferenceBridge(
      resolveBackend: () async {
        if (!_initialized) await initialize();
        final av = _avService;
        return av == null ? null : ToxAvConferenceBackend(av);
      },
      audio: _audioHandler,
      isOneToOneCallActive: () => _isOneToOneClaimed,
      requestMicrophone: () async =>
          (await _requestCallPermissions(wantVideo: false)).granted,
      hooks: ConferenceMediaHooks(
        onMediaStarted: (displayName) async {
          _syncAvPollBoost();
          _elevateForegroundForCall(peerName: displayName);
          if (_callAudioPlatform.isSupported) {
            // No proximity sensor / earpiece UI on the conference page.
            await _callAudioPlatform.activateSession(preferSpeaker: true);
          }
        },
        onMediaStopped: () async {
          _syncAvPollBoost();
          // The bridge drops conference ownership BEFORE awaiting the audio
          // release, so a 1:1 call can have started — and elevated the Android
          // foreground service / activated the session — by the time this hook
          // runs. Restoring unconditionally would demote that live call's
          // service to dataSync and leave it unable to restore at its own end.
          if (_isOneToOneClaimed) return;
          _restoreForegroundAfterCall();
          if (_callAudioPlatform.isSupported) {
            await _callAudioPlatform.deactivateSession();
          }
        },
      ),
    );
  }

  /// Signaling invite auto-rejected as busy (CallBridgeService already sent
  /// the `line_busy` reject): record it as a missed call.
  void _onInvitationRejectedBusy(CallInfo invitation) {
    // Glare winner: the peer is cancelling this invite to answer ours —
    // not a missed call.
    if (_isGlareWith(invitation.inviter)) return;
    _recordBusyMissedCall(
      peerId: invitation.inviter,
      isVideo: invitation.data.contains('"video":true'),
      inviteId: invitation.inviteID,
    );
  }

  /// A native ToxAV call from someone other than the current peer while the
  /// pipeline is busy: decline it (toxav CANCEL) instead of letting it ring
  /// out unanswered, and record the missed call.
  Future<void> _rejectNativeIncomingAsBusy(int friendNumber, bool video) async {
    AppLogger.info(
      '[CallServiceManager] native incoming friendNumber=$friendNumber '
      'auto-rejected: line busy',
    );
    final userId = _avService?.getUserIdByFriendNumber(friendNumber);
    try {
      await _avService?.endCall(friendNumber);
    } catch (e) {
      AppLogger.warn('[CallServiceManager] busy native reject failed: $e');
    }
    if (userId != null && userId.isNotEmpty) {
      _recordBusyMissedCall(peerId: userId, isVideo: video);
    }
  }

  /// [inviteId]: the signaling invite, or null for a native ToxAV leg.
  void _recordBusyMissedCall({
    required String peerId,
    required bool isVideo,
    String? inviteId,
  }) {
    final newAttempt = _busyRejects.claim(
      peerKey: toToxPublicKey(peerId),
      inviteId: inviteId,
      now: DateTime.now(),
    );
    if (!newAttempt) return;
    unawaited(() async {
      final nickname = await _resolveNickname(peerId);
      onCallRecordNeeded?.call(peerId, isVideo, false, 0, 'line_busy');
      try {
        await NotificationService.instance.showMissedCallNotification(
          peerId: peerId,
          displayName: nickname ?? peerId,
          wasVideo: isVideo,
        );
      } catch (e) {
        AppLogger.warn('[CallServiceManager] busy missed-call notify: $e');
      }
    }());
  }
}
