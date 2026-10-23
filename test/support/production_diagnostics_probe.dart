// Separate process so the parent can inspect actual stdout/stderr, including
// logger initialization/failure paths which bypass Dart Zone.print.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/bootstrap/logging_bootstrap.dart';
import 'package:toxee/bootstrap/runtime_error_hooks.dart';
import 'package:toxee/util/logger.dart';

const marker = 'PRIVATE_DIAGNOSTIC_MARKER_a549a2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('production console and file boundary', () async {
    final directory = await Directory.systemTemp.createTemp(marker);
    final priorError = FlutterError.onError;
    final priorPresentation = FlutterError.presentError;
    try {
      AppLogger.resetForTesting(production: true);
      final log = File('${directory.path}/$marker.log');
      AppLogger.setLogPath(log.path);
      final hooks = RuntimeErrorHooks(production: true);
      hooks.handleZoneError(StateError(marker), StackTrace.current);
      await AppLogger.initialize();
      AppLogger.setConsoleLoggingEnabled(true);
      AppLogger.info(marker);
      AppLogger.warn(marker);
      AppLogger.error(marker);
      AppLogger.logError(
        marker,
        StateError(marker),
        StackTrace.fromString(marker),
      );
      LoggingBootstrap.routePrintToLogger(marker);
      FlutterError.onError = (_) =>
          throw StateError('release must consume framework errors');
      FlutterError.presentError = (_) =>
          throw StateError('release must not present raw errors');
      hooks.install();
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError(marker),
          context: ErrorDescription(marker),
        ),
      );
      expect(
        hooks.handleDispatcherError(StateError(marker), StackTrace.current),
        isTrue,
      );
      expect(await log.readAsString(), isNot(contains(marker)));
      // A failure after initialization also exercises the synchronous write path.
      await log.delete();
      await Directory(log.path).create();
      AppLogger.logError(marker, StateError(marker));
      AppLogger.resetForTesting(production: true);
      final blocker = File('${directory.path}/blocked');
      await blocker.writeAsString('not a directory');
      AppLogger.setLogPath('${blocker.path}/$marker.log');
      await AppLogger.initialize();
      hooks.handleZoneError(StateError(marker), StackTrace.current);
    } finally {
      FlutterError.onError = priorError;
      FlutterError.presentError = priorPresentation;
      AppLogger.resetForTesting();
      await directory.delete(recursive: true);
    }
  });
}
