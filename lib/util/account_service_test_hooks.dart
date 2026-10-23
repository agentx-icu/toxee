import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'secret_password.dart';

// Injection points that let the account teardown / registration flows be driven
// in unit tests without a real Tox instance, a keychain, or profile encryption.
//
// Split out of `account_service.dart` (complexity-gate pin) and re-exported from
// it, so every `AccountTeardownTestHooks.…` call site is unchanged. Production
// code only ever READS the getters; test-only setters retain the write boundary.
// The hooks are null unless a test set them, and every
// test that does must call `reset()` in its tearDown.

abstract final class AccountTeardownTestHooks {
  AccountTeardownTestHooks._();

  static Future<void> Function(FfiChatService service)? _shutdownIrcSession;
  static Future<void> Function(FfiChatService service)?
  get shutdownIrcSession => _shutdownIrcSession;
  @visibleForTesting
  static set shutdownIrcSession(
    Future<void> Function(FfiChatService service)? value,
  ) => _shutdownIrcSession = value;

  static Future<void> Function(FfiChatService service)? _disposeService;
  static Future<void> Function(FfiChatService service)? get disposeService =>
      _disposeService;
  @visibleForTesting
  static set disposeService(
    Future<void> Function(FfiChatService service)? value,
  ) => _disposeService = value;

  static Future<void> Function(String profilePath, SecretPassword password)?
  _encryptProfileFile;
  static Future<void> Function(String profilePath, SecretPassword password)?
  get encryptProfileFile => _encryptProfileFile;
  @visibleForTesting
  static set encryptProfileFile(
    Future<void> Function(String profilePath, SecretPassword password)? value,
  ) => _encryptProfileFile = value;

  @visibleForTesting
  static void reset() {
    shutdownIrcSession = null;
    disposeService = null;
    encryptProfileFile = null;
  }
}

abstract final class AccountPasswordChangeTestHooks {
  AccountPasswordChangeTestHooks._();

  /// Stands in for `FfiChatService.rekeyLiveProfilePassphrase` — the native
  /// re-key that needs a live session — so a widget test can drive the real
  /// password-change transaction without one. Null => the real call.
  static bool Function(FfiChatService service, SecretPassword? password)?
  _rekeyLive;
  static bool Function(FfiChatService service, SecretPassword? password)?
  get rekeyLive => _rekeyLive;
  @visibleForTesting
  static set rekeyLive(
    bool Function(FfiChatService service, SecretPassword? password)? value,
  ) => _rekeyLive = value;

  @visibleForTesting
  static void reset() {
    rekeyLive = null;
  }
}

abstract final class AccountRegistrationTestHooks {
  AccountRegistrationTestHooks._();

  static Future<void> Function(FfiChatService service)? _disposeService;
  static Future<void> Function(FfiChatService service)? get disposeService =>
      _disposeService;
  @visibleForTesting
  static set disposeService(
    Future<void> Function(FfiChatService service)? value,
  ) => _disposeService = value;

  /// Runs right before a protected registration reopens the profile with its
  /// account-scoped service — the last step that can still fail after the
  /// account row is published. Tests throw here to exercise the rollback.
  static Future<void> Function(String toxId)? _beforeScopedReopen;
  static Future<void> Function(String toxId)? get beforeScopedReopen =>
      _beforeScopedReopen;
  @visibleForTesting
  static set beforeScopedReopen(Future<void> Function(String toxId)? value) =>
      _beforeScopedReopen = value;

  /// Runs inside `createAccountScopedService`, after the scoped service was
  /// constructed and initialised but before it is handed back. Tests throw
  /// here to exercise the factory's own cleanup of that service.
  static Future<void> Function(FfiChatService service)? _duringScopedOpen;
  static Future<void> Function(FfiChatService service)? get duringScopedOpen =>
      _duringScopedOpen;
  @visibleForTesting
  static set duringScopedOpen(
    Future<void> Function(FfiChatService service)? value,
  ) => _duringScopedOpen = value;

  @visibleForTesting
  static void reset() {
    disposeService = null;
    beforeScopedReopen = null;
    duringScopedOpen = null;
  }
}
