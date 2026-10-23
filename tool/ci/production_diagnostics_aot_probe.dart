import 'dart:io';

import 'package:toxee/util/diagnostic_record.dart';

void _throwDiagnosticProbe() =>
    throw StateError('PRIVATE_DIAGNOSTIC_MARKER_a549a2');

void main() {
  try {
    _throwDiagnosticProbe();
  } catch (error, stack) {
    final record = DiagnosticRecord.capture(
      DiagnosticOrigin.zone,
      error,
      stack,
    );
    stdout.writeln(record.body);
    for (final frame in record.frames) {
      stdout.writeln(frame);
    }
  }
}
