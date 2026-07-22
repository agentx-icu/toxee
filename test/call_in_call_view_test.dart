import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/call/in_call_view.dart';
import 'package:toxee/call/in_call_manager.dart';
import 'package:toxee/call/call_audio_platform.dart';
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
}
