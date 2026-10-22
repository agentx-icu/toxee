import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/bootstrap/session_shutdown.dart';
import 'package:toxee/util/active_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(ActiveSession.reset);
  for (final stopped in [false, true]) {
    test('joining a teardown preserves its stopped=$stopped result', () async {
      final completion = Completer<bool>();
      ActiveSession.trackTeardown(completion.future).ignore();
      final result = SessionShutdown.tearDownActiveAccount(
        timeout: const Duration(seconds: 1),
        logContext: 'test',
      );
      completion.complete(stopped);
      expect(await result, stopped);
    });
  }
  testWidgets(
    'desktop shutdown joins an already running teardown without deadline',
    (tester) async {
      final completion = Completer<bool>();
      ActiveSession.trackTeardown(completion.future).ignore();
      var completed = false;
      final result = SessionShutdown.tearDownActiveAccount(logContext: 'test')
          .then((stopped) {
            completed = true;
            return stopped;
          });
      await tester.pump(const Duration(seconds: 11));
      expect(completed, isFalse);
      completion.complete(true);
      expect(await result, isTrue);
    },
  );
  test(
    'a timeout reports failure while the in-flight teardown continues',
    () async {
      final completion = Completer<bool>();
      ActiveSession.trackTeardown(completion.future).ignore();
      expect(
        await SessionShutdown.tearDownActiveAccount(
          timeout: Duration.zero,
          logContext: 'test',
        ),
        isFalse,
      );
      completion.complete(true);
      await completion.future;
    },
  );
}
