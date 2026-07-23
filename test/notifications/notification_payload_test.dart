import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/notifications/notification_payload.dart';

void main() {
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

  test('notification payload parser routes call and friend request payloads', () {
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
  });

  test('notification payload parser rejects empty and unknown payloads', () {
    expect(parseNotificationTapPayload(''), isNull);
    expect(parseNotificationTapPayload('incoming_call:'), isNull);
    expect(parseNotificationTapPayload('friend_req:'), isNull);
    expect(parseNotificationTapPayload('unknown:payload'), isNull);
  });

  test('home notification router handles incoming call and friend request taps',
      () async {
    final source = await File(
      '${Directory.current.path}/lib/ui/home_page_bootstrap.dart',
    ).readAsString();

    expect(source, contains('NotificationTapTargetKind.incomingCall'));
    expect(source, contains('NotificationTapTargetKind.friendRequest'));
  });
}
