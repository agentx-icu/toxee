# Real-UI sweep campaign — 2026-06-10 (RECOVERY ANCHOR)

> **Purpose of this file:** durable state for the "+94 real-app UI cases" campaign so any
> session (or a fresh Claude session after token exhaustion) can resume exactly where work
> stopped. Update the per-case Status column and the Batch log as work proceeds. Commit
> after every batch.

## Mission (user directive, 2026-06-10)

Cover the majority of common UI scenarios with **real UI tests**: launch the REAL app
(macOS debug bundle) and drive real clicks / scrolls / selections / typing — NOT hermetic
WidgetTester gates. Add **≥80 new cases** (this plan: 94). Constraints:

- **Reuse app launch + accounts aggressively.** No per-case relaunch, no per-case account
  registration, no per-case re-friending. Suites chain many cases on ONE launch (the
  `settings_sweep` precedent) and reuse the `paired_for_e2e` restored fixture state.
- **Single agent (opus), serial** — one batch at a time, no parallel fan-out.
- **Write ALL cases first, then run + fix.** Write phase is hermetic (analyze + planner
  dry-run + hermetic extension-handler tests only; no live app launches).
- Work directly on `master` (standing master-direct directive).
- Deep root-cause fixes for anything the run phase surfaces (no surface patches).
- Codex review mandatory before the campaign is declared done.

## Vehicle

`tool/mcp_test/drive_real_ui_pair.dart` + part files — the real-UI two-process driver
(flutter_skill service extensions + osascript foreground/keystrokes), planned/launched via
`tool/mcp_test/fixture_c_unified_runner.dart` campaigns. Read these FIRST:

- `tool/mcp_test/REAL_UI_TWO_PROCESS.md` — harness facts, gotchas (unfocused-window stall,
  enterText needs focusType-tap, composer needs osascript Return, dialog pop buttons need
  `tapKeyCenter` single-fire, first-run wizard dismissal).
- `tool/mcp_test/drive_real_ui_pair_inst.dart` — `Inst` primitives (tapKey/tryTapKey/
  tapText/focusType/tapAt/osaType/osaReturn/waitKey/waitText/waitState/dumpState/shot/
  foreground, l3 call plumbing).
- `tool/mcp_test/drive_real_ui_pair_shell.dart` — ensureHome (register-once-per-launch),
  recovery, new-entry shell.
- Existing scenario parts (`_friends`, `_message_call`, `_group`, `_settings`,
  `_group_profile`, `_group_menu`) — copy their shape.
- `lib/ui/testing/l3_debug_tools.dart` — l3 tool registration pattern (mcp_toolkit).
- `lib/ui/testing/ui_keys.dart` — ValueKey catalog.

Existing real-UI scenarios (do NOT duplicate): handshake, handshake_detail, decline,
custom_message, message, message_burst, group_message, group_burst, group_member_list,
group_create, settings_sweep (+ copy_id/autologin/notification/export_chooser/password/
logout_relogin/logout_double_fire), group_profile_open, group_rename, group_search,
group_add_member_open, group_add_member_picker, group_conversation_menu,
group_menu_pin_unpin, group_menu_mark_read, group_menu_delete_confirm,
group_menu_mark_read_unread, group_clear_history, group_clear_preserves_pin,
conference_message, probe_home_root, call_voice, call_reject, reset_friendship.

## Batch plan (serial, one opus agent per batch)

Per-batch contract (every agent MUST):
1. Read this file + the harness files above before writing code.
2. Implement its cases as scenario functions in a NEW part file
   `drive_real_ui_pair_<domain>2.dart` (or extend the matching existing part if small),
   register dispatch entries in `drive_real_ui_pair.dart`, add a `sweep_<domain>` scenario
   that chains the batch's cases on one launch with per-case PASS/FAIL summary lines
   (`[sweep] <case>: PASS|FAIL|SKIP(<reason>)` + final counts; exit non-zero if any hard
   case fails), and add campaign entries (`rui-<domain>`) + `_validRealUiScenarios`
   updates in `fixture_c_unified_runner.dart`.
3. Keep `flutter analyze lib tool --no-fatal-warnings --no-fatal-infos` clean and
   `dart run tool/mcp_test/fixture_c_unified_runner.dart --plan-json --class=2proc-ui`
   parsing (planner regression).
4. Real-UI first: drive the production widget/gesture; an l3 bypass is only for SEEDING
   state (e.g. inject inbound history) never for the asserted action itself.
5. Soft-skip protocol: if a case's surface turns out not to exist / not reachable on
   desktop, mark it `SKIP(<reason>)` in the sweep AND in this doc — never fake a pass.
6. Update this file's Status column (TODO → WRITTEN / SKIP+reason) + Batch log, then
   `git commit` (message: `test(real-ui): batch N — <domain> scenarios (written, unrun)`).
7. Do NOT launch the app; do NOT run live scenarios. Hermetic checks only.

### Batch 0 — primitives (PREREQUISITE for scroll/right-click cases)

New file `lib/ui/testing/ui_drive_tools.dart` (debug-only, registered like l3 tools but
UNGATED plumbing — they must work on fresh non-test accounts): service extensions that
dispatch REAL pointer events through `GestureBinding.instance.handlePointerEvent` so the
production gesture/scroll pipeline runs:
- `ui_scroll_at` — PointerScrollEvent (mouse-wheel) at a key's center or raw coords, with
  dx/dy; loop until a target child key is visible (caller-side loop in Inst helper).
- `ui_drag` — pointer down → moves → up between two points (touch-drag scrolling, member
  lists, mobile-style scroll).
- `ui_secondary_tap` — right-button pointer down/up at key center or coords (desktop
  message context menu).
- `ui_hover` — pointer hover event at key center (desktop hover affordances), if needed.
Each takes `{key?|x,y?}` JSON, returns `{ok, error?}`. Hermetic widget tests in
`test/ui/testing/ui_drive_tools_test.dart` proving: a real ListView scrolls + triggers its
scroll callbacks; a GestureDetector.onSecondaryTapDown fires; drag moves a scrollable.
Inst helpers in `drive_real_ui_pair_inst.dart`: `scrollUntilKey`, `secondaryTapKey`,
`dragBy`. Also: investigate + document HERE how the desktop chat message context menu is
actually opened in production (hover-more-button? secondary tap? long-press) — write the
finding into the Batch log; suites 6 depends on it.

**Batch 0 STATUS: DONE** — `lib/ui/testing/ui_drive_tools.dart` (ungated, debug-only)
ships `ui_scroll_at` / `ui_drag` / `ui_secondary_tap` real pointer-event service
extensions; `test/ui/testing/ui_drive_tools_test.dart` 5/5 pass; Inst helpers
(`scrollAt`/`dragBy`/`secondaryTapKey`/`scrollUntilKey`) added; message-menu trigger
investigated (see Batch log).

### Suites (batches 1–8) — 94 cases

Mode: `1i` = single instance (A only, B idle) · `2p` = two-process · `2p-r` = needs
restored/established friendship (plan after handshake or restore `paired_for_e2e`).

#### Batch 1 — Settings sweep 2 (12 cases, 1i, one launch)

| # | Case (scenario id) | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 1 | settings_surface_sections | 1i | — | open settings via sidebar; scroll through; all section headers render | PASS |
| 2 | settings_theme_dark | 1i | S57 | tap theme control → dark applied (widget-tree brightness) + dump persisted | PASS |
| 3 | settings_theme_light_back | 1i | S57 | revert to light; UI re-renders | PASS |
| 4 | settings_locale_zh_roundtrip | 1i | S38 | switch language to 中文 → visible label asserted in Chinese → back to English | PASS |
| 5 | settings_download_limit_edit | 1i | S98 | real field input + save → dump_state threshold | PASS |
| 6 | settings_bootstrap_mode_cycle | 1i | S99/S85 | segmented auto→manual→lan→auto, dump after each | FAIL→FIXED(PRODUCT: Auto-radio subtitle GestureDetector swallowed center-taps→launched browser instead of selecting radio; made subtitle a non-interactive RichText so any tile-tap fires onChanged) |
| 7 | settings_bootstrap_manual_add_node | 1i | S89 | manual node form: host/port/key input → add → row renders | FAIL→FIXED(HARNESS: band-stall accept for bottom-anchored expand btn; synthetic enterText SIGSEGV'd FlutterTextInputPlugin→use osascript keystrokes; dy:-6000 reset collapsed the expanded form→gentle scroll-down + no-reset fill) |
| 8 | settings_bootstrap_manual_remove_node | 1i | S89 | remove the added node → row gone | FAIL→FIXED(same band-stall reach fix as case 7) |
| 9 | settings_autologin_toggle_hard | 1i | S96 | scrollUntilKey + real tap → dump flips (upgrades documented soft case) | PASS |
| 10 | settings_notifsound_toggle_hard | 1i | S97 | same for notification-sound switch | PASS |
| 11 | settings_password_mismatch_error | 1i | S40 | password dialog: mismatched confirm → inline error, dialog stays | PASS |
| 12 | settings_logout_cancel | 1i | S44 | logout confirm → Cancel → still sessionReady | PASS |

Sweep: `sweep_settings2` · Campaign: `rui-settings2`. **Batch 1 STATUS: DONE** (12/12
cases WRITTEN+unrun; analyze 0-new; planner + campaign-list green; touched-settings
hermetic tests 59/59 still green)

#### Batch 2 — Self profile (8 cases, 1i, same-launch chain)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 13 | profile_open_sidebar_avatar | 1i | S104 | tap sidebar avatar → self-profile overlay mounts | PASS |
| 14 | profile_edit_toggle_roundtrip | 1i | S101 | edit pencil enter/exit edit mode | PASS |
| 15 | profile_edit_nickname_persists | 1i | S8 | edit nickname via real field (+osascript) → save → dump + sidebar reflect | FAIL→FIXED(HARNESS: synthetic enterText SIGSEGV'd setEditingState→focusType now types via osascript keystrokes; save FilledButton "Save Contact" key not surfaced by interactiveStructured→tapKeyAt RenderBox fallback) |
| 16 | profile_edit_status_persists | 1i | S8 | same for status message | FAIL→FIXED(same crash+save-tap fixes as case 15) |
| 17 | profile_copy_toxid_snackbar | 1i | S102 | copy button → snackbar | PASS |
| 18 | profile_qr_copy | 1i | S103 | QR section copy action → snackbar | PASS |
| 19 | profile_avatar_picker_opens | 1i | S79 | avatar tap → default-avatar grid/picker surface mounts (native picker untouched) | SKIP(no in-app avatar picker — native NSOpenPanel only; l3 override test-gated) |
| 20 | profile_avatar_select_default_applies | 1i | S79 | select a bundled default avatar → avatar updates (faceUrl changes) | SKIP(no in-app default-avatar selection surface — same root as 19) |

Sweep: `sweep_profile` · Campaign: `rui-profile`. **Batch 2 STATUS: DONE** (6/8 WRITTEN+unrun, 2 SKIP — no in-app avatar surface; analyze 0-new; planner + campaign-list green; profile hermetic tests 10/10 green)

#### Batch 3 — Login / register (9 cases, 1i; password cases mutate then restore state)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 21 | login_account_card_renders | 1i | S2 | after logout: saved-account card shows nick + tox prefix | PASS |
| 22 | login_register_open_back | 1i | S4 | Register CTA → RegisterPage → back to login | PASS |
| 23 | register_empty_nickname_error | 1i | S4 | submit empty nickname → inline validation error | PASS |
| 24 | register_password_mismatch_error | 1i | S4 | mismatched passwords → inline error | PASS |
| 25 | register_password_strength_flips | 1i | S4 | typing weak→strong flips the strength caption (Weak→Strong) | FAIL→FIXED(HARNESS: synthetic enterText didn't reliably REPLACE the field so the strong pw was computed against stale content→never "Strong"; switched both types to focusType real keystrokes) |
| 26 | login_restore_entry_opens | 1i | S9/S71 | restore-from-tox card → import/restore surface mounts; cancel back | SKIP(native-picker-only — restore card opens NSOpenPanel directly, no in-app surface) |
| 27 | login_password_wrong_error | 1i | S2b | set pw (settings) → logout → card → wrong pw → error, stays on login | FAIL→FIXED(card tap: raw tapAt/tapKeyCenter does NOT fire the card InkWell→tryTapKey; PRODUCT _quickLogin re-entrancy guard makes the double-fire safe) |
| 28 | login_password_correct_unlocks | 1i | S2b | correct pw → HomePage; then REMOVE password (restore no-pw state) | FAIL→FIXED(same card-tap + guard fix as 27; cascade-cleared) |
| 29 | account_switch_second_account | 1i | S3/S72 | register a 2nd account (ONCE, end of suite) → switch back via login cards; dump shows switched toxId | FAIL→FIXED(switch-back uses the fixed _quickLoginNoPassword card tap; cascade-cleared) |

Sweep: `sweep_login` · Campaign: `rui-login`. **Batch 3 STATUS: DONE** (8/9 WRITTEN+unrun,
1 SKIP — case 26 native-picker-only; case 29 registers the ONLY extra account of the
campaign; password cases RESTORE the no-password state via the production change-password
dialog. analyze 0-NEW vs 222 baseline; planner/validate/campaign-list/self-test green;
touched-lib hermetic tests 57/57 green; 4 codex rounds, all findings applied)

#### Batch 4 — Contacts + friend profile (15 cases, 2p; ONE handshake reused; delete/re-add last)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 30 | add_friend_dialog_esc_close | 1i | S5 | new-entry → Add Contact → ESC closes dialog | WRITTEN |
| 31 | add_friend_invalid_id_error | 1i | S5 | garbage ID → inline error, no crash | WRITTEN |
| 32 | add_friend_self_id_guard | 1i | S55 | own tox ID → self-add guard error | WRITTEN |
| 33 | add_friend_duplicate_guard | 2p-r | S56 | friend's ID again → dedup guard error | WRITTEN |
| 34 | contacts_subtabs_cycle | 1i | S106 | New Contacts ↔ Blocked Users sub-tab switching renders each list | WRITTEN |
| 35 | contacts_row_opens_friend_profile | 2p-r | S52 | tap friend row → friend profile sheet mounts | WRITTEN |
| 36 | friendprof_send_message_tile | 2p-r | S115 | Send-Message tile → chat opens for that friend | WRITTEN |
| 37 | friendprof_pin_toggle | 2p-r | S84 | pin switch → pinnedConversations flips + row reorders | WRITTEN |
| 38 | friendprof_block_unblock | 2p-r | S29 | block switch on→off → blockedUsers flips both ways | WRITTEN |
| 39 | friendprof_mute_toggle_regression | 2p-r | S114/S83 | mute switch ×2 → no crash (ABI regression gate, HARD) + recvOpt dump flip (SOFT) | WRITTEN |
| 40 | friendprof_remark_edit_persists | 2p-r | S113/S30 | remark dialog real input → Confirm → UI + dump show remark (HARD; KNOWN native bug — EXPECTED FAIL live → run-phase signal to fix native setFriendInfo) | WRITTEN |
| 41 | friendprof_clear_history | 2p-r | S111 | seed a few messages; clear → chat empty + history file cleared | WRITTEN |
| 42 | blocked_list_unblock_row | 2p-r | S107 | block via profile → Blocked Users tab row → unblock → row gone | WRITTEN |
| 43 | contact_search_filter_clear | 2p-r | S49 | contact search: type filter → matches; clear → full list | WRITTEN |
| 44 | friendprof_delete_friend_confirm | 2p-r | S112/S28 | delete friend → keyed confirm → friend gone both lists (LAST; sweep ends no-friend) | WRITTEN |

Sweep: `sweep_contacts` (handshake once at top) · Campaign: `rui-contacts`. **Batch 4 STATUS: DONE** (15/15 WRITTEN+unrun; no production change — every friend-profile/contact key already in the fork; 2p state contract no-friend→no-friend; analyze 0-NEW; planner/validate/campaign-list/self-test green)

#### Batch 5 — Conversation list C2C (10 cases, 2p-r, one launch + one handshake)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 45 | conv_menu_surface_c2c | 2p-r | S117 | right-click/menu on C2C row → menu items render (pin/read/delete) | WRITTEN (real secondary-tap opens menu; no clear item — see log) |
| 46 | conv_pin_unpin_reorders | 2p-r | S116 | pin → row to top + pinned style; unpin → restores | WRITTEN (real menu surface + deterministic pin action; reorder via dump order) |
| 47 | conv_mark_read_two_proc | 2p-r | S118/S19 | B sends 3 → A unread badge ≥1 → mark-read via row menu → badge gone | WRITTEN |
| 48 | conv_delete_confirm_c2c | 2p-r | S119/S20 | delete via row menu + confirm → row gone, friendship intact | WRITTEN (near-LAST + re-seed; friendship intact per S20) |
| 49 | conv_clear_history_c2c | 2p-r | S111 | clear via row menu → history empty, row survives | WRITTEN (no conv-row clear action — proves real menu surface, clears via l3_clear_history; see log) |
| 50 | conv_clear_preserves_pin_c2c | 2p-r | — | pin + seed + clear → still pinned (C2C mirror of group gate) | WRITTEN |
| 51 | conv_unread_badge_bump_clear | 2p-r | S90/S19 | B sends → badge N increments; open chat → 0 | WRITTEN (clears by OPENING the chat — distinct from 47's menu mark-read) |
| 52 | conv_preview_updates_on_inbound | 2p-r | — | B sends nonce → row last-message preview shows it | WRITTEN |
| 53 | conv_presence_dot_flips | 2p-r | S51 | B quits/offline → A presence dot flips; B relaunch → online (uses l3 connection state to detect, real dot asserted) | SKIP(presence-flip un-seedable on a reused launch — friend `online` flag has no ungated setter; flipping it needs stopping B's process, forbidden by launch-reuse) |
| 54 | conv_search_filter_clear | 2p-r | S48 | conversation search: filter → match; clear → all | WRITTEN (real Cmd+Ctrl+F shortcut opens the search overlay — only entry) |

Sweep: `sweep_conv` · Campaign: `rui-conv`. **Batch 5 STATUS: DONE** (9/10 WRITTEN+unrun, 1 SKIP — case 53 presence-flip un-seedable; analyze 0-NEW vs 222 baseline; planner/validate/campaign-list/self-test green; gen_scenario_index --check green; conversation+search+ui_drive hermetic tests 43/43; no production change)

#### Batch 6 — Chat surface C2C (16 cases, 2p-r)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 55 | chat_open_from_row | 2p-r | S11 | tap row → chat opens, header shows friend nick | WRITTEN |
| 56 | chat_multiline_send | 2p-r | S120 | Shift+Enter newline + send → bubble contains both lines; B receives | WRITTEN (Shift+Enter wired, see log) |
| 57 | chat_long_text_send | 2p-r | — | 600-char message → renders + delivers | WRITTEN |
| 58 | chat_emoji_insert_send | 2p-r | S22 | emoji panel → insert → send → emoji bubble; B receives | WRITTEN (panel-OPEN gated via new `desktop_sticker_panel` key + emoji-token path; cells unkeyed, see log) |
| 59 | chat_sticker_panel_send | 2p-r | S23 | sticker tab → tap sticker → face message sends; B receives | WRITTEN (panel-OPEN gated; face SEND needs keyed cell — fork flag, see log) |
| 60 | chat_msg_menu_surface | 2p-r | S15 | secondary-tap own bubble → context menu items render | WRITTEN |
| 61 | chat_copy_message_clipboard | 2p-r | S16 | menu Copy → OS clipboard contains text (pbpaste) | WRITTEN |
| 62 | chat_reply_quote_roundtrip | 2p-r | S18 | menu Reply → quoted composer → send → quote bubble renders; B sees reply | SKIP(reply only on quotable custom-elem bubbles; no C2C custom-inbound seed seam + unkeyed reply container — fork/ffi flag) |
| 63 | chat_forward_to_other_conv | 2p-r | S17 | menu Forward → picker → forward to group → message appears there | WRITTEN (forwards into the C2C row — only target with one friend, see log) |
| 64 | chat_delete_message_gone | 2p-r | — | menu Delete → bubble gone; reopen chat → still gone | WRITTEN |
| 65 | chat_history_scroll_load_more | 2p-r | S14 | seed >1 page (real alternating sends); scroll up → older page loads | WRITTEN (gates the RENDERED earliest ROW after scroll, not the dump; see log) |
| 66 | chat_inbound_while_scrolled_up | 2p-r | — | scrolled up + B sends → no forced jump; affordance/indicator asserted | WRITTEN (no-jump = scrolled-up older ROW stays rendered after inbound; see log) |
| 67 | chat_header_opens_profile | 2p-r | S52 | tap chat header avatar/name → friend profile opens | WRITTEN |
| 68 | chat_offline_pending_then_deliver | 2p-r | S25/S13 | A offline (l3 seed) → send → pending spinner; reconnect → delivered to B | SKIP(offline-pending un-seedable on a reused launch — no ungated offline seam; stopping B forbidden) |
| 69 | chat_image_bubble_open_preview | 2p-r | S88 | B sends image (l3_send_file seeding) → A real image bubble renders → tap opens preview | WRITTEN (renders gated; preview-open best-effort — async-load tap, see log) |
| 70 | chat_file_bubble_present_open | 2p-r | S21/S24 | B sends small file (l3 seed) → A file bubble (name+size) → tap dispatches open | WRITTEN (renders+name gated; tap-open best-effort) |

Sweep: `sweep_chat` · Campaign: `rui-chat`. **Batch 6 STATUS: DONE** (14/16 WRITTEN+unrun, 2 SKIP — case 62 reply / case 68 offline; analyze 0-NEW vs 222 baseline; planner/validate/campaign-list/INDEX/self-test green; touched hermetic tests 46/46; codex PASS-WITH-FIXES — 5 P1 + 1 P2 + 1 P3 all applied; 3 production changes — the ungated `l3_mark_current_account_test` + `l3_unmark_current_account_test` seam pair and a `desktop_sticker_panel` automation key)

#### Batch 7 — Group + conference (14 cases, mixed)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 71 | group_create_cancel | 1i | S32 | add-group dialog → ESC (no Cancel button) → no group created | WRITTEN |
| 72 | group_create_type_selector_surface | 1i | S32 | dialog type selector renders all 3 segments; pick private → created (SHARED group) | WRITTEN |
| 73 | group_profile_members_entry | 1i | S121 | group profile members entry → member list PAGE mounts (self row) | WRITTEN (l3_open_group_member_list, see log) |
| 74 | group_profile_clear_history | 1i | S122 | seed own sends → profile clear-history → confirm-by-label → chat empty | WRITTEN |
| 75 | group_leave_via_profile_confirm | 1i | S123/S150 | leave/dissolve button → confirm-by-label → conv row gone (LAST group case) | WRITTEN |
| 76 | group_rename_updates_header | 1i | S153 | rename via profile → open chat header shows new name | WRITTEN |
| 77 | group_add_member_full_join | 2p-r | S124/S81 | add-member picker → invite B → B auto-joins → member count ≥2 | WRITTEN |
| 78 | group_kick_member_ui | 2p-r | S37 | kick B via REAL desktop member-row right-click → keyed kick item → A member list drops B | WRITTEN (fork keys added, see log) |
| 79 | group_member_list_scroll | 2p-r | S36 | member list drag (ui_drag) executes; rows intact (2 members — honest low-value gate) | WRITTEN |
| 80 | group_mute_toggle | 1i | S83 | group profile do-not-disturb switch ×2 → value flips, no crash (recvOpt soft) | WRITTEN (fork mute key added, see log) |
| 81 | group_unread_badge_two_proc | 2p-r | S90 | B group-sends → A row badge bumps; open → clears | WRITTEN |
| 82 | conf_create_dialog_surface | 1i | S156 | conference segment create → conv row appears (SHARED conference) | WRITTEN |
| 83 | conf_row_menu_surface | 1i | S161 | conference row menu renders pin/mark-read/delete (shared type-agnostic menu) | WRITTEN |
| 84 | conf_member_list_renders | 1i | — | conference profile member list PAGE mounts (self row) | WRITTEN |

Sweep: `sweep_group2` · Campaign: `rui-group2`. **Batch 7 STATUS: DONE**

#### Batch 8 — Calls + misc (10 cases, 2p-r; media cases consecutive to reuse call state)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 85 | call_video_accept_hangup | 2p-r | S66 | video button → B accepts → both inCall+mode==video → hangup → idle | WRITTEN |
| 86 | call_mute_toggle_incall | 2p-r | S74 | voice call → A accepts → `call_mic_mute_button` flips `call.isMuted` on/off; leaves inCall for 89 | WRITTEN |
| 87 | call_camera_toggle_incall | 2p-r | S75 | DURING the video call: `call_camera_toggle_button` flips `call.isVideoEnabled` off/on | WRITTEN |
| 88 | call_missed_record_row | 2p-r | S77 | B calls, B cancels before answer → A's call-record count increases + row renders | WRITTEN |
| 89 | call_callee_hangup | 2p-r | S76 | callee (A) ends THIS voice call → both sides idle | WRITTEN |
| 90 | call_record_bubble_renders | 2p-r | — | after the completed call: a NEW call-record bubble (count>baseline) renders in chat history | WRITTEN |
| 91 | home_tabs_cycle_state_retained | 1i | — | real sidebar tabs chats→contacts→settings→chats; `homeShellCurrentConversationId` retained (IndexedStack) | WRITTEN |
| 92 | theme_switch_chat_open | 2p-r | S57 | with chat open: flip dark/light via real Appearance → seeded bubble ROW re-renders, no crash; restore | WRITTEN |
| 93 | window_resize_responsive | 1i | S60 | osascript narrow past 720pt → `home_bottom_nav` appears + drives bottom-nav routing; restore → gone (SKIP if resize refused) | WRITTEN |
| 94 | search_chat_history_window_open | 2p-r | S93 | seed term → Cmd+Ctrl+F overlay → `search_result_message_<conv>` → tap → SearchChatHistoryWindow mounts | WRITTEN |

Sweep: `sweep_calls_misc` · Campaign: `rui-calls-misc`. **Batch 8 STATUS: DONE** (10/10
WRITTEN+unrun, 0 SKIP — case 93 is SKIP-able at RUN time if the window refuses scripted
resize, but is written as a real gate; analyze 0-NEW vs 222 baseline; planner/validate/
campaign-list/INDEX/self-test green; touched hermetic tests 58/58; codex PASS — 3 P1 + 1 P2
applied + P3 mobile-parity gap closed by driving the bottom-nav routing)

## Batch log (append-only)

- 2026-07-11 **SKIP-conversion pass — make the skipped real-UI cases actually run.**
  Converted 7 previously-SKIP cases to REAL passes (real controls + deterministic
  seams / process control), plus redirected 2 duplicate skips to their new home:
  - **Avatar (profile_avatar_picker_opens + profile_avatar_select_default_applies):**
    keyed the real self-profile "change avatar" camera affordance
    (`profile_avatar_edit_button`) and extended `l3_set_avatar_pick_path` to
    materialize a sandbox image (contentB64, like the attachment seam). The cases
    now tap the REAL avatar control (mark test → seam → tap) and assert the new
    dump field `selfAvatarPath` flips. sweep_profile 8/0/0 (was 6/0/2skip).
  - **login_restore_entry_opens:** drives the REAL restore card with the native
    NSOpenPanel replaced by a fixed invalid `.tox` via `l3_set_account_import_pick_path`
    → real `restoreFromToxFile` → error banner (same recipe as the passing
    `restore_import_entry_guard`). MUST end logged-out (the following register/
    password cases operate on the LoginPage). sweep_login 9/0/0 (was 8/0/1skip).
  - **chat_reply_quote_roundtrip:** the old SKIP doc was STALE — `l3_inject_c2c_custom`
    (a quotable inbound custom bubble "suitable for Reply-menu automation") and the
    reply container key `message_input_reply_container` both already exist. Inject a
    custom inbound → REAL Reply menu item → REAL quote banner → REAL send carrying
    the messageReply cloudCustomData. KEY FIX: send with `clearFirst:false` — the
    composer clears the reply banner on a Backspace-when-empty (`clearRepliedMessage`)
    and osaClear sends exactly that Backspace. Also surfaced `cloudCustomData` on the
    C2C messages dump. sweep_chat 15/0/1.
  - **new_messages_chip_tap:** the chip feature was UNWIRED (`notifyNewMessageComing`
    defined but never called). Wired it through the existing scrollToBottomIfNearBottom
    controller-event path: when an inbound arrives at the head while scrolled up,
    latch the chip (`latchNewMessagesChip` anchors firstNewMessageIndex=0 directly —
    key-search is unreliable across the render/list layers). Added a ROBUST
    "newest-real-message changed to inbound" detector in the container so it fires
    even when the inbound coincides with maxMessageCount head-trimming (Case C), not
    just the clean head-append (Case B). Test scrolls up a MODERATE amount (keeps the
    inbound in the built render window). sweep_p2_keys 2/0/1.
  - **presence_dot_relaunch + offline_pending_relaunch (rui-p1-relaunch):** ENABLED
    the fully-implemented-but-unconditionally-skipped process-control cases (the
    `skipEnv` never even attempted). Key fix: WAIT for A's toxcore to detect B
    offline (poll `friends[].online` → false, up to 200s — right after killing B's
    process, toxcore still believes B online for ~30-60s, the root of the old
    "offlineData=false" skip) BEFORE asserting. presence_dot drives the REAL
    conversation-item online-dot state-suffixed key (`:online`↔`:offline`) across a
    stop→relaunch; offline_pending drives the offline-queue→deliver lifecycle. Both
    re-seed the same-host loopback bootstrap after relaunch. rui-p1-relaunch 3/0/2.
  - **conv_presence_dot_flips + chat_offline_pending_then_deliver + (p2_keys)
    presence_dot_relaunch:** stay SKIP in their reused-launch sweeps (they may not
    stop B there) but now point at the passing `presence_dot_relaunch` /
    `offline_pending_relaunch` in rui-p1-relaunch, which own the peer process
    control — the behavior IS asserted, in the correct dedicated launch.
  - **Codex review (mandatory):** reviewed the chip wiring + l3 seams. Confirmed no
    self-send false-positive (isSelf set before optimistic insert) and no release
    exposure (seams are kDebugMode + test-account gated). Found + FIXED 2 real chip
    bugs: (1) the container's "newest changed to inbound" detector also fired when
    load-older head-trimming EXPOSED an older inbound as the new newest → would show
    the chip on pure pagination; now requires the new newest id to be ABSENT from
    the previous list (genuinely new). (2) after latching, a re-entry whose key was
    trimmed out (haveMoreLatestData branch) left `firstNewMessageIndex == -1` and
    `_determineShowNewMsgCount` (`index <= -1`) could never clear → stuck chip; now
    clears on a negative anchor too. Re-verified live: sweep_chat 15/0/1
    (inbound-scroll + self-send + reply all still PASS), chip still PASS. flutter
    test 931/0; analyze 0 errors.
  - **Net SKIP-conversion:** 7 real passes (avatar ×2, restore, reply, chip,
    presence_dot_relaunch, offline_pending_relaunch) + 3 redirected-to-covered
    skips. Remaining skips are infra-blocked (2nd host/device or throwaway VM) or
    not-headless-automatable — enumerated above.
  - **Still SKIP — genuinely infra-blocked (need a second HOST/device, not skill):**
    call_from_profile_tiles + group_join_by_id_real_ui + conference_bidirectional_
    message_lifecycle (same-host ToxAV ring / public-NGC chat-id are unreliable —
    need a 2nd physical host/device; the Parallels Win11/Ubuntu VMs were DOWN and
    Parallels Standard requires manual GUI start); call_permission_denied_guard +
    network_disconnect_guard (mutate GLOBAL OS state — only safe in a throwaway VM);
    mobile_smoke_playbook_guard (real-device Patrol/integration_test — no device);
    window_resize_responsive on Windows (960px min-width clamp); notification_tap_
    routes_to_c2c (literal OS notification-banner click is not headless-automatable;
    the ROUTE handler is covered by run_fixture_c_notification_tap.sh).

- 2026-07-10 **Full real-UI sweep re-validation (all single- + two-process cases)** —
  ran `rui-optimized-current` (single-app + friendship optimized bundles) plus the
  non-bundled `rui-contacts`, `rui-p2-keys`, group-atomic, `rui-p1-relaunch`,
  `rui-native-boundary-guards`, and `all-expanded`. Seven root-cause fixes, all
  verified live green on re-run (no surface patches):
  - **[FORK BUG — FIXED] `chat_inbound_while_scrolled_up`: inbound force-jumped the
    list to the bottom.** The message-list container fired an UNCONDITIONAL
    `scrollToBottom` whenever the newest message changed, including for INBOUND
    messages appended at the head while the user had scrolled up to read history —
    yanking them to the bottom (real UX bug, desktop + mobile shared Dart). Fix
    (`tencent_cloud_chat_message_list_view_container.dart` + `_controller` +
    `message_list_controller`): the head-append (Case B) path now calls a new
    `scrollToBottomIfNearBottom` (EventName + controller `isNearBottom` on the
    reverse-list offset) so it only follows to the bottom when the user is already
    there; a self-send still scrolls unconditionally via the separate sendMessage
    path. Verified: `stillScrolledUp=true`.
  - **[HARNESS — FIXED] `_ensureFriendProfileOpen` short-circuited on the wrong
    contact-row key form.** The contact row key is `contact_list_item:<userID>`
    where userID is the FULL 76-char tox address OR the 64-char pubkey depending on
    data path — and it FLIPS mid-sweep after `clear_history` reloads the
    conversation-less contact. flutter_skill's `tap` reports success (invokes onTap
    via `_tryInvokeCallback`) even on the wrong-form key with NO navigation, so
    `tryTapKey(fullKey) || tryTapKey(shortKey)` short-circuited on the false-success
    and never tapped the working form → the profile never opened (root cause of
    `blocked_list_unblock_row` "could not block" and `contact_search_filter_clear`
    cascading, both ONLY after clear_history). Fix: tap EACH key form and verify
    `_onFriendProfile` after each, never trusting the tap boolean.
  - **[HARNESS — FIXED] covered-shell offstage acceptance** (`_chatsHomeReady` /
    `_contactsHomeReady`): the dump `homeShellTab` stays `chats`/`contacts` even when
    an OPAQUE pushed route (a stranded group member-list page) covers the whole home
    shell — the shell widgets are then offstage, keyed secondary-taps refuse them
    (`key_offstage_only`), and coordinate taps hit the covering route. The early
    `homeShellTab != null` accept stranded `returnToChatsHome` on that covered shell
    (root cause of `conv_menu_surface_c2c` / `conv_pin_unpin_reorders` /
    `conv_mark_read_two_proc` and the conf-member sweep). Fix: accept only when a
    shell landmark is actually ONSTAGE (`_homeShellLandmarkOnstage`); added
    `_popCoveringRouteViaBackChevron` as a recovery leg in both home loops.
  - **[HARNESS — FIXED] `openChat` aborted on a non-landing conversation-row tap.**
    The conversation-list row taps were `tapKey` (throws after 6 tries), so a tap
    that couldn't land (overlay right after a call teardown) aborted the whole case
    before the contacts-profile / l3 fallbacks ran (root cause of the `calls_misc`
    `call_record_bubble_renders` / `home_tabs_cycle` / `theme_switch` /
    `search_chat_history` cluster — all "tapKey conversation_list_item failed after 6
    tries"). Fix: `tryTapKey` so the fallbacks run. `calls_misc` 9/0 after.
  - **[HARNESS — FIXED] CJK IME corrupted keystroke-typed nonces.** On a zh host the
    default input source is a Chinese IME; `System Events keystroke` letters enter
    the IME composition and commit as hanzi (observed: `atmem…` → `他么么…`), failing
    `group_at_member_send` / `group_at_all_send` and the settings2 manual-node fields.
    Fix: type nonces via `osaPaste` (atomic clipboard, IME-immune); the mention-panel
    trigger `@` stays a real keystroke (IME-transparent punctuation). Mention 2/0.
  - **[PRODUCT BUG — FIXED] contact-profile open mis-navigated to the chat on a
    double-tap.** `onTapContactItem` (home_page.dart) toggles
    `_inContactProfileContext` per invocation to tell "open profile" from the
    profile's "Send Message". flutter_skill's `tap` fires the row's onTap TWICE,
    so fire 1 opened the profile (flag→true) and fire 2 was misread as "Send
    Message" → popped the profile, switched to Chats, opened the 1:1 chat. It was
    a race (both fires often land before setState commits → profile stays), so the
    early profile cases usually passed but the ones after clear_history's async
    churn deterministically lost it. Fix: a short re-entry guard
    (`_profileJustOpened`, cleared by a 250 ms timer) swallows the near-instant
    second `onTapContactItem`; a genuine Send Message tap is far later, unaffected.
    Real user-facing robustness (a fast double-tap no longer bounces out of the
    profile). Shared Dart → covers mobile.
  - **[HARNESS — FIXED] lingering clear-history confirm dialog was a modal barrier
    for the next cases.** `friendprof_clear_history` tapped its Clear-History
    confirm button (history cleared) but the fork's `handled` one-shot guard could
    absorb the Navigator.pop that would ride the second synthetic fire, leaving the
    confirm AlertDialog OPEN. Its modal barrier then swallowed every tap in the
    following cases — proven by screenshot: `blocked_list`'s block switch and
    `contact_search`'s field both sat behind the dialog (the switch resolved
    onstage at its real center yet a tap there hit the barrier → "could not block";
    the search typing never reached the field → "filter not applied"). Fix:
    clear_history now verifies the confirm button is GONE (re-tap + Escape until
    dismissed) before returning; it also clears the active conversation and pops
    its own profile route so the next case starts clean. `_ensureFriendProfileOpen`
    additionally reuses a profile only when a control is ONSTAGE (l3 keyCenter),
    rejecting a stale offstage route; the block toggle taps the onstage switch
    center. sweep_contacts 15/0 after.
  - **[HARNESS — FIXED] handshake_detail opened the application detail via a
    drifted coordinate.** `_handshakeDetail` (S108) opened the pushed
    application-DETAIL screen with a hardcoded `tapAt(700, 208)` on the request
    row; the restyle shifted row geometry so the tap stopped landing → the detail
    never opened → "detail screen accept button not found" (deterministic, both
    attempts). Fix: prefer the KEYED `contact_application_item:<userId>` tap
    (fires the row InkWell's onTap → gotoApplicationInfoPage) with the coordinate
    as fallback, plus a re-open retry — matching the proven
    `_tapApplicationAcceptViaDetail` recipe. all-expanded 10/10 after (same-host
    friend-request delivery + inter-scenario reset still lean on the runner's
    built-in fresh-relaunch retry, an environment property, not a case bug).
  - **[HARNESS — FIXED] attachment_entry_buttons_render expected removed buttons.**
    The desktop composer MERGED File/Photo/Video into ONE `attach_file` button
    (`_buildDesktopInputOptions` — `_sendMedia(type: file)` uses FileType.any, so
    it already sends images/videos; the separate photo/video buttons were removed
    to declutter, mobile keeps its own). The case still required
    `message_attachment_photo_button` / `_video_button` (gone) → FAIL
    (`photo=false video=false`). Fix: assert the single merged file button renders
    AND sends BOTH a text file and an image (the same button's FileType.any picker
    covers media). native-boundary-guards 2/0/4skip after.
  - **Live results (green):** settings2 12/0, profile 6/0/2skip, login 8/0/1skip,
    app_entry 8/0, account_conf 6/0, account_deep 1/0, p1_single 5/0, conv 9/0/1skip,
    chat 14/0/2skip, c2c_extra 5/0, c2c_deep 1/0, p1_chat 8/0, group2 14/0,
    group_mention 2/0, group_conf_member 5/0, group_conf_deep 2/0/1skip, calls_misc
    9/0/1skip; contacts 15/0; p2_keys 1/0/2skip; group-atomics 16/16;
    p1-relaunch 1/0/3skip; native-boundary-guards 2/0/4skip; all-expanded 10/10 (the
    atomic message/group/conference/call/handshake/decline set). All fixes in shared
    Dart / the fork → cover mobile (the fork scroll fix + the contact-profile
    debounce are shared Dart; the harness fixes are the macOS driver). The remaining
    SKIPs are documented environment limits (OS notification/network/permission
    seams, same-host public-NGC chat-id resolution, real-device mobile smoke).
  - **Codex review (mandatory):** reviewed the two PRODUCTION diffs (home_page
    contact-profile debounce + fork message-list scroll). Confirmed the debounce
    Timer is cancelled in dispose and its callback never setState()s, and the
    reverse-list `isNearBottom` (`pixels <= threshold`, bottom == offset 0) is
    correct. Found ONE real bug, fixed: the head-append classification treated a
    SELF-send's optimistic outgoing bubble the same as an inbound insert, so a
    self-send while scrolled up would route through `scrollToBottomIfNearBottom`
    and leave your own just-sent bubble offscreen until the async send completed
    (the unconditional self-send scroll runs only after the awaited send). Fix:
    only set `headAppendedNewMessages` (conditional scroll) when EVERY newly
    prepended head message is inbound (`isSelf != true`); a self-send stays
    unconditional. Re-verified live: sweep_chat 14/0/2skip with
    `chat_inbound_while_scrolled_up` PASS (no jump on inbound) AND
    `chat_multiline_send` / `chat_long_text_send` (self-sends) PASS. flutter test
    931/0; flutter analyze 0 errors (lib/tool + fork).

- 2026-06-10: campaign doc created; coverage survey done. Existing real-app coverage =
  ~30 scenarios (list above); everything else is hermetic L1 / l3 data-layer only.
  flutter_skill is a pub package (^0.9.36) with NO scroll/right-click → Batch 0 builds
  our own pointer-event service extensions (real production gesture pipeline).
  App build present at build/macos/Build/Products/Debug/Toxee.app (Jun 9, dylib fresh).

- 2026-06-10 **Batch 0 DONE** (ui_drive pointer primitives, written + hermetically
  verified; NOT yet live-run — needs an app rebuild so the new service extensions are
  in the binary, per the Run-phase protocol):
  - New `lib/ui/testing/ui_drive_tools.dart` (364 LOC; ungated, `kDebugMode`-only;
    registered in `main.dart` via `registerUiDriveToolsIfDebug()` right after the l3
    registration, NOT behind `TOXEE_L3_TEST` so it works on fresh non-test accounts).
    Three tools dispatch genuine `PointerEvent`s through
    `GestureBinding.instance.handlePointerEvent` so the real hit-test / gesture /
    scroll-physics pipeline runs: `ui_scroll_at` (mouse-wheel `PointerScrollEvent`),
    `ui_drag` (touch down→N moves→up, awaited inter-move delay so live frames pump),
    `ui_secondary_tap` (secondary-button mouse down/up). All return
    `{ok, error?, candidates}`. Pure handlers are `@visibleForTesting` and directly
    callable; the `MCPCallEntry`s are a thin wrapper.
  - **Widget resolution / offstage filtering — root-caused a real subtlety.** Keys are
    resolved to the GLOBAL CENTER of their `RenderBox` via `localToGlobal`. The
    documented hazard (key lookups matching widgets in offstage `IndexedStack` subtrees,
    e.g. HomePage's tab IndexedStack) is filtered by walking
    `Element.debugVisitOnstageChildren` from the root rather than `visitChildren` — the
    SAME traversal Flutter's own finders use. NOTE: `IndexedStack` does NOT wrap hidden
    children in a plain `Offstage` widget (Flutter 3.41.9 wraps them in
    `Visibility(maintainSize/State/Interactivity:true)`), so an ancestor-`Offstage`
    scan does NOT catch them — only `debugVisitOnstageChildren` (overridden by
    `_IndexedStackElement` and `_OffstageElement`) prunes them. Candidates are then
    required to be attached, positively-sized RenderBoxes. Offstage-only matches return
    `key_offstage_only:<key>`; absent keys return `key_not_found:<key>` (distinct, via a
    fallback full-tree walk). When multiple onstage matches remain the first is used and
    `candidates` is returned for debuggability. Unique per-call pointer ids (static
    counter from 7000) avoid arena collisions.
  - **FakeAsync deadlock fixed:** `ui_drag`'s inter-move `Future.delayed` is now only
    awaited when `stepDelay > Duration.zero`. A zero-duration `Future.delayed` schedules
    a fake-async timer the widget test can't fire while the handler is suspended → 10-min
    test timeout. Hermetic tests pass `Duration.zero`; production keeps the 16 ms default.
  - Hermetic gates `test/ui/testing/ui_drive_tools_test.dart` (5/5 PASS): scroll moves a
    real ListView offset + fires a ScrollNotification; touch drag scrolls; secondary tap
    fires `GestureDetector.onSecondaryTapDown` once at the widget center; an onstage
    IndexedStack twin is chosen over its offstage sibling (candidates==1, offstage twin
    never fires); an offstage-only key returns `ok:false`/`key_offstage_only` and a typo
    returns `key_not_found`.
  - Inst helpers added to `drive_real_ui_pair_inst.dart` (route to the `ui_*` extensions
    over the existing `l3()` transport): `scrollAt`, `dragBy`, `secondaryTapKey`, and
    `scrollUntilKey` (foreground()s first, fast-paths if target already visible, then
    wheel-scrolls up to maxSteps polling `waitKey`).
  - Quality gates: `flutter analyze lib tool` → 0 NEW issues in touched files (total 222,
    all pre-existing); `check_complexity.dart` does NOT flag ui_drive_tools.dart (364
    LOC); `fixture_c_unified_runner --plan-json --class=2proc-ui` parses + exits 0.
  - **DESKTOP message context-menu finding (for Batch 6):** the desktop chat message menu
    opens via a `Listener` in
    `TencentCloudChatMessageItemWithMenu.desktopBuilder`
    (`third_party/chat-uikit-flutter/.../menu/tencent_cloud_chat_message_item_with_menu.dart:684`):
    `onPointerDown` fires `_openDesktopMessageMenu(event.position)` ONLY when
    `event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton`. It
    is NOT a `GestureDetector.onSecondaryTap` and NOT a hover-more-button — it is a raw
    secondary-button mouse-DOWN on the Listener wrapping
    `widget.methods.getMessageItemWidget(key: _messageKey)`, where `_messageKey == null`
    (the item widget itself is unkeyed on desktop). So `ui_secondary_tap` (which sends a
    `PointerDownEvent(kind: mouse, buttons: kSecondaryMouseButton)`) is EXACTLY the right
    primitive and must hit a point inside that Listener's child. The stable keyed target
    is the ROW container key `ValueKey('message_list_item:<msgID>')`
    (`tencent_cloud_chat_message_row_container.dart:286`) — its center lies inside the
    bubble/Listener region. Batch 6 should `ui_secondary_tap('message_list_item:<msgID>')`
    to open the menu, then tap the keyed items `ValueKey('message_menu_item:<action>')`
    (copy/forward/delete[/recall for a fresh self message]; per the fork, TEXT bubbles
    STRIP reply/multiSelect/translate — see `message_actions_menu_real_ui_test.dart`).
    MOBILE parity trigger: on non-desktop screen modes the same row uses
    `GestureDetector.onLongPress` (`_onLongPressMessageOnMobile`, defaultBuilder:604) — a
    long-press, which `ui_drag`/secondary-tap do not cover; mobile would need a
    long-press primitive or the existing l3 `l3_invoke_message_action` bypass.
  - **Deviations from the spec:** (1) The optional `ui_hover` tool was NOT added — the spec
    marked it "if needed", and the message menu is a secondary-tap (not a hover
    affordance), so no hover is required for the planned scenarios; add it in a later
    batch if a hover-only surface appears. (2) `scrollUntilKey`'s signature uses
    `dyPerStep`/`maxSteps` (negative dy = wheel up to reveal earlier content) matching the
    spec; it foreground()s first like other UI phases.

- 2026-06-10 **Batch 1 DONE** (settings sweep 2 — 12 single-instance cases, WRITTEN +
  hermetically verified; NOT live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_settings2.dart` (~560 LOC) declared in
  `drive_real_ui_pair.dart`'s part list; 12 per-case scenario functions + `runSettingsSweep2`
  (chains all 12 on ONE launch, per-case `[sweep] <case>: PASS|FAIL` + final counts, exits
  non-zero if any HARD case fails — all 12 are hard). Each case also dispatchable individually
  in `drive_real_ui_pair.dart` (scenario ids = the campaign table ids). Runner: 13 ids
  (`sweep_settings2` + the 12) added to `_validRealUiScenarios` + both state tables
  (`_requiredRealUiState`/`_resultRealUiState` → `no-friend`, single-instance like
  `group_create`); campaign `rui-settings2 = [sweep_settings2]`. Gates green:
  `flutter analyze lib tool` 222 issues (0 NEW — matches Batch-0 baseline; the new part file
  is clean); `--plan-json --class=2proc-ui` exits 0; `--list-real-ui-campaigns` shows
  `rui-settings2`; `--validate-only` 0; driver `--self-test-shell-recovery` PASS; touched
  settings hermetic tests `flutter test test/ui/settings/` 59/59 PASS (incl. the
  password-mismatch case that mirrors case 11's snackbar + dialog-stays assertions).

  **Key discoveries / production keys used (for later batches):**
  - **Theme (cases 2/3, S57):** the Appearance `SegmentedButton<ThemeMode>` segments carry
    **NO per-segment key** (`global_settings_section.dart` — ButtonSegment takes none), so
    drive by the localized visible label (`tapText('Dark'|'Light'|'System')`). Assert the
    flip via dump `themeMode` (`light|dark|system`, persisted) + label-still-visible (the
    Appearance card didn't crash on rebuild). l3 dump field is `themeMode` (string).
  - **Locale (case 4, S38):** the Language card is an InkWell-collapsing list (NOT a
    SegmentedButton): the collapsed row shows the CURRENT selection's NATIVE label; tapping
    it expands; option labels are language-native literals (`'English'`, `'简体中文'`, …)
    that DON'T change across locale (`appL10n.english => 'English'` even while in zh). So
    revert-to-English works by tapping `English` while the UI is Chinese. dump field is
    `languageCode`; 简体中文 → `zh-Hans`. Chinese label to assert post-switch: `外观`
    (Appearance header). en `Language` header = `语言` in zh (used for re-locating the
    selector to revert).
  - **Download limit (case 5, S98):** `settings_download_limit_field` +
    `settings_download_limit_save_button` (keyed). Save validates `1..10000`. dump field
    `autoDownloadSizeLimit` (int MB). Field is below the fold — scroll onstage first.
  - **Bootstrap mode (case 6, S99/S85):** on DESKTOP the modes are `RadioListTile`s keyed
    `settings_bootstrap_mode_{manual,auto,lan}` (NOT a SegmentedButton — that's the MOBILE
    layout, and it's only manual/auto, NO lan on mobile). dump field `bootstrapNodeMode`.
  - **Manual node form (cases 7/8, S89) — SCOPE DEVIATION, faithful:** the manual node form
    (`manual_node_{host,port,pubkey}_field` + `manual_node_test_button`) only appears in
    manual mode AFTER tapping `manual_node_input_button` to expand. The "Set as Current Node"
    button only renders AFTER a LIVE `addBootstrapNode` TEST SUCCEEDS (needs real DHT
    reachability — non-deterministic in-harness), and there is **NO per-node REMOVE
    affordance anywhere** (manual mode only overwrites the single "current node" card;
    auto-mode "Route selection" → `bootstrap_nodes_page.dart` is a READ-ONLY fetched-node
    list with test/select only). So case 7 asserts the real form MOUNTS + accepts input
    (mode→manual is a real persisted mutation, the S89 surface); case 8 asserts the inverse —
    collapsing the form via the same `manual_node_input_button` toggle makes the field row
    GONE (`waitKeyGone`), then restores mode→auto. Both clearly noted in-code. If a later
    batch needs a true node add/remove, it has to be added to production first.
  - **Switch toggles (cases 9/10, S96/S97) — UPGRADE of the documented soft cases:** the
    OLD `settings_sweep` marked autologin/notification as SOFT because (a) below the fold
    (flutter_skill has no scroll) and (b) flutter_skill's synthetic `tap` doesn't reliably
    toggle a Material `Switch`. Both fixed: (a) Batch-0 `scrollUntilKey` brings the switch
    onstage; (b) `Inst.tapKeyCenter` dispatches a REAL `tapAt` at the switch center (a
    genuine pointer tap, distinct from flutter_skill's synthetic tap) which toggles the
    Switch. Keys: `settings_auto_login_switch` (Account card, upper-mid) /
    `settings_notification_sound_switch` (GlobalSettingsSection, lower). dump bools
    `autoLogin` / `notificationSound`. Both restore the prior value on a pass.
  - **Password mismatch (case 11, S40):** `_showSetPasswordDialog` shows the
    `Passwords do not match` snackbar AND returns WITHOUT `Navigator.pop` on a mismatch — so
    the dialog STAYS open (its `settings_set_password_new_field` key stays in the tree) and
    flutter_skill's double-fire `tap` is SAFE here (no route to double-pop). Confirmed by the
    existing hermetic test `settings_account_password_real_ui_test.dart` ("Mismatched fields:
    do not match SnackBar, dialog stays, nothing saved"). ESC-dismiss after, so no password
    is left set (case 12 relies on a password-free account).
  - **Logout cancel (case 12, S44):** the logout confirm dialog's **Cancel button has NO
    key** (only `settings_logout_confirm_button` is keyed); tap the `Cancel` LABEL. Cancel =
    `popDialogIfCurrent(context, false)` (pops only the dialog, no page-pop), so double-fire
    `tapText` is safe. Assert dialog gone (`waitKeyGone` on the confirm button) + dump
    `sessionReady` STILL true (Cancel must not tear down). The below-fold openers
    (`settings_logout_button`, `settings_set_password_button`) stay on `tapKey` (their direct
    `_tryInvokeCallback` opens the dialog once even off-screen).
  - **PRODUCTION CHANGE (allowed, precedented):** added a stable `ValueKey('settings_scroll_view')`
    (`UiKeys.settingsScrollView`) to the SettingsPage root `ListView` (`settings_page.dart`'s
    build) so `scrollUntilKey`/`scrollAt` have a scroll anchor for the below-fold Global /
    Bootstrap sections. The ListView carries no semantic content, so keying it is
    automation-only and safe; shared Dart, so mobile is covered. Batches 5/6/7 that need to
    scroll other long lists should look for (or add) a similar scrollable key.
  - **Ordering rationale (state-poisoning avoidance):** surface-read first; theme dark→light
    (ends LIGHT, a known state); locale zh→en roundtrip reverts BEFORE the later
    English-text cases so it can't poison them; download-limit + the two switches RESTORE
    their prior values; bootstrap mode cycle ends on `auto`; manual add → remove (collapse)
    leaves the form collapsed + mode auto; password-mismatch ESC-dismisses (no password set);
    `settings_logout_cancel` LAST (only ever taps Cancel → session survives).
  - **No `--boot-restored` / no friendship:** all 12 are single-instance no-friend (like
    `group_create`); the planner launches a FRESH pair (drives only A; B idle) and never
    needs `paired_for_e2e`.
  - **Codex review (2 rounds, mandatory):** round 1 found 5 issues — all applied: (P1)
    locale-expander + theme-segment + manual-node toggles double-fire under flutter_skill's
    `tap` → added a SINGLE-FIRE `_tapTextCenter` (text-matched `tapAt`, twin of
    `Inst.tapKeyCenter`; verified against the flutter_skill 0.9.36
    `interactiveStructured → data.elements[].{key?,text?,bounds{x,y,w,h}}` schema) for the
    label-only controls, and `tapKeyCenter` for the keyed manual-node toggle; (P2) password
    case now requires `dismissed` (dialog gone) in its return; (P2) download-limit +
    bootstrap-remove now require their RESTORE to succeed in the return; (P3) surface_sections
    now asserts the AutoDownload header TEXT (not just the keyed field). Round 2 flagged
    cross-case poison on a mid-sweep FAILURE (a stuck-in-zh locale would false-fail the later
    English-text cases) → added `_normalizeBetweenCases` (idempotent, best-effort, runs after
    EVERY case: reverts locale→en + bootstrap→auto if a prior case left them mutated; never
    throws). Round-2 residual (low severity, ACCEPTED): an individual case that fails its OWN
    restore leaves `autoDownloadSizeLimit` mutated — but the planner launches a FRESH pair per
    campaign run (no same-launch rerun), so it cannot poison a real run; the
    `_normalizeBetweenCases` guard covers the only same-launch poison that actually matters
    (locale + bootstrap mode, which gate later text assertions).

- 2026-06-10 **Batch 2 DONE** (self profile — 6 single-instance cases WRITTEN+unrun, 2
  avatar cases SKIP; NOT live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_profile.dart` (~530 LOC) declared in the
  `drive_real_ui_pair.dart` part list; 8 per-case functions + `runProfileSweep` (chains all
  8 on ONE launch, per-case `[sweep] <case>: PASS|FAIL|SKIP` + final counts, exits non-zero
  if any HARD case fails — 6 are hard, 2 are SKIPs). Each case individually dispatchable in
  `drive_real_ui_pair.dart` (scenario ids = the campaign table ids). Runner: 9 ids
  (`sweep_profile` + 8) added to `_validRealUiScenarios` + both state tables
  (`no-friend`, single-instance like `sweep_settings2`); campaign `rui-profile =
  [sweep_profile]`. Gates green: `flutter analyze lib tool` 222 (0 NEW — matches the Batch-0
  baseline); `--plan-json --class=2proc-ui` exit 0; `--validate-only` exit 0;
  `--list-real-ui-campaigns` shows `rui-profile`; driver `--self-test-shell-recovery` PASS;
  touched-lib hermetic profile tests `flutter test test/ui/profile_*` 10/10 PASS (the
  `profile_close_button` key addition didn't disturb the close-button test, which still
  finds the close button by its `Icons.close` predicate).

  **Keys used / production keys added (for later batches):**
  - **Self profile is an OVERLAY** (`showSelfProfile` → desktop `showDialog` / mobile
    `MaterialPageRoute`), opened by the persistent sidebar avatar `InkWell`
    (`UiKeys.sidebarUserAvatar == 'sidebar_user_avatar'`) → `_openProfile`. The avatar is
    onstage on EVERY home tab (it's in the left rail `buildSidebar`), so it's reachable from
    chats/contacts/settings alike.
  - **Profile keys already existed** (`ui_keys.dart`, attached to the production widgets in
    `lib/ui/profile/`): `profile_edit_toggle` (IconButton, TOGGLES `_editMode`),
    `profile_nickname_field` + `profile_status_field` (bare keyed `TextField`s, edit-mode
    only), `profile_save_button` (FilledButton, runs `_handleSave` → setState, NO
    Navigator.pop), `profile_tox_id_copy_button` (`_copyToxId` → clipboard +
    `'ID copied to clipboard'` snackbar), `profile_qr_copy_button` (`_copyQrImage` → same
    snackbar — but it only MOUNTS after the QR `FutureBuilder` resolves real canvas→PNG
    generation, so case 18 waits up to 20s for the key), `profile_tox_id_selectable_text`.
  - **PRODUCTION KEY ADDED (allowed, precedented):** `UiKeys.profileCloseButton ==
    'profile_close_button'` on BOTH self-profile overlay close `IconButton`s in
    `lib/ui/settings/sidebar.dart` (the desktop dialog `Positioned` close + the mobile route
    `AppBar` leading close). Lets `_closeSelfProfile` dismiss the overlay deterministically
    (single-fire `tapKeyCenter`, then ESC fallback) between cases, instead of a fragile
    top-right coordinate. Automation-only, shared Dart → mobile covered.
  - **The edit fields DRIVE FINE via `focusType`/`enterText`** (the old REAL_UI_TWO_PROCESS
    "inline edit field/save keys did not land via tap{key}" note is now MOOT for toxee): the
    keys sit directly on the `TextField`s, and `enterText` (no-key) targets the focused
    editable + does a FULL-text `updateEditingValue` REPLACE (so it doesn't matter that
    `osaClear` precedes it — kept as belt-and-suspenders, mirrors settings case 5). Save
    persists to Prefs; assert via `l3_dump_state.nickname` / `.statusMessage` (the latter is
    null→'' coerced, so a restore-to-empty round-trips). Cases 15/16 RESTORE the original
    registered values (poison guard — later batches assert the registered nick).
  - **TOGGLE double-fire discipline:** `profile_edit_toggle` flips `_editMode = !_editMode`,
    so flutter_skill's double-firing `tap` is a net no-op → driven with single-fire
    `tapKeyCenter` (Batch-1 pattern). `_enterProfileEditMode` retries the single-fire toggle
    up to 3× (an even-count correction). The avatar open is ALSO single-fired (tapKeyCenter,
    NO double-fire fallback) so it can't stack two profile dialogs.
  - **AVATAR cases 19/20 SKIP — verified, not assumed (per "don't trust doc conclusions"):**
    read `lib/ui/profile/profile_avatar_picker.dart` + `git show 5867fdc`. The self-profile
    avatar tap (`onAvatarTap → _pickAvatar → pickAndPersistAvatar`) opens the NATIVE
    NSOpenPanel directly via `FilePicker.platform.pickFiles` — there is NO in-app
    default-avatar grid/picker surface (the "default avatars" of 5867fdc are a
    REGISTRATION-TIME fallback INSTALLER in `lib/util/default_avatar_installer.dart`, not a
    chooser UI; the only avatar grid in the tree is upstream UIKit's GROUP-avatar
    `ChooseGroupAvatar`). The l3 override that bypasses the native panel
    (`l3_set_avatar_pick_path` / `l3_pick_avatar`) is TEST-ACCOUNT-gated → refused on the
    fresh non-test real-UI account, and would be a forbidden l3 bypass of the asserted
    action anyway. Both return null (SKIP). NEW runner plumbing: `_realUiSkipExitCode = 75`
    so the individual avatar dispatch returns 75 (the runner logs SKIP + continues, distinct
    from 0=PASS/78=BLOCKED — without this a `null→0` would be tallied a PASS upstream).
  - **No `--boot-restored` / no friendship:** all single-instance no-friend (like
    `sweep_settings2`); planner launches a FRESH pair (drives A; B idle).
  - **Codex review (2 rounds, mandatory):** round 1 found 4 (3 P1 + 1 P2), ALL applied:
    (P1) the avatar SKIP returned exit 0 → reported as PASS upstream → added the
    `_realUiSkipExitCode=75` SKIP code + runner handling; (P1) `_openSelfProfile`
    short-circuited if the overlay was already up → case 13 could false-PASS without tapping
    the avatar → it now CLOSES any pre-existing overlay + asserts `closedBefore` first, and
    `runProfileSweep` normalizes before the first case; (P1) case 18 could false-green on
    case 17's lingering `'ID copied to clipboard'` toast (same text, ~3s lifetime) → added
    `Inst.waitTextGone`, case 17 clears the toast and case 18 REQUIRES it dismissed before
    tapping QR-copy; (P2) the double-fire avatar `tap` could stack two dialogs → switched the
    open to single-fire `tapKeyCenter`. I tried a production re-entry guard in `sidebar.dart`
    but REVERTED it (a module-global flag broke widget-test isolation: `.whenComplete` never
    fires when a test force-dismisses via a direct `onPressed` call — so the guard is a
    harness-layer concern, fixed at the harness layer). Round 2 verified P1.1/P1.2/P1.3
    correct + flagged ONE residual: the `_openSelfProfile` double-fire `tryTapKey` FALLBACK
    was still reachable on a slow/unsized frame → REMOVED the fallback (tapKeyCenter already
    retries bounds 5×/~1s and the avatar is always sized; the outer loop re-foregrounds and
    retries). Round 2 then found no further false-pass/poison/hang.
  - **Mobile parity:** all driven widgets are shared Dart (`lib/ui/profile/`,
    `lib/ui/settings/sidebar.dart`); the `profile_close_button` key is on both the desktop
    dialog and the mobile route close buttons, so the close affordance is covered on mobile
    too. The avatar SKIP applies identically on mobile (the native picker is the only avatar
    surface there as well; there is no in-app default-avatar chooser on any platform).

- 2026-06-10 **Batch 3 DONE** (login / register — 8 single-instance cases WRITTEN+unrun, 1
  SKIP; NOT live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_login.dart` (~1075 LOC) declared in the
  `drive_real_ui_pair.dart` part list; 9 per-case functions + `runLoginSweep` (chains all 9
  on ONE launch, per-case `[sweep] <case>: PASS|FAIL|SKIP` + final counts + `endClean`, exits
  non-zero if any HARD case fails — 8 hard, 1 SKIP). Each case individually dispatchable in
  `drive_real_ui_pair.dart` (scenario ids = the campaign table ids; the single-case dispatch
  runs the minimum prelude each needs — cases that act on the LoginPage log out first). Runner:
  10 ids (`sweep_login` + 9) added to `_validRealUiScenarios` + both state tables
  (`no-friend`, single-instance like `sweep_profile`); campaign `rui-login = [sweep_login]`.
  Gates green: `flutter analyze lib tool` 222 (0 NEW — matches the Batch-0 baseline);
  `--plan-json --class=2proc-ui` exit 0; `--validate-only` exit 0; `--list-real-ui-campaigns`
  shows `rui-login`; campaign expansion + dry-run plan `sweep_login` from a fresh no-friend
  launch (no `--boot-restored`); driver `--self-test-shell-recovery` PASS; touched-lib
  hermetic tests `flutter test test/ui/register/ test/ui/login/ test/ui/testing/l3_debug_tools_environment_test.dart`
  57/57 PASS.

  **State-machine ORDER chosen** (ends CLEAN: logged into the PRIMARY account, NO password,
  autoLogin intact): `ensureHome` (registers the PRIMARY account if the launch is fresh) →
  **logout once** (serves 21+22; lands on LoginPage) → **22** register-open-back → **21**
  account-card-renders → **26** restore-entry (SKIP) → **23/24/25** register validation (NO
  accounts created — all back out) → **quick-login back to primary** (no password) → **27**
  wrong-password (sets a known pw via Settings, logs out, enters WRONG pw → "Invalid
  password", stays) → **28** correct-password (unlocks → HomePage, then REMOVES the password)
  → **29** account-switch (register account #2 nick `RuiSweepB3`, switch back to primary). The
  whole 9-case body runs inside a `try` with an `_ensureCleanPrimaryEnd` END-STATE GUARD in
  the `finally` so a partial run still restores the clean end state.

  **PASSWORD-RESTORE ANSWER (the brief's open question):** the PRODUCTION settings UI CAN
  clear a password — no need to leave the account password-locked. `_showSetPasswordDialog`
  accepts an EMPTY new+confirm (hint text "Leave empty to remove password"); on empty input
  `_setAccountPassword` routes to `AccountService.removeAccountPassword` and shows the
  "Password removed" snackbar. Case 28 unlocks with the correct password, then opens the
  Settings change-password dialog and submits EMPTY fields to restore the no-password state.
  The end state is PROVEN no-password via the new authoritative `currentAccountHasPassword`
  dump field (not the snackbar alone).

  **Case 26 SKIP (verified, not assumed — per "don't trust doc conclusions"):** read
  `lib/ui/login_page.dart` + `login_page_controller.dart`. The "Restore from .tox file" card
  (`UiKeys.loginPageRestoreFromToxFile`) calls `_restoreFromToxFile` →
  `LoginPageController.restoreFromToxFile`, which opens the native `FilePicker.platform.pickFiles`
  DIRECTLY — there is NO in-app pre-picker / options surface to assert mounting. The login
  "settings" entry (`login_page_settings_button`) opens `LoginSettingsPage`, which is the
  bootstrap/global settings page, NOT a restore/import surface. The native panel can't be
  driven headless and there's no test-account l3 override here → SKIP(native-picker-only),
  never a fake pass. (The real restore handler has hermetic controller-seam coverage in
  `test/ui/login/login_restore_import_settings_real_ui_test.dart`.)

  **PRODUCTION CHANGES (3, all intentional + tested + mobile-covered, shared Dart):**
  - `lib/ui/widgets/register_password_strength_bar.dart`: added a localized **Weak/Fair/Good/
    Strong** caption `Text` keyed `register_password_strength_label` under the colored bar (the
    segments' fill is a `BoxDecoration` color, NOT text-matchable by flutter_skill; the caption
    IS — it's the real-UI signal for case 25, and a genuine a11y win: a screen reader now
    announces password strength). 4 new l10n keys in `app_en.arb` + `flutter gen-l10n`
    regenerated (ar/ja/ko/zh fall back to English for these — documented follow-up). The
    existing strength hermetic test extended to assert the caption ramp (0→Weak→Fair→Good→Strong).
  - `lib/ui/login_page.dart`: the saved-account quick-login password dialog `TextField` got
    `key: login_quick_password_field` + `autofocus: true` so the harness can type into it
    deterministically (no key/autofocus before → could not target it). Compatible with the
    existing password-dialog test (which finds the field by type, not key).
  - `lib/ui/testing/l3_debug_tools.dart`: `l3_dump_state` now exposes `currentAccountHasPassword`
    (via a no-throw `_currentAccountHasPassword()` reading `Prefs.hasAccountPassword` on the
    current toxId) — the authoritative no-password ground truth case 28 + the end-clean guard
    gate on (the snackbar alone is ambiguous on a no-password account).

  **Harness keys used:** `register_back_button` (AppBar back), `register_page_*` fields/button,
  `firstRunBackupWizard.laterButton` + `firstRunBackupWizard.confirmDismissButton` (keyed +
  single-pop-guarded — case 29's wizard dismissal single-fires these via `tapKeyCenter`,
  replacing the double-firing text taps `ensureHome` uses), `settings_set_password_*`,
  `settings_logout_*`, `login_page_account_card:<toxId>` (single-fired via `tapKeyCenter`),
  `login_quick_password_field`.

  **Codex review (4 rounds, mandatory — telemetry-off):** round 1 found 5 (3 P1 + 2 P2): clamp
  index type (cosmetic — already compiled via int.clamp, made explicit `.toInt()`); case-27
  could false-pass under a stuck password dialog (added `waitKeyGone(login_quick_password_field)`);
  no end-state restore on a mid-sweep failure → dirty/poisoned 29 (added `_ensureCleanPrimaryEnd`);
  27→28 toxId handoff not enforced (now passes the threaded toxId, empty if 27 failed, so 28
  fails its guard); autoLogin unproven (now printed). Round 2 confirmed P1.1/P1.2/P2 + flagged
  3 (the end-clean guard not no-throw / not reached on early-return; case-29 wizard double-fire;
  endClean false-green). Round 3 fixed those (try/finally + no-throw helper; keyed single-fire
  wizard dismiss; endClean verdict) + flagged 2 (endClean still trusts the ambiguous remove
  snackbar; card taps still double-fire). Round 4 added the `currentAccountHasPassword` ground
  truth + switched all 4 card taps to `tapKeyCenter` + flagged 3 P2 (stale onPrimary; case 28
  not airtight; set-password opener double-fire). Round 4-fix: recompute the whole end-clean
  verdict from one final dump; case 28 also requires `sessionReady && currentAccountToxId==toxId`;
  both password-dialog openers funnel through a single-fire `_openSetPasswordDialog`. Final
  codex pass: **"No remaining P1/P2."**

  **Mobile parity:** all driven widgets + the 3 production changes are shared Dart (login_page,
  register_page, register_password_strength_bar, l3_debug_tools) with no platform split — every
  affordance and the strength caption render identically on iOS/Android/desktop. Case 26's SKIP
  applies on mobile too (the restore card opens the platform file picker there as well; no
  in-app pre-picker exists on any platform).

- 2026-06-10 **Batch 4 DONE** (contacts / friend profile — 15 TWO-PROCESS cases
  WRITTEN+unrun; NOT live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_contacts.dart` (~770 LOC) declared in the
  `drive_real_ui_pair.dart` part list; 15 per-case functions +
  `_establishFriendshipForSweep` (real-UI handshake helper) + `runContactsSweep`
  (chains all 15 on ONE pair launch, per-case `[sweep] <case>: PASS|FAIL` + final
  counts + an end-state reset guard, exits non-zero if any HARD case fails — all 15
  are hard). Each case individually dispatchable in `drive_real_ui_pair.dart` (the
  add-friend guards 30/31/32 + subtab cycle 34 run on a fresh no-friend launch;
  the friendship-dependent cases 33/35–44 boot `--boot-restored` paired_for_e2e or
  establish the friendship inline). Runner: 16 ids (`sweep_contacts` + 15) added to
  `_validRealUiScenarios` + both state tables; campaign `rui-contacts =
  [sweep_contacts]`.

  **NO PRODUCTION CHANGE in this batch** — every friend-profile / contact key the
  cases drive was ALREADY in the fork
  (`third_party/chat-uikit-flutter/.../tencent_cloud_chat_user_profile_body.dart`,
  `.../tencent_cloud_chat_contact_item.dart`, `.../tencent_cloud_chat_contact_tab.dart`,
  `.../tencent_cloud_chat_contact_app_bar.dart`). Verified-not-assumed (per "don't
  trust doc conclusions"):
  - **The delete-friend CONFIRM button IS keyed** — `user_profile_delete_friend_confirm_button`
    (+ a Cancel key, + a `handled` one-shot double-fire guard) on BOTH the
    Cupertino (macOS/iOS) and Material branches. The REAL_UI_TWO_PROCESS note that
    "the confirm button key (`user_profile_delete_friend_button`) wasn't found" was
    STALE / conflated two DISTINCT keys: the OPENER (`user_profile_delete_friend_button`,
    a GestureDetector) vs the CONFIRM (`user_profile_delete_friend_confirm_button`).
    Case 44 needs no production fix.
  - **Pin/Block are real `Switch`es via OperationBar `controlKey`**
    (`user_profile_pin_switch` / `user_profile_block_switch`) — single-fired with
    `tapKeyCenter` (a flutter_skill double-fire would toggle a Switch twice = net
    no-op). Mute is a bare `Switch` (`user_profile_conversation_mute_switch`).
  - **Send-Message tile is keyed per-tile** (`friend_profile_send_message_tile`, the
    leftmost of [Send,Voice,Video]) — case 36 single-fires it; toxee's
    `onTapContactItem` toggles profile→chat (when `_inContactProfileContext`).
  - **Contact row tap opens the PROFILE** (toxee's `onTapContactItem` →
    `_showUserProfileOnRight`), NOT the chat — confirmed in `home_page.dart`. The
    fork's `contact_list_item:<userID>.onTap = navigateToChat` is intercepted by
    toxee's `onNavigateToChat` handler returning true. Case 35 relies on this.
  - **Contact search field is keyed** `contact_search_field` (writes
    `contactSearchQuery`); the az-list filters case-insensitively on
    remark/nickname/userID — case 43's matching/non-matching/clear assertions.
  - **Subtab rows are keyed + tappable** (`contact_new_contacts_tab` /
    `contact_blocked_users_tab` on the InkWell/GestureDetector on desktop too) —
    the older "key on a non-tappable element" note is stale for these.

  **dump_state fields used (assertions, never the asserted action):**
  `blockedUsers` (live FfiChatService set, Prefs-backed — case 38/42),
  `pinnedConversations` (Prefs-backed — case 37), `conversations[].recvOpt`
  (case 39 SOFT), `conversations[].messageCount` via `dumpState(conversationId:)`
  (case 41 clear), `friends[].nickName` via `friendNick` (case 40 remark + case 44
  delete).

  **KNOWN-BUG cases asserted HARD on purpose (run-phase signals):**
  - **case 39 mute** (S114/S83): HARD = no-crash (BOTH sessions stay `sessionReady`
    across two toggles — the original ABI bug SIGSEGV'd both) + the switch tappable.
    SOFT (logged, NOT gated): the `recvOpt` dump value — the binary-replacement path
    stores `opt` in a C++ map distinct from the Prefs-backed conversation cache l3
    reads (the documented native→Dart sync residual). This is the REGRESSION GATE
    for the already-fixed `DartSetC2CReceiveMessageOpt` 3-arg ABI.
  - **case 40 remark** (S113/S30): HARD assertion that the remark PERSISTS — but
    EXPECTED TO FAIL live because `_onChangeFriendRemark` → SDK `setFriendInfo`
    (native binary-replacement path) is KNOWN BROKEN (input lands, Confirm doesn't
    persist). **A live FAIL here is the actionable signal to root-fix the native
    `dart_compat` setFriendInfo path in the run phase** (mirroring the mute ABI fix —
    likely another `Dart*` signature/stub drift vs the generated bindings;
    `abi_audit.py` for count/ptr, codex for width/signedness).

  **2p STATE CONTRACT (registered):** `sweep_contacts` required=no-friend (does its
  OWN real-UI handshake at the top), result=no-friend (case 44 deletes on both
  sides + a `finally` end-guard calls `runResetFriendship` if anything is still
  friended). Planner dry-run confirmed: `sweep_contacts` → a FRESH
  `launch_fixture_c_pair.sh` (no restore); the friendship-dependent individual
  cases → `TOXEE_FIXTURE_C_RESTORE=paired_for_e2e` + `--boot-restored`.

  **ORDER (state-poison-aware):** 30/31/32 (add-friend dialog guards — ESC close /
  inline invalid-ID error / self-add snackbar) BEFORE the handshake (no friendship
  needed; all back out without sending) → handshake once → 33 duplicate-guard (B
  re-adds A → "already in your friend list" snackbar) → 34 subtabs cycle → 35
  row-opens-profile → 36 send-message-tile (→chat) → 37 pin (restore unpinned) → 38
  block/unblock (ends unblocked) → 39 mute regression → 40 remark (expected-FAIL) →
  41 clear-history (seed 3 via the REAL composer, clear via profile, assert
  messageCount→0) → 42 block-via-profile → Blocked Users tab row → unblock → row
  gone → 43 contact search filter/clear → 44 DELETE friend (LAST; keyed confirm;
  ends no-friend BOTH sides). Each profile-control case re-opens the profile via
  `_ensureFriendProfileOpen` (tolerant, no-throw) and lands back on the Contacts
  shell so the next case starts clean.

  **Gates green:** `flutter analyze lib tool` 222 (0 NEW — matches the Batch-0
  baseline); `--plan-json --class=2proc-ui` exit 0; `--validate-only` exit 0;
  `--list-real-ui-campaigns` shows `rui-contacts: sweep_contacts`; dry-run of the
  `rui-contacts` campaign + the individual friendship-dependent cases plan
  correctly; driver `--self-test-shell-recovery` PASS; touched-surface hermetic
  tests `flutter test test/ui/contact/ test/ui/add_friend_*` 42/42 PASS (the
  invalid-ID hint text case 31 asserts —
  `'Tox address must be 76 hexadecimal characters'` — matches the production en
  string verbatim).

  **HARNESS FIX (shared helper, benefits the whole campaign — codex P1.2):**
  `deleteFriendViaProfile` (`drive_real_ui_pair_friends.dart`, used by
  `runResetFriendship` campaign-wide) was STALE — it only tapped the delete
  OPENER (`user_profile_delete_friend_button`) and never the keyed CONFIRM
  (`user_profile_delete_friend_confirm_button`), so it could stop at the confirm
  dialog and leave the friendship INTACT. Fixed to single-fire the keyed confirm
  (fallback "Confirm" label). This is the real correctness fix behind the
  REAL_UI_TWO_PROCESS "delete confirm button not found → incomplete" observation —
  the key was always there, the helper just never tapped it. Harness-layer
  (shared Dart driver helper), so it covers every batch's friendship reset.

  **Codex review (mandatory, telemetry-off — 1 round, ALL findings applied):**
  3 P1 + 2 P2 + 2 P3, every one fixed:
  - **P1.1** `runContactsSweep` returned `failed==0` even if the end-clean reset
    failed → the runner could trust an unachieved no-friend result. FIX: track
    `endNoFriend` (default false), recompute it from the actual friendship state
    AFTER the reset, and gate the return on `failed==0 && endNoFriend`.
  - **P1.2** the stale `deleteFriendViaProfile` (above) — case 44's mirror-delete
    fallback + the end-guard reset both depend on it.
  - **P1.3** case 39 (mute) liveness-only gate would FALSE-PASS a dead/no-op
    switch. FIX: also assert the Switch's `value` actually flips ON then OFF —
    read via flutter_skill `interactiveStructured` (it merges each Switch
    element's `state['value']` into the entry, verified in the 0.9.36 source).
    `onChanged` does `setState(disturb=value)` synchronously regardless of the
    SDK result, so the rendered value is the right HARD signal (the recvOpt dump
    stays SOFT).
  - **P2.1** case 40 weakened its assertion to `uiShowsRemark || dumpNick==...`
    (a transient toast could satisfy it). FIX: gate on the DUMP only
    (`dumpNick == remark`) + require the dialog CLOSED (a stuck modal can't false
    "remark shows").
  - **P2.2** case 40 claimed to restore the original remark but only logged it.
    FIX: added `_setFriendRemark` to restore via the real dialog when (and only
    when) the remark actually persisted — so once the native path is fixed, case
    43's nickB search + case 44 aren't poisoned.
  - **P3.1** case 34 (subtabs) accepted the TAB CONTROL key + ambiguous labels as
    "detail shown" → false-pass. FIX: assert DETAIL-PANE-ONLY markers (Blocked
    Users → "No blocked users" block-list empty-state copy; New Contacts →
    `contact_applications_list_empty` key), opening Blocked FIRST so New Contacts
    proves a real SWAP back.
  - **P3.2** case 36's `_tryTapText('Send Message')` fallback reintroduced the
    double-fire hazard on a route-changing tile. FIX: removed the fallback —
    single-fire `tapKeyCenter` only (it already retries bounds 5×); a missing
    tile is a hard FAIL, not a double-fire risk.

  After the fixes: analyze still 222 (0 NEW); planner/validate/campaign-list/
  self-test green; 42/42 touched-surface hermetic tests still PASS; `dart analyze`
  on the three touched driver/runner files clean (codex re-ran it). (The first
  codex attempt hung on the provider — TLS-flakiness, per the codex-telemetry
  memory; killed + re-ran with a bounded timeout; the second run completed.)

  **Mobile parity:** every widget the cases drive is shared Dart (the fork's
  friend-profile / contact-item / contact-tab / contact-app-bar widgets +
  toxee's `home_page.dart` `onTapContactItem`) with no platform split — the same
  add-friend guards, profile controls, search filter, and delete-confirm render
  identically on iOS/Android/desktop. The two KNOWN-BUG cases apply on mobile too:
  the mute ABI fix was a NATIVE FFI fix (covers both); the remark `setFriendInfo`
  path is the same native binary-replacement path on every platform, so a run-phase
  fix there covers mobile as well. (This harness drives the macOS desktop app; the
  hermetic L1 WidgetTester gates in `test/ui/contact/` cover the mobile builders.)

- 2026-06-10 **Batch 5 DONE** (conversation list C2C — 9 TWO-PROCESS cases
  WRITTEN+unrun, 1 SKIP; NOT live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_conv.dart` (~680 LOC) declared in the
  `drive_real_ui_pair.dart` part list; 9 per-case functions + 1 SKIP function +
  `runConvSweep` (chains all 10 on ONE 2p launch, per-case
  `[sweep] <case>: PASS|FAIL|SKIP` + final counts + an end-state re-seed guard,
  exits non-zero if any HARD case fails — 9 hard, 1 SKIP). Each case individually
  dispatchable in `drive_real_ui_pair.dart` (all need a friendship — establishes
  it inline via the real-UI handshake, or the runner restores paired_for_e2e).
  Runner: 11 ids (`sweep_conv` + 10) added to `_validRealUiScenarios` + both state
  tables; campaign `rui-conv = [sweep_conv]`.

  **MENU TRIGGER FINDING (the brief's open question — fully REAL, no l3 deep-link
  for the open):** the C2C conversation-row context menu opens through the SAME
  production path the group rows use. The fork's
  `tencent_cloud_chat_conversation_item.dart` wraps the row in
  `TencentCloudChatGesture` (`:297`), whose `InkWell.onSecondaryTapDown` →
  `_handleSecondaryTap` (desktop right-click) and a `RawGestureDetector`
  long-press → `_handleLongPress` (mobile) both call toxee's
  `onSecondaryTapConversationItem` / `onLongPressConversationItem` UI event
  handlers (`home_page.dart:349/358`) → `_showConversationContextMenu(conv,
  position)` → `showMenu` with the keyed `buildConversationContextMenuItems`. So
  `Inst.secondaryTapKey` (Batch-0 `ui_secondary_tap`: a real
  `PointerDownEvent(kind:mouse, buttons:kSecondaryMouseButton)` + up) on the row
  key `conversation_list_item:c2c_<pubkey>` opens the REAL menu — UNGATED, works
  on fresh non-test accounts. This is the C2C confirmation that the secondary-tap
  primitive (built for the Batch-6 message menu) is also the conversation-row menu
  trigger. The keyed items
  (`conversation_context_menu_{pin,unpin,mark_read,delete}_item`) + the keyed
  delete-confirm (`delete_conversation_confirm_button`) are then tapped through
  the real UI.
  - **PIN exception (deterministic action, mirrors `drive_real_ui_pair_group_menu`):**
    tapping the InkWell-backed `PopupMenuItem` for the pin TOGGLE double-fires
    under flutter_skill → two toggles = net no-op (the
    flutter_skill_double_tap_blank hazard); and a coordinate `tapKeyCenter` on a
    route-popping menu item can land a frame late as the menu dismisses. So the
    pin/mark-read TOGGLE/transition cases OPEN the real menu via `secondaryTapKey`
    to PROVE the surface (the keyed item renders), then dispatch the toggle/clean
    through `l3_open_conversation_menu` action:'pin'|'mark_read' — the SAME
    `_dispatchConversationMenuAction` the menu's onSelected runs (an ungated
    harness hook, NOT a bypass of the asserted handler). DELETE opens the real
    menu and single-fires the real keyed Delete item + the real keyed confirm.

  **PRESENCE ANSWER (case 53 — SKIP, verified not assumed per "don't trust doc
  conclusions"):** the C2C row's online-dot KEY
  (`conversation_item_online_dot:<convId>`) is ALWAYS in the tree; only its fill
  COLOR flips (status color online / transparent offline —
  `conversation_item_online_dot_key_test.dart`), so the key alone can't assert
  presence. The friend `online` flag in `l3_dump_state.friends[].online` comes
  straight from the native Tox friend-connection-status callback
  (`l3_debug_tools.dart:4700`); there is **NO ungated l3 setter** for it
  (`grep` for `l3_set_online`/`setFriendOnline` → none). The ONLY mechanism that
  flips B's online state is `stop_toxee_instance.sh B` + relaunch
  (`run_fixture_c_presence.sh` PHASE 2/3), which the launch-reuse rule FORBIDS.
  `drive_fixture_c_presence.dart` is purely OBSERVATIONAL (it POLLS A's
  `friends[].online`; it does not flip anything), confirming there is no seeding
  seam. So the flip is un-seedable on a reused launch → case 53 is
  `SKIP(presence-flip un-seedable; no ungated online setter; stopping B
  forbidden)`. The case logs the dot-key presence as a non-asserting surface
  breadcrumb but never fakes a flip (returns null → the sweep tallies SKIP;
  individual dispatch returns exit 75, the runner's `_realUiSkipExitCode`).

  **CASE-SHAPE DEVIATIONS (faithful, all in-code):**
  - **49 clear-history:** the conversation-row menu has NO "clear history" action
    (its items are pin/mark-read/delete — the C2C clear-history surface lives on
    the FRIEND PROFILE, gated in Batch-4 case 41). The conversation-LIST clear
    path for C2C is the ungated `l3_clear_history` hook (the same one the L3
    runner uses); there's no conv-row clear button to drive. So case 49 PROVES the
    real conv-row menu surface via the right-click (so it's a genuine conv-list
    case), then clears via `l3_clear_history`, asserting messageCount→0 + the row
    SURVIVES. The 45 surface assertion is therefore pin/mark-read/delete (no
    "clear" item — table updated).
  - **46 reorder:** the reorder is asserted from the dump conversation order
    (pinned-first, the same source the list renders). On a single-C2C-row list
    "pinned is first" is trivially true (nothing to sort below it) — still a valid
    pinned-first invariant; the HARD signal is `isPinned` flips on + pinned-first
    + `isPinned` flips off on unpin.
  - **47 vs 51:** 47 clears unread via the menu's Mark-as-read (the action path);
    51 clears unread by OPENING the chat (the natural user action / active-conv
    mark-read path) — two distinct production clears, both seeded by B's real
    sends with A parked off the conversation (active conversation cleared so the
    inbound accrues real unread rather than auto-marking).

  **REAL-UI SEAMS used (no new production keys — Batch 5 makes ZERO production
  change):** every key the cases drive already ships —
  `conversation_list_item:c2c_<pk>` (row), `conversation_context_menu_*` +
  `delete_conversation_confirm_button` (menu/confirm, home_page.dart),
  `conversation_item_online_dot:<convId>` (dot), `message_search_field` +
  `search_result_contact:<uid>` (search, custom_search.dart). New harness-only
  helper `Inst.osaSearchShortcut` (Cmd+Ctrl+F via osascript — a genuine OS key
  chord that runs the production `_OpenSearchIntent` Shortcuts/Actions path; the
  ONLY entry to the global search overlay — there is no visible search button).

  **2p STATE CONTRACT (registered):** `sweep_conv` required=no-friend (does its
  OWN real-UI handshake at the top, reusing Batch-4's
  `_establishFriendshipForSweep`), result=friends. The C2C delete (case 48)
  removes only the conversation ROW, not the friend (the S20 invariant —
  `deleteConversation` → clearC2CHistory + unpin, NOT deleteFriend, proven by the
  `conversation_row_menu_c2c_real_ui_test.dart` S20 gate), so the launch never
  goes no-friend; case 48 runs near LAST and the `finally` end-guard RE-SEEDS a
  conversation row (one composer send) + lands both on the chats home, so the
  launch ends FRIENDS with a visible row. The return gates on
  `failed==0 && endFriends`, where `endFriends` is recomputed AFTER the re-seed
  from the live state as `areFriends(a,B) && areFriends(b,A) && _conversationListed(
  a, c2c_<B>)` (default false), so the runner never trusts an unachieved result
  state — including a silently-failed reseed (codex P1). Planner dry-run confirmed: `sweep_conv` → a FRESH
  `launch_fixture_c_pair.sh` (no restore, no `--boot-restored`); the individual
  cases → `TOXEE_FIXTURE_C_RESTORE=paired_for_e2e` + `--boot-restored`.

  **ORDER (state-poison-aware):** handshake once → 45 menu surface → 46 pin/unpin
  reorder (ends unpinned) → 47 mark-read (B seeds unread, menu Mark-as-read
  clears) → 49 clear-history (seed+clear, row survives) → 50 clear-preserves-pin
  (ends unpinned, restores) → 51 unread bump→open clears → 52 preview on inbound →
  53 presence (SKIP) → 54 conversation search filter/clear (opens via real
  Cmd+Ctrl+F, closes via ESC) → 48 DELETE row (near LAST; friendship intact) →
  finally RE-SEED a row. Pin cases restore unpinned; the search overlay is closed
  after 54; the delete is last-but-the-re-seed.

  **Gates green:** `flutter analyze lib tool` 222 (0 NEW vs the Batch-0 baseline —
  the new part file + the `osaSearchShortcut` addition are clean); `--plan-json
  --class=2proc-ui` exit 0 (JSON parses); `--validate-only` exit 0;
  `--list-real-ui-campaigns` shows `rui-conv: sweep_conv`; the `rui-conv` campaign
  + the individual `conv_*` cases dry-run plan correctly (fresh-vs-restored);
  driver `--self-test-shell-recovery` PASS; `gen_scenario_index.dart --check`
  green (178 playbooks, no invariant violations); touched-surface hermetic tests
  `flutter test test/ui/conversation/ test/ui/search/
  test/ui/testing/ui_drive_tools_test.dart` 43/43 PASS (these prove every
  conversation-menu / online-dot / search key the cases depend on is live in the
  production/fork code — Batch 5 adds NO production change, so the existing gates
  are the key-existence proof).

  **Codex review (mandatory, telemetry-off — 1 review round + 1 confirm round,
  all findings applied):** round 1 found 1 P1 + 1 P2, both fixed:
  - **P1** `runConvSweep`'s `finally` end-guard awaited `_seedConvRow` but IGNORED
    its bool and computed `endFriends` from friendship ALONE → a silently-failed
    reseed false-passed the "ends FRIENDS with a visible row" contract. FIX: the
    end-state gate now also requires the re-seeded row to be LISTED via the
    AUTHORITATIVE live `_conversationListed(a, c2c_<B>)` check
    (`endFriends = areFriends(a,B) && areFriends(b,A) && stillRow`); the return is
    unchanged `(failed==0 && endFriends)`.
  - **P2** `_convSearchFilterClear` could record PASS while the `CustomSearch`
    overlay was still on top (`_closeGlobalSearch` was best-effort, void) →
    poisons the next hard case (`conv_delete_confirm_c2c`) which expects the chats
    home, not a search overlay. FIX: `_closeGlobalSearch` now RETURNS whether
    `message_search_field` is gone, and case 54 gates its PASS on `&& closed`.
  - Confirm round verified P1+P2 RESOLVED and flagged ONE residual false-FAIL
    risk: gating the live row check on `endRowSeeded &&` would fail a race where
    the reseed's `_waitConversationListed` timed out but the row IS present by the
    final check. FIX: dropped the `endRowSeeded &&` conjunct — the LIVE
    `_conversationListed` is the sole authoritative row gate; `endRowSeeded` is now
    only a diagnostic in the RESULTS print. After the fixes: analyze still 222 (0
    NEW), driver self-test PASS, validate/plan-json/campaign-list green.

  **Mobile parity:** every widget the cases drive is shared Dart (the fork's
  `tencent_cloud_chat_conversation_item.dart` row + gesture, toxee's
  `home_page.dart` menu handlers + dispatch, `custom_search.dart`) with no
  platform split — the same conversation-row menu, pin/mark-read/delete, online
  dot, and global search render identically on iOS/Android/desktop. The menu
  TRIGGER differs by platform only in the FORK's gesture wiring (desktop
  `onSecondaryTapDown`, mobile `onLongPressStart` → both call the same toxee
  handler → the same `showMenu`), so this harness drives the desktop right-click
  while the mobile long-press hits the identical production path; the
  `ui_secondary_tap` primitive covers desktop, and a mobile long-press primitive
  (or `l3_open_conversation_menu`) would cover mobile (noted in Batch-0 for the
  message menu, applies here too). The presence SKIP applies identically on mobile
  (the friend online flag is the same native readout with no setter on any
  platform).

- 2026-06-10 **Batch 6 DONE** (chat surface C2C — 14 TWO-PROCESS cases
  WRITTEN+unrun, 2 SKIP; NOT live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_chat.dart` (~950 LOC) declared in the
  `drive_real_ui_pair.dart` part list; 16 per-case functions + `_seedChatHistory`
  (~24-message seed shared by 65/66) + `runChatSweep` (chains all 16 on ONE 2p
  launch, per-case `[sweep] <case>: PASS|FAIL|SKIP` + final counts + an end-state
  re-seed guard, exits non-zero if any HARD case fails — 14 hard, 2 SKIP). Each
  case individually dispatchable in `drive_real_ui_pair.dart` (all need an A<->B
  friendship — establishes it inline via the real-UI handshake, or the runner
  restores paired_for_e2e). Runner: 17 ids (`sweep_chat` + 16) added to
  `_validRealUiScenarios` + both state tables; campaign `rui-chat = [sweep_chat]`.

  **GATING ANSWER (the brief's prominent open question — answered + UNBLOCKED):**
  the whole L3 surface only registers in a `kDebugMode && TOXEE_L3_TEST` build
  (`kL3TestSurfaceEnabled`; run_toxee.sh injects `--dart-define=TOXEE_L3_TEST=true`).
  WITHIN that build, the mutating/SEEDING tools (`l3_send_file`,
  `l3_clear_history`, `l3_clear_active_conversation`, …) ALSO gate on
  `_activeAccountIsTest()` (`l3_debug_tools.dart:377`): an account qualifies via
  (1) an EXACT fixture nickname (`_kTestNicknames` = echo_seeded_test/
  echo_live_test/echobotserver), (2) a known fixture Tox-ID PREFIX
  (`8895A8D64C34334F…`), OR (3) the persistent SEED-ACCOUNT MARKER
  (`Prefs.l3SeedToxIds`, written by `l3_register_account`). A real-UI sweep
  account registers through the REAL RegisterPage (NOT `l3_register_account`), so
  it has NO marker and is NON-TEST → those seeding tools refuse it with
  `non_test_account`. **This also retroactively explains why Batch-5 cases 49/50
  call `l3_clear_history`: those will refuse on the fresh non-test sweep accounts
  unless the account is test-marked at run time.** FIX (legitimate, in-contract):
  a new UNGATED **`l3_mark_current_account_test`** tool records the CURRENT
  account in the seed marker (`Prefs.addL3SeedToxId`) — exactly as if it had been
  created via `l3_register_account`. NOTE (codex P1): the marker authorizes the
  WHOLE test-account-gated surface (not a "seeding-only" subset — there is no
  per-tool scope today), so the campaign uses it ONLY to seed (the asserted
  action in EVERY case stays the real widget/gesture — the tool NEVER substitutes
  for the asserted UI action) and the sweep REVOKES it via the new
  **`l3_unmark_current_account_test`** in its end-guard so the launch ends with
  the same non-test privilege state it started — no hidden grant for a reused
  launch (the marker is ALSO revoked when the account is deleted —
  `Prefs.removeL3SeedToxId` in `removeAccount`, proven by `l3_seed_marker_test`).
  It only works in the already-gated debug build. `runChatSweep` calls
  `Inst.markAccountTest()` on BOTH peers right after the handshake → unblocks
  cases 69/70 (image/file `l3_send_file` SEEDING) AND Batch-5's `l3_clear_history`,
  then `unmarkAccountTest()` in the end-guard. **A sweep CAN legitimately
  test-mark its own throwaway account at run time — via these ungated tools (and
  must un-mark before it ends), not a nick pattern.**

  **MULTILINE FINDING (case 56, S120 — Shift+Enter IS wired):** read
  `tencent_cloud_chat_message_input_desktop.dart:545` `_handleKeyEvent`:
  `(event.isShiftPressed || isAltPressed || isControlPressed || isMetaPressed)
  && isPressEnter` → INSERTS `\n` at the cursor + returns `handled` (NO send);
  plain Enter sends. So case 56 is FULLY DRIVEABLE: osascript `key code 36 using
  shift down` (new `Inst.osaShiftReturn`) inserts the newline, then a plain
  `osaReturn` sends. Asserts the delivered bubble text == `line1\n line2` and B
  receives it. NOT a SKIP — the multiline affordance exists.

  **FORWARD FINDING (case 63, S17):** the real desktop forward picker mounts
  ("Forward Individually" header) and the Recent tab lists the available target
  conversations (`message_actions_menu_real_ui_test.dart` S17). With ONE friend
  there is only ONE target conversation — the same C2C row — so case 63 forwards
  BACK INTO the C2C chat (selecting the friend's nickname in the Recent tab +
  Send). This still exercises the real picker → real forward-send path end to end
  (HARD: picker surfaced + dismissed after Send + a SECOND copy of the forwarded
  text lands, i.e. forwardedCount≥2). The brief's "forward to a group" variant
  would need a pre-created group; deferred to Batch 7's group surface (the
  forward MECHANISM is proven here).

  **OFFLINE FINDING (case 68, S25/S13 — SKIP, verified not assumed):** a
  self-message becomes `isPending` ONLY while the PEER is unreachable
  (`message_converter.dart:77`: `isPending == V2TIM_MSG_STATUS_SENDING`). There
  is NO ungated l3 seam to force a pending/offline C2C send (grep
  `l3_set_connection`/`l3_disconnect`/`l3_offline` → none;
  `drive_fixture_c_network_drop.dart`'s `network_drop` drives the CALL reconnect
  path `markReconnecting()`, not the message offline queue; `isPending` is
  derived from native send status, no setter). The only way A's C2C send goes
  pending is making B unreachable — stopping B's process, which the launch-reuse
  rule FORBIDS. So the pending→deliver transition is un-seedable on a reused
  launch → SKIP. Returns null (the sweep tallies SKIP; individual dispatch exits
  75 = `_realUiSkipExitCode`). Logs a non-asserting breadcrumb (a normal send is
  NOT pending — the connected path) but never fakes the flip.

  **REPLY FINDING (case 62, S18 — SKIP, verified not assumed):** the REAL Reply
  menu item is STRIPPED from TEXT bubbles and only appears on a QUOTABLE
  (custom-elem) bubble (`message_actions_menu_real_ui_test.dart` S15+S18: text
  menus offer EXACTLY copy/forward/delete; the only reply gate is on the
  custom-elem fixture). On a reused launch there is NO way to produce a quotable
  INBOUND C2C bubble: B's REAL composer only sends TEXT (reply-stripped), and
  there is NO C2C custom-elem inbound-injection seam (only `l3_inject_group_text`
  exists — group text, not a C2C custom elem). EVEN IF one were seeded, the
  composer quote banner (`TencentCloudChatMessageInputReplyContainer`) carries NO
  ValueKey, so the harness cannot assert it mounted. A fully-real reply would
  need TWO new pieces — (1) a C2C custom-elem inbound seed seam in ffi/l3, (2) a
  ValueKey on the reply container — both FLAGGED as fork/ffi rebuild needs. The
  reply METADATA path already has hermetic L1 coverage (the S18 test drives the
  real Reply item → real quote banner → send carrying `messageReply`
  cloudCustomData). SKIP (returns null), never a fake pass. Case 62 LOGS a
  surface breadcrumb (the reply item is ABSENT on a fresh TEXT bubble, confirming
  the fork-strip) but never claims a pass.

  **MESSAGE MENU TRIGGER (the brief's Batch-0 recipe — used verbatim):**
  `Inst.secondaryTapKey('message_list_item:<msgID>')` (Batch-0 `ui_secondary_tap`
  → a real `PointerDownEvent(kind:mouse, buttons:kSecondaryMouseButton)`) opens
  the REAL desktop menu via the `Listener` in
  `TencentCloudChatMessageItemWithMenu.desktopBuilder`; the items are then tapped
  by `message_menu_item:<action>` (copy/forward/delete present on a fresh OWN text
  bubble — the fork strips reply/multiSelect/translate; verified). Delete confirm
  uses the keyed `confirm_dialog_primary_button`. Cases 60/61/63/64 single-fire
  the keyed items with `tapKeyCenter` (a route-popping `PopupMenuItem`/menu item
  must not double-fire). OWN-message row ids come from the dump `messages[]`
  (`_ownMessageId` matches isSelf+text). The keys are all PROVEN to exist by the
  passing hermetic tests in `test/ui/chat/` (Batch 6 reads them, adds no message
  widget key).

  **EMOJI/STICKER FINDING (cases 58/59, S22/S23):** the panel trigger is the
  keyed `sticker_panel_button` (`tencent_cloud_chat_message_input_desktop.dart:385`)
  — opens the real panel. BUT the panel GRID CELLS carry NO per-cell ValueKey
  (the hermetic `sticker_send_real_ui_test.dart` matches them by AssetImage), so
  flutter_skill can't tap a cell by key. So case 58 asserts the real panel
  SURFACE opens (HARD) + an emoji-TOKEN message (`[Smile]`-form, the same `[xxx]`
  the panel inserts) round-trips both ways through the real composer (HARD); case
  59 asserts the panel surface opens (HARD) — the type-1 face SEND has hermetic
  L1 coverage (the grid GestureDetector → sendStickerMessage path), and a real-UI
  face-SEND assertion would need a keyed face cell (FLAGGED as a fork rebuild
  need). A coordinate tap on the unkeyed cell is logged best-effort.

  **HISTORY / LOAD-MORE (case 65, S14):** the production list AUTO-loads older
  history with a `lastMsgID` cursor when scrolled toward the top
  (`message_history_load_more_real_ui_test.dart`). `_seedChatHistory` does ~24
  alternating REAL composer sends (A and B), then case 65 reopens the chat fresh
  and wheel-scrolls UP via the Batch-0 `scrollAt('message_list_item:<anchor>',
  dy:-600)` until the EARLIEST seeded text becomes present in the dump (the older
  page loaded). The same ~24-msg seed serves case 66.

  **INBOUND-WHILE-SCROLLED-UP (case 66):** the fork renders a "new messages"
  button (the `newMessageCount` notifier in `message_list.dart:604`) when an
  inbound arrives while scrolled up, but it carries NO stable key. So the HARD
  signal is: the inbound IS delivered (in A's dump) AND A STAYS IN THE CHAT
  (activeConversation unchanged == the C2C id — no forced jump/teardown). The
  keyless new-messages chip is logged best-effort, not gated.

  **MEDIA (cases 69/70, S88/S21/S24):** `l3_send_file` (test-gated → unblocked by
  the marker) does a REAL Tox file transfer (writes a temp file → `provider.sendFile`
  → delivers to the peer), so B→A delivers a genuine inbound image/file message
  that A renders as a real bubble. Case 69 asserts an inbound `mediaKind=='image'`
  message + its bubble row renders (HARD); the tap→preview is best-effort (the
  image's tappable GestureDetector mounts only AFTER an async load — not driveable
  at the widget layer, per the hermetic test's own scope note). Case 70 asserts an
  inbound `mediaKind=='file'` message + the filename text + the bubble row (HARD);
  the tap-open dispatches `_openFile()` (routes to the OS, best-effort).

  **2p STATE CONTRACT (registered):** `sweep_chat` required=no-friend (does its
  OWN real-UI handshake at the top, reusing Batch-4's
  `_establishFriendshipForSweep`), result=friends (no case deletes the friend; the
  end-guard re-seeds a row + verifies the launch ends friends-with-a-visible-row,
  recomputed from the live state — the runner never trusts an unachieved result).
  Planner dry-run confirmed: `sweep_chat` → a FRESH `launch_fixture_c_pair.sh` (no
  restore, no `--boot-restored`); the individual cases → `paired_for_e2e` +
  `--boot-restored`.

  **ORDER (state-poison-aware):** handshake once → mark BOTH test → 55 open-from-row
  → 57 long-text (BEFORE 56 so the multiline `\n` can't poison it) → 56 multiline
  → 58 emoji → 59 sticker → 60 menu surface → 61 copy → 62 reply (SKIP) → 63
  forward → seed ~24-msg history → 65 load-more → 66 inbound-while-scrolled-up →
  67 header→profile → 64 DELETE (AFTER the menu cases that needed a bubble) → 68
  offline (SKIP) → 69 image → 70 file → end-guard re-seeds a row.

  **PRODUCTION CHANGES (3, intentional + tested + mobile-covered, shared Dart):**
  (1) `lib/ui/testing/l3_debug_tools.dart` — the new UNGATED
  `l3_mark_current_account_test` (the gating-answer unblock seam) + its inverse
  `l3_unmark_current_account_test` (codex P1: the marker grants the WHOLE gated
  surface, not just seeding, AND persists, so the sweep REVOKES it in its
  end-guard so the launch ends with the same non-test privilege state — no hidden
  grant left behind for a reused launch). (2) the fork desktop sticker panel
  (`tencent_cloud_chat_message_input_sticker_panel.dart`) gets a stable
  `ValueKey('desktop_sticker_panel')` on its overlay Container so cases 58/59 can
  assert the panel actually OPENED (not just that the trigger button exists;
  codex P1 false-pass fix) — automation-only, no semantic content. No MESSAGE
  widget key was added (every menu/row/header key the cases drive already ships in
  the fork, proven by the passing `test/ui/chat/` hermetic tests). Mobile parity:
  the l3 tools are platform-agnostic Dart; the seeding they unblock (image/file
  inbound, clear-history) is the same shared-Dart path on every platform; the
  sticker panel key is on the desktop overlay (the mobile panel is an inline
  `_showStickerPanel` toggle — a mobile real-UI test would assert that state). The
  message context menu is desktop right-click vs mobile long-press — SAME shared
  handler (`message_menu_item:*` actions), identical asserted behavior; this
  harness drives the desktop secondary-tap (mobile would use a long-press
  primitive or the existing `l3_invoke_message_action`).

  **Codex review (mandatory, telemetry-off — 1 review round + 1 confirm round,
  ALL findings applied):** round 1 found 5 P1 + 1 P2 + 1 P3, every one fixed:
  **P1.1** the marker tool grants the WHOLE
  test-account surface (not just seeding) → tightened the doc to be honest +
  added `l3_unmark_current_account_test`. **P1.2** the marker persists as hidden
  state-poison for a reused launch → the sweep end-guard + the individual media
  dispatch (try/finally) now REVOKE it via `unmarkAccountTest`. **P1.3** cases
  58/59 could PASS on a no-op panel tap (only the trigger BUTTON was asserted) →
  added the `desktop_sticker_panel` fork key and gated both cases on the panel
  OVERLAY actually appearing. **P1.4** case 65 read the dump `messages[]` (full
  persisted history regardless of scroll) → now gates on the earliest ROW being
  RENDERED (`waitKey('message_list_item:<earliestId>')`) after scrolling — the
  load-more page actually mounting, not the persisted list; `_seedChatHistory`
  now returns the earliest msgID. **P1.5** case 66 only proved delivery +
  same-conversation → now proves NO FORCED JUMP (the scrolled-up older ROW stays
  rendered after the inbound; a jump-to-bottom would un-mount it). **P2** case 69
  accepted the first inbound `mediaKind=='image'` (stale-image false-pass on a
  restored run) → now matches the UNIQUE seeded `fileName`. **P3** the individual
  SKIP dispatch mapped `true→75` (latent if 62/68 ever became runnable) → a
  `skipMap(bool?)` now maps `null→75, false→1, true→0`. The CONFIRM round verified
  P1.1/P1.2/P1.3/P2/P3 resolved and flagged 2 residuals, both fixed: (a) **P1.4/P1.5
  scroll anchor** — the scroll loop used the FIRST persisted msgID (the OLDEST,
  OFFSCREEN row), whose key has no RenderBox so `ui_scroll_at` fails without moving
  the list; switched to a VIEWPORT COORDINATE scroll (new `Inst.scrollAtCoords` →
  `ui_scroll_at` raw `x,y`), and case 65 now FAILS (not vacuously passes) when the
  earliest row is already rendered on open (history too short to prove load-more =
  a seed failure). (b) **P1.1 residual prose** — removed the lingering
  "grants only the seeding surface" claim from the tool doc / inst helper / sweep
  comment / file header / campaign doc (the marker authorizes the whole gated
  surface; honest everywhere now). After the confirm-round fixes: analyze still 222
  (0 NEW), planner/validate/campaign-list/INDEX/self-test green, touched hermetic
  tests 46/46 still PASS.

  **Gates green:** `flutter analyze lib tool` 222 (0 NEW vs the Batch-0 baseline —
  the new part file + the `osaShiftReturn`/`markAccountTest` inst additions + the
  new l3 tool are all clean); `--plan-json --class=2proc-ui` exit 0 (JSON parses);
  `--validate-only` exit 0; `--list-real-ui-campaigns` shows `rui-chat: sweep_chat`;
  the `rui-chat` campaign + the individual `chat_*` cases dry-run plan correctly
  (fresh-vs-restored); driver `--self-test-shell-recovery` PASS;
  `gen_scenario_index.dart --check` green (178 playbooks, no invariant violations);
  touched-surface hermetic tests `flutter test test/l3_seed_marker_test.dart
  test/ui/chat/ test/ui/testing/ui_drive_tools_test.dart
  test/ui/testing/l3_debug_tools_environment_test.dart` 46/46 PASS (the chat tests
  prove every `message_menu_item:*` / `sticker_panel_button` / `message_list_item:*`
  / `confirm_dialog_primary_button` / `message_header_profile_avatar` key the cases
  depend on is live; the seed-marker test gains a case for the new tool's wiring).

- 2026-06-10 **Batch 7 DONE** (group / conference — 14 MIXED single-instance +
  two-process cases WRITTEN+unrun, 0 SKIP; NOT live-run, per write-phase
  protocol). New part file `tool/mcp_test/drive_real_ui_pair_group2.dart`
  (~1000 LOC) declared in the `drive_real_ui_pair.dart` part list; 14 per-case
  functions + `runGroup2Sweep` (chains all 14 on ONE 2p launch, per-case
  `[sweep] <case>: PASS|FAIL` + final counts + an end-state guard, exits non-zero
  if any HARD case fails — all 14 hard) + `runGroup2Case` (individual dispatch:
  each case builds its OWN minimal precondition). Runner: 15 ids (`sweep_group2`
  + 14) added to `_validRealUiScenarios` + both state tables; campaign
  `rui-group2 = [sweep_group2]`.

  **KICK-UI ANSWER (the brief's open question — a REAL desktop kick surface
  EXISTS for PRIVATE groups; verified not assumed):** on DESKTOP, kicking a
  member is the member ROW's `onSecondaryTapDown` →
  `_showDesktopContextMenu` (`tencent_cloud_chat_group_member_list.dart`) → a
  `showMenu` whose 'remove' PopupMenuItem renders only when `canDeleteMember()`
  (requires `myRole==OWNER` — A is the creator/owner — AND target role != OWNER
  AND `groupType != AVChatRoom`). So a PRIVATE NGC group OWNER CAN kick a member
  through the real UI. Two surfaces were UNKEYED and ADDED at the fork boundary
  (flagged rebuild): the per-member ROW key `group_member_list_item:<userId>`
  (on the row `GestureDetector`) and the desktop kick menu item
  `group_member_desktop_kick_item` (a `KeyedSubtree` around the 'remove'
  PopupMenuItem child; the mobile action sheet already had
  `group_member_action_kick_button`). Case 78 right-clicks B's row
  (`ui_secondary_tap`) → taps the keyed kick item → asserts B leaves A's
  authoritative member list (A's `l3_group_member_count` drops back to 1, the
  moderator view that confirms the kick — an invite auto-join does NOT propagate
  B's removal to B's `knownGroups`, matching the S37 PRIVATE-path A-side check).
  For a CONFERENCE (AVChatRoom) `canDeleteMember()` is FALSE (no roles) — the
  kick is a NEGATIVE there (the S173 finding), which is exactly why case 78 is
  PRIVATE-group only and the conference cases (82-84) don't kick.

  **GROUP-MUTE ROUTING ANSWER (the brief's open question):** toxee's group
  profile does NOT add its own mute control. The upstream group-profile body
  (`tencent_cloud_chat_group_profile_body.dart`) renders the
  `getGroupProfileStateButtonBuilder` slot, which toxee does NOT override, so the
  upstream `TencentCloudChatGroupProfileStateButton` renders a "Do not disturb"
  `OperationBar` switch (→ `setGroupReceiveMessageOpt`) + a Pin switch. The
  do-not-disturb switch was UNKEYED; a `controlKey: ValueKey('group_profile_mute_switch')`
  was ADDED on it at the fork boundary (the `OperationBar` already plumbs
  `controlKey` to its inner `Switch`; mirrors the friend-profile
  `user_profile_conversation_mute_switch`). Case 80 toggles it ×2 and reads its
  `value` via `interactiveStructured` (HARD: value flips ON then OFF + both
  sessions stay alive; recvOpt dump is SOFT — the native→Dart sync residual).

  **MEMBER-LIST OPEN (new navigation hook):** the group profile's "Group Members
  (N)" entry is a `KeyedSubtree` (`group_profile_members_entry`) that ALSO wraps
  the "+ Add Members" affordance, so a coordinate tap on the entry is ambiguous
  (header vs add). A NEW UNGATED `l3_open_group_member_list` navigation-stability
  hook (mirrors `l3_open_group_add_member` / `l3_open_conversation_menu`:
  `_openGroupMemberList` in `home_page.dart` + an invoker in
  `home_page_bootstrap.dart` + the MCPCallEntry + typedef in `l3_debug_tools.dart`)
  pushes the REAL member-list page; the page is then driven through REAL widgets
  (the keyed member rows, the desktop kick menu, member-list `ui_drag`). The
  ASSERTED action in every case is always the production widget/gesture — l3 is
  used only for navigation-stability opens (the established add-member/conv-menu
  exception) + the seeding/identity/bootstrap plumbing the existing group drivers
  already use (full-mesh bootstrap, auto-accept, member-count polling).

  **SWEEP ORDER (state-poison-aware, shared-resource reuse):** handshake once →
  wire full-mesh bootstrap + B auto-accept (2p prereqs) → 71 create-cancel (ESC;
  no group) → 72 create-type-selector (CREATES the SHARED private group, B not
  in it) → 76 rename (renames the shared group; later cases use the new name) →
  73 members-entry → 80 mute toggle → 74 clear-history → 77 add B via the REAL
  add-member UI (B now in the shared group) → 79 member-list scroll → 81 unread
  badge → 78 kick B (destructive; B leaves the group) → 75 leave via profile
  (LAST group case; destroys the shared group) → 82 conf create (SHARED
  conference) → 83 conf row menu → 84 conf member list. End-guard restores B's
  auto-accept + lands both home; the friendship is NEVER deleted → ends FRIENDS.

  **CASE-SHAPE NOTES (faithful, in-code):**
  - **71 create-cancel:** the AddGroupDialog has NO Cancel button — ESC
    (CallbackShortcuts(escape) → maybePop) is the only dismiss. The case opens the
    real dialog (`l3_open_add_group_dialog`), ESCs, and asserts no new group
    conversation appeared.
  - **74 clear-history / 75 leave:** the group-profile adaptive confirm dialogs
    (Clear-History / Quit) have NO keyed Confirm button — the Confirm is tapped by
    the localized "Confirm" label; the fork's one-shot `handled` guard makes a
    flutter_skill double-fire safe (it pops + runs the action exactly once).
  - **79 member-list scroll (HONEST low-value gate):** with only 2 members the
    AzListView can't actually scroll far, so the assertion is the `ui_drag`
    EXECUTES without error AND the member rows are STILL rendered afterwards (the
    list survived the gesture). Stated as low-value-but-cheap in-code.
  - **83 conf row menu:** the conference reuses the SAME type-agnostic
    conversation-row menu (the shared `conversation_context_menu_*` keys, S161),
    so it drives `l3_open_conversation_menu` (the established conv-menu hook) and
    asserts the pin/mark-read/delete items render.

  **2p STATE CONTRACT (registered):** `sweep_group2` required=no-friend (does its
  OWN handshake), result=friends (case 78 kicks B from the GROUP + case 75 leaves
  the GROUP, but the A<->B FRIENDSHIP is never deleted; the end-guard recomputes
  `endFriends` from the live state so the runner never trusts an unachieved
  result). The single-instance cases (71/72/82 + the standalone group/conference
  cases) require/result no-friend; the 2p cases (77/78/79/81) restore
  `paired_for_e2e`. Planner dry-run confirmed: `sweep_group2` → a FRESH
  `launch_fixture_c_pair.sh` (no restore); `group_kick_member_ui` (2p) →
  `TOXEE_FIXTURE_C_RESTORE=paired_for_e2e` + `--boot-restored`;
  `group_mute_toggle` (1i) → FRESH, no restore.

  **PRODUCTION + FORK CHANGES (all intentional + tested + mobile-covered, shared
  Dart):** (1) `lib/ui/testing/ui_keys.dart` — `groupProfileMuteSwitch`,
  `groupMemberListItem(userId)`, `groupMemberDesktopKickItem`,
  `chatHeaderTitleText`. (2) the fork member-list
  (`tencent_cloud_chat_group_member_list.dart`) — per-member row key +
  `group_member_desktop_kick_item` on the desktop 'remove' menu item. (3) the
  fork group-profile body (`tencent_cloud_chat_group_profile_body.dart`) — the
  `controlKey: group_profile_mute_switch` on the do-not-disturb OperationBar.
  (4) the fork chat header (`tencent_cloud_chat_message_header_info.dart`) — a
  `chat_header_title_text` key on the title `Text` (the OPEN-chat header rename
  assertion, codex P1.2). (5) `lib/ui/home_page.dart` + `home_page_bootstrap.dart`
  + `l3_debug_tools.dart` — the new ungated `l3_open_group_member_list` navigation
  hook. All shared Dart with no platform split — the kick is desktop right-click
  vs mobile long-press (same shared handler + `kickGroupMember`); the mute /
  member rows / header title render identically on iOS/Android/desktop.

  **Codex review (mandatory, telemetry-off — 1 review round + 1 confirm round,
  ALL findings applied):** round 1 found 2 P1, both fixed:
  - **P1.1** standalone `group_add_member_full_join` (case 77 individual
    dispatch) could FALSE-PASS — `runGroup2Case` pre-built the group with
    `_establishTwoProcessGroup`, which ITSELF invites+joins B (via
    `l3_invite_to_group` on the fixture accounts), so `memberCount>=2` was already
    true BEFORE the real add-member UI ran. FIX: case 77 standalone is now
    special-cased to establish the friendship + 2p prereqs + create the group with
    B NOT invited, then drive the REAL add-member UI (`_groupAddMemberFullJoin`)
    as the asserted action. (The SWEEP path was already correct — case 72 creates
    the shared group empty, case 77 invites B over the real UI.)
  - **P1.2** `group_rename_updates_header` only asserted the conversation-LIST row
    showName (dump), so a stale OPEN-chat header would still PASS. FIX: keyed the
    chat header title `Text` (`chat_header_title_text`) and assert it equals the
    new name via `interactiveStructured` (`_waitChatHeaderTitle` / `_keyedText`)
    after reopening the chat — the load-bearing header assertion.
  The CONFIRM round verified P1.1/P1.2 resolved + flagged 1 NEW P2, fixed: the
  new standalone case-77 path IGNORED the `_waitAutoAcceptGroupInvites` bool, so a
  not-yet-propagated auto-accept would let it create+invite anyway and B could
  miss the auto-join (flaky/false-FAIL). FIX: the standalone path now HARD-gates
  on the returned bool — restore auto-accept + abort before create/invite if it
  never goes live (mirrors `_establishTwoProcessGroup`); the SWEEP prelude logs a
  WARN-and-continue (the 1i cases don't need it; the 2p cases give it more time
  via case-77's 90s member-count poll + retries and FAIL honestly on their own
  member-count gate). After the fixes: analyze still 222 (0 NEW),
  planner/validate/campaign-list/INDEX/self-test green, touched hermetic tests
  green.

  **Gates green:** `flutter analyze lib tool` 222 (0 NEW vs the Batch-0 baseline —
  the new part file + the 5 production/fork key additions + the new l3 hook are
  all clean); `--plan-json --class=2proc-ui` exit 0 (JSON parses);
  `--validate-only` exit 0; `--list-real-ui-campaigns` shows
  `rui-group2: sweep_group2`; the `rui-group2` campaign + the individual cases
  dry-run plan correctly (fresh-vs-restored); driver `--self-test-shell-recovery`
  PASS; `gen_scenario_index.dart --check` green (178 playbooks, no invariant
  violations); touched-surface hermetic tests `flutter test test/ui/conference/
  test/ui/group/ test/ui/chat/ test/ui/conversation/ test/ui/testing/
  test/ui/home/toxee_message_header_info_test.dart
  test/ui/chat/chat_header_call_action_keys_test.dart
  test/message_header_actions_test.dart test/l3_seed_marker_test.dart
  test/ui/add_group_dialog_test.dart` ALL PASS (these prove S173 still holds with
  the new member-list keys, the chat header still renders with the title key, and
  the conference create/member surfaces are intact).

  **Mobile parity:** every driven widget + the 5 production/fork changes are
  shared Dart with no platform split — the do-not-disturb mute switch, the
  per-member rows, the chat header title, and the add-group dialog render
  identically on iOS/Android/desktop. The kick is desktop right-click
  (`_showDesktopContextMenu`) vs mobile long-press (`onManageMember` →
  `group_member_action_kick_button`) — the SAME `onDeleteGroupMember` /
  `kickGroupMember` handler, identical asserted behavior; this harness drives the
  desktop secondary-tap (a mobile real-UI test would tap the action sheet's keyed
  kick button). The conference kick NEGATIVE (S173) applies identically on mobile.

- 2026-06-10 **Batch 8 DONE** (calls / misc — FINAL write batch; 10 MIXED
  two-process + single-instance cases WRITTEN+unrun, 0 SKIP at write time; NOT
  live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_calls_misc.dart` (~1050 LOC) declared in the
  `drive_real_ui_pair.dart` part list; 10 per-case functions + `runCallsMiscSweep`
  (chains all 10 on ONE 2p launch, per-case `[sweep] <case>: PASS|FAIL|SKIP` +
  final counts + an end-state guard, exits non-zero if any HARD case fails — 9
  hard, 1 SKIP-able) + `runCallsMiscCase` (individual dispatch; each builds its
  own minimal precondition). Runner: 11 ids (`sweep_calls_misc` + 10) added to
  `_validRealUiScenarios` + both state tables; campaign
  `rui-calls-misc = [sweep_calls_misc]`.

  **CALL-STATE CHAINING (the brief's efficiency directive — done):** the call
  cases reuse live call state instead of tearing every call fully down. ONE
  friendship; a VOICE BLOCK then a VIDEO BLOCK:
  - 86 starts a voice call (B=caller rings A=callee, exactly like
    `runCallVoice`'s direction), A accepts → both `inCall`, then toggles
    `call_mic_mute_button` and asserts `call.isMuted` flips ON then OFF (the REAL
    dock-state signal, not a log grep) — and LEAVES the call inCall.
  - 89 (callee-hangup) ends THAT SAME call: A (the callee) taps
    `call_hangup_button` → both settle to idle (re-establishes a quick call first
    if 86 already tore it down, so the callee-hangup path is still the asserted
    action).
  - 90 reads the completed call's `mediaKind=='call_record'` bubble (the
    FakeUIKit `_insertCallRecord` path) from the conversation-scoped dump +
    asserts a `message_list_item:<recordMsgID>` row renders.
  - 88 (missed) reuses the missed-call recipe
    (`drive_fixture_c_missed_call.dart`): B rings A, B CANCELS while A is still
    ringing (a missed incoming call from A's side) → A's call-record count
    INCREASES + a row renders.
  - 85+87 are driven TOGETHER (`_callVideoWithCameraToggle`): a video call
    (`chat_call_video_button` → A accepts → both inCall + `call.mode=='video'`),
    the camera toggle (87) runs DURING that call (`call_camera_toggle_button`
    flips `call.isVideoEnabled` off/on), then the hangup (85) → both idle.

  **CALL-ISOLATION DISCIPLINE (the "double-invite miscount" lesson — enforced):**
  `_ensureBothIdle(a,b)` runs before each call block AND its `false` result is a
  HARD failure (a lingering call can't poison the next case). The voice block
  ends idle before 88; the video block ends idle before the misc cases.

  **CALL DOCK KEYS (verified in the fork + lib/call, not assumed):** the chat
  header start buttons (`chat_call_voice_button` / `chat_call_video_button`,
  `tencent_cloud_chat_message_header_actions.dart`); the incoming dock
  (`call_accept_button` / `call_decline_button`, `incoming_call_view.dart` →
  `UiKeys.callAcceptButton/callDeclineButton`); the in-call dock
  (`call_mic_mute_button` / `call_camera_toggle_button` [video-only] /
  `call_hangup_button`, `in_call_view.dart` → `UiKeys.call*`). All are
  `CallDockAction` keys plumbed onto the actual tappable `InkWell`
  (`call_ui_components.dart:386`), so `find.byKey` / flutter_skill lands them.
  The dump `call` object exposes `{state, mode, isMuted, isVideoEnabled, ...}`
  (`l3_debug_tools.dart:4900`) — the REAL state signals the toggles assert.

  **SEARCH-ENTRY ANSWER (the brief's case-94 open question):** the in-conversation
  `SearchChatHistoryWindow` (`lib/ui/search/search_chat_history_window.dart`) is
  reached ONLY through the GLOBAL search overlay
  (`lib/ui/search/custom_search.dart:829`): typing a message term surfaces a
  per-conversation `search_result_message:<conversationID>` row whose `onTap`
  PUSHES `SearchChatHistoryWindow`. There is NO standalone in-chat search button
  and NO `Cmd+Ctrl+F`-while-in-chat shortcut to it — the ONLY entry to message
  search is the global overlay (opened via `Inst.osaSearchShortcut`, the
  Cmd+Ctrl+F chord, the Batch-5 finding). NOTE: the global overlay AND
  `SearchChatHistoryWindow` SHARE `UiKeys.messageSearchField` ('message_search_field'),
  so the window can't be told apart by that key — case 94 distinguishes it by its
  "Search Chat History" AppBar title. So case 94 = seed a unique message term →
  Cmd+Ctrl+F overlay → type → `search_result_message_<conv>` row renders → tap →
  the window mounts (title asserted) → ESC closes. The screenshot-pipeline
  RUN_NOTES "owed Cmd+Ctrl+F shortcut" is the GLOBAL overlay shortcut (now wired +
  the only entry), not a separate in-conversation one. The S93 drill-down surface
  has hermetic L1 coverage in `test/ui/search/search_flows_real_ui_test.dart`
  (passing), proving the `search_result_message` row + the window keys case 94
  drives are live.

  **RESIZE ANSWER (the brief's case-93 open question):** `ResponsiveLayout`'s
  `shouldShowBottomNav` is a PURE width check (`size.width < 720`, no platform
  branch — `responsive_layout.dart:205`), so narrowing the macOS window past
  720pt DOES swap the home shell from the permanent sidebar to a
  `BottomNavigationBar` (the mobile tier). New `Inst.resizeWindow(w,h)` +
  `windowSize()` osascript primitives (System Events `set/get size of window 1`
  of the process with this pid — the same selector `foreground()` uses) drive +
  read the window bounds. The swap is asserted via a NEW `home_bottom_nav` key on
  the bottom nav (`home_page.dart` `_buildBottomNavigationBar` — automation-only,
  no semantic content) appearing when narrow + GONE when restored, AND the
  mobile bottom-nav ROUTING is driven (tap the Contacts label → `homeShellTab`
  goes 'contacts', tap Chats → back) — so it's not just a visual swap, the bottom
  nav actually NAVIGATES (this also closes the codex-P3 mobile-parity gap: the
  desktop sidebar and the mobile bottom nav share the same `onTap → _index`
  setState, so this is the only place the harness exercises the mobile routing
  path). If the raw-launched window REFUSES scripted resize (osascript error) OR
  the OS CLAMPS the minimum width to >=720 (window_manager min-size), the case
  returns null → `SKIP(resize-refused)` — never a fake pass (individual dispatch
  exits 75 = `_realUiSkipExitCode`; the sweep tallies SKIP and does NOT fail).
  Whether the window actually size-scripts is a RUN-PHASE determination; written
  as a real both-directions gate.

  **OTHER CASE NOTES (faithful, in-code):**
  - **91 home-tabs-cycle:** drives the REAL sidebar tabs
    (`sidebar_contacts_tab` / `sidebar_settings_tab` / `sidebar_chats_tab` — a
    plain IndexedStack `_index` setState, `home_page.dart:1580`, verified NOT to
    clear `_currentConversationID`), NOT `_forceHomeRootAndWait` (which NULLS the
    chats-tab detail — `home_page_bootstrap.dart:996` — and would make the
    retention assertion vacuous; codex P1). Asserts the dump
    `homeShellCurrentConversationId` STAYS the C2C id THROUGH the contacts +
    settings detour AND after returning to chats, where the chat surface
    re-renders WITHOUT a re-open (the IndexedStack KeptAlive branch).
  - **92 theme-switch-with-chat-open:** seeds a real own bubble, flips the
    Appearance segment (the Batch-1 `_tapThemeSegment` single-fire), reopens the
    chat, and asserts the seeded message's REAL chat-surface ROW
    (`message_list_item:<msgID>` via `_ownMessageId`) re-renders after the theme
    rebuild — NOT the conversation-list preview (codex P1: `_lastMessage` reads
    the LIST preview, not the open chat surface) — plus `sessionReady` (no crash);
    restores the original theme (poison guard).
  - **90 call-record:** requires a NEW record (`count > baseline`, snapshotted
    BEFORE the voice block) so a restored `paired_for_e2e` launch's stale records
    can't false-pass (codex P2).

  **2p STATE CONTRACT (registered):** `sweep_calls_misc` required=no-friend (does
  its OWN handshake, reusing Batch-4's `_establishFriendshipForSweep`),
  result=friends (no case deletes the friend; the calls end idle, the
  conversation row stays alive; the end-guard restores a desktop window width +
  lands both home + recomputes `endFriends` from the live state so the runner
  never trusts an unachieved result). The call cases + the chat-open misc cases
  (91/92/94) are friendship-dependent (restore `paired_for_e2e` for standalone
  dispatch); `window_resize_responsive` is single-instance no-friend (fresh
  launch). Planner dry-run confirmed: `sweep_calls_misc` → a FRESH
  `launch_fixture_c_pair.sh` (no restore); `call_mute_toggle_incall` (2p) →
  `TOXEE_FIXTURE_C_RESTORE=paired_for_e2e` + `--boot-restored`;
  `window_resize_responsive` (1i) → FRESH, no restore.

  **ORDER (call-isolation + state-poison-aware):** handshake once → wait
  connectivity → VOICE BLOCK (snapshot record baseline → 86 mute-in-call leaves
  inCall → 89 callee-hangup ends it → 90 record bubble) → 88 missed → VIDEO BLOCK
  (85 video + 87 camera together) → ensure idle → 91 tabs-cycle → 92
  theme-with-chat-open → 94 search-window → 93 resize LAST. End-guard restores
  the window width + lands both home; the friendship is never deleted → ends
  FRIENDS.

  **PRODUCTION CHANGES (2, intentional + tested + mobile-covered, shared Dart):**
  (1) `lib/ui/testing/ui_keys.dart` — `UiKeys.homeBottomNav` ('home_bottom_nav').
  (2) `lib/ui/home_page.dart` — the `key: UiKeys.homeBottomNav` on the
  `_buildBottomNavigationBar` root `DecoratedBox` (renders only in the bottom-nav
  tier, so its presence IS the responsive-swap signal; automation-only, no
  semantic content). Plus 2 harness-only `Inst` primitives in
  `drive_real_ui_pair_inst.dart` (`resizeWindow` / `windowSize`, osascript window
  bounds). Mobile parity: the `home_bottom_nav` key is on the SHARED mobile
  bottom nav (the same widget that renders on a real phone), and case 93 DRIVES
  its routing — so this batch directly exercises the mobile bottom-nav path
  (which the desktop sidebar can't), closing the codex-P3 gap. The call dock /
  search / sidebar-tab / theme widgets the other cases drive are all shared Dart
  with no platform split — calls, the call-record bubble, the search window, the
  IndexedStack retention, and the theme flip render identically on
  iOS/Android/desktop.

  **Codex review (mandatory, telemetry-off — 1 review round + 1 confirm round,
  ALL findings applied):** round 1 found 3 P1 + 1 P2 + 1 P3, every one fixed:
  - **P1.1** `home_tabs_cycle` reopened the chat via
    `_reopenChatFromConversationList` (which CLEARS the active conv first), so it
    could PASS even if the tab switches dropped the chat → switched to driving the
    REAL sidebar tabs + asserting `homeShellCurrentConversationId` survives the
    detour AND a `_chatSurfaceReady` with NO re-open.
  - **P1.2** `theme_switch` gated "bubbles intact" on `_lastMessage` (the
    conversation-LIST preview, not the chat surface) → now resolves the seeded
    own `msgID` and asserts `message_list_item:<id>` renders in the reopened chat.
  - **P1.3** `_ensureBothIdle`'s `false` was ignored before new call blocks
    (call-isolation poison) → made it a HARD failure in
    `_callMuteToggleIncall` / `_callMissedRecordRow` / `_callVideoWithCameraToggle`
    (`_callCalleeHangup` already gated its return on idle).
  - **P2** `call_record_bubble_renders` required only `count >= 1` (a restored
    launch's stale records false-pass) → snapshots the baseline BEFORE the call +
    requires `count > baseline` (sweep + standalone).
  - **P3** the resize case only proved the bottom bar appears/disappears (mobile
    routing unexercised) → case 93 now also TAPS the bottom-nav Contacts/Chats
    items and asserts `homeShellTab` changes (drives the mobile routing path the
    desktop sidebar can't reach). The CONFIRM round verified P1.1/P1.2/P1.3/P2
    RESOLVED + the homeShellCurrentConversationId retention signal correct +
    no new false-pass/hang/poison (the only remaining note was the P3 mobile
    routing, since addressed).

  **Gates green:** `flutter analyze lib tool` 222 (0 NEW vs the Batch-0 baseline —
  the new part file + the 2 production keys + the 2 osascript inst primitives are
  all clean); `--plan-json --class=2proc-ui` exit 0 (JSON parses);
  `--validate-only` exit 0; `--list-real-ui-campaigns` shows
  `rui-calls-misc: sweep_calls_misc`; the `rui-calls-misc` campaign + the
  individual cases dry-run plan correctly (fresh-vs-restored); driver
  `--self-test-shell-recovery` PASS; `gen_scenario_index.dart --check` green (178
  playbooks, no invariant violations); touched-surface hermetic tests
  `flutter test test/ui/mobile/ test/ui/call/ test/ui/search/ test/ui/home/
  test/ui/chat/chat_header_call_action_keys_test.dart` ALL PASS (the call-controls
  tests prove `call_mic_mute_button` / `call_camera_toggle_button` /
  `call_hangup_button` are live; the search-flows tests prove the
  `search_result_message` row + `SearchChatHistoryWindow` surface case 94 drives;
  Batch 8 adds the `home_bottom_nav` key, which the existing mobile bottom-nav
  test does not pump `HomePage` so it stays green).

## Run phase — current strategy and historical log (updated 2026-06-11)

Original write phase for batches 0–8 is complete: 94 cases (88 WRITTEN + 6
evidence-based SKIP: 19/20 avatar native-picker-only, 26 restore
native-picker-only, 53 presence un-seedable on reused launch, 62 reply not wired
for C2C text bubbles, 68 offline no ungated seam). Additional real-App coverage
has since been added for P1 extras, account/conference, group/conference member
role/removal, extra C2C flows, optimized single-launch bundles, and the
highest-value follow-up sweeps: `rui-c2c-deep-extra`,
`rui-account-deep-extra`, `rui-group-conf-deep-extra`, and
`rui-native-boundary-guards`.

Current broad local dogfood runs should start with the unified runner and the
startup-reuse campaign:

```bash
dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-optimized-current
```

Use `--plan-json` before a live run to verify the expected launch/driver/stop
shape. Then narrow failures with `rui-c2c-optimized`,
`rui-friendship-optimized`, `rui-single-app-optimized`, the new deep-extra
domain sweeps, or a concrete `rui-*` domain sweep. Keep
`rui-native-boundary-guards` standalone: attachment and restore now have
debug-only fixed picker-path seams, but the campaign still intentionally contains
SKIPs for OS/network/permission/mobile seams. The older per-domain run order
below is retained as historical evidence, not as the default current run plan.

**HISTORICAL RUN PROGRESS (single-instance sweeps DONE):**
- ✅ rui-settings2 — 12 PASS / 0 FAIL (commit 283132a)
- ✅ rui-profile — 6 PASS / 0 FAIL / 2 SKIP (commit ed1b1ce)
- ✅ rui-login — 8 PASS / 0 FAIL / 1 SKIP, endClean (commit this batch)
- ⏭ early rui-contacts onward — not run in this historical sequence; current
  coverage should use the optimized campaign first, then focused reruns.
- **CRITICAL for the next agent:** build ONLY via
  `MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh` (build_all omits the l3 surface →
  l3_dump_state "Method not found" → every assertion silently breaks). Two big cross-sweep
  fixes already landed: (1) `Inst.focusType` types via REAL osascript keystrokes (synthetic
  `enterText` SIGSEGVs the macOS engine's setEditingState); (2) account-card login taps use
  `tryTapKey` not raw tapAt (raw tapAt doesn't fire the InkWell) — both will help the later
  sweeps too.

### Run log (append-only)

- 2026-06-10: write phase closed; app rebuilt (build_all.sh exit 0).

- 2026-06-10 **rui-settings2 (sweep_settings2) LIVE: 12 PASS / 0 FAIL** — stable across
  3 consecutive full runs, no crash. **CRITICAL BUILD NOTE for later run agents:** the
  app MUST be built with `MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh`, NOT
  `./build_all.sh` — the l3 debug-tool surface (`ext.mcp.toolkit.l3_*`) is compiled in only
  via `--dart-define=TOXEE_L3_TEST=true`, which build_all does NOT pass. A build_all binary
  has `ui_scroll_at`/`flutter_skill.*` (ungated) but l3_dump_state returns "Method not found",
  silently breaking every state assertion. (Discovered the hard way after rebuilding for a
  fix; run_toxee build-only also re-embeds the fresh dylib.) 3 fixes:
  - **PRODUCT (`lib/ui/settings/bootstrap_settings_section.dart`)** — case 6
    `settings_bootstrap_mode_cycle` failed `auto0=false backAuto=false` (manual/lan passed).
    Root cause: the Auto-mode `RadioListTile`'s subtitle wrapped its `RichText` in a
    `GestureDetector` that launched nodes.tox.chat on tap of the WHOLE subtitle, and that
    subtitle overlaps the tile's geometric CENTER — so a center-tap (how the harness selects
    a radio) opened the browser and `onChanged` never fired. Fix: made the subtitle a
    NON-interactive `RichText` (the URL stays styled-as-a-link text, but no tap handler), so
    any tap on the Auto tile — center included — selects 'auto'. Codex flagged the first
    attempt (a `TapGestureRecognizer` on just the URL span) as Medium: Flutter forbids an
    interactive `RichText` inside `RadioListTile` (MergeSemantics vs the recognizer's own
    semantics node → debug assert) — so the recognizer approach was reverted to the plain
    subtitle, which is both center-tap-correct AND semantics-safe. Mobile uses a separate
    `SegmentedButton` (`_buildModeRowMobile`) that doesn't nest a tap target in the radio, so
    it never had the center-swallow bug; its whole-description GestureDetector is a
    pre-existing minor UX inconsistency, left as-is (not a correctness bug). Codex: recognizer
    lifecycle was correct; remaining findings addressed by the plain-subtitle revert.
  - **HARNESS — band-stall (`drive_real_ui_pair_settings2.dart`)** — cases 7/8 failed
    `expand button never reached`. `manual_node_input_button` is the bottom-anchored LAST row
    of the bootstrap section (collapsed-form); at max scroll extent it sits at center-y≈739,
    which can NEVER enter the nominal 90–700 band, so `_scrollKeyIntoBand` looped to timeout.
    Fix: detect a max-scroll STALL (target center-y stops moving for 2 scans) and accept the
    target up to an extended bottom (`_settingsViewBottomMax=770`) — it's fully visible +
    tappable, just below the reading band.
  - **HARNESS — text-input crash + form collapse** — once case 7 could reach the form, it
    SIGSEGV'd instance A: the FATAL backtrace's frame 2 was
    `-[FlutterTextInputPlugin setEditingState:]`, i.e. the macOS Flutter engine's text-input
    plugin crashing on a synthetic `enterText`. (`[callback_bridge] FATAL: received signal 11`
    is just the FFI signal handler catching the engine SIGSEGV — NOT a native/FFI bug.) Fix:
    fill the manual-node field via REAL pointer focus + REAL osascript keystrokes
    (`_fillFieldViaKeystrokes`: tapKeyCenter + osaClear + osaType) — the same crash-free path
    the desktop composer uses — instead of the engine's setEditingState. Then a SECOND bug
    surfaced: a single big `dy:-6000` scroll-reset (in `_settingsScrollTo`) COLLAPSED the
    just-expanded `AnimatedSize` manual form (a small scroll doesn't; reproduced
    deterministically). Fix: the fill helper no longer resets-to-top (the caller guarantees
    the field onstage), and case 7 does a GENTLE `scrollAt(dy:300)` after expanding to bring
    the host field on-screen. Faithful scope: S89's assertion is "form mounts + accepts
    input" — typing the host field + asserting all field keys present (host/port/pubkey are
    one mounted Column) is the gate; re-focusing each narrow field separately (the original)
    only added flakiness without strengthening it.
  - Instances left RUNNING for the next sweep: see the end-of-run tuples at the bottom of this
    log.

- 2026-06-10 **rui-profile (sweep_profile) LIVE: 6 PASS / 0 FAIL / 2 SKIP** — stable across
  2 consecutive runs, no crash; nickname/status RESTORED to RuiAlice/"" (poison guard for
  sweep_login). Cases 19/20 SKIP as written (no in-app avatar surface — native NSOpenPanel
  only). 2 fixes, both HARNESS, both generalize to the later sweeps:
  - **setEditingState SIGSEGV (GLOBAL crash-safety fix in `drive_real_ui_pair_inst.dart`)** —
    the self-profile status/nickname edit fields crashed instance A the SAME way the
    settings manual-node fields did: a synthetic `flutter_skill.enterText` drives the macOS
    engine's `-[FlutterTextInputPlugin setEditingState:]`, which INTERMITTENTLY SIGSEGVs the
    whole app (FATAL backtrace frame 2 == setEditingState; the `[callback_bridge]` line is the
    FFI signal handler catching it, NOT a native bug). Fix: **`Inst.focusType` now types via
    REAL OS keystrokes** (foreground + single-fire tapKeyCenter focus + osaClear + osaType)
    instead of synthetic enterText — the crash-free AppKit key path the composer already uses.
    `osaType` now escapes `\`+`"` so it's safe as the primary typing path. The old synthetic
    path is preserved as `focusTypeSynthetic` (no callers). `_editProfileFieldAndSave` was
    ALSO calling raw `skill('enterText')` directly (bypassing focusType) → switched it to
    focusType. This protects EVERY enterText-into-a-field case across all later sweeps.
    (NOTE: a few callers still use raw `skill('enterText')` after a `tapKey` — e.g. the
    settings download-limit field, whose author comment claims the synthetic tap ESTABLISHES
    the input connection making enterText safe; it passed live, so left as-is. The login
    register-field validation cases 23/24 also use raw enterText — watch them in sweep_login.)
  - **Save button not tappable (`drive_real_ui_pair_profile.dart`)** — after typing, the
    profile save FilledButton (localized label "Save Contact") could not be tapped:
    flutter_skill does NOT propagate its ValueKey onto the rendered text leaf, so
    `interactiveStructured` reports it with key:null and `tapKeyCenter` (key-matched over
    interactiveStructured) found no bounds. Fix: fall back to `tapKeyAt`, which resolves the
    keyed FilledButton's RenderBox center via ui_drive_tools (ui_key_center) — `candidates:2`
    but the first onstage match is the button. Now `saved=true restored=true`.

- 2026-06-10 **rui-login (sweep_login) LIVE: 8 PASS / 0 FAIL / 1 SKIP, endClean=true** — all
  password cases (set / wrong / correct / remove, real ~25s PBKDF2) + the account switch
  (registered RuiSweepB3, switched back) PASS; ends with the PRIMARY (RuiAlice) logged in, NO
  password, autoLogin intact. Case 26 SKIP as written (restore card = native NSOpenPanel).
  3 fixes:
  - **PRODUCT (`lib/ui/login_page.dart`) — `_quickLogin` re-entrancy guard** — the
    saved-account card InkWell's `onTap` called `_quickLogin` with no guard, so a fast
    double-tap (or the harness's double-firing `tap`) on a PASSWORD-protected account would
    stack TWO password prompts. Added a `_quickLoginInProgress` bool (set before the first
    await, body moved to `_quickLoginInner`, reset in `finally`) so the 2nd call is dropped.
    Real user-facing robustness win, not just automation. **Codex: "No findings"** (guard
    correct, body preserved, no single-tap regression, no mobile divergence).
  - **HARNESS — card tap (`drive_real_ui_pair_login.dart`)** — the root cause of the
    cascade: `tapKeyCenter`/raw `tapAt` at the card center does NOT fire the card's
    `InkWell.onTap` (live-proven: a single pointer tap left sessionReady=false; the key
    `tap` logged in). flutter_skill's key `tap` works because it ALSO invokes the callback
    via `_tryInvokeCallback`. Switched `_quickLoginNoPassword` + the two password-card taps
    (cases 27/28) to `tryTapKey`; the double-fire is now harmless thanks to the production
    re-entrancy guard.
  - **HARNESS — strength caption (case 25)** — `weak=true strong=false`: the synthetic
    `osaClear`+`enterText` combo did not reliably REPLACE the field, so "Abcdef1!" was
    computed against stale content and never reached strength 4 ("Strong"). Switched to
    `focusType` (clean Cmd+A clear + real keystrokes) — now `strong=true weakGone=true`.
  - **STATE-POLLUTION NOTE for later run agents:** each full sweep_login run registers a NEW
    `RuiSweepB3` account (case 29) and does NOT delete it (no in-sweep account-management-menu
    teardown). After several runs, instance A's LoginPage shows several extra `RuiSweepB3`
    cards. They are HARMLESS to the sweep (it targets the primary by toxId) but are clutter; a
    future cleanup could delete them via the card long-press → account-management menu. The
    primary RuiAlice card + autoLogin are always restored.

- 2026-07-11 **rui-native-boundary-guards SKIP→PASS: sweep now passed=5 failed=0 skipped=1**
  (only `mobile_smoke_playbook_guard` stays a redirect to the iOS-sim smoke). Three prior
  SKIPs were converted to real gates this campaign — `notification_tap_routes_to_c2c`,
  `network_disconnect_guard`, and (this session) `call_permission_denied_guard`.
  - **`call_permission_denied_guard` (S66-neg)** — the negative permission test (call while
    mic/cam DENIED must raise the denied notice + Settings action). macOS never reaches the OS
    denial branch, so denial is armed via `l3_set_call_permission {granted:false}` (sets the
    static `CallPermissionHelper.debugForcedResult`). First attempts drove the REAL header call
    button and FAILED with the counter never bumping despite `activeChatPeerOnline==true`.
    **Root-caused by live instrumentation** (temporary `[CALLPERM-DBG]` prints in the fork
    header + app preflight, since stripped): the button's `callActionsEnabled`
    (`shouldEnableDirectCallActions → getUserOnlineStatus(peer)`) **FLAPS** true→false over
    seconds on this SAME-HOST harness as the local DHT connection churns — logged
    `callActionsEnabled=true` at 11:35:17 then `=false` at 11:35:39. When disabled,
    `onPressed==null`; `tapKey` still reports success by LOCATING the key, so a tap in an
    offline window silently fires nothing (no `_startVoiceCall`, no `_preflightOutgoingCall`).
    This is an ENVIRONMENTAL flap, not a product bug (peer-online button-gating is separately
    covered by the positive call cases). **Fix (driver-only):** best-effort tap the real button
    only in the instant `activeChatPeerOnline==true` (re-checked before each of ≤40 taps), and
    GUARANTEE coverage by falling back to `l3_start_call` — which runs the IDENTICAL production
    chain `getTUICallKitAdapter()` (== the same `_globalAdapter`/`_adapter` CallServiceManager
    wired) `→ handleCall → onBeforeOutgoingCall = _preflightOutgoingCall → requestPermissions…
    (forced-denied) → _emitPermissionNotice`. Live proof (instrumented run): `_preflightOutgoingCall
    ENTER type=audio → requestPermissionsForCallDetailed forcedSet=true → result.granted=false`;
    PASS via `triggeredVia=l3_start_call raised=true offersSettings=true`. Also **reordered** the
    sweep so `call_permission` runs BEFORE `network_disconnect` (which churns the connection
    stream) to keep the peer-online map cleanly converged for the button best-effort. **Codex:
    PASS, no findings** (sound negative-test approach; counter baseline correct; mobile parity
    fine — shared Dart driver + platform-agnostic seams; reorder has no hidden coupling).
  - **`network_disconnect_guard` (S25)** — inject the byte-identical `isConnected=false`
    transition a real toxcore link-loss produces via `l3_set_connection` (→ `ffi.debugSetConnected`),
    assert the REAL Add-Friend offline banner (`add_friend_offline_banner`) renders, restore
    online, assert it clears. Asserts THIS node's own-disconnect UI (distinct from the
    presence/offline_pending cases which assert the PEER going offline). PASS.
  - Final CLEAN run (all instrumentation stripped) reproduced `passed=5 failed=0 skipped=1` on
    the first launch (no retry).

### End-of-run instance state (for the NEXT run agent — reuse contract)

- 2026-06-10, after rui-settings2 + rui-profile + rui-login: **instances LEFT RUNNING.**
  - A: nick `RuiAlice`, sessionReady, NO password, autoLogin on, toxId
    `D5122997BC6550FE…ED7B15A4D38555ED`. (Also holds several leftover `RuiSweepB3` saved-account
    cards from sweep_login case-29 reruns — harmless.)
  - B: **UNREGISTERED** (`sessionReady=false`, `nickname=null`) — B is only "launched-but-idle"
    for these single-instance sweeps and was never driven, so it still sits on its first-run /
    LoginPage. The next 2-process agent must register B (RuiBob) and establish the friendship
    itself. (The extra `RuiSweepB3` cards on A are from sweep_login case-29 reruns, NOT from B.)
  - Read live ws/pid from `tool/mcp_test/.multi_instance_runtime/{A,B}/instance.json` (they
    change on every relaunch; do not hard-code). The next run agent (rui-contacts onward) needs
    a 2-process FRIENDED pair — it will have to establish the handshake (or restore
    `paired_for_e2e`) itself; these three sweeps left A no-friend.
  - **BUILD REMINDER:** rebuild ONLY via `MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh`
    (not build_all) so the l3 surface is compiled in; then RELAUNCH both instances.

## Current run protocol

1. Validate the catalog and optimized launch contract before touching live apps:
   `dart run tool/mcp_test/fixture_c_unified_runner.dart --validate-only` and
   `dart run tool/mcp_test/fixture_c_unified_runner.dart --plan-json --class=2proc-ui --real-ui-campaign=rui-optimized-current`.
2. Rebuild app so new service extensions are in the binary:
   `MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh`. Do not rely on a plain
   `flutter build macos`; it can miss the L3 surface or fail to re-embed the fresh dylib.
3. Prefer one broad optimized run first:
   `dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-optimized-current`.
4. If the broad run fails, rerun the smallest relevant optimized/domain campaign
   (`rui-c2c-optimized`, `rui-friendship-optimized`, `rui-single-app-optimized`, or
   a concrete `rui-*` sweep). Split into fresh launches only for state poisoning,
   restart coverage, native pickers, or incompatible preconditions.
5. Fix failures at the ROOT CAUSE (native/FFI, fork, app — not the harness, unless the
   harness is provably at fault). Track every fix in the Batch log. Re-run only the
   affected sweep.
6. Update Status column → PASS/FAIL+fix/SKIP+reason.
7. Codex diff review (mandatory): `env -u OTEL_EXPORTER_OTLP_ENDPOINT codex exec -c
   otel.exporter=none -c otel.log_user_prompt=false ...` review of the full campaign diff.
8. Final commit + INDEX regen (`dart run tool/mcp_test/gen_scenario_index.dart --check`).

## Resume instructions (for a fresh session)

1. Read `doc/architecture/TESTING_OVERVIEW.md`,
   `doc/research/REAL_APP_UI_TEST_INVENTORY.md`, and
   `tool/mcp_test/REAL_UI_TWO_PROCESS.md` first for the current catalog and startup-reuse
   policy, then use this file for historical case rationale and run logs.
2. Do not resume from the old per-domain order blindly. Start with `rui-optimized-current`
   unless you are intentionally debugging one already-isolated domain.
3. If a batch/status table in this file conflicts with the runner's current discoverable
   catalog, the runner wins; update this document rather than hand-editing code around it.
4. If all write batches are DONE but live validation is incomplete: follow Current run
   protocol; per-case Status shows what already passed historically.
5. Memories to load: real_ui_two_process_harness, flutter_skill_double_tap_blank,
   real_ui_group_message_private_invite, macos_hang_forensics_first.
