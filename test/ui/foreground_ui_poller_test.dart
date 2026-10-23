import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/home/foreground_ui_poller.dart';

void main() {
  testWidgets('visible polling stops while hidden and refreshes on resume', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var reads = 0;
    final poller = ForegroundUiPoller(
      read: () async => reads++,
      onError: (error, stack) => fail('Unexpected poll failure: $error'),
    )..start();
    addTearDown(poller.dispose);
    await tester.pump();
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 20));
    expect(reads, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 3);
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 4);
    poller.dispose();
  });

  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('starting $state does not read until visible', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(state);
      var reads = 0;
      final poller = ForegroundUiPoller(
        read: () async => reads++,
        onError: (_, _) => fail('Unexpected poll failure'),
      )..start();
      addTearDown(poller.dispose);
      await tester.pump(const Duration(seconds: 20));
      expect(reads, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(reads, 1);
      poller.dispose();
    });
  }

  testWidgets('visible inactive window keeps a single poll schedule', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var reads = 0;
    final poller = ForegroundUiPoller(
      read: () async => reads++,
      onError: (_, _) => fail('Unexpected poll failure'),
    )..start();
    addTearDown(poller.dispose);
    await tester.pump();
    poller.start();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 2);
    poller.dispose();
  });

  testWidgets('slow read coalesces ticks and one refresh after resume', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final pending = <Completer<void>>[];
    final poller = ForegroundUiPoller(
      read: () {
        final next = Completer<void>();
        pending.add(next);
        return next.future;
      },
      onError: (_, _) => fail('Unexpected poll failure'),
    )..start();
    addTearDown(poller.dispose);
    await tester.pump(const Duration(seconds: 20));
    expect(pending, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(pending, hasLength(1));
    pending.first.complete();
    await tester.pump();
    expect(pending, hasLength(2));
    pending.last.complete();
    await tester.pump();
    expect(pending, hasLength(2));
    poller.dispose();
  });

  testWidgets('dispose during read prevents a queued resume refresh', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final pending = Completer<void>();
    var reads = 0;
    final poller = ForegroundUiPoller(
      read: () {
        reads++;
        return pending.future;
      },
      onError: (_, _) => fail('Unexpected poll failure'),
    )..start();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    poller.dispose();
    poller.dispose();
    pending.complete();
    await tester.pump(const Duration(seconds: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    poller.start();
    await tester.pump();
    expect(reads, 1);
  });

  testWidgets(
    'failed and synchronous reads are observed and later ticks work',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var reads = 0;
      final failures = <Object>[];
      final error = StateError('test read failure');
      final poller = ForegroundUiPoller(
        read: () {
          reads++;
          if (reads == 1) throw error;
          if (reads == 2) return Future.error(error);
          return Future<void>.value();
        },
        onError: (error, _) => failures.add(error),
      )..start();
      addTearDown(poller.dispose);
      await tester.pump();
      expect(failures, [error]);
      await tester.pump(const Duration(seconds: 2));
      expect(failures, [error, error]);
      await tester.pump(const Duration(seconds: 2));
      expect(reads, 3);
      expect(tester.takeException(), isNull);
      poller.dispose();
    },
  );
}
