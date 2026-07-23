import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final channelFile = File(
    '$repoRoot/android/app/src/main/kotlin/com/toxee/app/CallAudioChannel.kt',
  );

  Future<String> source() async {
    expect(
      channelFile.existsSync(),
      isTrue,
      reason: 'Android call audio channel moved; update this regression test.',
    );
    return channelFile.readAsString();
  }

  test(
    'Android call audio defaults do not persist as explicit route choices',
    () async {
      final src = await source();

      expect(
        src,
        isNot(contains('preferredRouteId = if (preferSpeaker)')),
        reason:
            'preferSpeaker is a per-state default. Persisting it as '
            'preferredRouteId leaves accepted audio calls on speaker after the '
            'ringing state and leaks route choice into the next call.',
      );
      expect(
        src,
        contains('applyPreferredRoute(preferSpeaker)'),
        reason:
            'activateSession should apply the current call-state default whenever '
            'the user has not selected an explicit route.',
      );
      expect(
        src,
        contains('preferredRouteId = null'),
        reason:
            'Explicit route choices are per-call; deactivation must clear them so '
            'the next call starts from its audio/video default.',
      );
    },
  );

  test(
    'Android speaker route exits Bluetooth SCO on pre-Android 12 devices',
    () async {
      final src = await source();
      final routeToSpeaker = RegExp(
        r'private fun routeToSpeaker\(\) \{([\s\S]*?)\n    \}',
      ).firstMatch(src)?.group(1);

      expect(routeToSpeaker, isNotNull);
      expect(
        routeToSpeaker,
        contains('stopBluetoothScoIfActive()'),
        reason:
            'Selecting speaker after a Bluetooth route must leave SCO mode, '
            'otherwise pre-S Android can keep audio on the old headset route.',
      );
      expect(src, contains('audioManager.stopBluetoothSco()'));
    },
  );

  test(
    'Android proximity wake lock is released on every teardown path',
    () async {
      final src = await source();

      expect(src, contains('PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK'));
      expect(src, contains('"setProximityMonitoring"'));
      expect(src, contains('setProximityMonitoring(false)'));
      expect(src, contains('PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY'));
    },
  );

  test('Android duckable focus loss is not a full media interruption', () async {
    final src = await source();

    expect(
      src,
      contains(
        'AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "focusDucked"',
      ),
      reason:
          'Duckable focus loss should not stop microphone/camera capture; Dart '
          'treats focusLost as a hard media interruption.',
    );
    expect(
      src,
      isNot(
        contains(
          'AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,\n                -> "focusLost"',
        ),
      ),
    );
  });
}
