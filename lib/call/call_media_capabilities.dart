import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../util/logger.dart';

class CallMediaCapabilities {
  const CallMediaCapabilities._();

  /// Direct earpiece/speaker toggle is intentionally `false` everywhere —
  /// the route-selection sheet ([supportsAudioRouteSelection]) covers the
  /// same need on platforms that support it, and on platforms that don't
  /// (macOS, Linux, Windows) the OS owns the route. Adding a "speaker"
  /// button that secretly only flips a Dart-side flag would be a worse
  /// experience than the current visible-but-disabled route picker with a
  /// tooltip ("Audio route managed by system on this platform"). See
  /// `in_call_view.dart`'s build of the route action for the rendering
  /// path.
  static bool supportsSpeakerToggle({TargetPlatform? platform}) => false;

  static bool supportsAudioRouteSelection({TargetPlatform? platform}) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return effectivePlatform == TargetPlatform.android ||
        effectivePlatform == TargetPlatform.iOS;
  }

  /// Whether camera CAPTURE has a working backend on this platform.
  /// Android/iOS use `package:camera`, macOS uses `camera_macos`; Windows and
  /// Linux have NO camera plugin implementation, so a "video call" there
  /// silently sends no frames (VideoHandler catches MissingPluginException).
  /// Video-call entry points and the in-call camera toggle must gate on this
  /// so users aren't offered a control that can't work. Receiving/rendering
  /// remote video works everywhere and is deliberately NOT gated by this.
  static bool supportsVideoCapture({TargetPlatform? platform}) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    final platformHasBackend =
        effectivePlatform == TargetPlatform.android ||
        effectivePlatform == TargetPlatform.iOS ||
        effectivePlatform == TargetPlatform.macOS;
    // A backend is necessary but not sufficient: the DEVICE must actually have
    // a capture device. See [refreshCaptureDevices] for why this matters.
    return platformHasBackend && (_effectiveDeviceHasCamera ?? true);
  }

  /// `null` until [refreshCaptureDevices] has produced an answer, or when the
  /// enumeration is not available on this platform. `null` means "assume the
  /// platform default", so every previously-supported platform keeps its old
  /// behaviour unless we positively learn there is no camera.
  static bool? _deviceHasCamera;

  /// The IN-FLIGHT enumeration, so concurrent callers share ONE probe and
  /// [ensureCaptureDevicesKnown] can await the startup one instead of racing it.
  /// Cleared when the probe completes — it is not a result cache (see
  /// [refreshCaptureDevices]).
  static Future<void>? _enumeration;

  /// When the last enumeration COMPLETED. Rate-limits re-probing so a burst of
  /// call-setup calls does not enumerate once per call.
  static DateTime? _lastProbeAt;

  /// How long a NEGATIVE or inconclusive answer is reused before the next
  /// caller re-probes. Short enough that "I closed the other app / granted the
  /// MDM exception" is recoverable within a session, long enough that the
  /// several `ensureCaptureDevicesKnown()` calls one call setup makes share one
  /// enumeration.
  static const Duration _negativeAnswerTtl = Duration(seconds: 5);

  /// Test injection. Takes precedence over anything an enumeration learns, so a
  /// probe that lands later cannot clobber it (the previous implementation only
  /// nulled `_enumeration`, which left exactly that race open).
  static bool? _debugDeviceHasCameraOverride;

  static bool? get _effectiveDeviceHasCamera =>
      _debugDeviceHasCameraOverride ?? _deviceHasCamera;

  @visibleForTesting
  static set debugDeviceHasCamera(bool? value) {
    _debugDeviceHasCameraOverride = value;
    _deviceHasCamera = value;
    // Drop any cached probe state so the next test starts clean.
    _enumeration = null;
    _lastProbeAt = null;
  }

  /// Learn whether this DEVICE has any camera, and cache it.
  ///
  /// WHY (measured 2026-08-15 on an iOS Simulator): `supportsVideoCapture` was
  /// platform-only, so iOS always claimed camera capture. Starting a video call
  /// therefore ran `requestPermissionsForCallDetailed(isVideo: true)`, which
  /// raised the system camera sheet on a device that HAS no camera and where
  /// nothing can ever answer it (`xcrun simctl privacy` has no `camera`
  /// service). The modal then covered the app for the rest of the session:
  /// every later tap missed, and unrelated VOICE-call cases failed with "the
  /// call never rang". The same trap exists on real hardware whose camera is
  /// absent or MDM-restricted.
  ///
  /// Enumerating capture devices does NOT itself require permission on iOS or
  /// Android, so this is safe to call at startup. When the enumeration is
  /// unavailable (macOS uses the separate `camera_macos` backend and throws
  /// `MissingPluginException` here) the answer stays `null` and behaviour is
  /// unchanged. Camera-less devices then follow the SAME receive-only video
  /// path Windows/Linux already take.
  /// On iOS specifically, "no cameras" comes back as an EMPTY LIST, not an
  /// exception: `camera_avfoundation`'s `availableCameras()` builds its reply
  /// from an `AVCaptureDevice.DiscoverySession` and only converts a
  /// `PlatformException` (a channel-level failure) into a `CameraException`
  /// (avfoundation_camera.dart:68-76). So a Simulator returns `[]` and this
  /// probe reaches the `false` answer it needs to. The catch below is for the
  /// genuinely inconclusive cases (no plugin implementation, channel error),
  /// where staying `null` preserves the old per-platform behaviour.
  /// IT REALLY REFRESHES. The previous implementation returned the cached
  /// `_enumeration` future forever once the first probe had run, so the method
  /// named "refresh" could never revisit its answer — and a single `[]` from
  /// `availableCameras()` disabled video calling for the WHOLE process.
  ///
  /// That is not hypothetical on real hardware: the enumeration is fired
  /// unawaited at bootstrap (`lib/bootstrap/app_bootstrap.dart:55`), and it can
  /// come back empty because another app holds the camera, because an MDM
  /// profile restricts it, or because the Android plugin has not finished
  /// registering. The `?? true` default in [supportsVideoCapture] only covers
  /// the INCONCLUSIVE case (the probe threw); it cannot rescue a wrong `false`.
  /// The user then sees no video-call entry at all, with
  /// `callVideoUnsupportedPlatform` as the only clue, until they restart.
  ///
  /// Caching rule:
  ///  * a POSITIVE answer is kept — a device that has a camera keeps having one,
  ///    and "the camera is busy right now" is the capture/permission layer's
  ///    problem, not this predicate's;
  ///  * a NEGATIVE or inconclusive answer is reused for [_negativeAnswerTtl] and
  ///    then re-probed by the next caller, so the outage is recoverable in-session;
  ///  * a concurrent caller always joins the IN-FLIGHT probe rather than
  ///    starting a second one.
  static Future<void> refreshCaptureDevices() {
    // A test-injected answer is authoritative; never enumerate over it.
    if (_debugDeviceHasCameraOverride != null) return Future<void>.value();
    final inFlight = _enumeration;
    if (inFlight != null) return inFlight;
    if (!_shouldReprobe) return Future<void>.value();
    final started = _refreshCaptureDevices();
    _enumeration = started;
    return started;
  }

  static bool get _shouldReprobe {
    if (_deviceHasCamera == true) return false;
    final last = _lastProbeAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _negativeAnswerTtl;
  }

  /// Await the capture-device answer before acting on it.
  ///
  /// [refreshCaptureDevices] is kicked off UNAWAITED at startup so a slow or
  /// hanging plugin cannot block app launch. That leaves a window in which
  /// `supportsVideoCapture()` still returns the platform default, which on iOS
  /// means "yes, there is a camera" — i.e. a video call started early would
  /// raise exactly the unanswerable permission sheet this class exists to
  /// prevent. Every path that is about to REQUEST camera permission awaits this
  /// first, which either joins the in-flight startup probe, reuses a recent
  /// answer, or starts a new one — see [refreshCaptureDevices]'s caching rule.
  static Future<void> ensureCaptureDevicesKnown() => refreshCaptureDevices();

  static Future<void> _refreshCaptureDevices() async {
    try {
      final cameras = await availableCameras();
      _deviceHasCamera = cameras.isNotEmpty;
      // Logged on BOTH outcomes: "did the probe conclude, and what did it
      // conclude" is the first question when a camera sheet appears anyway.
      AppLogger.log(
        '[CallMediaCapabilities] capture devices enumerated: '
        'count=${cameras.length} deviceHasCamera=$_deviceHasCamera',
      );
    } catch (e) {
      // MissingPluginException (macOS/desktop), CameraException, anything else:
      // do not downgrade a platform on an inconclusive probe.
      _deviceHasCamera = null;
      AppLogger.log(
        '[CallMediaCapabilities] camera enumeration unavailable: $e',
      );
    } finally {
      // Release the in-flight slot and start the negative-answer TTL. Without
      // this the very first probe's future stayed cached forever and a wrong
      // `false` was permanent for the process.
      _lastProbeAt = DateTime.now();
      _enumeration = null;
    }
  }

  /// Whether the active capture backend supports changing cameras in-call.
  ///
  /// Android and iOS use `package:camera`, whose device descriptions can be
  /// selected when capture restarts. macOS uses the separate `camera_macos`
  /// backend and does not currently expose that switch path here.
  static bool supportsCameraSwitch({TargetPlatform? platform}) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return effectivePlatform == TargetPlatform.android ||
        effectivePlatform == TargetPlatform.iOS;
  }

  /// True when this process is an app running inside an iOS Simulator.
  ///
  /// PRIMARY signal is the build-time define `TOXEE_IOS_SIMULATOR`, set by
  /// `run_toxee_ios.sh`'s `build_ios_simulator_app`, which only ever produces
  /// `flutter build ios --simulator` slices (device builds go through
  /// run_toxee_ios_device.sh). Measured 2026-08-16: the Simulator's
  /// `SIMULATOR_UDID` / `SIMULATOR_DEVICE_NAME` are NOT visible through Dart's
  /// `Platform.environment` inside the guest app, so an env-only check silently
  /// returned false and the app kept aborting. The env keys are still consulted
  /// as a secondary signal for builds made by another toolchain path.
  /// Overridable for tests.
  @visibleForTesting
  static bool? debugIsIosSimulator;

  static const bool _iosSimulatorDefine = bool.fromEnvironment(
    'TOXEE_IOS_SIMULATOR',
  );

  static bool get isIosSimulator {
    final forced = debugIsIosSimulator;
    if (forced != null) return forced;
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    if (_iosSimulatorDefine) return true;
    final env = Platform.environment;
    return env.containsKey('SIMULATOR_UDID') ||
        env.containsKey('SIMULATOR_DEVICE_NAME');
  }

  /// Whether MICROPHONE capture can be started without killing the process.
  ///
  /// FALSE on the iOS Simulator. `package:record`'s iOS backend builds an
  /// `AVAudioEngine` and reads `inputNode`, which runs
  /// `AVAudioEngineImpl::UpdateInputNode -> AURemoteIO::Initialize ->
  /// _ReportRPCTimeout -> abort()`. That is a SIGABRT raised INSIDE
  /// AudioToolbox, so the `try/catch` around `startStream` in
  /// `AudioHandler.startCapture` cannot see it: the whole app dies the instant
  /// a call is answered. Measured 2026-08-16 on an iPad Pro 11-inch simulator
  /// (crash report `Runner-2026-08-16-135639.ips`, faulting thread
  /// `com.apple.main-thread`), where every `sweep_calls_misc` case after the
  /// accept died with "VM service connection refused".
  ///
  /// A camera-less platform already takes a receive-only VIDEO path
  /// ([supportsVideoCapture]); this is the audio twin of that rule. Remote
  /// audio still renders, the call still connects, mute/hang-up still work —
  /// only the local microphone stream is skipped, and only on a Simulator.
  /// Real iOS hardware is unaffected (neither env var is set there).
  static bool supportsAudioCapture() => !isIosSimulator;

  /// Whether remote PCM can be handed to the playback engine without killing
  /// the process.
  ///
  /// FALSE on the iOS Simulator for the same class of reason as
  /// [supportsAudioCapture], but a DIFFERENT stack: `flutter_pcm_sound`'s
  /// `AudioQueue` converter chain raises SIGILL on the `AudioControl` thread
  /// inside `AudioConverterNewInternal` (crash report
  /// `Runner-2026-08-16-143603.ips`), which killed the app moments AFTER the
  /// four voice-call cases had passed and failed the rest of the sweep with
  /// "VM service connection refused". Kept as its own predicate so a future
  /// platform that can record but not play (or vice versa) is expressible.
  static bool supportsAudioPlayback() => !isIosSimulator;
}
