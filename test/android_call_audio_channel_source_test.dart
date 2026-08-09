// WHAT THIS IS: a source-text contract over Kotlin, not a behaviour test.
//
// It asserts on the raw text of `android/app/.../CallAudioChannel.kt`. No
// product Dart runs, so it contributes nothing to coverage, and a rename or a
// reformat of the Kotlin can turn it red without any behaviour changing.
//
// WHY IT IS STILL HERE (2026-08-07 audit): the assertions guard shipped
// *native* code — route persistence, Bluetooth SCO teardown, proximity wake
// locks, duckable focus loss — that a Dart unit test cannot execute at all
// (there is no Kotlin under `flutter test`). The real verification is the
// on-device call scenarios in `tool/mcp_test`; this is the cheap early warning
// that a refactor silently dropped one of those fixes. Sibling greps that only
// looked at harness scripts were moved out to
// `tool/check_source_contracts.py`; these were kept in `test/` because
// `flutter test` is currently their only automated gate.
//
// If you extend this file: prefer adding an instrumented Android test instead.

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
