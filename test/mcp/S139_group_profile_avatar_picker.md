# S139 — Group: change the group avatar through the local picker override

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] files=[image]`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once the desktop file-picker surface is automatable in the current harness; adjacent single-chat sibling is S79
**Status**: covered at the widget layer (L1) — **`test/ui/chat_core_real_ui_test.dart` "S139 group profile avatar override renders a tappable picker surface"** (2026-06-08, PASS). Mounts the toxee `groupProfileAvatarBuilder` and asserts the local-pick camera badge (`Icons.camera_alt_outlined`) + the tappable GestureDetector render (the real FilePicker is not fired — it needs the plugin + per-account paths). Mirrors the conference analog `test/ui/conference/conference_profile_real_ui_test.dart`. The two-process profile route stays harness-unreachable (see S136).

## Precondition
- Group `<gidG>` profile is open.
- A local image fixture is available for the avatar picker.

## UI Driver
1. Tap the group avatar area in the profile.
2. Pick a local image file.
3. Return to the profile and conversation list.

## Assertions
- The profile avatar updates to the newly selected local image.
- The conversation row reflects the locally overridden avatar on the next render.
- No runtime errors appear vs baseline.

## Notes
- Toxee intentionally overrides the upstream Tencent-hosted preset grid with a local file-picker flow.
- This is a per-account, per-device customization, not a shared network avatar.
