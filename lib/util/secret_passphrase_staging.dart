// The FfiChatService passphrase entry points over a [SecretPassword].
//
// tim2tox takes raw UTF-8 bytes (`setProfilePassphraseBytes`,
// `rekeyLiveProfilePassphraseBytes`): it copies them into native memory,
// zeroes that copy, and leaves the host's buffer alone. These adapters hand it
// a scoped view of the borrowed SecretPassword, so no String and no extra Dart
// copy is ever made on the way down. Null or empty means "no passphrase".

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'secret_password.dart';

extension SecretPassphraseStaging on FfiChatService {
  /// See [FfiChatService.setProfilePassphraseBytes].
  bool setProfilePassphraseSecret(SecretPassword? password) => password == null
      ? setProfilePassphraseBytes(null)
      : password.withBytes(setProfilePassphraseBytes);

  /// See [FfiChatService.rekeyLiveProfilePassphraseBytes].
  bool rekeyLiveProfilePassphraseSecret(SecretPassword? password) =>
      password == null
      ? rekeyLiveProfilePassphraseBytes(null)
      : password.withBytes(rekeyLiveProfilePassphraseBytes);
}
