// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Highest-value real-App + real-control additions. These are intentionally
// split by stability domain:
// - c2c_deep/account_deep/group_conf_deep are green-path assertions suitable for
//   the optimized launch-reuse bundles.
// - native_boundary_guards documents and probes OS-bound seams honestly: in-app
//   entry/render/routing assertions can PASS, while unautomatable native dialogs,
//   network toggles, mobile-only smoke, and OS permission denial return SKIP.

const _realUiSkipExitCodeHighValue = 75;

const _c2cDeepExtraCases = {'c2c_search_result_opens_target_message'};

bool _isC2cDeepExtraCaseScenario(String scenario) =>
    _c2cDeepExtraCases.contains(scenario);

Future<int> runC2cDeepExtraCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for $scenario: A=$toxA B=$toxB');
  }
  if (!await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB)) {
    print('[pair] $scenario: could not establish friendship');
    return 1;
  }

  final ok = switch (scenario) {
    'c2c_search_result_opens_target_message' =>
      await _hveC2cSearchResultOpensTargetMessage(a, toxB),
    _ => throw ArgumentError('unsupported C2C deep extra: $scenario'),
  };
  await _hveC2cNormalize(a);
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runC2cDeepExtraSweep(
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
    print('[sweep] sweep_c2c_deep_extra: missing tox ids');
    return 1;
  }
  if (!await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB)) {
    print('[sweep] sweep_c2c_deep_extra: handshake failed');
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
      print('[sweep] sweep_c2c_deep_extra EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _hveC2cNormalize(a);
    }
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print('[sweep] sweep_c2c_deep_extra ${ok ? 'PASS' : 'FAIL'}: $name');
  }

  await hard(
    'c2c_search_result_opens_target_message',
    () => _hveC2cSearchResultOpensTargetMessage(a, toxB),
  );

  await _seedConvRow(
    a,
    toxB,
    text: 'RuiC2CDeepEnd-${DateTime.now().microsecondsSinceEpoch}',
  );
  final endFriends = await areFriends(a, toxB) && await areFriends(b, toxA);
  print(
    '[sweep] sweep_c2c_deep_extra summary: passed=$passed failed=$failed '
    'endFriends=$endFriends',
  );
  return failed == 0 && endFriends ? 0 : 1;
}

Future<void> _hveC2cNormalize(Inst inst) async {
  try {
    await _closeGlobalSearch(inst);
    await returnToChatsHome(inst, rounds: 4);
  } on Object catch (e) {
    print('[sweep] C2C deep normalize best-effort failed: $e');
  }
}

Future<bool> _hveC2cSearchResultOpensTargetMessage(
  Inst inst,
  String toxFriend,
) async {
  final c2c = _c2cConvId(toxFriend);
  // Robust setup open (row tap, then the production _openChat seam): a prior
  // case can leave the app off the chats list so the conv row isn't tappable
  // (openChat alone then throws "conversation_list_item ... failed after N").
  if (!await _ensureChatOpen(inst, _pubkey(toxFriend))) {
    print('[pair] c2c_search_result_opens_target_message: chat did not open');
    return false;
  }
  final term = 'RUIHVSEARCH${DateTime.now().microsecondsSinceEpoch}';
  if (!await sendComposerMessage(inst, term)) {
    print('[pair] c2c_search_result_opens_target_message: send failed');
    return false;
  }
  if (!await _waitC2cMessageText(
    inst,
    toxFriend,
    term,
    isSelf: true,
    timeoutSecs: 12,
  )) {
    print('[pair] c2c_search_result_opens_target_message: self text missing');
    return false;
  }

  var msgId = '';
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline) && msgId.isEmpty) {
    msgId = await _ownMessageId(inst, toxFriend, term) ?? '';
    if (msgId.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
  if (msgId.isEmpty) {
    print('[pair] c2c_search_result_opens_target_message: msgID unresolved');
    return false;
  }

  await returnToChatsHome(inst, rounds: 4);
  if (!await _openGlobalSearch(inst)) {
    print('[pair] c2c_search_result_opens_target_message: search did not open');
    return false;
  }
  await inst.focusType('message_search_field', term);
  await Future<void>.delayed(const Duration(milliseconds: 1200));

  final resultKey = await _c2ceFirstVisibleKey(inst, [
    'search_result_message_$c2c',
    'search_result_message:$c2c',
  ]);
  var windowOpened = false;
  var historyRowShown = false;
  var returnedToChat = false;
  var targetBubbleShown = false;
  final historyKey = 'search_history_message_$msgId';
  if (resultKey != null) {
    await inst.tapKeyCenter(resultKey, timeoutSecs: 6);
    windowOpened =
        await inst.waitText('Search Chat History', timeoutSecs: 8) ||
        await inst.waitKey(historyKey, timeoutSecs: 8);
    historyRowShown = await inst.waitKey(historyKey, timeoutSecs: 10);
    if (historyRowShown) {
      await inst.tapKeyCenter(historyKey, timeoutSecs: 6);
      returnedToChat = await _chatSurfaceReady(inst, c2c, timeoutSecs: 12);
      targetBubbleShown =
          returnedToChat &&
          await inst.waitKey('message_list_item:$msgId', timeoutSecs: 8);
    }
  }

  await inst.shot('/tmp/ui_hve_c2c_search_target_${inst.name}.png');
  print(
    '[pair] c2c_search_result_opens_target_message: resultKey=$resultKey '
    'windowOpened=$windowOpened historyRowShown=$historyRowShown '
    'returnedToChat=$returnedToChat targetBubbleShown=$targetBubbleShown '
    'msgId=$msgId',
  );
  return resultKey != null &&
      windowOpened &&
      historyRowShown &&
      returnedToChat &&
      targetBubbleShown;
}

const _accountDeepExtraCases = {'account_multi_account_state_isolation'};

bool _isAccountDeepExtraCaseScenario(String scenario) =>
    _accountDeepExtraCases.contains(scenario);

Future<int> runAccountDeepExtraCase(
  Inst a,
  String nickA,
  String scenario,
) async {
  await ensureHome(a, nickA);
  final primaryToxId =
      (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (primaryToxId.isEmpty) {
    throw DriveError('missing primary toxId for $scenario');
  }
  final ok = switch (scenario) {
    'account_multi_account_state_isolation' =>
      await _hveAccountMultiAccountStateIsolation(a, primaryToxId),
    _ => throw ArgumentError('unsupported account deep extra: $scenario'),
  };
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runAccountDeepExtraSweep(Inst a, String nickA) async {
  await ensureHome(a, nickA);
  final primaryToxId =
      (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (primaryToxId.isEmpty) {
    throw DriveError('missing primary toxId for sweep_account_deep_extra');
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
      print('[sweep] sweep_account_deep_extra EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _aceNormalizePrimary(a, primaryToxId);
    }
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print('[sweep] sweep_account_deep_extra ${ok ? 'PASS' : 'FAIL'}: $name');
  }

  await hard(
    'account_multi_account_state_isolation',
    () => _hveAccountMultiAccountStateIsolation(a, primaryToxId),
  );

  final endClean = await _aceNormalizePrimary(a, primaryToxId);
  if (!endClean) failed++;
  print(
    '[sweep] sweep_account_deep_extra summary: passed=$passed failed=$failed '
    'endClean=$endClean',
  );
  return failed == 0 ? 0 : 1;
}

Future<bool> _hveAccountMultiAccountStateIsolation(
  Inst inst,
  String primaryToxId,
) async {
  var secondTox = '';
  var primaryGroupId = '';
  var assertedOk = false;
  var cleanupOk = true;

  try {
    if (!await _aceNormalizePrimary(inst, primaryToxId)) {
      print(
        '[pair] account_multi_account_state_isolation: primary normalize failed',
      );
      return false;
    }

    final groupName =
        'RUI-ACCTISO-${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final created = await _createGroupViaUI(
      inst,
      groupName,
      groupType: 'private',
    );
    primaryGroupId = created.groupId;
    final primaryConvId = 'group_$primaryGroupId';
    await openGroupChat(
      inst,
      groupId: primaryGroupId,
      groupName: groupName,
      viaL3Seam: true,
    );
    final primaryListedBefore = await _waitConversationListed(
      inst,
      primaryConvId,
      timeoutSecs: 10,
    );
    final primaryActiveBefore =
        (await _currentConversationId(inst)) == primaryConvId;

    if ((await _logoutToLoginPage(inst)) != primaryToxId) {
      print(
        '[pair] account_multi_account_state_isolation: primary logout failed',
      );
      return false;
    }
    secondTox = await _p1RegisterSecondAccount(
      inst,
      'RuiIso${DateTime.now().millisecondsSinceEpoch % 100000}',
    );
    if (secondTox.isEmpty || secondTox == primaryToxId) {
      print(
        '[pair] account_multi_account_state_isolation: second account missing',
      );
      return false;
    }

    final secondState = await inst.dumpState();
    final switchedToSecond =
        secondState['sessionReady'] == true &&
        secondState['currentAccountToxId']?.toString() == secondTox;
    final secondIds = ((secondState['conversationIds'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    final secondDoesNotSeePrimaryGroup = !secondIds.contains(primaryConvId);
    final secondActiveIsolated =
        (await _currentConversationId(inst)) != primaryConvId;
    final savedIds = ((secondState['savedAccountToxIds'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    final bothCardsPersisted =
        savedIds.contains(primaryToxId) && savedIds.contains(secondTox);

    if ((await _logoutToLoginPage(inst)) != secondTox) {
      print(
        '[pair] account_multi_account_state_isolation: second logout failed',
      );
      return false;
    }
    final reloggedPrimary = await _quickLoginNoPassword(inst, primaryToxId);
    await returnToChatsHome(inst, rounds: 4);
    final primaryStateAfter = await inst.dumpState();
    final backOnPrimary =
        reloggedPrimary &&
        primaryStateAfter['sessionReady'] == true &&
        primaryStateAfter['currentAccountToxId']?.toString() == primaryToxId;
    final primaryListedAfter = await _waitConversationListed(
      inst,
      primaryConvId,
      timeoutSecs: 10,
    );

    await inst.shot('/tmp/ui_hve_account_isolation_${inst.name}.png');
    print(
      '[pair] account_multi_account_state_isolation: primaryListedBefore='
      '$primaryListedBefore primaryActiveBefore=$primaryActiveBefore '
      'switchedToSecond=$switchedToSecond secondDoesNotSeePrimaryGroup='
      '$secondDoesNotSeePrimaryGroup secondActiveIsolated='
      '$secondActiveIsolated bothCardsPersisted=$bothCardsPersisted '
      'backOnPrimary=$backOnPrimary primaryListedAfter=$primaryListedAfter',
    );
    assertedOk =
        primaryListedBefore &&
        primaryActiveBefore &&
        switchedToSecond &&
        secondDoesNotSeePrimaryGroup &&
        secondActiveIsolated &&
        bothCardsPersisted &&
        backOnPrimary &&
        primaryListedAfter;
  } finally {
    if (secondTox.isNotEmpty) {
      cleanupOk = await _p1AccountDeleteFullFlow(inst, primaryToxId, [
        secondTox,
      ]);
      if (!cleanupOk) {
        print(
          '[pair] account_multi_account_state_isolation: cleanup delete failed',
        );
      }
    }
    await _aceNormalizePrimary(inst, primaryToxId);
    if (primaryGroupId.isNotEmpty) {
      await _leaveAllGroups(inst);
      await _waitGroupCandidatesDrained(inst);
    }
  }

  return assertedOk && cleanupOk;
}

const _groupConfDeepExtraCases = {
  'group_member_role_reopen_surface',
  'group_member_remove_receiver_state',
  'conference_bidirectional_message_lifecycle',
};

bool _isGroupConfDeepExtraCaseScenario(String scenario) =>
    _groupConfDeepExtraCases.contains(scenario);

Future<int> runGroupConfDeepExtraCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final ok = switch (scenario) {
    'group_member_role_reopen_surface' =>
      await _hveGroupMemberRoleReopenSurface(a, b, nickA, nickB),
    'group_member_remove_receiver_state' =>
      await _hveGroupMemberRemoveReceiverState(a, b, nickA, nickB),
    'conference_bidirectional_message_lifecycle' =>
      await _hveConferenceBidirectionalMessageLifecycle(a, b, nickA, nickB),
    _ => throw ArgumentError('unsupported group/conf deep extra: $scenario'),
  };
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runGroupConfDeepExtraSweep(
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
    print('[sweep] sweep_group_conf_deep_extra: missing tox ids');
    return 1;
  }
  if (!await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB)) {
    print('[sweep] sweep_group_conf_deep_extra: handshake failed');
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
      print('[sweep] sweep_group_conf_deep_extra EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _gcmeCleanupGroups(a, b);
    }
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print('[sweep] sweep_group_conf_deep_extra ${ok ? 'PASS' : 'FAIL'}: $name');
  }

  await hard(
    'group_member_role_reopen_surface',
    () => _hveGroupMemberRoleReopenSurface(a, b, nickA, nickB),
  );
  await hard(
    'group_member_remove_receiver_state',
    () => _hveGroupMemberRemoveReceiverState(a, b, nickA, nickB),
  );
  await hard(
    'conference_bidirectional_message_lifecycle',
    () => _hveConferenceBidirectionalMessageLifecycle(a, b, nickA, nickB),
  );

  await _gcmeCleanupGroups(a, b);
  final endFriends = await areFriends(a, toxB) && await areFriends(b, toxA);
  print(
    '[sweep] sweep_group_conf_deep_extra summary: passed=$passed '
    'failed=$failed endFriends=$endFriends',
  );
  return failed == 0 && endFriends ? 0 : 1;
}

Future<bool> _hveGroupMemberRoleReopenSurface(
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
    namePrefix: 'RUI-HV-ROLE',
    run: (est) async {
      final toxB =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      final before = await _groupMemberCount(a, est.groupIdA);
      final row = await _gcmeOpenPeerDesktopMenu(
        a,
        est.groupIdA,
        toxB,
        label: 'hve_role_reopen_first',
      );
      if (row == null) return false;
      if (!await a.waitKey('group_member_desktop_role_item', timeoutSecs: 4)) {
        print('[pair] group_member_role_reopen_surface: role item absent');
        return false;
      }
      final roleTapped = await a.tapKeyCenter(
        'group_member_desktop_role_item',
        timeoutSecs: 6,
      );
      final firstMenuGone = await a.waitKeyGone(
        'group_member_desktop_role_item',
        timeoutSecs: 5,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1000));

      final reopenedRow = await _gcmeOpenPeerDesktopMenu(
        a,
        est.groupIdA,
        toxB,
        label: 'hve_role_reopen_second',
      );
      final roleStillVisible =
          reopenedRow != null &&
          await a.waitKey('group_member_desktop_role_item', timeoutSecs: 4);
      final kickStillVisible =
          reopenedRow != null &&
          await a.waitKey('group_member_desktop_kick_item', timeoutSecs: 4);
      final after = await _groupMemberCount(a, est.groupIdA);
      await a.shot('/tmp/ui_hve_group_role_reopen_A.png');
      await _dismissContextMenu(a);
      print(
        '[pair] group_member_role_reopen_surface: before=$before after=$after '
        'roleTapped=$roleTapped firstMenuGone=$firstMenuGone '
        'reopenedRow=$reopenedRow roleStillVisible=$roleStillVisible '
        'kickStillVisible=$kickStillVisible',
      );
      return before >= 2 &&
          after >= 2 &&
          roleTapped &&
          firstMenuGone &&
          roleStillVisible &&
          kickStillVisible;
    },
  );
}

Future<bool> _hveGroupMemberRemoveReceiverState(
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
    namePrefix: 'RUI-HV-RMRECV',
    run: (est) async {
      final toxB =
          (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
      final beforeA = await _groupMemberCount(a, est.groupIdA);
      final beforeB = await _groupMemberCount(b, est.groupIdB);
      final row = await _gcmeOpenPeerDesktopMenu(
        a,
        est.groupIdA,
        toxB,
        label: 'hve_remove_receiver',
      );
      if (row == null) return false;
      if (!await a.waitKey('group_member_desktop_kick_item', timeoutSecs: 4)) {
        print('[pair] group_member_remove_receiver_state: kick item absent');
        return false;
      }
      final tapped = await a.tapKeyCenter(
        'group_member_desktop_kick_item',
        timeoutSecs: 6,
      );

      var afterA = beforeA;
      var afterB = beforeB;
      var bRowGone = false;
      final bConvId = 'group_${est.groupIdB}';
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      while (DateTime.now().isBefore(deadline)) {
        afterA = await _groupMemberCount(a, est.groupIdA);
        afterB = await _groupMemberCount(b, est.groupIdB);
        bRowGone = !await _conversationListed(b, bConvId);
        if (afterA < beforeA && (afterB < beforeB || bRowGone)) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      await a.shot('/tmp/ui_hve_group_remove_receiver_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_hve_group_remove_receiver_B.png');
      print(
        '[pair] group_member_remove_receiver_state: beforeA=$beforeA '
        'afterA=$afterA beforeB=$beforeB afterB=$afterB bRowGone=$bRowGone '
        'tapped=$tapped row=$row',
      );
      return beforeA >= 2 &&
          beforeB >= 2 &&
          tapped &&
          afterA < beforeA &&
          (afterB < beforeB || bRowGone);
    },
  );
}

Future<bool> _hveConferenceBidirectionalMessageLifecycle(
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
    namePrefix: 'RUI-HV-CONFMSG',
    run: (est) async {
      final aCount = await _groupMemberCount(a, est.groupIdA);
      final bCount = await _groupMemberCount(b, est.groupIdB);
      await openGroupChat(b, groupId: est.groupIdB, groupName: est.groupName);
      await openGroupChat(a, groupId: est.groupIdA, groupName: est.groupName);

      final nonce = DateTime.now().microsecondsSinceEpoch;
      final mA = 'RUIHVCONF-A-$nonce';
      final aSent = await sendComposerMessage(a, mA);
      final bGot = await _waitGroupMessageAnyConversation(
        b,
        mA,
        timeoutSecs: 60,
      );

      await openGroupChat(a, groupId: est.groupIdA, groupName: est.groupName);
      await openGroupChat(b, groupId: est.groupIdB, groupName: est.groupName);
      final mB = 'RUIHVCONF-B-$nonce';
      final bSent = await sendComposerMessage(b, mB);
      final aGot = await _waitGroupMessageAnyConversation(
        a,
        mB,
        timeoutSecs: 60,
      );

      await a.shot('/tmp/ui_hve_conf_message_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_hve_conf_message_B.png');
      print(
        '[pair] conference_bidirectional_message_lifecycle: aCount=$aCount '
        'bCount=$bCount aSent=$aSent bGot=$bGot bSent=$bSent aGot=$aGot',
      );
      return aCount >= 2 && bCount >= 2 && aSent && bGot && bSent && aGot;
    },
  );
}

const _nativeBoundaryGuardCases = {
  'attachment_entry_buttons_render',
  'restore_import_entry_guard',
  'notification_tap_routes_to_c2c',
  'network_disconnect_guard',
  'call_permission_denied_guard',
  'mobile_smoke_playbook_guard',
};

const _nativeBoundaryFriendshipCases = {
  'attachment_entry_buttons_render',
  // notification_tap_routes_to_c2c is now an unconditional SKIP — it must NOT
  // require friendship setup first (a friendship failure would false-FAIL a
  // case that does no real driving anyway; codex-review catch).
};

bool _isNativeBoundaryGuardCaseScenario(String scenario) =>
    _nativeBoundaryGuardCases.contains(scenario);

Future<int> runNativeBoundaryGuardCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for $scenario: A=$toxA B=$toxB');
  }
  if (_nativeBoundaryFriendshipCases.contains(scenario) &&
      !await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB)) {
    print('[pair] $scenario: could not establish friendship');
    return 1;
  }

  final code = switch (scenario) {
    'attachment_entry_buttons_render' =>
      await _hveAttachmentEntryButtonsRender(a, b, toxA, toxB) ? 0 : 1,
    'restore_import_entry_guard' =>
      await _hveRestoreImportEntryGuard(a, toxA) ? 0 : 1,
    'notification_tap_routes_to_c2c' => await _hveSkip(
      'notification_tap_routes_to_c2c',
      // The asserted action is a real OS notification click (UNUserNotification),
      // which is not headless-automatable on the macOS runner. Driving it via
      // `l3_simulate_notification_tap` would make an l3 tool THE asserted action
      // (campaign rule forbids that). The routing half already has an executable
      // gate: `run_fixture_c_notification_tap.sh` (2proc-l3). codex-review catch.
      'requires a real OS notification click (UNUserNotification) that is not '
          'headless-automatable; routing is covered by run_fixture_c_notification_tap.sh',
    ),
    'network_disconnect_guard' => await _hveSkip(
      'network_disconnect_guard',
      'requires an OS/network-link toggle seam; stopping network would poison '
          'launch-reuse and is not safe in this runner',
    ),
    'call_permission_denied_guard' => await _hveSkip(
      'call_permission_denied_guard',
      'requires deterministic OS permission denial/reset; macOS runner cannot '
          'drive that native dialog without global side effects',
    ),
    'mobile_smoke_playbook_guard' => await _hveSkip(
      'mobile_smoke_playbook_guard',
      'mobile smoke is covered by integration_test/Patrol playbook, not the '
          'macOS desktop two-process harness',
    ),
    _ => throw ArgumentError('unsupported native boundary guard: $scenario'),
  };
  print(
    '[pair] ${code == 0
        ? 'PASS'
        : code == 75
        ? 'SKIP'
        : 'FAIL'}: $scenario',
  );
  return code;
}

Future<int> runNativeBoundaryGuardSweep(
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
    print('[sweep] sweep_native_boundary_guards: missing tox ids');
    return 1;
  }

  var passed = 0;
  var failed = 0;
  var skipped = 0;
  final results = <String, String>{};

  Future<void> step(String name, Future<int> Function() body) async {
    var code = 1;
    try {
      code = await body();
    } on PermissionBlockedError {
      rethrow;
    } on Object catch (e, st) {
      print('[sweep] sweep_native_boundary_guards EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _aceNormalizePrimary(a, toxA);
    }
    if (code == 0) {
      passed++;
      results[name] = 'PASS';
    } else if (code == _realUiSkipExitCodeHighValue) {
      skipped++;
      results[name] = 'SKIP';
    } else {
      failed++;
      results[name] = 'FAIL($code)';
    }
    print('[sweep] sweep_native_boundary_guards ${results[name]}: $name');
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
    print('[sweep] sweep_native_boundary_guards: handshake failed');
    return 1;
  }

  await step(
    'attachment_entry_buttons_render',
    () async =>
        await _hveAttachmentEntryButtonsRender(a, b, toxA, toxB) ? 0 : 1,
  );
  await step(
    'restore_import_entry_guard',
    () async => await _hveRestoreImportEntryGuard(a, toxA) ? 0 : 1,
  );
  await step(
    'notification_tap_routes_to_c2c',
    () => _hveSkip(
      'notification_tap_routes_to_c2c',
      'requires a real OS notification click (UNUserNotification) that is not '
          'headless-automatable; routing is covered by run_fixture_c_notification_tap.sh',
    ),
  );
  await step(
    'network_disconnect_guard',
    () => _hveSkip(
      'network_disconnect_guard',
      'requires an OS/network-link toggle seam; stopping network would poison '
          'launch-reuse and is not safe in this runner',
    ),
  );
  await step(
    'call_permission_denied_guard',
    () => _hveSkip(
      'call_permission_denied_guard',
      'requires deterministic OS permission denial/reset; macOS runner cannot '
          'drive that native dialog without global side effects',
    ),
  );
  await step(
    'mobile_smoke_playbook_guard',
    () => _hveSkip(
      'mobile_smoke_playbook_guard',
      'mobile smoke is covered by integration_test/Patrol playbook, not the '
          'macOS desktop two-process harness',
    ),
  );

  final endClean = await _aceNormalizePrimary(a, toxA);
  final endFriends = await areFriends(a, toxB) && await areFriends(b, toxA);
  if (!endClean || !endFriends) failed++;
  print(
    '[sweep] sweep_native_boundary_guards summary: passed=$passed '
    'failed=$failed skipped=$skipped results=$results '
    'endClean=$endClean endFriends=$endFriends',
  );
  return failed == 0 ? 0 : 1;
}

Future<int> _hveSkip(String name, String reason) async {
  print('[pair] $name: SKIP — $reason');
  return _realUiSkipExitCodeHighValue;
}

Future<bool> _hveAttachmentEntryButtonsRender(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] attachment_entry_buttons_render: chat did not open');
    return false;
  }
  final fileButton = await a.waitKey(
    'message_attachment_file_button',
    timeoutSecs: 8,
  );
  final photoButton = await a.waitKey(
    'message_attachment_photo_button',
    timeoutSecs: 4,
  );
  final videoButton = await a.waitKey(
    'message_attachment_video_button',
    timeoutSecs: 4,
  );
  final searchButton = await a.waitKey(
    'message_attachment_search_button',
    timeoutSecs: 2,
  );
  final fileSent = fileButton
      ? await _hveAttachmentPickAndSend(
          a,
          b,
          toxA,
          toxB,
          buttonKey: 'message_attachment_file_button',
          fileName: 'rui_hve_attachment.txt',
          contentB64: base64Encode(utf8.encode('RUI-HVE-ATTACHMENT-FILE')),
          mediaKind: 'file',
        )
      : false;
  final imageSent = photoButton
      ? await _hveAttachmentPickAndSend(
          a,
          b,
          toxA,
          toxB,
          buttonKey: 'message_attachment_photo_button',
          fileName: 'rui_hve_attachment.png',
          contentB64: _hveTinyPngB64,
          mediaKind: 'image',
        )
      : false;
  await a.shot('/tmp/ui_hve_attachment_entries_${a.name}.png');
  print(
    '[pair] attachment_entry_buttons_render: file=$fileButton '
    'photo=$photoButton video=$videoButton search=$searchButton '
    'fileSent=$fileSent imageSent=$imageSent',
  );
  return fileButton && photoButton && videoButton && fileSent && imageSent;
}

const _hveTinyPngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9'
    'awAAAABJRU5ErkJggg==';

Future<bool> _hveAttachmentPickAndSend(
  Inst a,
  Inst b,
  String toxA,
  String toxB, {
  required String buttonKey,
  required String fileName,
  required String contentB64,
  required String mediaKind,
}) async {
  final beforeA = {
    for (final m in await _c2cMessages(a, toxB)) _p2kMessageId(m),
  };
  final beforeB = {
    for (final m in await _c2cMessages(b, toxA)) _p2kMessageId(m),
  };
  final source = File(
    '/tmp/${DateTime.now().microsecondsSinceEpoch}_$fileName',
  );
  var marked = false;
  try {
    await source.writeAsBytes(base64Decode(contentB64));
    marked = await a.markAccountTest();
    if (!marked) {
      print('[pair] attachment picker: markAccountTest failed');
      return false;
    }
    final override = await a.l3('l3_set_attachment_pick_path', {
      'path': source.path,
    });
    if (override['ok'] != true) {
      print('[pair] attachment picker: override failed $override');
      return false;
    }
    // Re-bind the chat via the production `_openChat` path right before the tap:
    // the desktop attachment option's onTap captures the message-input's userID
    // at build time. After a row-tap open (or a prior case) the input can carry a
    // STALE/null userID, so `_sendMedia` would pick the file but skip `sendFile`
    // (the `if (userId != null)` guard) and silently send nothing. l3_open_chat
    // re-binds currentConversation + the right-pane input userID (live-probed:
    // the send then fires), keeping the asserted action the real keyed button tap.
    await a.openChatViaL3(userId: _pubkey(toxB));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!await a.tapKeyAt(buttonKey)) {
      print('[pair] attachment picker: $buttonKey not tappable');
      return false;
    }
    final sent = await _p2kWaitC2cMessageWhere(a, toxB, (m) {
      final id = _p2kMessageId(m);
      return !beforeA.contains(id) &&
          m['isSelf'] == true &&
          m['mediaKind']?.toString() == mediaKind &&
          (m['fileName']?.toString() ?? '').contains(fileName);
    }, timeoutSecs: 35);
    final sentId = _p2kMessageId(sent);
    final rowRendered =
        sentId.isNotEmpty &&
        await a.waitKey('message_list_item:$sentId', timeoutSecs: 8);
    final received = await _p2kWaitC2cMessageWhere(b, toxA, (m) {
      final id = _p2kMessageId(m);
      return !beforeB.contains(id) &&
          m['isSelf'] == false &&
          m['mediaKind']?.toString() == mediaKind &&
          (m['fileName']?.toString() ?? '').contains(fileName);
    }, timeoutSecs: 60);
    print(
      '[pair] attachment picker: key=$buttonKey mediaKind=$mediaKind '
      'sentId=$sentId rowRendered=$rowRendered received=${received != null}',
    );
    return sent != null && rowRendered && received != null;
  } finally {
    if (marked) {
      try {
        await a.l3('l3_set_attachment_pick_path', {'path': ''});
      } on Object catch (e) {
        print('[pair] attachment picker: clear override failed: $e');
      }
      await a.unmarkAccountTest();
    }
    if (await source.exists()) {
      await source.delete();
    }
  }
}

Future<bool> _hveRestoreImportEntryGuard(Inst inst, String primaryToxId) async {
  var ok = false;
  var marked = false;
  final invalidTox = File(
    '/tmp/rui_hve_restore_invalid_${DateTime.now().microsecondsSinceEpoch}.tox',
  );
  try {
    await invalidTox.writeAsString('not a tox profile');
    marked = await inst.markAccountTest();
    if (!marked) {
      print('[pair] restore_import_entry_guard: markAccountTest failed');
      return false;
    }
    final override = await inst.l3('l3_set_account_import_pick_path', {
      'path': invalidTox.path,
    });
    if (override['ok'] != true) {
      print('[pair] restore_import_entry_guard: override failed $override');
      return false;
    }
    await inst.unmarkAccountTest();
    marked = false;

    final loggedOut = await _logoutToLoginPage(inst);
    if (loggedOut != primaryToxId) {
      print('[pair] restore_import_entry_guard: logout mismatch');
      return false;
    }
    final restoreCard = await inst.waitKey(
      'login_page_restore_from_tox_file',
      timeoutSecs: 8,
    );
    final importCard = await inst.waitKey(
      'login_page_import_account_card',
      timeoutSecs: 4,
    );
    final restoreTapped =
        restoreCard && await inst.tapKeyAt('login_page_restore_from_tox_file');
    final restoreErrorShown =
        restoreTapped &&
        await inst.waitKey('login_page_error_banner', timeoutSecs: 10);
    await inst.shot('/tmp/ui_hve_restore_import_entries_${inst.name}.png');
    ok = restoreCard && importCard && restoreTapped && restoreErrorShown;
    print(
      '[pair] restore_import_entry_guard: restoreCard=$restoreCard '
      'importCard=$importCard restoreTapped=$restoreTapped '
      'restoreErrorShown=$restoreErrorShown',
    );
  } finally {
    if (marked) await inst.unmarkAccountTest();
    await _quickLoginNoPassword(inst, primaryToxId);
    try {
      final clearMarked = await inst.markAccountTest();
      if (clearMarked) {
        await inst.l3('l3_set_account_import_pick_path', {'path': ''});
        await inst.unmarkAccountTest();
      }
    } on Object catch (e) {
      print('[pair] restore_import_entry_guard: clear override failed: $e');
    }
    await returnToChatsHome(inst, rounds: 4);
    if (await invalidTox.exists()) {
      await invalidTox.delete();
    }
  }
  return ok;
}

