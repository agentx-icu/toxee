import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_media_interruption_controller.dart';

void main() {
  test(
    'duplicate loss and gain events suspend and resume exactly once',
    () async {
      final controller = CallMediaInterruptionController();
      var suspends = 0;
      var resumes = 0;

      await Future.wait([
        controller.suspend(() async => suspends += 1),
        controller.suspend(() async => suspends += 1),
      ]);
      await Future.wait([
        controller.resume(
          canResume: () => true,
          resumeMedia: () async => resumes += 1,
        ),
        controller.resume(
          canResume: () => true,
          resumeMedia: () async => resumes += 1,
        ),
      ]);

      expect(suspends, 1);
      expect(resumes, 1);
    },
  );

  test('cancel prevents a queued resume after hang-up', () async {
    final controller = CallMediaInterruptionController();
    final stopCompleter = Completer<void>();
    var resumes = 0;

    final suspendFuture = controller.suspend(() => stopCompleter.future);
    expect(controller.isSuspended, isTrue);
    final resumeFuture = controller.resume(
      canResume: () => true,
      resumeMedia: () async => resumes += 1,
    );
    controller.cancel();
    stopCompleter.complete();

    await Future.wait([suspendFuture, resumeFuture]);
    expect(resumes, 0);
  });

  test('resume is skipped when the call is no longer active', () async {
    final controller = CallMediaInterruptionController();
    var resumes = 0;

    await controller.suspend(() async {});
    await controller.resume(
      canResume: () => false,
      resumeMedia: () async => resumes += 1,
    );

    expect(resumes, 0);
  });

  test('failed suspend is logged and does not poison later resume', () async {
    final loggedErrors = <Object>[];
    final controller = CallMediaInterruptionController(
      logTailError: (error, stackTrace) => loggedErrors.add(error),
    );
    var resumes = 0;

    await expectLater(
      controller.suspend(() async {
        throw StateError('audio interruption failed');
      }),
      throwsStateError,
    );
    await controller.resume(
      canResume: () => true,
      resumeMedia: () async => resumes += 1,
    );

    expect(loggedErrors, hasLength(1));
    expect(loggedErrors.single, isA<StateError>());
    expect(resumes, 1);
  });

  test('failed resume remains suspended so a later resume can retry', () async {
    final loggedErrors = <Object>[];
    final controller = CallMediaInterruptionController(
      logTailError: (error, stackTrace) => loggedErrors.add(error),
    );
    var attempts = 0;

    await controller.suspend(() async {});
    await expectLater(
      controller.resume(
        canResume: () => true,
        resumeMedia: () async {
          attempts += 1;
          throw StateError('audio resume failed');
        },
      ),
      throwsStateError,
    );
    await controller.resume(
      canResume: () => true,
      resumeMedia: () async => attempts += 1,
    );

    expect(attempts, 2);
    expect(loggedErrors, hasLength(1));
    expect(loggedErrors.single, isA<StateError>());
    expect(controller.isSuspended, isFalse);
  });
}
