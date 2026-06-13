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

## Run phase (DEFERRED — owned by a later session)

The write phase is closed; the remaining live work is run-phase execution.

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
