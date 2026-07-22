import 'package:flutter/foundation.dart';

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
    return effectivePlatform == TargetPlatform.android ||
        effectivePlatform == TargetPlatform.iOS ||
        effectivePlatform == TargetPlatform.macOS;
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
}
