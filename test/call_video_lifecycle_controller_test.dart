import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_video_lifecycle_controller.dart';

void main() {
  test(
    'duplicate background/resume events stop and restart video once',
    () async {
      final controller = CallVideoLifecycleController();
      const active = true;
      var stops = 0;
      var starts = 0;

      await Future.wait([
        controller.suspend(
          canSuspend: () => active,
          stopVideo: () async => stops++,
        ),
        controller.suspend(
          canSuspend: () => active,
          stopVideo: () async => stops++,
        ),
      ]);
      await Future.wait([
        controller.resume(
          canResume: () => active,
          startVideo: () async => starts++,
        ),
        controller.resume(
          canResume: () => active,
          startVideo: () async => starts++,
        ),
      ]);

      expect(stops, 1);
      expect(starts, 1);
    },
  );

  test('cancel prevents an old lifecycle resume after call end', () async {
    final controller = CallVideoLifecycleController();
    var starts = 0;

    await controller.suspend(canSuspend: () => true, stopVideo: () async {});
    controller.cancel();
    await controller.resume(
      canResume: () => true,
      startVideo: () async => starts++,
    );

    expect(starts, 0);
  });

  test('failed resume remains suspended so a later resume can retry', () async {
    final loggedErrors = <Object>[];
    final controller = CallVideoLifecycleController(
      logTailError: (error, stackTrace) => loggedErrors.add(error),
    );
    var attempts = 0;

    await controller.suspend(canSuspend: () => true, stopVideo: () async {});
    await expectLater(
      controller.resume(
        canResume: () => true,
        startVideo: () async {
          attempts++;
          throw StateError('camera unavailable');
        },
      ),
      throwsStateError,
    );
    await controller.resume(
      canResume: () => true,
      startVideo: () async => attempts++,
    );

    expect(attempts, 2);
    expect(loggedErrors, hasLength(1));
    expect(loggedErrors.single, isA<StateError>());
  });
}
