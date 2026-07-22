import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final manifestFile = File(
    '$repoRoot/android/app/src/main/AndroidManifest.xml',
  );
  final pollingServiceFile = File(
    '$repoRoot/android/app/src/main/kotlin/com/toxee/app/ToxPollingService.kt',
  );
  final foregroundChannelFile = File(
    '$repoRoot/android/app/src/main/kotlin/com/toxee/app/RuntimeForegroundChannel.kt',
  );
  final mainActivityFile = File(
    '$repoRoot/android/app/src/main/kotlin/com/toxee/app/MainActivity.kt',
  );
  final notificationServiceFile = File(
    '$repoRoot/lib/notifications/notification_service.dart',
  );

  test(
    'Android phone-call foreground service declares required permissions',
    () async {
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'AndroidManifest.xml moved; update this regression test.',
      );
      final manifest = await manifestFile.readAsString();

      expect(
        manifest,
        contains('android.permission.FOREGROUND_SERVICE_PHONE_CALL'),
      );
      expect(
        manifest,
        contains('android.permission.MANAGE_OWN_CALLS'),
        reason:
            'Android requires phoneCall foreground services to either declare '
            'MANAGE_OWN_CALLS or run as the default dialer.',
      );
      expect(
        manifest,
        contains('android.permission.MODIFY_AUDIO_SETTINGS'),
        reason:
            'CallAudioChannel changes communication devices, speakerphone, '
            'and Bluetooth SCO routing.',
      );
      expect(
        manifest,
        contains('android.permission.WAKE_LOCK'),
        reason: 'Voice calls use a proximity-screen-off wake lock on earpiece.',
      );
      expect(
        manifest,
        contains('android.permission.FOREGROUND_SERVICE_MICROPHONE'),
      );
      expect(
        manifest,
        contains('android.permission.FOREGROUND_SERVICE_CAMERA'),
      );
      expect(
        manifest,
        contains(
          'android:foregroundServiceType="dataSync|phoneCall|microphone|camera"',
        ),
      );
    },
  );

  test(
    'Android call foreground mode includes mic and optional camera types',
    () async {
      final service = await pollingServiceFile.readAsString();
      final channel = await foregroundChannelFile.readAsString();

      expect(
        service,
        contains('ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE'),
      );
      expect(service, contains('ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA'));
      expect(service, contains('EXTRA_USE_CAMERA'));
      expect(channel, contains('EXTRA_USE_CAMERA'));
    },
  );

  test('Android incoming-call lock-screen surface is runtime gated', () async {
    final manifest = await manifestFile.readAsString();
    final activity = await mainActivityFile.readAsString();
    final notificationService = await notificationServiceFile.readAsString();

    expect(manifest, contains('android.permission.USE_FULL_SCREEN_INTENT'));
    expect(
      manifest,
      isNot(contains('android:showWhenLocked="true"')),
      reason:
          'MainActivity must not always show private chat UI over the lock screen.',
    );
    expect(
      manifest,
      isNot(contains('android:turnScreenOn="true"')),
      reason:
          'Only incoming-call notification launches may turn the screen on.',
    );
    expect(activity, contains('SELECT_NOTIFICATION'));
    expect(activity, contains('payload'));
    expect(activity, contains('incoming_call:'));
    expect(activity, contains('INCOMING_CALL_WINDOW_TOKEN_ARG'));
    expect(activity, contains('INCOMING_CALL_WINDOW_TOKEN_PREF_KEY'));
    expect(activity, contains('activeIncomingCallWindowToken'));
    expect(activity, contains('armIncomingCallWindow'));
    expect(activity, contains('setShowWhenLocked'));
    expect(activity, contains('setTurnScreenOn'));
    expect(notificationService, contains('toxee/incoming_call_window'));
    expect(notificationService, contains('_newIncomingCallWindowToken'));
    expect(notificationService, contains('_incomingCallWindowTokenPrefsKey'));
    expect(notificationService, contains('armIncomingCallWindow'));
    expect(notificationService, contains('clearIncomingCallWindow'));
    expect(notificationService, contains('_stripIncomingCallWindowToken'));
  });

  test('Android opts into predictive back for PopScope handlers', () async {
    final manifest = await manifestFile.readAsString();
    expect(manifest, contains('android:enableOnBackInvokedCallback="true"'));
  });
}
