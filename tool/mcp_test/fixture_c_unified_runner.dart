// Unified Fixture C / real-UI two-process runner.
//
// The first layer is intentionally hermetic: manifest parsing, filtering,
// grouping, validation, and dry-run command planning do not launch Toxee. Live
// execution builds on that same plan so the expensive two-process work matches
// the CI-checkable contract.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const _usage = '''
usage: fixture_c_unified_runner.dart [--tier=non-media|media|all]
       [--class=2proc-l3|2proc-ui] [--id=<script>[,<script>]]
       [--real-ui-scenario=<name>[,<name>]]
       [--real-ui-campaign=<name>[,<name>]] [--include-destructive]
       [--real-ui-platform=macos|ios|android|windows]
       [--list|--plan-json|--dry-run|--validate-only]
       [--list-real-ui-campaigns]

Hermetic modes:
  --list               print filtered manifest entries
  --plan-json          print the grouped execution plan as JSON
  --dry-run            print the shell commands the live runner would execute
  --validate-only      validate manifest/planning invariants

Live execution:
  (no mode flags)      execute the grouped plan

Real-UI helpers:
  --real-ui-scenario=handshake,message
                       narrow the 2proc-ui plan to the selected scenario list
                       in the exact order provided
  --real-ui-campaign=all-current
                       expand a named merged campaign of compatible real-UI
                       scenarios
  --list-real-ui-campaigns
                        print the built-in reusable real-UI campaign catalog

Platform support (all four have A/B real-UI pair launchers wired in):
  macos                 launch_fixture_c_pair.sh (run on the Mac)
  ios                   launch_ios_fixture_c_pair.sh (two Simulators on the Mac)
  android               launch_android_fixture_c_pair.sh (run on a host with adb
                        + two devices/emulators; the loopback IRC server is made
                        reachable via `adb reverse`)
  windows               launch_windows_fixture_c_pair.ps1 (run the runner ON the
                        Windows host; two flutter-run instances share its loopback)
  Note: the irc_join_channel_loopback_live JOIN needs the native libirc_client
  library (bundled on macOS); irc_join_channel_real_controls is pure-Dart and
  portable. See tool/mcp_test/REAL_UI_TWO_PROCESS.md.
''';

const _manifestPath = 'tool/mcp_test/fixture_c_manifest.json';
const _pairManifest = 'tool/mcp_test/fixtures/paired_for_e2e_manifest.json';
const _macosPairJson = 'tool/mcp_test/.multi_instance_runtime/pair.json';
const _iosPairJson = 'tool/mcp_test/.ios_runtime/pair.json';
const _androidPairJson = 'tool/mcp_test/.android_runtime/pair.json';
const _windowsPairJson = 'tool/mcp_test/.windows_runtime/pair.json';
const _defaultRealUiNickA = 'RealUiAlice';
const _defaultRealUiNickB = 'RealUiBob';

/// Fixed loopback IRC port for the Android real-UI platform. The Android app
/// runs on a device/emulator, so the host-side LocalIrcServer (started by the
/// driver) is only reachable through `adb reverse tcp:<port> tcp:<port>`, which
/// the Android pair launcher sets up BEFORE the driver picks a port — hence a
/// known fixed value rather than an ephemeral one. The runner injects this into
/// both the launch env (so the launcher reverses it) and the driver env (so
/// `LocalIrcServer.startFromEnv` binds it). macOS / iOS / Windows share the host
/// loopback and keep the ephemeral default (no reverse-forward needed).
const _androidIrcLoopbackPort = '16667';

/// Per-platform wiring for the real-UI A/B pair: where the runtime pair.json
/// lands, which launch/stop scripts produce + tear it down, how those scripts
/// are invoked (bash vs PowerShell), whether the runner builds the app on the
/// host before launching, and the fixed IRC loopback port (Android only). This
/// replaces the scattered `_realUiPlatform == 'ios' ? ... : ...` branches so a
/// new platform is one map entry.
class _RealUiPlatformConfig {
  const _RealUiPlatformConfig({
    required this.pairJson,
    required this.launchScript,
    required this.stopScript,
    required this.usesPowershell,
    required this.prebuildOnHost,
    this.ircLoopbackPort,
  });

  /// Relative path to the runtime pair.json the launcher writes / the runner +
  /// driver read (ws_uri / pid / nickname per instance).
  final String pairJson;
  final String launchScript;
  final String stopScript;

  /// PowerShell `.ps1` launch/stop scripts (Windows) are invoked via
  /// `powershell -ExecutionPolicy Bypass -File <script>`; bash `.sh` scripts run
  /// directly. Governs both the symbolic dry-run/plan-json output and execution.
  final bool usesPowershell;

  /// macOS builds the app bundle once via `run_toxee.sh` before the pair launch;
  /// the iOS/Android/Windows launch scripts self-build, so the runner skips it.
  final bool prebuildOnHost;

  /// Fixed IRC loopback port for `adb reverse` (Android). Null on the
  /// same-host-loopback platforms (macOS/iOS/Windows), which keep ephemeral.
  final String? ircLoopbackPort;
}

const _realUiPlatformConfigs = <String, _RealUiPlatformConfig>{
  'macos': _RealUiPlatformConfig(
    pairJson: _macosPairJson,
    launchScript: 'tool/mcp_test/launch_fixture_c_pair.sh',
    stopScript: 'tool/mcp_test/stop_fixture_c_pair.sh',
    usesPowershell: false,
    prebuildOnHost: true,
  ),
  'ios': _RealUiPlatformConfig(
    pairJson: _iosPairJson,
    launchScript: 'tool/mcp_test/launch_ios_fixture_c_pair.sh',
    stopScript: 'tool/mcp_test/stop_ios_fixture_c_pair.sh',
    usesPowershell: false,
    prebuildOnHost: false,
  ),
  'android': _RealUiPlatformConfig(
    pairJson: _androidPairJson,
    launchScript: 'tool/mcp_test/launch_android_fixture_c_pair.sh',
    stopScript: 'tool/mcp_test/stop_android_fixture_c_pair.sh',
    usesPowershell: false,
    prebuildOnHost: false,
    ircLoopbackPort: _androidIrcLoopbackPort,
  ),
  'windows': _RealUiPlatformConfig(
    pairJson: _windowsPairJson,
    launchScript: 'tool/mcp_test/launch_windows_fixture_c_pair.ps1',
    stopScript: 'tool/mcp_test/stop_windows_fixture_c_pair.ps1',
    usesPowershell: true,
    prebuildOnHost: false,
  ),
};

_RealUiPlatformConfig get _realUiConfig =>
    _realUiPlatformConfigs[_realUiPlatform] ?? _realUiPlatformConfigs['macos']!;

const _validTiers = {'non-media', 'media', 'all'};
const _validClasses = {'2proc-l3', '2proc-ui'};
const _validBases = {'paired_for_e2e', 'fresh', 'real-ui'};
const _validRealUiPlatforms = {'macos', 'ios', 'android', 'windows'};
// All four platforms now have A/B pair launchers wired into this runner, so this
// blocker map is empty. It is kept as the seam for declaring a future platform
// "known but not yet wired" (a non-empty entry makes `--real-ui-platform=<name>`
// fail with the stated reason) without re-introducing scattered special-cases.
const _unsupportedRealUiPlatforms = <String, String>{};
String _realUiPlatform = 'macos';

/// Exit code a real-UI driver returns when a scenario is a SKIP (its surface
/// genuinely does not exist on this platform — e.g. the Batch-2 avatar cases,
/// whose self-profile avatar tap opens a native NSOpenPanel with no in-app
/// picker grid). Distinct from 0 (PASS), non-zero failures, and 78 (BLOCKED) so
/// the runner does not tally a SKIP as a PASS. EX_NOPERM-adjacent; arbitrary but
/// reserved here.
const _realUiSkipExitCode = 75;
const _validRealUiScenarios = {
  'handshake',
  'message',
  'message_burst',
  'group_message',
  'group_create',
  'group_profile_open',
  'group_rename',
  'group_search',
  'group_add_member_open',
  'group_add_member_picker',
  'group_conversation_menu',
  'group_menu_pin_unpin',
  'group_menu_mark_read',
  'group_menu_mark_read_unread',
  'group_menu_delete_confirm',
  'group_clear_history',
  'group_clear_preserves_pin',
  'group_burst',
  'group_member_list',
  'conference_message',
  'handshake_detail',
  'decline',
  'custom_message',
  'call_voice',
  'call_reject',
  // Batch 1 — settings sweep 2 (single-instance, no-friend). The 12 cases are
  // individually runnable; sweep_settings2 chains them on one launch.
  'sweep_settings2',
  'sweep_ios_settings_main',
  'settings_surface_sections',
  'settings_theme_dark',
  'settings_theme_light_back',
  'settings_locale_zh_roundtrip',
  'settings_download_limit_edit',
  'settings_bootstrap_mode_cycle',
  'settings_bootstrap_manual_add_node',
  'settings_bootstrap_manual_remove_node',
  'settings_autologin_toggle_hard',
  'settings_notifsound_toggle_hard',
  'settings_password_mismatch_error',
  'settings_logout_cancel',
  // Batch 2 — self profile (single-instance, no-friend). The 8 cases are
  // individually runnable; sweep_profile chains them on one launch. Cases 19/20
  // (avatar) are SKIPs inside the sweep — no in-app avatar picker surface.
  'sweep_profile',
  'profile_open_sidebar_avatar',
  'profile_edit_toggle_roundtrip',
  'profile_edit_nickname_persists',
  'profile_edit_status_persists',
  'profile_copy_toxid_snackbar',
  'profile_qr_copy',
  'profile_avatar_picker_opens',
  'profile_avatar_select_default_applies',
  // Batch 3 — login / register (single-instance, no-friend). The 9 cases are
  // individually runnable; sweep_login chains them on one launch. Case 26
  // (login_restore_entry_opens) is a SKIP inside the sweep — the restore card
  // opens the native NSOpenPanel with no in-app pre-picker surface.
  'sweep_login',
  'login_register_open_back',
  'login_account_card_renders',
  'login_restore_entry_opens',
  'register_empty_nickname_error',
  'register_password_mismatch_error',
  'register_password_strength_flips',
  'login_password_wrong_error',
  'login_password_correct_unlocks',
  'account_switch_second_account',
  // Batch 4 — contacts / friend profile (TWO-PROCESS). sweep_contacts chains
  // all 15 on one launch: required=no-friend (it does its OWN handshake) and
  // result=no-friend (case 44 deletes the friend on both sides). The individual
  // cases are runnable too — the add-friend dialog guards (30/31/32) + subtab
  // cycle (34) are no-friend; the friendship-dependent cases (33, 35–43)
  // require/leave a friendship; 44 leaves no-friend.
  'sweep_contacts',
  'add_friend_dialog_esc_close',
  'add_friend_invalid_id_error',
  'add_friend_self_id_guard',
  'add_friend_duplicate_guard',
  'contacts_subtabs_cycle',
  'contacts_row_opens_friend_profile',
  'friendprof_send_message_tile',
  'friendprof_pin_toggle',
  'friendprof_block_unblock',
  'friendprof_mute_toggle_regression',
  'friendprof_remark_edit_persists',
  'friendprof_clear_history',
  'blocked_list_unblock_row',
  'contact_search_filter_clear',
  'friendprof_delete_friend_confirm',
  // Batch 5 — conversation list C2C (TWO-PROCESS). sweep_conv chains all 10 on
  // one launch: required=no-friend (it does its OWN handshake) and result=friends
  // (the C2C delete removes only the conversation ROW, not the friend; the sweep
  // re-seeds a row, so the launch ends friends). All cases are friendship-
  // dependent (B's sends seed real unread/preview/history). Case 53 (presence) is
  // a SKIP inside the sweep — the friend online flag has no ungated setter and
  // flipping it needs stopping B's process (forbidden by launch-reuse).
  'sweep_conv',
  'conv_menu_surface_c2c',
  'conv_pin_unpin_reorders',
  'conv_mark_read_two_proc',
  'conv_delete_confirm_c2c',
  'conv_clear_history_c2c',
  'conv_clear_preserves_pin_c2c',
  'conv_unread_badge_bump_clear',
  'conv_preview_updates_on_inbound',
  'conv_presence_dot_flips',
  'conv_search_filter_clear',
  // Batch 6 — chat surface C2C (TWO-PROCESS). sweep_chat chains all 16 on one
  // launch: required=no-friend (it does its OWN handshake) and result=friends
  // (no case deletes the friend; the sweep ends with the C2C conversation alive).
  // All cases are friendship-dependent (B's real sends seed history; l3 seeding
  // delivers inbound media). Case 62 (reply) stays a legacy SKIP in this +94
  // sweep; the P1/P2/P3 campaign covers the newly driveable reply flow as
  // `reply_quote_real`. Case 68 (offline-pending) is a SKIP — the
  // pending→deliver flip is un-seedable on a reused launch (no ungated offline
  // seam; stopping B is forbidden).
  'sweep_chat',
  'chat_open_from_row',
  'chat_multiline_send',
  'chat_long_text_send',
  'chat_emoji_insert_send',
  'chat_sticker_panel_send',
  'chat_msg_menu_surface',
  'chat_copy_message_clipboard',
  'chat_reply_quote_roundtrip',
  'chat_forward_to_other_conv',
  'chat_delete_message_gone',
  'chat_history_scroll_load_more',
  'chat_inbound_while_scrolled_up',
  'chat_header_opens_profile',
  'chat_offline_pending_then_deliver',
  'chat_image_bubble_open_preview',
  'chat_file_bubble_present_open',
  // Focused C2C expansion — safe-path real controls not covered by the main
  // chat/conv sweeps: search entry, cancel branches, and profile send-back.
  'sweep_c2c_extra',
  'c2c_global_search_contact_opens_chat',
  'c2c_conv_delete_cancel',
  'c2c_profile_clear_history_cancel',
  'c2c_delete_friend_cancel',
  'c2c_header_profile_send_back',
  // Optimized orchestration bundles — reuse existing sweeps in one app launch
  // and, where possible, one A<->B friendship.
  'sweep_single_app_optimized',
  'sweep_c2c_optimized',
  'sweep_friendship_optimized',
  'sweep_optimized_current',
  // Batch 7 — group / conference (MIXED single-instance + two-process).
  // sweep_group2 chains all 14 on one launch: required=no-friend (it does its
  // OWN handshake) and result=friends (no case deletes the FRIEND — case 78
  // kicks B from the group, case 75 leaves the group, but the A<->B friendship
  // stays intact). The single-instance create cases (71/72/82) are no-friend;
  // the rest of the single-instance group/conference cases create their own
  // group standalone (no friendship needed); the 2p cases (77/78/79/81) need a
  // friendship (the standalone dispatch establishes it + joins B).
  'sweep_group2',
  'group_create_cancel',
  'group_create_type_selector_surface',
  'group_rename_updates_header',
  'group_profile_members_entry',
  'group_mute_toggle',
  'group_profile_clear_history',
  'group_add_member_full_join',
  'group_member_list_scroll',
  'group_unread_badge_two_proc',
  'group_kick_member_ui',
  'group_leave_via_profile_confirm',
  'conf_create_dialog_surface',
  'conf_row_menu_surface',
  'conf_member_list_renders',
  // Batch 8 — calls / misc (FINAL batch; MIXED two-process + single-instance).
  // sweep_calls_misc chains all 10 on one launch: required=no-friend (it does
  // its OWN handshake) and result=friends (no case deletes the friend; the
  // calls end idle, the conversation row stays alive). The call cases + the
  // chat-open misc cases (91/92/94) are friendship-dependent (the standalone
  // dispatch establishes it); window_resize_responsive is single-instance and
  // is a SKIP-able case (exit 75) when the raw-launched window refuses resize.
  'sweep_calls_misc',
  'call_video_accept_hangup',
  'call_mute_toggle_incall',
  'call_camera_toggle_incall',
  'call_missed_record_row',
  'call_callee_hangup',
  'call_record_bubble_renders',
  'home_tabs_cycle_state_retained',
  'theme_switch_chat_open',
  'search_chat_history_window_open',
  'window_resize_responsive',
  // P1/P2/P3 campaign Batch II — single-instance account/locale/conference
  // cases (sweep_p1_single chains all 5 on one launch; each is individually
  // dispatchable; the delete case is DESTRUCTIVE to its own throwaway account
  // and runs last in the sweep).
  'sweep_p1_single',
  'zh_locale_page_walk',
  'conference_rename_leave',
  'settings_switch_account_entry',
  'account_card_management_menu',
  'account_delete_full_flow',
  // P1/P2/P3 campaign Batch III — two-process chat/conv octet. sweep_p1_chat
  // chains all 8 on one launch: required=no-friend (it does its OWN handshake)
  // and result=friends (no case deletes the friend; the end-guard re-seeds a
  // row). Three cases are NEGATIVE product-gap pins decided by verify-first
  // code reading: read_receipt_double_tick, draft_restore_on_conv_switch, and
  // typing_indicator_render.
  'sweep_p1_chat',
  'chat_recall_message',
  'read_receipt_double_tick',
  'forward_to_group_target',
  'draft_restore_on_conv_switch',
  'typing_indicator_render',
  'unread_badge_total_sidebar',
  'search_empty_state',
  'image_preview_open_hardened',
  // P1/P2/P3 campaign Batch IV — relaunch + profile-call quartet. The sweep
  // internally restarts instances, so the runner treats its result as
  // relaunch-dirty and relaunches before the next external scenario.
  'sweep_p1_relaunch',
  'relaunch_history_autologin',
  'offline_pending_relaunch',
  'call_from_profile_tiles',
  'group_join_by_id_real_ui',
  // P1 extra — feasible follow-ups from the inventory's "still add" bucket
  // that are driveable in the current macOS real-app harness.
  'sweep_p1_extra',
  'ar_rtl_page_walk',
  'keyboard_global_search_shortcut',
  // App-entry extra — §7.5.1 high-frequency single-instance real-control cases
  // (drive only A): new-entry popup, add-friend paste, two desktop shortcuts,
  // register password-visibility toggle, login Import entry render-gate.
  'sweep_app_entry_extra',
  'new_entry_menu_surface',
  'add_friend_paste_clipboard',
  'keyboard_new_conversation_shortcut',
  'keyboard_open_settings_shortcut',
  'irc_join_channel_real_controls',
  'irc_join_channel_loopback_live',
  'register_password_visibility_toggle',
  'login_import_account_card_open',
  // Group @-mention — §7.5.1 two-process: real desktop mention panel + send.
  'sweep_group_mention',
  'group_at_member_send',
  'group_at_all_send',
  // Account/conference focused expansion — single-instance, real controls,
  // non-destructive assertions with cleanup-gated state.
  'sweep_account_conf_extra',
  'settings_switch_account_cancel',
  'login_account_delete_cancel',
  'settings_delete_account_cancel',
  'conference_profile_id_surface',
  'conference_profile_send_message_tile',
  'conference_search_result_opens',
  // Focused group/conference member-management expansion — real member-list
  // row menus, role action smoke, remove, and conference negative affordances.
  'sweep_group_conf_member_extra',
  'group_member_peer_menu_surface',
  'group_member_role_action_smoke',
  'group_member_remove_ui',
  'conference_member_peer_row_surface',
  'conference_member_role_remove_absent',
  // Highest-value follow-up additions: optimized-stable deep cases plus
  // standalone native-boundary guards.
  'sweep_c2c_deep_extra',
  'c2c_search_result_opens_target_message',
  'sweep_account_deep_extra',
  'account_multi_account_state_isolation',
  'sweep_group_conf_deep_extra',
  'group_member_role_reopen_surface',
  'group_member_remove_receiver_state',
  'conference_bidirectional_message_lifecycle',
  'sweep_native_boundary_guards',
  'attachment_entry_buttons_render',
  'restore_import_entry_guard',
  'notification_tap_routes_to_c2c',
  'network_disconnect_guard',
  'call_permission_denied_guard',
  'mobile_smoke_playbook_guard',
  // P1/P2/P3 campaign Batch V — P2 selector-backed cases. The sweep chains all
  // three and restarts B for presence; individual sticker/chip cases keep the
  // friendship, presence reports relaunch-dirty.
  'sweep_p2_keys',
  'sticker_face_cell_send',
  'new_messages_chip_tap',
  'presence_dot_relaunch',
  // P1/P2/P3 campaign Batch VI — C2C custom inbound seed + real Reply.
  'sweep_p2_reply',
  'reply_quote_real',
  // P1/P2/P3 campaign Batch VII — verify-first P2 trio outcome. Voice and tray
  // are documented as L3-pinned/product gaps; pasted-image is driveable.
  'sweep_p2_verify',
  'paste_image_into_composer',
  // P1/P2/P3 campaign Batch VIII — P3 writable subset. The live real-UI case is
  // message_burst_perf; ar_rtl_smoke runs as a hermetic Flutter test.
  'sweep_p3_writable',
  'message_burst_perf',
};
const _realUiCampaigns = <String, List<String>>{
  // Batch 1 — settings sweep 2 (the whole 12-case chain on one launch).
  'rui-settings2': ['sweep_settings2'],
  // Batch 2 — self profile (the whole 8-case chain on one launch; cases 19/20
  // are SKIPs inside the chain).
  'rui-profile': ['sweep_profile'],
  // Batch 3 — login / register (the whole 9-case chain on one launch; case 26
  // is a SKIP inside the chain — native picker only).
  'rui-login': ['sweep_login'],
  // Batch 4 — contacts / friend profile (the whole 15-case chain on one
  // TWO-PROCESS launch; one handshake at the top, delete-friend last so the
  // launch ends no-friend on both sides). Case 40 (remark) is a HARD gate that
  // is EXPECTED to FAIL live until the native setFriendInfo path is fixed.
  'rui-contacts': ['sweep_contacts'],
  // Batch 5 — conversation list C2C (the whole 10-case chain on one TWO-PROCESS
  // launch; one handshake at the top, delete-row near last + a re-seed so the
  // launch ends friends with a visible row). Case 53 (presence) is a SKIP inside
  // the chain — the friend online flag is un-seedable on a reused launch.
  'rui-conv': ['sweep_conv'],
  // Batch 6 — chat surface C2C (the whole 16-case chain on one TWO-PROCESS
  // launch; one handshake at the top, marks both accounts test to unblock l3
  // SEEDING). Cases 62 (reply) + 68 (offline) are SKIPs inside the chain.
  'rui-chat': ['sweep_chat'],
  // Focused C2C expansion: global search contact entry, non-destructive cancel
  // branches, and chat header -> profile -> chat round-trip.
  'rui-c2c-extra': ['sweep_c2c_extra'],
  // Optimized bundles: fewer app launches / account registrations / handshakes.
  'rui-single-app-optimized': ['sweep_single_app_optimized'],
  'rui-c2c-optimized': ['sweep_c2c_optimized'],
  'rui-friendship-optimized': ['sweep_friendship_optimized'],
  'rui-optimized-current': ['sweep_optimized_current'],
  // Batch 7 — group / conference (the whole 14-case chain on one TWO-PROCESS
  // launch; one handshake at the top, one shared PRIVATE group + one shared
  // conference created via the REAL add-group dialog and reused across cases.
  // Case 78 kicks B from the group, case 75 leaves the group, but the A<->B
  // friendship stays intact, so the launch ends FRIENDS.
  'rui-group2': ['sweep_group2'],
  // Batch 8 — calls / misc (the whole 10-case chain on one TWO-PROCESS launch;
  // one handshake at the top, the call state chained — voice block then video
  // block — then the misc cases. The friendship is never deleted, so the launch
  // ends FRIENDS. Case 93 (window-resize) is a SKIP inside the chain when the
  // raw-launched window won't size-script.
  'rui-calls-misc': ['sweep_calls_misc'],
  // P1/P2/P3 campaign Batch II — single-instance account/locale/conference
  // chain (one launch; drives only A).
  'rui-p1-single': ['sweep_p1_single'],
  // P1/P2/P3 campaign Batch III — two-process chat/conv octet (one launch;
  // one handshake at the top, both accounts marked test for l3 seeding and
  // revoked at the end; ends friends with a re-seeded row).
  'rui-p1-chat': ['sweep_p1_chat'],
  // P1/P2/P3 campaign Batch IV — relaunch + profile-call quartet. The sweep
  // restarts one peer inside the driver, then reports relaunch-dirty so the
  // next campaign starts from a clean pair launch.
  'rui-p1-relaunch': ['sweep_p1_relaunch'],
  // P1 extra — single-instance Arabic real-app locale walk + keyboard global
  // search shortcut flow.
  'rui-p1-extra': ['sweep_p1_extra'],
  // §7.5.1 app-entry extra — high-frequency single-instance real-control cases.
  'rui-app-entry-extra': ['sweep_app_entry_extra'],
  // §7.5.1 group @-mention — two-process real desktop mention panel.
  'rui-group-mention': ['sweep_group_mention'],
  // Focused account-management + conference expansion.
  'rui-account-conf-extra': ['sweep_account_conf_extra'],
  // Focused group/conference member role/remove expansion.
  'rui-group-conf-member-extra': ['sweep_group_conf_member_extra'],
  // Highest-value optimized-stable follow-ups.
  'rui-c2c-deep-extra': ['sweep_c2c_deep_extra'],
  'rui-account-deep-extra': ['sweep_account_deep_extra'],
  'rui-group-conf-deep-extra': ['sweep_group_conf_deep_extra'],
  // Native/mobile boundary probes. PASS where the in-app entry/routing is
  // deterministic; SKIP where the next step is an OS dialog/link/permission seam.
  'rui-native-boundary-guards': ['sweep_native_boundary_guards'],
  // P1/P2/P3 campaign Batch V — P2 fork-key-backed real-UI cases.
  'rui-p2-keys': ['sweep_p2_keys'],
  // P1/P2/P3 campaign Batch VI — C2C custom inbound seed + real Reply.
  'rui-p2-reply': ['sweep_p2_reply'],
  // P1/P2/P3 campaign Batch VII — pasted-image write-phase driver; voice/tray
  // conclusions live in the campaign anchor.
  'rui-p2-verify': ['sweep_p2_verify'],
  // P1/P2/P3 campaign Batch VIII — P3 writable subset.
  'rui-p3-writable': ['sweep_p3_writable'],
  // iOS true-App first-pass coverage. These sweeps start from fresh accounts and
  // establish any needed friendship/group state internally, so they do not rely
  // on the macOS-only restored Fixture C pair.
  'rui-ios-account-settings': ['sweep_login', 'sweep_ios_settings_main'],
  'rui-ios-chat-main': ['sweep_chat', 'sweep_group2'],
  'rui-ios-main': [
    'sweep_login',
    'sweep_ios_settings_main',
    'sweep_chat',
    'sweep_group2',
  ],
  'all-current': ['handshake', 'message', 'handshake_detail', 'decline'],
  'accepted-friend-inline': ['handshake', 'message'],
  'accepted-friend-detail': ['handshake_detail', 'message'],
  'accepted-friend-inline-burst': ['handshake', 'message_burst'],
  'accepted-friend-detail-burst': ['handshake_detail', 'message_burst'],
  'accepted-friend-inline-group-message': ['handshake', 'group_message'],
  'accepted-friend-detail-group-message': ['handshake_detail', 'group_message'],
  // Single-instance group create/open/composer surface (no friendship needed).
  'group-create': ['group_create'],
  'group-profile-open': ['group_profile_open'],
  'group-rename': ['group_rename'],
  'group-search': ['group_search'],
  'group-add-member-open': ['group_add_member_open'],
  'group-add-member-picker': ['handshake', 'group_add_member_picker'],
  // Single-instance group conversation-row context menu (no friendship needed).
  'group-menu-surface': ['group_conversation_menu'],
  'group-menu-pin': ['group_menu_pin_unpin'],
  'group-menu-mark-read': ['group_menu_mark_read'],
  'group-menu-delete': ['group_menu_delete_confirm'],
  // Combined single-instance group-menu sweep. pin/unpin AND delete-confirm are
  // now driven through the deterministic `l3_open_conversation_menu` action (no
  // flutter_skill PopupMenuItem double-fire), so S132 + S134 are back in the
  // bundle. For a group, "Delete" fires onConversationDeleted (the host
  // suppresses the row until a new inbound) + clears history/pin, so the row
  // leaves the sidebar — the "gone" assertion holds. mark_read here is the
  // single-instance SURFACE check (own sends can't seed unread); the TRUE
  // unread>0→0 transition is the two-process `group-menu-mark-read-unread`
  // campaign.
  'group-menu': [
    'group_conversation_menu',
    'group_menu_pin_unpin',
    'group_menu_mark_read',
    'group_menu_delete_confirm',
  ],
  // Combined single-instance group-surface sweep. Only the live-PASS
  // single-instance scenarios are included so the bundle is green; the
  // currently-BLOCKED single-instance gates (group_profile_open, group_rename,
  // group_search — see their spec Status) keep their own dedicated campaigns.
  'group-surfaces': [
    'group_create',
    'group_conversation_menu',
    'group_menu_pin_unpin',
    'group_menu_mark_read',
  ],
  // Two-process group alternating-burst (S152) + invite→member-list (S155),
  // both require an existing friendship (handshake first), like group_message.
  'group-burst': ['handshake', 'group_burst'],
  'group-member-list': ['handshake', 'group_member_list'],
  // Two-process group menu/clear gates that need REAL inbound state (a peer must
  // send so unread/history actually accrue), so they require a friendship first:
  //  - mark-read-unread (S118/S133): B seeds unread, A marks read → unread→0.
  //  - clear-history (S122): B seeds history, A clears → messageCount→0, row stays.
  //  - clear-preserves-pin (S154): A pins + B seeds, A clears → still pinned.
  'group-menu-mark-read-unread': ['handshake', 'group_menu_mark_read_unread'],
  'group-clear-history': ['handshake', 'group_clear_history'],
  'group-clear-preserves-pin': ['handshake', 'group_clear_preserves_pin'],
  // Legacy Tox conference, same two-process invite+delivery shape as group.
  'accepted-friend-inline-conference-message': [
    'handshake',
    'conference_message',
  ],
  'accepted-friend-detail-conference-message': [
    'handshake_detail',
    'conference_message',
  ],
  'fresh-no-friend': ['decline'],
  'accepted-friend-inline-call': ['handshake', 'message', 'call_voice'],
  'accepted-friend-detail-call': ['handshake_detail', 'message', 'call_voice'],
  'accepted-friend-inline-call-reject': ['handshake', 'call_reject'],
  'accepted-friend-detail-call-reject': ['handshake_detail', 'call_reject'],
  'accepted-friend-inline-chat-stack': [
    'handshake',
    'message',
    'message_burst',
  ],
  'accepted-friend-detail-chat-stack': [
    'handshake_detail',
    'message',
    'message_burst',
  ],
  'accepted-friend-inline-call-stack': [
    'handshake',
    'message',
    'call_voice',
    'call_reject',
  ],
  'accepted-friend-detail-call-stack': [
    'handshake_detail',
    'message',
    'call_voice',
    'call_reject',
  ],
  'accepted-friend-inline-full': [
    'handshake',
    'message',
    'message_burst',
    'group_message',
    'conference_message',
    'call_voice',
    'call_reject',
  ],
  'accepted-friend-detail-full': [
    'handshake_detail',
    'message',
    'message_burst',
    'group_message',
    'conference_message',
    'call_voice',
    'call_reject',
  ],
  'no-friend-then-inline': ['custom_message', 'handshake'],
  'no-friend-then-detail': ['custom_message', 'handshake_detail'],
  'no-friend-inline-chat': ['custom_message', 'handshake', 'message'],
  'no-friend-detail-chat': ['custom_message', 'handshake_detail', 'message'],
  'no-friend-inline-group-message': [
    'custom_message',
    'handshake',
    'group_message',
  ],
  'no-friend-detail-group-message': [
    'custom_message',
    'handshake_detail',
    'group_message',
  ],
  'no-friend-inline-burst': ['custom_message', 'handshake', 'message_burst'],
  'no-friend-detail-burst': [
    'custom_message',
    'handshake_detail',
    'message_burst',
  ],
  'no-friend-inline-call': ['custom_message', 'handshake', 'call_voice'],
  'no-friend-detail-call': ['custom_message', 'handshake_detail', 'call_voice'],
  'no-friend-inline-call-reject': [
    'custom_message',
    'handshake',
    'call_reject',
  ],
  'no-friend-detail-call-reject': [
    'custom_message',
    'handshake_detail',
    'call_reject',
  ],
  'inline-then-decline': ['handshake', 'decline'],
  'detail-then-decline': ['handshake_detail', 'decline'],
  'inline-chat-then-decline': ['handshake', 'message', 'decline'],
  'detail-chat-then-decline': ['handshake_detail', 'message', 'decline'],
  'inline-burst-then-decline': ['handshake', 'message_burst', 'decline'],
  'detail-burst-then-decline': ['handshake_detail', 'message_burst', 'decline'],
  'inline-call-then-decline': ['handshake', 'call_voice', 'decline'],
  'detail-call-then-decline': ['handshake_detail', 'call_voice', 'decline'],
  'inline-call-reject-then-decline': ['handshake', 'call_reject', 'decline'],
  'detail-call-reject-then-decline': [
    'handshake_detail',
    'call_reject',
    'decline',
  ],
  'fresh-custom-message': ['custom_message'],
  'all-expanded': [
    'handshake',
    'message',
    'message_burst',
    'group_message',
    'conference_message',
    'call_voice',
    'call_reject',
    'custom_message',
    'handshake_detail',
    'decline',
  ],
};
const _realUiStateNoFriend = 'no-friend';
const _realUiStateFriends = 'friends';
const _realUiStateRelaunchDirty = 'relaunch-dirty';
const _internalRealUiResetScenario = 'reset_friendship';

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final opts = _Options.parse(args);
  if (opts.error != null) {
    stderr.writeln(opts.error);
    stderr.writeln(_usage);
    return 64;
  }
  if (opts.listRealUiCampaigns) {
    _printRealUiCampaigns();
    return 0;
  }
  if (opts.showUsage) {
    print(_usage.trim());
    return 0;
  }

  late final _Manifest manifest;
  try {
    manifest = _Manifest.load(_manifestPath);
  } catch (e) {
    stderr.writeln('[unified] manifest load failed: $e');
    return 70;
  }

  final errors = _validate(manifest);
  if (opts.validateOnly) {
    for (final error in errors) {
      stderr.writeln('[unified] VALIDATION ERROR: $error');
    }
    return errors.isEmpty ? 0 : 1;
  }
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('[unified] VALIDATION ERROR: $error');
    }
    return 1;
  }

  final selected = _select(manifest.entries, opts);
  if (selected.isEmpty) {
    stderr.writeln(
      '[unified] no manifest entries matched the requested filters',
    );
    return 65;
  }
  if (opts.realUiScenarios.isNotEmpty) {
    final realUiEntries = selected.where((entry) => entry.klass == '2proc-ui');
    if (realUiEntries.isEmpty) {
      stderr.writeln(
        '[unified] --real-ui-scenario requires a matching 2proc-ui entry',
      );
      return 64;
    }
    final unknown = opts.realUiScenarios.toSet().difference(
      _validRealUiScenarios,
    );
    if (unknown.isNotEmpty) {
      stderr.writeln(
        '[unified] unknown real-UI scenario(s): ${unknown.join(', ')}',
      );
      return 64;
    }
  }
  if (opts.realUiCampaigns.isNotEmpty) {
    final realUiEntries = selected.where((entry) => entry.klass == '2proc-ui');
    if (realUiEntries.isEmpty) {
      stderr.writeln(
        '[unified] --real-ui-campaign requires a matching 2proc-ui entry',
      );
      return 64;
    }
  }

  final plan = _Plan.fromEntries(selected, opts: opts);
  _realUiPlatform = opts.realUiPlatform;

  // Android/Windows real-UI support only NO-FRIEND scenarios today: their A/B
  // launchers reject TOXEE_FIXTURE_C_RESTORE (paired_for_e2e restore into a
  // sandboxed device / per-instance Windows store is not implemented). Reject a
  // friendship-dependent scenario HERE — at planning time, so --plan-json and
  // --dry-run also fail — instead of planning a restore the launcher would
  // hard-reject mid-run.
  final restoreGapError = _realUiRestoreGap(plan);
  if (restoreGapError != null) {
    stderr.writeln(restoreGapError);
    return 64;
  }

  if (opts.list) {
    _printList(selected);
    return 0;
  }
  if (opts.planJson) {
    print(const JsonEncoder.withIndent('  ').convert(plan.toJson()));
    return 0;
  }
  if (opts.dryRun) {
    _printDryRun(plan);
    return 0;
  }

  try {
    return await _executePlan(plan);
  } catch (e, st) {
    stderr.writeln('[unified] execution failed: $e\n$st');
    return 1;
  }
}

class _Options {
  _Options({
    required this.tier,
    required this.includeDestructive,
    required this.list,
    required this.planJson,
    required this.dryRun,
    required this.validateOnly,
    required this.showUsage,
    required this.listRealUiCampaigns,
    required this.classFilter,
    required this.idFilter,
    required this.realUiScenarios,
    required this.realUiCampaigns,
    required this.realUiPlatform,
    this.error,
  });

  final String tier;
  final bool includeDestructive;
  final bool list;
  final bool planJson;
  final bool dryRun;
  final bool validateOnly;
  final bool showUsage;
  final bool listRealUiCampaigns;
  final Set<String> classFilter;
  final Set<String> idFilter;
  final List<String> realUiScenarios;
  final List<String> realUiCampaigns;
  final String realUiPlatform;
  final String? error;

  static _Options parse(List<String> args) {
    var tier = 'non-media';
    var includeDestructive = false;
    var list = false;
    var planJson = false;
    var dryRun = false;
    var validateOnly = false;
    var showUsage = false;
    var listRealUiCampaigns = false;
    final classFilter = <String>{};
    final idFilter = <String>{};
    final realUiScenarios = <String>[];
    final realUiCampaigns = <String>[];
    var realUiPlatform = 'macos';
    String? error;

    for (final arg in args) {
      if (arg == '--include-destructive') {
        includeDestructive = true;
      } else if (arg == '--list') {
        list = true;
      } else if (arg == '--plan-json') {
        planJson = true;
      } else if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg == '--validate-only') {
        validateOnly = true;
      } else if (arg.startsWith('--tier=')) {
        tier = arg.substring('--tier='.length);
      } else if (arg.startsWith('--class=')) {
        classFilter.addAll(_splitFlag(arg.substring('--class='.length)));
      } else if (arg.startsWith('--id=')) {
        idFilter.addAll(_splitFlag(arg.substring('--id='.length)));
      } else if (arg.startsWith('--real-ui-scenario=')) {
        realUiScenarios.addAll(
          _splitFlagList(arg.substring('--real-ui-scenario='.length)),
        );
      } else if (arg.startsWith('--real-ui-campaign=')) {
        realUiCampaigns.addAll(
          _splitFlagList(arg.substring('--real-ui-campaign='.length)),
        );
      } else if (arg.startsWith('--real-ui-platform=')) {
        realUiPlatform = arg.substring('--real-ui-platform='.length);
      } else if (arg == '-h' || arg == '--help' || arg == 'help') {
        showUsage = true;
      } else if (arg == '--list-real-ui-campaigns') {
        listRealUiCampaigns = true;
      } else if (arg.trim().isNotEmpty) {
        error = 'unknown argument: $arg';
      }
    }

    if (!_validTiers.contains(tier)) {
      error ??= 'unknown tier: $tier';
    }
    if (!_validRealUiPlatforms.contains(realUiPlatform)) {
      error ??= 'unknown real-UI platform: $realUiPlatform';
    }
    final unsupportedReason = _unsupportedRealUiPlatforms[realUiPlatform];
    if (unsupportedReason != null) {
      error ??=
          'unsupported real-UI platform: $realUiPlatform ($unsupportedReason)';
    }
    final badClasses = classFilter.difference(_validClasses);
    if (badClasses.isNotEmpty) {
      error ??= 'unknown class value(s): ${badClasses.join(', ')}';
    }
    final badRealUi = realUiScenarios.toSet().difference(_validRealUiScenarios);
    if (badRealUi.isNotEmpty) {
      error ??= 'unknown real-UI scenario(s): ${badRealUi.join(', ')}';
    }
    final badCampaigns = realUiCampaigns.toSet().difference(
      _realUiCampaigns.keys.toSet(),
    );
    if (badCampaigns.isNotEmpty) {
      error ??= 'unknown real-UI campaign(s): ${badCampaigns.join(', ')}';
    }
    if (realUiScenarios.isNotEmpty && realUiCampaigns.isNotEmpty) {
      error ??=
          'choose either --real-ui-scenario=... or --real-ui-campaign=..., not both';
    }

    return _Options(
      tier: tier,
      includeDestructive: includeDestructive,
      list: list,
      planJson: planJson,
      dryRun: dryRun,
      validateOnly: validateOnly,
      showUsage: showUsage,
      listRealUiCampaigns: listRealUiCampaigns,
      classFilter: classFilter,
      idFilter: idFilter,
      realUiScenarios: realUiScenarios,
      realUiCampaigns: realUiCampaigns,
      realUiPlatform: realUiPlatform,
      error: error,
    );
  }
}

Set<String> _splitFlag(String raw) => raw
    .split(',')
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toSet();

List<String> _splitFlagList(String raw) => [
  for (final part in raw.split(',').map((part) => part.trim()))
    if (part.isNotEmpty) part,
];

class _Manifest {
  _Manifest(this.entries);

  final List<_Entry> entries;

  static _Manifest load(String path) {
    final root =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final rawEntries = (root['entries'] as List? ?? const <dynamic>[]);
    return _Manifest([
      for (var i = 0; i < rawEntries.length; i++)
        _Entry.fromJson(i, rawEntries[i] as Map<String, dynamic>),
    ]);
  }
}

class _Entry {
  _Entry({
    required this.index,
    required this.script,
    required this.scenarios,
    required this.klass,
    required this.media,
    required this.destructive,
    required this.costSecs,
    required this.base,
    required this.driver,
    required this.driverArgs,
    required this.scenarioCommands,
    required this.legacyOnly,
    required this.tcpOnly,
    required this.launchNote,
  });

  final int index;
  final String script;
  final List<String> scenarios;
  final String klass;
  final bool media;
  final bool destructive;
  final int costSecs;
  final String base;
  final String driver;
  final List<String> driverArgs;
  final List<String> scenarioCommands;
  final bool legacyOnly;
  // Same-host NGC two-process discovery is ~40% flaky over UDP, so NGC gates
  // (join/member_list) launch their shared pair with TOXEE_PAIR_TCP_ONLY=1 —
  // which makes same-host NGC deterministic — instead of relaunching a fresh
  // UDP pair per attempt. Routes the entry into the 'ngc-paired-reuse' group.
  final bool tcpOnly;
  final String? launchNote;

  factory _Entry.fromJson(int index, Map<String, dynamic> json) {
    return _Entry(
      index: index,
      script: json['script']?.toString() ?? '',
      scenarios: _stringList(json['scenarios']),
      klass: json['class']?.toString() ?? '2proc-l3',
      media: json['media'] == true,
      destructive: json['destructive'] == true,
      costSecs: (json['costSecs'] as num?)?.toInt() ?? 0,
      base: json['base']?.toString() ?? '',
      driver: json['driver']?.toString() ?? '',
      driverArgs: _stringList(json['driverArgs']),
      scenarioCommands: _stringList(json['scenarioCommands']),
      legacyOnly: json['legacyOnly'] == true,
      tcpOnly: json['tcpOnly'] == true,
      launchNote: json['launchNote']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final doc = <String, dynamic>{
      'script': script,
      'scenarios': scenarios,
      'class': klass,
      'media': media,
      'destructive': destructive,
      'costSecs': costSecs,
      'base': base,
      'driver': driver,
      'driverArgs': driverArgs,
      'legacyOnly': legacyOnly,
      if (tcpOnly) 'tcpOnly': tcpOnly,
    };
    if (scenarioCommands.isNotEmpty) {
      doc['scenarioCommands'] = scenarioCommands;
    }
    if (launchNote != null && launchNote!.isNotEmpty) {
      doc['launchNote'] = launchNote;
    }
    return doc;
  }
}

List<String> _stringList(Object? value) => [
  for (final item in (value as List? ?? const <dynamic>[])) item.toString(),
];

List<String> _validate(_Manifest manifest) {
  final errors = <String>[];
  if (manifest.entries.isEmpty) {
    errors.add('manifest has no entries');
    return errors;
  }

  final seen = <String>{};
  for (final entry in manifest.entries) {
    if (entry.script.isEmpty) {
      errors.add('entry ${entry.index}: missing script');
    }
    if (!seen.add(entry.script)) {
      errors.add('duplicate script: ${entry.script}');
    }
    if (!_validClasses.contains(entry.klass)) {
      errors.add('${entry.script}: unsupported class ${entry.klass}');
    }
    if (entry.scenarios.isEmpty) {
      errors.add('${entry.script}: no scenarios');
    }
    if (!_validBases.contains(entry.base)) {
      errors.add('${entry.script}: unsupported base ${entry.base}');
    }
    if (entry.driver.isEmpty) {
      errors.add('${entry.script}: missing driver');
    }
    if (entry.driverArgs.any((arg) => arg.trim().isEmpty)) {
      errors.add('${entry.script}: driverArgs contains an empty item');
    }
    if (!File('tool/mcp_test/${entry.driver}').existsSync()) {
      errors.add('${entry.script}: driver missing: ${entry.driver}');
    }
    if (entry.legacyOnly &&
        !File('tool/mcp_test/${entry.script}').existsSync()) {
      errors.add('${entry.script}: legacy shell missing');
    }
    if (entry.klass == '2proc-ui') {
      if (entry.base != 'real-ui') {
        errors.add('${entry.script}: 2proc-ui entries must use base "real-ui"');
      }
      if (entry.scenarioCommands.isEmpty) {
        errors.add('${entry.script}: 2proc-ui entry needs scenarioCommands');
      }
      final badScenarios = entry.scenarioCommands.toSet().difference(
        _validRealUiScenarios,
      );
      if (badScenarios.isNotEmpty) {
        errors.add(
          '${entry.script}: unsupported scenarioCommands ${badScenarios.join(', ')}',
        );
      }
    } else if (entry.scenarioCommands.isNotEmpty) {
      errors.add(
        '${entry.script}: only 2proc-ui entries may declare scenarioCommands',
      );
    }
  }
  return errors;
}

List<_Entry> _select(List<_Entry> entries, _Options opts) {
  return [
    for (final entry in entries)
      if (_tierMatches(entry, opts.tier) &&
          (opts.includeDestructive || !entry.destructive) &&
          (opts.classFilter.isEmpty ||
              opts.classFilter.contains(entry.klass)) &&
          (opts.idFilter.isEmpty || opts.idFilter.contains(entry.script)))
        entry,
  ];
}

bool _tierMatches(_Entry entry, String tier) {
  switch (tier) {
    case 'non-media':
      return !entry.media;
    case 'media':
      return entry.media;
    case 'all':
      return true;
  }
  return false;
}

class _Plan {
  _Plan(this.groups);

  final List<_Group> groups;

  factory _Plan.fromEntries(List<_Entry> entries, {required _Options opts}) {
    final paired = <_PlannedEntry>[];
    final ngc = <_PlannedEntry>[];
    final fresh = <_PlannedEntry>[];
    final media = <_PlannedEntry>[];
    final realUi = <_PlannedEntry>[];
    final legacy = <_PlannedEntry>[];
    final destructive = <_PlannedEntry>[];

    for (final entry in entries) {
      final planned = _PlannedEntry(
        entry,
        realUiScenarios: entry.klass == '2proc-ui'
            ? _selectedRealUiScenarios(entry, opts)
            : const <String>[],
      );
      if (entry.klass == '2proc-ui') {
        realUi.add(planned);
      } else if (entry.destructive) {
        destructive.add(planned);
      } else if (entry.base == 'fresh') {
        fresh.add(planned);
      } else if (entry.media) {
        if (entry.legacyOnly) {
          legacy.add(planned);
        } else {
          media.add(planned);
        }
      } else if (entry.legacyOnly) {
        legacy.add(planned);
      } else if (entry.tcpOnly) {
        ngc.add(planned);
      } else {
        paired.add(planned);
      }
    }

    return _Plan([
      if (paired.isNotEmpty) _Group('paired-reuse', paired),
      if (ngc.isNotEmpty) _Group('ngc-paired-reuse', ngc),
      for (final entry in fresh) _Group('fresh-isolated', [entry]),
      if (media.isNotEmpty) _Group('media-paired-reuse', media),
      if (realUi.isNotEmpty) _Group('real-ui', realUi),
      for (final entry in legacy) _Group('legacy-isolated', [entry]),
      for (final entry in destructive) _Group('destructive-isolated', [entry]),
    ]);
  }

  Map<String, dynamic> toJson() => {
    'format_version': 2,
    'groups': [for (final group in groups) group.toJson()],
  };
}

class _PlannedEntry {
  _PlannedEntry(this.entry, {required this.realUiScenarios});

  final _Entry entry;
  final List<String> realUiScenarios;

  Map<String, dynamic> toJson() {
    final doc = entry.toJson();
    if (realUiScenarios.isNotEmpty) {
      doc['realUiScenarios'] = realUiScenarios;
    }
    return doc;
  }
}

class _Group {
  _Group(this.mode, this.entries);

  final String mode;
  final List<_PlannedEntry> entries;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'entries': [for (final entry in entries) entry.toJson()],
    'commands': _commandsForGroup(this),
  };
}

List<String> _selectedRealUiScenarios(_Entry entry, _Options opts) {
  if (opts.realUiScenarios.isNotEmpty) {
    return opts.realUiScenarios;
  }
  if (opts.realUiCampaigns.isNotEmpty) {
    return [
      for (final campaign in opts.realUiCampaigns)
        ...?_realUiCampaigns[campaign],
    ];
  }
  return entry.scenarioCommands;
}

void _printRealUiCampaigns() {
  print('REAL-UI campaigns (${_realUiCampaigns.length})');
  for (final name in _realUiCampaigns.keys.toList()..sort()) {
    print('$name: ${_realUiCampaigns[name]!.join(' -> ')}');
  }
}

void _printList(List<_Entry> entries) {
  print('CLASS      MEDIA  DESTR  LEGACY  BASE             SCRIPT');
  for (final entry in entries) {
    print(
      '${entry.klass.padRight(10)} '
      '${entry.media.toString().padRight(5)}  '
      '${entry.destructive.toString().padRight(5)}  '
      '${entry.legacyOnly.toString().padRight(6)}  '
      '${entry.base.padRight(15)}  '
      '${entry.script} (${entry.scenarios.join(',')})',
    );
  }
}

void _printDryRun(_Plan plan) {
  for (final group in plan.groups) {
    print('# group: ${group.mode}');
    for (final command in _commandsForGroup(group)) {
      print(command);
    }
    print('');
  }
}

List<String> _commandsForGroup(_Group group) {
  switch (group.mode) {
    case 'paired-reuse':
      return [
        _launchPairCommand(restore: 'paired_for_e2e'),
        for (final entry in group.entries)
          _symbolicDriverCommand(entry.entry, paired: true),
        _stopPairCommand(),
      ];
    case 'fresh-isolated':
      final entry = group.entries.single.entry;
      return [
        _quietStopPairCommand(),
        _launchPairCommand(),
        _symbolicEntryCommand(entry, paired: false),
        _stopPairCommand(),
      ];
    case 'media-paired-reuse':
      return [
        _launchPairCommand(restore: 'paired_for_e2e'),
        // Boot+verify the pair once up front: unlike the other media drivers,
        // drive_fixture_c_call.dart does not self-boot, and the boot is
        // idempotent for the ones that do (their ensureReady skips when
        // sessionReady is already true).
        _pairBootCommand(),
        for (final entry in group.entries)
          _symbolicDriverCommand(entry.entry, paired: true),
        _stopPairCommand(),
      ];
    case 'ngc-paired-reuse':
      // NGC join/member_list on ONE TCP-only shared pair (deterministic
      // same-host NGC) instead of relaunching a fresh UDP pair per attempt.
      return [
        _launchPairCommand(restore: 'paired_for_e2e', tcpOnly: true),
        for (final entry in group.entries)
          _symbolicDriverCommand(entry.entry, paired: true),
        _stopPairCommand(),
      ];
    case 'real-ui':
      return [
        for (final entry in group.entries) ..._symbolicRealUiCommands(entry),
      ];
    case 'legacy-isolated':
      return [_legacyShellCommand(group.entries.single.entry)];
    case 'destructive-isolated':
      final entry = group.entries.single.entry;
      if (entry.legacyOnly) {
        return [_legacyShellCommand(entry)];
      }
      return [
        _launchPairCommand(restore: 'paired_for_e2e'),
        _symbolicDriverCommand(entry, paired: true),
        _stopPairCommand(),
      ];
  }
  return const <String>[];
}

String _symbolicEntryCommand(_Entry entry, {required bool paired}) {
  if (entry.legacyOnly) {
    return _legacyShellCommand(entry);
  }
  return _symbolicDriverCommand(entry, paired: paired);
}

String _symbolicDriverCommand(_Entry entry, {required bool paired}) {
  final buffer = StringBuffer(
    'dart run tool/mcp_test/${entry.driver} "\$A_WS" "\$B_WS"',
  );
  if (paired) {
    buffer.write(' --fixture-manifest $_pairManifest');
  }
  for (final arg in entry.driverArgs) {
    buffer.write(' ${_shellLiteral(arg)}');
  }
  return buffer.toString();
}

List<String> _symbolicRealUiCommands(_PlannedEntry planned) {
  final commands = <String>[];
  var pairActive = false;
  String? pairState;
  var pairNeedsRestoreBoot = false;
  String? previousScenario;

  for (var i = 0; i < planned.realUiScenarios.length; i++) {
    final scenario = planned.realUiScenarios[i];
    final requiredState = _requiredRealUiState(scenario);
    if (!pairActive) {
      final restore = _restoreForRealUiState(requiredState);
      commands.add(_launchRealUiPairCommand(restore: restore));
      pairActive = true;
      pairState = requiredState;
      pairNeedsRestoreBoot = restore != null;
    } else if (pairState != requiredState) {
      if (pairState == _realUiStateFriends &&
          requiredState == _realUiStateNoFriend) {
        commands.add(_symbolicRealUiResetCommand());
        pairState = _realUiStateNoFriend;
        pairNeedsRestoreBoot = false;
      } else if (pairState == _realUiStateNoFriend &&
          requiredState == _realUiStateFriends) {
        commands.add(_stopRealUiPairCommand());
        final restore = _restoreForRealUiState(requiredState);
        commands.add(_launchRealUiPairCommand(restore: restore));
        pairState = requiredState;
        pairNeedsRestoreBoot = restore != null;
      } else {
        commands.add(_stopRealUiPairCommand());
        final restore = _restoreForRealUiState(requiredState);
        commands.add(_launchRealUiPairCommand(restore: restore));
        pairState = requiredState;
        pairNeedsRestoreBoot = restore != null;
      }
    } else if (pairState == _realUiStateNoFriend &&
        _requiresFreshNoFriendRelaunch(
          previousScenario: previousScenario,
          nextScenario: scenario,
        )) {
      commands.add(_stopRealUiPairCommand());
      commands.add(_launchRealUiPairCommand());
      pairState = _realUiStateNoFriend;
      pairNeedsRestoreBoot = false;
    }

    final envPrefix = _realUiSymbolicDriverEnvPrefix();
    commands.add(
      '${envPrefix}dart run tool/mcp_test/${planned.entry.driver} '
      '${pairNeedsRestoreBoot ? '--boot-restored ' : ''}'
      '${_shellLiteral(scenario)} '
      '"\$A_WS" "\$A_PID" "\$A_NICK" "\$B_WS" "\$B_PID" "\$B_NICK"',
    );
    pairState = _resultRealUiState(scenario);
    pairNeedsRestoreBoot = false;
    previousScenario = scenario;
  }

  if (pairActive) {
    commands.add(_stopRealUiPairCommand());
  }
  return commands;
}

String _requiredRealUiState(String scenario) {
  switch (scenario) {
    case 'message':
    case 'message_burst':
    case 'group_message':
    case 'group_burst':
    case 'group_member_list':
    case 'group_menu_mark_read_unread':
    case 'group_clear_history':
    case 'group_clear_preserves_pin':
    case 'group_add_member_picker':
    case 'conference_message':
    case 'call_voice':
    case 'call_reject':
    // Batch 4 — friendship-dependent contacts/friend-profile cases: the runner
    // restores paired_for_e2e so the friend exists before the case drives the
    // friend profile / duplicate-add guard.
    case 'add_friend_duplicate_guard':
    case 'contacts_row_opens_friend_profile':
    case 'friendprof_send_message_tile':
    case 'friendprof_pin_toggle':
    case 'friendprof_block_unblock':
    case 'friendprof_mute_toggle_regression':
    case 'friendprof_remark_edit_persists':
    case 'friendprof_clear_history':
    case 'blocked_list_unblock_row':
    case 'contact_search_filter_clear':
    case 'friendprof_delete_friend_confirm':
    // Batch 5 — friendship-dependent conversation-list cases: the runner restores
    // paired_for_e2e so the C2C conversation can be seeded by B before the case
    // drives the row menu / search / preview.
    case 'conv_menu_surface_c2c':
    case 'conv_pin_unpin_reorders':
    case 'conv_mark_read_two_proc':
    case 'conv_delete_confirm_c2c':
    case 'conv_clear_history_c2c':
    case 'conv_clear_preserves_pin_c2c':
    case 'conv_unread_badge_bump_clear':
    case 'conv_preview_updates_on_inbound':
    case 'conv_presence_dot_flips':
    case 'conv_search_filter_clear':
    // Batch 6 — friendship-dependent chat-surface cases: the runner restores
    // paired_for_e2e so the C2C chat can be seeded by B before the case drives
    // the composer / menu / media bubbles.
    case 'chat_open_from_row':
    case 'chat_multiline_send':
    case 'chat_long_text_send':
    case 'chat_emoji_insert_send':
    case 'chat_sticker_panel_send':
    case 'chat_msg_menu_surface':
    case 'chat_copy_message_clipboard':
    case 'chat_reply_quote_roundtrip':
    case 'chat_forward_to_other_conv':
    case 'chat_delete_message_gone':
    case 'chat_history_scroll_load_more':
    case 'chat_inbound_while_scrolled_up':
    case 'chat_header_opens_profile':
    case 'chat_offline_pending_then_deliver':
    case 'chat_image_bubble_open_preview':
    case 'chat_file_bubble_present_open':
    // Focused C2C extra individual cases require an existing friendship.
    case 'c2c_global_search_contact_opens_chat':
    case 'c2c_conv_delete_cancel':
    case 'c2c_profile_clear_history_cancel':
    case 'c2c_delete_friend_cancel':
    case 'c2c_header_profile_send_back':
    // C2C deep individual case needs an existing friendship; the sweep starts
    // no-friend and establishes it once.
    case 'c2c_search_result_opens_target_message':
    // Optimized friendship bundles start from fresh no-friend when invoked as
    // a campaign, but individual sub-sweeps establish/reuse the friendship.
    // Batch 7 — the two-process group cases need a friendship (the standalone
    // dispatch establishes it + joins B); the runner restores paired_for_e2e.
    case 'group_add_member_full_join':
    case 'group_member_list_scroll':
    case 'group_unread_badge_two_proc':
    case 'group_kick_member_ui':
    // Focused group/conference member-management cases all need an A<->B
    // friendship so B can be invited into the fresh target group/conference.
    case 'group_member_peer_menu_surface':
    case 'group_member_role_action_smoke':
    case 'group_member_remove_ui':
    case 'conference_member_peer_row_surface':
    case 'conference_member_role_remove_absent':
    // Group/conference deep individual cases also need an A<->B friendship.
    case 'group_member_role_reopen_surface':
    case 'group_member_remove_receiver_state':
    case 'conference_bidirectional_message_lifecycle':
    // Batch 8 — the call cases + the chat-open misc cases need a friendship (the
    // call signaling + the C2C chat); the runner restores paired_for_e2e for the
    // standalone dispatch.
    case 'call_video_accept_hangup':
    case 'call_mute_toggle_incall':
    case 'call_camera_toggle_incall':
    case 'call_missed_record_row':
    case 'call_callee_hangup':
    case 'call_record_bubble_renders':
    case 'home_tabs_cycle_state_retained':
    case 'theme_switch_chat_open':
    case 'search_chat_history_window_open':
    // Native-boundary cases that assert C2C toolbar/routing need friendship; the
    // full guard sweep starts no-friend and establishes it once.
    case 'attachment_entry_buttons_render':
    case 'notification_tap_routes_to_c2c':
    // P1/P2/P3 Batch III — every individual chat/conv case needs friendship;
    // standalone dispatch restores paired_for_e2e or establishes it first.
    case 'chat_recall_message':
    case 'read_receipt_double_tick':
    case 'forward_to_group_target':
    case 'draft_restore_on_conv_switch':
    case 'typing_indicator_render':
    case 'unread_badge_total_sidebar':
    case 'search_empty_state':
    case 'image_preview_open_hardened':
    // P1/P2/P3 Batch IV — individual cases need an existing friendship. Two of
    // them restart a peer internally; their *result* state is relaunch-dirty,
    // but their launch precondition is still paired_for_e2e.
    case 'relaunch_history_autologin':
    case 'offline_pending_relaunch':
    case 'call_from_profile_tiles':
    case 'group_join_by_id_real_ui':
    // P1/P2/P3 Batch V — individual P2 key cases need an existing friendship.
    // presence_dot_relaunch restarts B internally but still starts from friends.
    case 'sticker_face_cell_send':
    case 'new_messages_chip_tap':
    case 'presence_dot_relaunch':
    // P1/P2/P3 Batch VI — individual reply case needs an existing friendship.
    case 'reply_quote_real':
    // P1/P2/P3 Batch VII — pasted-image is a C2C chat case.
    case 'paste_image_into_composer':
    // P1/P2/P3 Batch VIII — message_burst_perf needs an existing friendship.
    case 'message_burst_perf':
      return _realUiStateFriends;
    case 'handshake':
    case 'handshake_detail':
    case 'decline':
    case 'custom_message':
    // These single-instance group scenarios only drive A (no friendship needed),
    // so they run from a fresh no-friend launch.
    case 'group_create':
    case 'group_profile_open':
    case 'group_rename':
    case 'group_search':
    case 'group_add_member_open':
    case 'group_conversation_menu':
    case 'group_menu_pin_unpin':
    case 'group_menu_mark_read':
    case 'group_menu_delete_confirm':
    // Batch 1 — settings sweep 2: single-instance (drive only A, B idle), no
    // friendship required, so they run from a fresh no-friend launch.
    case 'sweep_settings2':
    case 'sweep_ios_settings_main':
    case 'settings_surface_sections':
    case 'settings_theme_dark':
    case 'settings_theme_light_back':
    case 'settings_locale_zh_roundtrip':
    case 'settings_download_limit_edit':
    case 'settings_bootstrap_mode_cycle':
    case 'settings_bootstrap_manual_add_node':
    case 'settings_bootstrap_manual_remove_node':
    case 'settings_autologin_toggle_hard':
    case 'settings_notifsound_toggle_hard':
    case 'settings_password_mismatch_error':
    case 'settings_logout_cancel':
    // Batch 2 — self profile: single-instance (drive only A, B idle), no
    // friendship required, so they run from a fresh no-friend launch.
    case 'sweep_profile':
    case 'profile_open_sidebar_avatar':
    case 'profile_edit_toggle_roundtrip':
    case 'profile_edit_nickname_persists':
    case 'profile_edit_status_persists':
    case 'profile_copy_toxid_snackbar':
    case 'profile_qr_copy':
    case 'profile_avatar_picker_opens':
    case 'profile_avatar_select_default_applies':
    // Batch 3 — login / register: single-instance (drive only A, B idle), no
    // friendship required, so they run from a fresh no-friend launch.
    case 'sweep_login':
    case 'login_register_open_back':
    case 'login_account_card_renders':
    case 'login_restore_entry_opens':
    case 'register_empty_nickname_error':
    case 'register_password_mismatch_error':
    case 'register_password_strength_flips':
    case 'login_password_wrong_error':
    case 'login_password_correct_unlocks':
    case 'account_switch_second_account':
    // Batch 4 — sweep_contacts runs its OWN handshake, so it requires a fresh
    // NO-FRIEND pair launch (driving both A and B). The add-friend dialog guard
    // cases (30/31/32) + the subtab cycle (34) need no friendship either.
    case 'sweep_contacts':
    case 'add_friend_dialog_esc_close':
    case 'add_friend_invalid_id_error':
    case 'add_friend_self_id_guard':
    case 'contacts_subtabs_cycle':
    // Batch 5 — sweep_conv runs its OWN handshake, so it requires a fresh
    // NO-FRIEND pair launch (driving both A and B).
    case 'sweep_conv':
    // Batch 6 — sweep_chat runs its OWN handshake, so it requires a fresh
    // NO-FRIEND pair launch (driving both A and B).
    case 'sweep_chat':
    // Focused C2C extra sweep runs its OWN handshake.
    case 'sweep_c2c_extra':
    // C2C deep sweep runs its OWN handshake.
    case 'sweep_c2c_deep_extra':
    // Optimized bundles start from one fresh no-friend pair launch and compose
    // existing sweeps internally to avoid relaunch/rehash overhead.
    case 'sweep_single_app_optimized':
    case 'sweep_c2c_optimized':
    case 'sweep_friendship_optimized':
    case 'sweep_optimized_current':
    // Batch 7 — sweep_group2 runs its OWN handshake, so it requires a fresh
    // NO-FRIEND pair launch. The single-instance create cases (71/72/82) +
    // the single-instance group/conference cases that create their own group
    // standalone (76/73/80/74/75/83/84) need no friendship either.
    case 'sweep_group2':
    case 'group_create_cancel':
    case 'group_create_type_selector_surface':
    case 'group_rename_updates_header':
    case 'group_profile_members_entry':
    case 'group_mute_toggle':
    case 'group_profile_clear_history':
    case 'group_leave_via_profile_confirm':
    case 'conf_create_dialog_surface':
    case 'conf_row_menu_surface':
    case 'conf_member_list_renders':
    // Focused group/conference member-management sweep runs its OWN handshake.
    case 'sweep_group_conf_member_extra':
    // Group/conference deep sweep runs its OWN handshake.
    case 'sweep_group_conf_deep_extra':
    // Batch 8 — sweep_calls_misc runs its OWN handshake, so it requires a fresh
    // NO-FRIEND pair launch. window_resize_responsive is single-instance (drive
    // only A, no friendship needed).
    case 'sweep_calls_misc':
    case 'window_resize_responsive':
    // P1/P2/P3 campaign Batch II — single-instance (drive only A, B idle), no
    // friendship involved at all (locale walk, conference lifecycle, account
    // switch/menu/delete are all account-local).
    case 'sweep_p1_single':
    case 'zh_locale_page_walk':
    case 'conference_rename_leave':
    case 'settings_switch_account_entry':
    case 'account_card_management_menu':
    case 'account_delete_full_flow':
    // P1/P2/P3 Batch III — sweep_p1_chat runs its OWN handshake, so it needs a
    // fresh no-friend pair launch.
    case 'sweep_p1_chat':
    // P1/P2/P3 Batch IV — sweep_p1_relaunch runs its OWN handshake and then
    // restarts instances internally.
    case 'sweep_p1_relaunch':
    // P1 extra — single-instance app-local Arabic/keyboard search cases; no
    // friendship involved.
    case 'sweep_p1_extra':
    case 'ar_rtl_page_walk':
    case 'keyboard_global_search_shortcut':
    // App-entry extra — single-instance (drive only A), no friendship involved.
    case 'sweep_app_entry_extra':
    case 'new_entry_menu_surface':
    case 'add_friend_paste_clipboard':
    case 'keyboard_new_conversation_shortcut':
    case 'keyboard_open_settings_shortcut':
    case 'irc_join_channel_real_controls':
    case 'irc_join_channel_loopback_live':
    case 'register_password_visibility_toggle':
    case 'login_import_account_card_open':
    // Group @-mention — establishes its OWN friendship + group when needed, so it
    // requires only a fresh no-friend pair launch.
    case 'sweep_group_mention':
    case 'group_at_member_send':
    case 'group_at_all_send':
    // Account/conference focused expansion — runs on A only, creates any
    // temporary account/conference internally, and cleans them before exit.
    case 'sweep_account_conf_extra':
    case 'settings_switch_account_cancel':
    case 'login_account_delete_cancel':
    case 'settings_delete_account_cancel':
    case 'conference_profile_id_surface':
    case 'conference_profile_send_message_tile':
    case 'conference_search_result_opens':
    // Account deep expansion is A-only and cleans the temporary account/group.
    case 'sweep_account_deep_extra':
    case 'account_multi_account_state_isolation':
    // Native-boundary sweep starts no-friend and establishes friendship only for
    // the toolbar/routing probes; non-friend guard cases below never form one.
    case 'sweep_native_boundary_guards':
    case 'restore_import_entry_guard':
    case 'network_disconnect_guard':
    case 'call_permission_denied_guard':
    case 'mobile_smoke_playbook_guard':
    // P1/P2/P3 Batch V — sweep_p2_keys runs its OWN handshake, then restarts B
    // for the presence-dot case.
    case 'sweep_p2_keys':
    // P1/P2/P3 Batch VI — sweep_p2_reply runs its OWN handshake.
    case 'sweep_p2_reply':
    // P1/P2/P3 Batch VII — sweep_p2_verify runs its OWN handshake.
    case 'sweep_p2_verify':
    // P1/P2/P3 Batch VIII — sweep_p3_writable runs its OWN handshake.
    case 'sweep_p3_writable':
      return _realUiStateNoFriend;
  }
  throw ArgumentError('unsupported real-UI scenario: $scenario');
}

String _resultRealUiState(String scenario) {
  switch (scenario) {
    case 'handshake':
    case 'handshake_detail':
    case 'message':
    case 'message_burst':
    case 'group_message':
    case 'group_burst':
    case 'group_member_list':
    case 'group_menu_mark_read_unread':
    case 'group_clear_history':
    case 'group_clear_preserves_pin':
    case 'group_add_member_picker':
    case 'conference_message':
    case 'call_voice':
    case 'call_reject':
    // Batch 4 — these friendship-dependent cases LEAVE the friendship intact
    // (they toggle profile controls / read the list, never delete the friend).
    case 'add_friend_duplicate_guard':
    case 'contacts_row_opens_friend_profile':
    case 'friendprof_send_message_tile':
    case 'friendprof_pin_toggle':
    case 'friendprof_block_unblock':
    case 'friendprof_mute_toggle_regression':
    case 'friendprof_remark_edit_persists':
    case 'friendprof_clear_history':
    case 'blocked_list_unblock_row':
    case 'contact_search_filter_clear':
    // Batch 5 — conversation-list cases LEAVE the friendship intact (the C2C
    // delete removes only the conversation ROW, never the friend — the S20
    // invariant — and every other case toggles pin / reads unread / searches).
    // sweep_conv re-seeds a row at the end, so the whole launch ends friends.
    case 'sweep_conv':
    case 'conv_menu_surface_c2c':
    case 'conv_pin_unpin_reorders':
    case 'conv_mark_read_two_proc':
    case 'conv_delete_confirm_c2c':
    case 'conv_clear_history_c2c':
    case 'conv_clear_preserves_pin_c2c':
    case 'conv_unread_badge_bump_clear':
    case 'conv_preview_updates_on_inbound':
    case 'conv_presence_dot_flips':
    case 'conv_search_filter_clear':
    // Batch 6 — chat-surface cases LEAVE the friendship intact (no case deletes
    // the friend; every case sends/menus/reads messages). sweep_chat re-seeds a
    // row at the end, so the whole launch ends friends.
    case 'sweep_chat':
    case 'chat_open_from_row':
    case 'chat_multiline_send':
    case 'chat_long_text_send':
    case 'chat_emoji_insert_send':
    case 'chat_sticker_panel_send':
    case 'chat_msg_menu_surface':
    case 'chat_copy_message_clipboard':
    case 'chat_reply_quote_roundtrip':
    case 'chat_forward_to_other_conv':
    case 'chat_delete_message_gone':
    case 'chat_history_scroll_load_more':
    case 'chat_inbound_while_scrolled_up':
    case 'chat_header_opens_profile':
    case 'chat_offline_pending_then_deliver':
    case 'chat_image_bubble_open_preview':
    case 'chat_file_bubble_present_open':
    // Focused C2C extra leaves the friendship intact; Cancel cases deliberately
    // avoid deleting/clearing, and the sweep re-seeds a visible row at the end.
    case 'sweep_c2c_extra':
    case 'c2c_global_search_contact_opens_chat':
    case 'c2c_conv_delete_cancel':
    case 'c2c_profile_clear_history_cancel':
    case 'c2c_delete_friend_cancel':
    case 'c2c_header_profile_send_back':
    case 'sweep_c2c_deep_extra':
    case 'c2c_search_result_opens_target_message':
    case 'sweep_c2c_optimized':
    case 'sweep_friendship_optimized':
    case 'sweep_optimized_current':
    // Batch 7 — sweep_group2 ends FRIENDS (no case deletes the friend; case 78
    // kicks B from the group + case 75 leaves the group, but the A<->B
    // friendship stays intact). The two-process group cases also leave the
    // friendship intact (kick/scroll/unread never delete the friend).
    case 'sweep_group2':
    case 'group_add_member_full_join':
    case 'group_member_list_scroll':
    case 'group_unread_badge_two_proc':
    case 'group_kick_member_ui':
    // Group @-mention — both the member and @All cases (and the sweep) create a
    // temporary group + B-join, leave it in cleanup, and never delete the
    // friend, so they end FRIENDS. (group_at_all_send was a no-op SKIP until the
    // @All identity fix landed; it is now a real gate with the same state.)
    case 'sweep_group_mention':
    case 'group_at_member_send':
    case 'group_at_all_send':
    // Focused member-management sweep/cases leave the friend relationship
    // intact; member removal only removes B from that temporary group.
    case 'sweep_group_conf_member_extra':
    case 'group_member_peer_menu_surface':
    case 'group_member_role_action_smoke':
    case 'group_member_remove_ui':
    case 'conference_member_peer_row_surface':
    case 'conference_member_role_remove_absent':
    // Group/conference deep sweep/cases leave the friend relationship intact.
    case 'sweep_group_conf_deep_extra':
    case 'group_member_role_reopen_surface':
    case 'group_member_remove_receiver_state':
    case 'conference_bidirectional_message_lifecycle':
    // Native-boundary full sweep and the C2C toolbar/routing probes form or keep
    // friendship; SKIP-only non-friend guards are listed in the no-friend result.
    case 'sweep_native_boundary_guards':
    case 'attachment_entry_buttons_render':
    case 'notification_tap_routes_to_c2c':
    // Batch 8 — sweep_calls_misc ends FRIENDS (no case deletes the friend; the
    // calls end idle and the conversation row stays alive). The call cases + the
    // chat-open misc cases also leave the friendship intact.
    case 'sweep_calls_misc':
    case 'call_video_accept_hangup':
    case 'call_mute_toggle_incall':
    case 'call_camera_toggle_incall':
    case 'call_missed_record_row':
    case 'call_callee_hangup':
    case 'call_record_bubble_renders':
    case 'home_tabs_cycle_state_retained':
    case 'theme_switch_chat_open':
    case 'search_chat_history_window_open':
    // P1/P2/P3 Batch III — no case deletes the friend; the sweep end-guard
    // re-seeds a visible C2C row.
    case 'sweep_p1_chat':
    case 'chat_recall_message':
    case 'read_receipt_double_tick':
    case 'forward_to_group_target':
    case 'draft_restore_on_conv_switch':
    case 'typing_indicator_render':
    case 'unread_badge_total_sidebar':
    case 'search_empty_state':
    case 'image_preview_open_hardened':
    // P1/P2/P3 Batch IV — profile-call + join-by-ID keep the friendship and do
    // not restart peers. Relaunch cases are marked below as relaunch-dirty.
    case 'call_from_profile_tiles':
    case 'group_join_by_id_real_ui':
    // P1/P2/P3 Batch V — sticker/chip keep the existing friendship.
    case 'sticker_face_cell_send':
    case 'new_messages_chip_tap':
    // P1/P2/P3 Batch VI — reply flow keeps the existing friendship.
    case 'sweep_p2_reply':
    case 'reply_quote_real':
    // P1/P2/P3 Batch VII — pasted-image keeps the existing friendship.
    case 'sweep_p2_verify':
    case 'paste_image_into_composer':
    // P1/P2/P3 Batch VIII — burst perf keeps the existing friendship.
    case 'sweep_p3_writable':
    case 'message_burst_perf':
      return _realUiStateFriends;
    case 'sweep_p1_relaunch':
    case 'relaunch_history_autologin':
    case 'offline_pending_relaunch':
    case 'sweep_p2_keys':
    case 'presence_dot_relaunch':
      return _realUiStateRelaunchDirty;
    case 'decline':
    case 'custom_message':
    // These single-instance group scenarios leave the friendship state untouched.
    case 'group_create':
    case 'group_profile_open':
    case 'group_rename':
    case 'group_search':
    case 'group_add_member_open':
    case 'group_conversation_menu':
    case 'group_menu_pin_unpin':
    case 'group_menu_mark_read':
    case 'group_menu_delete_confirm':
    // Batch 1 — settings sweep 2: single-instance, leaves friendship untouched.
    case 'sweep_settings2':
    case 'sweep_ios_settings_main':
    case 'settings_surface_sections':
    case 'settings_theme_dark':
    case 'settings_theme_light_back':
    case 'settings_locale_zh_roundtrip':
    case 'settings_download_limit_edit':
    case 'settings_bootstrap_mode_cycle':
    case 'settings_bootstrap_manual_add_node':
    case 'settings_bootstrap_manual_remove_node':
    case 'settings_autologin_toggle_hard':
    case 'settings_notifsound_toggle_hard':
    case 'settings_password_mismatch_error':
    case 'settings_logout_cancel':
    // Batch 2 — self profile: single-instance, leaves friendship untouched.
    case 'sweep_profile':
    case 'profile_open_sidebar_avatar':
    case 'profile_edit_toggle_roundtrip':
    case 'profile_edit_nickname_persists':
    case 'profile_edit_status_persists':
    case 'profile_copy_toxid_snackbar':
    case 'profile_qr_copy':
    case 'profile_avatar_picker_opens':
    case 'profile_avatar_select_default_applies':
    // Batch 3 — login / register: single-instance, leaves friendship untouched.
    case 'sweep_login':
    case 'login_register_open_back':
    case 'login_account_card_renders':
    case 'login_restore_entry_opens':
    case 'register_empty_nickname_error':
    case 'register_password_mismatch_error':
    case 'register_password_strength_flips':
    case 'login_password_wrong_error':
    case 'login_password_correct_unlocks':
    case 'account_switch_second_account':
    // Batch 4 — sweep_contacts ends no-friend (case 44 deletes + an end-guard
    // reset). The add-friend dialog guards (30/31/32) + subtab cycle (34) leave
    // the no-friend launch untouched. friendprof_delete_friend_confirm (44) is
    // the standalone delete case, which leaves the pair NO-FRIEND.
    case 'sweep_contacts':
    case 'add_friend_dialog_esc_close':
    case 'add_friend_invalid_id_error':
    case 'add_friend_self_id_guard':
    case 'contacts_subtabs_cycle':
    case 'friendprof_delete_friend_confirm':
    // Batch 7 — the single-instance create cases + the standalone
    // single-instance group/conference cases never form a friendship, so the
    // launch ends NO-FRIEND.
    case 'group_create_cancel':
    case 'group_create_type_selector_surface':
    case 'group_rename_updates_header':
    case 'group_profile_members_entry':
    case 'group_mute_toggle':
    case 'group_profile_clear_history':
    case 'group_leave_via_profile_confirm':
    case 'conf_create_dialog_surface':
    case 'conf_row_menu_surface':
    case 'conf_member_list_renders':
    // Batch 8 — window_resize_responsive is single-instance and forms no
    // friendship, so the launch ends NO-FRIEND.
    case 'window_resize_responsive':
    // P1/P2/P3 campaign Batch II — single-instance, never touches B or any
    // friendship. The sweep's end-clean guard (and the standalone delete case)
    // leave the launch on the PRIMARY account, locale EN, no-friend. Cases that
    // mutate accounts (switch registers a throwaway #2; delete removes it)
    // stay account-local, so the pair state contract is unchanged.
    case 'sweep_p1_single':
    case 'zh_locale_page_walk':
    case 'conference_rename_leave':
    case 'settings_switch_account_entry':
    case 'account_card_management_menu':
    case 'account_delete_full_flow':
    // P1 extra — locale is restored to EN and the search overlay is closed in
    // the driver end-clean; no friendship/account mutation.
    case 'sweep_p1_extra':
    case 'ar_rtl_page_walk':
    case 'keyboard_global_search_shortcut':
    // App-entry extra — the driver end-clean dismisses dialogs/popups and (for
    // the LoginPage cases) relogins; no friendship/account mutation.
    case 'sweep_app_entry_extra':
    case 'new_entry_menu_surface':
    case 'add_friend_paste_clipboard':
    case 'keyboard_new_conversation_shortcut':
    case 'keyboard_open_settings_shortcut':
    case 'irc_join_channel_real_controls':
    case 'irc_join_channel_loopback_live':
    case 'register_password_visibility_toggle':
    case 'login_import_account_card_open':
    // Account/conference focused expansion — all cases clean their temporary
    // account/conference artifacts and never form a friendship.
    case 'sweep_account_conf_extra':
    case 'settings_switch_account_cancel':
    case 'login_account_delete_cancel':
    case 'settings_delete_account_cancel':
    case 'conference_profile_id_surface':
    case 'conference_profile_send_message_tile':
    case 'conference_search_result_opens':
    // Account deep expansion cleans the throwaway account and primary group.
    case 'sweep_account_deep_extra':
    case 'account_multi_account_state_isolation':
    // Native-boundary individual guards that do not establish friendship.
    case 'restore_import_entry_guard':
    case 'network_disconnect_guard':
    case 'call_permission_denied_guard':
    case 'mobile_smoke_playbook_guard':
    // A-only optimized bundle leaves the pair friendship state untouched.
    case 'sweep_single_app_optimized':
      return _realUiStateNoFriend;
  }
  throw ArgumentError('unsupported real-UI scenario: $scenario');
}

bool _requiresFreshNoFriendRelaunch({
  String? previousScenario,
  required String nextScenario,
}) => false;

String? _restoreForRealUiState(String state) {
  if (state == _realUiStateFriends) {
    return 'paired_for_e2e';
  }
  return null;
}

/// Returns an error string when the selected real-UI platform cannot run one of
/// the planned scenarios because it would require a `paired_for_e2e` restore that
/// the platform's launcher does not implement (Android/Windows). Null when every
/// planned scenario is launchable on the platform.
String? _realUiRestoreGap(_Plan plan) {
  if (_realUiPlatform != 'android' && _realUiPlatform != 'windows') return null;
  final unsupported = <String>{};
  for (final group in plan.groups) {
    if (group.mode != 'real-ui') continue;
    for (final entry in group.entries) {
      for (final scenario in entry.realUiScenarios) {
        if (_requiredRealUiState(scenario) == _realUiStateFriends) {
          unsupported.add(scenario);
        }
      }
    }
  }
  if (unsupported.isEmpty) return null;
  return '[unified] real-UI platform "$_realUiPlatform" supports only no-friend '
      'scenarios today (its A/B launcher does not implement paired_for_e2e '
      'restore); friendship-dependent scenario(s) not allowed: '
      '${unsupported.toList()..sort()}';
}

String _symbolicRealUiResetCommand() {
  return '${_realUiSymbolicDriverEnvPrefix()}'
      'dart run tool/mcp_test/drive_real_ui_pair.dart '
      '$_internalRealUiResetScenario '
      '"\$A_WS" "\$A_PID" "\$A_NICK" "\$B_WS" "\$B_PID" "\$B_NICK"';
}

String _legacyShellCommand(_Entry entry) =>
    'bash tool/mcp_test/${entry.script}';

String _realUiPairJson() => _realUiConfig.pairJson;

/// The env-prefix prepended to the symbolic driver/reset commands in dry-run /
/// plan-json output. macOS needs none (the driver defaults to the macOS pair
/// json + `macos` platform); the other platforms set the pair json + platform
/// (+ the fixed IRC loopback port for Android). This mirrors `_realUiDriverEnv`,
/// which sets the same values for live execution.
String _realUiSymbolicDriverEnvPrefix() {
  if (_realUiPlatform == 'macos') return '';
  final cfg = _realUiConfig;
  final buffer = StringBuffer(
    'TOXEE_REAL_UI_PAIR_JSON=${cfg.pairJson} '
    'TOXEE_REAL_UI_PLATFORM=$_realUiPlatform ',
  );
  final ircPort = cfg.ircLoopbackPort;
  if (ircPort != null) {
    buffer.write('TOXEE_IRC_LOOPBACK_PORT=$ircPort ');
  }
  return buffer.toString();
}

/// Symbolic launch/stop invocation token. Bash `.sh` scripts are printed as the
/// bare path (the live runner runs them via `bash`); PowerShell `.ps1` scripts
/// are printed as a `powershell -ExecutionPolicy Bypass -File <script>` line so
/// the Windows dry-run is faithful to how the runner executes it.
String _realUiLaunchInvocation() => _realUiScriptInvocation(_realUiConfig.launchScript);

String _realUiStopInvocation() => _realUiScriptInvocation(_realUiConfig.stopScript);

String _realUiScriptInvocation(String script) => _realUiConfig.usesPowershell
    ? 'powershell -ExecutionPolicy Bypass -File $script'
    : script;

/// Argv for `Process.start` to run a real-UI launch/stop script: `bash <script>`
/// for `.sh`, `powershell -ExecutionPolicy Bypass -File <script>` for `.ps1`.
List<String> _realUiScriptExecCommand(String script) =>
    _realUiConfig.usesPowershell
    ? ['powershell', '-ExecutionPolicy', 'Bypass', '-File', script]
    : ['bash', script];

Map<String, String> _realUiDriverEnv() => {
  ...Platform.environment,
  'TOXEE_REAL_UI_PAIR_JSON': _realUiPairJson(),
  'TOXEE_REAL_UI_PLATFORM': _realUiPlatform,
  if (_realUiConfig.ircLoopbackPort != null)
    'TOXEE_IRC_LOOPBACK_PORT': _realUiConfig.ircLoopbackPort!,
};

String _launchPairCommand({String? restore, bool tcpOnly = false}) {
  final prefix = tcpOnly ? 'TOXEE_PAIR_TCP_ONLY=1 ' : '';
  if (restore == null || restore.isEmpty) {
    return '${prefix}tool/mcp_test/launch_fixture_c_pair.sh';
  }
  return '${prefix}TOXEE_FIXTURE_C_RESTORE=$restore '
      'tool/mcp_test/launch_fixture_c_pair.sh';
}

/// Symbolic command for the canonical pair boot+verify driver (used as the
/// up-front boot step for the media group, whose call driver does not self-boot).
String _pairBootCommand() =>
    'dart run tool/mcp_test/drive_fixture_c_pair.dart "\$A_WS" "\$B_WS" '
    '--fixture-manifest $_pairManifest';

String _launchRealUiPairCommand({String? restore}) {
  // The symbolic env prefix uses bash `VAR=value cmd` convention (the runner's
  // own host context) even for the PowerShell launch invocation; live execution
  // passes these via the process environment (`_launchRealUiPair`), not a shell
  // prefix, so the representation stays faithful in WHAT is set, if not in
  // copy-paste syntax. The Android launch ALSO receives TOXEE_IRC_LOOPBACK_PORT
  // live (for adb reverse), so include it here too.
  final ircPort = _realUiConfig.ircLoopbackPort;
  final ircPrefix = ircPort != null ? 'TOXEE_IRC_LOOPBACK_PORT=$ircPort ' : '';
  final invocation = _realUiLaunchInvocation();
  if (restore == null || restore.isEmpty) return '$ircPrefix$invocation';
  return '${ircPrefix}TOXEE_FIXTURE_C_RESTORE=$restore $invocation';
}

String _stopPairCommand() => 'tool/mcp_test/stop_fixture_c_pair.sh';

String _stopRealUiPairCommand() => _realUiStopInvocation();

String _quietStopPairCommand() =>
    'tool/mcp_test/stop_fixture_c_pair.sh >/dev/null 2>&1 || true';

String _shellLiteral(String value) {
  if (value.isEmpty) return "''";
  final simple = RegExp(r'^[A-Za-z0-9_./:=+-]+$');
  if (simple.hasMatch(value)) return value;
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

Future<int> _executePlan(_Plan plan) async {
  for (final group in plan.groups) {
    stdout.writeln('[unified] >>> ${group.mode}');
    final rc = await _executeGroup(group);
    if (rc != 0) {
      return rc;
    }
  }
  return 0;
}

Future<int> _executeGroup(_Group group) async {
  switch (group.mode) {
    case 'paired-reuse':
      return _executeSharedPairGroup(group.entries);
    case 'ngc-paired-reuse':
      return _executeSharedPairGroup(group.entries, tcpOnly: true);
    case 'fresh-isolated':
      return _executeFreshEntry(group.entries.single.entry);
    case 'media-paired-reuse':
      return _executeSharedPairGroup(group.entries, bootFirst: true);
    case 'real-ui':
      for (final entry in group.entries) {
        final rc = await _executeRealUiEntry(entry);
        if (rc != 0) return rc;
      }
      return 0;
    case 'legacy-isolated':
      return _executeLegacyEntry(group.entries.single.entry);
    case 'destructive-isolated':
      return _executeDestructiveEntry(group.entries.single.entry);
  }
  return 0;
}

Future<int> _executeSharedPairGroup(
  List<_PlannedEntry> entries, {
  bool tcpOnly = false,
  bool bootFirst = false,
}) async {
  await _bestEffortStopPair();
  final launchRc = await _launchPair(
    restore: 'paired_for_e2e',
    tcpOnly: tcpOnly,
  );
  if (launchRc != 0) {
    return launchRc;
  }
  try {
    if (bootFirst) {
      // The call driver does not self-boot; boot+verify the pair once up front.
      // Idempotent for the media drivers that do self-boot.
      final bootRc = await _executePairBoot();
      if (bootRc != 0) {
        return bootRc;
      }
    }
    for (final planned in entries) {
      final rc = await _executeDirectEntry(planned.entry, paired: true);
      if (rc != 0) {
        return rc;
      }
    }
    return 0;
  } finally {
    await _bestEffortStopPair();
  }
}

Future<int> _executePairBoot() async {
  final runtime = _RuntimePair.load(_macosPairJson);
  return _runProcess([
    'dart',
    'run',
    'tool/mcp_test/drive_fixture_c_pair.dart',
    runtime.a.wsUri,
    runtime.b.wsUri,
    '--fixture-manifest',
    _pairManifest,
  ]);
}

Future<int> _executeFreshEntry(_Entry entry) async {
  await _bestEffortStopPair();
  final launchRc = await _launchPair();
  if (launchRc != 0) {
    return launchRc;
  }
  try {
    if (entry.legacyOnly) {
      return _executeLegacyEntry(entry);
    }
    return _executeDirectEntry(entry, paired: false);
  } finally {
    await _bestEffortStopPair();
  }
}

Future<int> _executeDestructiveEntry(_Entry entry) async {
  if (entry.legacyOnly) {
    return _executeLegacyEntry(entry);
  }
  await _bestEffortStopPair();
  final launchRc = await _launchPair(restore: 'paired_for_e2e');
  if (launchRc != 0) {
    return launchRc;
  }
  try {
    return _executeDirectEntry(entry, paired: true);
  } finally {
    await _bestEffortStopPair();
  }
}

Future<int> _executeLegacyEntry(_Entry entry) async {
  return _runProcess(['bash', 'tool/mcp_test/${entry.script}']);
}

Future<int> _executeDirectEntry(_Entry entry, {required bool paired}) async {
  final runtime = _RuntimePair.load(_macosPairJson);
  final args = <String>[
    'run',
    'tool/mcp_test/${entry.driver}',
    runtime.a.wsUri,
    runtime.b.wsUri,
    if (paired) '--fixture-manifest',
    if (paired) _pairManifest,
    ...entry.driverArgs,
  ];
  return _runProcess(['dart', ...args]);
}

Future<int> _executeRealUiEntry(_PlannedEntry planned) async {
  var pairActive = false;
  String? pairState;
  var pairNeedsRestoreBoot = false;
  String? previousScenario;
  try {
    for (var i = 0; i < planned.realUiScenarios.length; i++) {
      final scenario = planned.realUiScenarios[i];
      final requiredState = _requiredRealUiState(scenario);
      var resetApplied = false;
      if (!pairActive) {
        final restore = _restoreForRealUiState(requiredState);
        final launchRc = await _launchRealUiPair(restore: restore);
        if (launchRc != 0) {
          return launchRc;
        }
        pairActive = true;
        pairState = requiredState;
        pairNeedsRestoreBoot = restore != null;
      } else if (pairState != requiredState) {
        if (pairState == _realUiStateFriends &&
            requiredState == _realUiStateNoFriend) {
          final resetRc = await _executeInternalRealUiReset();
          if (resetRc != 0) {
            return resetRc;
          }
          pairState = _realUiStateNoFriend;
          pairNeedsRestoreBoot = false;
          resetApplied = true;
        } else {
          await _bestEffortStopRealUiPair();
          final restore = _restoreForRealUiState(requiredState);
          final launchRc = await _launchRealUiPair(restore: restore);
          if (launchRc != 0) {
            return launchRc;
          }
          pairState = requiredState;
          pairNeedsRestoreBoot = restore != null;
        }
      } else if (pairState == _realUiStateNoFriend &&
          _requiresFreshNoFriendRelaunch(
            previousScenario: previousScenario,
            nextScenario: scenario,
          )) {
        await _bestEffortStopRealUiPair();
        final launchRc = await _launchRealUiPair();
        if (launchRc != 0) {
          return launchRc;
        }
        pairActive = true;
        pairState = _realUiStateNoFriend;
        pairNeedsRestoreBoot = false;
      }

      var rc = await _executeRealUiScenario(
        planned.entry.driver,
        scenario,
        bootRestored: pairNeedsRestoreBoot,
      );
      if (rc == 78) {
        return rc;
      }
      // A SKIP (e.g. a scenario whose surface does not exist on desktop — the
      // Batch-2 avatar cases) is NOT a pass and NOT a failure: log it and move
      // on without updating pairState (the scenario did nothing). Without this,
      // a SKIP returning 0 would be tallied upstream as a PASS.
      if (rc == _realUiSkipExitCode) {
        stdout.writeln(
          '[unified] SKIP real-ui scenario "$scenario" (surface n/a)',
        );
        continue;
      }
      if (rc != 0 && resetApplied) {
        rc = await _retryRealUiScenarioFromFreshLaunch(
          requiredState: requiredState,
          driver: planned.entry.driver,
          scenario: scenario,
          pairActiveSetter: () {
            pairActive = true;
            pairState = requiredState;
          },
          reason:
              'real-ui reset reuse failed before "$scenario"; relaunching fresh',
          attempts: _maxRealUiAttempts(requiredState),
        );
      } else if (rc != 0 && _maxRealUiAttempts(requiredState) > 1) {
        rc = await _retryRealUiScenarioFromFreshLaunch(
          requiredState: requiredState,
          driver: planned.entry.driver,
          scenario: scenario,
          pairActiveSetter: () {
            pairActive = true;
            pairState = requiredState;
          },
          reason:
              'real-ui scenario "$scenario" failed on a no-friend launch; retrying fresh',
          attempts: _maxRealUiAttempts(requiredState) - 1,
        );
      }
      if (rc != 0) {
        return rc;
      }
      pairState = _resultRealUiState(scenario);
      pairNeedsRestoreBoot = false;
      previousScenario = scenario;
    }
    return 0;
  } finally {
    if (pairActive) {
      await _bestEffortStopRealUiPair();
    }
  }
}

int _maxRealUiAttempts(String requiredState) {
  if (requiredState == _realUiStateNoFriend) {
    return 2;
  }
  if (requiredState == _realUiStateFriends) {
    return 2;
  }
  return 1;
}

Future<int> _retryRealUiScenarioFromFreshLaunch({
  required String requiredState,
  required String driver,
  required String scenario,
  required void Function() pairActiveSetter,
  required String reason,
  required int attempts,
}) async {
  for (var attempt = 1; attempt <= attempts; attempt++) {
    stdout.writeln('[unified] $reason (attempt $attempt/$attempts)');
    await _bestEffortStopRealUiPair();
    final relaunchRc = await _launchRealUiPair(
      restore: _restoreForRealUiState(requiredState),
    );
    if (relaunchRc != 0) {
      return relaunchRc;
    }
    pairActiveSetter();
    final rc = await _executeRealUiScenario(
      driver,
      scenario,
      bootRestored: requiredState == _realUiStateFriends,
    );
    if (rc == 78 || rc == _realUiSkipExitCode) {
      return rc;
    }
    if (rc == 0) {
      return 0;
    }
  }
  return 1;
}

Future<int> _executeRealUiScenario(
  String driver,
  String scenario, {
  required bool bootRestored,
}) async {
  final runtime = _RuntimePair.load(
    _realUiPairJson(),
    fallbackNickA: _defaultRealUiNickA,
    fallbackNickB: _defaultRealUiNickB,
  );
  return _runProcess([
    'dart',
    'run',
    'tool/mcp_test/$driver',
    if (bootRestored) '--boot-restored',
    scenario,
    runtime.a.wsUri,
    '${runtime.a.pid}',
    runtime.a.nickname,
    runtime.b.wsUri,
    '${runtime.b.pid}',
    runtime.b.nickname,
  ], environment: _realUiDriverEnv());
}

Future<int> _executeInternalRealUiReset() async {
  final runtime = _RuntimePair.load(
    _realUiPairJson(),
    fallbackNickA: _defaultRealUiNickA,
    fallbackNickB: _defaultRealUiNickB,
  );
  return _runProcess([
    'dart',
    'run',
    'tool/mcp_test/drive_real_ui_pair.dart',
    _internalRealUiResetScenario,
    runtime.a.wsUri,
    '${runtime.a.pid}',
    runtime.a.nickname,
    runtime.b.wsUri,
    '${runtime.b.pid}',
    runtime.b.nickname,
  ], environment: _realUiDriverEnv());
}

Future<int> _launchPair({String? restore, bool tcpOnly = false}) async {
  final env = <String, String>{
    ...Platform.environment,
    if (restore != null && restore.isNotEmpty)
      'TOXEE_FIXTURE_C_RESTORE': restore,
    // Same-host NGC discovery is ~40% flaky over UDP; TCP-only (A as relay,
    // both forced TCP) makes it deterministic for the NGC reuse group.
    if (tcpOnly) 'TOXEE_PAIR_TCP_ONLY': '1',
  };
  return _runProcess([
    'bash',
    'tool/mcp_test/launch_fixture_c_pair.sh',
  ], environment: env);
}

Future<void> _bestEffortStopPair() async {
  await Process.run('bash', ['tool/mcp_test/stop_fixture_c_pair.sh']);
}

Future<int> _launchRealUiPair({String? restore}) async {
  final cfg = _realUiConfig;
  if (cfg.prebuildOnHost) {
    // macOS only: build the debug Toxee.app once via run_toxee.sh before the
    // pair launch (the iOS/Android/Windows launch scripts self-build, so the
    // runner skips this for them).
    final buildRc = await _runProcess(
      ['bash', 'run_toxee.sh', '--skip-bootstrap'],
      environment: {
        ...Platform.environment,
        'MCP_BINDING': 'skill',
        'TOXEE_L3_TEST': 'true',
        'TOXEE_BUILD_ONLY': '1',
      },
    );
    if (buildRc != 0) return buildRc;
  }
  final env = <String, String>{
    ...Platform.environment,
    if (restore != null && restore.isNotEmpty)
      'TOXEE_FIXTURE_C_RESTORE': restore,
    // Android: hand the fixed IRC loopback port to the launcher so it can
    // `adb reverse` it on both devices before the driver binds the server.
    if (cfg.ircLoopbackPort != null)
      'TOXEE_IRC_LOOPBACK_PORT': cfg.ircLoopbackPort!,
  };
  final rc = await _runProcess(
    _realUiScriptExecCommand(cfg.launchScript),
    environment: env,
  );
  if (rc != 0) {
    // A failed pair launch can leave one instance running (e.g. A came up, B
    // failed) — the launch returns non-zero before the runner marks the pair
    // active, so its outer finally won't stop it. Best-effort tear down here so
    // a stray instance doesn't leak or hold a fixed VM/IRC port for the retry.
    await _bestEffortStopRealUiPair();
  }
  return rc;
}

Future<void> _bestEffortStopRealUiPair() async {
  final cmd = _realUiScriptExecCommand(_realUiConfig.stopScript);
  await Process.run(cmd.first, cmd.sublist(1));
}

Future<int> _runProcess(
  List<String> command, {
  Map<String, String>? environment,
}) async {
  stdout.writeln('[unified] \$ ${command.map(_shellLiteral).join(' ')}');
  final process = await Process.start(
    command.first,
    command.sublist(1),
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

class _RuntimePair {
  _RuntimePair({required this.a, required this.b});

  final _RuntimeInst a;
  final _RuntimeInst b;

  static _RuntimePair load(
    String path, {
    String fallbackNickA = _defaultRealUiNickA,
    String fallbackNickB = _defaultRealUiNickB,
  }) {
    final root =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final instances = (root['instances'] as Map).cast<String, dynamic>();
    final restored =
        (((root['fixture_restore'] as Map?)?['restored'] as Map?)?['instances']
                as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    String restoredNick(String name, String fallback) {
      final raw = ((restored[name] as Map?)?['nickname'])?.toString();
      return (raw == null || raw.isEmpty) ? fallback : raw;
    }

    _RuntimeInst loadInst(String name, String fallbackNick) {
      final raw = (instances[name] as Map).cast<String, dynamic>();
      return _RuntimeInst(
        wsUri: raw['ws_uri']?.toString() ?? '',
        pid: (raw['pid'] as num?)?.toInt() ?? 0,
        nickname: restoredNick(name, fallbackNick),
      );
    }

    return _RuntimePair(
      a: loadInst('A', fallbackNickA),
      b: loadInst('B', fallbackNickB),
    );
  }
}

class _RuntimeInst {
  _RuntimeInst({
    required this.wsUri,
    required this.pid,
    required this.nickname,
  });

  final String wsUri;
  final int pid;
  final String nickname;
}
