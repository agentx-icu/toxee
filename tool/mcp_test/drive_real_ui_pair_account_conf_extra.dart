// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Account + conference extra sweep. These cases target the two areas that were
// thin in the real-app inventory while staying honest: every asserted action is
// a real settings/login/conference control, and cleanup is gated so the runner's
// no-friend/no-extra-account state contract is not wishful thinking.

const _accountConfExtraCases = {
  'settings_switch_account_cancel',
  'login_account_delete_cancel',
  'settings_delete_account_cancel',
  'conference_profile_id_surface',
  'conference_profile_send_message_tile',
  'conference_search_result_opens',
};

bool _isAccountConfExtraCaseScenario(String scenario) =>
    _accountConfExtraCases.contains(scenario);

Future<int> runAccountConfExtraCase(
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
    'settings_switch_account_cancel' => await _aceSettingsSwitchAccountCancel(
      a,
      primaryToxId,
    ),
    'login_account_delete_cancel' => await _aceLoginAccountDeleteCancel(
      a,
      primaryToxId,
    ),
    'settings_delete_account_cancel' => await _aceSettingsDeleteAccountCancel(
      a,
      primaryToxId,
    ),
    'conference_profile_id_surface' => await _aceConferenceProfileIdSurface(a),
    'conference_profile_send_message_tile' =>
      await _aceConferenceProfileSendMessageTile(a),
    'conference_search_result_opens' => await _aceConferenceSearchResultOpens(
      a,
    ),
    _ => throw ArgumentError('unsupported account/conf extra: $scenario'),
  };
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runAccountConfExtraSweep(Inst a, String nickA) async {
  await ensureHome(a, nickA);
  final primaryToxId =
      (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (primaryToxId.isEmpty) {
    throw DriveError('missing primary toxId for sweep_account_conf_extra');
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
      print('[sweep] sweep_account_conf_extra EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _aceNormalizePrimary(a, primaryToxId);
    }
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print('[sweep] sweep_account_conf_extra ${ok ? 'PASS' : 'FAIL'}: $name');
  }

  await hard(
    'settings_switch_account_cancel',
    () => _aceSettingsSwitchAccountCancel(a, primaryToxId),
  );
  await hard(
    'login_account_delete_cancel',
    () => _aceLoginAccountDeleteCancel(a, primaryToxId),
  );
  await hard(
    'settings_delete_account_cancel',
    () => _aceSettingsDeleteAccountCancel(a, primaryToxId),
  );
  await hard(
    'conference_profile_id_surface',
    () => _aceConferenceProfileIdSurface(a),
  );
  await hard(
    'conference_profile_send_message_tile',
    () => _aceConferenceProfileSendMessageTile(a),
  );
  await hard(
    'conference_search_result_opens',
    () => _aceConferenceSearchResultOpens(a),
  );

  final endClean = await _aceNormalizePrimary(a, primaryToxId);
  if (!endClean) failed++;
  print(
    '[sweep] sweep_account_conf_extra summary: passed=$passed failed=$failed '
    'endClean=$endClean',
  );
  return failed == 0 ? 0 : 1;
}

Future<bool> _aceNormalizePrimary(Inst inst, String primaryToxId) async {
  try {
    if (await inst.waitKey(
          'login_delete_account_confirm_input',
          timeoutSecs: 1,
        ) ||
        await inst.waitKey(
          'settings_delete_account_confirm_input',
          timeoutSecs: 1,
        ) ||
        await inst.waitKey(
          'settings_account_switch_confirm_button',
          timeoutSecs: 1,
        )) {
      try {
        await inst.osaEscape();
      } on DriveError {
        await _tapTextCenter(inst, 'Cancel', timeoutSecs: 2);
      }
    }
    if (await inst.waitKey(
      'login_account_management_export_option',
      timeoutSecs: 1,
    )) {
      try {
        await inst.osaEscape();
      } on DriveError {
        await inst.tapAt(300, 100);
      }
    }
    final st = await inst.dumpState();
    if (st['sessionReady'] != true) {
      await _quickLoginNoPassword(inst, primaryToxId);
    } else if (st['currentAccountToxId']?.toString() != primaryToxId) {
      final current = st['currentAccountToxId']?.toString() ?? '';
      if ((await _logoutToLoginPage(inst)).isNotEmpty && current.isNotEmpty) {
        await _p1AccountDeleteFullFlow(inst, primaryToxId, [current]);
      }
    }
    await returnToChatsHome(inst, rounds: 4);
  } on Object catch (e) {
    print('[sweep] account-conf normalize failed: $e');
  }
  final after = await inst.dumpState();
  return after['sessionReady'] == true &&
      after['currentAccountToxId']?.toString() == primaryToxId;
}

Future<bool> _aceSettingsSwitchAccountCancel(
  Inst inst,
  String primaryToxId,
) async {
  var secondTox = '';
  var cleanupOk = true;
  var assertedOk = false;
  try {
    if ((await _logoutToLoginPage(inst)) != primaryToxId) {
      print('[pair] settings_switch_account_cancel: logout did not land login');
      return assertedOk;
    }
    secondTox = await _p1RegisterSecondAccount(
      inst,
      'RuiCancel${DateTime.now().millisecondsSinceEpoch % 100000}',
    );
    if (secondTox.isEmpty || secondTox == primaryToxId) {
      print('[pair] settings_switch_account_cancel: second account missing');
      return assertedOk;
    }
    await _openSettings(inst);
    final swapKey = 'settings_account_switch_button:$primaryToxId';
    if (!await _settingsScrollTo(inst, swapKey)) {
      print('[pair] settings_switch_account_cancel: swap key not in band');
    }
    final dialogUp = await _p1OpenDialogViaKey(
      inst,
      swapKey,
      'settings_account_switch_cancel_button',
    );
    if (!dialogUp) {
      await inst.shot('/tmp/ui_ace_switch_cancel_nodialog_${inst.name}.png');
      return assertedOk;
    }
    final cancelTapped = await inst.tapKeyCenter(
      'settings_account_switch_cancel_button',
      timeoutSecs: 6,
    );
    final dialogGone = await inst.waitKeyGone(
      'settings_account_switch_confirm_button',
      timeoutSecs: 6,
    );
    final stillSecond =
        (await inst.dumpState())['currentAccountToxId']?.toString() ==
        secondTox;
    await inst.shot('/tmp/ui_ace_switch_cancel_${inst.name}.png');
    print(
      '[pair] settings_switch_account_cancel: cancelTapped=$cancelTapped '
      'dialogGone=$dialogGone stillSecond=$stillSecond',
    );
    assertedOk = cancelTapped && dialogGone && stillSecond;
  } finally {
    if (secondTox.isNotEmpty) {
      cleanupOk = await _p1AccountDeleteFullFlow(inst, primaryToxId, [
        secondTox,
      ]);
      if (!cleanupOk) {
        print('[pair] settings_switch_account_cancel: cleanup delete failed');
      }
    }
  }
  return assertedOk && cleanupOk;
}

Future<bool> _aceLoginAccountDeleteCancel(
  Inst inst,
  String primaryToxId,
) async {
  if ((await _logoutToLoginPage(inst)).isEmpty) return false;
  final cardKey = 'login_page_account_card:$primaryToxId';
  if (!await _waitForAccountCard(inst, primaryToxId)) return false;
  await inst.longPressKey(cardKey);
  final menuUp = await inst.waitKey(
    'login_account_management_delete_option',
    timeoutSecs: 6,
  );
  if (!menuUp) {
    print('[pair] login_account_delete_cancel: management menu absent');
    return false;
  }
  if (!await inst.tapKeyCenter(
    'login_account_management_delete_option',
    timeoutSecs: 6,
  )) {
    return false;
  }
  final dialogUp = await inst.waitKey(
    'login_delete_account_confirm_input',
    timeoutSecs: 10,
  );
  if (!dialogUp) {
    await inst.shot(
      '/tmp/ui_ace_login_delete_cancel_nodialog_${inst.name}.png',
    );
    return false;
  }
  final cancelTapped = await _tapTextCenter(inst, 'Cancel', timeoutSecs: 6);
  final dialogGone = await inst.waitKeyGone(
    'login_delete_account_confirm_input',
    timeoutSecs: 6,
  );
  final stillOut = (await inst.dumpState())['sessionReady'] != true;
  final cardStill = await inst.waitKey(cardKey, timeoutSecs: 6);
  await inst.shot('/tmp/ui_ace_login_delete_cancel_${inst.name}.png');
  final backOnPrimary =
      await _quickLoginNoPassword(inst, primaryToxId) &&
      (await inst.dumpState())['currentAccountToxId']?.toString() ==
          primaryToxId;
  print(
    '[pair] login_account_delete_cancel: cancelTapped=$cancelTapped '
    'dialogGone=$dialogGone '
    'stillOut=$stillOut cardStill=$cardStill backOnPrimary=$backOnPrimary',
  );
  return cancelTapped && dialogGone && stillOut && cardStill && backOnPrimary;
}

Future<bool> _aceSettingsDeleteAccountCancel(
  Inst inst,
  String primaryToxId,
) async {
  final before = await inst.dumpState();
  if (before['sessionReady'] != true) {
    if (!await _quickLoginNoPassword(inst, primaryToxId)) return false;
  } else if (before['currentAccountToxId']?.toString() != primaryToxId) {
    print('[pair] settings_delete_account_cancel: not on primary account');
    return false;
  }
  await _openSettings(inst);
  if (!await _settingsScrollTo(inst, 'settings_delete_account_button')) {
    print('[pair] settings_delete_account_cancel: delete button not in band');
  }
  final dialogUp = await _p1OpenDialogViaKey(
    inst,
    'settings_delete_account_button',
    'settings_delete_account_confirm_input',
  );
  if (!dialogUp) {
    await inst.shot(
      '/tmp/ui_ace_settings_delete_cancel_nodialog_${inst.name}.png',
    );
    return false;
  }
  final cancelTapped = await _tapTextCenter(inst, 'Cancel', timeoutSecs: 6);
  final dialogGone = await inst.waitKeyGone(
    'settings_delete_account_confirm_input',
    timeoutSecs: 6,
  );
  final st = await inst.dumpState();
  final stillPrimary =
      st['sessionReady'] == true && st['currentAccountToxId'] == primaryToxId;
  await inst.shot('/tmp/ui_ace_settings_delete_cancel_${inst.name}.png');
  print(
    '[pair] settings_delete_account_cancel: cancelTapped=$cancelTapped '
    'dialogGone=$dialogGone '
    'stillPrimary=$stillPrimary',
  );
  return cancelTapped && dialogGone && stillPrimary;
}

Future<bool> _aceConferenceProfileIdSurface(Inst inst) async {
  final name = _aceConfName('ID');
  final gid = await _confCreateDialogSurface(inst, name);
  if (gid.isEmpty) return false;
  var cleanupOk = false;
  try {
    await openGroupChat(inst, groupId: gid, groupName: name);
    await _openGroupProfile(inst);
    final hasId = await inst.waitKey('group_profile_id_text', timeoutSecs: 8);
    final hasMembers = await inst.waitKey(
      'group_profile_members_entry',
      timeoutSecs: 4,
    );
    await inst.shot('/tmp/ui_ace_conf_id_${inst.name}.png');
    cleanupOk = await _groupLeaveViaProfileConfirm(inst, gid, name);
    print(
      '[pair] conference_profile_id_surface: hasId=$hasId '
      'hasMembers=$hasMembers cleanupOk=$cleanupOk',
    );
    return hasId && hasMembers && cleanupOk;
  } finally {
    if (!cleanupOk) await _aceLeaveConferenceBestEffort(inst, gid, name);
  }
}

Future<bool> _aceConferenceProfileSendMessageTile(Inst inst) async {
  final name = _aceConfName('SEND');
  final gid = await _confCreateDialogSurface(inst, name);
  if (gid.isEmpty) return false;
  var cleanupOk = false;
  try {
    await openGroupChat(inst, groupId: gid, groupName: name);
    await _openGroupProfile(inst);
    final buttonShown = await inst.waitKey(
      'group_profile_send_message_button',
      timeoutSecs: 8,
    );
    if (!buttonShown) return false;
    if (!await inst.tapKeyCenter(
      'group_profile_send_message_button',
      timeoutSecs: 6,
    )) {
      return false;
    }
    final chatOpened = await _chatSurfaceReadyForAnyGroup(
      inst,
      timeoutSecs: 12,
      requireGroupId: gid,
    );
    final headerOk = await _waitChatHeaderTitle(inst, name, timeoutSecs: 8);
    await inst.shot('/tmp/ui_ace_conf_send_tile_${inst.name}.png');
    cleanupOk = await _groupLeaveViaProfileConfirm(inst, gid, name);
    print(
      '[pair] conference_profile_send_message_tile: buttonShown=$buttonShown '
      'chatOpened=$chatOpened headerOk=$headerOk cleanupOk=$cleanupOk',
    );
    return buttonShown && chatOpened && headerOk && cleanupOk;
  } finally {
    if (!cleanupOk) await _aceLeaveConferenceBestEffort(inst, gid, name);
  }
}

Future<bool> _aceConferenceSearchResultOpens(Inst inst) async {
  final name = _aceConfName('SEARCH');
  final gid = await _confCreateDialogSurface(inst, name);
  if (gid.isEmpty) return false;
  var cleanupOk = false;
  try {
    await returnToChatsHome(inst, rounds: 4);
    await inst.foreground();
    await inst.osaSearchShortcut();
    if (!await inst.waitKey('message_search_field', timeoutSecs: 10)) {
      await inst.shot('/tmp/ui_ace_conf_search_nofield_${inst.name}.png');
      return false;
    }
    await inst.focusType('message_search_field', name);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final groupRowKey = 'search_result_group:$gid';
    final convRowKey = 'search_result_conversation:group_$gid';
    String? rowKey;
    if (await inst.waitKey(groupRowKey, timeoutSecs: 8)) {
      rowKey = groupRowKey;
    } else if (await inst.waitKey(convRowKey, timeoutSecs: 4)) {
      rowKey = convRowKey;
    }
    if (rowKey == null) {
      await inst.shot('/tmp/ui_ace_conf_search_norow_${inst.name}.png');
      return false;
    }
    await inst.tapKey(rowKey);
    final opened = await _chatSurfaceReadyForAnyGroup(
      inst,
      timeoutSecs: 12,
      requireGroupId: gid,
    );
    final headerOk = await _waitChatHeaderTitle(inst, name, timeoutSecs: 8);
    await inst.shot('/tmp/ui_ace_conf_search_${inst.name}.png');
    cleanupOk = await _groupLeaveViaProfileConfirm(inst, gid, name);
    print(
      '[pair] conference_search_result_opens: rowKey=$rowKey opened=$opened '
      'headerOk=$headerOk cleanupOk=$cleanupOk',
    );
    return opened && headerOk && cleanupOk;
  } finally {
    if (!cleanupOk) await _aceLeaveConferenceBestEffort(inst, gid, name);
  }
}

String _aceConfName(String slug) =>
    'RUI-ACE-$slug-${DateTime.now().millisecondsSinceEpoch}';

Future<void> _aceLeaveConferenceBestEffort(
  Inst inst,
  String gid,
  String name,
) async {
  try {
    await _groupLeaveViaProfileConfirm(inst, gid, name);
  } on Object catch (e) {
    print('[pair] account-conf cleanup: leave conference failed: $e');
    try {
      await returnToChatsHome(inst, rounds: 4);
    } on Object {
      // best-effort
    }
  }
}
