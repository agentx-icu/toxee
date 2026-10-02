// The optional `password` argument of the L3 account tools, as bytes.
//
// The MCP request's JSON String is this debug-only seam's UI edge: it is
// converted once, and the account layer below only ever sees a
// [SecretPassword], zeroed when the tool's body completes. Null or empty
// means "no password", matching what the tools did with the String.

import '../../util/secret_password.dart';

Future<T> withL3PasswordArg<T>(
  Map<String, dynamic> request,
  Future<T> Function(SecretPassword? password) body,
) {
  final text = request['password']?.toString();
  return SecretPassword.useOrNull(
    text == null || text.isEmpty ? null : text,
    body,
  );
}
