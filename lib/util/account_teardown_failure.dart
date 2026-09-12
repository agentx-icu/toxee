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
