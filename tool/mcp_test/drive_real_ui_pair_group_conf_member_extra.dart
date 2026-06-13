// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Focused group/conference member-management real-UI sweep. The asserted
// actions are the member-list row context menu and its real role/remove items;
// l3 hooks only stabilize navigation/setup/cleanup, matching the existing
// group2 exceptions.

const _groupConfMemberExtraCases = {
  'group_member_peer_menu_surface',
  'group_member_role_action_smoke',
  'group_member_remove_ui',
  'conference_member_peer_row_surface',
  'conference_member_role_remove_absent',
};

bool _isGroupConfMemberExtraCaseScenario(String scenario) =>
    _groupConfMemberExtraCases.contains(scenario);

Future<int> runGroupConfMemberExtraCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final ok = switch (scenario) {
    'group_member_peer_menu_surface' => await _gcmeGroupPeerMenuSurface(
      a,
      b,
      nickA,
      nickB,
    ),
    'group_member_role_action_smoke' => await _gcmeGroupRoleActionSmoke(
      a,
      b,
      nickA,
      nickB,
    ),
    'group_member_remove_ui' => await _gcmeGroupMemberRemoveUi(
      a,
      b,
      nickA,
      nickB,
    ),
    'conference_member_peer_row_surface' => await _gcmeConferencePeerRowSurface(
      a,
      b,
      nickA,
      nickB,
    ),
    'conference_member_role_remove_absent' =>
      await _gcmeConferenceRoleRemoveAbsent(a, b, nickA, nickB),
    _ => throw ArgumentError('unsupported group/conf member extra: $scenario'),
  };
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runGroupConfMemberExtraSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[sweep] sweep_group_conf_member_extra: missing tox ids');
    return 1;
  }
  final friended = await _establishFriendshipForSweep(
    a,
    b,
    toxA,
    toxB,
    nickA,
    nickB,
  );
  if (!friended) {
    print('[sweep] sweep_group_conf_member_extra: handshake failed');
    return 1;
  }

  var passed = 0;
  var failed = 0;

  Future<void> hard(String name, Future<bool> Function() body) async {
    var ok = false;
    try {
      ok = await body();
    } on PermissionBlockedError {
      rethrow;
    } on Object catch (e, st) {
      print('[sweep] sweep_group_conf_member_extra EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _gcmeCleanupGroups(a, b);
    }
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print(
      '[sweep] sweep_group_conf_member_extra ${ok ? 'PASS' : 'FAIL'}: $name',
    );
  }

  await hard(
    'group_member_peer_menu_surface',
    () => _gcmeGroupPeerMenuSurface(a, b, nickA, nickB),
  );
  await hard(
    'group_member_role_action_smoke',
    () => _gcmeGroupRoleActionSmoke(a, b, nickA, nickB),
  );
  await hard(
    'group_member_remove_ui',
    () => _gcmeGroupMemberRemoveUi(a, b, nickA, nickB),
  );
  await hard(
    'conference_member_peer_row_surface',
    () => _gcmeConferencePeerRowSurface(a, b, nickA, nickB),
  );
  await hard(
    'conference_member_role_remove_absent',
    () => _gcmeConferenceRoleRemoveAbsent(a, b, nickA, nickB),
  );

  await _gcmeCleanupGroups(a, b);
  final endFriends = await areFriends(a, toxB) && await areFriends(b, toxA);
  print(
    '[sweep] sweep_group_conf_member_extra summary: passed=$passed '
    'failed=$failed endFriends=$endFriends',
  );
  return failed == 0 && endFriends ? 0 : 1;
}

Future<bool> _gcmeWithEstablishedTarget(
  Inst a,
  Inst b,
  String nickA,
  String nickB, {
  required String groupType,
  required String namePrefix,
  required Future<bool> Function(_EstablishedGroup est) run,
}) async {
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: groupType,
    namePrefix: namePrefix,
  );
  if (est == null) {
    print('[pair] $namePrefix: could not establish $groupType target');
    return false;
  }
  try {
    return await run(est);
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (e) {
        print('[pair] $namePrefix: restore auto-accept failed: ${e.message}');
      }
    }
    await _gcmeCleanupGroups(a, b);
  }
}

Future<void> _gcmeCleanupGroups(Inst a, Inst b) async {
  try {
    await _leaveAllGroups(b);
    await _leaveAllGroups(a);
    await _waitGroupCandidatesDrained(b);
    await _waitGroupCandidatesDrained(a);
    await returnToChatsHome(a, rounds: 3);
    await b.foreground();
    await returnToChatsHome(b, rounds: 3);
  } on Object catch (e) {
    print('[sweep] group-conf-member cleanup best-effort failed: $e');
  }
}

Future<String?> _gcmeVisiblePeerRowKey(Inst inst, String peerTox) async {
  final byFriend = await _memberRowKeyFor(inst, peerTox);
  if (byFriend != null && await inst.waitKey(byFriend, timeoutSecs: 2)) {
    return byFriend;
  }

  final selfTox =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  final selfPk = _pubkey(selfTox);
  final r = await inst.skill('interactiveStructured', const {});
  final data = r['data'];
  final elements = data is Map ? data['elements'] : null;
  if (elements is! List) return null;
  for (final e in elements) {
    if (e is! Map) continue;
    final key = e['key']?.toString() ?? '';
    if (!key.startsWith('group_member_list_item:')) continue;
    final suffix = key.substring('group_member_list_item:'.length);
    if (_pubkey(suffix) == selfPk || suffix == selfTox) continue;
    return key;
  }
  return null;
}

Future<String?> _gcmeOpenPeerDesktopMenu(
  Inst inst,
  String groupId,
  String peerTox, {
  required String label,
}) async {
  if (!await _openGroupMemberListPage(inst, groupId)) {
    print('[pair] $label: member-list page did not open');
    return null;
  }
  final rowKey = await _gcmeVisiblePeerRowKey(inst, peerTox);
  if (rowKey == null) {
    await inst.shot('/tmp/ui_${label}_norow_${inst.name}.png');
    print('[pair] $label: peer member row not rendered');
    return null;
  }
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      await inst.secondaryTapKey(rowKey);
    } on DriveError catch (e) {
      print('[pair] $label: secondaryTap warn: ${e.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final menuUp =
        await inst.waitKey('group_member_desktop_info_item', timeoutSecs: 2) ||
        await inst.waitKey('group_member_desktop_copy_id_item', timeoutSecs: 1);
    if (menuUp) return rowKey;
  }
  await inst.shot('/tmp/ui_${label}_nomenu_${inst.name}.png');
  print('[pair] $label: desktop member menu did not open');
  return null;
}

Future<bool> _gcmeGroupPeerMenuSurface(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  return _gcmeWithEstablishedTarget(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GCME-MENU',
    run: (est) async {
      final toxB =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      final row = await _gcmeOpenPeerDesktopMenu(
        a,
        est.groupIdA,
        toxB,
        label: 'gcme_group_menu',
      );
      if (row == null) return false;
      final hasInfo = await a.waitKey(
        'group_member_desktop_info_item',
        timeoutSecs: 3,
      );
      final hasCopy = await a.waitKey(
        'group_member_desktop_copy_id_item',
        timeoutSecs: 3,
      );
      final hasRole = await a.waitKey(
        'group_member_desktop_role_item',
        timeoutSecs: 3,
      );
      final hasKick = await a.waitKey(
        'group_member_desktop_kick_item',
        timeoutSecs: 3,
      );
      await a.shot('/tmp/ui_gcme_group_menu_A.png');
      await _dismissContextMenu(a);
      print(
        '[pair] group_member_peer_menu_surface: row=$row info=$hasInfo '
        'copy=$hasCopy role=$hasRole kick=$hasKick',
      );
      return hasInfo && hasCopy && hasRole && hasKick;
    },
  );
}

Future<bool> _gcmeGroupRoleActionSmoke(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  return _gcmeWithEstablishedTarget(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GCME-ROLE',
    run: (est) async {
      final toxB =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      final before = await _groupMemberCount(a, est.groupIdA);
      final row = await _gcmeOpenPeerDesktopMenu(
        a,
        est.groupIdA,
        toxB,
        label: 'gcme_group_role',
      );
      if (row == null) return false;
      if (!await a.waitKey('group_member_desktop_role_item', timeoutSecs: 4)) {
        print('[pair] group_member_role_action_smoke: role item absent');
        return false;
      }
      final tapped = await a.tapKeyCenter(
        'group_member_desktop_role_item',
        timeoutSecs: 6,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final menuGone = await a.waitKeyGone(
        'group_member_desktop_role_item',
        timeoutSecs: 4,
      );
      final after = await _groupMemberCount(a, est.groupIdA);
      final alive = (await a.dumpState())['sessionReady'] == true;
      await a.shot('/tmp/ui_gcme_group_role_A.png');
      print(
        '[pair] group_member_role_action_smoke: before=$before after=$after '
        'tapped=$tapped menuGone=$menuGone alive=$alive',
      );
      return before >= 2 && after >= 2 && tapped && menuGone && alive;
    },
  );
}

Future<bool> _gcmeGroupMemberRemoveUi(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  return _gcmeWithEstablishedTarget(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GCME-RM',
    run: (est) async {
      final toxB =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      final before = await _groupMemberCount(a, est.groupIdA);
      final row = await _gcmeOpenPeerDesktopMenu(
        a,
        est.groupIdA,
        toxB,
        label: 'gcme_group_remove',
      );
      if (row == null) return false;
      if (!await a.waitKey('group_member_desktop_kick_item', timeoutSecs: 4)) {
        print('[pair] group_member_remove_ui: kick item absent');
        return false;
      }
      final tapped = await a.tapKeyCenter(
        'group_member_desktop_kick_item',
        timeoutSecs: 6,
      );
      var after = before;
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        after = await _groupMemberCount(a, est.groupIdA);
        if (after < before) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      await a.shot('/tmp/ui_gcme_group_remove_A.png');
      print(
        '[pair] group_member_remove_ui: before=$before after=$after '
        'tapped=$tapped row=$row',
      );
      return before >= 2 && tapped && after < before;
    },
  );
}

Future<bool> _gcmeConferencePeerRowSurface(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  return _gcmeWithEstablishedTarget(
    a,
    b,
    nickA,
    nickB,
    groupType: 'conference',
    namePrefix: 'RUI-GCME-CONFROW',
    run: (est) async {
      final toxB =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      final count = await _groupMemberCount(a, est.groupIdA);
      if (!await _openGroupMemberListPage(a, est.groupIdA)) {
        print('[pair] conference_member_peer_row_surface: list did not open');
        return false;
      }
      final row = await _gcmeVisiblePeerRowKey(a, toxB);
      final hasRow = row != null && await a.waitKey(row, timeoutSecs: 4);
      await a.shot('/tmp/ui_gcme_conf_row_A.png');
      print(
        '[pair] conference_member_peer_row_surface: count=$count '
        'row=$row hasRow=$hasRow',
      );
      return count >= 2 && hasRow;
    },
  );
}

Future<bool> _gcmeConferenceRoleRemoveAbsent(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  return _gcmeWithEstablishedTarget(
    a,
    b,
    nickA,
    nickB,
    groupType: 'conference',
    namePrefix: 'RUI-GCME-CONFNEG',
    run: (est) async {
      final toxB =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      final row = await _gcmeOpenPeerDesktopMenu(
        a,
        est.groupIdA,
        toxB,
        label: 'gcme_conf_negative',
      );
      if (row == null) return false;
      final hasInfo = await a.waitKey(
        'group_member_desktop_info_item',
        timeoutSecs: 3,
      );
      final hasCopy = await a.waitKey(
        'group_member_desktop_copy_id_item',
        timeoutSecs: 3,
      );
      final roleAbsent = !await a.waitKey(
        'group_member_desktop_role_item',
        timeoutSecs: 2,
      );
      final kickAbsent = !await a.waitKey(
        'group_member_desktop_kick_item',
        timeoutSecs: 2,
      );
      await a.shot('/tmp/ui_gcme_conf_negative_A.png');
      await _dismissContextMenu(a);
      print(
        '[pair] conference_member_role_remove_absent: row=$row '
        'info=$hasInfo copy=$hasCopy roleAbsent=$roleAbsent '
        'kickAbsent=$kickAbsent',
      );
      return hasInfo && hasCopy && roleAbsent && kickAbsent;
    },
  );
}
