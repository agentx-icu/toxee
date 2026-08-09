# S128 — Group: copy the created group ID from Add Group dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=empty`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once post-create dialog persistence is stabilized; adjacent create-half is S32
**Status**: covered at the widget layer (L1) — **`test/ui/add_group_dialog_test.dart` "S128 create success renders the created-info card with Copy ID button and the new id"** (2026-06-08, PASS). The created-info card (Copy ID button `add_group_copy_id_button` + the new group id as a SelectableText) renders only while `_createdGroupId != null`, and `_createGroup` auto-pops the dialog on success — so the test mounts `AddGroupDialog` DIRECTLY (not via showDialog) so the pop is a no-op and the card stays mounted, then asserts the Copy ID button + id render after a stubbed create. The clipboard-value-equals-the-chats-row half is two-process and not asserted here.

## Precondition
- One signed-in account A is Online.
- A create-group run leaves the `_createdGroupId` affordance visible long enough to tap `UiKeys.addGroupCopyIdButton`.

## UI Driver
1. Open `AddGroupDialog` and create a group.
2. Stay on the success state instead of dismissing immediately.
3. Tap `UiKeys.addGroupCopyIdButton`.
4. Read the clipboard and compare it with the created group's ID.

## Assertions
- The copied value is a 64-hex group chat ID.
- The copied value matches the group row that just appeared in the chats list.
- No runtime errors appear vs baseline.

## Notes
- The current auto-pop timing makes this a flaky real-ui surface today; that is the main blocker.
- This case intentionally targets the create-dialog copy affordance, not the profile page.
