import 'dart:async';

import '../util/account_service.dart';
import '../util/active_session.dart';
import '../util/logger.dart';

/// Tears the live account down on the paths that end the process.
///
/// WHY IT EXISTS: `AccountService.teardownCurrentSession` is the ONLY place
/// that re-encrypts `tox_profile.tox`. A session decrypts the profile in place
/// and leaves it that way for its whole lifetime, so any exit that skips
/// teardown strands a password-protected account's private key, friend list and
/// nospam in plaintext on disk. Two exits used to do exactly that:
///
///   * desktop: `DesktopShellBootstrap.onWindowClose` destroyed the window (and
///     with it the app) without touching the account;
///   * mobile: there is no window to close, so `AppLifecycleState.detached` is
///     the only exit notice the framework gives us.
///
/// Both now route here, which is also why this lives in one place: the two
/// handlers were otherwise the same twenty lines with a different timeout.
///
/// SCOPE — what this does NOT fix. `detached` is explicitly allowed to be
/// skipped, and an OS kill (how a backgrounded mobile app usually dies)
/// delivers nothing at all, so this is a mitigation and not a guarantee. The
/// durable fix is to encrypt at the savedata persistence boundary so the file
/// is never plaintext at rest; that is tracked separately. The
/// *authentication* consequence is closed independently — the auto-login gate
/// in `StartupSessionUseCase` keys off the durable verifier
/// (`Prefs.accountProtectionState`), never the file's encryption state — so a
/// missed teardown here costs at-rest confidentiality, not access control.
abstract final class SessionShutdown {
  SessionShutdown._();

  /// Run — or JOIN — account teardown for the live session, bounded by
  /// [timeout].
  ///
  /// Joining matters as much as running. A logout or account switch already in
  /// flight has disposed the service (so `ActiveSession.current` is on its way
  /// to null) but may not have written the re-encrypted profile yet. Returning
  /// early there would let the caller destroy the window mid-encryption, which
  /// is the very outcome this helper exists to prevent — so a pending teardown
  /// is awaited instead.
  ///
  /// Idempotent: `teardownCurrentSession` unregisters the service at the end, so
  /// a second call (desktop reaching both `onWindowClose` and `detached`) finds
  /// nothing left to do.
  ///
  /// Never throws. A teardown that fails or overruns must not wedge the exit;
  /// the profile is then left as it was, which the startup gate handles safely
  /// because it keys off the durable verifier rather than the file.
  static Future<void> tearDownActiveAccount({
    required Duration timeout,
    required String logContext,
  }) async {
    final pending = ActiveSession.pendingTeardown;
    if (pending != null) {
      try {
        await pending.timeout(timeout);
        AppLogger.info(
          '[$logContext] joined an in-flight account teardown before exit',
        );
      } catch (e, stackTrace) {
        AppLogger.logError(
          '[$logContext] in-flight account teardown did not complete before '
          'exit; the on-disk profile may remain unencrypted',
          e,
          stackTrace,
        );
      }
      return;
    }
    final service = ActiveSession.current;
    if (service == null) return;
    try {
      await AccountService.teardownCurrentSession(
        service: service,
      ).timeout(timeout);
      AppLogger.info('[$logContext] account torn down before exit');
    } catch (e, stackTrace) {
      AppLogger.logError(
        '[$logContext] account teardown before exit did not complete; the '
        'on-disk profile may remain unencrypted until the next clean logout',
        e,
        stackTrace,
      );
    }
  }
}
