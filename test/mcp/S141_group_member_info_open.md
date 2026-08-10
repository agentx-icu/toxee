# S141 — Group: open member info from the member list

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 autoLogin=on network=online groups=[gidG joined by both]`
**Harness mode**: peerHarness=none (two toxee processes; remote member required)
**Promotion target**: L3 candidate once a real-ui two-process member-list runner exists; adjacent data-half siblings are S36 and S37
**Status**: covered at the widget layer (L1) — **`test/ui/chat_core_real_ui_test.dart` "S141 group member info body renders the member name and id"** (2026-06-08, PASS) mounts the real `TencentCloudChatGroupMemberInfoBody` and asserts the member's name + identifier render. The two-process real-UI member-info-OPEN-via-tap path stays BLOCKED on the group-profile-route harness reachability limitation (the member list lives inside the pushed profile route, which is visible but not flutter_skill-reachable — see S136); the WidgetTester gate is the codex-endorsed fallback for that route.

## Precondition
- Group `<gidG>` has at least one remote member B besides A.
- A can open the group profile and member list for `<gidG>`.

## UI Driver
1. Open the group profile.
2. Enter the member list.
3. Tap B's member row.

## Assertions
- The member info surface opens for B.
- The opened member info shows B's display name and identifier.
- No runtime errors appear vs baseline.

## Notes
- This is distinct from S121's “member list mounts” surface; it drills one step deeper into member info.
- A remote member is required; self-only groups cannot exercise this path.
