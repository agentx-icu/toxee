part of 'session_runtime_coordinator.dart';

/// Runs under [SessionRuntimeCoordinator._disposing]. Every stage is attempted,
/// but the runtime remains fail-closed until one complete attempt succeeds.
Future<void> _runSessionRuntimeTeardown() async {
  SessionRuntimeCoordinator._generation++;
  final inFlight = SessionRuntimeCoordinator._initializing;
  if (inFlight != null) {
    try {
      await inFlight;
    } catch (_) {
      // The initialization failure is already surfaced to its own caller.
    }
  }
  SessionRuntimeCoordinator._state = SessionRuntimeState.tearingDown;

  final teardownOverride = SessionRuntimeCoordinator.debugTeardownBodyOverride;
  if (teardownOverride != null) {
    try {
      await teardownOverride();
    } catch (error, stackTrace) {
      _recordSessionRuntimeTeardownFailure(error, stackTrace);
      rethrow;
    }
    _commitSessionRuntimeTeardownSuccess();
    return;
  }

  Object? firstError;
  StackTrace? firstStack;
  Future<void> step(String stage, FutureOr<void> Function() operation) async {
    try {
      await operation();
    } catch (error, stackTrace) {
      SafeDiagnostics.logFailure(
        '[SessionRuntimeCoordinator] teardown_failed stage=$stage',
        error,
      );
      firstError ??= error;
      firstStack ??= stackTrace;
    }
  }

  await step(
    'pending_hook_subscription',
    () => SessionRuntimeCoordinator._pendingHookSelfIdSub?.cancel(),
  );
  await step('history_hook', BinaryReplacementHistoryHook.uninstallStandalone);
  await step('ios_bg_refresh', () {
    BgRefreshBridge.instance.onRefresh = null;
  });
  await step('badge_service', BadgeService.instance.dispose);
  await step(
    'notification_listener',
    NotificationMessageListener.disposeAndReset,
  );
  await step(
    'notification_session',
    NotificationService.instance.resetSessionState,
  );
  await step('fake_uikit', () => FakeUIKit.instance.dispose());

  final platform = TencentCloudChatSdkPlatform.instance;
  if (platform is Tim2ToxSdkPlatform) {
    var platformDisposed = false;
    await step('tim2tox_platform', () {
      platform.dispose();
      platformDisposed = true;
    });
    if (platformDisposed) {
      await step('platform_reset', () {
        if (identical(TencentCloudChatSdkPlatform.instance, platform)) {
          TencentCloudChatSdkPlatform.instance =
              MethodChannelTencentCloudChatSdk();
        }
      });
    }
  }

  await step('foreground_service', RuntimeForegroundService.instance.stop);

  if (firstError != null) {
    final stackTrace = firstStack ?? StackTrace.current;
    _recordSessionRuntimeTeardownFailure(firstError!, stackTrace);
    Error.throwWithStackTrace(firstError!, stackTrace);
  }
  _commitSessionRuntimeTeardownSuccess();
}

void _recordSessionRuntimeTeardownFailure(Object error, StackTrace stackTrace) {
  SessionRuntimeCoordinator._teardownError = error;
  SessionRuntimeCoordinator._teardownStackTrace = stackTrace;
  SessionRuntimeCoordinator._state = SessionRuntimeState.teardownFailed;
}

void _commitSessionRuntimeTeardownSuccess() {
  SessionRuntimeCoordinator._pendingHookSelfIdSub = null;
  SessionRuntimeCoordinator._hookInstalled = false;
  SessionRuntimeCoordinator._teardownError = null;
  SessionRuntimeCoordinator._teardownStackTrace = null;
  SessionRuntimeCoordinator._state = SessionRuntimeState.disposed;
}
