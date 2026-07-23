import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_audio_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses audio route state from native payload', () {
    final state = CallAudioState.fromMap({
      'sessionActive': true,
      'selectedRouteId': 'speaker',
      'routes': [
        {
          'id': 'earpiece',
          'kind': 'earpiece',
          'label': 'Earpiece',
          'selected': false,
        },
        {
          'id': 'speaker',
          'kind': 'speaker',
          'label': 'Speaker',
          'selected': true,
        },
      ],
    });

    expect(state.sessionActive, isTrue);
    expect(state.selectedRouteId, 'speaker');
    expect(state.routes, hasLength(2));
    expect(state.selectedRoute?.kind, CallAudioRouteKind.speaker);
    expect(state.canSelectRoutes, isTrue);
  });

  test('parses ducking as distinct from full focus loss', () {
    expect(
      CallAudioEvent.fromMap({'type': 'focusDucked'}).kind,
      CallAudioEventKind.focusDucked,
    );
    expect(
      CallAudioEvent.fromMap({'type': 'focusLost'}).kind,
      CallAudioEventKind.focusLost,
    );
  });

  test('parses interruption shouldResume flag from native payload', () {
    expect(
      CallAudioEvent.fromMap({
        'type': 'interruptionEnded',
        'shouldResume': false,
      }).shouldResume,
      isFalse,
    );
    expect(
      CallAudioEvent.fromMap({
        'type': 'interruptionEnded',
        'shouldResume': true,
      }).shouldResume,
      isTrue,
    );
  });

  test('interruptionEnded with shouldResume=false does not resume media', () {
    final event = CallAudioEvent.fromMap({
      'type': 'interruptionEnded',
      'shouldResume': false,
    });

    expect(
      shouldResumeInterruptedCallMedia(event: event, hasActiveMediaCall: true),
      isFalse,
    );
  });

  test('proximity is enabled only for an active voice call on earpiece', () {
    expect(
      shouldEnableCallProximity(
        isActiveMediaCall: true,
        isVideoCall: false,
        selectedRouteKind: CallAudioRouteKind.earpiece,
      ),
      isTrue,
    );
    for (final scenario
        in <({bool active, bool video, CallAudioRouteKind route})>[
          (active: false, video: false, route: CallAudioRouteKind.earpiece),
          (active: true, video: true, route: CallAudioRouteKind.earpiece),
          (active: true, video: false, route: CallAudioRouteKind.speaker),
          (active: true, video: false, route: CallAudioRouteKind.bluetooth),
          (active: true, video: false, route: CallAudioRouteKind.wired),
        ]) {
      expect(
        shouldEnableCallProximity(
          isActiveMediaCall: scenario.active,
          isVideoCall: scenario.video,
          selectedRouteKind: scenario.route,
        ),
        isFalse,
        reason: '$scenario',
      );
    }
  });

  test('setProximityMonitoring forwards the requested native state', () async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = originalPlatform);

    const channel = MethodChannel('toxee/call_audio_proximity_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final platform = CallAudioPlatform(methodChannel: channel);
    await platform.setProximityMonitoring(true);
    await platform.setProximityMonitoring(false);

    expect(calls.map((call) => call.method), [
      'setProximityMonitoring',
      'setProximityMonitoring',
    ]);
    expect(calls.first.arguments, containsPair('enabled', true));
    expect(calls.last.arguments, containsPair('enabled', false));
    await platform.dispose();
  });
}
