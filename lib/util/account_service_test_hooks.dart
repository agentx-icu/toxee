import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

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
  static Future<void> Function(String profilePath, String password)?
  encryptProfileFile;

  @visibleForTesting
  static void reset() {
    shutdownIrcSession = null;
    disposeService = null;
    encryptProfileFile = null;
  }
}

abstract final class AccountRegistrationTestHooks {
  AccountRegistrationTestHooks._();

  @visibleForTesting
  static Future<void> Function(FfiChatService service)? disposeService;

  @visibleForTesting
  static Future<void> Function(String profilePath, String password)?
  encryptProfileFile;

  @visibleForTesting
  static void reset() {
    disposeService = null;
    encryptProfileFile = null;
  }
}
