# S51 — Friend online/offline presence indicator

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A in com.toxee.app, B in com.toxee.b.app — separate sandboxes) current(A)=A1 current(B)=B1 profileCrypt=plain autoLogin=on network=online friends=1(A↔B paired) dhtCache=warm`
**Harness mode**: peerHarness=none (two-toxee, NOT echo peer)
**Promotion target**: L3-pinned — presence derives from `tox_friend_get_connection_status` in C++ memory; no disk state can fake a live online→offline→online flip.
**Status**: covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_presence.sh` (3 phases: boot+confirm A↔B online → stop B / A sees B go offline → relaunch+reboot B / A sees B back online). Validated live 2026-06-01.

## Precondition
- A↔B already friends (skip AddFriend): A's `Prefs.local_friends_<first16-toxA>` has normalized toxB (`local_friends`, `lib/util/prefs.dart:41`, scoped via `_scopedKey` `:211`).
- Two sandboxes, distinct `CFBundleIdentifier`; both plaintext, `autoLogin=on`, locale=`en`, raw VM URI per side.
- Both Online (sidebar `<nick>\nOnline` ≤60s); ≥1 C2C conversation with toxB on A (dot is mountable).

## Driver
1. A: `marionette.tap(UiKeys.sidebarChats)`; baseline `official.get_runtime_errors({})` both sides.
2. Take B offline: kill toxB binary (`pgrep -fl com.toxee.b.app`, kill the binary not the wrapper) or `ifconfig <iface> down` on B.
3. A: poll log ≤60s for B `connection_status=0` (A2); poll A snapshot ≤60s for dot to clear.
4. Bring B back: relaunch toxB (reconnect MCP) or `ifconfig <iface> up`.
5. A: poll log ≤120s (cold re-bootstrap is slow) for B `connection_status=2`; poll snapshot for dot to reappear.

## Assertions
- A1 (baseline): on A's Chats tab toxB's `UiKeys.conversationItemOnlineDot("c2c_<toxB>")` anchor is filled — gated on `getIsOnline()` → `_userStatusList[].statusType == 1` (`tencent_cloud_chat_conversation/lib/widgets/tencent_cloud_chat_conversation_list.dart:86`/`:93`); rendered `color: widget.isOnline ? colors.conversationItemUserStatusBgColor : Colors.transparent` (`.../tencent_cloud_chat_conversation_item.dart:428`).
- A2 (offline): A log `[V2TIMManagerImpl] HandleFriendConnectionStatus: ENTRY - friend_number=<n>, connection_status=0` for toxB (`V2TIMManagerImpl.cpp:5846`); statusType→OFFLINE via `(connection_status != TOX_CONNECTION_NONE)` (`:5878`).
- A3: A's dot clears. Fan-in: driver `V2TimUserStatus(statusType: u.online ? 1 : 0)` (`lib/ui/home_page_bootstrap.dart:746`) → `buildUserStatusList` (`:749`); also the 2s poll `_setupFriendStatusChecker` (`tim2tox_sdk_platform.dart:2543`) fires `onUserStatusChanged` with `statusType: currentOnline ? 1 : 0` (`:2560`).
- A4 (online): A log `HandleFriendConnectionStatus: ENTRY - ... connection_status=2` (UDP) after Step 4; A's dot re-fills within the poll window.
- A5: A log `[V2TIMManagerImpl] HandleFriendConnectionStatus: Notifying <k> SDK listeners (...)` (`:5891`) per transition (proves fan-out, not just entry).
- A6 (self-side, negative): A keeps showing online to B — A log has the one-time `HandleSelfConnectionStatus: Notified self online status` (`:5461`) at startup but NO repeated self churn during B's downtime; on a B-reconnect A may emit `Re-set status to ensure friend <pk> can see us as online` (`:5941`).
- A7 (negative): A log MUST NOT contain `HandleFriendConnectionStatus: Failed to get public key` (`:5870`) for toxB.
- A8: `official.get_runtime_errors({})` == Step-1 baseline both sides; no `FATAL`/`bad_alloc`/`tox_kill`.

## Notes
- Two-instance fixture is mandatory and **blocked on Fixture C spike** (`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`); echo peer is NOT a substitute (single non-toxee process — playbook §3.7).
- Connected = `connection_status=2` (UDP) or `=1` (TCP); C++ annotates `(0=NONE,1=TCP,2=UDP)` at `:1395`. Treat non-zero as online.
- Two presence sources race: the C++ `HandleFriendConnectionStatus` push AND the Dart 2s poll. Either flips the dot — assert on the log line for determinism, the dot for the user-visible effect; allow ≤2s poll slack.
- In-chat AppBar presence still has no stable key — fall back to `inspect_widget_at_point`. The conversation row itself is now targetable via `conversation_list_item:<friendId>`, and the row's presence dot now exposes `conversation_item_online_dot:<conversationId>`.
