import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../util/diagnostic_record.dart';
import '../util/logger.dart';

/// Install after the chosen binding, before session ownership or bootstrap.
/// Debug retains the binding's error buffer and Flutter's rich presentation.
/// Production consumes the error using closed metadata, including before the
/// sink is ready; default stderr presentation must not bypass that boundary.
final class RuntimeErrorHooks {
  RuntimeErrorHooks({bool production = !kDebugMode})
    : production = !kDebugMode || production;

  final bool production;

  void install() {
    final prior = FlutterError.onError;
    FlutterError.onError = (details) {
      _capture(DiagnosticOrigin.framework, details.exception, details.stack);
      if (production) return;
      if (prior != null && prior != FlutterError.presentError) prior(details);
      final description = StringBuffer('Flutter Error: ${details.exception}');
      if (details.context != null) {
        description.write(' (context: ${details.context})');
      }
      if (details.library != null) {
        description.write(' [library: ${details.library}]');
      }
      AppLogger.logError(
        description.toString(),
        details.exception,
        details.stack,
      );
      final information = details.informationCollector?.call();
      if (information != null) {
        final text = information
            .map((node) => node.toString())
            .where((line) => line.trim().isNotEmpty)
            .join('\n');
        if (text.isNotEmpty) AppLogger.error('Flutter Error details:\n$text');
      }
      FlutterError.presentError(details);
    };
    ui.PlatformDispatcher.instance.onError = handleDispatcherError;
  }

  bool handleDispatcherError(Object error, StackTrace stack) {
    _capture(DiagnosticOrigin.dispatcher, error, stack);
    // false would invoke the embedder's unfiltered stderr handler.
    return true;
  }

  void handleZoneError(Object error, StackTrace stack) {
    _capture(DiagnosticOrigin.zone, error, stack);
  }

  void _capture(DiagnosticOrigin origin, Object error, StackTrace? stack) {
    try {
      AppLogger.recordError(origin, error, stack);
      if (!production) {
        AppLogger.logError('Uncaught ${origin.name} error', error, stack);
      }
    } catch (_) {
      // No original value or stack and no call back into a failed logger.
      try {
        stderr.writeln('origin=logger error_type=unavailable');
      } catch (_) {}
    }
  }
}
