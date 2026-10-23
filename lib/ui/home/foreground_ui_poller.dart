import 'dart:async';

import 'package:flutter/widgets.dart';

/// Polls visible UI state without owning the service being observed.
///
/// A visible but unfocused desktop window still needs its status. Hidden,
/// paused and detached windows do not. An already running read can finish;
/// subsequent ticks never overlap it. Returning to a visible window requests
/// one fresh read, including when the previous read is still completing.
final class ForegroundUiPoller with WidgetsBindingObserver {
  ForegroundUiPoller({
    required this.read,
    required this.onError,
    this.interval = const Duration(seconds: 2),
  });

  final Future<void> Function() read;
  final void Function(Object error, StackTrace stack) onError;
  final Duration interval;
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  bool _visible = false;
  bool _reading = false;
  bool _refreshAfterRead = false;

  static bool _isVisible(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  void start() {
    if (_started || _disposed) return;
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'Must be positive');
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _visible = _isVisible(WidgetsBinding.instance.lifecycleState);
    if (_visible) _resume();
  }

  void _resume() {
    _timer = Timer.periodic(interval, (_) => _requestRead());
    _requestRead(refreshAfterCurrent: true);
  }

  void _requestRead({bool refreshAfterCurrent = false}) {
    if (_disposed || !_visible) return;
    if (_reading) {
      _refreshAfterRead |= refreshAfterCurrent;
      return;
    }
    unawaited(_read());
  }

  Future<void> _read() async {
    _reading = true;
    try {
      await read();
    } catch (error, stack) {
      onError(error, stack);
    } finally {
      _reading = false;
      if (_refreshAfterRead) {
        _refreshAfterRead = false;
        _requestRead();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = _isVisible(state);
    if (!_started || _disposed || visible == _visible) return;
    _visible = visible;
    if (visible) {
      _resume();
    } else {
      _timer?.cancel();
      _timer = null;
      _refreshAfterRead = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _refreshAfterRead = false;
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}
