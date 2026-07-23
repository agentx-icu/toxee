import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'call_audio_platform.dart';

/// Minimal interface required by [InCallView]. Allows tests to supply a fake.
///
/// `toggleMute`, `toggleVideo`, and `hangUp` are async (ToxAV FFI / signaling
/// RPCs). Returning `Future<void>` makes that explicit; the previous `void`
/// signatures silently swallowed failures from the underlying calls.
abstract class InCallManager {
  ValueListenable<CallAudioState> get audioState;
  ValueListenable<ui.Image?> get remoteVideo;
  Listenable get previewListenable;
  Widget? get localPreview;
  Future<void> toggleMute();
  Future<void> toggleVideo();
  Future<void> switchCamera();
  Future<void> toggleSpeaker();
  Future<void> hangUp();
  Future<void> selectAudioRoute(String routeId);
}
