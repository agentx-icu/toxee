// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

/// B drives the add-friend dialog targeting A's tox id (real UI).
Future<void> driveAddFriend(Inst b, String toxA, {String? message}) async {
  // The new_entry_menu_button (NewEntryButton) is not rendered on the Windows
  // desktop wide layout, so ensureNewEntryShell (which requires it) can't be
  // satisfied. The dialog-open path below already falls back to the
  // layout-independent openAddFriendDialogViaL3, so skip the shell-ensure on
  // Windows and let that seam open the real AddFriendDialog directly.
  if (!_isWindowsRealUi) {
    await ensureNewEntryShell(b);
  }
  var dialogReady = false;
  // The keyed NewEntry menu (new_entry_menu_button) lives in the CONTACTS app
  // bar. On a fresh non-test account B usually sits on the Chats home and can't
  // flip tabs via l3_force_home_root (refused). Open the real AddFriendDialog
  // straight through the tab-independent, non-blocking L3 invoker instead of
  // blind coordinate taps on the wrong tab (which can stray-open a conversation
  // and leave B in a non-reusable shell). Confirm via the dialog's input field.
  if ((_isWindowsRealUi || await _homeShellTab(b) != 'contacts') &&
      await b.openAddFriendDialogViaL3()) {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (await b.waitKey('add_friend_id_input', timeoutSecs: 3)) {
      dialogReady = true;
    }
  }
  for (var attempt = 0; attempt < 3 && !dialogReady; attempt++) {
    if (!await b.tryTapKey('new_entry_menu_button', retries: 2) &&
        !await b.tryTapKey('contact_app_bar_menu_button', retries: 2)) {
      if (!await _tryTapText(b, 'New Chat')) {
        await b.tapAt(1236, 34);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!await b.tryTapKey('new_entry_add_contact_item', retries: 2) &&
        !await b.tryTapKey('contact_app_bar_add_contact_item', retries: 2) &&
        !await _tryTapText(b, 'Add Contact')) {
      // Fixed desktop fallback: both toxee's NewEntryButton menu and UIKit's
      // default contacts app-bar menu anchor in the top-right corner and place
      // "Add Contact" as the first row directly below the trigger.
      await b.tapAt(1156, 88);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (!await b.waitKey('add_friend_id_input', timeoutSecs: 1)) {
      await b.openAddFriendDialogViaL3();
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (await b.waitKey('add_friend_id_input', timeoutSecs: 3)) {
      dialogReady = true;
      break;
    }
  }
  if (!dialogReady) {
    final hasNewEntryButton = await b.waitKey(
      'new_entry_menu_button',
      timeoutSecs: 1,
    );
    final hasContactAppBarMenu = await b.waitKey(
      'contact_app_bar_menu_button',
      timeoutSecs: 1,
    );
    final hasTrailingOverride = await b.waitKey(
      'contact_app_bar_trailing_override',
      timeoutSecs: 1,
    );
    final shotPath = _portableTmp('/tmp/add_friend_dialog_${b.name}.png');
    await b.shot(shotPath);
    throw DriveError(
      '[${b.name}] add-friend dialog did not open '
      '(newEntryButton=$hasNewEntryButton '
      'contactAppBarMenu=$hasContactAppBarMenu '
      'trailingOverride=$hasTrailingOverride '
      'shot=$shotPath)',
    );
  }
  await b.focusType('add_friend_id_input', toxA);
  if (message != null && message.isNotEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await b.focusType('add_friend_message_input', message);
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await b.tapKey('add_friend_submit_button');
  print('[${b.name}] add-friend submitted toward ${toxA.substring(0, 16)}...');
}

String _pubkey(String id) {
  final u = id.trim().toUpperCase();
  return u.length >= 64 ? u.substring(0, 64) : u;
}

/// A navigates Contacts -> New Contacts and accepts (or declines) B via the
/// real keyed buttons.
Future<void> driveRespondToApplication(
  Inst a,
  String toxB, {
  required bool accept,
}) async {
  await ensureContactsShell(a);
  await a.foreground();
  // NOTE: UiKeys.contactNewContactsTab ('contact_new_contacts_tab') does NOT
  // match the navigable row in this UIKit build (key sits on a non-tappable
  // wrapper). tapText('New Contacts') matches the PAGE TITLE (top-left), not the
  // master-list ROW, so the right-hand "New Application" detail never loads and
  // Accept/Decline never render. Tap the master-list row by coordinates
  // (1280x768 window: the first row under the Contacts sub-tab) to open the
  // application list. Finding to fix in the fork: give the row a tappable key.
  if (!await a.tryTapKey('contact_new_contacts_tab')) {
    await _tryTapText(a, 'New Contacts');
    await a.tapAt(240, 173);
  }
  // Wait for B's application to arrive in the model.
  final st = await a.waitState(
    (s) {
      final apps = (s['friendApplications'] as List?) ?? const [];
      return apps.any(
        (e) =>
            e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
      );
    },
    timeoutSecs: 120,
    label: 'friendApplication from B',
  );
  final apps = (st['friendApplications'] as List).cast<dynamic>();
  final app =
      apps.firstWhere(
            (e) =>
                e is Map &&
                _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
          )
          as Map;
  final userId = app['userId'].toString();
  print(
    '[${a.name}] application present (userId=${userId.substring(0, 16)}...)',
  );
  await _refreshApplicationList(a, userId, detail: false);
  final keyBase = accept
      ? 'contact_application_accept_button'
      : 'contact_application_decline_button';
  var tapped = await a.tryTapKey('$keyBase:$userId', retries: 2);
  if (!tapped) {
    tapped = await _tapApplicationActionByCoordinate(
      a,
      userId: userId,
      otherTox: toxB,
      accept: accept,
    );
  }
  if (!tapped && accept) {
    tapped = await _tapApplicationAcceptViaDetail(a, userId, toxB);
  }
  // Prefer the keyed control; fall back to the visible Accept/Decline label.
  if (!tapped) {
    await a.tapText(accept ? 'Accept' : 'Decline');
  }
  print('[${a.name}] tapped ${accept ? "ACCEPT" : "DECLINE"} on real UI');
}

/// S108: A opens B's application DETAIL screen (not the inline row button) and
/// accepts there. The row's GestureDetector.onTap calls `gotoApplicationInfoPage`
/// which Navigator.push-es `TencentCloudChatContactApplicationInfo`; its accept
/// control is `contact_application_detail_accept_button:<userId>`. The detail
/// accept does NOT pop the route (just safeSetState), so the flutter_skill
/// double-fire is harmless here.
Future<void> driveRespondViaDetail(Inst a, String toxB) async {
  await ensureContactsShell(a);
  await a.foreground();
  if (!await a.tryTapKey('contact_new_contacts_tab')) {
    await _tryTapText(a, 'New Contacts');
    await a.tapAt(240, 173);
  }
  // Wait for B's application to arrive in the model.
  final st = await a.waitState(
    (s) {
      final apps = (s['friendApplications'] as List?) ?? const [];
      return apps.any(
        (e) =>
            e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
      );
    },
    timeoutSecs: 120,
    label: 'friendApplication from B',
  );
  final apps = (st['friendApplications'] as List).cast<dynamic>();
  final app =
      apps.firstWhere(
            (e) =>
                e is Map &&
                _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
          )
          as Map;
  final userId = app['userId'].toString();
  print(
    '[${a.name}] application present (userId=${userId.substring(0, 16)}...)',
  );
  await _refreshApplicationList(a, userId, detail: true);
  // OPEN the detail screen by tapping the application ROW (the left text area —
  // the inline Accept/Decline buttons sit at the far right ~x:1148). The row's
  // `contact_application_item:<userId>` KeyedSubtree wraps a GestureDetector that
  // key/text-tap can't land, so tap by coordinates: first row at y~208 in the
  // 1280x768 window. The row.onTap → gotoApplicationInfoPage pushes the detail.
  await a.tapAt(700, 208);
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  final onDetail = await a.waitKey(
    'contact_application_detail_accept_button:$userId',
    timeoutSecs: 10,
  );
  if (!onDetail) {
    if (await areFriends(a, toxB)) {
      print(
        '[${a.name}] detail screen already transitioned to accepted state '
        'for ${userId.substring(0, 16)}...',
      );
      return;
    }
    throw DriveError(
      '[${a.name}] detail screen accept button not found for $userId',
    );
  }
  print('[${a.name}] detail screen open; tapping DETAIL accept');
  await a.tapKey('contact_application_detail_accept_button:$userId');
  print('[${a.name}] tapped DETAIL ACCEPT on real UI');
}

Future<void> _refreshApplicationList(
  Inst a,
  String userId, {
  required bool detail,
}) async {
  await a.foreground();
  final probeKey = detail
      ? 'contact_application_item:$userId'
      : 'contact_application_accept_button:$userId';
  for (var attempt = 0; attempt < 3; attempt++) {
    // The New Contacts detail panel does not live-refresh reliably when the
    // inbound request lands while it is already open. Force a fresh load by
    // navigating away and back. Drive the KEYED sub-tab rows
    // (contact_blocked_users_tab / contact_new_contacts_tab) — a coordinate tap
    // on the master row MISSES the tappable InkWell in this window layout, so
    // the right-hand detail pane never loads and the keyed Accept button never
    // mounts (root-caused live: the asymmetric handshake where A keeps the
    // application pending). The keyed tap fires the InkWell's onTap via
    // flutter_skill's `_tryInvokeCallback`. Coordinate taps remain as a fallback.
    if (!await a.tryTapKey('contact_blocked_users_tab', retries: 2)) {
      await a.tapAt(240, 270); // Blocked Users master row (fallback)
    }
    await Future<void>.delayed(Duration(milliseconds: detail ? 1200 : 700));
    if (!await a.tryTapKey('contact_new_contacts_tab', retries: 2)) {
      await a.tapAt(240, 173); // New Contacts master row (fallback)
    }
    await Future<void>.delayed(Duration(milliseconds: detail ? 1800 : 1200));
    if (await a.waitKey(probeKey, timeoutSecs: 4)) return;
  }
}

Future<bool> _tapApplicationActionByCoordinate(
  Inst a, {
  required String userId,
  required String otherTox,
  required bool accept,
}) async {
  await a.foreground();
  // First application row action buttons in the 1280x768 desktop layout. The
  // Feishu restyle shifted row geometry, so try a small horizontal band and
  // only report success if the action's model-side effect is observable. A raw
  // coordinate tap itself always returns success, which used to false-positive
  // while leaving the application pending.
  final xs = accept
      ? const <num>[1008, 1048, 1088, 1128]
      : const <num>[1128, 1170, 1210];
  for (final x in xs) {
    await a.tapAt(x, 208);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final state = await a.dumpState();
    final apps = (state['friendApplications'] as List?) ?? const [];
    final appGone = !apps.any(
      (e) => e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(userId),
    );
    if (accept) {
      if (await areFriends(a, otherTox)) return true;
    } else if (appGone) {
      return true;
    }
  }
  return false;
}

Future<bool> _tapApplicationAcceptViaDetail(
  Inst a,
  String userId,
  String otherTox,
) async {
  await a.foreground();
  if (!await a.tryTapKey('contact_application_item:$userId', retries: 2)) {
    await a.tapAt(700, 208);
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  final detailKey = 'contact_application_detail_accept_button:$userId';
  if (await a.waitKey(detailKey, timeoutSecs: 8)) {
    if (!await a.tapKeyCenter(detailKey, timeoutSecs: 6)) {
      await a.tapKey(detailKey);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return areFriends(a, otherTox);
  }
  return false;
}

Future<bool> areFriends(Inst x, String otherTox) async {
  final s = await x.dumpState();
  final friends = (s['friends'] as List?) ?? const [];
  return friends.any(
    (f) =>
        f is Map && _pubkey(f['userId']?.toString() ?? '') == _pubkey(otherTox),
  );
}

Future<String> friendNick(Inst x, String otherTox) async {
  final s = await x.dumpState();
  for (final f in (s['friends'] as List? ?? const [])) {
    if (f is Map &&
        _pubkey(f['userId']?.toString() ?? '') == _pubkey(otherTox)) {
      return f['nickName']?.toString() ?? '';
    }
  }
  return '';
}

String _normalizeNick(String value) => value.trim();

String _shortId(String id) => id.length <= 16 ? id : id.substring(0, 16);

String _defaultFriendRequestWording(String scenario) =>
    'RUI-$scenario-${DateTime.now().microsecondsSinceEpoch}';

Future<void> openFriendProfile(Inst inst, String otherTox) async {
  await inst.foreground();
  await ensureContactsShell(inst);
  final fullId = otherTox.trim();
  final shortId = _pubkey(otherTox);
  final fullKey = 'contact_list_item:$fullId';
  final shortKey = 'contact_list_item:$shortId';
  for (var attempt = 0; attempt < 3; attempt++) {
    final tapped =
        await inst.tryTapKey(fullKey, retries: 2) ||
        await inst.tryTapKey(shortKey, retries: 2);
    if (!tapped) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      continue;
    }
    final onProfile =
        await inst.waitKey('user_profile_friend_name_text', timeoutSecs: 6) ||
        await inst.waitKey(
          'friend_profile_send_message_button',
          timeoutSecs: 6,
        ) ||
        await inst.waitKey('user_profile_delete_friend_button', timeoutSecs: 6);
    if (!onProfile) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await inst.waitKey(
      'user_profile_delete_friend_button',
      timeoutSecs: 10,
    )) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
  throw DriveError(
    '[${inst.name}] friend profile did not render delete button for '
    '${_shortId(shortId)}...',
  );
}

Future<bool> deleteFriendViaProfile(Inst inst, String otherTox) async {
  if (!await areFriends(inst, otherTox)) return false;
  try {
    await openFriendProfile(inst, otherTox);
    // OPEN the delete-confirm dialog (the opener is a GestureDetector).
    if (!await inst.tryTapKey('user_profile_delete_friend_button')) {
      await inst.tapText('Delete');
    }
    // CONFIRM the deletion. The opener only SHOWS the confirm dialog; the actual
    // deleteFromFriendList fires from the confirm button, which is keyed
    // (user_profile_delete_friend_confirm_button, with a `handled` one-shot
    // guard). Earlier versions of this helper stopped at the opener and left the
    // dialog up (friendship intact) — single-fire the keyed confirm so the
    // delete actually dispatches. Fall back to the "Confirm" label only if the
    // keyed button can't be found.
    if (await inst.waitKey(
      'user_profile_delete_friend_confirm_button',
      timeoutSecs: 6,
    )) {
      if (!await inst.tapKeyCenter(
        'user_profile_delete_friend_confirm_button',
        timeoutSecs: 6,
      )) {
        await inst.tapText('Confirm');
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return true;
  } on DriveError catch (e) {
    print(
      '[${inst.name}] WARN deleteFriendViaProfile falling back to L3 delete: '
      '${e.message}',
    );
    if (await inst.deleteFriendViaL3(otherTox)) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      return true;
    }
    rethrow;
  }
}

Future<bool> waitFriendshipState(
  Inst a,
  Inst b,
  String toxA,
  String toxB, {
  required bool friends,
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final aHasB = await areFriends(a, toxB);
    final bHasA = await areFriends(b, toxA);
    if (friends) {
      if (aHasB && bHasA) return true;
    } else if (!aHasB && !bHasA) {
      return true;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

Future<int> runResetFriendship(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final stateA = await a.dumpState();
  final stateB = await b.dumpState();
  if (stateA['sessionReady'] != true) {
    await ensureHome(a, nickA);
  }
  if (stateB['sessionReady'] != true) {
    await ensureHome(b, nickB);
  }
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for reset: A=$toxA B=$toxB');
  }
  final aHasB = await areFriends(a, toxB);
  final bHasA = await areFriends(b, toxA);
  if (!aHasB && !bHasA) {
    print('[pair] reset_friendship no-op: pair already not friends');
    return 0;
  }
  if (aHasB) {
    await deleteFriendViaProfile(a, toxB);
  }
  if (!await waitFriendshipState(
        a,
        b,
        toxA,
        toxB,
        friends: false,
        timeoutSecs: 12,
      ) &&
      await areFriends(b, toxA)) {
    await deleteFriendViaProfile(b, toxA);
  }
  final cleared = await waitFriendshipState(
    a,
    b,
    toxA,
    toxB,
    friends: false,
    timeoutSecs: 20,
  );
  if (cleared) {
    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      await returnToChatsHome(a);
      await returnToChatsHome(b);
    } on DriveError catch (e) {
      print(
        '[pair] WARN: friendship reset succeeded but home recovery failed: ${e.message}',
      );
    }
    print('[pair] PASS: friendship reset both directions');
    return 0;
  }
  print(
    '[pair] FAIL: friendship reset incomplete '
    '(A has B=${await areFriends(a, toxB)} B has A=${await areFriends(b, toxA)})',
  );
  return 1;
}
