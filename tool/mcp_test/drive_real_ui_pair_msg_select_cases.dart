// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// MESSAGE MULTI-SELECT case bodies. Split out of
// drive_real_ui_pair_msg_select.dart (which keeps the dispatch, the sweep,
// and the shared preconditions) purely so both halves stay under the 500-LOC
// complexity cap — they are one library, so this is organizational only. See
// that file's header for WHY the multi-select surface needs a CUSTOM bubble
// and for the assertion discipline every case below follows.

// ===========================================================================
// msg_select_enter_and_cancel — the select-mode state machine itself
// ===========================================================================
/// Enter select mode from the REAL menu entry and leave it through the REAL
/// header Cancel button.
///
/// OBSERVABLE SIDE EFFECT: entering select mode swaps BOTH ends of the chat
/// surface — the header becomes the select bar (`message_select_count_text` +
/// `message_select_cancel_button` mount) and the composer becomes the
/// multi-select toolbar (`message_select_delete_button` mounts). Cancelling must
/// take all three back OUT of the tree. Presence/absence of those keys IS the
/// `inSelectMode` flag; nothing else in the dump exposes it.
Future<bool?> _mselEnterAndCancel(Inst a, String toxB) async {
  const label = 'msg_select_enter_and_cancel';
  final msgId = await _mselSeedCustomBubble(a, toxB, label);
  if (msgId == null) return false;
  if (!await _mselEnterSelectMode(a, msgId, label)) return false;

  final toolbar = await a.waitKeyCenter(
    'message_select_delete_button',
    timeoutSecs: 8,
  );
  final cancelUp = await a.waitKeyCenter(
    'message_select_cancel_button',
    timeoutSecs: 4,
  );
  // Advisory: a bare Text's key is not always surfaced by interactiveStructured,
  // so the counter's VALUE is a breadcrumb, not the gate (the same rule
  // `unread_badge_total_sidebar` documents for the badge text).
  final countText = await _keyedText(a, 'message_select_count_text');
  await a.shot('/tmp/ui_msg_select_enter_${_realUiPlatform}_${a.name}.png');

  if (!cancelUp) {
    print('[pair] $label: the select-mode header Cancel never mounted');
    return false;
  }
  if (!await a.tapKeyCenter('message_select_cancel_button', timeoutSecs: 6)) {
    print('[pair] $label: the header Cancel button could not be tapped');
    return false;
  }
  final headerGone = await a.waitKeyGone(
    'message_select_count_text',
    timeoutSecs: 8,
  );
  final toolbarGone = await a.waitKeyGone(
    'message_select_delete_button',
    timeoutSecs: 8,
  );
  print(
    '[pair] $label: toolbarUp=$toolbar countText=$countText '
    'headerGone=$headerGone toolbarGone=$toolbarGone',
  );
  return toolbar && headerGone && toolbarGone;
}

// ===========================================================================
// msg_select_delete_cancel_keeps_message — the NEGATIVE half of delete
// ===========================================================================
/// Open the multi-select delete dialog and CANCEL it: the dialog must close, the
/// message must survive in BOTH the widget tree and the conversation history,
/// and select mode must still be up (only `onDeleteForMe` leaves it).
///
/// This is the assertion that a "did the tap work" style case would miss: the
/// fork's cancel branch shares a `handled` latch with the confirm branch, so a
/// regression there deletes on Cancel.
Future<bool?> _mselDeleteCancelKeepsMessage(Inst a, String toxB) async {
  const label = 'msg_select_delete_cancel_keeps_message';
  final msgId = await _mselSeedCustomBubble(a, toxB, label);
  if (msgId == null) return false;
  if (!await _mselEnterSelectMode(a, msgId, label)) return false;

  final dialogUp = await _mselOpenDeleteDialog(
    a,
    label,
    'message_select_delete_cancel_button',
  );
  final confirmUp = await a.waitKeyCenter(
    'message_select_delete_confirm_button',
    timeoutSecs: 3,
  );
  await a.shot('/tmp/ui_msg_select_delete_dialog_${_realUiPlatform}_${a.name}.png');
  if (!dialogUp) {
    print('[pair] $label: the delete confirmation dialog never mounted');
    return false;
  }
  if (!await a.tapKeyCenter(
    'message_select_delete_cancel_button',
    timeoutSecs: 6,
  )) {
    print('[pair] $label: the dialog Cancel could not be tapped');
    return false;
  }
  final dialogGone = await a.waitKeyGone(
    'message_select_delete_cancel_button',
    timeoutSecs: 8,
  );
  final rowSurvived = await a.waitKey(
    'message_list_item:$msgId',
    timeoutSecs: 6,
  );
  final historySurvived = await _mselMessageInHistory(a, toxB, msgId);
  final stillSelecting =
      await a.keyCenter('message_select_count_text') != null;
  print(
    '[pair] $label: dialogUp=$dialogUp confirmUp=$confirmUp '
    'dialogGone=$dialogGone rowSurvived=$rowSurvived '
    'historySurvived=$historySurvived stillSelecting=$stillSelecting',
  );
  return confirmUp &&
      dialogGone &&
      rowSurvived &&
      historySurvived &&
      stillSelecting;
}

// ===========================================================================
// msg_select_delete_for_me_removes_row — the POSITIVE half of delete
// ===========================================================================
/// Confirm the multi-select delete and assert the full effect chain: the dialog
/// closes, select mode exits by itself (`onDeleteForMe` sets
/// `inSelectMode = false` before deleting), the row leaves the widget tree, and
/// the message leaves the conversation history.
///
/// DESTRUCTIVE ONLY TO ITS OWN PROBE: the deleted message is the throwaway
/// custom bubble this case seeded moments earlier, so it neither touches real
/// conversation content nor changes the friendship state.
Future<bool?> _mselDeleteForMeRemovesRow(Inst a, String toxB) async {
  const label = 'msg_select_delete_for_me_removes_row';
  final msgId = await _mselSeedCustomBubble(a, toxB, label);
  if (msgId == null) return false;
  if (!await _mselEnterSelectMode(a, msgId, label)) return false;

  if (!await _mselOpenDeleteDialog(
    a,
    label,
    'message_select_delete_confirm_button',
  )) {
    print(
      '[pair] $label: the delete dialog never offered its confirm action '
      '(enableMessageDeleteForSelf is pinned true in '
      'lib/ui/home_page_bootstrap.dart, so this is the dialog failing to '
      'mount, not a config gate) — nothing to drive',
    );
    return false;
  }
  if (!await a.tapKeyCenter(
    'message_select_delete_confirm_button',
    timeoutSecs: 6,
  )) {
    print('[pair] $label: the dialog Confirm could not be tapped');
    return false;
  }
  final dialogGone = await a.waitKeyGone(
    'message_select_delete_confirm_button',
    timeoutSecs: 8,
  );
  final selectModeExited = await a.waitKeyGone(
    'message_select_count_text',
    timeoutSecs: 10,
  );
  // "The row left the SCREEN", asserted through the onstage flag rather than
  // through key ABSENCE. Live on iPad 2026-08-16 the deleted bubble was gone
  // from the screenshot AND gone from history, yet both `waitKeyGone`
  // (flutter_skill's index) and a plain `ui_key_center` resolve still reported
  // `message_list_item:<id>` present: the UIKit message list retains a
  // measurement copy of the removed row, which is laid out with positive
  // bounds and no hiding ancestor. `onstage` separates the two — the visible
  // row resolves through the onstage walk, the retained copy only through the
  // full-tree fallback. A row that is still really on screen would report
  // `onstage:true` and still red the case.
  var rowGone = false;
  bool? rowOnstage;
  final rowDeadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(rowDeadline)) {
    rowOnstage = await _kg3KeyOnstage(a, 'message_list_item:$msgId');
    if (rowOnstage != true) {
      rowGone = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  final historyGone = await _mselWaitMessageGoneFromHistory(a, toxB, msgId);
  await a.shot('/tmp/ui_msg_select_deleted_${_realUiPlatform}_${a.name}.png');
  print(
    '[pair] $label: dialogGone=$dialogGone selectModeExited=$selectModeExited '
    'rowGone=$rowGone (rowOnstage=$rowOnstage) historyGone=$historyGone '
    '(msgId=$msgId) '
    // The `rowGone`/`historyGone` PAIR is the diagnosis, so print the row's
    // full resolution beside it: `historyGone=true rowGone=false` isolates the
    // fault to the UIKit list removal (the fork's msgID gate) rather than to
    // the delete itself, while BOTH false means the delete genuinely no-op'd
    // one layer down (platform / FfiChatService).
    'row[${describeKeyCenter(await a.keyCenterDetail('message_list_item:$msgId'))}]',
  );
  return dialogGone && selectModeExited && rowGone && historyGone;
}

/// Tap the multi-select delete button and wait for [dialogKey] to mount.
///
/// SHARED by both delete cases so the diagnosis lives in one place. `Inst.
/// tapKeyCenter` picks its target from `interactiveStructured` and taps the LAST
/// same-key match with positive bounds — and that dump has NO paint/cover/
/// onstage guard, so a stale, still-laid-out copy of the select-mode toolbar
/// (the AnimatedSwitcher swaps it in and out on every select-mode entry/exit)
/// is reported exactly like the live one. When the stale copy sorts last, the
/// coordinate tap lands on a corpse: no error, no dialog, select mode still up —
/// which is precisely how this failed on Android.
///
/// So: try the coordinate tap first (unchanged happy path), and if the dialog
/// does not come up, dump the WHOLE match list plus the opener's resolved
/// geometry and retry through flutter_skill's `tap`, which resolves the ELEMENT
/// rather than a point. The log always states which path opened the dialog, so a
/// genuine regression cannot hide behind the retry. Safe: this button SHOWS a
/// dialog (it never `Navigator.pop`s), so the double-fire hazard that forces
/// `tapKeyCenter` on dialog pop-buttons does not apply here.
Future<bool> _mselOpenDeleteDialog(
  Inst a,
  String label,
  String dialogKey,
) async {
  const opener = 'message_select_delete_button';
  final before = await a.keyCenterDetail(opener);
  if (!await a.tapKeyCenter(opener, timeoutSecs: 8)) {
    print(
      '[pair] $label: the multi-select delete button could not be tapped '
      'center[${describeKeyCenter(before)}]',
    );
    return false;
  }
  if (await a.waitKeyCenter(dialogKey, timeoutSecs: 8)) return true;
  final matches = await describeKeyMatches(a, opener);
  final retry = await a.tryTapKeyDetailed(opener, retries: 2);
  final opened = await a.waitKeyCenter(dialogKey, timeoutSecs: 8);
  print(
    '[pair] $label: the coordinate tap on $opener did NOT open $dialogKey '
    'center[${describeKeyCenter(before)}] '
    'skillMatches=${matches.length}'
    '${matches.isEmpty ? '' : ' [${matches.join(' | ')}]'} '
    'retryTap[${describeTapResult(retry.result)}] retryOpened=$opened',
  );
  return opened;
}

// ===========================================================================
// msg_select_forward_surface — the multi-select forward entry point
// ===========================================================================
/// Drive the toolbar's forward affordance for whichever builder is on screen and
/// assert the REAL forward target picker opens, then close it with the picker's
/// own Cancel.
///
/// The two builder shapes are DETECTED, not guessed:
///   * phone `defaultBuilder` — one `message_select_forward_button` that opens a
///     bottom sheet; the sheet's `message_select_forward_individually_item` is
///     what actually calls `onMessagesForward`.
///   * tablet/desktop — `message_select_forward_individually_button` calls it
///     directly (no sheet).
/// Combined forward is intentionally not driven: toxee pins
/// `enableMessageForwardCombined` to false until the merger-elem protocol exists,
/// so its button/sheet row never renders.
///
/// NO SKIP BRANCH — "no forward affordance" is a hard FAIL. The old SKIP claimed
/// both forward flags could be off in this build; in toxee they cannot be. The
/// phone `defaultBuilder` gates its icon on
/// `enableMessageForwardCombined || enableMessageForwardIndividually`
/// (select_mode.dart:190) and toxee pins Individually to `true`
/// (`lib/ui/home_page_bootstrap.dart:683`, matching the fork's own default),
/// so the disjunction is `false || true` — always true. A toolbar with no
/// forward control therefore cannot mean "config off"; it can only mean the
/// toolbar never mounted, which is exactly the regression this case exists to
/// catch. Nothing is forwarded, so the conversation is unchanged when the case
/// ends.
Future<bool?> _mselForwardSurface(Inst a, String toxB) async {
  const label = 'msg_select_forward_surface';
  final msgId = await _mselSeedCustomBubble(a, toxB, label);
  if (msgId == null) return false;
  if (!await _mselEnterSelectMode(a, msgId, label)) return false;

  // WAIT for an affordance instead of probing once. The select-mode toolbar
  // replaces the composer through an AnimatedSwitcher, so a single instant
  // `keyCenter` right after `_mselEnterSelectMode` can read the tree a frame
  // early and take the SKIP branch on a race — which is exactly what happened
  // on iPad 2026-08-16 (attempt 1 "no forward affordance", attempt 2 found the
  // phone opener in the same build). A SKIP that can fire on a timing race is
  // indistinguishable from a real "the build has no forward control", so it has
  // to be a real wait.
  var phoneSheetOpener = false;
  var directForward = false;
  final affordanceDeadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(affordanceDeadline)) {
    phoneSheetOpener =
        await a.keyCenter('message_select_forward_button') != null;
    directForward =
        await a.keyCenter('message_select_forward_individually_button') != null;
    if (phoneSheetOpener || directForward) break;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  print(
    '[pair] $label: forward affordance probe '
    'phoneOpener=$phoneSheetOpener directIndividually=$directForward '
    'directCombined='
    '${await a.keyCenter('message_select_forward_combined_button') != null}',
  );
  if (!phoneSheetOpener && !directForward) {
    print(
      '[pair] $label: FAIL — the multi-select toolbar rendered NO forward '
      'affordance. This is NOT a config-off SKIP: the phone builder gates its '
      'icon on `enableMessageForwardCombined || enableMessageForwardIndividually` '
      '(select_mode.dart:190) and toxee pins Individually to true '
      '(lib/ui/home_page_bootstrap.dart:683 + the fork default), so that '
      'disjunction is always true and the icon MUST mount whenever the toolbar '
      'does. The only remaining diagnosis is that the select-mode toolbar itself '
      'never built (or built without its Row children) — a product/fork '
      'regression. deleteButton='
      '${describeKeyCenter(await a.keyCenterDetail('message_select_delete_button'))}',
    );
    return false;
  }

  var sheetItemSeen = false;
  if (phoneSheetOpener) {
    if (!await a.tapKeyCenter('message_select_forward_button', timeoutSecs: 6)) {
      print('[pair] $label: the phone forward icon could not be tapped');
      return false;
    }
    sheetItemSeen = await a.waitKeyCenter(
      'message_select_forward_individually_item',
      timeoutSecs: 8,
    );
    var retryTap = <String, dynamic>{};
    if (!sheetItemSeen) {
      // Retry through flutter_skill's `tap`, which resolves the element and
      // invokes its `onPressed` in-engine. (An earlier note here blamed the
      // home-indicator gesture strip for "swallowing" the tap — that was
      // FACTUALLY WRONG and is deleted: both `tapAt` and `tap` synthesize
      // pointer events straight into `binding.handlePointerEvent`, so no OS
      // gesture strip and no IME is even in the path.) Safe here: this button
      // SHOWS a sheet (it does not `Navigator.pop`), so the double-fire hazard
      // that forces `tapKeyCenter` on dialog pop-buttons does not apply.
      final detailed = await a.tryTapKeyDetailed(
        'message_select_forward_button',
        retries: 2,
      );
      retryTap = detailed.result;
      sheetItemSeen = await a.waitKeyCenter(
        'message_select_forward_individually_item',
        timeoutSecs: 8,
      );
    }
    if (!sheetItemSeen) {
      final shot =
          '/tmp/ui_msg_select_forward_nosheet_${_realUiPlatform}_${a.name}.png';
      await a.shot(shot);
      // THE diagnostic line. Which of the three physically different failures
      // this was is only decidable from the raw `tap` payload plus the opener's
      // resolved geometry: E002 + a `position` past `viewWidth` means the
      // toolbar overflowed the device edge (a fork LAYOUT bug), `success=true`
      // with no sheet means `_showForwardOptions`'s `showModalBottomSheet` never
      // stuck (a fork WIDGET bug), and E001 means the key is not in the tree at
      // all (a DRIVER bug). Never print just the bool again.
      print(
        '[pair] $label: the forward-type bottom sheet never mounted '
        '(combinedItem='
        '${await a.keyCenter('message_select_forward_combined_item') != null}) '
        'openerTap[${describeTapResult(retryTap)}] '
        'openerCenter[${describeKeyCenter(await a.keyCenterDetail('message_select_forward_button'))}] '
        'deleteCenter[${describeKeyCenter(await a.keyCenterDetail('message_select_delete_button'))}] '
        'shot=$shot',
      );
      return false;
    }
    if (!await a.tapKeyCenter(
      'message_select_forward_individually_item',
      timeoutSecs: 6,
    )) {
      print('[pair] $label: the sheet forward-individually row was not tappable');
      return false;
    }
  } else if (!await a.tapKeyCenter(
    'message_select_forward_individually_button',
    timeoutSecs: 6,
  )) {
    print('[pair] $label: the forward-individually button could not be tapped');
    return false;
  }

  final pickerUp = await a.waitKeyCenter(
    'forward_picker_send_button',
    timeoutSecs: 12,
  );
  await a.shot('/tmp/ui_msg_select_forward_${_realUiPlatform}_${a.name}.png');
  if (!pickerUp) {
    print(
      '[pair] $label: the forward target picker did not mount after the '
      'forward tap (phoneSheet=$phoneSheetOpener)',
    );
    return false;
  }
  // Close WITHOUT forwarding: the picker's own Cancel runs the production
  // onCancel (popDialogIfCurrent / the desktop popup's close callback).
  if (!await a.tapKeyCenter('forward_picker_cancel_button', timeoutSecs: 8)) {
    print('[pair] $label: the picker Cancel could not be tapped');
    return false;
  }
  final pickerGone = await a.waitKeyGone(
    'forward_picker_send_button',
    timeoutSecs: 10,
  );
  print(
    '[pair] $label: phoneSheet=$phoneSheetOpener sheetItem=$sheetItemSeen '
    'pickerUp=$pickerUp pickerGone=$pickerGone',
  );
  return pickerGone;
}
