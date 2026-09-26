// L1 gate for S59 — notification permission CONSEQUENCE. The macOS/iOS GRANT is
// irreducibly OS-owned (TCC), but the in-app behavior it drives IS testable: a
// DENIED notification permission must SUPPRESS the banner; a granted one must
// let it through. notification_service.dart gates display on
// `_androidPermissionGranted == false` (line ~328). On a non-Android test host
// both that branch and `_ensureAndroidPermission`'s plugin resolution are
// `Platform.isAndroid`-gated, so we use two `@visibleForTesting` seams:
// `debugForceIsAndroid` (take the Android gate path) + `debugAndroidPermission
// Granted` (seed the cached result, bypassing the null plugin). The observable
// is the `flutter_local_notifications` method channel: a suppressed notification
// never reaches the `show` platform call; an allowed one does.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/notifications/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final captured = <String>[];

  setUp(() {
    captured.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured.add(call.method);
      // initialize → ok; permission/launch queries → benign defaults.
      if (call.method == 'initialize') return true;
      if (call.method == 'getNotificationAppLaunchDetails') return null;
      return null;
    });
  });

  tearDown(() {
    // The platform override is a GLOBAL static — reset it so it can't leak into
    // other test files.
    NotificationService.debugForceIsAndroid = null;
    NotificationService.instance.debugAndroidPermissionGranted = null;
    NotificationService.instance.debugAreNotificationsEnabled = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'S59: a DENIED notification permission suppresses the banner; a GRANTED '
      'one lets it through', () async {
    final svc = NotificationService.instance;
    await svc.init(); // _initialized = true (macOS branch, channel mocked)

    // Force the Android permission-gate path on this macOS host.
    NotificationService.debugForceIsAndroid = true;

    // DENIED → showMessageNotification must early-return before any `show`.
    svc.debugAndroidPermissionGranted = false;
    captured.clear();
    await svc.showMessageNotification(
      conversationId: 'c2c_peer',
      senderName: 'Alice',
      preview: 'hello',
    );
    expect(captured, isNot(contains('show')),
        reason: 'a denied permission must NOT emit a platform show call');

    // GRANTED → the same call must reach the platform `show`.
    svc.debugAndroidPermissionGranted = true;
    captured.clear();
    await svc.showMessageNotification(
      conversationId: 'c2c_peer',
      senderName: 'Alice',
      preview: 'hello again',
    );
    expect(captured, contains('show'),
        reason: 'a granted permission must emit the platform show call');
  });

  group('a denial is re-read on resume, never cached for the session', () {
    Future<void> send(NotificationService svc) => svc.showMessageNotification(
          conversationId: 'c2c_peer',
          senderName: 'Alice',
          preview: 'hello',
        );

    test('enabled in system settings -> notifications resume', () async {
      final svc = NotificationService.instance;
      await svc.init();
      NotificationService.debugForceIsAndroid = true;
      svc.debugAndroidPermissionGranted = false;
      svc.debugAreNotificationsEnabled = () async => true;

      await svc.refreshAndroidPermission();
      captured.clear();
      await send(svc);
      expect(captured, contains('show'),
          reason: 'turning notifications on in settings must take effect '
              'without restarting the app');
    });

    test('still disabled -> still suppressed', () async {
      final svc = NotificationService.instance;
      await svc.init();
      NotificationService.debugForceIsAndroid = true;
      svc.debugAndroidPermissionGranted = false;
      svc.debugAreNotificationsEnabled = () async => false;

      await svc.refreshAndroidPermission();
      captured.clear();
      await send(svc);
      expect(captured, isNot(contains('show')));
    });

    test('a granted state is not re-queried', () async {
      final svc = NotificationService.instance;
      await svc.init();
      NotificationService.debugForceIsAndroid = true;
      svc.debugAndroidPermissionGranted = true;
      var queries = 0;
      svc.debugAreNotificationsEnabled = () async {
        queries++;
        return false;
      };

      await svc.refreshAndroidPermission();
      expect(queries, 0);
      captured.clear();
      await send(svc);
      expect(captured, contains('show'));
    });
  });
}
