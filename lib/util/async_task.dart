import 'dart:async';

import 'safe_diagnostics.dart';

/// Observes work whose owner must stay responsive instead of awaiting it.
///
/// This does not cancel or reorder the work. Its owner still controls lifecycle
/// invalidation; failures are recorded rather than becoming unhandled Futures.
void observeBackgroundTask(Future<void>? task, String operation) {
  if (task == null) return;
  unawaited(
    task.catchError((Object error, StackTrace _) {
      SafeDiagnostics.logFailure(operation, error);
    }),
  );
}
