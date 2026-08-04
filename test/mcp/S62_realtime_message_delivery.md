# S62 — Real-time message delivery (two processes)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `paired_for_e2e` = `accounts=2(A/B launched by Fixture C harness with per-instance App Support + SharedPreferences prefix isolation) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(already paired, both online) history=seeded`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because two live toxees deliver a C2C message over the real Tox DHT — no on-disk seed can stand in for the live `onNativeEvent(type==0)` round-trip, and a second running process is L3-only per `UI_TEST_LAYERING.md` §3.
**Status**: covered by executable Fixture C state driver

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`
- Two toxee instances launched by `tool/mcp_test/run_fixture_c_non_media.sh paired_for_e2e`; A/B state is isolated by `TOXEE_APP_SUPPORT_DIR`, `TOXEE_SHARED_PREFS_PREFIX`, and `TOXEE_TCCF_GLOBAL_SUBDIR`.
- A and B are **already friends** (`local_friends_<toxA>` contains normalized toxB, and vice-versa) — this is the paired post-S26 state, not a fresh request.
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`.
- Both reach Online before driving: poll the sidebar `<nick>\nOnline` semantic-snapshot ≤60s per side (the idiom S10/S61 use). Peer-connected is confirmed in the log by `[V2TIMManagerImpl] HandleFriendConnectionStatus: ENTRY - friend_number=<n>, connection_status=2` (`third_party/tim2tox/source/V2TIMManagerImpl.cpp:5846`) — A sees it for toxB, B for toxA. Both-online is the S62 invariant — distinct from S25's offline-queue path.

## Executable Driver

```bash
tool/mcp_test/run_fixture_c_non_media.sh paired_for_e2e
```

The wrapper restores `tool/mcp_test/fixtures/paired_for_e2e_A|B`, boots both
existing accounts through `l3_boot_existing_account`, sends A->B text, waits
for B to observe it as inbound, then sends B->A text and waits for A to observe
it as inbound. It stops both app processes on exit.

## UI Driver
1. On each side: poll snapshot ≤60s for sidebar `\nOnline`; baseline `official.get_runtime_errors({})`.
2. On A: `marionette.tap` on `UiKeys.sidebarChats` (`sidebar_chats_tab`); snapshot → tap B's conversation row (no `conv_<friendId>` key yet; match the row ref / label). Confirm `TencentCloudChatMessageHeader` with `<nickB>`.
3. On A: enter `"S62 A->B <nonce>"` via `UiKeys.chatInputTextField` (`chat_input_text_field`). If the wrapper key cannot directly focus the descendant field in this harness, fall back to `fmt_enter_text` on the unique chat-panel text-field ref.
4. On A: send — `fmt_press_key({key: "Enter"})` (desktop). Desktop still has no separate keyed send button contract; the stable automation path is keyboard-driven send on the focused composer.
5. On B (with B's conversation to A open, or sidebar visible): poll snapshot up to 30s for the received text / unread preview. Do NOT `sleep` — poll the snapshot + B's log.
6. Reverse: on B enter `"S62 B->A <nonce>"`, send; on A poll ≤30s for receipt. Confirms bidirectional real-time delivery.

## Assertions
- A1: A send-side log (Platform path) — the two guaranteed (unconditional `print`) markers in order: `[Tim2ToxSdkPlatform] sendMessage called: id=` (`third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:4953`) → `[Tim2ToxSdkPlatform] Found message: msgID=` (`:4992`). The intermediate `[Tim2ToxSdkPlatform] Looking for message in targetID: <toxB>` (`:4969`) is gated behind `if (_debugLog)` — assert it ONLY when debug logging is on; do not require it otherwise. NO `_queueOfflineText` (`third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:3595`) — that is the S25 offline branch and must be absent when both are online.
- A2: within 30s, B's snapshot shows a received bubble or conversation-row last-message preview equal to `"S62 A->B <nonce>"` (text round-trips verbatim).
- A3: B receive-side — the C2C text lands via `_onNativeEvent(type==0)` (`third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:4052-4068`) which builds the inbound `ChatMessage` with `isSelf == false` and calls `_appendHistory(sender, msg)`. There is no guaranteed receive-side log string here (`fake_im.dart:256` `// Received message: sender is the peer.` is a SOURCE COMMENT, not a runtime log) — verify the receive by B's snapshot text (A2) plus the connection precondition above. Note: the `[Tim2ToxSdkPlatform] Notifying new message` lines (1859/1881) are gated behind `_debugLog`; don't rely on them unless debug logging is on. `_sendReceipt` is a no-op (early `return` at `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:5191`) so no receipt marker exists.
- A4 (reverse): B→A repeats A1–A3 with sender/receiver swapped; A's snapshot shows `"S62 B->A <nonce>"`.
- A5: `official.get_runtime_errors({})` matches Step-1 baseline on both sessions.
- Negative grep (both sides): `[Tim2ToxSdkPlatform] sendMessage failed:` (`third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:5064`/5090/5359) MUST NOT appear.

## Notes
- Multi-instance validation now uses the `paired_for_e2e` Fixture C composition. On 2026-06-01 it passed restored-account boot plus bidirectional ping/pong via `tool/mcp_test/run_fixture_c_non_media.sh paired_for_e2e`.
- Distinct from S25: S62 keeps both peers online for live real-time delivery; S25 is the offline-queue → reconnect path (`offline_message_queue.json` / `_sendPendingMessages`). If A's `_queueOfflineText` fires here, the fixture is wrong (B not actually online at send time) — fix the fixture, don't relax A1.
- Send branches on the pre-check `friend.online` value at send time (`third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:3567`); don't drive Step 3 until Step 2's sidebar `\nOnline` + `HandleFriendConnectionStatus … connection_status=2` lands, or the online send silently becomes the offline branch.
- Current key status: `chat_input_text_field` is now exported from `lib/ui/testing/ui_keys.dart` and attached at toxee's `messageInputBuilder` boundary; UIKit also ships `message_list_item:<msgID>` internally. Remaining ergonomic gaps are mostly conversation-row targeting and richer send-surface semantics, so some steps still tap by ref/label as in S12.
