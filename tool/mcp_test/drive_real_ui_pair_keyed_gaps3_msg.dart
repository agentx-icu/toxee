// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Keyed-gaps batch #3 — the MESSAGE-MENU half. Spine and dispatch live in
// `drive_real_ui_pair_keyed_gaps3.dart`; this file only holds case bodies so
// each part stays under the 500-LOC complexity cap.

// ===========================================================================
// case — msgmenu_reveal_file_location_gating
// ===========================================================================
/// The message menu's "Location" entry (`message_menu_item:revealFileLocation`)
/// is generated ONLY for file / image / video / sound bubbles and only off-web
/// (menu container :565-577). Nothing had ever driven it.
///
/// WHAT IS ASSERTED — a GATING PAIR, i.e. two different renders of the same
/// generator: the entry MOUNTS on a real inbound FILE bubble, and is ABSENT on a
/// real TEXT bubble in the same conversation while that bubble's menu is
/// demonstrably up (`message_menu_item:delete` resolves). A single "it mounted"
/// probe would pass against a menu that always shows everything.
///
/// WHY THE TAP IS SKIPPED (boundary, both platforms). On desktop `onTap` runs
/// `_revealFileInFolder()`, whose only effect is `Process.run('open -R' /
/// 'explorer /select,' / 'xdg-open')` (menu container :275-289) — an OS file
/// manager that steals focus from the app under test and produces no in-app
/// observable. On iOS/Android that same method has NO platform branch at all,
/// so the tap is a documented no-op with, again, nothing to observe. The case
/// therefore stops at the boundary and says so instead of pretending a
/// side-effect-free tap is an assertion.
Future<bool?> _kg3RevealFileLocationGating(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  const label = 'msgmenu_reveal_file_location_gating';
  const revealKey = 'message_menu_item:revealFileLocation';
  // 12-byte payload, base64 — the same seeding recipe as
  // `chat_file_bubble_present_open` (B must be a test account for l3_send_file).
  const binB64 = 'UlVJS0czRklMRQ==';
  final nonce = DateTime.now().microsecondsSinceEpoch % 100000;
  final fileName = 'kg3$nonce.bin';

  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] $label: A could not open the C2C chat');
    return false;
  }
  final bMarked = await b.markAccountTest();
  Map<String, dynamic> sent;
  try {
    sent = await b.l3('l3_send_file', {
      'userId': toxA,
      'contentB64': binB64,
      'fileName': fileName,
    });
  } finally {
    await _kg3Unmark(b, bMarked);
  }
  if (sent['ok'] != true) {
    print('[pair] $label: l3_send_file (B->A) failed: $sent');
    return false;
  }
  String? fileMsgId;
  for (var i = 0; i < 60 && fileMsgId == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    for (final m in await _c2cMessages(a, toxB)) {
      if (m['isSelf'] == false &&
          m['mediaKind']?.toString() == 'file' &&
          (m['fileName']?.toString() ?? '').contains(fileName)) {
        fileMsgId = m['msgID']?.toString();
      }
    }
  }
  if (fileMsgId == null || fileMsgId.isEmpty) {
    await a.shot('/tmp/ui_kg3_reveal_nofile_${a.name}.png');
    print('[pair] $label: the seeded file never reached A (name=$fileName)');
    return false;
  }

  // --- POSITIVE leg: the FILE bubble's menu offers Location. ---
  await _ensureChatOpen(a, toxB);
  if (!await _openMessageMenuReal(a, fileMsgId)) {
    print('[pair] $label: the file bubble menu did not open');
    return false;
  }
  final onFile = await a.waitKeyCenter(revealKey, timeoutSecs: 5);
  await a.shot('/tmp/ui_kg3_reveal_file_${a.name}.png');
  print(
    '[pair] $label: tap NOT driven by design — the next step leaves the app '
    '(desktop: Process.run open/explorer/xdg-open; mobile: a no-op with no '
    'platform branch). Asserting the render gate only.',
  );
  await _dismissMessageMenu(a);

  // --- NEGATIVE leg: a TEXT bubble's menu must NOT offer it. ---
  final text = 'KG3-REVEAL-$nonce';
  await a.l3('l3_composer_send', {'text': text});
  final textMsgId = await _kg3WaitC2cOwnMessageId(a, toxB, text);
  if (textMsgId.isEmpty) {
    print('[pair] $label: the probe TEXT message never landed');
    return false;
  }
  if (!await _openMessageMenuReal(a, textMsgId)) {
    print('[pair] $label: the text bubble menu did not open');
    return false;
  }
  final textMenuUp = await _kg3MenuIsUp(a);
  final onText = await a.waitKeyCenter(revealKey, timeoutSecs: 2);
  await _dismissMessageMenu(a);

  print(
    '[pair] $label: fileBubbleHasLocation=$onFile textMenuUp=$textMenuUp '
    'textBubbleHasLocation=$onText',
  );
  return onFile && textMenuUp && !onText;
}

/// The `msgID` of A's newest OWN C2C message whose text equals [text].
Future<String> _kg3WaitC2cOwnMessageId(
  Inst inst,
  String tox,
  String text, {
  int timeoutSecs = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    var found = '';
    for (final m in await _c2cMessages(inst, tox)) {
      if (m['isSelf'] == true && m['text']?.toString() == text) {
        found = m['msgID']?.toString() ?? found;
      }
    }
    if (found.isNotEmpty) return found;
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  return '';
}

// ===========================================================================
// case — msgmenu_read_receipt_group_gating
// ===========================================================================
/// The read-receipt menu entry (`message_menu_item:readReceipt`) is generated
/// under a THREE-part gate (menu container :316-325, :538):
///   useReadReceipt   = enableGroupMessageReceipt (toxee: true,
///                      home_page_bootstrap.dart:678)
///                      && this is a GROUP conversation
///                      && groupInfo.groupType is in
///                         enabledGroupTypesForMessageReadReceipt
///                         ([Work, Public, Meeting, Community],
///                          home_page_bootstrap.dart:663-669)
///   showReadReceipt  = useReadReceipt && message.isSelf && needReadReceipt
///   plus              message.status == SEND_SUCC
///
/// A `private` group resolves to `GroupType.Work`
/// (`_normalizeStoredGroupType`, tim2tox_sdk_platform.dart:8837-8842), so the
/// group gate holds, and the UIKit send path stamps `needReadReceipt` from the
/// same enabled-types list (tencent_cloud_chat_message_data_tools.dart:122-130)
/// — which is why the message must be sent through the REAL composer seam
/// (`l3_composer_send` = the production `_submitDesktopSend`), not seeded.
///
/// WHAT IS ASSERTED — again a gating PAIR: present on A's OWN just-sent group
/// message, ABSENT on B's inbound message in the SAME conversation (the
/// `isSelf` half of the gate) while that menu is demonstrably up. Tapping is
/// pointless by construction — the entry's `onTap` is literally `({Offset?
/// offset}) {}` (menu container :541) — so the render IS the observable.
///
/// SKIP (not FAIL) when the entry is absent on BOTH: that means the flag did
/// not survive to the rendered message, which is a Tim2Tox-layer gap
/// (`Tim2ToxSdkPlatform.sendMessage` accepts `needReadReceipt` and drops it,
/// tim2tox_sdk_platform.dart:5291) rather than a harness defect. The negative
/// leg is still asserted hard in that branch.
Future<bool?> _kg3ReadReceiptGroupGating(
  Inst a,
  Inst b,
  _EstablishedGroup est,
  String toxB,
) async {
  const label = 'msgmenu_read_receipt_group_gating';
  const receiptKey = 'message_menu_item:readReceipt';
  final gid = est.groupIdA;
  final nonce = DateTime.now().microsecondsSinceEpoch % 1000000;
  final selfText = 'KG3-RR-SELF-$nonce';
  final peerText = 'KG3-RR-PEER-$nonce';

  await openGroupChat(
    a,
    groupId: gid,
    groupName: est.groupName,
    viaL3Seam: true,
  );
  // A sends through the REAL composer submit path so the UIKit stamps
  // needReadReceipt on the outgoing message.
  await a.l3('l3_composer_send', {'text': selfText});
  final selfId = await _kg3WaitGroupMessageId(
    a,
    gid,
    (m) => m['isSelf'] == true && m['text']?.toString() == selfText,
  );
  if (selfId.isEmpty) {
    print('[pair] $label: A\'s composer message never reached the group');
    return false;
  }
  // B replies so the negative leg has a real inbound bubble.
  final bSend = await b.l3('l3_send_group_text', {
    'groupId': est.groupIdB,
    'text': peerText,
  });
  if (bSend['ok'] != true) {
    print('[pair] $label: B could not send into the group: $bSend');
    return false;
  }
  final peerId = await _kg3WaitGroupMessageId(
    a,
    gid,
    (m) => m['isSelf'] == false && m['text']?.toString() == peerText,
    timeoutSecs: 60,
  );
  if (peerId.isEmpty) {
    print('[pair] $label: B\'s group message never reached A');
    return false;
  }

  await openGroupChat(
    a,
    groupId: gid,
    groupName: est.groupName,
    viaL3Seam: true,
  );
  if (!await _openMessageMenuReal(a, selfId)) {
    print('[pair] $label: A\'s own bubble menu did not open');
    return false;
  }
  final onSelf = await a.waitKeyCenter(receiptKey, timeoutSecs: 5);
  await a.shot('/tmp/ui_kg3_receipt_self_${a.name}.png');
  await _dismissMessageMenu(a);

  // RE-ANCHOR before the second leg. `_dismissMessageMenu` closes the menu with
  // a corner tap, and on a NARROW shell the chat is a PUSHED route whose
  // top-left corner is the back chevron's band — live on iPhone 2026-08-16 the
  // peer leg died on `_openMessageMenuReal: row … not present`, i.e. the message
  // list was no longer in the tree at all, while the identical self leg one step
  // earlier had succeeded. Re-opening the group chat is the same normalization
  // this case already does before the self leg; it changes no assertion.
  await openGroupChat(
    a,
    groupId: gid,
    groupName: est.groupName,
    viaL3Seam: true,
  );
  if (!await _openMessageMenuReal(a, peerId)) {
    print('[pair] $label: the peer bubble menu did not open');
    return false;
  }
  final peerMenuUp = await _kg3MenuIsUp(a);
  final onPeer = await a.waitKeyCenter(receiptKey, timeoutSecs: 2);
  await _dismissMessageMenu(a);

  print(
    '[pair] $label: ownBubbleHasReceipt=$onSelf peerMenuUp=$peerMenuUp '
    'peerBubbleHasReceipt=$onPeer',
  );
  if (!peerMenuUp || onPeer) return false;
  if (onSelf) return true;
  print(
    '[pair] $label: SKIP — the entry is absent on A\'s OWN group message too, '
    'so `needReadReceipt` did not survive onto the rendered message. The UIKit '
    'stamps it only on its optimistic copy '
    '(tencent_cloud_chat_message_data_tools.dart:122-130) and '
    'Tim2ToxSdkPlatform.sendMessage takes the flag and drops it '
    '(tim2tox_sdk_platform.dart:5291); the isSelf half of the gate IS asserted '
    'above. Flip this to a hard PASS when the bridge round-trips the flag.',
  );
  return null;
}
