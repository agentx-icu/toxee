import 'safe_diagnostics.dart';

// Stage identifiers and the typed failure for account-session teardown. Split out
// of `account_service.dart` (complexity-gate pin) and re-exported from it, so
// every existing `AccountTeardownFailure` / `AccountTeardownStage` reference is
// unchanged. These are data: the stages describe an ordering the teardown owns,
// and the failure carries which one stopped.

enum AccountTeardownStage {
  runtimeDisposal,
  providerRegistryCleanup,
  singletonCacheCleanup,
  ircSessionShutdown,
  serviceDisposal,
  profileReEncryption,
  sessionPasswordClear,
}

/// `dispose()` returned, but the native Tox instance could not be proven
/// stopped: Tim2Tox quarantines an instance whose poll or background task did
/// not drain in time (`FfiChatService.nativeInstanceStopped == false`), or an
/// older library cannot say (`null`). Such an instance can still write
/// savedata into the profile directory, so nothing may delete, replace or
/// re-encrypt that directory until a process restart. Teardown itself does not
/// throw this (the session is gone either way); the callers that would go on
/// to touch the directory do.
final class NativeInstanceNotStoppedException implements Exception {
  const NativeInstanceNotStoppedException({
    required this.toxId,
    required this.operation,
  });

  final String toxId;

  /// What was refused, e.g. `account_deletion`.
  final String operation;

  @override
  String toString() =>
      'Native Tox instance not proven stopped; refusing $operation';
}

final class AccountTeardownFailure implements Exception {
  const AccountTeardownFailure({
    required this.toxId,
    required this.stage,
    required this.cause,
    required this.stackTrace,
  });

  final String toxId;
  final AccountTeardownStage stage;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'Account teardown failed stage=${stage.name} '
        '${SafeDiagnostics.describeError(cause)}';
  }
}
