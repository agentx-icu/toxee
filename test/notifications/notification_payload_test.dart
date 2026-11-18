import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/notifications/notification_payload.dart';
import 'package:toxee/notifications/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a cold launch does not deliver another account’s saved tap', () async {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final payload = bindNotificationPayload('c2c_peer', 'a' * 64);
    var requestedLaunchDetails = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'getNotificationAppLaunchDetails') {
        requestedLaunchDetails = true;
        return {
          'notificationLaunchedApp': true,
          'notificationResponse': {
            'notificationResponseType': 0,
            'payload': payload,
          },
        };
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = NotificationService.instance;
    await service.init();
    expect(requestedLaunchDetails, isTrue);

    service.setSessionPostsEnabled(true, accountKey: 'b' * 64);
    addTearDown(() => service.setSessionPostsEnabled(true));
    expect(service.consumeLaunchPayload(), isNull);
  });

  test('only the account that issued a notification can open its chat', () {
    final key = 'a' * 64;
    final payload = bindNotificationPayload('c2c_peer', key);
    final fullAddress = '${key.toUpperCase()}${'1' * 12}';

    expect(notificationPayloadForAccount(payload, fullAddress), 'c2c_peer');
    expect(notificationPayloadForAccount(payload, 'b' * 64), isNull);
    expect(notificationPayloadForAccount(payload, null), isNull);
    expect(notificationPayloadForAccount('c2c_peer', key), isNull);
    expect(isMessageNotificationPayload(payload), isTrue);
    expect(isMessageNotificationPayload('c2c_legacy'), isTrue);
    expect(
      isMessageNotificationPayload(
        bindNotificationPayload('friend_req:p', key),
      ),
      isFalse,
    );
  });
  test('notification payload parser routes conversation payloads', () {
    expect(
      parseNotificationTapPayload('c2c_${'A' * 64}'),
      NotificationTapTarget.c2c('A' * 64),
    );
    expect(
      parseNotificationTapPayload('group_group-1'),
      const NotificationTapTarget.group('group-1'),
    );
    expect(
      parseNotificationTapPayload('missed_call:${'B' * 64}'),
      NotificationTapTarget.c2c('B' * 64),
    );
  });

  test(
    'notification payload parser routes call and friend request payloads',
    () {
      expect(
        parseNotificationTapPayload('incoming_call:call-1'),
        const NotificationTapTarget.incomingCall('call-1'),
      );
      expect(
        parseNotificationTapPayload('incoming_call:call-1:window-token'),
        const NotificationTapTarget.incomingCall('call-1'),
      );
      expect(
        parseNotificationTapPayload('friend_req:${'C' * 64}'),
        NotificationTapTarget.friendRequest('C' * 64),
      );
    },
  );

  test('notification payload parser rejects empty and unknown payloads', () {
    expect(parseNotificationTapPayload(''), isNull);
    expect(parseNotificationTapPayload('incoming_call:'), isNull);
    expect(parseNotificationTapPayload('friend_req:'), isNull);
    expect(parseNotificationTapPayload('unknown:payload'), isNull);
  });

  test(
    'home notification router handles incoming call and friend request taps',
    () async {
      final source = await File(
        '${Directory.current.path}/lib/ui/home_page_bootstrap.dart',
      ).readAsString();

      expect(source, contains('NotificationTapTargetKind.incomingCall'));
      expect(source, contains('NotificationTapTargetKind.friendRequest'));
    },
  );
}
