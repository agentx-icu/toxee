// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Focused C2C real-UI expansion. The existing `rui-conv` / `rui-chat` sweeps
// already cover message send, row menus, confirm-delete, copy/forward/delete,
// media bubbles, history scroll, unread and preview. This small campaign fills
// common safe-path gaps: contact search -> chat entry, destructive-dialog
// Cancel branches, and profile/chat round-trips.

const _c2cExtraCases = {
  'c2c_global_search_contact_opens_chat',
  'c2c_conv_delete_cancel',
  'c2c_profile_clear_history_cancel',
  'c2c_delete_friend_cancel',
  'c2c_header_profile_send_back',
};

bool _isC2cExtraCaseScenario(String scenario) =>
    _c2cExtraCases.contains(scenario);

Future<int> runC2cExtraCase(
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
    'c2c_global_search_contact_opens_chat' =>
      await _c2ceGlobalSearchContactOpensChat(a, toxB, nickB),
    'c2c_conv_delete_cancel' => await _c2ceConvDeleteCancel(a, toxB),
    'c2c_profile_clear_history_cancel' => await _c2ceProfileClearHistoryCancel(
      a,
      toxB,
    ),
    'c2c_delete_friend_cancel' => await _c2ceDeleteFriendCancel(a, toxB),
    'c2c_header_profile_send_back' => await _c2ceHeaderProfileSendBack(a, toxB),
    _ => throw ArgumentError('unsupported C2C extra: $scenario'),
  };
  await _c2ceNormalize(a);
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runC2cExtraSweep(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[sweep] sweep_c2c_extra: missing tox ids');
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
    print('[sweep] sweep_c2c_extra: handshake failed');
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
      print('[sweep] sweep_c2c_extra EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _c2ceNormalize(a);
    }
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print('[sweep] sweep_c2c_extra ${ok ? 'PASS' : 'FAIL'}: $name');
  }

  await hard(
    'c2c_global_search_contact_opens_chat',
    () => _c2ceGlobalSearchContactOpensChat(a, toxB, nickB),
  );
  await hard('c2c_conv_delete_cancel', () => _c2ceConvDeleteCancel(a, toxB));
  await hard(
    'c2c_profile_clear_history_cancel',
    () => _c2ceProfileClearHistoryCancel(a, toxB),
  );
  await hard(
    'c2c_delete_friend_cancel',
    () => _c2ceDeleteFriendCancel(a, toxB),
  );
  await hard(
    'c2c_header_profile_send_back',
    () => _c2ceHeaderProfileSendBack(a, toxB),
  );

  await _seedConvRow(
    a,
    toxB,
    text: 'RuiC2CEnd-${DateTime.now().microsecondsSinceEpoch}',
  );
  final endFriends = await areFriends(a, toxB) && await areFriends(b, toxA);
  print(
    '[sweep] sweep_c2c_extra summary: passed=$passed failed=$failed '
    'endFriends=$endFriends',
  );
  return failed == 0 && endFriends ? 0 : 1;
}

Future<void> _c2ceNormalize(Inst inst) async {
  try {
    if (await inst.waitKey(
      'delete_conversation_cancel_button',
      timeoutSecs: 1,
    )) {
      await inst.tapKeyCenter(
        'delete_conversation_cancel_button',
        timeoutSecs: 3,
      );
    }
    if (await inst.waitKey(
      'user_profile_clear_history_cancel_button',
      timeoutSecs: 1,
    )) {
      await inst.tapKeyCenter(
        'user_profile_clear_history_cancel_button',
        timeoutSecs: 3,
      );
    }
    if (await inst.waitKey(
      'user_profile_delete_friend_cancel_button',
      timeoutSecs: 1,
    )) {
      await inst.tapKeyCenter(
        'user_profile_delete_friend_cancel_button',
        timeoutSecs: 3,
      );
    }
    await _closeGlobalSearch(inst);
    await returnToChatsHome(inst, rounds: 4);
  } on Object catch (e) {
    print('[sweep] C2C extra normalize best-effort failed: $e');
  }
}

Future<bool> _c2ceGlobalSearchContactOpensChat(
  Inst inst,
  String toxFriend,
  String friendNickName,
) async {
  await returnToChatsHome(inst, rounds: 4);
  final fullKey = 'search_result_contact:${toxFriend.trim()}';
  final shortKey = 'search_result_contact:${_pubkey(toxFriend)}';
  if (!await _openGlobalSearch(inst)) {
    print('[pair] c2c_global_search_contact_opens_chat: search did not open');
    return false;
  }
  final trimmedNick = friendNickName.trim();
  final matchQuery = trimmedNick.isNotEmpty
      ? trimmedNick.substring(
          0,
          trimmedNick.length >= 3 ? 3 : trimmedNick.length,
        )
      : _pubkey(toxFriend).substring(0, 6);
  await inst.focusType('message_search_field', matchQuery);
  await Future<void>.delayed(const Duration(milliseconds: 1400));
  final rowKey = await _c2ceFirstVisibleKey(inst, [shortKey, fullKey]);
  if (rowKey == null) {
    await inst.shot('/tmp/ui_c2c_search_no_contact_${inst.name}.png');
    await _closeGlobalSearch(inst);
    print(
      '[pair] c2c_global_search_contact_opens_chat: no contact row '
      '(query="$matchQuery")',
    );
    return false;
  }
  final tapped =
      await inst.tapKeyCenter(rowKey, timeoutSecs: 6) ||
      await inst.tryTapKey(rowKey, retries: 2);
  final opened =
      tapped &&
      await _chatSurfaceReady(inst, _c2cConvId(toxFriend), timeoutSecs: 12);
  await inst.shot('/tmp/ui_c2c_search_open_chat_${inst.name}.png');
  print(
    '[pair] c2c_global_search_contact_opens_chat: rowKey=$rowKey '
    'tapped=$tapped opened=$opened',
  );
  return opened;
}

Future<bool> _c2ceConvDeleteCancel(Inst inst, String toxFriend) async {
  final convId = _c2cConvId(toxFriend);
  if (!await _seedConvRow(inst, toxFriend)) {
    print('[pair] c2c_conv_delete_cancel: could not seed row');
    return false;
  }
  final friendBefore = await areFriends(inst, toxFriend);
  if (!await _openConvRowMenuReal(inst, toxFriend)) {
    print('[pair] c2c_conv_delete_cancel: real row menu did not open');
    return false;
  }
  if (!await inst.waitKey(
    'conversation_context_menu_delete_item',
    timeoutSecs: 4,
  )) {
    await _dismissConvMenu(inst);
    print('[pair] c2c_conv_delete_cancel: delete item absent');
    return false;
  }
  if (!await inst.tapKeyCenter(
    'conversation_context_menu_delete_item',
    timeoutSecs: 6,
  )) {
    await _dismissConvMenu(inst);
    print('[pair] c2c_conv_delete_cancel: delete item not tappable');
    return false;
  }
  if (!await inst.waitKey(
    'delete_conversation_cancel_button',
    timeoutSecs: 8,
  )) {
    await inst.shot('/tmp/ui_c2c_conv_delete_cancel_nodialog_${inst.name}.png');
    print('[pair] c2c_conv_delete_cancel: cancel dialog did not open');
    return false;
  }
  final cancelTapped = await inst.tapKeyCenter(
    'delete_conversation_cancel_button',
    timeoutSecs: 6,
  );
  final dialogGone = await inst.waitKeyGone(
    'delete_conversation_confirm_button',
    timeoutSecs: 6,
  );
  final rowStillListed = await _waitConversationListed(
    inst,
    convId,
    timeoutSecs: 8,
  );
  final friendAfter = await areFriends(inst, toxFriend);
  await inst.shot('/tmp/ui_c2c_conv_delete_cancel_${inst.name}.png');
  print(
    '[pair] c2c_conv_delete_cancel: friendBefore=$friendBefore '
    'cancelTapped=$cancelTapped dialogGone=$dialogGone '
    'rowStillListed=$rowStillListed friendAfter=$friendAfter',
  );
  return friendBefore &&
      cancelTapped &&
      dialogGone &&
      rowStillListed &&
      friendAfter;
}

Future<bool> _c2ceProfileClearHistoryCancel(Inst inst, String toxFriend) async {
  final convId = _c2cConvId(toxFriend);
  if (!await _ensureChatOpen(inst, toxFriend)) {
    print('[pair] c2c_profile_clear_history_cancel: chat did not open');
    return false;
  }
  final seedText = 'RuiC2CClearCancel-${DateTime.now().microsecondsSinceEpoch}';
  if (!await sendComposerMessage(inst, seedText)) {
    print('[pair] c2c_profile_clear_history_cancel: seed send failed');
    return false;
  }
  final beforeCount =
      ((await inst.dumpState(conversationId: convId))['messageCount'] as num?)
          ?.toInt() ??
      -1;
  if (beforeCount <= 0) {
    print(
      '[pair] c2c_profile_clear_history_cancel: bad beforeCount=$beforeCount',
    );
    return false;
  }
  if (!await _ensureFriendProfileOpen(inst, toxFriend)) {
    print('[pair] c2c_profile_clear_history_cancel: profile did not open');
    return false;
  }
  if (!await inst.tryTapKey('user_profile_clear_history_button', retries: 3)) {
    print('[pair] c2c_profile_clear_history_cancel: opener not tappable');
    return false;
  }
  if (!await inst.waitKey(
    'user_profile_clear_history_cancel_button',
    timeoutSecs: 8,
  )) {
    await inst.shot('/tmp/ui_c2c_clear_cancel_nodialog_${inst.name}.png');
    print('[pair] c2c_profile_clear_history_cancel: dialog did not open');
    return false;
  }
  final cancelTapped = await inst.tapKeyCenter(
    'user_profile_clear_history_cancel_button',
    timeoutSecs: 6,
  );
  final dialogGone = await inst.waitKeyGone(
    'user_profile_clear_history_confirm_button',
    timeoutSecs: 6,
  );
  final afterCount =
      ((await inst.dumpState(conversationId: convId))['messageCount'] as num?)
          ?.toInt() ??
      -1;
  await inst.shot('/tmp/ui_c2c_clear_cancel_${inst.name}.png');
  print(
    '[pair] c2c_profile_clear_history_cancel: beforeCount=$beforeCount '
    'cancelTapped=$cancelTapped dialogGone=$dialogGone '
    'afterCount=$afterCount',
  );
  return cancelTapped && dialogGone && afterCount == beforeCount;
}

Future<bool> _c2ceDeleteFriendCancel(Inst inst, String toxFriend) async {
  if (!await _ensureFriendProfileOpen(inst, toxFriend)) {
    print('[pair] c2c_delete_friend_cancel: profile did not open');
    return false;
  }
  final friendBefore = await areFriends(inst, toxFriend);
  if (!await inst.tryTapKey('user_profile_delete_friend_button', retries: 3)) {
    print('[pair] c2c_delete_friend_cancel: delete friend opener not tappable');
    return false;
  }
  if (!await inst.waitKey(
    'user_profile_delete_friend_cancel_button',
    timeoutSecs: 8,
  )) {
    await inst.shot(
      '/tmp/ui_c2c_delete_friend_cancel_nodialog_${inst.name}.png',
    );
    print('[pair] c2c_delete_friend_cancel: dialog did not open');
    return false;
  }
  final cancelTapped = await inst.tapKeyCenter(
    'user_profile_delete_friend_cancel_button',
    timeoutSecs: 6,
  );
  final dialogGone = await inst.waitKeyGone(
    'user_profile_delete_friend_cancel_button',
    timeoutSecs: 6,
  );
  final friendAfter = await areFriends(inst, toxFriend);
  await inst.shot('/tmp/ui_c2c_delete_friend_cancel_${inst.name}.png');
  print(
    '[pair] c2c_delete_friend_cancel: friendBefore=$friendBefore '
    'cancelTapped=$cancelTapped dialogGone=$dialogGone '
    'friendAfter=$friendAfter',
  );
  return friendBefore && cancelTapped && dialogGone && friendAfter;
}

Future<bool> _c2ceHeaderProfileSendBack(Inst inst, String toxFriend) async {
  if (!await _ensureChatOpen(inst, toxFriend)) {
    print('[pair] c2c_header_profile_send_back: chat did not open');
    return false;
  }
  if (!await inst.waitKey('message_header_profile_avatar', timeoutSecs: 6)) {
    print('[pair] c2c_header_profile_send_back: header avatar absent');
    return false;
  }
  await inst.tapKey('message_header_profile_avatar');
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  final profileShown = await _onFriendProfile(inst, timeoutSecs: 8);
  if (!profileShown) {
    await inst.shot('/tmp/ui_c2c_header_profile_missing_${inst.name}.png');
    print('[pair] c2c_header_profile_send_back: profile did not show');
    return false;
  }
  final sendTapped = await inst.tapKeyCenter(
    'friend_profile_send_message_tile',
    timeoutSecs: 6,
  );
  final returned =
      sendTapped &&
      await _chatSurfaceReady(inst, _c2cConvId(toxFriend), timeoutSecs: 12);
  await inst.shot('/tmp/ui_c2c_header_send_back_${inst.name}.png');
  print(
    '[pair] c2c_header_profile_send_back: profileShown=$profileShown '
    'sendTapped=$sendTapped returned=$returned',
  );
  return returned;
}

Future<String?> _c2ceFirstVisibleKey(Inst inst, Iterable<String> keys) async {
  for (final key in keys) {
    if (await inst.waitKey(key, timeoutSecs: 2)) return key;
  }
  return null;
}
