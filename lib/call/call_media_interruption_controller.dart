import 'dart:async';

import '../util/logger.dart';
import '../util/serialized_async_tail.dart';

typedef MediaLifecycleAction = Future<void> Function();

class CallMediaInterruptionController {
  CallMediaInterruptionController({SerializedTailErrorLogger? logTailError})
    : _tail = SerializedAsyncTail(logError: logTailError ?? _logTailError);

  final SerializedAsyncTail _tail;
  int _generation = 0;
  bool _suspended = false;

  bool get isSuspended => _suspended;

  static void _logTailError(Object error, StackTrace stackTrace) {
    AppLogger.logError(
      '[CallMediaInterruptionController] queued media action failed',
      error,
      stackTrace,
    );
  }

  Future<void> suspend(MediaLifecycleAction suspendMedia) {
    final generation = _generation;
    if (_suspended) return Future<void>.value();
    _suspended = true;
    return _enqueue(() async {
      if (generation != _generation) return;
      await suspendMedia();
    });
  }

  Future<void> resume({
    required bool Function() canResume,
    required MediaLifecycleAction resumeMedia,
  }) {
    final generation = _generation;
    return _enqueue(() async {
      if (generation != _generation || !_suspended) return;
      if (!canResume()) return;
      await resumeMedia();
      if (generation == _generation) _suspended = false;
    });
  }

  void cancel() {
    _generation += 1;
    _suspended = false;
  }

  Future<void> _enqueue(MediaLifecycleAction action) {
    return _tail.enqueue(action);
  }
}
