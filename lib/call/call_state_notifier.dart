import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

enum CallMode { audio, video }

enum CallDirection { outgoing, incoming }

enum CallUIState { idle, ringing, inCall, reconnecting, ended }

/// Read-only call quality for UI display. Defaults to [unknown] until backend provides metrics.
enum CallQuality { good, medium, poor, unknown }

class CallStateNotifier extends ChangeNotifier {
  CallUIState _state = CallUIState.idle;
  CallMode _mode = CallMode.audio;
  CallDirection _direction = CallDirection.outgoing;
  String? _inviteID;
  String? _remoteUserID;
  String? _remoteNickname;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = true;
  Duration _callDuration = Duration.zero;
  Timer? _durationTimer;
  Timer? _endedResetTimer;
  bool _isMinimized = false;
  Offset _floatingPosition = const Offset(16, 80);
  CallQuality _callQuality = CallQuality.unknown;

  CallUIState get state => _state;
  CallMode get mode => _mode;
  CallDirection get direction => _direction;
  String? get inviteID => _inviteID;
  String? get remoteUserID => _remoteUserID;
  String? get remoteNickname => _remoteNickname;
  bool get isMuted => _isMuted;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isSpeakerOn => _isSpeakerOn;
  Duration get callDuration => _callDuration;
  bool get isMinimized => _isMinimized;
  Offset get floatingPosition => _floatingPosition;

  /// Call quality for in-call indicator. Defaults to [CallQuality.unknown];
  /// CallServiceManager pushes updates via [setCallQuality] from AV-layer events.
  CallQuality get callQuality => _callQuality;

  /// Update the call-quality indicator. Safe to call from any state — UI
  /// observers re-render only when the value actually changes.
  void setCallQuality(CallQuality q) {
    if (_callQuality == q) return;
    _callQuality = q;
    _safeNotifyListeners();
  }

  /// Push a UI-level call state from outside (e.g. SDK reconnect/recovery
  /// events). Most transitions still go through dedicated methods like
  /// [startRinging] / [enterCall] / [endCall]; this is intended for the
  /// reconnecting intermediate state.
  void setState(CallUIState state) {
    if (_state == state) return;
    _state = state;
    _safeNotifyListeners();
  }

  /// True when the underlying transport is briefly down mid-call — UI should
  /// surface a "Reconnecting…" affordance while we wait for recovery rather
  /// than tear the call screen down.
  // TODO: wire CallServiceManager quality/state events into reconnecting
  bool get isReconnecting => _state == CallUIState.reconnecting;

  /// Notify listeners now or after this frame to avoid setState/markNeedsBuild during build.
  void _safeNotifyListeners() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  bool _isDisposed = false;

  void startRinging({
    required CallMode mode,
    required CallDirection direction,
    required String inviteID,
    required String remoteUserID,
    String? remoteNickname,
  }) {
    debugPrint(
        '[CallStateNotifier] startRinging: mode=$mode, direction=$direction, inviteID=$inviteID, remoteUserID=$remoteUserID, prevState=$_state');
    _state = CallUIState.ringing;
    _mode = mode;
    _direction = direction;
    _inviteID = inviteID;
    _remoteUserID = remoteUserID;
    _remoteNickname = remoteNickname;
    _isMuted = false;
    _isVideoEnabled = mode == CallMode.video;
    _isMinimized = false;
    _safeNotifyListeners();
    debugPrint(
        '[CallStateNotifier] startRinging: notifyListeners() called, state=$_state');
  }

  void enterCall() {
    _state = CallUIState.inCall;
    _callDuration = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDuration += const Duration(seconds: 1);
      notifyListeners();
    });
    _safeNotifyListeners();
  }

  void endCall() {
    _state = CallUIState.ended;
    _isMinimized = false;
    _callQuality = CallQuality.unknown;
    _durationTimer?.cancel();
    _endedResetTimer?.cancel();
    _safeNotifyListeners();
    // Auto-reset to idle after 2 seconds (cancellable to avoid post-dispose assertion)
    _endedResetTimer = Timer(const Duration(seconds: 2), () {
      if (_state == CallUIState.ended) {
        _state = CallUIState.idle;
        _inviteID = null;
        _remoteUserID = null;
        if (!_isDisposed) notifyListeners();
      }
    });
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  void toggleVideo() {
    _isVideoEnabled = !_isVideoEnabled;
    notifyListeners();
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    notifyListeners();
  }

  void minimize() {
    _isMinimized = true;
    notifyListeners();
  }

  void restore() {
    _isMinimized = false;
    notifyListeners();
  }

  void updateFloatingPosition(Offset position) {
    _floatingPosition = position;
    // No notifyListeners() — drag handled by local setState in floating widget
  }

  @override
  void dispose() {
    _isDisposed = true;
    _durationTimer?.cancel();
    _endedResetTimer?.cancel();
    super.dispose();
  }
}
