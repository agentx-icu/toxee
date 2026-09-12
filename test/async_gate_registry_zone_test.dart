// Regression test for the serialization gate that silently swallowed registry
// writes inside widget tests.
//
// `Prefs` serializes every read-modify-write on `account_list` so a concurrent
// `touchAccountLoginTime` cannot drop a freshly imported account. The first
// implementation was the obvious `_tail = _tail.then(body)` chain — and that is
// a trap: `Future.then` on an already-completed future schedules its callback in
// the SOURCE future's zone. A mutation issued from inside a `testWidgets` body
// therefore chained onto a future created in `setUp`, i.e. in the outer zone,
// and its body did not run until the test was over:
//
//   * callers that do not await the write (the self-profile save closure) saw
//     the old row and the edit appeared to be lost;
//   * callers that do await it hung until the ten-minute test timeout — twenty
//     tests across account switch, logout and delete died this way.
//
// [AsyncGate] fixes it by starting the body immediately, in the CALLER's zone,
// whenever the gate is idle. These tests pin both halves: the zone behaviour,
// and the mutual exclusion that is the reason the gate exists at all.

library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/async_gate.dart';
import 'package:toxee/util/prefs.dart';

const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AsyncGate', () {
    test('serializes sections that overlap', () async {
      final gate = AsyncGate();
      final order = <String>[];

      Future<void> section(String name, int hops) async {
        order.add('$name:start');
        for (var i = 0; i < hops; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        order.add('$name:end');
      }

      // Started together, and the first one yields repeatedly: without the gate
      // `b:start` would land between `a:start` and `a:end`.
      final a = gate.run(() => section('a', 5));
      final b = gate.run(() => section('b', 1));
      await Future.wait(<Future<void>>[a, b]);

      expect(order, <String>['a:start', 'a:end', 'b:start', 'b:end']);
    });

    test('a failing section releases the gate and its error reaches its caller',
        () async {
      final gate = AsyncGate();
      await expectLater(
        gate.run<void>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(await gate.run(() async => 'after'), 'after');
      expect(gate.isBusy, isFalse);
    });

    test('a synchronous throw comes back as a failed future, not a throw', () {
      final gate = AsyncGate();
      expect(
        () => gate.run<void>(() => throw StateError('sync')),
        returnsNormally,
      );
    });

    test('a section submitted from inside a section still waits its turn',
        () async {
      // `Future.sync` starts the body synchronously, so the outer section is
      // already running when it submits the inner one. Publishing the barrier
      // only AFTER that call let the inner section see an idle gate and start
      // immediately: `outer:start, inner:start, outer:end` (codex reproduced it).
      // Submitting is legal; AWAITING the inner one from the outer would
      // deadlock, which is what "not re-entrant" means.
      final gate = AsyncGate();
      final order = <String>[];
      Future<void>? inner;

      final outer = gate.run(() async {
        order.add('outer:start');
        inner = gate.run(() async => order.add('inner:start'));
        await Future<void>.delayed(Duration.zero);
        order.add('outer:end');
      });
      await outer;
      await inner;

      expect(order, <String>['outer:start', 'outer:end', 'inner:start']);
    });

    test('a completion from before a reset cannot unlock the new generation',
        () async {
      final gate = AsyncGate();
      final stuck = Completer<void>();
      final abandoned = gate.run(() => stuck.future);

      gate.reset(); // as a test tearDown would, with a section still in flight

      final order = <String>[];
      final b = gate.run(() async {
        order.add('b:start');
        await Future<void>.delayed(Duration.zero);
        order.add('b:end');
      });
      // The abandoned section finishes now. Its bookkeeping used to decrement
      // the NEW generation's counter to zero, so the next caller saw an idle
      // gate and ran alongside `b`.
      stuck.complete();
      await abandoned;
      final c = gate.run(() async => order.add('c:start'));
      await Future.wait<void>(<Future<void>>[b, c]);

      expect(order, <String>['b:start', 'b:end', 'c:start']);
    });

    test('is idle again once the queue drains', () async {
      final gate = AsyncGate();
      await gate.run(() async {});
      expect(gate.isBusy, isFalse);
    });
  });

  group('the registry gate does not strand a write issued from a widget test',
      () {
    setUp(() async {
      Prefs.resetRegistryGate();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      // THE PRECONDITION that broke everything: a gated mutation performed in
      // the outer zone, leaving the gate's tail future owned by that zone.
      await Prefs.addAccount(toxId: _toxId, nickname: 'Before');
    });

    testWidgets('a fire-and-forget mutation lands within a few frames',
        (WidgetTester tester) async {
      // Deliberately NOT awaited: this is the self-profile save shape, where the
      // widget fires the write and the test pumps. Awaiting it would have hung
      // for ten minutes before the fix; unawaited, it simply never happened.
      unawaited(Prefs.addAccount(toxId: _toxId, nickname: 'AfterUnawaited'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final row = await Prefs.getAccountByToxId(_toxId);
      expect(row?['nickname'], 'AfterUnawaited');
    });

    testWidgets('an awaited mutation completes inside the test body',
        (WidgetTester tester) async {
      await Prefs.addAccount(toxId: _toxId, nickname: 'AfterAwaited');
      final row = await Prefs.getAccountByToxId(_toxId);
      expect(row?['nickname'], 'AfterAwaited');
    });
  });
}
