import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/notifications/incoming_call_window_lease.dart';
import 'package:toxee/notifications/notification_service.dart';
import 'package:toxee/util/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IncomingCallWindowLeaseStore', () {
    test('strips the nonce before incoming-call payload routing', () {
      expect(
        stripIncomingCallWindowNonce('incoming_call:call-1:private-nonce'),
        'incoming_call:call-1',
      );
      expect(
        stripIncomingCallWindowNonce('incoming_call:call-1'),
        'incoming_call:call-1',
      );
      expect(stripIncomingCallWindowNonce('c2c_peer'), 'c2c_peer');
    });

    test('persists only digests and an exact two-minute expiry', () async {
      final preferences = _FakeLeasePreferences();
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000123);
      var requestedRandomBytes = 0;
      final store = IncomingCallWindowLeaseStore(
        preferences: preferences,
        now: () => now,
        randomBytes: (length) {
          requestedRandomBytes = length;
          return List<int>.generate(length, (index) => index);
        },
      );

      final issue = await store.issue('sensitive-call-id');

      expect(requestedRandomBytes, 32);
      expect(issue.expiresAtEpochMs, now.millisecondsSinceEpoch + 120000);
      expect(
        preferences.values.keys,
        unorderedEquals(incomingCallWindowLeasePreferenceKeys),
      );
      expect(
        preferences.values[incomingCallWindowNonceDigestPrefsKey],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        preferences.values[incomingCallWindowCallDigestPrefsKey],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        preferences.values[incomingCallWindowExpiresAtPrefsKey],
        issue.expiresAtEpochMs,
      );
      expect(preferences.values.values, isNot(contains(issue.nonce)));
      expect(
        preferences.values.values.any(
          (value) => value.toString().contains('sensitive-call-id'),
        ),
        isFalse,
      );
      expect(
        issue.callDigest,
        isNot(sha256.convert(utf8.encode('sensitive-call-id')).toString()),
        reason: 'the call digest must use the incoming-call lease domain',
      );
      expect(issue.toString(), isNot(contains(issue.nonce)));
      expect(issue.toString(), isNot(contains(issue.callDigest)));
    });

    for (var failedWrite = 1; failedWrite <= 3; failedWrite++) {
      test(
        'write $failedWrite failure removes every partial lease key',
        () async {
          final preferences = _FakeLeasePreferences(failWrite: failedWrite);
          final store = IncomingCallWindowLeaseStore(
            preferences: preferences,
            randomBytes: (length) => List<int>.filled(length, 7),
          );

          await expectLater(
            store.issue('call-id'),
            throwsA(isA<IncomingCallWindowLeaseStorageException>()),
          );

          expect(preferences.values, isEmpty);
          expect(
            preferences.removeCalls,
            containsAll(incomingCallWindowLeasePreferenceKeys),
          );
        },
      );
    }

    for (var thrownWrite = 1; thrownWrite <= 3; thrownWrite++) {
      test(
        'thrown write $thrownWrite removes every partial lease key',
        () async {
          final preferences = _FakeLeasePreferences(throwWrite: thrownWrite);
          final store = IncomingCallWindowLeaseStore(
            preferences: preferences,
            randomBytes: (length) => List<int>.filled(length, 8),
          );

          await expectLater(
            store.issue('call-id'),
            throwsA(isA<IncomingCallWindowLeaseStorageException>()),
          );

          expect(preferences.values, isEmpty);
        },
      );
    }

    test('a rollback failure cannot leave a complete valid lease', () async {
      final preferences = _FakeLeasePreferences(
        failWrite: 3,
        failRemoveKey: incomingCallWindowNonceDigestPrefsKey,
        failRemoveOnlyWhenPresent: true,
      );
      final store = IncomingCallWindowLeaseStore(
        preferences: preferences,
        randomBytes: (length) => List<int>.filled(length, 9),
      );

      await expectLater(
        store.issue('call-id'),
        throwsA(isA<IncomingCallWindowLeaseStorageException>()),
      );

      expect(
        incomingCallWindowLeasePreferenceKeys.every(
          preferences.values.containsKey,
        ),
        isFalse,
      );
      expect(
        preferences.values.containsKey(incomingCallWindowExpiresAtPrefsKey),
        isFalse,
      );
    });

    for (final failedKey in incomingCallWindowLeasePreferenceKeys) {
      test(
        'clear reports a false remove for $failedKey after trying all keys',
        () async {
          final preferences = _FakeLeasePreferences(failRemoveKey: failedKey)
            ..values.addAll(<String, Object>{
              for (final key in incomingCallWindowLeasePreferenceKeys)
                key: 'old',
            });
          final store = IncomingCallWindowLeaseStore(preferences: preferences);

          await expectLater(
            store.clear(),
            throwsA(isA<IncomingCallWindowLeaseStorageException>()),
          );

          expect(
            preferences.removeCalls,
            unorderedEquals(incomingCallWindowLeasePreferenceKeys),
          );
          expect(preferences.values.keys, <String>[failedKey]);
        },
      );
    }

    test('initial clear exceptions prevent every lease write', () async {
      final preferences =
          _FakeLeasePreferences(
              throwRemoveKey: incomingCallWindowCallDigestPrefsKey,
            )
            ..values.addAll(<String, Object>{
              for (final key in incomingCallWindowLeasePreferenceKeys)
                key: 'old',
            });
      final store = IncomingCallWindowLeaseStore(preferences: preferences);

      await expectLater(
        store.issue('call-id'),
        throwsA(isA<IncomingCallWindowLeaseStorageException>()),
      );

      expect(preferences.writeCount, 0);
      expect(
        preferences.removeCalls,
        unorderedEquals(incomingCallWindowLeasePreferenceKeys),
      );
    });
  });

  group('NotificationService incoming-call lease lifecycle', () {
    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const windowChannel = MethodChannel('toxee/incoming_call_window');
    final shownPayloads = <String>[];
    final armedNonces = <String>[];
    Completer<void>? firstArmStarted;
    Completer<void>? releaseFirstArm;
    late final Directory logDirectory;
    late final File logFile;

    setUpAll(() async {
      logDirectory = await Directory.systemTemp.createTemp(
        'toxee-incoming-call-lease-test-',
      );
      logFile = File('${logDirectory.path}/notifications.log');
      AppLogger.setLogPath(logFile.path);
      AppLogger.setFileLoggingEnabled(true);
      AppLogger.setConsoleLoggingEnabled(false);
      await AppLogger.initialize();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            if (call.method == 'initialize') return true;
            if (call.method == 'getNotificationAppLaunchDetails') return null;
            if (call.method == 'show') {
              final arguments = call.arguments as Map<Object?, Object?>;
              shownPayloads.add(arguments['payload']! as String);
            }
            return null;
          });
      await NotificationService.instance.init();
      NotificationService.debugForceIsAndroid = true;
    });

    setUp(() {
      shownPayloads.clear();
      armedNonces.clear();
      firstArmStarted = null;
      releaseFirstArm = null;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      NotificationService.instance.debugAndroidPermissionGranted = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, (call) async {
            if (call.method == 'armIncomingCallWindow') {
              final arguments = call.arguments as Map<Object?, Object?>;
              armedNonces.add(arguments['token']! as String);
              if (armedNonces.length == 1 && releaseFirstArm != null) {
                firstArmStarted?.complete();
                await releaseFirstArm!.future;
              }
            }
            return null;
          });
    });

    tearDownAll(() async {
      NotificationService.debugForceIsAndroid = null;
      NotificationService.instance.debugAndroidPermissionGranted = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
      await logDirectory.delete(recursive: true);
    });

    test(
      'replacement clears a prior lease before permission-denied fallback',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          incomingCallWindowNonceDigestPrefsKey: 'old-nonce-digest',
          incomingCallWindowCallDigestPrefsKey: 'old-call-digest',
          incomingCallWindowExpiresAtPrefsKey: 9999999999999,
        });
        NotificationService.instance.debugAndroidPermissionGranted = false;

        final outcome = await NotificationService.instance
            .showIncomingCallNotification(
              callId: 'replacement-call',
              displayName: 'Caller',
              isVideo: false,
            );

        expect(outcome, IncomingCallNotificationOutcome.inAppOnlyFallback);
        final preferences = await SharedPreferences.getInstance();
        for (final key in incomingCallWindowLeasePreferenceKeys) {
          expect(preferences.containsKey(key), isFalse);
        }
      },
    );

    test('unsupported replacement still clears the prior lease', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        incomingCallWindowNonceDigestPrefsKey: 'old-nonce-digest',
        incomingCallWindowCallDigestPrefsKey: 'old-call-digest',
        incomingCallWindowExpiresAtPrefsKey: 9999999999999,
      });
      NotificationService.debugForceIsAndroid = false;
      addTearDown(() => NotificationService.debugForceIsAndroid = true);

      expect(
        await NotificationService.instance.showIncomingCallNotification(
          callId: 'unsupported-call',
          displayName: 'Caller',
          isVideo: false,
        ),
        IncomingCallNotificationOutcome.unsupported,
      );

      final preferences = await SharedPreferences.getInstance();
      for (final key in incomingCallWindowLeasePreferenceKeys) {
        expect(preferences.containsKey(key), isFalse);
      }
    });

    test(
      'test tap injection strips incoming-call nonces before routing',
      () async {
        final routedPayload = NotificationService.instance.onSelectStream.first;

        NotificationService.instance.debugInjectNotificationTap(
          'incoming_call:call-1:private-nonce',
        );

        expect(await routedPayload, 'incoming_call:call-1');
      },
    );

    test(
      'shown payload carries the nonce but persisted values do not',
      () async {
        final outcome = await NotificationService.instance
            .showIncomingCallNotification(
              callId: 'private-call-id',
              displayName: 'Caller',
              isVideo: true,
            );

        expect(outcome, IncomingCallNotificationOutcome.shown);
        expect(armedNonces, hasLength(1));
        expect(shownPayloads, hasLength(1));
        final nonce = armedNonces.single;
        expect(nonce, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(shownPayloads.single, 'incoming_call:private-call-id:$nonce');

        final preferences = await SharedPreferences.getInstance();
        final persisted = <Object?>[
          for (final key in incomingCallWindowLeasePreferenceKeys)
            preferences.get(key),
        ];
        expect(persisted, isNot(contains(nonce)));
        expect(
          persisted.any(
            (value) => value.toString().contains('private-call-id'),
          ),
          isFalse,
        );
      },
    );

    test('a stale async issue cannot clear its replacement lease', () async {
      firstArmStarted = Completer<void>();
      releaseFirstArm = Completer<void>();

      final stale = NotificationService.instance.showIncomingCallNotification(
        callId: 'stale-call',
        displayName: 'First',
        isVideo: false,
      );
      await firstArmStarted!.future;
      final replacement = NotificationService.instance
          .showIncomingCallNotification(
            callId: 'new-call',
            displayName: 'Second',
            isVideo: false,
          );
      releaseFirstArm!.complete();

      expect(await stale, IncomingCallNotificationOutcome.cancelled);
      expect(await replacement, IncomingCallNotificationOutcome.shown);
      expect(armedNonces, hasLength(2));
      expect(shownPayloads, <String>[
        'incoming_call:new-call:${armedNonces.last}',
      ]);

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(incomingCallWindowNonceDigestPrefsKey),
        sha256.convert(utf8.encode(armedNonces.last)).toString(),
      );
    });

    test(
      'incoming-call failures do not log lease secrets or call IDs',
      () async {
        const callId = 'private-log-call-id';
        String? nonce;
        String? nonceDigest;
        String? callDigest;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(windowChannel, (call) async {
              if (call.method != 'armIncomingCallWindow') return null;
              final arguments = call.arguments as Map<Object?, Object?>;
              nonce = arguments['token']! as String;
              final preferences = await SharedPreferences.getInstance();
              nonceDigest = preferences.getString(
                incomingCallWindowNonceDigestPrefsKey,
              );
              callDigest = preferences.getString(
                incomingCallWindowCallDigestPrefsKey,
              );
              throw PlatformException(
                code: 'arm-failed',
                message: '$callId $nonce $nonceDigest $callDigest',
              );
            });

        expect(
          await NotificationService.instance.showIncomingCallNotification(
            callId: callId,
            displayName: 'Caller',
            isVideo: false,
          ),
          IncomingCallNotificationOutcome.failedFallback,
        );

        final logs = await logFile.readAsString();
        expect(logs, isNot(contains(callId)));
        expect(logs, isNot(contains(nonce)));
        expect(logs, isNot(contains(nonceDigest)));
        expect(logs, isNot(contains(callDigest)));
      },
    );

    test(
      'terminal cancellation removes the complete persisted lease',
      () async {
        expect(
          await NotificationService.instance.showIncomingCallNotification(
            callId: 'terminal-call',
            displayName: 'Caller',
            isVideo: false,
          ),
          IncomingCallNotificationOutcome.shown,
        );

        await NotificationService.instance.cancelIncomingCallNotification();

        final preferences = await SharedPreferences.getInstance();
        for (final key in incomingCallWindowLeasePreferenceKeys) {
          expect(preferences.containsKey(key), isFalse);
        }
      },
    );
  });
}

class _FakeLeasePreferences implements IncomingCallWindowPreferences {
  _FakeLeasePreferences({
    this.failWrite,
    this.throwWrite,
    this.failRemoveKey,
    this.throwRemoveKey,
    this.failRemoveOnlyWhenPresent = false,
  });

  final int? failWrite;
  final int? throwWrite;
  final String? failRemoveKey;
  final String? throwRemoveKey;
  final bool failRemoveOnlyWhenPresent;
  final Map<String, Object> values = <String, Object>{};
  final List<String> removeCalls = <String>[];
  int _writeCount = 0;

  bool _canWrite() {
    _writeCount++;
    if (_writeCount == throwWrite) {
      throw StateError('simulated write failure');
    }
    return _writeCount != failWrite;
  }

  int get writeCount => _writeCount;

  @override
  Future<bool> remove(String key) async {
    removeCalls.add(key);
    if (key == throwRemoveKey) {
      throw StateError('simulated remove failure');
    }
    if (key == failRemoveKey &&
        (!failRemoveOnlyWhenPresent || values.containsKey(key))) {
      return false;
    }
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    if (!_canWrite()) return false;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    if (!_canWrite()) return false;
    values[key] = value;
    return true;
  }
}
