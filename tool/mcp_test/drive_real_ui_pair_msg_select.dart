// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// MESSAGE MULTI-SELECT cases — the surface behind `message_menu_item:multiSelect`.
//
// WHY THIS FILE EXISTS. `message_menu_item:multiSelect` was one of the keyed-but-
// never-driven menu actions: no scenario had ever entered select mode, so the
// ENTIRE multi-select surface (the toolbar that REPLACES the composer, its
// delete/forward affordances, the delete confirmation dialog, and the select-mode
// header bar) was dark. Those widgets had no keys at all until this batch; the
// keys added alongside these cases are catalogued in
// `lib/ui/testing/ui_keys_fork.dart` (class `ForkUiKeys`).
//
// WHICH BUBBLE CAN EVEN ENTER SELECT MODE (verified by reading the fork, not
// assumed). `tencent_cloud_chat_message_item_with_menu_container.dart` strips
// `_uikit_multi_message` from the menu for TEXT bubbles AND for
// file/image/video/sound bubbles. What is left is the CUSTOM bubble — the same
// bubble `reply_quote_real` drives for the Reply item, and for the same reason.
// So every case here seeds an inbound CUSTOM message through `l3_inject_c2c_custom`
// (the identical seam sweep_p2_reply uses) and long-presses / right-clicks THAT
// row.
//
// WHY A MISSING multiSelect ENTRY IS A **FAILURE**, NOT A SKIP. The custom
// bubble is the LAST bubble type that still carries `_uikit_multi_message`; it
// is the only door into the entire select-mode surface. If a fork sync ever
// strips it there too, every assertion in this file becomes unreachable. Were
// that reported as a SKIP, the sweep would go green-ish (`finish()` only
// returns 75 when NOTHING passed, and these cases are chained with others that
// do pass) and the whole multi-select surface would silently stop being
// covered — the exact "coverage evaporates without anyone noticing" failure
// mode this batch exists to prevent. So `_mselEnterSelectMode` returns FALSE
// there, and prints the diagnosis. Both halves of the regression are caught:
// the SOURCE half by `test/fork_message_multi_select_menu_test.dart` (runs in
// the device-free `flutter test` gate, so a bad fork sync is red before any
// campaign is even launched), the RUNTIME half by this FAIL.
//
// THERE IS NO SKIP LEFT IN THIS FILE — the last one was RETRACTED as false.
// `_mselForwardSurface` used to SKIP when the multi-select toolbar rendered no
// forward affordance, on the claim that `enableMessageForwardIndividually` /
// `enableMessageForwardCombined` are product CONFIG toggles a build may
// legitimately turn off. In toxee they are not toggles at all, and the SKIP was
// unreachable by construction:
//   * `enableMessageForwardIndividually` is pinned TRUE — toxee sets it in
//     `lib/ui/home_page_bootstrap.dart:683` and the fork's own
//     `TencentCloudChatMessageDefaultMessageSelectionOptionsConfig` default is
//     also true, so no code path yields false.
//   * `enableMessageForwardCombined` is pinned FALSE — the fork's select-mode
//     container hardcodes it (`..._input_select_mode_container.dart:43`) until
//     the Tox-side merger elem exists, ignoring whatever the app config says.
// The phone builder gates its single forward icon on
// `enableMessageForwardCombined || enableMessageForwardIndividually`
// (`..._input_select_mode.dart:190`) = `false || true` = ALWAYS TRUE, and the
// tablet/desktop builders gate their direct button on Individually alone —
// also always true. So "no forward affordance" can never mean "config off"; it
// can only mean the toolbar did not mount, which is a product/fork regression
// and is now reported as a FAIL carrying that diagnosis.
//
// ASSERTION DISCIPLINE. Every case asserts an observable side effect, never
// "the tap did not throw":
//   * enter/cancel  — the select-mode header (`message_select_count_text`,
//                     `message_select_cancel_button`) and the toolbar
//                     (`message_select_delete_button`) MOUNT, then UNMOUNT after
//                     the real Cancel tap.
//   * delete-cancel — the confirmation dialog's two keyed actions mount, Cancel
//                     dismisses them, the message ROW is still in the tree AND
//                     still in the conversation history, and select mode is
//                     still up (the dialog cancel must not leave select mode).
//   * delete-confirm— the row is GONE from the tree, the message is GONE from
//                     history, and select mode exited by itself
//                     (`onDeleteForMe` sets `inSelectMode = false`).
//   * forward       — the real forward TARGET picker mounts
//                     (`forward_picker_send_button`), then unmounts after the
//                     picker's Cancel. Nothing is actually forwarded, so the
//                     case leaves no state behind.
//
// FORM FACTOR. The toolbar renders on every form factor, but its forward
// affordance differs by builder: the PHONE `defaultBuilder` shows ONE icon that
// opens a bottom sheet of forward types, while tablet/desktop render the
// per-type buttons directly. The forward case DETECTS which is mounted (it does
// not guess from the platform, and a narrowed desktop window keeps the desktop
// builder), and drives that path. Everything else is shared Dart, so an iOS /
// Android / desktop run exercises the same widgets — these cases are registered
// in the mobile campaign matrix for exactly that reason.
//
// INPUT PATH. No `osa*` keystroke is used anywhere here (a silent no-op on
// iOS/Android — see drive_real_ui_pair_mobile_shell.dart's input-path rule):
// only real taps through `tapKeyCenter` / `tryTapKey`, the long-press/right-click
// menu opener `_openMessageMenuReal`, and the ungated l3 seed seam.
//
// NOT VERIFIED BY EXECUTION: authored offline; no campaign run has driven these
// cases yet.

const _msgSelectCases = {
  'msg_select_enter_and_cancel',
  'msg_select_delete_cancel_keeps_message',
  'msg_select_delete_for_me_removes_row',
  'msg_select_forward_surface',
};

bool _isMsgSelectCaseScenario(String scenario) =>
    _msgSelectCases.contains(scenario);

/// Scenario dispatch for the FORM-FACTOR families (mobile shell / tablet layout)
/// and for the multi-select cases above.
///
/// It lives here rather than inline in `drive_real_ui_pair.dart` so that file
/// stays under its `tool/.complexity_baseline.txt` pin — the same "move it into
/// a part file instead of re-pinning" move the campaign catalog used. Returns
/// null when [scenario] belongs to neither family, so the caller keeps walking
/// its dispatch chain.
Future<int?> dispatchFormFactor(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  if (scenario == 'sweep_mobile_shell') {
    return runMobileShellSweep(a, b, nickA, nickB);
  }
  if (scenario == 'sweep_tablet_layout') {
    return runTabletLayoutSweep(a, b, nickA, nickB);
  }
  if (_isMobileShellCaseScenario(scenario)) {
    return runMobileShellCase(a, b, nickA, nickB, scenario);
  }
  if (scenario == 'sweep_msg_select') {
    return runMsgSelectSweep(a, b, nickA, nickB);
  }
  if (_isMsgSelectCaseScenario(scenario)) {
    return runMsgSelectCase(a, b, nickA, nickB, scenario);
  }
  // Keyed-but-never-driven batch #3 (message-menu gating / application-detail
  // decline / friend-profile copy-id / personal card / group profile + member
  // info). TWO-PROCESS, so both peers are forwarded.
  final kg3 = await dispatchKeyedGaps3(a, b, nickA, nickB, scenario);
  if (kg3 != null) return kg3;
  // Keyed-but-never-driven batch #4 (select-mode Clear / combined-forward
  // gating / attachment surfaces / media viewer / narrow-shell composer +
  // @-mention picker / LoginPage account delete). Two-process except the login
  // sweep, so both peers are forwarded.
  final kg4 = await dispatchKeyedGaps4(a, b, nickA, nickB, scenario);
  if (kg4 != null) return kg4;
  // Keyed-but-never-driven batch #2 (register page / IRC app / add-group type
  // selector). Single-instance — B stays idle — so only A is forwarded. Routed
  // through here for the same reason the multi-select dispatch is: the
  // aggregator `drive_real_ui_pair.dart` is at its complexity pin.
  return dispatchKeyedGaps(a, nickA, scenario);
}

/// Standalone dispatch for one multi-select case (focused debugging). Shares the
/// sweep's precondition: both peers home + a live A<->B friendship, reusing an
/// existing one when the launch already has it.
Future<int> runMsgSelectCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  final ids = await _mselEnsureFriendship(a, b, nickA, nickB);
  if (ids == null) {
    print('[pair] $scenario: could not establish the A<->B friendship');
    return 1;
  }
  final result = await _mselRun(a, scenario, ids.toxB);
  final label = result == null ? 'SKIP' : (result ? 'PASS' : 'FAIL');
  print('[pair] $label: $scenario');
  return switch (result) {
    true => 0,
    false => 1,
    null => _msgSelectSkipExit,
  };
}

/// The runner's SKIP exit code (`_realUiSkipExitCode` in
/// fixture_c_unified_runner.dart). Mirrored here because the driver is a
/// separate process.
const _msgSelectSkipExit = 75;

/// All four cases on ONE launch and ONE friendship — the repository's
/// "real-UI startup reuse is the default" rule. Ordered so the DESTRUCTIVE case
/// (delete-for-me) runs after the non-destructive ones; each case seeds its own
/// throwaway custom bubble, so no case depends on another's message.
Future<int> runMsgSelectSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final ids = await _mselEnsureFriendship(a, b, nickA, nickB);
  if (ids == null) {
    print('[sweep] sweep_msg_select: could not establish the A<->B friendship');
    return 1;
  }
  final tally = _MobileShellTally('sweep_msg_select');
  for (final name in const [
    'msg_select_enter_and_cancel',
    'msg_select_delete_cancel_keeps_message',
    'msg_select_forward_surface',
    'msg_select_delete_for_me_removes_row',
  ]) {
    await tally.run(name, () => _mselRun(a, name, ids.toxB));
    // Leave no modal/select-mode residue for the next case even if one failed
    // mid-flow: a stuck dialog would cascade into false reds.
    await _mselForceLeaveSelectMode(a);
  }
  await _msLandHome(a, 'sweep_msg_select');
  return tally.finish();
}

Future<bool?> _mselRun(Inst a, String scenario, String toxB) => switch (scenario) {
  'msg_select_enter_and_cancel' => _mselEnterAndCancel(a, toxB),
  'msg_select_delete_cancel_keeps_message' => _mselDeleteCancelKeepsMessage(
    a,
    toxB,
  ),
  'msg_select_delete_for_me_removes_row' => _mselDeleteForMeRemovesRow(a, toxB),
  'msg_select_forward_surface' => _mselForwardSurface(a, toxB),
  _ => throw ArgumentError('unsupported multi-select scenario: $scenario'),
};

/// Both peers home + friends, reusing an existing friendship. Same shape as
/// `_msEnsureFriendship` in the mobile-shell driver.
Future<({String toxA, String toxB})?> _mselEnsureFriendship(
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
    print('[pair] msg-select: missing tox ids (A=$toxA B=$toxB)');
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

// ===========================================================================
// Shared preconditions
// ===========================================================================

/// Seed ONE inbound CUSTOM bubble into A's C2C conversation with [toxB] and
/// return its message id, or null when the seed / render never landed.
///
/// Custom (not text) on purpose: the fork strips the multi-select menu entry
/// from text and media bubbles, so a text probe would produce a case that can
/// only ever report "multiSelect absent".
Future<String?> _mselSeedCustomBubble(Inst a, String toxB, String label) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] $label: could not open the C2C chat');
    return null;
  }
  final before = await _p2kRenderMessageIds(a, toxB);
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final customData = '{"type":"msg_select_probe","nonce":$nonce}';
  var marked = false;
  try {
    await a.markAccountTest();
    marked = true;
    final inject = await a.l3('l3_inject_c2c_custom', {
      'fromUserId': toxB,
      'data': customData,
    });
    if (inject['ok'] != true || inject['ingested'] != true) {
      print('[pair] $label: custom inject failed: $inject');
      return null;
    }
  } on DriveError catch (e) {
    print('[pair] $label: custom inject seam error: ${e.message}');
    return null;
  } finally {
    if (marked) {
      await a.unmarkAccountTest();
    }
  }
  final history = await _p2kWaitC2cMessageWhere(
    a,
    toxB,
    (m) =>
        m['isSelf'] == false &&
        m['mediaKind']?.toString() == 'custom' &&
        m['text']?.toString() == customData,
    timeoutSecs: 12,
  );
  final msgId = _p2kMessageId(history);
  if (msgId.isEmpty) {
    print('[pair] $label: seeded custom message never reached history');
    return null;
  }
  final rendered = await _p2kWaitRenderMessageWhere(
    a,
    toxB,
    (m) => _p2kMessageId(m) == msgId,
    excludeIds: before,
    timeoutSecs: 12,
  );
  if (rendered == null ||
      !await a.waitKey('message_list_item:$msgId', timeoutSecs: 8)) {
    print('[pair] $label: seeded custom row did not render (id=$msgId)');
    return null;
  }
  return msgId;
}

/// Open [msgId]'s REAL message menu and tap `message_menu_item:multiSelect`.
///
/// Returns true when select mode came up (the header counter mounted) and false
/// on any failure — INCLUDING "the menu offers no multiSelect item". That last
/// one used to SKIP; see the file header for why it is a hard FAIL now (the
/// custom bubble is the only surviving entry point into select mode, so losing
/// it silently deletes the coverage of every case in this file).
Future<bool> _mselEnterSelectMode(Inst a, String msgId, String label) async {
  if (!await _openMessageMenuReal(a, msgId)) {
    print('[pair] $label: the message menu did not open for $msgId');
    return false;
  }
  if (!await a.waitKeyCenter('message_menu_item:multiSelect', timeoutSecs: 4)) {
    // Dump what the menu DID offer: the difference between "the fork dropped
    // _uikit_multi_message" and "this row rendered the wrong bubble type" is
    // the whole diagnosis, and the menu is gone by the time anyone reads this.
    final offered = await _mselMenuItemIds(a);
    await _dismissMessageMenu(a);
    print(
      '[pair] $label: FAIL — the message menu for the seeded CUSTOM bubble has '
      'no multiSelect entry, so select mode is UNREACHABLE and nothing in this '
      'file can be asserted. The custom bubble is the last bubble type that '
      'keeps `_uikit_multi_message` (tencent_cloud_chat_message_item_with_menu_'
      'container.dart strips it for text and for file/image/video/sound), so '
      'this is a product/fork regression, not an environment gap. Check (a) '
      'that `enableMessageSelect` is still true in the message menu config '
      '(lib/ui/home_page_bootstrap.dart pins it on) and (b) that no new '
      'removeWhere block in the fork\'s menu container drops '
      '_uikit_multi_message for custom messages. Menu items actually offered: '
      '${offered.isEmpty ? '<none resolved>' : offered.join(', ')}',
    );
    return false;
  }
  if (!await a.tapKeyCenter('message_menu_item:multiSelect', timeoutSecs: 4)) {
    await _dismissMessageMenu(a);
    print('[pair] $label: multiSelect item could not be tapped');
    return false;
  }
  // The fork defers `inSelectMode = true` by 150 ms after the tap; the header
  // then slides in through a 300-500 ms AnimatedSwitcher.
  final up = await a.waitKeyCenter('message_select_count_text', timeoutSecs: 8);
  if (!up) {
    await _dismissMessageMenu(a);
    print('[pair] $label: select mode never came up after tapping multiSelect');
    return false;
  }
  // ...and the BOTTOM half of the surface is a SEPARATE, slower animation that
  // the header says nothing about. The mobile composer swaps in the select-mode
  // toolbar through its own AnimatedSwitcher whose transitionBuilder slides
  // from `Offset(1, 0)` (`..._message_input_mobile.dart:972-983`), so the
  // toolbar flies in from the right edge while the header is already up.
  //
  // Gating only on the header made every toolbar tap a RACE against that slide,
  // and a coordinate tap loses it: the centre is resolved over one RPC and the
  // pointer dispatched over the next, by which time the button has moved. Live
  // on Android `message_select_delete_button` resolved at x=419.4 / x=200.8 for
  // a button that settles at x=40.0 — the pointer landed on empty space, no
  // error was raised anywhere, and the case reported "the dialog never mounted".
  // That is what produced the intermittent reds here (and, on iPad, the
  // "forward sheet never mounted" report). Waiting for the toolbar's centre to
  // STOP MOVING removes the race at its source, for every case in this file and
  // on every platform, instead of papering over it with per-case retries.
  final settled = await a.waitKeyCenterSettled(
    'message_select_delete_button',
    timeoutSecs: 10,
  );
  if (settled == null) {
    print(
      '[pair] $label: the select-mode toolbar never settled — '
      '${describeKeyCenter(await a.keyCenterDetail('message_select_delete_button'))}',
    );
    return false;
  }
  return true;
}

/// The `message_menu_item:*` action ids the CURRENTLY OPEN menu is showing.
///
/// Diagnostic only, and deliberately best-effort: it exists so the FAIL above
/// can say WHICH items survived when multiSelect did not (a menu that shows
/// copy/delete but no multiSelect is a strip-rule regression; a menu that shows
/// nothing at all means the probe long-pressed the wrong row). Never throws —
/// an empty list just means the structured dump was unavailable.
Future<List<String>> _mselMenuItemIds(Inst a) async {
  const prefix = 'message_menu_item:';
  try {
    final r = await a.skill('interactiveStructured', const {});
    final data = r['data'];
    final elements = data is Map ? data['elements'] : null;
    if (elements is! List) return const <String>[];
    final ids = <String>{};
    for (final e in elements) {
      if (e is! Map) continue;
      final key = e['key']?.toString() ?? '';
      if (key.startsWith(prefix)) ids.add(key.substring(prefix.length));
    }
    return ids.toList()..sort();
  } on Object catch (e) {
    print('[pair] msg-select: menu-item dump unavailable: $e');
    return const <String>[];
  }
}

/// Best-effort teardown: leave select mode and dismiss anything modal that a
/// half-finished case may have left up. Never asserts — the cases do that.
Future<void> _mselForceLeaveSelectMode(Inst a) async {
  try {
    for (final key in const [
      'message_select_delete_cancel_button',
      'forward_picker_cancel_button',
    ]) {
      if (await a.keyCenter(key) != null) {
        await a.tapKeyCenter(key, timeoutSecs: 4);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    if (await a.keyCenter('message_select_forward_individually_item') != null) {
      await _dismissMessageMenu(a);
    }
    if (await a.keyCenter('message_select_cancel_button') != null) {
      await a.tapKeyCenter('message_select_cancel_button', timeoutSecs: 4);
      await a.waitKeyGone('message_select_count_text', timeoutSecs: 6);
    }
  } on Object catch (e) {
    // Teardown must never turn a passing case red; the next case re-asserts the
    // surface it needs from scratch.
    print('[pair] msg-select: teardown best-effort: $e');
  }
}

/// True while [msgId] is still in A's C2C history with [toxB] — the DATA-layer
/// half of "the message survived", distinct from the row being in the tree.
Future<bool> _mselMessageInHistory(Inst a, String toxB, String msgId) async {
  final found = await _p2kWaitC2cMessageWhere(
    a,
    toxB,
    (m) => _p2kMessageId(m) == msgId,
    timeoutSecs: 2,
  );
  return found != null;
}

/// Poll until [msgId] is no longer in A's C2C history with [toxB].
Future<bool> _mselWaitMessageGoneFromHistory(
  Inst a,
  String toxB,
  String msgId, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (!await _mselMessageInHistory(a, toxB, msgId)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}
