import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void _expectContains(String source, String needle, String label) {
  if (!source.contains(needle)) {
    throw StateError('Missing $label: $needle');
  }
}

void _expectNotContains(String source, String needle, String label) {
  if (source.contains(needle)) {
    throw StateError('Stale $label: $needle');
  }
}

String _scenarioBlock(String source, String scenario, String nextScenario) {
  final startMarker = "if (scenario == '$scenario') {";
  final endMarker = "if (scenario == '$nextScenario') {";
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  if (start < 0 || end <= start) {
    throw StateError('Missing dispatch block for $scenario');
  }
  return source.substring(start, end);
}

void main() {
  test('real UI avatar and restore coverage stays registered', () {
    final campaign = File(
      'tool/mcp_test/REAL_UI_GATES.md',
    ).readAsStringSync();
    final currentTable = campaign.split('## Batch log').first;
    final profileDriver = File(
      'tool/mcp_test/drive_real_ui_pair_profile.dart',
    ).readAsStringSync();
    final loginDriver = File(
      'tool/mcp_test/drive_real_ui_pair_login.dart',
    ).readAsStringSync();
    final pairDriver = File(
      'tool/mcp_test/drive_real_ui_pair.dart',
    ).readAsStringSync();

    _expectContains(
      currentTable,
      '| 19 | profile_avatar_picker_opens | 1i | S79 |',
      'canonical avatar picker row',
    );
    _expectContains(
      currentTable,
      '| 20 | profile_avatar_select_default_applies | 1i | S79 |',
      'canonical avatar apply row',
    );
    _expectContains(
      currentTable,
      '| 26 | login_restore_entry_opens | 1i | S9/S71 |',
      'canonical restore row',
    );
    _expectContains(currentTable, '8/8 runnable, 0 SKIP', 'profile total');
    _expectContains(currentTable, '9/9 runnable,\n0 SKIP', 'login total');
    _expectNotContains(
      currentTable,
      'SKIP(no in-app avatar picker',
      'canonical avatar SKIP',
    );
    _expectNotContains(
      currentTable,
      'SKIP(native-picker-only',
      'canonical native-picker SKIP',
    );
    _expectContains(
      campaign,
      'sweep_profile 8/0/0 (was 6/0/2skip)',
      'avatar conversion log',
    );
    _expectContains(
      campaign,
      'sweep_login 9/0/0 (was 8/0/1skip)',
      'restore conversion log',
    );

    _expectContains(
      profileDriver,
      "'profile_avatar_edit_button'",
      'real avatar control',
    );
    _expectContains(
      profileDriver,
      "'l3_set_avatar_pick_path'",
      'avatar fixed picker-path seam',
    );
    _expectContains(profileDriver, "['selfAvatarPath']", 'avatar assertion');
    _expectNotContains(
      profileDriver,
      'SKIP(no-in-app-avatar-surface)',
      'avatar driver SKIP reason',
    );
    _expectContains(
      profileDriver,
      'return failed == 0 && skipped == 0 ? 0 : 1;',
      'profile sweep hard-fails skips',
    );
    _expectContains(
      loginDriver,
      "'login_page_restore_from_tox_file'",
      'real restore control',
    );
    _expectContains(
      loginDriver,
      "'l3_set_account_import_pick_path'",
      'restore fixed picker-path seam',
    );
    _expectContains(
      loginDriver,
      "'login_page_error_banner'",
      'restore error assertion',
    );
    _expectNotContains(
      loginDriver,
      'SKIP(native-picker-only)',
      'restore driver SKIP reason',
    );
    _expectContains(
      loginDriver,
      'return failed == 0 && skipped == 0 ? 0 : 1;',
      'login sweep hard-fails skips',
    );

    for (final entry in <({String scenario, String helper, String next})>[
      (
        scenario: 'profile_avatar_picker_opens',
        helper: '_profileAvatarPickerOpens',
        next: 'profile_avatar_select_default_applies',
      ),
      (
        scenario: 'profile_avatar_select_default_applies',
        helper: '_profileAvatarSelectDefaultApplies',
        next: 'sweep_login',
      ),
    ]) {
      final block = _scenarioBlock(pairDriver, entry.scenario, entry.next);
      if (entry.helper.allMatches(block).length != 1) {
        throw StateError(
          '${entry.scenario} must evaluate ${entry.helper} once',
        );
      }
      _expectContains(
        block,
        'final result = await ${entry.helper}(a);',
        '${entry.scenario} result capture',
      );
      _expectContains(block, 'true => 0,', '${entry.scenario} PASS mapping');
      _expectContains(block, 'false => 1,', '${entry.scenario} FAIL mapping');
      _expectContains(block, 'null => 75,', '${entry.scenario} SKIP mapping');
    }
  });
}
