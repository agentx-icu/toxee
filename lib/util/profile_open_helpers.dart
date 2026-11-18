import 'dart:io';
import 'dart:typed_data';

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'account_export/encryption.dart' show isDataEncrypted, passDecrypt;
import 'account_export/tox_file_io.dart' show extractToxIdFromProfile;
import 'account_export_service.dart';
import 'prefs.dart';
import 'profile_open_failure.dart';
import 'secret_passphrase_staging.dart';
import 'secret_password.dart';
import 'tox_utils.dart';

// Opening a protected profile: passphrase staging and failure classification.
// Split out of `account_service.dart` (complexity-gate pin); used by
// `AccountService.initialize` and `registerNewAccount`.

/// Validates the identity of a present profile before native init can save it.
///
/// Native init can replace damaged plaintext with a new identity. Inspect
/// plaintext before calling it so a failed open preserves the supplied file.
/// For an encrypted file, native init already preserves failed decryptions and
/// supplies the normal login error. Probe what can open successfully because a
/// valid file for another account would otherwise be saved again on teardown.
Future<bool> validateExistingAccountProfile(
  String profileFile,
  String toxId, {
  SecretPassword? password,
}) async {
  final file = File(profileFile);
  if (!await file.exists()) return false;
  final data = await file.readAsBytes();
  try {
    if (!isDataEncrypted(data)) {
      requireAccountProfileIdentity(toxId, extractToxIdFromProfile(data));
    } else if (password != null && password.isNotEmpty) {
      final actual = _probeEncryptedProfileIdentity(data, password);
      if (actual != null) requireAccountProfileIdentity(toxId, actual);
    }
  } finally {
    data.fillRange(0, data.length, 0);
  }
  return true;
}

String? _probeEncryptedProfileIdentity(
  Uint8List data,
  SecretPassword password,
) {
  try {
    final plaintext = passDecrypt(data, password);
    try {
      return extractToxIdFromProfile(plaintext);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  } on Exception {
    return null;
  }
}

final _accountPublicKeyPattern = RegExp(r'^[a-f0-9]{64}$');

/// Compare stable identity, accepting the legacy 16-hex prefix and the
/// key/address aliases persisted by different versions of the app.
void requireAccountProfileIdentity(String toxId, String? actualToxId) {
  final actualKey = toToxPublicKey(actualToxId ?? '');
  if (!_accountPublicKeyPattern.hasMatch(actualKey) ||
      !compareToxIds(toToxPublicKey(toxId), actualKey)) {
    throw const AccountProfileIdentityMismatchException();
  }
}

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
