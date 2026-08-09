# S136 — Group: open the group profile from the active chat header

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once header tapping for group chats is stabilized; adjacent siblings are S121-S123
**Status**: covered at the widget layer (L1) for the profile SURFACE — `test/ui/chat_core_real_ui_test.dart` "group profile members entry renders through the toxee keyed wrapper" asserts the keyed `group_profile_members_entry` mounts in the real profile content (the widget-layer proof the profile body renders). The two-process real-UI header-tap→profile-OPEN gate remains AUTHORED but BLOCKED (below) on the harness route-reachability limitation. `drive_real_ui_pair.dart` scenario `group_profile_open` (campaign `group-profile-open`) taps the keyed message-header avatar (`message_header_profile_avatar`, added to the fork `TencentCloudChatMessageHeaderProfileImage`) → `navigateToGroupProfile`. The profile DOES open (screenshot confirms group name + "Group ID:" + edit pencil), but NONE of the toxee group-profile override keys (`group_profile_id_text` / `group_profile_members_entry` / `group_profile_edit_name_button`) are flutter_skill-reachable once it is open (a `getWidgetTree` probe returns ~837 chars; waitKey finds none, while it works fine for other screens). Root cause CONFIRMED 2026-06-08 via `interactiveStructured` (18908-char full element list — traversal is NOT shallow): when the group profile is visibly open, flutter_skill's `WidgetsBinding.rootElement` walk lists the login-page account cards + the chat-header avatar but ZERO `group_profile_*` keys / no edit-name FAB. So the UIKit router's pushed group-profile route is RENDERED on a Navigator/Overlay that is NOT under the element tree flutter_skill traverses — a harness↔UIKit-navigator reachability limitation, NOT a missing key (the keys exist + render; the screenshot shows the edit pencil + "Group ID:"). BLOCKS S136, S153 (rename), S139/S141/S142/S143 (member-info/avatar live in this route), and the UI-surface half of S155 (count-gated, so S155 still PASSES). Follow-up: make the group-profile route flutter_skill-reachable (resolve the UIKit nested-navigator/overlay vs rootElement traversal) — a deep-link `l3_open_group_profile` alone won't help since it'd open the same unreachable route.

## Precondition
- Group `<gidG>` is already open in the chat pane.
- The group profile route is reachable by tapping the group chat header.

## UI Driver
1. Tap the active group chat header/avatar area.
2. Wait for `TencentCloudChatGroupProfile` to mount.

## Assertions
- The group profile route opens from the real chat header.
- The mounted profile exposes the toxee override surface for avatar, content, member entry, and destructive rows.
- No runtime errors appear vs baseline.

## Notes
- Current blocker: the header tap target has no dedicated key yet, so runner work still relies on ref/coordinate fallback.
- This scenario is the shared entry prerequisite for many later group profile cases.
