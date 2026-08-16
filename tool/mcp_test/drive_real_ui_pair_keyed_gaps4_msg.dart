// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Keyed-gaps batch #4 — the SELECT-MODE half. Spine and dispatch live in
// `drive_real_ui_pair_keyed_gaps4.dart`; this file holds only case bodies so
// each part stays under the 500-LOC complexity cap. One library.
//
// Both cases reuse `sweep_msg_select`'s preconditions verbatim
// (`_mselSeedCustomBubble` + `_mselEnterSelectMode`): a CUSTOM bubble is still
// the only message type the fork has not stripped `_uikit_multi_message` from,
// so it is the only door into select mode.

// ===========================================================================
// case — msg_select_clear_button_resets_count
// ===========================================================================
/// The select-mode header's `message_select_clear_button` — keyed with the
/// multi-select batch, never driven by any scenario.
///
/// WHAT IT DOES. `onClearSelect` is
/// `() => dataProvider.selectedMessages = []`
/// (tencent_cloud_chat_message_header_container.dart:257) — it empties the
/// SELECTION but leaves select mode up. Its neighbour `onCancelSelect` is
/// `() => dataProvider.inSelectMode = false` (:256). The two sit side by side
/// in the same header row, so the regression this case exists to catch is Clear
/// being wired to (or falling through to) Cancel's callback.
///
/// WHAT IS ASSERTED — two independent observables, neither of which a
/// "the tap did not throw" check could produce:
///
///   1. Select mode is STILL UP after Clear: `message_select_count_text` (the
///      header) and `message_select_delete_button` (the toolbar that REPLACED
///      the composer) both still resolve. That is the Clear-vs-Cancel
///      distinction, and presence of those keys IS `inSelectMode` — nothing in
///      `l3_dump_state` exposes the flag.
///   2. The SELECTION is genuinely empty: the case then drives the REAL delete
///      flow (toolbar delete -> `message_select_delete_confirm_button`) and the
///      seeded message SURVIVES in both the widget tree and the conversation
///      history. `onDeleteForMe(widget.data.messages)` is handed exactly the
///      selection, so with an emptied selection it has nothing to delete —
///      whereas the identical sequence WITHOUT Clear removes the row, which
///      `msg_select_delete_for_me_removes_row` already proves. A Clear that
///      silently kept the selection would delete the message here and red this
///      case.
///
/// The counter's rendered VALUE is printed as a breadcrumb only: a bare `Text`'s
/// key is not reliably surfaced by flutter_skill's `interactiveStructured` (the
/// same caveat `msg_select_enter_and_cancel` and `_waitChatHeaderTitle`
/// document), so gating on it would make the case flaky rather than strict.
///
/// Non-destructive by construction: the one deletion attempt is of an EMPTY
/// selection, and the probe bubble the case seeded seconds earlier is the thing
/// asserted to survive.
Future<bool?> _kg4SelectClearResetsCount(Inst a, String toxB) async {
  const label = 'msg_select_clear_button_resets_count';
  const clearKey = 'message_select_clear_button';
  final msgId = await _mselSeedCustomBubble(a, toxB, label);
  if (msgId == null) return false;
  if (!await _mselEnterSelectMode(a, msgId, label)) return false;

  final countBefore = await _keyedText(a, 'message_select_count_text');
  // Wait for the Clear button's centre to STOP MOVING, not merely to resolve.
  // The select-mode HEADER slides in through an AnimatedSwitcher, so a centre
  // resolved on one RPC and tapped on the next can land on stale coordinates —
  // the same race `_mselEnterSelectMode` already removes for the bottom
  // toolbar. Live symptom (iPad, 2 of 3 attempts on 2026-08-16): the tap missed
  // Clear and select mode simply exited, which reads as a product regression it
  // is not. Clear and Cancel sit ~240pt apart in the same Row.
  final settledClear = await a.waitKeyCenterSettled(clearKey, timeoutSecs: 10);
  if (settledClear == null) {
    await _mselForceLeaveSelectMode(a);
    print(
      '[pair] $label: the select-mode header rendered no settled Clear '
      'affordance ($clearKey). It is unconditional in '
      'tencent_cloud_chat_message_header_select_mode.dart, so this is a fork '
      'regression rather than a build-config gap. '
      '${describeKeyCenter(await a.keyCenterDetail(clearKey))}',
    );
    return false;
  }
  // TAP THE COORDINATES WE JUST SETTLED — do not re-resolve through a DIFFERENT
  // resolver.
  //
  // The settle above reads `ui_key_center` (resolveKeyCenter: the element tree).
  // `tapKeyCenter` then performed its OWN, INDEPENDENT resolution through
  // flutter_skill's `interactiveStructured` and tapped THAT, so the centre this
  // case validated as stable was never the one dispatched — the settle bought
  // nothing. Live on Android (phone shell, 2026-08-16) that second resolution
  // landed on `message_select_cancel_button` instead of Clear: select mode
  // simply exited and the post-tap screenshot shows the ordinary chat header and
  // composer restored, which reads as a product regression it is NOT
  // (`onClearSelect` is `selectedMessages = []`; nothing in the fork clears
  // `inSelectMode` on an empty selection — the only non-Cancel writer is
  // `onDeleteForMe`). The sibling `msg_select_enter_and_cancel` passes on the
  // same shell because Cancel is the RIGHT-hand button, so a mis-resolution that
  // drifts toward Cancel is invisible there and fatal only here.
  //
  // Dispatching the settled point keeps this a real coordinate tap on the real
  // control; it does not weaken the assertion. Element-resolved `skill('tap')`
  // is deliberately NOT used: it fires the callback TWICE (see `tapKeyCenter`'s
  // doc), which would hide a Clear/Cancel mis-wiring behind a second invocation.
  final cancelCentreBefore = describeKeyCenter(
    await a.keyCenterDetail('message_select_cancel_button'),
  );
  await a.tapAt(
    (settledClear['x'] as num).toDouble(),
    (settledClear['y'] as num).toDouble(),
  );
  await Future<void>.delayed(const Duration(milliseconds: 600));

  // --- Observable 1: Clear is not Cancel. ---
  final headerStillUp = await a.waitKeyCenter(
    'message_select_count_text',
    timeoutSecs: 6,
  );
  final toolbarStillUp = await a.waitKeyCenter(
    'message_select_delete_button',
    timeoutSecs: 6,
  );
  final countAfter = await _keyedText(a, 'message_select_count_text');
  await a.shot('/tmp/ui_kg4_select_clear_${a.name}.png');
  if (!headerStillUp || !toolbarStillUp) {
    // DIAGNOSIS, not an assertion (same discipline as `_preloginProbeVerdict`).
    // "Select mode left" has two very different causes and the boolean pair
    // above cannot tell them apart:
    //   (a) PRODUCT — Clear's `onClearSelect` really does more than
    //       `selectedMessages = []`, or something reacts to an empty selection
    //       by clearing `inSelectMode`; then Cancel is gone too and the tap
    //       landed where we aimed.
    //   (b) HARNESS — the coordinate tap MISSED Clear and hit
    //       `message_select_cancel_button` (or a row) instead. The header is an
    //       AnimatedSwitcher child and the two buttons are ~240pt apart in the
    //       right pane of the iPad master-detail shell, so an off-target tap is
    //       a live possibility, not a theoretical one.
    // Report the resolved centres of BOTH buttons plus the live count so the
    // next reader gets the answer instead of another campaign round-trip.
    final clearCentre = describeKeyCenter(await a.keyCenterDetail(clearKey));
    final cancelCentre = describeKeyCenter(
      await a.keyCenterDetail('message_select_cancel_button'),
    );
    await _mselForceLeaveSelectMode(a);
    print(
      '[pair] $label: FAIL — select mode LEFT after Clear '
      '(header=$headerStillUp toolbar=$toolbarStillUp). Clear must only empty '
      'the selection (`selectedMessages = []`); exiting select mode is '
      'Cancel\'s job (`inSelectMode = false`). '
      'count before="$countBefore" after="$countAfter" '
      // The PRE-tap centres are the ones that matter: post-tap both buttons are
      // unmounted, so the old pair printed `<unresolved> <unresolved>` and said
      // nothing. `tappedClear` is the exact point dispatched — compare it with
      // `cancelBefore` to see at a glance whether the tap drifted onto Cancel.
      'tappedClear=(${settledClear['x']}, ${settledClear['y']}) '
      'cancelBefore=$cancelCentreBefore '
      'clearCentreAfter=$clearCentre cancelCentreAfter=$cancelCentre',
    );
    return false;
  }

  // --- Observable 2: the selection really is empty. ---
  if (!await a.tapKeyCenter('message_select_delete_button', timeoutSecs: 6)) {
    await _mselForceLeaveSelectMode(a);
    print('[pair] $label: the toolbar delete affordance could not be tapped');
    return false;
  }
  if (!await a.waitKeyCenter(
    'message_select_delete_confirm_button',
    timeoutSecs: 8,
  )) {
    await _mselForceLeaveSelectMode(a);
    print(
      '[pair] $label: the multi-select delete dialog never opened, so the '
      '"empty selection" half could not be asserted',
    );
    return false;
  }
  if (!await a.tapKeyCenter(
    'message_select_delete_confirm_button',
    timeoutSecs: 6,
  )) {
    await _mselForceLeaveSelectMode(a);
    print('[pair] $label: the delete confirm button could not be tapped');
    return false;
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  final rowSurvives = await a.waitKey(
    'message_list_item:$msgId',
    timeoutSecs: 10,
  );
  final historySurvives = await _mselMessageInHistory(a, toxB, msgId);
  await _mselForceLeaveSelectMode(a);

  print(
    '[pair] $label: countBefore=$countBefore countAfter=$countAfter '
    'headerStillUp=$headerStillUp toolbarStillUp=$toolbarStillUp '
    'rowSurvives=$rowSurvives historySurvives=$historySurvives',
  );
  return rowSurvives && historySurvives;
}

// ===========================================================================
// case — msg_select_forward_combined_absent_gating
// ===========================================================================
/// `message_select_forward_combined_button` (tablet/desktop) and
/// `message_select_forward_combined_item` (the phone bottom sheet) are keyed but
/// can never render today: toxee pins `enableMessageForwardCombined` to false in
/// the select-mode container until the merger-elem protocol exists.
///
/// WHAT IS ASSERTED — a GATING PAIR, i.e. two renders of the SAME `if` chain:
/// the *individually* affordance MOUNTS (the positive leg, which proves the
/// forward surface is genuinely up and that the case is looking at the right
/// widget) while its *combined* twin is ABSENT. A bare "combined is missing"
/// probe would pass against a chat with no forward surface at all, or against a
/// mis-navigated screen — which is exactly the class of vacuous assertion this
/// batch refuses.
///
/// FORM FACTOR IS DETECTED, NOT ASSUMED. `defaultBuilder` (phone) renders ONE
/// forward icon that opens a bottom sheet holding the two per-type rows;
/// `tabletAppBuilder` / `desktopBuilder` render the per-type BUTTONS inline.
/// The case looks for whichever is mounted, so a narrowed desktop window (still
/// the desktop builder) does not red it.
///
/// FAIL — not skip — when neither forward affordance resolves. There is no
/// build in which both flags are off (Individually is pinned true at the app
/// AND fork-default layer), so that branch can only mean the select-mode toolbar
/// did not mount. Nothing is ever forwarded — the sheet is dismissed and select
/// mode left — so no state escapes the case.
Future<bool?> _kg4ForwardCombinedGating(Inst a, String toxB) async {
  const label = 'msg_select_forward_combined_absent_gating';
  const sheetOpener = 'message_select_forward_button';
  const inlineIndividually = 'message_select_forward_individually_button';
  const inlineCombined = 'message_select_forward_combined_button';
  const sheetIndividually = 'message_select_forward_individually_item';
  const sheetCombined = 'message_select_forward_combined_item';

  final msgId = await _mselSeedCustomBubble(a, toxB, label);
  if (msgId == null) return false;
  if (!await _mselEnterSelectMode(a, msgId, label)) return false;

  final hasInline = await a.waitKeyCenter(inlineIndividually, timeoutSecs: 5);
  if (hasInline) {
    // --- tablet / desktop: the per-type buttons are inline. ---
    final combined = await a.waitKeyCenter(inlineCombined, timeoutSecs: 2);
    await a.shot('/tmp/ui_kg4_fwd_inline_${a.name}.png');
    await _mselForceLeaveSelectMode(a);
    print(
      '[pair] $label: surface=inline individuallyMounted=$hasInline '
      'combinedMounted=$combined',
    );
    if (combined) {
      print(
        '[pair] $label: FAIL — the COMBINED forward button rendered. toxee pins '
        '`enableMessageForwardCombined` to false in '
        'tencent_cloud_chat_message_input_select_mode_container.dart until the '
        'merger-elem protocol lands; if that pin was deliberately flipped, this '
        'case must be rewritten to drive the combined path instead of gating '
        'on its absence.',
      );
    }
    return !combined;
  }

  final hasSheetOpener = await a.waitKeyCenter(sheetOpener, timeoutSecs: 4);
  if (!hasSheetOpener) {
    await a.shot('/tmp/ui_kg4_fwd_noaffordance_${a.name}.png');
    await _mselForceLeaveSelectMode(a);
    print(
      '[pair] $label: FAIL — the multi-select toolbar rendered NO forward '
      'affordance at all (neither $inlineIndividually nor $sheetOpener). This '
      'used to SKIP on the claim that both forward flags are off in this build. '
      'That claim is FALSE by construction and the SKIP was unreachable: '
      '`enableMessageForwardIndividually` is pinned TRUE '
      '(lib/ui/home_page_bootstrap.dart:683, and the fork\'s own '
      'TencentCloudChatMessageDefaultMessageSelectionOptionsConfig default is '
      'true too), the phone builder gates its single icon on '
      '`enableMessageForwardCombined || enableMessageForwardIndividually` '
      '(..._input_select_mode.dart:190 = false || true = ALWAYS true) and the '
      'tablet/desktop builders gate on Individually alone. The identical SKIP '
      'was already retracted for `_mselForwardSurface` '
      '(drive_real_ui_pair_msg_select.dart:37-56). The only thing that reaches '
      'this branch is the select-mode toolbar failing to mount — a product/fork '
      'regression.',
    );
    return false;
  }
  // --- phone: one icon opens the forward-type bottom sheet. ---
  if (!await a.tapKeyCenter(sheetOpener, timeoutSecs: 6)) {
    await _mselForceLeaveSelectMode(a);
    print('[pair] $label: the forward icon could not be tapped');
    return false;
  }
  final individuallyRow = await a.waitKeyCenter(
    sheetIndividually,
    timeoutSecs: 8,
  );
  final combinedRow = await a.waitKeyCenter(sheetCombined, timeoutSecs: 2);
  await a.shot('/tmp/ui_kg4_fwd_sheet_${a.name}.png');
  // Dismiss WITHOUT forwarding: neither row is tapped, so nothing is sent.
  await _dismissMessageMenu(a);
  final sheetGone = await _kg4WaitKeyCenterGone(a, sheetIndividually);
  await _mselForceLeaveSelectMode(a);

  print(
    '[pair] $label: surface=sheet individuallyRow=$individuallyRow '
    'combinedRow=$combinedRow sheetGone=$sheetGone',
  );
  if (!individuallyRow) {
    print(
      '[pair] $label: FAIL — the forward sheet opened but showed no '
      '"individually" row, so the positive leg of the gate is missing and the '
      'absent combined row proves nothing.',
    );
    return false;
  }
  return !combinedRow;
}
