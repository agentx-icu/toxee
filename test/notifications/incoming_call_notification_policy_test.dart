import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/call/call_service_manager.dart';
import 'package:toxee/notifications/incoming_call_window_lease.dart';
import 'package:toxee/notifications/notification_payload.dart';
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
      SharedPreferences.setMockInitialValues(<String, Object>{
        IncomingCallWindowLeasePrefs.legacyRawTokenKey: 'old-token',
        IncomingCallWindowLeasePrefs.nonceDigestKey: 'old-nonce-digest',
        IncomingCallWindowLeasePrefs.callIdDigestKey: 'old-call-digest',
        IncomingCallWindowLeasePrefs.expiresAtEpochMsKey: 9999999999999,
      });
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      const windowChannel = MethodChannel('toxee/incoming_call_window');
      var nativeClearCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'initialize') return true;
            if (call.method == 'getNotificationAppLaunchDetails') return null;
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, (call) async {
            if (call.method == 'clearIncomingCallWindow') nativeClearCount++;
            return null;
          });
      addTearDown(() {
        NotificationService.debugForceIsAndroid = null;
        NotificationService.instance.debugAndroidPermissionGranted = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(windowChannel, null);
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
      final prefs = await SharedPreferences.getInstance();
      for (final key in IncomingCallWindowLeasePrefs.allKeys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(nativeClearCount, 1);
    },
  );

  test('unsupported incoming-call replacement clears the old lease', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      IncomingCallWindowLeasePrefs.legacyRawTokenKey: 'old-token',
      IncomingCallWindowLeasePrefs.nonceDigestKey: 'old-nonce-digest',
      IncomingCallWindowLeasePrefs.callIdDigestKey: 'old-call-digest',
      IncomingCallWindowLeasePrefs.expiresAtEpochMsKey: 9999999999999,
    });
    NotificationService.debugForceIsAndroid = false;
    addTearDown(() => NotificationService.debugForceIsAndroid = null);

    expect(
      await NotificationService.instance.showIncomingCallNotification(
        callId: 'unsupported-call',
        displayName: 'Alice',
        isVideo: false,
      ),
      IncomingCallNotificationOutcome.unsupported,
    );

    final prefs = await SharedPreferences.getInstance();
    for (final key in IncomingCallWindowLeasePrefs.allKeys) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
  });

  test('Android incoming-call notification carries only raw nonce', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const windowChannel = MethodChannel('toxee/incoming_call_window');
    Object? showArguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'getNotificationAppLaunchDetails') return null;
          if (call.method == 'show') {
            showArguments = call.arguments;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async => null);
    addTearDown(() {
      NotificationService.debugForceIsAndroid = null;
      NotificationService.instance.debugAndroidPermissionGranted = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
    });

    final service = NotificationService.instance;
    await service.init();
    NotificationService.debugForceIsAndroid = true;
    service.debugAndroidPermissionGranted = true;

    final result = await service.showIncomingCallNotification(
      callId: 'call-lease',
      displayName: 'Alice',
      isVideo: false,
    );

    expect(result, IncomingCallNotificationOutcome.shown);
    final showMap = showArguments as Map<Object?, Object?>;
    final payload = showMap['payload']! as String;
    expect(payload, startsWith('incoming_call:call-lease:'));
    expect(
      parseNotificationTapPayload(payload),
      const NotificationTapTarget.incomingCall('call-lease'),
    );
    final nonce = payload.substring(payload.lastIndexOf(':') + 1);
    expect(nonce, hasLength(64));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(IncomingCallWindowLeasePrefs.nonceDigestKey),
      allOf(isNotNull, isNot(nonce)),
    );
    expect(
      prefs.getString(IncomingCallWindowLeasePrefs.callIdDigestKey),
      allOf(isNotNull, isNot('call-lease')),
    );
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key).toString();
      expect(value, isNot(contains(nonce)), reason: key);
      expect(value, isNot(contains('call-lease')), reason: key);
    }
  });

  test('stale async show cannot clear its replacement lease', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const windowChannel = MethodChannel('toxee/incoming_call_window');
    final firstShowStarted = Completer<void>();
    final releaseFirstShow = Completer<void>();
    final payloads = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'getNotificationAppLaunchDetails') return null;
          if (call.method == 'show') {
            final arguments = call.arguments as Map<Object?, Object?>;
            payloads.add(arguments['payload']! as String);
            if (payloads.length == 1) {
              firstShowStarted.complete();
              await releaseFirstShow.future;
            }
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (_) async => null);
    addTearDown(() {
      NotificationService.debugForceIsAndroid = null;
      NotificationService.instance.debugAndroidPermissionGranted = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
    });

    final service = NotificationService.instance;
    await service.init();
    NotificationService.debugForceIsAndroid = true;
    service.debugAndroidPermissionGranted = true;

    final stale = service.showIncomingCallNotification(
      callId: 'stale-call',
      displayName: 'First',
      isVideo: false,
    );
    await firstShowStarted.future;
    final replacement = service.showIncomingCallNotification(
      callId: 'replacement-call',
      displayName: 'Second',
      isVideo: false,
    );
    releaseFirstShow.complete();

    expect(await stale, IncomingCallNotificationOutcome.cancelled);
    expect(await replacement, IncomingCallNotificationOutcome.shown);
    expect(payloads, hasLength(2));
    expect(payloads.last, startsWith('incoming_call:replacement-call:'));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(IncomingCallWindowLeasePrefs.callIdDigestKey),
      IncomingCallWindowLeaseStore.callIdentityDigestForTest(
        'replacement-call',
      ),
    );
  });

  test(
    'terminal cancellation clears persisted and native lease state',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const notificationsChannel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      const windowChannel = MethodChannel('toxee/incoming_call_window');
      var nativeClearCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            if (call.method == 'initialize') return true;
            if (call.method == 'getNotificationAppLaunchDetails') return null;
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, (call) async {
            if (call.method == 'clearIncomingCallWindow') nativeClearCount++;
            return null;
          });
      addTearDown(() {
        NotificationService.debugForceIsAndroid = null;
        NotificationService.instance.debugAndroidPermissionGranted = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(notificationsChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(windowChannel, null);
      });

      final service = NotificationService.instance;
      await service.init();
      NotificationService.debugForceIsAndroid = true;
      service.debugAndroidPermissionGranted = true;
      expect(
        await service.showIncomingCallNotification(
          callId: 'terminal-call',
          displayName: 'Alice',
          isVideo: false,
        ),
        IncomingCallNotificationOutcome.shown,
      );

      await service.cancelIncomingCallNotification();

      final prefs = await SharedPreferences.getInstance();
      for (final key in IncomingCallWindowLeasePrefs.allKeys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(nativeClearCount, 2);
    },
  );

  for (final nativeClearFails in <bool>[false, true]) {
    final failureSource = nativeClearFails ? 'native' : 'persisted';
    test(
      'terminal cancellation attempts plugin cancel and reports $failureSource clear failure',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        const notificationsChannel = MethodChannel(
          'dexterous.com/flutter/local_notifications',
        );
        const windowChannel = MethodChannel('toxee/incoming_call_window');
        var pluginCancelCount = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(notificationsChannel, (call) async {
              if (call.method == 'initialize') return true;
              if (call.method == 'getNotificationAppLaunchDetails') {
                return null;
              }
              if (call.method == 'cancel') pluginCancelCount++;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(windowChannel, (_) async {
              if (nativeClearFails) {
                throw PlatformException(code: 'clear-failed');
              }
              return null;
            });
        addTearDown(() {
          NotificationService.debugForceIsAndroid = null;
          NotificationService.instance.debugAndroidPermissionGranted = null;
          NotificationService.instance.debugIncomingCallWindowLeaseStore = null;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(notificationsChannel, null);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(windowChannel, null);
        });

        final service = NotificationService.instance;
        await service.init();
        NotificationService.debugForceIsAndroid = true;
        service.debugAndroidPermissionGranted = true;
        if (!nativeClearFails) {
          service.debugIncomingCallWindowLeaseStore =
              IncomingCallWindowLeaseStore(
                preferences: _FailingClearPreferences(),
              );
        }

        await expectLater(
          service.cancelIncomingCallNotification(),
          throwsA(isA<IncomingCallWindowLeaseStorageException>()),
        );
        expect(pluginCancelCount, 1);
      },
    );
  }

  test('persisted clear failure blocks incoming notification issue', () async {
    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const windowChannel = MethodChannel('toxee/incoming_call_window');
    final preferences = _FailingClearPreferences();
    var showCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'getNotificationAppLaunchDetails') return null;
          if (call.method == 'show') showCount++;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (_) async => null);
    addTearDown(() {
      NotificationService.debugForceIsAndroid = null;
      NotificationService.instance.debugAndroidPermissionGranted = null;
      NotificationService.instance.debugIncomingCallWindowLeaseStore = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
    });

    final service = NotificationService.instance;
    await service.init();
    NotificationService.debugForceIsAndroid = true;
    service.debugAndroidPermissionGranted = true;
    service.debugIncomingCallWindowLeaseStore = IncomingCallWindowLeaseStore(
      preferences: preferences,
    );

    expect(
      await service.showIncomingCallNotification(
        callId: 'clear-failure-call',
        displayName: 'Alice',
        isVideo: false,
      ),
      IncomingCallNotificationOutcome.failedFallback,
    );
    expect(showCount, 0);
    expect(
      preferences.removeAttempts.toSet(),
      IncomingCallWindowLeasePrefs.allKeys.toSet(),
    );
  });

  test('native clear failure blocks incoming notification issue', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const windowChannel = MethodChannel('toxee/incoming_call_window');
    var showCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method == 'getNotificationAppLaunchDetails') return null;
          if (call.method == 'show') showCount++;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (_) async {
          throw PlatformException(code: 'clear-failed');
        });
    addTearDown(() {
      NotificationService.debugForceIsAndroid = null;
      NotificationService.instance.debugAndroidPermissionGranted = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
    });

    final service = NotificationService.instance;
    await service.init();
    NotificationService.debugForceIsAndroid = true;
    service.debugAndroidPermissionGranted = true;

    expect(
      await service.showIncomingCallNotification(
        callId: 'native-clear-failure-call',
        displayName: 'Alice',
        isVideo: false,
      ),
      IncomingCallNotificationOutcome.failedFallback,
    );
    expect(showCount, 0);
  });

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

class _FailingClearPreferences implements IncomingCallWindowLeasePreferences {
  final List<String> removeAttempts = <String>[];

  @override
  Future<bool> remove(String key) async {
    removeAttempts.add(key);
    return false;
  }

  @override
  Future<bool> setInt(String key, int value) async => true;

  @override
  Future<bool> setString(String key, String value) async => true;
}
