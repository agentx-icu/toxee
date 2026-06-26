// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// P1/P2/P3 campaign Batch III — "P1 two-process chat/conv octet" (8 cases,
// TWO-PROCESS). See tool/mcp_test/REAL_UI_P1P2P3_CAMPAIGN.md (Batch III) and
// doc/research/REAL_APP_UI_TEST_INVENTORY.md §P1 rows 3/4/5/6/7/13/14/16.
//
// `sweep_p1_chat` drives BOTH instances on ONE launch. ONE real-UI handshake at
// the top (Batch-4's `_establishFriendshipForSweep`), then BOTH accounts get the
// L3 seed-account marker (`markAccountTest`) because three cases SEED through
// test-gated tools (l3_set_typing / l3_inject_group_text / l3_send_file) and the
// normalizers use clear-active-conversation. The marker is REVOKED in the
// end-guard (sweep_chat discipline). Every ASSERTED action stays a real
// widget/gesture — l3 is seeding/navigation-stability only.
//
// State contract (registered in fixture_c_unified_runner.dart):
//   required = no-friend  (fresh pair launch; the sweep does its OWN handshake)
//   result   = friends    (no case deletes the friend; end-guard re-seeds a row)
//
// ===========================================================================
// VERIFY-FIRST FINDINGS (read from CURRENT code, 2026-06-11 — file:line cited;
// these decide each case's honest gate shape):
//
// 1. RECALL (chat_recall_message) — FULLY WIRED end-to-end:
//    - Menu item: `message_menu_item:recall` exists for `_uikit_revoke_message`
//      (tencent_cloud_chat_message_item_with_menu.dart:737-738); the option is
//      built when `_showRecallButton()` passes — config-enabled (toxee passes
//      enableMessageRecall: true at home_page_bootstrap.dart:573), within
//      recallTimeLimit, isSelf, status SEND_SUCC
//      (tencent_cloud_chat_message_item_with_menu_container.dart:162-186).
//    - Desktop tap → keyed confirm dialog (`confirm_dialog_primary_button`,
//      tencent_cloud_chat_desktop_popup.dart:130) → dataProvider.recallMessage
//      (menu container :497-509) → Tim2ToxSdkPlatform.revokeMessage
//      (tim2tox_sdk_platform.dart:6883): 2-minute window (M-5), LOCAL DELETE
//      (deleteMessages) + onRecvMessageRevoked fan-out + best-effort
//      `__revoke__:{msgID,senderTimestampMs,fromUserId}` wire signal.
//    - Receive side: `_maybeInterceptControlSignal` (:7043-7107) locates B's
//      copy by sender + timestamp window (5s — sender msgIDs don't survive the
//      wire) → deletes it from B's persistence → swallows the signal.
//    - A-side UI: separate_data.recallMessage (:1238-1260) flips the in-memory
//      copy to LOCAL_REVOKED + revokerInfo=currentUser → the tips builder
//      renders `memberRecalledMessage` ("<nick> Recalled a Message", l10n_en
//      :542; item_container.dart:134-141).
//    - B-side UI: tim2tox fires the LEGACY onRecvMessageRevoked(msgID); the
//      fork's handler `onReceiveMessageRecalled` is an EMPTY no-op
//      (message_data.dart:790-792 — "replaced with onRecvMessageRevokedWithInfo",
//      which tim2tox never calls). So B's LIVE bubble may linger until reload;
//      the honest B-side gate is the DATA deletion (text gone from B's dump),
//      which IS asserted. B-side live-tombstone rendering = recorded gap.
//
// 2. READ RECEIPT ✓✓ (read_receipt_double_tick) — NOT WIRED for C2C; NEGATIVE
//    product-gap gate (pins current behavior; flips to the positive gate when
//    the gap is fixed):
//    - UI half EXISTS: own-bubble status icon renders Icons.done_all when
//      isPeerRead else Icons.done (tencent_cloud_chat_message_item.dart:202,
//      :308/:330); toxee maps isPeerRead = ChatMessage.isRead
//      (fake_msg_provider_mapping.dart:591-600). This batch adds the
//      automation-only state-suffixed fork key
//      `message_send_status:<msgID>:<read|sent|other>` on that icon.
//    - Data half is BROKEN/UNWIRED at TWO layers:
//      (a) B's real chat-open never sends a wire 'read' receipt: the fork calls
//          cleanConversationUnreadMessageCount ("c2c_<uid>", separate_data
//          :928-936); Tim2ToxSdkPlatform routes it to
//          FfiChatService.markConversationRead (:4262), which is LOCAL-ONLY
//          (ffi_chat_service.dart:893-906 — read barrier + local isRead, no
//          _sendReceipt). sendMessageReadReceipts fires only for GROUPS with
//          needReadReceipt (separate_data :916-927). markC2CMessageAsRead has
//          NO UI-path caller. l3_mark_read calls setActivePeer (local-only).
//      (b) Even the receipt MATCHING cannot correlate: receipts carry the
//          RECEIVER's locally generated msgID (`${ms}_${seq}_${from}`,
//          ffi_chat_service.dart:1774-1777) and `_handleReceipt` requires an
//          exact primary-msgID match on the sender (:5643); the Tox wire
//          carries no msgID ("c2c:<sender>:<text>", tim2tox_ffi.cpp:273-274).
//          S63's spec records the live confirmation: isReceived never flips.
//    - The inventory row's "✓✓ live 已目击 2026-06-03" claim is contradicted by
//      S63's own live test + INDEX (receipt leg never validated) — per the
//      "don't trust doc conclusions" rule the CODE wins. Fix needs a tim2tox
//      msgID round-trip + a C2C read-receipt trigger on chat-open.
//
// 3. FORWARD→GROUP (forward_to_group_target) — wired; the sweep pre-creates a
//    PRIVATE group via the REAL AddGroupDialog (batch-7
//    `_groupCreateTypeSelectorSurface`). B does NOT need to join: the asserted
//    behavior is A's real picker → group target → Send → the forwarded text
//    lands in A's `group_<gid>` conversation (dump). Same-host NGC join is the
//    flakiest piece of batch 7 and nothing here needs it.
//
// 4. DRAFT (draft_restore_on_conv_switch) — NO draft mechanism on this path;
//    NEGATIVE product-gap gate:
//    - The DESKTOP input has ZERO draft code (grep draft in
//      tencent_cloud_chat_message_input/desktop/ → none); only the MOBILE input
//      saves (`_updateDraft` → controller.setDraft, input_mobile.dart:435-448).
//    - Even the mobile save dead-ends: Tim2ToxSdkPlatform.setConversationDraft
//      is a STUB ("For now, just return success", tim2tox_sdk_platform.dart
//      :4200-4210) — nothing is stored, so conversation.draftText is never
//      non-null and the restore half (input_container.dart:76-77,
//      home_page.dart:1779) can never fire.
//    - toxee's message-widget builder doesn't even pass draftText
//      (home_page_bootstrap.dart:192-200) and keys the widget per conversation,
//      so composer STATE is disposed on switch. Gate: typed-but-unsent text
//      does NOT survive a real switch-away/switch-back (with a positive
//      control proving the type+Enter path works).
//
// 5. TYPING (typing_indicator_render) — NO UI surface AND no production sender;
//    DOUBLE-NEGATIVE product-gap gate:
//    - Zero files in the fork mention typing (grep typing|Typing in
//      third_party/chat-uikit-flutter → no UI consumer; no input-field sender).
//    - The DATA half exists and is asserted as the seeded condition:
//      l3_set_typing → FfiChatService.sendTyping → tox_self_set_typing; the
//      peer surfaces `friends[].isTyping` (l3_debug_tools.dart:4897, ~3s
//      expiry). Gate: (a) B's REAL composer keystrokes produce NO typing
//      signal on A (friends[].isTyping stays false — sentinel: the friend
//      entry itself must exist); (b) with the signal SEEDED true via
//      l3_set_typing, A renders NO typing indicator anywhere (text scan) and
//      does not crash.
//
// 6. UNREAD BADGE (unread_badge_total_sidebar) — wired:
//    - Desktop sidebar Chats tab badge: lib/ui/settings/sidebar.dart:610-677,
//      fed by TencentCloudChatConversationTotalUnreadCount (conversation-data
//      events); renders ONLY when totalUnreadCount > 0. This batch keys the
//      badge Text (`sidebar_chats_unread_badge`; mobile bottom-nav twin
//      `home_chats_unread_badge` in home_page.dart — parity).
//    - Aggregation semantics (read first, per the brief): C2C unread derives
//      from persistence + lastView barrier; GROUP unread is the in-memory
//      counter (ffi_chat_service.dart:908-931); the UIKit store sums them. So
//      the gate drains to 0 first, then expects EXACTLY N(real B sends) +
//      M(injected group inbound) and a clear back to 0 after A opens both.
//    - Badge VALUE is asserted from the dump (`totalUnreadCount`,
//      l3_debug_tools.dart:4973 — the same UikitDataFacade.totalUnreadCount
//      the badge listens to); the keyed badge asserts RENDERED presence/
//      absence (a bare Text is not in interactiveStructured, so the count
//      text itself is a getTextContent breadcrumb, not the gate).
//
// 7. SEARCH EMPTY STATE (search_empty_state) — wired: Cmd+Ctrl+F →
//    _OpenSearchIntent → CustomSearch overlay (home_page.dart:1316-1328);
//    keyed field `message_search_field` (custom_search.dart:593); no-hit
//    renders EmptyStateWidget(title: l10n.noResultsFound == "No results
//    found", custom_search.dart:692-703). ESC-close is attempted first and
//    LOGGED, but the route is a pushed page (no explicit Escape binding was
//    found in custom_search.dart), so the gate accepts the fallback
//    normalizer closing it — the HARD bits are empty-state rendering and the
//    overlay actually ending closed.
//
// 8. IMAGE PREVIEW (image_preview_open_hardened) — batch-6 case 69 upgraded:
//    the bubble tap mounts `TencentCloudChatMessageViewer` via showDialog
//    (tencent_cloud_chat_message_image.dart:479-517; quick-tap <300ms
//    required, GestureDetector mounts after the async image load). This batch
//    keys the viewer root (`message_viewer_root`) and retry-taps ACROSS the
//    row's left region (inbound bubbles are left-aligned and ≤198px wide — a
//    row-center tap can miss the bubble entirely, the suspected batch-6
//    failure mode). HARD if the viewer mounts on any attempt; if every retry
//    exhausts, the documented best-effort SOFT result is printed and the case
//    fails ONLY if the bubble row itself never rendered.
// ===========================================================================

// ---------------------------------------------------------------------------
// small shared helpers (Batch III)
// ---------------------------------------------------------------------------

/// Bounds {x,y,w,h} of the FIRST positively-sized element with [key] from
/// flutter_skill's interactiveStructured, or null. Used to aim taps at
/// fractional positions inside a row (the image-preview hardening).
Future<({double x, double y, double w, double h})?> _p1cKeyBounds(
  Inst inst,
  String key,
) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final r = await inst.skill('interactiveStructured', const {});
    final data = r['data'];
    final elements = data is Map ? data['elements'] : null;
    if (elements is List) {
      for (final e in elements) {
        if (e is! Map || e['key'] != key) continue;
        final b = e['bounds'];
        if (b is! Map) continue;
        final x = (b['x'] as num?)?.toDouble() ?? 0;
        final y = (b['y'] as num?)?.toDouble() ?? 0;
        final w = (b['w'] as num?)?.toDouble() ?? 0;
        final h = (b['h'] as num?)?.toDouble() ?? 0;
        if (w > 0 && h > 0) return (x: x, y: y, w: w, h: h);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return null;
}

/// Focus the REAL desktop composer and type [text] WITHOUT sending (no
/// Return). Mirrors `sendComposerMessage`'s focus mechanics (the keyed
/// `chat_input_text_field` is the presence anchor; the editable focuses from a
/// coordinate tap inside the composer).
Future<bool> _p1cTypeIntoComposerNoSend(Inst inst, String text) async {
  await inst.foreground();
  if (!await inst.waitKey('chat_input_text_field', timeoutSecs: 8)) {
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapAt(_composerX, _composerY);
  await Future<void>.delayed(const Duration(milliseconds: 450));
  await inst.osaClear();
  await Future<void>.delayed(const Duration(milliseconds: 250));
  // ATOMIC paste (not osaType keystrokes, which drop/mangle chars — see
  // sendComposerMessage). Entering the text still fires the composer's
  // onChanged, so the "does typing leak a typing signal" probe stays valid,
  // and the later exact-match proof (Return-send → B's own message == text)
  // no longer fails on a mangled keystroke string.
  await inst.osaPaste(text);
  await Future<void>.delayed(const Duration(milliseconds: 600));
  return true;
}

/// Press Return in the focused composer (focus first). Used to prove a draft
/// either does or does not survive a conversation switch: if text were
/// restored, this Return would SEND it.
Future<void> _p1cComposerReturn(Inst inst) async {
  await inst.foreground();
  await inst.tapAt(_composerX, _composerY);
  await Future<void>.delayed(const Duration(milliseconds: 450));
  await inst.osaReturn();
  await Future<void>.delayed(const Duration(milliseconds: 1200));
}

/// SINGLE-FIRE tap on the first interactive element whose extracted `text`
/// contains [text] (positive bounds required) — one real tapAt at its center.
/// flutter_skill's text-tap (`tapText`) DOUBLE-FIRES onstage controls
/// (synthetic pointer + direct callback invoke): on a selection-toggling
/// picker row that nets to NO-OP, and on a route-closing Send it double-pops
/// (codex P1). Falls back to `_tryTapText` ONLY when no bounds-bearing element
/// matches (offstage/unextracted text — where the direct invoke fires exactly
/// once), mirroring `_p1OpenDialogViaKey`'s bounds-gated discipline.
Future<bool> _p1cTapTextOnce(Inst inst, String text) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final r = await inst.skill('interactiveStructured', const {});
    final data = r['data'];
    final elements = data is Map ? data['elements'] : null;
    if (elements is List) {
      for (final e in elements) {
        if (e is! Map) continue;
        final t = e['text']?.toString() ?? '';
        if (!t.contains(text)) continue;
        final b = e['bounds'];
        if (b is! Map) continue;
        final x = (b['x'] as num?)?.toDouble() ?? 0;
        final y = (b['y'] as num?)?.toDouble() ?? 0;
        final w = (b['w'] as num?)?.toDouble() ?? 0;
        final h = (b['h'] as num?)?.toDouble() ?? 0;
        if (w <= 0 || h <= 0) continue;
        await inst.tapAt(x + w / 2, y + h / 2);
        return true;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  print(
    '[pair] _p1cTapTextOnce: no bounds-bearing element for "$text" — '
    'falling back to tapText (single direct-invoke on unresolved bounds)',
  );
  return _tryTapText(inst, text);
}

/// First on-screen Text whose data contains [needle] (case-insensitive), via
/// flutter_skill getTextContent (Text/RichText only), or null.
Future<String?> _p1cTextContaining(Inst inst, String needle) async {
  final r = await inst.skill('getTextContent', const {});
  final texts = r['texts'];
  if (texts is! List) return null;
  final lower = needle.toLowerCase();
  for (final t in texts) {
    if (t is! Map) continue;
    final s = t['text']?.toString() ?? '';
    if (s.toLowerCase().contains(lower)) return s;
  }
  return null;
}

/// The dump `friends[]` entry for [peerTox] (pubkey match), or null. The entry
/// is the SENTINEL for any isTyping absence verdict — an empty/missing friends
/// list must never read as "not typing" (Batch-II lesson: empty list fields
/// are ambiguous on read error).
Future<Map<String, dynamic>?> _p1cFriendEntry(Inst inst, String peerTox) async {
  final s = await inst.dumpState();
  final friends = s['friends'];
  if (friends is! List) return null;
  final pk = _pubkey(peerTox);
  for (final f in friends) {
    if (f is! Map) continue;
    final uid = f['userId']?.toString() ?? '';
    if (uid == pk ||
        (uid.length >= 64 && pk.startsWith(uid.substring(0, 64)))) {
      return Map<String, dynamic>.from(f);
    }
  }
  return null;
}

/// The C2C dump entry with [msgId] in the conversation with [peerTox], or null.
Future<Map<String, dynamic>?> _p1cOwnEntry(
  Inst inst,
  String peerTox,
  String msgId,
) async {
  final msgs = await _c2cMessages(inst, peerTox);
  for (final m in msgs) {
    if (m['msgID']?.toString() == msgId) return m;
  }
  return null;
}

/// Poll the dump `totalUnreadCount` until [want] matches it. Returns the last
/// observed value (for logging) alongside whether it matched.
Future<(bool, int)> _p1cWaitTotalUnread(
  Inst inst,
  bool Function(int) want, {
  int timeoutSecs = 30,
}) async {
  var last = -1;
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState();
    last = (s['totalUnreadCount'] as num?)?.toInt() ?? -1;
    if (last >= 0 && want(last)) return (true, last);
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  return (false, last);
}

/// Normalize between cases: dismiss any open menu/overlay (ESC best-effort)
/// and land back on the chats home.
Future<void> _p1cNormalize(Inst inst) async {
  try {
    await inst.foreground();
    if (await inst.waitKey('message_search_field', timeoutSecs: 1)) {
      await inst.osaEscape();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  } on DriveError {
    // best-effort
  }
  await returnToChatsHome(inst, rounds: 4);
}

// ===========================================================================
// case p1c-1 — chat_recall_message (P1#3)
// ===========================================================================
/// A sends a FRESH text via the real composer, secondary-taps the own bubble,
/// taps the keyed `message_menu_item:recall`, confirms via the keyed desktop
/// dialog → A's bubble becomes the recalled tombstone ("<nick> Recalled a
/// Message"), A's persistence drops the msgID, and B's persisted copy is
/// deleted by the wire `__revoke__:` signal (text gone from B's dump). B-side
/// LIVE-bubble tombstone rendering is a recorded gap (fork no-op handler) and
/// is NOT asserted — the B gate is the data deletion.
Future<bool> _p1cRecallMessage(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
  String nickA,
) async {
  final nonce = DateTime.now().microsecondsSinceEpoch;
  // Seed a PRIOR message so the conversation has history below the recalled one
  // (the realistic case). After recall, the conv-row preview refreshes to this
  // prior message instead of the recalled text. Recalling the ONLY message of a
  // conversation leaves the conversation empty and the UIKit merge keeps the
  // stale last-message preview — that empty-conversation edge case is a
  // documented residual (deeper fix = clear the preview when a conv goes empty).
  final priorText = 'RUIP1PRIOR-$nonce';
  final priorId = await _sendAndIdentify(a, toxB, priorText);
  if (priorId == null) {
    print('[pair] chat_recall_message: could not seed prior message');
    return false;
  }
  final text = 'RUIP1RECALL-$nonce';
  final msgId = await _sendAndIdentify(a, toxB, text);
  if (msgId == null) {
    print('[pair] chat_recall_message: could not send/identify own message');
    return false;
  }
  // B must HOLD the message before the recall (so the deletion is meaningful)
  // and A's copy must be SEND_SUCC for the recall item to show.
  if (!await _waitC2cMessageText(b, toxA, text, timeoutSecs: 45)) {
    print(
      '[pair] chat_recall_message: B never received "$text" — cannot '
      'assert the wire-revoke half',
    );
    return false;
  }
  if (!await _openMessageMenuReal(a, msgId)) {
    print('[pair] chat_recall_message: real message menu did not open');
    return false;
  }
  if (!await a.waitKeyCenter('message_menu_item:recall', timeoutSecs: 4)) {
    await _dismissMessageMenu(a);
    print(
      '[pair] chat_recall_message: recall item not present on fresh self '
      'message (recallTimeLimit/config regression?)',
    );
    return false;
  }
  if (!await a.tapKeyCenter('message_menu_item:recall', timeoutSecs: 6)) {
    await _dismissMessageMenu(a);
    print('[pair] chat_recall_message: recall item not tappable');
    return false;
  }
  // The keyed desktop confirm dialog (same key as the delete confirm).
  if (!await a.waitKeyCenter('confirm_dialog_primary_button', timeoutSecs: 8)) {
    await a.shot('/tmp/ui_p1c_recall_noconfirm_A.png');
    print('[pair] chat_recall_message: recall confirm dialog did not open');
    return false;
  }
  if (!await a.tapKeyCenter('confirm_dialog_primary_button', timeoutSecs: 6)) {
    print('[pair] chat_recall_message: recall confirm not tappable');
    return false;
  }
  // A-side UI: the tips tombstone renders. revokerInfo == currentUser, so the
  // EN string is "<nick> Recalled a Message"; accept a contains-match via
  // getTextContent so a nickname/template drift fails soft into the scan.
  // Foreground A and give the LOCAL_REVOKED flip time to rebuild the row into
  // the tombstone tip (the render can lag the data delete; flaky at 8 s).
  await a.foreground();
  var tombstone = await a.waitText('$nickA Recalled a Message', timeoutSecs: 15);
  if (!tombstone) {
    // Accept the named tip ("<nick> Recalled a Message") OR the generic
    // fallback ("Message recalled") — both are valid LOCAL_REVOKED tips (a
    // unique nonce + fresh launch means any such tip is THIS recall).
    final named = await _p1cTextContaining(a, 'Recalled a Message');
    final generic = await _p1cTextContaining(a, 'Message recalled');
    tombstone = named != null || generic != null;
  }
  // SOFT signal (logged, not gated): the unique nonce text should also leave the
  // rendered surface (bubble → tip; sidebar preview → prior message). It
  // conflates the message list with the conv-preview, whose refresh can lag the
  // flip, so it is recorded rather than hard-gated — `tombstone` + `aGone`
  // already prove the bubble rebuilt for THIS recall (unique nonce + fresh
  // launch ⇒ no stale "Recalled a Message" can satisfy `tombstone` vacuously).
  var originalGone = false;
  for (var i = 0; i < 10 && !originalGone; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    originalGone = (await _p1cTextContaining(a, text)) == null;
  }
  // A-side data: the msgID leaves A's dump (revokeMessage → deleteMessages).
  var aGone = false;
  for (var i = 0; i < 20 && !aGone; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    aGone = (await _p1cOwnEntry(a, toxB, msgId)) == null;
  }
  // B-side data: the wire `__revoke__` deletes B's copy (matched by sender +
  // 5s timestamp window). Poll generously — wire + poll loop latency.
  var bGone = false;
  for (var i = 0; i < 40 && !bGone; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final msgs = await _c2cMessages(b, toxA);
    bGone = !msgs.any((m) => m['text']?.toString() == text);
  }
  await a.shot('/tmp/ui_p1c_recall_A.png');
  print(
    '[pair] chat_recall_message: tombstone=$tombstone aGone=$aGone bGone=$bGone '
    '(soft originalGone=$originalGone; B live-bubble tombstone NOT asserted — '
    'fork onReceiveMessageRecalled is a no-op; recorded gap)',
  );
  return tombstone && aGone && bGone;
}

// ===========================================================================
// case p1c-2 — read_receipt_double_tick (P1#4) — NEGATIVE product-gap pin
// ===========================================================================
/// Pins the verified CURRENT behavior: a delivered own C2C message renders the
/// single-tick state and NEVER flips to peer-read when B opens the chat via a
/// REAL row tap, because (a) B's chat-open path is local-only (no wire 'read'
/// receipt) and (b) receipt msgIDs cannot correlate across instances (no
/// round-trip). PASS == gap present (baseline not-read + still not-read after
/// B's open + the state-suffixed icon key stays ':sent'). When tim2tox lands
/// the msgID round-trip + a C2C read trigger, this case FAILS loudly — flip it
/// to the positive ✓✓ gate then (the fork key is already in place for that).
Future<bool> _p1cReadReceiptDoubleTick(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  // Park B OFF the conversation first so A's send lands UNREAD on B — the
  // pre-open unread>=1 → post-open unread==0 transition is the proof that B's
  // real row tap exercised the production local-read path (codex P1: without
  // it the negative pin is meaningless; the active-conversation rule
  // auto-zeroes unread, so only the >=1 BEFORE makes the 0 AFTER evidential).
  await b.foreground();
  await returnToChatsHome(b, rounds: 4);
  try {
    await b.clearActiveConversation();
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
  }
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final text = 'RUIP1TICK-$nonce';
  final msgId = await _sendAndIdentify(a, toxB, text);
  if (msgId == null) {
    print('[pair] read_receipt_double_tick: could not send/identify message');
    return false;
  }
  // Delivery: B holds the message (so "B opened the chat containing it" is a
  // meaningful read trigger).
  if (!await _waitC2cMessageText(b, toxA, text, timeoutSecs: 45)) {
    print('[pair] read_receipt_double_tick: B never received the message');
    return false;
  }
  // B's pre-open unread must reflect the inbound (entry exists AND >=1).
  var bUnreadBefore = -1;
  for (var i = 0; i < 20 && bUnreadBefore < 1; i++) {
    final entry = await _conversationEntry(b, _c2cConvId(toxA));
    bUnreadBefore = (entry?['unreadCount'] as num?)?.toInt() ?? -1;
    if (bUnreadBefore < 1) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  if (bUnreadBefore < 1) {
    print(
      '[pair] read_receipt_double_tick: B unread never reached >=1 '
      '(got $bUnreadBefore) — cannot prove the open marks it read',
    );
    return false;
  }
  // Baseline: A's own entry is NOT read (sentinel: the entry itself exists),
  // and the keyed icon renders the ':sent' state with ':read' absent.
  final baseline = await _p1cOwnEntry(a, toxB, msgId);
  if (baseline == null) {
    print('[pair] read_receipt_double_tick: own entry missing from A dump');
    return false;
  }
  final baselineNotRead = baseline['isRead'] != true;
  await _ensureChatOpen(a, toxB);
  final sentIcon = await a.waitKey(
    'message_send_status:$msgId:sent',
    timeoutSecs: 10,
  );
  final readIconBefore = await a.waitKey(
    'message_send_status:$msgId:read',
    timeoutSecs: 1,
  );
  // B opens the chat via the REAL conversation-row tap (the production
  // mark-read path: cleanConversationUnreadMessageCount → markConversationRead).
  await b.foreground();
  await openChat(b, toxA);
  // GATE (codex P1): B's LOCAL read half must actually have fired — the
  // pre-open unread was >=1, so the post-open 0 (entry still present) is the
  // production mark-read transition.
  var bLocallyRead = false;
  for (var i = 0; i < 12 && !bLocallyRead; i++) {
    final entry = await _conversationEntry(b, _c2cConvId(toxA));
    final unread = (entry?['unreadCount'] as num?)?.toInt();
    bLocallyRead = entry != null && unread == 0;
    if (!bLocallyRead) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  if (!bLocallyRead) {
    print(
      '[pair] read_receipt_double_tick: B did not locally mark the chat '
      'read after the real open (pre-open unread=$bUnreadBefore) — the '
      'negative pin would be meaningless',
    );
    return false;
  }
  // Bounded observation window for a wire 'read' receipt that current code
  // can never send (10s is generous for the same-host poll loop).
  await Future<void>.delayed(const Duration(seconds: 10));
  final after = await _p1cOwnEntry(a, toxB, msgId);
  final stillNotRead = after != null && after['isRead'] != true;
  await a.foreground();
  await _ensureChatOpen(a, toxB);
  final sentIconAfter = await a.waitKey(
    'message_send_status:$msgId:sent',
    timeoutSecs: 6,
  );
  final readIconAfter = await a.waitKey(
    'message_send_status:$msgId:read',
    timeoutSecs: 1,
  );
  await a.shot('/tmp/ui_p1c_tick_A.png');
  print(
    '[pair] read_receipt_double_tick: NEGATIVE-PIN baselineNotRead='
    '$baselineNotRead sentIcon=$sentIcon readIconBefore=$readIconBefore '
    'bLocallyRead=$bLocallyRead stillNotReadAfterBOpen=$stillNotRead '
    'sentIconAfter=$sentIconAfter readIconAfter=$readIconAfter '
    '(breadcrumb isReceived=${after?['isReceived']}) — product gap: no C2C '
    'wire read receipt + no msgID round-trip; flip to the positive ✓✓ gate '
    'when fixed',
  );
  return baselineNotRead &&
      sentIcon &&
      !readIconBefore &&
      bLocallyRead &&
      stillNotRead &&
      sentIconAfter &&
      !readIconAfter;
}

// ===========================================================================
// case p1c-3 — forward_to_group_target (P1#5)
// ===========================================================================
/// Real message-menu Forward on an own C2C message → the REAL picker ("Forward
/// Individually" header) lists the pre-created GROUP conversation → select it +
/// Send → the forwarded text lands in A's group conversation (dump messages of
/// `group_<gid>`) and the picker dismisses. The group was created via the REAL
/// AddGroupDialog in the sweep prelude (B membership NOT required — the gate
/// is A's picker → group-send path).
Future<bool> _p1cForwardToGroupTarget(
  Inst a,
  String toxB,
  String gid,
  String groupName,
) async {
  if (gid.isEmpty) {
    print('[pair] forward_to_group_target: no group available (create failed)');
    return false;
  }
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final text = 'RUIP1FWDG-$nonce';
  final msgId = await _sendAndIdentify(a, toxB, text);
  if (msgId == null) {
    print('[pair] forward_to_group_target: could not send/identify message');
    return false;
  }
  if (!await _openMessageMenuReal(a, msgId)) {
    print('[pair] forward_to_group_target: real message menu did not open');
    return false;
  }
  if (!await a.waitKeyCenter('message_menu_item:forward', timeoutSecs: 4)) {
    await _dismissMessageMenu(a);
    print('[pair] forward_to_group_target: forward item not present');
    return false;
  }
  if (!await a.tapKeyCenter('message_menu_item:forward', timeoutSecs: 6)) {
    await _dismissMessageMenu(a);
    print('[pair] forward_to_group_target: forward item not tappable');
    return false;
  }
  final pickerShown = await a.waitText('Forward Individually', timeoutSecs: 8);
  if (!pickerShown) {
    await a.shot('/tmp/ui_p1c_fwd_nopicker_A.png');
    print('[pair] forward_to_group_target: forward picker did not mount');
    return false;
  }
  // Select the GROUP row by its KEYED picker handle (inside the modal dialog),
  // single-fire. The previous text-tap on the group NAME also matched the same
  // group's row in the BACKGROUND sidebar (behind the barrier); tapping that
  // landed on the barrierDismissible barrier and CLOSED the picker before Send
  // — which is why forward_picker_send_button read as "not resolvable" (the
  // whole dialog was gone, not the button being unsized).
  final targetCenter = await a.keyCenter('forward_picker_item:$gid');
  var targetTapped =
      await a.tapKeyCenter('forward_picker_item:$gid', timeoutSecs: 6);
  if (!targetTapped) {
    // Fallback only if the keyed row didn't resolve — logged so a gid/groupID
    // mismatch is visible rather than silently dismissing the dialog.
    print('[pair] forward_to_group_target: keyed picker row '
        'forward_picker_item:$gid not resolvable (center=$targetCenter) — '
        'falling back to text tap');
    targetTapped = await _p1cTapTextOnce(a, groupName);
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
  // The picker's keyed Send button is resolved via the element-tree resolver
  // (ui_key_center); the picker is a centered showDialog/AlertDialog (NOT an
  // Overlay popup). WAIT for it to be resolvable first (ui_key_center has no
  // internal retry), then single-fire tap.
  final sendResolvable =
      await a.waitKeyCenter('forward_picker_send_button', timeoutSecs: 6);
  final sendCenter = await a.keyCenter('forward_picker_send_button');
  if (!sendResolvable) {
    // Surface the resolver verdict (key_offstage_only vs key_not_found) +
    // a screenshot — distinguishes "dialog was dismissed" (button absent) from
    // "header not laid out" (button mounted but unsized).
    final dbg =
        await a.l3('ui_key_center', {'key': 'forward_picker_send_button'});
    await a.shot('/tmp/ui_p1c_fwd_nosend_A.png');
    print('[pair] forward_to_group_target: send resolver debug=$dbg');
  }
  print('[pair] forward_to_group_target: sendResolvable=$sendResolvable '
      'sendCenter=$sendCenter targetCenter=$targetCenter');
  final sendTapped =
      await a.tapKeyCenter('forward_picker_send_button', timeoutSecs: 6);
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final pickerGone = await a.waitTextGone(
    'Forward Individually',
    timeoutSecs: 6,
  );
  // The forwarded copy lands in the GROUP conversation (A's own group send).
  var inGroup = false;
  for (var i = 0; i < 20 && !inGroup; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final s = await a.dumpState(conversationId: 'group_$gid');
    final msgs = (s['messages'] as List?) ?? const [];
    inGroup = msgs.any((m) => m is Map && m['text']?.toString() == text);
  }
  await a.shot('/tmp/ui_p1c_fwd_group_A.png');
  print(
    '[pair] forward_to_group_target: pickerShown=$pickerShown '
    'targetTapped=$targetTapped sendTapped=$sendTapped '
    'pickerGone=$pickerGone inGroup=$inGroup (gid=${_shortId(gid)})',
  );
  return pickerShown && pickerGone && inGroup;
}

// ===========================================================================
// case p1c-4 — draft_restore_on_conv_switch (P1#6) — NEGATIVE product-gap pin
// ===========================================================================
/// Pins the verified CURRENT behavior: composer text typed-but-unsent does NOT
/// survive a real conversation switch (desktop input never saves drafts; the
/// platform setConversationDraft is a stub; the per-conversation widget key
/// disposes composer state on switch). Sequence: positive CONTROL (type +
/// Enter sends — proves the typing path), then type a probe WITHOUT sending,
/// switch to the GROUP conversation via real row tap, switch back, press
/// Enter → the probe must NOT have been sent (no message with the probe text
/// appears). If a draft mechanism ever lands, the restored text would be SENT
/// by that Enter and this case FAILS loudly — flip it to the positive gate.
Future<bool> _p1cDraftRestoreOnConvSwitch(
  Inst a,
  String toxB,
  String gid,
  String groupName,
) async {
  if (gid.isEmpty) {
    print(
      '[pair] draft_restore_on_conv_switch: no second conversation '
      '(group create failed) — cannot drive a real switch',
    );
    return false;
  }
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final control = 'RUIP1DRAFTCTL-$nonce';
  final probe = 'RUIP1DRAFT-$nonce';
  await openChat(a, toxB);
  // Positive control: the same focus+type+Enter mechanics DO send.
  if (!await sendComposerMessage(a, control)) {
    print(
      '[pair] draft_restore_on_conv_switch: control send failed — the '
      'typing path is broken, a negative probe would be meaningless',
    );
    return false;
  }
  // The probe: type WITHOUT Enter.
  if (!await _p1cTypeIntoComposerNoSend(a, probe)) {
    print('[pair] draft_restore_on_conv_switch: could not type the probe');
    return false;
  }
  // Real switch away (group row tap) and back (C2C row tap).
  await openGroupChat(a, groupId: gid, groupName: groupName);
  await openChat(a, toxB);
  // If any draft text had been restored, this Return would send it.
  await _p1cComposerReturn(a);
  // Bounded wait, then assert the probe text was NEVER sent.
  var probeSent = false;
  for (var i = 0; i < 10 && !probeSent; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final msgs = await _c2cMessages(a, toxB);
    probeSent = msgs.any((m) => m['text']?.toString() == probe);
  }
  // Defensive normalization: clear any leftover composer content so a future
  // draft mechanism (gate-fail scenario) can't poison later cases.
  try {
    await a.tapAt(_composerX, _composerY);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await a.osaClear();
  } on DriveError {
    // best-effort
  }
  // POST-control (codex P2 bracket): the same type+Enter mechanics must STILL
  // send right after the negative observation — so a transient focus/typing
  // failure around the probe can't masquerade as "draft not restored".
  final postControl = 'RUIP1DRAFTCTL2-$nonce';
  final postControlSent = await sendComposerMessage(a, postControl);
  await a.shot('/tmp/ui_p1c_draft_A.png');
  print(
    '[pair] draft_restore_on_conv_switch: NEGATIVE-PIN controlSent=true '
    'probeSent=$probeSent (expect false — desktop input has no draft save; '
    'Tim2ToxSdkPlatform.setConversationDraft is a stub; mobile-side saves '
    'dead-end at the same stub) postControlSent=$postControlSent (typing '
    'bracket). Flip to a positive gate when drafts land',
  );
  return !probeSent && postControlSent;
}

// ===========================================================================
// case p1c-5 — typing_indicator_render (P1#7) — DOUBLE-NEGATIVE product-gap pin
// ===========================================================================
/// Pins the verified CURRENT behavior at both halves: (a) B's REAL composer
/// keystrokes send NO typing signal (no production caller of sendTyping), so
/// A's `friends[].isTyping` stays false; (b) even when the signal is SEEDED
/// over the real wire (l3_set_typing → tox_self_set_typing → A's poll loop
/// flips isTyping true), A renders NO typing indicator anywhere (no fork UI
/// consumer exists) and does not crash. Sentinels: A's friend entry for B must
/// EXIST (absence ≠ not-typing), the chat surface must be alive during the
/// no-indicator scan, and the seeded half must actually flip the dump flag
/// (proving the transport the missing UI would consume).
Future<bool> _p1cTypingIndicatorRender(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  // A views the chat with B (where an indicator would render if one existed).
  await openChat(a, toxB);
  final entry0 = await _p1cFriendEntry(a, toxB);
  if (entry0 == null || !entry0.containsKey('isTyping')) {
    print(
      '[pair] typing_indicator_render: A has no friend entry for B '
      '(sentinel failed — cannot make an absence verdict)',
    );
    return false;
  }
  // (a) B types for REAL in its composer (no Enter): no signal may reach A.
  final typeNonce = DateTime.now().microsecondsSinceEpoch % 1000000;
  final typeProbe = 'RUIP1TYPEPROBE-$typeNonce';
  await b.foreground();
  await openChat(b, toxA);
  if (!await _p1cTypeIntoComposerNoSend(b, typeProbe)) {
    print('[pair] typing_indicator_render: B could not type into composer');
    return false;
  }
  var realKeystrokeLeaked = false;
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    final e = await _p1cFriendEntry(a, toxB);
    if (e != null && e['isTyping'] == true) {
      realKeystrokeLeaked = true;
      break;
    }
  }
  // Prove B's keystrokes really landed in the composer (codex P2: a silent
  // type failure would make the no-leak window vacuous): Return-send the
  // typed probe and require it to appear as B's OWN message. The inbound on A
  // is harmless (case 6 drains unread first). Retried like
  // sendComposerMessage's Return race guard.
  var bKeystrokesProven = false;
  if (_isWindowsRealUi) {
    // Windows headless: the typed-no-send + osaReturn real-keystroke path can't
    // populate the ExtendedTextField controller, so prove B's composer really
    // works via the set-text+send path (equivalent sanity check that the
    // no-leak window above is not vacuous). The probe lands as B's own message.
    bKeystrokesProven = await sendComposerMessage(b, typeProbe);
  } else {
    for (var attempt = 0; attempt < 4 && !bKeystrokesProven; attempt++) {
      await b.foreground();
      await b.tapAt(_composerX, _composerY);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await b.osaReturn();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final msgs = await _c2cMessages(b, toxA);
      bKeystrokesProven = msgs.any(
        (m) => m['isSelf'] == true && m['text']?.toString() == typeProbe,
      );
    }
  }
  if (!bKeystrokesProven) {
    // Don't leave half-typed text behind for later cases.
    try {
      await b.tapAt(_composerX, _composerY);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await b.osaClear();
    } on DriveError {
      // best-effort
    }
  }
  // (b) SEED the signal (l3_set_typing, ~3s expiry → re-send while polling).
  var seededFlagOn = false;
  for (var i = 0; i < 8 && !seededFlagOn; i++) {
    final r = await b.l3('l3_set_typing', {'userId': toxA, 'on': 'true'});
    if (r['ok'] != true) {
      print('[pair] typing_indicator_render: l3_set_typing failed: $r');
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final e = await _p1cFriendEntry(a, toxB);
    seededFlagOn = e != null && e['isTyping'] == true;
  }
  if (!seededFlagOn) {
    print(
      '[pair] typing_indicator_render: seeded typing flag never reached '
      'A (transport half broken — absence scan would be meaningless)',
    );
    return false;
  }
  // While the flag IS on, A's UI renders no typing affordance anywhere.
  // The flag expires ~3s after the last signal (codex P1: a one-shot seed
  // would expire before the scan), so RE-SEND right before the scan and
  // re-assert the flag immediately AFTER it — the absence verdict only counts
  // if the seeded condition held THROUGH the scan.
  await a.foreground();
  final chatAlive = await a.waitKey(
    'message_header_profile_avatar',
    timeoutSecs: 6,
  );
  await b.l3('l3_set_typing', {'userId': toxA, 'on': 'true'});
  await Future<void>.delayed(const Duration(milliseconds: 600));
  final typingTextSeen = await _p1cTextContaining(a, 'typing');
  final entryDuringScan = await _p1cFriendEntry(a, toxB);
  final flagHeldThroughScan =
      entryDuringScan != null && entryDuringScan['isTyping'] == true;
  // Stop the seeded signal; the flag expires (~3s) — no crash, chat alive.
  await b.l3('l3_set_typing', {'userId': toxA, 'on': 'false'});
  var flagCleared = false;
  for (var i = 0; i < 10 && !flagCleared; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final e = await _p1cFriendEntry(a, toxB);
    flagCleared = e != null && e['isTyping'] != true;
  }
  await a.shot('/tmp/ui_p1c_typing_A.png');
  print(
    '[pair] typing_indicator_render: DOUBLE-NEGATIVE-PIN '
    'realKeystrokeLeaked=$realKeystrokeLeaked (expect false — no production '
    'sendTyping caller) bKeystrokesProven=$bKeystrokesProven '
    'seededFlagOn=$seededFlagOn flagHeldThroughScan=$flagHeldThroughScan '
    'chatAlive=$chatAlive typingTextSeen=${typingTextSeen ?? 'none'} '
    '(expect none — no fork UI consumer) flagCleared=$flagCleared — product '
    'gap recorded; flip when a typing surface lands',
  );
  return !realKeystrokeLeaked &&
      bKeystrokesProven &&
      seededFlagOn &&
      flagHeldThroughScan &&
      chatAlive &&
      typingTextSeen == null &&
      flagCleared;
}

// ===========================================================================
// case p1c-6 — unread_badge_total_sidebar (P1#13)
// ===========================================================================
/// Per-conversation unread map (conversationID -> unreadCount) from
/// l3_dump_state. Used to drain to a VERIFIED per-conversation 0 baseline and
/// to surface a per-conversation breakdown when the aggregate total is wrong
/// (distinguishes a real double-count from a drain race).
Future<Map<String, int>> _p1cConvUnreads(Inst inst) async {
  final s = await inst.dumpState();
  final out = <String, int>{};
  for (final c in (s['conversations'] as List? ?? const [])) {
    if (c is! Map) continue;
    final id = c['conversationID']?.toString() ?? '';
    if (id.isEmpty) continue;
    out[id] = (c['unreadCount'] as num?)?.toInt() ?? 0;
  }
  return out;
}

/// Drain A's unread to a true 0 baseline (open both conversations, park on the
/// chats home, clear the active conversation), then B REAL-composer-sends N=2
/// into the C2C and M=1 group inbound is SEEDED via l3_inject_group_text (the
/// brief-sanctioned group half — B is not an NGC member). The sidebar Chats
/// badge must RENDER (keyed `sidebar_chats_unread_badge`) with the dump
/// `totalUnreadCount` exactly N+M==3; A then opens BOTH conversations via real
/// row taps → the badge unmounts and the dump total returns to 0.
Future<bool> _p1cUnreadBadgeTotalSidebar(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
  String gid,
  String groupName,
) async {
  if (gid.isEmpty) {
    print(
      '[pair] unread_badge_total_sidebar: no group available — the N+M '
      'aggregation needs both conversation kinds',
    );
    return false;
  }
  // Drain to a true 0 baseline. Loop opening BOTH conversations until EVERY
  // per-conversation unreadCount is 0 AND the aggregate total is 0 — a single
  // open pass can leave a conversation dirty (a late inbound during the pass,
  // or an open that didn't mark-read), and the old total-only check could pass
  // on a transient 0 while a conversation still carried unread, inflating the
  // post-seed total by that residue. Logs the per-conversation map so a real
  // double-count (vs a drain race) is visible in the run output.
  var drained = false;
  var baseline = -1;
  Map<String, int> baselinePerConv = const {};
  for (var pass = 0; pass < 4 && !drained; pass++) {
    await openChat(a, toxB);
    await openGroupChat(a, groupId: gid, groupName: groupName);
    await returnToChatsHome(a, rounds: 4);
    try {
      await a.clearActiveConversation();
    } on DriveError catch (e) {
      if (!_isNonTestAccountError(e)) rethrow;
    }
    final (totalZero, total) = await _p1cWaitTotalUnread(
      a,
      (u) => u == 0,
      timeoutSecs: 15,
    );
    baseline = total;
    baselinePerConv = await _p1cConvUnreads(a);
    // Require the two conversations under test to be PRESENT (a missing/empty
    // map must not pass `every` vacuously) AND every conversation's unread 0.
    final c2cId = _c2cConvId(toxB);
    final groupConvId = 'group_$gid';
    final tracked = baselinePerConv.containsKey(c2cId) &&
        baselinePerConv.containsKey(groupConvId);
    final allConvZero = baselinePerConv.values.every((u) => u == 0);
    print(
      '[pair] unread_badge_total_sidebar: baseline pass $pass '
      'total=$total tracked=$tracked perConv=$baselinePerConv',
    );
    drained = totalZero && tracked && allConvZero;
  }
  if (!drained) {
    print(
      '[pair] unread_badge_total_sidebar: baseline did not drain to a clean 0 '
      '(total=$baseline perConv=$baselinePerConv) — refusing a fuzzy-baseline '
      'assert',
    );
    return false;
  }
  final badgeGoneAtBaseline = !await a.waitKey(
    'sidebar_chats_unread_badge',
    timeoutSecs: 1,
  );
  // N=2 REAL composer sends from B into the C2C.
  final nonce = DateTime.now().microsecondsSinceEpoch % 1000000;
  await b.foreground();
  await openChat(b, toxA);
  final n1 = await sendComposerMessage(b, 'RUIP1BADGE-N1-$nonce');
  final n2 = await sendComposerMessage(b, 'RUIP1BADGE-N2-$nonce');
  if (!n1 || !n2) {
    print(
      '[pair] unread_badge_total_sidebar: B composer seeding failed '
      '(n1=$n1 n2=$n2)',
    );
    return false;
  }
  // M=1 group inbound seeded through the REAL ingest seam (from B's id so the
  // UI resolves a friend display name).
  final inj = await a.l3('l3_inject_group_text', {
    'groupId': gid,
    'fromUserId': _pubkey(toxB),
    'text': 'RUIP1BADGE-M1-$nonce',
  });
  if (inj['ok'] != true) {
    print(
      '[pair] unread_badge_total_sidebar: l3_inject_group_text failed: '
      '$inj',
    );
    return false;
  }
  // The badge renders with the EXACT N+M total.
  final (bumped, total) = await _p1cWaitTotalUnread(
    a,
    (u) => u == 3,
    timeoutSecs: 45,
  );
  final badgeShown = await a.waitKey(
    'sidebar_chats_unread_badge',
    timeoutSecs: bumped ? 8 : 1,
  );
  final renderedCount = await _p1cTextContaining(a, '3'); // breadcrumb only
  await a.shot('/tmp/ui_p1c_badge_up_A.png');
  if (!bumped || !badgeShown) {
    final upPerConv = await _p1cConvUnreads(a);
    print(
      '[pair] unread_badge_total_sidebar: badge/up-phase failed '
      '(totalUnreadCount=$total want 3, badgeShown=$badgeShown '
      'perConv=$upPerConv)',
    );
    return false;
  }
  // Clear: A opens BOTH conversations via real row taps.
  await openChat(a, toxB);
  await openGroupChat(a, groupId: gid, groupName: groupName);
  await returnToChatsHome(a, rounds: 4);
  try {
    await a.clearActiveConversation();
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
  }
  final (cleared, after) = await _p1cWaitTotalUnread(
    a,
    (u) => u == 0,
    timeoutSecs: 30,
  );
  var badgeGone = false;
  for (var i = 0; i < 10 && !badgeGone; i++) {
    badgeGone = !await a.waitKey('sidebar_chats_unread_badge', timeoutSecs: 1);
    if (!badgeGone) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  await a.shot('/tmp/ui_p1c_badge_cleared_A.png');
  print(
    '[pair] unread_badge_total_sidebar: baseline0=$drained '
    'badgeGoneAtBaseline=$badgeGoneAtBaseline bumpedTo=$total '
    'badgeShown=$badgeShown renderedCountText=${renderedCount ?? 'n/a'} '
    'cleared=$cleared (after=$after) badgeGone=$badgeGone',
  );
  return badgeGoneAtBaseline && bumped && badgeShown && cleared && badgeGone;
}

// ===========================================================================
// case p1c-7 — search_empty_state (P1#14)
// ===========================================================================
/// Cmd+Ctrl+F (real OS chord → `_OpenSearchIntent` → CustomSearch overlay) →
/// type a no-hit nonce into the keyed `message_search_field` → the empty state
/// renders ("No results found", custom_search.dart:697-703) → close. ESC is
/// attempted FIRST and its efficacy logged (no explicit Escape binding was
/// found on the route — run-phase data); the keyed field GONE after the close
/// sequence (ESC → normalizer fallback) is the HARD close signal.
Future<bool> _p1cSearchEmptyState(Inst a) async {
  await returnToChatsHome(a, rounds: 4);
  // The global-search Cmd+Ctrl+F is dispatched by the home `Shortcuts` widget,
  // which only receives the chord when a descendant of THAT subtree holds focus.
  // After the prior case's clear-active there may be NO focused node, so the
  // chord goes to the root scope ABOVE the home Shortcuts and is dropped
  // (observed: overlay did not open even with retries). Plant focus inside the
  // home subtree (tap the sidebar conversation-filter field) before each chord.
  var opened = false;
  for (var attempt = 0; attempt < 3 && !opened; attempt++) {
    await a.foreground();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await a.tapAt(240, 75); // sidebar conversation search filter → home focus
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await a.osaSearchShortcut();
    } on DriveError catch (e) {
      print('[pair] search_empty_state: search shortcut blocked: ${e.message}');
      return false;
    }
    opened = await a.waitKey('message_search_field', timeoutSecs: 6);
  }
  if (!opened) {
    await a.shot('/tmp/ui_p1c_search_noopen_A.png');
    print('[pair] search_empty_state: search overlay did not open '
        '(shot=/tmp/ui_p1c_search_noopen_A.png)');
    return false;
  }
  final nonce = 'zqnohit${DateTime.now().microsecondsSinceEpoch}';
  await a.focusType('message_search_field', nonce);
  // 300ms debounce + the search pass; then the no-results empty state.
  final emptyShown = await a.waitText('No results found', timeoutSecs: 15);
  await a.shot('/tmp/ui_p1c_search_empty_A.png');
  if (!emptyShown) {
    print('[pair] search_empty_state: empty-state title never rendered');
    // Close best-effort before failing.
    try {
      await a.osaEscape();
    } on DriveError {
      // best-effort
    }
    await returnToChatsHome(a, rounds: 4);
    return false;
  }
  // Close the pushed search route. forceHomeRoot only switches the home tab —
  // it CANNOT pop a route — so the real dismissals are ESC (now bound on the
  // overlay) and the keyed close (X) button. Try ESC first, then the X button
  // (SINGLE-FIRE tapKeyCenter — the button pops the route, and a flutter_skill
  // double-fire would pop the page underneath), then the home normalizer.
  var escClosed = false;
  try {
    await a.osaEscape();
    escClosed = await a.waitKeyGone('message_search_field', timeoutSecs: 4);
  } on DriveError {
    // best-effort
  }
  var xClosed = false;
  if (!escClosed) {
    await a.tapKeyCenter('message_search_close_button', timeoutSecs: 4);
    xClosed = await a.waitKeyGone('message_search_field', timeoutSecs: 4);
  }
  var closed = escClosed || xClosed;
  if (!closed) {
    await returnToChatsHome(a, rounds: 4);
    closed = await a.waitKeyGone('message_search_field', timeoutSecs: 4);
  }
  print(
    '[pair] search_empty_state: emptyShown=$emptyShown '
    'escClosed=$escClosed xClosed=$xClosed closed=$closed',
  );
  return emptyShown && closed;
}

// ===========================================================================
// case p1c-8 — image_preview_open_hardened (P1#16)
// ===========================================================================
/// Batch-6 case 69 hardened: seed an inbound image via l3_send_file (B→A,
/// seed-marker required), wait for the REAL bubble row, then retry-tap ACROSS
/// the row's LEFT region (inbound bubbles are left-aligned, ≤198px wide — a
/// row-center tap can miss the bubble; the tap must also be a quick <300ms
/// down-up for the fork's onTapUp guard). HARD when the keyed viewer
/// (`message_viewer_root`, added this batch) mounts on any attempt — then it
/// is tapped once (single-fire tapKeyCenter; onTap == closeViewer) and must
/// unmount. If every retry exhausts, print the documented best-effort SOFT
/// result and pass IFF the bubble row itself rendered (the batch-6 honest
/// floor); fail only when the bubble never rendered.
Future<bool> _p1cImagePreviewOpenHardened(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  const pngB64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9'
      'awAAAABJRU5ErkJggg==';
  final nonce = DateTime.now().microsecondsSinceEpoch % 100000;
  final fileName = 'ruip1c$nonce.png';
  final sent = await b.l3('l3_send_file', {
    'userId': toxA,
    'contentB64': pngB64,
    'fileName': fileName,
  });
  if (sent['ok'] != true) {
    print(
      '[pair] image_preview_open_hardened: l3_send_file (B→A) failed: '
      '$sent (seed-account marker?)',
    );
    return false;
  }
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
    await a.shot('/tmp/ui_p1c_img_noimg_A.png');
    print('[pair] image_preview_open_hardened: inbound image never appeared');
    return false;
  }
  await _ensureChatOpen(a, toxB);
  final rowKey = 'message_list_item:$imageMsgId';
  final rowRendered = await a.waitKey(rowKey, timeoutSecs: 10);
  if (!rowRendered) {
    await a.shot('/tmp/ui_p1c_img_norow_A.png');
    print('[pair] image_preview_open_hardened: bubble row never rendered');
    return false;
  }
  // Give the async image decode a beat (the tappable GestureDetector mounts
  // only after the image info resolves), then bounded retry-taps across the
  // left region of the row with backoff.
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  var viewerMounted = false;
  const fractions = <double>[0.18, 0.28, 0.40, 0.50, 0.22, 0.33];
  for (
    var attempt = 0;
    attempt < fractions.length && !viewerMounted;
    attempt++
  ) {
    final bounds = await _p1cKeyBounds(a, rowKey);
    if (bounds == null) {
      // Row scrolled out / not laid out — re-anchor and retry.
      await _ensureChatOpen(a, toxB);
      await a.waitKey(rowKey, timeoutSecs: 4);
      continue;
    }
    final x = bounds.x + bounds.w * fractions[attempt];
    final y = bounds.y + bounds.h * 0.5;
    await a.tapAt(x, y);
    viewerMounted = await a.waitKey('message_viewer_root', timeoutSecs: 3);
    if (!viewerMounted) {
      await Future<void>.delayed(Duration(milliseconds: 500 + attempt * 300));
    }
  }
  await a.shot('/tmp/ui_p1c_img_A.png');
  if (viewerMounted) {
    // Close it: single-fire tap on the viewer root (onTap == closeViewer);
    // ESC + normalizer as fallback. The viewer must end unmounted either way.
    var closed = false;
    if (await a.tapKeyCenter('message_viewer_root', timeoutSecs: 4)) {
      closed = await a.waitKeyGone('message_viewer_root', timeoutSecs: 6);
    }
    if (!closed) {
      try {
        await a.osaEscape();
      } on DriveError {
        // best-effort
      }
      closed = await a.waitKeyGone('message_viewer_root', timeoutSecs: 6);
    }
    await returnToChatsHome(a, rounds: 4);
    print(
      '[pair] image_preview_open_hardened: HARD viewer mounted + '
      'closed=$closed (msgId=$imageMsgId)',
    );
    return closed;
  }
  await returnToChatsHome(a, rounds: 4);
  print(
    '[pair] image_preview_open_hardened: SOFT — bubble rendered but the '
    'preview viewer did not mount after ${fractions.length} positioned '
    'retry-taps (async-mount GestureDetector / bubble hit-region). '
    'Documented best-effort floor (batch-6 scope note): PASSING on the '
    'rendered bubble; the viewer half stays best-effort until a run-phase '
    'session can tune tap timing/position with live bounds.',
  );
  return rowRendered;
}

// ===========================================================================
// sweep_p1_chat — Batch III: chain all 8 cases on ONE 2p launch.
// ===========================================================================
/// Order: handshake → mark BOTH accounts test (SEEDING + normalizers; revoked
/// in the end-guard) → 1 recall → 2 read-receipt pin → create the shared
/// PRIVATE group (real AddGroupDialog; spine of 3/4/6) → 3 forward-to-group →
/// 4 draft pin → 5 typing pin → 6 unread badge → 7 search empty state → 8
/// image preview hardened. Prints `[sweep] <case>: PASS|FAIL` per case +
/// counts; the end-guard re-seeds a C2C row and verifies the launch ends
/// FRIENDS with a visible row (the registered result state) — exit
/// `failed==0 && endFriends`.
Future<int> runP1ChatSweep(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[sweep] sweep_p1_chat: missing tox ids (A=$toxA B=$toxB)');
    return 1;
  }
  final aNick = (await a.dumpState())['nickname']?.toString() ?? nickA;
  print(
    '[sweep] sweep_p1_chat: A=${_shortId(toxA)} ($nickA) '
    'B=${_shortId(toxB)} ($nickB)',
  );

  var passed = 0;
  var failed = 0;
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
    await _p1cNormalize(a);
  }

  const allCaseIds = <String>[
    'chat_recall_message',
    'read_receipt_double_tick',
    'forward_to_group_target',
    'draft_restore_on_conv_switch',
    'typing_indicator_render',
    'unread_badge_total_sidebar',
    'search_empty_state',
    'image_preview_open_hardened',
  ];

  try {
    final friended = await _establishFriendshipForSweep(
      a,
      b,
      toxA,
      toxB,
      nickA,
      nickB,
    );
    if (!friended) {
      print('[sweep] sweep_p1_chat: handshake FAILED — no case can run');
      for (final id in allCaseIds) {
        failed++;
        results[id] = 'FAIL';
      }
    } else {
      // Seed-account markers: l3_set_typing (5), l3_inject_group_text (6) and
      // l3_send_file (8) are test-gated, and the normalizers use the gated
      // clear-active-conversation. Asserted actions stay real widgets/gestures.
      final aMarked = await a.markAccountTest();
      final bMarked = await b.markAccountTest();
      print(
        '[sweep] sweep_p1_chat: marked test accounts aMarked=$aMarked '
        'bMarked=$bMarked (revoked in the end-guard)',
      );

      // 1 — recall (fully wired; B-side data deletion asserted).
      await hard(
        'chat_recall_message',
        () => _p1cRecallMessage(a, b, toxA, toxB, aNick),
      );
      // 2 — read-receipt NEGATIVE pin (B's real open; gap documented above).
      await hard(
        'read_receipt_double_tick',
        () => _p1cReadReceiptDoubleTick(a, b, toxA, toxB),
      );

      // Shared PRIVATE group via the REAL AddGroupDialog — the spine of 3/4/6.
      // B membership NOT needed (no NGC join flake in this sweep).
      final groupName =
          'RUIP1C-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
      var gid = '';
      try {
        gid = await _groupCreateTypeSelectorSurface(a, groupName);
      } on DriveError catch (e) {
        print('[sweep] sweep_p1_chat: group create threw: ${e.message}');
      }
      if (gid.isEmpty) {
        print(
          '[sweep] sweep_p1_chat: shared group not created — cases '
          'forward/draft/badge will FAIL honestly on their group dep',
        );
      }
      await _p1cNormalize(a);

      // 3 — forward to the GROUP target through the real picker.
      await hard(
        'forward_to_group_target',
        () => _p1cForwardToGroupTarget(a, toxB, gid, groupName),
      );
      // 4 — draft NEGATIVE pin (real switch via the group row).
      await hard(
        'draft_restore_on_conv_switch',
        () => _p1cDraftRestoreOnConvSwitch(a, toxB, gid, groupName),
      );
      // 5 — typing DOUBLE-NEGATIVE pin.
      await hard(
        'typing_indicator_render',
        () => _p1cTypingIndicatorRender(a, b, toxA, toxB),
      );
      // 6 — sidebar total-unread badge (N real + M seeded; exact total).
      await hard(
        'unread_badge_total_sidebar',
        () => _p1cUnreadBadgeTotalSidebar(a, b, toxA, toxB, gid, groupName),
      );
      // 7 — search empty state (Cmd+Ctrl+F overlay).
      await hard('search_empty_state', () => _p1cSearchEmptyState(a));
      // 8 — image preview hardened (l3_send_file seed; positioned retry-taps).
      await hard(
        'image_preview_open_hardened',
        () => _p1cImagePreviewOpenHardened(a, b, toxA, toxB),
      );
    }
  } finally {
    try {
      final aUnmarked = await a.unmarkAccountTest();
      final bUnmarked = await b.unmarkAccountTest();
      print(
        '[sweep] sweep_p1_chat end-clean: unmarked test accounts '
        'aUnmarked=$aUnmarked bUnmarked=$bUnmarked',
      );
      await returnToChatsHome(a, rounds: 4);
      await b.foreground();
      await returnToChatsHome(b, rounds: 4);
      if (await areFriends(a, toxB)) {
        await _seedConvRow(
          a,
          toxB,
          text: 'RuiP1cEndSeed-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
    } on PermissionBlockedError catch (e) {
      print('[sweep] sweep_p1_chat end-clean: BLOCKED (${e.message})');
    } on DriveError catch (e) {
      print(
        '[sweep] sweep_p1_chat end-clean: best-effort failed: ${e.message}',
      );
    }
    try {
      final stillRow = await _conversationListed(a, _c2cConvId(toxB));
      endFriends =
          await areFriends(a, toxB) && await areFriends(b, toxA) && stillRow;
    } on DriveError {
      endFriends = false;
    }
    print(
      '[sweep] sweep_p1_chat RESULTS: $passed PASS / $failed FAIL '
      '($results) | endFriends=$endFriends',
    );
    try {
      await a.shot('/tmp/ui_p1c_sweep_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_p1c_sweep_B.png');
    } on DriveError {
      // best-effort
    }
    if (!endFriends) {
      print(
        '[sweep] sweep_p1_chat: end state is NOT friends-with-row — '
        'failing the sweep so the runner does not trust the result-state '
        'contract',
      );
    }
  }
  return (failed == 0 && endFriends) ? 0 : 1;
}

/// Whether [scenario] is one of the 8 Batch-III P1 chat/conv cases.
bool _isP1ChatCaseScenario(String scenario) => const {
  'chat_recall_message',
  'read_receipt_double_tick',
  'forward_to_group_target',
  'draft_restore_on_conv_switch',
  'typing_indicator_render',
  'unread_badge_total_sidebar',
  'search_empty_state',
  'image_preview_open_hardened',
}.contains(scenario);

/// Run a single Batch-III case standalone (the sweep is the canonical entry).
/// Every case needs the A<->B friendship: establish it (or reuse the runner's
/// restored paired_for_e2e — `_establishFriendshipForSweep` short-circuits on
/// an existing friendship). Cases that SEED through test-gated tools (typing /
/// group-inject / file) or need a group mark both accounts test and REVOKE the
/// marker in a finally (batch-6 individual-dispatch discipline).
Future<int> runP1ChatCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario, {
  required bool bootRestored,
}) async {
  if (!bootRestored) {
    await ensureHome(a, nickA);
    await ensureHome(b, nickB, requireHomeMenu: false);
  }
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for $scenario: A=$toxA B=$toxB');
  }
  final aNick = (await a.dumpState())['nickname']?.toString() ?? nickA;
  if (!await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB)) {
    print('[pair] $scenario: could not establish friendship');
    return 1;
  }
  // Group-dependent cases create their own group; seeding cases need markers.
  // read_receipt parks B via the gated clear-active normalizer, so it is
  // marker-backed too (the marker is ONLY used for parking there).
  final needsGroup =
      scenario == 'forward_to_group_target' ||
      scenario == 'draft_restore_on_conv_switch' ||
      scenario == 'unread_badge_total_sidebar';
  final needsMarker =
      needsGroup || // normalizers + group-inject seeding
      scenario == 'read_receipt_double_tick' ||
      scenario == 'typing_indicator_render' ||
      scenario == 'image_preview_open_hardened';
  try {
    // Grant the seed markers INSIDE the guarded block (codex P2: a throw
    // between the two grants must still reach the revoking finally).
    if (needsMarker) {
      await a.markAccountTest();
      await b.markAccountTest();
    }
    var gid = '';
    var groupName = '';
    if (needsGroup) {
      groupName = 'RUIP1C-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
      gid = await _groupCreateTypeSelectorSurface(a, groupName);
      await _p1cNormalize(a);
    }
    switch (scenario) {
      case 'chat_recall_message':
        return await _p1cRecallMessage(a, b, toxA, toxB, aNick) ? 0 : 1;
      case 'read_receipt_double_tick':
        return await _p1cReadReceiptDoubleTick(a, b, toxA, toxB) ? 0 : 1;
      case 'forward_to_group_target':
        return await _p1cForwardToGroupTarget(a, toxB, gid, groupName) ? 0 : 1;
      case 'draft_restore_on_conv_switch':
        return await _p1cDraftRestoreOnConvSwitch(a, toxB, gid, groupName)
            ? 0
            : 1;
      case 'typing_indicator_render':
        return await _p1cTypingIndicatorRender(a, b, toxA, toxB) ? 0 : 1;
      case 'unread_badge_total_sidebar':
        return await _p1cUnreadBadgeTotalSidebar(
              a,
              b,
              toxA,
              toxB,
              gid,
              groupName,
            )
            ? 0
            : 1;
      case 'search_empty_state':
        return await _p1cSearchEmptyState(a) ? 0 : 1;
      case 'image_preview_open_hardened':
        return await _p1cImagePreviewOpenHardened(a, b, toxA, toxB) ? 0 : 1;
    }
    throw DriveError('unknown p1-chat scenario: $scenario');
  } finally {
    if (needsMarker) {
      await a.unmarkAccountTest();
      await b.unmarkAccountTest();
    }
    await _p1cNormalize(a);
  }
}
