#!/usr/bin/env python3
"""Cross-file source-text contracts (a lint, NOT a test suite).

Why this file exists
--------------------
Several files under `test/` used to do this:

    final src = File('lib/…').readAsStringSync();
    expect(src, contains('key: UiKeys.chatSendButton'));

That executes **zero** lines of product code. It contributes nothing to
coverage, it breaks on a rename or a reflow, and — critically — it proves the
wrong thing: `key: UiKeys.chatInputTextField` appearing in a source file is not
evidence that the Key is actually attached to a widget at runtime. Those
assertions are *lints* wearing a test costume, and mixing them into
`flutter test` dilutes the signal of the real behaviour tests.

Anything that genuinely can be proven by rendering a widget was converted into a
real behaviour test (see `test/ui/testing/message_surface_anchor_test.dart` and
`test/ui/testing/settings_anchor_test.dart`, which import `UiKeys` and assert on
the real constants). What is left here is the residue that cannot be:

  * `ui-anchors` — automation anchors that live in `third_party/chat-uikit-flutter`
    (a vendored fork we cannot pump in a unit test) or on widgets that require a
    fully booted session to render.
  * `harness-registration` — bookkeeping inside `tool/mcp_test/**` driver scripts
    and campaign markdown: "scenario X is registered in runner Y". Those are
    external processes; a unit test can only ever grep them.

Usage
-----
    python3 tool/check_source_contracts.py             # all groups
    python3 tool/check_source_contracts.py ui-anchors  # one group
    python3 tool/check_source_contracts.py --list

Exit code 1 on any violation. Run from the repository root.

NOTE FOR MAINTAINERS: this script is wired into `.github/workflows/analyze.yml`
next to the `check_complexity.dart` step, so update the contracts whenever the
corresponding UI anchor or harness registration changes.
"""

from __future__ import annotations

import os
import re
import sys

# --------------------------------------------------------------------------
# tiny assertion helpers — each records a failure instead of raising, so one
# run reports every violation rather than only the first.
# --------------------------------------------------------------------------

_failures: list[str] = []


def _fail(msg: str) -> None:
    _failures.append(msg)


def read(path: str) -> str | None:
    if not os.path.isfile(path):
        _fail(f'{path}: file is missing (moved or deleted?)')
        return None
    with open(path, encoding='utf-8', errors='replace') as handle:
        return handle.read()


def want(source: str | None, needle: str, path: str, label: str) -> None:
    """`path` must contain `needle`."""
    if source is None:
        return
    if needle not in source:
        _fail(f'{path}: missing {label} -> {needle!r}')


def reject(source: str | None, needle: str, path: str, label: str) -> None:
    """`path` must NOT contain `needle` (stale marker / regressed behaviour)."""
    if source is None:
        return
    if needle in source:
        _fail(f'{path}: stale {label} -> {needle!r}')


# --------------------------------------------------------------------------
# group: ui-anchors
# Ex test/ui/testing/message_surface_anchor_source_test.dart and
#    test/ui/testing/settings_anchor_source_test.dart (both of which had zero
#    `test()` declarations — they threw StateError from a bare `main()`).
# Only the assertions that cannot be replaced by a rendered-widget test kept.
# --------------------------------------------------------------------------

FORK = 'third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib'


def check_ui_anchors() -> None:
    # Fork widgets: the vendored UIKit fork cannot be pumped from a toxee unit
    # test, so the only available check is that the anchor key literal survives
    # the next patch re-application (see doc/operations/PATCH_MAINTENANCE.md).
    fork_contracts = [
        (
            f'{FORK}/tencent_cloud_chat_message_list_view/message_row/'
            'tencent_cloud_chat_message_row_container.dart',
            "ValueKey('message_list_item:",
            'per-message row key',
        ),
        (
            f'{FORK}/tencent_cloud_chat_message_widgets/menu/'
            'tencent_cloud_chat_message_item_with_menu.dart',
            "ValueKey('message_menu_item:$action')",
            'message menu item key factory',
        ),
        (
            f'{FORK}/tencent_cloud_chat_message_widgets/menu/'
            'tencent_cloud_chat_message_item_with_menu_container.dart',
            "ValueKey('confirm_dialog_primary_button')",
            'message delete confirm primary button key',
        ),
        (
            f'{FORK}/tencent_cloud_chat_message_input/mobile/'
            'tencent_cloud_chat_message_input_mobile.dart',
            "ValueKey('emoji_panel_button')",
            'mobile emoji panel toggle key',
        ),
        (
            f'{FORK}/common/for_desktop/image_tools.dart',
            "ValueKey('desktop_send_image_confirm_button')",
            'desktop pasted-image confirm button key',
        ),
    ]
    for path, needle, label in fork_contracts:
        want(read(path), needle, path, label)

    # First-party call sites. These widgets only exist inside a booted session
    # (message surface) or the settings shell, which the real-UI harness drives
    # end to end; the grep is the cheap early-warning that a refactor dropped
    # the anchor.
    attachment_contracts = [
        (
            'lib/ui/home_page_bootstrap.dart',
            'key: UiKeys.chatInputTextField',
            'messageInputBuilder chat-input wrapper',
        ),
        (
            'lib/ui/settings/settings_page_build.dart',
            'key: UiKeys.settingsCopyToxIdButton',
            'settings copy button attachment',
        ),
        (
            'lib/ui/settings/settings_page_widgets.dart',
            'key: UiKeys.settingsSetPasswordButton',
            'settings set-password button attachment',
        ),
        (
            'lib/ui/settings/settings_page_widgets.dart',
            'key: UiKeys.settingsLogoutButton',
            'settings logout button attachment',
        ),
        (
            'lib/ui/settings/settings_page.dart',
            'key: UiKeys.settingsAccountSwitchCancelButton',
            'settings account-switch cancel attachment',
        ),
        (
            'lib/ui/settings/settings_page.dart',
            'key: UiKeys.settingsAccountSwitchConfirmButton',
            'settings account-switch confirm attachment',
        ),
        (
            'lib/ui/settings/settings_page.dart',
            'key: UiKeys.settingsLogoutConfirmButton',
            'settings logout confirm attachment',
        ),
    ]
    cache: dict[str, str | None] = {}
    for path, needle, label in attachment_contracts:
        if path not in cache:
            cache[path] = read(path)
        want(cache[path], needle, path, label)


# --------------------------------------------------------------------------
# group: harness-registration
# Ex test/ui/testing/p3_writable_source_test.dart (zero `test()`),
#    test/ui/testing/irc_real_ui_source_test.dart and
#    test/ui/testing/real_ui_avatar_restore_coverage_source_test.dart.
# All three only ever grepped `tool/mcp_test/**` driver scripts and campaign
# markdown, i.e. they asserted that an out-of-process harness is wired up.
# --------------------------------------------------------------------------

MCP = 'tool/mcp_test'


def check_harness_registration() -> None:
    _p3_writable()
    _irc_real_ui()
    _avatar_and_restore_coverage()
    _mobile_shell_exit_contract()


def _p3_writable() -> None:
    driver_path = f'{MCP}/drive_real_ui_pair.dart'
    runner_path = f'{MCP}/fixture_c_unified_runner.dart'
    p3_path = f'{MCP}/drive_real_ui_pair_p3.dart'

    driver = read(driver_path)
    runner = read(runner_path)
    p3 = read(p3_path)

    want(driver, "part 'drive_real_ui_pair_p3.dart';", driver_path,
         'P3 writable driver part include')
    want(driver, "scenario == 'sweep_p3_writable'", driver_path,
         'sweep_p3_writable dispatch')
    want(driver, '_isP3WritableCaseScenario(scenario)', driver_path,
         'P3 writable standalone dispatch')

    want(p3, 'message_burst_perf', p3_path,
         'message_burst_perf scenario implementation')
    want(p3, 'RUI_BURST_PERF_COUNT', p3_path, 'parametric burst count env')
    want(p3, 'RUI_BURST_PERF_NONBLOCKING_MS', p3_path,
         'non-blocking performance threshold env')
    want(p3, 'NONBLOCKING', p3_path, 'non-blocking threshold log')

    want(runner, "'sweep_p3_writable'", runner_path,
         'sweep_p3_writable runner registration')
    want(runner, "'message_burst_perf'", runner_path,
         'message_burst_perf runner registration')
    want(runner, "'rui-p3-writable': ['sweep_p3_writable']", runner_path,
         'rui-p3-writable campaign registration')


def _mobile_shell_exit_contract() -> None:
    path = f'{MCP}/drive_real_ui_pair_mobile_shell.dart'
    source = read(path)
    want(
        source,
        'if (passed == 0 && skipped != 0) return 75;',
        path,
        'all-skipped mobile shell sweep result',
    )


def _irc_real_ui() -> None:
    driver_path = f'{MCP}/drive_real_ui_pair_app_entry_extra.dart'
    runner_path = f'{MCP}/fixture_c_unified_runner.dart'

    driver = read(driver_path)
    runner = read(runner_path)

    # 1. scenario is wired into app-entry automation
    for needle in (
        'irc_join_channel_real_controls',
        'irc_join_channel_loopback_live',
        'LocalIrcServer',
        'l3_irc_set_state',
        "'localAddOverride': true",
        'irc_channel_dialog_channel_field',
    ):
        want(driver, needle, driver_path, 'IRC app-entry wiring')
    for needle in (
        'irc_join_channel_real_controls',
        'irc_join_channel_loopback_live',
        "'MCP_BINDING': 'skill'",
        "'TOXEE_L3_TEST': 'true'",
        "'TOXEE_BUILD_ONLY': '1'",
        "'rui-app-entry-extra': ['sweep_app_entry_extra']",
    ):
        want(runner, needle, runner_path, 'IRC runner registration')

    sidebar_path = 'lib/ui/settings/sidebar.dart'
    want(read(sidebar_path), 'const bool _showApplicationsEntry = true;',
         sidebar_path, 'Applications entry feature flag')

    # 2. add-channel path uses the L3 local override seam
    debug_tools_path = 'lib/ui/testing/l3_debug_tools.dart'
    applications_path = 'lib/ui/applications/applications_page.dart'
    debug_tools = read(debug_tools_path)
    applications = read(applications_path)
    want(debug_tools, 'debugL3IrcLocalAddOverrideEnabled', debug_tools_path,
         'L3 IRC local-add override flag')
    want(debug_tools, 'cleanupGroupState(groupId)', debug_tools_path,
         'L3 IRC group cleanup')
    want(applications, 'debugL3IrcLocalAddOverrideEnabled', applications_path,
         'L3 IRC local-add override consumption')
    want(applications, 'Prefs.addIrcChannel(channel)', applications_path,
         'IRC channel persistence')

    # 3. the LIVE scenario must use the local server WITHOUT the local override
    if driver is not None:
        live = re.search(
            r'Future<bool\??> _aeeIrcJoinChannelLoopbackLive[\s\S]*?^\}\n',
            driver,
            re.MULTILINE,
        )
        if live is None:
            _fail(f'{driver_path}: _aeeIrcJoinChannelLoopbackLive not found')
        else:
            body = live.group(0)
            for needle in (
                'LocalIrcServer.start',
                'applications_irc_save_config_button',
                'applications_irc_install_button',
                'waitForCommandContaining',
            ):
                want(body, needle, driver_path,
                     'IRC loopback-live scenario body')
            reject(body, "'localAddOverride': true", driver_path,
                   'IRC loopback-live must not short-circuit via the override')

    # 4. macOS debug runner bundles the IRC OpenSSL dependencies
    runner_sh_path = 'run_toxee.sh'
    runner_sh = read(runner_sh_path)
    for needle in (
        r'libssl\..*dylib',
        r'libcrypto\..*dylib',
        '"openssl@3"',
        '@loader_path/$crypto_name',
        '$APP_EXE_DIR/$ssl_name',
    ):
        want(runner_sh, needle, runner_sh_path, 'IRC OpenSSL bundling')


def _scenario_block(source: str, scenario: str, next_scenario: str,
                    path: str) -> str | None:
    start_marker = f"if (scenario == '{scenario}') {{"
    end_marker = f"if (scenario == '{next_scenario}') {{"
    start = source.find(start_marker)
    if start < 0:
        _fail(f'{path}: missing dispatch block for {scenario}')
        return None
    end = source.find(end_marker, start + len(start_marker))
    if end <= start:
        _fail(f'{path}: dispatch block for {scenario} is not followed by '
              f'{next_scenario}')
        return None
    return source[start:end]


def _avatar_and_restore_coverage() -> None:
    campaign_path = f'{MCP}/REAL_UI_GATES.md'
    profile_path = f'{MCP}/drive_real_ui_pair_profile.dart'
    login_path = f'{MCP}/drive_real_ui_pair_login.dart'
    pair_path = f'{MCP}/drive_real_ui_pair.dart'

    campaign = read(campaign_path)
    profile = read(profile_path)
    login = read(login_path)
    pair = read(pair_path)

    if campaign is not None:
        current = campaign.split('## Batch log')[0]
        for needle, label in (
            ('| 19 | profile_avatar_picker_opens | 1i | S79 |',
             'canonical avatar picker row'),
            ('| 20 | profile_avatar_select_default_applies | 1i | S79 |',
             'canonical avatar apply row'),
            ('| 26 | login_restore_entry_opens | 1i | S9/S71 |',
             'canonical restore row'),
            ('8/8 runnable, 0 SKIP', 'profile total'),
            ('9/9 runnable,\n0 SKIP', 'login total'),
        ):
            want(current, needle, campaign_path, label)
        reject(current, 'SKIP(no in-app avatar picker', campaign_path,
               'canonical avatar SKIP')
        reject(current, 'SKIP(native-picker-only', campaign_path,
               'canonical native-picker SKIP')
        want(campaign, 'sweep_profile 8/0/0 (was 6/0/2skip)', campaign_path,
             'avatar conversion log')
        want(campaign, 'sweep_login 9/0/0 (was 8/0/1skip)', campaign_path,
             'restore conversion log')

    want(profile, "'profile_avatar_edit_button'", profile_path,
         'real avatar control')
    want(profile, "'l3_set_avatar_pick_path'", profile_path,
         'avatar fixed picker-path seam')
    want(profile, "['selfAvatarPath']", profile_path, 'avatar assertion')
    reject(profile, 'SKIP(no-in-app-avatar-surface)', profile_path,
           'avatar driver SKIP reason')
    want(profile,
         'return failed == 0 && unexpectedSkipped == 0 ? 0 : 1;',
         profile_path, 'profile sweep rejects unexpected skips')

    want(login, "'login_page_restore_from_tox_file'", login_path,
         'real restore control')
    want(login, "'l3_set_account_import_pick_path'", login_path,
         'restore fixed picker-path seam')
    want(login, "'login_page_error_banner'", login_path,
         'restore error assertion')
    reject(login, 'SKIP(native-picker-only)', login_path,
           'restore driver SKIP reason')
    want(login, 'return failed == 0 && skipped == 0 ? 0 : 1;', login_path,
         'login sweep hard-fails skips')

    if pair is not None:
        for scenario, helper, nxt in (
            ('profile_avatar_picker_opens', '_profileAvatarPickerOpens',
             'profile_avatar_select_default_applies'),
            ('profile_avatar_select_default_applies',
             '_profileAvatarSelectDefaultApplies', 'sweep_login'),
        ):
            block = _scenario_block(pair, scenario, nxt, pair_path)
            if block is None:
                continue
            if block.count(helper) != 1:
                _fail(f'{pair_path}: {scenario} must evaluate {helper} exactly '
                      f'once (found {block.count(helper)})')
            want(block, f'final result = await {helper}(a);', pair_path,
                 f'{scenario} result capture')
            want(block, 'true => 0,', pair_path, f'{scenario} PASS mapping')
            want(block, 'false => 1,', pair_path, f'{scenario} FAIL mapping')
            want(block, 'null => 75,', pair_path, f'{scenario} SKIP mapping')


GROUPS = {
    'ui-anchors': check_ui_anchors,
    'harness-registration': check_harness_registration,
}


def main(argv: list[str]) -> int:
    if '--list' in argv:
        for name in GROUPS:
            print(name)
        return 0
    selected = [a for a in argv if not a.startswith('-')]
    unknown = [s for s in selected if s not in GROUPS]
    if unknown:
        print(f'unknown group(s): {", ".join(unknown)}; '
              f'known: {", ".join(GROUPS)}', file=sys.stderr)
        return 2
    if not os.path.isdir('lib') or not os.path.isdir('tool'):
        print('[source-contracts] run from the repository root', file=sys.stderr)
        return 2

    for name in (selected or list(GROUPS)):
        GROUPS[name]()

    if _failures:
        for failure in _failures:
            print(f'[source-contracts] {failure}', file=sys.stderr)
        print(f'[source-contracts] {len(_failures)} violation(s)',
              file=sys.stderr)
        return 1
    print('[source-contracts] OK')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
