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
  final incomingCallLeaseStoreFile = File(
    '$repoRoot/android/app/src/main/kotlin/com/toxee/app/IncomingCallWindowLeaseStore.kt',
  );
  final notificationServiceFile = File(
    '$repoRoot/lib/notifications/notification_service.dart',
  );
  final incomingCallLeaseDartFile = File(
    '$repoRoot/lib/notifications/incoming_call_window_lease.dart',
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
    final leaseStore = await incomingCallLeaseStoreFile.readAsString();
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
    expect(activity, contains('action = intent?.action'));
    expect(leaseStore, contains('SELECT_NOTIFICATION'));
    expect(activity, contains('payload'));
    expect(
      leaseStore,
      contains('INCOMING_CALL_PAYLOAD_NAME = "incoming_call"'),
    );
    expect(leaseStore, contains('INCOMING_CALL_PAYLOAD_PREFIX'));
    expect(leaseStore, contains('MessageDigest.isEqual'));
    expect(leaseStore, contains('EXPIRES_AT_EPOCH_MS_KEY'));
    expect(activity, contains('IncomingCallWindowLeaseStore.consume'));
    expect(activity, contains('INCOMING_CALL_WINDOW_TOKEN_ARG'));
    expect(activity, contains('activeIncomingCallWindowNonceDigest'));
    expect(
      activity,
      contains('activeNonceDigest = activeIncomingCallWindowNonceDigest'),
    );
    expect(activity, contains('armIncomingCallWindow'));
    expect(activity, contains('commit()'));
    expect(activity, contains('setShowWhenLocked'));
    expect(activity, contains('setTurnScreenOn'));
    expect(notificationService, contains('toxee/incoming_call_window'));
    expect(
      notificationService,
      contains('_incomingCallWindowLeaseStore.issue(callId)'),
    );
    expect(notificationService, contains('IncomingCallWindowLeaseStore'));
    expect(notificationService, contains('_armAndroidIncomingCallWindow'));
    expect(notificationService, contains('armIncomingCallWindow'));
    expect(notificationService, contains('clearIncomingCallWindow'));
    expect(notificationService, contains('stripIncomingCallWindowNonce'));
  });

  test(
    'Android incoming-call lock-screen lease validates digest, binding, and expiry',
    () async {
      final activity = await mainActivityFile.readAsString();
      final leaseStore = await incomingCallLeaseStoreFile.readAsString();
      final dartLease = await incomingCallLeaseDartFile.readAsString();

      expect(activity, contains('java.security.MessageDigest'));
      expect(activity, contains('MessageDigest.getInstance("SHA-256")'));
      expect(activity, contains('MessageDigest.isEqual'));
      expect(activity, contains('activeIncomingCallWindowNonceDigest'));
      expect(leaseStore, contains('NONCE_DIGEST_KEY'));
      expect(leaseStore, contains('CALL_ID_DIGEST_KEY'));
      expect(leaseStore, contains('EXPIRES_AT_EPOCH_MS_KEY'));
      expect(
        leaseStore,
        contains('"flutter.toxee_incoming_call_window_nonce_sha256"'),
      );
      expect(
        leaseStore,
        contains('"flutter.toxee_incoming_call_window_call_id_sha256"'),
      );
      expect(
        leaseStore,
        contains('"flutter.toxee_incoming_call_window_expires_at_epoch_ms"'),
      );
      expect(dartLease, contains("'toxee_incoming_call_window_nonce_sha256'"));
      expect(dartLease, contains("'toxee_incoming_call_window_call_id_sha256'"));
      expect(
        dartLease,
        contains("'toxee_incoming_call_window_expires_at_epoch_ms'"),
      );
      expect(leaseStore, contains('"toxee.incoming-call.v1:"'));
      expect(dartLease, contains("'toxee.incoming-call.v1:\$callId'"));
      expect(
        leaseStore,
        isNot(contains('toxee:incoming-call-window:call:v1')),
      );
      expect(leaseStore, contains('grantAfterClear -> clearAll(storage)'));
      expect(activity, contains('System.currentTimeMillis()'));
      expect(activity, contains('IncomingCallWindowLeaseStore.consume'));
      expect(
        activity,
        isNot(
          contains('.putString(INCOMING_CALL_WINDOW_TOKEN_PREF_KEY, token)'),
        ),
        reason:
            'MainActivity must never overwrite the digest lease with a raw nonce.',
      );
      expect(
        leaseStore,
        contains('allKeys = listOf(LEGACY_RAW_TOKEN_KEY) + leaseKeys'),
        reason:
            'Native storage must remove legacy raw-token residue.',
      );
      expect(
        leaseStore,
        isNot(
          contains('storedNonceDigest = storage.getString(LEGACY_RAW_TOKEN_KEY)'),
        ),
        reason: 'A legacy raw token must never authorize lock-screen access.',
      );
      expect(
        activity,
        isNot(contains('activeIncomingCallWindowToken')),
        reason:
            'The in-memory one-shot value must be a nonce digest, not raw token text.',
      );
    },
  );

  test('Android opts into predictive back for PopScope handlers', () async {
    final manifest = await manifestFile.readAsString();
    expect(manifest, contains('android:enableOnBackInvokedCallback="true"'));
  });
}
