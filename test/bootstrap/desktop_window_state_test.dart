import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/bootstrap/desktop_window_state.dart';
import 'package:toxee/runtime/session_runtime_coordinator.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/active_session.dart';
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
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    AccountTeardownTestHooks.reset();
    SessionRuntimeCoordinator.debugReset();
    ActiveSession.reset();
  });
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
  testWidgets('failed checkpoint cancels quit and a later request retries', (
    tester,
  ) async {
    var attempts = 0;
    final state = DesktopWindowState(
      checkpointSession: () async => ++attempts > 1,
    )..restoring = false;
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
  testWidgets('quit waits past ten seconds for the same account teardown', (
    tester,
  ) async {
    final started = Completer<void>();
    final release = Completer<void>();
    var disposals = 0;
    SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {};
    AccountTeardownTestHooks.shutdownIrcSession = (_) async {};
    AccountTeardownTestHooks.disposeService = (_) async {
      disposals++;
      started.complete();
      await release.future;
    };
    final service = _FakeService();
    ActiveSession.set(service);
    final state = DesktopWindowState()..restoring = false;
    state.install();
    addTearDown(state.dispose);
    AppExitResponse? decision;
    final quit = tester.binding.handleRequestAppExit().then((result) {
      decision = result;
      return result;
    });
    await started.future;
    final joined = state.prepareToExit();
    await tester.pump(const Duration(seconds: 11));
    expect(
      decision,
      isNull,
      reason: 'teardown cannot be canceled by a timeout',
    );
    expect(ActiveSession.current, same(service));
    expect(disposals, 1);
    release.complete();
    await tester.pump();
    expect(await quit, AppExitResponse.exit);
    expect(await joined, isTrue);
    expect(ActiveSession.current, isNull);
  });
  testWidgets('completed destructive teardown failure still ends quit', (
    tester,
  ) async {
    SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {
      throw StateError('runtime checkpoint failed');
    };
    var disposed = false;
    AccountTeardownTestHooks.shutdownIrcSession = (_) async {};
    AccountTeardownTestHooks.disposeService = (_) async => disposed = true;
    ActiveSession.set(_FakeService());
    final state = DesktopWindowState()..restoring = false;
    state.install();
    addTearDown(state.dispose);
    final result = await tester.binding.handleRequestAppExit();
    expect(disposed, isTrue);
    expect(ActiveSession.current, isNull);
    expect(
      result,
      AppExitResponse.exit,
      reason: 'cancel would expose a page backed by the disposed account',
    );
  });
}

class _FakeService implements FfiChatService {
  @override
  String? getSelfToxId() => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
