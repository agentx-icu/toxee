import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large file provider accepts on request instance', () {
    final source = File(
      'lib/sdk_fake/fake_msg_provider.dart',
    ).readAsStringSync();
    expect(
      source,
      matches(
        RegExp(
          r'acceptFileTransfer\(\s*req\.peerId,\s*req\.fileNumber,\s*instanceId:\s*req\.instanceId',
        ),
      ),
    );
  });
}
