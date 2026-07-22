import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../util/logger.dart';

/// User-initiated actions reported by CallKit's system UI (lock screen,
/// in-call screen, Apple Watch, AirPods). Forwarded from native to Dart over
/// `toxee/callkit`'s `onCallKitAction` method.
enum CallKitActionKind { answer, end, mute, start, unknown }

class CallKitAction {
  final CallKitActionKind kind;

  /// The Dart-side call identifier (Tox invite ID, e.g. `native_av_<n>` or a
  /// signaling invite UUID). Never the CallKit UUID — the CallKit UUID lives
  /// entirely on the native side; Dart never sees it.
  final String callId;

  /// For [CallKitActionKind.mute] events: the muted state CallKit is
  /// requesting (i.e. user tapped mute → `true`, tapped unmute → `false`).
  /// `null` for other actions.
  final bool? muted;

  const CallKitAction({required this.kind, required this.callId, this.muted});

  @override
  String toString() =>
      'CallKitAction(kind: $kind, callId: $callId, muted: $muted)';
}

/// End-reason strings shared with native (`CallKitProvider.mapReason`). Keep
/// in sync with the Dart-side `CallServiceManager._emitCallRecord` vocabulary.
class CallKitEndReason {
  static const String hangup = 'hangup';
  static const String cancel = 'cancel';
  static const String reject = 'reject';
  static const String timeout = 'timeout';
  static const String networkError = 'network_error';
  static const String remoteHangup = 'remote_hangup';
}

/// Thin Dart wrapper around the native CallKit provider. iOS-only. On every
/// other platform every method short-circuits and the action stream is empty.
///
/// One instance is enough for the whole app; consumers should reuse the
/// `instance` singleton.
class CallKitBridge {
  CallKitBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('toxee/callkit') {
    _actions = StreamController<CallKitAction>.broadcast(
      onListen: _drainPendingActions,
    );
    if (isSupported) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  static final CallKitBridge instance = CallKitBridge();

  final MethodChannel _channel;
  late final StreamController<CallKitAction> _actions;

  /// Upper bound for the pre-subscription buffer. CallKit cannot legitimately
  /// queue more than a few actions before any listener is wired (incoming
  /// answer, then maybe a follow-up end). 8 is generous and bounds memory if
  /// something pathological happens (e.g. a runaway native loop emitting
  /// duplicates).
  static const int _kMaxPendingActions = 8;

  /// Pre-subscription buffer for actions that arrive before [userActions] has
  /// any listener (e.g. lock-screen Answer fires before
  /// `CallServiceManager.initialize` subscribes). Drained into the broadcast
  /// stream on the first `onListen`, then cleared. After that, this list
  /// stays empty — broadcast semantics handle subsequent late subscribers.
  final List<CallKitAction> _pendingActions = <CallKitAction>[];

  /// Becomes true once the broadcast stream has had at least one subscriber
  /// since construction. Used to decide whether incoming actions should be
  /// buffered (no listener yet) or forwarded directly.
  bool _hasEverHadListener = false;

  /// Whether the native bridge is wired on this platform. Anything other
  /// than iOS short-circuits — this includes tests, macOS, Android (which has
  /// its own ConnectionService/full-screen-intent path).
  bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Stream of user actions originating from the CallKit system UI.
  Stream<CallKitAction> get userActions => _actions.stream;

  /// Generate a stable call identifier for a new CallKit session. CallKit
  /// itself requires UUIDs on the native side; Dart uses whatever identifier
  /// the call layer already has (Tox invite ID). When the call layer doesn't
  /// have one — e.g. an outgoing call before the bridge service mints an
  /// invite ID — callers can use this helper to make a Dart-side handle.
  static String generateCallId() {
    // RFC4122 v4-ish: 16 random bytes, lay them out as
    // xxxxxxxx-xxxx-4xxx-Yxxx-xxxxxxxxxxxx (Y in {8,9,a,b}). We don't pull in
    // `package:uuid` just for this — the only consumer is CallKit-side
    // identification, never persisted.
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).toList();
    return '${h.sublist(0, 4).join()}-${h.sublist(4, 6).join()}-'
        '${h.sublist(6, 8).join()}-${h.sublist(8, 10).join()}-'
        '${h.sublist(10, 16).join()}';
  }

  Future<bool> reportIncomingCall({
    required String callId,
    required String displayName,
    required bool hasVideo,
  }) async {
    if (!isSupported) return false;
    try {
      await _channel.invokeMethod<void>('reportIncomingCall', <String, Object?>{
        'callId': callId,
        'displayName': displayName,
        'hasVideo': hasVideo,
      });
      return true;
    } on MissingPluginException {
      // Native side not registered (shouldn't happen on iOS once AppDelegate
      // is wired, but harmless during early-init races).
      return false;
    } on PlatformException catch (e) {
      // E.g. CallKit refused to show the UI because of "Silence Unknown
      // Callers". Logged so the call-service can fall back to in-app ring.
      debugPrint('[CallKitBridge] reportIncomingCall failed: $e');
      return false;
    }
  }

  Future<void> reportOutgoingCall({
    required String callId,
    required String displayName,
    required bool hasVideo,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('reportOutgoingCall', <String, Object?>{
        'callId': callId,
        'displayName': displayName,
        'hasVideo': hasVideo,
      });
    } on MissingPluginException {
      // No-op.
    } on PlatformException catch (e) {
      debugPrint('[CallKitBridge] reportOutgoingCall failed: $e');
    }
  }

  Future<void> reportCallConnected({required String callId}) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(
        'reportCallConnected',
        <String, Object?>{'callId': callId},
      );
    } on MissingPluginException {
      // No-op.
    } on PlatformException catch (e) {
      debugPrint('[CallKitBridge] reportCallConnected failed: $e');
    }
  }

  Future<void> reportCallEnded({
    required String callId,
    String reason = CallKitEndReason.hangup,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('reportCallEnded', <String, Object?>{
        'callId': callId,
        'reason': reason,
      });
    } on MissingPluginException {
      // No-op.
    } on PlatformException catch (e) {
      debugPrint('[CallKitBridge] reportCallEnded failed: $e');
    }
  }

  /// Visible for testing: surface what arrived from native without spinning
  /// the channel. Used by `callkit_bridge_test.dart` to verify decoding.
  @visibleForTesting
  void handleNativeMethodForTest(MethodCall call) {
    _handleNativeCall(call);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    // Hardened against post-dispose channel events and any decoding misstep:
    // the MethodChannel framework swallows exceptions from handlers, which
    // both hides analyzer-flagged failures and can leave the bridge in a
    // half-broken state. Catching here keeps the channel handler alive and
    // surfaces problems via the logger.
    try {
      switch (call.method) {
        case 'onCallKitAction':
          final args = call.arguments;
          if (args is! Map) return null;
          final actionStr = args['action'] as String? ?? '';
          final callId = args['callId'] as String? ?? '';
          if (callId.isEmpty) return null;
          final kind = _parseAction(actionStr);
          if (kind == CallKitActionKind.unknown) return null;
          _emitAction(
            CallKitAction(
              kind: kind,
              callId: callId,
              muted: args['muted'] as bool?,
            ),
          );
          return null;
        case 'onCallKitReset':
          // OS-level reset (e.g. CallKit daemon crash). Surface as a synthetic
          // "end all" by emitting an `end` action with empty callId so listeners
          // can decide to tear everything down.
          _emitAction(
            const CallKitAction(kind: CallKitActionKind.end, callId: ''),
          );
          return null;
        case 'onAudioSessionActivated':
        case 'onAudioSessionDeactivated':
          // The audio session lifecycle is handled by CallAudioPlatform; this
          // bridge just forwards informational pings. No-op for now — consumers
          // that need this can subscribe via CallAudioPlatform.events.
          return null;
        default:
          return null;
      }
    } catch (e, st) {
      AppLogger.warn('[CallKitBridge] _handleNativeCall error: $e\n$st');
      return null;
    }
  }

  /// Emit an action to the broadcast stream, buffering if no listener has ever
  /// attached yet. Once at least one listener has subscribed (via `onListen`),
  /// this becomes a direct passthrough; we do NOT buffer for late subscribers
  /// — broadcast semantics handle those by simply not replaying history, which
  /// is the correct behaviour after the first subscription is established.
  void _emitAction(CallKitAction action) {
    if (_actions.isClosed) {
      // Bridge has been disposed; drop silently. Adding to a closed controller
      // throws — and there's nobody left to deliver to anyway.
      return;
    }
    if (!_hasEverHadListener) {
      if (_pendingActions.length >= _kMaxPendingActions) {
        // Drop the oldest to keep memory bounded. In practice the buffer
        // should hold at most 1-2 entries before initialize() subscribes.
        _pendingActions.removeAt(0);
      }
      _pendingActions.add(action);
      return;
    }
    _actions.add(action);
  }

  /// Called by the broadcast controller's `onListen` hook on the very first
  /// subscription. We drain anything buffered while no listener was attached,
  /// then mark the bridge as "live" so subsequent emits bypass the buffer.
  void _drainPendingActions() {
    _hasEverHadListener = true;
    if (_pendingActions.isEmpty) return;
    final pending = List<CallKitAction>.from(_pendingActions);
    _pendingActions.clear();
    for (final action in pending) {
      if (_actions.isClosed) break;
      _actions.add(action);
    }
  }

  CallKitActionKind _parseAction(String value) {
    switch (value) {
      case 'answer':
        return CallKitActionKind.answer;
      case 'end':
        return CallKitActionKind.end;
      case 'mute':
        return CallKitActionKind.mute;
      case 'start':
        return CallKitActionKind.start;
      default:
        return CallKitActionKind.unknown;
    }
  }

  void dispose() {
    unawaited(_actions.close());
  }
}
