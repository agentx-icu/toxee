// Linux real-UI campaign catalog (`rui-linux-*`), the third desktop family
// beside `rui-win-*` (`fixture_c_real_ui_windows_campaigns.dart`) and the
// mobile matrix (`fixture_c_real_ui_mobile_campaigns.dart`).
//
// Split out of `fixture_c_unified_runner.dart` for the same reason as those
// two (the runner sits at its `tool/.complexity_baseline.txt` pin); the runner
// merges this map into `_realUiCampaigns`, so `--real-ui-campaign=`,
// `--list-real-ui-campaigns` and `--plan-json` work unchanged.
//
// Every sweep here is the SAME driver code macOS runs, grouped into
// launch-sized bundles in `result`/`required` state order so the runner
// inserts as few in-place friendship resets as possible. What differs from
// macOS is only the INPUT layer, and that is the point of the two sections:
//
//   * HEADLESS-SAFE bundles drive every keystroke through the documented
//     synthetic / l3 substitutes (`_isHeadlessRealUi`), so they are honest
//     whether or not `TOXEE_LINUX_OS_INPUT=1` is set.
//   * REAL-OS-INPUT bundles contain the sweeps whose PREMISE is the OS key
//     event — `@` typed into the composer (sweep_group_mention), "typed but
//     not sent" (sweep_p1_chat), a real Ctrl+V paste (sweep_p2_verify) — or
//     that restart a peer process (sweep_p1_relaunch / sweep_p2_keys, via the
//     Linux single-instance twins). Without the flag they SKIP / substitute
//     exactly as before, never vacuously pass.
//
// WHERE LINUX DIFFERS FROM WINDOWS: the OS-input bundles need no interactive
// console session. XTEST (xdotool) reaches an Xvfb display from an SSH login,
// so `rui-linux-os-input` runs in the SAME place as every other bundle — the
// Windows twin has to be launched through an interactive scheduled task. What
// Linux does NOT get is the three Super+Ctrl chords: the key events arrive,
// but the app's meta-requiring `SingleActivator` never matches them (evidence
// in drive_real_ui_pair_inst_linux_input.dart), so they keep the l3 seams
// Windows uses.
//
// DELIBERATELY NOT REGISTERED: the four `*_optimized` bundles (pure
// re-orchestration of sweeps listed here) and `sweep_mobile_shell` /
// `sweep_tablet_layout` / `sweep_ios_settings_main` (wrong form factor — every
// case would SKIP and inflate the tally).

const linuxRealUiCampaigns = <String, List<String>>{
  // ---- headless-safe -------------------------------------------------------
  // Single-instance surfaces first (required=no-friend / result=no-friend):
  // login/register, the keyed-gap batches that ride on LoginPage, settings,
  // profile.
  'rui-linux-account-settings': [
    'sweep_login',
    'sweep_keyed_gaps',
    'sweep_keyed_gaps4_login',
    'sweep_settings2',
    'sweep_profile',
  ],
  'rui-linux-contacts-conv': ['sweep_contacts', 'sweep_conv'],
  'rui-linux-chat': [
    'sweep_chat',
    'sweep_c2c_extra',
    'sweep_msg_select',
    'sweep_keyed_gaps3',
    'sweep_keyed_gaps4',
  ],
  'rui-linux-group': [
    'sweep_group2',
    'sweep_group_conf_member_extra',
    'sweep_group_conf_deep_extra',
  ],
  'rui-linux-account-extra': [
    'sweep_account_conf_extra',
    'sweep_account_deep_extra',
    'sweep_app_entry_extra',
  ],
  'rui-linux-c2c-deep': [
    'sweep_c2c_deep_extra',
    'sweep_native_boundary_guards',
  ],
  'rui-linux-calls-misc': ['sweep_calls_misc'],
  'rui-linux-p1': ['sweep_p1_single', 'sweep_p1_extra'],
  'rui-linux-p2': ['sweep_p2_reply', 'sweep_p3_writable'],
  // ---- real OS input (TOXEE_LINUX_OS_INPUT=1; no console session needed) ---
  'rui-linux-os-input': [
    'sweep_group_mention',
    'sweep_p1_chat',
    'sweep_p2_verify',
  ],
  // Focused re-run of the last os-input sweep (a bundle stops at a failing
  // sweep, so p2_verify never runs while p1_chat still has a red case).
  'rui-linux-p2-verify': ['sweep_p2_verify'],
  'rui-linux-relaunch': ['sweep_p1_relaunch', 'sweep_p2_keys'],
};
