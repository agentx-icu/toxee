# S143 — Group: kick-action surface appears for a removable member

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A owner,B member in separate sandboxes) current(A)=A1 autoLogin=on network=online groups=[gidG joined by both]`
**Harness mode**: peerHarness=none (two toxee processes; remote member required)
**Promotion target**: L3 candidate once real-ui two-process moderation driving is added; adjacent data-half sibling is S37
**Status**: covered at the widget layer (L1) — **`test/ui/chat_core_real_ui_test.dart` "S143 owner tapping a non-self member row surfaces the keyed kick action"** (2026-06-08, PASS). Mounts the real `TencentCloudChatGroupMemberListItem` (Work group, OWNER role, currentUser ≠ the member), taps the member NAME (the row's GestureDetector uses `deferToChild`, so a center/byType tap misses — codex), and asserts the keyed `group_member_action_kick_button` mounts in the plain-tap manage sheet (the desktop secondary-click opens a different unkeyed menu). The kick FUNCTION is also data-half-gated by S37 (`run_fixture_c_kick.sh` PASS, `l3_kick_group_member`). The two-process profile→member-list route stays harness-unreachable (see S136), so L1 is the gate.

## Precondition
- A is allowed to moderate B inside group `<gidG>`.
- A has opened B's member info or action sheet from the member list.

## UI Driver
1. Open B's member action surface.
2. Verify `UiKeys.groupMemberActionKickButton`.

## Assertions
- The kick action is visible and enabled for a removable remote member.
- The action is not surfaced for self rows.
- No runtime errors appear vs baseline.

## Notes
- This case only proves the real-ui action surface; the actual kick flow remains a deeper two-process scenario.
- It is the missing UI-side sibling of S37's data-half coverage.
