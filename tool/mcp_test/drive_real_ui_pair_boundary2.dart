// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// #9 bind-contract boundary cases. Hosted in their own part file to keep the
// pinned high_value_extra at its LOC ratchet; they run inside
// sweep_native_boundary_guards with the same conventions.

/// system_back_unbinds_chat — a REAL OS back gesture must unbind the active
/// conversation (ActiveConversationRouteObserver.didPop is the unbind half of
/// the compact bind contract). The gesture is only injectable on Android
/// (adb keyevent 4); other shells SKIP — the didPop unbind itself is
/// unit-covered in test/navigation/active_conversation_route_observer_test.
Future<int> _b2SystemBackUnbindsChat(Inst a, String toxB) async {
  if (!a.isAndroid) {
    return _hveSkip(
      'system_back_unbinds_chat',
      'the REAL OS back gesture is only injectable on Android (adb '
          'keyevent); the didPop unbind is unit-covered',
    );
  }
  final pk = _pubkey(toxB);
  await openChat(a, pk);
  final convId = _c2cConvId(toxB);
  // Precondition on the CONTRACT field itself (anti-vacuous, codex High):
  // activePeerId must actually hold this peer before BACK, else a
  // never-bound chat would "pass" the unbind assert trivially.
  final peerBefore = (await a.dumpState())['activePeerId']?.toString() ?? '';
  final boundBefore = peerBefore.contains(pk);
  if (!boundBefore) {
    print(
      '[pair] system_back_unbinds_chat: activePeer never bound '
      '(activePeer="$peerBefore" want ~$convId)',
    );
    return 1;
  }
  if (!await _androidBackKey(a)) {
    print('[pair] system_back_unbinds_chat: adb back injection failed');
    return 1;
  }
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  // THE CONTRACT FIELD IS activePeerId (it gates unread counting; the route
  // observer clears it — live-proved by its didPop log on this very back).
  // UikitDataFacade.currentConversation can be REBOUND by the conversation
  // refresh listener right after the pop, so it is diagnostic only.
  final st = await a.dumpState();
  final activePeer = st['activePeerId']?.toString();
  final convAfter = ((st['currentConversation'] as Map?)?['conversationID'])
      ?.toString();
  final unbound = activePeer == null || activePeer.isEmpty;
  final uncovered = !await _mobileHomeShellCovered(a);
  await a.shot('/tmp/ui_b2_sysback_${a.name}.png');
  print(
    '[pair] system_back_unbinds_chat: boundBefore=$boundBefore '
    'activePeerAfter=$activePeer convAfter=$convAfter '
    'unbound=$unbound shellUncovered=$uncovered',
  );
  return unbound && uncovered ? 0 : 1;
}

/// group_profile_send_binds — the GROUP profile "Send message" tile must
/// leave the chat BOUND (the same onNavigateToChat -> _openChat contract the
/// friend-profile Send tile takes; the fork tile carries
/// `group_profile_send_message_tile` for this drive).
Future<int> _b2GroupProfileSendBinds(Inst a) async {
  if (!await a.markAccountTest()) {
    print('[pair] group_profile_send_binds: markAccountTest failed');
    return 1;
  }
  var gid = '';
  try {
    final created = await a.l3('l3_create_group', {
      'name': 'RUI-B2-GPSB-${DateTime.now().millisecondsSinceEpoch % 100000}',
      'type': 'private',
    });
    gid = (created['groupId'] ?? created['group_id'] ?? '').toString();
    if (created['ok'] != true || gid.isEmpty) {
      print('[pair] group_profile_send_binds: create failed $created');
      return 1;
    }
    if (!await _openGroupProfileClean(a, gid)) {
      print('[pair] group_profile_send_binds: profile did not open');
      return 1;
    }
    // The COMPACT page's tile carries `group_profile_send_message_button`
    // (tencent_cloud_chat_group_profile.dart:364); the group_profile_body
    // variant carries `group_profile_send_message_tile`. Try both.
    final tapped =
        await a.tapKeyCenter(
          'group_profile_send_message_button',
          timeoutSecs: 4,
        ) ||
        await a.tapKeyCenter('group_profile_send_message_tile', timeoutSecs: 3);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final bound = await _currentConversationId(a) == 'group_$gid';
    await a.shot('/tmp/ui_b2_gpsend_${a.name}.png');
    print(
      '[pair] group_profile_send_binds: gid=$gid tapped=$tapped bound=$bound',
    );
    return tapped && bound ? 0 : 1;
  } finally {
    try {
      await _leaveAllGroups(a);
      await returnToChatsHome(a, rounds: 3);
    } on Object catch (e) {
      print('[pair] group_profile_send_binds cleanup: $e');
    } finally {
      try {
        await a.unmarkAccountTest();
      } on Object catch (_) {}
    }
  }
}

/// global_search_group_opens_chat (#10b) — searching a group's name in
/// GLOBAL search must open and BIND its chat via a real result-row tap:
/// the SDK groups row (`search_result_group:<gid>`) when the joined-list
/// snapshot has it, else the CONVERSATION fallback row (fresh groups can
/// miss the snapshot — recorded product debt; both onTaps navigate).
Future<bool> _b2GlobalSearchGroupOpensChat(
  Inst a, {
  bool manageMarker = true,
}) async {
  // Marker ownership is CALLER-controlled (codex High): the c2c sweep
  // pre-marks both accounts, and the marker is set-membership — an inner
  // unmark would revoke the outer grant mid-sweep.
  if (manageMarker && !await a.markAccountTest()) {
    print('[pair] global_search_group_opens_chat: markAccountTest failed');
    return false;
  }
  var gid = '';
  final name = 'RUIGSRCH${DateTime.now().millisecondsSinceEpoch % 1000000}';
  try {
    final created = await a.l3('l3_create_group', {
      'name': name,
      'type': 'private',
    });
    gid = (created['groupId'] ?? '').toString();
    if (created['ok'] != true || gid.isEmpty) {
      print('[pair] global_search_group_opens_chat: create failed $created');
      return false;
    }
    await returnToChatsHome(a, rounds: 4);
    if (!await _openGlobalSearch(a)) {
      print('[pair] global_search_group_opens_chat: search did not open');
      return false;
    }
    await a.focusType('message_search_field', name);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    // A FRESH group can miss the SDK groups section (joined-list cache) and
    // surface via the CONVERSATION fallback instead (live: "CONVERSATIONS /
    // ID: tox_1") — both rows open the group chat, so accept either.
    String? rowKey;
    for (final k in [
      'search_result_group:$gid',
      'search_result_conversation:group_$gid',
    ]) {
      if (await a.waitKey(k, timeoutSecs: 4)) {
        rowKey = k;
        break;
      }
    }
    final rowShown = rowKey != null;
    final tapped = rowShown && await a.tapKeyCenter(rowKey!, timeoutSecs: 6);
    final surface = await _chatSurfaceReady(a, 'group_$gid', timeoutSecs: 10);
    // Poll the facade bind through the readiness window (codex Medium): a
    // legitimate late bind must not false-fail a single early sample.
    var bound = false;
    for (var i = 0; i < 10 && !bound; i++) {
      bound =
          ((await a.dumpState())['currentConversation']
              as Map?)?['conversationID'] ==
          'group_$gid';
      if (!bound) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    await a.shot('/tmp/ui_b2_gsearch_${a.name}.png');
    print(
      '[pair] global_search_group_opens_chat: gid=$gid rowShown=$rowShown '
      'tapped=$tapped bound=$bound surface=$surface',
    );
    return rowShown && tapped && bound && surface;
  } finally {
    try {
      if (await a.waitKey('message_search_field', timeoutSecs: 1)) {
        await _closeGlobalSearch(a);
      }
      await _leaveAllGroups(a);
      await returnToChatsHome(a, rounds: 3);
    } on Object catch (e) {
      print('[pair] global_search_group_opens_chat cleanup: $e');
    } finally {
      // Unmark independently (codex High): a cleanup throw above must not
      // leak the broad L3 marker.
      if (manageMarker) {
        try {
          await a.unmarkAccountTest();
        } on Object catch (_) {}
      }
    }
  }
}
