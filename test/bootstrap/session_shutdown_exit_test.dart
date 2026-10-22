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
          timeout: const Duration(seconds: 1), logContext: 'test');
      completion.complete(stopped);
      expect(await result, stopped);
    });
  }
  test('a timeout reports failure while the in-flight teardown continues', () async {
    final completion = Completer<bool>();
    ActiveSession.trackTeardown(completion.future).ignore();
    expect(await SessionShutdown.tearDownActiveAccount(
        timeout: Duration.zero, logContext: 'test'), isFalse);
    completion.complete(true);
    await completion.future;
  });
}
