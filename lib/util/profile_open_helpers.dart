import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'account_export_service.dart';
import 'prefs.dart';
import 'profile_open_failure.dart';
import 'secret_passphrase_staging.dart';
import 'secret_password.dart';

// Opening a protected profile: passphrase staging and failure classification.
// Split out of `account_service.dart` (complexity-gate pin); used by
// `AccountService.initialize` and `registerNewAccount`.

/// Hands [password] to the native layer for the NEXT init. Refuses to run
/// on a native library without savedata encryption: silently falling back
/// to decrypt-in-place would reopen the plaintext-at-rest gap this exists
/// to close.
Future<void> stageProfilePassphrase(
  FfiChatService service,
  SecretPassword? password,
) async {
  if (password == null || password.isEmpty) return;
  if (!service.setProfilePassphraseSecret(password)) {
    throw StateError(
      'native library lacks savedata encryption '
      '(tim2tox_ffi_set_profile_passphrase); refusing to open a protected '
      'profile in plaintext',
    );
  }
}

/// A failed init under a verified password is reported as such, with the
/// hint that matters: whether a journaled password change was interrupted
/// (then the file is most likely under the other password).
Future<Object> classifyInitFailure(
  Object error,
  String toxId,
  String? profileFile,
  SecretPassword? password,
) async {
  if (password == null || password.isEmpty || profileFile == null) {
    return error;
  }
  try {
    if (!await AccountExportService.isProfileFileEncrypted(profileFile)) {
      return error;
    }
    final pending = await Prefs.passwordChanges.pending(toxId);
    return ProfileUnopenableWithPasswordException(
      passwordChangeInFlight: pending.record != null,
    );
  } catch (_) {
    return error;
  }
}
