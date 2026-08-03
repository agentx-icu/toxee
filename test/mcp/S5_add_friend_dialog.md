# S5 — Add Friend dialog (real network, full submit path)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=0`
**Harness mode**: peerHarness=echo_live
**Promotion target**: L3-pinned because exercises real Tox `addFriend` over DHT; S5-online needs a live peer toxee/echo bot
**Status**: covered (S5-online + S5-offline)

> Not the same as `test/ui/add_friend_dialog_smoke_test.dart` (hermetic widget test). S5 drives the real dialog against `libtim2tox_ffi`.

## Precondition
- **Echo peer running**: `bash tool/mcp_test/ensure_echo_peer.sh` — idempotent; on first call, builds + launches the bot if needed; waits for ID emission. Reads `tool/mcp_test/echo_peer.json` to capture `peer_id` (76-char Tox address). Bot auto-accepts friend requests + echoes received c2c text verbatim.
- **DHT warmup**: scenario runner should wait for `_drive_seed.dart`-style logic to confirm peer is DHT-reachable from the toxee side before proceeding — typically 5-30s; use a poll-for-peer-Online loop, not a fixed sleep.
- **Cleanup**: scenario runner should call `bash tool/mcp_test/stop_echo_peer.sh` in teardown (or rely on session-level reuse if running a batch).
- Fixture A: account A signed in, sidebar `<nicknameA>\nOnline`
- For S5-online: peer toxee/echo bot reachable on DHT, Tox ID known (e.g. `auto_tests` echo bot started with `RUN_VIRTUAL=0 ./run_tests_ordered.sh 1`)
- For S5-offline: peer Tox ID is a known-unreachable (decommissioned) ID; valid 64/76-hex checksum
- Pasteboard pre-loaded with peer Tox ID (`pbcopy`) — only if paste-button path used
- `MCP_BINDING=marionette`

## Driver
1. Poll snapshot up to 60s for sidebar `<nicknameA>\nOnline`
2. **`marionette.tap({ key: "sidebar_contacts_tab" })`** — `NewEntryButton` is mounted inside the UIKit **contacts** AppBar (`home_page.dart:1348` + `ContactAppBarNameOverride.trailing`), NOT the chats AppBar. The button is invisible on chats tab. (See F10 in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`.)
3. `marionette.tap` on `UiKeys.newEntryMenuButton` (`new_entry_menu_button`); snapshot → PopupMenu overlay shows `Add Contact` / `Create Group`
4. `marionette.tap` on `UiKeys.newEntryAddContactItem` (`new_entry_add_contact_item`)
5. Snapshot → assert `AddFriendDialog` mounted; `add_friend_id_input`, `add_friend_message_input`, `add_friend_submit_button` present; submit button disabled (race-fix gate: `_canSubmit` reads both controllers)
6. Fill the Tox ID: **read `peer_id` from `tool/mcp_test/echo_peer.json`** (the 76-char Tox address emitted by the echo peer; this is the canonical AddFriend target for S5-online). Then either `marionette.enter_text` on `UiKeys.addFriendIdInput` (`add_friend_id_input`) with that 76-hex peer_id, OR `pbcopy` the peer_id first and `marionette.tap` on `UiKeys.addFriendPasteButton` (`add_friend_paste_button`). For S5-offline, use the known-unreachable ID per Precondition instead.
7. Re-snapshot within ≤500ms → assert submit button `enabled=true` (codex-round-1 race-fix gate)
8. `marionette.tap` on `UiKeys.addFriendSubmitButton` (`add_friend_submit_button`)
9. Poll snapshot for SnackBar; for S5-online, tail peer log up to 60s

## Assertions
- A4 (regression gate): before fill, `add_friend_submit_button.enabled == false`
- A5 (regression gate): after fill, `add_friend_submit_button.enabled == true` within ≤500ms
- After submit: dialog dismisses within ≤2s (snapshot no longer finds `add_friend_id_input`)
- S5-online SnackBar text matches `Friend request sent` (`TencentCloudChatLocalizations.requestSent`)
- S5-offline SnackBar text matches `Offline — request queued and will be sent when you reconnect` (inline literal, `add_friend_dialog.dart:140-142`)
- Log negative grep (post-submit): `cannot add yourself`, `already in friend list`, `addFriend failed` must NOT appear
- S5-online peer log within 60s: `OnFriendRequest from=<LOCAL_TOXID>` (or `friend request received from=<LOCAL_TOXID>`)
- `tox_profile.tox` mtime advances within ≤30s of submit (nospam-stamped request persisted)
- `official.get_runtime_errors({})` returns Step-1 baseline

## Notes
- After tapping `new_entry_menu_button` (popup-revealed item) wait ~500ms for the menu animation before tapping the popup child `new_entry_add_contact_item`; otherwise marionette returns `Element matching {key: new_entry_add_contact_item} not found` (see F14 in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
- `_isSubmitting=true` flips before the first await (line 179) to prevent double-tap double-send.
- `accountKey` (real Tox address), not `selfId`, is used for the self-add guard (line 151).
- `requestSent` vs `requestQueued` keys off `_isConnected` stream snapshot at submit time.
- `_pasteFromClipboard` trims input — peer IDs often arrive with trailing newlines.
- Re-running against the same peer can trigger `_attemptedThisSession`; use a fresh peer per run.
