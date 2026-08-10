import 'dart:async';
import 'dart:io';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

import '../sdk_fake/fake_event_bus.dart';
import '../sdk_fake/fake_im.dart';
import '../sdk_fake/fake_models.dart';
import '../util/logger.dart';

/// OS-level dock/launcher badge for unread conversations.
///
/// Per-platform support (via `app_badge_plus`):
/// - macOS:   full — NSDockTile badge label
/// - iOS:     full — UIApplication.applicationIconBadgeNumber
/// - Android: best-effort — depends on launcher (Samsung TouchWiz, Xiaomi
///            MIUI, Pixel Launcher each implement ShortcutBadger-style
///            counts differently; no-op on launchers that don't support it)
/// - Linux:   not supported by the plugin (silently skipped)
/// - Windows: no native count badge API; the plugin reports
///            `isSupported() == false`. TODO: investigate taskbar overlay
///            icons via win32 channel if user-facing requirement justifies
///            the extra surface.
///
/// Architecture notes:
/// - Subscribes to [FakeIM.topicUnread] on the [FakeEventBus] — the same
///   stream UIKit's conversation listener uses (see
///   `FakeConversationManager._unreadSub` in
///   `lib/sdk_fake/fake_managers.dart`). The total is already summed by
///   [FakeIM.refreshUnreadTotal] across all C2C + groups, so this service
///   never has to re-walk conversations itself.
/// - Updates are debounced to 200ms so a burst of incoming messages from
///   multiple peers in the same poll cycle results in one badge write,
///   not one per peer.
/// - Writes are serialized through a single drain loop ([_drainWrites]) with
///   "latest value wins" semantics, so two overlapping async writes can never
///   complete out of order and leave the badge showing the older total.
/// - The badge API is always invoked from a microtask on the root isolate's
///   event loop — bus events may originate from the FFI poll thread (via
///   Tim2Tox callbacks), and platform channel calls must run on the platform
///   thread/main isolate.
/// - Dedupe is against the total we *confirmed* on the badge, not the total we
///   last attempted: a failed write is retried the next time the same total is
///   flushed. See [_lastWrittenTotal].
/// - All `AppBadgePlus` calls are wrapped in try/catch so an unsupported
///   launcher (Android) or platform never surfaces as an uncaught error.
class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  static const Duration _debounce = Duration(milliseconds: 200);

  StreamSubscription<FakeUnreadTotal>? _sub;
  Timer? _debounceTimer;
  int _pendingTotal = 0;

  /// The total we have *confirmed* on the OS badge — a [BadgeWriter.updateBadge]
  /// call that completed without throwing. `-1` means "unknown": nothing has
  /// been written yet, or we deliberately dropped our belief about the badge
  /// (see [clear] / [dispose]).
  ///
  /// Only a **successful** write advances this. A failed write leaves it alone
  /// so that flushing the same total again re-attempts it; otherwise one
  /// transient failure would pin the badge at a stale number until the unread
  /// count happened to change to some *other* value.
  int _lastWrittenTotal = -1;

  /// The total the badge *should* show: queued, in flight, or failed and
  /// waiting for another attempt. Cleared only once [_lastWrittenTotal] agrees
  /// with it. Null means "nothing outstanding".
  ///
  /// This is the second half of the dedupe key: an already-queued/in-flight
  /// value must not be enqueued a second time, or a repeated total would be
  /// written twice.
  int? _desired;

  /// Non-null while [_drainWrites] is running; completes when the loop goes
  /// idle. Serializes badge writes (see the class doc) and lets [clear] /
  /// [dispose] await work that is already in flight.
  Future<void>? _drain;

  /// Bumped by [debugResetForTesting] so a drain loop left over from a previous
  /// test can neither write nor clobber the fresh [_drain] handle.
  int _drainEpoch = 0;

  bool _started = false;
  int _lifecycleEpoch = 0;

  /// Cached result of [AppBadgePlus.isSupported] so we don't bounce across
  /// the platform channel on every write. Null until first probe completes;
  /// once known, fixed for the lifetime of the process.
  bool? _supported;

  /// Test-only override for [_platformPlausible].
  ///
  /// Why this exists: [_platformPlausible] reads `dart:io` `Platform.*`, which
  /// `debugDefaultTargetPlatformOverride` does NOT affect (same reason
  /// `ResponsiveLayout.debugIsDesktopPlatformOverride` exists). `flutter test`
  /// runs on the host OS — macOS locally but **Linux in CI** — so on CI the
  /// gate is `false` and [start], [clear] and [dispose] all short-circuit
  /// before doing anything observable. That made the whole service (bus
  /// subscription, 200ms debounce, coalescing, dedupe, the `isSupported`
  /// cache) unreachable from `flutter test` on the CI host.
  ///
  /// Set it in `setUp` and null it in `tearDown` — [BadgeService] is a
  /// singleton, so this is process-global state. [debugResetForTesting]
  /// clears it.
  @visibleForTesting
  bool Function()? debugPlatformPlausibleOverride;

  /// Test-only replacement for the real `app_badge_plus` writer.
  ///
  /// Why this exists: every badge call goes over a platform channel, so on a
  /// test host they throw `MissingPluginException`, which [_writeBadge] and
  /// [clear] swallow **by design** (best-effort UX, not a correctness gate).
  /// A test therefore cannot distinguish "wrote 3" from "wrote nothing", which
  /// is exactly what the debounce/coalesce/dedupe logic needs to assert on.
  /// Injecting a [BadgeWriter] also means tests never have to know the
  /// plugin's channel or method names — they are not discoverable from this
  /// repo (pub dependency, no vendored Dart source).
  ///
  /// Null (the default) means "use the real `AppBadgePlus`", so the production
  /// path is byte-for-byte the same calls as before.
  @visibleForTesting
  BadgeWriter? debugBadgeWriter;

  BadgeWriter get _writer => debugBadgeWriter ?? const _AppBadgePlusWriter();

  /// Coarse static gate: platforms where the plugin definitely has no
  /// implementation. Avoids a platform-channel round-trip just to learn it
  /// isn't there. Final word still belongs to [AppBadgePlus.isSupported].
  bool get _platformPlausible {
    final override = debugPlatformPlausibleOverride;
    if (override != null) return override();
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS || Platform.isAndroid;
  }

  /// Idempotent. Subscribes the service to [FakeIM.topicUnread] on [bus] and
  /// asks [im] to emit the current total once so the badge reflects state
  /// from the moment startup completes (instead of waiting for the first
  /// message-triggered emit).
  void start({required FakeEventBus bus, required FakeIM im}) =>
      _start(bus: bus, prime: im.refreshUnreadTotal);

  /// Test-only entry point equivalent to [start], minus the [FakeIM].
  ///
  /// Why this exists: [start] only ever uses `im` for the one
  /// `refreshUnreadTotal()` priming call, but `FakeIM`'s constructor requires a
  /// real `FfiChatService`, which dlopen's `libtim2tox_ffi` — unavailable in a
  /// plain `flutter test`. Taking the primer as a plain callback lets a test
  /// exercise the *real* bus subscription (and therefore the real debounce
  /// path) instead of poking at private members. [prime] defaults to a no-op.
  @visibleForTesting
  void debugStart({required FakeEventBus bus, void Function()? prime}) =>
      _start(bus: bus, prime: prime ?? () {});

  void _start({required FakeEventBus bus, required void Function() prime}) {
    if (_started) return;
    _started = true;
    if (!_platformPlausible) {
      AppLogger.debug(
        '[BadgeService] Platform not supported (${Platform.operatingSystem}); skipping',
      );
      return;
    }
    final subscriptionEpoch = ++_lifecycleEpoch;
    _sub = bus.on<FakeUnreadTotal>(FakeIM.topicUnread).listen((u) {
      if (!_started || _lifecycleEpoch != subscriptionEpoch) return;
      _scheduleWrite(u.total);
    });
    AppLogger.debug('[BadgeService] started');
    // Prime the badge with the current total. The emit is async (walks the
    // friend list); we don't await — the bus listener above will pick it up.
    prime();
  }

  /// Schedules a badge write with [_debounce] coalescing. Multiple unread
  /// totals arriving within the window collapse to a single write of the
  /// latest value.
  void _scheduleWrite(int total) {
    _pendingTotal = total < 0 ? 0 : total;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _flush);
  }

  void _flush() {
    final value = _pendingTotal;
    // Fast path: the badge already shows this and nothing is outstanding.
    // The `_desired == null` half matters — while a write is queued, in flight,
    // or has failed, the badge is *not* necessarily at [_lastWrittenTotal], so
    // deduping on it alone would drop a needed write.
    if (value == _lastWrittenTotal && _desired == null) return;
    _desired = value;
    unawaited(_pump());
  }

  /// Starts the serialized write loop unless it is already running. Returns a
  /// future that completes when the loop goes idle.
  Future<void> _pump() {
    final running = _drain;
    if (running != null) return running;
    if (_desired == null) return Future<void>.value();
    final drain = _drainWrites(_drainEpoch);
    _drain = drain;
    return drain;
  }

  /// Writes [_desired] to the badge, one call at a time, latest value wins.
  ///
  /// Stops — **without** clearing [_desired] — as soon as a write does not
  /// succeed. Retrying inside this loop would spin forever against a badge
  /// backend that is permanently unavailable (an unsupported launcher, a dead
  /// platform channel). Instead the next [_flush] restarts the loop, so a
  /// permanently failing backend costs exactly one attempt per debounce window
  /// that produced a flush — the same order of magnitude as the happy path,
  /// and strictly better than silently leaving the badge stale forever.
  Future<void> _drainWrites(int epoch) async {
    // Hop onto the root isolate's microtask queue before touching the platform
    // channel: bus events can originate from a polling callback. Suspending
    // here first also guarantees [_pump] has assigned [_drain] before this body
    // can reach its `finally`.
    await Future<void>.microtask(() {});
    try {
      while (_drainEpoch == epoch) {
        final value = _desired;
        if (value == null) return;
        if (value == _lastWrittenTotal) {
          // The badge already shows this — e.g. an earlier failed write left
          // [_desired] set and the unread count then came back to the confirmed
          // value. Nothing to write; drop the outstanding marker.
          _desired = null;
          return;
        }
        if (!await _writeBadge(value)) return;
        _lastWrittenTotal = value;
        // A newer total may have been queued while we were awaiting; only clear
        // the marker if it is still the value we just wrote.
        if (_desired == value) _desired = null;
      }
    } finally {
      if (_drainEpoch == epoch) _drain = null;
    }
  }

  /// Returns true only when [count] actually reached the OS badge.
  ///
  /// An unsupported plugin also returns false: nothing was written, so
  /// [_lastWrittenTotal] must not move. The cost is one cached-bool check per
  /// flush on such platforms — no platform-channel traffic.
  Future<bool> _writeBadge(int count) async {
    try {
      // Probe once — cache the answer for the rest of the process lifetime.
      final writer = _writer;
      _supported ??= await writer.isSupported();
      if (_supported != true) return false;
      await writer.updateBadge(count);
      AppLogger.debug('[BadgeService] badge written: $count');
      return true;
    } catch (e, st) {
      // Unsupported launchers (Android) and Windows / Linux throw here.
      // Swallow — this is best-effort UX, not a correctness gate.
      AppLogger.debug('[BadgeService] writeBadge failed (best-effort): $e');
      if (kDebugMode) {
        AppLogger.debug('[BadgeService] stack: $st');
      }
      return false;
    }
  }

  /// Force the badge to zero immediately (skips the debounce). Use when the
  /// app gains focus / a conversation is opened that drops the total to 0.
  ///
  /// This is a *force*, not a dedupe-checked update: the 0 is written even if
  /// we believe 0 is already showing. Awaiting it waits for the write queue to
  /// go idle, so a total that was already in flight lands first and the 0 wins.
  Future<void> clear() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingTotal = 0;
    if (!_platformPlausible) return;
    // Drop our belief about the badge so the queued 0 is never deduped away.
    _lastWrittenTotal = -1;
    _desired = 0;
    await _pump();
  }

  /// Tear down on session teardown (logout / account switch). The subscription
  /// would otherwise hold the previous session's FakeEventBus alive.
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _detachSubscription();
    _pendingTotal = 0;
    // Abandon anything queued (or failed and awaiting a retry) — the session is
    // going away, so those totals are meaningless now.
    _desired = null;
    _started = false;
    // Let a write that is already in flight land before ours, otherwise it
    // could complete after the 0 below and resurrect a stale count.
    final inFlight = _drain;
    if (inFlight != null) await inFlight;
    _lastWrittenTotal = -1;
    if (!_platformPlausible) return;
    try {
      if (_supported == true) {
        await _writer.updateBadge(0);
      }
    } catch (e) {
      AppLogger.warn('[BadgeService] clearing badge during dispose failed: $e');
    }
  }

  /// Test-only full reset of this singleton's process-global state.
  ///
  /// Why this exists: [dispose] deliberately keeps the cached [_supported]
  /// probe result ("fixed for the lifetime of the process") and obviously does
  /// not know about the two `debug*` seams above. Tests need a hard reset
  /// between cases, and must not leak an override into unrelated tests running
  /// in the same isolate. Call this from `tearDown`.
  @visibleForTesting
  Future<void> debugResetForTesting() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _detachSubscription();
    _pendingTotal = 0;
    _lastWrittenTotal = -1;
    _desired = null;
    _started = false;
    _supported = null;
    // Deliberately NOT awaited: a test may end with a write parked on a
    // never-completed gate, and that future can never resume once its FakeAsync
    // zone is gone — awaiting it would hang `tearDown`. Bumping the epoch makes
    // any such leftover loop a no-op that cannot touch the next test's state.
    _drainEpoch++;
    _drain = null;
    debugBadgeWriter = null;
    debugPlatformPlausibleOverride = null;
  }

  /// Detach the current bus subscription without making badge cleanup wait for
  /// the stream implementation's asynchronous cancellation future. The epoch
  /// check in the listener prevents queued events from a previous session from
  /// scheduling a write after [dispose] or [debugResetForTesting].
  void _detachSubscription() {
    final subscription = _sub;
    _sub = null;
    _lifecycleEpoch++;
    if (subscription != null) unawaited(subscription.cancel());
  }
}

/// The slice of the `app_badge_plus` API that [BadgeService] depends on.
///
/// Exists purely so [BadgeService.debugBadgeWriter] can substitute a recording
/// double in tests; production always uses [_AppBadgePlusWriter].
abstract class BadgeWriter {
  /// Mirrors `AppBadgePlus.isSupported()`.
  Future<bool> isSupported();

  /// Mirrors `AppBadgePlus.updateBadge(count)`.
  Future<void> updateBadge(int count);
}

class _AppBadgePlusWriter implements BadgeWriter {
  const _AppBadgePlusWriter();

  @override
  Future<bool> isSupported() async =>
      (await AppBadgePlus.isSupported()) == true;

  @override
  Future<void> updateBadge(int count) => AppBadgePlus.updateBadge(count);
}
