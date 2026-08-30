// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Camera-SWITCH leg of the calls_misc video block. Split from
// …_calls_misc_video.dart (at its LOC gate) along the mention2 precedent:
// same library, same helpers, one cohesive leg.

/// call_camera_switch_incall — the camera-SWITCH affordance on the SAME live
/// video call the block already established.
///
/// DESKTOP contract: `CallMediaCapabilities.supportsCameraSwitch()` is
/// Android/iOS-only, so the in-call dock must NOT render
/// `call_camera_switch_button` — the ABSENCE is the assertion there.
/// MOBILE contract: the button renders (video enabled), a REAL tap runs the
/// switch transaction (stop capture → select the opposite lens → restart:
/// VideoHandler.switchCamera), and the l3 `call.cameraLens` seam flips while
/// the call stays inCall with video enabled. With <2 enumerated cameras the
/// transaction is a product no-op (`performSwitch` returns before stopping
/// capture) — an honest SKIP (null). Anti-vacuous: a live video call must
/// already report an active lens before the tap.
Future<bool?> _cameraSwitchLeg(Inst a) async {
  const label = 'call_camera_switch_incall';
  Future<Map<dynamic, dynamic>> callMap() async =>
      ((await a.dumpState())['call'] as Map?) ?? const {};
  if (!a.isAndroid && !a.isIos) {
    final absent = !await a.waitKey(
      'call_camera_switch_button',
      timeoutSecs: 3,
    );
    // Codex High: absence alone would also pass on a DROPPED call — require
    // the live-video precondition the contract is about.
    final alive =
        await _callState(a) == 'inCall' &&
        await _callField(a, 'isVideoEnabled') == true;
    print('[pair] $label: desktop switch-button absent=$absent alive=$alive');
    return absent && alive;
  }
  // Capture-ready wait (codex Medium): isVideoEnabled flips BEFORE the
  // restart finishes, and the lens seam is LIVENESS-gated (null until the
  // controller is initialized) — poll it up first.
  Map<dynamic, dynamic> before = const {};
  String? lensBefore;
  for (var i = 0; i < 24 && (lensBefore == null || lensBefore.isEmpty); i++) {
    before = await callMap();
    lensBefore = before['cameraLens']?.toString();
    if (lensBefore == null || lensBefore.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  final nameBefore = before['cameraName']?.toString();
  final count = before['cameraCount'];
  if (lensBefore == null || lensBefore.isEmpty) {
    print('[pair] $label: capture never became live (call=$before)');
    return false;
  }
  if (count is! int || count < 2) {
    print(
      '[pair] $label: SKIP — cameraCount=$count; the switch transaction is '
      'a product no-op below 2 devices',
    );
    return null;
  }
  if (!await a.tapKeyCenter('call_camera_switch_button', timeoutSecs: 8)) {
    print('[pair] $label: switch button not tappable');
    return false;
  }
  // The transaction stops + restarts capture — poll THROUGH it. Primary
  // assert: the unique camera NAME changes (codex Medium: two same-direction
  // devices keep an equal lens name); the lens flip is reported alongside.
  String? lensAfter;
  String? nameAfter;
  for (var i = 0; i < 24; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final now = await callMap();
    lensAfter = now['cameraLens']?.toString();
    nameAfter = now['cameraName']?.toString();
    if (nameAfter != null && nameAfter.isNotEmpty && nameAfter != nameBefore) {
      break;
    }
  }
  final switched =
      nameAfter != null && nameAfter.isNotEmpty && nameAfter != nameBefore;
  final alive =
      await _callState(a) == 'inCall' &&
      await _callField(a, 'isVideoEnabled') == true;
  await a.shot('/tmp/ui_b8_camswitch_A.png');
  print(
    '[pair] $label: camera "$nameBefore" -> "$nameAfter" switched=$switched '
    'lens $lensBefore -> $lensAfter alive=$alive',
  );
  return switched && alive;
}
