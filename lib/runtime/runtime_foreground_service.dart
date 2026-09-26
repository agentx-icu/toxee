import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../util/logger.dart';

/// Dart-side wrapper around the Android `ToxPollingService` foreground service.
///
/// On Android, the OS aggressively kills backgrounded processes within seconds
/// to minutes, which would otherwise stop the tox polling loop running inside
/// `FfiChatService.startPolling()` and silently drop inbound messages and
/// calls. This service keeps the Flutter engine — and therefore the polling
/// loop — alive while the app is in the background.
///
/// Two modes are supported:
///   - `start` / `stop` — the default dataSync mode. Used for the whole
///     session lifetime after login.
///   - `elevateToCall` / `restoreFromCall` — swap to / from the `phoneCall`
///     foreground service type while a ToxAV call is in progress, so the OS
///     treats the process as a real ongoing call.
///
/// **Process-kill caveat**: when the user swipes the app away from
/// recent-apps, the Application process is killed and the service stops with
/// it. Tox polling stops. The user must re-open the app to resume — by design;
/// we do not implement process-restart from a `BroadcastReceiver`.
///
/// **OS-stopped service**: the OS can stop the service without Dart asking
/// (an API 35+ foreground-service time limit, a refused start from the
/// background). The wrapper remembers the last mode requested during the
/// session and, when the app returns to the foreground, asks the native side
/// whether the service is actually running in that mode (the OS may also
/// have accepted only a degraded call type) and replays that request if not
/// ([ensureRunning]). Replaying the last request, rather than always calling
/// `start`, keeps an in-progress call in its call mode.
///
/// All methods short-circuit to a no-op on non-Android platforms (iOS relies
/// on its `audio` / `fetch` background modes instead — see
/// doc/architecture/MOBILE_BACKGROUND.md; desktop runs in the foreground by
/// definition). [MissingPluginException] is swallowed defensively so unit
/// tests that don't register a mock handler don't have to special-case the
/// service.
class RuntimeForegroundService {
  RuntimeForegroundService({MethodChannel? channel, bool? isAndroidOverride})
    : _isAndroidOverride = isAndroidOverride,
      _channel = channel ?? const MethodChannel('toxee/runtime_foreground');

  final MethodChannel _channel;
  final bool? _isAndroidOverride;

  /// Singleton accessor for the production channel. Tests can construct their
  /// own [RuntimeForegroundService] with a mocked [MethodChannel] instead.
  static final RuntimeForegroundService instance = RuntimeForegroundService();

  /// Last mode requested during the current session (`start`, `elevateToCall`
  /// or `restoreFromCall`) and its arguments; null outside a session.
  String? _lastMethod;
  Map<String, Object?> _lastArgs = const {};

  /// True while the last request has not been accepted by the native side —
  /// e.g. `startForegroundService` refused a background start, so the intent
  /// never reached the service and its own mode check can't see the miss.
  bool _lastRequestUndelivered = false;
  _ResumeObserver? _resumeObserver;

  /// Records [method] as the session's current mode and sends it, tracking
  /// whether the native side accepted it so [ensureRunning] can replay it.
  Future<void> _request(String method, Map<String, Object?> args) async {
    _remember(method, args);
    _lastRequestUndelivered = true;
    try {
      await _channel.invokeMethod<void>(method, args);
      if (identical(_lastArgs, args)) _lastRequestUndelivered = false;
    } on MissingPluginException {
      // Native bridge not registered (e.g. unit-test JVM): nothing to replay.
      if (identical(_lastArgs, args)) _lastRequestUndelivered = false;
    } catch (e, st) {
      AppLogger.logError(
        '[RuntimeForegroundService] $method failed (non-fatal; replayed on '
        'the next resume)',
        e,
        st,
      );
    }
  }

  void _remember(String method, Map<String, Object?> args) {
    _lastMethod = method;
    _lastArgs = args;
    if (_resumeObserver == null && _isAndroidOverride == null) {
      // Production only: tests drive [ensureRunning] directly.
      _resumeObserver = _ResumeObserver(this);
      WidgetsBinding.instance.addObserver(_resumeObserver!);
    }
  }

  void _forget() {
    _lastMethod = null;
    _lastArgs = const {};
    _lastRequestUndelivered = false;
    final observer = _resumeObserver;
    if (observer != null) {
      WidgetsBinding.instance.removeObserver(observer);
      _resumeObserver = null;
    }
  }

  /// Re-establishes the service if the OS stopped it behind Dart's back.
  /// Called on every resume while a session is active; a no-op when the
  /// service is running or no session wants it. Starting from the foreground
  /// is always permitted and resets the background time budget.
  @visibleForTesting
  Future<void> ensureRunning() async {
    if (!_isApplicable || _lastMethod == null) return;
    try {
      final inMode = await _channel.invokeMethod<bool>('isInRequestedMode');
      final method = _lastMethod;
      // Re-read after the await: the session may have ended (stop) or the
      // mode may have changed (call elevated / restored) in the meantime.
      if (method == null) return;
      if ((inMode ?? true) && !_lastRequestUndelivered) return;
      AppLogger.log(
        '[RuntimeForegroundService] service not in the requested mode '
        '(stopped, degraded or refused by the OS); re-issuing $method',
      );
      await _request(method, _lastArgs);
    } on MissingPluginException {
      // Native bridge not registered: nothing to restore.
    } catch (e, st) {
      AppLogger.logError(
        '[RuntimeForegroundService] ensureRunning failed (non-fatal)',
        e,
        st,
      );
    }
  }

  bool get _isApplicable {
    if (_isAndroidOverride != null) return _isAndroidOverride;
    // Guard `Platform.isAndroid` so tests running on the VM (where the host
    // platform is desktop) short-circuit cleanly without touching the
    // platform channel.
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Start the foreground service in its always-on runtime mode (specialUse on
  /// API 34+, dataSync below). Idempotent on the native
  /// side — repeated calls update the notification text but don't re-create
  /// the service.
  Future<void> start({
    required String title,
    required String body,
    required String settingsLabel,
  }) async {
    if (!_isApplicable) return;
    final args = <String, Object?>{
      'title': title,
      'body': body,
      'settingsLabel': settingsLabel,
    };
    await _request('start', args);
  }

  /// Stop the foreground service. Safe to call when the service is not
  /// running (the native side just no-ops in that case).
  Future<void> stop() async {
    if (!_isApplicable) return;
    _forget();
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // No-op outside Android runtime.
    } catch (e, st) {
      AppLogger.logError(
        '[RuntimeForegroundService] stop failed (non-fatal)',
        e,
        st,
      );
    }
  }

  /// Swap the service type to `phoneCall` while a call is in progress.
  /// Caller is responsible for invoking [restoreFromCall] when the call ends.
  Future<void> elevateToCall({
    required String title,
    required String body,
    required String settingsLabel,
    bool usesCamera = false,
  }) async {
    if (!_isApplicable) return;
    final args = <String, Object?>{
      'title': title,
      'body': body,
      'settingsLabel': settingsLabel,
      'usesCamera': usesCamera,
    };
    await _request('elevateToCall', args);
  }

  /// Restore the service back to its runtime mode after a call ends.
  Future<void> restoreFromCall({
    required String title,
    required String body,
    required String settingsLabel,
  }) async {
    if (!_isApplicable) return;
    final args = <String, Object?>{
      'title': title,
      'body': body,
      'settingsLabel': settingsLabel,
    };
    await _request('restoreFromCall', args);
  }
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._owner);

  final RuntimeForegroundService _owner;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_owner.ensureRunning());
  }
}
