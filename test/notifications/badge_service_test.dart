import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/notifications/badge_service.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/util/logger.dart';

/// Records every badge call so [BadgeService]'s debounce / coalesce / dedupe
/// decisions become observable.
///
/// Stands in for `app_badge_plus`, whose real calls cross a platform channel
/// that throws `MissingPluginException` under `flutter test` — an exception
/// [BadgeService] swallows by design, which is exactly why the real plugin
/// cannot be used to tell "wrote 3" apart from "wrote nothing".
class _RecordingBadgeWriter implements BadgeWriter {
  _RecordingBadgeWriter({this.supported = true});

  bool supported;

  /// When non-null, [isSupported] throws this once and then clears it.
  Object? throwOnNextIsSupported;

  /// When non-null, [updateBadge] throws this once and then clears it.
  Object? throwOnNextUpdate;

  /// While true every [updateBadge] throws — a badge backend that is down for
  /// good, used to prove the service does not retry itself into a spin.
  bool failAllUpdates = false;

  /// When non-null, the next [updateBadge] parks on this completer before it
  /// succeeds or throws, so a test can hold a write *in flight* and observe
  /// what the service does with totals that arrive meanwhile.
  Completer<void>? blockNextUpdate;

  final List<int> writes = <int>[];
  int isSupportedCalls = 0;

  /// Counts every [updateBadge] entry, including the ones that throw — the
  /// difference between "did not retry" and "retried and failed" is invisible
  /// in [writes].
  int updateAttempts = 0;

  @override
  Future<bool> isSupported() async {
    isSupportedCalls++;
    final boom = throwOnNextIsSupported;
    if (boom != null) {
      throwOnNextIsSupported = null;
      throw boom;
    }
    return supported;
  }

  @override
  Future<void> updateBadge(int count) async {
    updateAttempts++;
    // Claim the one-shot outcome *before* parking, so it belongs to this call
    // no matter what runs while we are suspended.
    final boom = throwOnNextUpdate;
    if (boom != null) throwOnNextUpdate = null;
    final gate = blockNextUpdate;
    if (gate != null) {
      blockNextUpdate = null;
      await gate.future;
    }
    if (boom != null) throw boom;
    if (failAllUpdates) throw StateError('badge backend permanently down');
    writes.add(count);
  }
}

void main() {
  final service = BadgeService.instance;
  late _RecordingBadgeWriter writer;
  late bool platformPlausible;
  late List<FakeEventBus> buses;

  setUp(() {
    writer = _RecordingBadgeWriter();
    platformPlausible = true;
    buses = <FakeEventBus>[];
    service.debugBadgeWriter = writer;
    service.debugPlatformPlausibleOverride = () => platformPlausible;
    // AppLogger is never initialised in unit tests; without this it emits a
    // "log file is null" line on stderr. `true` is the production default.
    AppLogger.setFileLoggingEnabled(false);
  });

  tearDown(() async {
    // BadgeService is a process-global singleton and both seams live on it,
    // so a leaked override would poison unrelated tests in this isolate.
    await service.debugResetForTesting();
    for (final bus in buses) {
      bus.dispose();
    }
    AppLogger.setFileLoggingEnabled(true);
  });

  /// Creates a bus, subscribes the service to it, and returns it.
  ///
  /// The bus is created *inside* the [FakeAsync] zone (via the caller) and
  /// listened to there too, so every stream-delivery microtask is owned by
  /// [FakeAsync] and drained by `flushMicrotasks` / `elapse`.
  FakeEventBus startService({void Function()? prime}) {
    final bus = FakeEventBus();
    buses.add(bus);
    service.debugStart(bus: bus, prime: prime);
    return bus;
  }

  /// Publishes an unread total and lets the (non-sync) broadcast
  /// StreamController deliver it, without advancing the debounce clock.
  void emitUnread(FakeAsync asyncZone, FakeEventBus bus, int total) {
    bus.emit(FakeIM.topicUnread, FakeUnreadTotal(total));
    asyncZone.flushMicrotasks();
  }

  /// Pushes past the 200ms debounce window and drains the microtask hops
  /// `_flush -> scheduleMicrotask -> _writeBadge -> await` introduces.
  void settle(FakeAsync asyncZone) {
    asyncZone.elapse(const Duration(milliseconds: 250));
    asyncZone.flushMicrotasks();
  }

  group('debounce and coalescing', () {
    test(
        'collapses a burst inside the 200ms window into a single write of '
        'the latest value', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 1);
        asyncZone.elapse(const Duration(milliseconds: 50));
        emitUnread(asyncZone, bus, 2);
        asyncZone.elapse(const Duration(milliseconds: 50));
        emitUnread(asyncZone, bus, 7);

        // 150ms after the last emit we are still inside its window.
        asyncZone.elapse(const Duration(milliseconds: 150));
        asyncZone.flushMicrotasks();
        expect(writer.writes, isEmpty,
            reason: 'the debounce timer restarts on every emit');

        settle(asyncZone);
        expect(writer.writes, <int>[7]);
      });
    });

    test('emits in separate windows produce one write each', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 5);
        settle(asyncZone);

        expect(writer.writes, <int>[1, 5]);
      });
    });

    test('repeating the last written total does not re-write the badge', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 4);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 4);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 4);
        settle(asyncZone);

        expect(writer.writes, <int>[4],
            reason: 'flush dedupes against the last written total');
      });
    });

    test('a total that changes and changes back writes both times', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 0);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);

        expect(writer.writes, <int>[2, 0, 2]);
      });
    });
  });

  group('value handling', () {
    test('zero is written as an explicit 0 rather than skipped', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 0);
        settle(asyncZone);

        expect(writer.writes, <int>[0],
            reason: 'the last-written sentinel is -1, so 0 is a real change');
      });
    });

    test('negative totals are clamped to 0 before reaching the platform', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, -3);
        settle(asyncZone);

        expect(writer.writes, <int>[0]);
      });
    });

    test('a negative total following a 0 is deduped, not written twice', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 0);
        settle(asyncZone);
        emitUnread(asyncZone, bus, -9);
        settle(asyncZone);

        expect(writer.writes, <int>[0],
            reason: '-9 clamps to 0, which equals the last written total');
      });
    });

    test('large totals pass through unchanged', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 99999);
        settle(asyncZone);

        expect(writer.writes, <int>[99999]);
      });
    });
  });

  group('platform gate', () {
    test(
        'start() on an implausible platform subscribes to nothing and never '
        'probes the plugin', () {
      fakeAsync((asyncZone) {
        platformPlausible = false;
        var primed = false;

        final bus = startService(prime: () => primed = true);

        emitUnread(asyncZone, bus, 3);
        settle(asyncZone);

        expect(writer.writes, isEmpty);
        expect(writer.isSupportedCalls, 0,
            reason: 'the coarse gate must avoid the platform-channel hop');
        expect(primed, isFalse,
            reason: 'priming is pointless with nothing subscribed');
      });
    });

    test('clear() on an implausible platform writes nothing', () async {
      platformPlausible = false;

      await service.clear();

      expect(writer.writes, isEmpty);
      expect(writer.isSupportedCalls, 0);
    });

    test('dispose() on an implausible platform writes nothing', () async {
      platformPlausible = false;

      await service.dispose();

      expect(writer.writes, isEmpty);
      expect(writer.isSupportedCalls, 0);
    });
  });

  group('isSupported probe', () {
    test('an unsupported plugin means no badge writes at all', () {
      fakeAsync((asyncZone) {
        writer.supported = false;
        final bus = startService();

        emitUnread(asyncZone, bus, 3);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 4);
        settle(asyncZone);

        expect(writer.writes, isEmpty);
        expect(writer.isSupportedCalls, 1,
            reason: 'a negative probe is cached just like a positive one');
      });
    });

    test('the probe result is cached across writes', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 3);
        settle(asyncZone);

        expect(writer.writes, <int>[1, 2, 3]);
        expect(writer.isSupportedCalls, 1);
      });
    });

    test('a probe that throws is retried on the next write', () {
      fakeAsync((asyncZone) {
        writer.throwOnNextIsSupported = StateError('channel down');
        final bus = startService();

        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);
        expect(writer.writes, isEmpty);

        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);

        expect(writer.writes, <int>[2],
            reason: 'the cache stays null after a throw, so it re-probes');
        expect(writer.isSupportedCalls, 2);
      });
    });
  });

  group('failure tolerance', () {
    test(
        'a throwing updateBadge neither escapes nor kills later scheduling',
        () {
      fakeAsync((asyncZone) {
        writer.throwOnNextUpdate = StateError('launcher rejected badge');
        final bus = startService();

        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);
        expect(writer.writes, isEmpty, reason: 'the first write threw');

        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);

        expect(writer.writes, <int>[2],
            reason: 'the service must keep serving later totals');
      });
      // An async error escaping the service would surface as an uncaught
      // error in the surrounding test zone and fail this test, so reaching
      // this line is itself the assertion that it was swallowed internally.
    });

    // Previously asserted the opposite ("a failed write is NOT retried for the
    // same total"), locking in the bug it documented: `_flush` advanced the
    // last-written total *before* the async write, so a failed write left the
    // dedupe state claiming 6 was on the badge and re-emitting 6 was a no-op —
    // the badge stayed stale until the count changed to some *other* value.
    // The service now advances that state only on a confirmed write.
    test('a failed write IS retried when the same total comes round again', () {
      fakeAsync((asyncZone) {
        writer.throwOnNextUpdate = StateError('launcher rejected badge');
        final bus = startService();

        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);
        expect(writer.writes, isEmpty, reason: 'the first attempt threw');
        expect(writer.updateAttempts, 1);

        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);

        expect(writer.writes, <int>[6],
            reason: 'dedupe tracks confirmed writes, not attempted ones');
        expect(writer.updateAttempts, 2);
      });
    });

    test('dedupe resumes once a retry finally succeeds', () {
      fakeAsync((asyncZone) {
        writer.throwOnNextUpdate = StateError('launcher rejected badge');
        final bus = startService();

        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);
        expect(writer.writes, <int>[6]);

        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);

        expect(writer.writes, <int>[6],
            reason: 'the retry confirmed 6, so further 6s are deduped again');
        expect(writer.updateAttempts, 2, reason: 'no third platform call');
      });
    });

    test(
        'a permanently failing backend is attempted at most once per flush, '
        'never in a retry loop', () {
      fakeAsync((asyncZone) {
        writer.failAllUpdates = true;
        final bus = startService();

        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);

        expect(writer.writes, isEmpty);
        // Three flushes, three attempts. Self-retrying inside the write loop
        // would instead spin the microtask queue forever (and hang this test).
        expect(writer.updateAttempts, 3);

        writer.failAllUpdates = false;
        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);

        expect(writer.writes, <int>[1],
            reason: 'the service recovers as soon as the backend does');
      });
    });

    test('a failed total is abandoned once the unread count moves on', () {
      fakeAsync((asyncZone) {
        writer.throwOnNextUpdate = StateError('launcher rejected badge');
        final bus = startService();

        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);

        expect(writer.writes, <int>[2],
            reason: 'the retry target follows the latest total, not the '
                'stale 6 that failed');
        expect(writer.updateAttempts, 2);
      });
    });

    test('a failure is not retried when the badge already shows that total',
        () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 3);
        settle(asyncZone);
        expect(writer.writes, <int>[3]);

        writer.throwOnNextUpdate = StateError('launcher rejected badge');
        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);
        expect(writer.writes, <int>[3], reason: '6 failed');

        emitUnread(asyncZone, bus, 3);
        settle(asyncZone);

        expect(writer.writes, <int>[3]);
        expect(writer.updateAttempts, 2,
            reason: '3 is already confirmed on the badge — nothing to write, '
                'and the failed 6 is obsolete');
      });
    });

    test('an unsupported plugin is never re-probed by the retry path', () {
      fakeAsync((asyncZone) {
        writer.supported = false;
        final bus = startService();

        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);

        expect(writer.writes, isEmpty);
        expect(writer.updateAttempts, 0);
        expect(writer.isSupportedCalls, 1,
            reason: 'an unsupported plugin never advances the confirmed total, '
                'but the cached probe keeps that off the platform channel');
      });
    });
  });

  group('write serialization', () {
    test('a repeat of an in-flight total is not written twice', () {
      fakeAsync((asyncZone) {
        final gate = Completer<void>();
        writer.blockNextUpdate = gate;
        final bus = startService();

        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);
        expect(writer.updateAttempts, 1, reason: 'the write is parked');
        expect(writer.writes, isEmpty);

        // The same total again while the first write has not landed. Deduping
        // only against *confirmed* writes would let this through and write 6
        // twice.
        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);
        expect(writer.updateAttempts, 1);

        gate.complete();
        asyncZone.flushMicrotasks();
        expect(writer.writes, <int>[6]);

        emitUnread(asyncZone, bus, 6);
        settle(asyncZone);
        expect(writer.writes, <int>[6],
            reason: 'and it stays deduped after the write confirms');
      });
    });

    test('a total queued during an in-flight write lands after it, in order',
        () {
      fakeAsync((asyncZone) {
        final gate = Completer<void>();
        writer.blockNextUpdate = gate;
        final bus = startService();

        emitUnread(asyncZone, bus, 5);
        settle(asyncZone);
        expect(writer.updateAttempts, 1);

        emitUnread(asyncZone, bus, 3);
        settle(asyncZone);
        expect(writer.updateAttempts, 1,
            reason: 'writes are serialized, not fired concurrently');

        gate.complete();
        asyncZone.flushMicrotasks();

        expect(writer.writes, <int>[5, 3],
            reason: 'the older value must never land last');
      });
    });

    test('bursts during one in-flight write collapse to the latest total', () {
      fakeAsync((asyncZone) {
        final gate = Completer<void>();
        writer.blockNextUpdate = gate;
        final bus = startService();

        emitUnread(asyncZone, bus, 1);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);
        emitUnread(asyncZone, bus, 3);
        settle(asyncZone);

        gate.complete();
        asyncZone.flushMicrotasks();

        expect(writer.writes, <int>[1, 3],
            reason: '2 was superseded before it ever reached the platform');
      });
    });

    test('dispose() waits for an in-flight write so its 0 lands last', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        // Get past the probe so dispose() knows the plugin is usable.
        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);
        expect(writer.writes, <int>[2]);

        final gate = Completer<void>();
        writer.blockNextUpdate = gate;
        emitUnread(asyncZone, bus, 5);
        settle(asyncZone);
        expect(writer.updateAttempts, 2);

        unawaited(service.dispose());
        asyncZone.flushMicrotasks();
        expect(writer.writes, <int>[2],
            reason: 'dispose must not race its 0 past the parked write');

        gate.complete();
        asyncZone.flushMicrotasks();

        expect(writer.writes, <int>[2, 5, 0],
            reason: "dispose's 0 is the final state of the badge");
      });
    });
  });

  group('lifecycle', () {
    test('start() is idempotent — a second bus is ignored', () {
      fakeAsync((asyncZone) {
        var firstPrimed = 0;
        var secondPrimed = 0;

        final first = startService(prime: () => firstPrimed++);
        final second = startService(prime: () => secondPrimed++);

        emitUnread(asyncZone, second, 9);
        settle(asyncZone);
        expect(writer.writes, isEmpty,
            reason: 'the second bus was never subscribed');

        emitUnread(asyncZone, first, 3);
        settle(asyncZone);
        expect(writer.writes, <int>[3]);

        expect(firstPrimed, 1);
        expect(secondPrimed, 0);
      });
    });

    test('start() primes exactly once and the prime itself writes nothing',
        () {
      fakeAsync((asyncZone) {
        var primed = 0;
        startService(prime: () => primed++);
        settle(asyncZone);

        expect(primed, 1);
        expect(writer.writes, isEmpty,
            reason: 'priming only asks FakeIM to emit; it writes no badge');
      });
    });

    test('clear() forces 0 immediately and cancels a pending write', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 7);
        // Still inside the debounce window: the 7 is pending.
        unawaited(service.clear());
        asyncZone.flushMicrotasks();

        expect(writer.writes, <int>[0], reason: 'clear() skips the debounce');

        settle(asyncZone);
        expect(writer.writes, <int>[0],
            reason: 'the pending 7 must have been cancelled');
      });
    });

    test('clear() then an unread total of 0 does not double-write 0', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        unawaited(service.clear());
        asyncZone.flushMicrotasks();
        expect(writer.writes, <int>[0]);

        emitUnread(asyncZone, bus, 0);
        settle(asyncZone);

        expect(writer.writes, <int>[0],
            reason: 'clear() already set the last written total to 0');
      });
    });

    test('clear() is a force: it writes 0 even when 0 is already confirmed',
        () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 0);
        settle(asyncZone);
        expect(writer.writes, <int>[0]);

        unawaited(service.clear());
        asyncZone.flushMicrotasks();

        // Dedupe must not swallow clear(): it exists precisely for the case
        // where our idea of the badge and the OS's may have drifted apart.
        expect(writer.writes, <int>[0, 0]);
      });
    });

    test('clear() queues its 0 behind a write that is already in flight', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        // Get past the probe first.
        emitUnread(asyncZone, bus, 2);
        settle(asyncZone);

        final gate = Completer<void>();
        writer.blockNextUpdate = gate;
        emitUnread(asyncZone, bus, 5);
        settle(asyncZone);
        expect(writer.updateAttempts, 2, reason: 'the 5 is parked');

        unawaited(service.clear());
        asyncZone.flushMicrotasks();
        expect(writer.writes, <int>[2], reason: 'nothing may overtake the 5');

        gate.complete();
        asyncZone.flushMicrotasks();

        expect(writer.writes, <int>[2, 5, 0],
            reason: '0 is the last thing the badge sees');
      });
    });

    test('dispose() unsubscribes so later bus events are ignored', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 3);
        settle(asyncZone);
        expect(writer.writes, <int>[3]);

        unawaited(service.dispose());
        asyncZone.flushMicrotasks();
        expect(writer.writes, <int>[3, 0],
            reason: 'dispose clears the badge once the plugin is known good');

        emitUnread(asyncZone, bus, 8);
        settle(asyncZone);
        expect(writer.writes, <int>[3, 0],
            reason: 'the subscription is gone');
      });
    });

    test('dispose() does not touch the plugin when it was never probed', () {
      fakeAsync((asyncZone) {
        startService();

        unawaited(service.dispose());
        asyncZone.flushMicrotasks();

        expect(writer.writes, isEmpty);
        expect(writer.isSupportedCalls, 0);
      });
    });

    test('dispose() drops a pending debounced write', () {
      fakeAsync((asyncZone) {
        final bus = startService();

        emitUnread(asyncZone, bus, 5);
        unawaited(service.dispose());
        asyncZone.flushMicrotasks();
        settle(asyncZone);

        expect(writer.writes, isEmpty);
      });
    });

    test('start() works again after dispose() (logout then re-login)', () {
      fakeAsync((asyncZone) {
        final first = startService();
        emitUnread(asyncZone, first, 2);
        settle(asyncZone);
        expect(writer.writes, <int>[2]);

        unawaited(service.dispose());
        asyncZone.flushMicrotasks();
        expect(writer.writes, <int>[2, 0]);

        final second = startService();
        emitUnread(asyncZone, second, 2);
        settle(asyncZone);

        expect(writer.writes, <int>[2, 0, 2],
            reason: 'dispose resets the last-written sentinel, so 2 is new');
      });
    });
  });
}
