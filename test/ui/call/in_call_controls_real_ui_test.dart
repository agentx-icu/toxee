// Real-UI BEHAVIOR coverage for the in-call control dock — UI halves of
// S74 (mic mute/unmute), S75 (camera toggle), S76 (hang up).
//
// The existing `call_control_anchor_keys_test.dart` proves the buttons EXIST
// and that tapping them reaches the injected manager. The gap this file closes
// is the *behavior* half the L3 scenarios assert at the widget layer:
//   - tapping the real mic/camera button flips the dock icon + label + selected
//     state (S74 A1/A3, S75 A1) because the tap dispatches through the
//     production `CallOverlayManager` interface and the new state flows
//     through the real `CallStateNotifier` (the real `CallServiceManager`
//     method bodies — ToxAV mute, signaling — stay on the 2proc
//     `run_fixture_c_call.sh` gates), and
//   - tapping hang-up makes the production overlay reflect call-end (S76 A4) —
//     the real `CallOverlay` swaps `ValueKey('inCall')` → `ValueKey('ended')`.
//
// REAL-UI: we pump the production `CallOverlay` → real `InCallView` → real
// `CallActionDock` driven by the real `CallStateNotifier`, and let the
// production `ListenableBuilder` in `CallOverlay` rebuild on every state flip.
// The only stand-in is the manager: the real production manager is
// `CallServiceManager`, which cannot be constructed in a widget test (it owns
// the ToxAV FFI service, the signaling bridge and native handlers — the very
// pieces the L3 promotion pins to a connected two-process call). Our double
// records the call AND delegates to the SAME `CallStateNotifier` mutators the
// production `CallServiceManager` calls (`toggleMute` → `_callState.toggleMute()`
// at call_service_manager.dart:1139; `toggleVideo` → `:1193`; `hangUp` →
// `_callState.endCall()` at :1124). We never re-implement the icon/label/state
// logic — that lives in the real `InCallView`/`CallStateNotifier` under test.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_audio_platform.dart';
import 'package:toxee/call/call_media_capabilities.dart';
import 'package:toxee/call/call_overlay.dart';
import 'package:toxee/call/call_overlay_manager.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

/// Records control invocations and mirrors what the production
/// [CallServiceManager] does to the shared [CallStateNotifier], so the REAL
/// dock re-renders exactly as it would in the running app. Implements the full
/// [CallOverlayManager] surface so the real [CallOverlay] can render every
/// call-state view (incoming / outgoing / in-call / ended).
class _RecordingCallManager implements CallOverlayManager {
  _RecordingCallManager(this.callState);

  final CallStateNotifier callState;

  var muteCount = 0;
  var videoCount = 0;
  var cameraSwitchCount = 0;
  var speakerCount = 0;
  var hangUpCount = 0;
  var acceptCount = 0;
  var rejectCount = 0;
  var routeCount = 0;

  /// Camera permission gate result for [toggleVideo], mirroring
  /// `CallServiceManager.toggleVideo`'s `requestPermissionsForCallDetailed`
  /// branch (call_service_manager.dart:1179-1191). When false, enabling video
  /// is refused and the state does NOT flip (S75 A5 negative path).
  bool grantCameraPermission = true;

  @override
  final ValueNotifier<CallAudioState> audioState = ValueNotifier(
    const CallAudioState(),
  );

  @override
  final Listenable previewListenable = ValueNotifier<int>(0);

  @override
  final ValueNotifier<ui.Image?> remoteVideo = ValueNotifier<ui.Image?>(null);

  // The PiP preview surfaces only while the camera is on, matching production
  // (the capture pipeline yields a preview widget only while video is enabled).
  @override
  Widget? get localPreview => callState.isVideoEnabled
      ? const SizedBox(
          key: ValueKey('fake-local-preview'),
          width: 40,
          height: 40,
        )
      : null;

  @override
  Future<void> toggleMute() async {
    muteCount += 1;
    // Mirrors CallServiceManager.toggleMute (call_service_manager.dart:1139):
    // flip UI state first, then the (here-omitted) native ToxAV leg.
    callState.toggleMute();
  }

  @override
  Future<void> toggleVideo() async {
    videoCount += 1;
    // Mirrors CallServiceManager.toggleVideo (call_service_manager.dart:1177):
    // enabling video is permission-gated; on denial the state stays put.
    final enableVideo = !callState.isVideoEnabled;
    if (enableVideo && !grantCameraPermission) return;
    callState.toggleVideo();
  }

  @override
  Future<void> switchCamera() async {
    cameraSwitchCount += 1;
  }

  @override
  Future<void> toggleSpeaker() async {
    speakerCount += 1;
    callState.toggleSpeaker();
  }

  @override
  Future<void> hangUp() async {
    hangUpCount += 1;
    // Mirrors CallServiceManager.hangUp (call_service_manager.dart:1124): after
    // the native teardown the call state is ended, which the overlay reflects.
    callState.endCall();
  }

  @override
  Future<void> acceptCall() async {
    acceptCount += 1;
    callState.enterCall();
  }

  @override
  Future<void> rejectCall() async {
    rejectCount += 1;
    callState.endCall();
  }

  @override
  Future<void> selectAudioRoute(String routeId) async {
    routeCount += 1;
  }
}

/// Production rebuild path: the real [CallOverlay] owns the
/// `ListenableBuilder(listenable: callState)`, the call-state view switching,
/// and renders the real [InCallView]. We give it a placeholder [child] (shown
/// only once the call returns to idle) and the real localization delegates the
/// call views read via `AppLocalizations.of(context)`.
Widget _wrapOverlay(
  CallStateNotifier callState,
  _RecordingCallManager manager,
) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: CallOverlay(
      callState: callState,
      manager: manager,
      child: const Scaffold(
        body: Center(child: Text('idle-home', key: ValueKey('idle-home'))),
      ),
    ),
  );
}

/// The icon the production dock button currently RENDERS for [key]. The button
/// attaches its [ValueKey] to the tappable `InkWell` (call_ui_components.dart),
/// and the `Icon(action.icon)` is a descendant of that InkWell — so reading it
/// back asserts what the user actually sees, not a config object.
IconData _renderedIcon(WidgetTester tester, Key key) {
  final icon = tester.widget<Icon>(
    find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
  );
  return icon.icon!;
}

/// The label text the production dock button currently RENDERS for [key]. The
/// label `Text` is a sibling of the keyed InkWell inside the same per-button
/// `Column`, so we resolve it via that shared ancestor.
String _renderedLabel(WidgetTester tester, Key key) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find
          .ancestor(of: find.byKey(key), matching: find.byType(Column))
          .first,
      matching: find.byType(Text),
    ),
  );
  return text.data!;
}

/// Ends the call and pumps past the in-call duration timer and the 2s
/// `CallStateNotifier` ended→idle reset so no timer is left pending when the
/// widget tree is torn down (otherwise the binding asserts on disposal).
Future<void> _drainCall(
  WidgetTester tester,
  CallStateNotifier callState,
) async {
  if (callState.state != CallUIState.ended &&
      callState.state != CallUIState.idle) {
    callState.endCall();
  }
  await tester.pump(); // let the overlay react to the state change
  await tester.pump(const Duration(seconds: 3)); // fire + clear the reset timer
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The hang-up button fires HapticFeedback.lightImpact() via the platform
    // channel; swallow it so the test doesn't depend on a real platform.
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

  CallStateNotifier audioCall() => CallStateNotifier()
    ..startRinging(
      mode: CallMode.audio,
      direction: CallDirection.outgoing,
      inviteID: 'invite-audio',
      remoteUserID: 'charlie',
      remoteNickname: 'Charlie',
    )
    ..enterCall();

  CallStateNotifier videoCall() => CallStateNotifier()
    ..startRinging(
      mode: CallMode.video,
      direction: CallDirection.outgoing,
      inviteID: 'invite-video',
      remoteUserID: 'dana',
      remoteNickname: 'Dana',
    )
    ..enterCall();

  // ---- S74 UI half: mic mute / unmute flips icon + label + selected ----
  testWidgets(
    'S74: tapping mic button drives production mute and flips dock state, '
    'tapping again unmutes',
    (tester) async {
      final callState = audioCall();
      final manager = _RecordingCallManager(callState);
      addTearDown(callState.dispose);

      await tester.pumpWidget(_wrapOverlay(callState, manager));
      await tester.pumpAndSettle();

      // We are genuinely inside the real in-call overlay.
      expect(find.byKey(const ValueKey('inCall')), findsOneWidget);

      // Baseline: not muted → Icons.mic / "Mute" label.
      expect(_renderedIcon(tester, UiKeys.callMicMuteButton), Icons.mic);
      expect(callState.isMuted, isFalse);
      final muteLabel = _renderedLabel(tester, UiKeys.callMicMuteButton);

      // Tap → production toggleMute() runs and the real state notifier flips.
      await tester.tap(find.byKey(UiKeys.callMicMuteButton));
      await tester.pumpAndSettle();

      expect(manager.muteCount, 1);
      expect(callState.isMuted, isTrue);
      expect(
        _renderedIcon(tester, UiKeys.callMicMuteButton),
        Icons.mic_off,
        reason: 'S74 A1: muted shows mic_off',
      );
      final unmuteLabel = _renderedLabel(tester, UiKeys.callMicMuteButton);
      expect(
        unmuteLabel,
        isNot(muteLabel),
        reason: 'S74 A1: label switches Mute → Unmute',
      );

      // Tap again → unmute; state + icon + label revert (S74 A3).
      await tester.tap(find.byKey(UiKeys.callMicMuteButton));
      await tester.pumpAndSettle();

      expect(manager.muteCount, 2);
      expect(callState.isMuted, isFalse);
      expect(
        _renderedIcon(tester, UiKeys.callMicMuteButton),
        Icons.mic,
        reason: 'S74 A3: unmuted shows mic',
      );
      expect(
        _renderedLabel(tester, UiKeys.callMicMuteButton),
        muteLabel,
        reason: 'S74 A3: label back to Mute',
      );

      // S74 A4: the call did not end — still inCall throughout.
      expect(find.byKey(const ValueKey('inCall')), findsOneWidget);

      await _drainCall(tester, callState);
    },
  );

  // ---- S75 UI half: camera toggle in a VIDEO call flips icon + state ----
  testWidgets(
    'S75: tapping camera button drives production video toggle and flips the '
    'dock icon + label',
    (tester) async {
      final callState = videoCall();
      final manager = _RecordingCallManager(callState);
      addTearDown(callState.dispose);

      await tester.pumpWidget(_wrapOverlay(callState, manager));
      await tester.pumpAndSettle();

      // Video call → camera action is present, video on by default.
      expect(find.byKey(UiKeys.callCameraToggleButton), findsOneWidget);
      expect(
        _renderedIcon(tester, UiKeys.callCameraToggleButton),
        Icons.videocam,
      );
      expect(callState.isVideoEnabled, isTrue);
      final videoOffLabel = _renderedLabel(
        tester,
        UiKeys.callCameraToggleButton,
      );

      // Tap → turn video OFF.
      await tester.tap(find.byKey(UiKeys.callCameraToggleButton));
      await tester.pumpAndSettle();

      expect(manager.videoCount, 1);
      expect(callState.isVideoEnabled, isFalse);
      expect(
        _renderedIcon(tester, UiKeys.callCameraToggleButton),
        Icons.videocam_off,
        reason: 'S75 A1: video off shows videocam_off',
      );
      final videoOnLabel = _renderedLabel(
        tester,
        UiKeys.callCameraToggleButton,
      );
      expect(
        videoOnLabel,
        isNot(videoOffLabel),
        reason: 'S75 A1: label switches Video off → Video on',
      );

      // Tap again (permission granted) → video back ON, state + icon revert.
      await tester.tap(find.byKey(UiKeys.callCameraToggleButton));
      await tester.pumpAndSettle();

      expect(manager.videoCount, 2);
      expect(callState.isVideoEnabled, isTrue);
      expect(
        _renderedIcon(tester, UiKeys.callCameraToggleButton),
        Icons.videocam,
        reason: 'S75 A3: re-enabled shows videocam',
      );
      expect(
        _renderedLabel(tester, UiKeys.callCameraToggleButton),
        videoOffLabel,
      );

      await _drainCall(tester, callState);
    },
  );

  testWidgets(
    'video call exposes a camera-switch control that drives the manager',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final callState = videoCall();
      final manager = _RecordingCallManager(callState);
      addTearDown(callState.dispose);

      await tester.pumpWidget(_wrapOverlay(callState, manager));
      await tester.pumpAndSettle();

      final switchButton = find.byIcon(Icons.cameraswitch);
      expect(switchButton, findsOneWidget);

      await tester.tap(switchButton);
      await tester.pumpAndSettle();

      expect(manager.cameraSwitchCount, 1);
      expect(find.byKey(const ValueKey('inCall')), findsOneWidget);

      await _drainCall(tester, callState);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('macOS hides the unsupported camera-switch control', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final callState = videoCall();
    final manager = _RecordingCallManager(callState);
    addTearDown(callState.dispose);

    await tester.pumpWidget(_wrapOverlay(callState, manager));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cameraswitch), findsNothing);

    await _drainCall(tester, callState);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('audio call does not expose a camera-switch control', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final callState = audioCall();
      final manager = _RecordingCallManager(callState);
      addTearDown(callState.dispose);

      await tester.pumpWidget(_wrapOverlay(callState, manager));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cameraswitch), findsNothing);

      await _drainCall(tester, callState);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('video-off state hides the camera-switch control', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final callState = videoCall()..toggleVideo();
      final manager = _RecordingCallManager(callState);
      addTearDown(callState.dispose);

      await tester.pumpWidget(_wrapOverlay(callState, manager));
      await tester.pumpAndSettle();

      expect(callState.isVideoEnabled, isFalse);
      expect(find.byIcon(Icons.cameraswitch), findsNothing);

      await _drainCall(tester, callState);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // ---- S75 A5 negative: camera permission denied → state stays OFF ----
  testWidgets(
    'S75 A5: enabling camera with permission denied leaves video disabled and '
    'dock state unchanged',
    (tester) async {
      final callState = videoCall();
      final manager = _RecordingCallManager(callState);
      addTearDown(callState.dispose);

      await tester.pumpWidget(_wrapOverlay(callState, manager));
      await tester.pumpAndSettle();

      // Turn video OFF first (this path is not permission-gated).
      await tester.tap(find.byKey(UiKeys.callCameraToggleButton));
      await tester.pumpAndSettle();
      expect(callState.isVideoEnabled, isFalse);

      // Deny the camera the next time we try to enable it.
      manager.grantCameraPermission = false;
      await tester.tap(find.byKey(UiKeys.callCameraToggleButton));
      await tester.pumpAndSettle();

      // Production toggleVideo() was invoked, but the permission gate refused —
      // state stays OFF and the dock keeps the videocam_off / selected look.
      expect(manager.videoCount, 2);
      expect(
        callState.isVideoEnabled,
        isFalse,
        reason: 'S75 A5: denied permission keeps video disabled',
      );
      expect(
        _renderedIcon(tester, UiKeys.callCameraToggleButton),
        Icons.videocam_off,
      );

      await _drainCall(tester, callState);
    },
  );

  // ---- S76 UI half: hang-up drives production hangup + overlay reflects end -
  testWidgets(
    'S76: tapping hang-up drives production hangUp and the real overlay '
    'reflects call end',
    (tester) async {
      final callState = audioCall();
      final manager = _RecordingCallManager(callState);
      addTearDown(callState.dispose);

      await tester.pumpWidget(_wrapOverlay(callState, manager));
      await tester.pumpAndSettle();

      // S76 A1: in a connected call — inCall present, no ringing surfaces.
      expect(find.byKey(const ValueKey('inCall')), findsOneWidget);
      expect(find.byKey(const ValueKey('outgoing')), findsNothing);
      expect(find.byKey(const ValueKey('incoming')), findsNothing);

      await tester.tap(find.byKey(UiKeys.callHangupButton));
      await tester.pump(); // process the tap + async hangUp() → endCall()

      // S76 A2/A3: production hangUp ran exactly once and ended the call.
      expect(manager.hangUpCount, 1);
      expect(callState.state, CallUIState.ended);

      // S76 A4: the REAL overlay reflects call end. The overlay cross-fades via
      // an AnimatedSwitcher (220ms in / 150ms out), so advance past the out
      // transition — staying inside the 2s auto-reset window — to let the old
      // `inCall` view leave and the brief `ended` affordance settle in.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('inCall')), findsNothing);
      expect(find.byKey(const ValueKey('ended')), findsOneWidget);
      expect(
        find.text(
          AppLocalizations.of(
            tester.element(find.byKey(const ValueKey('ended'))),
          )!.callEnded,
        ),
        findsOneWidget,
      );

      // After the auto-reset window the overlay collapses back to its child.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ended')), findsNothing);
      expect(
        find.byKey(const ValueKey('idle-home')),
        findsOneWidget,
        reason: 'S76: overlay returns to the underlying app after ended',
      );
    },
  );

  // ---- S74-d: speaker / audio-route affordance is desktop-aware ----
  // toxee has no direct speaker toggle anywhere (supportsSpeakerToggle()==false
  // by design); the route picker stands in for it. The dock's route action is
  // platform-aware, so we drive both real branches of the production
  // `InCallView._buildDockActions` route logic:
  //   - desktop (macOS): the OS owns the route → a *disabled* Icons.route
  //     affordance with a system-route tooltip; tapping it reaches no manager.
  //   - mobile (android): route selection is supported → an *enabled*
  //     Icons.route button that opens the real audio-route sheet.
  testWidgets(
    'S74-d: desktop renders a disabled, system-owned route affordance that '
    'drives no speaker/route call',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      // Precondition for the desktop branch.
      expect(CallMediaCapabilities.supportsSpeakerToggle(), isFalse);
      expect(CallMediaCapabilities.supportsAudioRouteSelection(), isFalse);

      final callState = audioCall();
      final manager = _RecordingCallManager(callState);
      addTearDown(callState.dispose);

      await tester.pumpWidget(_wrapOverlay(callState, manager));
      await tester.pumpAndSettle();

      final routeButton = find.byIcon(Icons.route);
      expect(
        routeButton,
        findsOneWidget,
        reason: 'desktop shows the route affordance',
      );

      // The route affordance's tappable InkWell is wired with onTap: null — it
      // renders disabled (the OS owns the audio route on desktop) and carries
      // the system-route tooltip.
      final routeInkWell = tester.widget<InkWell>(
        find.ancestor(of: routeButton, matching: find.byType(InkWell)).first,
      );
      expect(
        routeInkWell.onTap,
        isNull,
        reason: 'S74-d: route action is disabled on desktop',
      );
      expect(
        find.ancestor(of: routeButton, matching: find.byType(Tooltip)),
        findsOneWidget,
        reason: 'S74-d: disabled route carries an explanatory tooltip',
      );

      // Tapping the disabled affordance must not invoke any route/speaker call.
      await tester.tap(routeButton, warnIfMissed: false);
      await tester.pump();
      expect(manager.routeCount, 0);
      expect(manager.speakerCount, 0);
      expect(find.byKey(const ValueKey('inCall')), findsOneWidget);

      await _drainCall(tester, callState);
      // Reset inside the body: the binding asserts foundation debug vars are
      // unset *before* per-test teardowns run.
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'S74-d: mobile renders an enabled route button that opens the audio-route '
    'sheet',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      // Precondition for the mobile branch.
      expect(CallMediaCapabilities.supportsAudioRouteSelection(), isTrue);

      final callState = audioCall();
      final manager = _RecordingCallManager(callState);
      addTearDown(callState.dispose);
      // The production sheet only opens when more than one route is selectable
      // (CallAudioState.canSelectRoutes). Seed two routes the way the audio
      // platform would, so the real `_showAudioRouteSheet` path runs.
      manager.audioState.value = const CallAudioState(
        routes: [
          CallAudioRoute(
            id: 'earpiece',
            kind: CallAudioRouteKind.earpiece,
            label: 'Phone',
            selected: true,
          ),
          CallAudioRoute(
            id: 'speaker',
            kind: CallAudioRouteKind.speaker,
            label: 'Speaker',
            selected: false,
          ),
        ],
      );

      await tester.pumpWidget(_wrapOverlay(callState, manager));
      await tester.pumpAndSettle();

      final routeButton = find.byIcon(Icons.route);
      expect(
        routeButton,
        findsOneWidget,
        reason: 'mobile shows the route affordance',
      );
      final routeInkWell = tester.widget<InkWell>(
        find.ancestor(of: routeButton, matching: find.byType(InkWell)).first,
      );
      expect(
        routeInkWell.onTap,
        isNotNull,
        reason: 'S74-d: route action is enabled on mobile',
      );

      // Tap → production opens the real audio-route sheet (a modal bottom
      // sheet) listing the routes; confirm it surfaces, then dismiss it.
      await tester.tap(routeButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Speaker'),
        findsOneWidget,
        reason: 'S74-d: enabled route button opens the route sheet',
      );

      // Close the sheet so the call surface is restored for teardown.
      Navigator.of(tester.element(find.text('Speaker'))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inCall')), findsOneWidget);

      await _drainCall(tester, callState);
      // Reset inside the body: the binding asserts foundation debug vars are
      // unset *before* per-test teardowns run.
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
