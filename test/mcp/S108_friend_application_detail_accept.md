# S108 — Friend application DETAIL screen accept

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=none(pre-pair)`
**Harness mode**: peerHarness=none + Fixture C — inbound friend applications are C++-in-memory `pending_applications_` only (no on-disk inject), so two live toxees on a real DHT are required. The echo peer cannot stand in (it does not drive toxee's application-detail UI).
**Promotion target**: L3-pinned — same two-live-instances constraint as S26/S61. `pending_applications_` has no disk representation; `tox_friend_get_connection_status` cannot be faked.
**Status**: covered. The accept DATA-path (a friendship is actually created) is covered TWO-PROCESS via `tool/mcp_test/run_fixture_c_accept.sh` (S26's gate) + the `handshake_detail` 2proc-ui driver. The DETAIL-screen UI is now ALSO covered by an L1 WidgetTester real-UI gate (`test/ui/contact/contact_application_detail_accept_real_ui_test.dart`): a REAL tap on `contact_application_detail_accept_button` runs the production `onAcceptApplication` end-to-end (button → bound handler → the real `contactSDK.acceptFriendApplication` wrapper → the real friendship manager, which on the SDK-not-initialized L1 path returns gracefully and runs the production application-cleanup, removing the seeded application from `dataInstance.contact`), and the post-accept RESULT-DISPLAY state (the result text replaces the action buttons) is asserted directly. The native accept SUCCESS (resultCode==0 → friendship via FFI `DartHandleFriendAddRequest`) cannot be reproduced hermetically and stays L3/2proc.
**Covered-by**: test/ui/contact/contact_application_detail_accept_real_ui_test.dart

## Precondition
- Two toxee instances in separate macOS Containers via `tool/mcp_test/launch_fixture_c_pair.sh`; isolated `TOXEE_APP_SUPPORT_DIR` / `TOXEE_SHARED_PREFS_PREFIX` / `TOXEE_TCCF_GLOBAL_SUBDIR` per side
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`, raw VM URI per side
- A's per-account pref `acct_auto_accept_friends_<toxA_prefix16>` = `false` (scoped via `_scopedKey`, `prefs.dart`; `_acceptFriendApplications` in `home_page_bootstrap.dart:794-798` would silently accept otherwise and mask the manual detail-screen accept) — CRITICAL, verify before each run
- `Prefs.local_friends_<toxA>` must NOT contain toxB pre-test; `Prefs.dismissed_friend_applications` on A absent/empty (a stale entry would swallow the application before it surfaces)
- Both sides reach Online before driving (poll `<nick>\nOnline` ≤60s per side)

## Executable Driver

```bash
tool/mcp_test/run_fixture_c_accept.sh
```

S26's gate: launches a FRESH pair, the driver registers two accounts, B sends a friend request to A, A polls until the pending application surfaces, A accepts via `l3_accept_friend_request`, then asserts B is in A's `friends[]` and the application left A's `friendApplications[]`. This covers the accept **data-path** end-to-end. It accepts programmatically — it does NOT open the application-detail screen or tap `contact_application_detail_accept_button`. S108 is that UI-control complement.

## UI Driver
1. On B: drive the add-friend dialog with toxA's full 76-hex address. Keys: `UiKeys.newEntryMenuButton` (`new_entry_menu_button`) → wait ~500ms → `UiKeys.newEntryAddContactItem` (`new_entry_add_contact_item`) → `marionette.enter_text(UiKeys.addFriendIdInput, <toxA 76-hex>)` → optional `UiKeys.addFriendMessageInput` with a recognizable wording → `marionette.tap(UiKeys.addFriendSubmitButton)`
2. On A: `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`)
3. On A: `marionette.tap({ key: "contact_new_contacts_tab" })` via `UiKeys.contactNewContactsTab` (`contact_new_contacts_tab`); poll snapshot ≤20s for a row `contact_application_item:<toxB>`
4. On A: **open the detail screen** — `marionette.tap({ key: "contact_application_item:<toxB>" })` via `UiKeys.contactApplicationItem("<toxB>")`. The row `GestureDetector.onTap` (`tencent_cloud_chat_contact_application_list.dart:226-228`) calls `gotoApplicationInfoPage`, which `Navigator.push`-es `TencentCloudChatContactApplicationInfo` (`:84-90`). Wait ~500ms for the route.
5. On A: `fmt_semantic_snapshot` → record label `S108_application_detail_open`; confirm the detail page mounted (the `tL10n.agree` / `tL10n.refuse` rows)
6. On A: `marionette.tap({ key: "contact_application_detail_accept_button:<toxB>" })` via `UiKeys.contactApplicationDetailAcceptButton("<toxB>")` — the DETAIL-screen accept (distinct from the inline row accept S26 taps). This `GestureDetector.onTap` is `onAcceptApplication` (`tencent_cloud_chat_contact_application_info.dart:370-374`).
7. On BOTH: poll log/snapshot ≤30s for the peer reaching connected

## Assertions
- A1: Step-1 B-side post-submit log has no `addFriend failed`, `cannot add yourself`, `already in friend list`
- A2: A-side log markers in order (unconditional `fprintf`): `[HandleFriendRequest] Received friend request from: <toxB_prefix>` (`V2TIMManagerImpl.cpp:5576`/stderr `:5578`) → `[HandleFriendRequest] Storing application in pending_applications_ for GetFriendApplicationList` (`:5650`)
- A3: Step-3 — pending application surfaces on A within 20s; snapshot contains `contact_application_item:<toxB>`
- A4: Step-5 — the detail screen mounted; snapshot contains `contact_application_detail_accept_button:<toxB>` and `contact_application_detail_decline_button:<toxB>` (`tencent_cloud_chat_contact_application_info.dart:371-373`/`:387-389`)
- A5 (primary): after Step 6, `l3_dump_state.friends[]` on A includes toxB (`l3_debug_tools.dart:3593`) — accept created the friendship
- A6 (primary): after Step 6, `l3_dump_state.friendApplications[]` on A no longer contains an entry with `userId == <toxB>` and `friendApplicationCount` decremented (`l3_debug_tools.dart:3604-3608`) — the application left the queue
- A7 (bidirectional): within 30s, B's `l3_dump_state.friends[]` contains toxA; B-side log `HandleFriendConnectionStatus: ENTRY - ... connection_status=2` (UDP-connected) for toxA
- A8: `[HomePage] acceptFriendRequest failed for <toxB>` (`home_page.dart:1645`) MUST NOT appear on A (logs only on failure)
- A9: `official.get_runtime_errors({})` empty vs Step-0 baseline on BOTH sessions

## Notes
- L3-pin reason: `pending_applications_` is C++-in-memory only (no on-disk file to inject) → two live toxees mandatory; same constraint S26/S61 record. See `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`.
- Keys verified: `contact_application_item:<userID>` at `tencent_cloud_chat_contact_application_list.dart:227` (GestureDetector, onTap → `gotoApplicationInfoPage`); `contact_application_detail_accept_button:<userID>` at `tencent_cloud_chat_contact_application_info.dart:371-373` (GestureDetector, onTap → `onAcceptApplication`); decline sibling at `:387-389`.
- Sibling distinction: **S26 accepts INLINE** via `contact_application_accept_button:<userId>` (the row's own accept button, `tencent_cloud_chat_contact_application_list.dart:464-467`) without leaving the list. **S108 opens the row first** (`gotoApplicationInfoPage` → detail page) and accepts via `contact_application_detail_accept_button:<userId>` on the pushed `TencentCloudChatContactApplicationInfo`. Both reach the same `acceptFriend` data-path (run_fixture_c_accept.sh's gate); the UI entry differs.
- Both detail buttons are `GestureDetector` with `onTap` and NO `Semantics.onTap` → `fmt_tap_widget` may no-op; use marionette key/text tap. Wait ~500ms after the row tap for the push animation (F14).
- Verify A's auto-accept pref before every run; if it fires first, A5 passes for the wrong reason and Step 6 never observes a manual detail accept.
- Mobile parity: the friend-application detail screen (`tencent_cloud_chat_contact_application_info.dart` in the contact fork) and its `contact_application_detail_accept_button:<uid>` key are SHARED UIKit widgets (no platform split) → iOS/Android render the same detail screen + key and route through the same `onAcceptApplication` → `acceptFriend` data-path, so this scenario covers mobile via the same anchor.
