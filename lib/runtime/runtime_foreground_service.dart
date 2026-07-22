import 'dart:io';

import 'package:flutter/services.dart';

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
/// All methods short-circuit to a no-op on non-Android platforms (iOS uses
/// VoIP background mode + PushKit instead; desktop runs in the foreground by
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

  /// Start the foreground service in dataSync mode. Idempotent on the native
  /// side — repeated calls update the notification text but don't re-create
  /// the service.
  Future<void> start({
    required String title,
    required String body,
    required String settingsLabel,
  }) async {
    if (!_isApplicable) return;
    try {
      await _channel.invokeMethod<void>('start', <String, Object?>{
        'title': title,
        'body': body,
        'settingsLabel': settingsLabel,
      });
    } on MissingPluginException {
      // Native bridge not registered (e.g. unit-test JVM): silently no-op.
    } catch (e, st) {
      AppLogger.logError(
        '[RuntimeForegroundService] start failed (non-fatal)',
        e,
        st,
      );
    }
  }

  /// Stop the foreground service. Safe to call when the service is not
  /// running (the native side just no-ops in that case).
  Future<void> stop() async {
    if (!_isApplicable) return;
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
    try {
      await _channel.invokeMethod<void>('elevateToCall', <String, Object?>{
        'title': title,
        'body': body,
        'settingsLabel': settingsLabel,
        'usesCamera': usesCamera,
      });
    } on MissingPluginException {
      // No-op outside Android runtime.
    } catch (e, st) {
      AppLogger.logError(
        '[RuntimeForegroundService] elevateToCall failed (non-fatal)',
        e,
        st,
      );
    }
  }

  /// Restore the service type back to dataSync after a call ends.
  Future<void> restoreFromCall({
    required String title,
    required String body,
    required String settingsLabel,
  }) async {
    if (!_isApplicable) return;
    try {
      await _channel.invokeMethod<void>('restoreFromCall', <String, Object?>{
        'title': title,
        'body': body,
        'settingsLabel': settingsLabel,
      });
    } on MissingPluginException {
      // No-op outside Android runtime.
    } catch (e, st) {
      AppLogger.logError(
        '[RuntimeForegroundService] restoreFromCall failed (non-fatal)',
        e,
        st,
      );
    }
  }
}
