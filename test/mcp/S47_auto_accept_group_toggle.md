# S47 — Auto-accept group invite toggle

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(A↔B pre-paired) groups=A-empty` (`paired_for_e2e`)
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — the auto-accept gate `auto_accept_group_invites_` lives in C++ (`V2TIMManagerImpl::GetAutoAcceptGroupInvites`, `V2TIMManagerImpl.cpp:4668`) and only fires on a real `tox_callback_conference`/`group_invite`, so it needs a second live toxee inviting over the DHT. Sibling of S46 (friend auto-accept) sharing the toggle/Prefs shape.
**Status**: partial (Dart fix landed; native residual) — FIXED the Platform no-op: `inviteUserToGroup` now delegates to the native_im path → C++ `tox_group_invite_friend`, so the invite actually transmits and the invitee AUTO-ACCEPTS it (live: `tox_group_invite_accept` err=0 + `HandleGroupSelfJoin`, group connected). Gate `run_fixture_c_group_invite.sh` (A1 invite-send PASSES; A2 auto-join proven at the protocol level but the two-process gate is flaky — NGC invite *delivery* timing between two fresh instances + the auto-joined group not propagating into the Dart-side knownGroups). The Dart half is now FULLY gated (2026-06-08): the scoped Pref round-trip by `test/account_toggle_persistence_test.dart`, AND — newly — the BOOTSTRAP PUSH (read the persisted toggle at HomePage startup → push into the native gate) by `test/ui/home/auto_accept_apply_test.dart`: the extracted `loadAndApplyAutoAcceptGroupInvites` (called from `home_page_bootstrap.dart`) loads `Prefs.getAutoAcceptGroupInvites(toxId)` and calls `service.setAutoAcceptGroupInvites(value)` over a capture-stub for both true/false, and the mounted-guard is gated too (an unmounted bootstrap loads the value but does NOT push a stale setting after an account switch). The residual is precisely NATIVE: the per-instance C++ gate (`g_auto_accept_group_invites` in `tim2tox_ffi.cpp:153`, the `GetAutoAcceptGroupInvites()`/auto-accept branch + `tox_group_invite_accept` in `V2TIMManagerImpl.cpp:571`, then `HandleGroupSelfJoin`/known-groups propagation) + the flaky two-process NGC delivery — exercised by the live group flows, shared with S81.
**Covered-by**: `test/ui/home/auto_accept_apply_test.dart`

## Precondition
- Two toxee instances in separate macOS Containers (distinct `CFBundleIdentifier`) so `SharedPreferences` don't clobber; both plaintext, `autoLogin=true`, `MCP_BINDING=marionette`.
- A and B already mutual friends (group invite over Tox requires an existing friendship); both reach Online before driving (poll `<nick>\nOnline` ≤60s per side).
- A's Pref `acct_auto_accept_group_invites_<toxA_prefix16>` is the scoped truth (constant `acct_auto_accept_group_invites` at `prefs.dart:82`, scoped via `_scopedKey` first-16-of-toxId at `prefs.dart:211`; read by `Prefs.getAutoAcceptGroupInvites`); it is pushed into the C++ gate at HomePage bootstrap via `service.setAutoAcceptGroupInvites(value)` (`home_page_bootstrap.dart:653-657`).
- B hosts a group ready to invite A into (run S32 on B first).

## Driver
1. On A: `marionette.tap({ key: "sidebar_settings_tab" })` (`UiKeys.sidebarSettings`).
2. On A: toggle the auto-accept-group `Switch` ON. No key yet — `settingsAutoAcceptGroupToggle` is not yet added to `lib/ui/testing/ui_keys.dart`; tap by label/ref today (the `Switch` at `settings_page_build.dart:272`, labelled `autoAcceptGroupInvites` / "Auto-accept group invitations"). Toggle drives `_setAutoAcceptGroupInvites` (`home_page.dart:1625`).
3. On B: invite A into the group (member-list → invite, or `InviteUserToGroup`).
4. Poll A's conversation list ≤30s for the new group row (no manual accept tapped).
5. Negative half: on A toggle the same `Switch` OFF, have B invite A into a second group, confirm the invite sits pending and a manual accept is required.

## Assertions
- ON path A1: with toggle ON, A auto-joins — group row appears in A's conversation list within 30s and NO accept UI was tapped.
- ON path A2 (log on A): `[GroupInvite] Auto-accept group invites setting: true` → `[GroupInvite] Tox instance available, proceeding with auto-accept` → `[GroupInvite] ✅ Successfully accepted group invite` (`V2TIMManagerImpl.cpp:560,624,673`).
- Pref A3: `defaults read com.toxee.app flutter.acct_auto_accept_group_invites_<toxA_prefix16>` reads `1`/`true` after step 2 (or `Prefs.getAutoAcceptGroupInvites(<toxA>)`).
- OFF path A4 (log on A): `[GroupInvite] Auto-accept is disabled, storing as pending invite before notifying` (`V2TIMManagerImpl.cpp:562`); NO `Successfully accepted group invite` line for the second invite.
- OFF path A5: second group does NOT appear in A's conversation list until a manual accept; Pref reads `false`.
- A6: `official.get_runtime_errors({})` empty vs Step 0 baseline on both sessions.

## Notes
- Multi-instance (two toxees + live DHT) is what pins this to L3 and BLOCKS it: there is no on-disk artifact to inject a group invite; the gate is C++-in-memory (`auto_accept_group_invites_`) and only flips on a real inbound invite. Gated on the Fixture C / `paired_for_e2e` spike — see `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`; until it passes this is `backlog`, not `covered`.
- Wanted UiKey `settingsAutoAcceptGroupToggle` (and sibling `settingsAutoAcceptFriendToggle`) not yet in `ui_keys.dart`; tap by label/ref today.
- Verify the Pref before each run: if the gate is already ON the OFF half passes for the wrong reason (mirror of S26's auto-accept-pref discipline).
- Sibling S46 shares the toggle/Prefs/`_set*` shape; if either earns a bug, the toggle→Pref→FFI plumbing is L1/L2-promotable, only the live-invite half is L3-pinned.
