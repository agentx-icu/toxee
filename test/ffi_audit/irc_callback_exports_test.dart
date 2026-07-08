import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final ffiSource = File('$repoRoot/third_party/tim2tox/ffi/tim2tox_ffi.cpp');

  test(
    'IRC callback setter FFI functions are exported and delegated',
    () async {
      expect(
        ffiSource.existsSync(),
        isTrue,
        reason: 'The tim2tox FFI source file moved; update this audit test.',
      );

      final src = await ffiSource.readAsString();

      for (final fn in const [
        'tim2tox_ffi_irc_set_connection_status_callback',
        'tim2tox_ffi_irc_set_user_list_callback',
        'tim2tox_ffi_irc_set_user_join_part_callback',
      ]) {
        expect(
          RegExp(r'void\s+' + fn + r'\s*\(').hasMatch(src),
          isTrue,
          reason:
              '$fn is declared in tim2tox_ffi.h and looked up from Dart, so '
              'the shared library must define it.',
        );
      }

      for (final symbol in const [
        'irc_client_set_connection_status_callback',
        'irc_client_set_user_list_callback',
        'irc_client_set_user_join_part_callback',
      ]) {
        expect(
          src,
          contains('dlsym(handle, "$symbol")'),
          reason:
              '$symbol must be loaded from libirc_client so Flutter can '
              'subscribe to IRC status and membership updates.',
        );
      }
    },
  );
}
