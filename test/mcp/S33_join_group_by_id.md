# S33 — Join existing group by ID

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2-instances current=A(host)/B(joiner) autoLogin=on network=online groups=B-empty`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because Fixture C requires two toxee instances with separate `HOME` overlays and live DHT for announce
**Status**: covered

## Precondition
- Two paired toxees: instance #1 hosts Public group `s33 host group` (run S32 first); instance #2 joins.
- Instance #2: `Prefs.groups` and `Prefs.quit_groups` empty.
- Both online; host group is DHT-announce-reachable (poll host log for `announce.*ok`, 5-60s).
- `MCP_BINDING=marionette` on both; distinct `HOME` overlays so containers don't collide.
- Drive instance #2 (joiner B) for the steps; host A only stays alive.

## Driver
1. `marionette.tap({key: "new_entry_menu_button"})`.
2. `marionette.tap({key: "new_entry_create_group_item"})` — mounts dialog with Join card (upper) + Create card (lower); no tab switching.
3. `marionette.enter_text({key: "add_group_join_id_input", input: "<gid>"})` (the 64-hex from host).
4. Optional: `marionette.enter_text({key: "add_group_join_message_input", input: "hello from S33"})`.
5. Optional: `marionette.enter_text({key: "add_group_alias_input", input: "my host group"})`.
6. Submit: proposed key `add_group_join_submit_button`; today disambiguate by ancestry inside the non-tinted join card.
7. Negative path: re-open, enter `"deadbeef"` (too short), `"xyz" + ("0" * 61)` (non-hex), or empty; tap submit. Validator should reject all three.

## Assertions
- Conversation list on B gets a new row: labeled with alias (if set), else canonical group name (may take 5-30s to propagate), else gid truncated.
- `defaults read com.toxee.app 'flutter.groups'` contains `<gid>`; `quit_groups` does not.
- If alias set: `Prefs.getGroupAlias(<gid>)` returns alias.
- Log markers: `[FfiChatService] joinGroup` → `tim2tox_ffi_join_group` → `tox_group_join.*<gid>` → `[FfiChatService] joinGroup: persisted gid=<gid>` → `handleGroupChanged: groupId=<gid>` → `refreshConversations <gid>`.
- Negative path: inline form error (`Please enter group ID` / `Only hexadecimal characters are allowed` / `ID must be exactly 64 hexadecimal characters`); no `[FfiChatService] joinGroup` log fires; dialog stays open.
- Negative grep on success path: `joinGroup failed`, `joinGroup: FFI returned rc=`, `createGroup` (wrong dispatch).
- `official.get_runtime_errors({})` returns baseline.

## Notes
- After tapping `new_entry_menu_button` (popup-revealed item) wait ~500ms for the menu animation before tapping the popup child `new_entry_create_group_item`; otherwise marionette returns `Element matching {key: new_entry_create_group_item} not found` (see F14 in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
- 4-step `handleGroupChanged` ordering invariant is shared with S32 (`test/ui/home/home_group_controller_ordering_test.dart` covers controller level).
- Canonical name propagation lag: rely on alias OR per-row dynamic key `conv_list_group_tile:<gid>` (proposed) for locale + propagation stability.
- P0-B5 fix: `joinGroup` now throws on rc≠1; regression would leave ghost gid in `_knownGroups` + `Prefs.groups`. Negative grep on `joinGroup failed` is the gate.
- If gid was previously in `quit_groups`, successful join must remove it (rejoin path); optional A8 variant pre-seeds quit_groups to assert this.
- Conference IDs are also 64-hex but `tox_group_join` rejects them — S33 covers NGC join only.
