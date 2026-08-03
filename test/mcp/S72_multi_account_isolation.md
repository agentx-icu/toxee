# S72 — Multi-account state isolation (privacy regression)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=none→A→B→A autoLogin=off network=online friends=add-F_A-to-A history=write-to-A theme=global`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — temporal isolation property (switch and check no bleed-through); requires real `FfiChatService` re-init, scoped Prefs writes, and per-account `account_data/<prefix>/` directories on disk.
**Status**: covered; tier-1 privacy invariants (I1-I6) gate ship.

## Precondition
- Clean `profiles/` and `account_data/` directories (wiped pre-flight).
- Two pre-staged accounts A and B via `.tox` fixture files at `tool/mcp_test/fixtures/S72_account_A.tox` and `S72_account_B.tox`, dropped into `profiles/p_<prefA16>/tox_profile.tox` and `profiles/p_<prefB16>/tox_profile.tox`.
- `account_list` JSON has both entries; `currentAccountToxId` unset (land on LoginPage).
- `F_A_toxId` is a known constant (long-lived bot, or Fixture C twin).
- Capture `toxIdA`, `toxIdB`, `prefA = toxIdA[0:16]`, `prefB = toxIdB[0:16]`.
- `MCP_BINDING=marionette`; macOS sandbox path `$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app`.

## Driver
1. Sign in A: tap A's card; poll for sidebar `<nick_A>\nOnline` (≤60s).
2. Add friend F_A: `new_entry_menu_button` → `new_entry_add_contact_item` → `enter_text(add_friend_id_input, <F_A_toxId>)` → `add_friend_submit_button`.
3. Open F_A conversation row (`conv_<F_A_toxId>` once dynamic key lands; semantic ref today) → `enter_text(message_input_field, "hi from A")` → `message_send_button`.
4. Rename A: tap sidebar avatar → `enter_text(profile_nickname_field, "Account A-test")` → `profile_save_button`; wait sidebar shows new nickname.
5. Set theme dark in Settings (informational — theme is global; documents current behavior).
6. Snapshot A's on-disk state: list `account_data/<prefA>/chat_history/`, read `<F_A_toxId>.json`, `offline_message_queue.json`; assert `account_data/<prefB>/` does NOT exist yet. Dump scoped Prefs keys ending in `_<prefA>` / `_<prefB>` via `plutil`.
7. Switch A→B via Settings swap-account row → confirm dialog → poll for `<nick_B>\nOnline`.
8. From B: verify isolation (see Assertions 6.1–6.7).
9. Switch B→A: same flow in reverse; poll for `Account A-test\nOnline`.
10. Verify A's state survived round-trip (see §8 assertions).

## Assertions
**Sign-in / setup:**
- Log shows `tim2tox_ffi_init_with_path: using initPath=…/p_<prefA>` and `Notified self online status (userID=<toxIdA>…)`.
- After Step 4: `defaults read com.toxee.app 'flutter.self_nickname'` == `"Account A-test"`; `accountList[toxIdA].nickname` == same.
- After Step 5: `defaults read com.toxee.app 'flutter.theme_mode'` == `"dark"` (unscoped key per `prefs.dart:34`).

**Post-switch to B (privacy invariants):**
- 6.1 No contact row references F_A's nickname or toxId prefix in B's contact list.
- 6.2 No conversation row references F_A in B's chat list.
- 6.3 Sidebar `_UserAvatar` label `^<nick_B>\nOnline$`; must NOT contain `Account A-test`.
- 6.4 **Headline regression** — `defaults read com.toxee.app 'flutter.self_nickname'` == `<nick_B>`, NOT `Account A-test`; `self_status_msg` == B's; `currentAccountToxId` == `toxIdB`.
- 6.5 `theme_mode` == `dark` (global, expected; not a bug today).
- 6.6 `account_data/<prefB>/` exists; `account_data/<prefB>/chat_history/<F_A_toxId>.json` does NOT exist; `account_data/<prefA>/chat_history/<F_A_toxId>.json` still exists, md5 unchanged.
- 6.7 Scoped prefs keys: each `_<prefA>` key changes only when A mutates; `_<prefB>` siblings absent or B-only.

**Round-trip back to A (§8):**
- F_A row present; conversation row present with last-msg preview `"hi from A"`; bubble exists in chat panel.
- Sidebar label `Account A-test\nOnline`.
- `self_nickname` == `Account A-test`; `self_status_msg` restored; `self_avatar_path` restored.
- md5 of A's `chat_history/<F_A_toxId>.json` and `offline_message_queue.json` matches pre-switch snapshot.

**Final invariants (block-ship if any fail):**
- I1: `account_data/<prefB>/chat_history/<F_A_toxId>.json` absent.
- I2: A's `chat_history/` lists no files belonging to B's friend set.
- I3: A's and B's `offline_message_queue.json` md5 differ (or B's absent).
- I4: A's `avatars/` and B's `avatars/` have disjoint file lists.
- I5: No scoped `_<prefA>` key changes when B mutates state, and vice versa.
- I6: Global identity prefs (`self_nickname`/`self_status_msg`/`self_avatar_path`) track the active account on every switch.
- I7: `currentAccountToxId` matches the toxId whose `p_<first16>/` directory FFI is reading.
- I8: `accountList` has exactly 2 entries with correct nickname/avatarPath/passwordHash.
- I9: No log line contains both `userID=<toxIdA>` and `userID=<toxIdB>` within the same Tox `init` block.
- I10: `theme_mode` constant across both accounts (flip this assertion if theme becomes per-account).

## Notes
- Echo peer harness intentionally not used — this scenario tests multi-account portability on a single toxee instance, no second peer required.
- After tapping `new_entry_menu_button` (popup-revealed item) wait ~500ms for the menu animation before tapping the popup child `new_entry_add_contact_item`; otherwise marionette returns `Element matching {key: new_entry_add_contact_item} not found` (see F14 in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
- This locks in the 2026-05-28 fix at `account_service.dart:248-272` that mirrors `nickname`/`statusMessage`/`avatarPath` per-account on switch. Without it, S3 passes but the sidebar shows A's nickname on B.
- I1-I6 are privacy-critical and gate ship; I7-I10 are correctness/documentation.
- Theme is global by design today (`_kThemeMode='theme_mode'` unscoped, `prefs.dart:34`); if product moves to per-account theme, flip §6.5 and I10 assertions.
- `Prefs._scopedKey` uses 16-char prefix (`prefs/scoped_key.dart`); `SharedPreferencesAdapter` for FFI uses `<key>_<prefA>` (`account_service.dart:331-334`).
- DHT bootstrap dominates each switch (5-30s × 2 inits); use ≥60s polls on every "wait until Online".
- F_A request "sent" vs "queued" depends on F_A's liveness; assert only that the outgoing message lands in A's `chat_history/<F_A_toxId>.json` regardless of delivery state.
- `defaults read` may return stale values before SharedPreferences flush; add 500 ms wait or `marionette.hot_reload()` to force flush.
