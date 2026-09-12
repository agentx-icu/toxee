import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Serializes async critical sections — read-modify-write pairs that must not
/// interleave — without ever making an idle caller wait on a future created
/// somewhere else.
///
/// WHY THIS IS NOT JUST `_tail = _tail.then(body)`:
///
/// That obvious one-liner chains every call onto a future created by whichever
/// caller ran last, and `Future.then` on an ALREADY-COMPLETED future schedules
/// its callback in *that* future's zone, not the caller's (`_Future._addListener`
/// uses the source future's `_zone`). Inside `testWidgets` the body runs in a
/// `FakeAsync` zone that is driven by `pump`, and a microtask queued in the
/// outer zone does not run until the test returns — so a mutation issued from a
/// widget test chained onto a future created in `setUp` NEVER STARTED while the
/// test was running. It resumed after the test had already failed.
///
/// That is not a test-only wart: it silently turned every gated registry write
/// into a no-op for the duration of a widget test, which showed up both as
/// "the write did not take effect" (callers that do not await) and as
/// ten-minute hangs (callers that do). A serialization primitive that can stop
/// a write from happening is worse than the interleaving it prevents.
///
/// So: when the gate is IDLE the body starts immediately, synchronously, in the
/// caller's own zone — no cross-zone hop exists to be stalled. Chaining happens
/// only when a section is genuinely in flight, which is the case the gate exists
/// for, and both participants are then in the same zone in every real scenario
/// (production has a single `runZonedGuarded` zone).
final class AsyncGate {
  /// Completion of the last queued section, or null when nothing is in flight.
  Future<void>? _tail;

  /// Sections queued but not finished. The count, rather than `_tail`'s
  /// completion, is what marks the gate idle: `Future` exposes no "is it
  /// complete" and we must not chain onto a finished future from another zone.
  int _pending = 0;

  /// Bumped by [reset], so bookkeeping from a discarded generation cannot touch
  /// the counter of the new one.
  int _generation = 0;

  /// Whether a section is currently in flight.
  bool get isBusy => _pending > 0;

  /// Run [body] once every previously queued section has finished.
  ///
  /// Returns [body]'s own result, including its error — a failing section
  /// reaches its caller and does not wedge the queue for anyone else.
  ///
  /// NOT re-entrant, deliberately: a section that AWAITS another section on the
  /// same gate deadlocks, because the inner one is queued behind the outer one
  /// that is waiting for it. Submitting without awaiting is fine and is properly
  /// serialized.
  Future<T> run<T>(Future<T> Function() body) {
    final tail = _pending == 0 ? null : _tail;
    _pending++;
    final generation = _generation;
    // Publish this section's barrier BEFORE any user code runs. `Future.sync`
    // starts [body] synchronously, so a section that submits another section
    // from that synchronous prefix used to find `_tail` still unset, take the
    // idle path, and start immediately — two sections inside the gate at once,
    // which is the one thing this class exists to prevent.
    final barrier = Completer<void>();
    _tail = barrier.future;
    // `Future.sync` keeps the "idle" path in the caller's zone AND turns a
    // synchronous throw from [body] into a normal error result.
    final pending = tail == null
        ? Future<T>.sync(body)
        : tail.then((_) => body());
    pending.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      // Only the generation that incremented may decrement: a completion left
      // over from before a [reset] would otherwise report the gate idle while a
      // section of the new generation is still running. The barrier is always
      // completed, generation or not — someone may be queued behind it.
      if (generation == _generation) _pending--;
      barrier.complete();
    });
    return pending;
  }

  /// Drop any queued state.
  ///
  /// For tests only, and specifically for the case a test ABANDONS a section:
  /// the bookkeeping above is resolved by callbacks, so a section still in
  /// flight when its test ends leaves `_pending` above zero and the next test
  /// chaining onto a future from a dead zone.
  @visibleForTesting
  void reset() {
    _generation++;
    _tail = null;
    _pending = 0;
  }
}
