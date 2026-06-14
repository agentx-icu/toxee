// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 5 of the real-UI sweep campaign — "Conversation list C2C" (10 cases,
// TWO-PROCESS). See tool/mcp_test/REAL_UI_SWEEP_CAMPAIGN.md.
//
// `sweep_conv` drives BOTH instances. ONE handshake at the top establishes the
// A<->B friendship that all cases reuse; B's REAL composer sends seed real
// unread / preview / history state on A — the entire point of running this 2p
// (a single instance can't accrue C2C unread, since own sends never bump own
// unread and inbound needs a peer). The destructive cases (delete-row 48) run
// near the end and RE-SEED a row afterwards so the launch ends tidy.
//
// State contract (registered in fixture_c_unified_runner.dart):
//   required = no-friend  (fresh pair launch; the sweep does its OWN handshake,
//                          reusing Batch-4's `_establishFriendshipForSweep`)
//   result   = friends    (the C2C delete removes only the conversation ROW, not
//                          the friend — confirmed by the S20 hermetic gate:
//                          deleteConversation → clearC2CHistory + unpin, NOT
//                          deleteFriend; case 48 re-seeds a row, the friendship
//                          stays intact, so the launch ends FRIENDS, matching the
//                          friendship-leaving Batch-4 cases)
//
// MENU TRIGGER (investigated for the Batch log — fully REAL, no l3 deep-link for
// the open): the C2C conversation row's context menu opens through the SAME path
// the group rows use. The fork's `TencentCloudChatConversationItem` wraps the row
// in `TencentCloudChatGesture` (tencent_cloud_chat_conversation_item.dart:297)
// whose InkWell carries `onSecondaryTapDown` → `_handleSecondaryTap` (desktop
// right-click) and a `RawGestureDetector` long-press → `_handleLongPress`
// (mobile). Both call toxee's `onSecondaryTapConversationItem` /
// `onLongPressConversationItem` UI event handlers (home_page.dart:349/358), which
// run `_showConversationContextMenu(conv, position)` → `showMenu` with the keyed
// `buildConversationContextMenuItems`. So `Inst.secondaryTapKey` (Batch-0
// `ui_secondary_tap`: a real PointerDown+Up with `kSecondaryMouseButton`) on the
// row key `conversation_list_item:c2c_<pubkey>` opens the REAL production menu —
// no gated tool, works on fresh non-test accounts. The menu items are then tapped
// single-fire (`tapKeyCenter`) by their keys
// (`conversation_context_menu_{pin,unpin,mark_read,delete}_item`).
//
// PIN exception (why the toggle uses the deterministic action): tapping the
// InkWell-backed `PopupMenuItem` for the pin TOGGLE double-fires under
// flutter_skill (synthetic pointer + direct onTap → two toggles = net no-op —
// the flutter_skill_double_tap_blank hazard). `tapKeyCenter` is a single real
// `tapAt`, BUT a `PopupMenuItem`'s `onTap` pops the menu route, so a coordinate
// tap that lands a frame late can miss the dismissing item. So the pin case OPENS
// the real menu via secondaryTapKey to PROVE the surface (the pin item renders),
// then dispatches the toggle through `l3_open_conversation_menu` action:'pin'
// (the SAME `_dispatchConversationMenuAction` the menu's onSelected runs — an
// ungated harness hook, NOT a bypass of the asserted handler) for a deterministic
// reorder assertion. mark_read uses the same deterministic action for the true
// unread>0→0 transition; delete OPENS the real menu and taps the real Delete item
// + the real keyed confirm dialog. This mirrors `drive_real_ui_pair_group_menu`.
//
// PRESENCE (case 53) — SKIP, verified not assumed: the C2C row's online dot key
// (`conversation_item_online_dot:<convId>`) is ALWAYS in the tree; only its fill
// COLOR flips (status color when online, transparent when offline —
// conversation_item_online_dot_key_test.dart). The friend's `online` flag in
// l3_dump_state comes straight from the native Tox friend-connection-status
// callback (l3_debug_tools.dart:4700 `'online': friend.online`); there is NO
// ungated l3 seam to set it. The ONLY mechanism that flips B's online state is
// `stop_toxee_instance.sh B` + relaunch (run_fixture_c_presence.sh PHASE 2/3),
// which the launch-reuse rule FORBIDS. So the FLIP is un-seedable on a reused
// launch → case 53 is SKIP(presence-flip requires stopping B's process — forbidden
// by launch-reuse; no ungated online-flip seam). drive_fixture_c_presence.dart is
// purely OBSERVATIONAL (polls A's friends[].online), confirming there is no setter.

// ===========================================================================
// shared conv-list helpers
// ===========================================================================

/// The C2C conversation-row / conversation-list-item key for a friend.
String _c2cConvId(String tox) => 'c2c_${_pubkey(tox)}';
String _convRowKey(String tox) => 'conversation_list_item:${_c2cConvId(tox)}';

/// Ensure a C2C conversation ROW exists in A's sidebar for [tox] by sending one
/// real composer message (the row is created from conversation history). Returns
/// whether the row is listed afterwards. Lands back on the chats home.
Future<bool> _seedConvRow(Inst inst, String tox, {String? text}) async {
  final convId = _c2cConvId(tox);
  if (await _conversationListed(inst, convId)) {
    await returnToChatsHome(inst, rounds: 4);
    return true;
  }
  await openChat(inst, tox);
  final msg = text ?? 'RuiB5Seed-${DateTime.now().microsecondsSinceEpoch}';
  await sendComposerMessage(inst, msg);
  await returnToChatsHome(inst, rounds: 4);
  return _waitConversationListed(inst, convId, timeoutSecs: 12);
}

/// Open the REAL C2C conversation-row context menu for [tox] via a genuine
/// secondary-tap (right-click) on the row — the production
/// `onSecondaryTapConversationItem` path (no gated tool). Lands on the chats
/// home first so the conversation list is mounted. Returns whether the menu's
/// keyed items appeared.
Future<bool> _openConvRowMenuReal(Inst inst, String tox) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  // Pop a leaked contact profile that can cover the conversation list.
  await _dismissFriendProfileToUnderlying(inst);
  final rowKey = _convRowKey(tox);
  if (!await inst.waitKey(rowKey, timeoutSecs: 8)) {
    print('[pair] _openConvRowMenuReal: row $rowKey not present');
    return false;
  }
  final rowCenter = await inst.keyCenter(rowKey);
  for (var attempt = 0; attempt < 4; attempt++) {
    await inst.foreground();
    try {
      // Alternate the keyed secondary-tap (which can resolve a stale OFFSTAGE
      // copy and right-click empty space) with a coordinate secondary-tap at the
      // resolved row center — a full-width conv row is tappable anywhere on it.
      if (attempt.isOdd && rowCenter != null) {
        await inst.secondaryTapAt(rowCenter.x, rowCenter.y);
      } else {
        await inst.secondaryTapKey(rowKey);
      }
    } on DriveError catch (e) {
      print('[pair] _openConvRowMenuReal: secondaryTap warn: ${e.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    // Either the Pin or Unpin item renders depending on current pin state.
    // Detect via the element-tree resolver (waitKeyCenter → resolveKeyCenter):
    // the context menu can render in an Overlay.insert entry that flutter_skill's
    // whole-tree waitKey does not traverse.
    if (await inst.waitKeyCenter('conversation_context_menu_pin_item',
            timeoutSecs: 3) ||
        await inst.waitKeyCenter('conversation_context_menu_unpin_item',
            timeoutSecs: 2)) {
      return true;
    }
  }
  return false;
}

/// Dispatch a conversation-row menu action (`pin`/`mark_read`/`delete`) for a
/// C2C conversation DIRECTLY through the production handler via the ungated
/// `l3_open_conversation_menu` action deep-link (the SAME
/// `_dispatchConversationMenuAction` the real menu's onSelected runs). Used only
/// where the flutter_skill PopupMenuItem double-fire defeats the action (the pin
/// TOGGLE) or where a deterministic transition is asserted (mark_read). Lands on
/// the chats home first. C2C mirror of `_dispatchConversationAction`.
Future<void> _dispatchC2cConvAction(Inst inst, String tox, String action) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  final r = await inst.l3('l3_open_conversation_menu', {
    'conversationId': _c2cConvId(tox),
    'action': action,
  });
  if (r['ok'] != true) {
    await inst.shot('/tmp/ui_conv_c2c_action_${action}_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] l3_open_conversation_menu action=$action failed for '
      '${_c2cConvId(tox)}: $r',
    );
  }
}

/// Dismiss an open context menu / popup by tapping the modal barrier corner.
Future<void> _dismissConvMenu(Inst inst) async {
  await inst.tapAt(8, 8);
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/// The ORDERED list of C2C conversationIDs in A's sidebar (top-to-bottom is the
/// dump order — pinned conversations sort first in the production list). Used by
/// case 46's reorder assertion.
Future<List<String>> _c2cConvOrder(Inst inst) async {
  final s = await inst.dumpState();
  final ids = <String>[];
  for (final c in (s['conversations'] as List?) ?? const []) {
    if (c is! Map) continue;
    final id = c['conversationID']?.toString() ?? '';
    if (id.startsWith('c2c_')) ids.add(id);
  }
  return ids;
}

// ===========================================================================
// case 45 — conv_menu_surface_c2c (S117)
// ===========================================================================
/// Right-click the C2C row → the REAL production menu renders pin + mark-read +
/// delete items (keyed). Drives the genuine secondary-tap (no gated open).
Future<bool> _convMenuSurfaceC2c(Inst inst, String tox) async {
  if (!await _seedConvRow(inst, tox)) {
    print('[pair] conv_menu_surface_c2c: could not seed the C2C row');
    return false;
  }
  if (!await _openConvRowMenuReal(inst, tox)) {
    print('[pair] conv_menu_surface_c2c: real row menu did not open');
    return false;
  }
  // Pin OR Unpin (depending on current pin state) + mark-read + delete.
  final hasPin = await inst.waitKeyCenter('conversation_context_menu_pin_item',
          timeoutSecs: 4) ||
      await inst.waitKeyCenter('conversation_context_menu_unpin_item',
          timeoutSecs: 2);
  final hasMarkRead = await inst.waitKey(
      'conversation_context_menu_mark_read_item',
      timeoutSecs: 4);
  final hasDelete = await inst.waitKey(
      'conversation_context_menu_delete_item',
      timeoutSecs: 4);
  await inst.shot('/tmp/ui_conv_menu_surface_${inst.name}.png');
  await _dismissConvMenu(inst);
  print(
    '[pair] conv_menu_surface_c2c: pin/unpin=$hasPin markRead=$hasMarkRead '
    'delete=$hasDelete',
  );
  return hasPin && hasMarkRead && hasDelete;
}

// ===========================================================================
// case 46 — conv_pin_unpin_reorders (S116)
// ===========================================================================
/// Pin the C2C row → it sorts to the TOP of the conversation list (pinned-first)
/// AND `isPinned` flips true; unpin → `isPinned` flips false (the row order
/// reverts). The surface is first PROVEN via the real right-click menu (the
/// keyed pin item renders), then the TOGGLE is dispatched through the
/// deterministic `pin` action (flutter_skill double-fires the PopupMenuItem,
/// toggling pin twice = net no-op). Reorder is asserted from the dump order (the
/// same source the list renders); a single-conversation list can't reorder, so
/// the reorder check is BEST-EFFORT-logged when there is only one C2C row, while
/// the `isPinned` flip + pinned-first invariant are the HARD signal.
Future<bool> _convPinUnpinReorders(Inst inst, String tox) async {
  final convId = _c2cConvId(tox);
  if (!await _seedConvRow(inst, tox)) {
    print('[pair] conv_pin_unpin_reorders: could not seed the C2C row');
    return false;
  }
  // Surface check via the REAL menu (pin item renders).
  if (!await _openConvRowMenuReal(inst, tox)) {
    print('[pair] conv_pin_unpin_reorders: real row menu did not open');
    return false;
  }
  final hasPinItem = await inst.waitKey(
          'conversation_context_menu_pin_item', timeoutSecs: 4) ||
      await inst.waitKeyCenter('conversation_context_menu_unpin_item',
          timeoutSecs: 2);
  await _dismissConvMenu(inst);
  if (!hasPinItem) {
    print('[pair] conv_pin_unpin_reorders: pin item not present');
    return false;
  }
  // Start from a known-unpinned state.
  if (await _isConvPinned(inst, convId)) {
    await _dispatchC2cConvAction(inst, tox, 'pin');
    await _waitConversationPinned(inst, convId, false);
  }
  // Pin → assert pinned + pinned-first (top of the C2C order).
  await _dispatchC2cConvAction(inst, tox, 'pin');
  final pinned = await _waitConversationPinned(inst, convId, true);
  final orderPinned = await _c2cConvOrder(inst);
  final pinnedFirst = orderPinned.isNotEmpty && orderPinned.first == convId;
  // Unpin → assert unpinned (restore).
  await _dispatchC2cConvAction(inst, tox, 'pin');
  final unpinned = await _waitConversationPinned(inst, convId, false);
  await inst.shot('/tmp/ui_conv_pin_${inst.name}.png');
  final multiRow = orderPinned.length > 1;
  print(
    '[pair] conv_pin_unpin_reorders: pinned=$pinned pinnedFirst=$pinnedFirst '
    '(c2cRows=${orderPinned.length}${multiRow ? '' : ' — single-row: reorder '
        'best-effort'}) unpinned=$unpinned',
  );
  // HARD: pin flips on, pinned conversation is first, unpin flips off. When the
  // list has only one C2C row, "first" is trivially satisfied (still a valid
  // pinned-first invariant — there is nothing to sort below it).
  return pinned && pinnedFirst && unpinned;
}

/// Read a conversation's pinned state from the dump conversation list entry.
Future<bool> _isConvPinned(Inst inst, String convId) async {
  final entry = await _conversationEntry(inst, convId);
  return entry != null && entry['isPinned'] == true;
}

// ===========================================================================
// case 47 — conv_mark_read_two_proc (S118/S19)
// ===========================================================================
/// TRUE unread>0 → 0 transition for a C2C row. A parks off the conversation
/// (active conversation cleared) so B's inbound messages accrue real unread on
/// A; A then marks read via the row menu's Mark-as-read and the badge clears.
/// Seeding is REAL (B's composer sends); the asserted action runs the production
/// `cleanConversationUnreadMessageCount` path (dispatched deterministically to
/// dodge the PopupMenuItem double-fire — the same handler the menu's onSelected
/// runs). The menu SURFACE (mark-read item renders) is proven via the real
/// right-click first.
Future<bool> _convMarkReadTwoProc(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  final convId = _c2cConvId(toxB);
  // A must NOT be viewing the conversation, or the inbound auto-marks read.
  await returnToChatsHome(a, rounds: 4);
  try {
    await a.clearActiveConversation();
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
    // Fresh non-test account: parking on the chats home (active conv != the
    // C2C) is enough — the inbound only auto-marks when that chat is OPEN.
  }
  // B sends real messages while A is parked off the conversation. RETRY the
  // B-send: the FIRST cross-process C2C delivery after the sweep setup can lag
  // (the A<->B messaging path isn't warm yet — the IDENTICAL
  // conv_unread_badge_bump / conv_preview cases PASS later once it is, so this
  // is delivery-timing, not a bug). Re-open B's chat and re-send until A's
  // unread accrues.
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  var bSent = 0;
  var seeded = false;
  for (var attempt = 0; attempt < 3 && !seeded; attempt++) {
    await openChat(b, toxA);
    for (var i = 0; i < 3; i++) {
      if (await sendComposerMessage(b, 'RUIB5UNREAD-$attempt$i-$nonce')) bSent++;
    }
    seeded = await _waitConversationUnread(a, convId, (u) => u >= 1,
        timeoutSecs: 22);
  }
  if (bSent == 0) {
    print('[pair] conv_mark_read_two_proc: B failed to send any seed message');
    return false;
  }
  if (!seeded) {
    final entry = await _conversationEntry(a, convId);
    await a.shot('/tmp/ui_conv_markread_noseed_A.png');
    print('[pair] conv_mark_read_two_proc: unread did not accrue (entry=$entry '
        'bSent=$bSent)');
    return false;
  }
  // Surface check via the REAL menu (mark-read item renders).
  final menuShown = await _openConvRowMenuReal(a, toxB);
  final hasMarkRead = menuShown &&
      await a.waitKeyCenter('conversation_context_menu_mark_read_item',
          timeoutSecs: 4);
  await _dismissConvMenu(a);
  // Dispatch the mark-read action through the production handler.
  await _dispatchC2cConvAction(a, toxB, 'mark_read');
  final cleared =
      await _waitConversationUnread(a, convId, (u) => u == 0, timeoutSecs: 20);
  await a.shot('/tmp/ui_conv_markread_A.png');
  print(
    '[pair] conv_mark_read_two_proc: bSent=$bSent seeded=$seeded '
    'markReadItem=$hasMarkRead cleared=$cleared',
  );
  return hasMarkRead && cleared;
}

// ===========================================================================
// case 49 — conv_clear_history_c2c (S111)
// ===========================================================================
/// Seed real C2C history (3 composer sends), open the REAL row menu, and clear
/// the history. The conversation-row menu has NO "clear history" action (its
/// items are pin/mark-read/delete — the C2C clear-history surface lives on the
/// FRIEND PROFILE, gated in Batch-4 case 41). The CONVERSATION-LIST clear path
/// for C2C is the ungated `l3_clear_history` harness hook (the same one the L3
/// runner uses) — there is no separate conv-row clear button to drive. So this
/// case PROVES the row menu surface via the real right-click (so it's a genuine
/// conv-list case, not a profile case) then clears via `l3_clear_history` and
/// asserts history empty + the row SURVIVES (clear never deletes the row).
Future<bool> _convClearHistoryC2c(Inst inst, String tox) async {
  final convId = _c2cConvId(tox);
  // 1) Seed real history.
  await openChat(inst, tox);
  var seeded = 0;
  for (var i = 0; i < 3; i++) {
    final text = 'RuiB5Clear-$i-${DateTime.now().microsecondsSinceEpoch}';
    if (await sendComposerMessage(inst, text)) seeded++;
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
  final beforeCount =
      ((await inst.dumpState(conversationId: convId))['messageCount'] as num?)
              ?.toInt() ??
          0;
  if (seeded == 0 || beforeCount == 0) {
    print('[pair] conv_clear_history_c2c: failed to seed history '
        '(seeded=$seeded beforeCount=$beforeCount)');
    return false;
  }
  // 2) Prove the real conv-row menu surface (so this is a conv-list case).
  await returnToChatsHome(inst, rounds: 4);
  final menuShown = await _openConvRowMenuReal(inst, tox);
  await _dismissConvMenu(inst);
  // 3) Clear via the ungated conversation-list clear hook (C2C only).
  final r = await inst.l3('l3_clear_history', {'userId': tox});
  if (r['ok'] != true) {
    print('[pair] conv_clear_history_c2c: l3_clear_history failed: $r');
    return false;
  }
  // 4) Assert history empty + the row survives.
  final emptied =
      await _waitConvMessageCount(inst, convId, 0, timeoutSecs: 15);
  final rowPresent = await _conversationListed(inst, convId);
  await inst.shot('/tmp/ui_conv_clear_${inst.name}.png');
  print(
    '[pair] conv_clear_history_c2c: menuShown=$menuShown beforeCount=$beforeCount '
    'emptied=$emptied rowPresent=$rowPresent',
  );
  return menuShown && emptied && rowPresent;
}

// ===========================================================================
// case 50 — conv_clear_preserves_pin_c2c (C2C mirror of the group gate)
// ===========================================================================
/// Pin the C2C row, seed real history, clear the history → the row must stay
/// PINNED (pin and history are independent stores: clearC2CHistory touches the
/// history persistence + last/unread maps, never the pinned set). C2C mirror of
/// `runGroupClearPreservesPin`.
Future<bool> _convClearPreservesPinC2c(Inst inst, String tox) async {
  final convId = _c2cConvId(tox);
  if (!await _seedConvRow(inst, tox)) {
    print('[pair] conv_clear_preserves_pin_c2c: could not seed the C2C row');
    return false;
  }
  // Pin (deterministic action — toggle).
  if (!await _isConvPinned(inst, convId)) {
    await _dispatchC2cConvAction(inst, tox, 'pin');
  }
  if (!await _waitConversationPinned(inst, convId, true)) {
    await inst.shot('/tmp/ui_conv_clrpin_nopin_${inst.name}.png');
    print('[pair] conv_clear_preserves_pin_c2c: initial pin did not take');
    return false;
  }
  // Seed real history. RETRY the open+send: right after the pin the chat
  // surface / composer can briefly not be ready, so a single pass no-ops the
  // send (seeded=0 beforeCount=0). Re-open + re-send until A's local history
  // (own-sent messages persist immediately) has a message.
  var seeded = 0;
  var beforeCount = 0;
  for (var attempt = 0; attempt < 3 && beforeCount == 0; attempt++) {
    await openChat(inst, tox);
    for (var i = 0; i < 3; i++) {
      final text =
          'RuiB5ClrPin-$attempt$i-${DateTime.now().microsecondsSinceEpoch}';
      if (await sendComposerMessage(inst, text)) seeded++;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    beforeCount =
        ((await inst.dumpState(conversationId: convId))['messageCount'] as num?)
                ?.toInt() ??
            0;
  }
  await returnToChatsHome(inst, rounds: 4);
  if (seeded == 0 || beforeCount == 0) {
    print('[pair] conv_clear_preserves_pin_c2c: failed to seed history '
        '(seeded=$seeded beforeCount=$beforeCount)');
    // Unpin to restore before bailing.
    await _restoreUnpinned(inst, tox, convId);
    return false;
  }
  // Clear history (C2C ungated hook).
  final r = await inst.l3('l3_clear_history', {'userId': tox});
  if (r['ok'] != true) {
    print('[pair] conv_clear_preserves_pin_c2c: l3_clear_history failed: $r');
    await _restoreUnpinned(inst, tox, convId);
    return false;
  }
  final emptied =
      await _waitConvMessageCount(inst, convId, 0, timeoutSecs: 15);
  final stillPinned = await _waitConversationPinned(inst, convId, true);
  final rowPresent = await _conversationListed(inst, convId);
  // Restore unpinned so later cases start clean.
  await _restoreUnpinned(inst, tox, convId);
  await inst.shot('/tmp/ui_conv_clrpin_${inst.name}.png');
  print(
    '[pair] conv_clear_preserves_pin_c2c: beforeCount=$beforeCount '
    'emptied=$emptied stillPinned=$stillPinned rowPresent=$rowPresent',
  );
  return emptied && stillPinned && rowPresent;
}

/// Toggle a conversation back to unpinned if it is currently pinned (restore).
Future<void> _restoreUnpinned(Inst inst, String tox, String convId) async {
  if (await _isConvPinned(inst, convId)) {
    try {
      await _dispatchC2cConvAction(inst, tox, 'pin');
      await _waitConversationPinned(inst, convId, false);
    } on DriveError catch (e) {
      print('[pair] _restoreUnpinned: best-effort failed: ${e.message}');
    }
  }
}

// ===========================================================================
// case 51 — conv_unread_badge_bump_clear (S90/S19)
// ===========================================================================
/// B sends → A's row unread badge bumps to N≥1; A OPENS the chat (real row tap)
/// → unread clears to 0 (opening the conversation marks it read through the
/// production active-conversation path). Distinct from case 47 (which clears via
/// the menu's mark-read): here the clear is driven by OPENING the chat — the
/// natural user action. Seeding is REAL (B's composer sends).
Future<bool> _convUnreadBadgeBumpClear(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  final convId = _c2cConvId(toxB);
  await returnToChatsHome(a, rounds: 4);
  try {
    await a.clearActiveConversation();
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
  }
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await openChat(b, toxA);
  var bSent = 0;
  for (var i = 0; i < 2; i++) {
    if (await sendComposerMessage(b, 'RUIB5BUMP-$i-$nonce')) bSent++;
  }
  if (bSent == 0) {
    print('[pair] conv_unread_badge_bump_clear: B failed to send seed message');
    return false;
  }
  final bumped =
      await _waitConversationUnread(a, convId, (u) => u >= 1, timeoutSecs: 60);
  if (!bumped) {
    final entry = await _conversationEntry(a, convId);
    await a.shot('/tmp/ui_conv_bump_noseed_A.png');
    print('[pair] conv_unread_badge_bump_clear: unread did not bump '
        '(entry=$entry bSent=$bSent)');
    return false;
  }
  // OPEN the chat by tapping the real row → marks read on open.
  await a.foreground();
  await openChat(a, toxB);
  final cleared =
      await _waitConversationUnread(a, convId, (u) => u == 0, timeoutSecs: 20);
  await returnToChatsHome(a, rounds: 4);
  await a.shot('/tmp/ui_conv_bump_A.png');
  print(
    '[pair] conv_unread_badge_bump_clear: bSent=$bSent bumped=$bumped '
    'cleared=$cleared',
  );
  return bumped && cleared;
}

// ===========================================================================
// case 52 — conv_preview_updates_on_inbound
// ===========================================================================
/// B sends a distinctive nonce message → A's C2C row last-message PREVIEW
/// (`lastMessageText` for that conversation, the same source the row subtitle
/// renders) shows it. Seeding is REAL (B's composer send).
Future<bool> _convPreviewUpdatesOnInbound(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  final convId = _c2cConvId(toxB);
  await returnToChatsHome(a, rounds: 4);
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final preview = 'RUIB5PREVIEW-$nonce';
  await openChat(b, toxA);
  if (!await sendComposerMessage(b, preview)) {
    print('[pair] conv_preview_updates_on_inbound: B failed to send preview');
    return false;
  }
  final shown = await _waitConvLastMessage(a, convId, preview, timeoutSecs: 60);
  await a.shot('/tmp/ui_conv_preview_A.png');
  final last = await _lastMessageForConversation(a, convId);
  print(
    '[pair] conv_preview_updates_on_inbound: shown=$shown lastPreview="$last" '
    'want="$preview"',
  );
  return shown;
}

/// Poll until [convId]'s lastMessageText equals [text].
Future<bool> _waitConvLastMessage(
  Inst inst,
  String convId,
  String text, {
  int timeoutSecs = 60,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _lastMessageForConversation(inst, convId) == text) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

// ===========================================================================
// case 54 — conv_search_filter_clear (S48)
// ===========================================================================
/// Open the global conversation search overlay via the REAL Cmd+Ctrl+F keyboard
/// shortcut (`_OpenSearchIntent` → pushes `CustomSearch`; there is NO visible
/// search button on the home page, the shortcut is the only entry). Type a
/// filter matching the friend → the friend's CONTACT result row
/// (`search_result_contact:<uid>`) renders through the real
/// `_matchesKeywordCaseInsensitive` filter; clear → the result rows empty
/// (EmptyStateWidget); a fresh matching query restores the row. Close the
/// overlay (ESC / close icon) afterwards.
Future<bool> _convSearchFilterClear(Inst inst, String toxFriend,
    String friendNickName) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  // B surfaces in global search as a CONVERSATION result (A has a C2C conv with
  // B), keyed by its conversationID `c2c_<pubkey>` — NOT a `search_result_contact`
  // row (the CONTACTS section only lists a separate contact entry that may not
  // render when a conversation already matches). Match the conversation result,
  // which is what actually appears (verified by screenshot).
  final fullKey = 'search_result_conversation:c2c_${toxFriend.trim()}';
  final shortKey = 'search_result_conversation:c2c_${_pubkey(toxFriend)}';
  // Open the global search overlay via the real Cmd+Ctrl+F shortcut.
  if (!await _openGlobalSearch(inst)) {
    print('[pair] conv_search_filter_clear: search overlay did not open');
    return false;
  }
  // 1) Matching filter — the first hex chars of the tox id (contactMatchesQuery
  // matches on userID). We search the ID prefix, NOT the nickname, because in
  // the same-host 2-process environment the peer's self-name does not propagate
  // over the loopback friend connection (a c-toxcore name-exchange artifact,
  // distinct from the working message channel — deep-diagnosed 2026-06-14), so
  // A displays B by its tox id, which is exactly what a user searches for here.
  // This still exercises the real contact-search FILTER + clear, which is the
  // case's intent.
  final matchQuery = _pubkey(toxFriend).substring(0, 6);
  await inst.focusType('message_search_field', matchQuery);
  // The search debounces 300ms then runs the async FFI-backed search.
  await Future<void>.delayed(const Duration(milliseconds: 1400));
  final rowMatches = await inst.waitKey(shortKey, timeoutSecs: 6) ||
      await inst.waitKey(fullKey, timeoutSecs: 2);
  // 2) Clear → the keyword is empty → the result rows empty out.
  await inst.tapKey('message_search_field');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  final rowGoneOnClear = await inst.waitKeyGone(shortKey, timeoutSecs: 4) &&
      await inst.waitKeyGone(fullKey, timeoutSecs: 2);
  // 3) Re-type the matching filter → the row returns. Use focusType (osascript
  // keystrokes), NOT raw synthetic enterText — the latter drives the macOS
  // engine's -[FlutterTextInputPlugin setEditingState:] which SIGSEGVs the app.
  await inst.focusType('message_search_field', matchQuery);
  await Future<void>.delayed(const Duration(milliseconds: 1400));
  final rowBack = await inst.waitKey(shortKey, timeoutSecs: 6) ||
      await inst.waitKey(fullKey, timeoutSecs: 2);
  await inst.shot('/tmp/ui_conv_search_${inst.name}.png');
  // The overlay MUST be dismissed before this case is allowed to PASS — a
  // lingering CustomSearch route would poison the NEXT case (which expects the
  // chats home / conversation list, not a search overlay on top). Gate on it.
  final closed = await _closeGlobalSearch(inst);
  print(
    '[pair] conv_search_filter_clear: rowMatches=$rowMatches '
    'rowGoneOnClear=$rowGoneOnClear rowBack=$rowBack closed=$closed '
    '(matchQuery="$matchQuery" displayName="$friendNickName" '
    '[id-search: peer self-name does not propagate same-host])',
  );
  return rowMatches && rowGoneOnClear && rowBack && closed;
}

/// Open the global conversation search overlay via the real Cmd+Ctrl+F shortcut
/// (the only entry — no visible search button). Returns whether the search field
/// mounted. Best-effort + bounded.
Future<bool> _openGlobalSearch(Inst inst) async {
  await inst.foreground();
  if (await inst.waitKey('message_search_field', timeoutSecs: 1)) return true;
  // PRIMARY: the deterministic l3_open_global_search seam (pushes the SAME
  // CustomSearch route the Cmd/Ctrl+F shortcut uses). The osascript keystroke
  // below is occasionally dropped when the window isn't fully foregrounded
  // under 2-process contention, which flaked the open. The seam is opening-only
  // (navigation stability) — the result tap + chat open the case asserts stay
  // real gestures. Falls back to the real keystroke if the seam is absent (an
  // app build without the L3 surface) or no-ops.
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final r = await inst.l3('l3_open_global_search');
      if (r['ok'] == true &&
          await inst.waitKey('message_search_field', timeoutSecs: 4)) {
        return true;
      }
    } on DriveError catch (e) {
      print('[pair] _openGlobalSearch: l3 seam warn: ${e.message}');
      break; // seam not registered — go straight to the keystroke fallback
    }
  }
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      await inst.osaSearchShortcut();
    } on DriveError catch (e) {
      print('[pair] _openGlobalSearch: shortcut warn: ${e.message}');
    }
    if (await inst.waitKey('message_search_field', timeoutSecs: 4)) return true;
  }
  return false;
}

/// Close the global search overlay (ESC; falls back to the close IconButton's
/// tooltip is not key-targetable, so ESC is the deterministic dismiss). Returns
/// whether the overlay is GONE afterwards (the search field key is absent) — the
/// caller gates on this so a lingering overlay never false-passes case 54.
Future<bool> _closeGlobalSearch(Inst inst) async {
  if (!await inst.waitKey('message_search_field', timeoutSecs: 1)) return true;
  try {
    await inst.osaEscape();
  } on DriveError {
    // best-effort
  }
  if (await inst.waitKeyGone('message_search_field', timeoutSecs: 4)) return true;
  // Fallback: the overlay's close IconButton has no key; tap the top-right
  // corner where it renders (1280x768 AppBar trailing).
  await inst.tapAt(1240, 36);
  return inst.waitKeyGone('message_search_field', timeoutSecs: 3);
}

// ===========================================================================
// case 48 — conv_delete_confirm_c2c (S119/S20)  [destructive; near LAST]
// ===========================================================================
/// Open the REAL C2C row menu, tap the real Delete item → the real keyed confirm
/// dialog → confirm → the row leaves the sidebar while the FRIENDSHIP stays
/// intact (deleteConversation → clearC2CHistory + unpin, NOT deleteFriend —
/// the S20 invariant). Runs near the END; the sweep RE-SEEDS a row afterwards so
/// the launch ends tidy (friends, with a visible row).
Future<bool> _convDeleteConfirmC2c(Inst inst, String toxFriend) async {
  final convId = _c2cConvId(toxFriend);
  if (!await _seedConvRow(inst, toxFriend)) {
    print('[pair] conv_delete_confirm_c2c: could not seed the C2C row');
    return false;
  }
  final friendBefore = await areFriends(inst, toxFriend);
  // Open the REAL row menu + tap the real Delete item.
  if (!await _openConvRowMenuReal(inst, toxFriend)) {
    print('[pair] conv_delete_confirm_c2c: real row menu did not open');
    return false;
  }
  // Overlay-aware detection (the menu item renders in an Overlay.insert that
  // whole-tree waitKey doesn't traverse — codex), matching tapKeyCenter below.
  if (!await inst.waitKeyCenter('conversation_context_menu_delete_item',
      timeoutSecs: 4)) {
    await _dismissConvMenu(inst);
    print('[pair] conv_delete_confirm_c2c: delete item not present');
    return false;
  }
  // Single-fire the Delete menu item (it pops the menu route + raises the
  // confirm dialog; a double-fire could pop through).
  if (!await inst.tapKeyCenter('conversation_context_menu_delete_item',
      timeoutSecs: 6)) {
    await _dismissConvMenu(inst);
    print('[pair] conv_delete_confirm_c2c: delete item not tappable');
    return false;
  }
  if (!await inst.waitKey('delete_conversation_confirm_button',
      timeoutSecs: 10)) {
    await inst.shot('/tmp/ui_conv_del_nodialog_${inst.name}.png');
    print('[pair] conv_delete_confirm_c2c: confirm dialog did not open');
    return false;
  }
  // Single-fire the keyed confirm (the ModalRoute.isCurrent guard absorbs a
  // double-fire, but tapKeyCenter is one tap).
  if (!await inst.tapKeyCenter('delete_conversation_confirm_button',
      timeoutSecs: 6)) {
    print('[pair] conv_delete_confirm_c2c: confirm not tappable');
    return false;
  }
  // For a C2C conversation, deleteConversation fires onConversationDeleted (the
  // host suppresses the row until a new message arrives) + clears history/pin,
  // so the row leaves the sidebar.
  final gone = await _waitConversationGone(inst, convId, timeoutSecs: 20);
  // The friendship must be INTACT (S20: delete-conversation ≠ delete-friend).
  final friendAfter = await areFriends(inst, toxFriend);
  await inst.shot('/tmp/ui_conv_del_${inst.name}.png');
  print(
    '[pair] conv_delete_confirm_c2c: friendBefore=$friendBefore gone=$gone '
    'friendAfter=$friendAfter',
  );
  return friendBefore && gone && friendAfter;
}

// ===========================================================================
// case 53 — conv_presence_dot_flips (S51)  — SKIP (see file header)
// ===========================================================================
/// SKIP: the friend `online` flag is a read-only native connection-status
/// readout (no ungated l3 setter); the only flip mechanism is stopping/relaunching
/// B's process, which the launch-reuse rule forbids. Returns null (SKIP). As a
/// non-asserting surface note, the row's online-dot KEY is always present
/// regardless of online state — but the FLIP itself cannot be seeded on a reused
/// launch, so faking a flip would be dishonest. See the file header for the full
/// investigation (drive_fixture_c_presence.dart is purely observational).
Future<bool?> _convPresenceDotFlips(Inst a, String toxFriend) async {
  // Best-effort surface log: the dot key exists for the C2C row (always, online
  // or not). This is NOT the asserted flip — it's a debugging breadcrumb.
  final convId = _c2cConvId(toxFriend);
  try {
    await returnToChatsHome(a, rounds: 2);
    final dotPresent = await a.waitKey(
        'conversation_item_online_dot:$convId', timeoutSecs: 3);
    print('[pair] conv_presence_dot_flips: SKIP — presence flip un-seedable on '
        'a reused launch (no ungated online setter; stopping B is forbidden). '
        'dotKeyPresent=$dotPresent (surface only — NOT the asserted flip)');
  } on DriveError catch (e) {
    print('[pair] conv_presence_dot_flips: SKIP — ${e.message}');
  }
  return null;
}

// ===========================================================================
// sweep_conv — Batch 5: chain all 10 conversation-list cases on ONE 2p launch.
// ===========================================================================
/// Order (state-poison-aware): handshake once → 45 menu surface → 46 pin/unpin
/// reorder (ends unpinned) → 47 mark-read (B seeds unread, menu mark-read clears)
/// → 49 clear-history (seed + clear, row survives) → 50 clear-preserves-pin
/// (ends unpinned) → 51 unread bump→open clears → 52 preview updates on inbound
/// → 53 presence (SKIP) → 54 conversation search filter/clear → 48 DELETE row
/// (near LAST; friendship intact) → RE-SEED a row so the launch ends tidy.
///
/// Prints `[sweep] <case>: PASS|FAIL|SKIP` per case + final counts; exits
/// non-zero if any HARD case fails (9 hard, 1 SKIP). The whole body runs inside a
/// try with a `finally` end-guard that RE-SEEDS the conversation row and lands
/// both on the chats home so the launch ends in the registered FRIENDS state with
/// a visible row.
Future<int> runConvSweep(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[sweep] sweep_conv: missing tox ids (A=$toxA B=$toxB)');
    return 1;
  }
  print(
    '[sweep] sweep_conv: A=${_shortId(toxA)} ($nickA) '
    'B=${_shortId(toxB)} ($nickB)',
  );

  var passed = 0;
  var failed = 0;
  var skipped = 0;
  final results = <String, String>{};
  // Whether the launch ends in the registered FRIENDS state (with a re-seeded
  // row). Default false so an early/exceptional abort before the end-guard runs
  // is treated as DIRTY — the runner must not trust a friends result that was
  // never re-verified. Set inside the `finally` end-guard, read by the return.
  var endFriends = false;

  Future<void> hard(String id, Future<bool> Function() run) async {
    bool ok;
    String? detail;
    try {
      ok = await run();
    } on PermissionBlockedError {
      rethrow; // surfaces as BLOCKED(78) at the driver level
    } on DriveError catch (e) {
      ok = false;
      detail = 'DriveError: ${e.message}';
    }
    if (ok) {
      passed++;
      results[id] = 'PASS';
      print('[sweep] $id: PASS');
    } else {
      failed++;
      results[id] = 'FAIL';
      print('[sweep] $id: FAIL${detail != null ? ' ($detail)' : ''}');
    }
  }

  Future<void> skip(String id, Future<bool?> Function() run) async {
    try {
      final r = await run();
      if (r == true) {
        passed++;
        results[id] = 'PASS';
        print('[sweep] $id: PASS');
      } else if (r == false) {
        failed++;
        results[id] = 'FAIL';
        print('[sweep] $id: FAIL');
      } else {
        skipped++;
        results[id] = 'SKIP';
        print('[sweep] $id: SKIP');
      }
    } on DriveError catch (e) {
      skipped++;
      results[id] = 'SKIP';
      print('[sweep] $id: SKIP (${e.message})');
    }
  }

  try {
    // --- Establish the A<->B friendship (real-UI handshake) once. ---
    final friended =
        await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB);
    if (!friended) {
      print('[sweep] sweep_conv: handshake FAILED — no case can run; '
          'marking them failed');
      for (final id in const [
        'conv_menu_surface_c2c',
        'conv_pin_unpin_reorders',
        'conv_mark_read_two_proc',
        'conv_clear_history_c2c',
        'conv_clear_preserves_pin_c2c',
        'conv_unread_badge_bump_clear',
        'conv_preview_updates_on_inbound',
        'conv_search_filter_clear',
        'conv_delete_confirm_c2c',
      ]) {
        failed++;
        results[id] = 'FAIL';
      }
      results['conv_presence_dot_flips'] = 'SKIP';
      skipped++;
    } else {
      // Mark BOTH accounts as L3 seed accounts so the test-gated nav/clear tools
      // (l3_force_home_root for the contacts shell, l3_clear_active_conversation
      // for true-unread accrual, l3_clear_history for the clear-history cases)
      // work on these fresh non-test real-UI accounts. The marker authorizes the
      // whole gated surface; the asserted action in every case stays the real
      // widget/gesture, and it is REVOKED in the end-guard. (Mirrors sweep_chat /
      // sweep_p1_chat, which already mark; sweep_conv was missing it, so every
      // gated case failed with non_test_account.)
      final aMarked = await a.markAccountTest();
      final bMarked = await b.markAccountTest();
      print('[sweep] sweep_conv: marked test accounts aMarked=$aMarked '
          'bMarked=$bMarked (unblocks l3 nav/clear tools)');
      // --- 45: menu surface (right-click → items render). ---
      await hard('conv_menu_surface_c2c', () => _convMenuSurfaceC2c(a, toxB));
      // --- 46: pin/unpin + reorder (ends unpinned). ---
      await hard(
          'conv_pin_unpin_reorders', () => _convPinUnpinReorders(a, toxB));
      // --- 47: mark-read true unread>0→0 via the menu. ---
      await hard('conv_mark_read_two_proc',
          () => _convMarkReadTwoProc(a, b, toxA, toxB));
      // --- 49: clear-history (row survives). ---
      await hard('conv_clear_history_c2c', () => _convClearHistoryC2c(a, toxB));
      // --- 50: clear-preserves-pin (ends unpinned). ---
      await hard('conv_clear_preserves_pin_c2c',
          () => _convClearPreservesPinC2c(a, toxB));
      // --- 51: unread badge bump → open chat clears. ---
      await hard('conv_unread_badge_bump_clear',
          () => _convUnreadBadgeBumpClear(a, b, toxA, toxB));
      // --- 52: preview updates on inbound. ---
      await hard('conv_preview_updates_on_inbound',
          () => _convPreviewUpdatesOnInbound(a, b, toxA, toxB));
      // --- 53: presence dot flip (SKIP — un-seedable on a reused launch). ---
      await skip(
          'conv_presence_dot_flips', () => _convPresenceDotFlips(a, toxB));
      // --- 54: conversation search filter/clear. ---
      await hard('conv_search_filter_clear',
          () => _convSearchFilterClear(a, toxB, nickB));
      // --- 48: DELETE row (near LAST; friendship intact). ---
      await hard(
          'conv_delete_confirm_c2c', () => _convDeleteConfirmC2c(a, toxB));
    }
  } finally {
    // END-STATE GUARD: the registered result is FRIENDS with a VISIBLE re-seeded
    // conversation ROW. Case 48 removed the C2C row (friendship intact); re-seed
    // a row so the launch ends tidy, then VERIFY the row is actually listed (a
    // silently-failed reseed must not false-pass the contract — codex P1). Land
    // both on the chats home.
    var endRowSeeded = false;
    try {
      if (await areFriends(a, toxB)) {
        endRowSeeded = await _seedConvRow(a, toxB,
            text: 'RuiB5EndSeed-${DateTime.now().microsecondsSinceEpoch}');
      }
      await returnToChatsHome(a, rounds: 4);
      await b.foreground();
      await returnToChatsHome(b, rounds: 4);
    } on PermissionBlockedError catch (e) {
      print('[sweep] sweep_conv end-clean: BLOCKED (${e.message})');
    } on DriveError catch (e) {
      print('[sweep] sweep_conv end-clean: best-effort failed: ${e.message}');
    }
    // The registered result is FRIENDS with a visible row; verify the pair is
    // still friended both ways AND the re-seeded row is listed so the runner does
    // not trust an unachieved result state. The AUTHORITATIVE row signal is the
    // LIVE `_conversationListed` check (not the reseed return) — so a reseed whose
    // `_waitConversationListed` happened to time out but whose row IS present by
    // now still passes; `endRowSeeded` is only a fast diagnostic (codex follow-up:
    // gating on `endRowSeeded &&` would false-FAIL that race).
    try {
      final stillRow = await _conversationListed(a, _c2cConvId(toxB));
      endFriends =
          await areFriends(a, toxB) && await areFriends(b, toxA) && stillRow;
    } on DriveError {
      endFriends = false;
    }
    // Revoke the seed-account marker so the launch ends in the same non-test
    // privilege state it began in (the runner's state contract). Best-effort:
    // the reseed above already ran while still marked.
    try {
      await a.unmarkAccountTest();
      await b.unmarkAccountTest();
    } on DriveError {
      // best-effort
    }
    print(
      '[sweep] sweep_conv RESULTS: $passed PASS / $failed FAIL / $skipped SKIP '
      '($results) | endFriends=$endFriends endRowSeeded=$endRowSeeded',
    );
    try {
      await a.shot('/tmp/ui_conv_sweep_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_conv_sweep_B.png');
    } on DriveError {
      // best-effort
    }
    if (!endFriends) {
      print('[sweep] sweep_conv: end state is NOT friends-with-row — failing the '
          'sweep so the runner does not trust the result-state contract');
    }
  }
  // FAIL if any HARD case failed OR the launch did not reach the registered
  // FRIENDS-with-a-visible-row end state (so the runner never trusts a dirty
  // result).
  return (failed == 0 && endFriends) ? 0 : 1;
}
