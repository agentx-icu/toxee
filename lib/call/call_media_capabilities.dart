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
}
