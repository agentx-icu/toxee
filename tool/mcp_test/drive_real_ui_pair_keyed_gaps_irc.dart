// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// APPLICATIONS / IRC case bodies for `sweep_keyed_gaps`. Split out of
// drive_real_ui_pair_keyed_gaps.dart so both halves stay under the 500-LOC
// complexity cap; see that file's header for the batch rationale.
//
// WHAT WAS DARK BEFORE THIS BATCH. `irc_join_channel_real_controls` drives the
// HAPPY path only: Add Channel → fill → Join. Everything else the Applications
// page keys was never touched — the dialog's Cancel and password-visibility
// controls, the per-channel Remove button, and the IRC card's Uninstall button
// (with both confirmation dialogs). Those are the destructive/negative halves,
// i.e. exactly the branches where a silent regression costs a user their
// channels.
//
// PRECONDITION SEAM, NOT ASSERTION SEAM. The install state and the seeded
// channel list come from `l3_irc_set_state` (test-account gated, the same seam
// the existing IRC case uses) so no case needs libirc_client or a live IRC
// server. Everything ASSERTED is driven through the real Applications-page
// controls and the real confirmation dialogs. The confirm dialogs are unkeyed
// AlertDialogs, so their actions are tapped by TEXT — through
// `_kgTapTextTopmost`, which takes the LAST match, because the IRC card's own
// "Uninstall" / "Remove" labels sit EARLIER in the tree and are covered by the
// modal barrier.
//
// STATE RESTORATION. Every case resets the local IRC prefs
// (`l3_irc_set_state {reset:true}`) and revokes the test-account marker in its
// `finally`, so the launch ends with IRC uninstalled and no channels — the same
// state `irc_join_channel_real_controls` leaves behind.

/// Seed deterministic local IRC state and land on the Applications page.
/// Returns false when the test-account marker or the seam refused (the caller
/// then reports FAIL rather than pretending the surface was driven).
Future<bool> _kgIrcPrepare(
  Inst inst,
  String label, {
  required List<String> channels,
}) async {
  if (!await inst.markAccountTest()) {
    print('[pair] $label: markAccountTest failed — l3 IRC seam is gated');
    return false;
  }
  final reset = await inst.l3('l3_irc_set_state', {'reset': true});
  if (reset['ok'] != true) {
    print('[pair] $label: l3_irc_set_state reset failed: $reset');
    return false;
  }
  final prepared = await inst.l3('l3_irc_set_state', {
    'installed': true,
    'server': 'irc.invalid.local',
    'port': 6667,
    'useSasl': false,
    'channels': jsonEncode(channels),
    'localAddOverride': true,
  });
  if (prepared['ok'] != true) {
    print('[pair] $label: l3_irc_set_state prepare failed: $prepared');
    return false;
  }
  await ensureHome(inst, '');
  if (!await inst.tapKeyCenter('sidebar_applications_tab', timeoutSecs: 4) &&
      !await inst.tapKeyCenter('bottom_nav_applications_tab', timeoutSecs: 4)) {
    print('[pair] $label: no Applications tab on this shell');
    return false;
  }
  return true;
}

/// Undo everything [_kgIrcPrepare] set up. Best-effort — a teardown failure must
/// never turn a passing case red; the next case re-seeds from `reset:true`.
Future<void> _kgIrcCleanup(Inst inst, String label) async {
  try {
    await inst.l3('l3_irc_set_state', {'reset': true});
  } on Object catch (e) {
    print('[pair] $label: IRC reset cleanup failed: $e');
  }
  try {
    await inst.unmarkAccountTest();
  } on Object catch (e) {
    print('[pair] $label: unmarkAccountTest failed: $e');
  }
  try {
    await returnToChatsHome(inst, rounds: 4);
  } on Object catch (e) {
    print('[pair] $label: return home best-effort: $e');
  }
}

/// True while [channel] is in the app's persisted IRC channel list.
Future<bool> _kgIrcStateHasChannel(Inst inst, String channel) async {
  final state = await inst.dumpState();
  return ((state['ircChannels'] as List?) ?? const [])
      .map((e) => e.toString())
      .contains(channel);
}

// ===========================================================================
// irc_channel_dialog_cancel_discards
// ===========================================================================
/// Drive the two IRC-channel-dialog controls the happy path never touches:
/// `irc_channel_dialog_password_visibility_toggle` and
/// `irc_channel_dialog_cancel_button`.
///
/// OBSERVABLE SIDE EFFECTS:
///   * the password toggle flips `obscureText`, observed through the
///     state-suffixed icon key
///     `irc_channel_dialog_password_visibility_icon_{obscured,visible}` added
///     with this case (the field's value is identical either way, so the icon
///     key is the only honest signal);
///   * Cancel DISCARDS: the dialog unmounts, NO channel tile appears for the
///     name that was typed, and `l3_dump_state.ircChannels` still does not
///     contain it. That last assertion is the one that matters — a regression
///     where Cancel fell through to `addChannel` would still close the dialog.
Future<bool?> _kgIrcChannelDialogCancelDiscards(Inst inst) async {
  const label = 'irc_channel_dialog_cancel_discards';
  final channel = '#rui-kg-cancel-${DateTime.now().microsecondsSinceEpoch}';
  if (!await _kgIrcPrepare(inst, label, channels: const [])) {
    await _kgIrcCleanup(inst, label);
    return false;
  }
  try {
    if (!await inst.waitKey(
      'applications_irc_add_channel_button',
      timeoutSecs: 10,
    )) {
      print('[pair] $label: the Add Channel button never mounted');
      return false;
    }
    if (!await inst.tapKeyCenter('applications_irc_add_channel_button')) {
      await inst.tapKey('applications_irc_add_channel_button');
    }
    if (!await inst.waitKey(
      'irc_channel_dialog_channel_field',
      timeoutSecs: 8,
    )) {
      print('[pair] $label: the channel dialog did not open');
      return false;
    }
    await inst.focusType('irc_channel_dialog_channel_field', channel);
    await inst.focusType('irc_channel_dialog_password_field', 'rui-kg-secret');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final startObscured = await inst.waitKeyCenter(
      'irc_channel_dialog_password_visibility_icon_obscured',
      timeoutSecs: 6,
    );
    if (!await inst.tapKeyCenter(
      'irc_channel_dialog_password_visibility_toggle',
      timeoutSecs: 6,
    )) {
      print('[pair] $label: the password visibility toggle was not tappable');
      return false;
    }
    final revealed = await inst.waitKeyCenter(
      'irc_channel_dialog_password_visibility_icon_visible',
      timeoutSecs: 6,
    );
    await inst.tapKeyCenter(
      'irc_channel_dialog_password_visibility_toggle',
      timeoutSecs: 6,
    );
    final hiddenAgain = await inst.waitKeyCenter(
      'irc_channel_dialog_password_visibility_icon_obscured',
      timeoutSecs: 6,
    );
    await inst.shot('/tmp/ui_kg_irc_dialog_${inst.name}.png');

    if (!await inst.tapKeyCenter(
      'irc_channel_dialog_cancel_button',
      timeoutSecs: 6,
    )) {
      print('[pair] $label: the dialog Cancel was not tappable');
      return false;
    }
    final dialogGone = await inst.waitKeyGone(
      'irc_channel_dialog_channel_field',
      timeoutSecs: 8,
    );
    final tileAbsent = !await inst.waitKey(
      'applications_irc_channel_tile:$channel',
      timeoutSecs: 4,
    );
    final stateClean = !await _kgIrcStateHasChannel(inst, channel);
    print(
      '[pair] $label: startObscured=$startObscured revealed=$revealed '
      'hiddenAgain=$hiddenAgain dialogGone=$dialogGone '
      'tileAbsent=$tileAbsent stateClean=$stateClean',
    );
    return startObscured &&
        revealed &&
        hiddenAgain &&
        dialogGone &&
        tileAbsent &&
        stateClean;
  } finally {
    await _kgIrcCleanup(inst, label);
  }
}

// ===========================================================================
// irc_channel_remove_row_confirm
// ===========================================================================
/// Drive `applications_irc_remove_channel_button:<channel>` — the per-row X on a
/// channel tile — through BOTH branches of its confirmation dialog.
///
/// OBSERVABLE SIDE EFFECTS:
///   * CANCEL — the confirm dialog closes, the `applications_irc_channel_tile`
///     row is STILL in the tree and the channel is STILL in
///     `l3_dump_state.ircChannels`. (`_handleRemoveChannel` returns early on
///     `confirmed != true`; a regression that ignored the result would delete
///     here.)
///   * REMOVE — the row leaves the tree AND the channel leaves the persisted
///     list. Both halves are required: the tile disappearing alone could be a
///     rebuild artefact, and the pref changing alone would not prove the UI
///     reflected it.
Future<bool?> _kgIrcChannelRemoveRowConfirm(Inst inst) async {
  const label = 'irc_channel_remove_row_confirm';
  const dialogTitle = 'Remove IRC Channel';
  final channel = '#rui-kg-rm-${DateTime.now().microsecondsSinceEpoch}';
  if (!await _kgIrcPrepare(inst, label, channels: [channel])) {
    await _kgIrcCleanup(inst, label);
    return false;
  }
  try {
    final tileKey = 'applications_irc_channel_tile:$channel';
    final removeKey = 'applications_irc_remove_channel_button:$channel';
    if (!await inst.waitKey(tileKey, timeoutSecs: 12)) {
      await inst.shot('/tmp/ui_kg_irc_no_tile_${inst.name}.png');
      print('[pair] $label: the seeded channel tile never rendered');
      return false;
    }

    // --- negative branch: open the confirm dialog and Cancel it. ---
    if (!await inst.tapKeyCenter(removeKey, timeoutSecs: 8)) {
      print('[pair] $label: the row Remove button was not tappable');
      return false;
    }
    final cancelDialogUp = await inst.waitText(dialogTitle, timeoutSecs: 8);
    if (!cancelDialogUp) {
      await inst.shot('/tmp/ui_kg_irc_rm_nodialog_${inst.name}.png');
      print('[pair] $label: the remove confirmation never appeared');
      return false;
    }
    final cancelTapped = await _kgTapTextTopmost(inst, 'Cancel');
    final cancelDialogGone = await inst.waitTextGone(
      dialogTitle,
      timeoutSecs: 8,
    );
    final tileSurvived = await inst.waitKey(tileKey, timeoutSecs: 6);
    final stillPersisted = await _kgIrcStateHasChannel(inst, channel);

    // --- positive branch: confirm the removal. ---
    if (!await inst.tapKeyCenter(removeKey, timeoutSecs: 8)) {
      print('[pair] $label: Remove was not tappable a second time');
      return false;
    }
    if (!await inst.waitText(dialogTitle, timeoutSecs: 8)) {
      print('[pair] $label: the remove confirmation did not reopen');
      return false;
    }
    final confirmTapped = await _kgTapTextTopmost(inst, 'Remove');
    final tileGone = await inst.waitKeyGone(tileKey, timeoutSecs: 12);
    var goneFromState = false;
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      if (!await _kgIrcStateHasChannel(inst, channel)) {
        goneFromState = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await inst.shot('/tmp/ui_kg_irc_removed_${inst.name}.png');
    print(
      '[pair] $label: cancelTapped=$cancelTapped '
      'cancelDialogGone=$cancelDialogGone tileSurvived=$tileSurvived '
      'stillPersisted=$stillPersisted confirmTapped=$confirmTapped '
      'tileGone=$tileGone goneFromState=$goneFromState',
    );
    return cancelTapped &&
        cancelDialogGone &&
        tileSurvived &&
        stillPersisted &&
        confirmTapped &&
        tileGone &&
        goneFromState;
  } finally {
    await _kgIrcCleanup(inst, label);
  }
}

// ===========================================================================
// irc_app_uninstall_reinstall_card
// ===========================================================================
/// Drive `applications_irc_card` + `applications_irc_uninstall_button` — the IRC
/// app card's destructive action — through BOTH branches of its confirmation.
///
/// OBSERVABLE SIDE EFFECTS:
///   * CANCEL — the confirm dialog closes and the card still renders the
///     UNINSTALL button (i.e. still installed), with
///     `l3_dump_state.ircInstalled == true`.
///   * UNINSTALL — the action row SWAPS: `applications_irc_uninstall_button`
///     and `applications_irc_add_channel_button` unmount and
///     `applications_irc_install_button` mounts, with
///     `l3_dump_state.ircInstalled` flipping to false. The CARD itself
///     (`applications_irc_card`) must survive both branches — it is the app
///     entry, not the install state.
///
/// The card key sits on a `_HoverableAppCard`, which flutter_skill's interactive
/// index does not surface, so it is resolved with `waitKeyCenter`
/// (element-tree walk).
Future<bool?> _kgIrcAppUninstallReinstallCard(Inst inst) async {
  const label = 'irc_app_uninstall_reinstall_card';
  const dialogTitle = 'Uninstall IRC Channel App';
  if (!await _kgIrcPrepare(inst, label, channels: const [])) {
    await _kgIrcCleanup(inst, label);
    return false;
  }
  try {
    final cardUp = await inst.waitKeyCenter(
      'applications_irc_card',
      timeoutSecs: 12,
    );
    final uninstallUp = await inst.waitKey(
      'applications_irc_uninstall_button',
      timeoutSecs: 10,
    );
    if (!cardUp || !uninstallUp) {
      await inst.shot('/tmp/ui_kg_irc_card_absent_${inst.name}.png');
      print('[pair] $label: card=$cardUp uninstallButton=$uninstallUp');
      return false;
    }

    // --- negative branch: Cancel keeps the app installed. ---
    if (!await inst.tapKeyCenter(
      'applications_irc_uninstall_button',
      timeoutSecs: 8,
    )) {
      print('[pair] $label: the Uninstall button was not tappable');
      return false;
    }
    if (!await inst.waitText(dialogTitle, timeoutSecs: 8)) {
      await inst.shot('/tmp/ui_kg_irc_uninstall_nodialog_${inst.name}.png');
      print('[pair] $label: the uninstall confirmation never appeared');
      return false;
    }
    final cancelTapped = await _kgTapTextTopmost(inst, 'Cancel');
    final cancelDialogGone = await inst.waitTextGone(
      dialogTitle,
      timeoutSecs: 8,
    );
    final stillInstalledUi = await inst.waitKey(
      'applications_irc_uninstall_button',
      timeoutSecs: 6,
    );
    final stillInstalledState =
        (await inst.dumpState())['ircInstalled'] == true;

    // --- positive branch: confirm the uninstall. ---
    if (!await inst.tapKeyCenter(
      'applications_irc_uninstall_button',
      timeoutSecs: 8,
    )) {
      print('[pair] $label: Uninstall was not tappable a second time');
      return false;
    }
    if (!await inst.waitText(dialogTitle, timeoutSecs: 8)) {
      print('[pair] $label: the uninstall confirmation did not reopen');
      return false;
    }
    final confirmTapped = await _kgTapTextTopmost(inst, 'Uninstall');
    final installButtonUp = await inst.waitKey(
      'applications_irc_install_button',
      timeoutSecs: 15,
    );
    final uninstallGone = await inst.waitKeyGone(
      'applications_irc_uninstall_button',
      timeoutSecs: 10,
    );
    final addChannelGone = await inst.waitKeyGone(
      'applications_irc_add_channel_button',
      timeoutSecs: 10,
    );
    var uninstalledState = false;
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      if ((await inst.dumpState())['ircInstalled'] == false) {
        uninstalledState = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    final cardSurvived = await inst.waitKeyCenter(
      'applications_irc_card',
      timeoutSecs: 6,
    );
    await inst.shot('/tmp/ui_kg_irc_uninstalled_${inst.name}.png');
    print(
      '[pair] $label: cancelTapped=$cancelTapped '
      'cancelDialogGone=$cancelDialogGone stillInstalledUi=$stillInstalledUi '
      'stillInstalledState=$stillInstalledState confirmTapped=$confirmTapped '
      'installButtonUp=$installButtonUp uninstallGone=$uninstallGone '
      'addChannelGone=$addChannelGone uninstalledState=$uninstalledState '
      'cardSurvived=$cardSurvived',
    );
    return cancelTapped &&
        cancelDialogGone &&
        stillInstalledUi &&
        stillInstalledState &&
        confirmTapped &&
        installButtonUp &&
        uninstallGone &&
        addChannelGone &&
        uninstalledState &&
        cardSurvived;
  } finally {
    await _kgIrcCleanup(inst, label);
  }
}
