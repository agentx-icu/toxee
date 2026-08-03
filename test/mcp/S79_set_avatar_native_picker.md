# S79 — Set self avatar via the native image picker

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online window=default`
**Harness mode**: peerHarness=none (local avatar update needs no peer; friend propagation does — see Notes)
**Promotion target**: L3-pinned because the macOS native image picker cannot be MCP-driven (§7b) — needs a `pickFiles` test-override seam (not built today, see Notes).
**Status**: covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_avatar_picker.sh` (l3_pick_avatar bypasses the native NSOpenPanel via an override seam and runs the REAL pickAndPersistAvatar copy+persist; asserts the persisted avatar destPath). Validated live 2026-06-01.

## Precondition
- Feature IS implemented — tap path verified end-to-end (see Notes for file:line chain).
- A signed in, online; on HomePage with the desktop sidebar visible.
- Staged image at `/tmp/toxee_test/s79_avatar.png`.
- `MCP_BINDING=marionette`.

## Driver
1. Baseline `official.get_runtime_errors({})`; poll sidebar `<nick>\nOnline` ≤60s.
2. Tap the sidebar self-avatar (`_UserAvatar` `onTap → _openProfile`, `sidebar.dart:390`); no key on that tap target (see Notes). `showSelfProfile` (`sidebar.dart:40`) opens the profile dialog.
3. In the profile, tap the avatar / camera affordance (`ProfileAvatar` `onTap`, `profile_avatar.dart:86`/`:119`, wired `onAvatarTap: _pickAvatar`, `profile_page.dart:416`).
4. Drive the picker via the (not-yet-built) test seam — native picker cannot be tapped (§7b). Inject `/tmp/toxee_test/s79_avatar.png` so `pickAndPersistAvatar` (`profile_avatar_picker.dart:21`) returns a `PickedAvatar`; `_pickAvatar` (`profile_page.dart:314`) calls `setState` + `onAvatarChanged`.
5. Poll snapshot ≤5s for the updated avatar; on failure A surfaces `failedToUpdateAvatar` SnackBar (`profile_page.dart:332`).

## Assertions
- A1: `pickAndPersistAvatar` copies into the per-account avatars dir and writes `Prefs.setAvatarPath(destPath)` (`profile_avatar_picker.dart:64`) + `Prefs.setAccountAvatarPath` (`:66`).
- A2: `onAvatarChanged` (`sidebar.dart:89`) runs `service.updateAvatar(path)` (`:93`) + `Prefs.addAccount(avatarPath:…)` (`:101-105`).
- A3: `_avatarVersion++` bumps the `ValueKey('avatar-$avatarVersion')` (`profile_avatar.dart:70`) so the new `Image.file` is shown; sidebar avatar key `sidebar-avatar-<path>-<ver>` (`sidebar.dart:421`) re-renders.
- A4: log `[FfiChatService] updateAvatar: hash changed … path=<destPath>` (`ffi_chat_service.dart:6545-6546`); `setSelfAvatarHash` persisted (`:6548`).
- A5 (propagation, needs a peer): since broadcast is on by default (`_avatarBroadcastAsChatFileEnabled=true`, `ffi_chat_service.dart:160`), `updateAvatar` calls `sendAvatarToAllFriends` (`:6561`) → log `[FfiChatService] sendAvatarToAllFriends: done – sent=…` (`:6290`); each online friend gets the avatar via `sendFile(addToChatHistory:false)` (`:6273`).
- A6: `official.get_runtime_errors({})` matches Step-1 baseline.

## Notes
- **Real blocker (why `informational only`, NOT a media spike)**: this is an IMAGE/FILE picker, not the ToxAV mic/camera "media spike". The blocker is purely a missing seam: `pickAndPersistAvatar` (`profile_avatar_picker.dart:21`, `FilePicker.platform.pickFiles(type: FileType.image)` at `:25`) has NO test-override parameter — unlike the `.tox` restore flow (S9), which has `@visibleForTesting String? filePathOverride` at `login_page_controller.dart:332`. With no equivalent seam on the picker, the native macOS image picker dialog cannot be driven by MCP and Step 4 is undriveable until such a seam is added (wrap the `pickFiles` call, mirroring S9's override). Until then this spec documents the verified path only.
- Verified avatar-pick path: sidebar self-avatar `onTap → _openProfile` (`sidebar.dart:390`) → `showSelfProfile` (`sidebar.dart:40`) → `ProfileAvatar` (`profile_avatar.dart`) → `profile_page.dart:314` `_pickAvatar` → `pickAndPersistAvatar` → `FilePicker.pickFiles` → `Prefs.setAvatarPath` + `service.updateAvatar`. The tap → picker → persist → propagate chain itself is real and implemented.
- Picker uses the image filter (`FileType.image`), distinct from S9/S21 which use the file picker; the same `showSelfProfile` builder serves both desktop `_UserAvatar` and the mobile drawer header (`sidebar.dart:30`).
- A5 (friend propagation) is the only half that needs a peer — Fixture C (`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`); echo peer cannot verify it (file transfer, not c2c text).
- Wanted UiKeys (none today): sidebar self-avatar tap target, profile avatar/camera affordance.
