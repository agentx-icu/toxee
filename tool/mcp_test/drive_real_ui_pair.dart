// Real-UI two-process driver.
//
// Unlike the l3_* "debug bypass" drivers (drive_fixture_c_*.dart), this drives
// the REAL UIKit widgets across two live instances via the `flutter_skill`
// service extensions (tap / enterText / waitForElement / screenshot), i.e. it
// exercises the actual buttons/fields a user touches ("直接驱动 UI 控件").
//
// Hard-won harness facts (see /tmp diagnostics + REAL_UI_GATES notes):
//   * The instances are raw-launched (`launch_toxee_instance.sh`, direct exec).
//     An UNFOCUSED macOS window does NOT pump frames / service platform
//     channels, so any async UI step (route push, SharedPreferences read) STALLS
//     while backgrounded. FIX: osascript-foreground the target pid before each
//     UI phase. Data/DHT keeps running on native threads regardless, so the
//     other instance can be backgrounded between phases.
//   * `flutter_skill.enterText{key}` only matches an *editable* widget carrying
//     the key; our keys sit on TextFormField wrappers, so use focusType =
//     tap{key} (general widget search) then enterText{no key} into the focus.
//   * `flutter_skill.screenshot` returns {image:<base64 png>} but only when the
//     window is foreground (else empty).
//
// Usage:
//   dart run tool/mcp_test/drive_real_ui_pair.dart <scenario> \
//       [--boot-restored] <wsA> <pidA> <nickA> <wsB> <pidB> <nickB>
// scenarios:
//   handshake         S26 + S61 — B sends an add-friend request, A ACCEPTS via
//                     the INLINE row button (contact_application_accept_button);
//                     asserts friendship + nickname propagation both directions.
//   handshake_detail  S108 — same, but A accepts via the pushed application-
//                     DETAIL screen (contact_application_detail_accept_button),
//                     the distinct UI entry point S26 does NOT exercise.
//   decline           S27 — A DECLINES the inbound request; asserts the
//                     application cleared and no friendship formed.
//   message           S62 + S64 — bidirectional message delivery through the
//                     REAL composer + a real Return (RUITEST_STAMP=<n> for a
//                     stable nonce).
//   custom_message    S54 — B sends a friend request carrying a distinctive
//                     custom message; A verifies the wording round-trips, then
//                     declines the request so the pair returns to no-friend.
//   call_voice        S65 + S67 + S76 — with an existing friendship, B starts
//                     a voice call from the real chat header, A accepts via the
//                     real incoming-call UI, then B hangs up.
//   call_reject       S68 — with an existing friendship, B starts a voice call
//                     and A rejects it via the real incoming-call UI.
//   message_burst     S64 — a short alternating burst through the real
//                     composer on an already-friended pair.
//   group_message     S151 — with an existing friendship, A creates a PRIVATE
//                     group and invites B (who auto-joins over the friend link),
//                     then both sides send through the REAL group composer. On
//                     test accounts this drives the l3 setup tools; on fresh
//                     non-test accounts it falls back to the REAL add-group
//                     dialog + add-member screen + ungated plumbing hooks (the
//                     l3 create/invite/setting/member-list/leave tools are
//                     test-gated).
//   group_create      S126/S127/S128/S129/S130 — single-instance: A opens the
//                     REAL add-group dialog, creates a group, opens the new
//                     group conversation, and sends one message through the
//                     REAL composer (own-sent bubble renders). No second peer —
//                     a fast surface check distinct from group_message delivery.
//   conference_message S156/S159/S160/S177/S181 — same two-process shape as
//                     group_message but a LEGACY Tox CONFERENCE (created via the
//                     Conference dialog type; C++ InviteUserToGroup branches to
//                     tox_conference_invite, B auto-joins via tox_conference_join).
//   probe_home_root   restored-live probe: drive into a routed chat, then
//                     verify l3_force_home_root(tab: contacts|chats) restores
//                     the expected shell without sidebar-click recovery.
//   reset_friendship  Internal runner utility: if A and/or B are currently
//                     friends, delete the friendship through the real profile
//                     UI until both sides are back to a no-friend state.
//
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'fixture_c_bootstrap.dart';

// This driver is split into `part` files by concern (one library, shared scope —
// moving a scenario between parts is purely organizational). main() and the
// scenario dispatch live here; the implementations live in the parts below.
//   inst          — Inst (VM-service connect, skill/l3 calls, tap/wait helpers).
//   shell         — startup/login, home/contacts/new-entry shells, recovery.
//   friends       — add/accept/decline/remark/delete + friendship reset.
//   message_call  — C2C messaging, the composer, and voice-call scenarios.
//   group         — group create/invite/join + group messaging.
//   settings      — login/settings real-UI scenarios (copy-id, export, logout…).
//   settings2     — Batch-1 settings sweep 2 (theme/locale/download/bootstrap/
//                   switch-toggle/password-mismatch/logout-cancel) + the
//                   sweep_settings2 chain.
//   profile       — Batch-2 self-profile sweep (open overlay / edit-toggle /
//                   nickname+status edit / copy-toxid / qr-copy; avatar SKIPs) +
//                   the sweep_profile chain.
//   login         — Batch-3 login/register sweep (logout, saved-account card,
//                   register open/back + validation, restore SKIP, quick-login
//                   wrong/correct password + remove, account switch) +
//                   the sweep_login chain.
//   contacts      — Batch-4 contacts/friend-profile sweep (add-friend dialog
//                   guards, contact subtabs, row->profile, send-message tile,
//                   pin/block/mute/remark, clear-history, blocked-list unblock,
//                   contact search, delete-friend) + the sweep_contacts chain
//                   (TWO-PROCESS: one handshake at the top, delete-friend last).
//   group_profile — group profile, rename, search, add-member, member list.
//   group_menu    — conversation-row menu (pin/mark-read/clear/delete) + bursts.
//   conv          — Batch-5 conversation-list C2C sweep (right-click row menu
//                   surface, pin/unpin reorder, mark-read, delete-row,
//                   clear-history, clear-preserves-pin, unread bump/clear,
//                   preview-on-inbound, presence SKIP, conversation search) +
//                   the sweep_conv chain (TWO-PROCESS: one handshake, delete-row
//                   near last + re-seed so the launch ends friends).
//   chat          — Batch-6 chat-surface C2C sweep (open-from-row, multiline +
//                   long-text + emoji + sticker send, message context menu /
//                   copy / forward / delete, history load-more, inbound while
//                   scrolled up, header->profile, image/file bubbles; reply +
//                   offline SKIP) + the sweep_chat chain (TWO-PROCESS: one
//                   handshake, marks both accounts test to unblock l3 SEEDING).
//   c2c_extra     — focused C2C expansion: global search contact opens chat,
//                   non-destructive cancel branches for conversation/profile
//                   deletion surfaces, and chat-header profile send-back.
//   optimized     — orchestration-only bundles that reuse existing sweeps in a
//                   single app launch / friend relationship to reduce repeated
//                   launch, account creation, and add-friend cost.
//   p1_single     — P1/P2/P3-campaign Batch II (SINGLE-INSTANCE: drive only A):
//                   zh locale page walk, conference rename+leave, settings
//                   switch-account entry, login-card management menu (real
//                   long-press), account delete full flow (destructive, last)
//                   + the sweep_p1_single chain.
//   p1_chat       — P1/P2/P3-campaign Batch III (TWO-PROCESS chat/conv octet):
//                   recall roundtrip, read-receipt NEGATIVE pin, forward to a
//                   group target, draft NEGATIVE pin, typing DOUBLE-NEGATIVE
//                   pin, sidebar total-unread badge, search empty state, image
//                   preview hardened + the sweep_p1_chat chain.
//   p1_relaunch   — P1/P2/P3-campaign Batch IV (relaunch + profile-call
//                   quartet): autologin/history after instance restart,
//                   offline-pending then relaunch, profile voice/video call
//                   tiles, join-by-id real AddGroupDialog path.
//   p1_extra      — P1-extra feasible follow-ups (SINGLE-INSTANCE):
//                   Arabic real-app locale walk + keyboard global-search
//                   shortcut path.
//   account_conf_extra — focused account-management + conference expansion
//                   cases: cancel destructive account dialogs, switch cancel,
//                   conference profile/search send-back surfaces.
//   group_conf_member_extra — focused group/conference member-management cases:
//                   peer member menu, role-action smoke, member remove, and
//                   conference negative role/remove affordances.
//   high_value_extra — optimized follow-up real-App cases: C2C search-to-target,
//                   multi-account isolation, group/conference deep member/message
//                   flows, plus native-boundary guard probes.
//   p2_keys       — P1/P2/P3-campaign Batch V (P2 selector-backed cases):
//                   sticker face cell send, new-messages chip tap, and
//                   presence-dot state flip via relaunch.
//   p2_reply      — P1/P2/P3-campaign Batch VI (P2 reply seam/key case):
//                   C2C custom inbound seed + real Reply menu/send metadata.
//   p2_verify     — P1/P2/P3-campaign Batch VII (P2 verify-first result):
//                   pasted-image composer flow; voice/tray remain documented
//                   product gaps / L3-pinned surfaces.
//   p3             — P1/P2/P3-campaign Batch VIII (P3 writable subset):
//                   parametric C2C burst perf with advisory timing threshold.
part 'drive_real_ui_pair_inst.dart';
part 'drive_real_ui_pair_shell.dart';
part 'drive_real_ui_pair_friends.dart';
part 'drive_real_ui_pair_message_call.dart';
part 'drive_real_ui_pair_group.dart';
part 'drive_real_ui_pair_settings.dart';
part 'drive_real_ui_pair_settings2.dart';
part 'drive_real_ui_pair_profile.dart';
part 'drive_real_ui_pair_login.dart';
part 'drive_real_ui_pair_contacts.dart';
part 'drive_real_ui_pair_group_profile.dart';
part 'drive_real_ui_pair_group_menu.dart';
part 'drive_real_ui_pair_conv.dart';
part 'drive_real_ui_pair_chat.dart';
part 'drive_real_ui_pair_c2c_extra.dart';
part 'drive_real_ui_pair_optimized.dart';
part 'drive_real_ui_pair_group2.dart';
part 'drive_real_ui_pair_calls_misc.dart';
part 'drive_real_ui_pair_p1_single.dart';
part 'drive_real_ui_pair_p1_chat.dart';
part 'drive_real_ui_pair_p1_relaunch.dart';
part 'drive_real_ui_pair_p1_extra.dart';
part 'drive_real_ui_pair_account_conf_extra.dart';
part 'drive_real_ui_pair_group_conf_member_extra.dart';
part 'drive_real_ui_pair_high_value_extra.dart';
part 'drive_real_ui_pair_p2_keys.dart';
part 'drive_real_ui_pair_p2_reply.dart';
part 'drive_real_ui_pair_p2_verify.dart';
part 'drive_real_ui_pair_p3.dart';
part 'drive_real_ui_pair_app_entry_extra.dart';
part 'drive_real_ui_pair_group_mention.dart';

Future<void> main(List<String> args) async {
  exitCode = await HttpOverrides.runWithHttpOverrides(
    () => _main(args),
    _LocalVmServiceHttpOverrides(),
  );
}

Future<int> _main(List<String> args) async {
  if (args.length == 1 && args.single == '--self-test-shell-recovery') {
    return _runShellRecoverySelfTest();
  }
  final positional = <String>[];
  var bootRestored = false;
  for (final arg in args) {
    if (arg == '--boot-restored') {
      bootRestored = true;
    } else {
      positional.add(arg);
    }
  }
  if (positional.length < 7) {
    print(
      'usage: drive_real_ui_pair.dart <scenario> '
      '<wsA> <pidA> <nickA> <wsB> <pidB> <nickB>',
    );
    return 64;
  }
  final scenario = positional[0];
  final a = Inst('A', positional[1], int.parse(positional[2]));
  final nickA = positional[3];
  final b = Inst('B', positional[4], int.parse(positional[5]));
  final nickB = positional[6];
  await a.connect();
  await b.connect();
  try {
    _RestoredPair? restored;
    if (bootRestored) {
      restored = await _RestoredPair.load();
      await _ensureRestoredHome(a, restored.a);
      await _ensureRestoredHome(b, restored.b);
    }
    if (scenario == 'reset_friendship') {
      return await runResetFriendship(a, b, nickA, nickB);
    }
    if (scenario == 'custom_message') {
      return await runCustomMessage(a, b, nickA, nickB);
    }
    if (scenario == 'message') {
      // Stamp passed via env (scripts can't use DateTime determinism concerns here).
      final stamp =
          int.tryParse(Platform.environment['RUITEST_STAMP'] ?? '') ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return await runMessage(a, b, nickA, nickB, stamp);
    }
    if (scenario == 'message_burst') {
      return await runMessageBurst(a, b, nickA, nickB);
    }
    if (scenario == 'group_message') {
      return await runGroupMessage(a, b, nickA, nickB);
    }
    if (scenario == 'group_burst') {
      return await runGroupBurst(a, b, nickA, nickB);
    }
    if (scenario == 'group_member_list') {
      return await runGroupMemberList(a, b, nickA, nickB);
    }
    if (scenario == 'group_create') {
      // Single-instance: drive only A (B is launched-but-idle).
      return await runGroupCreate(a, nickA);
    }
    // Single-instance LOGIN + SETTINGS real-UI scenarios (drive only A).
    if (scenario == 'settings_sweep') {
      return await runSettingsSweep(a, nickA);
    }
    if (scenario == 'settings_copy_id') {
      await ensureHome(a, nickA);
      return await _settingsCopyId(a) ? 0 : 1;
    }
    if (scenario == 'settings_autologin') {
      await ensureHome(a, nickA);
      return await _settingsAutoLogin(a) ? 0 : 1;
    }
    if (scenario == 'settings_notification') {
      await ensureHome(a, nickA);
      return await _settingsNotification(a) ? 0 : 1;
    }
    if (scenario == 'settings_export_chooser') {
      await ensureHome(a, nickA);
      return await _settingsExportChooser(a) ? 0 : 1;
    }
    if (scenario == 'settings_password') {
      await ensureHome(a, nickA);
      return await _settingsPassword(a) ? 0 : 1;
    }
    if (scenario == 'settings_logout_relogin') {
      await ensureHome(a, nickA);
      return await _settingsLogoutRelogin(a) ? 0 : 1;
    }
    if (scenario == 'settings_logout_double_fire') {
      await ensureHome(a, nickA);
      return await _settingsLogoutDoubleFire(a) ? 0 : 1;
    }
    // Batch 1 — settings sweep 2 (single-instance; drive only A).
    if (scenario == 'sweep_settings2') {
      return await runSettingsSweep2(a, nickA);
    }
    if (scenario == 'settings_surface_sections') {
      await ensureHome(a, nickA);
      return await _settingsSurfaceSections(a) ? 0 : 1;
    }
    if (scenario == 'settings_theme_dark') {
      await ensureHome(a, nickA);
      return await _settingsThemeDark(a) ? 0 : 1;
    }
    if (scenario == 'settings_theme_light_back') {
      await ensureHome(a, nickA);
      return await _settingsThemeLightBack(a) ? 0 : 1;
    }
    if (scenario == 'settings_locale_zh_roundtrip') {
      await ensureHome(a, nickA);
      return await _settingsLocaleZhRoundtrip(a) ? 0 : 1;
    }
    if (scenario == 'settings_download_limit_edit') {
      await ensureHome(a, nickA);
      return await _settingsDownloadLimitEdit(a) ? 0 : 1;
    }
    if (scenario == 'settings_bootstrap_mode_cycle') {
      await ensureHome(a, nickA);
      return await _settingsBootstrapModeCycle(a) ? 0 : 1;
    }
    if (scenario == 'settings_bootstrap_manual_add_node') {
      await ensureHome(a, nickA);
      return await _settingsBootstrapManualAddNode(a) ? 0 : 1;
    }
    if (scenario == 'settings_bootstrap_manual_remove_node') {
      await ensureHome(a, nickA);
      return await _settingsBootstrapManualRemoveNode(a) ? 0 : 1;
    }
    if (scenario == 'settings_autologin_toggle_hard') {
      await ensureHome(a, nickA);
      return await _settingsAutologinToggleHard(a) ? 0 : 1;
    }
    if (scenario == 'settings_notifsound_toggle_hard') {
      await ensureHome(a, nickA);
      return await _settingsNotifSoundToggleHard(a) ? 0 : 1;
    }
    if (scenario == 'settings_password_mismatch_error') {
      await ensureHome(a, nickA);
      return await _settingsPasswordMismatchError(a) ? 0 : 1;
    }
    if (scenario == 'settings_logout_cancel') {
      await ensureHome(a, nickA);
      return await _settingsLogoutCancel(a) ? 0 : 1;
    }
    // Batch 2 — self profile (single-instance; drive only A). A `bool?` runner
    // returning null is a SKIP (no in-app avatar surface — cases 19/20), which
    // maps to a non-failing exit 0 here (the sweep tallies it as a SKIP).
    if (scenario == 'sweep_profile') {
      return await runProfileSweep(a, nickA);
    }
    if (scenario == 'profile_open_sidebar_avatar') {
      await ensureHome(a, nickA);
      return await _profileOpenSidebarAvatar(a) ? 0 : 1;
    }
    if (scenario == 'profile_edit_toggle_roundtrip') {
      await ensureHome(a, nickA);
      return await _profileEditToggleRoundtrip(a) ? 0 : 1;
    }
    if (scenario == 'profile_edit_nickname_persists') {
      await ensureHome(a, nickA);
      return await _profileEditNicknamePersists(a) ? 0 : 1;
    }
    if (scenario == 'profile_edit_status_persists') {
      await ensureHome(a, nickA);
      return await _profileEditStatusPersists(a) ? 0 : 1;
    }
    if (scenario == 'profile_copy_toxid_snackbar') {
      await ensureHome(a, nickA);
      return await _profileCopyToxIdSnackbar(a) ? 0 : 1;
    }
    if (scenario == 'profile_qr_copy') {
      await ensureHome(a, nickA);
      return await _profileQrCopy(a) ? 0 : 1;
    }
    if (scenario == 'profile_avatar_picker_opens') {
      await ensureHome(a, nickA);
      // A `bool?` runner returning null is a SKIP — exit 75 (the runner's
      // _realUiSkipExitCode, distinct from 0=PASS / 78=BLOCKED) so it is NOT
      // tallied as a PASS. false → 1 (FAIL); true → 0 (PASS) — neither happens
      // for these no-surface cases, which always return null.
      return await _profileAvatarPickerOpens(a) == false ? 1 : 75;
    }
    if (scenario == 'profile_avatar_select_default_applies') {
      await ensureHome(a, nickA);
      return await _profileAvatarSelectDefaultApplies(a) == false ? 1 : 75;
    }
    // Batch 3 — login / register (single-instance; drive only A). sweep_login
    // chains all 9 on one launch (the canonical entry). The individual cases
    // below run the minimum prelude each needs: cases that act on the LoginPage
    // (21/22/23/24/25) log out first; the password cases (27/28) and the account
    // switch (29) manage their own logout/login internally; 26 is a SKIP (exit
    // 75, like the Batch-2 avatar SKIPs).
    if (scenario == 'sweep_login') {
      return await runLoginSweep(a, nickA);
    }
    if (scenario == 'login_register_open_back') {
      await ensureHome(a, nickA);
      if ((await _logoutToLoginPage(a)).isEmpty) return 1;
      return await _loginRegisterOpenBack(a) ? 0 : 1;
    }
    if (scenario == 'login_account_card_renders') {
      await ensureHome(a, nickA);
      final tox =
          (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
      final nk = (await a.dumpState())['nickname']?.toString() ?? nickA;
      if ((await _logoutToLoginPage(a)).isEmpty) return 1;
      return await _loginAccountCardRenders(a, tox, nk) ? 0 : 1;
    }
    if (scenario == 'login_restore_entry_opens') {
      await ensureHome(a, nickA);
      // SKIP — native picker only (exit 75; false -> 1; true -> 0, neither
      // happens since this always returns null). Logging out is unnecessary for
      // a SKIP but keep the page state simple by staying on HomePage.
      return await _loginRestoreEntryOpens(a) == false ? 1 : 75;
    }
    if (scenario == 'register_empty_nickname_error') {
      await ensureHome(a, nickA);
      if ((await _logoutToLoginPage(a)).isEmpty) return 1;
      return await _registerEmptyNicknameError(a) ? 0 : 1;
    }
    if (scenario == 'register_password_mismatch_error') {
      await ensureHome(a, nickA);
      if ((await _logoutToLoginPage(a)).isEmpty) return 1;
      return await _registerPasswordMismatchError(a) ? 0 : 1;
    }
    if (scenario == 'register_password_strength_flips') {
      await ensureHome(a, nickA);
      if ((await _logoutToLoginPage(a)).isEmpty) return 1;
      return await _registerPasswordStrengthFlips(a) ? 0 : 1;
    }
    if (scenario == 'login_password_wrong_error') {
      await ensureHome(a, nickA);
      return await _loginPasswordWrongError(a, <String>[]) ? 0 : 1;
    }
    if (scenario == 'login_password_correct_unlocks') {
      // Standalone: set a pw, log out, then unlock with the correct pw + remove.
      await ensureHome(a, nickA);
      final holder = <String>[];
      final wrongOk = await _loginPasswordWrongError(a, holder);
      if (!wrongOk || holder.isEmpty) return 1;
      return await _loginPasswordCorrectUnlocks(a, holder.first) ? 0 : 1;
    }
    if (scenario == 'account_switch_second_account') {
      await ensureHome(a, nickA);
      final tox =
          (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
      return await _accountSwitchSecondAccount(a, tox) ? 0 : 1;
    }
    // Batch 4 — contacts / friend profile (TWO-PROCESS). sweep_contacts chains
    // all 15 on one launch (the canonical entry; one handshake at the top,
    // delete-friend last so the launch ends no-friend). The individual cases
    // are dispatchable too: the add-friend dialog guards (30/31/32) run on a
    // fresh no-friend launch (A-only); the friendship-dependent cases (33+)
    // establish the A<->B friendship first via the real-UI handshake.
    if (scenario == 'sweep_contacts') {
      return await runContactsSweep(a, b, nickA, nickB);
    }
    if (scenario == 'add_friend_dialog_esc_close' ||
        scenario == 'add_friend_invalid_id_error' ||
        scenario == 'add_friend_self_id_guard') {
      await ensureHome(a, nickA);
      final tox =
          (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
      switch (scenario) {
        case 'add_friend_dialog_esc_close':
          return await _addFriendDialogEscClose(a) ? 0 : 1;
        case 'add_friend_invalid_id_error':
          return await _addFriendInvalidIdError(a) ? 0 : 1;
        case 'add_friend_self_id_guard':
          return await _addFriendSelfIdGuard(a, tox) ? 0 : 1;
      }
    }
    if (scenario == 'contacts_subtabs_cycle') {
      await ensureHome(a, nickA);
      return await _contactsSubtabsCycle(a) ? 0 : 1;
    }
    if (scenario == 'add_friend_duplicate_guard' ||
        scenario == 'contacts_row_opens_friend_profile' ||
        scenario == 'friendprof_send_message_tile' ||
        scenario == 'friendprof_pin_toggle' ||
        scenario == 'friendprof_block_unblock' ||
        scenario == 'friendprof_mute_toggle_regression' ||
        scenario == 'friendprof_remark_edit_persists' ||
        scenario == 'friendprof_clear_history' ||
        scenario == 'blocked_list_unblock_row' ||
        scenario == 'contact_search_filter_clear' ||
        scenario == 'friendprof_delete_friend_confirm') {
      // Friendship-dependent: ensure A<->B friends first (the runner restores
      // paired_for_e2e for these, but a standalone direct invocation may need
      // the handshake). ensureHome both, then establish the friendship.
      if (!bootRestored) {
        await ensureHome(a, nickA);
        await ensureHome(b, nickB, requireHomeMenu: false);
      }
      final tox2A =
          (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
      final tox2B =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      if (tox2A.isEmpty || tox2B.isEmpty) {
        throw DriveError('missing tox ids for $scenario: A=$tox2A B=$tox2B');
      }
      if (!await _establishFriendshipForSweep(
        a,
        b,
        tox2A,
        tox2B,
        nickA,
        nickB,
      )) {
        print('[pair] $scenario: could not establish friendship');
        return 1;
      }
      switch (scenario) {
        case 'add_friend_duplicate_guard':
          return await _addFriendDuplicateGuard(b, tox2A) ? 0 : 1;
        case 'contacts_row_opens_friend_profile':
          return await _contactsRowOpensFriendProfile(a, tox2B) ? 0 : 1;
        case 'friendprof_send_message_tile':
          return await _friendprofSendMessageTile(a, tox2B) ? 0 : 1;
        case 'friendprof_pin_toggle':
          return await _friendprofPinToggle(a, tox2B) ? 0 : 1;
        case 'friendprof_block_unblock':
          return await _friendprofBlockUnblock(a, tox2B) ? 0 : 1;
        case 'friendprof_mute_toggle_regression':
          return await _friendprofMuteToggleRegression(a, b, tox2B) ? 0 : 1;
        case 'friendprof_remark_edit_persists':
          return await _friendprofRemarkEditPersists(a, tox2B) ? 0 : 1;
        case 'friendprof_clear_history':
          return await _friendprofClearHistory(a, tox2B) ? 0 : 1;
        case 'blocked_list_unblock_row':
          return await _blockedListUnblockRow(a, tox2B) ? 0 : 1;
        case 'contact_search_filter_clear':
          return await _contactSearchFilterClear(a, tox2B, nickB) ? 0 : 1;
        case 'friendprof_delete_friend_confirm':
          return await _friendprofDeleteFriendConfirm(a, b, tox2A, tox2B)
              ? 0
              : 1;
      }
    }
    // Batch 5 — conversation list C2C (TWO-PROCESS). sweep_conv chains all 10 on
    // one launch (the canonical entry; one handshake at the top, delete-row near
    // last + re-seed so the launch ends friends). The individual cases are
    // dispatchable too: all need an A<->B friendship, so they establish it first
    // via the real-UI handshake (or reuse the runner's restored paired_for_e2e).
    if (scenario == 'sweep_conv') {
      return await runConvSweep(a, b, nickA, nickB);
    }
    if (scenario == 'conv_menu_surface_c2c' ||
        scenario == 'conv_pin_unpin_reorders' ||
        scenario == 'conv_mark_read_two_proc' ||
        scenario == 'conv_delete_confirm_c2c' ||
        scenario == 'conv_clear_history_c2c' ||
        scenario == 'conv_clear_preserves_pin_c2c' ||
        scenario == 'conv_unread_badge_bump_clear' ||
        scenario == 'conv_preview_updates_on_inbound' ||
        scenario == 'conv_presence_dot_flips' ||
        scenario == 'conv_search_filter_clear') {
      if (!bootRestored) {
        await ensureHome(a, nickA);
        await ensureHome(b, nickB, requireHomeMenu: false);
      }
      final cTox2A =
          (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
      final cTox2B =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      if (cTox2A.isEmpty || cTox2B.isEmpty) {
        throw DriveError('missing tox ids for $scenario: A=$cTox2A B=$cTox2B');
      }
      if (!await _establishFriendshipForSweep(
        a,
        b,
        cTox2A,
        cTox2B,
        nickA,
        nickB,
      )) {
        print('[pair] $scenario: could not establish friendship');
        return 1;
      }
      switch (scenario) {
        case 'conv_menu_surface_c2c':
          return await _convMenuSurfaceC2c(a, cTox2B) ? 0 : 1;
        case 'conv_pin_unpin_reorders':
          return await _convPinUnpinReorders(a, cTox2B) ? 0 : 1;
        case 'conv_mark_read_two_proc':
          return await _convMarkReadTwoProc(a, b, cTox2A, cTox2B) ? 0 : 1;
        case 'conv_delete_confirm_c2c':
          return await _convDeleteConfirmC2c(a, cTox2B) ? 0 : 1;
        case 'conv_clear_history_c2c':
          return await _convClearHistoryC2c(a, cTox2B) ? 0 : 1;
        case 'conv_clear_preserves_pin_c2c':
          return await _convClearPreservesPinC2c(a, cTox2B) ? 0 : 1;
        case 'conv_unread_badge_bump_clear':
          return await _convUnreadBadgeBumpClear(a, b, cTox2A, cTox2B) ? 0 : 1;
        case 'conv_preview_updates_on_inbound':
          return await _convPreviewUpdatesOnInbound(a, b, cTox2A, cTox2B)
              ? 0
              : 1;
        case 'conv_presence_dot_flips':
          // SKIP (exit 75) — presence flip un-seedable on a reused launch;
          // false → 1 (FAIL); true → 0 (PASS), neither happens (always null).
          return await _convPresenceDotFlips(a, cTox2B) == false ? 1 : 75;
        case 'conv_search_filter_clear':
          return await _convSearchFilterClear(a, cTox2B, nickB) ? 0 : 1;
      }
    }
    // Batch 6 — chat surface C2C (TWO-PROCESS). sweep_chat chains all 16 on one
    // launch (the canonical entry; one handshake at the top, marks both accounts
    // test to unblock l3 SEEDING). The individual cases are dispatchable too: all
    // need an A<->B friendship, so they establish it first via the real-UI
    // handshake (or reuse the runner's restored paired_for_e2e). The cases that
    // SEED via the test-gated tools (image/file) mark the account test inline.
    if (scenario == 'sweep_chat') {
      return await runChatSweep(a, b, nickA, nickB);
    }
    if (scenario == 'chat_open_from_row' ||
        scenario == 'chat_multiline_send' ||
        scenario == 'chat_long_text_send' ||
        scenario == 'chat_emoji_insert_send' ||
        scenario == 'chat_sticker_panel_send' ||
        scenario == 'chat_msg_menu_surface' ||
        scenario == 'chat_copy_message_clipboard' ||
        scenario == 'chat_reply_quote_roundtrip' ||
        scenario == 'chat_forward_to_other_conv' ||
        scenario == 'chat_delete_message_gone' ||
        scenario == 'chat_history_scroll_load_more' ||
        scenario == 'chat_inbound_while_scrolled_up' ||
        scenario == 'chat_header_opens_profile' ||
        scenario == 'chat_offline_pending_then_deliver' ||
        scenario == 'chat_image_bubble_open_preview' ||
        scenario == 'chat_file_bubble_present_open') {
      if (!bootRestored) {
        await ensureHome(a, nickA);
        await ensureHome(b, nickB, requireHomeMenu: false);
      }
      final chTox2A =
          (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
      final chTox2B =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      if (chTox2A.isEmpty || chTox2B.isEmpty) {
        throw DriveError(
          'missing tox ids for $scenario: A=$chTox2A B=$chTox2B',
        );
      }
      if (!await _establishFriendshipForSweep(
        a,
        b,
        chTox2A,
        chTox2B,
        nickA,
        nickB,
      )) {
        print('[pair] $scenario: could not establish friendship');
        return 1;
      }
      // Cases that SEED via test-gated tools need the seed marker on both peers.
      // The marker grants the WHOLE gated surface, so REVOKE it in a `finally`
      // so the individual dispatch doesn't leave a privileged account behind
      // (codex P1 — mirrors the sweep's end-guard).
      final needsMarker =
          scenario == 'chat_image_bubble_open_preview' ||
          scenario == 'chat_file_bubble_present_open';
      if (needsMarker) {
        await a.markAccountTest();
        await b.markAccountTest();
      }
      // Map a `bool?` runner: null → SKIP (75), false → FAIL (1), true → PASS (0).
      int skipMap(bool? r) => r == null ? 75 : (r ? 0 : 1);
      try {
        switch (scenario) {
          case 'chat_open_from_row':
            return await _chatOpenFromRow(a, chTox2B) ? 0 : 1;
          case 'chat_multiline_send':
            return await _chatMultilineSend(a, b, chTox2A, chTox2B) ? 0 : 1;
          case 'chat_long_text_send':
            return await _chatLongTextSend(a, b, chTox2A, chTox2B) ? 0 : 1;
          case 'chat_emoji_insert_send':
            return await _chatEmojiInsertSend(a, b, chTox2A, chTox2B) ? 0 : 1;
          case 'chat_sticker_panel_send':
            return await _chatStickerPanelSend(a, chTox2B) ? 0 : 1;
          case 'chat_msg_menu_surface':
            return await _chatMsgMenuSurface(a, chTox2B) ? 0 : 1;
          case 'chat_copy_message_clipboard':
            return await _chatCopyMessageClipboard(a, chTox2B) ? 0 : 1;
          case 'chat_reply_quote_roundtrip':
            // SKIP — no driveable C2C reply surface (always returns null → 75).
            return skipMap(await _chatReplyQuoteRoundtrip(a, chTox2B));
          case 'chat_forward_to_other_conv':
            return await _chatForwardToOtherConv(a, chTox2B, nickB) ? 0 : 1;
          case 'chat_delete_message_gone':
            return await _chatDeleteMessageGone(a, chTox2B) ? 0 : 1;
          case 'chat_history_scroll_load_more':
            {
              final seeded = await _seedChatHistory(a, b, chTox2A, chTox2B);
              return await _chatHistoryScrollLoadMore(
                    a,
                    b,
                    chTox2A,
                    chTox2B,
                    earliestText: seeded?.earliestText ?? '',
                    earliestId: seeded?.earliestId ?? '',
                  )
                  ? 0
                  : 1;
            }
          case 'chat_inbound_while_scrolled_up':
            {
              final seeded = await _seedChatHistory(a, b, chTox2A, chTox2B);
              return await _chatInboundWhileScrolledUp(
                    a,
                    b,
                    chTox2A,
                    chTox2B,
                    earliestText: seeded?.earliestText ?? '',
                    earliestId: seeded?.earliestId ?? '',
                  )
                  ? 0
                  : 1;
            }
          case 'chat_header_opens_profile':
            return await _chatHeaderOpensProfile(a, chTox2B) ? 0 : 1;
          case 'chat_offline_pending_then_deliver':
            // SKIP — offline-pending un-seedable (always returns null → 75).
            return skipMap(await _chatOfflinePendingThenDeliver(a, chTox2B));
          case 'chat_image_bubble_open_preview':
            return await _chatImageBubbleOpenPreview(a, b, chTox2A, chTox2B)
                ? 0
                : 1;
          case 'chat_file_bubble_present_open':
            return await _chatFileBubblePresentOpen(a, b, chTox2A, chTox2B)
                ? 0
                : 1;
        }
      } finally {
        if (needsMarker) {
          await a.unmarkAccountTest();
          await b.unmarkAccountTest();
        }
      }
    }
    // Focused C2C expansion. The sweep starts no-friend and establishes A<->B
    // once; individual cases need friendship and create/retain a visible row.
    if (scenario == 'sweep_c2c_extra') {
      return await runC2cExtraSweep(a, b, nickA, nickB);
    }
    if (_isC2cExtraCaseScenario(scenario)) {
      return await runC2cExtraCase(a, b, nickA, nickB, scenario);
    }
    // Optimized real-UI bundles. These are orchestration-only wrappers around
    // existing sweeps, designed for run-phase throughput rather than debugging.
    if (_isOptimizedSweepScenario(scenario)) {
      return await runOptimizedSweep(a, b, nickA, nickB, scenario);
    }
    // Batch 7 — group / conference (MIXED single-instance + two-process).
    // sweep_group2 chains all 14 on one launch (the canonical entry; one
    // handshake at the top, one shared PRIVATE group + one shared conference
    // created via the REAL add-group dialog). The individual group/conference
    // cases are dispatchable too — they establish their OWN minimal precondition
    // (handshake + a fresh private/conference group; 2p cases also join B).
    if (scenario == 'sweep_group2') {
      return await runGroup2Sweep(a, b, nickA, nickB);
    }
    if (_isGroup2CaseScenario(scenario)) {
      return await runGroup2Case(a, b, nickA, nickB, scenario);
    }
    // Batch 8 — calls / misc (TWO-PROCESS for the call + chat-open cases,
    // single-instance for window-resize). sweep_calls_misc chains all 10 on one
    // launch (the canonical entry; one handshake at the top, the call state
    // chained efficiently — voice block then video block — and the friendship
    // never deleted so the launch ends friends). The individual cases are
    // dispatchable too: the friendship cases establish it first (or reuse the
    // runner's restored paired_for_e2e); window-resize is single-instance.
    if (scenario == 'sweep_calls_misc') {
      return await runCallsMiscSweep(a, b, nickA, nickB);
    }
    if (_isCallsMiscCaseScenario(scenario)) {
      return await runCallsMiscCase(
        a,
        b,
        nickA,
        nickB,
        scenario,
        bootRestored: bootRestored,
      );
    }
    // P1/P2/P3 campaign Batch II — single-instance account/locale/conference
    // cases (drive only A; B idle). sweep_p1_single chains all 5 on one launch
    // (the canonical entry; ends clean — primary logged in, locale EN, the
    // throwaway #2 account deleted). The individual cases run their minimal
    // prelude inside runP1SingleCase.
    if (scenario == 'sweep_p1_single') {
      return await runP1SingleSweep(a, nickA);
    }
    if (_isP1SingleCaseScenario(scenario)) {
      return await runP1SingleCase(a, nickA, scenario);
    }
    // P1/P2/P3 campaign Batch III — two-process chat/conv octet. sweep_p1_chat
    // chains all 8 on one launch (the canonical entry; one handshake at the
    // top, marks both accounts test for l3 seeding, and revokes the marker in
    // its end-guard). Individual cases need an A<->B friendship; standalone
    // dispatch gets that from paired_for_e2e or establishes it here.
    if (scenario == 'sweep_p1_chat') {
      return await runP1ChatSweep(a, b, nickA, nickB);
    }
    if (_isP1ChatCaseScenario(scenario)) {
      return await runP1ChatCase(
        a,
        b,
        nickA,
        nickB,
        scenario,
        bootRestored: bootRestored,
      );
    }
    // P1/P2/P3 campaign Batch IV — relaunch-capable scenarios. The sweep starts
    // from a fresh no-friend pair and does its own handshake; individual cases
    // need a restored friendship. Cases may restart one instance internally and
    // return relaunch-dirty so the runner stops/relaunches before the next case.
    if (scenario == 'sweep_p1_relaunch') {
      return await runP1RelaunchSweep(a, b, nickA, nickB);
    }
    if (_isP1RelaunchCaseScenario(scenario)) {
      return await runP1RelaunchCase(
        a,
        b,
        nickA,
        nickB,
        scenario,
        bootRestored: bootRestored,
      );
    }
    // P1 extra — single-instance feasible follow-ups from the inventory's
    // "still add" bucket. Drives only A; B is idle.
    if (scenario == 'sweep_p1_extra') {
      return await runP1ExtraSweep(a, nickA);
    }
    if (_isP1ExtraCaseScenario(scenario)) {
      return await runP1ExtraCase(a, nickA, scenario);
    }
    // App-entry extra — single-instance (drive only A). §7.5.1 high-frequency,
    // low-cost real-control cases.
    if (scenario == 'sweep_app_entry_extra') {
      return await runAppEntryExtraSweep(a, nickA);
    }
    if (_isAppEntryExtraCaseScenario(scenario)) {
      return await runAppEntryExtraCase(a, nickA, scenario);
    }
    // Group @-mention — two-process (§7.5.1). Establishes (or reuses) the A<->B
    // friendship + a shared private group, then drives the real @ panel.
    if (scenario == 'sweep_group_mention') {
      return await runGroupMentionSweep(a, b, nickA, nickB);
    }
    if (_isGroupMentionCaseScenario(scenario)) {
      return await runGroupMentionCase(a, b, nickA, nickB, scenario);
    }
    // Focused account-management + conference expansion sweep. Single-instance
    // by design; B stays idle.
    if (scenario == 'sweep_account_conf_extra') {
      return await runAccountConfExtraSweep(a, nickA);
    }
    if (_isAccountConfExtraCaseScenario(scenario)) {
      return await runAccountConfExtraCase(a, nickA, scenario);
    }
    // Focused group/conference member-management expansion. The sweep starts
    // no-friend, establishes A<->B once, then creates fresh group/conference
    // targets per case. Individual cases need an existing friendship.
    if (scenario == 'sweep_group_conf_member_extra') {
      return await runGroupConfMemberExtraSweep(a, b, nickA, nickB);
    }
    if (_isGroupConfMemberExtraCaseScenario(scenario)) {
      return await runGroupConfMemberExtraCase(a, b, nickA, nickB, scenario);
    }
    // Highest-value follow-up additions. The c2c/account/group deep sweeps are
    // stable enough for optimized bundles; native-boundary guards stay separate
    // because some OS-bound surfaces honestly SKIP on this desktop harness.
    if (scenario == 'sweep_c2c_deep_extra') {
      return await runC2cDeepExtraSweep(a, b, nickA, nickB);
    }
    if (_isC2cDeepExtraCaseScenario(scenario)) {
      return await runC2cDeepExtraCase(a, b, nickA, nickB, scenario);
    }
    if (scenario == 'sweep_account_deep_extra') {
      return await runAccountDeepExtraSweep(a, nickA);
    }
    if (_isAccountDeepExtraCaseScenario(scenario)) {
      return await runAccountDeepExtraCase(a, nickA, scenario);
    }
    if (scenario == 'sweep_group_conf_deep_extra') {
      return await runGroupConfDeepExtraSweep(a, b, nickA, nickB);
    }
    if (_isGroupConfDeepExtraCaseScenario(scenario)) {
      return await runGroupConfDeepExtraCase(a, b, nickA, nickB, scenario);
    }
    if (scenario == 'sweep_native_boundary_guards') {
      return await runNativeBoundaryGuardSweep(a, b, nickA, nickB);
    }
    if (_isNativeBoundaryGuardCaseScenario(scenario)) {
      return await runNativeBoundaryGuardCase(a, b, nickA, nickB, scenario);
    }
    // P1/P2/P3 campaign Batch V — P2 cases made driveable by fork keys. The
    // sweep starts from no-friend and does its own handshake; presence restart
    // returns relaunch-dirty so the runner relaunches before later work.
    if (scenario == 'sweep_p2_keys') {
      return await runP2KeysSweep(a, b, nickA, nickB);
    }
    if (_isP2KeysCaseScenario(scenario)) {
      return await runP2KeysCase(
        a,
        b,
        nickA,
        nickB,
        scenario,
        bootRestored: bootRestored,
      );
    }
    // P1/P2/P3 campaign Batch VI — P2 reply case made driveable by a C2C
    // custom-inbound l3 seam plus a keyed quote banner.
    if (scenario == 'sweep_p2_reply') {
      return await runP2ReplySweep(a, b, nickA, nickB);
    }
    if (_isP2ReplyCaseScenario(scenario)) {
      return await runP2ReplyCase(
        a,
        b,
        nickA,
        nickB,
        scenario,
        bootRestored: bootRestored,
      );
    }
    // P1/P2/P3 campaign Batch VII — verify-first P2 trio outcome. Only
    // pasted-image has a driveable write-phase desktop surface; voice/tray
    // findings are recorded in the campaign anchor.
    if (scenario == 'sweep_p2_verify') {
      return await runP2VerifySweep(a, b, nickA, nickB);
    }
    if (_isP2VerifyCaseScenario(scenario)) {
      return await runP2VerifyCase(
        a,
        b,
        nickA,
        nickB,
        scenario,
        bootRestored: bootRestored,
      );
    }
    // P1/P2/P3 campaign Batch VIII — P3 writable subset. The real-UI case is
    // message_burst_perf; ar_rtl_smoke is a hermetic Flutter smoke test.
    if (scenario == 'sweep_p3_writable') {
      return await runP3WritableSweep(a, b, nickA, nickB);
    }
    if (_isP3WritableCaseScenario(scenario)) {
      return await runP3WritableCase(
        a,
        b,
        nickA,
        nickB,
        scenario,
        bootRestored: bootRestored,
      );
    }
    if (scenario == 'group_profile_open') {
      return await runGroupProfileOpen(a, nickA);
    }
    if (scenario == 'group_rename') {
      return await runGroupRename(a, nickA);
    }
    if (scenario == 'group_search') {
      return await runGroupSearch(a, nickA);
    }
    if (scenario == 'group_add_member_open') {
      return await runGroupAddMemberOpen(a, nickA);
    }
    if (scenario == 'group_add_member_picker') {
      return await runGroupAddMemberPicker(a, b, nickA, nickB);
    }
    if (scenario == 'group_conversation_menu') {
      return await runGroupConversationMenu(a, nickA);
    }
    if (scenario == 'group_menu_pin_unpin') {
      return await runGroupMenuPinUnpin(a, nickA);
    }
    if (scenario == 'group_menu_mark_read') {
      return await runGroupMenuMarkRead(a, nickA);
    }
    if (scenario == 'group_menu_delete_confirm') {
      return await runGroupMenuDeleteConfirm(a, nickA);
    }
    if (scenario == 'group_menu_mark_read_unread') {
      // Two-process: B seeds real unread on A, A marks read via the row menu.
      return await runGroupMarkReadUnread(a, b, nickA, nickB);
    }
    if (scenario == 'group_clear_history') {
      // Two-process: B seeds history, A clears it; row survives.
      return await runGroupClearHistory(a, b, nickA, nickB);
    }
    if (scenario == 'group_clear_preserves_pin') {
      // Two-process: A pins, B seeds history, A clears; row stays pinned.
      return await runGroupClearPreservesPin(a, b, nickA, nickB);
    }
    if (scenario == 'conference_message') {
      // Same two-process flow as group_message but a legacy Tox CONFERENCE.
      return await runGroupMessage(
        a,
        b,
        nickA,
        nickB,
        groupType: 'conference',
        label: 'CONF',
        namePrefix: 'RUI-CONF',
        msgPrefix: 'RUICONF',
      );
    }
    if (scenario == 'probe_home_root') {
      return await runProbeHomeRoot(a, b, nickA, nickB);
    }
    if (scenario == 'call_voice') {
      return await runCallVoice(a, b, nickA, nickB);
    }
    if (scenario == 'call_reject') {
      return await runCallReject(a, b, nickA, nickB);
    }
    if (!bootRestored) {
      final needsNoFriendFlow =
          scenario == 'handshake' ||
          scenario == 'handshake_detail' ||
          scenario == 'decline';
      await ensureHome(a, nickA, requireHomeMenu: !needsNoFriendFlow);
      if (needsNoFriendFlow) {
        await ensureHome(b, nickB, requireHomeMenu: false);
        await ensureNewEntryShell(b);
      } else {
        await ensureHome(b, nickB);
      }
    }

    final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
    final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
    if (toxA.isEmpty || toxB.isEmpty) {
      throw DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[pair] toxA=${toxA.substring(0, 16)}.. toxB=${toxB.substring(0, 16)}..',
    );

    // Wait for both connected to the DHT before the handshake.
    await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
    await b.waitState((s) => s['isConnected'] == true, label: 'B connected');

    final accept = scenario != 'decline';
    await driveAddFriend(
      b,
      toxA,
      message: _defaultFriendRequestWording(scenario),
    );
    if (scenario == 'handshake_detail') {
      // S108: accept via the pushed application-DETAIL screen, not the inline row.
      await driveRespondViaDetail(a, toxB);
    } else {
      await driveRespondToApplication(a, toxB, accept: accept);
    }

    // Verify outcome.
    if (accept) {
      await a.waitState((_) => true, timeoutSecs: 1);
      final aHasB = await _retryBool(
        () => areFriends(a, toxB),
        label: 'A has B as friend',
      );
      final bHasA = await _retryBool(
        () => areFriends(b, toxA),
        label: 'B has A as friend',
      );
      // Name-propagation regression gate (the register-time setSelfInfo bug):
      // each peer must see the OTHER's registered nickname, not the raw tox-id.
      final aSeesNick = await _retryBool(
        () async =>
            _normalizeNick(await friendNick(a, toxB)) == _normalizeNick(nickB),
        label: 'A sees B nickname "$nickB"',
        attempts: 60,
      );
      final bSeesNick = await _retryBool(
        () async =>
            _normalizeNick(await friendNick(b, toxA)) == _normalizeNick(nickA),
        label: 'B sees A nickname "$nickA"',
        attempts: 60,
      );
      final aSeesNickNow =
          _normalizeNick(await friendNick(a, toxB)) == _normalizeNick(nickB);
      final bSeesNickNow =
          _normalizeNick(await friendNick(b, toxA)) == _normalizeNick(nickA);
      final finalASeesNick = aSeesNick || aSeesNickNow;
      final finalBSeesNick = bSeesNick || bSeesNickNow;
      print(
        '[pair] names: A sees B="${await friendNick(a, toxB)}" '
        'B sees A="${await friendNick(b, toxA)}"',
      );
      await a.shot('/tmp/ui_${scenario}_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_${scenario}_B.png');
      if (aHasB && bHasA && finalASeesNick && finalBSeesNick) {
        print('[pair] PASS: friendship + name propagation both directions');
        return 0;
      }
      print(
        '[pair] FAIL: aHasB=$aHasB bHasA=$bHasA '
        'aSeesNick=$finalASeesNick bSeesNick=$finalBSeesNick',
      );
      return 1;
    } else {
      // Decline: application should clear on A and no friendship forms.
      await Future<void>.delayed(const Duration(seconds: 3));
      final stillFriend = await areFriends(a, toxB);
      final apps =
          ((await a.dumpState())['friendApplications'] as List?) ?? const [];
      final appGone = !apps.any(
        (e) =>
            e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
      );
      await a.shot('/tmp/ui_${scenario}_A.png');
      if (!stillFriend && appGone) {
        print('[pair] PASS: decline removed application, no friendship');
        return 0;
      }
      print('[pair] FAIL: stillFriend=$stillFriend appGone=$appGone');
      return 1;
    }
  } on PermissionBlockedError catch (e) {
    print('[pair] BLOCKED: ${e.message}');
    return 78;
  } on DriveError catch (e) {
    print('[pair] ERROR: ${e.message}');
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
  }
}

Future<bool> _retryBool(
  Future<bool> Function() body, {
  required String label,
  int attempts = 30,
  int intervalMs = 1000,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (await body()) return true;
    await Future<void>.delayed(Duration(milliseconds: intervalMs));
  }
  print('[retry] "$label" never became true');
  return false;
}
