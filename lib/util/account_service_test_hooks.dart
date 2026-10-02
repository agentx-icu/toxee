import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'secret_password.dart';

// Injection points that let the account teardown / registration flows be driven
// in unit tests without a real Tox instance, a keychain, or profile encryption.
//
// Split out of `account_service.dart` (complexity-gate pin) and re-exported from
// it, so every `AccountTeardownTestHooks.…` call site is unchanged. Production
// code only ever READS these; they are null unless a test set them, and every
// test that does must call `reset()` in its tearDown.

abstract final class AccountTeardownTestHooks {
  AccountTeardownTestHooks._();

  @visibleForTesting
  static Future<void> Function(FfiChatService service)? shutdownIrcSession;

  @visibleForTesting
  static Future<void> Function(FfiChatService service)? disposeService;

  @visibleForTesting
  static Future<void> Function(String profilePath, SecretPassword password)?
  encryptProfileFile;

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
  @visibleForTesting
  static bool Function(FfiChatService service, SecretPassword? password)?
  rekeyLive;

  @visibleForTesting
  static void reset() {
    rekeyLive = null;
  }
}

abstract final class AccountRegistrationTestHooks {
  AccountRegistrationTestHooks._();

  @visibleForTesting
  static Future<void> Function(FfiChatService service)? disposeService;

  /// Runs right before a protected registration reopens the profile with its
  /// account-scoped service — the last step that can still fail after the
  /// account row is published. Tests throw here to exercise the rollback.
  @visibleForTesting
  static Future<void> Function(String toxId)? beforeScopedReopen;

  @visibleForTesting
  static void reset() {
    disposeService = null;
    beforeScopedReopen = null;
  }
}
