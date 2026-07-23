import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_service_manager.dart';
import 'package:toxee/notifications/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android incoming calls use a persistent full-screen call surface', () {
    final details = buildAndroidIncomingCallNotificationDetails();

    expect(details.importance, Importance.max);
    expect(details.priority, Priority.max);
    expect(details.category, AndroidNotificationCategory.call);
    expect(details.fullScreenIntent, isTrue);
    expect(details.ongoing, isTrue);
    expect(details.autoCancel, isFalse);
    expect(details.playSound, isFalse);
    expect(details.enableVibration, isFalse);
  });

  test(
    'cancelling a call invalidates in-flight and replaced notifications',
    () {
      final lease = IncomingCallNotificationLease();
      final first = lease.begin('call-1');
      expect(lease.isCurrent(first, 'call-1'), isTrue);

      lease.cancel();
      expect(lease.isCurrent(first, 'call-1'), isFalse);

      final second = lease.begin('call-2');
      final replacement = lease.begin('call-3');
      expect(lease.isCurrent(second, 'call-2'), isFalse);
      expect(lease.isCurrent(replacement, 'call-3'), isTrue);
    },
  );

  test(
    'Android denied incoming-call notification records in-app fallback',
    () async {
      const channel = MethodChannel('dexterous.com/flutter/local_notifications');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'initialize') return true;
            if (call.method == 'getNotificationAppLaunchDetails') return null;
            return null;
          });
      addTearDown(() {
        NotificationService.debugForceIsAndroid = null;
        NotificationService.instance.debugAndroidPermissionGranted = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = NotificationService.instance;
      await service.init();
      NotificationService.debugForceIsAndroid = true;
      service.debugAndroidPermissionGranted = false;

      final result = await service.showIncomingCallNotification(
        callId: 'call-42',
        displayName: 'Alice',
        isVideo: false,
      );

      expect(result, IncomingCallNotificationOutcome.inAppOnlyFallback);
      expect(
        service.debugLastIncomingCallNotificationOutcome,
        IncomingCallNotificationOutcome.inAppOnlyFallback,
      );
    },
  );

  test('incoming-call fallback outcomes request the right user notice', () {
    expect(
      shouldShowIncomingCallNotificationFallbackNotice(
        IncomingCallNotificationOutcome.inAppOnlyFallback,
      ),
      isTrue,
    );
    expect(
      shouldOfferSettingsForIncomingCallNotificationFallback(
        IncomingCallNotificationOutcome.inAppOnlyFallback,
      ),
      isTrue,
    );
    expect(
      shouldShowIncomingCallNotificationFallbackNotice(
        IncomingCallNotificationOutcome.failedFallback,
      ),
      isTrue,
    );
    expect(
      shouldOfferSettingsForIncomingCallNotificationFallback(
        IncomingCallNotificationOutcome.failedFallback,
      ),
      isFalse,
    );
    expect(
      shouldShowIncomingCallNotificationFallbackNotice(
        IncomingCallNotificationOutcome.shown,
      ),
      isFalse,
    );
  });
}
