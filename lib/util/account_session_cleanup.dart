import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'safe_diagnostics.dart';
import 'session_password_store.dart';

/// Signature of `AccountService.teardownCurrentSession`, injected so this helper
/// does not have to import the class that calls it.
typedef TeardownSessionFn =
    Future<void> Function({FfiChatService? service, bool reEncryptProfile});

/// The session-cleanup stage of account deletion: wipe the account's live data,
/// then stop the session.
///
/// TEARDOWN RUNS IN A `finally`, and that is the whole point of this helper
/// existing separately. `clearAllAccountData()` touches the filesystem (the
/// offline queue), so a full or read-only volume makes it throw — and the
/// original straight-line order then SKIPPED the teardown, leaving the native
/// session alive while the Settings page navigated away on the failure. A
/// subsequent login could adopt that instance and run as the account being
/// deleted.
///
/// The first error is what the caller needs in order to record the right failed
/// stage, so a teardown failure on top of it is logged and the original
/// rethrown.
Future<void> clearAndTearDownForDeletion({
  required FfiChatService service,
  required String toxId,
  required TeardownSessionFn teardown,
}) async {
  Object? primaryError;
  StackTrace? primaryStack;
  try {
    await service.clearAllAccountData();
  } catch (e, st) {
    primaryError = e;
    primaryStack = st;
  }
  try {
    // reEncryptProfile: false — the profile is about to be deleted, so
    // re-encrypting it would be wasted work on a file that will not exist.
    await teardown(service: service, reEncryptProfile: false);
    SessionPasswordStore.clear(toxId);
  } catch (teardownError, teardownStack) {
    if (primaryError == null) {
      primaryError = teardownError;
      primaryStack = teardownStack;
    } else {
      SafeDiagnostics.logFailure(
        '[AccountService] deletion teardown also failed after the '
        'account-data clear failed',
        teardownError,
      );
    }
  }
  if (primaryError != null) {
    Error.throwWithStackTrace(primaryError, primaryStack!);
  }
}
