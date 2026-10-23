import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/bootstrap/logging_bootstrap.dart';
import 'package:toxee/util/async_task.dart';
import 'package:toxee/util/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File log;
  setUp(() async {
    AppLogger.resetForTesting();
    directory = await Directory.systemTemp.createTemp('toxee_logger_zone_');
    log = File('${directory.path}/app_zone.log');
    await AppLogger.openFreshLogSink(log.path);
  });
  tearDown(() async {
    await debugPrintDone;
    AppLogger.resetForTesting();
    await directory.delete(recursive: true);
  });

  test(
    'SDK print routing does not recursively re-enter the console logger',
    () async {
      var routed = 0;
      AppLogger.setConsoleLoggingEnabled(true);
      await runZoned(
        () async {
          AppLogger.info('direct info');
          AppLogger.debug('direct debug');
          // This is the main() routing shape. A small guard bounds the old
          // recursion so a regression fails without overflowing the test process.
          Zone.current.print('sdk inbound');
          await debugPrintDone;
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            routed++;
            if (routed > 3) { throw StateError('recursive logger console output'); }
            LoggingBootstrap.routePrintToLogger(line);
          },
        ),
      );
      expect(
        routed,
        1,
        reason: 'Only the original SDK output enters the router',
      );
      final rows = await log.readAsLines();
      for (final message in ['direct info', 'direct debug', 'sdk inbound']) {
        expect(rows.where((line) => line.endsWith(message)), hasLength(1));
      }
      expect(rows.any((line) => line.contains('[INFO] direct info')), isTrue);
      expect(rows.any((line) => line.contains('[DEBUG] direct debug')), isTrue);
    },
  );

  test(
    'background task errors are recorded without escaping their owner',
    () async {
      final unhandled = <Object>[];
      final done = Completer<void>();
      runZonedGuarded(() {
        observeBackgroundTask(
          Future<void>.error(
            StateError('secret-profile-/private/account-key'),
            StackTrace.fromString('secret-stack-/private/account-key'),
          ),
          'media cleanup',
        );
        scheduleMicrotask(() => scheduleMicrotask(done.complete));
      }, (error, stack) => unhandled.add(error));
      await done.future;
      expect(unhandled, isEmpty);
      final text = await log.readAsString();
      expect(text, contains('[ERROR] media cleanup error_type=StateError'));
      expect(text, isNot(contains('secret-profile')));
      expect(text, isNot(contains('secret-stack')));
      expect(text, isNot(contains('/private/account-key')));
    },
  );
  test(
    'queued SDK debug output cannot reroute a formatted logger entry',
    () async {
      final previousDebugPrint = debugPrint;
      debugPrint = debugPrintThrottled;
      final filler = 'x' * (13 * 1024);
      var routed = 0;
      AppLogger.setConsoleLoggingEnabled(true);
      try {
        await runZoned(
          () async {
            // One large SDK line fills the shared throttle and schedules its next
            // flush in this routing zone before the logger emits its own line.
            debugPrint('$filler\ncomponent queued marker');
            AppLogger.debug('queued logger debug');
            await debugPrintDone;
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) {
              if (line == filler) return;
              routed++;
              if (routed > 3) {
                throw StateError('recursive buffered console output');
              }
              LoggingBootstrap.routePrintToLogger(line);
            },
          ),
        );
      } finally {
        await debugPrintDone;
        debugPrint = previousDebugPrint;
      }
      expect(routed, 1, reason: 'Only the queued SDK entry enters its router');
      final rows = await log.readAsLines();
      expect(
        rows.where((line) => line.endsWith('queued logger debug')),
        hasLength(1),
      );
      expect(
        rows.where((line) => line.endsWith('component queued marker')),
        hasLength(1),
      );
    },
  );
}
