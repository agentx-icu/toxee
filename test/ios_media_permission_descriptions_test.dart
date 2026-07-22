import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS camera and microphone descriptions cover chat capture', () async {
    final plist = await File(
      '${Directory.current.path}/ios/Runner/Info.plist',
    ).readAsString();

    expect(plist, contains('take photos and record videos in chats'));
    expect(plist, contains('record voice messages'));
  });

  test('iOS background modes exclude voip until PushKit is implemented', () async {
    final plist = await File(
      '${Directory.current.path}/ios/Runner/Info.plist',
    ).readAsString();

    expect(plist, contains('<key>UIBackgroundModes</key>'));
    expect(plist, contains('<string>audio</string>'));
    expect(plist, contains('<string>fetch</string>'));
    expect(plist, isNot(contains('<string>voip</string>')));
  });
}
