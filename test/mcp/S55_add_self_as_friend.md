# S55 — Add self as friend (A1 self-add guard rejects)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online`
**Harness mode**: peerHarness=none
**Promotion target**: L2 if a flutter_test widget driver can stub `FfiChatService.accountKey` to return the local Tox ID; L3-pinned today because the guard reads `widget.service.accountKey` which depends on a live `Tim2ToxSdkPlatform`.
**Status**: covered; two sub-variants (S55-full = 76-char address, S55-pubkey = 64-char public-key prefix).

## Precondition
- Account A signed in, plaintext profile, online.
- `LOCAL_TOXID` captured from log line `Notified self online status (userID=<76-char>)` before Step 3.
- For S55-pubkey: `LOCAL_TOXID_PUBKEY = LOCAL_TOXID[0:64]` (the `normalizeToxId` path at `tox_utils.dart:17-22` must collapse 76→64).
- `MCP_BINDING=marionette`.

## Driver
1. Confirm sidebar `<nicknameA>\nOnline` and capture `LOCAL_TOXID` from log.
2. `marionette.tap({ key: "new_entry_menu_button" })` → popup mounts.
3. `marionette.tap({ key: "new_entry_add_contact_item" })` → `AddFriendDialog` mounts (`addFriendIdInput`, `addFriendMessageInput`, `addFriendSubmitButton` present).
4. `marionette.enter_text({ key: "add_friend_id_input", input: "$LOCAL_TOXID" })` (S55-full) or `"$LOCAL_TOXID_PUBKEY"` (S55-pubkey).
5. Confirm submit button enabled (guard only fires at submit time, not on type).
6. `marionette.tap({ key: "add_friend_submit_button" })`.
7. Re-type a different 64-hex string into the field; confirm field updates and submit stays enabled (no `_isSubmitting` lock).
8. Clear, re-paste own Tox ID, tap submit again (regression gate for `_attemptedThisSession` ordering).
9. `marionette.tap({ key: "add_friend_cancel_button" })` or Escape → dismiss.

## Assertions
- After Step 6 (≤2s): SnackBar with text `You cannot add yourself as a friend` (today's fallback at `add_friend_dialog.dart:153-157`; `_localeText` switch has no `cannotAddSelf` case).
- Dialog remains mounted (`addFriendIdInput` still present) — guard returns at line 157 before `navigator.maybePop()` at line 207.
- `addFriendSubmitButton.enabled == true` after rejection — `_isSubmitting` never flipped.
- Negative log grep within ≤5s of submit: no `[FfiChatService] addFriend`, no `addFriend failed`, no `request queued`/`request sent`/`already in friend list`/`A friend request was already sent in this session`.
- `tox_profile.tox` mtime does not advance within ≤30s of submit.
- After Step 8: SnackBar text is still `You cannot add yourself as a friend` — NOT the `_attemptedThisSession` "already sent" text (proves guard order at lines 152-158 runs before line 196's `add(normalizedRaw)`).
- S55-pubkey: same A5/A6/A7 hold for the 64-char input — `normalizeToxId` regression gate.
- `get_runtime_errors({})` baseline-clean.

## Notes
- After tapping `new_entry_menu_button` (popup-revealed item) wait ~500ms for the menu animation before tapping the popup child `new_entry_add_contact_item`; otherwise marionette returns `Element matching {key: new_entry_add_contact_item} not found` (see F14 in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
- `_localeText('cannotAddSelf', fallback: ...)` falls through to the English fallback in all locales — assert on the English literal until ARB key is added.
- Guard reads `widget.service.accountKey` (`ffi_chat_service_account_key.dart:46-50` = `getSelfToxId() ?? selfId`); regression gate against reverting to plain `selfId` which is the V2TIM `'FlutterUIKitClient'` placeholder and would never match a hex input.
- SnackBar auto-dismisses after 4s — snapshot ≤2s of submit tap.
- Both sub-variants reuse the same launched app; just swap the pasted ID between runs.
