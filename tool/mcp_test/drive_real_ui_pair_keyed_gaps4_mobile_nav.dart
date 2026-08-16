// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// ===========================================================================
// case — mobile_chat_back_clears_active_peer
// ===========================================================================
/// THE REGRESSION THIS CASE EXISTS FOR (a real, user-facing product bug found
/// on 2026-08-16 and fixed the same day by
/// `lib/navigation/active_conversation_route_observer.dart`).
///
/// On a compact/phone shell there is no master-detail right pane, so opening a
/// chat PUSHES the UIKit message route. The bind happens on the way IN —
/// `onTapConversationItem` calls `FfiChatService.setActivePeer(conversationID)`
/// — and NOTHING used to unbind on the way OUT. Backing out of a chat therefore
/// left `_activePeerId` pointing at the conversation the user had just left, and
/// `FfiChatService.getC2CUnreadCount` short-circuits to 0 for the active peer:
/// every later message from that friend was counted as already-read. No row
/// badge, no bottom-nav badge, no tray badge — indefinitely, until the user
/// happened to open some other chat.
///
/// WHY THE EXISTING CASES COULD NOT CATCH IT. Every unread case in the harness
/// unbinds EXPLICITLY (`Inst.clearActiveConversation` → `l3_clear_active_
/// conversation`), which is exactly the step the product was missing. This case
/// is the one that never touches that seam after the bind: it opens the chat by
/// a REAL conversation-row tap and leaves by a REAL back-button tap, then reads
/// the product state.
///
/// WHAT IS ASSERTED, in order:
///   1. the row tap BINDS — `activePeerId` becomes non-null. (A run where the
///      bind never happened would make step 3 vacuous, so this is a hard gate,
///      not a convenience wait.)
///   2. the real back control pops the chat route (`chat_header_back_button`,
///      the same control a user taps; the chat surface must be gone).
///   3. `activePeerId` is null again — the fix, read straight off the product.
///   4. and the consequence a user actually sees: ONE real inbound from B while
///      A sits on the chats home now raises `totalUnreadCount` to 1. Before the
///      fix this stayed 0 forever.
///
/// SKIPS on any shell without a bottom navigation bar: a wide/master-detail
/// shell never pushes the chat route at all (it rebinds the right pane through
/// `_selectConversation`), so there is no pop to observe. That is a genuine
/// form-factor gate, and it is declared in `_keyedGaps4ExpectedSkipCases`.
Future<bool?> _kg4MobileChatBackClearsActivePeer(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  const label = 'mobile_chat_back_clears_active_peer';
  await a.foreground();
  await returnToChatsHome(a, rounds: 4);
  if (!await _msPhoneShell(a)) {
    print(
      '[pair] $label: SKIP — this shell has no bottom navigation bar '
      '(home_bottom_nav unresolvable), so the chat opens in a master-detail '
      'pane instead of a pushed route and there is no pop to observe.',
    );
    return null;
  }

  final convId = _c2cConvId(toxB);
  // Start from a genuinely unbound, drained baseline. The clear is the GATED
  // tool, so it goes through Inst.clearActiveConversation (which now recovers
  // from `non_test_account` itself) and a refusal FAILS rather than being
  // swallowed into a vacuous baseline.
  final aMarked = await a.markAccountTest();
  try {
    await openChat(a, toxB);
    await returnToChatsHome(a, rounds: 4);
    try {
      await a.clearActiveConversation();
    } on DriveError catch (e) {
      print('[pair] $label: baseline unbind refused (${e.message})');
      return false;
    }
    final (drained, baseTotal) = await _p1cWaitTotalUnread(
      a,
      (u) => u == 0,
      timeoutSecs: 20,
    );
    if (!drained) {
      print('[pair] $label: baseline never drained (total=$baseTotal)');
      return false;
    }

    // --- 1. REAL row tap binds the peer ---
    if (!await _waitConversationListed(a, convId, timeoutSecs: 12)) {
      print('[pair] $label: the C2C row never appeared in the list');
      return false;
    }
    await _tapConversationRowReal(a, 'conversation_list_item:$convId');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final bound = await _kg4WaitDump(
      a,
      (s) => (s['activePeerId']?.toString() ?? '').isNotEmpty,
      timeoutSecs: 15,
    );
    if (!bound) {
      print(
        '[pair] $label: the row tap never bound an active peer '
        '(${await _kg4ActiveConvSnapshot(a)}) — the pop assertion below would '
        'be vacuous, so this is a hard precondition failure',
      );
      return false;
    }

    // --- 2. REAL back control pops the pushed chat route ---
    final backTapped = await a.tapKeyCenter(
      'chat_header_back_button',
      timeoutSecs: 8,
    );
    if (!backTapped) {
      print('[pair] $label: chat_header_back_button did not resolve');
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    // ONSTAGE, not merely "resolvable". flutter_skill's `tap` fires a widget's
    // callback TWICE, so one driver tap on a push-navigating row can push TWO
    // identical routes; popping once leaves the buried copy laid out (an opaque
    // MaterialPageRoute does not Offstage the route beneath it), and an
    // existence-based check would then resolve that buried copy forever and
    // report "still there". `ui_key_center`'s `onstage` flag comes from the
    // debugVisitOnstageChildren walk, which prunes exactly that.
    final popped = await _kg4WaitKeyOffstage(a, 'chat_header_back_button');

    // --- 3. the fix: the peer is unbound by the POP alone ---
    final unbound = await _kg4WaitDump(
      a,
      (s) => (s['activePeerId']?.toString() ?? '').isEmpty,
      timeoutSecs: 15,
    );
    print(
      '[pair] $label: bound=$bound popped=$popped unbound=$unbound '
      '${await _kg4ActiveConvSnapshot(a)}',
    );

    // --- 4. the consequence: an inbound now COUNTS ---
    final probe = 'KG4BACK-${DateTime.now().microsecondsSinceEpoch % 1000000}';
    await b.foreground();
    await openChat(b, toxA);
    if (!await sendComposerMessage(b, probe)) {
      print('[pair] $label: B could not send through its real composer');
      return false;
    }
    await a.foreground();
    final (counted, total) = await _p1cWaitTotalUnread(
      a,
      (u) => u == 1,
      timeoutSecs: 45,
    );
    final delivered = (await _c2cMessages(
      a,
      toxB,
    )).any((m) => (m['text']?.toString() ?? '').contains(probe));
    print(
      '[pair] $label: afterBackOut totalUnreadCount=$total want 1 '
      'delivered=$delivered perConv=${await _p1cConvUnreads(a)}',
    );
    if (!counted && delivered) {
      print(
        '[pair] $label: the message ARRIVED but was counted as read — that is '
        'the active-peer leak this case exists for: nothing unbound the peer '
        'when the pushed chat route popped, so getC2CUnreadCount kept '
        'short-circuiting to 0 for it.',
      );
    }
    // Leave the unread state clean for whatever runs next.
    await openChat(a, toxB);
    await returnToChatsHome(a, rounds: 4);
    try {
      await a.clearActiveConversation();
    } on DriveError {
      // best-effort teardown; the assertions above already stand.
    }
    return bound && popped && unbound && counted;
  } finally {
    if (aMarked) await a.unmarkAccountTest();
  }
}

/// Poll `l3_dump_state` until [test] holds, returning WHETHER it held.
///
/// `Inst.waitState` throws on timeout, which is right for a precondition but
/// wrong for an assertion: this case has to REPORT that the peer stayed bound,
/// not abort with a DriveError the sweep would tally as an exception.
Future<bool> _kg4WaitDump(
  Inst inst,
  bool Function(Map<String, dynamic>) test, {
  int timeoutSecs = 15,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (test(await inst.dumpState())) return true;
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  return false;
}

/// Poll until [key] is no longer ONSTAGE (absent, or present only through
/// `ui_key_center`'s full-tree fallback — i.e. buried under a covering route).
Future<bool> _kg4WaitKeyOffstage(
  Inst inst,
  String key, {
  int timeoutSecs = 8,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final r = await inst.l3('ui_key_center', {'key': key});
      if (r['ok'] != true || r['onstage'] != true) return true;
    } on DriveError {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}
