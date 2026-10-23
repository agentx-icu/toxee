import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/bootstrap/logging_bootstrap.dart';
import 'package:toxee/bootstrap/runtime_error_hooks.dart';
import 'package:toxee/util/diagnostic_record.dart';
import 'package:toxee/util/logger.dart';
import 'package:toxee/util/safe_diagnostics.dart';

const marker = 'PRIVATE_MESSAGE_token=https://private.invalid/?key=SECRET_4fe8';

class MarkerFailure implements Exception {
  @override
  String toString() => marker;
}

class UnrenderableFailure implements Exception {
  @override
  String toString() =>
      throw StateError('exception values must not be rendered');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File log;
  late FlutterExceptionHandler? priorFramework;
  late FlutterExceptionHandler priorPresentation;
  late ui.ErrorCallback? priorDispatcher;

  setUp(() async {
    AppLogger.resetForTesting(production: true);
    directory = await Directory.systemTemp.createTemp(
      'toxee_safe_diagnostics_',
    );
    log = File('${directory.path}/app.log');
    priorFramework = FlutterError.onError;
    priorPresentation = FlutterError.presentError;
    priorDispatcher = ui.PlatformDispatcher.instance.onError;
  });
  tearDown(() async {
    FlutterError.onError = priorFramework;
    FlutterError.presentError = priorPresentation;
    ui.PlatformDispatcher.instance.onError = priorDispatcher;
    AppLogger.resetForTesting();
    await directory.delete(recursive: true);
  });
  Future<void> initialize() async {
    AppLogger.setLogPath(log.path);
    await AppLogger.initialize();
  }

  test(
    'all Dart body, exception, print and synthetic-stack entry points omit values',
    () async {
      await initialize();
      AppLogger.setConsoleLoggingEnabled(true);
      AppLogger.debug(marker);
      AppLogger.info(marker);
      AppLogger.warn(marker);
      AppLogger.error(marker);
      AppLogger.logError(
        marker,
        MarkerFailure(),
        StackTrace.fromString(marker),
      );
      SafeDiagnostics.logFailure(marker, MarkerFailure());
      LoggingBootstrap.routePrintToLogger(marker);
      LoggingBootstrap.routePrintToLogger(
        'TCCF:2026-02-11 03:48:47 PM:component:error:{ $marker }',
      );
      final text = await log.readAsString();
      expect(text, isNot(contains(marker)));
      expect(text, isNot(contains('private.invalid')));
      expect(text, contains('origin=application error_type=MarkerFailure'));
      expect(text, contains('body=omitted'));
    },
  );

  test(
    'framework hooks capture before initialization and consume without presentation or collectors',
    () async {
      var forwarded = 0;
      var presented = 0;
      FlutterError.onError = (_) => forwarded++;
      FlutterError.presentError = (_) => presented++;
      RuntimeErrorHooks(production: true).install();
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: UnrenderableFailure(),
          stack: StackTrace.fromString(marker),
          context: ErrorDescription(marker),
          library: marker,
          informationCollector: () =>
              throw StateError('collector must not run in release'),
        ),
      );
      expect(forwarded, 0);
      expect(presented, 0);
      await initialize();
      final text = await log.readAsString();
      expect(text, contains('origin=framework error_type=UnrenderableFailure'));
      expect(text, isNot(contains(marker)));
    },
  );

  test(
    'dispatcher and zone retain bounded early metadata without exception rendering',
    () async {
      final hooks = RuntimeErrorHooks(production: true);
      for (var i = 0; i < 40; i++) {
        expect(
          hooks.handleDispatcherError(
            UnrenderableFailure(),
            StackTrace.current,
          ),
          isTrue,
        );
      }
      hooks.handleZoneError(
        UnrenderableFailure(),
        StackTrace.fromString(marker),
      );
      await initialize();
      final text = await log.readAsString();
      expect(
        RegExp(
          'origin=dispatcher error_type=UnrenderableFailure',
        ).allMatches(text),
        hasLength(32),
      );
      expect(text, contains('early_records_dropped=9'));
      expect(text, isNot(contains(marker)));
      expect(text, contains('package:test_api/src/backend/invoker.dart'));
      expect(text, isNot(contains(directory.path)));
    },
  );

  test(
    'failed initialization cannot recurse and never renders an exception value',
    () async {
      final blocker = File('${directory.path}/blocked');
      await blocker.writeAsString('not a directory');
      AppLogger.setLogPath('${blocker.path}/$marker');
      await AppLogger.initialize();
      final hooks = RuntimeErrorHooks(production: true);
      expect(
        () => hooks.handleZoneError(UnrenderableFailure(), StackTrace.current),
        returnsNormally,
      );
      expect(log.existsSync(), isFalse);
    },
  );

  test(
    'real VM source frames are retained while synthetic sources are untrusted',
    () {
      final real = DiagnosticRecord.capture(
        DiagnosticOrigin.application,
        StateError(marker),
        StackTrace.current,
      );
      expect(real.frames, isNotEmpty);
      expect(real.frames.join('\n'), isNot(contains('/Users/')));
      final fake = DiagnosticRecord.capture(
        DiagnosticOrigin.zone,
        MarkerFailure(),
        StackTrace.fromString(
          '#0 secret (package:toxee/stolen.dart:1:1)\n$marker',
        ),
      );
      expect(fake.frames, isEmpty);
    },
  );

  test(
    'canonical explicit paths rotate at the existing 10 MB boundary and retain ten segments',
    () async {
      final path = '${directory.path}/app_1700000000000.log';
      AppLogger.setLogPath(path);
      await AppLogger.initialize();
      for (var i = 0; i < 12; i++) {
        final current = File(AppLogger.getLogPath()!);
        final handle = await current.open(mode: FileMode.append);
        try {
          await handle.truncate(10 * 1024 * 1024 - 1);
        } finally {
          await handle.close();
        }
        AppLogger.logError(marker, UnrenderableFailure());
        expect(AppLogger.getLogPath(), isNot(current.path));
        expect(
          directory.listSync().whereType<File>().length,
          lessThanOrEqualTo(10),
        );
        expect(
          File(AppLogger.getLogPath()!).lengthSync(),
          lessThan(10 * 1024 * 1024),
        );
      }
    },
  );

  test(
    'arbitrary custom fixture paths retain their explicit append behavior',
    () async {
      await initialize();
      final handle = await log.open(mode: FileMode.append);
      try {
        await handle.truncate(10 * 1024 * 1024);
      } finally {
        await handle.close();
      }
      AppLogger.logError(marker, UnrenderableFailure());
      expect(AppLogger.getLogPath(), log.path);
      expect(log.lengthSync(), greaterThan(10 * 1024 * 1024));
    },
  );

  test(
    'debug retains prior binding presentation and full harness details',
    () async {
      AppLogger.resetForTesting();
      await initialize();
      var forwarded = 0;
      var presented = 0;
      FlutterError.onError = (_) => forwarded++;
      FlutterError.presentError = (_) => presented++;
      RuntimeErrorHooks().install();
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: MarkerFailure(),
          context: ErrorDescription('debug context'),
          informationCollector: () => [ErrorDescription('debug render object')],
        ),
      );
      expect(forwarded, 1);
      expect(presented, 1);
      final text = await log.readAsString();
      expect(text, contains(marker));
      expect(text, contains('debug context'));
      expect(text, contains('debug render object'));
    },
  );
}
