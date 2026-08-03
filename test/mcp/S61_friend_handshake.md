# S61 — Friend handshake (two processes)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A/B launched by Fixture C harness with per-instance App Support + SharedPreferences prefix isolation) current(A)=A1 current(B)=B1 profileCrypt=plain autoLogin=on network=online friends=none(pre-pair) dhtCache=warm`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because it needs two live toxee processes + a real DHT handshake reaching connected — no on-disk state can fake `tox_friend_get_connection_status`. Sibling of S26 (accept-UI step) and S62 (post-handshake delivery), shares the two-sandbox fixture.
**Status**: covered by executable Fixture C state driver (UI accept surface remains S26)

> Differs from S26: S26 pins the *accept incoming request* UI step. S61 is the full bidirectional handshake — B requests, A accepts, and BOTH sides observe the peer reach `connection_status=2` (connected over UDP).

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`
- Two toxee instances launched by `tool/mcp_test/launch_fixture_c_pair.sh`; B uses a physical copied app bundle, and both sides get isolated `TOXEE_APP_SUPPORT_DIR`, `TOXEE_SHARED_PREFS_PREFIX`, and `TOXEE_TCCF_GLOBAL_SUBDIR`
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette` per instance, raw VM URI captured per side
- A's per-account pref `acct_auto_accept_friends_<first-16-of-toxA>` = `false` (UNDERSCORE-scoped via `_scopedKey`, `prefs.dart:211-215`; `_kAccountAutoAcceptFriends = 'acct_auto_accept_friends'`, `prefs.dart:81`) — auto-accept would mask the manual-accept leg
- Both reach Online before driving (sidebar `<nick>\nOnline` ≤60s per side; warm `dht_cache.json` keeps bootstrap under ~30s)
- A owns state under `.../multi_instance/A`; B owns state under `.../multi_instance/B`; never assert one side's Prefs/support files against the other's prefix/root

## Executable Driver

```bash
tool/mcp_test/run_fixture_c_non_media.sh fresh
```

The executable state driver registers A/B, sends the friend request from B to A,
accepts on A, then proves both peers can deliver A->B and B->A text. This is the
current gate for the real two-process handshake. The older UI-oriented steps
below remain useful for a manual accept-surface pass; S26 owns that UI detail.

## UI Driver
1. On B: `marionette.tap(UiKeys.sidebarContacts)` → `UiKeys.newEntryMenuButton` → wait ~500ms → `UiKeys.newEntryAddContactItem`
2. On B: `marionette.enter_text(UiKeys.addFriendIdInput, <toxA 76-hex>)`; optional `UiKeys.addFriendMessageInput`; then `marionette.tap(UiKeys.addFriendSubmitButton)`
3. On A: `marionette.tap(UiKeys.sidebarContacts)`; poll snapshot ≤20s for a New Contacts row containing toxB's first 16 hex
4. On A: prefer `marionette.tap({ key: "contact_new_contacts_tab" })` via `UiKeys.contactNewContactsTab`, then `marionette.tap({ key: "contact_application_accept_button:<toxB>" })` via `UiKeys.contactApplicationAcceptButton("<toxB>")`. Text-match on 接受 / Accept remains the fallback, disambiguated by AppBar title.
5. On BOTH: poll log ≤30s for the peer reaching connected

## Assertions
- A1: B-side post-submit log has no `addFriend failed`, `cannot add yourself`, `already in friend list`
- A2: A-side log: `[HandleFriendRequest] Received friend request from: <toxB_prefix>` (`V2TIMManagerImpl.cpp:5564`) → `[HandleFriendRequest] Storing application in pending_applications_ for GetFriendApplicationList` (`:5637`)
- A3: tapping 接受 makes the application row disappear from A's Applications view
- A4 (primary): toxB appears in A's contact list; A-side log fires `onFriendListAdded` (`tim2tox_sdk_platform.dart:3152` / `:7525`); A's `Prefs.local_friends_<first-16-of-toxA>` includes normalized toxB (`_kLocalFriends='local_friends'`, `prefs.dart:41`, scoped via `_scopedKey`)
- A5 (bidirectional, primary): A-side log `[V2TIMManagerImpl] HandleFriendConnectionStatus: ENTRY - friend_number=<n>, connection_status=2` (`:5846`) for toxB
- A6 (bidirectional, primary): within 30s, B's contact list contains toxA AND B-side log `HandleFriendConnectionStatus: ENTRY - friend_number=<n>, connection_status=2` (UDP-connected) for toxA — also `[Bootstrap] FriendConnectionStatusCallback ... connection_status=2 (0=NONE,1=TCP,2=UDP)` (`:1395`)
- A7: `[HomePage] acceptFriendRequest failed for <toxB>` (`home_page.dart:1645`) MUST NOT appear on A (logs only on failure)
- A8: `official.get_runtime_errors({})` empty vs Step-0 baseline on BOTH sessions

## Notes
- Two-instance fixture is mandatory — `pending_applications_` and `connection_status` are C++-in-memory only; no disk state can inject a connected peer. See `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`.
- On 2026-06-01 the stable fresh direction is B requests A, A accepts. A->B fresh requests can be slower/flakier immediately after both accounts are newly registered; the reusable post-handshake fixture is `paired_for_e2e`.
- Connected is `connection_status=2` (UDP) or `=1` (TCP) — the log annotates `(0=NONE,1=TCP,2=UDP)`; treat non-zero as connected, `=2` as the LAN/UDP happy path.
- Verify A's auto-accept pref before every run; if it fires first, A4 passes for the wrong reason and A3 won't observe a manual accept.
- 接受 is a `GestureDetector` without `Semantics.onTap` — `fmt_tap_widget` may no-op; use marionette text tap (same F14/menu-animation gotcha as S5/S26).
- Partial key status: `conversation_list_item:<friendId>`, `contact_new_contacts_tab`, `contact_application_item:<userID>`, and `contact_application_accept_button:<userID>` are now available.
