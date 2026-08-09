# S118 — Conversation row: Mark-read via context-menu item (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1 history=seeded(≥1 inbound unread)`
**Harness mode**: peerHarness=echo_live
**Promotion target**: L1 WidgetTester for the real menu-open + item tap (`chat_core_real_ui_test.dart:368` proves the conversation menu opens; the mark-read item is keyed). The unread→0 ASSERTION is L3 only and currently **expected-fail via this menu path** — see Status.
**Status**: covered at the widget layer (L1) — the mark-read item's enabled/disabled state based on hasUnread is gated by `test/ui/conversation/conversation_row_menu_c2c_real_ui_test.dart` (test "S118 C2C mark-read item is enabled when hasUnread, disabled otherwise"). The two-process real-UI gate also LIVE-VALIDATED 2026-06-08 (the prior "EXPECTED-FAIL / no-op" conclusion was STALE).
**Covered-by**: `test/ui/conversation/conversation_row_menu_c2c_real_ui_test.dart` The menu's `cleanConversationUnreadMessageCount` is NOT a no-op: it calls `ffiService.markConversationRead` (`tim2tox_sdk_platform.dart:4257-4284`) which advances the persisted read barrier (`markConversationViewed`), flags messages `isRead`, zeroes the in-memory unread counter, and fires `onConversationUnreadCleared` to refresh the list — so the context-menu Mark-as-read genuinely drives unread→0. The `group_menu_mark_read_unread` gate (`drive_real_ui_pair.dart`, campaign `group-menu-mark-read-unread`) establishes a two-process group, clears A's active conversation (`l3_set_active_conversation`), has B send so A accrues REAL unread (`ffi_chat_service`: `_activePeerId != gid` → `_unreadByPeer[gid]++`), asserts A's row `unreadCount>0`, marks read via the row menu's `mark_read` action (the SAME `_dispatchConversationMenuAction` the menu runs), and asserts `unreadCount→0`. **Live: PASS (unread>0 → 0, gid=tox_1).** The menu `mark_read` dispatch is identical for C2C and group rows, so this also covers the C2C conversation-row case. Shared desktop+mobile. See [[real_ui_group_message_fresh_nontest]].

> Real-MENU upgrade of S19. S19's open-conversation "mark as read" is `setActivePeer` → `markConversationViewed`. The toxee context-menu Mark-read item instead calls `cleanConversationUnreadMessageCount` (home_page.dart:1619-1625), which `Tim2ToxSdkPlatform` **implements for real** (tim2tox_sdk_platform.dart:4423-4450): it awaits `FfiChatService.markConversationRead` (ffi_chat_service.dart:1315-1328) — which advances the persisted read barrier via `markConversationViewed`, flags the conversation's current non-self messages `isRead`, and zeroes the in-memory GROUP counter WITHOUT changing `_activePeerId` — then fires `onConversationUnreadCleared` so the conversation list + badge refresh. So the menu item is keyed, tappable, AND genuinely clears unread. The earlier "Tim2Tox no-op / EXPECTED-FAIL" reading in this playbook is **STALE**.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Echo peer running**: `bash tool/mcp_test/ensure_echo_peer.sh` (idempotent; captures `peer_id` from `tool/mcp_test/echo_peer.json`; bot mirrors c2c text verbatim). Teardown `bash tool/mcp_test/stop_echo_peer.sh`. Peer must reach Online (poll, don't sleep) so an inbound mirror lands and increments unread.
- Seed an unread: send `mark-read-probe-<nonce>` to the peer; the echo mirrors it back as INBOUND (`isSelf:false`), so `l3_dump_state` for the peer reports `unreadCount >= 1` and `totalUnreadCount >= 1`. (`unreadCount` is read path-independently from `FfiChatService.getC2CUnreadCount`, l3_debug_tools.dart:7104, so the count is the same value `l3_mark_read` zeroes.)
- Account A logged in, plaintext, sidebar Online (poll ≤60s); context-menu handler registered (no `[HomePage] Failed to register conversation context-menu handlers`, home_page.dart:376).
- F's row present as `UiKeys.conversationListTile("c2c_<toxF>")` (`conversation_list_item:c2c_<toxF>`, fork tencent_cloud_chat_conversation_list.dart:118). With `hasUnread == true`, the mark-read item renders **enabled** (home_page.dart:144).

## Executable Driver

```bash
dart run tool/mcp_test/run_l3_scenarios.dart   # includes tool/mcp_test/scenarios/l3_unread_mark_read.json (nonBlocking)
```

`l3_unread_mark_read.json` is the data-half for the mark-read path: warmup → `send_text` → `wait_for message_exists isSelf:false` → `wait_for unread_at_least 1` → `mark_read` → assert `unreadCount == 0`. The `l3_mark_read` tool drives the SAME product entry point the menu item does — `getConversationManager().cleanConversationUnreadMessageCount` → `Tim2ToxSdkPlatform` → `FfiChatService.markConversationRead` (l3_debug_tools.dart:3047-3053). It does NOT call `setActivePeer` and does NOT make the conversation active, and the barrier write is AWAITED, so an immediate assertion and a kill+reload assertion are both safe. It is `nonBlocking` (the live echo + DHT timing makes `unread > 0` race-prone; one pass is not proof). S118's marionette MENU tap below exercises the keyed UI item, which routes into that same `cleanConversationUnreadMessageCount` — so the UI tap DOES reproduce the runner's unread→0 (A3/A4).

## UI Driver
1. `marionette.tap(UiKeys.sidebarChats)` (`sidebar_chats_tab`); baseline `official.get_runtime_errors({})`. Capture the seeded `unreadCount` (≥1) and `totalUnreadCount` for the peer from `l3_dump_state`.
2. Open the row's menu on `UiKeys.conversationListTile("c2c_<toxF>")`:
   - **DESKTOP**: right-click → `onSecondaryTapConversationItem` → `_showConversationContextMenu` (home_page.dart:328-336, :1582).
   - **MOBILE/marionette**: `marionette.long_press(...)` (`ext.flutter.marionette.longPress`) → `onLongPressConversationItem` → same handler (home_page.dart:337-345).
3. Tap `UiKeys.conversationContextMenuMarkReadItem` (`conversation_context_menu_mark_read_item`, home_page.dart:142, value `'mark_read'`). This invokes `cleanConversationUnreadMessageCount` (home_page.dart:1619-1625).
4. Poll `l3_dump_state` ≤2s and re-read the peer's `unreadCount` / `totalUnreadCount`.

## Assertions
- A1 (seeded unread, control): Step 1 — the peer's `conversations[].unreadCount >= 1` and `totalUnreadCount >= 1` (proves the gate is non-vacuous; without it A3 is meaningless).
- A2 (item enabled): the mark-read item renders enabled (`hasUnread == true`, home_page.dart:144); it is tappable, not greyed.
- A3 (**headline**): after tapping the menu item, the peer's `unreadCount` drops to `0` and `totalUnreadCount` decrements by the cleared amount — `cleanConversationUnreadMessageCount` awaits `FfiChatService.markConversationRead` and then fires `onConversationUnreadCleared` (tim2tox_sdk_platform.dart:4423-4450). Poll rather than read a single cold dump: the platform call is async and the list refresh is one hook hop behind it. (This assertion was historically marked `expected-fail` against a no-op platform stub; that is no longer the implementation.)
- A4 (no error path): `[HomePage] cleanConversationUnreadMessageCount failed for <convId>` (home_page.dart:1628) MUST NOT appear — the platform returns `code: 0` on success and only reports `code: -1` when `markConversationRead` throws.
- A5 (persistence, cross-ref): the clear is durable, not just in-memory — `markConversationRead` awaits `markConversationViewed`, so `chat_history/c2c_<toxF>.json` has `lastViewTimestamp >= max(msg.timestamp)` and zero `isSelf==false && isRead==false` rows. A kill+relaunch (S19 Steps 9-10 discipline) must still show `unreadCount == 0`. `l3_unread_mark_read.json` asserts the same observable head-lessly.
- A6: `official.get_runtime_errors({})` matches the Step-1 baseline.

## Notes
- L3-pin reason: the unread→0 side-effect needs a live inbound (real DHT peer) to seed a non-vacuous unread count; the menu SURFACE alone is L1-mountable. The clear itself is real — `cleanConversationUnreadMessageCount` → `FfiChatService.markConversationRead` (tim2tox_sdk_platform.dart:4423-4450). Note `cleanTimestamp`/`cleanSequence` are deliberately NOT forwarded: they are a V2TIM server message-sequence concept with no Tox analogue, and every caller passes 0/0, which is exactly "mark everything currently in the conversation read" — what `markConversationViewed` does.
- Keys verified: `conversationContextMenuMarkReadItem` @ home_page.dart:142 (defined ui_keys.dart:185-186); the call site is home_page.dart:1614-1625. The item is `enabled: hasUnread` (home_page.dart:144).
- Carry S19's caveat: `l3_unread_mark_read.json` is `nonBlocking`/FLAKY (live echo + DHT timing; per-run `{{nonce}}` so stragglers can't be miscounted). The unread/DHT race means one pass is not proof — the flakiness is in SEEDING the unread, not in clearing it.
- Sibling distinction: S19 = mark-read via open-conversation (`setActivePeer`, which also makes the conversation active); S118 = the real menu-item tap (`cleanConversationUnreadMessageCount`, which clears WITHOUT opening — `_activePeerId` is untouched). S116 = pin item, S117 = menu surface, S119 = delete item. S133 is the group sibling of S118 (identical menu dispatch).
- Desktop right-click vs mobile long-press: both route to the SAME `_showConversationContextMenu` (home_page.dart:334/343) → mobile gets the same real clear (shared Dart path). No mobile-specific divergence.
