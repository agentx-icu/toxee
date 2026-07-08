import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IRC real-UI scenario is wired into app-entry automation', () {
    final driver = File(
      'tool/mcp_test/drive_real_ui_pair_app_entry_extra.dart',
    ).readAsStringSync();
    final runner = File(
      'tool/mcp_test/fixture_c_unified_runner.dart',
    ).readAsStringSync();
    final sidebar = File('lib/ui/settings/sidebar.dart').readAsStringSync();

    expect(driver, contains('irc_join_channel_real_controls'));
    expect(driver, contains('irc_join_channel_loopback_live'));
    expect(driver, contains('LocalIrcServer'));
    expect(driver, contains('l3_irc_set_state'));
    expect(driver, contains("'localAddOverride': true"));
    expect(driver, contains('irc_channel_dialog_channel_field'));
    expect(runner, contains('irc_join_channel_real_controls'));
    expect(runner, contains('irc_join_channel_loopback_live'));
    expect(runner, contains("'MCP_BINDING': 'skill'"));
    expect(runner, contains("'TOXEE_L3_TEST': 'true'"));
    expect(runner, contains("'TOXEE_BUILD_ONLY': '1'"));
    expect(sidebar, contains('const bool _showApplicationsEntry = true;'));
    expect(
      runner,
      contains("'rui-app-entry-extra': ['sweep_app_entry_extra']"),
    );
  });

  test('IRC real-UI add-channel path uses L3 local override seam', () {
    final debugTools = File(
      'lib/ui/testing/l3_debug_tools.dart',
    ).readAsStringSync();
    final applicationsPage = File(
      'lib/ui/applications/applications_page.dart',
    ).readAsStringSync();

    expect(debugTools, contains('debugL3IrcLocalAddOverrideEnabled'));
    expect(debugTools, contains('cleanupGroupState(groupId)'));
    expect(applicationsPage, contains('debugL3IrcLocalAddOverrideEnabled'));
    expect(applicationsPage, contains('Prefs.addIrcChannel(channel)'));
  });

  test('IRC live real-UI path uses local server without local override', () {
    final driver = File(
      'tool/mcp_test/drive_real_ui_pair_app_entry_extra.dart',
    ).readAsStringSync();

    final liveScenario = RegExp(
      r"Future<bool> _aeeIrcJoinChannelLoopbackLive[\s\S]*?^}\n",
      multiLine: true,
    ).firstMatch(driver)?.group(0);

    expect(liveScenario, isNotNull);
    expect(liveScenario, contains('LocalIrcServer.start'));
    expect(liveScenario, contains('applications_irc_save_config_button'));
    expect(liveScenario, contains('applications_irc_install_button'));
    expect(liveScenario, contains('waitForCommandContaining'));
    expect(liveScenario, isNot(contains("'localAddOverride': true")));
  });

  test('macOS debug runner bundles IRC OpenSSL dependencies', () {
    final runner = File('run_toxee.sh').readAsStringSync();

    expect(runner, contains('libssl\\..*dylib'));
    expect(runner, contains('libcrypto\\..*dylib'));
    expect(runner, contains('"openssl@3"'));
    expect(runner, contains(r'@loader_path/$crypto_name'));
    expect(runner, contains(r'$APP_EXE_DIR/$ssl_name'));
  });
}
