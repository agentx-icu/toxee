import 'dart:io';

import 'package:toxee/util/diagnostic_record.dart';

void _throwDiagnosticProbe() =>
    throw StateError('PRIVATE_DIAGNOSTIC_MARKER_a549a2');

@pragma('vm:never-inline')
void _captureDiagnosticProbe() {
  try {
    _throwDiagnosticProbe();
  } catch (error) {
    final record = DiagnosticRecord.capture(DiagnosticOrigin.zone, error);
    stdout.writeln(record.body);
    for (final frame in record.frames) {
      stdout.writeln(frame);
    }
  }
}

void main() => _captureDiagnosticProbe();
