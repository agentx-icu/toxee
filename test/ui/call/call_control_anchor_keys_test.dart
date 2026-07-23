import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_audio_platform.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/call/in_call_manager.dart';
import 'package:toxee/call/in_call_view.dart';
import 'package:toxee/call/incoming_call_view.dart';
import 'package:toxee/call/outgoing_call_view.dart';
import 'package:toxee/call/ringing_call_manager.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

class _FakeRingingCallManager implements RingingCallManager {
  var acceptCount = 0;
  var rejectCount = 0;
  var hangUpCount = 0;

  @override
  Future<void> acceptCall() async {
    acceptCount += 1;
  }

  @override
  Future<void> rejectCall() async {
    rejectCount += 1;
  }

  @override
  Future<void> hangUp() async {
    hangUpCount += 1;
  }
}

class _FakeInCallManager implements InCallManager {
  var muteCount = 0;
  var videoCount = 0;
  var hangUpCount = 0;

  @override
  final ValueNotifier<CallAudioState> audioState = ValueNotifier(
    const CallAudioState(),
  );

  @override
  Widget? localPreview = const SizedBox(
    key: ValueKey('fake-local-preview'),
    width: 40,
    height: 40,
  );

  @override
  final Listenable previewListenable = ValueNotifier<int>(0);

  @override
  final ValueNotifier<ui.Image?> remoteVideo = ValueNotifier<ui.Image?>(null);

  @override
  Future<void> hangUp() async {
    hangUpCount += 1;
  }

  @override
  Future<void> selectAudioRoute(String routeId) async {}

  @override
  Future<void> toggleMute() async {
    muteCount += 1;
  }

  @override
  Future<void> toggleSpeaker() async {}

  @override
  Future<void> toggleVideo() async {
    videoCount += 1;
  }

  @override
  Future<void> switchCamera() async {}
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('incoming call controls expose accept and decline anchors', (
    tester,
  ) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.audio,
        direction: CallDirection.incoming,
        inviteID: 'invite-incoming',
        remoteUserID: 'alice',
        remoteNickname: 'Alice',
      );
    final manager = _FakeRingingCallManager();

    await tester.pumpWidget(
      _wrap(IncomingCallView(callState: callState, manager: manager)),
    );

    expect(find.byKey(UiKeys.callAcceptButton), findsOneWidget);
    expect(find.byKey(UiKeys.callDeclineButton), findsOneWidget);

    await tester.tap(find.byKey(UiKeys.callAcceptButton));
    await tester.pump();
    await tester.tap(find.byKey(UiKeys.callDeclineButton));
    await tester.pump();

    expect(manager.acceptCount, 1);
    expect(manager.rejectCount, 1);
  });

  testWidgets('outgoing call control exposes hangup anchor', (tester) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.audio,
        direction: CallDirection.outgoing,
        inviteID: 'invite-outgoing',
        remoteUserID: 'bob',
        remoteNickname: 'Bob',
      );
    final manager = _FakeRingingCallManager();

    await tester.pumpWidget(
      _wrap(OutgoingCallView(callState: callState, manager: manager)),
    );

    expect(find.byKey(UiKeys.callHangupButton), findsOneWidget);

    await tester.tap(find.byKey(UiKeys.callHangupButton));
    await tester.pump();

    expect(manager.hangUpCount, 1);
  });

  testWidgets('audio in-call controls expose mute and hangup anchors', (
    tester,
  ) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.audio,
        direction: CallDirection.outgoing,
        inviteID: 'invite-audio',
        remoteUserID: 'charlie',
        remoteNickname: 'Charlie',
      )
      ..enterCall();
    final manager = _FakeInCallManager();

    await tester.pumpWidget(
      _wrap(InCallView(callState: callState, manager: manager)),
    );

    expect(find.byKey(UiKeys.callMicMuteButton), findsOneWidget);
    expect(find.byKey(UiKeys.callHangupButton), findsOneWidget);
    expect(find.byKey(UiKeys.callCameraToggleButton), findsNothing);

    await tester.tap(find.byKey(UiKeys.callMicMuteButton));
    await tester.pump();
    await tester.tap(find.byKey(UiKeys.callHangupButton));
    await tester.pump();

    expect(manager.muteCount, 1);
    expect(manager.hangUpCount, 1);

    callState.endCall();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('video in-call controls expose camera anchor', (tester) async {
    final callState = CallStateNotifier()
      ..startRinging(
        mode: CallMode.video,
        direction: CallDirection.outgoing,
        inviteID: 'invite-video',
        remoteUserID: 'dana',
        remoteNickname: 'Dana',
      )
      ..enterCall();
    final manager = _FakeInCallManager();

    await tester.pumpWidget(
      _wrap(InCallView(callState: callState, manager: manager)),
    );

    expect(find.byKey(UiKeys.callCameraToggleButton), findsOneWidget);

    await tester.tap(find.byKey(UiKeys.callCameraToggleButton));
    await tester.pump();

    expect(manager.videoCount, 1);

    callState.endCall();
    await tester.pump(const Duration(seconds: 3));
  });
}
