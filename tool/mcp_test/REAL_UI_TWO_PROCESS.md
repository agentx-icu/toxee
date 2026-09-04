# Real-UI two-process driving — harness, recipe, findings

Goal: execute the test scenarios that **directly drive UI controls** (the real
UIKit widgets a user touches) **across two live instances** (`accounts=2`) —
i.e. the intersection the `l3_*` "debug bypass" drivers (`drive_fixture_c_*.dart`)
do **not** cover. "直接驱动 UI 控件且是双进程".

## The driving channel (no marionette, no hang)

The default `skill` build (`run_toxee.sh`, `MCP_BINDING=skill`) already exposes a
full real-UI driving API over the VM service — **no marionette binding** (which
hangs at startup) is needed:

- `ext.flutter.flutter_skill.{tap,enterText,pressKey,tapAt,waitForElement,
  interactiveStructured,getWidgetTree,screenshot}` — drives **real widgets** by
  `ValueKey` / visible text / coordinates. Reachable with raw `vm_service`
  (`callServiceExtension`), the same transport the l3 drivers use.
- `ext.mcp.toolkit.l3_*` — data-layer assertions/setup (dump_state, etc.).

`tool/mcp_test/_scratch/skill_call.dart <ws> <ext.method> '<json>'` is the
one-shot probe; `tool/mcp_test/drive_real_ui_pair.dart` is the low-level
reusable driver that the unified runner calls for each `2proc-ui` scenario.

## Preferred entrypoint (unified runner)

Real-UI two-process scenarios now enter the same `fixture_c_manifest.json` and
planning system as the rest of Fixture C via
`tool/mcp_test/fixture_c_unified_runner.dart`.

### Startup-reuse policy for new real-UI cases

Default rule: every new "真实 App + 真实控件" case should have two shapes:

1. an atomic scenario for focused debugging and failure reproduction;
2. a sweep / optimized campaign path for broad coverage that reuses the current
   app launch, registered accounts, and A<->B friendship.

Do not add a new broad-run campaign that relaunches the pair just to run one
case if the state can be safely reused. Prefer these homes:

- C2C conversation/chat/profile cases: add the atomic case to the relevant
  domain sweep, then include it in `sweep_c2c_optimized` if it preserves the
  friendship.
- Group/conference/call cases: include them in their domain sweep, then in
  `sweep_friendship_optimized` if they end with the friendship intact.
- A-only account/settings/profile/locale cases: include them in
  `sweep_single_app_optimized` if they leave the primary account logged in and
  clean up temporary accounts/conferences.
- Broad smoke/run phase: prefer `rui-optimized-current` first; if it fails,
  use its child sweep name in the log to fall back to the smaller campaign.

Allowed exceptions: keep a case out of optimized single-launch bundles when it
deletes friendship, restarts/stops a peer, depends on native/OS picker or
notification automation, mutates global app state that cannot be restored, or
has a known live failure that would mask unrelated coverage. Document the
exception next to the campaign registration and in the durable campaign anchor.
After registering a new case, run `--plan-json` for the optimized campaign and
check that it still plans as one pair launch unless an exception above applies.

Typical commands:

- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-optimized-current`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-c2c-optimized`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-c2c-deep-extra`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-account-deep-extra`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-group-conf-deep-extra`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-native-boundary-guards`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-scenario=handshake`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=accepted-friend-detail`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=accepted-friend-inline-call`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=accepted-friend-inline-burst`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=accepted-friend-inline-call-reject`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-scenario=custom_message`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --list-real-ui-campaigns`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --plan-json --class=2proc-ui`
- `dart run tool/mcp_test/fixture_c_unified_runner.dart --dry-run --class=2proc-ui`

Behavior to know:

- `2proc-ui` is no longer skipped at planning time; it is planned from the same
  manifest/groups as `2proc-l3`.
- `--real-ui-scenario=...` narrows to one real-UI scenario (`handshake`,
  `message`, `message_burst`, `group_message`, `handshake_detail`, `decline`,
  `custom_message`, `call_voice`, `call_reject`)
  without leaving the unified planner.
- `--plan-json` now records both the selected `realUiScenarios` list and the
  concrete `commands` sequence, so the reusable batch semantics are hermetically
  regression-checkable without launching Toxee.
- The default `--class=2proc-ui` batch is intentionally stateful, not "4 fixed
  isolated launches": the runner tries to reuse already prepared account /
  contact state whenever the next scenario's preconditions are already
  satisfied.
- In the currently codified 4-scenario batch, that means one fresh launch for
  `handshake -> message -> reset_friendship -> handshake_detail -> reset_friendship -> decline`.
- `message` and `call_voice` are the key preconditioned steps: they need an
  existing friendship, so the planner either chains them immediately after an
  accepted handshake (`handshake` / `handshake_detail`) or restores
  `paired_for_e2e` for a focused replay.
- `--real-ui-campaign=...` expands named merged batches of compatible
  scenarios. The current discoverable catalog has 100 built-in campaigns
  (verified 2026-08-08 by brace-balanced parse of `_realUiCampaigns` in
  `fixture_c_unified_runner.dart`; it read 96 before the form-factor campaigns
  below, 88 before that). Treat `--list-real-ui-campaigns` as the exact source
  of truth for names and counts.
- The current catalog is organized around these scheduling buckets:
  - `rui-optimized-*`: preferred broad local dogfood bundles that keep one app
    pair alive and cover as many real controls as possible in a single launch.
    Use `rui-optimized-current` for the broadest current smoke pass.
  - `rui-*` domain sweeps: focused real-control sweeps for settings, profile,
    login, contacts, conversations, chat, calls, group, account, conference,
    group/conference member management, and C2C extras.
  - accepted-friend stacks: reusable chat/call/group steps after a successful
    friend relationship.
  - fresh/no-friend and then-decline stacks: request/decline/custom-message
    branches, with explicit `reset_friendship` maintenance when reuse is
    cheaper than relaunch.
  - `all-*` smoke bundles: representative legacy end-to-end scheduling shapes.
- Representative optimized commands:
  - `--real-ui-campaign=rui-optimized-current` runs the current broad
    single-launch optimized bundle.
  - `--real-ui-campaign=rui-c2c-optimized` narrows to the C2C-heavy optimized
    subset.
  - `--real-ui-campaign=rui-friendship-optimized` narrows to add/delete/request
    friendship coverage.
  - `--real-ui-campaign=rui-single-app-optimized` covers account/settings style
    single-app flows without paying for extra relaunches.
  - `--real-ui-campaign=rui-native-boundary-guards` probes attachment/restore/
    notification boundaries: attachment now clicks real file/photo controls with
    fixed picker paths and restore clicks the real Restore card with a fixed
    invalid `.tox` path; OS/network/permission/mobile-only seams stay explicit
    SKIPs, so keep it outside optimized bundles.
- Use `--list-real-ui-campaigns` to print the full current catalog. Treat that
  list as the source of truth for exact campaign names; this document only
  calls out the representative buckets above.
- `--real-ui-platform=macos|ios|android|windows` are all wired. Each has an A/B
  pair launch/stop pair that produces the same `pair.json` contract (per-instance
  `ws_uri` + `pid`, plus a `fixture_restore` block), and the runner plans +
  executes against it. The launchers (and how the runner invokes them) differ by
  topology:
  - **macos** — `launch_fixture_c_pair.sh`; run the runner on the Mac. Two
    `Toxee.app` processes on one host (per-instance `TOXEE_APP_SUPPORT_DIR` +
    `HOME` override). The runner pre-builds via `run_toxee.sh`.
  - **ios** — `launch_ios_fixture_c_pair.sh`; two iOS Simulators on the Mac
    (same host network → loopback reachable; A is the single TCP relay).
  - **android** — `launch_android_fixture_c_pair.sh`; run the runner on a host
    with `adb` + **two** devices/emulators. Each instance is `flutter run
    --machine` (auto-forwards the device VM service to the host; the driver
    attaches over `127.0.0.1`). The loopback IRC server is reached from the
    device via `adb reverse tcp:<port> tcp:<port>` — the launcher reverses the
    fixed `TOXEE_IRC_LOOPBACK_PORT` (default 16667) the runner injects, and
    `LocalIrcServer.startFromEnv` binds it. The driver resolves each `Inst`'s
    platform from `TOXEE_REAL_UI_PLATFORM=android` and drives purely via
    synthetic flutter_skill / L3 RPC (`_isHeadlessRealUi`, shared with Windows —
    no host osascript, since the app lives on a device).
    Tox A↔B connectivity (2026-07-12): two emulators sit behind separate NATs
    (UDP never routes between them), so the launcher applies the same lever as
    the Windows/Linux pairs — TCP-only + A as the TCP relay — via the
    `debug.toxee.force_tcp_only` / `debug.toxee.tcp_relay_port` system
    properties (`adb shell setprop`; ToxManager.cpp `read_harness_knob` falls
    back to them on Android because a device app cannot be handed env vars).
    The relay is plumbed B-guest → (`adb reverse`) → host → (`adb forward`) →
    A-guest. Since 2026-08-31 the HOST middle leg and B-guest's loopback ride
    `RELAY_HOST_PORT` (default 33390, mirrored by `fixtureCTcpRelayHostPort()`)
    while A-guest's listener stays on `TCP_RELAY_PORT` (3389); the driver's
    `wireFullMeshBootstrap` passes the host port as its TCP-relay fallback for
    udpPort=0 peers — host 3389 is AVOIDED (an unrelated legacy-VM listener
    hijacked it silently for weeks; the pairs quietly rode PUBLIC relays).
    `stop_android_fixture_c_pair.sh` clears the props (they persist to reboot)
    and removes BOTH ports' tunnels.
  - **form-factor coverage vs. reuse** — until the `sweep_mobile_shell` /
    `sweep_tablet_layout` additions (below) every `rui-ios-*` / `rui-ipad-*`
    campaign only RE-RAN the desktop sweeps on a smaller screen. That is layout
    REUSE, not layout COVERAGE. See "Form-factor scenarios" below for what is
    now exclusive to each shell.
  - **ipad** — same `ios` platform + launchers: selecting a `rui-ipad-*`
    campaign makes the runner force `TOXEE_IOS_DEVICE_TYPE=tablet` into the
    pair-launch env, so both instances boot on iPad simulators and the shared
    sweeps exercise the wide/tablet layout branches. `rui-ipad-account-settings`
    went live-green first try on 2026-07-12 (sweep_login 9/9 +
    sweep_ios_settings_main 6/6 on two iPad Pro 11-inch sims). NOTE: the sim
    list parser in both iOS launch scripts must keep the GREEDY name capture —
    the old `[^()]+` pattern silently dropped every device whose NAME contains
    parentheses ("iPad Pro 11-inch (M4)", "iPad mini (A17 Pro)"), leaving the
    tablet pool with <2 matches (iPhone names have no parens, which is why the
    phone pairs never exposed it).
  - **windows** — `launch_windows_fixture_c_pair.ps1`; run the runner **on the
    Windows host** (PowerShell). It builds once, copies the Debug runner dir to a
    per-instance dir for A and B, and direct-launches each with a fixed Dart
    VM-service port + `disable-service-auth-codes` (deterministic ws URI) and
    per-instance `TOXEE_APP_SUPPORT_DIR` / `TOXEE_SHARED_PREFS_PREFIX`. Runner,
    driver, both apps, and the loopback IRC server share the host loopback, so no
    reverse-forwarding is needed. The runner invokes the `.ps1` via
    `powershell -ExecutionPolicy Bypass -File`.
  - **Restore (`paired_for_e2e`)** is wired on ALL five platforms (the runner's
    old planning-time Android reject is gone, 2026-07-12). macOS/iOS/Windows/
    Linux copy the portable snapshot into the per-instance support dir on the
    host; Android streams it into the DEBUG app's sandboxed `files/` dir via
    `adb exec-in run-as com.toxee.app tar -x` after the app is installed+running
    (a fresh boot idles on the login shell and only reads `profiles/` when the
    driver calls `l3_boot_existing_account`, so the post-launch copy is
    race-free), with `pm clear` pre-launch for determinism and the same
    profile/history integrity checks as the other launchers. Android restore is
    IMPLEMENTED and the launcher **does bring the pair up to the business
    layer** (see "Android status" below). **The first scenario-level green run
    landed 2026-08-16**: `rui-android-msg-select` (`sweep_msg_select`, all four
    cases) went `passed=4 failed=0 skipped=0` on two emulators
    (`emulator-5554` / `emulator-5556`), including the live A<->B friendship the
    sweep establishes itself. Other `rui-android-*` campaigns are still
    unproven — do not report THOSE as android-green until they have their own
    run.
- **Native libirc_client gap (honest live-coverage note).** The two IRC cases
  differ in what they need:
  - `irc_join_channel_real_controls` sets the L3 `localAddOverride`, so adding a
    channel is **pure Dart/Prefs** (no socket). It is portable and is the live
    proof that the IRC UI + the new pair launcher + driver work on any platform.
  - `irc_join_channel_loopback_live` drives the REAL connect path
    (`IrcAppManager.addChannel → service.connectIrcChannel`), which dlopens the
    native `libirc_client` library to open the TCP socket and send `JOIN`. That
    library is built + bundled **on macOS only** (`run_toxee.sh`). The app loader
    `IrcAppManager._ircLibraryPath()` is platform-aware (`.dll` Windows / `.so`
    Android+Linux / `.dylib` macOS+iOS), and the C++
    (`third_party/tim2tox/source/IrcClientManager.cpp`) is cross-platform
    (winsock + POSIX + OpenSSL), so the ONLY remaining gap is BUILDING + bundling
    the `.dll` for Windows (the launcher copies it next to `toxee.exe` if found
    under `build/native-artifacts/windows/`) and the `.so` for Android
    (`jniLibs/<abi>/`). Until those are built, the loopback `JOIN` cannot complete
    live on Windows/Android — do **not** report it as passing there; use
    `real_controls` for the portable live proof and treat `loopback_live` as
    native-lib-gated on those platforms.
- **Mobile parity.** The IRC client manager, the Applications page, the IRC
  channel dialog, and the `ircChannels` dump_state projection are all shared Dart
  with no platform stripping (the L1 widget gates in `test/ui/applications/`
  cover mobile rendering), so the IRC UI behaves identically on Android. The
  remaining mobile-specific work is purely the native `libirc_client.so` build
  (above), not any Dart/UI divergence.
- Treat the exact number of launches as an optimization detail, not an API.
  What is stable is the state contract: the runner may insert friendship-reset
  maintenance steps when that is cheaper than relaunching the pair.
- The legacy Fixture C shell entrypoints stay as compatibility shims and
  delegate into the unified runner. Real-UI still has no dedicated `.sh`
  wrapper because it needs two manually launched live instances plus a
  foreground-able macOS session.

## Hard-won harness facts (the "problems found" + how solved)

1. **Unfocused window stalls the UI.** Instances launched by
   `launch_toxee_instance.sh` (direct `exec`) do **not** pump frames / service
   platform channels while their macOS window is backgrounded. A post-register
   `await Prefs.getAccountList()` (SharedPreferences method channel) then hangs,
   so the app never navigates past RegisterPage and `screenshot` returns empty —
   even though `dump_state` says `sessionReady:true`. **FIX:** osascript-
   foreground the target pid before each UI phase:
   `osascript -e 'tell application "System Events" to set frontmost of (first
   process whose unix id is <pid>) to true'`. Data/DHT runs on native threads, so
   the *other* instance can stay backgrounded between phases.
2. **`flutter_skill.enterText{key}` only matches an editable carrying the key.**
   Our text keys (`register_page_nickname_field`, `add_friend_id_input`) sit on
   `TextFormField` wrappers, not the inner editable → "No TextField matching
   key". **FIX:** `focusType` = `tap{key}` (general widget search focuses it) then
   `enterText{no key}` into the focused field.
3. **The desktop chat composer can't be driven synthetically.** It is an
   `ExtendedTextField`; `enterText` lands "via system channel (no focused
   TextField)". **FIX:** `tapAt` the composer center, then **real OS keystrokes**
   (`osascript … keystroke`).
4. **Enter-to-send rides the legacy `FocusNode.onKey` RawKeyEvent path**
   (`tencent_cloud_chat_message_input_desktop.dart:545`). A synthetic key does
   not reach it, and a freshly-typed field races a single real Return. **FIX:**
   real `osascript … key code 36`, **retry focus+Return until the conversation's
   lastMessage == text** (`sendComposerMessage`).
5. **First-run backup wizard blocks navigation** after register
   (`FeatureFlags.enableFirstRunBackupWizard=true`). It is pushed on the
   `rootNavigator`. **FIX:** dismiss via text "I'll do it later" →
   "I understand, continue".
6. **`contact_new_contacts_tab` ValueKey is on a non-tappable element.** The key
   exists (`tencent_cloud_chat_contact_tab.dart:47/111`) but `tap{key}` can't land
   it; tapping the **"New Contacts"** label works. *(Fork fix candidate: move the
   key onto the tappable row; needs a rebuild — driver uses the text fallback.)*
7. **The `osa*` surface is macOS-only, and on iOS it USED to be a silent
   no-op.** `osa*` wraps `osascript`, which exists only on the macOS host.
   `Inst._osa` opens with `if (isIos || _isHeadlessRealUi) return;`, so there
   are two very different mobile situations — do not conflate them:
   - **Android / Windows / Linux — SUBSTITUTED, not silent.** These platforms
     are in `_isHeadlessRealUi` (`drive_real_ui_pair_inst.dart:212`, which
     deliberately does NOT include iOS), and each `osa*` helper falls through to
     an l3 / flutter_skill substitute (synthetic key events, `l3_set_clipboard`,
     composer seams). The case really does drive something — just not the OS
     input stack.
   - **iOS — historically SILENT.** `isIos` short-circuits `_osa` *before* the
     headless substitution, and only `focusType` had an iOS branch, so
     `osaReturn` (Enter-to-send), `osaEscape`, `osaClear` (Cmd+A+Delete),
     `osaPaste`, `osaType`, the Cmd/Ctrl shortcuts and `resizeWindow` all
     returned without doing anything while the surrounding case still reported
     PASS — a case that "ran" but asserted nothing. iOS is being given the same
     substitute branches as the other non-macOS platforms; until that lands,
     treat any iOS run of an `osa*`-carrying chain as unproven (this is exactly
     the Wave 1 / Wave 2 split in `fixture_c_real_ui_mobile_campaigns.dart`).

   **A substitute is NOT a real OS keyboard.** Synthetic key events do not reach
   the legacy `FocusNode.onKey` `RawKeyEvent` path (fact 4 above), do not open a
   real IME, and cannot put an image on a pasteboard. So a case whose ASSERTION
   IS the keystroke — Enter-to-send on the desktop composer, the Cmd/Ctrl global
   shortcuts, `osaType('@')` in `sweep_group_mention`, pasting an image in
   `sweep_p2_verify` — must **SKIP (exit 75) on mobile**, not be re-pointed at a
   substitute. Substitutes are legitimate only when the keystroke is *plumbing*
   for the thing under test, never when it *is* the thing under test.

   The always-usable mobile input paths are the synthetic `flutter_skill` ones
   (`tap`/`tapAt`/`tapKeyCenter`/`enterText`/`waitKey`/`waitText`/
   `getWidgetTree`/`screenshot`), the ungated `ui_*` pointer tools
   (`ui_key_center`/`ui_long_press`/`ui_drag`/`ui_scroll_at`), and the `l3_*`
   seams (`l3_composer_set_text`, `l3_composer_send`, `l3_open_add_group_dialog`,
   …). Anything that genuinely cannot be driven must be an explicit SKIP, not a
   silently-green pass.

## Form-factor scenarios (mobile-shell / tablet-layout exclusives)

`tool/mcp_test/drive_real_ui_pair_mobile_shell.dart` holds the first scenarios
that touch controls existing ONLY on one form factor. Two sweeps chain them on a
single pair launch; every case is also individually dispatchable.

Layout tier is detected from LIVE signals, never from the platform name (a
landscape phone is wider than a portrait tablet):

- phone / bottom-nav tier — `home_bottom_nav` resolves via `ui_key_center`
  (`ResponsiveLayout.shouldShowBottomNav`, width < 720pt).
- master-detail tier — dump field `homeShellShouldShowMasterDetail` (>= 800pt;
  both iPad orientations and desktop).

| Scenario | Real control driven | Hard assertion | SKIP (75) when |
|---|---|---|---|
| `mobile_bottom_nav_tab_switch` | the four `bottom_nav_*_tab` items (a different widget + callback from the desktop `sidebar_*_tab`) | dump `homeShellTab` flips chats→contacts→applications→settings→chats (the IndexedStack keeps every tab MOUNTED, so a `waitForElement` probe would false-pass) | no bottom nav in this layout tier |
| `mobile_composer_send_button_reveals` | the mobile composer's `chat_send_button` (the desktop composer has NO send affordance at all) | the button MOUNTS on non-empty text and UNMOUNTS when cleared (`_onTextChanged` → `_showSendButton`) | `l3_composer_set_text` reports `no_composer` — i.e. this shell renders the desktop composer |
| `mobile_composer_send_delivers` | same button, two-process | B receives the exact text; the send path used is printed (`sendPath=real_button` or `l3_seam`) | same as above |
| `mobile_message_long_press_menu` | REAL long-press (`ui_long_press`, 800 ms) on the message bubble — the mobile twin of the desktop right-click | the overlay's `message_menu_item:copy` + `:delete` mount | not a mobile platform, or not the compact shell (desktop opens the same menu by right-click → `chat_msg_menu_surface`) |
| `tablet_master_detail_row_opens_chat` | conversation ROW tap in the left pane | the chat binds (`currentConversation`) AND the composer's centre x sits well RIGHT of the row's centre x — the two-pane signature a phone's full-screen push collapses to ~0 | shell is not master-detail |
| `dialog_width_form_factor_tier` | real Add-Contact / Add-Group dialogs opened from the "+" popup | the per-form-factor width cap: the id field ↔ paste-button span is >= 200pt on tablet/desktop and <= 190pt on a phone | ambiguous form factor on a mobile platform (see below) |

Design notes that matter if you extend this file:

- **No absolute screen size is readable on iOS.** `l3_window_state` is
  `window_manager` (desktop) + test-account gated, and osascript cannot see the
  Simulator. Both geometric cases are therefore SELF-CALIBRATING: they compare
  two on-screen anchors resolved through `ui_key_center` instead of measuring
  against the viewport.
- **`dialog_width_form_factor_tier` mirrors the DIALOG's own branching, not the
  shell's.** `_dialogMaxWidth` keys off `ResponsiveLayout.isDesktop`, which is
  platform-driven (true on every desktop OS at any window width) and also true
  for tablets; the shell tiers are pure width checks. Mapping shell→dialog
  directly would red a narrowed desktop window. A LANDSCAPE phone (wide shell,
  mobile dialog cap) is the one unresolvable case and is an explicit SKIP — the
  launchers never rotate a simulator, so the wired campaigns cannot hit it.
- **`mobile_composer_send_delivers` gates on DELIVERY, not on the tap.** A
  synthetic tap on `chat_send_button` is a live-diagnosed unreliable gesture on a
  compact phone (see `_sendComposerMessageIos`); the case tries the real button
  three times, then falls back to `l3_composer_send`, which invokes the SAME
  production `_submitTextMessage` the button's `onTap` calls, and always prints
  which path delivered. A permanently-red case would only pollute the pass rate;
  a silent fallback would hide a regression — printing the path does neither.

Campaign wiring (startup-reuse policy: atomic case + a sweep that reuses one
launch):

- `--real-ui-campaign=rui-mobile-shell` — the phone-shell sweep alone.
- `rui-ios-main` now ends with `sweep_mobile_shell` (the phone bundle).
- `--real-ui-campaign=rui-ipad-layout` — the tablet sweep alone (forces iPad
  simulators like every other `rui-ipad-*`).
- `rui-ipad-main` now ends with `sweep_tablet_layout`.
- `rui-android-mobile-shell` / `rui-android-main` exist for parity and require
  `--real-ui-platform=android` (the name does not force it — only the
  `rui-ipad-*` device-type override does).
- `sweep_mobile_shell` is deliberately NOT in the `rui-ipad-*` campaigns and
  `sweep_tablet_layout` not in the iPhone ones: on the wrong form factor every
  case would SKIP and only inflate the skip tally.
- Both sweeps declare `required=no-friend` / `result=friends` and establish (or
  REUSE) the A<->B friendship themselves, so they need no `paired_for_e2e`
  restore — which also keeps them runnable on Android, whose restore path is
  implemented but has no scenario-level green run on record yet.

## Message multi-select (`sweep_msg_select`)

`tool/mcp_test/drive_real_ui_pair_msg_select.dart` (dispatch + sweep +
preconditions) and `..._msg_select_cases.dart` (the case bodies) cover the
surface behind `message_menu_item:multiSelect`. Until this batch that menu entry
was keyed but never driven, so the whole select-mode surface was dark AND
keyless: the toolbar that REPLACES the composer, its delete/forward affordances,
the delete confirmation dialog, and the select-mode header bar. The keys added
with it are catalogued in `lib/ui/testing/ui_keys_fork.dart` (`ForkUiKeys`):
`message_select_{delete,forward,forward_individually,forward_combined}_button`,
`message_select_forward_{individually,combined}_item`,
`message_select_delete_{confirm,cancel}_button`,
`message_select_{clear,cancel}_button`, `message_select_count_text`, plus
`forward_picker_cancel_button` (the dismiss twin of the existing
`forward_picker_send_button`).

**Only a CUSTOM bubble can enter select mode.**
`tencent_cloud_chat_message_item_with_menu_container.dart` strips
`_uikit_multi_message` from the menu for TEXT bubbles and for
file/image/video/sound bubbles, which leaves the custom bubble — the same reason
`reply_quote_real` drives Reply on one. Every case therefore seeds an inbound
custom message with `l3_inject_c2c_custom` and long-presses / right-clicks THAT
row.

### Sweep verdicts: an UNDECLARED skip is a failure

`_MobileShellTally` (`drive_real_ui_pair_sweep_tally.dart`) is the shared
PASS/FAIL/SKIP bookkeeper for `sweep_mobile_shell`, `sweep_tablet_layout`,
`sweep_keyed_gaps3`, `sweep_keyed_gaps4(_login)` and `sweep_msg_select`.

Its original `finish()` was `failed != 0 -> 1; passed == 0 && skipped != 0 ->
75; else 0` — so **`passed > 0 && skipped > 0` was GREEN**. That is right for
the two FORM-FACTOR sweeps it was written for (a case whose surface does not
exist in the running layout tier is making a capability assertion), and wrong
for the three sweeps that later adopted it, where every case is meant to run on
every form factor. The sibling `runKeyedGapsSweep` — written in the same batch —
already treated an unexpected SKIP as exit 1; the tally now matches it.

`run()` therefore takes `expectedSkip`, **defaulting to false**: a skip fails
the sweep unless the call site declares that skipping is a legitimate outcome
for that case. The declared set is the EXPECTED-SKIP REGISTRY at the top of
`drive_real_ui_pair_sweep_tally.dart`, one place, each entry naming the LIVE
probe that decides it (layout tier, live composer/menu surface, measured scroll
extent, or a source-proven bridge gap). `passed == 0 && skipped != 0` still
exits 75 — a sweep pointed at the wrong shell is inapplicable, not broken.

When adding a case: do NOT add it to the registry to make a red go away. A skip
justified by flakiness or by an estimated geometry threshold is a swallowed
failure — that is exactly how `message_viewer_save_and_zoom_surface`,
`msg_select_forward_combined_absent_gating` and the `group_profile_scroll_view`
viewport guess were each hiding a real red until 2026-08-16.

**A missing multiSelect entry FAILS — it does not SKIP.** The custom bubble is
the LAST bubble type that still carries `_uikit_multi_message`, i.e. the only
door into the entire select-mode surface. Reporting its absence as a SKIP was a
soft assertion: `_MobileShellTally.finish()` only returns 75 when NOTHING
passed, and these cases are chained behind others that do pass, so a fork sync
that dropped multiSelect from custom bubbles too would have made the whole
surface stop being covered while the run still went green. `_mselEnterSelectMode`
now returns FALSE there and prints the diagnosis together with the
`message_menu_item:*` ids the menu DID offer. The source half of the same
regression is caught device-free by `test/fork_message_multi_select_menu_test.dart`
in the ordinary `flutter test` gate.

**RETRACTED (2026-08-16): this family has NO SKIP.** An earlier revision of this
document claimed `msg_select_forward_surface` legitimately SKIPs when the toolbar
renders no forward affordance, because `enableMessageForwardIndividually` /
`enableMessageForwardCombined` are product CONFIG toggles a build may turn off.
That claim was wrong for toxee, and the SKIP it justified was unreachable:
`enableMessageForwardIndividually` is pinned **true** (`lib/ui/home_page_bootstrap.dart:683`,
and the fork's own config default is true too), while `enableMessageForwardCombined`
is pinned **false** by the fork's select-mode container
(`..._input_select_mode_container.dart:43`, hardcoded until the Tox-side merger
elem exists). The phone builder gates its single forward icon on
`enableMessageForwardCombined || enableMessageForwardIndividually`
(`..._input_select_mode.dart:190`) — `false || true`, always true — and the
tablet/desktop builders gate theirs on Individually alone, also always true. So a
toolbar with no forward control cannot mean "config off"; it can only mean the
toolbar never mounted. That is now a **FAIL** carrying exactly that diagnosis,
alongside the raw `skill('tap')` payload and the opener's resolved geometry.

| Scenario | Real control driven | Hard assertion | SKIP (75) when |
|---|---|---|---|
| `msg_select_enter_and_cancel` | `message_menu_item:multiSelect`, then the header's `message_select_cancel_button` | select mode MOUNTS both ends of the chat surface (`message_select_count_text` + `message_select_delete_button`) and Cancel UNMOUNTS them — presence of those keys IS `inSelectMode`; nothing in the dump exposes it | never — no multiSelect entry is a FAIL |
| `msg_select_delete_cancel_keeps_message` | multi-select delete → the dialog's `message_select_delete_cancel_button` | dialog closes, the row is still in the tree, the message is still in history, and select mode is STILL up (the fork shares a `handled` latch between the confirm and cancel branches) | never |
| `msg_select_delete_for_me_removes_row` | the dialog's `message_select_delete_confirm_button` | the row leaves the tree, the message leaves history, and select mode exits by itself (`onDeleteForMe` sets `inSelectMode = false`) | never |
| `msg_select_forward_surface` | the toolbar's forward affordance, then `forward_picker_cancel_button` | the REAL forward target picker mounts (`forward_picker_send_button`) and unmounts again; nothing is forwarded, so no state is left behind | never — "no forward affordance" is a FAIL (the flags are pinned, so the config-off SKIP is unreachable) |

Design notes if you extend it:

- **The forward path is DETECTED, not guessed.** The phone `defaultBuilder`
  renders one icon that opens a forward-type bottom sheet; `tabletAppBuilder` /
  `desktopBuilder` render the per-type buttons directly. The case looks for
  whichever key is mounted, so a narrowed desktop window (still the desktop
  builder) does not red it.
- **The toolbar must SETTLE before it can be tapped** (root cause of the
  intermittent reds here, fixed 2026-08-16). `_mselEnterSelectMode` used to
  return as soon as the select-mode HEADER mounted, but the bottom toolbar is a
  separate, slower animation: the mobile composer swaps it in through an
  AnimatedSwitcher whose transitionBuilder is a `SlideTransition` from
  `Offset(1, 0)` (`..._message_input_mobile.dart:972-983`), so it flies in from
  the right edge. A coordinate tap loses that race by construction — the centre
  is resolved over one RPC and the pointer dispatched over the next. Measured on
  Android: `message_select_delete_button` resolved at x=419.4 and x=200.8 for a
  button that settles at x=40.0 in a 411.4-wide view. The pointer hit empty
  space, nothing raised an error, and the case reported "the delete dialog never
  mounted". Element-resolved `skill('tap')` was immune (it invokes the callback,
  not a point), which is why the forward case appeared to work and the delete
  cases did not — the difference was the input path, never the control. The gate
  now waits for the toolbar's centre to stop moving
  (`Inst.waitKeyCenterSettled`, `drive_real_ui_pair_tap_diag.dart`). Reuse that
  helper for any other animated surface rather than adding per-case retries.
- **Combined forward is deliberately not driven.** toxee pins
  `enableMessageForwardCombined` to false in the select-mode container until the
  merger-elem protocol exists, so its button / sheet row never renders.
- **Destructive only to its own probe.** The one deletion is of the throwaway
  custom bubble the case seeded seconds earlier, so the sweep is
  `required=no-friend` / `result=friends` like the form-factor sweeps.
- **No `osa*` anywhere** (silent no-op on iOS/Android), so the sweep is honest on
  a Simulator/emulator with no driver change.

Campaign wiring: `--real-ui-campaign=rui-msg-select` (platform-agnostic) and
`rui-ios-msg-select` / `rui-ipad-msg-select` / `rui-android-msg-select` for
focused debugging; the broad runs get it through `rui-ios-chat-main`,
`rui-ipad-chat-main` and `rui-android-main`, where it reuses the same launch that
`sweep_chat` already paid for.

## Keyed-but-never-driven batch #2 (`sweep_keyed_gaps`)

`tool/mcp_test/drive_real_ui_pair_keyed_gaps.dart` (dispatch + sweep + shared
helpers + the add-group case), `..._keyed_gaps_register.dart` and
`..._keyed_gaps_irc.dart` cover eight controls that carried a `ValueKey` but that
no scenario had ever driven. All eight are SINGLE-INSTANCE (A only; B stays
launched-but-idle), `required=no-friend` / `result=no-friend`.

Production keys added with the batch (all ADDITIVE and state-ENCODED — the
pre-existing keys could only say "mounted", never "in which state", which is why
a driver could not assert a flip):

| New key | File | Why |
|---|---|---|
| `register_confirm_match_{ok,mismatch}` | `lib/ui/register_page_form.dart` | `register_confirm_match_icon` is identical for check_circle and cancel |
| `register_confirm_visibility_icon_{obscured,visible}` | same | `obscureText` is invisible through the field value |
| `register_strength_segment_<i>_{filled,empty}` | `lib/ui/widgets/register_password_strength_bar.dart` | segment fill is a `BoxDecoration.color` |
| `irc_channel_dialog_password_visibility_icon_{obscured,visible}` | `lib/ui/applications/irc_channel_dialog.dart` | same reason as the register toggle |

They all follow the already-shipped `register_password_visibility_icon_*`
pattern: the tappable widget keeps its stable key, a sibling key carries state.

| Scenario | Real control driven | Hard assertion |
|---|---|---|
| `add_group_type_selector_hint_switches` | `add_group_type_selector` (all three segments) | the per-type hint sentence under the selector SWAPS on every selection (previous hint gone + new hint shown); the dialog is closed with `add_group_close_button` so nothing is created |
| `irc_channel_dialog_cancel_discards` | `irc_channel_dialog_password_visibility_toggle` + `irc_channel_dialog_cancel_button` | the obscure icon key flips both ways; Cancel closes the dialog AND leaves no channel tile and no `ircChannels` entry (a Cancel that fell through to `addChannel` would still close the dialog) |
| `irc_channel_remove_row_confirm` | `applications_irc_remove_channel_button:<channel>`, both dialog branches | Cancel: tile survives in the tree AND in `ircChannels`; Remove: tile leaves the tree AND the channel leaves `ircChannels` |
| `irc_app_uninstall_reinstall_card` | `applications_irc_card` + `applications_irc_uninstall_button`, both branches | Cancel: still installed (button + `ircInstalled == true`); Uninstall: the action row SWAPS to `applications_irc_install_button`, add-channel unmounts, `ircInstalled` flips to false, and the CARD survives |
| `register_status_field_length_guard` | `register_status_field` | the "Status message too long" inline error MOUNTS over the 24-char cap and UNMOUNTS on a short value, with the typed value read back through `getTextValue` |
| `register_confirm_match_icon_flips` | `register_confirm_match_icon` | mismatch → match FLIP via the state keys, then the whole badge unmounts when the confirm field is cleared |
| `register_confirm_visibility_toggle_flips` | `register_confirm_visibility_toggle` | obscured→visible→obscured, PLUS the password field stays `obscured` while the confirm field is revealed (the two flags are independent) |
| `register_strength_segments_ramp` | `register_password_strength_bar` + `register_strength_segment_<i>` | every rung 0→1→2→3→4 asserted on the SEGMENTS (`_filled` present AND `_empty` absent per index), then reversible back to 0 — the existing `register_password_strength_flips` only reads the caption and pins two rungs |

Notes if you extend it:

- **The unkeyed confirm dialogs are tapped by text through `_kgTapTextTopmost`,
  not `_tapTextCenter`.** The IRC card's own "Uninstall"/"Remove" labels sit
  EARLIER in the element tree than the dialog action with the same label, so the
  first match is the widget covered by the modal barrier. `_kgTapTextTopmost`
  takes the LAST positive-bounds match, mirroring `tapKeyCenter`'s `.last` rule.
- **State keys are resolved with `waitKeyCenter` / `_kgWaitKeyCenterGone`**, not
  `waitKey` / `waitKeyGone`: they sit on `KeyedSubtree`s and bare `Icon`s, which
  flutter_skill's interactive index never surfaces.
- **No `osa*` anywhere** — only `focusType` (real paste on desktop,
  flutter_skill `enterText` on a device) — so the sweep is honest on a
  Simulator/emulator with no driver change.
- **Launch reuse**: `sweep_keyed_gaps` is APPENDED to `rui-app-entry-extra`,
  `rui-ios-account-settings`, `rui-ipad-account-settings` and `rui-android-main`,
  and is a step inside `sweep_single_app_optimized`. `rui-keyed-gaps` /
  `rui-android-keyed-gaps` exist only for focused debugging.

### Three-instance cases (2026-08-31)

`mobile_mention_multi_select_inserts` (campaign `rui-android-mention-multi`)
is the first THREE-instance case: the mobile @-mention picker's multi-select
contract (two ticked rows + confirm insert BOTH "@<label> " tokens) needs a
group with 2 non-self members, and NGC membership is a live peer list (no
seam can fake a member). The case launches a macOS **C** instance in-case
via `launch_toxee_instance.sh C` (own ditto'd app copy;
`l3_register_account`), then uses the PROVEN friend-link machinery: mutual
`l3_seed_friend`, friend-ONLINE gates, a PRIVATE group and
`l3_invite_to_group` auto-joins. Public join-by-chat-id was abandoned —
NGC public discovery under TCP-only is onion-over-relay and never converged
in 90s. On the Android pair the local relay star runs host-port
`fixtureCTcpRelayHostPort()` (33390) mapped to A-guest:3389 — NOT host
3389, which an unrelated listener can hijack silently (measured: a legacy
qemu VM's hostfwd ate it for weeks and every pair quietly rode PUBLIC
relays). Result state: FRIENDS (seeded A<->B persists; A<->C is deleted
before C stops). Own campaign by design: the extra-instance lifecycle
(launch + teardown in `finally`) must not leak into chained sweeps — the
standing-agreement exception for conflicting state contracts.

### Verify-first exclusions from this batch (do NOT "fix" by writing a case)

- **`av_conference_{join,mute,enable,leave}_button`** — no constructible
  precondition. The header action renders only when
  `conversation.groupType == 'av_conference'` (`home_page_bootstrap.dart:6`), and
  the only producer of that type is an INBOUND `TOX_CONFERENCE_TYPE_AV` invite
  (`V2TIMManagerImpl.cpp:1157`, `is_av_invite ? "av_conference" : "conference"`).
  The AddGroupDialog creates exactly three types (`group` / `privateGroup` /
  `conference`, `add_group_dialog.dart:193`) and `l3_create_group` maps only
  public/private, so neither the app nor the harness can produce an AV
  conference. `call_camera_switch_button` additionally needs a live VIDEO call
  plus `CallMediaCapabilities.supportsCameraSwitch()`.
- **`message_attachment_{image,photo,video,search}_button`** — dead under
  toxee's configuration. `buildToxeeMessageAttachmentConfig()`
  (`lib/ui/home/mobile_attachment_policy.dart`) pins `enableSendImage`,
  `enableSendVideo`, `enableSendFile` and `enableSearch` to false, and
  `_buildDesktopInputOptions` builds only `Icons.attach_file` (plus
  `Icons.qr_code_2` in C2C). The one live sibling is
  `message_attachment_personal_card_button`, which is a two-process case for the
  native-boundary sweep and is NOT in this batch.
- **`add_group_copy_id_button`** — unreachable in production. `_buildCreatedInfo()`
  renders only while `_createdGroupId != null`, but `_createGroup` pops the
  dialog on success unless `closeOnCreateSuccess == false`, and nothing in `lib/`
  ever passes that flag (it defaults to true). Only a widget test can reach it.
- **`login_page_settings_button`** is NOT uncovered: `sweep_settings2`'s
  `settings_prelogin_bootstrap_node_test`
  (`drive_real_ui_pair_settings2_prelogin.dart:96`) already taps it and drives
  `LoginSettingsPage` → `BootstrapSettingsSection`.

## Keyed-but-never-driven batch #3 (`sweep_keyed_gaps3`)

`tool/mcp_test/drive_real_ui_pair_keyed_gaps3.dart` (dispatch + sweep + shared
helpers), `..._keyed_gaps3_msg.dart`, `..._keyed_gaps3_contacts.dart` and
`..._keyed_gaps3_group.dart` close the LAST tranche of keyed-but-undriven
controls. Unlike batch #2 this one is TWO-PROCESS: `required=no-friend` (the
sweep runs its own handshake and reuses an existing one) / `result=friends`.
The six group cases share ONE `_establishTwoProcessGroup`, so the whole batch
costs one launch, one friendship and one group.

| Scenario | Real control driven | Hard assertion |
|---|---|---|
| `msgmenu_reveal_file_location_gating` | `message_menu_item:revealFileLocation` on a real inbound FILE bubble | GATING PAIR: the entry MOUNTS on the file bubble and is ABSENT on a text bubble whose menu is demonstrably up (`message_menu_item:delete` resolves). The TAP is deliberately not driven — desktop `onTap` only runs `Process.run(open/explorer/xdg-open)` (an OS file manager that steals focus) and mobile has no platform branch at all, so there is no in-app observable past the boundary |
| `msgmenu_read_receipt_group_gating` | `message_menu_item:readReceipt` on A's own group message | GATING PAIR: present on A's OWN just-sent group message (sent through the REAL composer submit seam so the UIKit stamps `needReadReceipt`), ABSENT on B's inbound message in the same group. The entry's `onTap` is literally `{}`, so the render IS the observable. Absent on BOTH → SKIP with the bridge-drops-the-flag diagnosis, negative leg still asserted |
| `contact_application_detail_decline_removes_row` | `contact_application_detail_decline_button:<uid>` | the detail route renders BOTH actions for a `l3_inject_friend_application` applicant, and after the real Decline the route shows the `tL10n.declined` RESULT text (locale-tolerant match). That string is reachable ONLY from the success arm of `onRefuseApplication`; the earlier `(buttonGone \|\| applicationRemoved) && alive` verdict passed on the FAILURE arm too, because `invalidApplication` also calls `deleteApplicationList` (fixed 2026-08-16) |
| `friendprof_copy_toxid_snackbar` | `user_profile_copy_id_button` | the production `'Tox ID copied'` SnackBar appears, asserted GONE first so a leftover toast cannot false-pass |
| `personal_card_send_c2c` | `message_attachment_personal_card_button` | the C2C conversation GROWS by a message (online → QR card file, offline → the two-line failure text) or the `'Personal Card sent'` snackbar shows. LIVE composer probe decides desktop-vs-mobile; the mobile composer SKIPs with the reason |
| `group_member_info_profile_entry_opens_profile` | `group_member_info_profile_entry` | three route transitions each proven by a route-exclusive key: member-info (`group_member_info_copy_id_button`) → entry mounts → the user profile (`user_profile_copy_id_button`) is the ONSTAGE route while the member-info key stops being onstage. Both onstage halves are in the verdict — `waitKeyCenter` alone resolves through the COVERED full-tree fallback, so a profile route mounted under an opaque cover used to pass (fixed 2026-08-16) |
| `group_member_action_cancel_closes_sheet` | `group_member_action_cancel_button` | after the real Cancel the sheet's Cancel AND Info actions UNMOUNT while the member-list route stays up (the peer ROW still resolves) — "the sheet closed" vs "Cancel popped the route". LIVE surface probe: the desktop popup SKIPs |
| `group_add_member_button_opens_picker` | `group_add_member_button` | the REAL profile row (every existing add-member case uses the `l3_open_group_add_member` deep link) mounts the picker's `group_member_invite_confirm_button`, which is then dismissed WITHOUT inviting and the member count is unchanged |
| `group_profile_scroll_view_scrolls` | `group_profile_scroll_view` | a gesture through the keyed ListView moves the content: the top anchor's centre y drops ≥ 80 (or leaves the tree) and a bottom-anchored control becomes reachable. SKIPs only when the body demonstrably fits: the bottom control sits above the scroll view's MEASURED bottom edge (`ui_key_center` y + h/2), not above a guessed constant that any shorter body would have turned into a swallowed SKIP |
| `group_profile_edit_name_dialog_cancel` | `group_profile_edit_name_dialog` + its Cancel action | the dialog key MOUNTS, a new name is typed into the real field, Cancel UNMOUNTS it, and the group's `showName` is still the ORIGINAL (Cancel discarded rather than applied) |

Notes if you extend it:

- **Launch reuse**: `sweep_keyed_gaps3` is APPENDED to `rui-ios-chat-main`,
  `rui-ipad-chat-main` and `rui-android-main` (after `sweep_msg_select`, whose
  `result=friends` matches), and to the desktop `rui-msg-select-keyed-gaps3`
  bundle, and it is a step inside `sweep_friendship_optimized` (right after
  `sweep_group_conf_member_extra`, whose state contract it matches).
  `--plan-json` confirms ONE pair launch with a single in-place
  `reset_friendship` between the two sweeps. `rui-{,ios-,ipad-,android-}keyed-gaps3`
  exist only for focused debugging.
- **Overlay/KeyedSubtree keys need `waitKeyCenter` / `_kg3WaitKeyCenterGone`**,
  never `waitKey` / `waitKeyGone` — same reason as batch #2 and
  `_memberMenuGone`.
- **`_safeDispose` moved** from `drive_real_ui_pair.dart` into
  `..._keyed_gaps3.dart` (same library, unchanged) to pay for this batch's four
  `part` directives without re-pinning the aggregator's complexity baseline.

### Verify-first exclusions from batch #3 (do NOT "fix" by writing a case)

- **`message_menu_item:translate`** — DEAD unconditionally. The generator adds
  `_uikit_translate`
  (`tencent_cloud_chat_message_item_with_menu_container.dart:544-552`) and then
  BOTH post-filters strip it: `:583` for every non-text elemType, `:608-614` for
  text. No elemType survives both.
- **`message_menu_item:convertToText`** — DEAD by construction. It needs
  `dataProvider.soundToTextPluginInstance != null`
  (`tencent_cloud_chat_message_row_container.dart:483`), but toxee gates the
  plugin registration on `tim2toxSoundToTextBackendSupported`, a
  **`const bool ... = false`** (`lib/ui/home/tim2tox_plugin_policy.dart:1`,
  called from `lib/ui/home_page_plugins.dart:270`). The voice-message
  precondition is moot.
- **`contact_group_notifications_tab`** — DEAD. The key is switched on
  `item.id == 'group_notification'` (`tencent_cloud_chat_contact_tab.dart:48`
  default / `:112` desktop), but the toxee fork DELETED that tab item from BOTH
  builders (`tencent_cloud_chat_contact.dart:192-207` and `:280-283`) because
  the Tox bridge has no group-application concept.
- **`group_invite_accept_button:<gid>`** — DEAD at two layers. It renders only
  inside `TencentCloudChatContactGroupApplicationList`
  (`..._contact_group_application_list.dart:315`), reachable only via
  `TencentCloudChatRouteNames.groupApplication`; `navigateToGroupApplication`
  (`tencent_cloud_chat_navigator.dart:268-275`) has ZERO callers, and
  `Tim2ToxSdkPlatform.getGroupApplicationList()` returns a hard-coded empty list
  (`tim2tox_sdk_platform.dart:9652-9675`) with `acceptGroupApplication` a no-op.
- **`contact_app_bar_add_group_item`** (and its `..._add_contact_item` /
  `contact_app_bar_menu_button` siblings) — DEAD in production. They live in the
  `else` arm of `if (TencentCloudChatContactAppBarName.trailingBuilder != null)`
  (`tencent_cloud_chat_contact_app_bar.dart:145-146` / `:198-199`); toxee assigns
  that hook for HomePage's whole lifetime (`lib/ui/home_page.dart:394`, cleared
  only in the dispose bag at `:406`) AND overrides `contactAppBarNameBuilder`
  (`lib/ui/home_page_bootstrap.dart:124` / `:303`).

## Keyed-but-never-driven batch #4 (`sweep_keyed_gaps4` + `sweep_keyed_gaps4_login`)

`tool/mcp_test/drive_real_ui_pair_keyed_gaps4.dart` (spine + dispatch + shared
probes), `..._keyed_gaps4_msg.dart`, `..._keyed_gaps4_attach.dart`,
`..._keyed_gaps4_mobile.dart` and `..._keyed_gaps4_login.dart`.

**Re-derived, not inherited.** The gap list was recomputed from scratch:
every key string in `lib/ui/testing/ui_keys{,_fork,_login}.dart` plus every
`ValueKey('…')` / `Key('…')` literal under `lib/ui`, `lib/call` and
`third_party/chat-uikit-flutter`, minus every string appearing in **non-comment**
driver code under `tool/mcp_test/drive_*.dart`. Result: **282** distinct UI keys,
**246** already driven, **13** prose-only and **23** absent. Two of the 13
(`contact_application_decline_button:<uid>`, `search_result_contact:<uid>`) are
false positives — they are driven through a key string assembled at runtime — and
one is a doc placeholder, so the honest undriven total is **33**. This batch
drives **16**; the other 17 are documented verify-first exclusions in the spine
file's header.

`sweep_keyed_gaps4` is TWO-PROCESS, `required=no-friend` / `result=friends`
(own handshake, one throwaway group via the shared `_kg3WithGroup`).
`sweep_keyed_gaps4_login` is SINGLE-instance, `required=no-friend` /
`result=no-friend` — it is a separate sweep **on purpose**: it logs out,
registers a throwaway account and deletes it, which is a state contract the
two-process sweep does not have, and merging them would force a reset.

| Scenario | Real control driven | Hard assertion | SKIP (75) when |
|---|---|---|---|
| `msg_select_clear_button_resets_count` | `message_select_clear_button` | Clear is not Cancel (select mode still up) AND the selection really is empty: the subsequent REAL delete-confirm leaves the seeded bubble alive in tree AND history — the same sequence without Clear deletes it | — |
| `msg_select_forward_combined_absent_gating` | `message_select_forward_combined_{button,item}` | GATING PAIR: the *individually* affordance mounts while its *combined* twin is absent (toxee pins `enableMessageForwardCombined` false). Surface is DETECTED — inline buttons on tablet/desktop, bottom sheet on phone | never — "no forward affordance" is a FAIL. Individually is pinned true at the app AND fork-default layer and the phone builder gates on `combined \|\| individually`, so the only thing that reaches that branch is the select-mode toolbar failing to mount (retracted 2026-08-16, same as `msg_select_forward_surface`) |
| `attachment_toolbar_disabled_entries_gating` | `message_attachment_{image,photo,video,search}_button` | GATING PAIR over one icon→key switch: file + personal-card entries mount, all four disabled entries absent | the MOBILE composer is mounted |
| `mobile_attachment_panel_entries` | `message_attachment_{options,file,camera}_button` | the "+" overlay MOUNTS both data-driven entries and they UNMOUNT on dismiss. Entries not tapped (OS picker / camera) | the DESKTOP composer is mounted |
| `mobile_voice_record_button_reveals` | `chat_voice_record_button` | mutual exclusion of the composer's trailing control across empty→typed→empty; the mic arm was previously invisible to every driver | the DESKTOP composer is mounted |
| `message_viewer_save_and_zoom_surface` | `message_image_bubble:<msgID>` (the fork's keyed tap target, single `tapAt` at its resolved centre; the row-fraction ladder is only a fallback), then `message_viewer_save_button`, `message_viewer_zoom_<msgID>` | the zoom key carries the MESSAGE IDENTITY, so it proves the viewer bound the right message; save button mounts; both unmount on close. Save tap NOT driven (OS gallery write). On failure it prints `render=` (image/error/loading/absent), `onDisk=` (the driver stats the very file, since iOS runs on this host) and `rendersFinalPath=` — enough to name the layer without another run | never — a viewer that will not open is a FAIL. Flakiness is not a product shape: a SKIP there is indistinguishable from a broken GestureDetector / an image that never decodes / a route that no longer pushes (retracted 2026-08-16) |
| `mobile_chats_unread_badge_flips` | `home_chats_unread_badge` | drained-0 baseline (badge absent) → one real inbound → `totalUnreadCount == 1` AND badge mounts → read → 0 AND badge unmounts | no bottom nav in this layout tier |
| `mobile_chat_back_clears_active_peer` | conversation row (real tap) + `chat_header_back_button` (real tap) | the row tap BINDS `activePeerId`, the real back control pops the pushed chat route (asserted **onstage**, not merely resolvable), `activePeerId` is null again, and one real inbound then raises `totalUnreadCount` to 1. NOTHING calls the `l3_clear_active_conversation` seam between the bind and the assert — that seam is precisely what the product was missing | no bottom nav in this layout tier (a master-detail shell rebinds a pane instead of pushing a route) |
| `mobile_mention_picker_confirm_inserts` | `mention_member:<uid>`, `mention_member_list_confirm_button` | the PEER receives a group message containing `@<label>` — end-to-end, not an in-app probe | the DESKTOP composer is mounted |
| `mobile_mention_picker_back_empty_selection` | `mention_member_list_back_button` | empty-selection contract: back commits nothing, so the peer receives the probe text with a bare trailing `@` and no label | same |
| `login_account_delete_confirm_removes_card` | `login_delete_account_confirm_button` | wrong-word guard holds (dialog stays open, card intact), then the right word UNMOUNTS the throwaway card while the primary survives; `finally` quick-logs back into the primary | — |

### Product/fork keys added with batch #4

Five controls had **no key at all**. Every addition is additive (an optional
parameter or a `key:` argument), changes no behaviour/layout/callback, and reuses
a key STRING `ui_keys.dart` already declared — so the pinned registry file was
not touched:

| Key | File | Note |
|---|---|---|
| `message_attachment_options_button` | fork `..._message_input_mobile.dart` | `_buildInputAreaIcon` gained an optional `iconKey`. `ui_keys.dart` already CLAIMED this parameter existed; it did not |
| `message_attachment_{file,camera}_button` | fork `..._message_attachment_options.dart` | derived from the option's `IconData` (only the two icons toxee injects; anything else returns null, so duplicate siblings are impossible) |
| `chat_voice_record_button` | fork `..._message_input_mobile.dart` | on the `Listener`, deliberately NOT on the `Transform`/`AnimatedBuilder` above it — a state-encoding key on an animated widget remounts it and destroys the animation |
| `mention_member:<uid>` / `mention_member:atAll` | fork `..._at_group_member_list.dart` | the MOBILE @-picker had zero keys while the desktop panel had the full contract |
| `mention_member_list_{back,confirm}_button` | same | back is NOT a cancel: both app-bar affordances call `_submitAtMemberList()` |

**Side effect worth knowing:** `personal_card_send_c2c` (batch #3) probes
`message_attachment_options_button` to tell the mobile composer from the desktop
toolbar. Until this batch attached it, that probe could never resolve, so the
case's mobile SKIP branch was unreachable and it reported the wrong diagnosis.

### Batch #4 campaign wiring

Launch reuse is honoured — `--plan-json` shows **one** pair launch for every
chain below, with only in-place `reset_friendship` maintenance:

- desktop: `rui-msg-select-keyed-gaps34` (`sweep_msg_select` →
  `sweep_keyed_gaps3` → `sweep_keyed_gaps4`), `rui-keyed-gaps4`,
  `rui-keyed-gaps4-login`; `sweep_keyed_gaps4` is a step inside
  `sweep_friendship_optimized` and `sweep_keyed_gaps4_login` inside
  `sweep_single_app_optimized` (immediately before the destructive
  `sweep_p1_single` tail).
- iPhone: appended to `rui-ios-chat-main` and `rui-ios-account-settings`; focused
  entries `rui-ios-keyed-gaps4` / `rui-ios-keyed-gaps4-login`.
- iPad: appended to `rui-ipad-chat-main` and `rui-ipad-account-settings`; focused
  entries `rui-ipad-keyed-gaps4` / `rui-ipad-keyed-gaps4-login`. On a tablet only
  ONE case skips — `mobile_chats_unread_badge_flips`, on `_msPhoneShell` — while
  the forward case hits `tabletAppBuilder`'s inline buttons instead of the phone
  sheet. **The "four narrow-shell cases SKIP on a tablet" claim this bullet used
  to make was WRONG**; see "iPad mounts the MOBILE composer" below.
- Android: appended to `rui-android-main`; focused entries
  `rui-android-keyed-gaps4` / `rui-android-keyed-gaps4-login`.

`sweep_keyed_gaps4_login` also rides `rui-app-entry-extra` (all three sweeps
there are single-instance `no-friend`/`no-friend`). Note this widened
`tool/check_source_contracts.py`'s `rui-app-entry-extra` needle from an exact
one-element list to a prefix, so appending compatible sweeps stays legal.

**No `osa*` anywhere** in either sweep — only `focusType` (atomic on every
platform), real taps, and the `l3_composer_set_text` / `l3_composer_send` /
`l3_send_file` / `l3_group_member_list` seams. The `@` that opens the mention
picker is PLUMBING for the surface under test, not the thing asserted, which is
why these cases do not have to SKIP on a device the way `sweep_group_mention`
does.

**NOT EXECUTION-VERIFIED.** Authored offline against the widget source; no
campaign run has driven any batch-#4 case yet.

### Mobile campaign matrix (`fixture_c_real_ui_mobile_campaigns.dart`)

The mobile half of the campaign catalog was split out of
`fixture_c_unified_runner.dart` into
`tool/mcp_test/fixture_c_real_ui_mobile_campaigns.dart` (the runner spreads
`mobileRealUiCampaigns` into `_realUiCampaigns`, so every flag behaves exactly
as before). Read that file for the per-campaign rationale; the load-bearing
rules are:

**Inventory** — **53** mobile campaigns as of 2026-08-16. **Re-derive, do not
trust this table**: `--list-real-ui-campaigns` is the authority. The previous
version claimed 38 and carried hand-maintained per-sweep CASE counts that
nothing regenerates; only the figures a script can produce from
`mobileRealUiCampaigns` are kept, because a hand-maintained number is a stale
number waiting to happen.

| family | campaigns | sweeps covered |
| --- | --- | --- |
| iPhone (`rui-ios-*` + `rui-mobile-shell`) | 22 | account_conf_extra, account_deep_extra, c2c_deep_extra, c2c_extra, calls_misc, chat, contacts, conv, group2, group_conf_deep_extra, ios_settings_main, keyed_gaps, keyed_gaps3, keyed_gaps4, keyed_gaps4_login, login, mobile_shell, msg_select, native_boundary_guards, p1_single, p2_reply, p3_writable, profile, settings2 |
| iPad (`rui-ipad-*`) | 20 | account_conf_extra, c2c_deep_extra, c2c_extra, calls_misc, chat, contacts, conv, group2, group_conf_deep_extra, group_conf_member_extra, ios_settings_main, keyed_gaps, keyed_gaps3, keyed_gaps4, keyed_gaps4_login, login, msg_select, p1_chat, p1_single, profile, settings2, tablet_layout |
| Android (`rui-android-*`) | 11 | chat, contacts, conv, keyed_gaps, keyed_gaps3, keyed_gaps4, keyed_gaps4_login, login, mobile_shell, msg_select, profile, settings2 |

**Ordering is free.** Every `sweep_*` scenario in `_requiredRealUiState` (all 32
of them, mobile-registered or not) declares `required=no-friend`, and the
`friends -> no-friend` transition is done IN PLACE by
`_executeInternalRealUiReset()` — no relaunch. So any sweep order is
self-consistent; the chains merely put `result=no-friend` sweeps first so the
runner does not have to insert a reset between them.

**Mobile campaign budget — `TOXEE_IOS_KEEP_SIMULATOR_FRONT`.** A backgrounded
iOS Simulator has its apps reclaimed by iOS after ~2-3 minutes (App Nap disable
and `caffeinate` do NOT prevent it; it is the iOS app lifecycle). Any mobile
campaign that chains **>= 2 sweeps** — and in practice the long single sweeps
too (`sweep_contacts` 15 cases, `sweep_settings2` 12) — will die mid-run unless
the Simulator is kept frontmost:

```bash
export TOXEE_IOS_KEEP_SIMULATOR_FRONT=1
dart run tool/mcp_test/fixture_c_unified_runner.dart \
  --class=2proc-ui --real-ui-platform=ios --real-ui-campaign=rui-ios-contacts
```

`launch_toxee_ios_instance.sh:64-68` reads the variable and switches
`open -g -a Simulator` (background, does not steal focus) to `open -a Simulator`
(frontmost, apps survive the whole run). The unified runner only PASSES THROUGH
`Platform.environment` and deliberately never sets the flag itself: topping the
Simulator window steals the host's mouse/focus, so it stays an explicit,
opt-in caller decision. Driving is still VM-service only — the window is raised
once at launch and never grabbed again.

**`rui-ipad-*` invocation rules** (unchanged, restated because the matrix grew):
selecting any `rui-ipad-*` campaign forces `TOXEE_IOS_DEVICE_TYPE=tablet` into
the pair launch, so it requires `--real-ui-platform=ios` and **cannot be mixed**
with a non-iPad campaign in one invocation (the device type is a pair-launch
property; mixing would silently run the second campaign on the first's
simulators).

**Sweeps deliberately absent from every mobile campaign** (the regression script
asserts this, so adding one turns the suite red):

| sweep | why it cannot be honest on a device |
| --- | --- |
| `sweep_p1_relaunch`, `sweep_p2_keys` | restart a peer through `Process.run('tool/mcp_test/stop_toxee_instance.sh' / 'launch_toxee_instance.sh')` (`drive_real_ui_pair_p1_relaunch.dart:773`/`:803`) — those are the macOS **desktop** instance launchers, so an iOS/Android pair would boot a macOS Toxee.app and overwrite the pair manifest |
| `sweep_p2_verify` | `paste_image_into_composer` needs an **image** on the host pasteboard; the portable seam `l3_set_clipboard` is text-only |
| `sweep_group_mention` | `osaType('@')` **is** the trigger under assertion; an l3/skill substitute would bypass the path the case exists to prove |
| the four `*_optimized` bundles | pure re-orchestration of sweeps already registered — they would only double-count the same cases |
| `sweep_mobile_shell` in `rui-ipad-*`, `sweep_tablet_layout` in `rui-ios-*` | every case SKIPs on the wrong form factor, inflating the skip tally without adding coverage |

**Wave gating.** The iPhone/iPad entries are grouped into three waves in the
catalog file: Wave 1 chains contain zero `osa*` call sites and are honest on a
Simulator today; Wave 2 depends on the iOS `osa*` substitute branches (fact 7
above); Wave 3 additionally depends on the narrow-shell long-press-menu /
bottom-bar / coordinate work. They are all REGISTERED so the catalog is the
single description of the intended matrix — registration is not a claim that
they pass.

**Two sweeps are iPad-only on purpose.** `sweep_group_conf_member_extra` has
zero `isMobileShell` branches, so its member-list / peer-menu navigation is only
known-good on a wide shell; `sweep_p1_chat`'s narrow-shell branches (recall /
forward / draft-restore across a pushed route) are not written yet, so an iPhone
run would drive the wrong surface instead of SKIPping. Add `rui-ios-group-member`
/ `rui-ios-p1-chat` once those branches exist — do not assume them.

`sweep_p1_chat` itself is **live-green on iPad (7 PASS / 0 FAIL / 1 SKIP,
2026-08-16)**. It got there through ONE root cause, not four: the non-desktop
recall-confirm dialog carried no `confirm_dialog_primary_button` key, and because
`showAdaptiveDialog` defaults to `barrierDismissible: false` the abandoned dialog
stayed on the Navigator stack and swallowed every subsequent tap — which is why
four unrelated-looking cases failed together. Green on iPad is NOT a claim about
iPhone: the sweep stays `rui-ipad-p1-chat`-only until its `isMobileShell`
navigation branches are written (the `osa*` objection to running it on a phone
was a red herring — every `osa*` wrapper already gates on `_usesSyntheticInput`,
which includes iOS).

### iPad mounts the MOBILE composer (corrects several claims above)

Proved live on 2026-08-16 (`rui-ipad-keyed-gaps4`, two independent runs) and
confirmed at the source: `TencentCloudChatMessageInput.tabletAppBuilder`
(`..._message_input/tencent_cloud_chat_message_input.dart`) delegates straight to
`defaultBuilder`, which builds `TencentCloudChatMessageInputMobile`. Only
`desktopBuilder` builds `TencentCloudChatMessageInputDesktop`. So on a tablet:

- `mobile_attachment_panel_entries` and `mobile_voice_record_button_reveals`
  **PASS** on iPad — they do not skip, because the "+" overlay opener and the
  hold-to-record mic are both mounted;
- `attachment_toolbar_disabled_entries_gating` **SKIPs** on iPad with "the MOBILE
  composer is mounted". Its desktop-composer branch is therefore reachable ONLY
  on a real desktop shell — an iPad run does not cover it, contrary to what the
  campaign catalog used to claim;
- the two `mobile_mention_picker_*` cases **RUN** on iPad (they gate on
  `_kg4ComposerKind`, not on the platform name);
- `mobile_chats_unread_badge_flips` is the ONLY tablet skip in the batch, and it
  gates on `_msPhoneShell` (no `home_bottom_nav`), not on the composer.

Rule of thumb: on iOS/Android, "wide shell" changes the SHELL (sidebar rail vs
bottom nav, master-detail vs pushed routes), not the COMPOSER. Anything that
wants the desktop input builder needs an actual desktop run.

### A swallowed `non_test_account` is a silent vacuous baseline

`l3_clear_active_conversation`, `l3_force_home_root` and the L3 seeding tools are
**test-gated**: an account registered through the real UI is a PRODUCT account
and gets `{ok:false, error:'non_test_account'}`. `Inst.forceHomeRoot` recovers
from that itself (mark → retry → unmark); **`Inst.clearActiveConversation` does
not**, and the widespread `on DriveError { if (!_isNonTestAccountError(e)) rethrow; }`
idiom then swallows the refusal as if it were benign.

It is not benign for anything that measures UNREAD.
`FfiChatService.getC2CUnreadCount` short-circuits to 0 for `_activePeerId`, so a
conversation that was never unbound reads 0 no matter what arrives. A drain loop
therefore "reaches a 0 baseline" immediately, the next real inbound is counted as
READ on arrival, and the case reports a broken badge that is really a live
diagnosis of its own precondition. That is exactly why
`mobile_chats_unread_badge_flips` sat at `totalUnreadCount=0 want 1` on iPhone
across every attempt: A's log contained **no** `l3_clear_active_conversation:
cleared …` line at all, while `l3_force_home_root` logged its clears fine.

Rules for any case that asserts unread/badge state:

1. wrap the clears in `markAccountTest()` / `unmarkAccountTest()` — the same
   idiom `_kg4ViewerSaveAndZoom` already uses around `l3_send_file`;
2. **fail** on a refusal, never swallow it — every assertion after it is
   unfalsifiable;
3. assert the conversation row is PRESENT in the dump (`tracked`), so an
   un-hydrated conversation list cannot drain "clean" vacuously.

Open follow-up (found, not fixed): on the NARROW shell nothing product-side
clears `setActivePeer` when the pushed chat route is popped — `_openChat` pushes
the UIKit message route and only `onTapConversationItem` binds the peer, with no
matching unbind. So a phone user who backs out of a chat keeps that peer's unread
suppressed. Fixing it needs a `NavigatorObserver` (or an equivalent route-pop
hook) in `HomePage`; the harness cases above do not depend on it because they
unbind explicitly.

**What the fix un-masked** (`mobile_chats_unread_badge_flips`, iPhone,
2026-08-16). With the conversation genuinely unbound the COUNT half is now
correct — `totalUnreadCount=1 want 1`, `perConv={c2c_…: 1}`,
`currentConversation=null` — so the case has moved from "the count never moves"
to a single remaining unknown: `badgeShown=false`, i.e. neither
`waitKeyCenter('home_chats_unread_badge')` nor `waitKey` resolves the badge
while the count IS 1. The count is read from the same
`TencentCloudChat…conversation.totalUnreadCount` the badge's builder
(`TencentCloudChatConversationTotalUnreadCount`, which does subscribe to the
`totalUnreadCount` key and `safeSetState`s) reads, so the two candidates are:

- a DRIVER limit — the badge is a `Positioned(top:-5, right:-6)` inside a
  `Stack(clipBehavior: Clip.none)` inside `BottomNavigationBarItem.icon`, so it
  paints OUTSIDE its parent's bounds; a centre-point probe that validates
  hit-testing can legitimately refuse it. Its sibling
  `sidebar_chats_unread_badge` has no such geometry, which is why
  `unread_badge_total_sidebar` passes on iPad;
- a PRODUCT gap — the bottom-nav item subtree not rebuilding with the store.

Next step is to probe `bottom_nav_chats` (the parent `Stack`'s key) and the
rendered count TEXT in the same run: if the parent resolves and the digit is on
screen, it is the driver's geometry rule, not the badge.

### Fourth iOS shift — three product bugs, root-caused live (2026-08-16)

Each of these was diagnosed by disproving the previous shift's hypothesis with a
live probe first, then fixed at the layer the evidence pointed at.

**1. The bottom-nav unread badge never rendered on the tab you were standing on**
(`mobile_chats_unread_badge_flips`, `badgeShown=false` while the store said 1).
`BottomNavigationBar` renders `selected ? item.activeIcon : item.icon`
(flutter/src/material/bottom_navigation_bar.dart). toxee attached the badge — and
the `bottom_nav_chats_tab` automation key — to `icon` ONLY, with `activeIcon` a
bare `Icon`, so BOTH vanished the moment the Chats tab was selected. Not a driver
geometry limit: the widget was not in the element tree at all. Fixed by
extracting `ChatsNavIcon` (`lib/ui/home/home_widgets.dart`) and building it for
both glyphs. **Mobile parity: shared Dart, so iOS and Android both get it; the
wide shell has no bottom nav and uses `sidebar_chats_unread_badge`.** Green on
iPhone in two independent runs, and independently confirmed green on Android.

**2. Backing out of a chat suppressed that peer's unread count forever.** On a
compact shell `_openChat` PUSHES the UIKit message route; `onTapConversationItem`
binds `setActivePeer(conversationID)` on the way in and nothing unbound on the
way out. `FfiChatService.getC2CUnreadCount` short-circuits to 0 for the active
peer, so every later message from that friend was counted as already-read — no
row badge, no nav badge, no tray badge — until the user happened to open some
other chat. Fixed with `ActiveConversationRouteObserver`
(`lib/navigation/active_conversation_route_observer.dart`), registered on the
root `MaterialApp`, which clears the binding when a route named
`TencentCloudChatRouteNames.message` pops / is removed / is replaced. An observer
rather than an `await`-at-the-push-site because the route is pushed from at least
four places and can also leave the stack via gestures with no call site at all.
**Mobile parity: iOS and Android share the observer; desktop/tablet never push
that route (they rebind a master-detail pane), so it simply never fires there.**
Covered by the new `mobile_chat_back_clears_active_peer` case, which is the one
case that never touches the `l3_clear_active_conversation` seam after binding.

**3. `message_viewer_save_and_zoom_surface` was red for four device shifts
because of TWO harness defects — and the "product decode bug" everyone
(including this shift, at first) inferred from the error placeholder was NOT
one.** The evidence chain, in order:

- `structured=null` proved the OLD failure mode outright: the case aimed its
  "6 bounded retry taps" using `_p1cKeyBounds`, i.e. flutter_skill's
  `interactiveStructured`, which only reports widgets in its interactive
  allow-list. `message_list_item:` sits on `TencentCloudChatMessageItemContainer`
  (a plain StatefulWidget), so the lookup returned NOTHING and **zero taps were
  ever dispatched**. The fork's 300 ms `onTapUp` window was NOT the cause —
  flutter_skill's `_dispatchTap` is a 50 ms down→up, and its `onTapDownTime > 0`
  clause makes even a dropped down harmless.
- With the tap actually landing (the new `message_image_bubble:<msgID>` key on
  the fork's GestureDetector, resolved through `ui_key_center`), the viewer STILL
  did not open, and the new `render=` probe said `error` while `onDisk=70B`
  reported a valid PNG on disk. The error placeholder is an `InkWell`, which wins
  the gesture arena over the image's parent `GestureDetector` — **an errored
  bubble is untappable by construction**, so no tap timing or position could ever
  have fixed it.
- `rendersFinalPath=true` then killed the "stale path" theory: the widget was
  decoding the EXACT file the driver had just stat'ed at 70 bytes. Which left
  one suspect nobody had checked — **the seed itself**. A three-line hermetic
  probe settled it: the shared fixture,
  `iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC…` (a 1x1 8-bit GRAY+ALPHA PNG),
  makes `ui.instantiateImageCodec` throw *"Codec failed to produce an image,
  possibly due to invalid image data"*. `file(1)` calls it "PNG image data,
  1 x 1", which is exactly why it survived four shifts of inspection. **The
  product was right to render the decode-error placeholder. The fixture was
  broken.**

Replaced with a 2x2 8-bit RGBA PNG in all four drivers that carried it
(`keyed_gaps4_attach`, `p1_chat`, `chat`, `high_value_extra`), plus the two
avatar seeds in `profile` which turned out to be undecodable in the same way.
`message_viewer_save_and_zoom_surface` then went **green on iPad, first attempt,
with `render=image`** and the bubble measuring a square 198x198 instead of the
placeholder's 198x263.34.

**New hermetic gate: `test/mcp/real_ui_image_seed_decodes_test.dart`.** It scans
the driver SOURCE for base64 PNG literals (re-joining Dart's adjacent-string
wrapping) and decodes each with the real Flutter codec. It caught the profile
avatar seeds on its first run. A device campaign is an absurd place to discover
an invalid fixture; this costs under a second in `flutter test`.

The fork hardening stays, on its own merits: on a local decode error the image
bubble now `evict()`s the cached provider, re-runs `_getImageUrl()` (so a stale
path is re-resolved too) and rebuilds with a bumped nonce, up to 8 times with
backoff capped at 2 s, and the error placeholder's own tap re-arms the same
recovery for the user. `Image` resolves its provider once per provider identity
and `FileImage` compares equal on (path, scale), so without this ONE unlucky
decode of a genuinely half-written received file sticks until the user leaves and
re-enters the chat. **Mobile parity: fork Dart, so iOS/Android/desktop all get
it.** Note it did NOT rescue the bad seed (8 retries over ~13 s all failed, as
they should) — that is the cleanest evidence that the seed, not the timing, was
the problem.

Three fork keys were added for this, mirrored in `lib/ui/testing/ui_keys_fork.dart`
and pinned in `tool/check_source_contracts.py`:
`message_image_bubble:<msgID>` (the tap target), `message_image_error:<msgID>` /
`message_image_loading:<msgID>` (the two placeholders, which share the image's
geometry so a bounds probe cannot tell them apart), and
`message_image_render_path:<path>` (the key CARRIES the path being decoded, so
one probe separates "undecodable file" from "stale path").

`_p1cImagePreviewOpenHardened` (`sweep_p1_chat`) used the same broken bounds
lookup AND passed on `rowRendered` alone as a "documented best-effort floor".
That floor is **retracted**: it made the case unable to fail for the exact
regression it names, and it hid this bug for a whole batch. It now drives the
bubble key and is hard in both directions.

**Also fixed this shift**

- `settings_prelogin_bootstrap_node_test` on iPhone
  (`onScreen="none-of-the-known-verdicts"`, both halves). NOT a missing sixth
  verdict and NOT `BootstrapProbeUnavailable`: the screenshot the case now takes
  on failure showed all three manual-node fields correctly filled, the caret
  still in the public-key field, and the Test button below the visible fold. The
  three fills leave the SOFT KEYBOARD up; the IME covers the bottom of a phone
  screen and swallows taps aimed there while the element tree keeps reporting
  those controls at their unobscured coordinates — so the tap "succeeded" and the
  probe never ran. Fixed with `Inst.hideKeyboard()` plus dropping the measured
  settings band cache (a band measured with the IME up is wrong for the resized
  viewport) before nudging and tapping. iPad never hit it: it has the viewport to
  spare, which is why this case had only ever been exercised there. iPhone:
  **13 PASS / 0 FAIL, first attempt.** The failure diagnostics gained the
  `invalidNodeInfo` sixth candidate, a per-field `form[...]` presence report and
  a screenshot, so the next reader gets the answer without a round-trip.
- `msgmenu_read_receipt_group_gating` on iPhone (`_openMessageMenuReal: row … not
  present`). The self leg passed and the PEER leg died with the message list
  absent from the tree entirely — `_dismissMessageMenu`'s corner tap pops the
  pushed chat route on a narrow shell. The case now re-anchors the group chat
  between the two legs (the same normalization it already does before the self
  leg; no assertion changed), and `_openMessageMenuReal`'s not-present branch now
  prints `_convShellDiag` so "row missing" can never again be confused with
  "surface gone". iPhone: **8 PASS / 0 FAIL / 2 declared SKIP, first attempt**.
- `Inst.clearActiveConversation` now has the mark → retry → unmark recovery
  `forceHomeRoot` had. The recovery was hoisted into a shared `_l3TestGated`
  helper and applied to the third test-gated `Inst` seam as well
  (`l3_pop_to_root`, reached from `osaEscape` and `_popMobileCoveringRoute`,
  which used to log a `non_test_account` refusal as a warn and carry on with the
  covering route still up). Paying for it needed a deliberate split: the OS-input
  primitives moved to `drive_real_ui_pair_inst_os_input.dart` as an
  `extension InstOsInput on Inst` (Dart has no partial classes; same library, so
  private access is unchanged), taking that file from its 1354 pin to 1178. The
  other two gated `Inst` seams — `l3_delete_friend` and `l3_window_state` — are
  deliberately NOT wrapped: both are called from paths that already mark the
  account, and both FAIL loudly rather than reporting a vacuous success.

### iPhone rollout — live results (2026-08-16, `rui-ios-*`)

First end-to-end iPhone runs of campaigns previously only exercised on iPad. All
under the STRICTER tally (`unexpectedSkipped` counts as failure), one complete
run each, `TOXEE_IOS_KEEP_SIMULATOR_FRONT=1`, pair torn down between campaigns:

| campaign | result | notes |
| --- | --- | --- |
| `rui-ios-msg-select` | **4 P / 0 F / 0 S**, rc=0 | clean first attempt |
| `rui-ios-keyed-gaps3` | 8 P / 1 F / 1 S (declared) | FAIL `msgmenu_read_receipt_group_gating` — `_openMessageMenuReal` reports "row … not present", i.e. the self bubble never rendered for the long-press; this case is in the expected-skip registry but it FAILED rather than skipped |
| `rui-ios-settings2` | 12 P / 1 F | FAIL `settings_prelogin_bootstrap_node_test` — see below |
| `rui-ios-keyed-gaps4` | 6 P / 2 F / 1 S (declared) | both `mobile_mention_picker_*` PASS; see the two reds below |

`settings_prelogin_bootstrap_node_test` is a genuinely NEW code path the iPad run
never reached. The iOS pair is TCP-only, so `peerPort=0` and the case takes its
udp-less branch and waits for `nodeTestUdpUnavailable` ("Node test needs UDP;
this device is running TCP-only"). The probe reported
`onScreen="none-of-the-known-verdicts"` for BOTH the dead and the live host —
none of the five verdict strings resolved at all, not merely the wrong one. Both
the snackbar (`BootstrapVerdictUi.snackBarFor`) and the persistent pill
(`pillFor`) use that exact l10n string, so the next step is whether the pill is
simply below the fold on a narrow shell after the probe re-renders (the case
already scrolls in bands) rather than a missing verdict. iPad passes this case
through its reachable/unreachable branches, which is why the udp-less branch had
never been executed anywhere.

Two sweeps stay iPad-only for the reasons in "Two sweeps are iPad-only on
purpose": `sweep_p1_chat` (no `isMobileShell` branches for recall / forward /
draft-restore across a pushed route) and `sweep_group_conf_member_extra` (zero
`isMobileShell` branches at all). `home_tabs_cycle_state_retained` remains a
by-design SKIP on a phone — there is no master-detail pane to retain.

### Back-to-back iOS pairs MUST be torn down between campaigns

The iOS pair pins **fixed host ports** for the Tox TCP relay —
`TOXEE_IOS_TCP_RELAY_PORT` default **3389** for A and **3390** for B
(`launch_ios_fixture_c_pair.sh`) — because two sandboxed Simulator apps cannot
reach each other over same-host UDP loopback and need exactly one relay each.
Both Simulators share the host network stack, so a **survivor from a previous
campaign still holding `TCP *:3389 (LISTEN)`** makes the next pair's `tox_new`
fail at registration. Guest apps also leak across a device-type switch
(iPhone → iPad and back), which is how an iPhone campaign launched straight
after an iPad one used to die in `[A] registering ... via real UI`.

So any script that runs more than one iOS campaign must call
`./tool/mcp_test/stop_ios_fixture_c_pair.sh` (and pause a few seconds) **between**
campaigns — not only at the end:

```bash
for camp in rui-ipad-keyed-gaps4 rui-ios-keyed-gaps4 rui-ios-settings2; do
  dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui \
    --real-ui-platform=ios --real-ui-campaign="$camp" > "/tmp/$camp.log" 2>&1
  ./tool/mcp_test/stop_ios_fixture_c_pair.sh >/dev/null 2>&1
  sleep 8
done
```

`stop_ios_fixture_c_pair.sh` documents the same rule at its head; this is the
campaign-level restatement, since the failure surfaces as a registration timeout
in the NEXT campaign and reads like a flake rather than a leak.

**Verification status (be precise about this):** these scenarios were authored
offline and are **NOT EXECUTION-VERIFIED** — no dart/flutter toolchain was
available where they were written, so nothing here has been run against a live
pair. The name/registry contracts ARE machine-checked
(`fixture_c_unified_runner_regression.sh`: scenario-name drift, the
fall-through guard, the SKIP/flaky tallies), and the geometry thresholds are
derived from the widget source (`add_friend_dialog.dart` /
`add_group_dialog.dart` caps, `AppSpacing.xl/lg` paddings), not measured.

**Android status (an earlier claim here was WRONG — corrected 2026-08-14).**
This document used to say Android had "never reached the business layer" and
that "the logs stop at EGL / there is no `pair.json`". Both pieces of evidence
were misread:

- `tool/mcp_test/.android_runtime/A|B/build/flutter_run.log` contains
  `app.started` **and** the `imsdk version arm64` banner **and** the Badge
  launcher probe. The Badge probe can only be emitted by an already-LOGGED-IN
  session: `BadgeService.instance.start` has exactly one call site,
  `lib/runtime/session_runtime_coordinator.dart:298`, which runs after the
  session is wired. EGL lines are just the first noisy thing in the log, not
  where it stops.
- The absent `pair.json` is not evidence of a failed launch either —
  `stop_android_fixture_c_pair.sh:55` deletes it on every NORMAL teardown, so a
  clean run always leaves the directory without one.

The accurate statement (updated 2026-08-16) is: **the Android pair reaches the
business layer AND one campaign is now proven green end-to-end.**
`rui-android-msg-select` ran `passed=4 failed=0 skipped=0` on `emulator-5554` /
`emulator-5556`. Every OTHER `rui-android-*` campaign is still UNPROVEN, not
impossible — report those as such.

Two things that first green run taught, both worth knowing before the next one:

- **JDK.** The Gradle build needs a JVM >= 11. A machine with only the system
  Java 8 fails at `assembleDebug` with "Dependency requires at least JVM runtime
  version 11", and the launcher surfaces it only as "A flutter run exited before
  the VM URI appeared". Export `JAVA_HOME` to a JDK 17 before launching.
- **Host contention is the dominant flake source.** Running the Android pair
  next to an iOS Simulator campaign starved the emulator to ~4.9 s frames and
  killed instance A's VM service mid-sweep (`SocketException: Connection
  refused` on the forwarded port, then every subsequent case fails as an
  EXCEPTION). That is environmental, not a scenario defect; the runner's
  automatic second attempt recovered it. Prefer not to overlap the two.

### Still not covered on mobile (deliberate, with reasons)

- **Mobile voice message (hold-to-record mic).** The mic affordance is a
  `Listener(onPointerDown/onPointerUp)` with no ValueKey and no L3 seam, and it
  needs a real microphone permission grant on the device. `ui_long_press` could
  synthesize the hold, but nothing in the tree can be targeted by key and the
  recorded artefact cannot be asserted — left uncovered rather than faked.
- **Mobile attachment/photo sheet.** Ends in an OS picker (the same seam the
  `rui-native-boundary-guards` sweep already documents as a SKIP on desktop);
  the mobile picker has no L3 path-injection equivalent.
- **Swipe actions / pull-to-refresh on the conversation list.** `ui_drag` can
  synthesize the gesture, but toxee's conversation row exposes no keyed swipe
  affordance to assert against, so a "gesture ran" check would assert nothing.
- **Bottom-nav re-tap scroll-to-top.** The handler exists
  (`TencentCloudChatConversationController.scrollToTop`) but there is no
  scroll-offset signal in `l3_dump_state`, so the effect is unobservable.
- **Landscape / rotation behaviour.** No launcher rotates a simulator and there
  is no in-app orientation seam; rotating would also require re-deriving the
  dialog-tier expectations (see the ambiguity note above).

## Direct driver (low-level / debugging)

Use the direct driver when you already have `ws/pid/nick` tuples or want to
debug one phase below the unified planner.

`dart run tool/mcp_test/drive_real_ui_pair.dart <scenario> <wsA> <pidA> <nickA> <wsB> <pidB> <nickB>`

Scenarios implemented: `handshake` (S61+S26, A accepts via the INLINE row
button), `handshake_detail` (S108, A accepts via the pushed application-DETAIL
screen — `contact_application_detail_accept_button`, the distinct UI entry S26
does not exercise), `decline` (S27), `message` (S62/S64, `RUITEST_STAMP=<n>` for
a stable nonce), `message_burst` (S64 alternating burst on an already-friended
pair), `group_message` (S151, A creates a public group over l3 setup, B joins
it, then both sides send via the REAL group composer), `custom_message` (S54,
verifies the add-wording round-trip then self-cleans back to no-friend),
`call_voice` (S65/S67/S76 happy path: invite -> accept -> hangup),
`call_reject` (S68 reject path), plus the runner-internal `reset_friendship`
maintenance step. Reusable primitives: `foreground`, `tapKey`/`tryTapKey`/
`tapText`/`focusType`/`tapAt`, `osaType`/`osaReturn`/`osaClear`, `waitKey`/
`waitText`/`waitState`, `openChat`, `openGroupChat`, `sendComposerMessage`,
`dumpState`, `shot`.

When invoked directly, `message` still assumes the pair is already friends; the
unified runner handles that dependency by planning it after an accepted
handshake when possible, or by restoring `paired_for_e2e` when `message` is
selected on its own.

## Single-instance LOGIN + SETTINGS scenarios (real clicks, one live app)

Added alongside `group_create` (same "drive only A, B launched-but-idle" shape):
real flutter_skill clicks on the REAL login/settings widgets of ONE live
instance, asserting real side-effects via `l3_dump_state`
(`autoLogin`/`notificationSound`/`sessionReady`/`currentAccountToxId`) or the
real UI response (snackbar / dialog mount / login-page transition).

`dart run tool/mcp_test/drive_real_ui_pair.dart <scenario> <wsA> <pidA> <nickA> <wsB> <pidB> <nickB>`

- `settings_sweep` — the whole suite on ONE launch (reuses startup; maximizes
  cases/batch). Order: copy_id → export_chooser → autologin → notification →
  logout_relogin → password (logout BEFORE password so the saved-account
  relogin is no-password; password LAST since it sets one).
- `settings_copy_id` (S100) — tap `settings_copy_tox_id_button` → "ID copied to
  clipboard" snackbar.
- `settings_export_chooser` (S105) — tap `settings_export_account_button` → the
  chooser mounts both `settings_export_profile_tox_option` +
  `settings_export_full_backup_option`; ESC dismisses (no native save panel).
- `settings_password` — tap `settings_set_password_button` → the keyed dialog
  (`settings_set_password_new_field`/`_confirm_field`/`_save_button`) opens; fill
  matching + Save → assert the **`Password set successfully` snackbar** (only
  shown when `AccountService.setAccountPassword` actually persists; real PBKDF2
  runs on the live isolate, so 25 s) **and** that the dialog is gone. "Dialog
  closed" alone is a false pass — the dialog pops before the async write
  completes.
- `settings_logout_relogin` — tap `settings_logout_button` →
  `settings_logout_confirm_button` → the app returns to the login page
  (`sessionReady=false`) showing `login_page_account_card:<tox>` → tap the card →
  quick-login back to HomePage (`sessionReady=true`).
- `settings_autologin` / `settings_notification` — tap the keyed `Switch` and
  assert the `l3_dump_state` flip. **Soft (harness limitation):** flutter_skill's
  synthetic `tap` finds an off-stage/below-fold `Switch` in the whole-tree search
  but does not toggle it, and flutter_skill has **no scroll** to bring the lower
  switches on-stage; `settings_sweep` excludes these from its hard pass.

> **Harness hazard — dialog pop buttons must be single-fired.** flutter_skill's
> `tap` fires the callback TWICE (a synthetic pointer hit AND a direct
> `widget.onPressed!()` via `_tryInvokeCallback`). On an **on-screen** dialog
> button that calls `Navigator.pop(...)` (logout confirm, password save) both
> land: the first pop closes the dialog, the second — fired while the button is
> still mounted mid-dismiss — pops the **page underneath** (HomePage). The
> logout/password handlers then hit their trailing `if (!mounted) return` and
> skip `pushAndRemoveUntil(LoginPage)`, leaving an **empty Navigator** (blank
> screen, zero interactive elements). Drive those pop buttons with
> `Inst.tapKeyCenter` (one `tapAt` at the element centre). The dialog **openers**
> (`settings_logout_button`, `settings_set_password_button`) stay on `tapKey`:
> they sit below the fold, where `tap`'s synthetic pointer misses and only its
> direct `_tryInvokeCallback` fires (exactly once → one dialog), and a coordinate
> `tapAt` would miss entirely.

**Live-verified (single instance, fresh account):** register click-through →
`copy_id` → `export_chooser` → `logout_relogin` (logout + saved-account
quick-login) → `password` all PASS via real clicks; the two `Switch` gates are
the documented soft cases above. Mobile parity: the underlying login/settings
widgets are shared Dart (mobile is covered by the L1 WidgetTester gates in
`test/ui/login,register,settings/`); this harness drives the macOS desktop app.

## Codified today vs live-verified today

The shared planner/driver contract now codifies nine real-UI scenarios plus an
expanded reusable campaign catalog:

- `handshake`
- `message`
- `message_burst`
- `group_message`
- `handshake_detail`
- `decline`
- `custom_message`
- `call_voice`
- `call_reject`

Representative catalog buckets:

- `accepted-friend-*`: one-launch chat/call stacks after an accepted
  friendship, for example `accepted-friend-inline-full` and
  `accepted-friend-inline-group-message`.
- `fresh-*` / `no-friend-*`: request/no-friend flows that stay schedulable on
  one launch, for example `fresh-custom-message` and `no-friend-inline-call`.
- `*-then-decline`: mixed-state chains where the planner inserts
  `reset_friendship` maintenance instead of forcing a relaunch, for example
  `inline-call-then-decline`.
- `all-*`: end-to-end smoke bundles such as `all-current` and `all-expanded`.

That "codified" claim is about manifest/planner/dry-run semantics and the
discoverable scheduler catalog. It does **not** mean all 100 campaign branches
have already been repeatedly dogfooded live. Today the continued live
confidence is:

- `handshake` and `message`: live-driven and verified below.
- `group_message`: planner/driver support is now landed and was dogfooded on
  2026-06-07. The scenario now clears full-mesh bootstrap, group create/join,
  and real UI chat open, but live delivery remains unstable: some runs pass
  `A->B`, others drop both directions entirely, with the joiner showing an
  empty candidate group conversation and the creator retaining only its own
  self-send. So it is not yet a stable gate.
- `call_voice`: live-driven in continued execution below, but still a local
  dogfood result rather than a CI-grade gate.
- `message_burst`, `call_reject`, `handshake_detail`, `decline`, and
  `custom_message`: scheduler/driver support is in place and hermetic
  regression covers the planning contract, but continued live dogfood is still
  in progress before treating them as stable gates.

## Live-verified so far (real UI, two process)

| Spec | What was driven (real UI) | Result |
|---|---|---|
| **S26 / S61** accept / handshake | B: Add-Friend dialog (`new_entry_menu_button` → `new_entry_add_contact_item` → `add_friend_id_input` → `add_friend_submit_button`); A: New Contacts → **Accept** | **PASS** — friendship both directions, application consumed |
| **S62 / S64** message delivery | real composer + real Return, A↔B | **PASS** — bidirectional, rendered bubbles on both sides |
| **S65 / S67 / S76** voice call happy path | real chat header voice button + real incoming-call accept + real hangup | **Observed PASS** — see continued execution notes below; still local dogfood, not CI-gated |

## Filtered set still to codify (same primitives)

Friend: S46 auto-accept. · Messaging: S64 concurrent (burst), S21/S88
file/image (attach button), S78 voice. · Group: S33 join, S37
kick, S81 invite, S47 auto-accept. · Calls: S66 initiate video, S68 decline,
S74/S75 mute/camera. · Conversation: S83 mute, S52 profile, S63 receipt/typing.

Each reuses `foreground` + `flutter_skill` taps + (for sends) the osascript
composer/Return recipe.

## Findings from continued execution (blockers / real bugs)

Driving the next batch surfaced that the real-UI layer is **not fully wired for
this slice** — these are the "problems found", several are genuine product/fork
bugs the `l3_*` bypass masks:

- **[PRODUCT BUG — FIXED ✅] Register-time display name never reached the live
  Tox instance.** After a fresh real-UI handshake, BOTH peers showed each other
  by raw tox-ID (`nickName` empty, both directions). **Root cause** (logs:
  `HandleFriendName: … changed name to:` *empty*): `registerNewAccount`
  (`account_service.dart`) called `updateSelfProfile`→`setSelfInfo`→
  `tox_self_set_name` on the **temp** FfiChatService, then **disposed** it
  (`await svc.dispose()`) and re-created a `_createAccountScopedService` from the
  on-disk profile saved *before* the name was set — so the name lived only on the
  discarded temp instance; the live instance kept an empty name and Tox sent ""
  to peers. The l3 S52 gate masked it (asserts via an explicit later
  `l3_set_self_profile` push). **Fix:** call `updateSelfProfile(nickname,
  statusMessage)` on the live scoped instance in BOTH register branches.
  **Verified** on the rebuilt app: handshake gate now prints
  `A sees B="BobFix" B sees A="AliceFix"` and the contact list renders the
  nickname. The driver's `handshake` scenario now gates on name propagation.
- **[FORK — FIXED ✅] Call automation `ValueKey`s now attached.**
  `chat_call_voice_button`/`chat_call_video_button` added to the header
  `IconButton`s (`tencent_cloud_chat_message_header_actions.dart`).
  `call_accept_button`/`call_decline_button` added to the `CallDockAction`s in
  `incoming_call_view.dart`. The in-call mute/camera/hangup + outgoing hangup keys
  already existed but were **dropped** — `_CallDockButton` never applied
  `action.key`; fixed in `call_ui_components.dart` (key the InkWell), which
  activates ALL `CallDockAction` keys at once. `contact_new_contacts_tab` was
  already correctly on the tappable row (earlier "not found" was the stale build).
  **Verified live** (rebuilt): `chat_call_voice_button` taps → initiates the call;
  A's outgoing UI renders with a findable+tappable `call_hangup_button` (tap → call
  idle). accept/decline/mute/camera use the same now-proven activation.
- **[NOT A BUG — call flow works] S65 + S67 verified end-to-end via real UI.**
  An earlier "incoming call never rings / finishes in 1s" reading was a **test
  artifact** of rapid *overlapping* manual call attempts confusing the call state.
  A **clean** single call (both idle first) showed B `ringing/incoming` **stably
  for 7+ s**; tapping `call_accept_button` put **both sides `inCall`**. A suspected
  outgoing **double-invite was also a miscount** — the clean isolated log shows one
  tap → one `audioCall` → one `signaling_invite` → one `startCall`/
  `_onOutgoingCallInitiated`. (The earlier `grep -c` matched two *different* line
  patterns for one call; the `inv_0`/`inv_1` were two separate taps.) Full real-UI
  call path confirmed: `chat_call_voice_button` → ring → `call_accept_button` →
  `inCall`, `call_hangup_button` → idle. No fix needed. **Lesson:** isolate the
  scenario (idle start, fresh log window) before declaring a state-machine bug.
- **Composer→typing not wired (S63).** No setTyping on composer text-change in the
  message-input dir, so typing in the real composer does not raise the peer's
  `isTyping`. (l3 uses `l3_set_typing`.) Real-UI typing would need that wiring.
- **Self-profile edit is an overlay**, edit pencil at the top of a dialog
  (`profile_edit_toggle` IS attached); the inline edit field/save keys did not
  land via `tap{key}` in edit mode — drive by coordinates + osascript, or attach
  keys to the editable.

- **[PRODUCT CRASH — found via real UI, FIXED ✅] Conversation-mute switch
  SIGSEGV'd the app — an FFI ABI signature mismatch.** Toggling the real
  friend-profile mute switch (`user_profile_conversation_mute_switch`) crashed
  both instances: `[callback_bridge] FATAL: received signal 11`. **Root cause:**
  the native `DartSetC2CReceiveMessageOpt` (`dart_compat_user.cpp`) declared **2
  args** `(const char*, void* user_data)`, but the Dart binding
  (`native_imsdk_bindings_generated.dart:711`) calls it with **3**
  `(Pointer<Char> json_identifier_array, UnsignedInt opt, Pointer<Void>
  user_data)`. The args misaligned: native `user_data` received the `opt`
  **integer** and dereferenced it as a pointer (`SendApiCallbackResult` →
  `UserDataToString` → `str[0]` on addr `0x2`), and the userID JSON was parsed as
  a nested object so the list was always empty. Exactly the
  "`Dart*` signature drift compiles fine, crashes at call time" hazard in
  tim2tox's CLAUDE.md. The l3 gate (`l3_set_c2c_recv_opt`, prefs) bypassed the
  binding entirely, so the data-layer S83 gate never caught it. **Fix:** corrected
  the native signature to the 3-arg ABI, parse `json_identifier_array` as a plain
  string array, take `opt` directly (+ retained a use-after-free hardening on the
  success callback: copy `user_data` to a string up front, use
  `SendApiCallbackResultWithString`). **Verified:** rebuilt `libtim2tox_ffi`,
  re-embedded, toggled the switch 3× → NO crash, switch flips ON. **Native FFI fix
  → covers desktop AND mobile** (the ABI mismatch crashed both). GET + group
  variants checked: GET's 2-arg ABI already matches; group SET routes through the
  safe Platform. **Residual (separate, pre-existing):** the binary-replacement
  path stores `opt` in a C++ map, distinct from the Prefs-backed conversation
  cache that `notification_message_listener._shouldSuppress` reads, so the cache
  `recvOpt` (and notification suppression) doesn't reflect the toggle — a
  native→Dart sync follow-up, not the crash.

### Friend-profile controls sweep (real UI, single instance) — a clear pattern

Drove every control in the friend-profile sheet. **toxee Prefs-backed controls
work; SDK native-manager controls are broken/crashy** — the systematic split that
real-UI driving surfaces (the l3/Prefs gates bypass the SDK native path):

| Control | Path | Result |
|---|---|---|
| **Pin (S84)** | toxee `FakeConversationManager.setPinned` (Prefs) | ✅ `pinnedConversations` flips, no crash |
| **Block/unblock (S29)** | toxee Prefs blackList | ✅ `blockedUsers` flips both ways, no crash |
| **Mute (S83)** | SDK `setC2CReceiveMessageOpt` (native) | crash FIXED (ABI); switch toggles; `recvOpt` cache-sync residual |
| **Remark (S30)** | SDK `setFriendInfo` (native) | ⚠️ dialog + keystroke land text, but Confirm **doesn't persist** (UI + dump stay "BobFix"); same broken native-manager path as mute (likely another `Dart*` ABI/stub) |
| **Clear Chat History** | — | tapped + confirmed, no crash; observable inconclusive (a `[Call]` record remained) |
| **Delete friend (S28)** | — | delete tap ok, but the confirm-dialog button key (`user_profile_delete_friend_button`) wasn't found → incomplete |

**Takeaway:** the friend-profile controls that route through toxee's own
Prefs-backed managers (Pin, Block) are solid; the ones routing through the Tencent
SDK's native binary-replacement managers (Mute `recvOpt`, Remark `setFriendInfo`)
are where the bugs cluster — the **audit opportunity** (other `Dart*` natives vs
the generated bindings) is real and high-value. Remark (S30) is the next likely
ABI/stub fix in the same family as the mute crash.

**Net:** the foundational slice (friend handshake/accept, C2C messaging, calls)
executes cleanly via real UI and PASSES; the friend-profile Pin/Block controls
PASS; Mute crash is fixed; Remark + the recvOpt cache-sync are open native-path
follow-ups. The rest of the filtered slice is gated on fork
UI-wiring work (attach keys, wire typing) + one native bug (name propagation),
each rebuild-gated. Those are the concrete next "problems to solve".

## Platform launchers (all five wired into the unified runner)

`--real-ui-platform=` selects the A/B pair launcher; the drivers are shared.

| platform | launcher | restore (`paired_for_e2e`) | input path |
| --- | --- | --- | --- |
| macos   | `launch_fixture_c_pair.sh`          | `restore_fixture_c_pair.sh`  | osascript + VM-service |
| ios     | `launch_ios_fixture_c_pair.sh`      | via macOS container restore  | synthetic VM-service |
| android | `launch_android_fixture_c_pair.sh`  | `adb exec-in run-as ... tar -x` into the debug app sandbox (2026-07-12; the pair DOES reach the business layer — see "Android status" — but no scenario-level green run is on record) | synthetic VM-service (l3/skill substitutes for `osa*`) |
| windows | `launch_windows_fixture_c_pair.ps1` | `restore_fixture_c_pair.ps1` (PowerShell-native, no bash/jq) | synthetic VM-service (headless) |
| linux   | `launch_linux_fixture_c_pair.sh`    | `restore_fixture_c_pair.sh` (portable: tox_profile + JSON history) | synthetic VM-service (headless) |

Linux specifics (added with the 2026-07-11 VM campaign):

- Runtime root defaults to `build/linux_runtime/` — always locally writable,
  including on a share-shim checkout (`tool/vmtest/make_shim.sh`) where `tool/`
  is a read-only symlink into the Mac share. Override: `TOXEE_LINUX_RUNTIME_ROOT`.
- Headless hosts (SSH, no `$DISPLAY`): the launcher (and `run_toxee_linux.sh`)
  auto-start a private Xvfb `:99` — synthetic flutter_skill input needs a live
  GTK surface, not a physical screen. `DISPLAY` is honored when already set.
- `TOXEE_PAIR_TCP_ONLY=1` mirrors the macOS same-host TCP-only mode.
- Fixed VM-service ports 8201/8202 (`TOXEE_LINUX_VM_PORT_A/B`),
  `disable-service-auth-codes` → deterministic `ws://127.0.0.1:<port>/ws`.
- `libirc_client.so` (built via `tool/ci/build_tim2tox.sh --target linux
  --with-irc`) is bundled next to the runner when present; without it only the
  `irc_join_channel_loopback_live` live JOIN is affected.

Windows restore (same campaign): the launcher no longer refuses
`TOXEE_FIXTURE_C_RESTORE` — `restore_fixture_c_pair.ps1` restores the fixture
trees into `<runtime>\support\A|B` and the instances boot them via
`l3_boot_existing_account`. The unified runner's restore gap-guard is now
Android-only. OpenSSL runtime DLLs for `libirc_client.dll` are staged from
`build\native-artifacts\windows\` (produced by `--with-irc`).

## Windows — aligned with macOS (2026-09-04, win11_ltsc Parallels VM)

Windows used to be the "headless" desktop: every `osa*` primitive was
substituted by an l3 / flutter_skill seam, the relaunch sweeps could not run
(they shelled out to the macOS `.sh` single-instance launchers), and nothing
had been run on the VM since the 2026-07 restore work. It now has the same
three things macOS has — a REAL OS-input layer, peer process control, and a
campaign catalog — plus a runbook that works from an SSH session.

### Real OS input (`TOXEE_WIN_OS_INPUT=1`)

`drive_real_ui_pair_inst_os_input.dart` gained a Windows backend: every
`osa*` wrapper (type / paste / Return / Shift+Return / Escape / clear /
clipboard) runs a PowerShell step through `tool/mcp_test/win_os_input.ps1`
(passed as `-EncodedCommand`; `-Command <text>` strips embedded double
quotes), serialized on the same chain as osascript so two peers' key events
never interleave. Each step starts with `Enter-ToxeeInput`: release stuck
modifiers, `Set-ToxeeForeground` (verified with `GetForegroundWindow`; the
`AttachThreadInput` bypass is what actually wins against the peer's foreground
lock), then `FocusFlutterView` (Win32 focus on the engine's `FLUTTERVIEW`
child). Keys go through `Send-ScanText` / `Send-ScanKey` — `SendInput` WITH
real scan codes, Shift held across shifted runs, 25 ms per key. `focusType`
takes the real paste path (with the `getTextValue` verify + `enterText`
fallback macOS has), the composer send / multiline / "typed but not sent" /
real Ctrl+V image-paste (`System.Windows.Forms.Clipboard.SetImage`) cases run
their genuine keystroke paths, and `_usesSyntheticInput` is false for Windows
under the flag. It is OPT-IN because it needs the interactive window station:
the driver must run INSIDE the console session (see runbook); without the flag
Windows keeps the documented synthetic contract byte-for-byte. Still
substituted even with the flag: the three Cmd+Ctrl chords (search / new
conversation / settings) — the app binds them with `meta` = the Windows key —
so they stay on their l3 intent seams.

Why not `WScript.Shell.AppActivate` + `SendKeys` (the first cut, 2026-09-04,
diagnosed with `probe_win_composer_input.dart`, runs 9-18):

- **`SendKeys` never reached Flutter at all.** It injects virtual keys with
  scan code 0; the Windows embedder maps every such key to the same physical
  key (`0x1600000000`), the first key-up mismatches the logical key recorded
  for it, `HardwareKeyboard` asserts (`'!_pressedKeys.containsKey(...)'`, 68
  times in one run) and from then on EVERY KeyDown is rejected before text
  input. Notepad took the same keys happily, so only a Flutter-side view of
  the app log exposed it. Scan-coded `SendInput` produces zero assertions.
- **`AppActivate(pid)` returned `True` while the peer stayed foreground.** B
  is launched last and holds the input lock; `SetForegroundWindow` from a
  third process is ignored (`SwitchToThisWindow` too, here). Keys therefore
  went to B. And on an already-foreground window `AppActivate` moves Win32
  focus from `FLUTTERVIEW` to the runner frame, where WM_CHAR is dropped.
- **Toggling Shift per character dropped characters** (`REALNICK` → `R`,
  `RE`, `REALN` at 6-40 ms); holding it across the shifted run and pacing
  25 ms per key typed everything. Lower-case text was always intact.
- **Cases must not type into a composer that is still settling** — the
  draft coordinator reloads the field when the conversation context settles
  and drops text typed before that (the probe's first typing step vanished;
  the driver's `openChat` waits for the surface, so cases are unaffected).

### Native crash the VM exposed: toxcore API calls raced `tox_iterate` (fixed in tim2tox)

The first full `rui-win-os-input` runs died between sweeps: toxee A vanished during
`reset_friendship` (Windows Application log: `tim2tox_ffi.dll` 0xc0000005 at 05:29:17,
and an earlier `ntdll` 0xc0000374 heap corruption at 02:32). A's log showed the
Tox event thread's `HandleFriendConnectionStatus` callback interleaved INSIDE the
Dart thread's `tox_friend_delete`. tim2tox drives `tox_iterate()` from its own
`event_thread_` but every FFI-side API call (`tox_friend_delete`, `tox_friend_add`,
group/file APIs, ~300 sites) hit the same `Tox*` unserialized — toxcore is
single-threaded per instance by contract (`tox.h`), and `ToxManager::iterate_mutex_`
only ever guarded iterate vs shutdown. macOS runs the same code; the ARM64 VM's
x64 emulation just widens the window (3 of 5 runs crashed there).

Fix (tim2tox, shared native code, so mobile too): enable toxcore's own per-instance
lock — `tox_options_set_experimental_thread_safety(opts, true)` in
`ToxManager::initialize` (and the throwaway restore instance). toxcore takes the lock
per API call and RELEASES it around every user callback, so callbacks may call tox
APIs and take tim2tox mutexes without a lock-order cycle. The few toxcore entry
points that bypass that lock (`tox_callback_*` registration, `toxav_new`/`toxav_kill`)
now run under the new `ToxManager::lockIterate()` (no-op on the iterating thread).
Symbols for the next crash: `TIM2TOX_NATIVE_BUILD_TYPE=RelWithDebInfo` (honoured by
`tool/ci/build_tim2tox.sh`, PDB captured next to the DLL) + WER `LocalDumps` for
`toxee.exe` into `C:\vmtest\dumps` + the SDK's `cdb` (`Debuggers\arm64\cdb.exe`
reads x64 dumps).

### Case fixes from the first Windows real-input runs

- `image_preview_open_hardened` — two layers. (1) Harness: the keyed image bubble
  resolved a centre BELOW the fold (Windows' default window is ≈625 logical px tall
  and the freshly received image row hung under the composer), so the keyed tap hit
  the composer; `_ensureKeyInViewport` (drive_real_ui_pair_geom.dart) wheel-scrolls
  the list until the bubble sits above the composer. (2) PRODUCT, Tim2Tox Dart: the
  bubble then showed the error placeholder because a received file was NEVER attached
  to its message on Windows — `FfiChatService` validated native paths with
  `startsWith('/')` (`progress_recv: WARNING - actualPath is invalid`, `file_done:
  ERROR - Invalid local path`), which rejects every `C:\...` path; the completed
  file sat in `file_recv/` while the message kept the `receiving_…` placeholder.
  Now `_isAbsoluteLocalPath` (`package:path` `isAbsolute`); mobile/macOS paths start
  with `/` and are unaffected.
- `sweep_p1_relaunch` — two layers. (1) Harness: `_runInstanceCtl` captured the
  single-instance launcher's stdio; the toxee.exe it starts inherits that pipe, so
  the driver blocked until the app EXITED (25 min at "relaunching instance") — on
  Windows it now spawns with `inheritStdio`. (2) Harness isolation, product side:
  `shared_preferences_windows` rewrites ONE per-user JSON file from each process's
  in-memory map, so A and B clobbered each other's keys on disk and the relaunched A
  read back only B's (`l3_force_home_root refused — non-test account`); macOS'
  NSUserDefaults merges per key, which is why the key prefix sufficed there. When
  `TOXEE_APP_SUPPORT_DIR` is set on Windows/Linux, `PrefsBootstrap` now installs
  `IsolatedPrefsStore` (`<dir>/shared_preferences.json`, serialized write-then-rename),
  the same switch that isolates every other store.
- `group_at_all_send` / `draft_restore_on_conv_switch` / `typing_indicator_render`
  (real-keystroke premises) now run and pass on Windows under the flag.

### Second pass — the leftovers, root-caused (2026-09-04, later)

- **`read_receipt_double_tick` on a REUSED pair** — two layers. (1) Harness seam
  gap on desktop: `l3_clear_active_conversation` cleared the FFI active peer and
  the facade's current conversation but NOT the HomePage's detail pane, which
  stays mounted in the master-detail layout and marks inbound read as it arrives;
  the seam now re-applies the current shell tab (the product's own deselect
  path). (2) The PRODUCT defect that remained (repro_rr8, B log): after
  `reset_friendship` the `FakeFriendDeleted` handler tombstones `c2c_A` in
  `FakeChatDataProvider._sdkDeletedConvIds`; the 5 s rebuild skips tombstoned
  ids, and the only thing that lifted the tombstone was a `topicMessage` event —
  which the product's inbound path never emits (the binary-replacement hook
  persists directly and `_emitInboundMessage` stays silent). So after the
  re-add, A's messages landed in persistence (`persistenceUnread=1`) while B's
  sidebar entry (native-push placeholder) stayed at unread 0 / stale preview
  until B opened the chat or sent something. Same for "delete conversation, peer
  writes again". Fix: the hook now fires `onInboundMessagePersisted` after the
  row is stored; toxee lifts the tombstone and rebuilds that one entry
  (`FakeChatDataProvider.noteInboundMessagePersisted`), and FakeIM emits
  `FakeFriendAdded` on the friend-list diff so a re-add lifts it too. Shared
  Dart — covers mobile. Regression: `test/sdk_fake/fake_provider_inbound_tombstone_test.dart`.
- **`sweep_p1_relaunch` flake (offline_pending / presence_dot after B's relaunch)**
  — every relaunch log, passing or failing, shows the post-relaunch re-wire
  returning `bootstrap ok=false` both ways: `l3_add_bootstrap_node` is
  test-account gated and the relaunched side comes back without the seed
  marker, so the re-wire was always refused and B only reconnected through the
  relay its savedata still held. With per-peer relays (the restarted peer's
  relay has a NEW DHT key, so A's stored entry is dead) that became a coin
  flip. `_p1rReseedMutualBootstrap` now marks both sides for the wiring window
  (and restores the non-test state), like the launch-time seed.
- **`typing_indicator_render` flake** — Tim2Tox expired a received typing flag
  3 s after arrival although tox typing is STATE (transmitted only on change);
  any slow receiver dropped a still-typing peer. Now kept until the peer clears it
  or goes offline (30 s safety cap); the case seeds once and samples after its scan.
- **"A connected" timeouts (TCP-only pairs)** — A hosted the only relay, and the
  A -> B wire dialed that same port with B's DHT key (a handshake against the
  wrong server key), so A reached "connected" only through a public relay
  (minutes, or never). Both launchers now give each side its own relay
  (B = A + 1, recorded per instance in pair.json) and `wireFullMeshBootstrap`
  connects each side to the PEER's relay (`pairInstanceTcpRelayPort`).
- **Native log lines printed `{}` / `%zu` literally** — the legacy
  `V2TIM_LOG(level, fmt, args...)` overload dropped every argument; it now
  substitutes both placeholder styles (`V2TIMLog::legacyFormat`), so
  `add_bootstrap_node host=127.0.0.1 port=33391 err=0` reads as such.
- **`DeleteFriend` global callback threw** `List<dynamic> is not a subtype of
  String` on every friend deletion (all platforms): SDK patch 0019 routes
  `friend_id_array` through `_getGlobalCallbackJsonString`.
- **`libirc_client.dll` missing on the Windows shim** — built once with
  `build_tim2tox.sh --target windows --with-irc` (vcpkg openssl); captured next to
  the FFI in `build/native-artifacts/windows`, bundled by the launcher.
- **Recall-notice row overflow (screenshot 2026-09-04 14:09)** — the desktop
  message row placed the tips item as a bare child of a max-size `Row`, so it got
  UNBOUNDED width, capped itself to the WINDOW and overflowed the narrower pane.
  The row now wraps it in `Flexible` (`tencent_cloud_chat_message_row.dart`) and the
  tip caps to its pane constraints minus the margin
  (`tencent_cloud_chat_message_tips_common.dart`). Regression test through the REAL
  row: `test/ui/chat/message_tips_pane_width_test.dart` (fails on the old row with
  `RenderFlex overflowed by 784 pixels`).

### Live results (win11_ltsc, 2026-09-04, `TOXEE_WIN_OS_INPUT=1`)

Re-derive rather than trust; one day's runs on an emulated-x64 ARM VM.

| bundle / sweep | result | notes |
| --- | --- | --- |
| rui-win-os-input / sweep_group_mention | 2/0/0 (5 runs) | real `@` typing, incl. the previously SKIPped @All render check |
| rui-win-os-input / sweep_p1_chat | 8/0 on the reused pair (repro_rr9 + full bundle), 8/0 fresh | `read_receipt_double_tick` on the REUSED pair after `reset_friendship` was the conversation-tombstone product defect (see "Second pass"); green since the hook→provider inbound notify + FakeFriendAdded fix |
| rui-win-p2-verify / sweep_p2_verify | 1/0/0 | real Ctrl+V image paste into the composer |
| rui-win-account-settings | login 9/0 · keyed_gaps 8/0 · keyed_gaps4_login 1/0 · settings2 13/0 · profile 8/0 | first attempt, no retries (was 6/2 · 11/13 before the scan-code input) |
| rui-win-relaunch / sweep_p1_relaunch | 3/0/2 first attempt, post-relaunch re-wire `bootstrap ok=true` both ways | was flaky (0/3, 1/2, 3/0, 1/2→retry) until the reseed ran under the test marker (see "Second pass"); the 2 SKIPs are the same same-host limits macOS records (call ring, public NGC chat-id) |
| rui-win-relaunch / sweep_p2_keys | 2/0/1 | the SKIP is by design (presence_dot_relaunch is owned by the p1 sweep) |

Flakes seen and their causes: `typing_indicator_render` (typing flag expires 3 s after
arrival; the case now reads the entry before the slow text scan), `chat_recall_message`
"foreground failed (exit 124)" (per-process `Add-Type` csc compile took >25 s; the helper
now caches its assembly, load ≈0.4 s), one fresh relaunch where A never reached
`isConnected` within the wait (TCP-relay bootstrap timing).

### Peer process control (relaunch sweeps)

`stop_toxee_instance.ps1` / `launch_toxee_instance.ps1` are the PowerShell
twins of the macOS single-instance scripts. The pair launcher now records each
instance's contract in `instance.json` (`exe`, `vm_port`, `support_dir`,
`tcp_only`, `tcp_relay_port`), and the relaunch twin re-creates the SAME
instance from it (no build, no wipe → the relaunched process autologs into the
stopped account). `drive_real_ui_pair_instance_ctl.dart` picks the scripts +
runtime dir per platform, so `sweep_p1_relaunch` / `presence_dot_relaunch`
run unchanged.

### Campaign catalog (`rui-win-*`)

`fixture_c_real_ui_windows_campaigns.dart` — the desktop `sweep_*` catalog
grouped into launch-sized bundles: nine HEADLESS-SAFE bundles (honest with or
without the flag) and two REAL-OS-INPUT bundles (`rui-win-os-input` =
group_mention + p1_chat + p2_verify; `rui-win-relaunch` = p1_relaunch +
p2_keys) that need the flag + console session. `--list-real-ui-campaigns`
prints them; `--plan-json --real-ui-platform=windows` plans them.

### Runbook (from the Linux VM, via `ssh mac2` → `ssh win11_ltsc`)

The VM (`win11_ltsc`, ARM64 Win11, Flutter x64 3.41.9 at `C:\dev\flutter`,
VS 2022 BuildTools 14.44, vcpkg x64-windows + arm64-windows, Git for Windows,
Strawberry cmake/ninja) sees the Mac working tree as `\\Mac\bin.gao\chat-uikit\toxee`
(`Y:` in the console session only). Build from a share-shim, run in the
console session:

```powershell
# 1. shim (sources symlinked to the share; build/, .dart_tool/, every
#    <platform>\flutter\ephemeral local) — tool\vmtest\make_shim.ps1
# 2. vcvarsall arm64_amd64 + CC=cl CXX=cl, TIM2TOX_NATIVE_BUILD_ROOT under
#    build\ (NOT the share), VCPKG_ROOT=C:\vcpkg, TOXEE_PAIR_TCP_ONLY=1
# 3. one campaign inside session 1 (real OS input):
powershell -File tool\vmtest\win_run_interactive.ps1 -WorkingDirectory C:\vmtest\toxee-win `
  -EnvFile <env.ps1 with the above + TOXEE_WIN_OS_INPUT=1> -LogPath C:\vmtest\logs\x.log `
  -Command "dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-platform=windows --real-ui-campaign=rui-win-account-settings"
```

`win_run_interactive.ps1` registers a one-shot INTERACTIVE scheduled task
(`schtasks /IT`) as the logged-in user — an OpenSSH session is session 0
(no desktop, no `Y:`, `AppActivate`/`SendKeys` dead), the console session has
all of it — waits on a done marker and streams the log. The user must be
logged in at the VM console (locked = keys don't land).

### Traps found bringing the VM up (all fixed at the source)

- **Share dotfiles are HIDDEN** — `Copy-Item` kept the attribute and the
  flutter tool cannot rewrite a hidden `.flutter-plugins-dependencies`
  ("cannot access the file") → `make_shim.ps1` normalizes copied files.
- **Every platform dir needs a local `flutter\ephemeral`** — `flutter pub get`
  writes `.plugin_symlinks` for `linux\` too, and a symlink cannot be created
  inside a share-backed dir (ERROR_INVALID_FUNCTION) → both shims treat all
  six platform dirs as real dirs.
- **Runtime root was on the share** — `tool\mcp_test\.windows_runtime` under a
  `tool\` symlink wrote every instance's profiles/logs INTO the Mac tree →
  default is now `build\windows_runtime` (runner + launcher + stop script).
- **Strawberry g++ won the CMake compiler search** (GCC 13 fails on
  `std::thread::id`) and a stale non-MSVC CMake cache then pinned it → run
  under vcvars with `CC=cl CXX=cl` and drop `build\tim2tox-native` when its
  cache names another compiler.
- **`opus.dll` was never bundled** — the ToxAV build links it dynamically;
  without it `tim2tox_ffi.dll` fails LoadLibrary (126) and registration never
  reaches sessionReady → `windows/CMakeLists.txt` installs it (product fix)
  and the launcher copies it (harness fix).
- **3389 is the RDP listener on Windows** → A's relay could not bind, tox_new
  failed → Windows launcher default relay port 33390; the driver now adds the
  desktop relay EXPLICITLY (`_pairTcpRelayFallbackPort`) instead of relying on
  toxcore's default-port probing.
- **`pid` inside an extension is `dart:io`'s** — `AppActivate(<driver pid>)`;
  the macOS `tell process` had the same latent bug → `this.pid`.
- **`powershell -Command <text>` re-parses the text and strips embedded double
  quotes** (`Write-Output ("x=" + $y)` becomes `Write-Output (x= + $y)` and a
  silent non-zero exit) → the driver passes every step as `-EncodedCommand`,
  the probe writes a temp `.ps1` and runs `-File`.
- A PowerShell pipeline that captures the launcher's output blocks until the
  launched `toxee.exe` children exit (inherited console handles); the runner
  is fine (`Process.start(inheritStdio)` + exitCode), scripts must redirect
  through `cmd /c … > file` instead of `| Tee-Object`.
- `V2TIM_LOG` `{}` placeholders are printed literally in `flutter_client.log`
  (e.g. `Failed to create Tox instance, error: {} ({})`) — the native error
  code never reaches the log. Pre-existing, cross-platform, NOT fixed here.

## Full five-surface matrix — macOS / iPhone / iPad / Android (2026-08-22/23)

First run of EVERY registered real-UI sweep on all four device surfaces
(Windows/Linux are headless and were not part of this pass), driven from a
Linux VM over `ssh mac2`, one platform at a time (the macOS phase types real OS
keystrokes into the frontmost window and the iOS phase needs
`TOXEE_IOS_KEEP_SIMULATOR_FRONT=1` — they cannot share the display). Campaign
logs: `~/rui_logs/<platform>__<campaign>.log` on the Mac; orchestration scripts
next to them (`run_macos*.sh` must run inside Terminal.app via `osascript … do
script`; `run_mobile.sh ios,ipad,android` boots two headless AVDs itself).

**Re-derive, do not trust these tallies** — they are one night's run. Per sweep
(PASS/FAIL/SKIP, first attempt unless noted):

| sweep | macOS | iPhone | iPad | Android |
| --- | --- | --- | --- | --- |
| login / ios_settings_main | 9/0/0 | 9/0/0 · 6/0 | 9/0/0 · 6/0 | 9/0/0 |
| settings2 / profile | 12/0 · 8/0 | 13/0 · 7/0/1 | 13/0 · 7/0/1 (profile retry) | 13/0 · 7/0/1 |
| keyed_gaps / keyed_gaps4_login | 8/0 · 1/0 | 8/0 · 1/0 | 8/0 · 1/0 | 8/0 · 1/0 |
| keyed_gaps3 / keyed_gaps4 | 8/0/2 · 4/0/6 | 8/0/2 · 9/0/1 | 7/0/3 · 7/0/3 | 8/0/2 · 9/0/1 |
| contacts | 15/0/0 | 14/0/1 | 14/0/1 | 14/0/1 |
| conv | 9/0/1 | 9/0/1 | 9/0/1 (retry) | 9/0/1 |
| chat | 15/0/1 | 13/0/3 | 13/0/3 | 13/0/3 |
| msg_select | 4/0 | 4/0 | 4/0 | 4/0 |
| group2 | 14/0 | 1/13 → see below | 12/2 (clear-history / kick reach) | — |
| c2c_extra / c2c_deep_extra | 5/0 · 1/0 | 5/0 · 0/1 | 5/0 · 1/0 | — |
| group_conf_member_extra / group_conf_deep_extra | 5/0 · 2/0/1 | — · 2/0/1 | 5/0 · 2/0/1 | — |
| account_conf_extra / account_deep_extra | 6/0 · 1/0 | 4/2 · 0/1 | 6/0 · — | — |
| calls_misc | 10/0/0 | 3/5/2 (cascade, see below) | 7/0/3 | — |
| p1_chat / p1_single | 8/0 · 1/2 | — · 4/1 | 7/0/1 · 5/0 (retry) | — |
| p2_reply / p2_verify / p3_writable | 1/0 · 1/0 · 1/0 | 1/0 · — · 1/0 | — | — |
| p1_extra / app_entry_extra / native_boundary_guards | 2/0 · 8/0 · 5/0/1 | — · — · 3/2/1 | — | — |
| mobile_shell / tablet_layout | — | 5/0 | 1/0 | 5/0 |
| p1_relaunch / p2_keys / group_mention | 3/0/2 · 2/0/1 · 2/0 (flaky) | — | — | — |
| legacy scenario stacks (all-expanded + group-*) | 31 pass / 6 flaky | — | — | — |

### Product defects found and fixed (each with a regression test)

1. **Bootstrap node probe libelled an unresolvable host as a local UDP
   constraint** (macOS `settings_bootstrap_manual_add_node`, 2/2). `tox.example.org`
   fails every `tox_dht_send_nodes_request` with `BAD_IP`; the probe mapped
   `sendCount == 0` to `udpUnavailable` and Settings said "this device is
   running TCP-only" on a UDP-capable desktop. `tim2tox_ffi_dht_send_nodes_request`
   now returns the negated `Tox_Err_Dht_Send_Nodes_Request` (1 = accepted, 0 =
   FFI refused pre-toxcore), `DhtSendNodesRequestError` /
   `dhtSendNodesRequestChecked` decode it, and `BootstrapNodeProbe.verdictFor`
   holds descriptor-only refusals (`BAD_IP` / `BAD_PORT`) against the node.
   Tests: `test/util/bootstrap_node_probe_verdict_test.dart`, tim2tox
   `scenario_dht_nodes_response_api_test` "send refusal carries its reason".
2. **Conversation long-press / secondary-tap menu clobbered after a HomePage
   remount** (all three mobile pairs, `sweep_conv` first attempt 4/5; the
   screenshot shows UIKit's upstream Mark-as-Read/Hide/Delete sheet). HomePage
   reset the UIKit handlers unconditionally on dispose; mobile `forceHomeRoot`
   remounts through `pushAndRemoveUntil`, so the OLD dispose erased the NEW
   registration. `lib/ui/home/conversation_context_menu_handlers.dart` installs
   and identity-guards them. Test: `test/ui/home/conversation_context_menu_handlers_test.dart`.
   Verified first-attempt green on iPhone and Android.
3. **Compact-shell chat open never bound the active conversation** (iPhone:
   `c2c_global_search_contact_opens_chat`, `c2c_header_profile_send_back`,
   `friendprof_send_message_tile`, `message_burst_perf`, `call_record_bubble_renders`,
   `sweep_conv` end-state). Only the row tap called `setActivePeer` +
   `currentConversation`; `HomePage._openChat` (profile tile, notification tap,
   `l3_open_chat`, post-create) and global search pushed the message route
   unbound — unread kept counting, the open chat's notifications were not
   suppressed. `lib/navigation/active_conversation_binding.dart` is the BIND half
   (the route observer was already the unbind half). Test:
   `test/navigation/active_conversation_binding_test.dart`. Verified: c2c_extra
   5/5, contacts 14/0/1, p3_writable 1/0, conv 9/0/1 on iPhone.

### Harness defects found and fixed

- `reply_quote_real` compared `messageReply.messageSender` to B's pubkey; the
  fork (like upstream) writes `nickName ?? sender`, so the case failed whenever A
  already knew B's name (inside any bundle). Accepts the label now.
- AddGroupDialog on a phone: with the iOS keyboard up, the key-addressed submit
  tap dismissed the dialog without creating (live-proven; the same tap after
  `ui_hide_keyboard` creates). `_revealDialogKey`'s drag at y=400 starts on the
  modal barrier and dismisses it too. `_prepareDialogSubmit` (hide keyboard, no
  reveal) — iPhone `group_create` scenario and `account_conf_extra` creates now
  pass.
- `conference_search_result_opens` and `search_chat_history_window_open` drive
  the desktop search OVERLAY; they now declare SKIP on any compact shell from
  the live `homeShellShouldShowMasterDetail` (was Android-only / not at all).
- `_printGroupCreateDiag` (tap_diag part) prints shell + conversations +
  dialog state when a real-UI create never surfaces — the iPhone pair has no
  on-disk app log, so this is the only evidence a red run leaves.

### Second pass (2026-08-24): fixes driven by the open list

- **Conversation row ErrorWidget after a call (iPhone)** — B's render tree
  after `call_callee_hangup` held a `RenderErrorBox` under
  `TencentCloudChatConversationItemContent` (264×100000): toxee's call-record
  emitter omitted `call_end` for a 0-second call and the fork's
  `CallingMessage` hang-up branch called `getShowTime(null)`. Fixed on both
  sides (`lib/sdk_fake/fake_uikit_core.dart`, fork
  `tencent_cloud_chat_message_calling_message.dart`); regression
  `test/ui/conversation_row_call_record_test.dart`. This is what made the
  `calls_misc` chain cascade and every later "could not open chat via
  conversation-list" on the phone.
- **Compact-shell header stale after rename** — `ToxeeMessageHeaderInfo` now
  follows UIKit conversation-list events (and carries
  `chat_header_title_text`); `test/ui/home/toxee_message_header_info_live_name_test.dart`.
- **Desktop @-mention** — fork `_replaceAtTag` tolerates an invalid selection;
  `membersNeedToMention` consumed by identity; `test/ui/chat/desktop_mention_insert_test.dart`.
- **Notification tap seam** answers `no_listener` until HomePage subscribes
  (the broadcast used to drop the injected tap); the driver polls.
- **Harness reach on mobile** — profile scroll drags `group_profile_scroll_view`;
  iOS/Android kick goes through the `CupertinoActionSheet`
  (`group_member_action_kick_button`); Settings scrolls by touch drag on
  mobile shells and maps the switch/delete buttons to Account Management
  (iPhone `account_conf_extra` 5/0/1 declared); the AddGroupDialog submit
  hides the keyboard first and no longer drags the barrier; the two
  desktop-search-overlay cases declare SKIP on compact shells; attachment
  picks open the mobile "+" sheet before each tap.
- **macOS "silent exit" ROOT-CAUSED: flutter_skill screenshot leak.** lldb
  proved A stays alive (100% CPU, VM-service listener gone) until the runner's
  teardown SIGTERM; the RSS curve showed every bundle dying at ~770-790MB with
  the DART heap at only ~220MB — the bloat is native. The published
  `flutter_skill` 0.9.36 never `dispose()`s the `ui.Image`/`Picture` behind
  ANY of its screenshot paths, and `_captureFullScene` captures at PHYSICAL
  size (~16MB per shot on a 2x display); a bundle takes dozens of shots.
  Fixed by VENDORING the package (`third_party/flutter_skill`, MIT) with the
  dispose calls and routing it through `tool/bootstrap_deps.dart`'s generated
  overrides — drop the vendored copy when upstream fixes it. (The
  `FfiChatService.dispose()` poll-teardown hardening found on the way is real
  and kept.) Debug/test builds only — production has no flutter_skill.

  RESIDUAL: with the leak fixed the bundle got further (58 cases vs ~48) but
  the debug VM still dies at ~770MB dirty — `vmmap` shows the remainder is the
  debug JIT + Dart heap (`VM_ALLOCATE` 253MB and climbing; MALLOC only
  ~150MB): the single-launch mega-bundle simply exceeds what a debug VM
  survives on macOS. Every member sweep passes in its own launch, so treat
  `rui-single-app-optimized` / `rui-optimized-current` as a smoke-density
  trade-off with a known ceiling, not as the correctness gate. `Inst.shot`
  now caps captures at 1000px wide to lower the transient peak.

### Status after the second pass (2026-08-24)

Everything "open" after the first pass is now either FIXED (verified
in-sweep), root-caused and documented, or a known flaky class:

- **FIXED & verified**: iOS/iPad `conference_rename_leave` header staleness
  (live conversation-name subscription in `ToxeeMessageHeaderInfo`); macOS
  `conference_rename_leave` in-sweep ("edit-name dialog did not open" was a
  stale text-selection handle overlay swallowing the coordinate tap —
  `_dismissStaleSelectionOverlay`; `sweep_p1_single` 5/0 in-sweep); iPhone
  `group_kick_member_ui` / iPad `group_profile_clear_history` (mobile-sheet
  kick + live-height profile scroll; scenario run 14/0); iPhone settings
  cancel cases (Account Management mapping + touch-drag scrolling); iPhone
  `notification_tap_routes_to_c2c` (listener-aware inject seam + baseline
  poll) and `attachment_entry_buttons_render` (mobile "+" sheet reveal
  before each tap); the conversation-row call-record crash (`call_end` now
  written by `fake_uikit_core` for ended calls; the fork tolerates records
  without it) — which also explains the iPhone `calls_misc` cascade.
- **FIXED & verified in-bundle (friendship-r7 sweep_group_mention 2/0;
  iOS calls-misc-r4 5/0)**: macOS
  `group_at_member_send` inside the friendship bundle — final root cause
  (superseding the interim SelectionHandleOverlay theory): group2's kick
  case ends on the full-screen GroupMemberList route, the mention flow's
  open-chat seam short-circuits on the already-current conversation, and
  every POINTER tap then lands on the leftover page while KEYBOARD events
  still reach the composer beneath. Proof: byte-identical failure shots
  across r4/r6 showing that page; dumps with the mention panel open UNDER
  it; and `group_at_all_send` "passing" only because its bare contains('@')
  matched the typed '@' itself (assertion now requires `@\S`). The mention
  flow now resets to home root + clears the active conversation before a
  real re-open, taps only a STABLE row center, and verifies the composer
  holds "@<label>" before sending (fork-side `_replaceAtTag` hardening +
  `identical` consumption stay in as real fixes for the -1-selection
  RangeError); and iPhone `call_missed_record_row` in-sweep (an
  earlier case can leave the call overlay minimized to the PiP
  `floating-call-card` — `_restoreCallOverlayIfMinimized` before hangup;
  verified `endedA=true endedB=true rowRendered=true`, first attempt).
- **Root-caused, documented constraint (not an open bug)**: the macOS
  `rui-single-app-optimized` A-exit — flutter_skill screenshot leak (fixed
  by the vendored dispose) plus debug-VM JIT/heap growth past ~770MB; see
  the leak section above. The member sweeps are the correctness gate.
- **Known flaky classes (retry-covered)**: mobile first-attempt
  message-delivery timing (`msgmenu_read_receipt_group_gating`,
  `msg_select_clear_button_resets_count`); same-host NGC/DHT handshake after
  `reset_friendship` on a long-lived pair (`handshake*`,
  `conference_message`); macOS keystroke focus (`group_search`); one-off
  VM-service screenshot stalls under long-bundle load (r7 retry:
  `c2c_conv_delete_cancel` died on a 45s `flutter_skill.screenshot` timeout
  and the very next call recovered — `Inst.shot` is now NON-FATAL so a
  diagnostics capture can never fail a case again).
- **Pre-existing, unrelated**: tim2tox `scenario_dht_nodes_response_api_test`
  "DHT nodes crawling" fails on the untouched baseline too (phase 11, not
  in CI).

### Mobile coverage batch (2026-08-26)

Two new MOBILE real-UI cases in `sweep_keyed_gaps4` (batch 2, part file
`drive_real_ui_pair_keyed_gaps4_mention2.dart`), both verified PASS on an
iPhone pair (`kg4-newcases-3`, 11/0 with all siblings green):

- `mobile_mention_at_all_inserts` — pins TWO fork parity bugs the coverage
  inventory exposed: `TencentCloudChatAtGroupMemberList.defaultBuilder`
  dropped the container's `isGroupAdmin` verdict, and the @All row was gated
  on `groupType ∈ {Work, Public, Meeting}` — Tencent taxonomy toxee's
  lowercase types never satisfy, so **@All was unreachable on mobile for
  every toxee group** while desktop offered it. Note the picker's @All row
  AUTO-SUBMITS on tap (sentinel branch in `_onSelectGroupMember`) — it can
  never be combined with member rows, which is why this is not a
  multi-select case.
- `mobile_search_contact_back_unbinds` — drives the one bind entry point no
  case covered (global-search CONTACT row → `pushCompactChatRoute`) plus the
  pop-unbind observer leg and the unread-counts-again consequence. Its FIRST
  run caught a REAL cross-platform product bug: `DartSearchFriends` in the
  tim2tox FFI bridge mismatched the vendored SDK's JSON contract in BOTH
  directions (request: expected `friend_search_param_*` keys the SDK never
  sends, so the keyword list always parsed empty; response:
  `FriendInfoResultVectorToJson` emitted a shape `V2TimFriendInfoResult
  .fromJson` reads none of, so `friendInfo` was always null) — contact
  search silently returned nothing on the binary path on ALL platforms, and
  `DartGetFriendsInfo` shared the broken serializer. Both directions fixed
  in `dart_compat_friendship.cpp` / `dart_compat_callbacks.cpp`.
  Known first-attempt timing: one run showed `popped=true unbound=false`
  (unbind not observed within 15s) and passed on retry — same
  mobile first-attempt class as its sibling nav case; watch item.

The batch surfaced a THIRD product bug, iPad-only in practice:
`removeGroupMemberList` (chat-uikit-flutter group_profile_data) trimmed the
member cache with `getRange(0, min(length - 1, 20))` — an off-by-one that
silently drops the LAST member on every `_cleanGroupData` (chat
close/switch). On a master-detail shell the pane rebinds fire that
constantly, and `loadGroupMemberList`'s debounce then serves the truncated
cache: in a 2-member group SELF can be the dropped row, so
`_resolveIsGroupAdmin` finds no self and the @All entry vanishes — which is
exactly why `mobile_mention_at_all_inserts` failed ONLY on iPad and ONLY
in-sweep (fresh standalone runs always passed). Fixed to `min(length, 20)`
(cap without dropping). Verification matrix for the batch: iPhone 11/0,
Android 11/0 (first Android kg4 run ever recorded green), iPad 8/0/4
(designed skips), each with zero first-attempt failures on the final run.
