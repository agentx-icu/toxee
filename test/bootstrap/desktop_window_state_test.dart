import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/bootstrap/desktop_window_state.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late bool maximized;
  late Rect bounds;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
    maximized = false;
    bounds = const Rect.fromLTWH(50, 60, 1000, 700);
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isMaximized':
          return maximized;
        case 'isFullScreen':
        case 'isMinimized':
          return false;
        case 'getBounds':
          return {
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
          };
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('maximized exit retains the last normal bounds', () async {
    final state = DesktopWindowState()..restoring = false;
    await state.rememberNormalBounds();
    maximized = true;
    bounds = const Rect.fromLTWH(0, 0, 1920, 1080);
    await state.prepareToExit();
    expect(
      await Prefs.getWindowBounds(),
      const Rect.fromLTWH(50, 60, 1000, 700),
    );
    expect(await Prefs.getWindowMaximized(), true);
    expect(identical(state.prepareToExit(), state.prepareToExit()), true);
  });
  testWidgets('failed checkpoint cancels quit and a later request retries', (tester) async {
    var attempts = 0;
    final state = DesktopWindowState(checkpointSession: () async => ++attempts > 1)..restoring = false;
    state.install();
    addTearDown(state.dispose);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(attempts, 2);
  });
  testWidgets('framework quit awaits window checkpoint', (tester) async {
    final state = DesktopWindowState()..restoring = false;
    state.install();
    addTearDown(state.dispose);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(await Prefs.getWindowBounds(), bounds);
  });
}
