# S30 — Edit friend nickname (alias / 备注)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1 (F nickname=Friend Original, no prior remark)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L3-pinned — exercises UIKit modify-remark dialog + Tim2Tox `setFriendInfo` (with the loud-fail "no preferences service" path) + `SharedPreferencesAdapter.setFriendRemark` round-trip + cold-restart read path. Sibling of S28 (same friend-profile entry).
**Runner gate**: `tool/mcp_test/scenarios/l3_friend_remark_toggle.json`
**Status**: covered (executable, hermetic) — set/clear round-trip via l3_set_friend_remark + l3_dump_state.friends[].remark; the UI A-block (profile/contact-list display) and B-block (conversation list / chat header reflect alias) remain a documented MCP-playbook gap

## Precondition
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — restores `~/Library/Containers/com.toxee.app/Data/...` (profiles + account_data) + Prefs (`flutter.account_list`, `flutter.current_account_tox_id`, `flutter.local_friends_<prefix>`, scoped per-account keys) from cached tarball at `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst`. The restore wipes existing toxee state.
- **Seeded state**: after restore, the active account is `echo_seeded_test` (auto-login enabled); 1 friend (the echo peer) is in the contact list with status "Offline" (since the bot isn't running for seeded scenarios); chat history contains 3 ping/pong message pairs.
- **Cache miss**: if `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst` doesn't exist on this machine, restore auto-calls `regen_echo_peer_seed.sh` to populate. Generation takes a few minutes (launches Toxee, drives via marionette, snapshots). Subsequent restores are fast.
- **Echo peer NOT running**: the bot is intentionally offline during this scenario — the friend appears Offline. Tests that depend on peer being Online belong in `peerHarness=echo_live` scenarios.
- Account A logged in, plaintext, sidebar Online (poll 60s)
- `local_friends:<toxA_prefix16>` contains `<toxF>`
- `friend_nickname_<toxF>_<toxA_prefix16>` = `Friend Original` (the unambiguous "before" label)
- `friend_remark_<toxF>_<toxA_prefix16>` MUST be absent pre-test (so A1/A3 observe a fresh write, not a no-op). Verify: `defaults read ... | grep "does not exist"`.
- Note: scoped key uses FIRST 16 CHARS of `<toxA>`, matching `Prefs._scopedKey`

## Driver
1. `marionette.tap({ key: "sidebar_contacts_tab" })`; tap F's row (label `Friend Original`) → push `TencentCloudChatUserProfile`
2. Tap `UiKeys.userProfileEditRemarkButton` (`user_profile_edit_remark_button`) adjacent to the name text.
3. Dialog mounts at `UiKeys.userProfileModifyRemarkDialog` (`user_profile_modify_remark_dialog`) with title `tL10n.modifyRemark` ("Modify remark"/"修改备注"). Enter `Custom Alias` into `UiKeys.userProfileModifyRemarkTextField` (`user_profile_modify_remark_text_field`).
4. Tap `UiKeys.userProfileModifyRemarkConfirmButton` (`user_profile_modify_remark_confirm_button`).
5. Navigate back to Contacts; verify the list row label
6. Optional restart leg: kill toxee, relaunch, reconnect MCP, re-snapshot

## Assertions — A-block (must pass on current build)
- A1: profile-body name `Text` at `UiKeys.userProfileFriendNameText` now reads `Custom Alias` (not `Friend Original`)
- A2: contact-list row label for `<toxF>` flipped to `Custom Alias`
- A3 (primary persistence): `Prefs.friend_remark_<toxF>_<toxA_prefix16>` literal = `Custom Alias`
- A4: `Prefs.friend_nickname_<toxF>_<toxA_prefix16>` UNCHANGED — alias is local, did not overwrite peer's nickname
- A5: after restart, contact-list row still reads `Custom Alias` — proves `fakeUserToV2TimFriendInfo` → `prefs.getFriendRemark` cold read path
- A6: NO `tox_friend_send_*` log line during the dialog flow (alias is local-only, never on the wire)
- A7: log shows `setFriendInfo` followed by `code: 0`
- A9: `official.get_runtime_errors({})` empty vs Step 0 baseline
- Negative grep: `no preferences service available` MUST NOT appear (this means the adapter is unwired)

## Assertions — B-block (known gap, do NOT fail the run)
- B1: Chats-tab sidebar row for `c2c_<toxF>` showName reflects `Custom Alias` — FAILS today; `FakeConversation.title` is set from nickname not remark (`fake_provider.dart:462`)
- B2: chat header title reflects `Custom Alias` — FAILS today (same root cause)
- B3: B1+B2 after restart — FAILS today
- Fix is separate PR: prefer `prefs.getFriendRemark` over `getFriendNickname` in `tim2tox_sdk_platform_converters.dart:461-468` AND `fake_provider.dart:_mapConv`, plus a `topicFriendRemarkChanged` event to nudge `_emitConvList`

## Notes
- **Runner gate (data half)**: `tool/mcp_test/scenarios/l3_friend_remark_toggle.json` (run via `dart run tool/mcp_test/run_l3_scenarios.dart`) drives `l3_set_friend_remark` with a unique-nonce remark, asserts `l3_dump_state.friends[].remark` contains it, then clears it (empty string) and asserts the friends list no longer contains it (the `state_not_contains` predicate/assertion). `l3_set_friend_remark` drives the SAME SDK boundary the profile remark dialog hits — `getFriendshipManager().setFriendInfo(userID:, friendRemark:)` → `Tim2ToxSdkPlatform.setFriendInfo` → `ExtendedPreferencesService.setFriendRemark` (the adapter's account-scoped `_prefixKey`), then forces a contact-list rebuild (`l3_debug_tools.dart:3410-3432`). It does NOT write `Prefs.setFriendRemark` directly any more, which matters: `l3_dump_state.friends[].remark` reads back through the OTHER key implementation (`Prefs.getFriendRemark` / `Prefs._scopedKey`), so the round-trip is a genuine cross-implementation check of the two independent account-scoping key builders rather than a write-and-read of the same one. `Tim2ToxSdkPlatform.setFriendInfo` returns `code != 0` when no preferences service is attached, so a silently-dropped remark fails loudly. An empty remark clears it (the adapter `remove`s the key). The remark is account-scoped and local-only — distinct from the Tox `nickName`. This gate proves the set/clear persistence round-trip only; the alias-in-conversation-header display (B-block above) is a separate UIKit concern not exercised here.
- The seeded fixture pins the friend's `<toxF>` (echo peer ID) and the active account prefix `<toxA_prefix16>` per `manifest.json:peer_id` / `manifest.json:prefix`. The A3 persistence assertion lands on the per-account scoped wire key `flutter.friend_remark_<toxF>_<toxA_prefix16>` (note `flutter.` prefix from `shared_preferences`; see `lib/util/prefs.dart`). Pre-test absence check: `defaults read com.toxee.app "flutter.friend_remark_<toxF>_<toxA_prefix16>" 2>&1 | grep "does not exist"`.
- Playbook prose "tap 备注 field" is wrong — there is no inline editable row, only a pencil + dialog. "备注" appears only in the dialog title.
- The edit flow now exposes stable anchors for the pencil button, profile name text, dialog root, dialog field, and confirm action.
- `setFriendInfo` with empty string DELETES the alias (`shared_prefs_adapter.dart:262-267` calls `remove(key)` on empty) — useful for a B30b clear-alias variant
- Cancel-path widget at `tencent_cloud_chat_user_profile_body.dart:176-181` only calls `Navigator.pop`, never `_onChangeFriendRemark`; covered by S30b not S30
- Partial key status: `contact_list_tile:<toxId>`, `user_profile_edit_remark_button`, `user_profile_friend_name_text`, `user_profile_modify_remark_dialog`, `user_profile_modify_remark_text_field`, and `user_profile_modify_remark_confirm_button` are now available.
