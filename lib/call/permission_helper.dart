import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../i18n/app_localizations.dart';
import '../util/harness_environment.dart';

/// Request microphone and camera permissions before starting calls.
enum CallPermission { microphone, camera }

class CallPermissionResult {
  final bool granted;
  final bool requiresSettings;
  final List<CallPermission> missingPermissions;

  const CallPermissionResult({
    required this.granted,
    required this.requiresSettings,
    required this.missingPermissions,
  });
}

class CallPermissionHelper {
  /// Serialises every OS permission request this class makes.
  ///
  /// `permission_handler` allows exactly ONE in-flight request per process: a
  /// second concurrent `Permission.x.request()` is rejected by the platform
  /// side with `PlatformException(ERROR_ALREADY_REQUESTING_PERMISSIONS)`. That
  /// is reachable from ordinary use — double-tapping the call button issues two
  /// `audioCall`s, and the second one threw straight out of
  /// `CallServiceManager._preflightOutgoingCall`, surfacing as
  /// `CallSetupFailureReason.internalError` ("the call never rang") instead of
  /// a permission outcome. Queueing here makes the second caller wait for and
  /// then observe the first request's result, which is what it wanted anyway.
  static Future<void> _gate = Future<void>.value();

  static Future<T> _serialised<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _gate = _gate.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Request [permission], degrading a plumbing failure to a STATUS rather than
  /// letting it escape.
  ///
  /// A `PlatformException` from the permission channel is not a call-setup
  /// fault: propagating it made every caller report `internalError` and show
  /// the generic "signalling failed" notice for what is really "we could not
  /// obtain the permission". Fall back to the last known status so the caller
  /// takes its normal denied path (notice + Settings action).
  /// How long to wait for the OS to answer one permission request before
  /// giving up on it.
  ///
  /// Not a UX deadline — it is the release valve for the serialisation gate.
  /// An unanswered system sheet never completes its callback, and because
  /// `permission_handler` is single-flight process-wide that would wedge
  /// [_gate] forever, so a LATER voice call could never even ask for the
  /// microphone. Timing out reports "not granted" (the caller then shows its
  /// permission notice) and, crucially, lets the queue drain. A user who
  /// answers the sheet afterwards is picked up by the next status read.
  static const Duration _requestTimeout = Duration(seconds: 45);

  static Future<PermissionStatus> _requestSafely(Permission permission) async {
    try {
      return await permission.request().timeout(_requestTimeout);
    } on TimeoutException {
      debugPrint(
        '[CallPermissionHelper] request for $permission timed out '
        '(system sheet unanswered)',
      );
      try {
        return await permission.status;
      } on PlatformException {
        return PermissionStatus.denied;
      }
    } on MissingPluginException {
      rethrow;
    } on PlatformException catch (e) {
      debugPrint(
        '[CallPermissionHelper] request failed for $permission: ${e.code}',
      );
      try {
        return await permission.status;
      } on PlatformException {
        return PermissionStatus.denied;
      }
    }
  }

  /// TEST-ONLY (kDebugMode): when set, [requestPermissionsForCallDetailed]
  /// returns this result instead of asking the OS. Lets a real-UI test drive the
  /// genuine call permission-denied UI (the `_emitPermissionNotice` SnackBar +
  /// Settings action in call_service_manager) deterministically — the ONLY way to
  /// reach the denial branch on macOS, where `shouldRequestRuntimePermission` is
  /// false so the OS is never asked (and no `tccutil` reset would help). No-op in
  /// release (never set). Gated further behind the test-account l3 tool.
  static CallPermissionResult? debugForcedResult;

  /// Whether runtime permission requests should be attempted on the platform.
  static bool shouldRequestRuntimePermission({TargetPlatform? platform}) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    switch (effectivePlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// Request microphone permission (for audio calls).
  ///
  /// Checks current status first to avoid re-prompting when the user has
  /// already granted (no-op fast path) or permanently denied (re-requesting
  /// would silently no-op on iOS / Android 11+, so the caller should send the
  /// user to system settings instead).
  static Future<bool> requestAudioPermission() async {
    if (!shouldRequestRuntimePermission()) return true;
    try {
      final current = await Permission.microphone.status;
      if (current.isGranted) return true;
      if (current.isPermanentlyDenied || current.isRestricted) return false;
      final status = await Permission.microphone.request();
      return status.isGranted;
    } on MissingPluginException {
      // Some desktop builds may not register permission_handler plugins.
      return true;
    }
  }

  /// Request camera permission (for video calls).
  ///
  /// Same status-first pattern as [requestAudioPermission].
  static Future<bool> requestVideoPermission() async {
    if (!shouldRequestRuntimePermission()) return true;
    try {
      final current = await Permission.camera.status;
      if (current.isGranted) return true;
      if (current.isPermanentlyDenied || current.isRestricted) return false;
      final status = await Permission.camera.request();
      return status.isGranted;
    } on MissingPluginException {
      // Some desktop builds may not register permission_handler plugins.
      return true;
    }
  }

  /// Request both microphone and camera (for video calls).
  static Future<bool> requestAllCallPermissions() async {
    if (!shouldRequestRuntimePermission()) return true;
    try {
      final mic = await Permission.microphone.request();
      final cam = await Permission.camera.request();
      return mic.isGranted && cam.isGranted;
    } on MissingPluginException {
      // Some desktop builds may not register permission_handler plugins.
      return true;
    }
  }

  static CallPermissionResult evaluatePermissionResult({
    required bool isVideo,
    required PermissionStatus microphoneStatus,
    PermissionStatus? cameraStatus,
  }) {
    final missingPermissions = <CallPermission>[
      if (!microphoneStatus.isGranted) CallPermission.microphone,
      if (isVideo && cameraStatus != null && !cameraStatus.isGranted)
        CallPermission.camera,
    ];
    final requiresSettings =
        microphoneStatus.isPermanentlyDenied ||
        microphoneStatus.isRestricted ||
        (cameraStatus?.isPermanentlyDenied ?? false) ||
        (cameraStatus?.isRestricted ?? false);

    return CallPermissionResult(
      granted: missingPermissions.isEmpty,
      requiresSettings: requiresSettings,
      missingPermissions: missingPermissions,
    );
  }

  static String describeDeniedPermissionResult(
    CallPermissionResult result,
    AppLocalizations l10n,
  ) {
    final needsMicrophone = result.missingPermissions.contains(
      CallPermission.microphone,
    );
    final needsCamera = result.missingPermissions.contains(
      CallPermission.camera,
    );
    if (needsMicrophone && needsCamera) {
      return l10n.callPermissionMicrophoneCameraRequired;
    }
    if (needsCamera) {
      return l10n.callPermissionCameraRequired;
    }
    if (needsMicrophone) {
      return l10n.callPermissionMicrophoneRequired;
    }
    return l10n.failed;
  }

  static Future<CallPermissionResult> requestPermissionsForCallDetailed({
    required bool isVideo,
  }) async {
    // TEST-ONLY forced result (kDebugMode): drives the real denial UI downstream.
    if (kDebugMode && debugForcedResult != null) {
      return debugForcedResult!;
    }
    if (!shouldRequestRuntimePermission()) {
      return const CallPermissionResult(
        granted: true,
        requiresSettings: false,
        missingPermissions: <CallPermission>[],
      );
    }

    try {
      return await _serialised(() async {
        final micStatus = await _requestSafely(Permission.microphone);
        PermissionStatus? camStatus;
        if (isVideo) {
          camStatus = await _requestSafely(Permission.camera);
        }

        return evaluatePermissionResult(
          isVideo: isVideo,
          microphoneStatus: micStatus,
          cameraStatus: camStatus,
        );
      });
    } on MissingPluginException {
      return const CallPermissionResult(
        granted: true,
        requiresSettings: false,
        missingPermissions: <CallPermission>[],
      );
    }
  }

  static Future<bool> requestPermissionsForCall({required bool isVideo}) async {
    final result = await requestPermissionsForCallDetailed(isVideo: isVideo);
    return result.granted;
  }

  /// Ask for the MICROPHONE early (on Home render) so the first call does not
  /// stall on a permission sheet.
  ///
  /// Deliberately does NOT touch the camera. Requesting camera access before
  /// the user has ever started a video call is both an unexplained prompt and
  /// an availability hazard: `permission_handler` serialises requests
  /// process-wide, so while an unanswered camera sheet is up EVERY later
  /// request — including the microphone request a plain voice call needs —
  /// fails with `ERROR_ALREADY_REQUESTING_PERMISSIONS`. That is exactly how a
  /// voice call died on an iOS Simulator (which can never answer the sheet:
  /// `xcrun simctl privacy` has no `camera` service), and the same wedge exists
  /// on a real device for as long as the user leaves the sheet open. The camera
  /// is requested at the point of use instead, by
  /// [requestPermissionsForCallDetailed] with `isVideo: true`.
  static Future<void> prewarmCallPermissions() async {
    if (!shouldRequestRuntimePermission()) return;
    // Harness opt-out: an OS permission sheet parks above the app where
    // synthetic input cannot dismiss it, and it lands in device-framebuffer
    // captures. Same key family as the notification-prompt suppression; never
    // set in a product build.
    if (HarnessEnvironment.boolValue(
      HarnessEnvironment.disableCallPermissionPrewarmKey,
    )) {
      return;
    }
    try {
      await _serialised(() async {
        final micStatus = await Permission.microphone.status;
        if (!micStatus.isGranted &&
            !micStatus.isPermanentlyDenied &&
            !micStatus.isRestricted) {
          await _requestSafely(Permission.microphone);
        }
      });
    } on MissingPluginException {
      // Some desktop/test builds may not register permission_handler plugins.
    }
  }
}
