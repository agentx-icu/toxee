import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../i18n/app_localizations.dart';

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
    final requiresSettings = microphoneStatus.isPermanentlyDenied ||
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
    final needsMicrophone =
        result.missingPermissions.contains(CallPermission.microphone);
    final needsCamera =
        result.missingPermissions.contains(CallPermission.camera);
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
      final micStatus = await Permission.microphone.request();
      PermissionStatus? camStatus;
      if (isVideo) {
        camStatus = await Permission.camera.request();
      }

      return evaluatePermissionResult(
        isVideo: isVideo,
        microphoneStatus: micStatus,
        cameraStatus: camStatus,
      );
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

  static Future<void> prewarmCallPermissions() async {
    if (!shouldRequestRuntimePermission()) return;
    try {
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted &&
          !micStatus.isPermanentlyDenied &&
          !micStatus.isRestricted) {
        await Permission.microphone.request();
      }

      final camStatus = await Permission.camera.status;
      if (!camStatus.isGranted &&
          !camStatus.isPermanentlyDenied &&
          !camStatus.isRestricted) {
        await Permission.camera.request();
      }
    } on MissingPluginException {
      // Some desktop/test builds may not register permission_handler plugins.
    }
  }
}
