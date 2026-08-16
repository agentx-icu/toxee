// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// The per-member management menu in the group member list — ONE user-facing
// surface, TWO platform affordances. Every group/conference member case that
// used to hard-code the `group_member_desktop_*` keys goes through here.
//
// WHY this exists (verified live on an iPad simulator, 2026-08-15):
// `tencent_cloud_chat_group_member_list.dart#defaultBuilder` wires the row as
//
//   Listener(onPointerDown: isDesktop ? _showDesktopContextMenu : null,
//            child: GestureDetector(onTap: onManageMember, ...))
//
// where `isDesktop` is `TencentCloudChatPlatformAdapter().isDesktop` — a
// PLATFORM test, not a width test. So on iOS/iPadOS/Android the secondary-tap
// branch is literally `null`: the desktop popup menu can never appear, no
// matter how wide the shell is (an iPad runs the master-detail layout AND the
// mobile member sheet at the same time). `Inst.isMobileShell` is
// `isIos || isAndroid`, which is exactly the same predicate, so it is the right
// switch here.
//
// The two surfaces are NOT identical, and the difference is real product
// behaviour rather than a harness limitation:
//
//   desktop popup : Info | Copy ID | Set/Dismiss admin | Remove
//   mobile  sheet : Info | Set/Dismiss admin | Remove | Cancel
//
// i.e. the mobile sheet has NO inline Copy-ID action; the same capability sits
// one level deeper, behind Info → the member-info route's
// `group_member_info_copy_id_button`. `memberMenuCopyIdReachable` asserts that
// capability on BOTH platforms instead of dropping the assertion on mobile.
//
// Role and kick are conditional on `canSetAdmin()` / `canDeleteMember()`, so on
// a conference row the mobile sheet is Info + Cancel only — which is why the
// "is the menu up?" probe keys off Info (always present) and not off role/kick.

/// Key of the ROLE (set/dismiss admin) action in the live member menu.
String _memberMenuRoleKey(Inst inst) => inst.isMobileShell
    ? 'group_member_action_role_button'
    : 'group_member_desktop_role_item';

/// Key of the REMOVE/kick action in the live member menu.
String _memberMenuKickKey(Inst inst) => inst.isMobileShell
    ? 'group_member_action_kick_button'
    : 'group_member_desktop_kick_item';

/// Key of the INFO action — the only action present on BOTH platforms for EVERY
/// member row (group or conference, owner or not), hence the menu-up probe.
String _memberMenuInfoKey(Inst inst) => inst.isMobileShell
    ? 'group_member_action_info_button'
    : 'group_member_desktop_info_item';

/// Open the member menu for [peerTox] in [groupId] through the REAL affordance
/// for the platform: a secondary-tap on desktop, a plain row tap on mobile.
/// Returns the resolved member row key, or null with a screenshot + reason.
Future<String?> _openPeerMemberMenu(
  Inst inst,
  String groupId,
  String peerTox, {
  required String label,
}) async {
  if (!await _openGroupMemberListPage(inst, groupId)) {
    print('[pair] $label: member-list page did not open');
    return null;
  }
  final rowKey = await _gcmeVisiblePeerRowKey(inst, groupId, peerTox);
  if (rowKey == null) {
    await inst.shot('/tmp/ui_${label}_norow_${inst.name}.png');
    print('[pair] $label: peer member row not rendered');
    return null;
  }
  final rowCenter = await inst.keyCenter(rowKey);
  for (var attempt = 0; attempt < 3; attempt++) {
    if (inst.isMobileShell) {
      // The mobile sheet is opened by the row's ordinary onTap. Use the
      // element-tree resolver: the member rows are KeyedSubtree children that
      // whole-tree key lookup does not traverse (same reason
      // `_gcmeVisiblePeerRowKey` exists).
      if (!await inst.tapKeyCenter(rowKey, timeoutSecs: 6)) {
        print('[pair] $label: member row tap did not land (attempt $attempt)');
      }
    } else {
      try {
        await inst.secondaryTapKey(rowKey);
      } on DriveError catch (e) {
        print('[pair] $label: secondaryTap warn: ${e.message}');
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    // Both surfaces render in an Overlay entry, so probe with the element-tree
    // resolver rather than whole-tree waitKey. On mobile also accept the sheet's
    // Cancel action: it predates the Info key, so "Cancel present, Info absent"
    // pins the failure on a stale bundle rather than on the sheet not opening.
    if (await inst.waitKeyCenter(_memberMenuInfoKey(inst), timeoutSecs: 2)) {
      return rowKey;
    }
    if (inst.isMobileShell &&
        await inst.waitKeyCenter(
          'group_member_action_cancel_button',
          timeoutSecs: 1,
        )) {
      print(
        '[pair] $label: member sheet IS up but '
        '${_memberMenuInfoKey(inst)} is absent — stale app bundle?',
      );
      return rowKey;
    }
  }
  await inst.shot('/tmp/ui_${label}_nomenu_${inst.name}.png');
  print(
    '[pair] $label: member menu did not open '
    '(row=$rowKey center=$rowCenter mobileShell=${inst.isMobileShell})',
  );
  return null;
}

/// Poll until a member-menu item is GONE, via the ELEMENT-TREE walk.
///
/// `Inst.waitKeyGone` goes through flutter_skill's `waitForGone`, which does not
/// surface the menu/action-sheet overlay entries at all — so it reports
/// `gone: true` on the very first poll whether or not the menu is still up,
/// turning a "menu closed" assertion into a no-op. Mirroring `waitKeyCenter`
/// (which the open-side probes already use) keeps the assertion real.
Future<bool> _memberMenuGone(
  Inst inst,
  String key, {
  int timeoutSecs = 5,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await inst.keyCenter(key) == null) return true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

/// Close whatever member menu is up. Desktop dismisses via the modal barrier;
/// the mobile action sheet has a keyed Cancel action (an outside tap on a
/// CupertinoActionSheet barrier is unreliable on a narrow shell — the fork
/// added `group_member_action_cancel_button` for exactly this).
Future<void> _dismissMemberMenu(Inst inst) async {
  if (!inst.isMobileShell) {
    await _dismissContextMenu(inst);
    return;
  }
  if (await inst.waitKeyCenter(
    'group_member_action_cancel_button',
    timeoutSecs: 2,
  )) {
    await inst.tapKeyCenter(
      'group_member_action_cancel_button',
      timeoutSecs: 4,
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/// Assert the member's Tox ID can be COPIED from the member menu surface.
///
/// Desktop exposes this inline (`group_member_desktop_copy_id_item`). Mobile
/// does not put it in the sheet at all, so the mobile leg drives the real path a
/// phone user takes — Info → member-info route → `group_member_info_copy_id_button`.
///
/// Called with the member menu ALREADY OPEN, and — on mobile — CONSUMES it (the
/// Info tap pops the sheet and pushes the member-info route). Callers must
/// therefore probe role/kick BEFORE calling this, and treat the menu as closed
/// afterwards; the mobile leg unwinds to the chats root so the next case starts
/// from a known place.
Future<bool> _memberMenuCopyIdReachable(
  Inst inst, {
  required String label,
}) async {
  if (!inst.isMobileShell) {
    return inst.waitKeyCenter(
      'group_member_desktop_copy_id_item',
      timeoutSecs: 3,
    );
  }
  if (!await inst.tapKeyCenter(_memberMenuInfoKey(inst), timeoutSecs: 6)) {
    print('[pair] $label: mobile member-menu Info action did not tap');
    return false;
  }
  final reachable = await inst.waitKeyCenter(
    'group_member_info_copy_id_button',
    timeoutSecs: 6,
  );
  if (!reachable) {
    await inst.shot('/tmp/ui_${label}_nocopyid_${inst.name}.png');
    print('[pair] $label: member-info copy-id button not reachable');
  }
  // Unwind the pushed member-info route (l3_pop_to_root is the only portable
  // pop seam; there is no single-level pop tool).
  await inst.l3('l3_pop_to_root');
  await Future<void>.delayed(const Duration(milliseconds: 600));
  return reachable;
}
