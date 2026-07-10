import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/service/toxav_service.dart';
import 'package:tim2tox_dart/service/call_bridge_service.dart';
import 'package:tim2tox_dart/service/tuicallkit_adapter.dart';
import 'package:tim2tox_dart/service/tuicallkit_tuicore_integration.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import '../adapters/logger_adapter.dart';
import '../util/logger.dart';
import 'call_codec_profile.dart';
import 'call_media_capabilities.dart';
import 'call_quality_estimator.dart';
import 'call_state_notifier.dart';
import 'call_overlay_manager.dart';
import 'audio_handler.dart';
import 'call_audio_platform.dart';
import 'callkit_bridge.dart';
import 'video_handler.dart';
import 'ringtone_player.dart';
import 'permission_helper.dart';
import 'call_ui_notice.dart';
import '../i18n/app_localizations.dart';
import '../notifications/notification_service.dart';
import '../runtime/runtime_foreground_service.dart';
import '../util/locale_controller.dart';
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

  /// CallKit bridge (iOS only; no-op on every other platform). Surfaces the
  /// system call UI for ringing/in-call states so calls work on the lock
  /// screen and through CarPlay / AirPods controls.
  ///
  /// Tracked-but-aware: a CallKit-driven "answer"/"end"/"mute" tap is
  /// forwarded back through `_callKitSub` and drives the same `acceptCall` /
  /// `hangUp` / `toggleMute` paths the in-app UI uses, so we keep one source
  /// of truth for call state.
  final CallKitBridge _callKit = CallKitBridge.instance;
  StreamSubscription<CallKitAction>? _callKitSub;

  /// `callId` last reported to CallKit per Tox inviteID. Whenever we report
  /// an incoming/outgoing call to CallKit, we use the Tox inviteID directly
  /// as the Dart-side identifier and store it here so subsequent
  /// `reportCallConnected` / `reportCallEnded` find the same record.
  /// Cleared on call end.
  String? _activeCallKitId;
  bool _initialized = false;

  /// Maps native inviteID → friendNumber for active native ToxAV calls.
  final Map<String, int> _nativeCallFriendNumbers = {};

  /// Called when a call ends, to insert a call record into the chat.
  /// Parameters: (remoteUserID, isVideo, isOutgoing, durationSeconds, endReason)
  /// endReason: 'hangup' | 'cancel' | 'reject' | 'timeout' | 'network_error'
  ///
  /// 'network_error' is used when the reconnect grace period expires — the
  /// call was connected and then irrecoverably dropped by the transport.
  /// Consumers that don't know the value treat it as a generic end (see
  /// `lib/sdk_fake/fake_uikit_core.dart` — defaults to actionType=hangup).
  void Function(
    String remoteUserID,
    bool isVideo,
    bool isOutgoing,
    int durationSeconds,
    String endReason,
  )?
  onCallRecordNeeded;

  /// Prevents duplicate call record emissions per call.
  bool _callRecordEmitted = false;
  final ValueNotifier<CallUiNotice?> uiNotice = ValueNotifier(null);
  int _nextNoticeId = 0;

  /// Monotonic generation token bumped on every call-end path. Used by
  /// [_startMediaCapture] to detect that a hang-up landed mid-init and tear
  /// down any partial capture state instead of leaving the audio/video
  /// handlers stuck with `_capturing = true`.
  int _captureGeneration = 0;

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

  /// Whether the Android foreground service has been elevated to phoneCall
  /// mode for the currently-active call. Tracked so back-to-back
  /// enterCall/endCall transitions don't fire spurious restore events and
  /// so an out-of-order end (e.g. ended before we ever entered inCall on
  /// the signaling path) doesn't leave the service stuck in phoneCall mode.
  bool _foregroundElevated = false;

  /// Elevate the Android foreground service to `phoneCall` mode for the
  /// duration of the active call. Idempotent. Localized via the user's
  /// currently-selected locale (no [BuildContext] needed at this layer).
  void _elevateForegroundForCall() {
    if (_foregroundElevated) return;
    _foregroundElevated = true;
    try {
      final l10n = lookupAppLocalizations(AppLocale.locale.value);
      final callerName =
          _callState.remoteNickname ?? _callState.remoteUserID ?? '';
      final body = callerName.isEmpty
          ? l10n.runtimeForegroundCallBody
          : l10n.runtimeForegroundCallBodyWithCaller(callerName);
      unawaited(
        RuntimeForegroundService.instance.elevateToCall(
          title: l10n.runtimeForegroundCallTitle,
          body: body,
          settingsLabel: l10n.runtimeForegroundSettingsLabel,
        ),
      );
    } catch (e, st) {
      AppLogger.warn(
        '[CallServiceManager] _elevateForegroundForCall failed: $e\n$st',
      );
    }
  }

  /// Restore the Android foreground service to dataSync mode at end-of-call.
  /// Idempotent — only fires if we previously elevated.
  void _restoreForegroundAfterCall() {
    if (!_foregroundElevated) return;
    _foregroundElevated = false;
    try {
      final l10n = lookupAppLocalizations(AppLocale.locale.value);
      unawaited(
        RuntimeForegroundService.instance.restoreFromCall(
          title: l10n.runtimeForegroundTitle,
          body: l10n.runtimeForegroundBody,
          settingsLabel: l10n.runtimeForegroundSettingsLabel,
        ),
      );
    } catch (e, st) {
      AppLogger.warn(
        '[CallServiceManager] _restoreForegroundAfterCall failed: $e\n$st',
      );
    }
  }

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
      remoteUserID,
      isVideo,
      isOutgoing,
      durationSeconds,
      endReason,
    );
  }

  /// Fire-and-forget OS-level missed-call notification. Reads peer info from
  /// the current call state, so call this *before* `_callState.endCall()`
  /// (which clears `remoteUserID` / `remoteNickname`). Safe to call when the
  /// notification service isn't initialised — the service itself no-ops on
  /// unsupported platforms and self-initialises on first use.
  void _emitMissedCallNotification() {
    final peerId = _callState.remoteUserID;
    if (peerId == null || peerId.isEmpty) return;
    final displayName = _callState.remoteNickname ?? peerId;
    final wasVideo = _callState.mode == CallMode.video;
    unawaited(
      NotificationService.instance.showMissedCallNotification(
        peerId: peerId,
        displayName: displayName,
        wasVideo: wasVideo,
      ),
    );
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
    bool? ffiOnline;
    try {
      final friends = await _chatService.getFriendList();
      for (final f in friends) {
        if (compareToxIds(f.userId, userID)) {
          ffiOnline = f.online;
          break;
        }
      }
    } catch (_) {
      ffiOnline = null;
    }
    if (ffiOnline == true) {
      return true;
    }
    // Call buttons in the real UI already gate on UIKit's contact-status cache.
    // During multi-instance restored runs we've observed brief skew where the
    // UI cache has already refreshed the friend to online while
    // `_chatService.getFriendList()` still reports offline/missing, which causes
    // `_onOutgoingCallInitiated` to auto-cancel a call the UI just allowed to
    // start. Use the UIKit cache as a fallback so the auto-cancel decision stays
    // aligned with what the user just saw and tapped.
    final uikitOnline = TencentCloudChat.instance.dataInstance.contact
        .getOnlineStatusByUserId(userID: userID);
    AppLogger.info(
      '[CallServiceManager] _isFriendOnline userID=$userID '
      'ffiOnline=$ffiOnline uikitOnline=$uikitOnline',
    );
    if (uikitOnline) {
      return true;
    }
    // Fail-closed only after both sources say "not online" (or the FFI source
    // failed to answer and UIKit also has no online signal).
    return ffiOnline ?? false;
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
  ///
  /// Production wiring: [_checkPeerTransport] (a 1s watchdog active while
  /// inCall/reconnecting) samples the friend's Tox transport state via
  /// ToxAVService.getFriendConnectionStatus and drives this on the
  /// offline edge; the L3 harness (`l3_call_action('network_drop')`) drives
  /// it synthetically. The ToxAV friend_call_state bitfield itself cannot
  /// distinguish "reconnecting" from "ended", hence the sampling approach.
  void markReconnecting() {
    if (_callState.state != CallUIState.inCall &&
        _callState.state != CallUIState.reconnecting) {
      return;
    }
    _callState.setState(CallUIState.reconnecting);
    // Drop bitrate samples so the transport-down dip doesn't pin the indicator
    // at poor after recovery, and so _applyPeerSuggestedProfile won't latch a
    // floor-tier profile based on stale-during-blackout samples.
    _qualityEstimator.reset();
    _callState.setCallQuality(CallQuality.unknown);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectGrace, () {
      if (_callState.state == CallUIState.reconnecting) {
        debugPrint('[CallServiceManager] reconnect grace expired, ending call');
        // 'network_error' rather than 'hangup' — the call was dropped by the
        // transport, not user-terminated. Surfacing this distinctly lets the
        // UI / history layer label the record accurately.
        //
        // We intentionally do NOT fire a missed-call notification here:
        // reconnect grace expiry means the user was already on a connected
        // call that dropped, so the call UI was on screen the entire time
        // (or in PiP) and they saw the drop. A "missed call" notification
        // would be misleading — they didn't miss anything; their call ended
        // unexpectedly. Surfacing the drop only via the call record is the
        // less-noisy, more accurate signal. (A distinct "call dropped" OS
        // notification could be added later if telemetry shows users want it.)
        _emitCallRecord('network_error');
        unawaited(_callKitReportEnded('network_error'));
        _endCallCleanup();
        _callState.endCall();
        _restoreForegroundAfterCall();
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

  /// Whether the loaded native library has a real ToxAV backend. False for
  /// stub builds (BUILD_TOXAV off) and for libraries predating the
  /// availability probe — conservative "calls off" in both cases, so the UI
  /// never offers a call button that would silently no-op.
  bool get isCallingAvailable => _avService?.isAvailable ?? false;

  Future<void> initialize() async {
    if (_initialized) return;

    final logger = AppLoggerAdapter();
    _avService = ToxAVService(_chatService.tim2toxFfi, logger: logger);
    if (!_avService!.isAvailable) {
      AppLogger.warn(
        '[CallServiceManager] native library has no ToxAV backend '
        '(stub build) — calling disabled, skipping call-system init',
      );
      _initialized = true;
      return;
    }
    await _avService!.initialize();

    _callBridge = CallBridgeService(
      TencentCloudChatSdkPlatform.instance,
      _avService!,
      logger: logger,
    );

    _adapter = await TUICallKitAdapter.initialize(
      TencentCloudChatSdkPlatform.instance,
      _avService!,
      _callBridge!,
      logger: logger,
    );
    registerToxAVWithTUICore(_adapter!);
    _adapter!.isCallIdle = () => _callState.state == CallUIState.idle;

    _callBridge!.onCallStateChanged = _onCallStateChanged;
    _adapter!.onOutgoingCallInitiated = _onOutgoingCallInitiated;
    _adapter!.onBeforeOutgoingCall = _preflightOutgoingCall;
    _adapter!.onCallSetupFailed = _onCallSetupFailed;
    _avService!.setCallCallback(_onIncomingCall);
    _avService!.setCallStateCallback(_onCallState);
    _avService!.setAudioBitrateChangedCallback(_onAudioBitrateChanged);
    _avService!.setVideoBitrateChangedCallback(_onVideoBitrateChanged);
    _avService!.setAudioReceiveCallback(_audioHandler.onAudioReceived);
    _avService!.setVideoReceiveCallback(_videoHandler.onVideoReceived);
    await _callAudioPlatform.initialize();
    _audioPlatformSub?.cancel();
    _audioPlatformSub = _callAudioPlatform.events.listen(_onAudioPlatformEvent);

    _callKitSub?.cancel();
    _callKitSub = _callKit.userActions.listen(_onCallKitAction);

    // AV poll boost: toxav_iterate rides FfiChatService's adaptive poll loop,
    // which relaxes to 1000ms when the text side is idle — starving RTP
    // receive/call-state progress mid-call. Track the UI call state (the
    // single source of truth every path funnels into: signaling, native
    // ToxAV, CallKit actions) and pin the fast cadence for the whole call
    // lifecycle.
    _callState.addListener(_syncAvPollBoost);
    // Reconnect watchdog: ToxAV has no discrete "transport down" callback
    // (the friend_call_state bitfield can't distinguish reconnecting from
    // ended), so sample the friend's Tox transport state during active calls
    // and drive markReconnecting/clearReconnecting from the edges.
    _callState.addListener(_syncReconnectWatchdog);

    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // CallKit bridge helpers (iOS only; no-op elsewhere)
  // ---------------------------------------------------------------------------

  /// Forward a CallKit system-UI action (Answer / End / Mute) to the same
  /// code paths the in-app UI uses, so call state stays single-sourced.
  ///
  /// `callId` is the Tox invite ID; we ignore actions whose callId doesn't
  /// match the currently-active call (covers stale callbacks fired after we
  /// already locally ended). Empty callId means CallKit was reset — tear
  /// down whatever's live.
  void _onCallKitAction(CallKitAction action) {
    debugPrint('[CallServiceManager] CallKit action: $action');
    final activeId = _callState.inviteID;
    if (action.callId.isEmpty) {
      if (activeId != null) unawaited(hangUp());
      return;
    }
    if (activeId != null && action.callId != activeId) {
      debugPrint(
        '[CallServiceManager] CallKit action for stale callId ${action.callId}; ignoring',
      );
      return;
    }
    switch (action.kind) {
      case CallKitActionKind.answer:
        unawaited(acceptCall());
        break;
      case CallKitActionKind.end:
        // If we're ringing as the callee, treat CallKit "End" as a reject so
        // the record reflects the user's intent. Otherwise it's a hang-up.
        if (_callState.state == CallUIState.ringing &&
            _callState.direction == CallDirection.incoming) {
          unawaited(rejectCall());
        } else {
          unawaited(hangUp());
        }
        break;
      case CallKitActionKind.mute:
        final requested = action.muted ?? !_callState.isMuted;
        if (requested != _callState.isMuted) {
          unawaited(toggleMute());
        }
        break;
      case CallKitActionKind.start:
      case CallKitActionKind.unknown:
        break;
    }
  }

  /// Report an incoming or outgoing call to CallKit so the system call UI
  /// shows up. iOS-only; no-op elsewhere. `_activeCallKitId` tracks the
  /// session id so subsequent connected/ended reports find the same record.
  Future<void> _callKitReportRinging({
    required String callId,
    required String displayName,
    required bool hasVideo,
    required bool incoming,
  }) async {
    if (!_callKit.isSupported) return;
    _activeCallKitId = callId;
    if (incoming) {
      await _callKit.reportIncomingCall(
        callId: callId,
        displayName: displayName,
        hasVideo: hasVideo,
      );
    } else {
      await _callKit.reportOutgoingCall(
        callId: callId,
        displayName: displayName,
        hasVideo: hasVideo,
      );
    }
  }

  Future<void> _callKitReportConnected() async {
    final id = _activeCallKitId;
    if (id == null || !_callKit.isSupported) return;
    await _callKit.reportCallConnected(callId: id);
  }

  Future<void> _callKitReportEnded(String reason) async {
    final id = _activeCallKitId;
    if (id == null || !_callKit.isSupported) return;
    _activeCallKitId = null;
    await _callKit.reportCallEnded(callId: id, reason: reason);
  }

  // ---------------------------------------------------------------------------
  // Signaling-path callbacks (UIKit)
  // ---------------------------------------------------------------------------

  /// Called when the user initiates an outgoing call via the UIKit call button.
  void _onOutgoingCallInitiated(
    String inviteID,
    String userID,
    String type,
  ) async {
    AppLogger.info(
      '[CallServiceManager] outgoing initiated inviteID=$inviteID '
      'userID=$userID type=$type state=${_callState.state}',
    );
    debugPrint(
      '[CallServiceManager] _onOutgoingCallInitiated: inviteID=$inviteID, userID=$userID, type=$type, currentState=${_callState.state}',
    );
    final nickname = await _resolveNickname(userID);
    // The adapter continues past this callback into startCall(); if that
    // fails it tears the invite down via CallBridgeService.endCall → our
    // ended handler. The nickname await above can resume AFTER that cleanup
    // — re-opening a ringing overlay for a dead invite. Only start ringing
    // if the bridge still tracks the invite.
    if (_callBridge?.getCallInfo(inviteID) == null) {
      AppLogger.info(
        '[CallServiceManager] outgoing invite $inviteID ended during '
        'nickname resolution — not showing ringing UI',
      );
      return;
    }
    _callRecordEmitted = false;
    _callState.startRinging(
      mode: type == TYPE_VIDEO ? CallMode.video : CallMode.audio,
      direction: CallDirection.outgoing,
      inviteID: inviteID,
      remoteUserID: userID,
      remoteNickname: nickname,
    );
    // Surface in the iOS system call UI so the user can see / interact with
    // the outgoing call from the lock screen / AirPods. No-op off-iOS.
    unawaited(
      _callKitReportRinging(
        callId: inviteID,
        displayName: nickname ?? userID,
        hasVideo: type == TYPE_VIDEO,
        incoming: false,
      ),
    );
    debugPrint(
      '[CallServiceManager] _onOutgoingCallInitiated: after startRinging, state=${_callState.state}',
    );

    // Check friend online status — auto-cancel if offline
    final isOnline = await _isFriendOnline(userID);
    if (!isOnline && _callState.state == CallUIState.ringing) {
      debugPrint(
        '[CallServiceManager] Friend $userID is offline, auto-ending call after brief delay',
      );
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

  void _onCallStateChanged(
    String inviteID,
    CallState state, {
    String? endReason,
  }) async {
    AppLogger.info(
      '[CallServiceManager] signaling state inviteID=$inviteID '
      'state=$state endReason=$endReason currentUiState=${_callState.state}',
    );
    switch (state) {
      case CallState.ringing:
        final callInfo = _callBridge!.getCallInfo(inviteID);
        if (callInfo != null) {
          final nickname = await _resolveNickname(callInfo.inviter);
          _callRecordEmitted = false;
          final isVideo = callInfo.data.contains('"video":true');
          _callState.startRinging(
            mode: isVideo ? CallMode.video : CallMode.audio,
            direction: CallDirection.incoming,
            inviteID: inviteID,
            remoteUserID: callInfo.inviter,
            remoteNickname: nickname,
          );
          if (isVideo && !CallMediaCapabilities.supportsVideoCapture()) {
            // Receive-only video on camera-less platforms: remote renders,
            // local camera is never advertised as on.
            _callState.disableLocalVideo();
          }
          unawaited(
            _callKitReportRinging(
              callId: inviteID,
              displayName: nickname ?? callInfo.inviter,
              hasVideo: isVideo,
              incoming: true,
            ),
          );
          _ringtone.start(); // incoming call ringtone
        }
        break;
      case CallState.inCall:
        _ringtone.stop();
        _callState.enterCall();
        unawaited(_callKitReportConnected());
        _elevateForegroundForCall();
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
        // Prefer the bridge-supplied endReason (reject/hangup/timeout/cancel).
        // Fall back to the pre-Fix-Y heuristic when the bridge omits it so
        // legacy code paths keep producing a sensible record.
        final resolvedEndReason =
            endReason ??
            (_callState.state == CallUIState.inCall ? 'hangup' : 'cancel');
        // Missed-call OS banner: an incoming ring that ended without us
        // entering inCall is a missed call from the user's perspective.
        // ('reject' means the user explicitly rejected — don't re-notify on
        // that path; the user is already aware.)
        final wasIncomingRing =
            _callState.state == CallUIState.ringing &&
            _callState.direction == CallDirection.incoming &&
            resolvedEndReason != 'reject';
        _emitCallRecord(resolvedEndReason);
        if (wasIncomingRing) {
          _emitMissedCallNotification();
        }
        unawaited(_callKitReportEnded(resolvedEndReason));
        _endCallCleanup();
        _callState.endCall();
        _restoreForegroundAfterCall();
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
    int friendNumber,
    bool audioEnabled,
    bool videoEnabled,
  ) async {
    AppLogger.info(
      '[CallServiceManager] native incoming friendNumber=$friendNumber '
      'audio=$audioEnabled video=$videoEnabled state=${_callState.state}',
    );
    // Ignore if already in a call.
    if (_callState.state != CallUIState.idle) {
      debugPrint(
        '[CallServiceManager] _onIncomingCall: ignored (not idle), friendNumber=$friendNumber',
      );
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
    unawaited(
      _callKitReportRinging(
        callId: inviteID,
        displayName: nickname ?? remoteUserID,
        hasVideo: videoEnabled,
        incoming: true,
      ),
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
      '[CallServiceManager] _onCallState: friendNumber=$friendNumber, state=$state',
    );

    // Error or finished → end the call
    if (state == stateError || state == stateFinished) {
      _ringtone.stop();
      _audioHandler.stop();
      _videoHandler.stop();
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      String nativeEndReason = 'hangup';
      // Emit call record before clearing state
      if (_callState.state == CallUIState.inCall ||
          _callState.state == CallUIState.reconnecting) {
        // ERROR is the transport telling us the link died (toxcore fires it
        // in the same iterate tick that declares the friend offline —
        // verified live by the S69 real-kill gate). Label the record
        // honestly: the peer did NOT hang up.
        if (state == stateError) {
          nativeEndReason = 'network_error';
          _emitCallRecord('network_error');
        } else {
          nativeEndReason = 'remote_hangup';
          _emitCallRecord('hangup');
        }
      } else if (_callState.state == CallUIState.ringing) {
        final wasIncoming = _callState.direction == CallDirection.incoming;
        nativeEndReason = wasIncoming ? 'cancel' : 'timeout';
        _emitCallRecord(nativeEndReason);
        // Incoming ring ended without local accept → that's a missed call
        // from the user's perspective. Fire an OS-level banner so they can
        // see it even if the app is in the background. Outgoing 'timeout'
        // is the caller's own ring-out, which the caller already saw, so we
        // don't notify there.
        if (wasIncoming) {
          _emitMissedCallNotification();
        }
      }
      unawaited(_callKitReportEnded(nativeEndReason));
      _endCallCleanup();
      _callState.endCall();
      _restoreForegroundAfterCall();
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
        unawaited(_callKitReportConnected());
        _elevateForegroundForCall();
        _startMediaCapture(friendNumber);
      } else if (_callState.state == CallUIState.reconnecting) {
        // Media is flowing again — recover from reconnecting state.
        clearReconnecting();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Call quality (from ToxAV peer-suggested bitrates)
  // ---------------------------------------------------------------------------

  /// Pure bitrate → CallQuality mapper. Kept as a member field rather than
  /// a static helper so call lifecycle (reset on end) maps cleanly.
  final CallQualityEstimator _qualityEstimator = CallQualityEstimator();

  void _onAudioBitrateChanged(int friendNumber, int audioBitRate) {
    debugPrint(
      '[CallServiceManager] _onAudioBitrateChanged: friendNumber=$friendNumber, audioBitRate=$audioBitRate',
    );
    // While reconnecting the transport is mid-recovery; peer-suggested values
    // here reflect the dip, not steady state. Skip estimator + profile entirely
    // so reset()/clearReconnecting() recovery isn't polluted by dirty samples.
    if (_callState.state == CallUIState.reconnecting) return;
    // Bit rate 0 means the peer disabled audio — that's a state change, not
    // a quality signal. Don't downgrade the indicator on a mute.
    if (!_qualityEstimator.observeAudioBitrate(audioBitRate)) return;
    _callState.setCallQuality(_qualityEstimator.currentQuality());
    _applyPeerSuggestedProfile(audioBitRate: audioBitRate);
  }

  void _onVideoBitrateChanged(int friendNumber, int videoBitRate) {
    debugPrint(
      '[CallServiceManager] _onVideoBitrateChanged: friendNumber=$friendNumber, videoBitRate=$videoBitRate',
    );
    if (_callState.state == CallUIState.reconnecting) return;
    if (!_qualityEstimator.observeVideoBitrate(videoBitRate)) return;
    _callState.setCallQuality(_qualityEstimator.currentQuality());
    _applyPeerSuggestedProfile(videoBitRate: videoBitRate);
  }

  /// Map a peer-suggested kbit/s value to the nearest [CallCodecProfile]
  /// tier and, when the tier changed, tell the local encoder + camera
  /// throttle to follow. This is the "adaptive" half of the spec: PR 2
  /// wires the callback up; this method translates the signal into
  /// encoder + capture-side changes.
  ///
  /// We only push to the encoder on a *tier change* (not every callback),
  /// because libtoxav debounces internally and re-setting the same target
  /// is wasted FFI overhead plus a small risk of confusing the codec
  /// rate-control loop.
  void _applyPeerSuggestedProfile({int? audioBitRate, int? videoBitRate}) {
    final fn = _getActiveFriendNumber();
    if (fn == null || _avService == null) return;

    final next = audioBitRate != null
        ? CallCodecProfile.fromAudioBitRate(audioBitRate)
        : CallCodecProfile.fromVideoBitRate(videoBitRate ?? 0);
    if (next == null) return;
    if (next.tier == _activeProfile.tier) return;

    _activeProfile = next;
    _videoHandler.setCodecProfile(next);
    // Mirror to libtoxav so our outgoing encoder follows the suggestion.
    _avService!.setAudioBitRate(fn, next.audioBitRate);
    if (_callState.mode == CallMode.video) {
      _avService!.setVideoBitRate(fn, next.videoBitRate);
    }
  }

  /// Currently-active profile. Starts at [CallCodecProfile.defaultProfile]
  /// and is mutated only by [_applyPeerSuggestedProfile].
  CallCodecProfile _activeProfile = CallCodecProfile.defaultProfile;

  // ---------------------------------------------------------------------------
  // Media capture
  // ---------------------------------------------------------------------------

  /// Request permissions and start audio/video capture for an active call.
  ///
  /// Race-safe against hang-up: callers fire-and-forget, and an async
  /// `startCapture` may still be initialising when the user (or peer) ends
  /// the call. In that case [_captureGeneration] has been bumped via
  /// [_endCallCleanup]; this method observes the change after each
  /// `startCapture` and explicitly tears down anything that did start, so
  /// `AudioHandler._capturing` / `VideoHandler._capturing` cannot get
  /// stranded as `true` past the call.
  Future<void> _startMediaCapture(int friendNumber) async {
    final gen = _captureGeneration;
    final avService = _avService;
    if (avService == null) return;
    try {
      await _audioHandler.startCapture(friendNumber, avService);
      if (gen != _captureGeneration) {
        // Hang-up landed while we were initialising the mic; tear it down.
        await _audioHandler.stop();
        return;
      }
      if (_callState.mode == CallMode.video &&
          CallMediaCapabilities.supportsVideoCapture()) {
        await _videoHandler.startCapture(friendNumber, avService);
        if (gen != _captureGeneration) {
          await _videoHandler.stop();
        }
      }
    } catch (e) {
      debugPrint('[CallServiceManager] _startMediaCapture error: $e');
      // Best-effort cleanup if something blew up mid-init.
      await _audioHandler.stop();
      await _videoHandler.stop();
    }
  }

  /// Called from every path that ends an active call (hang-up, reject,
  /// reconnect grace expiry, peer cancel, peer reject, signaling timeout,
  /// native CallState transitions to ended). Bumps [_captureGeneration] so
  /// any in-flight [_startMediaCapture] tears down on completion instead of
  /// leaving the audio/video handlers half-started.
  void _endCallCleanup() {
    _captureGeneration++;
    // Forget bitrate history so the next call starts at CallQuality.unknown
    // instead of inheriting the last call's last-seen value.
    _qualityEstimator.reset();
    // Reset adaptive-bitrate profile so the next call opens at mid-tier
    // again instead of stuck at whatever tier the previous call ended on.
    _activeProfile = CallCodecProfile.defaultProfile;
    _videoHandler.setCodecProfile(CallCodecProfile.defaultProfile);
  }

  Future<bool> _ensurePermissionsForCurrentMode() async {
    // Camera-less platforms accept video calls receive-only: local capture
    // never starts (see _startMediaCapture / acceptCall's videoBitRate 0),
    // so requesting camera permission would only block or reject an accept
    // that needs nothing but the microphone.
    final result = await CallPermissionHelper.requestPermissionsForCallDetailed(
      isVideo: _callState.mode == CallMode.video &&
          CallMediaCapabilities.supportsVideoCapture(),
    );
    if (!result.granted) {
      _emitPermissionNotice(result);
      debugPrint(
        '[CallServiceManager] Required call permissions denied for mode=${_callState.mode}',
      );
    }
    return result.granted;
  }

  Future<bool> _preflightOutgoingCall(String userID, String type) async {
    // Central video-capture gate: hidden buttons (useVideoCall) cover the
    // main surfaces, but the fork has other startVideoCall entry points
    // (call-record bubble tap, message row). Deny at setup so EVERY outgoing
    // video path on a camera-less platform (Windows/Linux) gets the notice
    // instead of a frame-less call.
    if (type == TYPE_VIDEO && !CallMediaCapabilities.supportsVideoCapture()) {
      _emitLocalizedUiNotice((l10n) => l10n.callVideoUnsupportedPlatform);
      return false;
    }
    final activeRemoteUserID = _callState.remoteUserID;
    final duplicateOutgoingRing =
        _callState.state == CallUIState.ringing &&
        _callState.direction == CallDirection.outgoing &&
        activeRemoteUserID != null &&
        compareToxIds(activeRemoteUserID, userID);
    if (duplicateOutgoingRing) {
      AppLogger.info(
        '[CallServiceManager] duplicate outgoing call suppressed '
        'userID=$userID state=${_callState.state} '
        'activeRemoteUserID=$activeRemoteUserID',
      );
      return false;
    }
    final result = await CallPermissionHelper.requestPermissionsForCallDetailed(
      isVideo: type == TYPE_VIDEO,
    );
    if (!result.granted) {
      _emitPermissionNotice(result);
    }
    return result.granted;
  }

  /// Outgoing-call setup failed inside the adapter. Historically these
  /// failures were swallowed (TUICore ignores handleCall's return value), so
  /// tapping a call button could simply do nothing. Surface everything except
  /// [CallSetupFailureReason.preflightDenied] — that one is our own decision
  /// (_preflightOutgoingCall already emitted the permission notice, and
  /// duplicate-ring suppression is intentionally silent).
  void _onCallSetupFailed(CallSetupFailureReason reason, List<String> userids) {
    AppLogger.warn(
        '[CallServiceManager] call setup failed: $reason userids=${userids.length}');
    switch (reason) {
      case CallSetupFailureReason.preflightDenied:
        return;
      case CallSetupFailureReason.groupCallsUnsupported:
        _emitLocalizedUiNotice((l10n) => l10n.callFailedGroupUnsupported);
      case CallSetupFailureReason.avStartFailed:
        _emitLocalizedUiNotice((l10n) => l10n.callFailedMediaChannel);
      case CallSetupFailureReason.noUsers:
      case CallSetupFailureReason.inviteFailed:
      case CallSetupFailureReason.internalError:
        _emitLocalizedUiNotice((l10n) => l10n.callFailedSignaling);
    }
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

  /// Single-flight queue tail for [syncPlatformEffectsForState]. Rapid call
  /// state transitions (e.g. ringing -> inCall within milliseconds) would
  /// otherwise fire concurrent activate/deactivate platform-channel calls,
  /// leaving the audio session in an indeterminate state. We chain each new
  /// sync onto the tail of the previous one so they execute strictly in order.
  Future<void>? _pendingSync;

  Future<void> syncPlatformEffectsForState(CallUIState state) {
    final next = (_pendingSync ?? Future<void>.value())
        // Don't poison the chain if a prior sync threw — but record the failure
        // so it doesn't vanish silently.
        .catchError((Object e, StackTrace st) {
          AppLogger.warn(
            '[CallServiceManager] previous platform-effects sync failed: $e',
          );
        })
        .then((_) => _doSyncPlatformEffectsForState(state));
    _pendingSync = next;
    return next;
  }

  Future<void> _doSyncPlatformEffectsForState(CallUIState state) async {
    if (!_callAudioPlatform.isSupported) {
      return;
    }

    if (state == CallUIState.ringing ||
        state == CallUIState.inCall ||
        state == CallUIState.reconnecting) {
      final preferSpeaker = state == CallUIState.reconnecting
          ? _callState.isSpeakerOn
          : state == CallUIState.ringing || _callState.mode == CallMode.video;
      await _callAudioPlatform.activateSession(preferSpeaker: preferSpeaker);
      return;
    }

    await _callAudioPlatform.deactivateSession();
  }

  @override
  Future<void> selectAudioRoute(String routeId) async {
    await _callAudioPlatform.selectRoute(routeId);
  }

  /// Most-recently-seen audio route kind. Tracked across `routeChanged`
  /// events so a Bluetooth-disconnect transition (e.g. AirPods walked out of
  /// range) can surface a user-visible notice — without firing the notice
  /// for every user-initiated route switch.
  CallAudioRouteKind? _lastRouteKind;

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
      case CallAudioEventKind.routeChanged:
        // Surface a notice only when the previously-active route was
        // Bluetooth and the new route is *not* — i.e. the headset went away
        // unexpectedly, the OS reverted to earpiece/speaker, and the user
        // should know the call audio moved. User-initiated route switches
        // (kind A → kind B where neither is Bluetooth, or earpiece →
        // bluetooth pair-up) stay silent.
        final newKind = event.state?.selectedRoute?.kind;
        final previousWasBluetooth =
            _lastRouteKind == CallAudioRouteKind.bluetooth;
        final newIsBluetooth = newKind == CallAudioRouteKind.bluetooth;
        if (previousWasBluetooth && !newIsBluetooth) {
          _emitLocalizedUiNotice(
            (l10n) => l10n.callAudioInterrupted,
            offerSettings: false,
          );
        }
        _lastRouteKind = newKind;
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
    final callInfo = inviteID != null
        ? _callBridge?.getCallInfo(inviteID)
        : null;
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
        final profile = isVideo
            ? CallCodecProfile.defaultProfile
            : CallCodecProfile.defaultProfile.audioOnly();
        // Camera-less platforms answer video calls receive-only: bitRate 0
        // tells the peer we won't send video (we still decode theirs).
        // Audio-only profiles already carry videoBitRate 0.
        final sendVideoBitRate =
            isVideo && CallMediaCapabilities.supportsVideoCapture()
                ? profile.videoBitRate
                : 0;
        await _avService!.answerCall(
          fn,
          audioBitRate: profile.audioBitRate,
          videoBitRate: sendVideoBitRate,
        );
        // Immediately enter call state and start media
        _ringtone.stop();
        _callState.enterCall();
        unawaited(_callKitReportConnected());
        _elevateForegroundForCall();
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
    unawaited(_callKitReportEnded('reject'));
    _endCallCleanup();

    if (_isNativeCall(inviteID)) {
      // Native ToxAV path — reject via toxav_call_control(CANCEL)
      final fn = _getNativeFriendNumber(inviteID);
      if (fn != null && _avService != null) {
        await _avService!.endCall(fn);
      }
      _ringtone.stop();
      _callState.endCall();
      _restoreForegroundAfterCall();
      _cleanupNativeCall();
    } else {
      await _callBridge?.rejectInvitation(inviteID);
      _ringtone.stop();
      _callState.endCall();
      _restoreForegroundAfterCall();
    }
  }

  @override
  Future<void> hangUp() async {
    final inviteID = _callState.inviteID;
    if (inviteID == null) return;

    // Always cancel any pending reconnect timer — the user explicitly hung up,
    // so the grace-period recovery is moot. Without this the timer can fire
    // later, emit a stale 'network_error' record and re-trigger cleanup on an
    // already-ended call.
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Emit call record before clearing state. `reconnecting` is treated like
    // `inCall` here — the call was connected from the user's perspective and
    // they're choosing to end it during the transient drop, not cancel an
    // unanswered ring.
    String hangUpReason = 'hangup';
    if (_callState.state == CallUIState.inCall ||
        _callState.state == CallUIState.reconnecting) {
      _emitCallRecord('hangup');
    } else if (_callState.state == CallUIState.ringing &&
        _callState.direction == CallDirection.outgoing) {
      hangUpReason = 'cancel';
      _emitCallRecord('cancel');
    }
    unawaited(_callKitReportEnded(hangUpReason));
    // Bump generation BEFORE issuing endCall so any in-flight
    // _startMediaCapture observes the change and tears itself down.
    _endCallCleanup();

    if (_isNativeCall(inviteID)) {
      // Native ToxAV path
      final fn = _getNativeFriendNumber(inviteID);
      if (fn != null && _avService != null) {
        await _avService!.endCall(fn);
      }
      _audioHandler.stop();
      _videoHandler.stop();
      _callState.endCall();
      _restoreForegroundAfterCall();
      _cleanupNativeCall();
    } else {
      await _callBridge?.endCall(inviteID);
      _ringtone.stop();
      _audioHandler.stop();
      _videoHandler.stop();
      _callState.endCall();
      _restoreForegroundAfterCall();
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
      final callInfo = inviteID != null
          ? _callBridge?.getCallInfo(inviteID)
          : null;
      if (callInfo?.friendNumber != null) {
        await _avService?.muteAudio(
          callInfo!.friendNumber!,
          _callState.isMuted,
        );
      }
    }
  }

  @override
  Future<void> toggleSpeaker() async {
    _callState.toggleSpeaker();
    if (!_callAudioPlatform.isSupported) return;
    final preferSpeaker = _callState.isSpeakerOn;
    try {
      await _callAudioPlatform.activateSession(preferSpeaker: preferSpeaker);
    } catch (e) {
      AppLogger.warn(
        '[CallServiceManager] toggleSpeaker activateSession failed: $e',
      );
    }
  }

  @override
  Future<void> toggleVideo() async {
    final enableVideo = !_callState.isVideoEnabled;
    if (enableVideo) {
      if (!CallMediaCapabilities.supportsVideoCapture()) {
        // Windows/Linux have no camera capture backend — enabling the camera
        // would silently send no frames (see VideoHandler's
        // MissingPluginException fallback). Tell the user instead.
        _emitLocalizedUiNotice((l10n) => l10n.callVideoUnsupportedPlatform);
        return;
      }
      final result =
          await CallPermissionHelper.requestPermissionsForCallDetailed(
            isVideo: true,
          );
      if (!result.granted) {
        _emitPermissionNotice(result);
        debugPrint(
          '[CallServiceManager] Video permission denied while enabling camera',
        );
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

  bool _avPollBoosted = false;

  void _syncAvPollBoost() {
    final boost = _callState.state == CallUIState.ringing ||
        _callState.state == CallUIState.inCall ||
        _callState.state == CallUIState.reconnecting;
    if (boost == _avPollBoosted) return;
    _avPollBoosted = boost;
    _chatService.setAvSessionActive(boost);
  }

  Timer? _peerTransportWatchdog;

  /// True when the *watchdog* moved the call into reconnecting. The watchdog
  /// may only auto-clear a reconnecting state it set itself: external
  /// callers (the L3 harness's synthetic network_drop) mark reconnecting
  /// while the peer transport is genuinely up, and auto-clearing their state
  /// within a second would break the driven state machine.
  bool _watchdogMarkedReconnecting = false;

  void _syncReconnectWatchdog() {
    final active = _callState.state == CallUIState.inCall ||
        _callState.state == CallUIState.reconnecting;
    if (active && _peerTransportWatchdog == null) {
      _peerTransportWatchdog = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _checkPeerTransport(),
      );
    } else if (!active && _peerTransportWatchdog != null) {
      _peerTransportWatchdog!.cancel();
      _peerTransportWatchdog = null;
      _watchdogMarkedReconnecting = false;
    }
  }

  void _checkPeerTransport() {
    final friendNumber = _getActiveFriendNumber();
    if (friendNumber == null) return;
    final status = _avService?.getFriendConnectionStatus(friendNumber) ?? -1;
    if (status == 0 && _callState.state == CallUIState.inCall) {
      // Offline EDGE only: markReconnecting re-arms its grace timer on every
      // call, so invoking it each tick while the peer stays offline would
      // push the deadline out forever and the call would never time out.
      AppLogger.warn(
        '[CallServiceManager] peer transport lost (friend=$friendNumber) — reconnecting',
      );
      _watchdogMarkedReconnecting = true;
      markReconnecting();
    } else if (status > 0 &&
        _callState.state == CallUIState.reconnecting &&
        _watchdogMarkedReconnecting) {
      AppLogger.info(
        '[CallServiceManager] peer transport restored (friend=$friendNumber)',
      );
      _watchdogMarkedReconnecting = false;
      clearReconnecting();
    }
    // status < 0 (unknown/old lib): stay quiet — no evidence either way.
  }

  void dispose() {
    _callState.removeListener(_syncAvPollBoost);
    _callState.removeListener(_syncReconnectWatchdog);
    _peerTransportWatchdog?.cancel();
    _peerTransportWatchdog = null;
    if (_avPollBoosted) {
      _avPollBoosted = false;
      _chatService.setAvSessionActive(false);
    }
    _ringtone.stop();
    _ringtone.dispose();
    _audioHandler.stop();
    _videoHandler.stop();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    uiNotice.dispose();
    _audioPlatformSub?.cancel();
    _callKitSub?.cancel();
    _callKitSub = null;
    unawaited(_callAudioPlatform.dispose());
    _nativeCallFriendNumbers.clear();
    _avService?.shutdown();
    _callBridge?.dispose();
    _adapter?.dispose();
  }
}
