import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

/// Process-wide handle on the currently booted [FfiChatService], plus the
/// in-flight teardown a shutdown path must join rather than race.
///
/// WHY THIS EXISTS: shutdown paths that are not driven by a widget had no way
/// to reach the live session, so they exited without running
/// `AccountService.teardownCurrentSession` — which is the ONLY place that
/// re-encrypts `tox_profile.tox`. Closing the desktop window
/// (`DesktopShellBootstrap.onWindowClose`) destroys the window and terminates
/// the app; before this registry existed it could not tear the account down, so
/// a password-protected account was left in plaintext on disk after a
/// completely ordinary exit.
///
/// [pendingTeardown] is the other half, and it is not optional. Teardown
/// re-encrypts the profile AFTER disposing the service, so there is a window in
/// which the account is being torn down but the ciphertext is not on disk yet.
/// A shutdown that only looked at [current] would see null in that window,
/// conclude there was nothing to do, and destroy the process mid-encryption.
/// Joining the pending future instead makes the exit wait for the write.
///
/// Scope is deliberately minimal. It is NOT a service locator: UI code already
/// receives the service by constructor injection and must keep doing so. Only
/// shutdown/lifecycle code with no other handle should read this.
///
/// Single-slot by design, matching `SessionPasswordStore` and toxee's
/// single-instance Tox model: `switchAccount` tears down A before booting B, so
/// two sessions are never live at once.
abstract final class ActiveSession {
  ActiveSession._();

  static FfiChatService? _service;
  static Future<void>? _teardown;

  /// The live session, or null when logged out / mid-teardown.
  static FfiChatService? get current => _service;

  /// The teardown currently running, or null when none is. Completes only after
  /// profile re-encryption, so awaiting it is what makes an exit safe.
  static Future<void>? get pendingTeardown => _teardown;

  /// Publish [service] as the live session. Called once boot succeeds, so a
  /// half-initialized service is never handed to a shutdown path.
  static void set(FfiChatService service) {
    _service = service;
  }

  /// Register [run] as the in-flight teardown for the duration of its
  /// execution.
  ///
  /// Returns [run] so callers can `return ActiveSession.trackTeardown(...)`.
  /// The slot is cleared on completion whether [run] succeeded or threw — a
  /// failed teardown must not leave every later shutdown joining a dead future.
  static Future<void> trackTeardown(Future<void> run) {
    _teardown = run;
    return run.whenComplete(() {
      if (identical(_teardown, run)) _teardown = null;
    });
  }

  /// Forget the live session. Idempotent, and a no-op when [service] is not the
  /// registered one — a late teardown of an already-replaced session must not
  /// unregister the new one.
  static void clear([FfiChatService? service]) {
    if (service == null || identical(_service, service)) {
      _service = null;
    }
  }

  @visibleForTesting
  static void reset() {
    _service = null;
    _teardown = null;
  }
}
