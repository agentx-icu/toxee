// Real-UI two-process scenario catalog (the `--real-ui-scenario=` vocabulary).
//
// Split out of `fixture_c_unified_runner.dart` for the same reason the mobile
// campaign matrix was (see fixture_c_real_ui_mobile_campaigns.dart): this is
// DATA plus the rationale for every batch, it grew faster than the runner's
// logic, and the runner is pinned in `tool/.complexity_baseline.txt`. The
// runner aliases it as `_validRealUiScenarios`, so `--real-ui-scenario=`,
// campaign expansion and the unknown-name rejection all behave unchanged.
//
// A name here is only half the contract: every scenario must ALSO appear in
// the runner's `_requiredRealUiState` / `_resultRealUiState` switches, which
// throw on an unknown name — that is what stops a scenario being listed but
// never planned.

const realUiScenarioNames = <String>{
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
  // drive the real avatar control with deterministic fixed picker-path input.
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
  // individually runnable; sweep_login chains them on one launch. Case 26 taps
  // the real restore card with deterministic invalid-file picker input.
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
  'global_search_group_opens_chat',
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
  'system_back_unbinds_chat',
  'group_profile_send_binds',
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
  // FORM-FACTOR cases (mobile shell / tablet layout). These are the first
  // scenarios that drive controls which exist ONLY on the mobile shell (bottom
  // navigation, the mobile composer send button, the long-press message menu)
  // or assert the tablet-only master-detail split — the `rui-ios-*`/`rui-ipad-*`
  // campaigns before them only RE-RAN the desktop sweeps on a smaller screen.
  // Each case detects its layout tier from live signals (`home_bottom_nav`
  // onstage / `homeShellShouldShowMasterDetail`) and SKIPs (exit 75) when the
  // running shell has no such surface, so the same scenario list is safe to
  // point at any platform. sweep_mobile_shell chains the phone cases on one
  // launch; sweep_tablet_layout chains the wide-layout ones.
  'sweep_mobile_shell',
  'sweep_tablet_layout',
  'mobile_bottom_nav_tab_switch',
  'mobile_composer_send_button_reveals',
  'mobile_composer_send_delivers',
  'mobile_message_long_press_menu',
  'tablet_master_detail_row_opens_chat',
  'dialog_width_form_factor_tier',
  // MESSAGE MULTI-SELECT (the surface behind `message_menu_item:multiSelect`).
  // Before this batch the multiSelect menu entry was keyed but never driven, so
  // the toolbar that REPLACES the composer in select mode, its delete/forward
  // affordances, the delete confirmation dialog and the select-mode header bar
  // were all dark — and none of them carried a key at all. Two-process:
  // required=no-friend (the sweep does its OWN handshake and reuses an existing
  // one) / result=friends (nothing here deletes the friend; the only delete is
  // of the case's own throwaway custom bubble).
  //
  // Every case seeds an inbound CUSTOM message: the fork strips
  // `_uikit_multi_message` from TEXT and file/image/video/sound menus, so a
  // custom bubble is the only reachable way into select mode (the same reason
  // `reply_quote_real` uses one). If a build offers no multiSelect entry at all,
  // the cases SKIP with that reason rather than failing.
  'sweep_msg_select',
  'msg_select_enter_and_cancel',
  'msg_select_delete_cancel_keeps_message',
  'msg_select_delete_for_me_removes_row',
  'msg_select_forward_surface',
  // KEYED-BUT-NEVER-DRIVEN batch #2. Eight single-instance cases (A only) over
  // three surfaces that carried ValueKeys no scenario had ever touched: the
  // RegisterPage status field / confirm-match badge / confirm visibility toggle
  // / password-strength SEGMENTS, the Applications-page IRC dialog Cancel +
  // password-visibility toggle, the per-channel Remove row, and the IRC card's
  // Uninstall action — plus the add-group TYPE SELECTOR itself (the existing
  // `group_create_type_selector_surface` only asserts the three segment keys
  // render; this one drives the selection and asserts the per-type hint swaps).
  //
  // required=no-friend / result=no-friend: nothing here forms or deletes a
  // friendship, creates a group, or registers an account, which is what lets
  // the runner APPEND `sweep_keyed_gaps` to an existing campaign chain with no
  // reset and no extra pair launch (startup reuse is the default). Registered
  // into rui-app-entry-extra + the rui-{ios,ipad,android}-account-settings /
  // -main chains rather than getting a campaign of its own.
  //
  // Verify-first exclusions documented in drive_real_ui_pair_keyed_gaps.dart:
  // the av_conference_* / call_camera_switch_button keys have no constructible
  // precondition, the message_attachment_{image,photo,video,search}_button
  // fork keys are dead under toxee's attachment config, and
  // add_group_copy_id_button is unreachable because the dialog always pops on
  // create success.
  'sweep_keyed_gaps',
  'add_group_type_selector_hint_switches',
  'irc_channel_dialog_cancel_discards',
  'irc_channel_remove_row_confirm',
  'irc_app_uninstall_reinstall_card',
  'register_status_field_length_guard',
  'register_confirm_match_icon_flips',
  'register_confirm_visibility_toggle_flips',
  'register_strength_segments_ramp',
  // KEYED-BUT-NEVER-DRIVEN batch #3 — the LAST tranche. Ten TWO-PROCESS cases
  // over five surfaces whose ValueKeys no scenario had ever touched: the
  // message menu's `revealFileLocation` / `readReceipt` entries, the friend
  // application DETAIL screen's Decline twin, the friend profile's Tox-ID copy
  // button, the desktop composer's personal-card entry, the member-info route's
  // Profile entry, the mobile member sheet's Cancel action, and the group
  // profile's real add-member row / scroll view / rename DIALOG (cancel branch).
  //
  // required=no-friend (the sweep runs its OWN handshake and reuses an existing
  // one) / result=friends (nothing deletes the friend; the group half creates
  // ONE group for all six group cases and leaves it in cleanup). Registered
  // into rui-msg-select-adjacent chains rather than getting a launch of its own.
  //
  // Verify-first exclusions documented in drive_real_ui_pair_keyed_gaps3.dart:
  // `message_menu_item:translate` is stripped for EVERY elemType,
  // `message_menu_item:convertToText` needs a plugin gated behind a
  // `const false`, `contact_group_notifications_tab` and
  // `group_invite_accept_button` sit on surfaces the toxee fork deleted /
  // never routes to, and `contact_app_bar_add_group_item` only renders when
  // HomePage's trailing-hook override is absent.
  'sweep_keyed_gaps3',
  'contact_application_detail_decline_removes_row',
  'friendprof_copy_toxid_snackbar',
  'msgmenu_reveal_file_location_gating',
  'msgmenu_read_receipt_group_gating',
  'personal_card_send_c2c',
  'group_member_info_profile_entry_opens_profile',
  'group_member_action_cancel_closes_sheet',
  'group_add_member_button_opens_picker',
  'group_profile_scroll_view_scrolls',
  'group_profile_edit_name_dialog_cancel',
  // KEYED-BUT-NEVER-DRIVEN batch #4. Re-derived from scratch (registry keys +
  // every ValueKey literal under lib/ui, lib/call and the fork, MINUS every
  // string that appears in non-comment driver code): 33 keys were genuinely
  // undriven, and these ten cases drive 16 of them.
  //
  // `sweep_keyed_gaps4` is TWO-PROCESS, required=no-friend (own handshake,
  // reuses an existing one) / result=friends — the two @-mention cases share
  // ONE throwaway group that the shared `_kg3WithGroup` cleanup leaves.
  // `sweep_keyed_gaps4_login` is SINGLE-instance and
  // required=no-friend / result=no-friend: its case logs out, registers a
  // throwaway account, deletes it from the LoginPage and logs back into the
  // primary. They are separate sweeps because their state contracts differ.
  //
  // Five controls had NO key at all and got an ADDITIVE fork key with this
  // batch (mobile composer "+" and its panel entries, the hold-to-record mic,
  // and the whole mobile @-mention picker). Verify-first exclusions live in
  // drive_real_ui_pair_keyed_gaps4.dart: the av_conference_* family has no
  // constructible precondition, `draft_persistence_text` renders only under a
  // WidgetTester-only debug flag, `pairing_qr_url` is behind a `const false`
  // feature flag, `group_avatar_*` is a cache-busting KeyedSubtree rather than
  // a control, and the two `user_profile_*_dialog` container keys are redundant
  // handles on dialogs whose keyed CHILDREN existing cases already gate on.
  'sweep_keyed_gaps4',
  'sweep_keyed_gaps4_login',
  'msg_select_clear_button_resets_count',
  'msg_select_forward_combined_absent_gating',
  'attachment_toolbar_disabled_entries_gating',
  'mobile_attachment_panel_entries',
  'mobile_voice_record_button_reveals',
  'message_viewer_save_and_zoom_surface',
  'mobile_chats_unread_badge_flips',
  'mobile_chat_back_clears_active_peer',
  'mobile_mention_picker_confirm_inserts',
  'mobile_mention_picker_back_empty_selection',
  'mobile_mention_at_all_inserts',
  'mobile_search_contact_back_unbinds',
  'login_account_delete_confirm_removes_card',
};
