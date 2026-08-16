part of 'call_service_manager.dart';

// Pure decision predicates used by [CallServiceManager].
//
// Split out of `call_service_manager.dart` along a real seam: every function
// here is a total function of its arguments with no reference to the manager's
// state, its platform channels, or its streams — which is exactly why they are
// `@visibleForTesting` and unit-tested directly. Keeping them in the manager
// file only made an already-baselined file longer without making either half
// easier to read.

/// Whether the foreground service must declare CAMERA use for this call.
///
/// All four conditions are required: Android rejects a `camera` foreground
/// service type when nothing is actually capturing, and declaring it for an
/// audio call would ask the user for a capability the call never uses.
@visibleForTesting
bool callForegroundUsesCamera({
  required CallMode mode,
  required bool isVideoEnabled,
  required bool supportsVideoCapture,
  required bool isVideoCapturing,
}) {
  return mode == CallMode.video &&
      isVideoEnabled &&
      supportsVideoCapture &&
      isVideoCapturing;
}

/// Whether to tell the user that the incoming-call notification degraded.
///
/// Both fallbacks are user-visible degradations (the call rings in-app only, or
/// not at all), so both earn a notice; a fully successful post does not.
@visibleForTesting
bool shouldShowIncomingCallNotificationFallbackNotice(
  IncomingCallNotificationOutcome outcome,
) {
  return outcome == IncomingCallNotificationOutcome.inAppOnlyFallback ||
      outcome == IncomingCallNotificationOutcome.failedFallback;
}

/// Whether that notice should offer a jump to system settings.
///
/// Only the in-app-only fallback is fixable by the user (it means notification
/// permission is missing). `failedFallback` is a platform failure that settings
/// cannot repair, so offering the button there would be a dead end.
@visibleForTesting
bool shouldOfferSettingsForIncomingCallNotificationFallback(
  IncomingCallNotificationOutcome outcome,
) {
  return outcome == IncomingCallNotificationOutcome.inAppOnlyFallback;
}
