import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import '../util/logger.dart';
import '../util/platform_utils.dart';
import '../util/serialized_async_tail.dart';

typedef VideoLifecycleAction = Future<void> Function();

/// Whether an ongoing call's camera may run in [state]. Mobile capture needs
/// the app on screen, including inactive without focus (e.g. iPad Split View).
/// Desktop calls also keep capturing while hidden/minimized. Paused/detached
/// suspend capture on every host. Checklist V5/B1.
bool cameraMayRunIn(AppLifecycleState state, {bool? isDesktop}) =>
    state == AppLifecycleState.resumed ||
    state == AppLifecycleState.inactive ||
    ((isDesktop ?? PlatformUtils.isDesktop) &&
        state == AppLifecycleState.hidden);

/// Serializes camera release/restart across app lifecycle transitions.
class CallVideoLifecycleController {
  CallVideoLifecycleController({SerializedTailErrorLogger? logTailError})
    : _tail = SerializedAsyncTail(logError: logTailError ?? _logTailError);

  final SerializedAsyncTail _tail;
  int _generation = 0;
  bool _suspended = false;

  static void _logTailError(Object error, StackTrace stackTrace) {
    AppLogger.logError(
      '[CallVideoLifecycleController] queued lifecycle action failed',
      error,
      stackTrace,
    );
  }

  Future<void> suspend({
    required bool Function() canSuspend,
    required VideoLifecycleAction stopVideo,
  }) {
    final generation = _generation;
    return _enqueue(() async {
      if (generation != _generation || _suspended || !canSuspend()) return;
      _suspended = true;
      await stopVideo();
    });
  }

  Future<void> resume({
    required bool Function() canResume,
    required VideoLifecycleAction startVideo,
  }) {
    final generation = _generation;
    return _enqueue(() async {
      if (generation != _generation || !_suspended) return;
      if (!canResume()) {
        _suspended = false;
        return;
      }
      await startVideo();
      if (generation == _generation) _suspended = false;
    });
  }

  void cancel() {
    _generation++;
    _suspended = false;
  }

  Future<void> _enqueue(VideoLifecycleAction action) {
    return _tail.enqueue(action);
  }
}
