import 'dart:async';

import '../util/account_service.dart';
import '../util/active_session.dart';
import '../util/logger.dart';

/// Tears the live account down on the paths that end the process.
///
/// Protected profiles remain ciphertext during the session. Orderly teardown
/// still checkpoints pending data and clears session credentials; OS process
/// death can skip final callbacks, so it supplements ongoing persistence.
class SessionShutdown {
  SessionShutdown._();

  /// Run — or JOIN — account teardown for the live session. Desktop exits must
  /// await completion; [timeout] bounds only best-effort mobile exit paths.
  ///
  /// Joining matters as much as running. A logout or account switch already in
  /// flight may still be checkpointing profile and pending messages after
  /// releasing the active session; join it before closing the window.
  ///
  /// Idempotent: `teardownCurrentSession` unregisters the service at the end, so
  /// a second call (desktop reaching both `onWindowClose` and `detached`) finds
  /// nothing left to do.
  ///
  /// Reports false on failure/timeout. Teardown is destructive even on failure,
  /// so this result does not mean the old account can resume. A timeout stops
  /// waiting, not the teardown itself. Mobile detached remains best effort.
  static Future<bool> tearDownActiveAccount({
    Duration? timeout,
    required String logContext,
  }) async {
    final pending = ActiveSession.pendingTeardown;
    if (pending != null) {
      try {
        final teardown = pending as Future<Object?>;
        final stopped = await (timeout == null
            ? teardown
            : teardown.timeout(timeout));
        if (stopped == false) return false;
        AppLogger.info(
          '[$logContext] joined an in-flight account teardown before exit',
        );
        return true;
      } catch (e, stackTrace) {
        AppLogger.logError(
          '[$logContext] in-flight account teardown did not complete before '
          'exit; pending data may not be checkpointed',
          e,
          stackTrace,
        );
        return false;
      }
    }
    final service = ActiveSession.current;
    if (service == null) return true;
    try {
      final teardown = AccountService.teardownCurrentSession(service: service);
      final stopped = await (timeout == null
          ? teardown
          : teardown.timeout(timeout));
      AppLogger.info('[$logContext] account torn down before exit');
      return stopped;
    } catch (e, stackTrace) {
      AppLogger.logError(
        '[$logContext] account teardown before exit did not complete; the '
        'pending state may not have been checkpointed',
        e,
        stackTrace,
      );
      return false;
    }
  }
}
