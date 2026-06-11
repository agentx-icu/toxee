import 'dart:io';

void _expectContains(String source, String needle, String label) {
  if (!source.contains(needle)) {
    throw StateError('Missing $label: $needle');
  }
}

void main() {
  final driver = File(
    'tool/mcp_test/drive_real_ui_pair.dart',
  ).readAsStringSync();
  final runner = File(
    'tool/mcp_test/fixture_c_unified_runner.dart',
  ).readAsStringSync();
  final p3Part = File('tool/mcp_test/drive_real_ui_pair_p3.dart');
  if (!p3Part.existsSync()) {
    throw StateError('Missing P3 writable driver part: ${p3Part.path}');
  }
  final p3 = p3Part.readAsStringSync();

  _expectContains(
    driver,
    "part 'drive_real_ui_pair_p3.dart';",
    'P3 writable driver part include',
  );
  _expectContains(
    driver,
    "scenario == 'sweep_p3_writable'",
    'sweep_p3_writable dispatch',
  );
  _expectContains(
    driver,
    '_isP3WritableCaseScenario(scenario)',
    'P3 writable standalone dispatch',
  );
  _expectContains(
    p3,
    'message_burst_perf',
    'message_burst_perf scenario implementation',
  );
  _expectContains(p3, 'RUI_BURST_PERF_COUNT', 'parametric burst count env');
  _expectContains(
    p3,
    'RUI_BURST_PERF_NONBLOCKING_MS',
    'non-blocking performance threshold env',
  );
  _expectContains(p3, 'NONBLOCKING', 'non-blocking threshold log');
  _expectContains(
    runner,
    "'sweep_p3_writable'",
    'sweep_p3_writable runner registration',
  );
  _expectContains(
    runner,
    "'message_burst_perf'",
    'message_burst_perf runner registration',
  );
  _expectContains(
    runner,
    "'rui-p3-writable': ['sweep_p3_writable']",
    'rui-p3-writable campaign registration',
  );
}
