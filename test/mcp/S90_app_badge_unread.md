# S90 — App badge unread count (inbound bumps total, mark-read clears it)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1(echo_seeded_test) autoLogin=on network=online friends=1(echo peer, online) history=empty` (the `echo_seeded` snapshot) — OR the `paired_for_e2e` two-process base (B as the inbound source)
**Harness mode**: peerHarness=echo_live (the echo peer sends the inbound message back; `paired_for_e2e` B is the alternative source — see Notes)
**Promotion target**: L3-pinned because the badge total is driven by a live inbound message arriving over the real DHT and incrementing the conversation store's `totalUnreadCount`; a single-process L2 with no peer cannot originate the inbound that bumps it. Covers feature **K2** (应用角标: 未读 + 200ms 防抖, `lib/notifications/badge_service.dart`) — the COUNT half — plus the global-unread aggregate. Sibling of S19 (per-conversation unread N→0→0 across restart); S90 asserts the AGGREGATE dock/sidebar total via `totalUnreadCount`.
**Status**: covered (the BUMP half) by an executable L3 echo gate — the "no gate ships" claim was stale (it only looked for a `run_*.sh`; the gate is an L3 `.json`). `tool/mcp_test/scenarios/l3_total_unread_badge.json` baselines the count to 0 (warmup + `mark_read`), sends a nonce text, lets the echo peer mirror it back INBOUND, and asserts `l3_dump_state.totalUnreadCount == 1` (the only seeded conversation), via `tool/mcp_test/run_l3_scenarios.dart`. It is `nonBlocking` (the live-echo + hybrid-unread/DHT timing is race-prone, so one pass isn't proof — same posture as its sibling `l3_unread_mark_read.json`). The COMPLEMENTARY clear half (unread → 0 via mark-read) is gated by S19 (`l3_unread_mark_read.json`) and the group sibling S118/S133 (`group_menu_mark_read_unread`, blocking, live-validated). Together they cover the 0 → N → 0 round-trip the OS dock/taskbar badge reflects (the OS badge PIXEL itself is out of scope; the COUNT is the assertion). `totalUnreadCount` at `l3_debug_tools.dart:2922`; `l3_mark_read` at `l3_debug_tools.dart:1010-1090`.
**Covered-by**: `tool/mcp_test/scenarios/l3_total_unread_badge.json` (the data-layer count BUMP, L3 echo); `test/ui/mobile/home_bottom_nav_real_ui_test.dart` (UI half, L1 — the mobile bottom-nav's unread provider widget `TencentCloudChatConversationTotalUnreadCount` reactively surfaces a count only when `totalUnreadCount` is non-zero, driven through the real `setTotalUnreadCount` event-bus API; 0 → 7 → 99+ → 0)

> NOTE (mobile bottom-nav UI scope): the full phone bottom-nav bar is built by the private `_buildBottomNavigationBar` (`lib/ui/home_page.dart:1345-1486`) inside `_HomePageState`; pumping `HomePage` in a `test/` widget test is not supported (see the comment at `lib/ui/home_page.dart:218-229` — `build()` binds UIKit globals + the full IndexedStack tabs → routed to `integration_test/`). So the L1 gate above covers the production unread-PROVIDER widget the bar embeds (the load-bearing reactive count), not the bar's 4-tab/IndexedStack chrome.

## Precondition
- A signed in on a test/seed account (`echo_seeded_test` or a `paired_for_e2e` account) — mutating L3 tools refuse a non-test account (`l3_debug_tools.dart:253-258`).
- `history=empty` for the target conversation so the unread baseline is 0 (use `l3_clear_history` to reset, `l3_debug_tools.dart:934`).
- Inbound source live: echo peer reachable (`ensure_echo_peer.sh`, `peer_id` from `echo_peer.json`) OR paired B online.
- macOS arm64 for the OS-badge LOG line (`BadgeService` is platform-gated, `badge_service.dart:62-65` — `Platform.isIOS || isMacOS || isAndroid`); the `totalUnreadCount` COUNT assertion is platform-independent.
- `MCP_BINDING=marionette`.

## Driver
1. Connect; `ensureReady`; `waitForConnected`; resolve the peer Tox id (echo `peer_id`, or `toxB`).
2. `l3_clear_history(userId: <peer>)`; assert baseline `l3_dump_state.totalUnreadCount == 0`.
3. **Do NOT open the peer's conversation** (opening marks it read and suppresses the unread). Cause an inbound: send a nonce text to the echo peer via `l3_send_text` and let it echo back; OR on paired B send `l3_send_text(userId: toxA, ...)`.
4. Poll `l3_dump_state.totalUnreadCount` ≤90s until it increments to N≥1; also read `conversations[]` and confirm the matching `conversations[].unreadCount` is the same N (`l3_debug_tools.dart:2909`).
5. (macOS) poll the log ≤2s for `[BadgeService] badge written: <N>` (200ms debounce + microtask hop).
6. `l3_mark_read(userId: <peer>)` — marks the conversation read WITHOUT opening it, via the real product path `getConversationManager().cleanConversationUnreadMessageCount` → `Tim2ToxSdkPlatform` → `FfiChatService.markConversationRead` (`l3_debug_tools.dart:3047-3053`). It does NOT call `setActivePeer`, so `activePeerId` is unchanged and later inbound for that peer still counts as unread (which is exactly what the badge scenarios measure).
7. Poll `l3_dump_state.totalUnreadCount` ≤5s until it drops to 0; (macOS) poll log for `[BadgeService] badge written: 0`.

## Assertions
- A1 (baseline): Step 2 `totalUnreadCount == 0` (and the peer's `conversations[].unreadCount == 0`).
- A2 (increment, headline): after the inbound (Step 4), `totalUnreadCount == N` (N≥1) AND the peer conversation's `unreadCount == N`. Grounded: `totalUnreadCount` wraps `TencentCloudChat.instance.dataInstance.conversation.totalUnreadCount` (`uikit_data_facade.dart:200-201`); `BadgeService` subscribes the SAME `FakeIM.topicUnread` stream the conversation store sums (`badge_service.dart:79-81`).
- A3 (debounce, macOS): exactly one `[BadgeService] badge written: <N>` per debounce window — multiple inbound emits within 200ms coalesce to one write (`badge_service.dart:46`, `:91-104` cancel+restart Timer; same-value coalesce at `:99`). Marker string: `badge written: $count` (`badge_service.dart:112`).
- A4 (clear): after `l3_mark_read` (Step 7), `totalUnreadCount == 0`; (macOS) `[BadgeService] badge written: 0` appears, and no later `badge written: N>0` (no bounce-back).
- A5: `official.get_runtime_errors({})` baseline-clean; no `[BadgeService] writeBadge failed` that escalates (it is intentionally swallowed best-effort, `badge_service.dart:113-120`, so its presence is non-fatal but should not appear on macOS where the plugin IS supported).

## Notes
- OS pixel is OUT of scope: `AppBadgePlus.updateBadge` paints the real dock/launcher count, but no MCP surface reads the rendered NSDockTile/taskbar pixel. The runner-checkable signal is the in-process COUNT (`totalUnreadCount`) + the `badge written: N` log; do not claim the visual badge is verified.
- Platform gating: Linux/Windows skip A3/A4 LOG lines — `_platformPlausible` is false there (`badge_service.dart:62-65`), so `BadgeService` no-ops and writes no log. The `totalUnreadCount` COUNT assertions (A1/A2/A4) still hold on every platform.
- Echo vs paired: echo (`peerHarness=echo_live`) is the cheaper inbound source (single binary, no second toxee); paired B is heavier but exercises a real human-style send. Either bumps `totalUnreadCount` identically.
- `l3_mark_read` AWAITS the persisted lastView barrier write (`Tim2ToxSdkPlatform.cleanConversationUnreadMessageCount` awaits `FfiChatService.markConversationRead`, `tim2tox_sdk_platform.dart:4423-4450`), then fires `onConversationUnreadCleared` to refresh the list. So both A4's in-memory `totalUnreadCount==0` AND a kill+reload variant are safe without a settle buffer — the barrier is on disk before the tool returns. (An older note here claimed the barrier write was unawaited; that described the previous `setActivePeer`-based implementation and is STALE.)
- Multi-message variant: send K distinct inbound nonces before opening → assert `totalUnreadCount == K`, then mark-read → 0. The 200ms debounce means the badge may only log the final K, not each intermediate — assert the COUNT settles at K, not the count of `badge written` lines.
