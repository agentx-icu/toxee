// M7 (MOBILE_DEVICE_FEATURES): the shared QR scanner view recovers from a
// denied camera permission and keeps a square viewfinder in any window shape.
//
// Found on an API 36 emulator: with the camera permission denied ("don't ask
// again") the Scan QR page showed mobile_scanner's bare "Camera permission
// denied." with no way to Settings, and after granting the permission and
// coming back it stayed on that error until the page was reopened.
//
// Drives the REAL MobileScanner + MobileScannerController through a mocked
// mobile_scanner platform channel (the same one the Android/iOS plugins
// answer).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/widgets/qr_scanner_view.dart';

const _method = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
const _events = EventChannel('dev.steenbakker.mobile_scanner/scanner/event');

/// The camera side of the platform, as the plugin reports it, plus the
/// app-level permission answers (permission_handler's seams).
class _FakeCamera {
  bool granted = false;
  int permissionRequests = 0; // app-level prompts (may show the OS sheet)
  String? startErrorCode;
  int starts = 0;
  int stops = 0;
  int requests = 0;
  Completer<void>? startGate; // holds a platform start in flight

  final List<String> log = [];

  Future<Object?> handle(MethodCall call) async {
    log.add(call.method);
    switch (call.method) {
      case 'state':
        return granted ? 1 : 2; // authorized : denied
      case 'request':
        requests++;
        return granted;
      case 'stop':
        stops++;
        return null;
      case 'start':
        starts++;
        final gate = startGate;
        if (gate != null) await gate.future;
        if (startErrorCode != null) {
          throw PlatformException(code: startErrorCode!, message: 'boom');
        }
        return <String, Object?>{
          'textureId': 7,
          'numberOfCameras': 1,
          'currentTorchState': -1,
          'size': <String, Object?>{'width': 1080.0, 'height': 1920.0},
        };
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeCamera camera;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    camera = _FakeCamera();
    messenger.setMockMethodCallHandler(_method, camera.handle);
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(_method, null);
    messenger.setMockStreamHandler(_events, null);
  });

  Future<void> pumpView(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    Future<void> Function()? openSettings,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Unmount inside the test and let the controller's async dispose reach
    // the (process-wide) plugin platform instance, so it can't leak into the
    // next test.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: QrScannerView(
            onDetect: (_) {},
            openSettings: openSettings,
            requestCameraPermission: () async {
              camera.permissionRequests++;
              return camera.granted;
            },
            cameraPermissionGranted: () async => camera.granted,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  QrScannerViewState stateOf(WidgetTester tester) =>
      tester.state<QrScannerViewState>(find.byType(QrScannerView));
  MobileScannerController controllerOf(WidgetTester tester) =>
      stateOf(tester).controller;

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  const settingsButton = ValueKey('qr_scanner_open_settings');
  const retryButton = ValueKey('qr_scanner_retry');
  const viewfinder = ValueKey('qr_scanner_viewfinder');

  testWidgets(
    'denied: explains, offers Settings, and never starts the camera',
    (tester) async {
      var settingsOpened = 0;
      await pumpView(tester, openSettings: () async => settingsOpened++);

      expect(camera.permissionRequests, 1);
      expect(
        find.text(
          'Camera access is off. Allow it in Settings to scan QR codes.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(viewfinder), findsNothing);
      // No failed plugin start(): that is what leaked stream subscriptions.
      expect(camera.starts, 0);
      expect(camera.requests, 0);

      await tester.tap(find.byKey(settingsButton));
      await tester.pump();
      expect(settingsOpened, 1);
    },
  );

  testWidgets('granted: starts the camera once, with a viewfinder', (
    tester,
  ) async {
    camera.granted = true;
    await pumpView(tester);
    expect(camera.starts, 1);
    expect(controllerOf(tester).value.isRunning, isTrue);
    expect(find.byKey(viewfinder), findsOneWidget);
  });

  testWidgets('granting in Settings and coming back starts the camera', (
    tester,
  ) async {
    await pumpView(tester, openSettings: () async {});
    expect(find.byKey(settingsButton), findsOneWidget);

    camera.granted = true; // the user flips the switch in Settings
    await resume(tester);

    expect(controllerOf(tester).value.isRunning, isTrue);
    expect(camera.starts, 1);
    expect(find.byKey(settingsButton), findsNothing);
    expect(find.byKey(viewfinder), findsOneWidget);
    // Coming back only re-read the status; it did not prompt again.
    expect(camera.permissionRequests, 1);
  });

  testWidgets('coming back still denied: no new prompt, no start', (
    tester,
  ) async {
    await pumpView(tester, openSettings: () async {});
    await resume(tester);
    await resume(tester);
    expect(find.byKey(settingsButton), findsOneWidget);
    // A new request would re-open Android's prompt, whose dismissal resumes
    // the app again — a loop.
    expect(camera.permissionRequests, 1);
    expect(camera.starts, 0);
  });

  testWidgets('leaving the screen stops the camera, coming back restarts it', (
    tester,
  ) async {
    camera.granted = true;
    await pumpView(tester);
    // Deltas: a previous test's controller may still be disposing (the
    // plugin's platform side is one process-wide instance).
    final stopsBefore = camera.stops;
    await resume(tester);
    expect(camera.stops, stopsBefore + 1);
    expect(camera.starts, 2);
    expect(controllerOf(tester).value.isRunning, isTrue);
  });

  testWidgets('losing focus alone (split screen, Control Center) keeps it', (
    tester,
  ) async {
    camera.granted = true;
    await pumpView(tester);
    final stopsBefore = camera.stops;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.stops, stopsBefore);
    expect(camera.starts, 1);
    expect(controllerOf(tester).value.isRunning, isTrue);
  });

  testWidgets('stopCamera() (pairing, before connecting) stops it', (
    tester,
  ) async {
    camera.granted = true;
    await pumpView(tester);
    final stopsBefore = camera.stops;
    await stateOf(tester).stopCamera();
    await tester.pumpAndSettle();
    expect(camera.stops, stopsBefore + 1);
    expect(controllerOf(tester).value.isRunning, isFalse);
  });

  testWidgets(
    'stopCamera() while the start is still in flight stops it once it lands, '
    'and a later resume keeps it off',
    (tester) async {
      camera
        ..granted = true
        ..startGate = Completer<void>();
      await pumpView(tester);
      expect(camera.starts, 1);
      expect(controllerOf(tester).value.isRunning, isFalse);
      final stopsBefore = camera.stops;

      var stopped = false;
      unawaited(stateOf(tester).stopCamera().then((_) => stopped = true));
      await tester.pump();
      expect(stopped, isFalse, reason: 'waits for the pending start');

      camera.startGate!.complete();
      await tester.pumpAndSettle();
      expect(stopped, isTrue);
      expect(camera.stops, stopsBefore + 1);
      expect(controllerOf(tester).value.isRunning, isFalse);

      await resume(tester);
      expect(camera.starts, 1, reason: 'held off after stopCamera()');
      expect(controllerOf(tester).value.isRunning, isFalse);
    },
  );

  testWidgets(
    'unmounted while the start is still in flight: the camera is stopped as '
    'soon as the start lands',
    (tester) async {
      camera
        ..granted = true
        ..startGate = Completer<void>();
      await pumpView(tester);
      expect(camera.starts, 1);
      final stopsBefore = camera.stops;

      // The page moves on (e.g. pairing after stopCamera()'s bounded wait).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      camera.startGate!.complete();
      await tester.pumpAndSettle();
      expect(
        camera.stops,
        greaterThan(stopsBefore),
        reason: 'the late start must not leave the camera running',
      );
      expect(camera.log.last, 'stop');
    },
  );

  testWidgets(
    'unmounted while a RESUME restart is in flight: stopped once it lands',
    (tester) async {
      camera.granted = true;
      await pumpView(tester);
      // Leave the screen (camera stopped), come back with the restart held.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();
      camera.startGate = Completer<void>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(camera.starts, 2, reason: 'restart issued, still in flight');
      final stopsBefore = camera.stops;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      camera.startGate!.complete();
      await tester.pumpAndSettle();

      expect(camera.stops, greaterThan(stopsBefore));
      expect(camera.log.last, 'stop');
    },
  );

  testWidgets('a start failure offers Retry; a double tap retries once', (
    tester,
  ) async {
    camera
      ..granted = true
      ..startErrorCode = 'MOBILE_SCANNER_GENERIC_ERROR';
    await pumpView(tester);
    expect(find.text('The camera could not be started.'), findsOneWidget);
    expect(find.byKey(viewfinder), findsNothing);
    final failed = controllerOf(tester);

    camera.startErrorCode = null;
    await tester.tap(find.byKey(retryButton));
    await tester.tap(find.byKey(retryButton), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(camera.starts, 2, reason: 'one failed start + ONE retry');
    expect(identical(controllerOf(tester), failed), isFalse);
    expect(controllerOf(tester).value.isRunning, isTrue);
    expect(find.byKey(viewfinder), findsOneWidget);
  });

  group('viewfinder stays square', () {
    for (final size in const [
      Size(400, 800), // portrait phone body
      Size(900, 330), // landscape phone body
      Size(411, 200), // short split-screen pane
      Size(1200, 900), // tablet: capped
    ]) {
      testWidgets('$size', (tester) async {
        camera.granted = true;
        await pumpView(tester, size: size);
        final rect = tester.getRect(find.byKey(viewfinder));
        expect(rect.width, rect.height);
        expect(rect.width, QrScannerView.viewfinderSide(size));
        expect(rect.width, lessThanOrEqualTo(280));
        expect(rect.center, Offset(size.width / 2, size.height / 2));
      });
    }
  });

  testWidgets('no room (preview squeezed by the keyboard): no frame at all', (
    tester,
  ) async {
    camera.granted = true;
    await pumpView(tester, size: const Size(700, 100));
    expect(QrScannerView.viewfinderSide(const Size(700, 100)), 0);
    expect(find.byKey(viewfinder), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
