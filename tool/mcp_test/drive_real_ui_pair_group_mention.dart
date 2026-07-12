// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Group @-mention — REAL-control cases from REAL_APP_UI_TEST_INVENTORY §7.5.1
// (2026-06-12 verify-first review). Two-process: A drives the real group
// composer, types "@", picks a row from the REAL desktop mention panel, and
// sends. The panel rows carry a fork automation key
// (`mention_member:<ngcUserId>` / `mention_member:atAll`, added to
// tencent_cloud_chat_message_input_member_mention_panel.dart).
//
// HONEST ASSERTION (verify-first): toxee's tox backend carries NO
// groupAtUserList metadata (it is a Tencent-IM concept; dump_state exposes no
// at-list and the bridge transmits none). The @ is therefore TEXT-ONLY — picking
// a member runs the fork's `_replaceAtTag(showName)`, so the SENT message text
// contains "@<label>". The gate asserts that text, which is exactly what a toxee
// user sees. (If a future bridge adds structured at-lists, strengthen here.)
//
// SCOPE: group_at_member_send and group_at_all_send are both real HARD gates.
// group_at_all_send was a documented SKIP until the @All identity blocker was
// fixed — @All is admin-gated, and isGroupAdmin was always false because the
// UIKit currentUser.userID was the V2TIM placeholder AND the admin match was an
// exact 76-vs-64-char comparison. Both are fixed now (real tox-id currentUser in
// home_page_bootstrap + the normalized `_resolveIsGroupAdmin` in the message
// input), so the group owner sees @All and the row renders (see _gmAtAllSend).
//
// Mobile parity: the desktop mention panel is a distinct widget from the mobile
// @-list (`mobile/tencent_cloud_chat_at_group_member_list.dart`); this macOS
// harness drives the desktop panel only. A mobile @ smoke would need the
// analogous key on the mobile list — tracked as a follow-up under the mobile
// real-app smoke (§7.2#6/7), not duplicated here.

const _groupMentionCases = {'group_at_member_send', 'group_at_all_send'};

bool _isGroupMentionCaseScenario(String scenario) =>
    _groupMentionCases.contains(scenario);

Future<int> runGroupMentionCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  if (!await _ensureFriendshipForMention(a, b, nickA, nickB)) {
    print('[pair] $scenario: could not establish friendship');
    return 1;
  }
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-MENTION',
  );
  if (est == null) {
    print('[pair] $scenario: could not establish a two-process group');
    return 1;
  }
  var ok = false;
  try {
    ok = switch (scenario) {
      'group_at_member_send' =>
        await _gmAtMemberSend(a, est.groupIdA, est.groupName, nickB),
      'group_at_all_send' =>
        await _gmAtAllSend(a, est.groupIdA, est.groupName),
      _ => throw ArgumentError('unsupported group-mention scenario: $scenario'),
    };
  } finally {
    await _gmCleanup(a, b, nickA, nickB, est);
  }
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runGroupMentionSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  if (!await _ensureFriendshipForMention(a, b, nickA, nickB)) {
    print('[sweep] sweep_group_mention: could not establish friendship');
    return 1;
  }
  // ONE group + B-join shared by both @ cases (launch/group reuse).
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-MENTION',
  );
  if (est == null) {
    print('[sweep] sweep_group_mention: could not establish a two-process group');
    return 1;
  }

  var passed = 0;
  var failed = 0;
  var skipped = 0;
  try {
    // group_at_member_send — HARD gate (real member row; not admin-gated).
    var ok = false;
    try {
      ok = await _gmAtMemberSend(a, est.groupIdA, est.groupName, nickB);
    } on PermissionBlockedError {
      rethrow;
    } on Object catch (e, st) {
      ok = false;
      print('[sweep] sweep_group_mention EXCEPTION in group_at_member_send: $e');
      print(st);
    }
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print(
      '[sweep] sweep_group_mention ${ok ? 'PASS' : 'FAIL'}: group_at_member_send',
    );

    // group_at_all_send — REAL gate now (the @All identity blocker is fixed:
    // real-tox-id currentUser + normalized admin match → @All renders for the
    // owner). Reuses the same group. WINDOWS SKIP: this case's whole point is
    // proving the ADMIN-GATED @All entry RENDERS in the mention panel, which
    // only appears from real char-by-char "@" typing through onChanged — the
    // l3_mention_send seam used for @member would just inject the @All sentinel
    // and BYPASS the render check (a fake pass), so it stays SKIP-with-reason.
    if (_isWindowsRealUi) {
      skipped++;
      print('[sweep] sweep_group_mention SKIP: group_at_all_send — verifies the '
          'admin-gated @All panel RENDERS, which needs char-by-char "@" typing '
          '(undrivable headless); the mention seam would bypass the render check');
    } else {
      var okAll = false;
      try {
        okAll = await _gmAtAllSend(a, est.groupIdA, est.groupName);
      } on PermissionBlockedError {
        rethrow;
      } on Object catch (e, st) {
        okAll = false;
        print('[sweep] sweep_group_mention EXCEPTION in group_at_all_send: $e');
        print(st);
      }
      if (okAll) {
        passed++;
      } else {
        failed++;
      }
      print(
        '[sweep] sweep_group_mention ${okAll ? 'PASS' : 'FAIL'}: group_at_all_send',
      );
    }
  } finally {
    await _gmCleanup(a, b, nickA, nickB, est);
  }

  print(
    '[sweep] sweep_group_mention summary: passed=$passed failed=$failed '
    'skipped=$skipped',
  );
  return failed == 0 ? 0 : 1;
}

/// Idempotent friendship gate: real-UI handshake only when not already friends
/// (so the sweep works on a fresh no-friend launch AND reuses an existing
/// friendship inside sweep_friendship_optimized).
Future<bool> _ensureFriendshipForMention(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) return false;
  if (await areFriends(a, toxB) && await areFriends(b, toxA)) return true;
  return _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB);
}

/// Restore B's auto-accept, leave the shared group on both sides (so groups
/// don't accumulate across reused launches), land both on the chats home. The
/// A<->B friendship is preserved.
Future<void> _gmCleanup(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  _EstablishedGroup est,
) async {
  try {
    await _setAutoAcceptGroupInvites(b, est.priorAutoAccept);
  } on DriveError catch (e) {
    print('[pair] group_mention cleanup: restore auto-accept failed: ${e.message}');
  }
  await _leaveGroupUnchecked(a, est.groupIdA);
  await _leaveGroupUnchecked(b, est.groupIdB);
  try {
    await ensureHome(a, nickA);
    await ensureHome(b, nickB);
  } on Object catch (e) {
    print('[pair] group_mention cleanup: return home best-effort: $e');
  }
}

/// Ungated best-effort group leave for cleanup (real-UI accounts are non-test, so
/// the gated `l3_leave_group` would refuse — use the `_unchecked` plumbing hook).
Future<void> _leaveGroupUnchecked(Inst inst, String gid) async {
  if (gid.isEmpty) return;
  try {
    await inst.l3('l3_leave_group_unchecked', {'groupId': gid});
  } on DriveError catch (e) {
    print('[pair] group_mention cleanup: leave $gid best-effort: ${e.message}');
  }
}

/// Resolve B's NGC group-specific member userID (the value the mention panel keys
/// on) AND the display label the fork inserts. l3_group_member_list is test-gated,
/// so mark A, list, unmark — a SEED step; the asserted action stays the real
/// mention tap. Returns the first non-self member as (userID, label), or null.
///
/// The label mirrors the fork's `_getShowName = nameCard ?? nickName ?? userID`.
/// l3 exposes no nameCard (NGC groups have none), so the inserted "@<label>" is
/// the member's nickName when present, else its userID — assert against THIS, not
/// the runner's nickB (which can differ from the member's stored name).
Future<({String userID, String label})?> _resolveOtherMember(
  Inst a,
  String gid,
) async {
  Future<({String userID, String label})?> tryList() async {
    final r = await a.l3('l3_group_member_list', {'groupId': gid});
    if (r['ok'] != true) return null;
    final members = (r['members'] as List?) ?? const <dynamic>[];
    for (final m in members) {
      if (m is Map && m['isSelf'] != true) {
        final uid = m['userID']?.toString() ?? '';
        if (uid.isEmpty) continue;
        final nick = m['nickName']?.toString() ?? '';
        return (userID: uid, label: nick.isNotEmpty ? nick : uid);
      }
    }
    return null;
  }

  final direct = await tryList();
  if (direct != null) return direct;
  // Gated refusal on a non-test account: mark, retry, unmark (restore non-test).
  final marked = await a.markAccountTest();
  try {
    return await tryList();
  } finally {
    if (marked) await a.unmarkAccountTest();
  }
}

/// Shared driver: open the group composer, type "@", tap [mentionKey] in the REAL
/// desktop mention panel, append [nonce], and send via the osascript Return path
/// (retry until the last group message carries the nonce). Returns the final sent
/// text (empty on send failure) so the caller can assert the inserted "@<label>".
Future<String> _gmTypeMentionAndSend(
  Inst a,
  String gidA,
  String gname,
  String mentionKey,
  String nonce,
) async {
  // A freshly-created group sorts to the conversation-list bottom (no message →
  // ts 0) where a synthetic coordinate row-tap doesn't reliably fire its onTap
  // (→ currentConversation null). This is timing-sensitive and reproduces on
  // macOS too, especially under same-host TCP-only transport (slower group
  // connect). Open via the production `_openChat` seam on ALL platforms — the
  // asserted action here is the @-mention insert + send, NOT opening the group
  // from the list (that row-tap is covered by group-create / group2 sweeps).
  await openGroupChat(a, groupId: gidA, groupName: gname, viaL3Seam: true);
  await a.foreground();
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await a.tapAt(_composerX, _composerY);
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await a.osaClear();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  // Typing "@" raises the fork's mention panel (onChanged detects '@').
  await a.osaType('@');
  if (!await a.waitKeyCenter(mentionKey, timeoutSecs: 8)) {
    print('[pair] group_mention: panel row "$mentionKey" did not appear');
    return '';
  }
  if (!await a.tapKeyAt(mentionKey)) {
    print('[pair] group_mention: panel row "$mentionKey" not tappable');
    return '';
  }
  // _replaceAtTag has now inserted "@<label> " and put the cursor after it.
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await a.foreground();
  await a.tapAt(_composerX, _composerY);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  // PASTE the nonce (atomic), never keystroke it: when the host Mac's input
  // source is a CJK IME (this is a zh user's daily driver), `System Events
  // keystroke` letters enter the IME's composition and commit as hanzi —
  // observed live: " atmem<micros>" became " 他么么<micros>", failing the
  // nonce match on BOTH broad passes. The '@' above stays a real keystroke
  // (IME-transparent punctuation) because the mention panel only opens from
  // char-typed onChanged.
  await a.osaPaste(nonce);
  await Future<void>.delayed(const Duration(milliseconds: 600));
  // Send (retry until the TARGET GROUP's last message carries the nonce —
  // conversation-scoped so an unrelated conversation can't false-pass/fail).
  final convId = 'group_$gidA';
  for (var attempt = 0; attempt < 6; attempt++) {
    await a.foreground();
    await a.tapAt(_composerX, _composerY);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await a.osaReturn();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final last = await _lastMessageForConversation(a, convId);
    if (last.contains(nonce)) return last;
  }
  return await _lastMessageForConversation(a, convId);
}

/// group_at_member_send: @-mention a specific group member (B). The sent message
/// text must contain "@<B nickname>" (the inserted mention) and the nonce.
Future<bool> _gmAtMemberSend(
  Inst a,
  String gidA,
  String gname,
  String nickB,
) async {
  final member = await _resolveOtherMember(a, gidA);
  if (member == null) {
    print('[pair] group_at_member_send: could not resolve the other member');
    return false;
  }
  final nonce = ' atmem${DateTime.now().microsecondsSinceEpoch}';
  String last;
  if (_isWindowsRealUi) {
    // The mention panel only renders from real char-by-char "@" typing through
    // the composer's onChanged, which the headless Windows harness can't drive.
    // Send the @-mention through the production composer mention-send seam
    // (l3_mention_send → sendTextMessage with mentionedUsers + "@<label>" text),
    // the exact data a real select-member-then-send produces. Retry until the
    // target group's last message carries the nonce.
    await openGroupChat(a, groupId: gidA, groupName: gname, viaL3Seam: true);
    await a.foreground();
    final convId = 'group_$gidA';
    last = '';
    for (var attempt = 0;
        attempt < 4 && !last.contains(nonce.trim());
        attempt++) {
      await a.l3('l3_mention_send', {
        'userId': member.userID,
        'label': member.label,
        'text': nonce.trim(),
      });
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      last = await _lastMessageForConversation(a, convId);
    }
  } else {
    last = await _gmTypeMentionAndSend(
      a,
      gidA,
      gname,
      'mention_member:${member.userID}',
      nonce,
    );
  }
  await a.shot('/tmp/ui_group_mention_member_${a.name}.png');
  final sent = last.contains(nonce.trim());
  // Assert the fork-inserted label (nickName ?? userID), NOT the runner nickB —
  // they can differ. nickB is logged only for context.
  final hasMention = last.contains('@${member.label}');
  final shortUid = member.userID.length > 8
      ? member.userID.substring(0, 8)
      : member.userID;
  print(
    '[pair] group_at_member_send: member=$shortUid label="${member.label}" '
    'nickB="$nickB" sent=$sent hasMention=$hasMention last="$last"',
  );
  return sent && hasMention;
}

/// group_at_all_send: REAL gate (was a documented SKIP until the @All identity
/// fix landed). The desktop @All entry renders only when `isGroupAdmin` is true
/// (`tencent_cloud_chat_message_input_desktop.dart`). That was always false
/// because (1) the UIKit currentUser.userID was the V2TIM login placeholder, now
/// set to the real tox id in home_page_bootstrap (group2), and (2) the admin
/// match was an EXACT 76-char-vs-64-char comparison, now a normalized
/// public-key match (`_resolveIsGroupAdmin` in the message-input container). The
/// group creator is the OWNER (role 400), so isGroupAdmin resolves true and the
/// `mention_member:atAll` row renders — which `_gmTypeMentionAndSend` requires
/// (it returns '' if the row never appears). A non-empty sent text with the
/// nonce therefore PROVES @All rendered + was tappable + sent.
Future<bool> _gmAtAllSend(Inst a, String gidA, String gname) async {
  final nonce = ' atall${DateTime.now().microsecondsSinceEpoch}';
  final last = await _gmTypeMentionAndSend(
    a,
    gidA,
    gname,
    'mention_member:atAll',
    nonce,
  );
  await a.shot('/tmp/ui_group_mention_atall_${a.name}.png');
  final sent = last.contains(nonce.trim());
  // The @All entry rendered + was tappable iff _gmTypeMentionAndSend returned a
  // non-empty sent text (it bails to '' when the row never appears). The fork's
  // _replaceAtTag inserts "@<tL10n.atAll>", so the sent text carries an '@'.
  final hasMention = last.contains('@');
  print(
    '[pair] group_at_all_send: sent=$sent hasMention=$hasMention last="$last"',
  );
  return sent && hasMention;
}
