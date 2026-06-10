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
//   group_profile — group profile, rename, search, add-member, member list.
//   group_menu    — conversation-row menu (pin/mark-read/clear/delete) + bursts.
part 'drive_real_ui_pair_inst.dart';
part 'drive_real_ui_pair_shell.dart';
part 'drive_real_ui_pair_friends.dart';
part 'drive_real_ui_pair_message_call.dart';
part 'drive_real_ui_pair_group.dart';
part 'drive_real_ui_pair_settings.dart';
part 'drive_real_ui_pair_settings2.dart';
part 'drive_real_ui_pair_group_profile.dart';
part 'drive_real_ui_pair_group_menu.dart';

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
