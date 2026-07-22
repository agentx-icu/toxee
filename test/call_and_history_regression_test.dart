import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations_en.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/i18n/app_localizations_zh.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:toxee/call/permission_helper.dart';
import 'package:toxee/call/call_overlay.dart';
import 'package:toxee/call/call_overlay_manager.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/call/call_audio_platform.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';

/// Fake [CallOverlayManager] for overlay tests (no real SDK).
class FakeCallOverlayManager implements CallOverlayManager {
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
    key: ValueKey('fake-overlay-preview'),
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
  @override
  Future<void> acceptCall() async {}
  @override
  Future<void> rejectCall() async {}
}

Widget buildCallOverlayTestApp(CallStateNotifier callState) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: CallOverlay(
      callState: callState,
      manager: FakeCallOverlayManager(),
      child: const SizedBox.expand(),
    ),
  );
}

void main() {
  group('Call overlay redesigned surfaces', () {
    testWidgets(
      'overlay shows full-screen dock then floating card after minimize',
      (tester) async {
        final callState = CallStateNotifier()
          ..startRinging(
            mode: CallMode.video,
            direction: CallDirection.outgoing,
            inviteID: 'ov-1',
            remoteUserID: 'bob',
            remoteNickname: 'Bob',
          )
          ..enterCall();
        await tester.pumpWidget(buildCallOverlayTestApp(callState));

        expect(find.byKey(const ValueKey('call-action-dock')), findsOneWidget);

        callState.minimize();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('floating-call-card')),
          findsOneWidget,
        );

        callState.endCall();
        await tester.pump(const Duration(seconds: 3));
      },
    );
  });

  group('FakeMessageManager latest-window slicing', () {
    test('returns newest N items from ascending list', () {
      final input = <int>[1, 2, 3, 4, 5];

      expect(FakeMessageManager.takeLatestWindow(input, 2), <int>[4, 5]);
      expect(FakeMessageManager.takeLatestWindow(input, 5), <int>[
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(FakeMessageManager.takeLatestWindow(input, 10), <int>[
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(FakeMessageManager.takeLatestWindow(input, 0), <int>[
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(FakeMessageManager.takeLatestWindow(input, -1), <int>[
        1,
        2,
        3,
        4,
        5,
      ]);
    });
  });

  group('CallPermissionHelper platform policy', () {
    test('does not request runtime permission on macOS/linux', () {
      expect(
        CallPermissionHelper.shouldRequestRuntimePermission(
          platform: TargetPlatform.macOS,
        ),
        isFalse,
      );
      expect(
        CallPermissionHelper.shouldRequestRuntimePermission(
          platform: TargetPlatform.linux,
        ),
        isFalse,
      );
    });

    test('still requests runtime permission on iOS/android/windows', () {
      expect(
        CallPermissionHelper.shouldRequestRuntimePermission(
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
      expect(
        CallPermissionHelper.shouldRequestRuntimePermission(
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        CallPermissionHelper.shouldRequestRuntimePermission(
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
    });

    test('localizes denied call permission messages', () {
      final result = CallPermissionHelper.evaluatePermissionResult(
        isVideo: true,
        microphoneStatus: PermissionStatus.granted,
        cameraStatus: PermissionStatus.permanentlyDenied,
      );

      expect(result.granted, isFalse);
      expect(result.requiresSettings, isTrue);
      expect(result.missingPermissions, contains(CallPermission.camera));
      expect(
        CallPermissionHelper.describeDeniedPermissionResult(
          result,
          AppLocalizationsEn(),
        ),
        'Camera permission is required to continue the call.',
      );
      expect(
        CallPermissionHelper.describeDeniedPermissionResult(
          result,
          AppLocalizationsZhHans(),
        ),
        '继续通话需要相机权限。',
      );
    });
  });
}
