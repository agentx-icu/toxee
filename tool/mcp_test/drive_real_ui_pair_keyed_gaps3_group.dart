// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Keyed-gaps batch #3 — the GROUP half. Spine and dispatch live in
// `drive_real_ui_pair_keyed_gaps3.dart`; this file only holds case bodies so each
// part stays under the 500-LOC cap. All five run inside the SAME
// `_establishTwoProcessGroup` when driven from the sweep.

/// Tri-state read of `ui_key_center`'s `onstage` flag: null when [key] does not
/// resolve at all, false when it resolved only through `resolveKeyCenter`'s
/// full-tree fallback (laid out but UNDER an opaque pushed route), true when
/// the onstage walk found it.
///
/// Distinct from `_keyOnstage` (drive_real_ui_pair_conv_mobile.dart), which
/// collapses "absent" and "covered" into one `false`: the route assertions here
/// want to tell those apart in the printed diagnosis.
Future<bool?> _kg3KeyOnstage(Inst inst, String key) async {
  try {
    final r = await inst.l3('ui_key_center', {'key': key});
    if (r['ok'] != true) return null;
    return r['onstage'] == true;
  } on DriveError {
    return null;
  }
}

/// POLL until [key] stops being onstage (covered by a pushed route, or gone).
///
/// A single sample right after the tap reads the tree MID push-transition,
/// while the outgoing route is still onstage — a guaranteed false FAIL
/// (`true->true covered=false`) even though the navigation worked.
Future<bool> _kg3WaitKeyNotOnstage(
  Inst inst,
  String key, {
  int timeoutSecs = 8,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _kg3KeyOnstage(inst, key) != true) return true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

/// Bring the keyed [key] inside the group-profile viewport and return its
/// resolved centre, or null when it never becomes resolvable.
///
/// Two scroll mechanisms, because the group-profile ListView has needed BOTH
/// historically: a touch DRAG on the keyed scroll view (`ui_drag`) and a mouse
/// WHEEL at the content column (`ui_scroll_at`, what
/// `_scrollProfileButtonIntoBand` uses on desktop). Drag first, wheel as the
/// fallback; bounded steps so an absent key surfaces as the caller's assertion
/// rather than as a hang.
Future<({double x, double y})?> _kg3RevealProfileKey(
  Inst inst,
  String key, {
  double topBand = 120,
  double bottomBand = 620,
}) async {
  for (var step = 0; step < 14; step++) {
    final c = await inst.keyCenter(key);
    if (c != null && c.y >= topBand && c.y <= bottomBand) return c;
    final dy = (c == null || c.y > bottomBand) ? -260.0 : 260.0;
    var scrolled = false;
    try {
      await inst.dragBy('group_profile_scroll_view', dy: dy, steps: 14);
      scrolled = true;
    } on DriveError catch (e) {
      print('[pair] kg3 reveal: drag warn: ${e.message}');
    }
    if (!scrolled) {
      final view = await inst.keyCenter('group_profile_scroll_view');
      if (view == null) return c;
      try {
        await inst.scrollAtCoords(view.x, view.y, dy: -dy);
      } on DriveError catch (e) {
        print('[pair] kg3 reveal: wheel warn: ${e.message}');
        return c;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return inst.keyCenter(key);
}

// ===========================================================================
// case — group_member_info_profile_entry_opens_profile
// ===========================================================================
/// `group_member_info_profile_entry`
/// (tencent_cloud_chat_group_member_info.dart:218) is the member-info route's
/// ONLY navigation affordance — the row that pushes that member's user
/// profile. Batch #2 added the key; nothing drove it. This case walks the real
/// chain a user walks: member list -> member row menu -> Info -> member info ->
/// Profile.
///
/// WHAT IS ASSERTED. Three route transitions, each by a key that exists ONLY on
/// that route: `group_member_info_copy_id_button` proves the member-info route,
/// the entry itself must MOUNT there, and after the tap the user-profile route
/// must be the VISIBLE one — `user_profile_copy_id_button` resolves AND is
/// `onstage`, while the member-info key stops being onstage. `Navigator.push`
/// leaves the route underneath mounted and laid out, so an UNMOUNT assertion is
/// wrong here (it produced a false iPad red). Both onstage halves are required:
/// `waitKeyCenter` alone resolves through `resolveKeyCenter`'s COVERED
/// full-tree fallback, so a profile route mounted under something opaque would
/// otherwise pass.
///
/// Both platforms reach the Info action — `_memberMenuInfoKey` resolves it to
/// the desktop popup item or the mobile sheet action — so no form-factor gate
/// is needed here.
Future<bool?> _kg3MemberInfoProfileEntry(
  Inst a,
  _EstablishedGroup est,
  String toxB,
) async {
  const label = 'group_member_info_profile_entry_opens_profile';
  final row = await _openPeerMemberMenu(a, est.groupIdA, toxB, label: label);
  if (row == null) return false;
  if (!await a.tapKeyCenter(_memberMenuInfoKey(a), timeoutSecs: 6)) {
    print('[pair] $label: the member-menu Info action was not tappable');
    return false;
  }
  final onMemberInfo = await a.waitKeyCenter(
    'group_member_info_copy_id_button',
    timeoutSecs: 8,
  );
  if (!onMemberInfo) {
    await a.shot('/tmp/ui_kg3_meminfo_${a.name}.png');
    print('[pair] $label: the member-info route did not mount');
    return false;
  }
  final entryMounted = await a.waitKeyCenter(
    'group_member_info_profile_entry',
    timeoutSecs: 6,
  );
  if (!entryMounted) {
    await a.shot('/tmp/ui_kg3_meminfo_noentry_${a.name}.png');
    print('[pair] $label: group_member_info_profile_entry did not render');
    return false;
  }
  // Baseline the onstage signal WHILE the member-info route is still the top
  // route, so the post-tap reading below is a proven FLIP and not a value that
  // was already false for layout reasons.
  final memberInfoOnstageBefore = await _kg3KeyOnstage(
    a,
    'group_member_info_copy_id_button',
  );
  if (!await a.tapKeyCenter(
    'group_member_info_profile_entry',
    timeoutSecs: 6,
  )) {
    print('[pair] $label: the Profile entry was not tappable');
    return false;
  }
  final onUserProfile = await a.waitKeyCenter(
    'user_profile_copy_id_button',
    timeoutSecs: 10,
  );
  // The member-info route must stop being the VISIBLE route. It is NOT
  // unmounted — `Navigator.push` keeps it in the tree with positive bounds — so
  // the honest signal is `onstage`: null (gone) or false (found only by the
  // covered full-tree fallback). Live-diagnosed on iPad 2026-08-16, where the
  // old `_kg3WaitKeyCenterGone` check read the still-laid-out member-info route
  // and FAILED a navigation the screenshot shows working. POLLED, not sampled
  // once (see [_kg3WaitKeyNotOnstage]): sampling made this a guaranteed Android
  // FAIL by reading the signal mid push-transition.
  final memberInfoCovered = await _kg3WaitKeyNotOnstage(
    a,
    'group_member_info_copy_id_button',
  );
  // Sampled AFTER the poll above, so the transition has settled: reading it
  // first would catch the incoming route mid-push and under-report onstage.
  final userProfileOnstage = await _kg3KeyOnstage(
    a,
    'user_profile_copy_id_button',
  );
  await a.shot('/tmp/ui_kg3_meminfo_profile_${a.name}.png');
  await _kg3PopToRoot(a);
  print(
    '[pair] $label: memberInfoRoute=$onMemberInfo entry=$entryMounted '
    'userProfileRoute=$onUserProfile '
    'userProfileOnstage=$userProfileOnstage '
    'memberInfoOnstageBefore=$memberInfoOnstageBefore '
    'covered=$memberInfoCovered',
  );
  // `userProfileOnstage` is part of the VERDICT, not just the diagnosis: it used
  // to be computed and printed but excluded, so a profile route mounted UNDER an
  // opaque cover passed on `waitKeyCenter`'s full-tree fallback alone.
  return onUserProfile && userProfileOnstage == true && memberInfoCovered;
}

// ===========================================================================
// case — group_member_action_cancel_closes_sheet
// ===========================================================================
/// `group_member_action_cancel_button` is the MOBILE member action sheet's own
/// Cancel action. Batch #2 added it (an outside tap on a CupertinoActionSheet
/// barrier is unreliable on a narrow shell) and `_dismissMemberMenu` uses it
/// for TEARDOWN — but teardown is not an assertion, so its contract had never
/// been gated by a case.
///
/// FORM FACTOR — LIVE SURFACE PROBE. The member row wires the desktop popup
/// only when `TencentCloudChatPlatformAdapter().isDesktop`
/// (tencent_cloud_chat_group_member_list.dart#defaultBuilder), so the two
/// surfaces are mutually exclusive at runtime. Rather than trusting a platform
/// name, this case OPENS the menu and looks at which one came up: the desktop
/// popup item (`group_member_desktop_info_item`) means there is no Cancel action
/// to drive and the case SKIPs (a declared, product-shaped skip); the sheet's
/// Cancel action means the mobile surface is live.
///
/// WHAT IS ASSERTED. After the real Cancel tap the sheet's Cancel AND Info
/// actions both UNMOUNT (element-tree probe — `waitKeyGone` cannot see overlay
/// entries) while the underlying member-list route stays up: the peer's member
/// ROW is still resolvable. That distinguishes "the sheet closed" from "Cancel
/// popped the whole route".
Future<bool?> _kg3MemberActionCancel(
  Inst a,
  _EstablishedGroup est,
  String toxB,
) async {
  const label = 'group_member_action_cancel_closes_sheet';
  const cancelKey = 'group_member_action_cancel_button';
  final row = await _openPeerMemberMenu(a, est.groupIdA, toxB, label: label);
  if (row == null) return false;
  final desktopPopup = await a.waitKeyCenter(
    'group_member_desktop_info_item',
    timeoutSecs: 2,
  );
  final sheetCancel = await a.waitKeyCenter(cancelKey, timeoutSecs: 3);
  if (desktopPopup && !sheetCancel) {
    await _dismissMemberMenu(a);
    await _kg3PopToRoot(a);
    print(
      '[pair] $label: SKIP — the DESKTOP member popup is the live surface '
      '(group_member_desktop_info_item resolved). That menu has no Cancel '
      'item: it is dismissed by its modal barrier, and the sheet action this '
      'case asserts only exists on the mobile CupertinoActionSheet.',
    );
    return null;
  }
  if (!sheetCancel) {
    await a.shot('/tmp/ui_kg3_sheetcancel_absent_${a.name}.png');
    print('[pair] $label: neither member-menu surface exposed a known action');
    return false;
  }
  final infoUp = await a.waitKeyCenter(_memberMenuInfoKey(a), timeoutSecs: 3);
  if (!await a.tapKeyCenter(cancelKey, timeoutSecs: 6)) {
    print('[pair] $label: the sheet Cancel action was not tappable');
    return false;
  }
  final cancelGone = await _kg3WaitKeyCenterGone(a, cancelKey, timeoutSecs: 8);
  final infoGone = await _kg3WaitKeyCenterGone(
    a,
    _memberMenuInfoKey(a),
    timeoutSecs: 6,
  );
  final rowStillThere = await a.waitKeyCenter(row, timeoutSecs: 6);
  await a.shot('/tmp/ui_kg3_sheetcancel_${a.name}.png');
  await _kg3PopToRoot(a);
  print(
    '[pair] $label: sheetWasUp=$infoUp cancelUnmounted=$cancelGone '
    'infoUnmounted=$infoGone memberListStillUp=$rowStillThere',
  );
  return infoUp && cancelGone && infoGone && rowStillThere;
}

// ===========================================================================
// case — group_add_member_button_opens_picker
// ===========================================================================
/// `group_add_member_button`
/// (tencent_cloud_chat_group_profile_body.dart:1620) is the real "+ Add
/// Members" row of the group-profile member section. It renders whenever
/// `checkCanAddMember()` holds (`approveOpt != V2TIM_GROUP_ADD_FORBID`, :45-50)
/// and it IS live in toxee: the override wraps the upstream
/// `TencentCloudChatGroupProfileGroupMember` rather than replacing it
/// (lib/ui/group/group_builder_override.dart:63-75).
///
/// WHY THIS CASE. Every existing add-member scenario
/// (`group_add_member_open`, `group_add_member_picker`,
/// `group_add_member_full_join`) opens the picker through the
/// `l3_open_group_add_member` DEEP LINK, so the real button that a user taps
/// had never been exercised — a regression that unmounted it would not have
/// been caught anywhere.
///
/// WHAT IS ASSERTED. The button resolves in the profile ListView (scrolled into
/// view through the keyed scroll view when it is below the fold), and tapping
/// it MOUNTS the invite picker's own `group_member_invite_confirm_button`. The
/// picker is then popped WITHOUT confirming, and the group member count is
/// asserted UNCHANGED so the case leaves the shared group exactly as it found
/// it for the other four group cases.
Future<bool?> _kg3AddMemberButtonOpensPicker(
  Inst a,
  _EstablishedGroup est,
) async {
  const label = 'group_add_member_button_opens_picker';
  final gid = est.groupIdA;
  if (!await _openGroupProfileClean(a, gid)) {
    print('[pair] $label: the group profile did not open');
    return false;
  }
  final before = await _groupMemberCount(a, gid);
  final centre = await _kg3RevealProfileKey(a, 'group_add_member_button');
  if (centre == null) {
    await a.shot('/tmp/ui_kg3_addmember_absent_${a.name}.png');
    print(
      '[pair] $label: group_add_member_button never resolved in the profile '
      'ListView (checkCanAddMember() false, or the section did not render)',
    );
    return false;
  }
  if (!await a.tapKeyCenter('group_add_member_button', timeoutSecs: 8)) {
    print('[pair] $label: the add-member row was not tappable');
    return false;
  }
  final pickerUp = await a.waitKeyCenter(
    'group_member_invite_confirm_button',
    timeoutSecs: 12,
  );
  await a.shot('/tmp/ui_kg3_addmember_${a.name}.png');
  await _kg3PopToRoot(a);
  final pickerGone = await _kg3WaitKeyCenterGone(
    a,
    'group_member_invite_confirm_button',
    timeoutSecs: 8,
  );
  final after = await _groupMemberCount(a, gid);
  print(
    '[pair] $label: buttonAt=$centre pickerMounted=$pickerUp '
    'pickerDismissed=$pickerGone members $before -> $after',
  );
  return pickerUp && pickerGone && before == after;
}

// ===========================================================================
// case — group_profile_scroll_view_scrolls
// ===========================================================================
/// `group_profile_scroll_view` (tencent_cloud_chat_group_profile_body.dart:67)
/// is the group profile's ListView. Its sibling `group_profile_scroll_anchor`
/// is dragged by `sweep_group2`, but the scroll view key itself had never been
/// used — so nothing pinned that the profile body is ONE scrollable with that
/// handle, which every "below the fold" reveal in the group cases depends on.
///
/// WHAT IS ASSERTED. A real scroll gesture driven THROUGH the keyed scroll view
/// moves the content: the top anchor's resolved centre y strictly DECREASES by
/// a meaningful amount (or the anchor scrolls off the tree entirely), and a
/// bottom-anchored control (`group_profile_leave_button`) becomes resolvable
/// afterwards — an inert key would leave the anchor pinned.
Future<bool?> _kg3ProfileScrollViewScrolls(Inst a, _EstablishedGroup est) async {
  const label = 'group_profile_scroll_view_scrolls';
  const anchorKey = 'group_profile_scroll_anchor';
  if (!await _openGroupProfileClean(a, est.groupIdA)) {
    print('[pair] $label: the group profile did not open');
    return false;
  }
  final view = await a.keyCenter('group_profile_scroll_view');
  if (view == null) {
    await a.shot('/tmp/ui_kg3_scrollview_absent_${a.name}.png');
    print('[pair] $label: group_profile_scroll_view did not resolve');
    return false;
  }
  final before = await a.keyCenter(anchorKey);
  if (before == null) {
    print('[pair] $label: the top anchor did not resolve before scrolling');
    return false;
  }
  // A ListView whose content already fits the viewport has ZERO scroll extent —
  // there is nothing for a gesture to move, and on iOS BouncingScrollPhysics
  // even an overscroll springs straight back. That is real on an iPad, whose
  // 1194pt-tall portrait viewport renders the whole profile body (live
  // 2026-08-16: anchor y=100, Leave y≈1068), so the case SKIPs there.
  //
  // THE SKIP CONDITION IS MEASURED, NOT ESTIMATED. It used to compare the bottom
  // control against `2 * view.y - 120` — the scroll view's centre doubled minus
  // a GUESSED app-bar/safe-area constant. That guess drifts with every chrome
  // change, so anything shortening the profile body would have turned a genuine
  // "the drag did nothing" red into a swallowed SKIP. `ui_key_center` reports
  // the RenderBox's own `h`, so the scrollable's true bottom edge is `y + h / 2`
  // and the skip now tracks the product's actual layout. With no measurement the
  // case does NOT skip — it goes on to assert the drag.
  final viewportBottom = await _measuredBottomEdge(
    a,
    'group_profile_scroll_view',
  );
  final bottomBefore = await a.keyCenter('group_profile_leave_button');
  if (viewportBottom != null &&
      bottomBefore != null &&
      bottomBefore.y <= viewportBottom) {
    print(
      '[pair] $label: SKIP — the whole profile body fits this viewport, so '
      'group_profile_scroll_view has no scroll extent to move '
      '(top anchor y=${before.y} AND the bottom-most control '
      'group_profile_leave_button y=${bottomBefore.y} are BOTH above the '
      'MEASURED scroll-view bottom edge $viewportBottom before any gesture).',
    );
    return null;
  }
  var moved = false;
  var after = before;
  for (var step = 0; step < 6 && !moved; step++) {
    var scrolled = false;
    try {
      await a.dragBy('group_profile_scroll_view', dy: -260, steps: 14);
      scrolled = true;
    } on DriveError catch (e) {
      print('[pair] $label: drag warn: ${e.message}');
    }
    if (!scrolled) {
      try {
        await a.scrollAtCoords(view.x, view.y, dy: 260);
      } on DriveError catch (e) {
        print('[pair] $label: wheel warn: ${e.message}');
        break;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final probe = await a.keyCenter(anchorKey);
    if (probe == null) {
      // Scrolled clean off the top of the viewport — an even stronger signal.
      moved = true;
      break;
    }
    after = probe;
    moved = before.y - probe.y >= 80;
  }
  final leaveReachable =
      await _kg3RevealProfileKey(a, 'group_profile_leave_button') != null;
  await a.shot('/tmp/ui_kg3_scrollview_${a.name}.png');
  print(
    '[pair] $label: anchor y ${before.y} -> ${after.y} moved=$moved '
    'bottomControlReachable=$leaveReachable',
  );
  return moved && leaveReachable;
}

// ===========================================================================
// case — group_profile_edit_name_dialog_cancel
// ===========================================================================
/// `UiKeys.groupProfileEditNameDialog` (lib/ui/group/group_builder_override.dart
/// :603) keys the rename AlertDialog itself. Every existing rename case
/// (`group_rename_updates_header`, `conference_rename_leave`,
/// `settings`-adjacent walks) drives the BUTTON, the FIELD and the CONFIRM
/// action but probes none of them for the dialog key, and none of them takes
/// the CANCEL branch at all — so both the dialog handle and the discard path
/// were dark.
///
/// WHAT IS ASSERTED. The dialog key MOUNTS after the real edit button tap; a
/// new name is typed into the real field; the real Cancel action UNMOUNTS the
/// dialog; and the group's `showName` in `l3_dump_state.conversations` is still
/// the ORIGINAL — i.e. Cancel discarded the edit instead of applying it. The
/// name check is what makes this more than a dialog-open smoke test.
///
/// Cancel has no key of its own (it is the AlertDialog's plain `tL10n.cancel`
/// TextButton), so it is tapped by its visible label through
/// `_kgTapTextTopmost`, which targets the TOPMOST match — the dialog action —
/// rather than any same-labelled control on the page underneath.
Future<bool?> _kg3EditNameDialogCancel(Inst a, _EstablishedGroup est) async {
  const label = 'group_profile_edit_name_dialog_cancel';
  const dialogKey = 'group_profile_edit_name_dialog';
  final gid = est.groupIdA;
  final original = est.groupName;
  final discarded = '$original-DISCARDED';
  if (!await _openGroupProfileClean(a, gid)) {
    print('[pair] $label: the group profile did not open');
    return false;
  }
  if (!await a.tapKeyCenter('group_profile_edit_name_button', timeoutSecs: 8)) {
    print('[pair] $label: the edit-name button was not tappable');
    return false;
  }
  final dialogUp = await a.waitKeyCenter(dialogKey, timeoutSecs: 10);
  final fieldUp = await a.waitKeyCenter(
    'group_profile_edit_name_field',
    timeoutSecs: 8,
  );
  if (!dialogUp || !fieldUp) {
    await a.shot('/tmp/ui_kg3_renamedlg_${a.name}.png');
    print('[pair] $label: dialog=$dialogUp field=$fieldUp — nothing to cancel');
    return false;
  }
  await a.focusType('group_profile_edit_name_field', discarded);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final cancelTapped = await _kgTapTextTopmost(a, 'Cancel', timeoutSecs: 6);
  if (!cancelTapped) {
    print('[pair] $label: the dialog Cancel action was not tappable');
    // Leave no modal behind for the next case.
    await a.osaEscape();
    return false;
  }
  final dialogGone = await _kg3WaitKeyCenterGone(a, dialogKey, timeoutSecs: 8);
  // The rename would have propagated through Prefs + refreshConversations, so
  // give it the same window a successful rename gets before asserting it did
  // NOT happen.
  final leaked = await _waitGroupShowName(a, gid, discarded, timeoutSecs: 6);
  final kept = await _waitGroupShowName(a, gid, original, timeoutSecs: 6);
  await a.shot('/tmp/ui_kg3_renamedlg_after_${a.name}.png');
  print(
    '[pair] $label: dialogMounted=$dialogUp dialogUnmounted=$dialogGone '
    'nameLeaked=$leaked nameKept=$kept ("$original")',
  );
  return dialogGone && !leaked && kept;
}
