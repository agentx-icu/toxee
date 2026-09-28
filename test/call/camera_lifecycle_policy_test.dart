// V5: the call camera keeps running while the app is on screen without focus
// (the other half of an iPad Split View, an Android multi-window pair, a
// desktop window click, Control Center) — stopping it there froze the video
// for the peer. It stops only once the app is no longer on screen.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_video_lifecycle_controller.dart';

void main() {
  test('on screen, focused or not: the camera may run', () {
    expect(cameraMayRunIn(AppLifecycleState.resumed), isTrue);
    expect(cameraMayRunIn(AppLifecycleState.inactive), isTrue);
  });

  test('not on screen: it may not', () {
    expect(cameraMayRunIn(AppLifecycleState.hidden), isFalse);
    expect(cameraMayRunIn(AppLifecycleState.paused), isFalse);
    expect(cameraMayRunIn(AppLifecycleState.detached), isFalse);
  });
}
