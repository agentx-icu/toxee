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
  scenarios. The current discoverable catalog has 88 built-in campaigns. Treat
  `--list-real-ui-campaigns` as the exact source of truth for names and counts.
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
discoverable scheduler catalog. It does **not** mean all 42 campaign branches
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
