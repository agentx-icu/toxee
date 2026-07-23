import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_camera_switch_controller.dart';

void main() {
  test(
    'rapid taps coalesce and revalidate after camera stop completes',
    () async {
      final controller = CallCameraSwitchController();
      final stopped = Completer<void>();
      final transactionStarted = Completer<void>();
      var active = true;
      var switchTransactions = 0;
      var restarts = 0;

      Future<void> performSwitch(bool Function() canRestart) async {
        switchTransactions += 1;
        transactionStarted.complete();
        await stopped.future;
        if (canRestart()) restarts += 1;
      }

      final first = controller.switchCamera(
        canSwitch: () => active,
        prepareSwitch: () async {},
        performSwitch: performSwitch,
      );
      final second = controller.switchCamera(
        canSwitch: () => active,
        prepareSwitch: () async {},
        performSwitch: performSwitch,
      );

      await transactionStarted.future;
      active = false;
      stopped.complete();
      await Future.wait([first, second]);

      expect(switchTransactions, 1);
      expect(restarts, 0);
    },
  );

  test('inactive calls do not start a camera switch transaction', () async {
    final controller = CallCameraSwitchController();
    var switchTransactions = 0;

    await controller.switchCamera(
      canSwitch: () => false,
      prepareSwitch: () async {},
      performSwitch: (_) async => switchTransactions += 1,
    );

    expect(switchTransactions, 0);
  });

  test(
    'a call replaced during preparation cannot start destructive switching',
    () async {
      final controller = CallCameraSwitchController();
      final preparationStarted = Completer<void>();
      final finishPreparation = Completer<void>();
      var active = true;
      var switchTransactions = 0;

      final switching = controller.switchCamera(
        canSwitch: () => active,
        prepareSwitch: () async {
          preparationStarted.complete();
          await finishPreparation.future;
        },
        performSwitch: (_) async => switchTransactions += 1,
      );

      await preparationStarted.future;
      active = false;
      finishPreparation.complete();
      await switching;

      expect(switchTransactions, 0);
    },
  );

  test('a replaced call session cannot restart an old switch', () async {
    final controller = CallCameraSwitchController();
    final stopped = Completer<void>();
    final transactionStarted = Completer<void>();
    var generation = 4;
    var inviteID = 'call-a';
    final capturedGeneration = generation;
    final capturedInviteID = inviteID;
    var restarts = 0;

    bool isOriginalSession() =>
        generation == capturedGeneration && inviteID == capturedInviteID;

    final switching = controller.switchCamera(
      canSwitch: isOriginalSession,
      prepareSwitch: () async {},
      performSwitch: (canRestart) async {
        transactionStarted.complete();
        await stopped.future;
        if (canRestart()) restarts += 1;
      },
    );

    await transactionStarted.future;
    generation += 1;
    inviteID = 'call-b';
    stopped.complete();
    await switching;

    expect(restarts, 0);
  });
}
