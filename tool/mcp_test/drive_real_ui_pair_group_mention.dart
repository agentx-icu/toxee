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
// SCOPE: group_at_member_send is the real HARD gate. group_at_all_send is a
// DOCUMENTED SKIP — @All is admin-gated and toxee's UIKit current user id is the
// V2TIM login placeholder, not the tox pubkey, so isGroupAdmin is always false
// and the @All row never renders (see _gmAtAllSendSkip for the full evidence +
// the real fix, which is a separate root-cause task).
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
  // group_at_all_send is a documented SKIP (architectural blocker — see
  // _gmAtAllSendSkip); it needs no group, so short-circuit before paying setup.
  // 75 = the real-UI SKIP exit code (distinct from 0=PASS / 1=FAIL / 78=BLOCKED).
  if (scenario == 'group_at_all_send') {
    _gmAtAllSendSkip();
    return 75;
  }
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

    // group_at_all_send — documented SKIP (architectural blocker).
    _gmAtAllSendSkip();
    skipped++;
    print('[sweep] sweep_group_mention SKIP: group_at_all_send');
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
  await openGroupChat(a, groupId: gidA, groupName: gname);
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
  await a.osaType(nonce);
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
  final last = await _gmTypeMentionAndSend(
    a,
    gidA,
    gname,
    'mention_member:${member.userID}',
    nonce,
  );
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

/// group_at_all_send: DOCUMENTED SKIP (verify-first, codex-confirmed 2026-06-13).
///
/// The desktop @All mention entry is added ONLY when `isGroupAdmin` is true
/// (`tencent_cloud_chat_message_input_desktop.dart:331`). `isGroupAdmin` is
/// computed by matching a group member whose `userID == currentUserid`
/// (`tencent_cloud_chat_message_input_container.dart:742`), where `currentUserid`
/// is the UIKit current user id. toxee seeds that from `FfiChatService.selfId`
/// (`home_page_bootstrap.dart`), which is the **V2TIM LOGIN STRING** (a
/// placeholder), NOT the tox public key (`placeholder_account_migration.dart:17`:
/// "selfId returns the V2TIM login string, not the Tox ID"). NGC member userIDs
/// are 64-hex tox pubkeys, so `pubkey == <placeholder>` is always false ->
/// `isGroupAdmin` is always false -> the @All row never renders -> nothing to tap.
///
/// The real fix is to seed `UikitDataFacade` currentUser.userID with the real tox
/// public key. That touches the placeholder-migration system and ~18
/// currentUser.userID usages — a separate root-cause task, deliberately NOT
/// papered over with a fake pass here. The fork key `mention_member:atAll`
/// already exists, so this flips to a real gate once that identity fix lands.
void _gmAtAllSendSkip() {
  print(
    '[pair] group_at_all_send: SKIP — @All is admin-gated and toxee\'s UIKit '
    'current user id is the V2TIM login placeholder, not the tox pubkey '
    '(placeholder_account_migration.dart:17), so isGroupAdmin is always false '
    'for NGC groups and the @All entry never renders. Fix = real-pubkey UIKit '
    'currentUser (broad blast radius; separate root-cause task).',
  );
}
