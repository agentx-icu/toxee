# S56 — Add duplicate friend (A2 dedup guard rejects)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online friends=≥1`
**Harness mode**: peerHarness=none
**Promotion target**: Tier 1 (existing-friend) → L2 candidate with a stub `FfiChatService.getFriendList()`. Tier 2 (session-set) L3-pinned and deferred — currently unreachable from clean MCP drive (see Notes).
**Status**: BOTH tiers covered at the widget layer (2026-06-08) — tier 2 is no longer deferred. `test/ui/add_friend_guards_test.dart` drives the real `AddFriendDialog` over a stub `FfiChatService`: tier 1 (existing-friend, `getFriendList()` dedup → `alreadyFriend` SnackBar, no `addFriend` dispatch) AND tier 2 (the in-session `_attemptedThisSession` dedup → `alreadySent` SnackBar). The tier-2 blocker ("the success path auto-dismisses via `navigator.maybePop()`, disposing the State + its session set") was a MARIONETTE limitation, not a product gap: the L1 test mounts the dialog DIRECTLY as the home body (no pushed route), so `maybePop()` is a no-op and the State survives — a first submit of id X dispatches `addFriend` once + records X, a second submit of X is rejected BEFORE any second dispatch (`addFriendCount` stays 1). Sibling S55 (self-add guard) is in the same file. Shared desktop+mobile (the guards live in `_submit`).
**Covered-by**: `test/ui/add_friend_guards_test.dart`

## Precondition
- Account A signed in, online, plaintext profile.
- Friend F already present in `getFriendList()` (verify via contact list pre-flight before dialog open).
- For tier 2 (deferred): a fresh ID P that is NOT yet a friend.
- `tox_profile.tox` mtime captured pre-flight as `PROFILE_MTIME_BEFORE`.
- `MCP_BINDING=marionette`.

## Driver
1. Confirm sidebar `<nicknameA>\nOnline`; tap `sidebar_contacts_tab` and confirm F appears; return to `sidebar_chats_tab`.
2. `marionette.tap({ key: "new_entry_menu_button" })`.
3. `marionette.tap({ key: "new_entry_add_contact_item" })` → `AddFriendDialog` mounts.
4. Tier 1: `marionette.enter_text({ key: "add_friend_id_input", input: "<F_TOX_ID>" })`.
5. `marionette.tap({ key: "add_friend_submit_button" })`.
6. Re-snapshot ≤2s — assert SnackBar text + dialog still mounted.
7. (Deferred tier 2: clear field, enter P, submit → would dismiss, breaking session-set reach. Skip.)
8. Stat `tox_profile.tox` mtime; compare to pre-flight.
9. `marionette.tap({ key: "add_friend_cancel_button" })` → dismiss.

## Assertions
- After Step 5 (≤2s): SnackBar matches `This user is already in your friend list` (fallback English in `add_friend_dialog.dart:167-170` until ARB key lands).
- Dialog stays mounted (`addFriendIdInput` still present).
- `addFriendSubmitButton.enabled == true` within ≤1s after rejection (spinner cleared via `finally` at line 212).
- Negative log grep within ≤5s of submit: no `[FfiChatService] addFriend` line for F's submit; no `TOX_ERR_FRIEND_ADD_ALREADY_SENT` surfaces.
- `tox_profile.tox` mtime diff ≤ profile-save-interval (~30s) between Step 1 and Step 8.
- Tier 2 (deferred): SnackBar `A friend request was already sent in this session` from `add_friend_dialog.dart:171-174`; synchronous early-return (≤500ms); dialog stays mounted; `_isSubmitting` never flipped.
- `get_runtime_errors({})` baseline-clean.

## Notes
- After tapping `new_entry_menu_button` (popup-revealed item) wait ~500ms for the menu animation before tapping the popup child `new_entry_add_contact_item`; otherwise marionette returns `Element matching {key: new_entry_add_contact_item} not found` (see F14 in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
- Tier 2 unreachable from MCP today: line 196's `_attemptedThisSession.add(normalizedRaw)` runs only on success, but success path auto-dismisses via line 207's `navigator.maybePop()`, disposing the State. Unlock requires the dialog to stop dismissing on success or add a "send another" affordance.
- `normalizeToxId` lower-cases and strips whitespace; both guards use it consistently.
- `getFriendList()` exceptions are swallowed at lines 189-192 — silently disables tier 1 guard. Pre-flight contact-list check is the canary.
- SnackBar texts are captured before await at lines 167-170; a refactor that moves capture inside the try block would no-op on `mounted==false`.
- A6's log negative grep is load-bearing only after `[FfiChatService] addFriend` log marker lands (currently silent).
