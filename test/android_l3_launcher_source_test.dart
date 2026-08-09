import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android L3 launcher disables implicit pub resolution', () {
    final source = File('run_toxee_android.sh').readAsStringSync();
    const startMarker = 'run_android_l3() {';
    const endMarker = '\n# Main\n';
    final start = source.indexOf(startMarker);
    final end = source.indexOf(endMarker, start + startMarker.length);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final function = source.substring(start, end);
    expect(
      function,
      matches(
        RegExp(
          r'nohup flutter run -d "\$SELECTED_DEVICE_ID" '
          r'--"\$MODE" --machine\s+--no-pub',
        ),
      ),
      reason:
          '--skip-pub-get must also prevent flutter run from starting an '
          'implicit network-dependent pub resolution before the VM service.',
    );
  });

  test('Android Fixture C pair disables implicit pub resolution', () {
    final source = File(
      'tool/mcp_test/launch_android_fixture_c_pair.sh',
    ).readAsStringSync();
    const startMarker = 'launch_android_instance() {';
    const endMarker = '\n# Launch A then B SEQUENTIALLY';
    final start = source.indexOf(startMarker);
    final end = source.indexOf(endMarker, start + startMarker.length);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final function = source.substring(start, end);
    expect(
      function,
      matches(
        RegExp(
          r'nohup flutter run -d "\$device_id" '
          r'--"\$MODE" --machine\s+--no-pub',
        ),
      ),
      reason:
          'Fixture C already owns its pub preflight; each flutter run must not '
          'start another network-dependent package resolution.',
    );
  });
}
