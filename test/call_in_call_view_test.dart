import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/call/in_call_view.dart';
import 'package:toxee/call/in_call_manager.dart';
import 'package:toxee/call/call_audio_platform.dart';
import 'package:toxee/call/camera_availability.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

class FakeInCallManager implements InCallManager {
  @override
  final ValueNotifier<CallAudioState> audioState = ValueNotifier(
    const CallAudioState(),
  );

  @override
  final ValueNotifier<ui.Image?> remoteVideo = ValueNotifier<ui.Image?>(null);

  @override
  final ValueNotifier<int> previewListenable = ValueNotifier<int>(0);

  @override
  Widget? localPreview = const SizedBox(
    key: ValueKey('fake-local-preview'),
    width: 40,
    height: 40,
  );

  @override
  Future<void> toggleMute() async {}

  @override
  Future<void> toggleVideo() async {}
  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> toggleSpeaker() async {}

  @override
  Future<void> hangUp() async {}

  @override
  Future<void> selectAudioRoute(String routeId) async {}
}

Widget buildInCallTestApp(CallStateNotifier callState) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: InCallView(callState: callState, manager: FakeInCallManager()),
  );
}

void main() {
  testWidgets(
    'video in-call view shows top status bar, local preview card, and dock',
    (tester) async {
      final callState = CallStateNotifier()
        ..startRinging(
          mode: CallMode.video,
          direction: CallDirection.outgoing,
          inviteID: 'invite-1',
          remoteUserID: 'alice',
          remoteNickname: 'Alice',
        )
        ..enterCall();
      await tester.pumpWidget(buildInCallTestApp(callState));

      expect(find.byKey(const ValueKey('call-top-bar')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('call-local-preview-card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('call-action-dock')), findsOneWidget);
      expect(find.byKey(UiKeys.callMicMuteButton), findsOneWidget);
      expect(find.byKey(UiKeys.callCameraToggleButton), findsOneWidget);
      expect(find.byKey(UiKeys.callHangupButton), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);

      callState.endCall();
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets(
    'V5: a camera iPadOS paused shows why on the local preview, and clears',
    (tester) async {
      addTearDown(
        () => CameraAvailability.apply(unavailable: false, reason: 0),
      );
      final callState = CallStateNotifier()
        ..startRinging(
          mode: CallMode.video,
          direction: CallDirection.outgoing,
          inviteID: 'invite-2',
          remoteUserID: 'alice',
          remoteNickname: 'Alice',
        )
        ..enterCall();
      await tester.pumpWidget(buildInCallTestApp(callState));
      expect(find.byIcon(Icons.videocam_off_outlined), findsNothing);

      // Split View / Slide Over / Stage Manager took the camera.
      CameraAvailability.apply(unavailable: true, reason: 4);
      await tester.pump();
      expect(
        find.text('Camera paused while other apps share the screen'),
        findsOneWidget,
      );

      // Another app holds it.
      CameraAvailability.apply(unavailable: true, reason: 3);
      await tester.pump();
      expect(find.text('Camera unavailable'), findsOneWidget);

      // Back to full screen.
      CameraAvailability.apply(unavailable: false, reason: 0);
      await tester.pump();
      expect(find.byIcon(Icons.videocam_off_outlined), findsNothing);
      expect(find.byKey(const ValueKey('fake-local-preview')), findsOneWidget);

      callState.endCall();
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('V5: the paused-camera note fits the smallest card at 2x text', (
    tester,
  ) async {
    addTearDown(() => CameraAvailability.apply(unavailable: false, reason: 0));
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.video,
        direction: CallDirection.outgoing,
        inviteID: 'invite-3',
        remoteUserID: 'alice',
        remoteNickname: 'Alice',
      )
      ..enterCall();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: buildInCallTestApp(callState),
      ),
    );
    CameraAvailability.apply(unavailable: true, reason: 4);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.text('Camera paused while other apps share the screen'),
      findsOneWidget,
    );
    callState.endCall();
    await tester.pump(const Duration(seconds: 3));
  });
}
