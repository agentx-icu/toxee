# S142 — Group: copy a member ID from member info

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 autoLogin=on network=online groups=[gidG joined by both]`
**Harness mode**: peerHarness=none (two toxee processes; remote member required)
**Promotion target**: L3 candidate once member-info actions are runner-covered; adjacent sibling is S141
**Status**: covered at the widget layer (L1) — **`test/ui/chat_core_real_ui_test.dart` "S142 group member info copy-id button copies the member id to the clipboard"** (2026-06-08, PASS). This also fixed a real PRODUCT gap: the fork `TencentCloudChatGroupMemberInfoBody` showed the member id as plain text with NO copy affordance (the only copy path was the member-LIST desktop right-click — leaving MOBILE users no way to copy a member id). toxee added a keyed Copy-ID button (`group_member_info_copy_id_button`) next to the id; the test taps it and asserts the member userID lands on the clipboard (mocked `SystemChannels.platform`). The two-process profile route stays harness-unreachable (see S136).

## Precondition
- A has opened B's member info inside group `<gidG>`.

## UI Driver
1. Trigger the copy-ID action from the member info surface.
2. Read the clipboard.

## Assertions
- The copied value matches B's member identifier as shown in the member info view.
- The action is non-destructive and keeps the member info surface mounted.
- No runtime errors appear vs baseline.

## Notes
- The upstream member info surface exposes the member ID and copy affordance, but not yet through a toxee-owned key.
- This is the group-member analog of the contact/profile ID-copy family.
