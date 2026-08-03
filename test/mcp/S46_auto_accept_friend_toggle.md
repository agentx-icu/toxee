# S46 — Auto-accept friend request toggle

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=none(pre-pair)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because it needs two live toxees on a real DHT — the inbound friend request and auto-accept handshake only exist over the live network (`pending_applications_` is C++ in-memory only). Inverse of S26 (which requires the toggle OFF); shares the same two-sandbox fixture shape.
**Status**: covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_autoaccept_friend.sh` (recipient autoAcceptFriends=true via l3_set_setting [live applier], twin sends a friend request, recipient AUTO-adds it with no manual accept; asserts friends gains the twin + no pending application). Validated live 2026-06-01.

## Precondition
- Two toxee instances in separate macOS Containers (distinct `CFBundleIdentifier` — e.g. `Toxee_B.app` with id `com.toxee.b.app`) so `SharedPreferences` don't clobber
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`
- A's pref `acct_auto_accept_friends_<toxA_prefix16>` starts `false` (default; `Prefs.getAutoAcceptFriends` falls back to `false`) — Phase 1 flips it ON, Phase 2 flips it OFF
- B is NOT yet in A's `local_friends_<toxA>` (pre-pair)
- Both reach Online before driving (poll `<nick>\nOnline` ≤60s per side)

## Driver
**Phase 1 — toggle ON, auto-accept fires**
1. On A: `marionette.tap({ key: "sidebar_settings_tab" })` (`UiKeys.sidebarSettings`)
2. Tap the "Auto-accept friend requests" Switch. No key today (`settingsAutoAcceptFriendToggle` not yet added) — tap by `Switch` snapshot ref next to the `Auto-accept friend requests` label; `Switch` has no text fallback
3. Verify Switch flips `selected: true`
4. On B: drive add-friend dialog with toxA's full 76-char address. Keys: `new_entry_menu_button` → `new_entry_add_contact_item` → `add_friend_id_input` → `add_friend_submit_button`
5. On A: poll snapshot up to 30s for the auto-accept SnackBar and toxB in the contact list — NO manual tap on any Applications row

**Phase 2 — toggle OFF, request stays pending**
6. On A: re-enter Settings, tap the same Switch to `selected: false`
7. From a fresh B-side identity (or re-pair), B sends A a friend request again
8. On A: poll Contacts → New Contacts tab; the application MUST sit pending (no SnackBar, no auto-add) — exactly the S26 inverse

## Assertions
- A1 (Phase 1): after toggle ON, read from **A's** domain — `defaults read com.toxee.app flutter.acct_auto_accept_friends_<toxA_prefix16>` returns `1` (A is the account that toggled; `com.toxee.b.app` is B the requester's container, not A's)
- A2 (Phase 1, primary): A auto-accepts WITHOUT manual interaction — SnackBar text matches `autoAcceptedNewFriendRequest` ("Auto-accepted new friend request", `home_page.dart:1652`)
- A3 (Phase 1, primary): toxB appears in A's contact list within 30s; `Prefs.local_friends_<toxA>` includes normalized toxB key
- A4 (Phase 1): A's log shows `[HandleFriendRequest] Storing application in pending_applications_` immediately followed by the `_acceptFriendApplications` path (`home_page_bootstrap.dart:794-798`) → `NotifyFriendApplicationListDeleted`, with NO operator tap in between
- A5 (Phase 1): `[FfiChatService] acceptFriendRequest: FFI returned rc=` (`ffi_chat_service.dart:3950`) MUST NOT appear on A (logs only on failure)
- A6 (Phase 2): after toggle OFF, `defaults read com.toxee.app flutter.acct_auto_accept_friends_<toxA_prefix16>` (A's domain) returns `0`; the second request surfaces in New Contacts and stays pending (no `autoAcceptedNewFriendRequest` SnackBar, no `NotifyFriendApplicationListDeleted` without a manual accept)
- A7: `official.get_runtime_errors({})` empty vs Step 0 baseline on both sessions

## Notes
- Multi-instance fixture (two toxees in separate Containers, live DHT) is mandatory and is exactly what is BLOCKED on the Fixture C spike — see `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`. Per `doc/architecture/UI_TEST_LAYERING.en.md` §6, this thin spec is retained to record the desired flow while `Status: blocked on Fixture C spike`.
- `pending_applications_` is C++ in-memory only — there is no on-disk file to inject an inbound request, so this cannot be expressed at L2.
- Per-account key is `acct_auto_accept_friends_<prefix16>` (`prefs.dart:81`, `_scopedKey` uses first-16 of toxId); legacy unscoped `auto_accept_friends` is the `false` fallback.
- `settingsAutoAcceptFriendToggle` not yet added to `lib/ui/testing/ui_keys.dart`; tap by label/ref today.
- Re-running Phase 2 needs a fresh/unpaired B identity or A already has B as a friend and no new application arrives.
