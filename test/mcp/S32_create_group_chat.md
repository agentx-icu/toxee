# S32 — Create group chat

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online history=empty groups=empty`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because group create requires live FFI + clipboard verification (`pbpaste`) and DHT announce
**Status**: covered

## Precondition
- One signed-in account A; `Prefs.groups` and `Prefs.quit_groups` empty.
- Account online (`<nicknameA>\nOnline` in sidebar; poll up to 60s for DHT bootstrap).
- `MCP_BINDING=marionette` (segment tap requires key-based fallback).
- Run three variants: type=`Public` / `Private` / `Conference`.

## Driver
1. `marionette.tap({key: "new_entry_menu_button"})` — opens NewEntry popup.
2. `marionette.tap({key: "new_entry_create_group_item"})` — mounts `AddGroupDialog`.
3. `marionette.enter_text({key: "add_group_create_name_input", input: "test group <type>"})`.
4. Type select: default=Public (skip); Private/Conference → semantic-tap the `Private` / `Conference` segment of `UiKeys.addGroupTypeSelector` (`add_group_type_selector`). Per-segment keys not yet shipped; use `fmt_tap_widget` on the label node.
5. Submit: tap `Create Group` button (proposed `add_group_create_submit_button`); today disambiguate from dialog title by ancestry inside the tinted create card.
6. After success: re-open dialog and tap `add_group_copy_id_button` to copy gid (auto-pop bug: see Notes).

## Assertions
- Conversation list contains a row labeled `test group <type>` (via `Prefs.resolveGroupDisplayName`).
- `defaults read com.toxee.app 'flutter.groups'` contains the new gid; `quit_groups` does not.
- `Prefs.getGroupName(gid) == "test group <type>"`.
- Log markers in order: `[FfiChatService] createGroup` → `tim2tox_ffi_create_group: <Public|Private>` (or `tim2tox_ffi_create_conference`) → `[HomeGroupController] handleGroupChanged: groupId=<gid>` → `deleteGroupInfoFromJoinedGroupList` → `unblockConversation 'group_<gid>'` → `refreshConversations <gid>` (the 4-step ordering invariant).
- `pbpaste` after Copy ID tap matches `^[0-9a-fA-F]{64}$`.
- Negative grep: `createGroup failed`, `joinGroup failed`, `ToxManager not initialized` must not appear.
- `official.get_runtime_errors({})` returns baseline.

## Notes
- After tapping `new_entry_menu_button` (popup-revealed item) wait ~500ms for the menu animation before tapping the popup child `new_entry_create_group_item`; otherwise marionette returns `Element matching {key: new_entry_create_group_item} not found` (see F14 in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
- Public selector value `'group'` is historically a footgun (was silently PRIVATE in `dart_compat_group.cpp`) — A7 grep on log type string is the regression gate.
- Auto-pop after success destroys the in-dialog `_createdGroupId` state; Copy ID affordance only renders for one frame. Recommended source fix: don't auto-pop, OR move Copy ID to the conversation header.
- Between runs: `defaults delete com.toxee.app 'flutter.groups'; defaults delete com.toxee.app 'flutter.quit_groups'` to keep "empty groups" precondition.
- Conference gid surfaces as `tox_conf_<n>` at FFI level; `FfiChatService` normalizes to 64-hex before `_knownGroups` / Prefs.
