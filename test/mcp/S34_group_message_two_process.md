# S34 — Group message send + receive (two processes)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `paired_for_e2e` = `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online groups=[gidG joined by both] history=empty`
**Harness mode**: peerHarness=none (two real toxees; echo peer is NOT a substitute — `MCP_UI_TEST_PLAYBOOK.en.md` §3.7)
**Promotion target**: L3-pinned because a group text crosses the live Tox NGC DHT between two toxee processes — the inbound copy arrives via the C++ `setGroupMessageGroupCallback` → `HandleGroupMessageGroup` path (`third_party/tim2tox/source/V2TIMManagerImpl.cpp:345`/`413`/`423`), which no on-disk seed can stand in for, and a second running process is L3-only per `UI_TEST_LAYERING.en.md` §3.
**Status**: covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_group.sh` (A `l3_create_group` → local id `tox_N` + 64-char chat-id; B `l3_join_group(chatId)` joins the PUBLIC NGC group by chat-id, no invite; A↔B `l3_send_group_text` roundtrip asserted via `l3_dump_state {conversationId:group_<gid>}` group history). Validated live 2026-06-01. Note: the creator keys history by its LOCAL id, the joiner by the chat-id, so the driver reads by trying all `knownGroups`/type-2 candidate keys; the first group message can drop before NGC sync, so the driver re-sends once.

## Precondition
- Two toxee instances in separate macOS Containers with distinct `CFBundleIdentifier` (A = `com.toxee.app`, B = `com.toxee.b.app`) so `SharedPreferences` / disk state don't clobber — same constraint as S26/S62.
- Both A and B have `<gidG>` in `Prefs.groups` (scoped `local_groups`/`groups` per account) and NOT in `quit_groups_list` — i.e. the post-S32(create on A) + S33(join on B) state. `_knownGroups` on both contains `<gidG>`.
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`.
- Both reach Online (poll sidebar `<nick>\nOnline` ≤60s per side) AND the NGC group is connected: A is host (created via `tim2tox_ffi_create_group`), B joined via `tox_group_join`. Group-connected is the S34 invariant — a group text only routes when `FfiChatService._isConnected` is true at send time (`third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:5478`).

## Driver
1. On each side: poll snapshot ≤60s for sidebar `\nOnline`; baseline `official.get_runtime_errors({})`.
2. On A: `marionette.tap` on `UiKeys.sidebarChats` (`sidebar_chats_tab`); snapshot → tap `<gidG>`'s conversation row (no `conv_<groupId>` key yet; proposed `conv_list_group_tile:<gid>` per S33/S36 — match the row ref / group-name label). Confirm group chat panel header shows the group name.
3. On A: enter `"S34 A->G <nonce>"` via `UiKeys.chatInputTextField` (`chat_input_text_field`). If the wrapper key cannot directly focus the descendant field in this harness, fall back to `fmt_enter_text` on the chat-panel text-field ref.
4. On A: send. Desktop input is Enter-to-send with NO tappable send button (`UiKeys.chatSendButton` caveat, `ui_keys.dart:96-105`; playbook §6b †). Synthetic `fmt_press_key({key:"Enter"})` does NOT reach the legacy `RawKeyEvent` handler — inject a REAL OS Return via `osascript … key code 36` (playbook §7b "Message send via Enter key"). This is required for the live-DHT round-trip.
5. On B (group conversation open, or sidebar visible): poll snapshot up to 30s for the received text / unread preview. Do NOT `sleep` — poll snapshot + B's log.
6. Reverse: on B enter `"S34 B->G <nonce>"`, send via real Return; on A poll ≤30s for receipt. Confirms bidirectional group delivery.

## Assertions
- A1 (A send path): the group text is sent through `FfiChatService.sendGroupText(groupId, text)` (`third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:5471`) which calls the FFI `sendGroupText` binding (`:5484`; raw binding `third_party/tim2tox/dart/lib/ffi/tim2tox_ffi.dart:367` → C `tim2tox_ffi_send_group_text` `third_party/tim2tox/ffi/tim2tox_ffi.cpp:1501` → `SendGroupTextMessage` `:1510`). NO `_queueOfflineGroupText` (`ffi_chat_service.dart:5479`/`5504`) — that is the offline branch and must be absent when the group is connected.
- A2: within 30s, B's snapshot shows a received group bubble or conversation-row last-message preview equal to `"S34 A->G <nonce>"` (text round-trips verbatim).
- A3 (B receive path): the inbound NGC text lands via the C++ group callback `HandleGroupMessageGroup` (registered by `setGroupMessageGroupCallback`, `V2TIMManagerImpl.cpp:345`/`413`) and surfaces to Dart in `_onNativeEvent` with `type == 10`, sender format `"g|<groupID>|<senderID>"` (`ffi_chat_service.dart:4327-4332`); it builds the inbound `ChatMessage` with `isSelf == (from == _selfId)` and calls `_appendHistory(gid, msg)` (`:4362`). There is no guaranteed receive-side `print` string — verify the receive by B's snapshot text (A2) plus the group-connected precondition.
- A4: B's `_unreadByPeer[gidG]` increments while B's active peer is not `<gidG>` (`ffi_chat_service.dart:4357-4361`); the unread badge clears when B opens the group conversation.
- A5 (reverse): B→A repeats A1–A3 with sender/receiver swapped; A's snapshot shows `"S34 B->G <nonce>"`. A's inbound copy is NOT flagged as a duplicate (`_isDuplicateGroupTextMessage`, `ffi_chat_service.dart:4336`/`4378`) since the (gid, from, text) tuples differ.
- A6: `official.get_runtime_errors({})` matches Step-1 baseline on both sessions.
- Negative grep (both sides): `[FfiChatService] _sendPendingGroupMessages` (`ffi_chat_service.dart:5538`/`5543`) MUST NOT appear during a both-connected send — its presence means a side was disconnected at send time and the message was queued, not live-delivered (fix the fixture, don't relax A1).

## Notes
- **Multi-instance block**: two live toxees on the real DHT is the `paired_for_e2e` (Fixture C) composition, never validated as test infra — spike contract + acceptance criteria in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`; status stays `blocked on Fixture C spike` until that passes (`UI_TEST_LAYERING.en.md` §6). The echo peer (`peerHarness=echo_*`) is a single non-toxee C2C process and CANNOT stand in for a second group member (playbook §3.7).
- C++ may deliver the same group text twice (conference + group callback) — `_isDuplicateGroupTextMessage` (5s window, `ffi_chat_service.dart:4378`) dedupes; if a doubled bubble shows up, that dedup window is the regression gate, not the send path.
- Send branches on `FfiChatService._isConnected` at send time (`ffi_chat_service.dart:5478`); don't drive Step 3 until both sidebars show `\nOnline` and the group is joined on both sides, or the live send silently becomes `_queueOfflineGroupText` and A2 never arrives.
- Current key status: toxee exports `chat_input_text_field`, and UIKit message rows carry `message_list_item:<msgID>` internally. Group conversation rows still largely rely on ref/label targeting, so tap-by-ref remains the practical path for the list-open step.
