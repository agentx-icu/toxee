import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Receives BGAppRefreshTask invocations from native iOS and gives the
/// caller a chance to do brief work (e.g. nudge `FfiChatService.startPolling`)
/// before signalling completion back to the OS.
///
/// Lifecycle:
/// 1. Native calls `performRefresh` with a `requestId`.
/// 2. We invoke the registered [onRefresh] callback, awaiting it up to
///    [refreshBudget].
/// 3. We call `refreshCompleted(requestId, success)` back on native, so iOS
///    can `setTaskCompleted(success:)`.
///
/// On non-iOS platforms every public method short-circuits; the callback is
/// never invoked.
class BgRefreshBridge {
  BgRefreshBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('toxee/bg_refresh') {
    if (isSupported) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  static final BgRefreshBridge instance = BgRefreshBridge();

  final MethodChannel _channel;

  /// Hard cap for the Dart side. Apple gives the BG task ~30 sec; native code
  /// arms its own watchdog at 25, so we cap ourselves slightly lower so the
  /// completion roundtrip lands before the OS pulls the rug.
  static const Duration refreshBudget = Duration(seconds: 20);

  /// Callback fired when iOS grants a refresh window. The callback should
  /// kick polling and complete as fast as it can. Returning a Future that
  /// resolves promptly (well within [refreshBudget]) is critical: iOS
  /// throttles apps that consistently miss their deadline.
  Future<void> Function()? onRefresh;

  bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Manually request the next BG refresh window from native. Most callers
  /// don't need to call this — native re-arms automatically after every
  /// completed task and on `applicationDidEnterBackground` — but it's exposed
  /// for diagnostic / test purposes.
  Future<void> scheduleNextRefresh() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('scheduleNextRefresh');
    } on MissingPluginException {
      // Not wired (shouldn't happen on iOS post-AppDelegate init).
    } on PlatformException catch (e) {
      debugPrint('[BgRefreshBridge] scheduleNextRefresh failed: $e');
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'performRefresh') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final requestId = args['requestId'] as String?;
    if (requestId == null || requestId.isEmpty) return null;

    var success = true;
    try {
      final cb = onRefresh;
      if (cb != null) {
        await cb().timeout(refreshBudget, onTimeout: () {
          // Timed out — log but still mark success(=true) so iOS doesn't
          // demote our scheduling priority. The 25-sec native watchdog will
          // call setTaskCompleted itself anyway; this completion call is the
          // happy path.
          debugPrint(
              '[BgRefreshBridge] onRefresh callback exceeded $refreshBudget');
        });
      }
    } catch (e) {
      debugPrint('[BgRefreshBridge] onRefresh threw: $e');
      success = false;
    }

    try {
      await _channel.invokeMethod<void>('refreshCompleted', <String, Object?>{
        'requestId': requestId,
        'success': success,
      });
    } on MissingPluginException {
      // No-op.
    } on PlatformException catch (e) {
      debugPrint('[BgRefreshBridge] refreshCompleted failed: $e');
    }
    return null;
  }

  /// Visible for testing: invoke the same code path as a native call.
  @visibleForTesting
  Future<void> handleNativeMethodForTest(MethodCall call) =>
      _handleNativeCall(call) as Future<void>;
}
