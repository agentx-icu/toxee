// Mobile real-UI campaign catalog (iPhone / iPad / Android).
//
// Split out of `fixture_c_unified_runner.dart` so the runner stays under its
// `tool/.complexity_baseline.txt` pin: the campaign map is DATA plus the
// rationale for each grouping, and it grew faster than the runner's logic.
// The runner merges this map into `_realUiCampaigns`, so `--real-ui-campaign=`,
// `--list-real-ui-campaigns` and the rui-ipad-* device-type override all keep
// working unchanged.
//
// Each value is an ORDERED list of sweep scenario names; the runner keeps one
// pair launch alive across the whole list and inserts an in-place
// friendship reset (`_executeInternalRealUiReset`) only when the previous
// sweep's RESULT state differs from the next sweep's REQUIRED state.

const mobileRealUiCampaigns = <String, List<String>>{
  // Every sweep registered below declares `required=no-friend`, and the
  // friends->no-friend transition is done IN PLACE by
  // `_executeInternalRealUiReset()` (no relaunch), so any ORDER is self
  // consistent. The chains are still ordered `result=no-friend` sweeps FIRST so
  // the runner does not have to insert a reset between them.
  //
  // BUDGET / SIMULATOR LIFECYCLE: any campaign here that chains >= 2 sweeps
  // must be launched with `export TOXEE_IOS_KEEP_SIMULATOR_FRONT=1` on
  // iOS/iPadOS. A backgrounded Simulator has its apps reclaimed by iOS after
  // ~2-3 min (see launch_toxee_ios_instance.sh) — App Nap disable + caffeinate
  // do NOT help — which kills a long chain mid-run. The runner only PASSES
  // THROUGH `Platform.environment` and deliberately never sets the flag
  // itself: topping the Simulator window steals the host's focus, so that
  // stays the caller's call. See REAL_UI_TWO_PROCESS.md "Mobile campaign
  // budget".
  //
  // DELIBERATELY NOT REGISTERED IN ANY MOBILE CAMPAIGN (do not "fix" these by
  // adding them):
  //   * `sweep_p1_relaunch` / `sweep_p2_keys` — both restart a peer via
  //     `Process.run('tool/mcp_test/stop_toxee_instance.sh' /
  //     'launch_toxee_instance.sh')` (drive_real_ui_pair_p1_relaunch.dart:773
  //     / :803). Those are the macOS DESKTOP single-instance launchers:
  //     pointing them at an iOS/Android pair would boot a macOS Toxee.app and
  //     overwrite the pair manifest, so the "restarted peer" would not be the
  //     device under test and the rest of the run would drive the wrong
  //     process.
  //   * `sweep_p2_verify` — `paste_image_into_composer` needs an IMAGE on the
  //     host pasteboard; the portable seam (`l3_set_clipboard`) is text-only,
  //     so the precondition cannot be constructed on a device.
  //   * `sweep_group_mention` — `osaType('@')` IS the trigger under assertion.
  //     Substituting an l3/skill text seam would bypass the exact keystroke
  //     path the case exists to prove, leaving a green case that asserted
  //     nothing.
  //   * the four `*_optimized` bundles — pure re-orchestration of sweeps that
  //     are already listed here; they would only double-count the same cases.
  //   * `sweep_mobile_shell` in any `rui-ipad-*` campaign, and
  //     `sweep_tablet_layout` in any iPhone campaign — on the wrong form
  //     factor every case SKIPs, which inflates the skip tally without adding
  //     any coverage.

  // ---- iPhone (rui-ios-*, plus the platform-agnostic rui-mobile-shell) ----
  // iOS true-App first-pass coverage. These sweeps start from fresh accounts
  // and establish any needed friendship/group state internally, so they do not
  // rely on the macOS-only restored Fixture C pair.
  // `sweep_keyed_gaps` rides along here (and in the iPad/Android twins below)
  // instead of getting its own campaign: it is single-instance,
  // required=no-friend / result=no-friend, and it drives the SAME LoginPage /
  // RegisterPage surface `sweep_login` already logs out onto — so the runner
  // reuses one launch and inserts no reset. Its input path is `focusType` only
  // (real paste on desktop, flutter_skill `enterText` on a device), with ZERO
  // `osa*` chords, so it is honest on a Simulator/emulator today.
  // `sweep_keyed_gaps4_login` is appended for the same reason as
  // `sweep_keyed_gaps`: single-instance, required=no-friend / result=no-friend,
  // and it drives the SAME LoginPage surface `sweep_login` already logs out
  // onto (it registers a throwaway account, deletes it through the real
  // LoginPage confirm dialog and quick-logs back into the primary in a
  // `finally`). Its only input path is `focusType`, which is atomic on every
  // platform, so there are no `osa*` chords to be silent on a Simulator.
  'rui-ios-account-settings': [
    'sweep_login',
    'sweep_ios_settings_main',
    'sweep_keyed_gaps',
    'sweep_keyed_gaps4_login',
  ],
  // sweep_msg_select is appended here (rather than given a launch of its own in
  // the broad runs) because it is the "startup reuse is the default" case: it
  // needs exactly what sweep_chat already leaves behind — a live A<->B
  // friendship and an open C2C conversation. Its required state is no-friend, so
  // the runner inserts one in-place reset before it, the same as it already does
  // between sweep_chat and sweep_group2.
  // `sweep_keyed_gaps4` follows `sweep_keyed_gaps3` for the same reason: same
  // required=no-friend / result=friends contract, with its own handshake and its
  // own throwaway group, so it needs no extra LAUNCH. It does still get an
  // in-place reset: `result=friends` -> `required=no-friend` is exactly the
  // transition `_executeInternalRealUiReset()` handles without relaunching
  // (fixture_c_unified_runner.dart, the `_realUiStateFriends` ->
  // `_realUiStateNoFriend` arm), same as between `sweep_chat` and
  // `sweep_group2`. On an iPHONE it is the highest-value member of this chain —
  // SIX of its nine cases gate on the live layout tier and SKIP on the other
  // one: `mobile_attachment_panel_entries`,
  // `mobile_voice_record_button_reveals`, `mobile_chats_unread_badge_flips` and
  // both `mobile_mention_picker_*` need the NARROW shell, while
  // `attachment_toolbar_disabled_entries_gating` needs the DESKTOP composer.
  // Those six are the sweep's ONLY declared skips
  // (`_keyedGaps4ExpectedSkipCases` in drive_real_ui_pair_sweep_tally.dart);
  // anything else that skips now FAILS the sweep.
  'rui-ios-chat-main': [
    'sweep_chat',
    'sweep_group2',
    'sweep_msg_select',
    'sweep_keyed_gaps3',
    'sweep_keyed_gaps4',
  ],
  // PHONE-shell exclusive controls (bottom nav, mobile composer send button,
  // long-press message menu) + the compact dialog-width tier. Deliberately NOT
  // in the rui-ipad-* campaigns: on a tablet every case would SKIP (the wide
  // shell renders the sidebar rail and the desktop composer), which would only
  // inflate the skip tally.
  'rui-mobile-shell': ['sweep_mobile_shell'],
  'rui-ios-main': [
    'sweep_login',
    'sweep_ios_settings_main',
    'sweep_chat',
    'sweep_group2',
    'sweep_mobile_shell',
  ],

  // iPhone WAVE 1 — sweeps whose chains contain ZERO `osa*` call sites, so they
  // need no driver change to be honest on a Simulator today.
  //
  // Self profile: 8 cases, single-instance (drives A only),
  // required=no-friend / result=no-friend, so it composes with anything without
  // a reset. Kept as its own campaign (rather than folded into rui-ios-main)
  // because it is the largest A-only chain and is useful as a fast smoke.
  'rui-ios-profile': ['sweep_profile'],
  // C2C reply: 1 case (reply_quote_real), two-process, required=no-friend /
  // result=friends. Injects a custom inbound bubble and drives the REAL message
  // menu Reply item — no keystrokes involved, hence Wave 1.
  'rui-ios-p2-reply': ['sweep_p2_reply'],
  // P3 writable subset: 1 live case (message_burst_perf), two-process,
  // required=no-friend / result=friends. Pure l3 seeding + timing assertions.
  'rui-ios-p3-writable': ['sweep_p3_writable'],
  // Deep follow-ups, 4 cases on ONE launch: sweep_c2c_deep_extra (1 —
  // c2c_search_result_opens_target_message) + sweep_group_conf_deep_extra (3 —
  // two member-role/remove gates plus a documented same-host conference SKIP).
  // Both are required=no-friend / result=friends, so chaining them costs
  // exactly one internal reset between the two sweeps; they are grouped
  // because each on its own would waste a whole pair launch on 1-3 cases.
  'rui-ios-deep-extra': ['sweep_c2c_deep_extra', 'sweep_group_conf_deep_extra'],
  // Message multi-select: 4 cases, two-process, required=no-friend /
  // result=friends. Wave 1 — the chain contains ZERO `osa*` call sites (real
  // taps + the `l3_inject_c2c_custom` seed seam only), so it is honest on a
  // Simulator today. Standalone campaign for focused debugging; the broad iPhone
  // run gets it through rui-ios-chat-main.
  'rui-ios-msg-select': ['sweep_msg_select'],
  // Keyed-but-never-driven batch #3: 10 cases, two-process, required=no-friend /
  // result=friends. Same launch-reuse contract as sweep_msg_select (it runs its
  // OWN handshake and creates ONE throwaway group), so the broad iPhone run gets
  // it through rui-ios-chat-main; this entry is for focused debugging.
  'rui-ios-keyed-gaps3': ['sweep_keyed_gaps3'],
  // Keyed-but-never-driven batch #2: 8 cases, SINGLE-instance (A only),
  // required=no-friend / result=no-friend. The broad iPhone run gets it through
  // rui-ios-account-settings (where it reuses sweep_login's launch); this entry
  // exists only for focused debugging of the batch on its own launch.
  'rui-ios-keyed-gaps': ['sweep_keyed_gaps'],
  // Keyed-but-never-driven batch #4: 9 cases, two-process, required=no-friend /
  // result=friends. Wave 1 — ZERO `osa*` call sites (real taps plus the
  // `l3_composer_set_text` / `l3_send_file` / `l3_group_member_list` seams), so
  // it is honest on a Simulator today. The broad iPhone run gets it through
  // rui-ios-chat-main; this entry is for focused debugging.
  'rui-ios-keyed-gaps4': ['sweep_keyed_gaps4'],
  // The SINGLE-instance login half on its own launch, for focused debugging of
  // the LoginPage delete-confirm flow. The broad run gets it through
  // rui-ios-account-settings.
  'rui-ios-keyed-gaps4-login': ['sweep_keyed_gaps4_login'],

  // iPhone WAVE 2 — unblocked by the iOS `osa*` branch work (until that lands,
  // these chains contain call sites that were silent no-ops on a Simulator).
  // Registered now so the campaign catalog is the single place that describes
  // the intended mobile matrix; run them only after the iOS branches are in.
  //
  // Settings sweep 2: 12 cases, single-instance,
  // required=no-friend / result=no-friend. LONGEST single chain in Wave 2 —
  // export TOXEE_IOS_KEEP_SIMULATOR_FRONT before running it.
  'rui-ios-settings2': ['sweep_settings2'],
  // P1 single-instance account/locale/conference: 5 cases,
  // required=no-friend / result=no-friend (the sweep's end-clean returns to the
  // primary account and EN locale).
  'rui-ios-p1-single': ['sweep_p1_single'],
  // Account-management + conference expansion: 6 cases, single-instance,
  // required=no-friend / result=no-friend (every case cleans its throwaway
  // account/conference and never forms a friendship).
  'rui-ios-account-conf': ['sweep_account_conf_extra'],
  // Focused C2C expansion: 5 cases, two-process,
  // required=no-friend / result=friends (all cancel-branches; the sweep
  // re-seeds a visible row at the end).
  'rui-ios-c2c-extra': ['sweep_c2c_extra'],
  // Native/mobile boundary probes: 6 cases, two-process,
  // required=no-friend / result=friends. Highest-value on a REAL phone shell —
  // this is the sweep whose SKIP reasons are all about OS dialog / link /
  // permission seams, which is exactly the surface a Simulator run is meant to
  // characterize.
  'rui-ios-boundary-guards': ['sweep_native_boundary_guards'],
  // Account deep expansion: 1 case (account_multi_account_state_isolation),
  // single-instance, required=no-friend / result=no-friend.
  'rui-ios-account-deep': ['sweep_account_deep_extra'],

  // iPhone WAVE 3 — additionally gated on the long-press menu / bottom-bar /
  // coordinate work for the narrow shell. These are the biggest chains in the
  // matrix, so each gets its OWN campaign (one long chain per launch keeps the
  // Simulator-lifetime budget manageable even with KEEP_SIMULATOR_FRONT).
  //
  // Conversation list C2C: 10 cases, two-process,
  // required=no-friend / result=friends.
  'rui-ios-conv': ['sweep_conv'],
  // Calls + misc: 11 cases, two-process, required=no-friend / result=friends.
  // Includes window_resize_responsive, which SKIPs on a Simulator (no window to
  // size-script) — expected, not a regression.
  'rui-ios-calls-misc': ['sweep_calls_misc'],
  // Three-instance @-mention multi-select on iOS: same case; C is a macOS
  // process on the host (Simulators share the host loopback for the relay).
  'rui-ios-mention-multi': ['mobile_mention_multi_select_inserts'],
  // Contacts / friend profile: 15 cases, two-process,
  // required=no-friend / result=NO-FRIEND (the chain deletes the friend last).
  // LONGEST chain in the whole mobile matrix — KEEP_SIMULATOR_FRONT is
  // effectively mandatory here even though it is a single sweep.
  'rui-ios-contacts': ['sweep_contacts'],
  // Group/conference member management on the PHONE shell — same 5 cases as
  // rui-ipad-group-member; the member-menu helpers are per-shell.
  'rui-ios-group-member': ['sweep_group_conf_member_extra'],
  // P1 chat octet on the PHONE shell (draft-restore stays a documented
  // keyboard-capability SKIP here; the other 7 cases run for real).
  'rui-ios-p1-chat': ['sweep_p1_chat'],

  // ---- iPad (rui-ipad-*; forces TOXEE_IOS_DEVICE_TYPE=tablet) ----
  // iPad true-App coverage: the SAME sweeps as the iPhone campaigns — the
  // sweeps already branch on the wide/tablet layout at runtime
  // (_settingsIsWide, inst.isIos scroll bands) — but the pair is launched on
  // iPad simulators: selecting a rui-ipad-* campaign makes the runner force
  // TOXEE_IOS_DEVICE_TYPE=tablet into the launch env (launch_ios_fixture_c_
  // pair.sh then matches *iPad* simulators). Requires --real-ui-platform=ios.
  'rui-ipad-account-settings': [
    'sweep_login',
    'sweep_ios_settings_main',
    'sweep_keyed_gaps',
    'sweep_keyed_gaps4_login',
  ],
  // On a TABLET `sweep_keyed_gaps4` is a genuinely different data point, not a
  // duplicate — but NOT for the reason this comment used to give. iPad mounts
  // the MOBILE composer: `TencentCloudChatMessageInput.tabletAppBuilder`
  // delegates to `defaultBuilder`, which builds
  // `TencentCloudChatMessageInputMobile`; only `desktopBuilder` builds the
  // desktop input. Live-proved 2026-08-16 — `mobile_attachment_panel_entries`
  // and `mobile_voice_record_button_reveals` PASS on iPad, and
  // `attachment_toolbar_disabled_entries_gating` SKIPs there with "the MOBILE
  // composer is mounted", so its desktop-composer branch is reachable only on a
  // real desktop run. What IS tablet-specific here: the select-mode forward
  // case hits `tabletAppBuilder`'s inline per-type buttons instead of the phone
  // bottom sheet, and `mobile_chats_unread_badge_flips` is the batch's only
  // tablet skip (it gates on `_msPhoneShell`, i.e. the bottom nav).
  'rui-ipad-chat-main': [
    'sweep_chat',
    'sweep_group2',
    'sweep_msg_select',
    'sweep_keyed_gaps3',
    'sweep_keyed_gaps4',
  ],
  // TABLET-exclusive layout behaviour the shared sweeps never assert: the
  // master-detail row->right-pane binding and the wide dialog-width tier.
  // (Forces iPad simulators like every other rui-ipad-* campaign.)
  'rui-ipad-layout': ['sweep_tablet_layout'],
  'rui-ipad-main': [
    'sweep_login',
    'sweep_ios_settings_main',
    'sweep_chat',
    'sweep_group2',
    'sweep_tablet_layout',
  ],

  // iPad WAVE 1 — same zero-`osa*` sweeps as the iPhone Wave 1, on tablets.
  //
  // Self profile: 8 cases, single-instance,
  // required=no-friend / result=no-friend. On iPad the profile pages render in
  // the wide split, which is a different layout branch from the iPhone run —
  // hence a real second data point, not a duplicate.
  'rui-ipad-profile': ['sweep_profile'],
  // Deep follow-ups, 4 cases on ONE launch (1 + 3, one internal reset between
  // the two sweeps); both required=no-friend / result=friends.
  'rui-ipad-deep-extra': [
    'sweep_c2c_deep_extra',
    'sweep_group_conf_deep_extra',
  ],
  // Message multi-select on a TABLET is a genuinely different data point, not a
  // duplicate of the iPhone run: `tabletAppBuilder` renders the per-type forward
  // BUTTONS directly, where the phone `defaultBuilder` renders one icon that
  // opens a forward-type bottom sheet. The case detects which is mounted.
  'rui-ipad-msg-select': ['sweep_msg_select'],
  'rui-ipad-keyed-gaps3': ['sweep_keyed_gaps3'],
  // Batch #2 on a TABLET: same 8 single-instance cases, but the register /
  // IRC / add-group dialogs render at the wide dialog tier here, which is a
  // different layout branch from the iPhone run. Broad iPad runs get it through
  // rui-ipad-account-settings; this entry is for focused debugging.
  'rui-ipad-keyed-gaps': ['sweep_keyed_gaps'],
  'rui-ipad-keyed-gaps4': ['sweep_keyed_gaps4'],
  'rui-ipad-keyed-gaps4-login': ['sweep_keyed_gaps4_login'],
  // Group/conference member management: 5 cases, two-process,
  // required=no-friend / result=friends. The chain is platform-aware now
  // (_openPeerMemberMenu drives the desktop popup OR the mobile action
  // sheet; every menu key resolves per-shell), so the phone entry exists
  // alongside the tablet one.
  'rui-ipad-group-member': ['sweep_group_conf_member_extra'],

  // iPad WAVE 2 — mirrors the iPhone Wave 2; same iOS `osa*` dependency (the
  // no-op applies to the whole iOS family, phone and tablet alike).
  //
  // Settings sweep 2: 12 cases, single-instance,
  // required=no-friend / result=no-friend. Exercises the `_settingsIsWide`
  // branch that the iPhone run never takes.
  'rui-ipad-settings2': ['sweep_settings2'],
  // P1 single-instance account/locale/conference: 5 cases,
  // required=no-friend / result=no-friend.
  'rui-ipad-p1-single': ['sweep_p1_single'],
  // Account-management + conference expansion: 6 cases, single-instance,
  // required=no-friend / result=no-friend.
  'rui-ipad-account-conf': ['sweep_account_conf_extra'],
  // Focused C2C expansion: 5 cases, two-process,
  // required=no-friend / result=friends.
  'rui-ipad-c2c-extra': ['sweep_c2c_extra'],
  // NOTE: sweep_native_boundary_guards / sweep_account_deep_extra stay
  // iPhone-only for now — both are about phone-shaped OS seams (permission
  // sheets, notification routing) where the tablet run would assert the same
  // thing at twice the launch cost. Promote them here if a tablet-specific
  // seam appears.

  // iPad WAVE 3 — additionally gated on the long-press menu / bottom-bar /
  // coordinate work. One long chain per campaign.
  //
  // Conversation list C2C: 10 cases, two-process,
  // required=no-friend / result=friends. On iPad the row tap binds the
  // master-detail right pane instead of pushing a route.
  'rui-ipad-conv': ['sweep_conv'],
  // Calls + misc: 11 cases, two-process, required=no-friend / result=friends.
  'rui-ipad-calls-misc': ['sweep_calls_misc'],
  // Contacts / friend profile: 15 cases, two-process,
  // required=no-friend / result=NO-FRIEND (deletes the friend last).
  'rui-ipad-contacts': ['sweep_contacts'],
  // P1/P2/P3 two-process chat/conv octet: 8 cases,
  // required=no-friend / result=friends.
  'rui-ipad-p1-chat': ['sweep_p1_chat'],

  // ---- Android (rui-android-*; requires --real-ui-platform=android) ----
  // Android true-App bundles. Same platform-agnostic sweeps; select with
  // `--real-ui-platform=android` (the campaign name does not force it — only
  // the rui-ipad-* device-type override does).
  //
  // STATUS: the Android pair DOES reach the business layer (both instances log
  // `app.started` + `imsdk version arm64` and fire the Badge launcher probe,
  // which only a logged-in session can trigger — `BadgeService.instance.start`
  // is called from lib/runtime/session_runtime_coordinator.dart:298). The FIRST
  // scenario-level green run landed 2026-08-16: `rui-android-msg-select`
  // (`sweep_msg_select`, all four cases) went passed=4 failed=0 skipped=0 on
  // two emulators (`emulator-5554` / `emulator-5556`), including the live A<->B
  // friendship the sweep establishes itself — see REAL_UI_TWO_PROCESS.md
  // "Android status". Every OTHER `rui-android-*` campaign is still unproven:
  // do not report those as android-green until each has its own run. (A missing
  // `.android_runtime/*/pair.json` is NOT the evidence it used to be treated as
  // — stop_android_fixture_c_pair.sh:55 deletes it on every normal teardown.)
  //
  // Unlike iOS, Android is in `_isHeadlessRealUi`
  // (drive_real_ui_pair_inst.dart:212), so the `osa*` surface routes to the
  // l3/skill substitutes instead of silently no-oping — that is why the Android
  // list is not split into waves. Pure-keyboard-shortcut cases still SKIP,
  // because a substitute is not a real OS keyboard.
  'rui-android-mobile-shell': ['sweep_mobile_shell'],
  'rui-android-main': [
    'sweep_login',
    'sweep_keyed_gaps',
    'sweep_keyed_gaps4_login',
    'sweep_chat',
    'sweep_mobile_shell',
    'sweep_msg_select',
    'sweep_keyed_gaps3',
    'sweep_keyed_gaps4',
  ],
  // Keyed-gaps batch #2: single-instance, required=no-friend /
  // result=no-friend, no `osa*` call sites. Chained after sweep_login in
  // rui-android-main (both end on the LoginPage/home boundary) and available
  // standalone here for focused debugging.
  'rui-android-keyed-gaps': ['sweep_keyed_gaps'],
  // Message multi-select: 4 cases, two-process, required=no-friend /
  // result=friends. No `osa*` dependency, so nothing here relies on the
  // headless substitutes beyond the shared tap/seed surface.
  'rui-android-msg-select': ['sweep_msg_select'],
  // Keyed-gaps batch #3: 10 cases, two-process, required=no-friend /
  // result=friends. Appended to rui-android-main after sweep_msg_select (both
  // end friends with the C2C row alive, so the runner adds no extra LAUNCH —
  // the `friends -> no-friend` step it does insert is the in-place
  // `_executeInternalRealUiReset()`, not a relaunch).
  'rui-android-keyed-gaps3': ['sweep_keyed_gaps3'],
  // Keyed-gaps batch #4: 9 cases, two-process, required=no-friend /
  // result=friends, plus the single-instance login half. No `osa*` dependency
  // anywhere in either sweep, so nothing here relies on the Android headless
  // substitutes beyond the shared tap/seed surface. Appended to
  // rui-android-main; these entries are for focused debugging.
  'rui-android-keyed-gaps4': ['sweep_keyed_gaps4'],
  'rui-android-keyed-gaps4-login': ['sweep_keyed_gaps4_login'],
  // Self profile: 8 cases, single-instance,
  // required=no-friend / result=no-friend.
  'rui-android-profile': ['sweep_profile'],
  // Settings sweep 2: 12 cases, single-instance,
  // required=no-friend / result=no-friend.
  'rui-android-settings2': ['sweep_settings2'],
  // Conversation list C2C: 10 cases, two-process,
  // required=no-friend / result=friends.
  'rui-android-conv': ['sweep_conv'],
  // Contacts / friend profile: 15 cases, two-process,
  // required=no-friend / result=NO-FRIEND (deletes the friend last).
  'rui-android-contacts': ['sweep_contacts'],

  // ---- 2026-08-27 Android expansion: the sweeps below were desktop/iOS-only
  // by omission, not by dependency — a scoped audit found no osa*/launcher/
  // TOXEE_IOS_* reliance on their required paths (osaEscape routes to
  // popToRoot, dialogs use _prepareDialogSubmit, search drives the real
  // mobile magnifier). STATUS: unproven on an emulator until first green.

  // Mobile settings index/sections: 6 cases, single-instance,
  // required=no-friend / result=no-friend. The `ios_` prefix is historical —
  // runIosSettingsMainSweep drives only `isMobileShell` surfaces and an
  // Android phone takes the same compact drill-in path.
  'rui-android-settings-main': ['sweep_ios_settings_main'],
  // Group / conference: 14 cases, mixed single+two-process,
  // required=no-friend / result=friends. Kick goes through the Cupertino
  // sheet before the desktop popup; AddGroupDialog submit hides the keyboard.
  'rui-android-group2': ['sweep_group2'],
  // Focused C2C expansion: 5 cases, two-process, required=no-friend /
  // result=friends.
  'rui-android-c2c-extra': ['sweep_c2c_extra'],
  // Deep follow-ups on ONE launch: c2c_deep (1) + group_conf_deep (2+1
  // documented same-host SKIP). Both required=no-friend / result=friends.
  'rui-android-deep-extra': [
    'sweep_c2c_deep_extra',
    'sweep_group_conf_deep_extra',
  ],
  // Account-management + conference expansion: 6 cases, single-instance,
  // required=no-friend / result=no-friend; conference_search_result_opens
  // declares SKIP on compact shells (expect 5/0/1).
  'rui-android-account-conf': ['sweep_account_conf_extra'],
  // Account deep expansion: 1 case, single-instance, no-friend/no-friend.
  'rui-android-account-deep': ['sweep_account_deep_extra'],
  // P1 single-instance account/locale/conference: 5 cases,
  // no-friend/no-friend (ends clean on the primary account + EN locale).
  'rui-android-p1-single': ['sweep_p1_single'],
  // C2C reply: 1 case, two-process, no-friend -> friends; menu opens via
  // ui_long_press on the mobile shell.
  'rui-android-p2-reply': ['sweep_p2_reply'],
  // P3 writable subset: 1 case, two-process, no-friend -> friends; the
  // timing threshold is NON-BLOCKING (slow emulators log an advisory).
  'rui-android-p3-writable': ['sweep_p3_writable'],
  // Native/mobile boundary probes: 6 cases, two-process, no-friend ->
  // friends. restore_import_entry_guard ships its fixture via the seam's
  // contentB64 (a driver-side /tmp path is unreadable in the app sandbox).
  'rui-android-boundary-guards': ['sweep_native_boundary_guards'],
  // Calls + misc: 11 cases, two-process, no-friend -> friends. The video
  // trio SKIPs when the app reports videoCaptureSupported=false on an
  // emulator-class environment (iOS Simulator self-report, or Android via
  // the driver-side platform check); AVDs WITH emulated cameras run them
  // for real. Expect 3 honest SKIPs otherwise (tabs-cycle, search-overlay,
  // window-resize).
  'rui-android-calls-misc': ['sweep_calls_misc'],
  // Three-instance @-mention multi-select: 1 case, required=no-friend /
  // result=friends (the case SEEDS the A<->B friendship; A<->C is deleted).
  // Launches a macOS C instance in-case; C is invited over the seeded
  // friend link (host relay port: fixtureCTcpRelayHostPort). Own campaign —
  // the extra-instance lifecycle must not leak into chained sweeps.
  'rui-android-mention-multi': ['mobile_mention_multi_select_inserts'],
};
