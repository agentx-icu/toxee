// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// KEYED-BUT-NEVER-DRIVEN gap batch #3 — the LAST tranche of controls that carry
// a `ValueKey` (so somebody meant them to be automatable) but that no scenario
// had ever touched. The sweep spine, the dispatch and the shared helpers live
// here; the case BODIES live in the sibling part files
// (`..._keyed_gaps3_msg.dart`, `..._keyed_gaps3_contacts.dart`,
// `..._keyed_gaps3_group.dart`) purely so each stays under the 500-LOC
// complexity cap. They are one library.
//
// TWO-PROCESS, ONE LAUNCH, ONE FRIENDSHIP, ONE GROUP. `sweep_keyed_gaps3` is
// `required=no-friend` (it runs its OWN handshake and REUSES an existing one)
// and `result=friends` (nothing here deletes the friend; the group half creates
// exactly ONE group for all six group cases and leaves it via the shared
// `_gcmeCleanupGroups`). That contract is what lets the runner append it to an
// existing campaign chain instead of paying another pair launch — "real-UI
// startup reuse is the default".
//
// ASSERTION DISCIPLINE (same bar as batches #1/#2): every case asserts an
// observable side effect — a keyed widget MOUNTING or UNMOUNTING, a menu entry
// present on one bubble and ABSENT on another (two different renders of the
// same generator), a snackbar the production code shows, an `l3_dump_state`
// field, or a scroll offset that actually moved. No case passes on "the tap did
// not throw", and the two cases whose next step is an OS surface stop at the
// boundary and say so.
//
// ===========================================================================
// VERIFY-FIRST FINDINGS — five of the listed keys are UNREACHABLE in this
// product and get NO case (documented instead of padded with a scenario that
// could only ever SKIP):
//
//   * `message_menu_item:translate` — DEAD, unconditionally. The generator does
//     add `_uikit_translate`
//     (tencent_cloud_chat_message_item_with_menu_container.dart:544-552), but
//     BOTH post-filters strip it again: `:583` removes it for every elemType
//     that is NOT text, and `:608-614` removes it for text. There is no
//     elemType for which it survives, so the key can never resolve — the
//     `isTextTranslatePluginEnabled` gate above it never even matters.
//
//   * `message_menu_item:convertToText` — DEAD by construction. The entry needs
//     `widget.isSoundToTextPluginEnabled`, which is
//     `dataProvider.soundToTextPluginInstance != null`
//     (tencent_cloud_chat_message_row_container.dart:483). toxee only registers
//     that plugin through `registerTim2toxSoundToTextIfSupported`, whose first
//     line is `if (!backendSupported) return false` with
//     `tim2toxSoundToTextBackendSupported` a **`const bool ... = false`**
//     (lib/ui/home/tim2tox_plugin_policy.dart:1, called from
//     lib/ui/home_page_plugins.dart:270). The plugin is never added, so the
//     menu entry cannot render — the "voice message precondition" is moot.
//
//   * `contact_group_notifications_tab` — DEAD. The key is switched on
//     `item.id == 'group_notification'`
//     (tencent_cloud_chat_contact_tab.dart:48 default / :112 desktop), but the
//     toxee fork DELETED that tab item from BOTH builders with an explicit
//     rationale (tencent_cloud_chat_contact.dart:192-207 desktopBuilder,
//     :280-283 defaultBuilder): the Tox bridge has no group-application
//     concept, so the entry only ever opened a permanently-empty list. The
//     three ids that survive are `new_contacts`, `groups` and `blocked_users`,
//     and the first/third are already driven by `contacts_subtabs_cycle`.
//
//   * `group_invite_accept_button:<gid>` — DEAD at two independent layers. The
//     button renders only inside `TencentCloudChatContactGroupApplicationList`
//     (tencent_cloud_chat_contact_group_application_list.dart:315), which is
//     reachable only through `TencentCloudChatRouteNames.groupApplication`
//     (registered at tencent_cloud_chat_contact.dart:425-430) — and
//     `navigateToGroupApplication`
//     (tencent_cloud_chat_navigator.dart:268-275) has ZERO callers anywhere in
//     the fork or in `lib/`. Even if it were routed to, the list would be
//     empty: `Tim2ToxSdkPlatform.getGroupApplicationList()` returns a
//     hard-coded empty result ("Tox doesn't have group application list",
//     tim2tox_sdk_platform.dart:9652-9675) and `acceptGroupApplication` is a
//     no-op stub. Tox group invites arrive on the onGroupInvited/auto-accept
//     path instead, which `group_add_member_full_join` already drives.
//
//   * `contact_app_bar_add_group_item` — DEAD in production. It is a
//     `MenuItemButton` inside the `MenuAnchor` that the fork builds ONLY in the
//     `else` arm of `if (TencentCloudChatContactAppBarName.trailingBuilder !=
//     null)` (tencent_cloud_chat_contact_app_bar.dart:145-146 default,
//     :198-199 desktop). toxee assigns that hook — `TencentCloudChat
//     ContactAppBarName.trailingBuilder = newEntryHook` (lib/ui/home_page.dart
//     :394) — while HomePage lives, and only clears it from the dispose bag
//     (:406). On top of that it installs a `contactAppBarNameBuilder` override
//     (lib/ui/home_page_bootstrap.dart:124 and :303) that replaces the whole
//     default name widget. The MenuAnchor arm can therefore only run when
//     HomePage is gone, i.e. when the Contacts page is not on screen at all.
//     Its sibling `contact_app_bar_add_contact_item` and the
//     `contact_app_bar_menu_button` fallback icon are dead for the same reason.
// ===========================================================================
//
// NOT VERIFIED BY EXECUTION: authored offline. No campaign run has driven any
// of these cases yet.

const _keyedGaps3Cases = {
  'contact_application_detail_decline_removes_row',
  'friendprof_copy_toxid_snackbar',
  'msgmenu_reveal_file_location_gating',
  'msgmenu_read_receipt_group_gating',
  'personal_card_send_c2c',
  'group_member_info_profile_entry_opens_profile',
  'group_member_action_cancel_closes_sheet',
  'group_add_member_button_opens_picker',
  'group_profile_scroll_view_scrolls',
  'group_profile_edit_name_dialog_cancel',
};

/// The six cases that need a live two-process GROUP. The sweep establishes ONE
/// group and runs all six inside it; a standalone dispatch establishes its own.
/// The ORDER is the sweep's execution order: the member-menu cases first (a
/// failed one is most likely to strand the member-list route, which
/// `_kg3Normalize` then unwinds), the profile cases after.
const _keyedGaps3GroupCases = <String>[
  'msgmenu_read_receipt_group_gating',
  'group_member_info_profile_entry_opens_profile',
  'group_member_action_cancel_closes_sheet',
  'group_add_member_button_opens_picker',
  'group_profile_scroll_view_scrolls',
  'group_profile_edit_name_dialog_cancel',
];

bool _isKeyedGaps3CaseScenario(String scenario) =>
    _keyedGaps3Cases.contains(scenario);

/// Dispatch for `sweep_keyed_gaps3` and its ten individual cases. Called from
/// `dispatchFormFactor` (drive_real_ui_pair_msg_select.dart) — the aggregator
/// `drive_real_ui_pair.dart` is at its complexity pin, so new dispatch lines go
/// through the existing form-factor chain. Returns null when [scenario] is not
/// ours so the caller keeps walking its chain.
Future<int?> dispatchKeyedGaps3(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  if (scenario == 'sweep_keyed_gaps3') {
    return runKeyedGaps3Sweep(a, b, nickA, nickB);
  }
  if (_isKeyedGaps3CaseScenario(scenario)) {
    return runKeyedGaps3Case(a, b, nickA, nickB, scenario);
  }
  return null;
}

/// The runner's SKIP exit code (`_realUiSkipExitCode`). Mirrored here because
/// the driver runs as a separate process.
const _keyedGaps3SkipExit = 75;

/// Standalone dispatch for ONE case (focused debugging). Shares the sweep's
/// preconditions: both peers home, a live A<->B friendship (reused when the
/// launch already has one), and — for the group cases — its own throwaway group.
Future<int> runKeyedGaps3Case(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  final ids = await _kg3EnsureFriendship(a, b, nickA, nickB);
  if (ids == null) {
    print('[pair] $scenario: could not establish the A<->B friendship');
    return 1;
  }
  bool? result;
  if (_keyedGaps3GroupCases.contains(scenario)) {
    result = await _kg3WithGroup(
      a,
      b,
      nickA,
      nickB,
      namePrefix: 'RUI-KG3-ONE',
      run: (est, toxB) => _kg3RunGroupCase(a, b, est, toxB, scenario),
    );
  } else {
    result = await _kg3RunFlatCase(a, b, ids.toxA, ids.toxB, scenario);
  }
  await _msLandHome(a, scenario);
  final label = result == null ? 'SKIP' : (result ? 'PASS' : 'FAIL');
  print('[pair] $label: $scenario');
  return switch (result) {
    true => 0,
    false => 1,
    null => _keyedGaps3SkipExit,
  };
}

/// All ten cases on ONE launch, ONE friendship and ONE group.
///
/// ORDER MATTERS. The friendship-only cases run FIRST (they are cheap and none
/// of them mutates the group state), then the group half runs inside a single
/// `_establishTwoProcessGroup`. Within the group half the MEMBER-menu cases run
/// before the profile cases because the member-list route is the one a failed
/// case is most likely to strand us on, and `_kg3PopToRoot` unwinds it between
/// cases.
Future<int> runKeyedGaps3Sweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final ids = await _kg3EnsureFriendship(a, b, nickA, nickB);
  if (ids == null) {
    print('[sweep] sweep_keyed_gaps3: could not establish the A<->B friendship');
    return 1;
  }
  final tally = _MobileShellTally('sweep_keyed_gaps3');
  for (final name in const [
    'contact_application_detail_decline_removes_row',
    'friendprof_copy_toxid_snackbar',
    'msgmenu_reveal_file_location_gating',
    'personal_card_send_c2c',
  ]) {
    await tally.run(
      name,
      () => _kg3RunFlatCase(a, b, ids.toxA, ids.toxB, name),
      expectedSkip: _keyedGaps3ExpectedSkipCases.contains(name),
    );
    await _kg3Normalize(a);
  }
  // The six group cases share ONE established group. A null return from
  // `_kg3WithGroup` here means the GROUP could not be established, which is a
  // hard failure of the whole half rather than a per-case skip.
  final groupHalfOk = await _kg3WithGroup(
    a,
    b,
    nickA,
    nickB,
    namePrefix: 'RUI-KG3',
    run: (est, toxB) async {
      for (final name in _keyedGaps3GroupCases) {
        await tally.run(
          name,
          () => _kg3RunGroupCase(a, b, est, toxB, name),
          expectedSkip: _keyedGaps3ExpectedSkipCases.contains(name),
        );
        await _kg3Normalize(a);
      }
      return true;
    },
  );
  await _msLandHome(a, 'sweep_keyed_gaps3');
  final endFriends =
      await areFriends(a, ids.toxB) && await areFriends(b, ids.toxA);
  print(
    '[sweep] sweep_keyed_gaps3: groupHalf=$groupHalfOk endFriends=$endFriends',
  );
  final tallyExit = tally.finish();
  if (groupHalfOk != true || !endFriends) return 1;
  return tallyExit;
}

Future<bool?> _kg3RunFlatCase(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
  String scenario,
) => switch (scenario) {
  'contact_application_detail_decline_removes_row' =>
    _kg3ApplicationDetailDecline(a),
  'friendprof_copy_toxid_snackbar' => _kg3FriendProfileCopyToxId(a, toxB),
  'msgmenu_reveal_file_location_gating' => _kg3RevealFileLocationGating(
    a,
    b,
    toxA,
    toxB,
  ),
  'personal_card_send_c2c' => _kg3PersonalCardSendC2c(a, toxB),
  _ => throw ArgumentError('unsupported keyed-gaps3 scenario: $scenario'),
};

Future<bool?> _kg3RunGroupCase(
  Inst a,
  Inst b,
  _EstablishedGroup est,
  String toxB,
  String scenario,
) => switch (scenario) {
  'msgmenu_read_receipt_group_gating' => _kg3ReadReceiptGroupGating(
    a,
    b,
    est,
    toxB,
  ),
  'group_member_info_profile_entry_opens_profile' =>
    _kg3MemberInfoProfileEntry(a, est, toxB),
  'group_member_action_cancel_closes_sheet' => _kg3MemberActionCancel(
    a,
    est,
    toxB,
  ),
  'group_add_member_button_opens_picker' => _kg3AddMemberButtonOpensPicker(
    a,
    est,
  ),
  'group_profile_scroll_view_scrolls' => _kg3ProfileScrollViewScrolls(a, est),
  'group_profile_edit_name_dialog_cancel' => _kg3EditNameDialogCancel(a, est),
  _ => throw ArgumentError('unsupported keyed-gaps3 group case: $scenario'),
};

// ===========================================================================
// Preconditions + teardown
// ===========================================================================

/// Both peers home + friends, REUSING an existing friendship. Same shape as
/// `_mselEnsureFriendship` in the multi-select driver.
Future<({String toxA, String toxB})?> _kg3EnsureFriendship(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[pair] keyed-gaps3: missing tox ids (A=$toxA B=$toxB)');
    return null;
  }
  if (await areFriends(a, toxB) && await areFriends(b, toxA)) {
    return (toxA: toxA, toxB: toxB);
  }
  if (!await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB)) {
    return null;
  }
  return (toxA: toxA, toxB: toxB);
}

/// Establish ONE two-process group, run [run] inside it, and always clean up
/// (restore B's auto-accept, leave the groups on both sides, revoke the test
/// markers). Returns `false` when the group itself could not be established —
/// that is a genuine failure, not a skip; `run`'s own null return is passed
/// through as a SKIP.
Future<bool?> _kg3WithGroup(
  Inst a,
  Inst b,
  String nickA,
  String nickB, {
  required String namePrefix,
  required Future<bool?> Function(_EstablishedGroup est, String toxB) run,
}) async {
  // Same marking contract as `_gcmeWithEstablishedTarget`: peer-row resolution
  // and the establish/cleanup l3 tools are test-gated, so mark up front and
  // unmark LAST, tracking each side independently.
  final aMarked = await a.markAccountTest();
  final bMarked = await b.markAccountTest();
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: namePrefix,
  );
  if (est == null) {
    print('[pair] $namePrefix: could not establish the two-process group');
    await _kg3Unmark(a, aMarked);
    await _kg3Unmark(b, bMarked);
    return false;
  }
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  try {
    return await run(est, toxB);
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (e) {
        print('[pair] $namePrefix: restore auto-accept failed: ${e.message}');
      }
    }
    await _gcmeCleanupGroups(a, b);
    await _kg3Unmark(a, aMarked);
    await _kg3Unmark(b, bMarked);
  }
}

Future<void> _kg3Unmark(Inst inst, bool marked) async {
  if (!marked) return;
  try {
    await inst.unmarkAccountTest();
  } on DriveError catch (_) {
    // Best effort — a revoked marker on a torn-down peer is not a case failure.
  }
}

/// Between-case teardown: dismiss anything modal a half-finished case left up
/// and unwind pushed routes. Never asserts — the cases do that.
Future<void> _kg3Normalize(Inst inst) async {
  try {
    await _dismissMemberMenu(inst);
    await _dismissMessageMenu(inst);
    await _kg3PopToRoot(inst);
  } on Object catch (e) {
    print('[pair] keyed-gaps3 normalize: best-effort: $e');
  }
}

/// Unwind every pushed route (member list / member info / user profile / add
/// member picker). `l3_pop_to_root` is the only portable pop seam — there is no
/// single-level pop tool — and it is navigation plumbing, never the assertion.
Future<void> _kg3PopToRoot(Inst inst) async {
  try {
    await inst.l3('l3_pop_to_root');
  } on DriveError catch (e) {
    print('[pair] keyed-gaps3: pop-to-root warn: ${e.message}');
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
}

// ===========================================================================
// Shared probes
// ===========================================================================

/// Poll until [key] is no longer resolvable through the ELEMENT-TREE walk
/// (`ui_key_center`).
///
/// `Inst.waitKeyGone` goes through flutter_skill's interactive-element index,
/// which never surfaces overlay entries (menus, action sheets) or bare
/// `KeyedSubtree`/`Icon` widgets — exactly what this batch asserts on — so it
/// would report "gone" on the first poll while the widget is on screen, turning
/// the assertion into a no-op. Same reason `_memberMenuGone` exists.
Future<bool> _kg3WaitKeyCenterGone(
  Inst inst,
  String key, {
  int timeoutSecs = 8,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await inst.keyCenter(key) == null) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

/// True when a message menu is currently up. `message_menu_item:delete` is the
/// probe rather than `:copy` because the fork strips copy from every non-TEXT
/// bubble (menu container :583) while delete survives on all of them whenever
/// `enableMessageDeleteForSelf` is on — which toxee pins to true
/// (lib/ui/home_page_bootstrap.dart:678).
Future<bool> _kg3MenuIsUp(Inst inst, {int timeoutSecs = 4}) =>
    inst.waitKeyCenter('message_menu_item:delete', timeoutSecs: timeoutSecs);

/// The ORDERED message entries of the group conversation [gid] from
/// `l3_dump_state` (same shape as `_c2cMessages`).
Future<List<Map<String, dynamic>>> _kg3GroupMessages(
  Inst inst,
  String gid,
) async {
  final s = await inst.dumpState(conversationId: 'group_$gid');
  final raw = (s['messages'] as List?) ?? const [];
  return [
    for (final m in raw)
      if (m is Map) m.cast<String, dynamic>(),
  ];
}

/// Poll the group conversation until a message matching [where] exists, and
/// return its `msgID` (empty when it never landed).
Future<String> _kg3WaitGroupMessageId(
  Inst inst,
  String gid,
  bool Function(Map<String, dynamic> m) where, {
  int timeoutSecs = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    for (final m in await _kg3GroupMessages(inst, gid)) {
      if (!where(m)) continue;
      final id = m['msgID']?.toString() ?? '';
      if (id.isNotEmpty) return id;
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  return '';
}

/// Dispose an [Inst] without letting a dead/unreachable peer's VM-service close
/// hang teardown. Best-effort: swallows errors and times out.
///
/// RELOCATED from `drive_real_ui_pair.dart` (which is pinned at its current
/// line count in `tool/.complexity_baseline.txt`, a ratchet that forbids growth)
/// so this batch's `part` directives fit without re-pinning the aggregator.
/// Behaviour is unchanged — it is the same library.
Future<void> _safeDispose(Inst inst) async {
  try {
    await inst.dispose().timeout(const Duration(seconds: 5));
  } on Object {
    // Peer already gone / connection broken — nothing left to clean up.
  }
}
