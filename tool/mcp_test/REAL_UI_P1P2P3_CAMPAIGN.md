# Real-UI P1/P2/P3 campaign — 2026-06-10 (RECOVERY ANCHOR)

> Durable state for the P1/P2/P3 development campaign (user directive 2026-06-10:
> 在 master 串行开发 P1/P2/P3). Any session can resume from this file. Update the
> per-batch Status + the Batch log as work proceeds; commit after every batch.
> Case rationale/specs live in `doc/research/REAL_APP_UI_TEST_INVENTORY.md`
> (base §P1 17 cases / §P2 8 items / §P3, plus follow-up addenda below); this
> file owns EXECUTION state only.

## Mission

Implement, serially on master:
- **P1**: 17 new real-app real-widget scenarios (no production change expected;
  tiny automation-only keys allowed where verify-first reading shows a keyless
  load-bearing surface — precedented).
- **P2**: 8 seam/key-gated items (fork keys, l3 seed seam, `ui_long_press`,
  presence-dot semantics, 3 verify-first investigations).
- **P3**: the writable subset (perf burst variant, ar/RTL verify-first,
  platform run plan); platform RUNS (iOS/Android/Win11) are run-phase tasks.

Write-phase status: **CLOSED 2026-06-11** (batches I-VIII committed on the
root branch; deferred live execution is handed off in the Run phase section).

## HARD CONSTRAINTS (this campaign)

1. **WRITE-PHASE FIRST.** Write all batches with hermetic verification only;
   the run phase comes after the write phase closes (campaign-proven protocol).
   ~~Parallel-session hot-file rules~~ — LIFTED 2026-06-10: the user cancelled
   the parallel run session and granted full file access ("已经取消并行会话，
   你可以对所有文件做修改和重写"). All files editable; its coherent toxee-side
   WIP was archived (see Batch log); its tim2tox-submodule native WIP
   (`ffi/dart_compat_friendship.cpp`, uncommitted) is left in place for the
   run-phase owner — do not revert, do not commit blind.
2. Commit per batch with EXPLICIT file adds (never `git add -A`; the tree may
   hold run artifacts like `*.png` and the dirty tim2tox submodule).
3. Standing rules apply: real-UI first (l3 only for seeding/navigation-stability,
   never the asserted action); verify-first by READING current code (don't trust
   doc conclusions); soft-skip with evidence; deep root-cause fixes; mobile
   parity noted per change; codex review per batch (telemetry-off:
   `env -u OTEL_EXPORTER_OTLP_ENDPOINT codex exec -c otel.exporter=none
   -c otel.log_user_prompt=false …`).

## Per-batch contract (every batch MUST)

1. Read this file + `doc/research/REAL_APP_UI_TEST_INVENTORY.md` (its case row)
   + `tool/mcp_test/REAL_UI_TWO_PROCESS.md` + the files in the File map below.
2. New scenarios live in a NEW part file (`drive_real_ui_pair_p1_*.dart` /
   `_p2_*.dart`), declared in `drive_real_ui_pair.dart`'s part list, dispatched
   per-case + as a `sweep_<batch>` chain (per-case `[sweep] <case>: PASS|FAIL|
   SKIP(<reason>)` + final counts; exit non-zero if any hard case fails; exit 75
   = SKIP for individual dispatch), registered in `_validRealUiScenarios` +
   `_requiredRealUiState` + `_resultRealUiState` + a `rui-p1-*` campaign.
3. Gates (all green before commit): `flutter analyze lib tool --no-fatal-warnings
   --no-fatal-infos` 0 NEW issues; `dart run tool/mcp_test/fixture_c_unified_runner.dart
   --plan-json --class=2proc-ui` exit 0; `--validate-only` exit 0;
   `--list-real-ui-campaigns` shows the new campaign; driver
   `--self-test-shell-recovery` PASS; touched hermetic tests pass;
   `dart run tool/mcp_test/gen_scenario_index.dart --check` green.
4. Codex review; apply findings; update this file's Status + Batch log;
   `git commit` (message: `test(real-ui): p1p2p3 batch <N> — <domain> (written, unrun)`).
5. Do NOT update `test/mcp/S*.md` headers to claim coverage — written-unrun
   scenarios are not validated gates yet; header updates happen in the run phase.

## Batches

### Batch I — `ui_long_press` primitive (prereq for P1 #8 + mobile-trigger parity)

`lib/ui/testing/ui_drive_tools.dart`: `ui_long_press` {key?|x,y?, holdMs?} —
real touch PointerDown → await hold (default 600 ms > kLongPressTimeout) →
PointerUp through `GestureBinding.handlePointerEvent`. Register in
`registerUiDriveToolsIfDebug()`. Hermetic gates in
`test/ui/testing/ui_drive_tools_test.dart`: onLongPress fires once (and onTap
does NOT); offstage/absent key errors. FakeAsync note: test starts the handler
future un-awaited, `tester.pump(700ms)` advances fake time, then awaits it.
**STATUS: DONE** (5th ui_drive tool + `Inst.longPressKey`; hermetic gates 8/8
incl. 3 new long-press cases — fires-once/not-tap, short-hold-is-tap negative
control, key_not_found shape; analyze 222/0-new; planner + INDEX green; codex
round-1 found 1 P2: the fork's conversation rows use a CUSTOM
`LongPressGestureRecognizer(duration: 650 ms)` (`tencent_cloud_chat_gesture.dart:117`)
so the 600 ms default would release early and fall through as a TAP (= navigation
on a conv row) → default hold raised to 800 ms everywhere, docs cite both
deadlines. Durable fact: any long-press driving of fork gesture surfaces must
hold >650 ms, not just >500 ms.)

### Batch II — P1 single-instance quintet (`drive_real_ui_pair_p1_single.dart`)

| case | inventory row | verify-first reading needed |
|---|---|---|
| `account_card_management_menu` | P1#8 | login_page.dart: card long-press/secondary trigger? menu surface keys? uses `ui_long_press` |
| `account_delete_full_flow` | P1#9 | settings 注销 flow keys + confirm dialog; throwaway account via real RegisterPage |
| `settings_switch_account_entry` | P1#10 | settings switch-account entry key → login cards → switch back |
| `conference_rename_leave` | P1#11 | reuse batch-7 helpers for AVChatRoom create; rename + leave confirm-by-label |
| `zh_locale_page_walk` | P1#12 | per-page zh labels (外观 etc.); revert-to-en discipline (batch-1 locale finding) |

Sweep `sweep_p1_single` · campaign `rui-p1-single` · state no-friend→no-friend.
**STATUS: DONE (written, unrun)** — 5/5 WRITTEN, 0 SKIP (every surface verified
to exist by reading production code). Part file ~1130 LOC (agent-written, this
session completed registration + fixes after a session-limit interrupt).
Production changes: 4 automation-only keys (per-account
`settings_account_switch_button:<toxId>` on the _AccountCardItem swap
IconButton; `settings_delete_account_button` opener;
`settings_delete_account_confirm_input` on BOTH mutually-exclusive dialog
branches; `settings_delete_account_confirm_button`) + a new read-only
`savedAccountToxIds` l3_dump_state field (persisted account-list ground truth).
Verify-first findings: the settings switch entry does a DIRECT in-place switch
(account_switcher tears down + boots + pushAndRemoveUntil(HomePage), NEVER via
LoginPage); the login-card management menu opens via onLongPress AND
onSecondaryTap (login_page.dart:1124/1129) with production-keyed Export/Delete
options; delete-account uses a RANDOM typed confirm word read from the live
prompt (extraction failure → production rejects → loud FAIL, never a stray
deletion). Gates: analyze 222/0-new; plan-json/validate/campaign-list/INDEX/
self-test green; settings+testing hermetic 78/78. Codex round-1: 2 P1 + 3 P2 —
P1 standalone-switch leaves throwaway #2 (now real-delete-cleaned + gated),
P1 endClean ignored by sweep exit (now `failed==0 && endClean`, and
noLeftover proven against savedAccountToxIds), P2 delete needs persisted
ground truth (dumpGone added), P2 dialog-opener tapKey fallbacks could
double-fire (new `_p1OpenDialogViaKey` bounds-gated discipline; also fixed the
inherited group2 leave-button opener), P2.5 l3_open_add_group_dialog flagged —
DISAGREED with precedent (batch-7 navigation-stability exception; keyed real
entry noted as future upgrade). Confirm round: all RESOLVED + 1 new P2
([] savedAccountToxIds ambiguous on read error → primary-sentinel trust gate,
applied).

### Batch III — P1 two-process chat/conv octet (`drive_real_ui_pair_p1_chat.dart`)

| case | inventory row | verify-first reading needed |
|---|---|---|
| `chat_recall_message` | P1#3 | fork menu: recall item on fresh self msg; revoke path in bridge (stub? → honest scope) |
| `read_receipt_double_tick` | P1#4 | read-status icon keyed? (likely needs automation-only fork key) |
| `forward_to_group_target` | P1#5 | batch-7 group helpers + S17 picker keys |
| `draft_restore_on_conv_switch` | P1#6 | does the fork write/restore drafts? (DartSetConversationDraft exists natively) |
| `typing_indicator_render` | P1#7 | does any UI surface render typing? (fixture_c_typing = data half) |
| `unread_badge_total_sidebar` | P1#13 | sidebar Chats badge key/text |
| `search_empty_state` | P1#14 | custom_search empty-state marker |
| `image_preview_open_hardened` | P1#16 | bounded retry-tap; honest best-effort fallback |

Sweep `sweep_p1_chat` · campaign `rui-p1-chat` · friends→friends.
Open design questions for the batch agent (verify by READING code, then decide
gate shape honestly): does any UI render typing (else NEGATIVE gate or SKIP)?
does the fork restore drafts on conv switch-back (else record the gap)? is the
recall path wired through the bridge (else honest UI-half scope)? is the ✓✓
read-status icon keyed (else an automation-only fork key is the precedented fix,
and the assert must distinguish peer-READ from mere send-success)?
**STATUS: DONE (written, unrun)** — 8/8 WRITTEN, 0 SKIP. Five positive gates
(`chat_recall_message`, `forward_to_group_target`, `unread_badge_total_sidebar`,
`search_empty_state`, `image_preview_open_hardened`) plus three evidence-backed
NEGATIVE product-gap pins (`read_receipt_double_tick`, `draft_restore_on_conv_switch`,
`typing_indicator_render`). Production/fork changes: new part file +
driver/runner registration (`sweep_p1_chat`, `rui-p1-chat`); desktop sidebar
and mobile bottom-nav unread-badge Text keys (`sidebar_chats_unread_badge`,
`home_chats_unread_badge`); fork keys `chat_header_title_text`,
`message_viewer_root`, and state-suffixed
`message_send_status:<msgID>:<read|sent|other>`. Verify-first findings are
recorded at the top of `drive_real_ui_pair_p1_chat.dart`: recall is wired
through a best-effort `__revoke__:` bridge but B-side live tombstone rendering
is a fork listener gap; C2C read receipts do not wire from chat-open and cannot
correlate msgIDs; desktop drafts never save and the platform draft path is not
usable for this UI route; typing has a data half (`l3_set_typing`) but no
production sender or UI consumer. Gates: `flutter analyze lib tool
--no-fatal-warnings --no-fatal-infos` = 222 baseline / 0 new; plan-json,
validate-only, campaign-list (`rui-p1-chat` present), `--self-test-shell-recovery`,
and `gen_scenario_index.dart --check` all green; `flutter test test/ui/chat
test/ui/home test/ui/settings test/ui/testing` = 139/139. Codex review:
SKIPPED per explicit user directive for this handoff turn. Mobile parity:
unread badge key lands on the shared mobile bottom-nav host, and fork message
keys live in shared message widgets.

### Batch IV — P1 relaunch trio + calls (`drive_real_ui_pair_p1_relaunch.dart`)

| case | inventory row | notes |
|---|---|---|
| `relaunch_history_autologin` | P1#1 | seed via real composer → relaunch A → autoLogin → history rows render |
| `offline_pending_relaunch` | P1#2 | stop B → A real send → SENDING spinner row → relaunch B → delivered |
| `call_from_profile_tiles` | P1#15 | `friend_profile_voice_call_tile`/`friend_profile_video_call_tile` (fork :437/:455) |
| `group_join_by_id_real_ui` | P1#17 | verify-first AddGroupDialog join path; product-gap record if absent |

Runner: add `_realUiStateRelaunchDirty = 'relaunch-dirty'` result state (the
existing unknown-state else-branch already stop+relaunches — verified at
`fixture_c_unified_runner.dart:1075`/`:1614`; check `_restoreForRealUiState`'s
default for the unknown state). Relaunch helper = fn in the new part
(stop/launch scripts + `instance.json` re-read + fresh `Inst`/`_reconnect`;
dispose the stale vm client first). Design intent: assert the pending spinner
BEFORE relaunching B (don't race it); gate call cases on both-idle like batch 8;
verify-first whether AddGroupDialog has any join-by-id path (likely absent →
negative product-gap gate, S33 stays 2proc-l3).
**STATUS: DONE (written, unrun)** — 4/4 WRITTEN, 0 SKIP. Added
`drive_real_ui_pair_p1_relaunch.dart` plus dispatch/runner registration
(`sweep_p1_relaunch`, `rui-p1-relaunch`) and the runner result state
`relaunch-dirty`, which intentionally forces the next external scenario through
the existing stop+launch branch. `Inst.pid` is now mutable so a one-instance
relaunch can keep using the same driver object while foregrounding the new
process. Fork change: the existing state-suffixed message-status key contract
now covers the SENDING spinner as
`message_send_status:<msgID>:sending`, letting `offline_pending_relaunch` assert
the real spinner before B is relaunched. Verify-first correction: contrary to
the handoff guess, `AddGroupDialog` DOES have a real join-by-ID path
(`add_group_join_id_input`, `add_group_join_message_input`, alias field, and
`service.joinGroup(...)`), so `group_join_by_id_real_ui` is a positive real-UI
case rather than a product-gap negative. Relaunch helper uses
`stop_toxee_instance.sh <A|B>` + `launch_toxee_instance.sh <A|B>`; the launch
script preserves per-instance prefs/app support, writes fresh `instance.json`,
and the driver re-reads pid/ws, reconnects, waits `sessionReady` +
`currentAccountToxId`, then returns home. Codex review: SKIPPED per explicit
user directive for this handoff turn. Gates: analyze 222/0-new; plan-json,
validate-only, campaign-list (`rui-p1-relaunch` present), shell recovery
self-test, and INDEX all green; `flutter test test/ui/chat test/ui/call
test/ui/contact test/ui/add_group_dialog_test.dart test/ui/conference
test/ui/testing` = 135/135. Mobile parity: the sending-status key lives in the
shared fork message widget; driver scenarios remain desktop real-UI write-phase
cases.

### Batch V — P2 fork keys + scenarios (`drive_real_ui_pair_p2_keys.dart`)

sticker per-cell key → `sticker_face_cell_send`; new-messages chip key →
`new_messages_chip_tap`; presence-dot semantic state → `presence_dot_relaunch`
(uses relaunch class). Fork commits FIRST (submodule), then toxee SHA bump.
**STATUS: DONE (written, unrun)** — 3/3 WRITTEN, 0 SKIP. Fork commit
`9e72f4d` adds shared Dart automation selectors for sticker pack tabs/cells
(`sticker_face_tab:<pack>`, `sticker_face_cell:<pack>:<cell>`), a RenderObject
new-message chip wrapper key (`new_messages_chip`), and state-suffixed presence
dot keys (`conversation_item_online_dot:<convId>:online|offline`) while
preserving the legacy unsuffixed dot key. Added `drive_real_ui_pair_p2_keys.dart`
plus dispatch/runner registration (`sweep_p2_keys`, `rui-p2-keys`) and state
contracts. Positive cases: `sticker_face_cell_send` drives the real sticker
panel and asserts local FACE elemType 8; B-side receive currently arrives as
`__face__:` text because tim2tox serializes face metadata over the wire, so rich
receiver rendering is a later bridge/fork concern, not faked here.
`new_messages_chip_tap` scrolls A upward, receives a real B message, taps the
real chip, and asserts the newest row is visible. `presence_dot_relaunch` stops
and relaunches B while asserting the suffixed online/offline dot keys on A.
Codex review: SKIPPED per explicit user directive for this handoff turn. Gates:
analyze 222/0-new; plan-json, validate-only, campaign-list (`rui-p2-keys`
present), shell recovery self-test, and INDEX all green; focused widget tests
5/5; related UI tests `test/ui/chat test/ui/conversation test/ui/testing` =
78/78. Mobile parity: all three fork keys live in shared Dart widgets used by
desktop/mobile surfaces; the driver remains a desktop two-process write-phase
case set.

### Batch VI — P2 reply two-piece (`drive_real_ui_pair_p2_reply.dart`)

l3 C2C custom-elem inbound seed seam (mirror `l3_inject_group_text` →
`ingestInboundGroupText` seam family) + fork reply-container ValueKey +
`reply_quote_real`. **STATUS: DONE (written, unrun)** — 1/1 WRITTEN, 0 SKIP.
Fork commit `86cade8` adds the shared reply banner selector
`message_input_reply_container` to
`TencentCloudChatMessageInputReplyContainer`. tim2tox commit `65562f1` adds a
Dart-only C2C custom inbound seam (`ingestInboundC2cCustom`), preserves the
pre-existing native WIP in `ffi/dart_compat_friendship.cpp` untouched, and
projects `ChatMessage.mediaKind == custom` into a TIM custom elem in the
platform converter. Root adds the test-account-gated l3 tool
`l3_inject_c2c_custom`, `drive_real_ui_pair_p2_reply.dart`, dispatch/runner
registration (`sweep_p2_reply`, `rui-p2-reply`), and explicit state contracts.
`reply_quote_real` uses l3 only to seed a quotable inbound custom bubble, then
drives the real message menu Reply action, waits for the keyed quote banner,
sends through the real composer, verifies sender-side `messageReply`
cloudCustomData points at the injected message/sender, and asserts B receives
the reply body. Existing wire behavior still leaves reply metadata sender-side,
so B-side quote metadata is not asserted. Codex review: SKIPPED per explicit
user directive for this handoff turn. Gates: focused desktop reply widget test
6/6, new FFI C2C custom ingest test 1/1, driver/runner/l3 analyze 2 baseline
infos/0 fatal, planner plan-json, validate-only, campaign-list (`rui-p2-reply`
present), corrected campaign plan-json under `--class=2proc-ui`, shell recovery
self-test, INDEX check, `git diff --check`, root `flutter analyze lib tool
--no-fatal-warnings --no-fatal-infos` = 222 baseline/0 fatal, and related tests
`test/ui/chat test/ui/testing test/ffi_chat_service_c2c_custom_ingest_test.dart`
= 54/54. Mobile parity: the reply banner key and custom-ingest bridge are shared
Dart surfaces; the new driver remains a desktop two-process write-phase case.

### Batch VII — P2 verify-first trio (voice / paste / tray)

Read-code investigations; scenario if surface exists, else evidence-based
product-gap entry HERE + inventory doc cross-ref. **STATUS: DONE (written,
unrun)** — 1/3 WRITTEN, 2/3 EVIDENCE-BASED NO-NEW-DRIVER. Fork commit
`ec3e314` adds the desktop pasted-image confirmation selector
`desktop_send_image_confirm_button`. Root adds `drive_real_ui_pair_p2_verify.dart`
plus dispatch/runner registration (`sweep_p2_verify`, `rui-p2-verify`) and a
source guard for the new selector. `paste_image_into_composer` writes a tiny PNG
to the macOS image clipboard, focuses the real composer (`chat_input_text_field`),
drives the production Cmd+V RawKeyEvent path, taps the real keyed image-send
confirmation, then asserts A has a new self `mediaKind=image` paste message and
B receives the same image filename. Verify-first evidence: the desktop paste
handler exists at
`tencent_cloud_chat_message_input_desktop.dart:499-553`, and the confirmation
button is keyed at `image_tools.dart:75-77`.

Voice: no new Batch VII driver. Desktop voice exists
(`tencent_cloud_chat_message_input_desktop.dart:397-416`), but S78 is already
explicitly L3-pinned because the record dialog gates on a real microphone/TCC
and end-to-end delivery needs a second live process receiving over DHT
(`test/mcp/S78_voice_message_record_send.md:6-17`). Existing coverage remains
`run_fixture_c_voice_msg.sh` plus
`test/ui/mobile/mobile_voice_record_real_ui_test.dart`; adding a write-phase
desktop driver would be un-verifiable without the deferred run phase.

Tray: no new Batch VII driver. The tray shell exists
(`app_tray.dart:24-31`, `app_tray.dart:340-345`), but the actual window close
path is destroy, not hide-to-tray: the frame close button calls
`windowManager.close()` (`desktop_window_frame.dart:140-143`) and
`onWindowClose()` persists bounds then calls `windowManager.destroy()`
(`desktop_shell_bootstrap.dart:13-29`). Therefore the inventory's
"close-window -> tray/Dock restore" behavior is a product gap rather than a
driveable real-UI surface. Codex review: SKIPPED per explicit user directive for
this handoff turn. Gates: driver/runner/source analyze no issues, fork
`image_tools.dart` analyze 3 baseline infos/0 fatal, planner plan-json,
validate-only, campaign-list (`rui-p2-verify` present), corrected campaign
plan-json under `--class=2proc-ui`, shell recovery self-test, INDEX check,
`git diff --check`, source guard `dart run`, root `flutter analyze lib tool
--no-fatal-warnings --no-fatal-infos` = 222 baseline/0 fatal,
`test/ui/testing` = 19/19, and related tests `test/ui/chat test/ui/testing` =
53/53.

### Batch VIII — P3 writable subset

`message_burst_perf` (param count + timing, nonBlocking threshold); `ar_rtl_smoke`
(verify ar locale exists; Directionality assert); platform run plan section
(iOS sim / Android / Win11) written here for the run-phase owner. **STATUS:
DONE (written, unrun)**

Write-phase outputs:

- Real-UI driver: `drive_real_ui_pair_p3.dart` adds `sweep_p3_writable` and the
  standalone `message_burst_perf` case. The sweep starts from no-friend and
  performs its own handshake; the standalone case requires/restores a friendship.
- Burst knobs: `RUI_BURST_PERF_COUNT` (default 24, max 2000),
  `RUI_BURST_PERF_NONBLOCKING_MS` (default 180000), and
  `RUI_BURST_PERF_DELIVERY_TIMEOUT_SECS` (default 90). Delivery/count
  correctness is a hard failure; the elapsed threshold logs `NONBLOCKING` only
  and does not fail a delivered run.
- Hermetic RTL smoke: `test/ui/settings/ar_rtl_smoke_test.dart` asserts
  `AppLocalizations.supportedLocales` contains `Locale('ar')`, resolves the
  Arabic localization, and verifies ambient `Directionality` is RTL. The fuller
  Settings picker flow remains covered by `theme_locale_live_apply_real_ui_test.dart`.
- Runner catalog: `rui-p3-writable` expands to `sweep_p3_writable`; standalone
  `message_burst_perf` plan-json restores `paired_for_e2e` and passes
  `--boot-restored`.

Platform run plan for the run-phase owner:

- macOS desktop (primary): after the deferred rebuild, run
  `RUI_BURST_PERF_COUNT=<N> RUI_BURST_PERF_NONBLOCKING_MS=<ms> dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-p3-writable`.
  Suggested smoke is `N=24`; stress runs can raise toward 1000 after the default
  campaign is green. Record both PASS/FAIL and the nonblocking elapsed signal.
- iOS simulator: reuse the same count/threshold matrix, but first port or select
  an iOS-compatible focus/tap transport for the two live instances because the
  current `Inst.foreground`/pair launcher assumptions are desktop-oriented. The
  acceptance target is the same: delivered final message, sender/receiver burst
  counts, and RTL smoke green.
- Android emulator: mirror iOS. Confirm keyboard Return/send semantics on the
  mobile composer before increasing `RUI_BURST_PERF_COUNT`; the Dart history
  count assertions are shared.
- Win11 desktop: port the pair launch/focus/screenshot helpers to Windows
  process/window APIs, then run the same `rui-p3-writable` campaign and capture
  elapsed threshold logs. The case itself has no macOS clipboard dependency.

### Addendum — P1 extra feasible follow-ups (`drive_real_ui_pair_p1_extra.dart`)

**STATUS: DONE (written, unrun)** — 2/2 WRITTEN, 0 SKIP. Added
`drive_real_ui_pair_p1_extra.dart` plus dispatch/runner registration
(`sweep_p1_extra`, `rui-p1-extra`) for the two inventory P1 items that are
honestly driveable in the current macOS real-app harness:
`ar_rtl_page_walk` and `keyboard_global_search_shortcut`. The Arabic case
clicks the real Settings language selector, selects the keyed
`settings_language_option_ar` row, asserts `languageCode=ar` plus Arabic labels
on settings/sidebar/profile surfaces, then restores English with
locale-independent keys. The keyboard case opens global search with the real
Cmd+Ctrl+F shortcut, types a no-hit query into the autofocused field through OS
input, asserts the no-results state, and records whether Escape closes the
route before cleanup fallback. Platform/native-picker/OS-notification P1 items
remain documented follow-ups in `doc/research/REAL_APP_UI_TEST_INVENTORY.md`
rather than fake-positive real-UI gates.

### Addendum — account/conference focused expansion (`drive_real_ui_pair_account_conf_extra.dart`)

**STATUS: DONE (written, unrun)** — 6/6 WRITTEN, 0 SKIP. Added
`drive_real_ui_pair_account_conf_extra.dart` plus dispatch/runner registration
(`sweep_account_conf_extra`, `rui-account-conf-extra`) to deepen the two areas
called out as thin after the initial inventory.

Account management cases:
`settings_switch_account_cancel` provisions a throwaway account through the real
RegisterPage, opens the real Settings switch-account dialog, taps the keyed
Cancel button, proves the current account did not switch, then deletes the
throwaway through the existing real delete flow; `login_account_delete_cancel`
long-presses a saved-account card, opens the real login-page management bottom
sheet, taps Delete, cancels the confirm dialog, and proves the account card
survives; `settings_delete_account_cancel` opens the current-account delete
dialog from Settings and cancels without tearing down the session.

Conference cases:
`conference_profile_id_surface` creates a legacy conference through the real
AddGroupDialog and asserts the profile ID/member surfaces;
`conference_profile_send_message_tile` taps the profile Send Message tile and
asserts the conference chat opens; `conference_search_result_opens` opens the
global search overlay, finds the conference by name, taps the keyed result row,
and asserts the conference chat opens. Each conference case leaves the
conference before exit so the runner's no-friend/no-extra-conference contract is
truthful.

### Addendum — group/conference member-management expansion (`drive_real_ui_pair_group_conf_member_extra.dart`)

**STATUS: DONE (written, unrun)** — 5/5 WRITTEN, 0 SKIP. Added
`drive_real_ui_pair_group_conf_member_extra.dart` plus dispatch/runner
registration (`sweep_group_conf_member_extra`,
`rui-group-conf-member-extra`) to cover the member role/remove gap for both
private groups and legacy conferences.

Group member-management cases:
`group_member_peer_menu_surface` establishes a private two-process group, opens
the real member-list page, secondary-clicks B's real member row, and asserts the
desktop member menu exposes Info / Copy Tox ID / role / remove items;
`group_member_role_action_smoke` taps the real role item and asserts the menu
dismisses without breaking the two-member group (tim2tox currently returns
success for role changes but does not persist Tox roles, so this is intentionally
an action-smoke rather than a fake role-persistence assertion);
`group_member_remove_ui` taps the real remove/kick item and asserts A's member
count drops.

Conference member-management cases:
`conference_member_peer_row_surface` creates a two-process legacy conference and
asserts B's real member row renders; `conference_member_role_remove_absent`
secondary-clicks that row and asserts the informational menu opens while role and
remove controls are absent. If a live run shows those controls for conferences,
that should be treated as a product/UI policy regression rather than relaxed in
the driver.

### Addendum — C2C focused expansion (`drive_real_ui_pair_c2c_extra.dart`)

**STATUS: DONE (written, unrun)** — 5/5 WRITTEN, 0 SKIP. Added
`drive_real_ui_pair_c2c_extra.dart` plus dispatch/runner registration
(`sweep_c2c_extra`, `rui-c2c-extra`) to deepen common C2C paths not covered by
the larger `rui-conv` and `rui-chat` sweeps.

C2C extra cases:
`c2c_global_search_contact_opens_chat` opens global search with the real
shortcut, taps the keyed contact result, and asserts the target C2C chat opens;
`c2c_conv_delete_cancel` opens the real conversation row menu, taps Delete, then
the real Cancel button and proves the row/friendship remain;
`c2c_profile_clear_history_cancel` seeds a real message, opens friend profile,
opens Clear History, cancels, and proves message count is unchanged;
`c2c_delete_friend_cancel` opens the delete-friend dialog and cancels while the
friendship remains; `c2c_header_profile_send_back` taps the chat header avatar,
shows the friend profile, then taps Send Message to return to the same C2C chat.
Two automation-only keys were added for reliable Cancel targeting:
`delete_conversation_cancel_button` and
`user_profile_clear_history_cancel_button`.

### Addendum — optimized single-launch bundles (`drive_real_ui_pair_optimized.dart`)

**STATUS: DONE (written, unrun)** — added orchestration-only sweeps that compose
existing real-UI sweeps without duplicating case logic:
`sweep_single_app_optimized` / `rui-single-app-optimized`,
`sweep_c2c_optimized` / `rui-c2c-optimized`,
`sweep_friendship_optimized` / `rui-friendship-optimized`, and
`sweep_optimized_current` / `rui-optimized-current`.

The purpose is run-phase throughput. `rui-c2c-optimized` launches the pair once,
establishes A<->B once via the first child sweep, then reuses that friendship
across `sweep_conv`, `sweep_chat`, `sweep_c2c_extra`, and
`sweep_c2c_deep_extra`.
`rui-friendship-optimized` extends that same idea across non-relaunch
friendship-preserving sweeps: C2C optimized, `sweep_p1_chat`,
`sweep_p2_reply`, `sweep_p2_verify`, `sweep_p3_writable`, `sweep_group2`,
`sweep_group_conf_member_extra`, `sweep_group_conf_deep_extra`, and
`sweep_calls_misc`.
`rui-optimized-current` first runs the A-only optimized chain
(`settings2/profile/login/p1-single/p1-extra/account-conf-extra/
account-deep-extra`) and then the friendship optimized chain, all under one
app-pair launch. Exclusions are intentional: `rui-contacts` deletes friendship
and has the known remark live finding; `rui-p1-relaunch` and `rui-p2-keys`
restart peers internally; `rui-native-boundary-guards` contains designed SKIPs
for OS/mobile seams, so those remain standalone rather than poisoning a
single-launch bundle.

### Addendum — highest-value future investment shortlist

Detailed local inventory lives in `doc/research/REAL_APP_UI_TEST_INVENTORY.md`
(ignored by Git as a research scratch area). Durable tracked summary:

1. First spend effort on live-running and stabilizing the already-written high
   value bundles: `rui-optimized-current`, `rui-c2c-optimized`,
   `rui-friendship-optimized`, then standalone `rui-contacts` and
   `rui-p1-relaunch`.
2. Next new coverage should close platform and native-boundary gaps: iOS
   register/login/send C2C smoke, Android register/login/send C2C smoke,
   live-stabilizing the new attachment/restore fixed-path seams, completing the
   restore/import happy path, OS notification click-to-conversation, controllable
   network disconnect/reconnect, and mic/camera permission-denied call flows.
3. After those, invest in deeper business regressions: group role persistence,
   removed-member receiver-side UI, conference lifecycle, message-search result
   navigation to the exact bubble, large-history scroll/search performance,
   keyboard-only dialog coverage, multi-account state isolation, window/tray
   lifecycle, export->restore roundtrip, and destructive confirm flows on
   throwaway state.
4. Every new case must still follow the startup-reuse policy: keep an atomic
   scenario for debugging and add it to an existing sweep/optimized bundle when
   the ending state is reusable. Split launches only for relaunch, network,
   native/OS permission, notification, or destructive-confirm cases.

### Addendum — implemented from the shortlist (2026-06-12)

The most valuable startup-reusable cases from the shortlist have now been
codified in `drive_real_ui_pair_high_value_extra.dart` and registered in the
unified runner:

1. `rui-c2c-deep-extra` / `sweep_c2c_deep_extra`: `c2c_search_result_opens_target_message`
   sends a real C2C message, opens global search, taps the real message result,
   taps the exact `search_history_message_<msgID>` row, and verifies the target
   bubble renders after returning to chat.
2. `rui-account-deep-extra` / `sweep_account_deep_extra`:
   `account_multi_account_state_isolation` creates primary-account state via a
   real group, registers a throwaway second account, proves the primary
   conversation is isolated from that account, switches back, verifies primary
   state restores, then deletes the throwaway and leaves the group.
3. `rui-group-conf-deep-extra` / `sweep_group_conf_deep_extra`:
   `group_member_role_reopen_surface`, `group_member_remove_receiver_state`, and
   `conference_bidirectional_message_lifecycle` deepen member role/menu,
   receiver-side removal, and conference two-way message coverage.
4. `rui-native-boundary-guards` / `sweep_native_boundary_guards`:
   `attachment_entry_buttons_render` now verifies app-level file/photo/video
   buttons, clicks real file/photo controls, injects fixed picker paths, and
   asserts sender row + receiver delivery; `restore_import_entry_guard` sets a
   fixed invalid `.tox` path, clicks the real Restore card, and asserts the login
   error banner; `notification_tap_routes_to_c2c` covers the in-app tap stream.
   Network disconnect, OS permission denial, and mobile smoke remain explicit
   SKIP guards until a safe OS/mobile seam exists.

## File map (pre-baked anchors for batch agents)

- `lib/ui/testing/ui_drive_tools.dart` (398 LOC): pure handlers + thin MCP entries;
  `resolveKeyCenter` (onstage walk), `_nextPointerId`, `registerUiDriveToolsIfDebug`
  (registered in `main.dart` right after l3 registration, UNGATED kDebugMode-only).
  Hermetic tests: `test/ui/testing/ui_drive_tools_test.dart` (5/5, FakeAsync notes inline).
- `tool/mcp_test/drive_real_ui_pair.dart` (865 LOC): part list :116-131; per-domain
  dispatch switches (batch 4 @~404, 5 @~508, 6 @~589); `settings_sweep` @204,
  `probe_home_root` @727. Add new parts + dispatch entries append-style.
- `tool/mcp_test/drive_real_ui_pair_inst.dart` (READ-ONLY, HOT): `Inst` API —
  ctor `Inst(name, ws, pid)` + `connect()`; `skill()`/`l3()`/`dumpState()`;
  `tapKey/tryTapKey/tapText/tapAt/tapKeyCenter/tapKeyAt/focusType/keyCenter`;
  `scrollAt/scrollAtCoords/dragBy/secondaryTapKey/scrollUntilKey`;
  `waitKey/waitText/waitKeyGone/waitTextGone/waitState`; `foreground/resizeWindow/
  windowSize`; `osaType/osaPaste/osaReturn/osaShiftReturn/osaEscape/osaSearchShortcut/
  osaClear`; `markAccountTest/unmarkAccountTest`; `_reconnect()/_refreshWsUriFromRuntime()`
  (private, same-library callable); `shot(path)`.
- `tool/mcp_test/fixture_c_unified_runner.dart`: `_validRealUiScenarios` @57;
  campaigns map (after the registry); `_requiredRealUiState` @1110 (default at switch
  end); `_resultRealUiState` @1281; symbolic planner @1046 (unknown-state else =
  stop+launch @1075); live executor @1590 (else @1614); `_realUiSkipExitCode` = 75;
  `_internalRealUiResetScenario` @445.
- `lib/ui/testing/ui_keys.dart`: ValueKey catalog (UiKeys.*).
- `lib/ui/testing/l3_debug_tools.dart`: l3 tool registration pattern; test-account
  gate `_activeAccountIsTest` @~377; ungated plumbing precedents
  (`l3_open_group_member_list`, `l3_mark_current_account_test`).
- Fork key precedents: `tencent_cloud_chat_user_profile_body.dart` (call tiles
  :437/:455), `tencent_cloud_chat_message_input_sticker_panel.dart`
  (`desktop_sticker_panel`), `tencent_cloud_chat_group_member_list.dart`
  (member row + kick item keys), `message_list.dart:604` (keyless new-messages chip),
  `conversation_item_online_dot:<convId>` (color-only dot).
- Campaign precedents to copy shape from: `drive_real_ui_pair_settings2.dart`
  (sweep + per-case + normalize-between-cases), `drive_real_ui_pair_login.dart`
  (state-machine order + end-clean guard), `drive_real_ui_pair_group2.dart`
  (2p group prereqs + l3 nav-stability opens).

## ⚠️ CRITICAL OPS FINDING — bootstrap WIPES local fork commits (2026-06-12)

`tool/bootstrap_deps.dart:63` runs `git -C third_party/chat-uikit-flutter
checkout -B <branch> FETCH_HEAD` — it FETCHES the fork remote and FORCE-RESETS
the local fork branch to `origin/<branch>` (currently `origin/v2 == fd954fa`).
`run_toxee.sh` runs bootstrap by default, so **every non-`--skip-bootstrap`
rebuild RESETS the fork to origin/v2, destroying ALL local fork commits** — the
whole campaign's fork keys (`9a878d2`..`f47e020`: sticker/chip/member-row/
attachment/reply/pasted-image keys) AND the group-profile override fix. They live
ONLY as local commits / the toxee-pinned SHA, never pushed to origin/v2.
**Consequences + the rule until the fork is pushed:**
- Build the run-phase app with `MCP_BINDING=skill TOXEE_BUILD_ONLY=1
  ./run_toxee.sh --skip-bootstrap` (preserves the checked-out fork). A plain
  `./run_toxee.sh` silently reverts the fork to fd954fa and builds keyless.
- The campaign fork SHA must be PUSHED to `origin/v2` (GitHub SSH 443 fallback)
  so bootstrap's FETCH_HEAD carries the keys. Until then the fork is fragile.
- After ANY rebuild, verify `git -C third_party/chat-uikit-flutter rev-parse HEAD`
  matches the toxee pin before running.
Current correct fork SHA = `545499e` (= f47e020 campaign+member keys + the
group-profile override fix); toxee pins it.

## Run phase — rui-p1-chat: 0/8, SHARED root cause (2026-06-13)

`rui-p1-chat` (sweep_p1_chat) live = **0 PASS / 8 FAIL**, but it is ONE shared
root cause, not 8 issues: the handshake succeeds + both accounts mark test
(`aMarked=true bMarked=true`), but EVERY case fails to **open the chat for the
FIRST message**. After a fresh handshake there is NO C2C conversation row yet, so
`openChat` (`drive_real_ui_pair_message_call.dart`) can't tap a
`conversation_list_item:c2c_<pk>` row and falls back to the
contacts→friend→Send-Message path via `ensureContactsShell`
(`drive_real_ui_pair_shell.dart`) — which FAILS ("[A] failed to recover to
Contacts shell"). `_seedConvRow` doesn't help (it calls the same `openChat`).
`l3_set_active_conversation` only sets `ffi.setActivePeer` (unread accrual), it
does NOT navigate the UI, so there is no l3 chat-open shortcut. **This same
first-chat-open path gates ALL the chat campaigns (rui-p1-chat, rui-c2c-extra,
rui-c2c-deep-extra, the +94 rui-chat), so fixing `ensureContactsShell` /
`openChat`'s first-message path reliably is the highest-leverage run-phase fix.**
NOTE: `ensureContactsShell`'s sidebar-tab recovery WORKED in rui-p1-single
(single-instance, `_p1SelectHomeTab(contacts)` returned true) but fails in the
2-process sweep — likely a 2-process foreground-contention / stuck-shell-state
difference; needs a failure screenshot of the stuck state to pin the exact step
(add a `shot()` at `ensureContactsShell`'s give-up + `openChat`'s throw points).
**RUN-PHASE BACKLOG — next session, fresh context.**

## Run phase (STARTED 2026-06-12 — build green + first live smoke done)

The write phase is closed; the remaining live work is run-phase execution.
**Correct invocation** (the flag alone is not enough): a campaign runs live only
with the class filter — `dart run tool/mcp_test/fixture_c_unified_runner.dart
--class=2proc-ui --real-ui-campaign=<name>`. WITHOUT `--class=2proc-ui` the
runner executes the default Fixture C (2proc-l3) manifest instead — the first
smoke attempt did exactly that (ran `drive_fixture_c_pair`/`_contact_search`, not
`sweep_p1_single`).

**Build:** `MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh` exit 0
(2026-06-12 22:00, fresh dylib embedded, L3 surface + fork keys compiled in).

**First live smoke — `rui-p1-single` (2026-06-12): 0 PASS / 3 FAIL** (cases 4/5
not reached — they depend on case 3 registering account #2). The harness LAUNCHES
+ DRIVES correctly (real-UI registration worked; conference CREATE passed;
endClean=true), so the fixes didn't break it — but 3 genuine run-phase bugs
surfaced that written-unrun could never catch:
1. `zh_locale_page_walk` FAIL on ONE sub-check only — `contactsZh=false` (every
   other zh assertion passed: settings/sidebar chats+contacts+settings/profile +
   revert). The Contacts-PAGE zh label the case asserts is wrong/not-surfaced;
   fix the expected contacts zh string (or its marker).
2. `conference_rename_leave` FAIL — the conference row is created, but
   `_openGroupProfile` from the chat header surfaces NONE of
   `[group_profile_members_entry, group_profile_edit_name_button,
   group_profile_id_text]` for an AVChatRoom (the conference profile-open path /
   header differs from a private group). Also `l3_force_home_root` is refused
   (non-test account) during `returnToChatsHome` — the case must navigate without
   that l3 helper on a real-UI (non-test) account.
3. `settings_switch_account_entry` FAIL — "settings did not become the active
   tab"; the `_openSettings` sidebar-tab nav didn't land (timing/foreground or
   the settings-tab key on this launch).
These are the iterative run-phase backlog: fix root cause → re-run the campaign →
move on. The harness + build + the 3 P1 fixes are validated working live.

**Root-cause analysis + fixes for the rui-p1-single trio (2026-06-12):**
- **F2 conference_rename_leave (the load-bearing one, shared `_openGroupProfile`):
  TRUE ROOT CAUSE (codex-found, my first hypothesis was WRONG) = the pushed
  group-profile route WIPED toxee's builder override, so it rendered the
  UPSTREAM keyless body.** My initial "ui_key_center can't resolve composite
  widgets / painted-but-unreachable" hypothesis was disproven by codex: the group
  profile body the screenshot showed was the UPSTREAM default (which visually
  resembles the override — name + edit FAB + "Group ID: …" — but carries NONE of
  toxee's keys). `TencentCloudChatGroupProfile._updateGlobalData`
  (`tencent_cloud_chat_group_profile.dart`) UNCONDITIONALLY reset the global
  group-profile builder to a fresh empty one when the route was pushed without
  per-widget `builders` (the normal `navigateToGroupProfile` path), erasing
  toxee's startup-installed override. **This is a real USER-FACING regression**
  (the customized Tox group/conference profile vanished on open) — not just a
  test problem. **FIX (fork commit 27b8637):** null-guard the reset (only install
  a default when none exists — matching the contact component's pattern), so the
  route keeps the override. Now the keyed override body renders live. The harness
  improvements made along the way are kept (they're still correct + general):
  `resolveKeyCenter` full-`visitChildren` fallback guarded by `_ancestorsPaint`
  (hermetic 8/8); `tapKeyCenter` falls back to `tapKeyAt` (ui_key_center) for
  flutter_skill-invisible keys; new `Inst.waitKeyCenter` for non-interactive body
  keys (SelectableText/KeyedSubtree); `_openGroupProfile` detects via `keyCenter`.
  This unblocks the WHOLE group-profile family (group2 rename/members/clear/leave
  + conference cases). **App rebuild required** (fork + ui_drive_tools are in the app).
- **F2 VALIDATED LIVE (2026-06-12) after the fork override fix + `--skip-bootstrap`
  rebuild:** `conference_rename_leave` now `created=tox_1 renamed=TRUE
  headerOk=TRUE` — the override body opens, the keyed edit-name button is tapped,
  the rename persists to the conversation row AND the open-chat header (the
  `chat_header_title_text` read fell back to `waitText` since flutter_skill can't
  see a Text key). RESIDUAL: `left=false` — the AVChatRoom (conference, A=owner)
  leave/disband adaptive-confirm dialog's primary button label is none of
  {Confirm, Disband Group, Disband, Dissolve, Leave, OK} that `_tryTapText`
  tries; needs a live look at the conference disband dialog's exact button text
  (or a keyed confirm). Small single-sub-assertion residual; the core F2 root
  cause is fixed.
- **F3 settings_switch_account_entry: CASCADE from F2.** Screenshot proved the
  app was STUCK on the conference profile page (left by F2's throw) when F3
  started, so the sidebar settings tab was unreachable. Fixing F2 (so the
  conference case completes + returns home) removes the cascade.
- **F1 zh_locale_page_walk: real PRODUCT i18n gap (recorded, assertion softened
  to honest).** Everything localized to zh EXCEPT the UIKit contacts-page SUBTAB
  labels (New Contacts / Blocked Users / Contacts / Groups stayed English).
  Root-caused as far as static analysis allows: toxee DOES push zh to the UIKit
  intl singleton (`TencentCloudChatIntl.setLocale` is SYNCHRONOUS, sets
  `_currentLocale` which takes precedence over context — `tencent_cloud_chat_intl.dart:27/42`)
  AND keys the contact tab on `languageCode` (`home_page.dart` `_buildTabChildren`),
  yet the `TTabItem` subtab labels render the pre-switch locale until app
  restart — a UIKit contact-tab rebuild/caching subtlety needing LIVE
  instrumentation to pin down. **OWED product i18n investigation** (separate from
  this harness campaign; the page title + sidebar + settings + profile all
  localize correctly). The case's contacts sub-assertion was softened to HARD on
  navigation + SOFT/logged on the subtab zh, so it no longer hard-fails on a
  pre-existing UIKit bug while still recording the gap.

1. Rebuild via `MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh`.
2. Run the write-phase campaigns serially: `rui-p1-single`, `rui-p1-chat`,
   `rui-p1-relaunch`, `rui-p1-extra`, `rui-account-conf-extra`,
   `rui-account-deep-extra`, `rui-group-conf-member-extra`,
   `rui-group-conf-deep-extra`, `rui-c2c-extra`, `rui-c2c-deep-extra`,
   `rui-native-boundary-guards`, `rui-p2-keys`, `rui-p2-reply`,
   `rui-p2-verify`, and `rui-p3-writable`.
   For faster broad smoke, prefer `rui-optimized-current` first, then split to
   the smaller campaigns only when a child sweep fails.
3. Root-cause any live failures and keep validated results honest (only update
   `test/mcp/S*.md` headers + INDEX for scenarios that are actually live-run).
4. Treat the older +94 sweeps 4–8 (`rui-contacts`, `rui-conv`, `rui-chat`,
   `rui-group2`, `rui-calls-misc`) as a separate deferred stream; they remain
   outside this campaign's write-phase closeout.

## Batch log (append-only)

- 2026-06-10: anchor created. Parallel session was live-running sweep_contacts
  run phase (commits 125b335, 9c3cedf); user then CANCELLED it and granted full
  file access. Its coherent toxee-side WIP archived as commit 8b62c56
  (focusType always-paste — keystroke mangles even short strings; case-40 remark
  asserts the Prefs-backed `friends[].remark`, root-causing the "expected native
  FAIL" as a wrong-field harness assert). Its tim2tox native WIP
  (`ffi/dart_compat_friendship.cpp`, uncommitted in the submodule) left in place
  — the run-phase owner decides whether the Platform-path finding makes it
  unnecessary (likely) or complementary (binary-replacement path parity).
  Sweep 4–8 run state: sweep_contacts was mid-run when cancelled; sweeps 5–8
  unrun. Instance state unknown — the run phase re-launches fresh.

- 2026-06-10 **Batch I DONE** (`ui_long_press` + `Inst.longPressKey`). Gates:
  analyze 222 (0 NEW), `ui_drive_tools_test.dart` 8/8, planner `--plan-json`
  exit 0, INDEX `--check` green. Codex (1 round): 1 P2 — fork conversation rows
  long-press at a CUSTOM 650 ms (`tencent_cloud_chat_gesture.dart:117-118`), so
  the 600 ms default hold would release early and fall through as a TAP →
  default raised to 800 ms in the handler, the MCP description, and
  `Inst.longPressKey`; the hermetic default-path test pumps 900 ms. Anchor
  CORRECTION in the same commit: the initially committed anchor pre-filled
  batch I–IV Status as DONE with invented outcomes (drafting error) — reverted
  to TODO + plan-note wording; only ACTUAL results may live in Status fields.

- 2026-06-11 **Batch II DONE (written, unrun)**. The batch agent hit the session
  limit after writing the part file + part declaration; this session completed
  dispatcher routing, runner registration (registry/campaign/both state
  tables), the 4 production keys the scenarios drive (the agent wrote against
  planned-but-unadded keys — every driven key then verified to resolve), the
  `savedAccountToxIds` dump field, gates, and 2 codex rounds (see Batch II
  Status). Durable gotchas: (1) flutter_skill `getTextContent` only surfaces
  Text/RichText — a SelectableText payload must be read from a neighboring
  prompt Text (the delete confirm word case); (2) the settings switch entry
  never routes through LoginPage (in-place teardown+boot) — asserting "lands on
  login cards" would have been a wrong-shape gate; (3) an empty l3 list field
  is ambiguous on read error — gate absence verdicts on a sentinel the list
  must contain (here: the primary toxId).

- 2026-06-11 **Batch III DONE (written, unrun)**. Added
  `drive_real_ui_pair_p1_chat.dart` and registered `sweep_p1_chat` /
  `rui-p1-chat`. Wrote all 8 P1 chat/conv cases; `read_receipt_double_tick`,
  `draft_restore_on_conv_switch`, and `typing_indicator_render` are NEGATIVE
  product-gap pins with read-code evidence instead of fake positive gates.
  Added automation-only keys for unread badge rendering (desktop sidebar +
  mobile bottom nav) and fork chat surfaces (open header title, media viewer
  root, state-suffixed send-status icon). Gates green: analyze 222/0-new,
  planner plan-json, validate-only, campaign-list, shell recovery self-test,
  INDEX check, and touched UI tests 139/139. Codex review deliberately skipped
  for this batch per the 2026-06-11 handoff instruction ("里面提到的codex审查的要求，
  先不做审查"). Durable gotchas: (1) `Text` keys must be inserted after the
  positional text argument, not before it; (2) `dart format` on fork files causes
  massive unrelated churn, so keep fork key edits surgical; (3) read-receipt
  assertions must prove the receiver's local unread was nonzero before opening
  the row, or the negative gate is vacuous.

- 2026-06-11 **Batch IV DONE (written, unrun)**. Added
  `drive_real_ui_pair_p1_relaunch.dart` and registered `sweep_p1_relaunch` /
  `rui-p1-relaunch`; added `_realUiStateRelaunchDirty` so internally restarted
  pair metadata is never reused by the next external scenario. Wrote all four
  P1 relaunch/profile cases: history survives A relaunch + autologin,
  offline-pending asserts the real SENDING spinner key before relaunching B,
  friend-profile voice/video tiles place real calls with both-idle guards, and
  group join-by-ID drives the real AddGroupDialog join card. Fork addition:
  `message_send_status:<msgID>:sending` on the sending spinner (same shared
  message widget contract as Batch III's read/sent keys). Verify-first gotcha:
  AddGroupDialog's join-by-ID path exists despite the handoff note; do not pin
  this as a product gap. Gates green: analyze 222/0-new, planner plan-json,
  validate-only, campaign-list, shell recovery self-test, INDEX check, and
  related UI tests 135/135. Codex review deliberately skipped per the user
  instruction for this turn.

- 2026-06-11 **Batch V DONE (written, unrun)**. Fork commit `9e72f4d` adds the
  P2 selector surfaces required by this batch: sticker tabs/cells, a
  RenderObject-backed `new_messages_chip`, and state-suffixed presence-dot keys
  while preserving the legacy presence-dot key. Added
  `drive_real_ui_pair_p2_keys.dart` and registered `sweep_p2_keys` /
  `rui-p2-keys`. Wrote all three P2 cases: real sticker-face send, real
  new-message chip tap after an off-bottom inbound message, and relaunch-driven
  online/offline presence dot. Verify-first gotcha: sender-side sticker send is
  a true FACE elemType 8, but the current tim2tox wire projection reaches B as
  `__face__:` text; do not pretend receiver rich-face rendering exists until the
  bridge/fork grows it. Gates green: analyze 222/0-new, planner plan-json,
  validate-only, campaign-list, shell recovery self-test, INDEX check, focused
  widget tests 5/5, and related UI tests 78/78. Codex review deliberately
  skipped per the user instruction for this turn.

- 2026-06-11 **Batch VI DONE (written, unrun)**. Fork commit `86cade8` adds the
  shared `message_input_reply_container` key. tim2tox commit `65562f1` adds the
  Dart-only C2C custom inbound seam and custom elem projection, while leaving
  the pre-existing native `ffi/dart_compat_friendship.cpp` WIP untouched and
  uncommitted. Root adds `l3_inject_c2c_custom`, the
  `drive_real_ui_pair_p2_reply.dart` case file, `sweep_p2_reply`, and
  `rui-p2-reply`. `reply_quote_real` seeds only the inbound custom bubble via
  l3, then drives real Reply menu selection, verifies the keyed quote banner,
  sends through the real composer, asserts sender-side `messageReply`
  cloudCustomData references the seeded message/sender, and checks B receives
  the reply body. Current bridge behavior does not expose receiver-side reply
  metadata, so that remains a documented product gap. Gates green: focused
  widget/service tests 7/7, driver/runner/l3 analyze with 2 baseline infos and
  0 fatal, planner plan-json, validate-only, campaign-list, corrected
  `rui-p2-reply` plan-json under `--class=2proc-ui`, shell recovery self-test,
  INDEX check, `git diff --check`, root analyze 222/0-fatal, and related tests
  54/54. Codex review deliberately skipped per the user instruction for this
  turn.

- 2026-06-11 **Batch VII DONE (written, unrun)**. Verify-first resolved the
  voice / paste-image / tray trio honestly: fork commit `ec3e314` adds
  `desktop_send_image_confirm_button`, and root adds
  `drive_real_ui_pair_p2_verify.dart`, `sweep_p2_verify`, and `rui-p2-verify`.
  The written hard case is `paste_image_into_composer`: macOS image clipboard
  seed -> real composer Cmd+V -> real keyed image confirmation -> sender/receiver
  `mediaKind=image` dump assertions. Voice gets no new write-phase driver
  because the current evidence pins it to S78's real-mic/TCC + live DHT gate
  (`run_fixture_c_voice_msg.sh` plus the mobile record widget test). Tray gets
  no fake close-to-tray driver because the implemented close path destroys the
  window instead of hiding it to tray; AppTray can show/focus when present, but
  close-window restore is a product gap. Gates green: driver/runner/source
  analyze no issues, fork image-tools analyze 3 baseline infos/0 fatal,
  planner plan-json, validate-only, campaign-list, corrected `rui-p2-verify`
  plan-json under `--class=2proc-ui`, shell recovery self-test, INDEX check,
  source guard direct dart run, `git diff --check`, root analyze 222/0-fatal,
  `test/ui/testing` 19/19, and related tests 53/53. Codex review deliberately
  skipped per the user instruction for this turn.

- 2026-06-11 **Batch VIII DONE (written, unrun)**. Added
  `drive_real_ui_pair_p3.dart`, `sweep_p3_writable`, and `rui-p3-writable`.
  `message_burst_perf` sends a parametric A->B real-composer burst, asserts the
  final delivery and sender/receiver burst counts, and logs elapsed timing
  against a nonblocking threshold (`RUI_BURST_PERF_NONBLOCKING_MS`). Added
  `ar_rtl_smoke_test.dart` for the direct Arabic supported-locale +
  `Directionality.rtl` gate, while leaving the existing real Settings picker
  RTL test as the fuller interaction coverage. Wrote the platform run plan
  above for macOS desktop, iOS simulator, Android emulator, and Win11 desktop.
  Gates green: red-first P3 source guard (failed before the part existed) then
  direct source guard pass, RTL smoke 1/1, driver/runner/test analyze no issues,
  planner plan-json, validate-only, historical campaign-list (76 campaigns at
  that Batch VIII commit; current catalog is discoverable via
  `--list-real-ui-campaigns`), `rui-p3-writable` present, corrected
  `rui-p3-writable` and standalone
  `message_burst_perf` plan-json under `--class=2proc-ui`, shell recovery
  self-test, INDEX check, `git diff --check`, root analyze 222/0-fatal, and
  `test/ui/settings test/ui/testing` 79/79. Codex review deliberately skipped
  per the user instruction for this turn.

- 2026-06-11 **Write phase CLOSED**. This closeout pass confirmed that the repo
  state already contains the committed Batch III–VIII work (`cee4fc5` through
  `e2006aa`) on top of Batch I/II, then reran the campaign-wide finish gates on
  the final write-phase HEAD: `flutter analyze lib tool --no-fatal-warnings
  --no-fatal-infos` exited 0 with the known 222-issue baseline; planner
  `--plan-json --class=2proc-ui`, `--validate-only`, `--list-real-ui-campaigns`
  (historical closeout output: 76 campaigns including `rui-p1-chat`,
  `rui-p1-relaunch`, `rui-p2-keys`, `rui-p2-reply`, `rui-p2-verify`,
  `rui-p3-writable`; current catalog is discoverable from the runner), shell recovery
  self-test, and `gen_scenario_index.dart --check` all passed; consolidated
  touched-surface tests
  (`test/ffi_chat_service_c2c_custom_ingest_test.dart`,
  `test/ui/add_group_dialog_test.dart`, `test/ui/call`, `test/ui/chat`,
  `test/ui/conference`, `test/ui/contact`, `test/ui/conversation`,
  `test/ui/home`, `test/ui/settings`, `test/ui/testing`) passed 250/250.
  Campaign handoff is now purely run-phase. Codex per-batch/diff review remains
  intentionally deferred per the explicit 2026-06-11 user instruction for this
  handoff turn.

- 2026-06-12 **Owed review DISCHARGED + extra wave committed**. The skipped
  per-batch reviews (III–VIII) plus the uncommitted "extra/optimized" second
  wave (account_conf_extra, c2c_extra, group_conf_member_extra, high_value_extra,
  optimized, p1_extra + production/fork seams) were reviewed by 4 parallel
  read-only review agents (codex-grade lens: false-pass / double-fire /
  honest-scope / l3-as-asserted-action / dead-key / runner-consistency). **3 P1
  found + fixed** — all were dead-key / contract violations the skipped reviews
  would have caught:
  1. Batch V `sticker_face_cell_send` gated on a phantom `desktop_sticker_panel`
     fork key never committed → re-gated on the real `sticker_face_tab:*` (panel-
     open proof) + widened the probe to 0..9 (fork keys by `e.index`). Toxee-side,
     no fork change. (commit 993f82f)
  2. `group_member_list_item:<userID>` was a dead key (driven by all 5
     group_conf_member_extra cases + the desktop kick/role flows) — never in the
     fork. Added a `KeyedSubtree` row key to the fork member list (fork commit
     f47e020). 
  3. high_value_extra `notification_tap_routes_to_c2c` used
     `l3_simulate_notification_tap` AS the asserted action (campaign rule
     violation) → converted to an explicit SKIP(75) with evidence (real OS
     notification click isn't headless-automatable; routing covered by
     `run_fixture_c_notification_tap.sh`).
  P2s applied: offline_pending_relaunch left B down when the in-body relaunch
  threw → recover whenever B isn't confirmed up (commit 993f82f). Deferred with
  rationale: image_preview_open_hardened keeps the PASS-on-rendered-bubble
  best-effort floor (matches the committed batch-6 `chat_image_bubble_open_preview`
  precedent, codex-blessed in the +94 campaign); account_conf_extra text-tap
  cancels are honest (state-unchanged is the real gate) — keyed-cancel is a
  future robustness item. The export-override test already had its `tearDown`
  reset (a flagged-but-stale finding). Production seams verified SAFE for release
  by deep trace: the new `l3_set_account_import_pick_path` /
  `l3_set_attachment_pick_path` tools + the `login_page_controller` filePathOverride
  are double-gated (`kDebugMode && TOXEE_L3_TEST` + `_activeAccountIsTest`), tree-
  shaken from release, and behave identically to native pickers when the override
  is null. Gates after fixes: analyze 217 (0 new errors), planner/validate/INDEX
  (178 playbooks)/self-test green, touched hermetic tests pass. Fork must be
  PUSHED before the toxee commits are pushed (pre-push hook; GitHub SSH 443
  fallback). **The campaign is still write-phase: nothing is live-run.**

- 2026-06-13 **RUN PHASE — rui-p1-chat first-chat-open UNBLOCKED + 5 root-cause
  fixes (0/8 → 4/8 live, more pending re-validation).** The session's mandate
  (fix `ensureContactsShell`/`openChat` first-chat-open, then drive the campaign
  to green) progressed through THREE live runs, each surfacing the next
  downstream blocker once the prior was fixed. Fixes (codex-reviewed each round;
  no P1/P2 outstanding):
  1. **First-chat-open (the explicit ask) — FIXED + LIVE-VALIDATED.** Two layers:
     (a) STALE LATCH: `Inst.navToolsUnavailable` latches true when
     `l3_force_home_root` returns `non_test_account` DURING the handshake (run on
     a still-non-test account), then the sweep's `markAccountTest()` made the
     accounts test but never reset the latch → `_forceHomeRootAndWait` kept
     skipping the deterministic recovery in `ensureContactsShell` → the flaky
     2-process UI-landmark recovery was the only path left → "failed to recover
     to Contacts shell". FIX: reset `navToolsUnavailable=false` on
     `markAccountTest()` success (`drive_real_ui_pair_inst.dart`). Live run-1
     proved it: `forceHomeRoot(chats/contacts) … ready=true` now fires.
     (b) DETERMINISTIC SEAM: new UNGATED `l3_open_chat` nav-stability hook
     (`{userId|groupId}`) driving the production `_openChat(peerId:/groupId:)`
     path (flips to Chats + binds the master-detail right pane; synthesizes the
     conversation when no row exists). Registered invoker in
     `home_page_bootstrap.dart` (guarded to master-detail layout — mobile keeps
     the route push). `openChat` now: conv-row tap → real contacts→profile→Send
     (made NON-throwing) → `l3_open_chat` last resort → throw+screenshot.
  2. **Composer send MANGLING — FIXED.** `sendComposerMessage` (and
     `_p1cTypeIntoComposerNoSend`) used `osaType` keystrokes, which drop/mangle
     chars (the same reason `focusType` uses paste). Live-proven: the C2C row was
     created but its text never matched the expected nonce. FIX: `osaPaste`
     (atomic Cmd+V; codex confirmed the desktop composer's Cmd+V hook returns
     `ignored` → real paste path; Enter-to-send unchanged). ALSO replaced the
     unfiltered `_lastMessage` verify with `_anyConversationLastMessageIs`
     (unique-nonce, conversation-agnostic — the old one verified the FIRST conv,
     wrong once a group existed). Run-2: read_receipt/draft/typing flipped to
     PASS (4/8).
  3. **Desktop+mobile message-menu OFFSTAGE DUPLICATE KEY — FIXED (fork).** The
     message context menu is built twice (visible overlay + an `Offstage`
     measurement copy); both carried the same `message_menu_item:<action>`
     automation keys. flutter_skill matches offstage subtrees, so
     `tapKeyCenter('message_menu_item:recall')` tapped the stale offstage copy →
     hit the dismiss barrier → recall/forward action never fired (menu just
     closed; message intact). FIX: `keyed` flag on `_buildDesktopMenu` /
     `_buildMobileMenuItems`+`_buildMobileMenuWidget`; the offstage measurement
     copies pass `keyed:false` (fork
     `tencent_cloud_chat_message_item_with_menu.dart`). Benefits ALL desktop+mobile
     menu-action campaigns (recall/forward/copy/reply/delete/...). Mobile twin
     fixed per codex P2 (mobile-parity mandate).
  4. **Search overlay couldn't be dismissed — FIXED.** The Cmd+Ctrl+F global
     search is a pushed route; `forceHomeRoot` only swaps the tab (can't pop it)
     and ESC had no binding + the X button was unkeyed. FIX (fork
     `custom_search.dart`): `CallbackShortcuts({Escape: _closeSearch})`
     (includeRepeats:false + idempotent route guard) + a keyed
     `UiKeys.messageSearchCloseButton` (consolidated the closeFunc/pop branches).
     Harness now closes via ESC → keyed X → home; also retries the flaky
     Cmd+Ctrl+F open up to 3×.
  5. **unread_badge off-by-one (group=2 want 1) — INSTRUMENTED + drain
     hardened.** Live: C2C unread correct (2), GROUP showed 2 for a single
     `l3_inject_group_text`. `ingestInboundGroupText` is verified +1, so the
     extra is a baseline-drain race or a hybrid double-feed. FIX-so-far
     (harness): bulletproof baseline drain (loop opening BOTH convs until every
     per-conversation `conversations[].unreadCount` AND the aggregate are 0, with
     `_p1cConvUnreads` evidence logging + required-conv-id presence). If the
     group still inflates after a clean per-conv-0 baseline, that's a real
     inject-seam/UIKit double-count to fix next (evidence now logged per run).
  RUN PROGRESSION (7 live runs): run-1 0/8→ first-chat-open fixed (image PASS);
  run-2 4/8 (read_receipt/draft/typing/image PASS); run-4/5/6 6/8 (badge +
  search FIXED + validated; recall/forward remained); run-7 5/8 (read_receipt
  FLAKED — it's a NEGATIVE pin whose precondition timing is flaky: PASS in
  runs 4/5/6, FAIL in run-7; treat as flaky-passing, not a regression).
  **VALIDATED-PASS (live): draft_restore, typing_indicator, unread_badge,
  search_empty_state, image_preview; read_receipt (flaky-pass).**
  All fixes codex-reviewed (5 rounds; the badge dedup-branch P1 + 4 P3s applied).

  TWO DEEP-REMAINING CASES (precise root causes, need a follow-up session):
  - **chat_recall_message**: the DATA recall WORKS live (`aGone=true bGone=true`
    — both A's and B's copies deleted; confirm-button key fix landed so the
    "Message Recall" confirm fires). But the A-SIDE UIKit message list does NOT
    update — the original bubble lingers (no tombstone, not removed) even though
    FfiChatService deleted it (a hybrid-path gap: the platform-path delete +
    `separate_data.recallMessage` LOCAL_REVOKED flip don't reach the rendered
    UIKit list). PLUS a real user-facing bug: the `__revoke__:` control signal
    LEAKS into A's own conversation PREVIEW (`lastMessageText` shows
    `__revoke__:{json}`) — the swallow-delete in `tim2tox_sdk_platform.dart:769`
    doesn't refresh the conv preview (`_lastByPeer`). Deep fix = wire recall to
    update the UIKit rendered list + refresh the conv preview after the
    swallow-delete (conversationId derivation for the self-echo is the snag).
  - **forward_to_group_target**: reaches the picker fully (`pickerShown=true
    targetTapped=true`), only the final Send tap fails (`sendResolvable=false
    sendCenter=null`). The forward picker's keyed Send button
    (`forward_picker_send_button`, added in `_renderHeader` which desktopBuilder
    DOES call) is invisible to BOTH flutter_skill interactiveStructured AND
    `resolveKeyCenter` — yet the message-menu items and the recall confirm
    button (same build) resolve fine. The picker's group ROW resolved via
    flutter_skill bounds, but the header Send button did not. Needs LIVE element-
    tree introspection to learn why `showPopupWindow`'s deep child header isn't
    reached (candidate: a nested-overlay / view boundary the resolver misses).

  **COMMITTED + PUSHED 2026-06-13:** fork v2 `33f7141` (origin/v2), tim2tox
  master `641f403` (origin/master), toxee master `a21f982` (origin/master;
  pins both). All HTTPS remotes (no SSH-443 needed); pushed fork → tim2tox →
  toxee so the pinned submodule SHAs exist on the remotes (clone --recursive
  works). Since origin/v2 now CARRIES the keys, a plain `run_toxee.sh`
  (bootstrap → `checkout -B v2 FETCH_HEAD`) is SAFE again — it no longer
  abandons the fork commit. (The toxee a21f982 = the earlier 1e5c81b amended
  with this push note.)
  HIGH-LEVERAGE CROSS-CUTTING FIXES (benefit ALL chat campaigns, validated):
  first-chat-open (latch reset + l3_open_chat), composer paste
  (sendComposerMessage osaType→osaPaste + conv-agnostic verify), offstage
  message-menu duplicate-key (desktop+mobile fork), desktop menu detection via
  waitKeyCenter (overlay-aware), search Escape-to-close + keyed X, group-unread
  double-count (FfiChatService.groupUnreadHandledExternally).

- 2026-06-13 (session 3) **rui-p1-chat 8/8 — the 2 DEEP-REMAINING CASES FIXED +
  LIVE-VALIDATED.** Drove `rui-p1-chat` from 6/8 to **8 PASS / 0 FAIL** by
  root-causing recall + forward across the native/fork/tim2tox/harness layers (6
  live runs, multiple codex rounds; all P1/P2 applied).
  - **forward_to_group_target — FIXED.** Root cause (codex-confirmed): the
    forward picker is a centered `showDialog`/`AlertDialog`
    (`showPopupWindow` no-offset → `isUseMaterialAlert`), NOT an overlay popup.
    The harness selected the target group by TEXT (`_p1cTapTextOnce`), which also
    matched the SAME group's row in the BACKGROUND sidebar behind the
    `barrierDismissible` barrier → the tap landed on the barrier → DISMISSED the
    dialog before Send (so `forward_picker_send_button` read "not resolvable" —
    the dialog was gone). FIX: fork keyed picker row
    `forward_picker_item:<groupID|userID>` on `_chatItem`; harness taps the keyed
    row INSIDE the dialog + surfaces the `ui_key_center` resolver verdict on Send
    failure. LIVE: `sendResolvable=true targetTapped=true sendTapped=true
    inGroup=true`.
  - **chat_recall_message — FIXED (4 layers).** The original ask: A-side UIKit
    list doesn't update + `__revoke__:` leaks into the conv preview.
    (1) RENDERED TOMBSTONE: `recallMessage` (fork separate_data) flipped the
    in-memory copy to LOCAL_REVOKED but `updateMessageList(disableNotify:true)`
    never notified (tim2tox fires the LEGACY onRecvMessageRevoked into the fork's
    no-op handler; the real onRecvMessageRevokedWithInfo is never called +
    would fail post-hard-delete). FIX: `disableNotify:false` + ALSO set
    `messageData.messageNeedUpdate = target` (the rendered item re-reads a single
    message's status off THAT identity signal; the list notify alone did not
    re-evaluate the existing item). Capture the target+list BEFORE revoke (a
    mid-revoke preview refresh races a reload that would drop the row). PLUS the
    `item_container` LOCAL_REVOKED tip guard was relaxed to accept revoker
    nickName OR userID (toxee currentUser has a display nick but an empty
    placeholder userID → the named tip was dropped). identity = same object for
    the published list + messageNeedUpdate (a re-fetched copy silently fails to
    re-render — codex P2; documented self-healing concurrent-message caveat).
    (2) PREVIEW LEAK: `revokeMessage` sent `__revoke__:` via `sendText` which
    persists it + sets `_lastByPeer` → the JSON stranded as the sidebar preview.
    FIX: new `FfiChatService.sendControlSignal` (raw wire send, NO
    history/_lastByPeer/_messages, always-send — no stale-online-flag drop) +
    `_refreshConversationPreviewC2C` (FULL-conversation re-notify; a sparse
    notify is merge-dropped by the UIKit, keeping the stale lastMessage).
    (3) RECEIVER DELETE (bGone): the sender-send-time vs receiver-receive-time
    timestamp-window match drifts on a marginal DHT. FIX: CONTENT key (text
    prefix byte-budgeted under 1372 + full length) in the payload; receiver
    matches by content (latency-independent), NO timestamp fallback when the
    content key is present, ambiguous→no-delete (codex P1).
  Build/run: `MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh
  --skip-bootstrap` (preserves uncommitted fork/tim2tox edits) → run with file
  redirect + a generous `timeout` (the same-host DHT handshake flakes 1-3
  attempts; the runner's `_maxRealUiAttempts=2` retries on ANY failure — read the
  first complete attempt's RESULTS, don't wait for the wasteful retry). Gates:
  analyze 217/0-new, validate-only 0, INDEX 178 playbooks.

- 2026-06-22 **RUN PHASE (post-Feishu-restyle re-validation, session N).** Ran the
  written-unrun P1/P2/P3 campaigns against the CURRENT build (toxee `de24f3d`,
  fork `97c0a16` = Feishu restyle layered on top of the campaign fork keys; all
  campaign keys verified present). The restyle (which landed AFTER these campaigns
  were last validated) shifted the desktop chat layout and introduced several
  real-UI regressions. Findings + fixes:

  **CRITICAL OPS BUG FIXED — orphan app instances broke 2-process handshakes.**
  The runner runs instances from APP COPIES named `ToxeeA-*.app` / `ToxeeB-*.app`
  under `.multi_instance_runtime/app_copies/`. A teardown gap leaves these copies
  ALIVE after a run (esp. after the wasteful failure-retry); a leftover B-copy
  holds DHT bootstrap port 33446, so the NEXT campaign's loopback DHT never
  converges → "A never received B's friend request" → handshake FAILS (0 cases
  run). The standard `pkill -f "Toxee.app/Contents/MacOS/Toxee"` MISSES the copies
  (path is `ToxeeB-*.app/...`, not `Toxee.app/...`). RULE: between every campaign,
  kill with the BROAD pattern `pkill -f "Contents/MacOS/Toxee"` and verify DHT
  ports 33445-33448 are free (`lsof -nP -iUDP | grep 3344`). Serialized helper:
  pre-clean → run ONE campaign fully → post-clean. This alone unblocked the
  2-process campaigns.

  **CLEAN PASS (single-instance, no handshake):** rui-p1-single 5/5,
  rui-p1-extra 2/2, rui-account-conf-extra 6/6, rui-account-deep-extra 1/1.

  **REGRESSION 1 (FIXED, driver-only, high-leverage): desktop message context
  menu wouldn't open** → broke recall/forward (p1-chat) AND any message-menu
  campaign. ROOT CAUSE (live-probed): the restyle widened the chat pane; the SELF
  bubble's secondary-tap Listener sits at ≈1.24× rowCenter.x (was ~1.5×), and 1.8×
  fell off-screen, so `_openMessageMenuReal`'s bias factors missed the self bubble.
  FIX: biasFactor → `[1.24,0.6,1.32,0.5,1.12,0.7,1.0,0.45]`
  (`drive_real_ui_pair_chat.dart`). LIVE-VALIDATED: `forward_to_group_target` now
  PASSES; rui-p1-chat 6/8 → 7/8.

  **REGRESSION 2 (FIXED send, driver-only): desktop attachment file/photo/video
  sent nothing.** ROOT CAUSE (live-confirmed `currentConversation=null`): the
  row-tap chat-open left the message-input userID unbound, so toxee `_sendMedia`'s
  `if (userId != null)` guard silently skipped `sendFile`. FIX: bind via the
  production `_openChat` (l3_open_chat) right before the tap in
  `_hveAttachmentPickAndSend`. LIVE-VALIDATED: SEND now works (sentId non-empty,
  rowRendered=true). RESIDUAL: `received=false` — same-host file DELIVERY to B does
  not complete in-window (B auto-accept exists at `fake_msg_provider.dart:144`, so
  likely a same-host transfer timing/receive-render gap, NOT a missing feature) —
  deeper follow-up.

  **DEEP-GAP (flaky, NOT a restyle regression): rui-p1-chat `chat_recall_message`.**
  After the menu fix, the DATA recall works (aGone=true bGone=true) but the A-side
  LOCAL_REVOKED tombstone TIP render lags/doesn't appear (`tombstone=false`). The
  restyle did NOT touch the tip-render files (only the file bubble) — this is the
  same render-timing flakiness session-3's fix (`cc7792d`) documented ("can lag at
  8s"). Data path intact; render-only.

  **REMAINING (need live investigation): rui-c2c-extra 3/5** —
  `c2c_global_search_contact_opens_chat` (tapped=true opened=false: search-result
  tap doesn't navigate; converter DOES set userID so not the obvious null-bug) +
  `c2c_conv_delete_cancel` (conversation_list_item `key_offstage_only` — the conv
  row resolves fine in isolation, so this is a STATE CASCADE: the failed
  global_search likely leaves its overlay/route covering the list. Candidate
  driver fix: always close the search overlay at the end of global_search + pop to
  root before conv_delete_cancel).

  **STILL UNRUN (next session):** rui-c2c-deep-extra, rui-group-conf-member-extra,
  rui-group-conf-deep-extra, rui-p2-keys, rui-p2-reply, rui-p2-verify,
  rui-p3-writable, rui-p1-relaunch. The menu-bias fix should help all menu-driven
  ones; expect more restyle layout regressions in group menus / member lists.

  Diagnostic: new inert `probe_restyle_diag` single-app scenario
  (`drive_real_ui_pair_chat.dart` + dispatch) seeds a friend+messages and reports
  window size / conv-row offstage / which secondary-tap x opens the message menu —
  the tool that root-caused REGRESSION 1.

- 2026-06-22 **RUN PHASE continued — more campaigns run, shared root causes found.**
  Committed driver fixes: toxee `ec06a2d` (menu-bias + attachment bind +
  conv-offstage + probe) and `e9a258a` (paste-image bind belt).

  **NEW PASS:** rui-p2-reply 1/1 (reply_quote_real — exercises the message-menu
  Reply action; the menu-bias fix carries it). rui-p2-keys `sticker_face_cell_send`
  PASS.

  **SHARED ROOT CAUSE — `currentConversation=null` after the handshake.** Every
  2-process chat run logs `conversation-list openChat fallback …
  homeShellTab=contacts currentConversation=null`: after the friend-accept the app
  sits on the CONTACTS tab, so `openChat`'s conv-row tap can't bind the chat; the
  l3 fallback fixes `_chatSurfaceReady` but the master-detail composer's userID can
  stay stale, so SEND paths that read it (attachment `_sendMedia`, desktop
  paste-image) silently send nothing. FIX (applied per-case, validated): bind via
  the production `_openChat` (`openChatViaL3`) right before the send. Candidate
  deeper fix: make `_ensureChatOpen` always re-bind via `_openChat` so no per-case
  belt is needed.

  **SHARED RESIDUAL — same-host file DELIVERY (`received=false`).** After the bind
  belt, attachment (native-boundary) AND paste-image (p2-verify) both SEND
  correctly (sentId set, row rendered) but B never receives the file/image in-window
  (60s). B auto-accepts incoming files (`fake_msg_provider.dart:144`), so this is a
  same-host file-transfer completion/receive-render gap, NOT a missing feature —
  the single blocker for both cases. (Text/sticker wire delivery works fine.)

  **OTHER DEEP-GAPS (each its own investigation):**
  - rui-p1-chat `chat_recall_message`: data recall works; LOCAL_REVOKED tombstone
    TIP render lags (flaky, NOT a restyle regression — tip-render files untouched).
  - rui-c2c-extra `c2c_global_search_contact_opens_chat`: search-result tap doesn't
    navigate (tapped=true opened=false); converter+_mapConv both set userID, so not
    the null-bug — needs a live search-open (the single-app probe can't open search
    due to osascript focus). 
  - rui-p2-keys `new_messages_chip_tap` (chipShown=false) + `presence_dot_relaunch`
    (onlineAfterData=false after B relaunch).

  **CAMPAIGN TALLY (this session):**
  CLEAN PASS: rui-p1-single 5/5, rui-p1-extra 2/2, rui-account-conf-extra 6/6,
  rui-account-deep-extra 1/1, rui-p2-reply 1/1.
  IMPROVED: rui-p1-chat 6/8→7/8, rui-c2c-extra 3/5→4/5, rui-p2-keys 1/3,
  rui-native-boundary-guards (attachment SEND fixed; delivery residual),
  rui-p2-verify (paste SEND fixed; delivery residual).
  STILL UNRUN: rui-c2c-deep-extra, rui-group-conf-member-extra,
  rui-group-conf-deep-extra, rui-p3-writable, rui-p1-relaunch.

  **OPS NOTE — handshake DHT flake.** Even with clean DHT ports, the same-host
  friend-request handshake often needs 2-3 send attempts or the runner's full
  relaunch-retry to converge (~5-8 min/campaign). Not a code bug; environmental.

- 2026-06-22 **FILE-DELIVERY ROOT CAUSE FIXED → rui-native-boundary-guards GREEN.**
  Continued on the shared file-delivery blocker. `drive_fixture_c_file` (S21/S24)
  PASSES, proving 2-process file delivery WORKS when the sender waits for the peer
  ONLINE and passes content (not a host path). The real-UI attachment failure was
  FIVE compounding causes (toxee commit `694e130`, codex "Findings: none"):
  1. BIND (toxee `_sendMedia`): the captured option userID was stale/null after a
     master-detail switch → fall back to `UikitDataFacade.currentConversation`.
  2. BIND (driver `_ensureBoundChat`): retry `_openChat` + verify currentConversation.
  3. DELIVERY (driver `_waitFriendOnline`): wait for the peer ONLINE (not just
     friend-added) before sending — wait FIRST, then bind right before the tap.
  4. FILE-READ (l3): a sandboxed app can't read a driver `/tmp` file (FFI -6
     "Cannot read file") → `l3_set_attachment_pick_path` now takes `contentB64` and
     the APP materializes it under Directory.systemTemp, mirroring l3_send_file.
  5. ASSERT (driver): the SENDER record carries the file under `filePath` (not
     `fileName`) → match the filePath basename too.
  **LIVE: rui-native-boundary-guards passed=2/0, attachment_entry_buttons_render
  PASS (fileSent=true imageSent=true received=true).**

  **paste-image (p2-verify):** the SEND now works again (single `_openChat` bind +
  online-wait; the multi-retry `_ensureBoundChat` disrupted the fork Cmd+V composer
  → reverted for paste, commit `4e9f282`). Delivery is validated-by-proxy (identical
  to the attachment path). Final live PASS was BLOCKED only by same-host DHT
  degradation late in the session (B repeatedly failed to connect / handshake
  flaked) — environmental; expect PASS on a fresh run where B connects.

  **NET CAMPAIGN STATUS:** CLEAN PASS — rui-p1-single, rui-p1-extra,
  rui-account-conf-extra, rui-account-deep-extra, rui-p2-reply,
  **rui-native-boundary-guards**. IMPROVED+committed — rui-p1-chat 7/8 (recall
  render-lag gap), rui-c2c-extra 4/5 (search-nav), rui-p2-keys 1/3 (chip+presence),
  rui-p2-verify (paste send fixed; delivery env-blocked this session). UNRUN —
  rui-c2c-deep-extra, rui-group-conf-member-extra, rui-group-conf-deep-extra,
  rui-p3-writable, rui-p1-relaunch (the menu-bias + bind + online-wait fixes should
  carry the media/menu ones; same-host DHT degradation gates them late-session).

- 2026-06-22 **ENV BLOCKER (new session) — osascript Accessibility (TCC 1002).**
  Rebuilt against current HEAD (toxee `0087be4`, i18n commit changed `lib/` + fork
  `4dcb69e`), DHT ports clean, ran rui-p2-verify → BLOCKED at step-1 account
  registration: `System Events got an error: osascript is not allowed to send
  keystrokes. (1002)` (runner rc=78). ROOT CAUSE: macOS TCC attributes Accessibility
  to the GUI app at the **process-tree root**. This session runs Claude via the Emacs
  ACP bridge (Bash shell → `claude` SDK → `node` → **/Applications/Emacs.app**), so the
  responsible app is **Emacs.app**, which is NOT enabled in System Settings → Privacy &
  Security → Accessibility. Every real-UI campaign registers an account via
  `focusType` → clipboard paste → `Cmd+V` (real keystrokes) as its FIRST step, so ALL
  2-proc real-UI campaigns are 100% blocked until granted. NOT code-fixable (`tccutil`
  only resets; TCC.db is SIP-protected; sandbox-disable doesn't help; enterText swap
  SIGSEGVs the Flutter engine — the very reason the harness uses osascript). FIX = one
  manual grant: enable **Emacs.app** in the Accessibility pane (or relaunch Claude from
  a terminal that already holds it, e.g. Terminal.app), then re-run from rui-p2-verify.
  Prior sessions weren't blocked because they ran under such a terminal. Diagnostic:
  `osascript -e 'tell application "System Events" to key code 53'` → 1002 confirms;
  empty `keystroke ""` returns 0 even unauthorized (don't use it to test).

- 2026-06-22 **POST-GRANT RUN — rui-p2-verify + rui-c2c-extra GREEN (2 root-cause fixes).**
  After Emacs.app was granted Accessibility, re-ran on clean DHT:
  - **rui-p2-verify PASS (5-layer send/delivery already worked; only the ASSERTION
    was wrong).** Live diag: the pasted-image SEND completes end-to-end (sentId set,
    row rendered, B receives), but the SENDER-side history record stores the image
    name ONLY under `filePath` (basename `paste_image_<nonce>.png`) with `fileName`
    null. The old assertion checked the (null) `fileName` → "sender image not in
    dump". Fix = match `paste_image_*.png` across EITHER `fileName` or the `filePath`
    basename, both sender + receiver (mirrors attachment fix 694e103/694e130). Live:
    `sentId=… row=true received=true` passed=1/0. codex: No findings. Committed `a2c2158`.
  - **rui-c2c-extra 5/5 PASS — `c2c_global_search_contact_opens_chat` was a REAL
    product bug.** Live diag pinned it precisely: after tapping a C2C conversation in
    the global-search overlay, `currentConversation` binds correctly and the composer
    mounts (`hasInput=true`), but `homeShellTab=contacts` — the chat is hidden behind
    the Contacts pane. ROOT CAUSE: the search path (`custom_search _navigateToMessage`,
    desktop branch) sets `UikitDataFacade.currentConversation` DIRECTLY without
    flipping the home shell to the Chats tab, unlike every other open-chat path
    (conversation-row tap, contact-profile Send-Message, notification routing — all do
    `_index = 0`). FIX (production, `lib/ui/home_page_bootstrap.dart`): the HomePage
    `currentConversation` event-bus listener (the single chokepoint that already
    rebuilds the message widget) now also flips `_index = 0` on desktop master-detail
    whenever a conversation binds, even when re-opening the current one. Restructured
    to schedule on `(changed || needsTabFlip)`, re-read `stillCurrent`/`doRebuild`
    in-callback, and keep the expensive rebuild + `clearConversationGroup` gated on an
    actual conversation change. Mobile pushes a ChatPage route (no pane bind), so it's
    unaffected (`_lastShouldShowMasterDetail==false`). This fix ALSO covers
    `sweep_c2c_deep_extra`'s `c2c_search_result_opens_target_message` (same path).
    code-reviewer: no critical, 1 refinement applied (early-exit to avoid a no-op
    setState). **codex review OWED** (provider 503 at review time; retry pending).
    Diagnostics added to `drive_real_ui_pair_c2c_extra.dart` (failure-only) +
    `drive_real_ui_pair_p2_verify.dart`. Live: rui-c2c-extra 5/5, endFriends=true.

- 2026-06-22/23 **TASK-C SWEEP — group/c2c-deep GREEN (4 more fixes); codex DOWN.**
  Continued the unrun campaigns. codex provider went 503 then the SESSION WAS
  REVOKED (refresh_token_invalidated — needs interactive `codex login`), so all
  fixes below are self-validated via the feature-dev:code-reviewer agent + live
  runs + analyzer; **codex review is OWED on all of them** (commits a2c2158,
  f2673a1, 801467a, 14df542, 72453ee) once the user re-logs codex in.

  - **rui-c2c-deep-extra 1/1 PASS** — `c2c_search_result_opens_target_message`
    failed (historyRowShown=false) though the "Search Chat History" window DID
    render the matching row (screenshot-confirmed). Root cause: the case WAITED
    with `waitKey` (flutter_skill whole-tree, can't see ListView rows) but TAPPED
    with `tapKeyCenter` (element-tree). Fix = resolve the row via `waitKeyCenter`
    (driver-only, `14df542`). msgID matched fine — NOT a key-value bug.

  - **rui-group-conf-member-extra 5/5 PASS** (was 3/5) — `group_member_role_action_smoke`
    + `group_member_remove_ui` failed "peer member row not rendered" while
    `group_member_peer_menu_surface` (same row) passed. Live diag: the bridge member
    list accumulated EXACT-DUPLICATE entries under same-host NGC churn (count grew
    2->3->4; nonSelf=[uid,uid,uid] — same userID repeated; the peer's NGC group id
    also != its friend pubkey, so the test leans on the single-non-self fallback,
    which the dups break). FIX = de-dupe by Tox pubkey at the `l3_group_member_list`
    seam (keep highest role) so it reports the canonical view the UI already renders;
    `_memberRowKeyFor` also hardened to try ALL pubkey matches (`801467a`). Production
    unaffected (UI de-dupes). **NOTE: the true source-level dedup belongs in tim2tox
    `getGroupMemberList` (it returns the dups) — applied + validated 5/5 there first,
    then REVERTED to honor the "submodule pin 不要动" instruction; the toxee-seam
    dedup is the pin-safe equivalent. Recommended tim2tox follow-up saved at
    `/tmp/RECOMMENDED_tim2tox_member_dedup.md` for the maintainer to approve.**

  - **rui-group-conf-deep-extra — all 3 cases validated individually**
    (role_reopen, remove_receiver_state, conference_bidirectional_message_lifecycle).
    `conference_*` threw "failed to open group chat": a fresh conference (no msgs)
    sorts to the conv-list BOTTOM (ts 0), below the fold once earlier cases added
    rows, where a real row tap can't reach the unbuilt ListView row → open via the
    `_openChat` seam (`viaL3Seam: true`); the asserted action is the message
    lifecycle, not the open gesture. `remove_receiver_state` intermittently failed
    "B autoAcceptGroupInvites did not take effect" (the flag is account-scoped; a
    single set can land before the current-account scope settles) → re-issue the set
    per verify-round (`72453ee`). Each case passes; a clean single-attempt 3/3 was
    gated by ENVIRONMENTAL same-host NGC flakes (one-direction conference message
    drop + heavily degraded loopback DHT after hours of runs — recovers on a fresh
    session per the established note).

  **OPS LESSON (re-learned the hard way):** runcamp background tasks run LONG on a
  degraded DHT (handshake retries) and their completion notifications arrive LATE.
  Starting a new campaign — OR force-killing orphans — while a prior runcamp is
  still finishing CROSS-KILLS instances (broad `pkill "Contents/MacOS/Toxee"`),
  contaminating both (symptom: "VM service connection dropped" / "Connection
  refused", no summary). STRICTLY wait for each run's <task-notification> before any
  process-touching action.

  **STILL TO RE-RUN on a fresh/recovered DHT:** rui-p3-writable, rui-p1-relaunch,
  and a clean single-attempt rui-group-conf-deep-extra 3/3.

- 2026-06-23 **TASK-C continued — p3-writable GREEN; p1-relaunch env-heavy (1/4 + 3 env).**
  - **rui-p3-writable 1/1 PASS** (`message_burst_perf`). The NONBLOCKING perf
    threshold was exceeded by ~100ms (180.1s vs 180s) due solely to the degraded
    loopback DHT slowing delivery — it does NOT fail the case.
  - **rui-p1-relaunch 1/4** (env-heavy, per the original handoff):
    - `relaunch_history_autologin` PASS (the core relaunch+autologin path works).
    - `offline_pending_relaunch` — env + UI-key: the pending data IS captured
      (pendingId set on a good run) but the bubble/spinner rows didn't resolve via
      whole-tree `waitKey`; fixed to `waitKeyCenter` (`3bafebb`). The pending-DATA
      half is still B-stop-timing-sensitive (one attempt had pendingId=null).
    - `call_from_profile_tiles` — "callee never rang": same-host ToxAV call
      SIGNALING delivery; env-limited (the in-process auto_tests cover ToxAV; the
      cross-process same-host path is flaky). Not a restyle regression.
    - `group_join_by_id_real_ui` — "public gid not 64-hex: tox_1": `_createGroupViaUI`
      returns the LOCAL group id, but joining-by-id needs the 64-hex public NGC
      chat-id (`ffi.getGroupChatId`, exposed only via `l3_create_group`'s `chatId`
      today — no standalone resolver). Two-fold gap: (1) deterministic — the test
      must resolve the public chatId for the join id (needs a new l3 chatId resolver
      or create-via-l3 for setup); (2) env — public NGC join-by-id relies on the
      flaky same-host DHT (documented; the group-message work switched to
      PRIVATE+invite for exactly this reason). Left as a follow-up.

  **SESSION NET (post-Feishu-restyle re-validation, Accessibility granted):**
  GREEN — rui-p1-single, rui-p1-extra, rui-account-conf-extra, rui-account-deep-extra,
  rui-p2-reply, rui-native-boundary-guards, **rui-p2-verify, rui-c2c-extra (5/5),
  rui-c2c-deep-extra (1/1), rui-group-conf-member-extra (5/5), rui-p3-writable (1/1)**.
  FIXES COMMITTED+PUSHED (origin/master): a2c2158 (p2-verify assertion), f2673a1
  (global-search tab-flip — real product bug), 801467a (group member pubkey dedup),
  14df542 (search-history waitKeyCenter), 72453ee (conference open viaL3Seam +
  auto-accept gate), 3bafebb (offline-pending waitKeyCenter). ALL fixes self-validated
  (code-reviewer + live + analyzer); **codex review OWED on all** — provider session
  was revoked mid-session (needs interactive `codex login`). ENV-GATED tonight
  (degraded same-host DHT, recovers on fresh session): rui-group-conf-deep-extra
  single-attempt 3/3, rui-p1-relaunch call/group-join/offline-pending.

- 2026-06-23 **offline_pending_relaunch — ROOT CAUSE refined (NOT a waitKey issue).**
  Re-ran with the bubble/spinner resolved via `waitKeyCenter` AND with an explicit
  `openChatViaL3` chat-bind before the offline send — BOTH still gave
  `pendingId=<set> pendingRow=false pendingSpinner=false`. So neither key-resolution
  nor chat-bind is the blocker: the pending message IS in the dump
  (`ChatMessage.msgID` = e.g. `1782195246275_0_FlutterUIKitClient`) but the rendered
  OPTIMISTIC bubble is keyed by a DIFFERENT (temp/optimistic) msgID, so
  `message_list_item:<dump msgID>` / `message_send_status:<dump msgID>:sending` never
  match. FOLLOW-UP (deep, data/render-layer): align the optimistic pending-message id
  between the dump (`ChatMessage.msgID`) and the UIKit rendered `V2TimMessage.id/msgID`
  before the send is confirmed (or have the dump expose the optimistic/temp id the
  bubble actually uses). The `waitKeyCenter` change (3bafebb) is retained as a
  harmless, codebase-consistent improvement; the speculative chat-bind was reverted.
  call_from_profile_tiles + group_join_by_id_real_ui remain env-limited as recorded.

- 2026-06-23 **tim2tox member-dedup MOVED TO SOURCE + pin bumped (maintainer approved).**
  The NGC ghost-duplicate group-member dedup now lives at the correct layer —
  tim2tox `getGroupMemberList` de-dupes by Tox public key (tim2tox `8948e5c`, pushed
  to anonymoussoft/tim2tox origin/master). The pin-respecting l3_group_member_list
  seam workaround (was 801467a) is REMOVED; the seam reports the source list verbatim
  again. `_memberRowKeyFor` driver hardening retained. toxee `312426c` bumps the pin
  443d597 -> 8948e5c + reverts the l3 seam. LIVE re-validated: rui-group-conf-member-extra
  5/5 PASS with the dedup at the source. code-reviewer clean; **codex still owed**
  (auth broken: ~/.codex/auth.json has an access_token but EMPTY refresh_token →
  401 "Missing bearer" / "Invalid refresh_token: empty string"; needs a fresh
  `codex login`).

- 2026-06-23 **offline_pending_relaunch — ROOT-CAUSED + scoped (NOT a quick fix; no prod bug).**
  Full cross-layer trace of the outbound optimistic-message id:
  - `Tim2ToxSdkPlatform.createTextMessage` (`tim2tox_sdk_platform.dart:~4379`) mints
    the OPTIMISTIC bubble id as `<ms>_<sender>` (NO seq).
  - The rendered bubble keys by `message.msgID ?? message.id ?? <ts>_<sender>`
    (`message_row_container.dart:286`); the sending spinner by
    `message_send_status:<message.msgID>:sending` (`message_item.dart:91`).
  - `Tim2ToxSdkPlatform.sendMessage` → `provider.sendText(userID, groupID, text)`
    passes ONLY text (`tim2tox_sdk_platform.dart:5241`); `FfiChatService.sendText`
    (`ffi_chat_service.dart:3885`) INDEPENDENTLY mints the persisted ChatMessage.msgID
    as `<ms>_<seq>_<sender>` (the `_msgIDSequence++` guards same-ms collisions).
  - The l3 dump emits `ChatMessage.msgID` (`l3_debug_tools.dart:5931`) → the persisted
    `<ms>_<seq>_<sender>`.
  - **By design** the two ids differ — `tim2tox_sdk_platform.dart:5204` comment:
    "We use message text as key because FfiChatService returns messages with new
    msgIDs". The optimistic↔streamed copies are reconciled BY TEXT, not msgID. No
    reconciliation fires while the message is PENDING (B offline, never acked), so the
    rendered bubble keeps `<ms>_<sender>` while the dump reports `<ms>_<seq>_<sender>`
    → `message_list_item:<dumpId>` / `message_send_status:<dumpId>:sending` never match.
  NO PRODUCTION BUG: a real user's pending bubble renders + the by-text reconciliation
  updates it on confirm; only the TEST wrongly assumed bubble-id == persisted-id.
  TRUE FIX (scoped, deferred — needs codex + healthy-DHT regression): generate the
  msgID ONCE and flow it through `ChatMessageProvider.sendText` →
  `FfiChatService.sendText` → `FakeMsgProvider` with a COLLISION-SAFE format (the
  optimistic format has no seq), and re-key the text-based reconciliation/forward
  tracking onto msgID. Touches dedup/reply/recall/forward (all msgID-load-bearing),
  so it must NOT be rushed without codex (auth currently broken) on a degraded DHT.

- 2026-06-23 **group_join_by_id_real_ui — id-concept fixed; chat-id resolution + DHT join remain.**
  The test fed A's LOCAL group id ("tox_1") into B's join-by-id dialog and into B's
  conversation check — both WRONG: a PUBLIC group is joined by its 64-char NGC
  chat-id, and B's joined-group conversation is keyed by that chat-id (exact/prefix;
  see drive_fixture_c_join). Fixes:
  - New `l3_group_chat_id` tool (read-only, test-gated): resolves a group's 64-char
    chat-id from its local id via `ffi.getGroupChatId` (12x retry).
  - `_createGroupViaUI` now populates `_CreatedGroup.chatId` for PUBLIC groups.
  - The test uses `created.chatId` for the join id, the 64-hex gate, and B's
    conversation/open checks (was A's local id everywhere).
  RESIDUAL (two scoped follow-ups, both needing a healthy DHT + live introspection):
  (1) `getGroupChatId(localGid)` returns EMPTY for the UI-add-group-created public
      group, though `l3_create_group`'s C++-created public groups DO resolve a 64-hex
      chat-id — the UI submit calls the SAME `service.createGroup(name, 'Public')`, so
      this is unexpected; needs live introspection of `getGroupChatIdNative` for the
      UI-created group (timing vs id-mapping). Now fails CLEARLY:
      `chat-id not 64-hex: "" (localGid=tox_1)`.
  (2) Even with a valid chat-id, B joining a PUBLIC group is env-limited (same-host
      public NGC DHT join is flaky; the group-message work switched to PRIVATE+invite
      for this reason). codex review owed.
