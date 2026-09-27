import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom image/video send delegates offline queue handling to service',
      () async {
    final src = await File('lib/ui/home_page.dart').readAsString();
    final start = src.indexOf('  Future<void> _sendMedia');
    final end = src.indexOf('  Future<String> _createSelfQrCardImage', start);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));

    final sendMediaBody = src.substring(start, end);

    expect(
      sendMediaBody,
      isNot(contains('widget.service.getFriendList()')),
      reason: 'FfiChatService.sendFile owns offline file queueing. The custom '
          'photo/video picker must not pre-emptively fail offline C2C sends.',
    );
    // The send goes through the M2 media preparation (HEIC -> JPEG, HEVC ->
    // H.264), which then hands the file to sendFile unchanged in spirit:
    // still no offline pre-check of its own.
    expect(
      sendMediaBody,
      contains('await _sendPreparedMedia(userId, pickedPath)'),
    );
    final capture = await File('lib/ui/home_page_capture.dart').readAsString();
    final helperStart = capture.indexOf('Future<bool> _sendPreparedMedia');
    expect(helperStart, isNonNegative);
    final helper = capture.substring(
      helperStart,
      capture.indexOf('\n  }\n', helperStart),
    );
    expect(helper, contains('await widget.service.sendFile(userId, prepared);'));
    expect(helper, isNot(contains('getFriendList')));
  });
}
