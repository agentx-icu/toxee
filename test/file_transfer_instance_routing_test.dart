import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('file request provider leaves ordinary files pending for the UI', () {
    final source = File(
      'lib/sdk_fake/fake_msg_provider.dart',
    ).readAsStringSync();
    expect(
      source,
      isNot(contains('_fileRequestsSub = ffi.fileRequests.listen(')),
    );
    expect(
      source,
      isNot(contains('acceptFileTransfer(\n            req.peerId')),
    );
  });
}
