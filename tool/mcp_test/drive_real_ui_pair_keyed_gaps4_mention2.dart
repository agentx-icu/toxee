// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// ===========================================================================
// keyed-gaps #4, batch 2 — the mobile @All/multi-select mention contract and
// the search-contact bind path. Split from …_keyed_gaps4_mobile.dart only
// because that file sits at the 500-LOC gate; same library, same helpers.
// ===========================================================================

/// mobile_mention_at_all_inserts — the @All row on the MOBILE picker.
///
/// THE REGRESSION THIS PINS (found by coverage inventory, fixed in the fork
/// the same day): `TencentCloudChatAtGroupMemberList.defaultBuilder` dropped
/// the `isGroupAdmin` verdict the container resolved, and `_getListTag` gated
/// the @All row on `groupType ∈ {Work, Public, Meeting}` — Tencent-IM
/// taxonomy that toxee's lowercase types ('group', 'conference', …) can never
/// satisfy. Net effect: @All was UNREACHABLE on mobile for every toxee group
/// while the desktop inline panel offered it freely. A — the group creator,
/// hence Owner/admin — must see it.
///
/// WHY NOT MULTI-SELECT: `_onSelectGroupMember` special-cases the @everyone
/// sentinel — tapping @All SUBMITS AND POPS IMMEDIATELY (it cannot be
/// combined with member rows), and a two-account pair has only one non-self
/// member anyway. The single-member multi-tick path is covered by
/// `mobile_mention_picker_confirm_inserts`; this case asserts the @All
/// fast-path end-to-end: tap -> auto-submit -> "@All " insertion -> what the
/// group actually receives.
Future<bool?> _kg4MentionAtAllInserts(Inst a, _EstablishedGroup est) async {
  const label = 'mobile_mention_at_all_inserts';
  const backKey = 'mention_member_list_back_button';
  const confirmKey = 'mention_member_list_confirm_button';
  const atAllKey = 'mention_member:atAll';
  final gid = est.groupIdA;
  await openGroupChat(
    a,
    groupId: gid,
    groupName: est.groupName,
    viaL3Seam: true,
  );
  if (await _kg4ComposerKind(a) != _Kg4Composer.mobile) {
    print(
      '[pair] $label: SKIP — the desktop composer resolves mentions through '
      'the inline panel; sweep_group_mention covers @All there '
      '(group_at_all_send).',
    );
    return null;
  }
  final nonce = DateTime.now().microsecondsSinceEpoch % 1000000;
  final prefix = 'KG4ATALL$nonce';
  if (!await _kg4SetComposerText(a, prefix)) return false;
  if (!await _kg4SetComposerText(a, '$prefix@')) return false;
  if (!await a.waitKeyCenter(confirmKey, timeoutSecs: 12)) {
    print('[pair] $label: the picker route never mounted');
    await _kg3PopToRoot(a);
    return false;
  }
  // THE pinned assertion: an admin on a toxee group must get the @All row.
  if (!await a.waitKeyCenter(atAllKey, timeoutSecs: 8)) {
    await a.shot('/tmp/ui_kg4_atall_norow_${a.name}.png');
    await a.tapKeyCenter(backKey, timeoutSecs: 6);
    await _kg3PopToRoot(a);
    print(
      '[pair] $label: mention_member:atAll never rendered — the '
      'defaultBuilder isGroupAdmin drop / Tencent group-type gate regression',
    );
    return false;
  }
  // Tapping @All submits and pops the picker BY ITSELF — no confirm tap.
  if (!await a.tapKeyCenter(atAllKey, timeoutSecs: 6)) {
    await a.shot('/tmp/ui_kg4_atall_stuck_${a.name}.png');
    await _kg3PopToRoot(a);
    print('[pair] $label: the @All row could not be tapped');
    return false;
  }
  final routeGone = await _kg4WaitKeyCenterGone(a, confirmKey, timeoutSecs: 10);
  await Future<void>.delayed(const Duration(milliseconds: 800));
  // As with the sibling picker cases: composer text has no read seam, so the
  // insertion is asserted in what the group receives.
  await a.l3('l3_composer_send', const {});
  final sent = await _kg4WaitGroupTextStartingWith(a, gid, prefix);
  await a.shot('/tmp/ui_kg4_atall_${a.name}.png');
  if (sent == null) {
    print('[pair] $label: the composer message never reached the group');
    return false;
  }
  // The @All label is localized (All / 所有人 / みんな …), so the insertion is
  // asserted structurally but STRICTLY: the whole message must be exactly
  // "<prefix>@<label> " — the label non-empty and the trailing space present
  // (the fork inserts "@<label> "), so a surviving bare '@' or a mangled
  // label cannot false-pass.
  final mentionInserted = RegExp(
    '^${RegExp.escape(prefix)}@\\S+ \$',
  ).hasMatch(sent);
  print(
    '[pair] $label: routeGone=$routeGone sent="$sent" '
    'mentionInserted=$mentionInserted',
  );
  return routeGone && mentionInserted;
}

/// mobile_search_contact_back_unbinds — the bind entry point NO case drove:
/// a global-search CONTACT row (`search_result_contact:<uid>`, mobile leg =
/// `pushCompactChatRoute`), then the same pop-unbind contract
/// `mobile_chat_back_clears_active_peer` pins for the conversation-row entry.
/// Same active-peer-leak consequence if the bind or the observer misses this
/// route: the friend's later messages are counted as read forever.
Future<bool?> _kg4SearchContactBindsBack(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  const label = 'mobile_search_contact_back_unbinds';
  await a.foreground();
  await returnToChatsHome(a, rounds: 4);
  if (!await _msPhoneShell(a)) {
    print(
      '[pair] $label: SKIP — no bottom navigation bar, so search results '
      'rebind the master-detail pane instead of pushing a chat route.',
    );
    return null;
  }
  final aMarked = await a.markAccountTest();
  try {
    // Baseline: genuinely unbound, unread drained (mirrors the sibling case).
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

    if (!await _openGlobalSearch(a)) {
      print('[pair] $label: the search overlay did not open');
      return false;
    }
    // The contacts filter matches remark | nick | userID (case-insensitive
    // substring), so an ID prefix is a deterministic query that cannot
    // collide with the peer's nickname rendering in the results.
    if (!await a.focusType('message_search_field', toxB.substring(0, 16))) {
      print('[pair] $label: could not type into message_search_field');
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // friendInfo.userID surfaces both as the full 76-char Tox id and as the
    // bare 64-char public key depending on the roster source (same duality
    // as contact_list_item:*), so probe both key forms.
    String? rowKey;
    for (final cand in <String>{
      'search_result_contact:$toxB',
      'search_result_contact:${toxB.substring(0, 64)}',
    }) {
      if (await a.waitKeyCenter(cand, timeoutSecs: 5)) {
        rowKey = cand;
        break;
      }
    }
    if (rowKey == null) {
      await a.shot('/tmp/ui_kg4_searchcontact_norow_${a.name}.png');
      print(
        '[pair] $label: no search_result_contact row resolved for either id '
        'form after an ID-prefix query',
      );
      await _kg3PopToRoot(a);
      return false;
    }
    if (!await a.tapKeyCenter(rowKey, timeoutSecs: 6)) {
      print('[pair] $label: the contact row could not be tapped');
      await _kg3PopToRoot(a);
      return false;
    }

    // --- bind (pushCompactChatRoute leg) ---
    final bound = await _kg4WaitDump(
      a,
      (s) => (s['activePeerId']?.toString() ?? '').isNotEmpty,
      timeoutSecs: 15,
    );
    if (!bound) {
      print(
        '[pair] $label: the search-row open never bound an active peer '
        '(${await _kg4ActiveConvSnapshot(a)})',
      );
      await _kg3PopToRoot(a);
      return false;
    }

    // --- pop unbinds (route-observer leg); chat popped back onto SEARCH ---
    if (!await a.tapKeyCenter('chat_header_back_button', timeoutSecs: 8)) {
      print('[pair] $label: chat_header_back_button did not resolve');
      await _kg3PopToRoot(a);
      return false;
    }
    final popped = await _kg4WaitKeyOffstage(a, 'chat_header_back_button');
    final unbound = await _kg4WaitDump(
      a,
      (s) => (s['activePeerId']?.toString() ?? '').isEmpty,
      timeoutSecs: 15,
    );

    // --- the user-visible consequence: one inbound now COUNTS ---
    final probe = 'KG4SRCH-${DateTime.now().microsecondsSinceEpoch % 1000000}';
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
    print(
      '[pair] $label: bound=$bound popped=$popped unbound=$unbound '
      'counted=$counted total=$total rowKey=$rowKey',
    );

    // Teardown: close the search overlay, drain the probe unread.
    await _kg3PopToRoot(a);
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

/// Shared mobile @-picker flow, ending at the EXIT tap (codex: the common
/// flow ends at confirm; insertion/deletion callers diverge after it, so no
/// send-path plumbing). Seam-sets [prefix] then appends the single '@' (the
/// controller listener pushes the picker route), waits for the route, then
/// waits for [member]'s row to render (BOTH legs assert row visibility, as
/// before the refactor), then either taps it and CONFIRM
/// ([selectAndConfirm]) or leaves the selection empty and taps BACK.
/// Returns null after printing the failed step (popped to root); otherwise
/// whether the route left the tree.
Future<({bool routeGone})?> _kg4DrivePickerFlow(
  Inst a, {
  required String label,
  required String prefix,
  required ({String userId, String nickName}) member,
  required bool selectAndConfirm,
}) async {
  const backKey = 'mention_member_list_back_button';
  const confirmKey = 'mention_member_list_confirm_button';
  if (!await _kg4SetComposerText(a, prefix)) return null;
  if (!await _kg4SetComposerText(a, '$prefix@')) return null;
  final routeUp =
      await a.waitKeyCenter(confirmKey, timeoutSecs: 12) &&
      await a.waitKeyCenter(backKey, timeoutSecs: 4);
  if (!routeUp) {
    await a.shot('/tmp/ui_kg4_mention_noroute_${a.name}.png');
    await _kg3PopToRoot(a);
    print(
      '[pair] $label: the @-mention picker route never mounted after the '
      'composer gained a single "@" — `_onTextChanged` should have called '
      '`onChooseGroupMembers()` and pushed TencentCloudChatAtGroupMemberList',
    );
    return null;
  }
  final rowKey = 'mention_member:${member.userId}';
  if (!await a.waitKeyCenter(rowKey, timeoutSecs: 8)) {
    await a.shot('/tmp/ui_kg4_mention_norow_${a.name}.png');
    await a.tapKeyCenter(backKey, timeoutSecs: 6);
    await _kg3PopToRoot(a);
    print(
      '[pair] $label: the picker mounted but member row $rowKey did not — '
      'the list is built from `_dataProvider.groupMemberList` minus self, '
      'and l3_group_member_list reported this member as a non-self peer',
    );
    return null;
  }
  if (selectAndConfirm && !await a.tapKeyCenter(rowKey, timeoutSecs: 6)) {
    await a.tapKeyCenter(backKey, timeoutSecs: 6);
    await _kg3PopToRoot(a);
    print('[pair] $label: the member row could not be tapped');
    return null;
  }
  final exitKey = selectAndConfirm ? confirmKey : backKey;
  if (!await a.tapKeyCenter(exitKey, timeoutSecs: 8)) {
    await _kg3PopToRoot(a);
    print('[pair] $label: $exitKey could not be tapped');
    return null;
  }
  final routeGone =
      await _kg4WaitKeyCenterGone(a, confirmKey, timeoutSecs: 10) &&
      await _kg4WaitKeyCenterGone(a, backKey, timeoutSecs: 6);
  return (routeGone: routeGone);
}

/// mobile_mention_deletion_clears_token (#10c) — the composer's ATOMIC
/// mention TEXT deletion: one REAL backspace anywhere inside the inserted
/// "@<label> " removes the WHOLE token from the text
/// (tencent_cloud_chat_message_input_mobile.dart `!isAddText` branch — the
/// code the iPhone `_replaceAtTag` fix hardened). That branch also prunes
/// `_mentionedUsers`, but toxee's wire carries no groupAtUserList, so the
/// pruning is UNOBSERVABLE end-to-end — a focused widget test on the fork
/// input is the recorded follow-up; this case pins the TEXT contract only.
/// Composer text has no read seam, so the pin is what the GROUP receives:
/// exactly the prefix, with no '@' or label residue. The backspace must be a
/// REAL OS key event; only Android can inject one (adb keyevent 67) — other
/// shells SKIP.
Future<bool?> _kg4MentionDeletionClearsToken(
  Inst a,
  _EstablishedGroup est,
) async {
  const label = 'mobile_mention_deletion_clears_token';
  final gid = est.groupIdA;
  await openGroupChat(
    a,
    groupId: gid,
    groupName: est.groupName,
    viaL3Seam: true,
  );
  // Per the keyed-gaps4 contract (sweep_tally doc): DESKTOP is the honest
  // SKIP; an UNKNOWN composer means the chat surface is missing — a FAIL.
  final composer = await _kg4ComposerKind(a);
  if (composer == _Kg4Composer.desktop) {
    print(
      '[pair] $label: SKIP — desktop composer resolves mentions through the '
      'inline panel (sweep_group_mention territory).',
    );
    return null;
  }
  if (composer != _Kg4Composer.mobile) {
    print('[pair] $label: composer state $composer — chat surface missing');
    return false;
  }
  if (!a.isAndroid) {
    print(
      '[pair] $label: SKIP — the atomic-deletion contract needs a REAL OS '
      'backspace, only injectable on Android (adb keyevent 67).',
    );
    return null;
  }
  final member = await _kg4PickPeerMember(a, gid, label);
  if (member == null) return false;
  final nonce = DateTime.now().microsecondsSinceEpoch % 1000000;
  final prefix = 'KG4DEL$nonce';
  final flow = await _kg4DrivePickerFlow(
    a,
    label: label,
    prefix: prefix,
    member: member,
    selectAndConfirm: true,
  );
  if (flow == null) return false;
  await Future<void>.delayed(const Duration(milliseconds: 900));
  // The seam-driven insertion leaves no REAL focus/caret for OS key events
  // (live: the first DEL was a no-op). Give the field a real tap, force the
  // caret to LINE END (single-line prefix, so line end == text end; a
  // mis-landed caret false-FAILS, never false-passes), then one backspace
  // lands on the trailing space — inside the token window.
  if (!await a.tapKeyCenter('chat_input_text_field', timeoutSecs: 6)) {
    print('[pair] $label: composer field tap failed');
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (!await _androidKeyEvent(a, _kcAndroidMoveEnd)) {
    print('[pair] $label: MOVE_END injection failed');
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!await _androidKeyEvent(a, _kcAndroidDel)) {
    print('[pair] $label: adb backspace injection failed');
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 900));
  await a.l3('l3_composer_send', const {});
  final sent = await _kg4WaitGroupTextStartingWith(a, gid, prefix);
  await a.shot('/tmp/ui_kg4_mentiondel_${a.name}.png');
  if (sent == null) {
    print('[pair] $label: the composer message never reached the group');
    return false;
  }
  // ATOMIC contract: the whole "@<label> " went with one backspace — the
  // received text is EXACTLY the prefix.
  final clean = sent == prefix;
  print(
    '[pair] $label: member=${member.userId} nick="${member.nickName}" '
    'sent="$sent" cleanDeletion=$clean',
  );
  return clean;
}
