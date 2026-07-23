class CallCameraSwitchController {
  Future<void>? _inFlight;

  /// Runs at most one camera-switch transaction at a time.
  ///
  /// [prepareSwitch] may perform non-destructive asynchronous work such as
  /// refreshing the camera list. [canSwitch] is checked before preparation,
  /// again before the destructive transaction starts, and is also passed to
  /// [performSwitch] so callers can revalidate after asynchronous teardown.
  Future<void> switchCamera({
    required bool Function() canSwitch,
    required Future<void> Function() prepareSwitch,
    required Future<void> Function(bool Function() canRestart) performSwitch,
  }) {
    final pending = _inFlight;
    if (pending != null) return pending;
    if (!canSwitch()) return Future<void>.value();

    final operation = Future<void>.sync(() async {
      await prepareSwitch();
      if (!canSwitch()) return;
      await performSwitch(canSwitch);
    });
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_inFlight, tracked)) _inFlight = null;
    });
    _inFlight = tracked;
    return tracked;
  }
}
