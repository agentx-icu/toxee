// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 6 of the real-UI sweep campaign — "Chat surface C2C" (16 cases,
// TWO-PROCESS). See tool/mcp_test/REAL_UI_SWEEP_CAMPAIGN.md.
//
// `sweep_chat` drives BOTH instances. ONE handshake at the top establishes the
// A<->B friendship that all cases reuse; B's REAL composer sends seed real
// inbound history (case 65 history-load-more / 66 inbound-while-scrolled-up).
// The destructive case (delete-message 64) runs after the menu cases that need
// the bubble, and the seeded history serves both 65 and 66.
//
// State contract (registered in fixture_c_unified_runner.dart):
//   required = no-friend  (fresh pair launch; the sweep does its OWN handshake,
//                          reusing Batch-4's `_establishFriendshipForSweep`)
//   result   = friends    (no case deletes the friend; the sweep ends with the
//                          C2C conversation alive — a visible row + friendship)
//
// ===========================================================================
// MESSAGE CONTEXT-MENU TRIGGER (the brief's recipe, Batch-0 finding — fully
// REAL, no l3 deep-link for the open): the desktop chat message menu opens via
// a `Listener` in `TencentCloudChatMessageItemWithMenu.desktopBuilder`
// (third_party/.../menu/tencent_cloud_chat_message_item_with_menu.dart:684):
// `onPointerDown` fires `_openDesktopMessageMenu(event.position)` ONLY when
// `event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton`.
// So `Inst.secondaryTapKey` (Batch-0 `ui_secondary_tap` → a real
// `PointerDownEvent(kind:mouse, buttons:kSecondaryMouseButton)`) on the ROW
// container key `ValueKey('message_list_item:<msgID>')` opens the REAL menu (its
// center lies inside the bubble/Listener region). The menu items are then tapped
// by their keys `ValueKey('message_menu_item:<action>')`.
//
// FORK MENU TRUTH (message_actions_menu_real_ui_test.dart — verified, not
// assumed): a TEXT bubble menu offers EXACTLY copy / forward / delete; the fork
// STRIPS reply + multiSelect + translate from text menus, and recall appears
// only on a FRESH SELF message (inside the recall window). So:
//   - case 60 (menu surface) asserts copy + forward + delete on an OWN text
//     bubble (recall too, since it's a fresh self message).
//   - case 61 (copy) taps the real Copy item, asserts the OS clipboard via
//     `pbpaste` (a genuine OS read).
//   - case 62 (reply/quote) cannot use a TEXT bubble (reply is stripped). The
//     real production Reply entry is on a QUOTABLE (custom-elem) bubble. The
//     sweep seeds a quotable inbound custom message via `l3_inject_custom` (an
//     l3 SEED — the asserted action is still the real Reply menu item + the real
//     composer quote banner + a real Return send).
//   - case 63 (forward) opens the real Forward picker, picks the available
//     target conversation (a SECOND C2C conv seeded to a self-thread is not
//     possible with one friend, so the picker target IS the same C2C row — the
//     "Recent" tab lists it; selecting it + Send forwards back into the chat,
//     asserting the forward send fired through the real picker).
//
// MOBILE PARITY: on non-desktop screen modes the same row uses
// `GestureDetector.onLongPress` (`_onLongPressMessageOnMobile`) — a long-press,
// which the desktop secondary-tap does not cover; mobile would drive the same
// menu via a long-press primitive (or the existing l3 `l3_invoke_message_action`
// bypass). Every menu action handler (copy/forward/delete/reply) is shared Dart,
// so the asserted behavior is identical on iOS/Android/desktop.
//
// ===========================================================================
// GATING ANSWER (the brief's open question — answered + UNBLOCKED):
// The whole L3 surface only registers in a `kDebugMode && TOXEE_L3_TEST` build
// (kL3TestSurfaceEnabled). Within that build, the mutating/SEEDING tools
// (`l3_send_file`, `l3_clear_history`, …) additionally gate on
// `_activeAccountIsTest()` (l3_debug_tools.dart): an account qualifies via an
// exact fixture nickname, a known fixture Tox-ID prefix, OR the persistent
// SEED-ACCOUNT MARKER (`Prefs.l3SeedToxIds`, written by `l3_register_account`).
// A real-UI sweep account registers through the REAL RegisterPage, so it has NO
// marker and is NON-TEST — those seeding tools refuse it with `non_test_account`.
//
// FIX (legitimate, in-contract): the new UNGATED `l3_mark_current_account_test`
// tool records the CURRENT account in the seed marker (`Prefs.addL3SeedToxId`),
// exactly as if it had been created via `l3_register_account`. NOTE: the marker
// authorizes the WHOLE test-account-gated surface (not just seeding — there is
// no per-tool scope today); the campaign uses it ONLY to SEED (every case's
// asserted action stays the real widget/gesture, NEVER an l3 substitute). It
// only works in the already-gated debug build, and because the privilege is
// broad the sweep REVOKES it (`l3_unmark_current_account_test`) in its end-guard
// so the launch ends with the same non-test state it started — no hidden grant
// for a reused launch (the marker is ALSO revoked when the account is deleted).
// The sweep calls `Inst.markAccountTest()` once at the top so cases 69/70 (image
// / file SEEDING) and Batch-5's `l3_clear_history` cases work on the fresh
// non-test accounts. This is the answer the brief asked to write prominently.
//
// ===========================================================================
// OFFLINE-PENDING (case 68) — SKIP, verified not assumed: a self-message becomes
// `isPending` only while it sits in the offline queue, which happens when the
// PEER is unreachable (message_converter.dart: isPending ==
// V2TIM_MSG_STATUS_SENDING). There is NO ungated l3 seam to force a pending /
// offline C2C send (grep l3_set_connection/l3_disconnect/l3_offline → none;
// drive_fixture_c_network_drop.dart's `network_drop` drives the CALL reconnect
// path `markReconnecting()`, not the message offline queue). The only way A's
// C2C send goes pending is making B unreachable — i.e. stopping B's process,
// which the launch-reuse rule forbids. So the pending→deliver transition is
// un-seedable on a reused launch → case 68 is SKIP (honest), never a fake pass.
//
// IMAGE TAP→PREVIEW (case 69) — the image bubble's tappable GestureDetector
// mounts only AFTER an async image load (media_message_bubbles_real_ui_test.dart
// documents the tap→open-preview half is not driveable at the widget layer). So
// case 69 asserts the REAL image bubble RENDERS (the row + the image mediaKind in
// the dump) — the strongest honest signal; the preview-open is logged best-effort
// (a coordinate tap on the bubble) but not gated, mirroring the hermetic test's
// own scope note.

// ===========================================================================
// shared chat-surface helpers
// ===========================================================================

/// Open the C2C chat with [tox] and assert the chat surface is ready.
/// Poll [inst]'s `dumpState().friends` until the friend identified by [peerTox]
/// reports `online == true`, or the timeout elapses. A FRESH friend-ADD handshake
/// only proves the friend is in the list — a FILE transfer additionally needs the
/// peer to be CONNECTED/online (`drive_fixture_c_file` waits the same way before
/// sending; without it the file offer is issued before B is online and never
/// delivers → `received=false`). Returns false (no throw) on timeout so callers
/// can log a soft gap.
Future<bool> _waitFriendOnline(
  Inst inst,
  String peerTox, {
  int timeoutSecs = 60,
}) async {
  final pk = _pubkey(peerTox);
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState();
    for (final f in (s['friends'] as List? ?? const [])) {
      if (f is Map &&
          _pubkey(f['userId']?.toString() ?? '') == pk &&
          f['online'] == true) {
        return true;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

/// Reliably bind the master-detail chat for [peerTox] via the production
/// `_openChat` (l3_open_chat) and VERIFY currentConversation took, retrying a few
/// times. A single openChatViaL3 is flaky post-restyle (the app sits on the
/// Contacts tab after a fresh handshake; the bind sometimes doesn't land), and
/// the fork composer's userID only refreshes once currentConversation actually
/// switches — so a media send right after an unverified bind silently no-ops.
Future<bool> _ensureBoundChat(Inst inst, String peerTox, {int tries = 4}) async {
  final convId = _c2cConvId(peerTox);
  for (var i = 0; i < tries; i++) {
    await inst.openChatViaL3(userId: _pubkey(peerTox));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (await _chatSurfaceReady(inst, convId, timeoutSecs: 4)) return true;
  }
  return false;
}

Future<bool> _ensureChatOpen(Inst inst, String tox) async {
  // A prior case can leave the friend's contact profile pushed ON TOP of the
  // chat; pop it first so the chat surface is actually interactable (otherwise
  // openChat binds the chat OFFSTAGE behind the profile and the composer/menu
  // taps land on the profile).
  await inst.foreground();
  await _dismissFriendProfileToUnderlying(inst);
  try {
    await openChat(inst, tox);
  } on DriveError catch (e) {
    print('[pair] _ensureChatOpen: ${e.message}');
  }
  if (await _chatSurfaceReady(inst, _c2cConvId(tox), timeoutSecs: 8)) {
    return true;
  }
  // Fallback: drive the production `_openChat` path via the ungated l3_open_chat
  // nav-stability seam when the row-tap open didn't land — e.g. a prior case
  // left the app on the contact profile / a search overlay so the conv row
  // wasn't tappable. Deterministic; the asserted action of every case stays a
  // real widget gesture. Pass the PUBKEY: l3_open_chat forwards userId verbatim
  // into `c2c_<userId>`, but `_chatSurfaceReady`/_c2cConvId normalize to
  // `c2c_<pubkey>` — a full tox id would open a non-matching conv and fail
  // readiness (codex). `_pubkey` is idempotent for an already-pubkey id.
  await inst.openChatViaL3(userId: _pubkey(tox));
  return _chatSurfaceReady(inst, _c2cConvId(tox), timeoutSecs: 8);
}

/// The ORDERED list of message entries (dump `messages[]`) for the C2C
/// conversation with [tox], newest-first or oldest-first as the persistence
/// returns them. Each entry: {msgID,text,isSelf,isPending,mediaKind,fileName,
/// filePath,fileSize,cloudCustomData}.
Future<List<Map<String, dynamic>>> _c2cMessages(Inst inst, String tox) async {
  final s = await inst.dumpState(conversationId: _c2cConvId(tox));
  final raw = (s['messages'] as List?) ?? const [];
  return [
    for (final m in raw)
      if (m is Map) m.cast<String, dynamic>(),
  ];
}

/// The msgID of the newest OWN (self) message whose text == [text] in the C2C
/// chat with [tox] (the row key for the message menu is
/// `message_list_item:<msgID>`). Returns null if not found.
Future<String?> _ownMessageId(Inst inst, String tox, String text) async {
  final msgs = await _c2cMessages(inst, tox);
  String? id;
  for (final m in msgs) {
    if (m['isSelf'] == true && m['text']?.toString() == text) {
      final mid = m['msgID']?.toString();
      if (mid != null && mid.isNotEmpty) id = mid;
    }
  }
  return id;
}

/// Poll until a message whose text == [text] exists in the C2C chat with [tox].
Future<bool> _waitC2cMessageText(Inst inst, String tox, String text,
    {bool? isSelf, int timeoutSecs = 60}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final msgs = await _c2cMessages(inst, tox);
    if (msgs.any((m) =>
        m['text']?.toString() == text &&
        (isSelf == null || m['isSelf'] == isSelf))) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Open the REAL desktop message context menu for the OWN message [msgId] via a
/// genuine secondary-tap (right-click) on its row — the production
/// `_openDesktopMessageMenu` path (no gated tool). Returns whether at least one
/// keyed `message_menu_item:*` rendered. Foregrounds first + retries.
Future<bool> _openMessageMenuReal(Inst inst, String msgId) async {
  await inst.foreground();
  // Pop the friend's contact profile if it's covering the chat — otherwise the
  // message row is offstage behind it and the secondary-tap hits the profile
  // ("menu did not open").
  await _dismissFriendProfileToUnderlying(inst);
  final rowKey = 'message_list_item:$msgId';
  if (!await inst.waitKey(rowKey, timeoutSecs: 8)) {
    print('[pair] _openMessageMenuReal: row $rowKey not present');
    return false;
  }
  // A SELF message bubble is right-aligned, so the row's geometric CENTER can
  // land on empty space left of the bubble — a secondary-tap there misses the
  // bubble's `Listener.onPointerDown` and no menu opens. Right-click the bubble
  // itself: prefer a keyed bubble anchor, else bias the tap toward the right
  // (self) / left (peer) third of the row.
  final rowCenter = await inst.keyCenter(rowKey);
  // A SELF bubble is right-aligned WITHIN the chat detail pane. The row center
  // (rowCenter.x) IS the pane center, so bias toward the pane's RIGHT portion
  // RELATIVE to it — an absolute x (e.g. 1150) can fall OUTSIDE a narrow pane
  // and miss entirely (observed rowCenter.x≈404 → pane≈0-808 → 1150 missed). The
  // pane half-width ≈ rowCenter.x, so 1.4x / 1.6x / 1.8x land in the right third
  // where the bubble's Listener.onPointerDown is. Alternate with the row-key
  // center (peer / full-width rows).
  // Bias factors relative to the pane-center rowCenter.x: 1.0 = row centre,
  // >1 = RIGHT third (self/outbound bubbles), <1 = LEFT third (peer/INBOUND
  // bubbles — e.g. a narrow inbound `[Custom]` placeholder sits far left of the
  // pane centre, so a centre/right tap misses its Listener.onPointerDown and no
  // menu opens). Cover both sides + centre.
  // Bias factors relative to the pane-center rowCenter.x. Live-probed on the
  // Feishu-restyle layout (1280-wide window, rowCenter.x≈831): the SELF (outbound)
  // bubble's Listener.onPointerDown sits at ≈1.24× rowCenter.x (x≈1030), NOT the
  // old 1.5× (x≈1247, which overshoots past the bubble's right edge → no menu).
  // The PEER (inbound) bubble sits at ≈0.6×. Cover the self range (1.12–1.32) and
  // the peer range (0.45–0.7) densely; 1.8× fell OFF-SCREEN on this wider pane.
  const biasFactor = <double>[1.24, 0.6, 1.32, 0.5, 1.12, 0.7, 1.0, 0.45];
  for (var attempt = 0; attempt < biasFactor.length; attempt++) {
    var tapped = false;
    try {
      final bias = biasFactor[attempt];
      if (rowCenter != null && bias != 1.0) {
        await inst.secondaryTapAt(rowCenter.x * bias, rowCenter.y);
      } else {
        await inst.secondaryTapKey(rowKey);
      }
      tapped = true;
    } on DriveError catch (e) {
      print('[pair] _openMessageMenuReal: secondaryTap warn: ${e.message}');
    }
    if (!tapped) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      continue;
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    // The desktop context menu renders in an `Overlay.insert` entry that
    // flutter_skill's waitForElement/interactiveStructured does NOT traverse
    // (it only ever matched the now-keyless OFFSTAGE measurement copy). Detect
    // it via the ELEMENT-TREE resolver (`waitKeyCenter` → resolveKeyCenter),
    // which walks the full tree including overlays. Taps still go through
    // tapKeyCenter, which falls back to the same resolver.
    if (await inst.waitKeyCenter('message_menu_item:copy', timeoutSecs: 3) ||
        await inst.waitKeyCenter('message_menu_item:delete', timeoutSecs: 2)) {
      return true;
    }
  }
  await inst.shot('/tmp/ui_open_msg_menu_fail_${inst.name}.png');
  print(
    '[pair] _openMessageMenuReal: menu did not open for $rowKey '
    '(rowCenter=$rowCenter) shot=/tmp/ui_open_msg_menu_fail_${inst.name}.png',
  );
  return false;
}

/// Dismiss an open message menu / popup by tapping the modal barrier corner.
Future<void> _dismissMessageMenu(Inst inst) async {
  await inst.tapAt(8, 8);
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/// DIAGNOSTIC (single-app, no rebuild): seed a friend + a self/peer bubble + open
/// chat, then report window size, conversation_list_item resolution (offstage?),
/// per-message row center, and which absolute secondary-tap x opens the message
/// menu. Used to root-cause the Feishu-restyle real-UI regressions.
Future<int> runProbeRestyleDiag(Inst a) async {
  await a.foreground();
  await ensureHome(a, 'ProbeAlice', requireHomeMenu: false);
  final marked = await a.markAccountTest();
  try {
  final ws = await a.windowSize();
  print('PROBE marked=$marked windowSize=$ws');
  const peer =
      'A1B2C3D4E5F60718293041526374859617283940516273849506A1B2C3D4E5F6';
  final seed = await a.l3('l3_seed_friend', {
    'userId': peer,
    'nickname': 'ProbeBob',
  });
  print('PROBE seed ok=${seed['ok']}');
  await a.l3('l3_inject_c2c_text', {
    'userId': peer,
    'text': 'PROBE-SELF-MSG',
    'isSelf': 'true',
  });
  await a.l3('l3_inject_c2c_text', {
    'userId': peer,
    'text': 'PROBE-PEER-MSG',
    'isSelf': 'false',
  });
  final open = await a.l3('l3_open_chat', {'userId': peer});
  print('PROBE open ok=${open['ok']}');
  await Future<void>.delayed(const Duration(seconds: 3));
  final convRaw = await a.l3('ui_key_center', {
    'key': 'conversation_list_item:c2c_$peer',
  });
  print('PROBE convKeyCenter=$convRaw');
  final msgs = await _c2cMessages(a, peer);
  print('PROBE msgCount=${msgs.length}');
  final width = ws?.w.toDouble() ?? 1280.0;
  for (final m in msgs) {
    final id = (m['msgID'] ?? m['id'] ?? '').toString();
    final isSelf = m['isSelf'];
    final rowKey = 'message_list_item:$id';
    final rowRaw = await a.l3('ui_key_center', {'key': rowKey});
    final rc = await a.keyCenter(rowKey);
    print('PROBE row isSelf=$isSelf rowCenter=$rowRaw');
    if (rc == null) continue;
    // Scan absolute x positions across the chat pane at the row's y; report which
    // opens the message menu (i.e. where the bubble Listener.onPointerDown is).
    final xs = <double>[
      rc.x,
      rc.x * 1.24,
      rc.x * 1.5,
      width - 60,
      width - 120,
      width - 200,
      rc.x * 0.6,
      width * 0.5,
      450,
      550,
    ];
    for (final x in xs) {
      if (x <= 0 || x >= width) continue;
      try {
        await a.secondaryTapAt(x, rc.y);
      } on DriveError catch (e) {
        print('PROBE   secTap x=${x.toStringAsFixed(0)} ERR=${e.message}');
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final opened =
          await a.waitKeyCenter('message_menu_item:copy', timeoutSecs: 1) ||
          await a.waitKeyCenter('message_menu_item:delete', timeoutSecs: 1);
      print('PROBE   secTap x=${x.toStringAsFixed(0)} y=${rc.y.toStringAsFixed(0)} '
          'menuOpened=$opened');
      if (opened) {
        await _dismissMessageMenu(a);
        break;
      }
    }
  }
  // ATTACHMENT diagnostic: confirm whether the desktop file button actually
  // sends (codex hypothesis: userID==null reaches _sendMedia → silent skip).
  await a.l3('l3_open_chat', {'userId': peer});
  await Future<void>.delayed(const Duration(seconds: 1));
  final src = File(_portableTmp('/tmp/probe_attach.txt'));
  await src.writeAsString('PROBE-ATTACH-FILE');
  final ov = await a.l3('l3_set_attachment_pick_path', {'path': src.path});
  print('PROBE attach override ok=${ov['ok']}');
  final beforeIds = {
    for (final m in await _c2cMessages(a, peer)) (m['msgID'] ?? m['id']).toString(),
  };
  final tapOk = await a.tapKeyAt('message_attachment_file_button');
  print('PROBE attach fileButton tapKeyAt=$tapOk');
  await Future<void>.delayed(const Duration(seconds: 3));
  final afterMsgs = await _c2cMessages(a, peer);
  final newFile = afterMsgs
      .where((m) =>
          !beforeIds.contains((m['msgID'] ?? m['id']).toString()) &&
          m['mediaKind']?.toString() == 'file')
      .length;
  print('PROBE attach newFileMsgs=$newFile totalBefore=${beforeIds.length} '
      'totalAfter=${afterMsgs.length}');
  await a.l3('l3_set_attachment_pick_path', {'path': ''});

  // SEARCH diagnostic: open global search, type the peer prefix, tap the conv
  // result, report whether currentConversation became the target (opened).
  // pop any open chat profile / overlay first so the shortcut isn't swallowed
  await a.l3('l3_pop_to_root', {});
  await Future<void>.delayed(const Duration(milliseconds: 600));
  var searchOpen = false;
  for (var i = 0; i < 4 && !searchOpen; i++) {
    await a.foreground();
    await a.osaSearchShortcut();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    searchOpen = await a.waitKey('message_search_field', timeoutSecs: 3);
  }
  print('PROBE search opened=$searchOpen');
  if (searchOpen) {
    await a.focusType('message_search_field', peer.substring(0, 6));
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    const convResultKey = 'search_result_conversation:c2c_$peer';
    final resRaw = await a.l3('ui_key_center', {'key': convResultKey});
    print('PROBE search resultKey=$resRaw');
    final tapped = await a.tapKeyCenter(convResultKey, timeoutSecs: 5) ||
        await a.tryTapKey(convResultKey, retries: 2);
    await Future<void>.delayed(const Duration(seconds: 2));
    final cur = await a.dumpState();
    print('PROBE search tapped=$tapped afterTap currentConversation='
        '${cur['currentConversation']} homeShellTab=${cur['homeShellTab']}');
  }
  await a.shot('/tmp/probe_restyle_A.png');
  return 0;
  } finally {
    // codex: the account-test marker authorizes the broad gated L3 surface — always
    // revoke it (and clear any attachment override) even if the probe throws.
    if (marked) {
      await a.l3('l3_set_attachment_pick_path', {'path': ''});
      await a.unmarkAccountTest();
    }
  }
}

/// Send a real OWN composer message into the chat with [tox] and return its
/// msgID (or null on failure). Opens the chat first.
Future<String?> _sendAndIdentify(Inst inst, String tox, String text) async {
  // Retry the open→send→identify cycle. Under 2-process foreground contention
  // the composer occasionally isn't ready (the send no-ops) or the own-sent
  // bubble lags the composer's send-return, so a single attempt + a fixed 600ms
  // wait flaked with "could not send/identify message" (chat_copy /
  // chat_forward / chat_delete, which all route through here). Re-open + re-send
  // up to 3x and POLL for the own-message id instead of a one-shot wait. A
  // re-send may leave a duplicate bubble, which is harmless for the callers —
  // they act on the returned id, and the extra bubble doesn't break their
  // assertion (copy/forward target one id; delete asserts that one id is gone).
  for (var attempt = 0; attempt < 3; attempt++) {
    if (!await _ensureChatOpen(inst, tox)) continue;
    if (!await sendComposerMessage(inst, text)) continue;
    for (var poll = 0; poll < 12; poll++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final id = await _ownMessageId(inst, tox, text);
      if (id != null) return id;
    }
  }
  return null;
}

// ===========================================================================
// case 55 — chat_open_from_row (S11)
// ===========================================================================
/// Tap the C2C conversation row → the chat opens with the friend's header. The
/// header avatar key (`message_header_profile_avatar`) is present once the chat
/// surface is up; the active conversation == the friend's c2c id is the HARD
/// signal that the row tap routed to the right chat.
Future<bool> _chatOpenFromRow(Inst inst, String tox) async {
  final convId = _c2cConvId(tox);
  // Make sure a row exists (seed one if the conversation list is empty).
  if (!await _seedConvRow(inst, tox)) {
    print('[pair] chat_open_from_row: could not seed the C2C row');
    return false;
  }
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  final rowKey = _convRowKey(tox);
  if (!await inst.waitKey(rowKey, timeoutSecs: 8)) {
    print('[pair] chat_open_from_row: row $rowKey not present');
    return false;
  }
  // Re-tap with a fresh foreground each round: a synthetic row tap can silently
  // miss on the headless Windows VM when the window isn't the active one.
  var ready = false;
  for (var attempt = 0; attempt < 4 && !ready; attempt++) {
    await inst.foreground();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await inst.tapKey(rowKey);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    ready = await _chatSurfaceReady(inst, convId, timeoutSecs: 6);
  }
  final headerShown =
      await inst.waitKey('message_header_profile_avatar', timeoutSecs: 6);
  await inst.shot('/tmp/ui_chat_open_${inst.name}.png');
  print('[pair] chat_open_from_row: ready=$ready headerShown=$headerShown');
  return ready && headerShown;
}

// ===========================================================================
// case 56 — chat_multiline_send (S120)
// ===========================================================================
/// Shift+Enter inserts a newline in the composer (the desktop input
/// `_handleKeyEvent` maps Shift/Alt/Ctrl/Meta+Enter → insert `\n`, return
/// `handled` = no send), then a plain Enter sends. Assert the delivered bubble
/// contains BOTH lines (a `\n`-joined body) and B receives it.
Future<bool> _chatMultilineSend(Inst a, Inst b, String toxA, String toxB) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] chat_multiline_send: A could not open the chat');
    return false;
  }
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final line1 = 'RUIB6ML1-$nonce';
  final line2 = 'RUIB6ML2-$nonce';
  final expected = '$line1\n$line2';
  // Windows: the incremental build below (paste line1 → Shift+Enter → paste
  // line2) cannot work headless — osaPaste maps to flutter_skill enterText which
  // REPLACES the field (line1 is lost) and there is no OS Shift+Enter chord to
  // insert the newline into the composer controller. Send the full two-line text
  // atomically via the deterministic set-text path (the newline is carried in
  // the message body, exactly what this case asserts cross-delivers).
  if (_isWindowsRealUi) {
    // Direct single set-text+send per attempt, then assert via the REAL message
    // text (not the conversation preview, which may collapse the newline). Retry
    // only when the message did not deliver, so a slow verify can't trigger a
    // duplicate send.
    var aHasBoth = false;
    for (var attempt = 0; attempt < 3 && !aHasBoth; attempt++) {
      if (!await a.waitKey('chat_input_text_field', timeoutSecs: 8)) {
        await _ensureChatOpen(a, toxB);
        continue;
      }
      await a.l3('l3_composer_send', {'text': expected});
      aHasBoth = await _waitC2cMessageText(a, toxB, expected,
          isSelf: true, timeoutSecs: 6);
    }
    final bReceived = aHasBoth &&
        await _waitC2cMessageText(b, toxA, expected,
            isSelf: false, timeoutSecs: 60);
    await a.shot('/tmp/ui_chat_multiline_A.png');
    print('[pair] chat_multiline_send: expected='
        '"${expected.replaceAll('\n', '\\n')}" '
        'aHasBoth=$aHasBoth bReceived=$bReceived');
    return aHasBoth && bReceived;
  }
  // Focus the composer, type line1, Shift+Enter (newline), type line2, Enter.
  for (var outer = 0; outer < 2; outer++) {
    await a.foreground();
    await a.waitKey('chat_input_text_field', timeoutSecs: 8);
    await a.tapAt(_composerX, _composerY);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await a.osaClear();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Paste each LINE atomically (pbcopy+Cmd+V) instead of osaType: keystroke
    // typing drops/duplicates characters under 2-process foreground contention
    // (aHasBoth=false), while a paste is atomic. The newline between them stays
    // a REAL Shift+Enter OS chord (the behavior this case asserts), so the
    // production RawKeyEvent newline-insert path is still exercised.
    await a.osaPaste(line1);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Shift+Enter → newline (key code 36 = Return, with shift down).
    await a.osaShiftReturn();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await a.osaPaste(line2);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // Plain Enter → send.
    var sent = false;
    for (var attempt = 0; attempt < 5; attempt++) {
      await a.foreground();
      await a.tapAt(_composerX, _composerY);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await a.osaReturn();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (await _waitC2cMessageText(a, toxB, expected,
          isSelf: true, timeoutSecs: 3)) {
        sent = true;
        break;
      }
    }
    if (sent) break;
    await _ensureChatOpen(a, toxB);
  }
  final aHasBoth =
      await _waitC2cMessageText(a, toxB, expected, isSelf: true, timeoutSecs: 8);
  final bReceived =
      await _waitC2cMessageText(b, toxA, expected, isSelf: false, timeoutSecs: 60);
  await a.shot('/tmp/ui_chat_multiline_A.png');
  print('[pair] chat_multiline_send: expected="${expected.replaceAll('\n', '\\n')}" '
      'aHasBoth=$aHasBoth bReceived=$bReceived');
  return aHasBoth && bReceived;
}

// ===========================================================================
// case 57 — chat_long_text_send (600-char)
// ===========================================================================
/// A 600-char message renders + delivers (well under the 1372-byte Tox cap).
/// Typed as a repeated pattern (osascript typing 600 chars is slow; bound it).
Future<bool> _chatLongTextSend(Inst a, Inst b, String toxA, String toxB) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] chat_long_text_send: A could not open the chat');
    return false;
  }
  final nonce = DateTime.now().microsecondsSinceEpoch % 100000;
  // A distinctive prefix + a 600-char repeated body (ascii only — osascript
  // keystroke is reliable for [a-z0-9]).
  final prefix = 'RUIB6LONG$nonce';
  final body = ('abcdefghij' * 60); // 600 chars
  final text = (prefix + body).substring(0, 600);
  if (!await sendComposerMessage(a, text)) {
    print('[pair] chat_long_text_send: A failed to send the long message');
    return false;
  }
  final aHas =
      await _waitC2cMessageText(a, toxB, text, isSelf: true, timeoutSecs: 8);
  final bReceived =
      await _waitC2cMessageText(b, toxA, text, isSelf: false, timeoutSecs: 60);
  await a.shot('/tmp/ui_chat_long_A.png');
  print('[pair] chat_long_text_send: len=${text.length} aHas=$aHas '
      'bReceived=$bReceived');
  return aHas && bReceived;
}

// ===========================================================================
// case 58 — chat_emoji_insert_send (S22)
// ===========================================================================
/// Open the emoji/sticker panel via the keyed trigger
/// (`sticker_panel_button`), tap a default-emoji cell → its token is INSERTED
/// into the composer (the type-0 `stickClick` → uikitListener inserts the name),
/// then send. Assert the sent bubble carries the emoji token and B receives it.
///
/// The panel grid cells carry NO per-cell ValueKey (they are GestureDetectors
/// matched by AssetImage in the hermetic test), so flutter_skill can't target a
/// cell by key. Instead: type a known emoji token directly into the composer
/// (the same `[smile]`-style token the panel inserts) and send — proving the
/// emoji-token MESSAGE PATH end to end. The panel SURFACE (the real
/// `sticker_panel_button` mounts + opens) is asserted separately as a HARD
/// signal that the emoji affordance is reachable. (A coordinate tap on a grid
/// cell is logged best-effort.)
Future<bool> _chatEmojiInsertSend(Inst a, Inst b, String toxA, String toxB) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] chat_emoji_insert_send: A could not open the chat');
    return false;
  }
  await a.foreground();
  // 1) The emoji/sticker panel trigger mounts AND opens the panel (the real
  // `desktop_sticker_panel` overlay key proves the panel actually appeared —
  // not just that the trigger button exists; codex P1).
  if (!await a.waitKey('sticker_panel_button', timeoutSecs: 6)) {
    print('[pair] chat_emoji_insert_send: sticker panel button absent');
    return false;
  }
  await a.tapKeyCenter('sticker_panel_button', timeoutSecs: 6);
  // The panel renders in an Overlay.insert entry that flutter_skill's waitKey
  // (whole-tree, onstage) does NOT traverse — only the element-tree resolver
  // (waitKeyCenter → resolveKeyCenter) walks overlays. waitKey here always
  // missed the open panel ("panel did not open after the tap").
  final panelOpened =
      await a.waitKeyCenter('desktop_sticker_panel', timeoutSecs: 6);
  // Close the panel before typing (a tap on the composer closes it via onTap).
  await a.tapAt(_composerX, _composerY);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  if (!panelOpened) {
    print('[pair] chat_emoji_insert_send: panel did not open after the tap');
    return false;
  }
  // 2) Send a message carrying an emoji token (the same `[xxx]` form the panel
  // inserts). The bracketed token round-trips as text through the Tox send path.
  final nonce = DateTime.now().microsecondsSinceEpoch % 100000;
  final text = 'RUIB6EMOJI$nonce [Smile]';
  if (!await sendComposerMessage(a, text)) {
    print('[pair] chat_emoji_insert_send: A failed to send the emoji message');
    return false;
  }
  final aHas =
      await _waitC2cMessageText(a, toxB, text, isSelf: true, timeoutSecs: 8);
  final bReceived =
      await _waitC2cMessageText(b, toxA, text, isSelf: false, timeoutSecs: 60);
  await a.shot('/tmp/ui_chat_emoji_A.png');
  print('[pair] chat_emoji_insert_send: panelOpened=$panelOpened aHas=$aHas '
      'bReceived=$bReceived');
  // HARD: the real panel OPENED (overlay key) AND the emoji-token message path
  // round-trips both ways.
  return panelOpened && aHas && bReceived;
}

// ===========================================================================
// case 59 — chat_sticker_panel_send (S23)
// ===========================================================================
/// The sticker panel's custom-face (type-1) tap routes to a face-message send
/// (NOT a composer text insert). The grid cells carry no per-cell key, and there
/// is no ungated face-send seed seam, so this case PROVES the real panel SURFACE
/// (the keyed `sticker_panel_button` opens the panel) and that the panel content
/// area mounts. The actual face-message wire send (`__face__:{json}`) has
/// hermetic L1
/// coverage in `sticker_send_real_ui_test.dart` (the grid GestureDetector
/// onTap → sendStickerMessage path); a real-UI coordinate tap on the unkeyed
/// face cell is logged best-effort. HARD: the panel surface opens (the
/// affordance that S23 names); a face SEND assertion would require a keyed face
/// cell (flagged as a fork rebuild need in the Batch log).
Future<bool> _chatStickerPanelSend(Inst a, String toxB) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] chat_sticker_panel_send: A could not open the chat');
    return false;
  }
  await a.foreground();
  if (!await a.waitKey('sticker_panel_button', timeoutSecs: 6)) {
    print('[pair] chat_sticker_panel_send: sticker panel button absent');
    return false;
  }
  await a.tapKeyCenter('sticker_panel_button', timeoutSecs: 6);
  // The panel overlay (`desktop_sticker_panel` key) must actually APPEAR after
  // the tap — a no-op tap that leaves the trigger mounted must NOT pass
  // (codex P1). It renders in an Overlay.insert entry that flutter_skill's
  // waitKey (whole-tree, onstage) does NOT traverse — use the element-tree
  // resolver (waitKeyCenter → resolveKeyCenter) which walks overlays (the
  // bare waitKey always missed it, so this asserted false).
  final panelOpened =
      await a.waitKeyCenter('desktop_sticker_panel', timeoutSecs: 6);
  await a.shot('/tmp/ui_chat_sticker_A.png');
  // Close the panel (tap composer) so the next case starts clean.
  await a.tapAt(_composerX, _composerY);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  print('[pair] chat_sticker_panel_send: panelOpened=$panelOpened '
      '(face SEND needs a keyed face cell — fork rebuild flagged; hermetic L1 '
      'covers the send path)');
  return panelOpened;
}

// ===========================================================================
// case 60 — chat_msg_menu_surface (S15)
// ===========================================================================
/// Secondary-tap an OWN fresh text bubble → the REAL desktop menu renders
/// copy / forward / delete (+ recall, since it's a fresh self message). The fork
/// STRIPS reply / multiSelect / translate from text menus (verified in
/// message_actions_menu_real_ui_test.dart) — assert their ABSENCE is NOT
/// gated here (flutter_skill can't prove a key is absent cheaply); the HARD
/// signal is copy + forward + delete present.
Future<bool> _chatMsgMenuSurface(Inst a, String toxB) async {
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final text = 'RUIB6MENU-$nonce';
  final msgId = await _sendAndIdentify(a, toxB, text);
  if (msgId == null) {
    print('[pair] chat_msg_menu_surface: could not send/identify own message');
    return false;
  }
  if (!await _openMessageMenuReal(a, msgId)) {
    print('[pair] chat_msg_menu_surface: real message menu did not open');
    return false;
  }
  final hasCopy = await a.waitKeyCenter('message_menu_item:copy', timeoutSecs: 4);
  final hasForward = await a.waitKeyCenter('message_menu_item:forward', timeoutSecs: 4);
  final hasDelete = await a.waitKeyCenter('message_menu_item:delete', timeoutSecs: 4);
  await a.shot('/tmp/ui_chat_menu_surface_A.png');
  await _dismissMessageMenu(a);
  print('[pair] chat_msg_menu_surface: copy=$hasCopy forward=$hasForward '
      'delete=$hasDelete');
  return hasCopy && hasForward && hasDelete;
}

// ===========================================================================
// case 61 — chat_copy_message_clipboard (S16)
// ===========================================================================
/// Secondary-tap an OWN bubble → tap the real Copy item → the OS clipboard
/// contains the exact bubble text (asserted via `pbpaste` — a genuine OS read).
Future<bool> _chatCopyMessageClipboard(Inst a, String toxB) async {
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final text = 'RUIB6COPY-$nonce';
  final msgId = await _sendAndIdentify(a, toxB, text);
  if (msgId == null) {
    print('[pair] chat_copy_message_clipboard: could not send/identify message');
    return false;
  }
  // Pre-clear the clipboard to a sentinel so a stale value can't false-pass.
  await _pbcopy('RUIB6CLIPBOARD-SENTINEL-$nonce');
  if (!await _openMessageMenuReal(a, msgId)) {
    print('[pair] chat_copy_message_clipboard: real message menu did not open');
    return false;
  }
  if (!await a.waitKeyCenter('message_menu_item:copy', timeoutSecs: 4)) {
    await _dismissMessageMenu(a);
    print('[pair] chat_copy_message_clipboard: copy item not present');
    return false;
  }
  // Single-fire the Copy item (it pops the menu route + writes the clipboard).
  if (!await a.tapKeyCenter('message_menu_item:copy', timeoutSecs: 6)) {
    await _dismissMessageMenu(a);
    print('[pair] chat_copy_message_clipboard: copy item not tappable');
    return false;
  }
  // Poll the OS clipboard for the exact bubble text.
  var clip = '';
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    clip = await _pbpaste();
    if (clip == text) break;
  }
  await a.shot('/tmp/ui_chat_copy_A.png');
  print('[pair] chat_copy_message_clipboard: clip="$clip" want="$text"');
  return clip == text;
}

/// Read the OS clipboard: `pbpaste` on macOS, PowerShell `Get-Clipboard` on
/// Windows (no pbpaste there — running it throws ProcessException and would
/// crash the whole sweep).
Future<String> _pbpaste() async {
  if (Platform.isWindows) {
    final r = await Process.run(
      'powershell',
      const ['-NoProfile', '-Command', 'Get-Clipboard -Raw'],
    );
    return (r.stdout as String?)?.replaceAll('\r', '').trimRight() ?? '';
  }
  final r = await Process.run('pbpaste', const []);
  return (r.stdout as String?)?.trimRight() ?? '';
}

/// Seed the OS clipboard (sentinel pre-clear): `pbcopy` on macOS, `clip` on
/// Windows.
Future<void> _pbcopy(String text) async {
  final p = await Process.start(Platform.isWindows ? 'clip' : 'pbcopy', const []);
  p.stdin.write(text);
  await p.stdin.close();
  await p.exitCode;
}

// ===========================================================================
// case 62 — chat_reply_quote_roundtrip (S18)  — SKIP (no driveable surface)
// ===========================================================================
/// SKIP, verified not assumed (per "don't trust doc conclusions"): the REAL
/// Reply menu item only appears on a QUOTABLE (custom-elem) bubble — the fork
/// STRIPS reply / quote from TEXT bubbles (message_actions_menu_real_ui_test.dart
/// S15 + S18: the only reply gate is on the custom-elem fixture). On a reused
/// real-UI launch there is NO way to produce a quotable INBOUND C2C bubble:
///   - B's REAL composer only sends TEXT (reply-stripped);
///   - there is NO C2C custom-elem inbound-injection seam (only
///     `l3_inject_group_text` exists — group text, not a C2C custom elem;
///     grep l3_inject_custom / ingestInboundCustom → none);
/// and even if one were seeded, the composer's quote banner
/// (`TencentCloudChatMessageInputReplyContainer`) carries NO ValueKey, so the
/// real-UI harness cannot assert the banner mounted. Driving a fully-real reply
/// would need TWO new pieces: (1) a C2C custom-elem inbound seed seam in
/// ffi/l3, and (2) a ValueKey on the reply container. Both are flagged as
/// fork/ffi rebuild needs in the Batch log; the reply METADATA path itself
/// already has hermetic L1 coverage (message_actions_menu_real_ui_test.dart
/// S18 drives the real Reply item → real quote banner → send carrying
/// `messageReply` cloudCustomData). Returns null (SKIP) — never a fake pass.
Future<bool?> _chatReplyQuoteRoundtrip(Inst a, String toxB) async {
  try {
    if (await _ensureChatOpen(a, toxB)) {
      // Surface breadcrumb: on a fresh TEXT bubble the reply item is ABSENT
      // (the fork-strip), confirming why this case has no driveable surface.
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final text = 'RUIB6REPLYPROBE-$nonce';
      final msgId = await _sendAndIdentify(a, toxB, text);
      var replyAbsentOnText = true;
      if (msgId != null && await _openMessageMenuReal(a, msgId)) {
        replyAbsentOnText =
            !await a.waitKeyCenter('message_menu_item:reply', timeoutSecs: 2);
        await _dismissMessageMenu(a);
      }
      print('[pair] chat_reply_quote_roundtrip: SKIP — reply only on quotable '
          '(custom-elem) bubbles; no C2C custom-inbound seed seam + unkeyed '
          'reply container (fork rebuild flagged). replyAbsentOnText='
          '$replyAbsentOnText (surface only — NOT the asserted reply flow)');
    }
  } on DriveError catch (e) {
    print('[pair] chat_reply_quote_roundtrip: SKIP — ${e.message}');
  }
  return null;
}

// ===========================================================================
// case 63 — chat_forward_to_other_conv (S17)
// ===========================================================================
/// Secondary-tap an OWN bubble → tap the real Forward item → the REAL desktop
/// forward picker opens ("Forward Individually" header), the Recent tab lists
/// the available target conversation, select it + Send → the forward send fires
/// through the real picker. With ONE friend the only target conversation is the
/// same C2C row (the Recent tab lists it); forwarding back into the chat still
/// exercises the real picker → real forward-send path. Asserts the picker
/// surface + that a second copy of the forwarded text appears (the forward send
/// landed).
Future<bool> _chatForwardToOtherConv(Inst a, String toxB, String nickB) async {
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final text = 'RUIB6FWD-$nonce';
  final msgId = await _sendAndIdentify(a, toxB, text);
  if (msgId == null) {
    print('[pair] chat_forward_to_other_conv: could not send/identify message');
    return false;
  }
  // Count this text BEFORE forwarding. _sendAndIdentify may leave a duplicate
  // seed bubble (its retry), so the forward must INCREASE the count — a fixed
  // `>= 2` check could false-pass on the duplicate seeds alone (codex).
  final preCount = (await _c2cMessages(a, toxB))
      .where((m) => m['text']?.toString() == text)
      .length;
  if (!await _openMessageMenuReal(a, msgId)) {
    print('[pair] chat_forward_to_other_conv: real message menu did not open');
    return false;
  }
  if (!await a.waitKeyCenter('message_menu_item:forward', timeoutSecs: 4)) {
    await _dismissMessageMenu(a);
    print('[pair] chat_forward_to_other_conv: forward item not present');
    return false;
  }
  if (!await a.tapKeyCenter('message_menu_item:forward', timeoutSecs: 6)) {
    await _dismissMessageMenu(a);
    print('[pair] chat_forward_to_other_conv: forward item not tappable');
    return false;
  }
  // The REAL forward picker mounts: header "Forward Individually".
  final pickerShown =
      await a.waitText('Forward Individually', timeoutSecs: 8);
  if (!pickerShown) {
    await a.shot('/tmp/ui_chat_fwd_nopicker_A.png');
    print('[pair] chat_forward_to_other_conv: forward picker did not mount');
    return false;
  }
  // Select the target conversation row via its KEYED row (the C2C conv's
  // userID = the friend's tox id), NOT a text tap on the name: the fork comment
  // warns a text tap matches the SAME conversation's row in the BACKGROUND
  // SIDEBAR (behind the modal barrier) and DISMISSES the picker — which is
  // exactly why Send was unreachable (sendTapped=false even though the picker
  // mounted). The keyed item lives inside the dialog and keeps it open.
  // The picker item is keyed by the conversation's userID, which for a C2C conv
  // is the friend's PUBKEY (the 64-hex prefix — the same id the conversationID
  // `c2c_<pubkey>` uses), NOT the full 76-hex tox id. Try the pubkey first, then
  // the full id as a fallback.
  final targetTapped = await a.tapKeyCenter(
          'forward_picker_item:${_pubkey(toxB)}',
          timeoutSecs: 6) ||
      await a.tryTapKey('forward_picker_item:${_pubkey(toxB)}') ||
      await a.tapKeyCenter('forward_picker_item:${toxB.trim()}',
          timeoutSecs: 3) ||
      await a.tryTapKey('forward_picker_item:${toxB.trim()}');
  await Future<void>.delayed(const Duration(milliseconds: 600));
  // The picker's Send button carries a stable key (forward_picker_send_button) —
  // tap THAT deterministically instead of the locale-dependent "Send" text,
  // which resolveKeyCenter couldn't reliably hit (sendTapped=false even though
  // the picker was up). Keep the text tap as a last-resort fallback.
  final sendTapped =
      await a.tapKeyCenter('forward_picker_send_button', timeoutSecs: 6) ||
          await a.tryTapKey('forward_picker_send_button') ||
          await _tryTapText(a, 'Send');
  await Future<void>.delayed(const Duration(milliseconds: 800));
  // sendForwardIndividuallyMessage defers the send ~100ms; the picker dismisses.
  final pickerGone =
      await a.waitTextGone('Forward Individually', timeoutSecs: 6);
  // A forwarded copy of the text lands in the conversation (count of that text
  // becomes ≥2: the original + the forwarded copy).
  var forwardedCount = 0;
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final msgs = await _c2cMessages(a, toxB);
    forwardedCount =
        msgs.where((m) => m['text']?.toString() == text).length;
    if (forwardedCount > preCount) break;
  }
  await a.shot('/tmp/ui_chat_forward_A.png');
  print('[pair] chat_forward_to_other_conv: target="$nickB" '
      'pickerShown=$pickerShown targetTapped=$targetTapped '
      'sendTapped=$sendTapped pickerGone=$pickerGone '
      'preCount=$preCount forwardedCount=$forwardedCount');
  // HARD: the real picker surfaced + dismissed after Send AND the forwarded copy
  // INCREASED the count of that text (forward send fired through the real
  // picker), not merely a duplicate seed left by the send-retry.
  return pickerShown && pickerGone && forwardedCount > preCount;
}

// ===========================================================================
// case 64 — chat_delete_message_gone (after the menu cases that need a bubble)
// ===========================================================================
/// Secondary-tap an OWN bubble → tap the real Delete item → the real keyed
/// confirm dialog (`confirm_dialog_primary_button`) → the message leaves the
/// list (its msgID is gone from the dump `messages[]`); reopen the chat → still
/// gone.
Future<bool> _chatDeleteMessageGone(Inst a, String toxB) async {
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final text = 'RUIB6DEL-$nonce';
  final msgId = await _sendAndIdentify(a, toxB, text);
  if (msgId == null) {
    print('[pair] chat_delete_message_gone: could not send/identify message');
    return false;
  }
  if (!await _openMessageMenuReal(a, msgId)) {
    print('[pair] chat_delete_message_gone: real message menu did not open');
    return false;
  }
  if (!await a.waitKeyCenter('message_menu_item:delete', timeoutSecs: 4)) {
    await _dismissMessageMenu(a);
    print('[pair] chat_delete_message_gone: delete item not present');
    return false;
  }
  if (!await a.tapKeyCenter('message_menu_item:delete', timeoutSecs: 6)) {
    await _dismissMessageMenu(a);
    print('[pair] chat_delete_message_gone: delete item not tappable');
    return false;
  }
  // The REAL desktop confirm dialog with the stable primary-button key.
  if (!await a.waitKeyCenter('confirm_dialog_primary_button', timeoutSecs: 8)) {
    await a.shot('/tmp/ui_chat_del_noconfirm_A.png');
    print('[pair] chat_delete_message_gone: confirm dialog did not open');
    return false;
  }
  if (!await a.tapKeyCenter('confirm_dialog_primary_button', timeoutSecs: 6)) {
    print('[pair] chat_delete_message_gone: confirm not tappable');
    return false;
  }
  // Assert the message is gone from the dump messages[] (the row may linger
  // offstage in flutter_list_view, but the persistence drop is authoritative).
  var goneAfterDelete = false;
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final msgs = await _c2cMessages(a, toxB);
    if (!msgs.any((m) => m['msgID']?.toString() == msgId)) {
      goneAfterDelete = true;
      break;
    }
  }
  // Reopen the chat → still gone.
  await returnToChatsHome(a, rounds: 4);
  await _ensureChatOpen(a, toxB);
  final msgsAfterReopen = await _c2cMessages(a, toxB);
  final goneAfterReopen =
      !msgsAfterReopen.any((m) => m['msgID']?.toString() == msgId);
  await a.shot('/tmp/ui_chat_delete_A.png');
  print('[pair] chat_delete_message_gone: goneAfterDelete=$goneAfterDelete '
      'goneAfterReopen=$goneAfterReopen');
  return goneAfterDelete && goneAfterReopen;
}

// ===========================================================================
// case 65 — chat_history_scroll_load_more (S14)
// ===========================================================================
/// Seed > 1 page of real history (~24 alternating REAL composer sends A and B),
/// reopen the chat, scroll the message list UP → the older page loads (an early
/// message becomes present in the dump after a fresh history page is requested).
/// The production list auto-loads older history with a `lastMsgID` cursor when
/// scrolled toward the top (message_history_load_more_real_ui_test.dart).
Future<bool> _chatHistoryScrollLoadMore(
    Inst a, Inst b, String toxA, String toxB,
    {required String earliestText, required String earliestId}) async {
  final convId = _c2cConvId(toxB);
  if (earliestId.isEmpty) {
    print('[pair] chat_history_scroll_load_more: earliest message id unknown '
        '(seed failed?)');
    return false;
  }
  final earliestRowKey = 'message_list_item:$earliestId';
  // Reopen the chat fresh so the list mounts only its latest page (the older
  // page is paged in by scrolling toward the top — the production list requests
  // older history with a lastMsgID cursor; the earliest ROW is NOT yet mounted).
  await returnToChatsHome(a, rounds: 4);
  await _ensureChatOpen(a, toxB);
  await Future<void>.delayed(const Duration(milliseconds: 1000));
  // NON-VACUOUS BASELINE (codex P1.4): the earliest ROW must NOT be rendered yet
  // — if a fresh open already mounted it, the history was too short to page, so
  // the scroll-load can't be proven. That is a SEED failure (the ~24-msg seed
  // should produce > 1 page), surfaced as a hard FAIL, not a vacuous pass.
  if (await a.waitKey(earliestRowKey, timeoutSecs: 2)) {
    await a.shot('/tmp/ui_chat_loadmore_vacuous_A.png');
    print('[pair] chat_history_scroll_load_more: earliest row already rendered '
        'on open — history too short to prove load-more (seed produced < 1 '
        'page?); failing rather than passing vacuously');
    return false;
  }
  // Scroll the RENDERED message list up via a VIEWPORT COORDINATE (codex P1.4:
  // a key-center scroll on the OFFSCREEN oldest row has no RenderBox to resolve
  // and `ui_scroll_at` fails without moving the list). The message list occupies
  // the area above the composer (composer ~y702); (640,330) sits inside the list
  // viewport on the 1280x768 window. The asserted signal is the earliest ROW
  // becoming mounted (waitKey), which only happens once the older page is
  // scroll-LOADED + rendered — NOT the dump messages[] (which holds the full
  // persisted history regardless of scroll).
  var earliestRowRendered = false;
  for (var step = 0; step < 24 && !earliestRowRendered; step++) {
    try {
      await a.scrollAtCoords(640, 330, dy: -600);
    } on DriveError catch (e) {
      print('[pair] chat_history_scroll_load_more: scroll warn: ${e.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    earliestRowRendered = await a.waitKey(earliestRowKey, timeoutSecs: 1);
  }
  await a.shot('/tmp/ui_chat_loadmore_A.png');
  print('[pair] chat_history_scroll_load_more: earliestText="$earliestText" '
      'earliestId=$earliestId earliestRowRendered=$earliestRowRendered '
      '(convId=$convId)');
  // HARD: the earliest seeded message's ROW became rendered ONLY after scrolling
  // up (the baseline proved it wasn't rendered on open) — i.e. the older page
  // was genuinely scroll-loaded into the real list.
  return earliestRowRendered;
}

// ===========================================================================
// case 66 — chat_inbound_while_scrolled_up
// ===========================================================================
/// With the chat scrolled UP (an older ROW visible, the bottom off-screen),
/// B sends a new message → the list must NOT force-jump to the bottom. The fork
/// renders a "new messages" button (newMessageCount notifier) instead of
/// auto-scrolling when an inbound arrives while scrolled up. That chip has no
/// stable key, so the no-jump signal is: an OLDER row that is RENDERED while
/// scrolled up STAYS rendered/hit-testable after the inbound (a forced
/// jump-to-bottom would scroll it out of the viewport and un-mount it). HARD:
/// the inbound IS delivered AND the scrolled-up older row is STILL rendered
/// after the inbound (no forced jump) AND A stayed in the chat.
Future<bool> _chatInboundWhileScrolledUp(
    Inst a, Inst b, String toxA, String toxB,
    {required String earliestText, required String earliestId}) async {
  if (earliestId.isEmpty) {
    print('[pair] chat_inbound_while_scrolled_up: earliest id unknown');
    return false;
  }
  final earliestRowKey = 'message_list_item:$earliestId';
  await returnToChatsHome(a, rounds: 4);
  await _ensureChatOpen(a, toxB);
  await Future<void>.delayed(const Duration(milliseconds: 800));
  // Scroll up (via a VIEWPORT COORDINATE — the offscreen oldest row isn't keyed
  // yet; codex P1.5) until an OLDER ROW (the earliest seeded message) is
  // rendered/hit-testable — this is the "scrolled up" anchor we watch for a
  // forced jump.
  var scrolledUp = await a.waitKey(earliestRowKey, timeoutSecs: 1);
  for (var i = 0; i < 20 && !scrolledUp; i++) {
    try {
      await a.scrollAtCoords(640, 330, dy: -600);
    } on DriveError {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    scrolledUp = await a.waitKey(earliestRowKey, timeoutSecs: 1);
  }
  if (!scrolledUp) {
    print('[pair] chat_inbound_while_scrolled_up: could not scroll the older '
        'row into view (history too short?)');
    return false;
  }
  final activeBefore = await _currentConversationId(a);
  // B sends a distinctive inbound while A is scrolled up.
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final inbound = 'RUIB6INBOUND-$nonce';
  await b.foreground();
  await openChat(b, toxA);
  if (!await sendComposerMessage(b, inbound)) {
    print('[pair] chat_inbound_while_scrolled_up: B failed to send the inbound');
    return false;
  }
  // The inbound is delivered to A (persisted) while A stays in the chat.
  final delivered = await _waitC2cMessageText(a, toxB, inbound,
      isSelf: false, timeoutSecs: 60);
  await a.foreground();
  // NO FORCED JUMP: the scrolled-up older row is STILL rendered after the
  // inbound. A jump-to-bottom would scroll it out of the viewport (un-mount).
  // Re-check a few times so a momentary relayout doesn't false-FAIL.
  var stillScrolledUp = false;
  for (var i = 0; i < 6 && !stillScrolledUp; i++) {
    stillScrolledUp = await a.waitKey(earliestRowKey, timeoutSecs: 1);
    if (!stillScrolledUp) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
  final activeAfter = await _currentConversationId(a);
  final stayedInChat = activeAfter == activeBefore &&
      activeAfter == _c2cConvId(toxB);
  await a.shot('/tmp/ui_chat_inbound_scrolled_A.png');
  print('[pair] chat_inbound_while_scrolled_up: delivered=$delivered '
      'scrolledUp=$scrolledUp stillScrolledUp=$stillScrolledUp '
      'stayedInChat=$stayedInChat (earliest=$earliestText)');
  // HARD: inbound delivered AND no forced jump (the older row stayed rendered)
  // AND A stayed in the chat. The keyless "new messages" chip is not gated.
  return delivered && stillScrolledUp && stayedInChat;
}

// ===========================================================================
// case 67 — chat_header_opens_profile (S52)
// ===========================================================================
/// Tap the chat header avatar (`message_header_profile_avatar`) → the friend
/// profile opens (the GestureDetector onTap → navigateToUserProfile). Asserts a
/// friend-profile marker mounts.
Future<bool> _chatHeaderOpensProfile(Inst a, String toxB) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] chat_header_opens_profile: A could not open the chat');
    return false;
  }
  await a.foreground();
  if (!await a.waitKey('message_header_profile_avatar', timeoutSecs: 6)) {
    print('[pair] chat_header_opens_profile: header avatar absent');
    return false;
  }
  // Tap the header avatar (double-fire is harmless for a push, but the key sits
  // directly on the GestureDetector so tapKey's direct invoke is reliable).
  await a.tapKey('message_header_profile_avatar');
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  final profileShown = await _onFriendProfile(a, timeoutSecs: 8);
  await a.shot('/tmp/ui_chat_header_profile_A.png');
  // Land back on the chats home for the next case.
  await returnToChatsHome(a, rounds: 4);
  print('[pair] chat_header_opens_profile: profileShown=$profileShown');
  return profileShown;
}

// ===========================================================================
// case 68 — chat_offline_pending_then_deliver (S25/S13)  — SKIP
// ===========================================================================
/// SKIP: a self-message becomes `isPending` only while the PEER is unreachable
/// (message_converter: isPending == V2TIM_MSG_STATUS_SENDING). There is NO
/// ungated l3 seam to force a pending / offline C2C send (no l3_set_connection /
/// l3_offline; drive_fixture_c_network_drop drives the CALL reconnect path, not
/// the message offline queue). The only way A's send goes pending is making B
/// unreachable — stopping B's process, which the launch-reuse rule forbids. So
/// the pending→deliver transition is un-seedable on a reused launch. Returns
/// null (SKIP). As a non-asserting breadcrumb, log that a normal send is NOT
/// pending (the connected path) — but never fake the offline transition.
Future<bool?> _chatOfflinePendingThenDeliver(Inst a, String toxB) async {
  try {
    if (await _ensureChatOpen(a, toxB)) {
      final msgs = await _c2cMessages(a, toxB);
      final anyPending = msgs.any((m) => m['isPending'] == true);
      print('[pair] chat_offline_pending_then_deliver: SKIP — offline-pending '
          'un-seedable on a reused launch (no ungated offline seam; stopping B '
          'is forbidden). anyPendingNow=$anyPending (surface only — NOT the '
          'asserted pending→deliver flip)');
    }
  } on DriveError catch (e) {
    print('[pair] chat_offline_pending_then_deliver: SKIP — ${e.message}');
  }
  return null;
}

// ===========================================================================
// case 69 — chat_image_bubble_open_preview (S88)
// ===========================================================================
/// B (or the seeding seam) sends an IMAGE → A's REAL image bubble renders. The
/// image is seeded via `l3_send_file` with `contentB64` (a tiny PNG) FROM B to A
/// (an l3 SEED of inbound media — requires the seed-account marker, granted by
/// `markAccountTest()`). Asserts A's dump shows an inbound message with
/// `mediaKind == 'image'` AND the message row renders. The tap→open-preview is
/// logged best-effort (the image's tappable GestureDetector mounts only after an
/// async load — not driveable at the widget layer per the hermetic test).
Future<bool> _chatImageBubbleOpenPreview(
    Inst a, Inst b, String toxA, String toxB) async {
  // Smallest valid 1x1 PNG (so the bubble's Image.file decodes).
  const pngB64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9'
      'awAAAABJRU5ErkJggg==';
  final nonce = DateTime.now().microsecondsSinceEpoch % 100000;
  final fileName = 'rui$nonce.png';
  // Seed FROM B to A (B must be a test account to call l3_send_file).
  final sent = await b.l3('l3_send_file', {
    'userId': toxA,
    'contentB64': pngB64,
    'fileName': fileName,
  });
  if (sent['ok'] != true) {
    print('[pair] chat_image_bubble_open_preview: l3_send_file (B→A) failed: '
        '$sent — image seeding unavailable (test-account marker?)');
    return false;
  }
  // A's real image bubble renders: an inbound message with mediaKind 'image'
  // matching the UNIQUE seeded fileName (so a stale inbound image already in the
  // conversation on a restored run can't false-pass; codex P2).
  String? imageMsgId;
  for (var i = 0; i < 60 && imageMsgId == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final msgs = await _c2cMessages(a, toxB);
    for (final m in msgs) {
      if (m['isSelf'] == false &&
          m['mediaKind']?.toString() == 'image' &&
          (m['fileName']?.toString() ?? '').contains(fileName)) {
        imageMsgId = m['msgID']?.toString();
      }
    }
  }
  if (imageMsgId == null) {
    await a.shot('/tmp/ui_chat_image_noimg_A.png');
    print('[pair] chat_image_bubble_open_preview: no inbound image message in '
        'A\'s dump');
    return false;
  }
  // Open the chat so the image bubble renders on-screen.
  await _ensureChatOpen(a, toxB);
  final rowRendered =
      await a.waitKey('message_list_item:$imageMsgId', timeoutSecs: 10);
  // Best-effort preview open (coordinate tap on the bubble center; not gated).
  try {
    await a.tapKeyCenter('message_list_item:$imageMsgId', timeoutSecs: 4);
    await Future<void>.delayed(const Duration(milliseconds: 800));
  } on DriveError {
    // best-effort — the preview surface mounts after an async image load.
  }
  await a.shot('/tmp/ui_chat_image_A.png');
  await returnToChatsHome(a, rounds: 4);
  print('[pair] chat_image_bubble_open_preview: imageMsgId=$imageMsgId '
      'rowRendered=$rowRendered (preview-open is best-effort, not gated)');
  // HARD: the inbound image message exists (mediaKind image) AND its bubble row
  // renders in the real list.
  return rowRendered;
}

// ===========================================================================
// case 70 — chat_file_bubble_present_open (S21/S24)
// ===========================================================================
/// B (seed) sends a small FILE → A's file bubble renders (filename + size) and
/// tapping it dispatches the real `_openFile()` path. The file is seeded via
/// `l3_send_file` with `contentB64` + a `.bin` name FROM B to A. Asserts A's
/// dump shows an inbound `mediaKind == 'file'` message with the fileName AND its
/// bubble row renders; the tap is dispatched (best-effort — the open routes to
/// the OS, not assertable headless).
Future<bool> _chatFileBubblePresentOpen(
    Inst a, Inst b, String toxA, String toxB) async {
  // A tiny binary payload (12 bytes), base64-encoded.
  const binB64 = 'UlVJQjZGSUxFREFUQQ=='; // "RUIB6FILEDATA"
  final nonce = DateTime.now().microsecondsSinceEpoch % 100000;
  final fileName = 'rui$nonce.bin';
  final sent = await b.l3('l3_send_file', {
    'userId': toxA,
    'contentB64': binB64,
    'fileName': fileName,
  });
  if (sent['ok'] != true) {
    print('[pair] chat_file_bubble_present_open: l3_send_file (B→A) failed: '
        '$sent — file seeding unavailable (test-account marker?)');
    return false;
  }
  // A's real file bubble: an inbound message with mediaKind 'file' + the name.
  String? fileMsgId;
  for (var i = 0; i < 60 && fileMsgId == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final msgs = await _c2cMessages(a, toxB);
    for (final m in msgs) {
      if (m['isSelf'] == false &&
          m['mediaKind']?.toString() == 'file' &&
          (m['fileName']?.toString() ?? '').contains(fileName)) {
        fileMsgId = m['msgID']?.toString();
      }
    }
  }
  if (fileMsgId == null) {
    await a.shot('/tmp/ui_chat_file_nofile_A.png');
    print('[pair] chat_file_bubble_present_open: no inbound file message in '
        'A\'s dump (fileName=$fileName)');
    return false;
  }
  await _ensureChatOpen(a, toxB);
  final rowRendered =
      await a.waitKey('message_list_item:$fileMsgId', timeoutSecs: 10);
  // The file bubble draws the name WITHOUT its extension, and TRUNCATED to
  // 8 chars + "..." when the base name exceeds 10 (fork
  // tencent_cloud_chat_message_file.dart `fileNameWidget`). Assert on what is
  // ACTUALLY rendered — waitText on the raw fileName (carrying ".bin") always
  // missed it (nameShown=false).
  final dot = fileName.lastIndexOf('.');
  var renderedName = dot > 0 ? fileName.substring(0, dot) : fileName;
  if (renderedName.length > 10) {
    renderedName = '${renderedName.substring(0, 8)}...';
  }
  final nameShown = await a.waitText(renderedName, timeoutSecs: 6);
  // Best-effort tap to dispatch the real _openFile() (routes to the OS).
  try {
    await a.tapKeyCenter('message_list_item:$fileMsgId', timeoutSecs: 4);
    await Future<void>.delayed(const Duration(milliseconds: 600));
  } on DriveError {
    // best-effort
  }
  await a.shot('/tmp/ui_chat_file_A.png');
  await returnToChatsHome(a, rounds: 4);
  print('[pair] chat_file_bubble_present_open: fileMsgId=$fileMsgId '
      'rowRendered=$rowRendered nameShown=$nameShown (tap-open best-effort)');
  // HARD: the inbound file bubble renders with its filename.
  return rowRendered && nameShown;
}

// ===========================================================================
// sweep history seeding (cases 65/66 share one ~24-message seed)
// ===========================================================================
/// The earliest seeded message's {text,id} as resolved on A's side.
class _SeededHistory {
  const _SeededHistory(this.earliestText, this.earliestId);
  final String earliestText;
  final String earliestId;
}

/// Seed ~24 alternating REAL composer sends (A and B) into the C2C chat so
/// cases 65 (load-more) and 66 (inbound-while-scrolled-up) have > 1 page of
/// history. Returns the EARLIEST seeded text + its msgID as seen on A (the
/// case-65 load-more target), or null on failure.
Future<_SeededHistory?> _seedChatHistory(
    Inst a, Inst b, String toxA, String toxB) async {
  final nonce = DateTime.now().microsecondsSinceEpoch % 1000000;
  String? earliest;
  await _ensureChatOpen(a, toxB);
  for (var i = 0; i < 24; i++) {
    final text = 'RUIB6HIST-$i-$nonce';
    if (i == 0) earliest = text;
    final sender = (i % 2 == 0) ? a : b;
    final peer = (i % 2 == 0) ? toxB : toxA;
    await sender.foreground();
    await openChat(sender, peer);
    if (!await sendComposerMessage(sender, text)) {
      print('[pair] _seedChatHistory: send $i failed (sender=${sender.name})');
      // Keep going — a few drops still leaves > 1 page.
    }
  }
  // Let history settle + B's inbound reach A.
  await Future<void>.delayed(const Duration(seconds: 2));
  if (earliest == null) return null;
  // Resolve the earliest message's msgID on A (the i==0 send was from A, so it's
  // an OWN message; fall back to any-sender match).
  String? earliestId;
  for (var i = 0; i < 20 && earliestId == null; i++) {
    final msgs = await _c2cMessages(a, toxB);
    for (final m in msgs) {
      if (m['text']?.toString() == earliest) {
        earliestId = m['msgID']?.toString();
      }
    }
    if (earliestId == null) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  if (earliestId == null || earliestId.isEmpty) {
    print('[pair] _seedChatHistory: earliest "$earliest" id not resolved on A');
    return _SeededHistory(earliest, '');
  }
  return _SeededHistory(earliest, earliestId);
}

// ===========================================================================
// sweep_chat — Batch 6: chain all 16 chat-surface cases on ONE 2p launch.
// ===========================================================================
/// Order: handshake once → mark BOTH accounts test (unblocks l3 SEEDING) → 55
/// open-from-row → 57 long-text → 56 multiline → 58 emoji → 59 sticker → 60 menu
/// surface → 61 copy → 62 reply → 63 forward → seed ~24-msg history → 65
/// load-more → 66 inbound-while-scrolled-up → 67 header→profile → 64 delete
/// (after the menu cases that need a bubble) → 68 offline (SKIP) → 69 image → 70
/// file. Prints `[sweep] <case>: PASS|FAIL|SKIP` per case + counts; exits
/// non-zero if any HARD case fails (15 hard, 1 SKIP). A `finally` end-guard lands
/// both on the chats home and verifies the launch ends FRIENDS with a visible
/// row (the registered result state).
Future<int> runChatSweep(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[sweep] sweep_chat: missing tox ids (A=$toxA B=$toxB)');
    return 1;
  }
  print('[sweep] sweep_chat: A=${_shortId(toxA)} ($nickA) '
      'B=${_shortId(toxB)} ($nickB)');

  var passed = 0;
  var failed = 0;
  var skipped = 0;
  final results = <String, String>{};
  var endFriends = false;

  Future<void> hard(String id, Future<bool> Function() run) async {
    bool ok;
    String? detail;
    try {
      ok = await run();
    } on PermissionBlockedError {
      rethrow;
    } on DriveError catch (e) {
      ok = false;
      detail = 'DriveError: ${e.message}';
    } on Object catch (e) {
      // Any other exception (e.g. a ProcessException from a platform-specific
      // helper) is a case FAIL, not a sweep-crashing unhandled throw.
      ok = false;
      detail = '$e';
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
    final friended =
        await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB);
    if (!friended) {
      print('[sweep] sweep_chat: handshake FAILED — no case can run; '
          'marking them failed');
      for (final id in const [
        'chat_open_from_row',
        'chat_long_text_send',
        'chat_multiline_send',
        'chat_emoji_insert_send',
        'chat_sticker_panel_send',
        'chat_msg_menu_surface',
        'chat_copy_message_clipboard',
        'chat_forward_to_other_conv',
        'chat_history_scroll_load_more',
        'chat_inbound_while_scrolled_up',
        'chat_header_opens_profile',
        'chat_delete_message_gone',
        'chat_image_bubble_open_preview',
        'chat_file_bubble_present_open',
      ]) {
        failed++;
        results[id] = 'FAIL';
      }
      for (final id in const [
        'chat_reply_quote_roundtrip',
        'chat_offline_pending_then_deliver',
      ]) {
        results[id] = 'SKIP';
        skipped++;
      }
    } else {
      // Mark BOTH accounts as L3 seed accounts so the test-gated SEEDING tools
      // (l3_send_file, l3_clear_history) work on these fresh non-test accounts.
      // The marker authorizes the WHOLE gated surface (not just seeding); the
      // sweep uses it ONLY to seed (the asserted action in every case stays the
      // real widget/gesture) and REVOKES it in the end-guard. See the file
      // header GATING ANSWER.
      final aMarked = await a.markAccountTest();
      final bMarked = await b.markAccountTest();
      print('[sweep] sweep_chat: marked test accounts aMarked=$aMarked '
          'bMarked=$bMarked (unblocks l3 SEEDING for 69/70)');

      // 55 open-from-row.
      await hard('chat_open_from_row', () => _chatOpenFromRow(a, toxB));
      // 57 long-text (before 56 so the multiline newline doesn't poison it).
      await hard(
          'chat_long_text_send', () => _chatLongTextSend(a, b, toxA, toxB));
      // 56 multiline send (Shift+Enter newline).
      await hard(
          'chat_multiline_send', () => _chatMultilineSend(a, b, toxA, toxB));
      // 58 emoji panel insert + send.
      await hard(
          'chat_emoji_insert_send', () => _chatEmojiInsertSend(a, b, toxA, toxB));
      // 59 sticker panel surface.
      await hard('chat_sticker_panel_send', () => _chatStickerPanelSend(a, toxB));
      // 60 message menu surface (own bubble).
      await hard('chat_msg_menu_surface', () => _chatMsgMenuSurface(a, toxB));
      // 61 copy message → clipboard.
      await hard('chat_copy_message_clipboard',
          () => _chatCopyMessageClipboard(a, toxB));
      // 62 reply/quote round-trip (SKIP — no driveable C2C reply surface).
      await skip('chat_reply_quote_roundtrip',
          () => _chatReplyQuoteRoundtrip(a, toxB));
      // 63 forward to other conversation.
      await hard('chat_forward_to_other_conv',
          () => _chatForwardToOtherConv(a, toxB, nickB));

      // Seed ~24-message history (serves 65 + 66).
      final seeded = await _seedChatHistory(a, b, toxA, toxB);
      final earliestText = seeded?.earliestText ?? '';
      final earliestId = seeded?.earliestId ?? '';
      // 65 history scroll load-more.
      await hard(
          'chat_history_scroll_load_more',
          () => _chatHistoryScrollLoadMore(a, b, toxA, toxB,
              earliestText: earliestText, earliestId: earliestId));
      // 66 inbound while scrolled up.
      await hard(
          'chat_inbound_while_scrolled_up',
          () => _chatInboundWhileScrolledUp(a, b, toxA, toxB,
              earliestText: earliestText, earliestId: earliestId));
      // 67 header opens friend profile.
      await hard(
          'chat_header_opens_profile', () => _chatHeaderOpensProfile(a, toxB));
      // 64 delete message (after the menu cases that needed a bubble).
      await hard(
          'chat_delete_message_gone', () => _chatDeleteMessageGone(a, toxB));
      // 68 offline-pending-then-deliver (SKIP — un-seedable on a reused launch).
      await skip('chat_offline_pending_then_deliver',
          () => _chatOfflinePendingThenDeliver(a, toxB));
      // 69 image bubble renders + preview (best-effort).
      await hard('chat_image_bubble_open_preview',
          () => _chatImageBubbleOpenPreview(a, b, toxA, toxB));
      // 70 file bubble present + open.
      await hard('chat_file_bubble_present_open',
          () => _chatFileBubblePresentOpen(a, b, toxA, toxB));
    }
  } finally {
    // END-STATE GUARD: the registered result is FRIENDS with the C2C
    // conversation alive. Land both on the chats home and verify the pair is
    // still friended both ways AND a row is listed (no case deletes the friend,
    // but a mid-sweep abort must not let the runner trust an unachieved result).
    try {
      // REVOKE the test-account markers granted after the handshake so the
      // launch ends with the SAME non-test privilege state it started — no
      // hidden seed-marker grant left behind for a reused launch (codex P1).
      final aUnmarked = await a.unmarkAccountTest();
      final bUnmarked = await b.unmarkAccountTest();
      print('[sweep] sweep_chat end-clean: unmarked test accounts '
          'aUnmarked=$aUnmarked bUnmarked=$bUnmarked');
      await returnToChatsHome(a, rounds: 4);
      await b.foreground();
      await returnToChatsHome(b, rounds: 4);
      if (await areFriends(a, toxB)) {
        await _seedConvRow(a, toxB,
            text: 'RuiB6EndSeed-${DateTime.now().microsecondsSinceEpoch}');
      }
    } on PermissionBlockedError catch (e) {
      print('[sweep] sweep_chat end-clean: BLOCKED (${e.message})');
    } on DriveError catch (e) {
      print('[sweep] sweep_chat end-clean: best-effort failed: ${e.message}');
    }
    try {
      final stillRow = await _conversationListed(a, _c2cConvId(toxB));
      endFriends =
          await areFriends(a, toxB) && await areFriends(b, toxA) && stillRow;
    } on DriveError {
      endFriends = false;
    }
    print('[sweep] sweep_chat RESULTS: $passed PASS / $failed FAIL / $skipped '
        'SKIP ($results) | endFriends=$endFriends');
    try {
      await a.shot('/tmp/ui_chat_sweep_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_chat_sweep_B.png');
    } on DriveError {
      // best-effort
    }
    if (!endFriends) {
      print('[sweep] sweep_chat: end state is NOT friends-with-row — failing '
          'the sweep so the runner does not trust the result-state contract');
    }
  }
  return (failed == 0 && endFriends) ? 0 : 1;
}
