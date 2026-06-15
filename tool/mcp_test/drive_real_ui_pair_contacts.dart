// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 4 of the real-UI sweep campaign — "Contacts + friend profile" (15
// cases, TWO-PROCESS). See tool/mcp_test/REAL_UI_SWEEP_CAMPAIGN.md.
//
// `sweep_contacts` drives BOTH instances. ONE handshake at the top establishes
// the A<->B friendship that cases 33–43 reuse; the add-friend-dialog guard
// cases (30/31/32) run BEFORE the handshake (they need no friendship — case 31
// asserts an inline invalid-ID error, case 32 a self-add guard, both back out
// without sending). Case 44 (delete friend via the keyed confirm dialog) runs
// LAST so the sweep ENDS no-friend on BOTH sides (the registered contract:
// required=no-friend, result=no-friend — a fresh pair, friended mid-sweep,
// torn down at the end).
//
// State contract (registered in fixture_c_unified_runner.dart):
//   required = no-friend  (fresh pair launch; the sweep does its OWN handshake)
//   result   = no-friend  (case 44 deletes the friend on both sides)
//
// REUSE (not reinvented): driveAddFriend / driveRespondToApplication / areFriends
// / friendNick / openFriendProfile / deleteFriendViaProfile / waitFriendshipState
// (drive_real_ui_pair_friends.dart); ensureContactsShell / ensureNewEntryShell /
// returnToChatsHome / _homeShellTab / _tryTapText (shell); openChat /
// sendComposerMessage (message_call).
//
// FRIEND-PROFILE keys (all ALREADY in the fork — no production change needed for
// this batch; tencent_cloud_chat_user_profile_body.dart):
//   - friend_profile_send_message_tile       (leftmost [Send,Voice,Video] tile)
//   - user_profile_pin_switch                (OperationBar Switch — Prefs-backed)
//   - user_profile_block_switch              (OperationBar Switch — Prefs-backed)
//   - user_profile_conversation_mute_switch  (bare Switch — native recvOpt path)
//   - user_profile_edit_remark_button        (opens the modify-remark dialog)
//   - user_profile_modify_remark_text_field / _confirm_button
//   - user_profile_clear_history_button      (opens clear-history confirm)
//   - user_profile_clear_history_confirm_button
//   - user_profile_delete_friend_button      (opens delete confirm dialog)
//   - user_profile_delete_friend_confirm_button  (keyed + `handled` double-fire
//     guard — the REAL_UI doc's "confirm button key not found" note is STALE; the
//     OPENER `user_profile_delete_friend_button` and the CONFIRM
//     `user_profile_delete_friend_confirm_button` are DISTINCT keys, both present)
// CONTACT keys: contact_list_item:<userId> (tap -> toxee `onTapContactItem` ->
//   `_showUserProfileOnRight` opens the friend profile), contact_search_field,
//   contact_new_contacts_tab, contact_blocked_users_tab.
//
// KNOWN-BUG cases (asserted HARD on purpose so the run phase surfaces them):
//   - case 39 (mute, S114/S83): the FFI ABI crash is FIXED (the
//     DartSetC2CReceiveMessageOpt 3-arg signature fix). This case is the
//     REGRESSION GATE: toggling the switch x2 must NOT crash and the switch must
//     flip. The recvOpt DUMP value sync is the documented native->Dart residual
//     (the binary-replacement path stores opt in a C++ map distinct from the
//     Prefs-backed conversation cache l3 reads), so the recvOpt assertion is SOFT
//     (logged, not gated) while the no-crash + switch-flip is HARD.
//   - case 40 (remark, S113/S30): `_onChangeFriendRemark` -> SDK `setFriendInfo`
//     (native binary-replacement path) is KNOWN BROKEN — the dialog input lands
//     but Confirm does not persist (UI + dump stay the old name). This case is a
//     HARD gate asserting the remark PERSISTS; a live FAIL here is the SIGNAL to
//     root-fix the native `dart_compat` setFriendInfo path in the run phase
//     (mirroring the mute ABI fix — likely another Dart* signature/stub drift).

const _b4RemarkText = 'RuiB4Remark';

/// Pubkey-keyed contact-row helpers: the contact list item key is
/// `contact_list_item:<userID>`, and `userID` may be the FULL 76-char tox
/// address OR the 64-char pubkey depending on the data path — try both.
String _contactItemFullKey(String tox) => 'contact_list_item:${tox.trim()}';
String _contactItemShortKey(String tox) => 'contact_list_item:${_pubkey(tox)}';

/// True if a friend-profile sheet is currently mounted (delete button / name /
/// send-message tile present). Reuses the same probes as `_isFriendProfileShell`.
Future<bool> _onFriendProfile(Inst inst, {int timeoutSecs = 6}) async {
  return await inst.waitKey('user_profile_delete_friend_button',
          timeoutSecs: timeoutSecs) ||
      await inst.waitKey('user_profile_friend_name_text', timeoutSecs: 2) ||
      await inst.waitKey('friend_profile_send_message_tile', timeoutSecs: 2);
}

/// Open the friend profile for [tox] from the Contacts tab by tapping the
/// contact row (toxee's `onTapContactItem` -> `_showUserProfileOnRight`). Unlike
/// `openFriendProfile` (friends.dart), this is tolerant: returns whether the
/// profile mounted (no throw) so the sweep can record a per-case FAIL instead
/// of aborting the whole chain.
Future<bool> _ensureFriendProfileOpen(Inst inst, String tox) async {
  await inst.foreground();
  if (await _onFriendProfile(inst, timeoutSecs: 1)) return true;
  await ensureContactsShell(inst);
  final fullKey = _contactItemFullKey(tox);
  final shortKey = _contactItemShortKey(tox);
  for (var attempt = 0; attempt < 4; attempt++) {
    final tapped = await inst.tryTapKey(fullKey, retries: 2) ||
        await inst.tryTapKey(shortKey, retries: 2);
    if (tapped && await _onFriendProfile(inst, timeoutSecs: 6)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  return _onFriendProfile(inst, timeoutSecs: 2);
}

/// Read a friend's USER-EDITED REMARK from the dump (`friends[].remark` — the
/// Prefs-backed alias the host displays from). The Tox `nickName` is a SEPARATE
/// field; the friend-profile remark dialog persists into `remark` (via the
/// Platform-path Tim2ToxSdkPlatform.setFriendInfo -> prefs.setFriendRemark), NOT
/// into `nickName`, so the remark must be asserted on this field.
Future<String> _friendRemark(Inst inst, String tox) async {
  final s = await inst.dumpState();
  for (final f in (s['friends'] as List? ?? const [])) {
    if (f is Map && _pubkey(f['userId']?.toString() ?? '') == _pubkey(tox)) {
      return f['remark']?.toString() ?? '';
    }
  }
  return '';
}

/// Read a friend's blocked state from the dump (`blockedUsers` is the live
/// FfiChatService.blockedUsers set — Prefs-backed, race-free, pubkey entries).
Future<bool> _isBlocked(Inst inst, String tox) async {
  final s = await inst.dumpState();
  final blocked = (s['blockedUsers'] as List?) ?? const [];
  return blocked.any((e) => _pubkey(e?.toString() ?? '') == _pubkey(tox));
}

/// Read a friend's pinned state from the dump (`pinnedConversations` is the
/// Prefs-backed pinned set; entries are conversationIDs `c2c_<pubkey>` OR raw
/// pubkeys depending on the path — match either).
Future<bool> _isPinned(Inst inst, String tox) async {
  final s = await inst.dumpState();
  final pinned = (s['pinnedConversations'] as List?) ?? const [];
  final pk = _pubkey(tox);
  return pinned.any((e) {
    final v = e?.toString() ?? '';
    return v == 'c2c_$pk' || _pubkey(v) == pk;
  });
}

/// Read a friend's C2C conversation recvOpt from the dump (`conversations[]`
/// entry for `c2c_<pubkey>`; recvOpt 2 == mute/do-not-disturb). Returns null
/// when the conversation isn't listed yet.
Future<int?> _recvOpt(Inst inst, String tox) async {
  final convId = 'c2c_${_pubkey(tox)}';
  final s = await inst.dumpState();
  for (final c in (s['conversations'] as List?) ?? const []) {
    if (c is Map && c['conversationID']?.toString() == convId) {
      final v = c['recvOpt'];
      return v is num ? v.toInt() : null;
    }
  }
  return null;
}

/// Read a keyed Switch's current boolean `value` via flutter_skill's
/// `interactiveStructured` (it merges each Switch element's `state['value']`
/// into the element entry). Returns null when the key isn't present / isn't a
/// Switch with a bool value — lets a caller distinguish "couldn't read" from
/// true/false.
Future<bool?> _switchValue(Inst inst, String key) async {
  final r = await inst.skill('interactiveStructured', const {});
  final data = r['data'];
  final elements = data is Map ? data['elements'] : null;
  if (elements is! List) return null;
  // Return the LAST matching element's value — when a real-UI sweep stacks
  // routes carrying the same Switch key (a re-opened group profile with buried
  // duplicates), the topmost (on-screen) Switch is the one tapKeyCenter targets
  // (resolveKeyCenter prefers the last/topmost candidate too), so reading the
  // first (oldest, buried) Switch would mismatch and falsely report no flip.
  bool? value;
  for (final e in elements) {
    if (e is! Map || e['key'] != key) continue;
    final v = e['value'];
    if (v is bool) value = v;
  }
  return value;
}

Future<bool> _waitBlocked(Inst inst, String tox, bool want,
    {int timeoutSecs = 12}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _isBlocked(inst, tox) == want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

Future<bool> _waitPinned(Inst inst, String tox, bool want,
    {int timeoutSecs = 12}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _isPinned(inst, tox) == want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Open the AddFriendDialog on [inst] (reuse driveAddFriend's robust opener
/// logic, but stop once the dialog's input field is present). Returns whether
/// the dialog opened (no throw).
Future<bool> _openAddFriendDialog(Inst inst) async {
  await inst.foreground();
  if (await inst.waitKey('add_friend_id_input', timeoutSecs: 1)) return true;
  // Tab-independent, non-blocking L3 invoker first (works from any home tab),
  // mirroring driveAddFriend.
  if (await inst.openAddFriendDialogViaL3()) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (await inst.waitKey('add_friend_id_input', timeoutSecs: 4)) return true;
  }
  await ensureNewEntryShell(inst);
  for (var attempt = 0; attempt < 3; attempt++) {
    if (!await inst.tryTapKey('new_entry_menu_button', retries: 2) &&
        !await inst.tryTapKey('contact_app_bar_menu_button', retries: 2)) {
      await _tryTapText(inst, 'New Chat');
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!await inst.tryTapKey('new_entry_add_contact_item', retries: 2) &&
        !await inst.tryTapKey('contact_app_bar_add_contact_item', retries: 2)) {
      await _tryTapText(inst, 'Add Contact');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (await inst.waitKey('add_friend_id_input', timeoutSecs: 2)) return true;
    await inst.openAddFriendDialogViaL3();
    if (await inst.waitKey('add_friend_id_input', timeoutSecs: 3)) return true;
  }
  return inst.waitKey('add_friend_id_input', timeoutSecs: 1);
}

/// Dismiss the AddFriendDialog (ESC; the dialog's `Focus(autofocus:true)` +
/// CallbackShortcuts maps Escape -> Navigator.maybePop). Best-effort + bounded.
Future<bool> _closeAddFriendDialog(Inst inst) async {
  if (!await inst.waitKey('add_friend_id_input', timeoutSecs: 1)) return true;
  try {
    await inst.osaEscape();
  } on DriveError {
    // best-effort
  }
  if (await inst.waitKeyGone('add_friend_id_input', timeoutSecs: 4)) return true;
  // Fallback: the keyed Cancel button (single-fire — it pops the dialog only).
  if (await inst.tapKeyCenter('add_friend_cancel_button', timeoutSecs: 3)) {
    return inst.waitKeyGone('add_friend_id_input', timeoutSecs: 4);
  }
  return inst.waitKeyGone('add_friend_id_input', timeoutSecs: 2);
}

// ===========================================================================
// case 30 — add_friend_dialog_esc_close (S5)
// ===========================================================================
/// Open Add Contact, then ESC closes the dialog (the input field is gone).
Future<bool> _addFriendDialogEscClose(Inst inst) async {
  if (!await _openAddFriendDialog(inst)) {
    print('[pair] add_friend_dialog_esc_close: dialog did not open');
    return false;
  }
  final opened = await inst.waitKey('add_friend_id_input', timeoutSecs: 4);
  // ESC closes (Focus(autofocus) + CallbackShortcuts(escape) -> maybePop).
  try {
    await inst.osaEscape();
  } on DriveError catch (e) {
    print('[pair] add_friend_dialog_esc_close: ESC unavailable: ${e.message}');
    await _closeAddFriendDialog(inst);
    return false;
  }
  final closed = await inst.waitKeyGone('add_friend_id_input', timeoutSecs: 6);
  print('[pair] add_friend_dialog_esc_close: opened=$opened closed=$closed');
  return opened && closed;
}

// ===========================================================================
// case 31 — add_friend_invalid_id_error (S5)
// ===========================================================================
/// Garbage Tox ID + a message -> Submit -> the form validator surfaces the
/// inline "Tox address must be 76 hexadecimal characters" error
/// (addFriendInvalidToxIdHint). No crash, dialog stays. Backs out at the end.
Future<bool> _addFriendInvalidIdError(Inst inst) async {
  if (!await _openAddFriendDialog(inst)) {
    print('[pair] add_friend_invalid_id_error: dialog did not open');
    return false;
  }
  // Both fields must be non-empty so the Submit button is enabled (_canSubmit
  // gates on both controllers). The message field is pre-filled with the
  // localized default; type a garbage ID into the id field.
  await inst.focusType('add_friend_id_input', 'not-a-valid-tox-id-1234');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  // Submit triggers _formKey.validate() -> _validateToxId returns the hint.
  await inst.tapKey('add_friend_submit_button');
  final errorShown = await inst.waitText(
    'Tox address must be 76 hexadecimal characters',
    timeoutSecs: 8,
  );
  // Dialog stays (validate() short-circuits before any FFI add) and no
  // friendship/application was created.
  final dialogStays = await inst.waitKey('add_friend_id_input', timeoutSecs: 3);
  // Clear the field + back out so the next add-friend case starts clean.
  await inst.tapKey('add_friend_id_input');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort
  }
  final closed = await _closeAddFriendDialog(inst);
  print(
    '[pair] add_friend_invalid_id_error: error=$errorShown '
    'dialogStays=$dialogStays closed=$closed',
  );
  return errorShown && dialogStays && closed;
}

// ===========================================================================
// case 32 — add_friend_self_id_guard (S55)
// ===========================================================================
/// Enter OWN tox ID (76 hex, passes the validator) + Submit -> _submit's
/// self-add guard (`compareToxIds(rawId, service.accountKey)`) surfaces the
/// "You cannot add yourself as a friend" SNACKBAR and returns WITHOUT sending.
/// Asserts the snackbar + dialog stays + no self-friendship, then backs out.
Future<bool> _addFriendSelfIdGuard(Inst inst, String selfTox) async {
  if (selfTox.isEmpty || selfTox.length < 76) {
    print('[pair] add_friend_self_id_guard: own tox id unavailable ($selfTox)');
    return false;
  }
  if (!await _openAddFriendDialog(inst)) {
    print('[pair] add_friend_self_id_guard: dialog did not open');
    return false;
  }
  await inst.focusType('add_friend_id_input', selfTox);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('add_friend_submit_button');
  final guardShown = await inst.waitText(
    'You cannot add yourself as a friend',
    timeoutSecs: 8,
  );
  final dialogStays = await inst.waitKey('add_friend_id_input', timeoutSecs: 3);
  // Sanity: we are not somehow our own friend.
  final notSelfFriend = !await areFriends(inst, selfTox);
  // Clear + back out.
  await inst.tapKey('add_friend_id_input');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort
  }
  final closed = await _closeAddFriendDialog(inst);
  print(
    '[pair] add_friend_self_id_guard: guard=$guardShown dialogStays=$dialogStays '
    'notSelfFriend=$notSelfFriend closed=$closed',
  );
  return guardShown && dialogStays && notSelfFriend && closed;
}

// ===========================================================================
// case 33 — add_friend_duplicate_guard (S56)  [needs friendship]
// ===========================================================================
/// With A<->B already friends, B enters A's tox ID again + Submit -> the dedup
/// guard (`alreadyFriend` after the getFriendList read) surfaces the "This user
/// is already in your friend list" SNACKBAR. No duplicate add, dialog stays.
Future<bool> _addFriendDuplicateGuard(Inst b, String toxA) async {
  if (!await areFriends(b, toxA)) {
    print('[pair] add_friend_duplicate_guard: B is not friends with A yet');
    return false;
  }
  if (!await _openAddFriendDialog(b)) {
    print('[pair] add_friend_duplicate_guard: dialog did not open');
    return false;
  }
  await b.focusType('add_friend_id_input', toxA);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await b.tapKey('add_friend_submit_button');
  // The guard fires AFTER an async getFriendList read, so allow a slightly
  // longer window than the synchronous validators.
  final guardShown = await b.waitText(
    'This user is already in your friend list',
    timeoutSecs: 12,
  );
  final dialogStays = await b.waitKey('add_friend_id_input', timeoutSecs: 3);
  await b.tapKey('add_friend_id_input');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  try {
    await b.osaClear();
  } on DriveError {
    // best-effort
  }
  final closed = await _closeAddFriendDialog(b);
  print(
    '[pair] add_friend_duplicate_guard: guard=$guardShown '
    'dialogStays=$dialogStays closed=$closed',
  );
  return guardShown && dialogStays && closed;
}

// ===========================================================================
// case 34 — contacts_subtabs_cycle (S106)
// ===========================================================================
/// On the Contacts tab, cycle New Contacts <-> Blocked Users sub-tabs and assert
/// the DETAIL PANE actually SWAPS each time (toxee's desktop two-pane swaps the
/// right module + title on a tab tap). The sub-tab rows are keyed
/// (contact_new_contacts_tab / contact_blocked_users_tab on the
/// InkWell/GestureDetector). Asserts DETAIL-ONLY markers (never the tab control
/// itself, which is always present): New Contacts -> the application list's
/// empty-state key `contact_applications_list_empty` (the pane mounted
/// TencentCloudChatContactApplication); Blocked Users -> the block-list
/// empty-state copy "No blocked users" (the pane mounted
/// TencentCloudChatContactBlockList). The list is empty at this point in the
/// sweep (no one blocked, no pending applications), so the empty-state markers
/// are the reliable detail-pane signal.
Future<bool> _contactsSubtabsCycle(Inst inst) async {
  await ensureContactsShell(inst);
  await inst.foreground();
  // Open Blocked Users FIRST so the New-Contacts assertion below proves a real
  // SWAP back (not just "happened to already be on New Contacts").
  if (!await inst.tryTapKey('contact_blocked_users_tab', retries: 2)) {
    await _tryTapText(inst, 'Blocked Users');
    await inst.tapAt(240, 270); // Blocked Users master-row fallback (1280x768)
  }
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  // Blocked Users DETAIL pane rendered: the block-list empty-state copy. This
  // text only renders inside TencentCloudChatContactBlockList's body (never on
  // the tab control), so it proves the pane swapped + rendered its body.
  final blockedDetailShown =
      await inst.waitText('No blocked users', timeoutSecs: 6);
  // Swap to New Contacts.
  if (!await inst.tryTapKey('contact_new_contacts_tab', retries: 2)) {
    await _tryTapText(inst, 'New Contacts');
    await inst.tapAt(240, 173); // New Contacts master-row fallback
  }
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  // New Contacts DETAIL pane rendered: the application list's empty-state KEY,
  // which only exists inside TencentCloudChatContactApplication's list body
  // (detail-pane-only). Proves the swap back to New Contacts mounted the
  // application panel.
  final newContactsDetailShown =
      await inst.waitKey('contact_applications_list_empty', timeoutSecs: 6);
  // Return to the contact friend list so later cases find friend rows.
  await ensureContactsShell(inst);
  print(
    '[pair] contacts_subtabs_cycle: blockedDetail=$blockedDetailShown '
    'newContactsDetail=$newContactsDetailShown',
  );
  return blockedDetailShown && newContactsDetailShown;
}

// ===========================================================================
// case 35 — contacts_row_opens_friend_profile (S52)  [needs friendship]
// ===========================================================================
/// Tap the friend's contact row -> toxee `onTapContactItem` opens the friend
/// profile sheet on the right (`_showUserProfileOnRight`). Asserts the profile
/// mounted (name text / delete button present).
Future<bool> _contactsRowOpensFriendProfile(Inst inst, String toxFriend) async {
  final opened = await _ensureFriendProfileOpen(inst, toxFriend);
  print('[pair] contacts_row_opens_friend_profile: opened=$opened');
  return opened;
}

// ===========================================================================
// case 36 — friendprof_send_message_tile (S115)  [needs friendship]
// ===========================================================================
/// From the friend profile, tap the Send-Message tile -> toxee pops the profile,
/// switches to Chats, opens the 1:1 chat for that friend. Asserts the chat
/// surface is active for c2c_<pubkey>.
Future<bool> _friendprofSendMessageTile(Inst inst, String toxFriend) async {
  if (!await _ensureFriendProfileOpen(inst, toxFriend)) {
    print('[pair] friendprof_send_message_tile: profile did not open');
    return false;
  }
  // Tap the leftmost [Send,Voice,Video] tile. SINGLE-FIRE ONLY: its onTap
  // toggles out of the profile + switches tab + opens the chat (a route change),
  // so a double-fire (flutter_skill's `tap` / a `tapText` fallback) could pop
  // through and re-enter. tapKeyCenter already retries the bounds resolution 5x
  // (~1s), so there is no text fallback here by design — a missing tile is a
  // hard FAIL, not a double-fire risk.
  if (!await inst.tapKeyCenter('friend_profile_send_message_tile',
      timeoutSecs: 6)) {
    print('[pair] friendprof_send_message_tile: tile not tappable (single-fire)');
    return false;
  }
  await inst.foreground();
  final convId = 'c2c_${_pubkey(toxFriend)}';
  final opened = await _chatSurfaceReady(inst, convId, timeoutSecs: 12);
  // Land back on the Contacts shell so the next profile-driven case re-opens
  // the profile cleanly.
  await ensureContactsShell(inst);
  print('[pair] friendprof_send_message_tile: chatOpened=$opened ($convId)');
  return opened;
}

// ===========================================================================
// case 37 — friendprof_pin_toggle (S84)  [needs friendship]
// ===========================================================================
/// Friend-profile Pin switch ON -> `pinnedConversations` includes the peer;
/// then OFF -> it's removed again (restore unpinned). Prefs-backed (solid).
Future<bool> _friendprofPinToggle(Inst inst, String toxFriend) async {
  if (!await _ensureFriendProfileOpen(inst, toxFriend)) {
    print('[pair] friendprof_pin_toggle: profile did not open');
    return false;
  }
  final before = await _isPinned(inst, toxFriend);
  // Single-fire the switch: flutter_skill's double-firing `tap` would toggle a
  // Switch twice (net no-op). tapKeyCenter dispatches exactly one pointer tap.
  if (!await inst.tapKeyCenter('user_profile_pin_switch', timeoutSecs: 6)) {
    print('[pair] friendprof_pin_toggle: pin switch not tappable');
    return false;
  }
  final pinnedOn = await _waitPinned(inst, toxFriend, !before);
  // Toggle back to the original (unpinned) state to restore.
  if (!await inst.tapKeyCenter('user_profile_pin_switch', timeoutSecs: 6)) {
    print('[pair] friendprof_pin_toggle: pin switch not tappable (restore)');
    return false;
  }
  final restored = await _waitPinned(inst, toxFriend, before);
  print(
    '[pair] friendprof_pin_toggle: before=$before flippedTo=${!before}=$pinnedOn '
    'restored=$restored',
  );
  return pinnedOn && restored;
}

// ===========================================================================
// case 38 — friendprof_block_unblock (S29)  [needs friendship]
// ===========================================================================
/// Friend-profile Block switch ON -> `blockedUsers` includes the peer; OFF ->
/// removed (both directions). Prefs-backed (solid). Ends UNBLOCKED.
Future<bool> _friendprofBlockUnblock(Inst inst, String toxFriend) async {
  if (!await _ensureFriendProfileOpen(inst, toxFriend)) {
    print('[pair] friendprof_block_unblock: profile did not open');
    return false;
  }
  // Make sure we start unblocked (a prior failed case could leave it blocked).
  if (await _isBlocked(inst, toxFriend)) {
    await inst.tapKeyCenter('user_profile_block_switch', timeoutSecs: 6);
    await _waitBlocked(inst, toxFriend, false);
  }
  if (!await inst.tapKeyCenter('user_profile_block_switch', timeoutSecs: 6)) {
    print('[pair] friendprof_block_unblock: block switch not tappable');
    return false;
  }
  final blockedOn = await _waitBlocked(inst, toxFriend, true);
  if (!await inst.tapKeyCenter('user_profile_block_switch', timeoutSecs: 6)) {
    print('[pair] friendprof_block_unblock: block switch not tappable (unblock)');
    return false;
  }
  final unblocked = await _waitBlocked(inst, toxFriend, false);
  print(
    '[pair] friendprof_block_unblock: blockedOn=$blockedOn unblocked=$unblocked',
  );
  return blockedOn && unblocked;
}

// ===========================================================================
// case 39 — friendprof_mute_toggle_regression (S114/S83)  [needs friendship]
// ===========================================================================
/// Mute switch REGRESSION GATE (the FFI ABI crash fix). Toggle the
/// `user_profile_conversation_mute_switch` TWICE: the app must NOT crash
/// (sessionReady stays true on BOTH sides) AND the switch's visible value must
/// actually FLIP on each toggle (ON then back OFF) — read directly from the
/// widget via `interactiveStructured`'s per-element `value`. HARD: no-crash +
/// the switch value flipped ON then OFF. SOFT (logged, NOT gated): the recvOpt
/// dump value — the binary-replacement path stores `opt` in a C++ map distinct
/// from the Prefs-backed conversation cache l3 reads (the documented native->Dart
/// sync residual), so the dump may not reflect the toggle even on a healthy run.
///
/// Why the switch-VALUE flip (not just liveness): a dead/no-op switch (the
/// regression we are guarding) would leave both sessions alive while never
/// flipping — a liveness-only gate would FALSE-PASS that. The Switch's onChanged
/// does `setState(disturb = value)` synchronously regardless of the SDK result,
/// so the rendered value flips even before the (residual) recvOpt sync — making
/// the value the right HARD signal that the tap reached a live, non-stubbed
/// Switch (and, with the ABI fix, that the dispatch didn't SIGSEGV).
Future<bool> _friendprofMuteToggleRegression(
  Inst a,
  Inst b,
  String toxFriend,
) async {
  const sw = 'user_profile_conversation_mute_switch';
  if (!await _ensureFriendProfileOpen(a, toxFriend)) {
    print('[pair] friendprof_mute_toggle_regression: profile did not open');
    return false;
  }
  final recvBefore = await _recvOpt(a, toxFriend);
  final valueBefore = await _switchValue(a, sw);
  if (valueBefore == null) {
    print('[pair] friendprof_mute_toggle_regression: mute switch value '
        'unreadable (key absent / not a Switch)');
    return false;
  }
  // Toggle #1 (flip away from the original value).
  if (!await a.tapKeyCenter(sw, timeoutSecs: 6)) {
    print('[pair] friendprof_mute_toggle_regression: mute switch not tappable');
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  // No-crash check after the FIRST toggle (the original ABI bug SIGSEGV'd here):
  // BOTH instances must still be alive + sessionReady (the crash took down both).
  final aliveAfter1 = await _bothSessionsAlive(a, b);
  if (!aliveAfter1) {
    print(
      '[pair] friendprof_mute_toggle_regression: CRASH/desync after toggle #1 '
      '(ABI regression — both sessions must stay ready)',
    );
    return false;
  }
  final valueAfter1 = await _switchValue(a, sw);
  final flipped1 = valueAfter1 != null && valueAfter1 == !valueBefore;
  // Toggle #2 (flip back to the original value so the next case starts clean).
  if (!await a.tapKeyCenter(sw, timeoutSecs: 6)) {
    print(
      '[pair] friendprof_mute_toggle_regression: mute switch not tappable '
      '(toggle #2)',
    );
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final aliveAfter2 = await _bothSessionsAlive(a, b);
  final valueAfter2 = await _switchValue(a, sw);
  final flipped2 = valueAfter2 != null && valueAfter2 == valueBefore;
  // SOFT: the recvOpt dump value (documented native->Dart sync gap). Logged for
  // the run phase, NOT gated — a flip here is a bonus, not a requirement.
  final recvAfter = await _recvOpt(a, toxFriend);
  print(
    '[pair] friendprof_mute_toggle_regression: aliveAfter1=$aliveAfter1 '
    'aliveAfter2=$aliveAfter2 valueBefore=$valueBefore valueAfter1=$valueAfter1 '
    '(flipped1=$flipped1) valueAfter2=$valueAfter2 (flipped2=$flipped2) '
    'recvOptBefore=$recvBefore recvOptAfter=$recvAfter '
    '(recvOpt is SOFT — documented native->Dart sync residual)',
  );
  // HARD: no-crash across BOTH toggles AND the switch value actually flipped ON
  // then back OFF. The switch is restored to its original state for the next case.
  return aliveAfter1 && aliveAfter2 && flipped1 && flipped2;
}

Future<bool> _bothSessionsAlive(Inst a, Inst b) async {
  try {
    final sa = await a.dumpState();
    final sb = await b.dumpState();
    return sa['sessionReady'] == true && sb['sessionReady'] == true;
  } on DriveError {
    // A dropped VM-service connection (the app crashed) is the failure signal.
    return false;
  }
}

// ===========================================================================
// case 40 — friendprof_remark_edit_persists (S113/S30)  [needs friendship]
// ===========================================================================
/// Friend-profile remark edit. Tap the edit-remark button -> the modify-remark
/// dialog opens -> type a remark -> Confirm -> the friend's display name shows
/// the remark AND the dump reflects it. ASSERTED HARD on purpose: this routes
/// through the SDK native `setFriendInfo` (binary-replacement) path, which is
/// KNOWN BROKEN (the dialog input lands but Confirm does not persist). A LIVE
/// FAIL HERE IS THE SIGNAL to root-fix the native `dart_compat` setFriendInfo
/// path in the run phase (mirroring the mute ABI fix). Restores the original
/// remark (best-effort) so a later case isn't poisoned.
Future<bool> _friendprofRemarkEditPersists(Inst inst, String toxFriend) async {
  if (!await _ensureFriendProfileOpen(inst, toxFriend)) {
    print('[pair] friendprof_remark_edit_persists: profile did not open');
    return false;
  }
  final originalNick = await friendNick(inst, toxFriend);
  // Open the modify-remark dialog (single-fire: it's a FloatingActionButton
  // whose onPressed opens a showDialog; a double-fire could stack two dialogs).
  if (!await inst.tapKeyCenter('user_profile_edit_remark_button',
      timeoutSecs: 6)) {
    print('[pair] friendprof_remark_edit_persists: edit-remark btn not tappable');
    return false;
  }
  if (!await inst.waitKey('user_profile_modify_remark_text_field',
      timeoutSecs: 8)) {
    print('[pair] friendprof_remark_edit_persists: remark dialog did not open');
    return false;
  }
  await inst.focusType('user_profile_modify_remark_text_field', _b4RemarkText);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  // Confirm (single-fire: it pops the dialog; a double-fire would pop the page
  // underneath). The confirm calls _onChangeFriendRemark -> setFriendInfo.
  if (!await inst.tapKeyCenter('user_profile_modify_remark_confirm_button',
      timeoutSecs: 6)) {
    print('[pair] friendprof_remark_edit_persists: confirm not tappable');
    return false;
  }
  // The dialog MUST close (its confirm popped). A stuck dialog means the case
  // proves nothing — require it gone (a stuck modal would also let the UI text
  // probe below read the dialog's own field as a false "remark shows").
  final dialogClosed = await inst.waitKeyGone(
    'user_profile_modify_remark_text_field',
    timeoutSecs: 8,
  );
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  // Assert PERSISTENCE through the DUMP. The remark persists into the Prefs-backed
  // `friends[].remark` field (via the Platform-path Tim2ToxSdkPlatform.setFriendInfo
  // -> prefs.setFriendRemark), NOT into the Tox `friends[].nickName`. The original
  // harness assertion read `nickName` (which never changes for a remark edit), so
  // it always reported FAIL even though the remark DID persist — root-caused live:
  // setFriendInfo routes through the PLATFORM override (not the binary-replacement
  // DartSetFriendInfo), and toxee's display path reads the Prefs remark store. Gate
  // on `remark` (the authoritative store the contact list / search / chat header
  // render from). The transient on-screen text alone is still NOT trusted.
  final dumpRemark = await _friendRemark(inst, toxFriend);
  final persisted = dumpRemark == _b4RemarkText;
  // RESTORE the original remark (empty for the echo fixture) so case 43's search
  // and case 44 aren't poisoned. Best-effort: only when the remark actually
  // persisted (a no-op clear is harmless either way).
  if (persisted) {
    try {
      await _setFriendRemark(inst, toxFriend, _originalRemark);
    } on DriveError catch (e) {
      print('[pair] friendprof_remark_edit_persists: restore best-effort '
          'failed: ${e.message}');
    }
  }
  print(
    '[pair] friendprof_remark_edit_persists: originalNick="$originalNick" '
    'dialogClosed=$dialogClosed dumpRemark="$dumpRemark" persisted=$persisted '
    '(HARD assert on friends[].remark — the Prefs-backed alias store the UI '
    'renders from)',
  );
  return dialogClosed && persisted;
}

/// The remark to restore after case 40. The paired_for_e2e echo accounts start
/// with NO remark, so the clean restore is an empty remark (clears the alias).
const _originalRemark = '';

/// Set a friend's remark via the real modify-remark dialog (used to RESTORE the
/// original remark after case 40 — only reached once the native setFriendInfo
/// path works, since the broken path never persists in the first place).
Future<void> _setFriendRemark(Inst inst, String toxFriend, String remark) async {
  if (!await _ensureFriendProfileOpen(inst, toxFriend)) return;
  if (!await inst.tapKeyCenter('user_profile_edit_remark_button',
      timeoutSecs: 6)) {
    return;
  }
  if (!await inst.waitKey('user_profile_modify_remark_text_field',
      timeoutSecs: 6)) {
    return;
  }
  await inst.focusType('user_profile_modify_remark_text_field', remark);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKeyCenter('user_profile_modify_remark_confirm_button',
      timeoutSecs: 6);
  await inst.waitKeyGone('user_profile_modify_remark_text_field',
      timeoutSecs: 6);
}

// ===========================================================================
// case 41 — friendprof_clear_history (S111)  [needs friendship]
// ===========================================================================
/// Seed a few messages into the C2C chat via the REAL composer, then clear the
/// history via the friend-profile Clear-History button + keyed confirm. Asserts
/// the conversation's messageCount drops to 0.
Future<bool> _friendprofClearHistory(Inst inst, String toxFriend) async {
  final convId = 'c2c_${_pubkey(toxFriend)}';
  // 1) Seed real history via the composer (open the chat first).
  await openChat(inst, toxFriend);
  var seeded = 0;
  for (var i = 0; i < 3; i++) {
    final text = 'RuiB4Clear-$i-${DateTime.now().microsecondsSinceEpoch}';
    if (await sendComposerMessage(inst, text)) seeded++;
  }
  if (seeded == 0) {
    // The composer can flake under 2-proc contention (and there may be no prior
    // history). Fall back to the deterministic l3_send_text seam — the asserted
    // action is the Clear-History gesture, not the send. The contacts sweep
    // marks both accounts test up front, which l3_send_text requires.
    for (var i = 0; i < 3 && seeded == 0; i++) {
      try {
        final r = await inst.l3('l3_send_text', {
          'userId': _pubkey(toxFriend),
          'text': 'RuiB4Clear-l3$i-${DateTime.now().microsecondsSinceEpoch}',
        });
        if (r['ok'] == true) {
          seeded++;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      } on DriveError catch (_) {/* honest fail below if all attempts miss */}
    }
  }
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final beforeCount =
      ((await inst.dumpState(conversationId: convId))['messageCount'] as num?)
              ?.toInt() ??
          0;
  // The asserted action is the CLEAR (messageCount -> 0). The precondition is
  // simply "there IS history to clear" — beforeCount > 0. The fresh composer
  // seeding is best-effort setup; if the conversation already carries messages
  // (a prior case's sends) we proceed even when the fresh seed flaked
  // (seeded == 0), so a flaky composer doesn't fail a case that's really about
  // the clear button.
  if (beforeCount == 0) {
    print(
      '[pair] friendprof_clear_history: no history to clear '
      '(seeded=$seeded beforeCount=$beforeCount)',
    );
    return false;
  }
  // 2) Open the friend profile + tap Clear-History -> confirm.
  if (!await _ensureFriendProfileOpen(inst, toxFriend)) {
    print('[pair] friendprof_clear_history: profile did not open');
    return false;
  }
  // The clear-history opener is a GestureDetector; tap by key. The confirm
  // dialog button has a `handled` one-shot guard, but is on-screen + pops the
  // dialog -> single-fire it.
  if (!await inst.tryTapKey('user_profile_clear_history_button', retries: 3)) {
    print('[pair] friendprof_clear_history: clear button not tappable');
    return false;
  }
  if (!await inst.waitKey('user_profile_clear_history_confirm_button',
      timeoutSecs: 8)) {
    print('[pair] friendprof_clear_history: confirm dialog did not open');
    return false;
  }
  // macOS CupertinoDialogAction has no resolvable RenderBox center → fall back
  // to tryTapKey (fires the callback via _tryInvokeCallback); the fork's
  // `handled` one-shot guard absorbs the double-fire.
  if (!await inst.tapKeyCenter('user_profile_clear_history_confirm_button',
          timeoutSecs: 6) &&
      !await inst.tryTapKey('user_profile_clear_history_confirm_button',
          retries: 3)) {
    print('[pair] friendprof_clear_history: confirm not tappable');
    return false;
  }
  // 3) Assert the history is empty.
  final emptied = await _waitConvMessageCount(inst, convId, 0, timeoutSecs: 15);
  final afterCount =
      ((await inst.dumpState(conversationId: convId))['messageCount'] as num?)
              ?.toInt() ??
          -1;
  await ensureContactsShell(inst);
  print(
    '[pair] friendprof_clear_history: seeded=$seeded beforeCount=$beforeCount '
    'afterCount=$afterCount emptied=$emptied',
  );
  return emptied;
}

Future<bool> _waitConvMessageCount(Inst inst, String convId, int want,
    {int timeoutSecs = 15}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final c = ((await inst.dumpState(conversationId: convId))['messageCount']
            as num?)
        ?.toInt();
    if (c == want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

// ===========================================================================
// case 42 — blocked_list_unblock_row (S107)  [needs friendship]
// ===========================================================================
/// Block the friend via the profile switch, then go to the Blocked Users
/// sub-tab: the friend's row renders there; unblock via the row's unblock
/// affordance (the blocked-list item carries the same block switch / unblock
/// button) -> the row leaves the list and `blockedUsers` no longer contains the
/// peer. Ends UNBLOCKED.
Future<bool> _blockedListUnblockRow(Inst inst, String toxFriend) async {
  // 1) Block via the profile switch (reuse the profile path).
  if (!await _ensureFriendProfileOpen(inst, toxFriend)) {
    print('[pair] blocked_list_unblock_row: profile did not open');
    return false;
  }
  if (!await _isBlocked(inst, toxFriend)) {
    if (!await inst.tapKeyCenter('user_profile_block_switch', timeoutSecs: 6)) {
      print('[pair] blocked_list_unblock_row: block switch not tappable');
      return false;
    }
  }
  final blocked = await _waitBlocked(inst, toxFriend, true);
  if (!blocked) {
    print('[pair] blocked_list_unblock_row: could not block the friend');
    return false;
  }
  // 2) Navigate to the Blocked Users sub-tab.
  await ensureContactsShell(inst);
  await inst.foreground();
  if (!await inst.tryTapKey('contact_blocked_users_tab', retries: 2)) {
    await _tryTapText(inst, 'Blocked Users');
    await inst.tapAt(240, 270);
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  // 3) The friend's row is present in the blocked list. The blocked-list row
  // opens the SAME user profile; unblock via the profile block switch (the
  // deterministic, key-stable affordance). Tap the row, flip block OFF.
  final shortKey = _contactItemShortKey(toxFriend);
  final fullKey = _contactItemFullKey(toxFriend);
  final rowPresent = await inst.waitKey(shortKey, timeoutSecs: 6) ||
      await inst.waitKey(fullKey, timeoutSecs: 4);
  if (rowPresent) {
    // Tap the blocked-list row to open the same user profile (try both key
    // forms; the second is only attempted if the first didn't land).
    if (!await inst.tryTapKey(shortKey, retries: 2)) {
      await inst.tryTapKey(fullKey, retries: 2);
    }
  }
  // Either we reached the profile (preferred) or fall back to opening the
  // profile through the contact list.
  if (!await _onFriendProfile(inst, timeoutSecs: 4)) {
    await _ensureFriendProfileOpen(inst, toxFriend);
  }
  if (await _isBlocked(inst, toxFriend)) {
    if (!await inst.tapKeyCenter('user_profile_block_switch', timeoutSecs: 6)) {
      print('[pair] blocked_list_unblock_row: unblock switch not tappable');
      return false;
    }
  }
  final unblocked = await _waitBlocked(inst, toxFriend, false);
  // 4) Re-check the Blocked Users list: the row is gone. The block-list panel
  // does not always live-refresh when the unblock happens off-panel, so FORCE a
  // fresh load by navigating New Contacts -> Blocked Users (keyed sub-tabs) the
  // same way _refreshApplicationList does — a single Blocked-Users tap can show
  // the stale cached list.
  await ensureContactsShell(inst);
  await inst.foreground();
  if (!await inst.tryTapKey('contact_new_contacts_tab', retries: 2)) {
    await inst.tapAt(240, 173);
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  if (!await inst.tryTapKey('contact_blocked_users_tab', retries: 2)) {
    await _tryTapText(inst, 'Blocked Users');
    await inst.tapAt(240, 270);
  }
  await Future<void>.delayed(const Duration(milliseconds: 1400));
  final rowGone = await inst.waitKeyGone(shortKey, timeoutSecs: 6) &&
      await inst.waitKeyGone(fullKey, timeoutSecs: 2);
  await ensureContactsShell(inst);
  print(
    '[pair] blocked_list_unblock_row: blocked=$blocked rowPresent=$rowPresent '
    'unblocked=$unblocked rowGone=$rowGone',
  );
  return blocked && rowPresent && unblocked && rowGone;
}

// ===========================================================================
// case 43 — contact_search_filter_clear (S49)  [needs friendship]
// ===========================================================================
/// In the contact list, type a filter into the search field (contact_search_field)
/// that matches the friend -> the friend's row stays; type a non-matching filter
/// -> the row is filtered out; clear -> the full list returns (row back).
Future<bool> _contactSearchFilterClear(
  Inst inst,
  String toxFriend,
  String friendNickName,
) async {
  await ensureContactsShell(inst);
  await inst.foreground();
  final shortKey = _contactItemShortKey(toxFriend);
  final fullKey = _contactItemFullKey(toxFriend);
  // The friend row is present before filtering.
  final rowBefore = await inst.waitKey(shortKey, timeoutSecs: 6) ||
      await inst.waitKey(fullKey, timeoutSecs: 2);
  if (!await inst.waitKey('contact_search_field', timeoutSecs: 6)) {
    print('[pair] contact_search_filter_clear: search field not present');
    return false;
  }
  // 1) Matching filter (a prefix of the friend's nickname; fall back to the
  // first hex chars of the tox id, which contactMatchesQuery also matches).
  final matchQuery = (friendNickName.trim().isNotEmpty)
      ? friendNickName.trim().substring(
          0, friendNickName.trim().length >= 3 ? 3 : friendNickName.trim().length)
      : _pubkey(toxFriend).substring(0, 6);
  await inst.focusType('contact_search_field', matchQuery);
  await Future<void>.delayed(const Duration(milliseconds: 1000));
  final rowMatchesFilter = await inst.waitKey(shortKey, timeoutSecs: 4) ||
      await inst.waitKey(fullKey, timeoutSecs: 2);
  // 2) Non-matching filter -> the row is filtered OUT. Type via focusType
  // (osascript keystrokes), NOT raw synthetic enterText — the latter drives the
  // macOS engine's -[FlutterTextInputPlugin setEditingState:], which SIGSEGVs
  // the whole app (root-caused live: A crashed here mid-sweep, killing this case
  // and case 44). focusType clears + types crash-free.
  await inst.focusType('contact_search_field', 'zzzznomatchzzzz');
  await Future<void>.delayed(const Duration(milliseconds: 1000));
  final rowFilteredOut = await inst.waitKeyGone(shortKey, timeoutSecs: 4) &&
      await inst.waitKeyGone(fullKey, timeoutSecs: 2);
  // 3) Clear -> the full list returns.
  await inst.tapKey('contact_search_field');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort
  }
  await Future<void>.delayed(const Duration(milliseconds: 1000));
  final rowBack = await inst.waitKey(shortKey, timeoutSecs: 6) ||
      await inst.waitKey(fullKey, timeoutSecs: 2);
  print(
    '[pair] contact_search_filter_clear: rowBefore=$rowBefore '
    'rowMatchesFilter=$rowMatchesFilter rowFilteredOut=$rowFilteredOut '
    'rowBack=$rowBack (matchQuery="$matchQuery")',
  );
  return rowBefore && rowMatchesFilter && rowFilteredOut && rowBack;
}

// ===========================================================================
// case 44 — friendprof_delete_friend_confirm (S112/S28)  [needs friendship]
// ===========================================================================
/// Delete the friend via the profile Delete button -> the KEYED confirm dialog
/// -> the friend is gone from BOTH sides' friend lists (the sweep ENDS
/// no-friend). The confirm dialog button is keyed
/// (`user_profile_delete_friend_confirm_button`) with a `handled` one-shot guard
/// (the doc's "confirm key not found" note was STALE). Runs LAST.
Future<bool> _friendprofDeleteFriendConfirm(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  if (!await _ensureFriendProfileOpen(a, toxB)) {
    print('[pair] friendprof_delete_friend_confirm: profile did not open');
    return false;
  }
  // Open the delete-confirm dialog (the opener is a GestureDetector; tap key).
  if (!await a.tryTapKey('user_profile_delete_friend_button', retries: 3)) {
    print('[pair] friendprof_delete_friend_confirm: delete btn not tappable');
    return false;
  }
  if (!await a.waitKey('user_profile_delete_friend_confirm_button',
      timeoutSecs: 8)) {
    print('[pair] friendprof_delete_friend_confirm: confirm dialog did not open');
    return false;
  }
  // Tap the keyed confirm. On macOS this is a CupertinoDialogAction whose
  // RenderBox center isn't resolvable via interactiveStructured (tapKeyCenter
  // returns false), so fall back to tryTapKey (flutter_skill `tap` fires the
  // callback via _tryInvokeCallback even without bounds). The fork's `handled`
  // one-shot guard absorbs the double-fire safely (it pops + deletes once).
  if (!await a.tapKeyCenter('user_profile_delete_friend_confirm_button',
          timeoutSecs: 6) &&
      !await a.tryTapKey('user_profile_delete_friend_confirm_button',
          retries: 3)) {
    print('[pair] friendprof_delete_friend_confirm: confirm not tappable');
    return false;
  }
  // Assert the friendship is gone on A; mirror-delete on B if needed so BOTH
  // sides end no-friend (the registered result state).
  var clearedBoth = await waitFriendshipState(
    a,
    b,
    toxA,
    toxB,
    friends: false,
    timeoutSecs: 15,
  );
  if (!clearedBoth && await areFriends(b, toxA)) {
    // A's delete should remove the link both ways; if B still sees A, delete on
    // B via the real profile UI too.
    await deleteFriendViaProfile(b, toxA);
    clearedBoth = await waitFriendshipState(
      a,
      b,
      toxA,
      toxB,
      friends: false,
      timeoutSecs: 15,
    );
  }
  final aHasB = await areFriends(a, toxB);
  final bHasA = await areFriends(b, toxA);
  // Land both back on a clean Chats home for any follow-on campaign step.
  try {
    await returnToChatsHome(a);
    await returnToChatsHome(b);
  } on DriveError catch (e) {
    print('[pair] friendprof_delete_friend_confirm: home recovery warn: '
        '${e.message}');
  }
  print(
    '[pair] friendprof_delete_friend_confirm: clearedBoth=$clearedBoth '
    'aHasB=$aHasB bHasA=$bHasA',
  );
  return clearedBoth && !aHasB && !bHasA;
}

/// True if [tox] is still a PENDING friend application on [inst] (not yet
/// accepted/declined). Used by the handshake's accept-retry to avoid re-driving
/// a consumed application (which would make driveRespondToApplication hang).
Future<bool> _hasPendingApplication(Inst inst, String tox) async {
  final s = await inst.dumpState();
  final apps = (s['friendApplications'] as List?) ?? const [];
  return apps.any((e) =>
      e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(tox));
}

/// Wire a full-mesh LOOPBACK bootstrap between the paired instances so same-host
/// peers can actually find each other (the public DHT never converges two
/// instances on one host). The `l3_dht_info` / `l3_add_bootstrap_node` tools are
/// test-account-gated, so this MARKS both accounts test, wires the bootstrap,
/// then REVOKES the marker — the bootstrap node is a one-shot Tox call whose
/// connection survives un-marking, so the sweep body sees the original (non-test)
/// privilege state. Tolerant: a missing endpoint / failed mark is logged, not
/// thrown (the downstream handshake assertion is the authoritative gate).
Future<void> _wireSweepLoopbackBootstrap(Inst a, Inst b) async {
  var markedA = false;
  var markedB = false;
  try {
    markedA = await a.markAccountTest();
    markedB = await b.markAccountTest();
    if (!markedA || !markedB) {
      print('[sweep] loopback-bootstrap: WARN could not test-mark both accounts '
          '(A=$markedA B=$markedB) — same-host handshake may not converge');
      return;
    }
    for (final ext in fixtureCBootstrapExtensions) {
      await a.waitExt(ext);
      await b.waitExt(ext);
    }
    await wireFullMeshBootstrap([
      BootstrapTarget('A', a.vm, a.iso),
      BootstrapTarget('B', b.vm, b.iso),
    ],
        log: (m) => print('[sweep] $m'),
        // Same-host DHTs need more than the default 6s to actually CONNECT
        // before a friend request routes between them (the addBootstrapNode
        // call returns immediately; the DHT handshake follows). The send loop in
        // _establishFriendshipForSweep re-submits if it's still not enough.
        settle: const Duration(seconds: 12));
  } on DriveError catch (e) {
    print('[sweep] loopback-bootstrap: best-effort failed: ${e.message}');
  } finally {
    // Revoke the marker so the sweep body keeps the original non-test privilege
    // state — the bootstrap connection persists (it is Tox-network state, not the
    // Prefs seed marker).
    if (markedA) await a.unmarkAccountTest();
    if (markedB) await b.unmarkAccountTest();
  }
}

// ===========================================================================
// Handshake helper for the sweep (establish A<->B friendship via REAL UI).
// ===========================================================================
/// B sends an add-friend request to A; A accepts via the inline New-Contacts
/// row button. Asserts friendship + name propagation both directions. Reuses
/// driveAddFriend + driveRespondToApplication. Returns whether the pair is
/// friends both ways.
Future<bool> _establishFriendshipForSweep(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
  String nickA,
  String nickB,
) async {
  if (await areFriends(a, toxB) && await areFriends(b, toxA)) {
    print('[sweep] contacts: pair already friends — skip handshake');
    return true;
  }
  await a.waitState((s) => s['isConnected'] == true,
      label: 'A connected', timeoutSecs: 90);
  await b.waitState((s) => s['isConnected'] == true,
      label: 'B connected', timeoutSecs: 90);
  // Same-host toxee instances bootstrap to the PUBLIC DHT but never to EACH
  // OTHER (root-caused live: A never receives B's friend request within the
  // window, so the handshake times out). Wire a full-mesh LOOPBACK bootstrap
  // (the same fix the group drivers use) so the C2C friend request actually
  // delivers same-host. This is connectivity SEEDING — the asserted action stays
  // the real add-friend UI; the marker is granted only to call the gated
  // bootstrap tools and is REVOKED immediately, so the sweep body's privilege
  // state is unchanged.
  await _wireSweepLoopbackBootstrap(a, b);
  // The loopback bootstrap call returns immediately but the two DHTs need time
  // to actually CONNECT before a friend request can route between them. Send
  // B's add-friend request, then wait for A to RECEIVE the application; if it
  // doesn't arrive in time, RE-SUBMIT (same-host delivery is non-deterministic
  // even with the bootstrap — the request can be dropped before the local DHT
  // converges). Re-submitting via the real UI keeps the asserted action real.
  var appArrived = false;
  for (var sendAttempt = 0; sendAttempt < 3 && !appArrived; sendAttempt++) {
    if (sendAttempt > 0) {
      print('[sweep] contacts: A has not received B\'s request yet — '
          're-submitting the real-UI add-friend (attempt ${sendAttempt + 1}/3)');
    }
    if (await _hasPendingApplication(a, toxB) || await areFriends(a, toxB)) {
      appArrived = true;
      break;
    }
    await driveAddFriend(b, toxA,
        message: _defaultFriendRequestWording('contacts'));
    appArrived = await _retryBool(
        () async =>
            await _hasPendingApplication(a, toxB) || await areFriends(a, toxB),
        label: 'A received B request (send attempt ${sendAttempt + 1})',
        attempts: 40);
  }
  if (!appArrived) {
    print('[sweep] contacts: B request never reached A after 3 sends — '
        'same-host DHT did not converge');
    return false;
  }
  // Accept on A's REAL UI, then VERIFY the accept took (the friendship forms on
  // A's side). A real-UI Accept tap can race the application-list refresh and
  // miss; re-drive the keyed Accept up to 3x until A actually has B. The accept
  // is the asserted real-UI action each time (the keyed
  // contact_application_accept_button), not an l3 bypass.
  var aHasB = await areFriends(a, toxB);
  for (var attempt = 0; attempt < 3 && !aHasB; attempt++) {
    if (attempt > 0) {
      print('[sweep] contacts: A accept did not take yet — re-driving '
          'real-UI Accept (attempt ${attempt + 1}/3)');
      // Only re-drive if the application is still pending (a consumed
      // application without a friendship would make driveRespondToApplication's
      // waitState hang). If it's gone but no friendship formed, bail out of the
      // retry — the friendship-poll below is the authoritative gate.
      final stillPending = await _hasPendingApplication(a, toxB);
      if (!stillPending) break;
    }
    await driveRespondToApplication(a, toxB, accept: true);
    aHasB = await _retryBool(() => areFriends(a, toxB),
        label: 'A has B (sweep handshake, attempt ${attempt + 1})',
        attempts: 20);
  }
  final bHasA = await _retryBool(() => areFriends(b, toxA),
      label: 'B has A (sweep handshake)', attempts: 60);
  print('[sweep] contacts: handshake aHasB=$aHasB bHasA=$bHasA');
  return aHasB && bHasA;
}

/// sweep_contacts — Batch 4: chain all 15 contacts/friend-profile cases on ONE
/// two-process launch.
///
/// Order (state-poison-aware): 30/31/32 (add-friend dialog guards, no friendship)
/// -> handshake once -> 33 duplicate-guard -> 34 subtabs -> 35 row-opens-profile
/// -> 36 send-message-tile -> 37 pin -> 38 block/unblock -> 39 mute regression
/// -> 40 remark (expected-FAIL hard) -> 41 clear-history -> 42 block-list-unblock
/// -> 43 search filter -> 44 DELETE friend (LAST; ends no-friend BOTH sides).
///
/// Prints `[sweep] <case>: PASS|FAIL` per case + final counts; exits non-zero if
/// any HARD case fails (all 15 are hard). 40 is a HARD gate that is EXPECTED to
/// FAIL live until the native setFriendInfo path is fixed (see its docs).
Future<int> runContactsSweep(Inst a, Inst b, String nickA, String nickB) async {
  // Fresh pair: register BOTH (no friendship). The add-friend dialog opens on
  // either tab via the L3 invoker, so requireHomeMenu can stay default for A.
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[sweep] sweep_contacts: missing tox ids (A=$toxA B=$toxB)');
    return 1;
  }
  print(
    '[sweep] sweep_contacts: A=${_shortId(toxA)} ($nickA) '
    'B=${_shortId(toxB)} ($nickB)',
  );

  var passed = 0;
  var failed = 0;
  // Whether the launch ends in the registered NO-FRIEND state. Default false so
  // an early/exceptional abort before the end-guard runs is treated as DIRTY
  // (the runner must NOT trust a no-friend result that was never achieved).
  var endNoFriend = false;
  final results = <String, String>{};
  // Mark both accounts test so the friend-profile cases' L3 helpers work:
  // friendprof_clear_history's l3_send_text seed fallback + the
  // clearActiveConversation recovery are test-gated, and without the mark
  // friendprof_clear failed ("no history") and cascaded into the next two cases
  // ("failed to recover to Contacts shell"). Set after the friendship below;
  // revoked in the end-guard. Tracked per side for independent unmark.
  var aMarked = false;
  var bMarked = false;

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

  try {
    // --- 30/31/32: add-friend dialog guards (BEFORE the handshake; A-side). ---
    await hard('add_friend_dialog_esc_close', () => _addFriendDialogEscClose(a));
    await hard('add_friend_invalid_id_error', () => _addFriendInvalidIdError(a));
    await hard('add_friend_self_id_guard', () => _addFriendSelfIdGuard(a, toxA));

    // --- Establish the A<->B friendship (real UI handshake) once. ---
    final friended =
        await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB);
    if (!friended) {
      print(
        '[sweep] sweep_contacts: handshake FAILED — cases 33–44 cannot run; '
        'marking them failed',
      );
      for (final id in const [
        'add_friend_duplicate_guard',
        'contacts_subtabs_cycle',
        'contacts_row_opens_friend_profile',
        'friendprof_send_message_tile',
        'friendprof_pin_toggle',
        'friendprof_block_unblock',
        'friendprof_mute_toggle_regression',
        'friendprof_remark_edit_persists',
        'friendprof_clear_history',
        'blocked_list_unblock_row',
        'contact_search_filter_clear',
        'friendprof_delete_friend_confirm',
      ]) {
        failed++;
        results[id] = 'FAIL';
      }
    } else {
      aMarked = await a.markAccountTest();
      bMarked = await b.markAccountTest();
      // --- 33: duplicate-guard (B re-adds A). ---
      await hard(
          'add_friend_duplicate_guard', () => _addFriendDuplicateGuard(b, toxA));
      // --- 34: contacts subtabs cycle (A-side). ---
      await hard('contacts_subtabs_cycle', () => _contactsSubtabsCycle(a));
      // --- 35: contact row opens friend profile (A views B). ---
      await hard('contacts_row_opens_friend_profile',
          () => _contactsRowOpensFriendProfile(a, toxB));
      // --- 36: friend-profile Send Message tile -> chat. ---
      await hard('friendprof_send_message_tile',
          () => _friendprofSendMessageTile(a, toxB));
      // --- 37: pin toggle (restore unpinned). ---
      await hard('friendprof_pin_toggle', () => _friendprofPinToggle(a, toxB));
      // --- 38: block/unblock. ---
      await hard(
          'friendprof_block_unblock', () => _friendprofBlockUnblock(a, toxB));
      // --- 39: mute regression gate (no-crash + flip; recvOpt soft). ---
      await hard('friendprof_mute_toggle_regression',
          () => _friendprofMuteToggleRegression(a, b, toxB));
      // --- 40: remark edit persists (HARD; expected FAIL live — see docs). ---
      await hard('friendprof_remark_edit_persists',
          () => _friendprofRemarkEditPersists(a, toxB));
      // --- 41: clear history (seed via composer, clear via profile). ---
      await hard(
          'friendprof_clear_history', () => _friendprofClearHistory(a, toxB));
      // --- 42: block via profile -> Blocked Users tab row -> unblock -> gone. ---
      await hard(
          'blocked_list_unblock_row', () => _blockedListUnblockRow(a, toxB));
      // --- 43: contact search filter/clear. ---
      await hard('contact_search_filter_clear',
          () => _contactSearchFilterClear(a, toxB, nickB));
      // --- 44: delete friend (LAST; ends no-friend BOTH sides). ---
      await hard('friendprof_delete_friend_confirm',
          () => _friendprofDeleteFriendConfirm(a, b, toxA, toxB));
    }
  } finally {
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
    // END-STATE GUARD: the registered result is no-friend. If case 44 didn't run
    // or didn't fully clear (a mid-sweep failure), tear down the friendship via
    // the shared reset utility so the launch ends in the documented state. The
    // reset's success is VERIFIED (not assumed): a logged-only failure here
    // would let the runner trust a no-friend result that was never achieved
    // (codex P1), so `endNoFriend` is recomputed from the actual friendship
    // state after the reset attempt and gates the return below.
    try {
      if (await areFriends(a, toxB) || await areFriends(b, toxA)) {
        print('[sweep] contacts end-clean: friendship still present -> reset');
        await runResetFriendship(a, b, nickA, nickB);
      }
      endNoFriend = await waitFriendshipState(
        a,
        b,
        toxA,
        toxB,
        friends: false,
        timeoutSecs: 15,
      );
    } on PermissionBlockedError catch (e) {
      print('[sweep] contacts end-clean: BLOCKED (${e.message})');
    } on DriveError catch (e) {
      print('[sweep] contacts end-clean: reset best-effort failed: ${e.message}');
    }
    print(
      '[sweep] sweep_contacts RESULTS: $passed PASS / $failed FAIL '
      '($results) | endNoFriend=$endNoFriend',
    );
    try {
      await a.shot('/tmp/ui_contacts_sweep_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_contacts_sweep_B.png');
    } on DriveError {
      // best-effort
    }
  }
  // FAIL if any case failed OR the launch did not reach the registered
  // NO-FRIEND end state (so the runner never trusts a dirty result).
  if (!endNoFriend) {
    print(
      '[sweep] sweep_contacts: end state is NOT no-friend — failing the sweep '
      'so the runner does not trust the result-state contract',
    );
  }
  return (failed == 0 && endNoFriend) ? 0 : 1;
}
