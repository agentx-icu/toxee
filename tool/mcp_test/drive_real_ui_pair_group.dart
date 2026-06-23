// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

Future<bool> _sendAndWait(
  Inst sender,
  Inst receiver,
  String receiverPubkey,
  String text, {
  int timeoutSecs = 60,
}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    await openChat(sender, receiverPubkey);
    final sent = await sendComposerMessage(sender, text);
    final received = await _waitLastMessage(
      receiver,
      text,
      timeoutSecs: timeoutSecs,
    );
    if (sent && received) return true;
    print(
      '[pair] WARN sendAndWait retry for "$text" '
      '(attempt ${attempt + 1}/2 sent=$sent recv=$received '
      'senderConv=${await _currentConversationId(sender)} '
      'receiverLast=${await _lastMessage(receiver)})',
    );
    await sender.shot('/tmp/send_fail_${sender.name}_${attempt + 1}.png');
    await receiver.foreground();
    await receiver.shot('/tmp/send_fail_${receiver.name}_${attempt + 1}.png');
  }
  return false;
}

Future<Set<String>> _groupConversationCandidates(Inst inst) async {
  final state = await inst.dumpState();
  final candidates = <String>{};
  final known = (state['knownGroups'] as List?) ?? const <dynamic>[];
  for (final g in known) {
    final id = g?.toString().trim() ?? '';
    if (id.isNotEmpty) candidates.add(id);
  }
  final convs = (state['conversations'] as List?) ?? const <dynamic>[];
  for (final c in convs) {
    if (c is! Map) continue;
    if (c['type'] != 2) continue;
    var cid = c['conversationID']?.toString().trim() ?? '';
    if (cid.isEmpty) continue;
    if (cid.startsWith('group_')) cid = cid.substring('group_'.length);
    if (cid.isNotEmpty) candidates.add(cid);
  }
  return candidates;
}

/// Whether the chat surface is on an OPEN group conversation. When
/// [requireGroupId] is given, the OPEN conversation must be exactly that group
/// (`group_<id>`) — not merely "some group". This matters across retries
/// (codex): `_leaveAllGroups` quits a group but does NOT clear the active
/// selection (the quit path leaves `activePeerId` set), so a stale `group_<old>`
/// detail would otherwise satisfy an any-group check and the next send would
/// target the wrong / already-left group.
Future<bool> _chatSurfaceReadyForAnyGroup(
  Inst inst, {
  int timeoutSecs = 10,
  String? requireGroupId,
}) async {
  final wantConv = requireGroupId == null ? null : 'group_$requireGroupId';
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final shellTab = await _homeShellTab(inst);
    final currentConversation = await _currentConversationId(inst);
    final hasInput = await inst.waitKey(
      'chat_input_text_field',
      timeoutSecs: 1,
    );
    final convOk = wantConv == null
        ? (currentConversation?.startsWith('group_') ?? false)
        : currentConversation == wantConv;
    if (shellTab == 'chats' && convOk && hasInput) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

Future<void> openGroupChat(
  Inst inst, {
  required String groupId,
  required String groupName,
  bool viaL3Seam = false,
}) async {
  await inst.foreground();
  // Require THIS group to be the open one — an early-return on "any group open"
  // would wrongly short-circuit when a stale (e.g. just-left) group detail is
  // still showing after a retry (codex).
  if (await _chatSurfaceReadyForAnyGroup(
    inst,
    timeoutSecs: 2,
    requireGroupId: groupId,
  )) {
    return;
  }
  // Opt-in reliable open via the production `_openChat` path (the ungated
  // l3_open_chat nav-stability seam the chat sweeps use for first-chat-open).
  // A FRESHLY-created conference/group opened AFTER the conversation list has
  // accumulated other rows (e.g. the account/conference sweeps) sorts to the
  // list BOTTOM (no message → ts 0), where the row is clipped at the viewport
  // edge and a synthetic CENTER tap does not reliably fire its onTap, leaving
  // currentConversation null. Driving the production handler deterministically
  // is MORE faithful than a flaky coordinate tap and is NOT the asserted action
  // (the profile/search surface stays a real gesture). DEFAULT stays the real
  // row tap so cases that ASSERT "open from the chat list" (e.g. S129
  // runGroupCreate, where the fresh group is the sole/top row of an empty list)
  // keep exercising — and can still regression-fail on — the keyed row onTap
  // rather than masking it through L3 (codex).
  if (viaL3Seam &&
      await inst.openChatViaL3(groupId: groupId) &&
      await _chatSurfaceReadyForAnyGroup(
        inst,
        timeoutSecs: 8,
        requireGroupId: groupId,
      )) {
    return;
  }
  final conversationKey = 'conversation_list_item:group_$groupId';
  DriveError? lastError;
  // Retry the whole row-tap + readiness: a FRESHLY-created conference can be
  // briefly not-yet-connected (group_connected=0), so the chat surface does not
  // always become ready on the first tap. Re-tap from the conversation list and
  // wait again, giving it a moment to connect between attempts.
  for (var attempt = 0; attempt < 3; attempt++) {
    await returnToChatsHome(inst, rounds: 4);
    var rowOpened = await inst.tryTapKey(conversationKey, retries: 1) ||
        await inst.tryTapKey('group_list_tile:$groupId', retries: 1);
    if (!rowOpened) {
      // A FRESHLY-created group/conference has no messages → its sort key is
      // `lastMessage.timestamp ?? 0` == 0 → it sorts to the BOTTOM of the conv
      // list, BELOW the fold, where the `ListView.builder` has not built its row
      // yet. Neither flutter_skill (whole-tree, needs the built element) nor a
      // coordinate tap can reach an unbuilt row — so scroll the conv list down
      // until the row is built + onstage, then tap its resolved center. (This is
      // why these cases only fail LATE in a shared launch, once the list has
      // accumulated other rows above the new group.)
      for (var i = 0;
          i < 12 && await inst.keyCenter(conversationKey) == null;
          i++) {
        await inst.scrollAtCoords(240, 400, dy: 600);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (await inst.keyCenter(conversationKey) != null) {
        rowOpened = await inst.tapKeyCenter(conversationKey, timeoutSecs: 6);
      }
    }
    if (!rowOpened) {
      rowOpened = await _tryTapText(inst, groupName);
    }
    if (!rowOpened) {
      lastError = DriveError(
        '[${inst.name}] failed to open group chat '
        '(groupId=${_shortId(groupId)} name="$groupName")',
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      continue;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (await _chatSurfaceReadyForAnyGroup(
      inst,
      timeoutSecs: 8,
      requireGroupId: groupId,
    )) {
      return;
    }
    lastError = DriveError(
      '[${inst.name}] group chat did not become ready '
      '(groupId=${_shortId(groupId)} name="$groupName" '
      'currentConversation=${await _currentConversationId(inst)})',
    );
    // Settle + retry (give the conference a moment to connect).
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  throw lastError ??
      DriveError('[${inst.name}] failed to open group chat '
          '(groupId=${_shortId(groupId)} name="$groupName")');
}

class _CreatedGroup {
  _CreatedGroup({required this.groupId, required this.chatId});
  final String groupId;
  final String chatId;
}

Future<_CreatedGroup> _createGroup(
  Inst inst,
  String name, {
  bool private = false,
}) async {
  final res = await inst.l3('l3_create_group', {
    'name': name,
    if (private) 'type': 'private',
  });
  if (res['error'] == 'non_test_account') {
    // Fresh / non-test account: l3_create_group is test-gated. Drive the REAL
    // AddGroupDialog instead — the genuinely valuable real-UI create path.
    return _createGroupViaUI(inst, name, groupType: private ? 'private' : 'public');
  }
  if (res['ok'] != true) {
    throw DriveError('[${inst.name}] l3_create_group failed: $res');
  }
  final groupId = (res['groupId']?.toString() ?? '').trim();
  final chatId = (res['chatId']?.toString() ?? '').trim();
  if (groupId.isEmpty) {
    throw DriveError('[${inst.name}] l3_create_group returned empty groupId');
  }
  if (chatId.length != 64) {
    throw DriveError(
      '[${inst.name}] l3_create_group returned invalid chatId '
      '(groupId=${_shortId(groupId)} chatId="$chatId")',
    );
  }
  return _CreatedGroup(groupId: groupId, chatId: chatId);
}

/// Invite [userId] (a friend's Tox id) to [groupId] over the friend connection.
Future<void> _inviteToGroup(Inst inst, String groupId, String userId) async {
  final res = await inst.l3('l3_invite_to_group', {
    'groupId': groupId,
    'userId': userId,
  });
  if (res['error'] == 'non_test_account') {
    // Fresh / non-test account: l3_invite_to_group is test-gated. Drive the
    // REAL group add-member screen instead.
    await _inviteToGroupViaUI(inst, groupId, userId);
    return;
  }
  if (res['ok'] != true) {
    throw DriveError('[${inst.name}] l3_invite_to_group failed: $res');
  }
}

/// Real-UI create-group for fresh/non-test accounts where `l3_create_group` is
/// test-gated. Drives the REAL AddGroupDialog (opened via the ungated
/// `l3_open_add_group_dialog` hook → pick Private → type name → Create) and
/// resolves A's own new group by its unique [name]. The 64-char NGC chat-id is
/// not surfaced through the UI path — runGroupMessage's PRIVATE flow never uses
/// it (peers connect over the friend link, not a chat-id DHT join) — so chatId
/// comes back empty.
Future<_CreatedGroup> _createGroupViaUI(
  Inst inst,
  String name, {
  String groupType = 'private',
}) async {
  await inst.foreground();
  final before = await _groupConversationCandidates(inst);
  final opened = await inst.l3('l3_open_add_group_dialog');
  if (opened['ok'] != true) {
    throw DriveError(
      '[${inst.name}] l3_open_add_group_dialog failed: $opened',
    );
  }
  if (!await inst.waitKey('add_group_create_name_input', timeoutSecs: 12)) {
    await inst.shot('/tmp/ui_group_create_noinput_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] real-UI create: AddGroupDialog name input never appeared',
    );
  }
  // Select the group-type segment. Keys live on KeyedSubtree label wrappers so
  // the tap is a single, locale-independent selection (selection is idempotent;
  // tapping Public too makes the choice deterministic rather than relying on the
  // default). Private = invite-only NGC (reliable same-host); conference =
  // legacy Tox conference (tox_conference_new).
  final segmentKey = switch (groupType) {
    'public' => 'add_group_type_public_segment',
    'conference' => 'add_group_type_conference_segment',
    _ => 'add_group_type_private_segment',
  };
  await inst.tapKey(segmentKey);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await inst.focusType('add_group_create_name_input', name);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('add_group_create_submit_button');
  // On success the dialog pops and A's own group surfaces as a fresh type==2
  // conversation titled [name]; resolve it unambiguously by that unique name.
  final gid = await _waitForJoinedGroup(
    inst,
    name,
    before: before,
    timeoutSecs: 30,
  );
  if (gid == null) {
    await inst.shot('/tmp/ui_group_create_fail_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] real-UI create: new group "$name" did not appear '
      'after Create',
    );
  }
  // For a PUBLIC group, resolve the 64-char NGC chat-id (a peer joins BY this id,
  // not the local "tox_N"). The create path only knows the local id; the chat-id
  // can lag the create by a tick, so the l3 resolver retries. Private/conference
  // groups join by invite (no chat-id needed) — skip the lookup for them.
  var chatId = '';
  if (groupType == 'public') {
    try {
      final r = await inst.l3('l3_group_chat_id', {'groupId': gid});
      if (r['ok'] == true) chatId = r['chatId']?.toString() ?? '';
    } on DriveError catch (e) {
      print('[${inst.name}] real-UI create: chat-id resolve failed: ${e.message}');
    }
  }
  return _CreatedGroup(groupId: gid, chatId: chatId);
}

/// Real-UI invite for fresh/non-test accounts where `l3_invite_to_group` is
/// test-gated. Deep-links to the REAL group add-member screen (ungated
/// `l3_open_group_add_member`), selects the friend via the real contact item,
/// and taps the real confirm button (`inviteUserToGroup`). [friendTox] is the
/// friend's Tox id; the add-member contact-item key is keyed by the friend's
/// stored userID, so resolve it from [inst]'s own contact list by pubkey (the
/// SAME list/format the key derives from) to avoid tox-id-vs-pubkey / casing
/// mismatches in the key suffix.
Future<void> _inviteToGroupViaUI(
  Inst inst,
  String groupId,
  String friendTox,
) async {
  final s = await inst.dumpState();
  String? friendUserId;
  for (final f in (s['friends'] as List?) ?? const []) {
    if (f is Map &&
        _pubkey(f['userId']?.toString() ?? '') == _pubkey(friendTox)) {
      friendUserId = f['userId']?.toString();
      break;
    }
  }
  if (friendUserId == null || friendUserId.isEmpty) {
    throw DriveError(
      '[${inst.name}] real-UI invite: friend ${_shortId(friendTox)} '
      'not in contact list',
    );
  }
  await inst.foreground();
  final opened = await inst.l3('l3_open_group_add_member', {
    'groupId': groupId,
  });
  if (opened['ok'] != true) {
    throw DriveError(
      '[${inst.name}] l3_open_group_add_member failed: $opened',
    );
  }
  final itemKey = 'add_member_contact_item:$friendUserId';
  if (!await inst.waitKey(itemKey, timeoutSecs: 12)) {
    await inst.shot('/tmp/ui_group_addmember_fail_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] real-UI invite: contact not selectable ($itemKey)',
    );
  }
  // KeyedSubtree-wrapped item → single-fire select (the toggle would net-empty
  // under flutter_skill's double tap otherwise). Confirm is likewise wrapped so
  // its invite+pop fires once.
  await inst.tapKey(itemKey);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('group_member_invite_confirm_button');
}

/// Enable native auto-accept of group invites on [inst] so an inbound PRIVATE
/// group invite is accepted over the friend link via `tox_group_invite_accept`
/// (the correct private-group join). Without this, a manual join-by-chat-id does
/// a public DHT join and lands the peer in a DISCONNECTED public group.
Future<void> _setAutoAcceptGroupInvites(Inst inst, bool value) async {
  var res = await inst.l3('l3_set_setting', {
    'key': 'autoAcceptGroupInvites',
    'value': '$value',
  });
  if (res['error'] == 'non_test_account') {
    // Fresh / non-test account: l3_set_setting is test-gated. Use the ungated
    // campaign hook (same Prefs + native ffi sync). Without this the whole
    // "B auto-joins" flow can't even start (codex CRITICAL).
    res = await inst.l3('l3_set_auto_accept_group_invites', {'value': '$value'});
  }
  // Hard gate (codex): this is the precondition that lets B accept the PRIVATE
  // invite over the friend link instead of a wrong public DHT join. If it didn't
  // stick, fail loudly rather than silently fall through to a misjoin.
  if (res['ok'] != true) {
    throw DriveError(
      '[${inst.name}] set autoAcceptGroupInvites=$value failed: $res',
    );
  }
}

Future<bool> _getAutoAcceptGroupInvites(Inst inst) async {
  final s = await inst.dumpState();
  return s['autoAcceptGroupInvites'] == true;
}

/// Poll until [inst]'s LIVE autoAcceptGroupInvites matches [expected]. The
/// l3_set_setting write must propagate to the cached/native flag before an
/// inbound invite can be auto-accepted; only checking the setter's ok is the
/// weaker precondition (codex). Mirrors the existing private-group drivers.
Future<bool> _waitAutoAcceptGroupInvites(
  Inst inst,
  bool expected, {
  int timeoutSecs = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _getAutoAcceptGroupInvites(inst) == expected) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Resolve B's auto-joined group for THIS attempt. B's auto-joined PRIVATE group
/// does not reliably surface in Dart-side `knownGroups` (that only tracks
/// SELF-created groups), so look at its type==2 CONVERSATIONS. Binds
/// UNAMBIGUOUSLY across retries (codex): prefer the conversation whose showName
/// is the attempt's UNIQUE [name]; before the name has synced, fall back to the
/// single fresh candidate vs [before] (knownGroups ∪ conversation gids) — if more
/// than one fresh candidate exists (e.g. a prior failed attempt's group surfaced
/// during this wait) it keeps polling rather than guessing. Returns null on
/// timeout.
Future<String?> _waitForJoinedGroup(
  Inst inst,
  String name, {
  required Set<String> before,
  int timeoutSecs = 45,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final state = await inst.dumpState();
    // 1. Exact name match (unambiguous — each retry uses a distinct name).
    for (final c in (state['conversations'] as List?) ?? const []) {
      if (c is! Map || c['type'] != 2) continue;
      if ((c['showName']?.toString() ?? '') != name) continue;
      var cid = c['conversationID']?.toString().trim() ?? '';
      if (cid.startsWith('group_')) cid = cid.substring('group_'.length);
      if (cid.isNotEmpty) return cid;
    }
    // 2. Fallback while the name hasn't synced: exactly ONE fresh candidate.
    final fresh = (await _groupConversationCandidates(inst)).difference(before);
    if (fresh.length == 1) return fresh.first;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return null;
}

/// Leave every group [inst] currently has (best-effort). Used to clean up a
/// failed retry attempt so the next one starts with NO group candidates, which
/// keeps the single-fresh resolution unambiguous.
Future<void> _leaveAllGroups(Inst inst) async {
  for (final gid in await _groupConversationCandidates(inst)) {
    try {
      final r = await inst.l3('l3_leave_group', {'groupId': gid});
      if (r['error'] == 'non_test_account') {
        // Fresh / non-test account: l3_leave_group is test-gated. Use the
        // ungated cleanup hook so a failed attempt's group doesn't leak into
        // the next retry (codex IMPORTANT — keeps single-fresh resolution sound).
        await inst.l3('l3_leave_group_unchecked', {'groupId': gid});
      }
    } on DriveError {
      // best effort
    }
  }
}

/// Wait until [inst] has no group conversation candidates left (after leaving).
Future<void> _waitGroupCandidatesDrained(
  Inst inst, {
  int timeoutSecs = 15,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if ((await _groupConversationCandidates(inst)).isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<String> _lastMessage(Inst inst) async {
  final s = await inst.dumpState();
  for (final c in (s['conversations'] as List? ?? const [])) {
    if (c is Map && c['lastMessageText'] != null) {
      return c['lastMessageText'].toString();
    }
  }
  return '';
}

Future<String> _lastMessageForConversation(
  Inst inst,
  String conversationId,
) async {
  final s = await inst.dumpState();
  for (final c in (s['conversations'] as List? ?? const [])) {
    if (c is! Map) continue;
    if (c['conversationID']?.toString() != conversationId) continue;
    return c['lastMessageText']?.toString() ?? '';
  }
  return '';
}

Future<bool> _waitGroupMessageAnyConversation(
  Inst inst,
  String text, {
  int timeoutSecs = 60,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    await inst.foreground();
    final candidates = await _groupConversationCandidates(inst);
    for (final candidate in candidates) {
      final state = await inst.dumpState(conversationId: 'group_$candidate');
      final messages = (state['messages'] as List?) ?? const <dynamic>[];
      for (final m in messages) {
        if (m is Map && m['text']?.toString() == text) {
          return true;
        }
      }
      if (await _lastMessageForConversation(inst, 'group_$candidate') == text) {
        return true;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  final candidates = await _groupConversationCandidates(inst);
  print(
    '[${inst.name}] WARN group text "$text" not found across candidates='
    '$candidates',
  );
  for (final candidate in candidates) {
    final state = await inst.dumpState(conversationId: 'group_$candidate');
    final messages = (state['messages'] as List?) ?? const <dynamic>[];
    final summary = <Map<String, Object?>>[
      for (final m in messages)
        if (m is Map)
          {'msgID': m['msgID'], 'isSelf': m['isSelf'], 'text': m['text']},
    ];
    print(
      '[${inst.name}] candidate group_$candidate '
      'last="${await _lastMessageForConversation(inst, 'group_$candidate')}" '
      'messages=$summary',
    );
  }
  return false;
}

Future<bool> _waitLastMessage(
  Inst inst,
  String text, {
  int timeoutSecs = 60,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _lastMessage(inst) == text) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

/// S62/S64: bidirectional message delivery driven through the REAL composer
/// across two processes. Assumes A and B are already friends.
Future<int> runMessage(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  int stamp,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final bobPk = _pubkey(toxB);
  final alicePk = _pubkey(toxA);
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print(
      '[pair] message scenario requires an existing friendship; run handshake first',
    );
    return 1;
  }
  final m1 = 'RUITEST-AtoB-$stamp';
  final m2 = 'RUITEST-BtoA-$stamp';

  final aOk = await _sendAndWait(a, b, bobPk, m1, timeoutSecs: 60);
  final bGot = await _waitLastMessage(b, m1, timeoutSecs: 2);
  print('[pair] A->B sent=$aOk received=$bGot ("$m1")');

  final bOk = await _sendAndWait(b, a, alicePk, m2, timeoutSecs: 60);
  final aGot = await _waitLastMessage(a, m2, timeoutSecs: 2);
  print('[pair] B->A sent=$bOk received=$aGot ("$m2")');

  await a.shot('/tmp/ui_message_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_message_B.png');

  if (aOk && bGot && bOk && aGot) {
    print('[pair] PASS: bidirectional real-UI message delivery');
    return 0;
  }
  print('[pair] FAIL: A->B(sent=$aOk,recv=$bGot) B->A(sent=$bOk,recv=$aGot)');
  return 1;
}

Future<int> _groupMemberCount(Inst inst, String groupId) async {
  try {
    final r = await inst.l3('l3_group_member_list', {'groupId': groupId});
    if (r['error'] == 'non_test_account') {
      // Fresh / non-test account: the full member-list tool is test-gated. Use
      // the ungated count hook so the peer-readiness gate can pass (codex
      // CRITICAL — otherwise the gate always sees 0 and never connects).
      final r2 = await inst.l3('l3_group_member_count', {'groupId': groupId});
      if (r2['ok'] != true) return 0;
      return (r2['count'] as num?)?.toInt() ?? 0;
    }
    if (r['ok'] != true) return 0;
    final members = (r['members'] as List?) ?? const [];
    return members.length;
  } on DriveError {
    return 0;
  }
}

/// NGC peer discovery on same-host is a timing race: after the joiner joins the
/// group, the creator and joiner must find each OTHER as group peers via the DHT
/// before any group message can deliver. A fixed post-join delay races this — the
/// send then fires with 0 peers and nothing is delivered (the "joiner shows an
/// empty group / creator keeps only its self-send" flake). Gate the send on the
/// real precondition: poll the group member list on BOTH sides until each sees
/// the other (>= 2 members = self + the peer).
Future<bool> _waitGroupPeersConnected(
  Inst a,
  String groupIdA,
  Inst b,
  String groupIdB, {
  int timeoutSecs = 90,
}) async {
  final sw = Stopwatch()..start();
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  var aCount = 0;
  var bCount = 0;
  while (DateTime.now().isBefore(deadline)) {
    aCount = await _groupMemberCount(a, groupIdA);
    bCount = await _groupMemberCount(b, groupIdB);
    if (aCount >= 2 && bCount >= 2) {
      print(
        '[pair] group peers connected after ${sw.elapsedMilliseconds}ms '
        '(A members=$aCount B members=$bCount)',
      );
      return true;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  print(
    '[pair] WARN group peers NOT connected within ${timeoutSecs}s '
    '(A members=$aCount B members=$bCount)',
  );
  return false;
}

// Bidirectional message delivery through a real-UI group. Defaults drive a
// PRIVATE NGC group (the validated `group_message` path); pass
// groupType:'conference' (+ distinct label/prefixes) to drive a legacy Tox
// CONFERENCE instead — same flow (create via the real dialog, A invites, B
// auto-joins, both send through the real composer) because the C++
// InviteUserToGroup branches NGC vs conference (tox_group_invite_friend vs
// tox_conference_invite) and auto-accept covers both.
Future<int> runGroupMessage(
  Inst a,
  Inst b,
  String nickA,
  String nickB, {
  String groupType = 'private',
  String label = 'GROUP',
  String namePrefix = 'RUI-GROUP',
  String msgPrefix = 'RUIGROUP',
}) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final friendsReady = await _retryBool(
    () async => await areFriends(a, toxB) && await areFriends(b, toxA),
    label: '$label friendship ready',
    attempts: 20,
    intervalMs: 1000,
  );
  if (!friendsReady) {
    print('[pair] $label requires an existing friendship');
    return 1;
  }

  await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
  await b.waitState((s) => s['isConnected'] == true, label: 'B connected');
  await a.waitExt('ext.mcp.toolkit.l3_create_group');
  await a.waitExt('ext.mcp.toolkit.l3_join_group');
  await a.waitExt('ext.mcp.toolkit.l3_send_group_text');
  await b.waitExt('ext.mcp.toolkit.l3_join_group');
  await b.waitExt('ext.mcp.toolkit.l3_send_group_text');
  for (final ext in fixtureCBootstrapExtensions) {
    await a.waitExt(ext);
    await b.waitExt(ext);
  }
  await wireFullMeshBootstrap([
    BootstrapTarget('A', a.vm, a.iso),
    BootstrapTarget('B', b.vm, b.iso),
  ]);

  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  // PRIVATE group: peers connect over the existing FRIEND connection (reliable
  // same-host) instead of the flaky public-NGC DHT announce/search that made
  // group delivery a coin-flip (founder's HandleGroupPeerJoin never fired on
  // ~half of same-host runs). B must ACCEPT the invite over the friend link
  // (native tox_group_invite_accept) — a manual join-by-chat-id instead does a
  // public DHT join and lands B in a DISCONNECTED public group (privacy_state
  // mismatch, 0 peers). Enable auto-accept on B, then A invites; B auto-joins.
  //
  // The NGC peer connection between two SEPARATE same-host processes is still
  // probabilistic (the in-process tim2tox auto_tests never hit this), so retry
  // the whole setup with a FRESH private group when the peers don't connect.
  // Confirm B's auto-accept is LIVE before inviting (codex: the setter's `ok` is
  // the weaker precondition; the flag must actually be set for the invite to be
  // accepted over the friend link). Capture the prior value to RESTORE it after,
  // so this scenario doesn't leak mutated account state into later reused runs.
  final bPriorAutoAccept = await _getAutoAcceptGroupInvites(b);
  // RE-ISSUE the set per verify-round, not once: the Prefs write is account
  // scoped (autoAcceptGroupInvites_<currentToxId>), and right after a launch/
  // case-reuse the current-account resolution can still be settling, so a single
  // set can land before the scope is final and the dump-read (also scoped to the
  // now-current account) never sees it — observed intermittently as
  // "did not take effect" under same-host load. Setting again each round, once
  // the account context is settled, makes the write+read converge.
  var autoAcceptLive = false;
  for (var attempt = 0; attempt < 3 && !autoAcceptLive; attempt++) {
    await _setAutoAcceptGroupInvites(b, true);
    autoAcceptLive = await _waitAutoAcceptGroupInvites(b, true, timeoutSecs: 8);
  }
  if (!autoAcceptLive) {
    if (!bPriorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (_) {}
    }
    print('[pair] FAIL: B autoAcceptGroupInvites did not take effect');
    return 1;
  }
  try {
    var groupName = '$namePrefix-$nonce';
    var groupIdA = '';
    var groupIdB = '';
    var groupReady = false;
    for (var attempt = 1; attempt <= 3 && !groupReady; attempt++) {
      if (attempt > 1) {
        // Clean up the prior attempt's group on BOTH sides so each retry starts
        // with NO group candidates — this makes the single-fresh resolution
        // unambiguous even if a prior attempt's group surfaces late (codex). The
        // peer-gate below is the final guard: a mispaired/stale groupIdB can't
        // pass it (a left/failed group has < 2 connected members).
        await _leaveAllGroups(b);
        await _leaveAllGroups(a);
        await _waitGroupCandidatesDrained(b);
        await _waitGroupCandidatesDrained(a);
        groupIdA = '';
        groupIdB = '';
      }
      groupName = '$namePrefix-$nonce-$attempt';
      // After cleanup this is empty on a retry; on attempt 1 it captures any
      // pre-existing groups so only THIS attempt's auto-join is fresh.
      final before = await _groupConversationCandidates(b);
      // Conference has no l3 create path (l3_create_group only does public/
      // private NGC), so drive the real dialog directly; NGC types still try the
      // l3 tool first and fall back to the dialog on non-test accounts.
      final created = groupType == 'conference'
          ? await _createGroupViaUI(a, groupName, groupType: 'conference')
          : await _createGroup(a, groupName, private: groupType == 'private');
      groupIdA = created.groupId;
      await _inviteToGroup(a, groupIdA, toxB);
      // Resolve B's auto-joined group UNAMBIGUOUSLY by this attempt's unique
      // name (conversation-based — B's auto-joined private group may not surface
      // in knownGroups), with a single-fresh-candidate fallback.
      final gidB = await _waitForJoinedGroup(
        b,
        groupName,
        before: before,
        timeoutSecs: 45,
      );
      if (gidB == null) {
        print(
          '[pair] group attempt $attempt/3: B did not auto-join a new group; '
          'retrying with a fresh group',
        );
        continue;
      }
      groupIdB = gidB;
      // Gate on real NGC peer connection (not a fixed delay).
      if (await _waitGroupPeersConnected(
        a,
        groupIdA,
        b,
        groupIdB,
        timeoutSecs: 45,
      )) {
        groupReady = true;
      } else {
        print(
          '[pair] group attempt $attempt/3: peers did not connect; '
          'retrying with a fresh group',
        );
      }
    }
    final tag = label.toLowerCase();
    if (!groupReady) {
      await a.shot('/tmp/ui_${tag}_message_nopeers_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_${tag}_message_nopeers_B.png');
      print(
        '[pair] FAIL: $label peers did not connect after 3 attempts '
        '(same-host cross-process discovery) '
        '(groupIdA=${_shortId(groupIdA)} groupIdB=${_shortId(groupIdB)})',
      );
      return 1;
    }
    await openGroupChat(b, groupId: groupIdB, groupName: groupName);

    final m1 = '$msgPrefix-AtoB-$nonce';
    await openGroupChat(a, groupId: groupIdA, groupName: groupName);
    final aSent = await sendComposerMessage(a, m1);
    final bGot = await _waitGroupMessageAnyConversation(b, m1, timeoutSecs: 60);
    print(
      '[pair] $label A->B sent=$aSent received=$bGot '
      '(groupIdA=${_shortId(groupIdA)} groupIdB=${_shortId(groupIdB)})',
    );

    final m2 = '$msgPrefix-BtoA-$nonce';
    await openGroupChat(a, groupId: groupIdA, groupName: groupName);
    await openGroupChat(b, groupId: groupIdB, groupName: groupName);
    final bSent = await sendComposerMessage(b, m2);
    final aGot = await _waitGroupMessageAnyConversation(a, m2, timeoutSecs: 60);
    print(
      '[pair] $label B->A sent=$bSent received=$aGot '
      '(groupIdA=${_shortId(groupIdA)} groupIdB=${_shortId(groupIdB)})',
    );

    await a.shot('/tmp/ui_${tag}_message_A.png');
    await b.foreground();
    await b.shot('/tmp/ui_${tag}_message_B.png');

    if (aSent && bGot && bSent && aGot) {
      print('[pair] PASS: bidirectional real-UI $label message delivery');
      return 0;
    }
    print(
      '[pair] FAIL: $label A->B(sent=$aSent,recv=$bGot) '
      'B->A(sent=$bSent,recv=$aGot)',
    );
    return 1;
  } finally {
    // Restore B's auto-accept so it doesn't leak into later reused scenarios.
    if (!bPriorAutoAccept) {
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

/// Single-instance real-UI group-create gate (S126/S127/S128/S129/S130): A opens
/// the REAL add-group dialog, creates a [groupType] group, opens the new group
/// conversation, and sends one message through the real composer — asserting the
/// own-sent bubble renders. No second peer / networking, so it is a fast,
/// deterministic surface check (dialog → create → open → composer send),
/// distinct from the two-process delivery gate (`group_message`). Only `a` is
/// driven; `b` is launched-but-idle.
Future<int> runGroupCreate(
  Inst inst,
  String nick, {
  String groupType = 'private',
}) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final name = 'RUI-GC-$nonce';
  final created = await _createGroupViaUI(inst, name, groupType: groupType);
  final gid = created.groupId;
  await openGroupChat(inst, groupId: gid, groupName: name);
  final msg = 'RUIGC-$nonce';
  final sent = await sendComposerMessage(inst, msg);
  // The own-sent message lands in the local group history regardless of peers,
  // so this asserts the composer→render surface without needing a joiner.
  final rendered = await _waitGroupMessageAnyConversation(
    inst,
    msg,
    timeoutSecs: 30,
  );
  await inst.shot('/tmp/ui_group_create_${inst.name}.png');
  if (sent && rendered) {
    print(
      '[pair] PASS: real-UI group create+open+composer-send '
      '(gid=${_shortId(gid)} type=$groupType)',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group create flow (sent=$sent rendered=$rendered '
    'gid=${_shortId(gid)} type=$groupType)',
  );
  return 1;
}

// ===========================================================================
// Single-instance LOGIN + SETTINGS real-UI scenarios.
//
// These drive the REAL login/settings widgets a user actually touches on ONE
// live instance (B stays launched-but-idle, exactly like group_create). They
// reuse `ensureHome` (the real "Register new account" click-through) for the
// logged-in precondition, then tap the real settings controls and assert the
// real side-effect via `l3_dump_state` (autoLogin / notificationSound /
// sessionReady / currentAccountToxId) or the real UI response (snackbar /
// dialog mount / login-page transition). New keys driven here
// (settings_set_password_* , login_page_account_card:<tox>) require a rebuilt
// app bundle.
// ===========================================================================
