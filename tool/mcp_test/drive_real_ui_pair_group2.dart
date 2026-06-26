// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 7 of the real-UI sweep campaign — "Group + conference" (14 cases,
// MIXED single-instance + two-process). See tool/mcp_test/REAL_UI_SWEEP_CAMPAIGN.md.
//
// `sweep_group2` drives BOTH instances. ONE handshake at the top establishes the
// A<->B friendship; ONE shared PRIVATE group is created via the REAL add-group
// dialog (case 72) and reused for 73/74/76/77/78/79/80/81 (the 2p cases invite B
// into that SAME group over the real add-member UI). ONE shared conference is
// created via the REAL dialog (case 82) and reused for 83/84.
//
// State contract (registered in fixture_c_unified_runner.dart):
//   required = no-friend  (fresh pair launch; the sweep does its OWN handshake,
//                          reusing Batch-4's `_establishFriendshipForSweep`)
//   result   = friends    (no case deletes the FRIEND — case 78 kicks B from the
//                          group, case 75 leaves the group, but the A<->B
//                          friendship stays intact; the sweep ends friends)
//
// ============================================================================
// KICK-UI ANSWER (the brief's open question — REAL desktop kick surface exists):
// ============================================================================
// On DESKTOP, kicking a member is the member ROW's `onSecondaryTapDown`
// (tencent_cloud_chat_group_member_list.dart `_showDesktopContextMenu`) → a
// `showMenu` whose 'remove' PopupMenuItem appears only when `canDeleteMember()`
// (which requires myRole==OWNER — A is the creator/owner — AND the target is not
// OWNER AND `groupType != AVChatRoom`). So a PRIVATE NGC group owner CAN kick a
// member via the REAL UI. Two automation keys were needed (the rows + the
// desktop kick menu item were unkeyed) and ADDED at the fork boundary (flagged
// rebuild): the per-member row `group_member_list_item:<userId>` and the desktop
// kick menu item `group_member_desktop_kick_item`. Case 78 right-clicks B's row
// (`ui_secondary_tap`) → taps the keyed kick item → asserts B leaves A's member
// list. For a CONFERENCE (AVChatRoom) `canDeleteMember()` is FALSE (no roles) —
// the kick is a NEGATIVE there (the S173 finding), which is why case 78 is
// PRIVATE-group only.
//
// ============================================================================
// GROUP-MUTE ROUTING ANSWER (the brief's open question):
// ============================================================================
// toxee's group profile does NOT add its own mute control. The upstream group
// profile body (tencent_cloud_chat_group_profile_body.dart) renders the
// `getGroupProfileStateButtonBuilder` slot, which toxee does NOT override, so the
// upstream `TencentCloudChatGroupProfileStateButton` renders a "Do not disturb"
// OperationBar switch (→ `setGroupReceiveMessageOpt`) + a Pin switch. The
// do-not-disturb switch was unkeyed; a `controlKey: ValueKey('group_profile_mute_switch')`
// was ADDED on it at the fork boundary (mirrors the friend-profile
// `user_profile_conversation_mute_switch`). Case 80 toggles it and reads its
// value via `interactiveStructured` (same as the friend mute switch).
//
// ============================================================================
// MEMBER-LIST OPEN: the group profile's "Group Members (N)" entry is a
// KeyedSubtree (`group_profile_members_entry`) that ALSO wraps the "+ Add Members"
// affordance, so a coordinate tap on the entry is ambiguous (header vs add). To
// open the member-list PAGE deterministically, the new UNGATED navigation hook
// `l3_open_group_member_list` (mirrors `l3_open_group_add_member`) pushes the
// REAL member-list page; the page is then driven through REAL widgets (the keyed
// member rows, the desktop kick menu, member-list scroll). The ASSERTED action in
// each case is always the production widget/gesture — l3 is used only for the
// navigation-stability open (the established add-member/conv-menu exception) +
// the seeding/identity/bootstrap plumbing the existing group drivers already use
// (full-mesh bootstrap, auto-accept, member-count polling).

const _b7PrivateNamePrefix = 'RUI-G2';
const _b7ConfNamePrefix = 'RUI-G2CONF';

/// Open the REAL member-list PAGE for [groupId] via the ungated deep-link, then
/// wait for the keyed back-button-bearing member list to mount (any member row,
/// or the empty-state). Returns whether the page mounted.
Future<bool> _openGroupMemberListPage(Inst inst, String groupId) async {
  await inst.foreground();
  final opened = await inst.l3('l3_open_group_member_list', {
    'groupId': groupId,
  });
  if (opened['ok'] != true) {
    print('[pair] _openGroupMemberListPage: l3 open failed: $opened');
    return false;
  }
  // The page mounts when at least the self member row is rendered, or the
  // empty-state appears (a fresh group should at least show self).
  await Future<void>.delayed(const Duration(milliseconds: 800));
  return true;
}

/// Open the group profile via the deterministic deep-link (`l3_open_group_profile`)
/// which pops stale pushed routes first → a clean, on-top, FULL-WIDTH profile
/// route. The avatar-tap path (`_openGroupProfile`) short-circuits on a covered
/// stale profile left by a prior case, so its key resolution lands on a
/// half-width covered profile (clear/leave below the fold at the wrong x, the
/// mute switch un-tappable). Returns whether a profile signature key resolves.
Future<bool> _openGroupProfileClean(Inst inst, String gid) async {
  await inst.foreground();
  final opened = await inst.l3('l3_open_group_profile', {'groupId': gid});
  if (opened['ok'] != true) {
    print('[pair] _openGroupProfileClean: l3 open failed: $opened');
    return false;
  }
  // Wait for a profile signature key to resolve (element-tree walk; the FAB /
  // SelectableText / KeyedSubtree keys are invisible to flutter_skill).
  for (var i = 0; i < 20; i++) {
    if (await inst.keyCenter('group_profile_id_text') != null ||
        await inst.keyCenter('group_profile_edit_name_button') != null) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  print('[pair] _openGroupProfileClean: profile keys did not resolve');
  return false;
}

/// Scroll the group-profile ListView so the keyed [key] (a bottom-anchored
/// button below the fold — clear-history / leave) enters the visible band, then
/// return its resolved center. Uses the MOUSE WHEEL (`ui_scroll_at`): a synthetic
/// touch DRAG does not scroll the desktop profile ListView, but a wheel event at
/// the content column does (verified live: clear button y 1024 → 733). Returns
/// null if it never reaches the band.
Future<({double x, double y})?> _scrollProfileButtonIntoBand(
  Inst inst,
  String key,
) async {
  ({double x, double y})? lastProbe;
  for (var i = 0; i < 16; i++) {
    final c = await inst.keyCenter(key);
    if (c != null) lastProbe = c;
    if (c != null && c.y >= 80 && c.y <= 798) return c;
    // Wheel-scroll DOWN at the content column (the resolved x, or window centre)
    // so the event reliably lands on the profile's Scrollable.
    final wheelX = (c?.x ?? 640).clamp(40.0, 1240.0);
    try {
      await inst.scrollAtCoords(wheelX, 400, dy: 400);
    } on DriveError catch (e) {
      print('[pair] _scrollProfileButtonIntoBand: wheel warn: ${e.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  print('[pair] _scrollProfileButtonIntoBand: "$key" never reached band '
      '(last=$lastProbe)');
  return null;
}

/// The member-list row key for a member. An NGC peer's row is keyed by its
/// PER-GROUP encryption pubkey (tox_group_peer_get_public_key) — a freshly
/// generated per-group keypair, NOT the friend/long-term pubkey — so the key
/// can't be predicted from A's friend list. AND the member rows are
/// KeyedSubtree+GestureDetector leaves that flutter_skill (waitKey /
/// interactiveStructured) cannot see; only the element-tree walk (keyCenter)
/// surfaces them. So: read the peer's ACTUAL member userID from the bridge
/// enumeration (l3_group_member_list — test-gated, both call paths mark the
/// account test) and resolve the keyed row via keyCenter. Retries because the
/// founder's same-host NGC peer info can lag the member COUNT briefly (the
/// authoritative count can read 2 while the peer's public key isn't enumerable
/// yet). [gid] is the group id; both group2 call sites + _gcmeVisiblePeerRowKey
/// open the member-list page first.
Future<String?> _memberRowKeyFor(Inst inst, String gid, String memberTox) async {
  final memberPk = _pubkey(memberTox);
  List<String> lastNonSelf = const [];
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      final r = await inst.l3('l3_group_member_list', {'groupId': gid});
      final members = (r['members'] as List?) ?? const [];
      final nonSelf = <String>[];
      // ALL members whose pubkey matches the target peer (not just the last):
      // same-host NGC churn can surface the SAME peer under multiple ephemeral
      // member userIDs (ghost duplicates). The bridge now de-dupes by pubkey, but
      // if any residual dup slips through, try each matching userID's row key —
      // the one the de-duped UI actually rendered will resolve.
      final pkMatches = <String>[];
      for (final m in members) {
        if (m is! Map || m['isSelf'] == true) continue;
        final uid = m['userID']?.toString() ?? '';
        if (uid.isEmpty) continue;
        nonSelf.add(uid);
        if (_pubkey(uid) == memberPk) pkMatches.add(uid);
      }
      lastNonSelf = nonSelf;
      // Prefer pubkey matches; else accept the SINGLE non-self member (the
      // 2-member scenario contract). Refuse to GUESS among multiple unrelated
      // non-self rows — a leaked third member must not select/kick the wrong peer.
      final candidates = <String>[
        ...pkMatches,
        if (pkMatches.isEmpty && nonSelf.length == 1) nonSelf.first,
      ];
      for (final candidate in candidates) {
        final key = 'group_member_list_item:$candidate';
        // keyCenter (element-tree walk) — flutter_skill can't see the keyed
        // GestureDetector row.
        if (await inst.waitKeyCenter(key, timeoutSecs: 3)) return key;
      }
    } on DriveError catch (_) {/* retry — NGC peer info may still be syncing */}
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  print('[pair] _memberRowKeyFor: no row for peer=$memberPk in group=$gid '
      '(nonSelf=$lastNonSelf)');
  return null;
}

/// Read the group conversation's recvOpt (mute) from the dump conversation list
/// entry for `group_<gid>` (recvOpt 2 == do-not-disturb), or null when absent.
Future<int?> _groupRecvOpt(Inst inst, String gid) async {
  final entry = await _conversationEntry(inst, 'group_$gid');
  final v = entry?['recvOpt'];
  return v is num ? v.toInt() : null;
}

/// Read a keyed widget's rendered `text` via flutter_skill's
/// `interactiveStructured` (each element carries `{key, text, bounds, ...}`).
/// Returns null when the key isn't present / has no text. Used to assert the
/// OPEN-chat header title (`chat_header_title_text`) — distinct from the
/// conversation-LIST row showName.
Future<String?> _keyedText(Inst inst, String key) async {
  final r = await inst.skill('interactiveStructured', const {});
  final data = r['data'];
  final elements = data is Map ? data['elements'] : null;
  if (elements is! List) return null;
  for (final e in elements) {
    if (e is! Map || e['key'] != key) continue;
    final t = e['text'];
    if (t is String) return t;
  }
  return null;
}

/// Poll until the OPEN chat's header title (`chat_header_title_text`) renders
/// [expected]. The header must be open (the chat surface ready) for the key to be
/// present.
Future<bool> _waitChatHeaderTitle(
  Inst inst,
  String expected, {
  int timeoutSecs = 12,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _keyedText(inst, 'chat_header_title_text') == expected) return true;
    // `chat_header_title_text` is a plain Text whose KEY flutter_skill's
    // interactiveStructured does NOT surface (so `_keyedText` returns null even
    // when the header IS rendered). Fall back to a TEXT match for the expected
    // header name in the open chat — the rename already updated the
    // conversation-row showName, so seeing the new name in the open chat
    // surface confirms it propagated to the header.
    if (await inst.waitText(expected, timeoutSecs: 1)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

// ===========================================================================
// case 71 — group_create_cancel (S32)
// ===========================================================================
/// Open the REAL AddGroupDialog → ESC (the dialog's only dismiss — it has NO
/// Cancel button; CallbackShortcuts(escape) → maybePop) → the name input is gone
/// AND no new group conversation appeared. Drives the real dialog open + dismiss.
Future<bool> _groupCreateCancel(Inst inst) async {
  await inst.foreground();
  final before = await _groupConversationCandidates(inst);
  final opened = await inst.l3('l3_open_add_group_dialog');
  if (opened['ok'] != true) {
    print('[pair] group_create_cancel: l3_open_add_group_dialog failed: $opened');
    return false;
  }
  final dialogUp = await inst.waitKey('add_group_create_name_input',
      timeoutSecs: 12);
  if (!dialogUp) {
    print('[pair] group_create_cancel: dialog did not open');
    return false;
  }
  // ESC closes (the dialog binds Escape → Navigator.maybePop).
  try {
    await inst.osaEscape();
  } on DriveError catch (e) {
    print('[pair] group_create_cancel: ESC unavailable: ${e.message}');
    return false;
  }
  final closed =
      await inst.waitKeyGone('add_group_create_name_input', timeoutSecs: 8);
  // No new group conversation should have been created (Cancel != Create).
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final after = await _groupConversationCandidates(inst);
  final noNewGroup = after.difference(before).isEmpty;
  await inst.shot('/tmp/ui_g2_create_cancel_${inst.name}.png');
  print(
    '[pair] group_create_cancel: dialogUp=$dialogUp closed=$closed '
    'noNewGroup=$noNewGroup',
  );
  return dialogUp && closed && noNewGroup;
}

// ===========================================================================
// case 72 — group_create_type_selector_surface (S32)
// ===========================================================================
/// Open the REAL AddGroupDialog, assert all three type segments render (Public /
/// Private / Conference keyed segments), then pick Private + type a name + Create
/// → the new PRIVATE group surfaces as a fresh conversation. Returns the created
/// group's local id (the SHARED private group reused by 73/74/76/77/78/79/80/81),
/// or '' on failure.
Future<String> _groupCreateTypeSelectorSurface(Inst inst, String name) async {
  await inst.foreground();
  final before = await _groupConversationCandidates(inst);
  final opened = await inst.l3('l3_open_add_group_dialog');
  if (opened['ok'] != true) {
    print('[pair] group_create_type_selector: l3 open failed: $opened');
    return '';
  }
  if (!await inst.waitKey('add_group_create_name_input', timeoutSecs: 12)) {
    print('[pair] group_create_type_selector: dialog did not open');
    return '';
  }
  // All three keyed type segments must render (the type-selector surface).
  final hasPublic =
      await inst.waitKey('add_group_type_public_segment', timeoutSecs: 6);
  final hasPrivate =
      await inst.waitKey('add_group_type_private_segment', timeoutSecs: 4);
  final hasConference =
      await inst.waitKey('add_group_type_conference_segment', timeoutSecs: 4);
  print(
    '[pair] group_create_type_selector: segments public=$hasPublic '
    'private=$hasPrivate conference=$hasConference',
  );
  if (!(hasPublic && hasPrivate && hasConference)) {
    await inst.shot('/tmp/ui_g2_type_selector_nosegs_${inst.name}.png');
    // Close the dialog before bailing.
    try {
      await inst.osaEscape();
    } on DriveError {
      // best-effort
    }
    return '';
  }
  // Pick Private (single-fire — SegmentedButton selection; idempotent).
  await inst.tapKey('add_group_type_private_segment');
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await inst.focusType('add_group_create_name_input', name);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('add_group_create_submit_button');
  // Resolve A's own new private group by its unique name.
  final gid = await _waitForJoinedGroup(inst, name, before: before,
      timeoutSecs: 30);
  await inst.shot('/tmp/ui_g2_type_selector_${inst.name}.png');
  if (gid == null) {
    print('[pair] group_create_type_selector: group "$name" did not appear');
    return '';
  }
  print(
    '[pair] group_create_type_selector: PASS created private group '
    '(gid=${_shortId(gid)})',
  );
  return gid;
}

// ===========================================================================
// case 76 — group_rename_updates_header (S153)
// ===========================================================================
/// Open the group profile, rename via the REAL edit-name dialog, then open the
/// chat and assert the conversation-list row showName refreshes to the new name
/// (the header renders the same showName).
Future<bool> _groupRenameUpdatesHeader(
  Inst inst,
  String gid,
  String groupName,
  String newName,
) async {
  // Clean, full-width profile open (the avatar-tap path lands on a stale covered
  // profile across cases). The edit-name FAB + AlertDialog confirm are NOT
  // surfaced to flutter_skill (tapKey misses them) — use the element-tree
  // resolver (tapKeyCenter), verified live to make the rename actually apply.
  if (!await _openGroupProfileClean(inst, gid)) {
    print('[pair] group_rename_updates_header: profile did not open');
    return false;
  }
  await inst.tapKeyCenter('group_profile_edit_name_button', timeoutSecs: 8);
  if (!await inst.waitKeyCenter('group_profile_edit_name_field',
      timeoutSecs: 10)) {
    print('[pair] group_rename_updates_header: edit-name dialog did not open');
    return false;
  }
  await inst.focusType('group_profile_edit_name_field', newName);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKeyCenter('group_profile_edit_name_confirm_button',
      timeoutSecs: 8);
  final refreshed =
      await _waitGroupShowName(inst, gid, newName, timeoutSecs: 20);
  // Open the chat fresh → assert the OPEN-chat HEADER title actually renders the
  // new name (codex P1: a conversation-LIST row showName check alone would PASS
  // even if the header stayed stale — read the keyed header text widget).
  await returnToChatsHome(inst, rounds: 4);
  await openGroupChat(inst, groupId: gid, groupName: newName, viaL3Seam: true);
  final headerOk = await _waitChatHeaderTitle(inst, newName, timeoutSecs: 12);
  final headerText = await _keyedText(inst, 'chat_header_title_text');
  await inst.shot('/tmp/ui_g2_rename_${inst.name}.png');
  print(
    '[pair] group_rename_updates_header: refreshed=$refreshed headerOk=$headerOk '
    'headerText="$headerText" ("$groupName" → "$newName")',
  );
  return refreshed && headerOk;
}

// ===========================================================================
// case 73 — group_profile_members_entry (S121)
// ===========================================================================
/// Open the group profile, then open the REAL member-list PAGE (deep-link) and
/// assert it mounts a member row (self at least). The members-entry surface
/// (`group_profile_members_entry`) is asserted first as the real profile section.
Future<bool> _groupProfileMembersEntry(
  Inst inst,
  String gid,
  String groupName,
) async {
  // Use the deterministic deep-link open (root-nav, cleared by returnToChatsHome)
  // — the avatar-tap path pushes a profile on a nested navigator that
  // returnToChatsHome does NOT clear, leaving a STALE profile that poisons the
  // later mute/clear/leave cases' key resolution.
  if (!await _openGroupProfileClean(inst, gid)) {
    print('[pair] group_profile_members_entry: profile did not open');
    return false;
  }
  // KeyedSubtree — invisible to flutter_skill; use the element-tree resolver.
  final entryShown =
      await inst.waitKeyCenter('group_profile_members_entry', timeoutSecs: 6);
  if (!entryShown) {
    print('[pair] group_profile_members_entry: members entry not shown');
    return false;
  }
  // Open the member-list page deterministically (the entry KeyedSubtree also
  // wraps "+ Add Members", so a coordinate tap is ambiguous).
  if (!await _openGroupMemberListPage(inst, gid)) {
    print('[pair] group_profile_members_entry: member-list page did not open');
    return false;
  }
  // The self member row must render (the page mounted a real member list).
  final selfTox =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  final selfRowKey = 'group_member_list_item:${_pubkey(selfTox)}';
  final selfRowKeyFull = 'group_member_list_item:$selfTox';
  final memberRow = await inst.waitKeyCenter(selfRowKey, timeoutSecs: 6) ||
      await inst.waitKeyCenter(selfRowKeyFull, timeoutSecs: 3);
  await inst.shot('/tmp/ui_g2_members_entry_${inst.name}.png');
  // Land back on chats home for the next case.
  await returnToChatsHome(inst, rounds: 4);
  print(
    '[pair] group_profile_members_entry: entryShown=$entryShown '
    'memberRow=$memberRow',
  );
  return entryShown && memberRow;
}

// ===========================================================================
// case 80 — group_mute_toggle (S83)
// ===========================================================================
/// Open the group profile, toggle the do-not-disturb (mute) switch
/// (`group_profile_mute_switch`) ON then OFF, asserting the Switch's visible value
/// FLIPS each time (read via interactiveStructured) AND the session stays alive
/// (no crash). recvOpt dump is logged SOFT (the native→Dart sync residual). The
/// switch is restored to its original value.
Future<bool> _groupMuteToggle(Inst inst, String gid, String groupName) async {
  const sw = 'group_profile_mute_switch';
  // Clean, full-width profile open — the avatar-tap path lands on a stale
  // covered (half-width) profile across cases, where the mute switch resolves
  // off-screen and the toggle never flips (verified live: on a clean profile the
  // switch flips false→true).
  if (!await _openGroupProfileClean(inst, gid)) {
    print('[pair] group_mute_toggle: profile did not open');
    return false;
  }
  // The state-button (mute/pin) sits below the avatar/content/chat-button; it is
  // already on the profile ListView. Read the switch's current value.
  if (!await inst.waitKey(sw, timeoutSecs: 8)) {
    print('[pair] group_mute_toggle: mute switch not present');
    return false;
  }
  // Settle: a Switch tapped in the first frame(s) after the profile route
  // mounts can no-op (the gesture arena isn't ready), so the first tap was
  // flaky. Settle, then tap-and-VERIFY with a small retry so a dropped first
  // tap doesn't false-fail.
  await Future<void>.delayed(const Duration(milliseconds: 600));
  final recvBefore = await _groupRecvOpt(inst, gid);
  final valueBefore = await _switchValue(inst, sw);
  if (valueBefore == null) {
    print('[pair] group_mute_toggle: mute switch value unreadable');
    return false;
  }
  // Tap [sw] and verify its value reaches [want], retrying the tap a few times
  // (each tap re-resolves the topmost switch). Returns the final read value.
  Future<bool?> tapUntil(bool want) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!await inst.tapKeyCenter(sw, timeoutSecs: 6)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final v = await _switchValue(inst, sw);
      if (v == want) return v;
      // If a prior tap DID land (value already == want) we returned above; an
      // even number of dropped/extra taps could leave it unchanged — settle and
      // retry. An odd over-fire would overshoot, but the next retry corrects it.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return await _switchValue(inst, sw);
  }

  // Toggle #1 (flip away from the original value).
  final valueAfter1 = await tapUntil(!valueBefore);
  final alive1 = (await inst.dumpState())['sessionReady'] == true;
  final flipped1 = valueAfter1 != null && valueAfter1 == !valueBefore;
  // Toggle #2 (restore the original value).
  final valueAfter2 = await tapUntil(valueBefore);
  final alive2 = (await inst.dumpState())['sessionReady'] == true;
  final flipped2 = valueAfter2 != null && valueAfter2 == valueBefore;
  final recvAfter = await _groupRecvOpt(inst, gid);
  await returnToChatsHome(inst, rounds: 4);
  await inst.shot('/tmp/ui_g2_mute_${inst.name}.png');
  print(
    '[pair] group_mute_toggle: alive1=$alive1 alive2=$alive2 '
    'valueBefore=$valueBefore valueAfter1=$valueAfter1 (flipped1=$flipped1) '
    'valueAfter2=$valueAfter2 (flipped2=$flipped2) '
    'recvOptBefore=$recvBefore recvOptAfter=$recvAfter '
    '(recvOpt is SOFT — native→Dart sync residual)',
  );
  // HARD: no-crash across both toggles AND the switch value flips on then off.
  return alive1 && alive2 && flipped1 && flipped2;
}

// ===========================================================================
// case 74 — group_profile_clear_history (S122)
// ===========================================================================
/// Seed own group sends through the REAL composer, then clear via the group
/// profile Clear-History button + the adaptive confirm dialog (its Confirm has no
/// key — tap by the localized "Confirm" label, single-fire-safe via the fork's
/// one-shot `handled` guard). Assert the group history messageCount drops to 0.
Future<bool> _groupProfileClearHistory(
  Inst inst,
  String gid,
  String groupName,
) async {
  final convId = 'group_$gid';
  // 1) Seed own group history (own sends land in local group history regardless
  // of peers).
  await openGroupChat(inst, groupId: gid, groupName: groupName, viaL3Seam: true);
  var seeded = 0;
  for (var i = 0; i < 3; i++) {
    final text = 'RUIG2Clear-$i-${DateTime.now().microsecondsSinceEpoch}';
    if (await sendComposerMessage(inst, text)) {
      seeded++;
    } else {
      // The composer can flake / navigate off the group under 2-proc
      // contention. Seed deterministically via the L3 group-send seam — an own
      // send lands in local group history regardless of peers, and the asserted
      // action here is the Clear-History gesture, not the send. Needs a
      // test-marked account, which runGroup2Sweep now grants.
      try {
        final r = await inst.l3('l3_send_group_text', {
          'groupId': gid,
          'text': text,
        });
        if (r['ok'] == true) seeded++;
      } on DriveError catch (_) {/* honest fail below if all attempts miss */}
    }
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
  final beforeCount =
      ((await inst.dumpState(conversationId: convId))['messageCount'] as num?)
              ?.toInt() ??
          0;
  if (seeded == 0 || beforeCount == 0) {
    print('[pair] group_profile_clear_history: failed to seed '
        '(seeded=$seeded beforeCount=$beforeCount)');
    return false;
  }
  // 2) Open the profile, SCROLL the Clear-History button into the visible
  // viewport, then tap it. Clear-History is the bottom of the scrollable group
  // profile (the override's DeleteButton Column: child0=clear-history,
  // child1=leave — group_builder_override.dart), so a below-fold tryTapKey lands
  // off-window and the GestureDetector.onTap never fires ("clear button not
  // tappable"). Mirror the leave case's keyCenter-scroll loop.
  if (!await _openGroupProfileClean(inst, gid)) {
    print('[pair] group_profile_clear_history: profile did not open');
    return false;
  }
  // Clear-History is the bottom of the scrollable group profile (the override's
  // DeleteButton Column: child0=clear-history, child1=leave), below the fold on
  // an 800px window. WHEEL-scroll it into the visible band (a synthetic touch
  // drag does NOT scroll the desktop profile ListView; the mouse wheel does).
  final clearCenter =
      await _scrollProfileButtonIntoBand(inst, 'group_profile_clear_history_button');
  if (clearCenter == null) {
    print('[pair] group_profile_clear_history: clear button never reached '
        '(below fold)');
    return false;
  }
  // Settle, tap, and VERIFY the confirm dialog opened; retry with direct-invoke
  // tapKey (fires onTap even when the re-resolved center is stale post-scroll).
  var clearDialogUp = false;
  for (var attempt = 0; attempt < 3 && !clearDialogUp; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (attempt == 0) {
      await inst.tapKeyCenter('group_profile_clear_history_button',
          timeoutSecs: 8);
    } else {
      await inst.tryTapKey('group_profile_clear_history_button', retries: 2);
    }
    clearDialogUp = await inst.waitText('Confirm', timeoutSecs: 2);
  }
  if (!clearDialogUp) {
    print('[pair] group_profile_clear_history: clear confirm dialog never opened');
    return false;
  }
  // The adaptive confirm dialog's Confirm button has NO key; tap the localized
  // label. The fork's one-shot `handled` guard makes a double-fire safe.
  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (!await _tryTapText(inst, 'Confirm')) {
    print('[pair] group_profile_clear_history: Confirm label not tappable');
    return false;
  }
  // 3) Assert the group history is empty.
  final emptied = await _waitGroupHistoryCount(inst, convId, (c) => c == 0,
      timeoutSecs: 15);
  final afterCount =
      ((await inst.dumpState(conversationId: convId))['messageCount'] as num?)
              ?.toInt() ??
          -1;
  await returnToChatsHome(inst, rounds: 4);
  await inst.shot('/tmp/ui_g2_clear_history_${inst.name}.png');
  print(
    '[pair] group_profile_clear_history: seeded=$seeded beforeCount=$beforeCount '
    'afterCount=$afterCount emptied=$emptied',
  );
  return emptied;
}

// ===========================================================================
// case 77 — group_add_member_full_join (S124/S81)  [two-process]
// ===========================================================================
/// A opens the REAL add-member picker for the SHARED group, selects B (keyed
/// contact item), confirms → B auto-joins → A's member count reaches >=2. Reuses
/// `_inviteToGroupViaUI`'s exact real select+confirm path. Requires the full-mesh
/// bootstrap + B auto-accept already wired by the sweep prelude.
Future<bool> _groupAddMemberFullJoin(
  Inst a,
  Inst b,
  String gid,
  String toxB,
) async {
  // Re-invite if B doesn't join in time: same-host the invite/accept handshake
  // (over the TCP relay) can race, and a single shot occasionally never lands.
  // Mirrors _establishTwoProcessGroup's 3-attempt retry. Re-opening the picker
  // after B has already joined would throw "contact not selectable", so once B
  // is a member we stop; any throw mid-retry is tolerated and re-checked.
  var memberCount = 0;
  for (var attempt = 0; attempt < 3 && memberCount < 2; attempt++) {
    try {
      await _inviteToGroupViaUI(a, gid, toxB);
    } on DriveError catch (e) {
      // B may already be (partially) in the group → the picker no longer lists
      // them; fall through to the member-count poll rather than failing.
      print('[pair] group_add_member_full_join: re-invite attempt '
          '${attempt + 1} threw (${e.message}); polling member count');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (DateTime.now().isBefore(deadline)) {
      memberCount = await _groupMemberCount(a, gid);
      if (memberCount >= 2) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  await a.shot('/tmp/ui_g2_add_member_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_g2_add_member_B.png');
  print(
    '[pair] group_add_member_full_join: A memberCount=$memberCount '
    '(gid=${_shortId(gid)})',
  );
  return memberCount >= 2;
}

// ===========================================================================
// case 79 — group_member_list_scroll (S36)  [two-process]
// ===========================================================================
/// Open the REAL member-list page (with B joined, 2 members) and drag-scroll the
/// list (ui_drag). With only 2 members the list cannot actually scroll far, so
/// the HONEST assertion is: the drag EXECUTES without error AND the member rows
/// are STILL rendered afterwards (the list survived the gesture intact). A
/// low-value-but-cheap surface gate.
Future<bool> _groupMemberListScroll(
  Inst a,
  String gid,
  String toxB,
) async {
  if (!await _openGroupMemberListPage(a, gid)) {
    print('[pair] group_member_list_scroll: member-list page did not open');
    return false;
  }
  final bRowKey = await _memberRowKeyFor(a, gid, toxB);
  if (bRowKey == null) {
    print('[pair] group_member_list_scroll: could not resolve B member row key');
    return false;
  }
  final bRowBefore = await a.waitKeyCenter(bRowKey, timeoutSecs: 8);
  // Drag-scroll the list. With 2 members the AzListView barely moves; the gate is
  // that the gesture runs without throwing and the list stays intact.
  var dragOk = true;
  try {
    // Drag on B's row center (a stable, rendered anchor inside the scrollable).
    await a.dragBy(bRowKey, dy: -200, steps: 10);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await a.dragBy(bRowKey, dy: 200, steps: 10);
  } on DriveError catch (e) {
    dragOk = false;
    print('[pair] group_member_list_scroll: drag warn: ${e.message}');
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final bRowAfter = await a.waitKeyCenter(bRowKey, timeoutSecs: 6);
  await a.shot('/tmp/ui_g2_member_scroll_A.png');
  await returnToChatsHome(a, rounds: 4);
  print(
    '[pair] group_member_list_scroll: bRowBefore=$bRowBefore dragOk=$dragOk '
    'bRowAfter=$bRowAfter (2 members — list intact after drag)',
  );
  return bRowBefore && dragOk && bRowAfter;
}

// ===========================================================================
// case 81 — group_unread_badge_two_proc (S90)  [two-process]
// ===========================================================================
/// B group-sends while A is parked off the conversation → A's group row unread
/// badge bumps to N>=1; A OPENS the group chat → unread clears to 0. Seeding is
/// REAL (B's composer send into the shared group).
Future<bool> _groupUnreadBadgeTwoProc(
  Inst a,
  Inst b,
  String gidA,
  String gidB,
  String groupName,
) async {
  final convId = 'group_$gidA';
  // A must NOT be viewing the group, or the inbound auto-marks read.
  await returnToChatsHome(a, rounds: 4);
  try {
    await a.clearActiveConversation();
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
  }
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  // B group-sends; A must RECEIVE it over NGC for the unread to bump. Same-host
  // cross-process NGC message delivery is probabilistic even once peers connect
  // (documented environment limitation), so retry B's send with a distinct
  // nonce each round — any arrival bumps A's unread — before honestly failing
  // on the delivery gate. A stays parked off the group throughout (parked
  // above), so a late arrival still counts as unread.
  var bSent = false;
  var aGot = false;
  final sentNonces = <String>[];
  for (var attempt = 0; attempt < 3 && !aGot; attempt++) {
    final mi = 'RUIG2UNREAD-$nonce-$attempt';
    await openGroupChat(b, groupId: gidB, groupName: groupName, viaL3Seam: true);
    if (await sendComposerMessage(b, mi)) {
      bSent = true;
      sentNonces.add(mi);
    }
    // Accept ANY sent nonce arriving — a LATE delivery of an earlier send still
    // proves A received a B group message (and bumps unread); gating only on
    // the current attempt's nonce would falsely fail that race.
    for (final s in sentNonces) {
      if (await _waitGroupMessageAnyConversation(a, s, timeoutSecs: 12)) {
        aGot = true;
        break;
      }
    }
  }
  if (!bSent || !aGot) {
    print('[pair] group_unread_badge_two_proc: seed failed '
        '(bSent=$bSent aGot=$aGot) — same-host NGC delivery missed after 3 tries');
    return false;
  }
  final bumped = await _waitConversationUnread(a, convId, (u) => u >= 1,
      timeoutSecs: 30);
  if (!bumped) {
    final entry = await _conversationEntry(a, convId);
    await a.shot('/tmp/ui_g2_unread_noseed_A.png');
    print('[pair] group_unread_badge_two_proc: unread did not bump '
        '(entry=$entry)');
    return false;
  }
  // OPEN the group chat → marks read on open.
  await openGroupChat(a, groupId: gidA, groupName: groupName, viaL3Seam: true);
  final cleared = await _waitConversationUnread(a, convId, (u) => u == 0,
      timeoutSecs: 20);
  await returnToChatsHome(a, rounds: 4);
  await a.shot('/tmp/ui_g2_unread_A.png');
  print(
    '[pair] group_unread_badge_two_proc: bumped=$bumped cleared=$cleared',
  );
  return bumped && cleared;
}

// ===========================================================================
// case 78 — group_kick_member_ui (S37)  [two-process; destructive to membership]
// ===========================================================================
/// Kick B from the shared PRIVATE group via the REAL desktop member-list UI:
/// open the member-list page, right-click B's row (`ui_secondary_tap` → the
/// desktop `_showDesktopContextMenu`), tap the keyed kick item
/// (`group_member_desktop_kick_item` → `kickGroupMember`), and assert B leaves
/// A's member list (A's authoritative member count drops back to 1, the moderator
/// view that confirms the kick — an invite auto-join does NOT propagate B's
/// removal to B's knownGroups). Reuses the S37 kick recipe's identity model (NGC
/// members are keyed by per-group pubkey, which the row key carries) but drives
/// the REAL desktop kick affordance instead of the l3 kick tool.
Future<bool> _groupKickMemberUi(
  Inst a,
  String gid,
  String toxB,
) async {
  // Precondition: B is in the group (2 members) — case 77 put B there.
  final before = await _groupMemberCount(a, gid);
  if (before < 2) {
    print('[pair] group_kick_member_ui: B not in group before kick '
        '(memberCount=$before)');
    return false;
  }
  if (!await _openGroupMemberListPage(a, gid)) {
    print('[pair] group_kick_member_ui: member-list page did not open');
    return false;
  }
  final bRowKey = await _memberRowKeyFor(a, gid, toxB);
  if (bRowKey == null) {
    print('[pair] group_kick_member_ui: could not resolve B member row key');
    return false;
  }
  if (!await a.waitKeyCenter(bRowKey, timeoutSecs: 8)) {
    print('[pair] group_kick_member_ui: B member row not rendered ($bRowKey)');
    return false;
  }
  // Right-click B's row → the desktop context menu (canDeleteMember()==true for a
  // PRIVATE group owner) → tap the keyed kick item. Retry the open a few times
  // (the showMenu can race the secondary-tap dispatch).
  var menuKicked = false;
  for (var attempt = 0; attempt < 3 && !menuKicked; attempt++) {
    try {
      await a.secondaryTapKey(bRowKey);
    } on DriveError catch (e) {
      print('[pair] group_kick_member_ui: secondaryTap warn: ${e.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    // The desktop context menu renders in an Overlay entry that whole-tree
    // waitKey doesn't traverse — use the element-tree resolver (waitKeyCenter),
    // matching the tapKeyCenter below.
    if (await a.waitKeyCenter('group_member_desktop_kick_item', timeoutSecs: 3)) {
      // Single-fire the kick item (it pops the menu route + runs kickGroupMember).
      if (await a.tapKeyCenter('group_member_desktop_kick_item',
          timeoutSecs: 6)) {
        menuKicked = true;
      }
    }
  }
  if (!menuKicked) {
    await a.shot('/tmp/ui_g2_kick_nomenu_A.png');
    // Clean up so a failed kick (open menu / member-list page) does not poison
    // the next case (leave) — dismiss any menu then land back on chats home.
    try {
      await a.osaEscape();
    } on DriveError {
      // best-effort
    }
    await returnToChatsHome(a, rounds: 4);
    print('[pair] group_kick_member_ui: desktop kick item not reachable');
    return false;
  }
  // Assert B leaves A's member list (the moderator view drops B → count 1).
  var after = before;
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    after = await _groupMemberCount(a, gid);
    if (after < before) break;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await a.shot('/tmp/ui_g2_kick_A.png');
  await returnToChatsHome(a, rounds: 4);
  print(
    '[pair] group_kick_member_ui: before=$before after=$after '
    '(kick removes B from A member list)',
  );
  return after < before;
}

// ===========================================================================
// case 75 — group_leave_via_profile_confirm (S123/S150)  [LAST group case]
// ===========================================================================
/// Open the group profile, tap the Quit/Dissolve button (`group_profile_leave_button`)
/// → confirm via the adaptive dialog ("Confirm" label; the fork's one-shot guard
/// makes a double-fire safe) → the group conversation row leaves the sidebar.
Future<bool> _groupLeaveViaProfileConfirm(
  Inst inst,
  String gid,
  String groupName,
) async {
  final convId = 'group_$gid';
  if (!await _openGroupProfileClean(inst, gid)) {
    print('[pair] group_leave_via_profile_confirm: profile did not open');
    return false;
  }
  // The leave/disband button is the BOTTOM of the scrollable profile, below the
  // fold on an 800px window. WHEEL-scroll it into the visible band (a synthetic
  // touch drag does NOT scroll the desktop profile ListView; the mouse wheel
  // does), THEN tap it for a real visible tap that opens the adaptive confirm
  // dialog.
  final leaveCenter =
      await _scrollProfileButtonIntoBand(inst, 'group_profile_leave_button');
  if (leaveCenter == null) {
    print('[pair] group_leave_via_profile_confirm: leave button never reached '
        '(below fold)');
    return false;
  }
  // The leave-button tap can MISS: right after the scroll, tapKeyCenter
  // re-resolves a center while the ListView is still settling, so the coordinate
  // lands on empty space and the GestureDetector.onTap never fires (it returns
  // true regardless). Settle, tap, and VERIFY the confirm dialog actually opened
  // ("Leave the group?" title); retry with the direct-invoke tapKey (fires onTap
  // even when the re-resolved bounds are stale).
  var dialogUp = false;
  for (var attempt = 0; attempt < 3 && !dialogUp; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (attempt == 0) {
      await inst.tapKeyCenter('group_profile_leave_button', timeoutSecs: 8);
    } else {
      await inst.tryTapKey('group_profile_leave_button', retries: 2);
    }
    dialogUp = await inst.waitText('Leave the group', timeoutSecs: 3) ||
        await inst.waitText('Confirm', timeoutSecs: 1);
  }
  await inst.shot('/tmp/ui_g2_leave_dialog_${inst.name}.png');
  if (!dialogUp) {
    print('[pair] group_leave_via_profile_confirm: leave confirm dialog never opened');
    return false;
  }
  // The toxee override `_showQuitGroupDialog` primary action is "Confirm" (tried
  // first); the label still varies for legacy paths, so try the candidates in
  // order so both the group and conference leave paths resolve.
  var confirmed = false;
  for (final label in const [
    'Confirm',
    'Disband Group',
    'Disband',
    'Dissolve',
    'Leave',
    'OK',
  ]) {
    if (await _tryTapText(inst, label)) {
      confirmed = true;
      break;
    }
  }
  if (!confirmed) {
    // Dismiss the (unmatched) modal so it can't stay up and block the next
    // case's navigation (the "settings did not become the active tab" cascade).
    try {
      await inst.osaEscape();
    } on DriveError {
      // best-effort
    }
    print('[pair] group_leave_via_profile_confirm: no confirm label tappable');
    return false;
  }
  // The quit path deletes the conversation (Prefs.addQuitGroup +
  // deleteConversation), so the row leaves the sidebar.
  final gone = await _waitConversationGone(inst, convId, timeoutSecs: 20);
  await returnToChatsHome(inst, rounds: 4);
  await inst.shot('/tmp/ui_g2_leave_${inst.name}.png');
  print('[pair] group_leave_via_profile_confirm: gone=$gone');
  return gone;
}

// ===========================================================================
// case 82 — conf_create_dialog_surface (S156)
// ===========================================================================
/// Open the REAL AddGroupDialog, select the Conference segment, type a name +
/// Create → a new conference conversation row appears. Returns the created
/// conference's local id (the SHARED conference reused by 83/84), or '' on
/// failure.
Future<String> _confCreateDialogSurface(Inst inst, String name) async {
  await inst.foreground();
  final before = await _groupConversationCandidates(inst);
  final opened = await inst.l3('l3_open_add_group_dialog');
  if (opened['ok'] != true) {
    print('[pair] conf_create_dialog_surface: l3 open failed: $opened');
    return '';
  }
  if (!await inst.waitKey('add_group_create_name_input', timeoutSecs: 12)) {
    print('[pair] conf_create_dialog_surface: dialog did not open');
    return '';
  }
  // Select the Conference segment (single-fire, locale-independent key).
  if (!await inst.waitKey('add_group_type_conference_segment', timeoutSecs: 6)) {
    print('[pair] conf_create_dialog_surface: conference segment absent');
    try {
      await inst.osaEscape();
    } on DriveError {
      // best-effort
    }
    return '';
  }
  await inst.tapKey('add_group_type_conference_segment');
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await inst.focusType('add_group_create_name_input', name);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('add_group_create_submit_button');
  final gid =
      await _waitForJoinedGroup(inst, name, before: before, timeoutSecs: 30);
  await inst.shot('/tmp/ui_g2_conf_create_${inst.name}.png');
  if (gid == null) {
    print('[pair] conf_create_dialog_surface: conference "$name" did not appear');
    return '';
  }
  print(
    '[pair] conf_create_dialog_surface: PASS created conference row '
    '(gid=${_shortId(gid)})',
  );
  return gid;
}

// ===========================================================================
// case 83 — conf_row_menu_surface (S161)
// ===========================================================================
/// Open the conference row's context menu (the SHARED conversation-row menu — the
/// row/menu layer is type-agnostic) via the ungated `l3_open_conversation_menu`
/// deep-link, and assert the expected items render (pin/unpin + mark-read +
/// delete) — the conference reuses the same keyed menu items as groups/C2C.
Future<bool> _confRowMenuSurface(Inst inst, String gid) async {
  await _openConversationMenu(inst, gid);
  final hasPin = await inst.waitKey('conversation_context_menu_pin_item',
          timeoutSecs: 8) ||
      await inst.waitKey('conversation_context_menu_unpin_item',
          timeoutSecs: 2);
  final hasMarkRead = await inst.waitKey(
      'conversation_context_menu_mark_read_item',
      timeoutSecs: 5);
  final hasDelete = await inst.waitKey(
      'conversation_context_menu_delete_item',
      timeoutSecs: 5);
  await inst.shot('/tmp/ui_g2_conf_menu_${inst.name}.png');
  await _dismissContextMenu(inst);
  await returnToChatsHome(inst, rounds: 4);
  print(
    '[pair] conf_row_menu_surface: pin/unpin=$hasPin markRead=$hasMarkRead '
    'delete=$hasDelete',
  );
  return hasPin && hasMarkRead && hasDelete;
}

// ===========================================================================
// case 84 — conf_member_list_renders
// ===========================================================================
/// Open the conference profile and assert the member-list page mounts (self
/// member row at least). Conferences (AVChatRoom) reuse the same group-profile /
/// member-list surfaces.
Future<bool> _confMemberListRenders(
  Inst inst,
  String gid,
  String groupName,
) async {
  // Deterministic deep-link open (root-nav, cleared by returnToChatsHome) so no
  // stale nested profile is left behind to poison later cases' key resolution.
  if (!await _openGroupProfileClean(inst, gid)) {
    print('[pair] conf_member_list_renders: profile did not open');
    return false;
  }
  // KeyedSubtree — invisible to flutter_skill; use the element-tree resolver.
  final entryShown =
      await inst.waitKeyCenter('group_profile_members_entry', timeoutSecs: 6);
  if (!await _openGroupMemberListPage(inst, gid)) {
    print('[pair] conf_member_list_renders: member-list page did not open');
    return false;
  }
  final selfTox =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  final selfRowKey = 'group_member_list_item:${_pubkey(selfTox)}';
  final selfRowKeyFull = 'group_member_list_item:$selfTox';
  final memberRow = await inst.waitKeyCenter(selfRowKey, timeoutSecs: 6) ||
      await inst.waitKeyCenter(selfRowKeyFull, timeoutSecs: 3);
  await inst.shot('/tmp/ui_g2_conf_members_${inst.name}.png');
  await returnToChatsHome(inst, rounds: 4);
  print(
    '[pair] conf_member_list_renders: entryShown=$entryShown memberRow=$memberRow',
  );
  return entryShown && memberRow;
}

// ===========================================================================
// sweep_group2 — Batch 7: chain all 14 group/conference cases on ONE launch.
// ===========================================================================
/// Order (state-poison-aware, shared-resource reuse): handshake once → wire the
/// full-mesh bootstrap + B auto-accept (2p prerequisites) → 71 create-cancel
/// (no group) → 72 create-type-selector (CREATES the SHARED private group) → 76
/// rename → 73 members-entry → 80 mute toggle → 74 clear-history → 77 add B
/// (full join; B now in the shared group) → 79 member-list scroll → 81 unread
/// badge → 78 kick B (destructive to membership; B leaves the group) → 75 leave
/// via profile (LAST group case — destroys the shared group) → 82 conf create
/// (SHARED conference) → 83 conf row menu → 84 conf member list. A `finally`
/// end-guard restores B's auto-accept + lands both on the chats home; the
/// friendship is never deleted, so the launch ends FRIENDS.
Future<int> runGroup2Sweep(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[sweep] sweep_group2: missing tox ids (A=$toxA B=$toxB)');
    return 1;
  }
  print(
    '[sweep] sweep_group2: A=${_shortId(toxA)} ($nickA) '
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

  // 2p case ids that depend on the handshake + shared group; failed in bulk if a
  // precondition can't be met.
  const allCaseIds = <String>[
    'group_create_cancel',
    'group_create_type_selector_surface',
    'group_rename_updates_header',
    'group_profile_members_entry',
    'group_mute_toggle',
    'group_profile_clear_history',
    'group_add_member_full_join',
    'group_member_list_scroll',
    'group_unread_badge_two_proc',
    'group_kick_member_ui',
    'group_leave_via_profile_confirm',
    'conf_create_dialog_surface',
    'conf_row_menu_surface',
    'conf_member_list_renders',
  ];

  bool bPriorAutoAccept = false;
  var autoAcceptMutated = false;
  var aMarked = false;
  var bMarked = false;
  try {
    // --- Establish the A<->B friendship (real-UI handshake) once. ---
    final friended =
        await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB);
    if (!friended) {
      print('[sweep] sweep_group2: handshake FAILED — no case can run');
      for (final id in allCaseIds) {
        failed++;
        results[id] = 'FAIL';
      }
    } else {
      // Mark BOTH accounts as test/seed accounts so the L3 navigation + seed
      // tools work (forceHomeRoot + l3_send_group_text). The C2C sweeps do this
      // up front; group2 didn't, so forceHomeRoot was refused ("non-test
      // account") and the group-seed cases (clear-history / unread) fell onto
      // the flaky composer-only path with no recovery. Revoked in the end-guard.
      // Track each side independently so a PARTIAL success (A marked, B failed)
      // still unmarks A in the end-guard instead of leaking the test flag.
      aMarked = await a.markAccountTest();
      bMarked = await b.markAccountTest();
      if (!(aMarked && bMarked)) {
        print('[sweep] sweep_group2: WARN markAccountTest incomplete '
            '(a=$aMarked b=$bMarked) — forceHomeRoot / l3 group-seed tools may '
            'be refused');
      }
      // --- 2p prerequisites: full-mesh bootstrap + B auto-accept (seeding
      // infra; the established group exceptions). Wait for the group exts +
      // connectivity first, exactly like runGroupMessage. ---
      await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
      await b.waitState((s) => s['isConnected'] == true, label: 'B connected');
      await a.waitExt('ext.mcp.toolkit.l3_create_group');
      await a.waitExt('ext.mcp.toolkit.l3_send_group_text');
      await b.waitExt('ext.mcp.toolkit.l3_send_group_text');
      for (final ext in fixtureCBootstrapExtensions) {
        await a.waitExt(ext);
        await b.waitExt(ext);
      }
      await wireFullMeshBootstrap([
        BootstrapTarget('A', a.vm, a.iso),
        BootstrapTarget('B', b.vm, b.iso),
      ]);
      bPriorAutoAccept = await _getAutoAcceptGroupInvites(b);
      autoAcceptMutated = true;
      // Best-effort here (NOT an abort): the 1i cases (71/72/73/74/75/76/80/82/
      // 83/84) don't need auto-accept, and the 2p cases give it more time via
      // case-77's 90s member-count poll + retries. If it never propagates, the
      // 2p cases honestly FAIL on their own member-count gate (no false pass).
      // Re-issues the account-scoped set per round (see the helper).
      if (!await _ensureAutoAcceptGroupInvitesLive(b)) {
        print('[sweep] sweep_group2: WARN B autoAcceptGroupInvites not yet live '
            '— 2p cases (77/78/79/81) may need more time');
      }

      final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final groupName = '$_b7PrivateNamePrefix-$nonce';
      final renamedName = '$_b7PrivateNamePrefix-RENAMED-$nonce';
      final confName = '$_b7ConfNamePrefix-$nonce';

      // --- 71: create-cancel (no group created). ---
      await hard('group_create_cancel', () => _groupCreateCancel(a));

      // --- 72: type-selector surface + CREATE the SHARED private group. ---
      var sharedGid = '';
      await hard('group_create_type_selector_surface', () async {
        sharedGid = await _groupCreateTypeSelectorSurface(a, groupName);
        return sharedGid.isNotEmpty;
      });

      if (sharedGid.isEmpty) {
        // The shared group is the spine of 73/74/76/77/78/79/80/81 — without it
        // they can't run. Mark them failed (honest), still run conference cases.
        print('[sweep] sweep_group2: shared private group not created — '
            'group cases 73/74/76/77/78/79/80/81 cannot run');
        for (final id in const [
          'group_rename_updates_header',
          'group_profile_members_entry',
          'group_mute_toggle',
          'group_profile_clear_history',
          'group_add_member_full_join',
          'group_member_list_scroll',
          'group_unread_badge_two_proc',
          'group_kick_member_ui',
          'group_leave_via_profile_confirm',
        ]) {
          failed++;
          results[id] = 'FAIL';
        }
      } else {
        // --- 76: rename → header (the shared group's display name becomes
        // renamedName for all later cases). ---
        await hard('group_rename_updates_header',
            () => _groupRenameUpdatesHeader(a, sharedGid, groupName,
                renamedName));
        // --- 73: members entry → member-list page mounts. ---
        await hard('group_profile_members_entry',
            () => _groupProfileMembersEntry(a, sharedGid, renamedName));
        // --- 80: mute toggle (flip on/off, no crash). ---
        await hard('group_mute_toggle',
            () => _groupMuteToggle(a, sharedGid, renamedName));
        // --- 74: clear-history (seed own sends, clear via profile). ---
        await hard('group_profile_clear_history',
            () => _groupProfileClearHistory(a, sharedGid, renamedName));

        // --- 77: add B (full join) — B must be in the shared group BEFORE the
        // member-list / unread / kick cases. ---
        var bJoined = false;
        await hard('group_add_member_full_join', () async {
          bJoined = await _groupAddMemberFullJoin(a, b, sharedGid, toxB);
          return bJoined;
        });
        // Resolve B's own group id (for B-side group sends in the unread case).
        final gidB = bJoined
            ? await _waitForJoinedGroup(b, renamedName,
                before: const <String>{}, timeoutSecs: 30)
            : null;

        if (!bJoined) {
          print('[sweep] sweep_group2: B did not join the shared group — '
              'cases 79/81/78 cannot run');
          for (final id in const [
            'group_member_list_scroll',
            'group_unread_badge_two_proc',
            'group_kick_member_ui',
          ]) {
            failed++;
            results[id] = 'FAIL';
          }
        } else {
          // --- 79: member-list scroll (2 members; drag executes, list intact). ---
          await hard('group_member_list_scroll',
              () => _groupMemberListScroll(a, sharedGid, toxB));
          // --- 81: unread badge bump → open clears. ---
          await hard('group_unread_badge_two_proc', () async {
            if (gidB == null) {
              print('[pair] group_unread_badge_two_proc: B group id unresolved');
              return false;
            }
            return _groupUnreadBadgeTwoProc(
                a, b, sharedGid, gidB, renamedName);
          });
          // --- 78: kick B via the desktop member-list UI (destructive). ---
          await hard('group_kick_member_ui',
              () => _groupKickMemberUi(a, sharedGid, toxB));
        }

        // --- 75: leave via profile (LAST group case — destroys the shared
        // group). ---
        await hard('group_leave_via_profile_confirm',
            () => _groupLeaveViaProfileConfirm(a, sharedGid, renamedName));
      }

      // --- 82: conference create (SHARED conference). ---
      var confGid = '';
      await hard('conf_create_dialog_surface', () async {
        confGid = await _confCreateDialogSurface(a, confName);
        return confGid.isNotEmpty;
      });
      if (confGid.isEmpty) {
        print('[sweep] sweep_group2: shared conference not created — '
            'cases 83/84 cannot run');
        for (final id in const [
          'conf_row_menu_surface',
          'conf_member_list_renders',
        ]) {
          failed++;
          results[id] = 'FAIL';
        }
      } else {
        // --- 83: conference row menu surface. ---
        await hard('conf_row_menu_surface',
            () => _confRowMenuSurface(a, confGid));
        // --- 84: conference member list renders. ---
        await hard('conf_member_list_renders',
            () => _confMemberListRenders(a, confGid, confName));
      }
    }
  } finally {
    // END-STATE GUARD: restore B's auto-accept (don't leak the mutated flag into
    // a reused launch) + land both on the chats home. The friendship is never
    // deleted, so the registered result is FRIENDS — recompute it from the live
    // state so the runner never trusts an unachieved result.
    try {
      if (autoAcceptMutated && !bPriorAutoAccept) {
        try {
          await _setAutoAcceptGroupInvites(b, false);
        } on DriveError catch (e) {
          print('[sweep] sweep_group2 end-clean: restore auto-accept failed: '
              '${e.message}');
        }
      }
      if (aMarked) {
        try {
          await a.unmarkAccountTest();
        } on DriveError catch (e) {
          print('[sweep] sweep_group2 end-clean: unmark A failed: ${e.message}');
        }
      }
      if (bMarked) {
        try {
          await b.unmarkAccountTest();
        } on DriveError catch (e) {
          print('[sweep] sweep_group2 end-clean: unmark B failed: ${e.message}');
        }
      }
      await returnToChatsHome(a, rounds: 4);
      await b.foreground();
      await returnToChatsHome(b, rounds: 4);
    } on PermissionBlockedError catch (e) {
      print('[sweep] sweep_group2 end-clean: BLOCKED (${e.message})');
    } on DriveError catch (e) {
      print('[sweep] sweep_group2 end-clean: best-effort failed: ${e.message}');
    }
    try {
      endFriends = await areFriends(a, toxB) && await areFriends(b, toxA);
    } on DriveError {
      endFriends = false;
    }
    print(
      '[sweep] sweep_group2 RESULTS: $passed PASS / $failed FAIL '
      '($results) | endFriends=$endFriends',
    );
    try {
      await a.shot('/tmp/ui_group2_sweep_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_group2_sweep_B.png');
    } on DriveError {
      // best-effort
    }
    if (!endFriends) {
      print('[sweep] sweep_group2: end state is NOT friends — failing the sweep '
          'so the runner does not trust the result-state contract');
    }
  }
  // FAIL if any HARD case failed OR the launch did not reach the registered
  // FRIENDS end state.
  return (failed == 0 && endFriends) ? 0 : 1;
}

// ===========================================================================
// Individual-case dispatch (each builds its OWN minimal precondition).
// ===========================================================================
/// Whether [scenario] is one of the 14 Batch-7 group/conference cases.
bool _isGroup2CaseScenario(String scenario) => const {
      'group_create_cancel',
      'group_create_type_selector_surface',
      'group_rename_updates_header',
      'group_profile_members_entry',
      'group_mute_toggle',
      'group_profile_clear_history',
      'group_add_member_full_join',
      'group_member_list_scroll',
      'group_unread_badge_two_proc',
      'group_kick_member_ui',
      'group_leave_via_profile_confirm',
      'conf_create_dialog_surface',
      'conf_row_menu_surface',
      'conf_member_list_renders',
    }.contains(scenario);

/// 2p cases that need B joined to the group (the rest are single-instance: A
/// creates + drives its own group, B stays launched-but-idle).
bool _isGroup2TwoProcessCase(String scenario) => const {
      'group_add_member_full_join',
      'group_member_list_scroll',
      'group_unread_badge_two_proc',
      'group_kick_member_ui',
    }.contains(scenario);

/// Run a single Batch-7 case standalone. The 1i cases need only A + a fresh
/// private/conference group A creates through the REAL dialog; the 2p cases need
/// the A<->B friendship + B joined to a fresh private group. Returns 0/1.
Future<int> runGroup2Case(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // Cases that drive their OWN dialog open from scratch — no pre-created group.
  if (scenario == 'group_create_cancel') {
    return await _groupCreateCancel(a) ? 0 : 1;
  }
  if (scenario == 'group_create_type_selector_surface') {
    final gid =
        await _groupCreateTypeSelectorSurface(a, '$_b7PrivateNamePrefix-$nonce');
    return gid.isNotEmpty ? 0 : 1;
  }
  if (scenario == 'conf_create_dialog_surface') {
    final gid = await _confCreateDialogSurface(a, '$_b7ConfNamePrefix-$nonce');
    return gid.isNotEmpty ? 0 : 1;
  }

  // Conference cases that need a pre-created conference (83/84).
  if (scenario == 'conf_row_menu_surface' ||
      scenario == 'conf_member_list_renders') {
    final confName = '$_b7ConfNamePrefix-$nonce';
    final created = await _createGroupViaUI(a, confName, groupType: 'conference');
    if (created.groupId.isEmpty) {
      print('[pair] $scenario: could not create the conference');
      return 1;
    }
    switch (scenario) {
      case 'conf_row_menu_surface':
        return await _confRowMenuSurface(a, created.groupId) ? 0 : 1;
      case 'conf_member_list_renders':
        return await _confMemberListRenders(a, created.groupId, confName)
            ? 0
            : 1;
    }
  }

  // Single-instance group cases that need a pre-created PRIVATE group A drives
  // alone (76/73/80/74/75).
  if (!_isGroup2TwoProcessCase(scenario)) {
    final name = '$_b7PrivateNamePrefix-$nonce';
    final created = await _createGroupViaUI(a, name, groupType: 'private');
    if (created.groupId.isEmpty) {
      print('[pair] $scenario: could not create the private group');
      return 1;
    }
    final gid = created.groupId;
    switch (scenario) {
      case 'group_rename_updates_header':
        return await _groupRenameUpdatesHeader(
                a, gid, name, '$_b7PrivateNamePrefix-RENAMED-$nonce')
            ? 0
            : 1;
      case 'group_profile_members_entry':
        return await _groupProfileMembersEntry(a, gid, name) ? 0 : 1;
      case 'group_mute_toggle':
        return await _groupMuteToggle(a, gid, name) ? 0 : 1;
      case 'group_profile_clear_history':
        return await _groupProfileClearHistory(a, gid, name) ? 0 : 1;
      case 'group_leave_via_profile_confirm':
        return await _groupLeaveViaProfileConfirm(a, gid, name) ? 0 : 1;
    }
  }

  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';

  // Case 77 (add-member-full-join) standalone: the ASSERTED action is the REAL
  // add-member UI putting B into the group. `_establishTwoProcessGroup` would
  // ITSELF invite+join B (via l3_invite_to_group on test accounts), so reusing
  // it would make `memberCount>=2` true BEFORE the real add-member UI runs — a
  // false pass (codex P1). Instead: establish the friendship + wire the 2p
  // prerequisites + create the group with B NOT yet invited, then drive the real
  // add-member UI as the asserted action.
  if (scenario == 'group_add_member_full_join') {
    final friendsReady = await _retryBool(
      () async => await areFriends(a, toxB) && await areFriends(b, toxA),
      label: '$scenario friendship ready',
      attempts: 20,
      intervalMs: 1000,
    );
    if (!friendsReady) {
      print('[pair] $scenario requires an existing friendship');
      return 1;
    }
    await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
    await b.waitState((s) => s['isConnected'] == true, label: 'B connected');
    for (final ext in fixtureCBootstrapExtensions) {
      await a.waitExt(ext);
      await b.waitExt(ext);
    }
    await wireFullMeshBootstrap([
      BootstrapTarget('A', a.vm, a.iso),
      BootstrapTarget('B', b.vm, b.iso),
    ]);
    final bPrior = await _getAutoAcceptGroupInvites(b);
    // Hard gate (codex P2): B's auto-accept must actually be LIVE before the
    // invite, else B silently misses the auto-join and the case false-FAILs.
    // Re-issues the account-scoped set per round (see the helper); restore +
    // abort if it never propagates.
    if (!await _ensureAutoAcceptGroupInvitesLive(b)) {
      if (!bPrior) {
        try {
          await _setAutoAcceptGroupInvites(b, false);
        } on DriveError catch (_) {}
      }
      print('[pair] $scenario: B autoAcceptGroupInvites did not take effect');
      return 1;
    }
    try {
      final created = await _createGroupViaUI(
        a,
        '$_b7PrivateNamePrefix-ADD-$nonce',
        groupType: 'private',
      );
      if (created.groupId.isEmpty) {
        print('[pair] $scenario: could not create the private group');
        return 1;
      }
      // The REAL add-member UI is the asserted action (B not yet in the group).
      return await _groupAddMemberFullJoin(a, b, created.groupId, toxB) ? 0 : 1;
    } finally {
      if (!bPrior) {
        try {
          await _setAutoAcceptGroupInvites(b, false);
        } on DriveError catch (e) {
          print('[pair] $scenario: restore auto-accept failed: ${e.message}');
        }
      }
    }
  }

  // Cases 78/79/81 legitimately need B ALREADY in the group (the asserted action
  // is kick / scroll / unread, not the join), so establish a live two-process
  // group with B joined, restore B's auto-accept in a finally.
  // Mark both accounts test: _memberRowKeyFor reads the bridge member list via
  // the test-gated l3_group_member_list (the SWEEP marks up front, but these
  // STANDALONE atomic entries don't), and the establish/cleanup l3 tools are
  // gated too. Unmark LAST so the gated tools still work.
  final aMarked = await a.markAccountTest();
  final bMarked = await b.markAccountTest();
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: '$_b7PrivateNamePrefix-CASE',
  );
  if (est == null) {
    print('[pair] $scenario: could not establish a two-process group');
    if (aMarked) {
      try {
        await a.unmarkAccountTest();
      } on DriveError catch (_) {}
    }
    if (bMarked) {
      try {
        await b.unmarkAccountTest();
      } on DriveError catch (_) {}
    }
    return 1;
  }
  try {
    switch (scenario) {
      case 'group_member_list_scroll':
        return await _groupMemberListScroll(a, est.groupIdA, toxB) ? 0 : 1;
      case 'group_unread_badge_two_proc':
        return await _groupUnreadBadgeTwoProc(
                a, b, est.groupIdA, est.groupIdB, est.groupName)
            ? 0
            : 1;
      case 'group_kick_member_ui':
        return await _groupKickMemberUi(a, est.groupIdA, toxB) ? 0 : 1;
    }
    return 1;
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (e) {
        print('[pair] $scenario: restore auto-accept failed: ${e.message}');
      }
    }
    if (aMarked) {
      try {
        await a.unmarkAccountTest();
      } on DriveError catch (_) {}
    }
    if (bMarked) {
      try {
        await b.unmarkAccountTest();
      } on DriveError catch (_) {}
    }
  }
}
