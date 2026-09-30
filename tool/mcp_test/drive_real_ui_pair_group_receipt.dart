// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Two-process GROUP read-receipt round trip.
//
// Its own part file rather than more lines in drive_real_ui_pair_group_menu.dart
// (pinned at 567 LOC): this family is already split by domain, and a new
// scenario is exactly the thing the split exists for. Only the dispatch line
// lands in the parent.

/// A's OWN (isSelf) group row carrying [text], from the group branch of
/// `l3_dump_state`. `isRead` on that row is what the author flips when a
/// matching group READ receipt comes back.
Future<Map<String, dynamic>?> _ownGroupRow(
  Inst inst,
  String conversationId,
  String text,
) async {
  final st = await inst.dumpState(conversationId: conversationId);
  for (final m in (st['messages'] as List? ?? const [])) {
    if (m is Map && m['isSelf'] == true && m['text'] == text) {
      return m.cast<String, dynamic>();
    }
  }
  return null;
}

/// Two-process group READ-receipt round trip: A authors a group message, B marks
/// the group read, and A's OWN row must flip `isRead` false -> true.
///
/// WHY THIS EXISTS, next to `group_menu_mark_read_unread`. That case proves the
/// READER's unread drops to 0, which is local read state and says nothing about
/// a receipt reaching the author. The author's own row only flips when a
/// matching group receipt arrives over the wire, so this is the assertion the
/// group read-receipt work was missing — its C2C twin is
/// `_p1cReadReceiptDoubleTick`. A single-instance l3 class cannot express it at
/// all, which is why it lives here.
///
/// B reads through `l3_mark_read`'s group branch, NOT `l3_mark_group_read`: the
/// latter needs `force: "true"` because the author's `needReadReceipt` intent has
/// no Tox wire carrier, and a forced call cannot claim the product gate was
/// exercised. The mark-read path does not consult that flag.
Future<int> runGroupReadReceiptTick(
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
    namePrefix: 'RUI-GRTICK',
  );
  if (est == null) {
    print('[pair] FAIL: group read-receipt could not establish a group');
    return 1;
  }
  final convA = 'group_${est.groupIdA}';
  final convB = 'group_${est.groupIdB}';
  try {
    // B must NOT be viewing the group: an inbound message for the active
    // conversation is auto-marked read, so there would be no read TRANSITION
    // for B to drive and nothing to receipt.
    await returnToChatsHome(b, rounds: 4);
    await b.l3('l3_set_active_conversation', <String, dynamic>{});

    final nonce = DateTime.now().microsecondsSinceEpoch;
    final text = 'RUIGRTICK-$nonce';
    await openGroupChat(a, groupId: est.groupIdA, groupName: est.groupName);
    if (!await sendComposerMessage(a, text)) {
      print('[pair] FAIL: group read-receipt — A could not send');
      return 1;
    }
    if (!await _waitGroupMessageAnyConversation(b, text, timeoutSecs: 60)) {
      print('[pair] FAIL: group read-receipt — B never received the message');
      return 1;
    }

    // Baseline, so the flip is evidential rather than a value that was already
    // true: A's own row must NOT be read before B reads it.
    final before = await _ownGroupRow(a, convA, text);
    if (before == null) {
      print('[pair] FAIL: group read-receipt — A own row missing from dump');
      return 1;
    }
    if (before['isRead'] == true) {
      print(
        '[pair] FAIL: group read-receipt — A own row was ALREADY isRead before '
        'B read it, so a later true proves nothing (row=$before)',
      );
      return 1;
    }
    if (!await _waitConversationUnread(b, convB, (u) => u > 0)) {
      final entry = await _conversationEntry(b, convB);
      print(
        '[pair] FAIL: group read-receipt — unread did not accrue on B '
        '(entry=$entry)',
      );
      return 1;
    }

    final marked = await b.l3('l3_mark_read', {'groupId': est.groupIdB});
    if (marked['ok'] != true) {
      print('[pair] FAIL: l3_mark_read(group) on B failed: $marked');
      return 1;
    }
    final cleared = await _waitConversationUnread(b, convB, (u) => u == 0);

    var flipped = false;
    Map<String, dynamic>? after;
    for (var i = 0; i < 40 && !flipped; i++) {
      after = await _ownGroupRow(a, convA, text);
      flipped = after?['isRead'] == true;
      if (!flipped) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    await a.shot('/tmp/ui_group_receipt_tick_A.png');
    if (flipped && cleared) {
      print(
        '[pair] PASS: real-UI group read receipt round trip — B mark-read '
        'cleared unread and A own row flipped isRead '
        '(gid=${_shortId(est.groupIdA)})',
      );
      return 0;
    }
    print(
      '[pair] FAIL: group read receipt (bUnreadCleared=$cleared '
      'aOwnRowIsRead=$flipped row=$after marked=$marked)',
    );
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
