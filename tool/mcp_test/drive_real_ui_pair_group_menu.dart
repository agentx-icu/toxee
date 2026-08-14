// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

/// Poll until the conversation `conversationId` has `isPinned == expected`.
Future<bool> _waitConversationPinned(
  Inst inst,
  String conversationId,
  bool expected, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final entry = await _conversationEntry(inst, conversationId);
    if (entry != null && (entry['isPinned'] == true) == expected) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Poll until the conversation `conversationId`'s unreadCount (from the top-level
/// conversation list, the same source the badge renders) satisfies [test].
Future<bool> _waitConversationUnread(
  Inst inst,
  String conversationId,
  bool Function(int unread) test, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final entry = await _conversationEntry(inst, conversationId);
    if (entry != null) {
      final unread = (entry['unreadCount'] as num?)?.toInt() ?? 0;
      if (test(unread)) return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Poll until the group conversation's history `messageCount` (from
/// `l3_dump_state {conversationId}`, the path-independent `ffi.getHistory`
/// readout) satisfies [test].
Future<bool> _waitGroupHistoryCount(
  Inst inst,
  String conversationId,
  bool Function(int count) test, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final st = await inst.dumpState(conversationId: conversationId);
    final count = (st['messageCount'] as num?)?.toInt() ?? -1;
    if (test(count)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Poll until the conversation `conversationId` is ABSENT from the sidebar list.
Future<bool> _waitConversationGone(
  Inst inst,
  String conversationId, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState();
    final ids = [
      for (final c in (s['conversations'] as List?) ?? const [])
        if (c is Map) c['conversationID']?.toString(),
    ];
    if (!ids.contains(conversationId)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Open the conversation-row context menu for `group_<gid>` via the ungated
/// `l3_open_conversation_menu` deep-link (flutter_skill cannot right-click /
/// long-press). Lands on the chats home first so the conversation list is
/// mounted.
Future<void> _openConversationMenu(Inst inst, String gid) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  final r = await inst.l3('l3_open_conversation_menu', {
    'conversationId': 'group_$gid',
  });
  if (r['ok'] != true) {
    await inst.shot('/tmp/ui_conv_menu_open_fail_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] l3_open_conversation_menu failed for group_$gid: $r',
    );
  }
}

/// Dismiss an open context menu by tapping the modal barrier (top-left corner).
Future<void> _dismissContextMenu(Inst inst) async {
  await inst.tapAt(8, 8);
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/// Dispatch a conversation-row context-menu action (`pin`/`mark_read`/`delete`)
/// DIRECTLY through the production handler (`l3_open_conversation_menu` with an
/// `action`), bypassing the PopupMenuItem tap. flutter_skill double-fires
/// InkWell-backed menu items, which turns the `pin` toggle into a net no-op —
/// the exact reason the menu-item-tap leg was unreliable. The deep-link runs the
/// same `_dispatchConversationMenuAction` the menu's onSelected runs. Lands on
/// the chats home first so the conversation list is mounted.
Future<void> _dispatchConversationAction(
  Inst inst,
  String gid,
  String action,
) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  final r = await inst.l3('l3_open_conversation_menu', {
    'conversationId': 'group_$gid',
    'action': action,
  });
  if (r['ok'] != true) {
    await inst.shot('/tmp/ui_conv_action_fail_${action}_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] l3_open_conversation_menu action=$action failed for '
      'group_$gid: $r',
    );
  }
}

/// S131 — single-instance: create a group, open its row context menu via the
/// ungated deep-link, assert the menu item keys (pin / mark-read / delete).
Future<int> runGroupConversationMenu(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final created = await _createGroupViaUI(
    inst,
    'RUI-GMENU-$nonce',
    groupType: 'private',
  );
  final gid = created.groupId;
  await _openConversationMenu(inst, gid);
  final hasPin = await inst.waitKey(
    'conversation_context_menu_pin_item',
    timeoutSecs: 8,
  );
  final hasMarkRead = await inst.waitKey(
    'conversation_context_menu_mark_read_item',
    timeoutSecs: 5,
  );
  final hasDelete = await inst.waitKey(
    'conversation_context_menu_delete_item',
    timeoutSecs: 5,
  );
  await inst.shot('/tmp/ui_group_conv_menu_${inst.name}.png');
  await _dismissContextMenu(inst);
  if (hasPin && hasMarkRead && hasDelete) {
    print(
      '[pair] PASS: real-UI group conversation context-menu surface '
      '(pin+mark_read+delete, gid=${_shortId(gid)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group conversation menu surface '
    '(pin=$hasPin markRead=$hasMarkRead delete=$hasDelete gid=${_shortId(gid)})',
  );
  return 1;
}

/// S132 — single-instance: Pin the group row → assert isPinned → Unpin → assert
/// unpinned, via the production `pinConversation` path. Drives the menu's `pin`
/// action through the deterministic deep-link (`l3_open_conversation_menu`
/// action:'pin') instead of tapping the PopupMenuItem — flutter_skill
/// double-fires the InkWell-backed item, toggling pin twice (net no-op), which
/// is why the tap leg was previously unreliable. First the surface is verified
/// (the keyed pin item renders), then the action is dispatched.
Future<int> runGroupMenuPinUnpin(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final created = await _createGroupViaUI(
    inst,
    'RUI-GPIN-$nonce',
    groupType: 'private',
  );
  final gid = created.groupId;
  final convId = 'group_$gid';

  // Surface check: the real keyed pin item must render in the row menu.
  await _openConversationMenu(inst, gid);
  final hasPinItem = await inst.waitKey(
    'conversation_context_menu_pin_item',
    timeoutSecs: 8,
  );
  await _dismissContextMenu(inst);
  if (!hasPinItem) {
    await inst.shot('/tmp/ui_group_pin_nopin_${inst.name}.png');
    throw DriveError('[${inst.name}] pin item not present for $convId');
  }

  // Pin (toggle) → assert pinned → pin again (toggle) → assert unpinned.
  await _dispatchConversationAction(inst, gid, 'pin');
  final pinned = await _waitConversationPinned(inst, convId, true);
  await _dispatchConversationAction(inst, gid, 'pin');
  final unpinned = await _waitConversationPinned(inst, convId, false);

  await inst.shot('/tmp/ui_group_pin_${inst.name}.png');
  if (pinned && unpinned) {
    print(
      '[pair] PASS: real-UI group menu pin→unpin via pinConversation '
      '(gid=${_shortId(gid)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group menu pin/unpin (pinned=$pinned unpinned=$unpinned '
    'gid=${_shortId(gid)})',
  );
  return 1;
}

/// S133 — single-instance: assert the Mark-as-read item surfaces + unread stays
/// 0. A single instance cannot seed group unread (own sends don't increment own
/// unread; inbound needs a peer), so this asserts the menu SURFACE + the
/// no-regression invariant, NOT a true unread>0→0 transition.
Future<int> runGroupMenuMarkRead(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final created = await _createGroupViaUI(
    inst,
    'RUI-GMR-$nonce',
    groupType: 'private',
  );
  final gid = created.groupId;
  final convId = 'group_$gid';

  await _openConversationMenu(inst, gid);
  final hasMarkRead = await inst.waitKey(
    'conversation_context_menu_mark_read_item',
    timeoutSecs: 8,
  );
  if (hasMarkRead) {
    await inst.tryTapKey(
      'conversation_context_menu_mark_read_item',
      retries: 2,
    );
  }
  await _dismissContextMenu(inst);

  final entry = await _conversationEntry(inst, convId);
  final unread = (entry?['unreadCount'] as num?)?.toInt() ?? 0;
  await inst.shot('/tmp/ui_group_markread_${inst.name}.png');
  if (hasMarkRead && unread == 0) {
    print(
      '[pair] PASS: real-UI group menu mark-read surface '
      '(item present; unread stays 0 single-instance, gid=${_shortId(gid)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group menu mark-read (item=$hasMarkRead unread=$unread '
    'gid=${_shortId(gid)})',
  );
  return 1;
}

/// S134 — single-instance: open the group row menu → Delete → confirm → assert
/// the group conversation is gone from the sidebar.
Future<int> runGroupMenuDeleteConfirm(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final created = await _createGroupViaUI(
    inst,
    'RUI-GDEL-$nonce',
    groupType: 'private',
  );
  final gid = created.groupId;
  final convId = 'group_$gid';

  // Surface check: the real keyed delete item renders in the row menu.
  await _openConversationMenu(inst, gid);
  final hasDeleteItem = await inst.waitKey(
    'conversation_context_menu_delete_item',
    timeoutSecs: 8,
  );
  await _dismissContextMenu(inst);
  if (!hasDeleteItem) {
    await inst.shot('/tmp/ui_group_del_noitem_${inst.name}.png');
    throw DriveError('[${inst.name}] delete item not present for $convId');
  }

  // Dispatch the delete action directly (avoids the flutter_skill double-fire on
  // the PopupMenuItem) — it raises the REAL confirm dialog, which the harness
  // confirms by tapping the guarded confirm button.
  await _dispatchConversationAction(inst, gid, 'delete');
  if (!await inst.waitKey(
    'delete_conversation_confirm_button',
    timeoutSecs: 10,
  )) {
    await inst.shot('/tmp/ui_group_del_nodialog_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] delete-conversation confirm dialog did not open',
    );
  }
  await inst.tapKey('delete_conversation_confirm_button');

  // For a group, `deleteConversation` fires onConversationDeleted (the host
  // suppresses the row until a new message arrives) AND clears history + pin, so
  // the row leaves the sidebar.
  final gone = await _waitConversationGone(inst, convId, timeoutSecs: 20);
  await inst.shot('/tmp/ui_group_del_${inst.name}.png');
  if (gone) {
    print(
      '[pair] PASS: real-UI group menu delete+confirm removes conversation '
      '(gid=${_shortId(gid)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group menu delete+confirm — $convId still present '
    '(gid=${_shortId(gid)})',
  );
  return 1;
}

/// S118 / S133 — two-process group: drive the TRUE unread>0 → 0 transition via
/// the row menu's Mark-as-read. The single-instance gate could only prove the
/// item renders (own sends never bump own unread). Here B sends into the group
/// while A is NOT viewing it (A's active conversation cleared), so A accrues real
/// group unread; then A marks read via the deterministic `mark_read` action and
/// the count must drop to 0 — through the production
/// `cleanConversationUnreadMessageCount` → markConversationRead path the docs
/// wrongly believed was a no-op.
Future<int> runGroupMarkReadUnread(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GMRUNREAD',
  );
  if (est == null) {
    print('[pair] FAIL: group mark-read could not establish a group');
    return 1;
  }
  final convId = 'group_${est.groupIdA}';
  try {
    // A must NOT be the active conversation, or the inbound message auto-marks
    // read (ffi_chat_service: _activePeerId == gid → unread stays 0). Park A on
    // the chats home and force the active conversation to none.
    await returnToChatsHome(a, rounds: 4);
    await a.l3('l3_set_active_conversation', <String, dynamic>{});

    final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final m = 'RUIGMRUNREAD-$nonce';
    await openGroupChat(b, groupId: est.groupIdB, groupName: est.groupName);
    final bSent = await sendComposerMessage(b, m);
    final aGot = await _waitGroupMessageAnyConversation(a, m, timeoutSecs: 60);
    if (!bSent || !aGot) {
      await a.shot('/tmp/ui_group_markread_seed_fail_A.png');
      print('[pair] FAIL: group mark-read seed (bSent=$bSent aGot=$aGot)');
      return 1;
    }

    final seeded = await _waitConversationUnread(a, convId, (u) => u > 0);
    if (!seeded) {
      final entry = await _conversationEntry(a, convId);
      await a.shot('/tmp/ui_group_markread_noseed_A.png');
      print(
        '[pair] FAIL: group mark-read — unread did not accrue on A (entry=$entry)',
      );
      return 1;
    }

    await _dispatchConversationAction(a, est.groupIdA, 'mark_read');
    final cleared = await _waitConversationUnread(a, convId, (u) => u == 0);
    await a.shot('/tmp/ui_group_markread_A.png');
    if (cleared) {
      print(
        '[pair] PASS: real-UI group menu mark-read drove unread>0 → 0 '
        '(gid=${_shortId(est.groupIdA)})',
      );
      return 0;
    }
    final entry = await _conversationEntry(a, convId);
    print('[pair] FAIL: group mark-read — unread did not clear (entry=$entry)');
    return 1;
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (e) {
        print(
          '[pair] WARN failed to restore B autoAcceptGroupInvites: ${e.message}',
        );
      }
    }
  }
}

/// S122 — two-process group: clear a group's history and assert the messages are
/// gone while the conversation row survives. B sends into the group (so A holds
/// real group history), then A clears via `l3_clear_group_history` (the group
/// counterpart to the C2C-only l3_clear_history). A's group history messageCount
/// must drop to 0 AND the conversation row must remain in the sidebar (the row is
/// rebuilt from knownGroups, independent of history).
Future<int> runGroupClearHistory(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GCLEAR',
  );
  if (est == null) {
    print('[pair] FAIL: group clear-history could not establish a group');
    return 1;
  }
  final convId = 'group_${est.groupIdA}';
  try {
    final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final m = 'RUIGCLEAR-$nonce';
    await openGroupChat(b, groupId: est.groupIdB, groupName: est.groupName);
    final bSent = await sendComposerMessage(b, m);
    final aGot = await _waitGroupMessageAnyConversation(a, m, timeoutSecs: 60);
    if (!bSent || !aGot) {
      print('[pair] FAIL: group clear-history seed (bSent=$bSent aGot=$aGot)');
      return 1;
    }
    final beforeCount =
        ((await a.dumpState(conversationId: convId))['messageCount'] as num?)
            ?.toInt() ??
        0;
    if (beforeCount <= 0) {
      print(
        '[pair] FAIL: group clear-history — no history to clear '
        '(before=$beforeCount)',
      );
      return 1;
    }
    final r = await a.l3('l3_clear_group_history', {'groupId': est.groupIdA});
    if (r['ok'] != true) {
      print('[pair] FAIL: l3_clear_group_history failed: $r');
      return 1;
    }
    final emptied = await _waitGroupHistoryCount(a, convId, (c) => c == 0);
    final rowPresent = (await _conversationEntry(a, convId)) != null;
    await a.shot('/tmp/ui_group_clear_A.png');
    if (emptied && rowPresent) {
      print(
        '[pair] PASS: real-UI group clear-history emptied history, row survives '
        '(before=$beforeCount gid=${_shortId(est.groupIdA)})',
      );
      return 0;
    }
    print(
      '[pair] FAIL: group clear-history '
      '(emptied=$emptied rowPresent=$rowPresent before=$beforeCount)',
    );
    return 1;
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (_) {}
    }
  }
}

/// S154 — two-process group: pin the group, seed history, clear history, and
/// assert the row stays pinned. Pin and history are independent stores
/// (`clearGroupHistory` touches the history persistence + last/unread maps, never
/// the pinned set), so a clear must never unpin. Combines S132 (pin action) +
/// S122 (clear): A pins via the row menu action, B sends (A gets history), A
/// clears, then the row must remain present AND pinned with 0 messages.
Future<int> runGroupClearPreservesPin(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GCLRPIN',
  );
  if (est == null) {
    print('[pair] FAIL: group clear-preserves-pin could not establish a group');
    return 1;
  }
  final convId = 'group_${est.groupIdA}';
  try {
    await _dispatchConversationAction(a, est.groupIdA, 'pin');
    if (!await _waitConversationPinned(a, convId, true)) {
      await a.shot('/tmp/ui_group_clrpin_nopin_A.png');
      print(
        '[pair] FAIL: group clear-preserves-pin — initial pin did not take',
      );
      return 1;
    }
    final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final m = 'RUIGCLRPIN-$nonce';
    await openGroupChat(b, groupId: est.groupIdB, groupName: est.groupName);
    final bSent = await sendComposerMessage(b, m);
    final aGot = await _waitGroupMessageAnyConversation(a, m, timeoutSecs: 60);
    if (!bSent || !aGot) {
      print('[pair] FAIL: clear-preserves-pin seed (bSent=$bSent aGot=$aGot)');
      return 1;
    }
    final r = await a.l3('l3_clear_group_history', {'groupId': est.groupIdA});
    if (r['ok'] != true) {
      print('[pair] FAIL: l3_clear_group_history failed: $r');
      return 1;
    }
    final emptied = await _waitGroupHistoryCount(a, convId, (c) => c == 0);
    final stillPinned = await _waitConversationPinned(a, convId, true);
    final rowPresent = (await _conversationEntry(a, convId)) != null;
    await a.shot('/tmp/ui_group_clrpin_A.png');
    if (emptied && stillPinned && rowPresent) {
      print(
        '[pair] PASS: real-UI group clear-history preserved row + pin '
        '(gid=${_shortId(est.groupIdA)})',
      );
      return 0;
    }
    print(
      '[pair] FAIL: clear-preserves-pin '
      '(emptied=$emptied stillPinned=$stillPinned rowPresent=$rowPresent)',
    );
    return 1;
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (_) {}
    }
  }
}
