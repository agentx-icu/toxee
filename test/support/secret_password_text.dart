import 'dart:convert';

import 'package:toxee/util/secret_password.dart';

/// Test-only: the UTF-8 text of [password], read at the moment of the call (a
/// fake records it before the production code zeroes the bytes). Production
/// code deliberately has no way to turn a SecretPassword back into a String.
String? secretText(SecretPassword? password) =>
    password?.withBytes(utf8.decode);
