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
  'rui-ios-account-settings': ['sweep_login', 'sweep_ios_settings_main'],
  'rui-ios-chat-main': ['sweep_chat', 'sweep_group2'],
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
  // Calls + misc: 10 cases, two-process, required=no-friend / result=friends.
  // Includes window_resize_responsive, which SKIPs on a Simulator (no window to
  // size-script) — expected, not a regression.
  'rui-ios-calls-misc': ['sweep_calls_misc'],
  // Contacts / friend profile: 15 cases, two-process,
  // required=no-friend / result=NO-FRIEND (the chain deletes the friend last).
  // LONGEST chain in the whole mobile matrix — KEEP_SIMULATOR_FRONT is
  // effectively mandatory here even though it is a single sweep.
  'rui-ios-contacts': ['sweep_contacts'],

  // ---- iPad (rui-ipad-*; forces TOXEE_IOS_DEVICE_TYPE=tablet) ----
  // iPad true-App coverage: the SAME sweeps as the iPhone campaigns — the
  // sweeps already branch on the wide/tablet layout at runtime
  // (_settingsIsWide, inst.isIos scroll bands) — but the pair is launched on
  // iPad simulators: selecting a rui-ipad-* campaign makes the runner force
  // TOXEE_IOS_DEVICE_TYPE=tablet into the launch env (launch_ios_fixture_c_
  // pair.sh then matches *iPad* simulators). Requires --real-ui-platform=ios.
  'rui-ipad-account-settings': ['sweep_login', 'sweep_ios_settings_main'],
  'rui-ipad-chat-main': ['sweep_chat', 'sweep_group2'],
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
  // Group/conference member management: 5 cases, two-process,
  // required=no-friend / result=friends. iPad ONLY for now: the chain in
  // drive_real_ui_pair_group_conf_member_extra.dart has ZERO `isMobileShell`
  // branches, so its member-list / peer-menu navigation is only known-good on a
  // wide shell. Add `rui-ios-group-member` once the narrow-shell navigation is
  // verified rather than assumed.
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
  // Calls + misc: 10 cases, two-process, required=no-friend / result=friends.
  'rui-ipad-calls-misc': ['sweep_calls_misc'],
  // Contacts / friend profile: 15 cases, two-process,
  // required=no-friend / result=NO-FRIEND (deletes the friend last).
  'rui-ipad-contacts': ['sweep_contacts'],
  // P1/P2/P3 two-process chat/conv octet: 8 cases,
  // required=no-friend / result=friends. iPad ONLY: the narrow-shell navigation
  // branches for this chain (recall / forward / draft-restore across a pushed
  // route) are not written yet, so an iPhone run would drive the wrong surface
  // rather than SKIP. Add `rui-ios-p1-chat` when those branches land.
  'rui-ipad-p1-chat': ['sweep_p1_chat'],

  // ---- Android (rui-android-*; requires --real-ui-platform=android) ----
  // Android true-App bundles. Same platform-agnostic sweeps; select with
  // `--real-ui-platform=android` (the campaign name does not force it — only
  // the rui-ipad-* device-type override does).
  //
  // STATUS: the Android pair DOES reach the business layer (both instances log
  // `app.started` + `imsdk version arm64` and fire the Badge launcher probe,
  // which only a logged-in session can trigger — `BadgeService.instance.start`
  // is called from lib/runtime/session_runtime_coordinator.dart:298). What is
  // still missing is a SCENARIO-LEVEL green run: no campaign here has been
  // driven end-to-end on two emulators yet, so do not report `rui-android-*`
  // results as proven. (A missing `.android_runtime/*/pair.json` is NOT the
  // evidence it used to be treated as — stop_android_fixture_c_pair.sh:55
  // deletes it on every normal teardown.)
  //
  // Unlike iOS, Android is in `_isHeadlessRealUi`
  // (drive_real_ui_pair_inst.dart:212), so the `osa*` surface routes to the
  // l3/skill substitutes instead of silently no-oping — that is why the Android
  // list is not split into waves. Pure-keyboard-shortcut cases still SKIP,
  // because a substitute is not a real OS keyboard.
  'rui-android-mobile-shell': ['sweep_mobile_shell'],
  'rui-android-main': [
    'sweep_login',
    'sweep_chat',
    'sweep_mobile_shell',
  ],
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
};
