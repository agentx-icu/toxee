import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/network_change_rebootstrapper.dart';

/// Checklist N1: the Dart trigger policy of the network-change re-bootstrap.
void main() {
  const wifi = NetworkPathSnapshot(available: true, identity: 'wlan0|wifi|10.0.0.2');
  const wifiNewIp = NetworkPathSnapshot(available: true, identity: 'wlan0|wifi|10.0.0.9');
  const cell = NetworkPathSnapshot(available: true, identity: 'rmnet0|cellular|100.64.1.2');
  const offline = NetworkPathSnapshot(available: false);

  late StreamController<NetworkPathSnapshot> events;
  late int kicks;
  late NetworkChangeReBootstrapper r;
  Completer<void>? gate;
  bool Function()? lastIsLive;

  void setUpTrigger() {
    events = StreamController<NetworkPathSnapshot>();
    kicks = 0;
    gate = null;
    r = NetworkChangeReBootstrapper(
      snapshots: events.stream,
      kick: (isLive) {
        kicks++;
        lastIsLive = isLive;
        return gate?.future ?? Future<void>.value();
      },
    )..start();
  }

  tearDown(() => events.close());

  void emit(FakeAsync async, NetworkPathSnapshot s) {
    events.add(s);
    async.flushMicrotasks();
  }

  test('the first snapshot is the current network, not a change', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      async.elapse(const Duration(minutes: 1));
      expect(kicks, 0);
    });
  });

  test('a handover kicks once, after the debounce', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      emit(async, cell);
      async.elapse(const Duration(seconds: 2));
      expect(kicks, 0, reason: 'still inside the 3 s debounce');
      async.elapse(const Duration(seconds: 2));
      expect(kicks, 1);
    });
  });

  test('a new address on the same interface is a change', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      emit(async, wifiNewIp);
      async.elapse(const Duration(seconds: 4));
      expect(kicks, 1);
    });
  });

  test('repeats of the same path are ignored', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      emit(async, wifi);
      emit(async, wifi);
      async.elapse(const Duration(seconds: 10));
      expect(kicks, 0);
    });
  });

  test('a burst of changes is debounced into one kick', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      emit(async, cell);
      async.elapse(const Duration(seconds: 1));
      emit(async, wifiNewIp);
      async.elapse(const Duration(seconds: 1));
      emit(async, cell);
      async.elapse(const Duration(seconds: 4));
      expect(kicks, 1);
    });
  });

  test('never kicks while offline; going offline cancels a pending kick', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      emit(async, cell);
      emit(async, offline);
      async.elapse(const Duration(seconds: 10));
      expect(kicks, 0);
    });
  });

  test('coming back online (even on the same network) is a change', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      emit(async, offline);
      emit(async, wifi);
      async.elapse(const Duration(seconds: 4));
      expect(kicks, 1);
    });
  });

  test('first snapshot offline, then a network appears: kicks', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, offline);
      emit(async, wifi);
      async.elapse(const Duration(seconds: 4));
      expect(kicks, 1);
    });
  });

  test('a change inside the 30 s window runs as ONE trailing kick', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      emit(async, cell);
      async.elapse(const Duration(seconds: 4));
      expect(kicks, 1);
      emit(async, wifi);
      async.elapse(const Duration(seconds: 4));
      emit(async, cell);
      async.elapse(const Duration(seconds: 4));
      expect(kicks, 1, reason: 'inside the minimum interval');
      async.elapse(const Duration(seconds: 30));
      expect(kicks, 2, reason: 'one trailing kick, not one per change');
      async.elapse(const Duration(minutes: 2));
      expect(kicks, 2);
    });
  });

  test('the trailing kick is dropped if the device went offline meanwhile', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      emit(async, cell);
      async.elapse(const Duration(seconds: 4));
      emit(async, wifi);
      async.elapse(const Duration(seconds: 4));
      emit(async, offline);
      async.elapse(const Duration(minutes: 1));
      expect(kicks, 1);
    });
  });

  test('only one kick runs at a time; a change during it trails', () {
    fakeAsync((async) {
      setUpTrigger();
      gate = Completer<void>();
      emit(async, wifi);
      emit(async, cell);
      async.elapse(const Duration(seconds: 4));
      expect(kicks, 1);
      // The kick is still running when the cool-down ends and a change lands.
      emit(async, wifi);
      async.elapse(const Duration(seconds: 40));
      expect(kicks, 1, reason: 'first kick still in flight');
      gate!.complete();
      gate = null;
      async.flushMicrotasks();
      expect(kicks, 2);
    });
  });

  test('dispose cancels pending work', () {
    fakeAsync((async) {
      setUpTrigger();
      emit(async, wifi);
      emit(async, cell);
      unawaited(r.dispose());
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(kicks, 0);
    });
  });

  test('an in-flight kick sees isLive turn false on dispose', () {
    fakeAsync((async) {
      setUpTrigger();
      gate = Completer<void>();
      emit(async, wifi);
      emit(async, cell);
      async.elapse(const Duration(seconds: 4));
      expect(kicks, 1);
      expect(lastIsLive!(), isTrue);
      unawaited(r.dispose());
      async.flushMicrotasks();
      expect(lastIsLive!(), isFalse,
          reason: 'a kick awaiting the node list must stop after teardown');
      gate!.complete();
      async.flushMicrotasks();
      expect(kicks, 1);
    });
  });

  test('platform events are parsed defensively', () {
    setUpTrigger();
    expect(
      NetworkPathSnapshot.fromEvent({'available': true, 'identity': 'x'})?.identity,
      'x',
    );
    expect(NetworkPathSnapshot.fromEvent({'available': false})?.available, isFalse);
    expect(NetworkPathSnapshot.fromEvent({'identity': 'x'}), isNull);
    expect(NetworkPathSnapshot.fromEvent('garbage'), isNull);
  });
}
