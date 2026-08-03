# S27 — Decline incoming friend request

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=none(pre-pair)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — same two-live-instances constraint as S26. The defining anti-regression assertion (anti-ghost-block) requires driving B to send a SECOND request with different wording.
**Runner gate**: `tool/mcp_test/run_fixture_c_decline.sh`
**Status**: covered (executable, two-process) — fresh pair, B requests A, A declines via l3_refuse_friend_request; asserts the application leaves friendApplications[] and no friendship forms. Live-validation owed (two-process).

## Precondition
- Same as S26 (two distinct Container bundles, plaintext profiles, `auto_accept_friends:<toxA> = false`)
- **S27-extra**: `dismissed_friend_applications` pref on A must be absent or empty before launch — a stale entry would silently swallow the application before it surfaces. `defaults delete com.toxee.app 'flutter.dismissed_friend_applications'` in pre-flight.
- **S27-extra**: `local_friends_<toxA>` must NOT contain toxB pre-test
- Both sides reach Online before driving

## Driver
1. On B: send friend request to toxA with a recognizable unique message string `WORDING_1 = "S27 first request - decline me"`. Same key path as S26 Step 1.
2. On A: open Contacts tab; poll up to 20s until the application surfaces with toxB prefix + WORDING_1 visible
3. Prefer `marionette.tap({ key: "contact_new_contacts_tab" })` via `UiKeys.contactNewContactsTab`; verify the application row. Label/ref tapping remains the fallback.
4. Prefer `marionette.tap({ key: "contact_application_decline_button:<toxB>" })` via `UiKeys.contactApplicationDeclineButton("<toxB>")`. Text-match on 拒绝 / Refuse remains the fallback.
5. Wait 7s (one full 5s poll tick + margin) and re-snapshot
6. Optional anti-ghost-block leg: on B send a SECOND request with `WORDING_2 = "S27 second request - this one should surface"`; verify it surfaces on A

## Assertions
- A1: pending application with WORDING_1 surfaces on A within 20s
- A2: tapping 拒绝 removes the row from Applications view
- A3 (primary inverse of S26): toxB does NOT appear in A's contact list
- A4 (primary): `Prefs.local_friends_<toxA>` does NOT contain toxB
- A5: `Prefs.dismissed_friend_applications` contains exactly one entry fingerprinted as `<toxB_64hex>|<WORDING_1>` (wording-keyed — load-bearing for anti-ghost-block)
- A6: log on A MUST NOT contain `acceptFriend`, `tox_friend_add_norequest`, `onFriendListAdded`, `NotifyFriendListAdded`, or `[FfiChatService] acceptFriendRequest:` between tap and end
- A8 (anti-reappearance): row stays gone after 7s (one full poll cycle re-fetches the C++ entry but the Dart-side filter swallows it pre-UI)
- A9 (anti-ghost-block, defining assertion): a fresh request with WORDING_2 DOES surface — fingerprint `<toxB>|<WORDING_2>` differs from the persisted `<toxB>|<WORDING_1>`, proving the filter is wording-keyed not userId-only
- A10: B's contact list does NOT contain toxA; B's log MUST NOT contain `friend connection status: ... status=2` for the friend-number mapped to toxA (Tox has no on-protocol "refuse"; B's request stays pending forever)
- A11: `official.get_runtime_errors({})` empty on both sessions

## Notes
- **Runner gate (two-process, data half)**: `tool/mcp_test/run_fixture_c_decline.sh` launches a FRESH pair (no fixture restore), drives `drive_fixture_c_decline.dart`: B (REQUESTER) sends `l3_add_friend_request` to A, A polls until the pending application surfaces, A (DECLINER) calls `l3_refuse_friend_request` on toxB, then asserts (A1) the application leaves A's `friendApplications[]` and (A2) toxB does not enter A's `friends[]` (the decline forms no friendship). The fresh-pair **B→A request direction is the stable one** per the handoff (`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`); the driver's assertions distinguish "B's application never reached A" from "declined but still present" so a live failure points at the right stage. **Live-validation owed** — this two-process gate has not yet been run on a live paired DHT this session.
- `refuseFriendApplication` is silent on the success path — no positive log marker; the assertion is the absence of accept markers + the persisted pref + the absence-from-list state
- The 5s poll re-fetches `getFriendApplications` from the C++ queue every tick; the dismiss filter is the only thing keeping the row hidden, so A8 is the regression gate for the filter
- Step 9 re-send may be deduplicated on B-side — workarounds: drive B to cancel + re-add via its outbound friend-request management UI, or use a debug-only `tim2tox_ffi_test_inject_pending_application` hook
- Partial key status: `contact_new_contacts_tab`, `contact_application_decline_button:<userID>`, `contact_application_item:<userID>`, and `contact_applications_list_empty` are now available.
- Detail-surface status: if the row is opened instead of declined inline, the detail page now exposes `contact_application_detail_accept_button:<userID>` and `contact_application_detail_decline_button:<userID>`.
