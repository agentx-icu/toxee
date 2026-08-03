# S26 — Accept incoming friend request

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=none(pre-pair)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — `pending_applications_` is in-memory only on the C++ side, so this needs two live toxees on a real DHT. Sibling of S27 (decline) which shares the fixture shape.
**Status**: covered

## Precondition
- Two toxee instances in separate macOS Containers (distinct `CFBundleIdentifier` — e.g. `Toxee_B.app` with id `com.toxee.b.app`) so `SharedPreferences` don't clobber
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`
- A's pref `acct_auto_accept_friends_<toxA_prefix16>` = `false` (the scoped key read by `Prefs.getAutoAcceptFriends`, `prefs.dart:645`; legacy unscoped `auto_accept_friends` is the `false` fallback) — CRITICAL, `_acceptFriendApplications` in `home_page_bootstrap.dart:794-798` would silently accept otherwise, masking the test
- Both reach Online before driving (poll `<nick>\nOnline` ≤60s per side)

## Driver
1. On B: drive add-friend dialog with toxA's full 76-char address. Keys: `new_entry_menu_button` → `new_entry_add_contact_item` → `add_friend_id_input` → `add_friend_submit_button`. Optional message text.
2. On A: `marionette.tap({ key: "sidebar_contacts_tab" })`
3. Poll snapshot on A up to 20s for the New Contacts badge `_applicationUnreadCount ≥ 1` or `TencentCloudChatContactApplicationItem` row containing toxB's first 16 chars
4. Prefer `marionette.tap({ key: "contact_new_contacts_tab" })` via `UiKeys.contactNewContactsTab`. Label/ref tapping remains the fallback if the tab key lookup regresses.
5. Prefer `marionette.tap({ key: "contact_application_accept_button:<toxB>" })` via `UiKeys.contactApplicationAcceptButton("<toxB>")`. Text-match on 接受 / Accept remains the fallback if the row key lookup regresses.

## Assertions
- A1: pending application surfaces on A within 20s — semantic snapshot contains row with toxB prefix
- A2: tapping 接受 makes the row disappear from Applications view
- A3 (primary): toxB appears in A's contact list
- A4: `Prefs.local_friends_<toxA_prefix16>` (scoped via `_scopedKey`, 16-char toxId prefix) includes normalized toxB key after accept
- A5: log on A contains `NotifyFriendApplicationListDeleted` after accept, no further `Storing application in pending_applications_` for toxB
- A6 (bidirectional, primary): within 30s of accept, B's contact list contains toxA; log on B: `friend connection status: friendNumber=<n> status=2`
- A7: `[FfiChatService] acceptFriendRequest: FFI returned rc=` MUST NOT appear on A (this line logs only on failure)
- A8: `official.get_runtime_errors({})` empty vs Step 0 baseline on both sessions
- A9: the `dismissed_friend_applications` SharedPreferences key (FfiChatService, `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:3864`; `|`-separated fingerprints) on A does not contain any `<normalized_toxB>|` entry (clean-up after accept)
- Log markers on A in order: `[HandleFriendRequest] Received friend request from: <toxB_prefix>` → `[HandleFriendRequest] Storing application in pending_applications_` → tap → `NotifyFriendApplicationListDeleted` → `onFriendListAdded`

## Notes
- After tapping `new_entry_menu_button` (popup-revealed item) wait ~500ms for the menu animation before tapping the popup child `new_entry_add_contact_item`; otherwise marionette returns `Element matching {key: ...} not found` (see F14 in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
- Two-instance fixture is mandatory: `pending_applications_` is C++-in-memory only; there is no on-disk file you can edit to inject one
- If A's auto-accept fires first, the test passes for the wrong reason — verify the pref before each run
- The 接受 button is a `GestureDetector` without `Semantics.onTap`, so `fmt_tap_widget` may silently no-op; fall back to text-based marionette tap
- Partial key status: `contact_new_contacts_tab`, `contact_application_item:<userID>`, `contact_application_accept_button:<userID>`, and `contact_application_decline_button:<userID>` are now available on the application list surface.
- Detail-surface status: if the row is opened instead of accepted inline, the detail page now exposes `contact_application_detail_accept_button:<userID>` and `contact_application_detail_decline_button:<userID>`.
- Both bundles need their own Container — same constraint as Fixture C in the playbook
