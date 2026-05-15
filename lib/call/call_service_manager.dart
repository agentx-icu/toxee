import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/service/toxav_service.dart';
import 'package:tim2tox_dart/service/call_bridge_service.dart';
import 'package:tim2tox_dart/service/tuicallkit_adapter.dart';
import 'package:tim2tox_dart/service/tuicallkit_tuicore_integration.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'call_state_notifier.dart';
import 'call_overlay_manager.dart';
import 'audio_handler.dart';
import 'call_audio_platform.dart';
import 'video_handler.dart';
import 'ringtone_player.dart';
import 'permission_helper.dart';
import 'call_ui_notice.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';

/// Manages ToxAV service lifecycle and bridges events to CallStateNotifier.
///
/// Supports two call paths:
///   1. **Signaling path** — via CallBridgeService (UIKit-based invitations)
///   2. **Native ToxAV path** — direct toxav_call/answer/control (qTox interop)
///
/// Native ToxAV calls use inviteIDs of the form `native_av_<friendNumber>`.
class CallServiceManager implements CallOverlayManager {
  final FfiChatService _chatService;
  final CallStateNotifier _callState;
  ToxAVService? _avService;
  CallBridgeService? _callBridge;
  TUICallKitAdapter? _adapter;
  final AudioHandler _audioHandler = AudioHandler();
  final CallAudioPlatform _callAudioPlatform = CallAudioPlatform();
  final VideoHandler _videoHandler = VideoHandler();
  final RingtonePlayer _ringtone = RingtonePlayer();
  StreamSubscription<CallAudioEvent>? _audioPlatformSub;
  bool _initialized = false;

  /// Maps native inviteID → friendNumber for active native ToxAV calls.
  final Map<String, int> _nativeCallFriendNumbers = {};

  /// Called when a call ends, to insert a call record into the chat.
  /// Parameters: (remoteUserID, isVideo, isOutgoing, durationSeconds, endReason)
  /// endReason: 'hangup' | 'cancel' | 'reject' | 'timeout'
  void Function(String remoteUserID, bool isVideo, bool isOutgoing,
      int durationSeconds, String endReason)? onCallRecordNeeded;

  /// Prevents duplicate call record emissions per call.
  bool _callRecordEmitted = false;
  final ValueNotifier<CallUiNotice?> uiNotice = ValueNotifier(null);
  int _nextNoticeId = 0;

  /// Active reconnect-window timer. When non-null, the call is currently in
  /// the [CallUIState.reconnecting] state; the timer fires after a grace
  /// period and tears the call down if recovery has not been observed.
  Timer? _reconnectTimer;
  static const Duration _reconnectGrace = Duration(seconds: 8);

  CallServiceManager(this._chatService, this._callState);

  bool get isInitialized => _initialized;
  @override
  ValueListenable<CallAudioState> get audioState => _callAudioPlatform.state;
  @override
  ValueListenable<ui.Image?> get remoteVideo => _videoHandler.remoteImage;
  @override
  Listenable get previewListenable => _videoHandler;
  @override
  Widget? get localPreview => _videoHandler.localPreview;

  // ---------------------------------------------------------------------------
  // Native call helpers
  // ---------------------------------------------------------------------------

  /// Whether [inviteID] represents a native ToxAV call (not signaling).
  bool _isNativeCall(String? inviteID) =>
      inviteID != null && inviteID.startsWith('native_av_');

  /// Get the friendNumber associated with a native inviteID, or null.
  int? _getNativeFriendNumber(String? inviteID) {
    if (inviteID == null || !inviteID.startsWith('native_av_')) return null;
    return _nativeCallFriendNumbers[inviteID];
  }

  /// Remove native call tracking for the current call.
  void _cleanupNativeCall() {
    final id = _callState.inviteID;
    if (id != null) {
      _nativeCallFriendNumbers.remove(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Call record helper
  // ---------------------------------------------------------------------------

  /// Emit a call record before call state is cleared.
  void _emitCallRecord(String endReason) {
    if (_callRecordEmitted) return; // Prevent duplicate records per call
    _callRecordEmitted = true;
    final remoteUserID = _callState.remoteUserID;
    if (remoteUserID == null) return;
    final isVideo = _callState.mode == CallMode.video;
    final isOutgoing = _callState.direction == CallDirection.outgoing;
    final durationSeconds = _callState.callDuration.inSeconds;
    onCallRecordNeeded?.call(
        remoteUserID, isVideo, isOutgoing, durationSeconds, endReason);
  }

  /// Resolve nickname for a given userID from local cache.
  Future<String?> _resolveNickname(String userID) async {
    try {
      return await Prefs.getFriendNickname(userID);
    } catch (_) {
      return null;
    }
  }

  /// Check if a friend is online via FfiChatService.
  Future<bool> _isFriendOnline(String userID) async {
    try {
      final friends = await _chatService.getFriendList();
      for (final f in friends) {
        if (compareToxIds(f.userId, userID)) {
          return f.online;
        }
      }
      return false; // Friend not found → treat as offline
    } catch (_) {
      // Fail-closed: previously returned `true` to be permissive, but that
      // causes outgoing calls to ring forever against unreachable peers when
      // the friend list lookup transiently fails. Better UX is to surface the
      // problem immediately than to leave the user staring at a dead ringer.
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Reconnect handling
  // ---------------------------------------------------------------------------

  /// Mark the call as reconnecting and start the grace-period timer.
  /// If [_reconnectGrace] elapses without [clearReconnecting] being called,
  /// the call is force-ended.
  ///
  /// Public so callers (e.g. ToxAV quality/disconnect event listeners) can
  /// drive the state from outside.
  // TODO: wire to SDK reconnect events when c-toxcore exposes a discrete
  // "transport down / re-establishing" callback. The ToxAV friend_call_state
  // bitfield (toxav.h) does not currently distinguish "reconnecting" from
  // "ended", so we expose this API for higher-level callers to drive.
  void markReconnecting() {
    if (_callState.state != CallUIState.inCall &&
        _callState.state != CallUIState.reconnecting) {
      return;
    }
    _callState.setState(CallUIState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectGrace, () {
      if (_callState.state == CallUIState.reconnecting) {
        debugPrint(
            '[CallServiceManager] reconnect grace expired, ending call');
        _emitCallRecord('hangup');
        _callState.endCall();
        _cleanupNativeCall();
      }
      _reconnectTimer = null;
    });
  }

  /// Cancel any pending reconnect timer and (optionally) move the call back
  /// to [CallUIState.inCall]. Idempotent.
  void clearReconnecting() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_callState.state == CallUIState.reconnecting) {
      _callState.setState(CallUIState.inCall);
    }
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) return;

    _avService = ToxAVService(_chatService.tim2toxFfi);
    await _avService!.initialize();

    _callBridge = CallBridgeService(
      TencentCloudChatSdkPlatform.instance,
      _avService!,
    );

    _adapter = await TUICallKitAdapter.initialize(
      TencentCloudChatSdkPlatform.instance,
      _avService!,
      _callBridge!,
    );
    registerToxAVWithTUICore(_adapter!);
    _adapter!.isCallIdle = () => _callState.state == CallUIState.idle;

    _callBridge!.onCallStateChanged = _onCallStateChanged;
    _adapter!.onOutgoingCallInitiated = _onOutgoingCallInitiated;
    _adapter!.onBeforeOutgoingCall = _preflightOutgoingCall;
    _avService!.setCallCallback(_onIncomingCall);
    _avService!.setCallStateCallback(_onCallState);
    _avService!.setAudioReceiveCallback(_audioHandler.onAudioReceived);
    _avService!.setVideoReceiveCallback(_videoHandler.onVideoReceived);
    await _callAudioPlatform.initialize();
    _audioPlatformSub?.cancel();
    _audioPlatformSub = _callAudioPlatform.events.listen(_onAudioPlatformEvent);

    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Signaling-path callbacks (UIKit)
  // ---------------------------------------------------------------------------

  /// Called when the user initiates an outgoing call via the UIKit call button.
  void _onOutgoingCallInitiated(
      String inviteID, String userID, String type) async {
    debugPrint(
        '[CallServiceManager] _onOutgoingCallInitiated: inviteID=$inviteID, userID=$userID, type=$type, currentState=${_callState.state}');
    final nickname = await _resolveNickname(userID);
    _callRecordEmitted = false;
    _callState.startRinging(
      mode: type == TYPE_VIDEO ? CallMode.video : CallMode.audio,
      direction: CallDirection.outgoing,
      inviteID: inviteID,
      remoteUserID: userID,
      remoteNickname: nickname,
    );
    debugPrint(
        '[CallServiceManager] _onOutgoingCallInitiated: after startRinging, state=${_callState.state}');

    // Check friend online status — auto-cancel if offline
    final isOnline = await _isFriendOnline(userID);
    if (!isOnline && _callState.state == CallUIState.ringing) {
      debugPrint(
          '[CallServiceManager] Friend $userID is offline, auto-ending call after brief delay');
      await Future.delayed(const Duration(milliseconds: 800));
      if (_callState.state == CallUIState.ringing &&
          _callState.inviteID == inviteID) {
        hangUp();
      }
    }

    if (_callState.state == CallUIState.ringing &&
        _callState.inviteID == inviteID) {
      final granted = await _ensurePermissionsForCurrentMode();
      if (!granted &&
          _callState.state == CallUIState.ringing &&
          _callState.inviteID == inviteID) {
        await hangUp();
      }
    }
  }

  void _onCallStateChanged(String inviteID, CallState state) async {
    switch (state) {
      case CallState.ringing:
        final callInfo = _callBridge!.getCallInfo(inviteID);
        if (callInfo != null) {
          final nickname = await _resolveNickname(callInfo.inviter);
          _callRecordEmitted = false;
          _callState.startRinging(
            mode: callInfo.data.contains('"video":true')
                ? CallMode.video
                : CallMode.audio,
            direction: CallDirection.incoming,
            inviteID: inviteID,
            remoteUserID: callInfo.inviter,
            remoteNickname: nickname,
          );
          _ringtone.start(); // incoming call ringtone
        }
        break;
      case CallState.inCall:
        _ringtone.stop();
        _callState.enterCall();
        final callInfoInCall = _callBridge!.getCallInfo(inviteID);
        if (callInfoInCall?.friendNumber != null && _avService != null) {
          final fn = callInfoInCall!.friendNumber!;
          // Request permissions then start capture (async, fire-and-forget)
          _startMediaCapture(fn);
        }
        break;
      case CallState.ended:
        _ringtone.stop();
        _audioHandler.stop();
        _videoHandler.stop();
        // Emit call record before clearing state
        final endReason =
            _callState.state == CallUIState.inCall ? 'hangup' : 'cancel';
        _emitCallRecord(endReason);
        _callState.endCall();
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Native ToxAV callbacks (qTox interop)
  // ---------------------------------------------------------------------------

  /// Called when ToxAV receives an incoming call directly (e.g. from qTox).
  void _onIncomingCall(
      int friendNumber, bool audioEnabled, bool videoEnabled) async {
    // Ignore if already in a call.
    if (_callState.state != CallUIState.idle) {
      debugPrint(
          '[CallServiceManager] _onIncomingCall: ignored (not idle), friendNumber=$friendNumber');
      return;
    }

    final inviteID = 'native_av_$friendNumber';
    _nativeCallFriendNumbers[inviteID] = friendNumber;

    // Reverse-lookup user ID from friend number (may return null).
    String remoteUserID = 'Tox Contact';
    final userId = _avService?.getUserIdByFriendNumber(friendNumber);
    if (userId != null && userId.isNotEmpty) remoteUserID = userId;

    final nickname = await _resolveNickname(remoteUserID);
    _callRecordEmitted = false;

    debugPrint(
        '[CallServiceManager] _onIncomingCall: friendNumber=$friendNumber, '
        'inviteID=$inviteID, remoteUserID=$remoteUserID, nickname=$nickname, '
        'audio=$audioEnabled, video=$videoEnabled');

    _callState.startRinging(
      mode: videoEnabled ? CallMode.video : CallMode.audio,
      direction: CallDirection.incoming,
      inviteID: inviteID,
      remoteUserID: remoteUserID,
      remoteNickname: nickname,
    );
    _ringtone.start();
  }

  /// Called when ToxAV call state changes (e.g. peer answered, peer hung up).
  /// [state] is a bitfield from c-toxcore toxav.h TOXAV_FRIEND_CALL_STATE_*.
  void _onCallState(int friendNumber, int state) {
    // ToxAV call_state bitfield constants
    const stateError = 1; // TOXAV_FRIEND_CALL_STATE_ERROR
    const stateFinished = 2; // TOXAV_FRIEND_CALL_STATE_FINISHED
    const stateSendingA = 4; // TOXAV_FRIEND_CALL_STATE_SENDING_A
    const stateAcceptingA = 16; // TOXAV_FRIEND_CALL_STATE_ACCEPTING_A

    debugPrint(
        '[CallServiceManager] _onCallState: friendNumber=$friendNumber, state=$state');

    // Error or finished → end the call
    if (state == stateError || state == stateFinished) {
      _ringtone.stop();
      _audioHandler.stop();
      _videoHandler.stop();
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      // Emit call record before clearing state
      if (_callState.state == CallUIState.inCall ||
          _callState.state == CallUIState.reconnecting) {
        _emitCallRecord('hangup');
      } else if (_callState.state == CallUIState.ringing) {
        _emitCallRecord(_callState.direction == CallDirection.outgoing
            ? 'timeout'
            : 'cancel');
      }
      _callState.endCall();
      _cleanupNativeCall();
      return;
    }

    // Peer accepted (state contains SENDING_A or ACCEPTING_A bits).
    // This handles both:
    //   - Outgoing call: qTox answered → we receive call_state with SENDING_A|ACCEPTING_A
    //   - Incoming call: after we answered → state confirms media is flowing
    if ((state & stateSendingA) != 0 || (state & stateAcceptingA) != 0) {
      if (_callState.state == CallUIState.ringing) {
        _ringtone.stop();
        _callState.enterCall();
        _startMediaCapture(friendNumber);
      } else if (_callState.state == CallUIState.reconnecting) {
        // Media is flowing again — recover from reconnecting state.
        clearReconnecting();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Media capture
  // ---------------------------------------------------------------------------

  /// Request permissions and start audio/video capture for an active call.
  Future<void> _startMediaCapture(int friendNumber) async {
    try {
      if (_avService != null) {
        _audioHandler.startCapture(friendNumber, _avService!);
      }
      if (_callState.mode == CallMode.video && _avService != null) {
        _videoHandler.startCapture(friendNumber, _avService!);
      }
    } catch (e) {
      debugPrint('[CallServiceManager] _startMediaCapture error: $e');
    }
  }

  Future<bool> _ensurePermissionsForCurrentMode() async {
    final result = await CallPermissionHelper.requestPermissionsForCallDetailed(
      isVideo: _callState.mode == CallMode.video,
    );
    if (!result.granted) {
      _emitPermissionNotice(result);
      debugPrint(
          '[CallServiceManager] Required call permissions denied for mode=${_callState.mode}');
    }
    return result.granted;
  }

  Future<bool> _preflightOutgoingCall(String _, String type) async {
    final result = await CallPermissionHelper.requestPermissionsForCallDetailed(
      isVideo: type == TYPE_VIDEO,
    );
    if (!result.granted) {
      _emitPermissionNotice(result);
    }
    return result.granted;
  }

  void _emitPermissionNotice(CallPermissionResult result) {
    _emitLocalizedUiNotice(
      (l10n) =>
          CallPermissionHelper.describeDeniedPermissionResult(result, l10n),
      offerSettings: result.requiresSettings,
    );
  }

  void _emitLocalizedUiNotice(
    CallUiMessageResolver resolveMessage, {
    bool isError = true,
    bool offerSettings = false,
  }) {
    uiNotice.value = CallUiNotice(
      id: ++_nextNoticeId,
      resolveMessage: resolveMessage,
      isError: isError,
      offerSettings: offerSettings,
    );
  }

  Future<void> syncPlatformEffectsForState(CallUIState state) async {
    if (!_callAudioPlatform.isSupported) {
      return;
    }

    if (state == CallUIState.ringing || state == CallUIState.inCall) {
      await _callAudioPlatform.activateSession(
        preferSpeaker:
            state == CallUIState.ringing || _callState.mode == CallMode.video,
      );
      return;
    }

    await _callAudioPlatform.deactivateSession();
  }

  @override
  Future<void> selectAudioRoute(String routeId) async {
    await _callAudioPlatform.selectRoute(routeId);
  }

  void _onAudioPlatformEvent(CallAudioEvent event) {
    switch (event.kind) {
      case CallAudioEventKind.interruptionBegan:
      case CallAudioEventKind.focusLost:
      case CallAudioEventKind.noisy:
        _emitLocalizedUiNotice(
          (l10n) => l10n.callAudioInterrupted,
          offerSettings: false,
        );
        break;
      default:
        break;
    }
  }

  int? _getActiveFriendNumber() {
    final inviteID = _callState.inviteID;
    if (_isNativeCall(inviteID)) {
      return _getNativeFriendNumber(inviteID);
    }
    final callInfo =
        inviteID != null ? _callBridge?.getCallInfo(inviteID) : null;
    return callInfo?.friendNumber;
  }

  // ---------------------------------------------------------------------------
  // Call actions — dual-path (signaling vs native ToxAV)
  // ---------------------------------------------------------------------------

  @override
  Future<void> acceptCall() async {
    final inviteID = _callState.inviteID;
    if (inviteID == null) return;

    final granted = await _ensurePermissionsForCurrentMode();
    if (!granted) {
      await rejectCall();
      return;
    }

    if (_isNativeCall(inviteID)) {
      // Native ToxAV path — answer directly via toxav_answer
      final fn = _getNativeFriendNumber(inviteID);
      if (fn != null && _avService != null) {
        final isVideo = _callState.mode == CallMode.video;
        await _avService!.answerCall(
          fn,
          audioBitRate: 48,
          videoBitRate: isVideo ? 5000 : 0,
        );
        // Immediately enter call state and start media
        _ringtone.stop();
        _callState.enterCall();
        _startMediaCapture(fn);
      }
    } else {
      // Signaling path
      await _callBridge?.acceptInvitation(inviteID);
    }
  }

  @override
  Future<void> rejectCall() async {
    final inviteID = _callState.inviteID;
    if (inviteID == null) return;

    _emitCallRecord('reject');

    if (_isNativeCall(inviteID)) {
      // Native ToxAV path — reject via toxav_call_control(CANCEL)
      final fn = _getNativeFriendNumber(inviteID);
      if (fn != null && _avService != null) {
        await _avService!.endCall(fn);
      }
      _ringtone.stop();
      _callState.endCall();
      _cleanupNativeCall();
    } else {
      await _callBridge?.rejectInvitation(inviteID);
      _ringtone.stop();
      _callState.endCall();
    }
  }

  @override
  Future<void> hangUp() async {
    final inviteID = _callState.inviteID;
    if (inviteID == null) return;

    // Emit call record before clearing state
    if (_callState.state == CallUIState.inCall) {
      _emitCallRecord('hangup');
    } else if (_callState.state == CallUIState.ringing &&
        _callState.direction == CallDirection.outgoing) {
      _emitCallRecord('cancel');
    }

    if (_isNativeCall(inviteID)) {
      // Native ToxAV path
      final fn = _getNativeFriendNumber(inviteID);
      if (fn != null && _avService != null) {
        await _avService!.endCall(fn);
      }
      _audioHandler.stop();
      _videoHandler.stop();
      _callState.endCall();
      _cleanupNativeCall();
    } else {
      await _callBridge?.endCall(inviteID);
      _ringtone.stop();
      _audioHandler.stop();
      _videoHandler.stop();
      _callState.endCall();
    }
  }

  @override
  Future<void> toggleMute() async {
    _callState.toggleMute();
    final inviteID = _callState.inviteID;

    if (_isNativeCall(inviteID)) {
      // Native ToxAV path — use friendNumber directly
      final fn = _getNativeFriendNumber(inviteID);
      if (fn != null) {
        await _avService?.muteAudio(fn, _callState.isMuted);
      }
    } else {
      // Signaling path — look up friendNumber from callInfo
      final callInfo =
          inviteID != null ? _callBridge?.getCallInfo(inviteID) : null;
      if (callInfo?.friendNumber != null) {
        await _avService?.muteAudio(
            callInfo!.friendNumber!, _callState.isMuted);
      }
    }
  }

  @override
  Future<void> toggleVideo() async {
    final enableVideo = !_callState.isVideoEnabled;
    if (enableVideo) {
      final result =
          await CallPermissionHelper.requestPermissionsForCallDetailed(
        isVideo: true,
      );
      if (!result.granted) {
        _emitPermissionNotice(result);
        debugPrint(
            '[CallServiceManager] Video permission denied while enabling camera');
        return;
      }
    }

    _callState.toggleVideo();
    final inviteID = _callState.inviteID;
    final friendNumber = _getActiveFriendNumber();

    if (_isNativeCall(inviteID)) {
      if (friendNumber != null) {
        await _avService?.muteVideo(friendNumber, !_callState.isVideoEnabled);
      }
    } else {
      if (friendNumber != null) {
        await _avService?.muteVideo(friendNumber, !_callState.isVideoEnabled);
      }
    }

    if (!_callState.isVideoEnabled) {
      await _videoHandler.stop();
      return;
    }

    if (_callState.state == CallUIState.inCall &&
        _callState.mode == CallMode.video &&
        friendNumber != null &&
        _avService != null) {
      await _videoHandler.startCapture(friendNumber, _avService!);
    }
  }

  void dispose() {
    _ringtone.stop();
    _ringtone.dispose();
    _audioHandler.stop();
    _videoHandler.stop();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    uiNotice.dispose();
    _audioPlatformSub?.cancel();
    unawaited(_callAudioPlatform.dispose());
    _nativeCallFriendNumbers.clear();
    _avService?.shutdown();
    _callBridge?.dispose();
    _adapter?.dispose();
  }
}
