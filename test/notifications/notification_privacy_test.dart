// S2 (doc/reference/MOBILE_DEVICE_FEATURES.md): "hide message content in
// notifications". With the switch on, a message notification must carry
// neither the sender nor the text — including lines grouped into the same
// conversation's inbox before the switch was turned on. Off (the default)
// leaves notifications as they were.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:toxee/notifications/incoming_call_window_lease.dart';
import 'package:toxee/notifications/notification_privacy.dart';
import 'package:toxee/notifications/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final shown = <Map<Object?, Object?>>[];
  final cancelled = <Object?>[];

  setUp(() {
    shown.clear();
    cancelled.clear();
    SharedPreferences.setMockInitialValues({});
    NotificationPrivacy.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'show') {
            shown.add(call.arguments as Map<Object?, Object?>);
          }
          if (call.method == 'cancel') cancelled.add(call.arguments);
          if (call.method == 'getActiveNotifications') {
            // Posted by a previous process. Android reports group + channel but
            // no payload; iOS / macOS report the payload.
            return [
              {'id': 901, 'groupKey': 'toxee.messages.c2c_x', 'channelId': 'm'},
              {'id': 903, 'payload': 'group_from_last_run'},
              {
                'id': 902,
                'groupKey': 'toxee.friend_requests',
                'channelId': 'toxee_friend_requests',
              },
              {'id': 904, 'payload': 'friend_req:someone'},
            ];
          }
          return null;
        });
  });

  tearDown(() async {
    await NotificationService.instance.resetSessionState();
    NotificationPrivacy.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> send(String preview) =>
      NotificationService.instance.showMessageNotification(
        conversationId: 'c2c_privacy_peer',
        senderName: 'Alice',
        preview: preview,
      );

  test('off by default: sender and text are shown', () async {
    expect(await NotificationPrivacy.hidesContent(), isFalse);
    await NotificationService.instance.init();
    await send('secret one');
    expect(shown.last['title'], 'Alice');
    expect(shown.last['body'], 'secret one');
  });

  test('a message waiting for preferences cannot post after logout', () async {
    final service = NotificationService.instance;
    await service.init();
    service.debugIncomingCallWindowLeaseStore = IncomingCallWindowLeaseStore(
      prefs: await SharedPreferences.getInstance(),
    );
    addTearDown(() => service.debugIncomingCallWindowLeaseStore = null);
    SharedPreferences.setMockInitialValues({});
    final original = SharedPreferencesStorePlatform.instance;
    final store = _PendingPreferenceRead();
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);

    final pending = send('previous account message');
    await store.started.future.timeout(const Duration(seconds: 2));
    await service.resetSessionState();
    store.result.complete({'flutter.notification_hide_content': false});
    await pending;

    expect(shown, isEmpty);
    await send('new account message');
    expect(shown.single['body'], 'new account message');
  });

  test('old event producers cannot post during teardown', () async {
    final service = NotificationService.instance;
    await service.init();
    service.setSessionPostsEnabled(false);
    addTearDown(() => service.setSessionPostsEnabled(true));
    await send('message during teardown');
    await service.showFriendRequestNotification(
      senderId: 'old_account_peer',
      senderName: 'Old account contact',
      requestMessage: '',
    );
    expect(shown, isEmpty);

    service.setSessionPostsEnabled(true);
    await send('new account message');
    expect(shown.single['body'], 'new account message');
  });

  test(
    'logout cancels platform banners after submitted posts settle',
    () async {
      final service = NotificationService.instance;
      await service.init();
      final posting = Completer<void>();
      final releasePost = Completer<void>();
      final operations = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'show') {
              posting.complete();
              await releasePost.future;
              operations.add('show completed');
            }
            if (call.method == 'cancelAll') operations.add('cancelAll');
            return null;
          });

      final post = send('previous account message');
      await posting.future;
      final reset = service.resetSessionState();
      await Future<void>.delayed(Duration.zero);
      releasePost.complete();
      await Future.wait([post, reset]);

      expect(operations, ['show completed', 'cancelAll']);
    },
  );

  test('on: no sender, no text, not even previously grouped lines', () async {
    await NotificationService.instance.init();
    await send('secret one'); // grouped before the switch
    await NotificationPrivacy.setHideContent(true);
    await send('secret two');
    await send('secret three');

    expect(shown, hasLength(3));
    for (final hidden in shown.skip(1).map((s) => s.toString())) {
      expect(hidden, isNot(contains('Alice')));
      expect(hidden, isNot(contains('secret')));
    }
    expect(shown.last['title'], 'Toxee');
    expect(shown.last['body'], 'New message');
  });

  test('turning it on withdraws posted message notifications only', () async {
    final svc = NotificationService.instance;
    await svc.init();
    await send('secret one');
    final messageId = shown.last['id'];
    await svc.showFriendRequestNotification(
      senderId: 'someone',
      senderName: 'Bob',
      requestMessage: 'hi',
    );
    final friendRequestId = shown.last['id'];

    await NotificationPrivacy.setHideContent(true);

    String ids() => cancelled.toString();
    expect(ids(), contains('$messageId'));
    expect(ids(), contains('901'));
    expect(ids(), contains('903'));
    expect(ids(), isNot(contains('902')));
    expect(ids(), isNot(contains('904')));
    expect(ids(), isNot(contains('$friendRequestId')));
  });

  test('hiding content withdraws a plaintext post still in flight', () async {
    final service = NotificationService.instance;
    await service.init();
    final posting = Completer<void>();
    final releasePost = Completer<void>();
    final operations = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'show') {
            posting.complete();
            await releasePost.future;
            operations.add('show completed');
          }
          if (call.method == 'cancel') operations.add('cancel');
          return null;
        });

    final post = send('private text');
    await posting.future;
    final hide = NotificationPrivacy.setHideContent(true);
    await Future<void>.delayed(Duration.zero);
    releasePost.complete();
    await Future.wait([post, hide]);

    expect(operations, ['show completed', 'cancel']);
  });

  test('rapid saves apply in order: the last choice wins', () async {
    await Future.wait([
      NotificationPrivacy.setHideContent(true),
      NotificationPrivacy.setHideContent(false),
    ]);
    expect(NotificationPrivacy.hideContent.value, isFalse);
    NotificationPrivacy.debugReset();
    expect(await NotificationPrivacy.hidesContent(), isFalse);
  });

  test('the choice persists', () async {
    await NotificationPrivacy.setHideContent(true);
    NotificationPrivacy.debugReset();
    expect(await NotificationPrivacy.hidesContent(), isTrue);
  });
}

class _PendingPreferenceRead extends InMemorySharedPreferencesStore {
  _PendingPreferenceRead() : super.withData({});

  final started = Completer<void>();
  final result = Completer<Map<String, Object>>();

  @override
  Future<Map<String, Object>> getAll() {
    started.complete();
    return result.future;
  }
}
