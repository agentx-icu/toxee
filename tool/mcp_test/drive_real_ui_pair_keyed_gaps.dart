// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// KEYED-BUT-NEVER-DRIVEN gap batch #2 — the sweep spine, the dispatch, the
// shared helpers, and the add-group type-selector case. The case BODIES for the
// other two domains live in the sibling part files
// (`..._keyed_gaps_register.dart`, `..._keyed_gaps_irc.dart`) purely so each
// half stays under the 500-LOC complexity cap; they are one library.
//
// WHY THIS BATCH EXISTS. An audit of `lib/ui/testing/ui_keys.dart` +
// the fork key catalog turned up controls that CARRY a ValueKey (so somebody
// intended them to be automatable) but that no scenario has ever driven. This
// batch closes the register-page, IRC-app and add-group-type-selector holes.
//
// SINGLE INSTANCE, LAUNCH-REUSED. Every case here drives ONLY A; B stays
// launched-but-idle. `sweep_keyed_gaps` is `required=no-friend` /
// `result=no-friend` (nothing forms or deletes a friendship), which is exactly
// the contract that lets the runner APPEND it to an existing campaign chain
// without inserting a reset or a second pair launch — the "startup reuse is the
// default" rule. It is registered into the `rui-app-entry-extra`,
// `rui-{ios,ipad,android}-account-settings` and `rui-{ios,ipad}-main` chains
// rather than getting a launch of its own, the same way `sweep_msg_select` is
// appended to `rui-ios-chat-main`.
//
// ASSERTION DISCIPLINE (same bar as the multi-select batch): every case asserts
// an observable side effect — a keyed widget MOUNTING or UNMOUNTING, a
// state-encoded key FLIPPING, an inline validator error appearing and then going
// away, or an `l3_dump_state` field changing. No case passes on "the tap did not
// throw".
//
// THREE PRODUCTION KEYS WERE ADDED alongside these cases, all additive and all
// state-ENCODED (the pre-existing keys could only say "mounted", never "in which
// state"):
//   * `register_confirm_match_{ok,mismatch}`      (register_page_form.dart)
//   * `register_confirm_visibility_icon_{obscured,visible}` (same file)
//   * `register_strength_segment_<i>_{filled,empty}` (register_password_strength_bar.dart)
//   * `irc_channel_dialog_password_visibility_icon_{obscured,visible}`
//     (irc_channel_dialog.dart)
// They mirror the already-shipped `register_password_visibility_icon_*` pattern:
// the tappable widget keeps its stable key, the sibling key carries the state.
//
// VERIFY-FIRST FINDINGS recorded while writing this batch (documented, NOT
// papered over with a fake case):
//   * `av_conference_{join,mute,enable,leave}_button` — UNREACHABLE. The header
//     action only renders when `conversation.groupType == 'av_conference'`
//     (home_page_bootstrap.dart:6), and the ONLY producer of that type is an
//     INBOUND `TOX_CONFERENCE_TYPE_AV` invite (V2TIMManagerImpl.cpp:1157,
//     `is_av_invite ? "av_conference" : "conference"`). The AddGroupDialog
//     offers exactly three create types (group/privateGroup/conference,
//     add_group_dialog.dart:193) and `l3_create_group` only maps
//     public/private, so nothing in the app or the harness can construct the
//     precondition. Same for `call_camera_switch_button`, which additionally
//     needs a live video call plus `CallMediaCapabilities.supportsCameraSwitch()`.
//   * `message_attachment_{image,photo,video,search}_button` — DEAD in this
//     product. toxee pins `enableSendImage/enableSendVideo/enableSendFile/
//     enableSearch` to false (lib/ui/home/mobile_attachment_policy.dart) and
//     `_buildDesktopInputOptions` builds only `Icons.attach_file` (+
//     `Icons.qr_code_2` in C2C), so those four fork keys can never resolve.
//     Only `message_attachment_personal_card_button` is live, and it is a
//     two-process case that belongs in the native-boundary sweep.
//   * `add_group_copy_id_button` — DEAD in production. `_buildCreatedInfo()`
//     only renders while `_createdGroupId != null`, but `_createGroup` pops the
//     dialog immediately on success unless `closeOnCreateSuccess == false`, and
//     NOTHING in `lib/` ever passes that flag (it defaults to true). The Copy-ID
//     card is reachable only from a widget test.
//
// NOT VERIFIED BY EXECUTION: authored offline; no campaign run has driven these
// cases yet.

const _keyedGapsCases = {
  'add_group_type_selector_hint_switches',
  'irc_channel_dialog_cancel_discards',
  'irc_channel_remove_row_confirm',
  'irc_app_uninstall_reinstall_card',
  'register_status_field_length_guard',
  'register_confirm_match_icon_flips',
  'register_confirm_visibility_toggle_flips',
  'register_strength_segments_ramp',
};

bool _isKeyedGapsCaseScenario(String scenario) =>
    _keyedGapsCases.contains(scenario);

/// The runner's SKIP exit code (`_realUiSkipExitCode`). Mirrored here because
/// the driver runs as a separate process.
const _keyedGapsSkipExit = 75;

/// Dispatch for `sweep_keyed_gaps` and its eight individual cases. Called from
/// `dispatchFormFactor` (drive_real_ui_pair_msg_select.dart) so the aggregator
/// `drive_real_ui_pair.dart` needs no new dispatch lines — it is already at its
/// complexity pin. Returns null when [scenario] is not ours.
Future<int?> dispatchKeyedGaps(Inst a, String nickA, String scenario) async {
  if (scenario == 'sweep_keyed_gaps') {
    return runKeyedGapsSweep(a, nickA);
  }
  if (_isKeyedGapsCaseScenario(scenario)) {
    return runKeyedGapsCase(a, nickA, scenario);
  }
  return null;
}

/// The logged-in account's tox id, read WHILE the session is live.
///
/// The register cases log out, and a logged-out `l3_dump_state` reports
/// `currentAccountToxId` as empty — so the end-clean relogin has to be told
/// which account to go back to rather than asking after the fact. Empty only if
/// the caller's `ensureHome` did not actually land a session.
Future<String> _kgCaptureAccount(Inst inst) async {
  try {
    return (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  } on DriveError {
    return '';
  }
}

/// Standalone dispatch for ONE case (focused debugging). Same prelude and same
/// end-clean as the sweep, so a single case leaves the launch reusable.
Future<int> runKeyedGapsCase(Inst a, String nickA, String scenario) async {
  await ensureHome(a, nickA);
  final tox = await _kgCaptureAccount(a);
  bool? ok;
  try {
    ok = await _kgRun(a, scenario);
  } finally {
    await _kgNormalize(a, nickA, toxId: tox);
  }
  print(
    '[pair] ${ok == null
        ? 'SKIP'
        : ok
        ? 'PASS'
        : 'FAIL'}: $scenario',
  );
  return switch (ok) {
    true => 0,
    false => 1,
    null => _keyedGapsSkipExit,
  };
}

Future<bool?> _kgRun(Inst a, String scenario) => switch (scenario) {
  'add_group_type_selector_hint_switches' => _kgAddGroupTypeSelectorHint(a),
  'irc_channel_dialog_cancel_discards' => _kgIrcChannelDialogCancelDiscards(a),
  'irc_channel_remove_row_confirm' => _kgIrcChannelRemoveRowConfirm(a),
  'irc_app_uninstall_reinstall_card' => _kgIrcAppUninstallReinstallCard(a),
  'register_status_field_length_guard' => _kgRegisterStatusFieldLengthGuard(a),
  'register_confirm_match_icon_flips' => _kgRegisterConfirmMatchIconFlips(a),
  'register_confirm_visibility_toggle_flips' =>
    _kgRegisterConfirmVisibilityToggleFlips(a),
  'register_strength_segments_ramp' => _kgRegisterStrengthSegmentsRamp(a),
  _ => throw ArgumentError('unsupported keyed-gaps scenario: $scenario'),
};

/// All eight cases on ONE launch. HOME-page cases run FIRST and the four
/// LoginPage (register) cases LAST: the register cases log out, so putting them
/// first would make every later case pay a relogin, and a relogin failure would
/// cascade into false reds for the IRC/add-group cases.
Future<int> runKeyedGapsSweep(Inst a, String nickA) async {
  await ensureHome(a, nickA);
  final sweepTox = await _kgCaptureAccount(a);
  var passed = 0;
  var failed = 0;
  var skipped = 0;
  var unexpectedSkipped = 0;

  Future<void> hard(String name) async {
    bool? ok;
    try {
      ok = await _kgRun(a, name);
    } on PermissionBlockedError {
      rethrow;
    } on Object catch (e, st) {
      ok = false;
      print('[sweep] sweep_keyed_gaps EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _kgNormalize(a, nickA, toxId: sweepTox);
    }
    if (ok == null) {
      skipped++;
      unexpectedSkipped++;
      print('[sweep] sweep_keyed_gaps SKIP(unexpected): $name');
    } else if (ok) {
      passed++;
      print('[sweep] sweep_keyed_gaps PASS: $name');
    } else {
      failed++;
      print('[sweep] sweep_keyed_gaps FAIL: $name');
    }
  }

  for (final name in const [
    'add_group_type_selector_hint_switches',
    'irc_channel_dialog_cancel_discards',
    'irc_channel_remove_row_confirm',
    'irc_app_uninstall_reinstall_card',
    'register_status_field_length_guard',
    'register_confirm_match_icon_flips',
    'register_confirm_visibility_toggle_flips',
    'register_strength_segments_ramp',
  ]) {
    await hard(name);
  }

  final endClean = await _kgNormalize(a, nickA, toxId: sweepTox);
  if (!endClean) failed++;
  print(
    '[sweep] sweep_keyed_gaps summary: passed=$passed failed=$failed '
    'skipped=$skipped endClean=$endClean',
  );
  return failed == 0 && unexpectedSkipped == 0 ? 0 : 1;
}

/// End-clean between cases: dismiss any modal a half-finished case left up,
/// recover the session when a register case stranded us on the LoginPage, and
/// land on the chats home. Never asserts — the cases do that.
Future<bool> _kgNormalize(Inst inst, String nickA, {String? toxId}) async {
  try {
    // Dialog-scoped escapes first (add-group / IRC channel dialogs), then the
    // generic pop-to-root.
    for (final key in const [
      'irc_channel_dialog_cancel_button',
      'add_group_close_button',
    ]) {
      if (await inst.keyCenter(key) != null) {
        await inst.tapKeyCenter(key, timeoutSecs: 4);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    await inst.osaEscape();
  } on Object catch (e) {
    print('[sweep] keyed-gaps normalize: dismiss best-effort: $e');
  }
  try {
    await _backOutOfRegister(inst);
  } on Object catch (e) {
    print('[sweep] keyed-gaps normalize: register back-out best-effort: $e');
  }
  var st = await inst.dumpState();
  if (st['sessionReady'] != true) {
    // PREFER the id captured while the session was still live ([toxId]).
    //
    // WHY (live-diagnosed on ANDROID 2026-08-16, reproduced on 3 consecutive
    // runs): the four register cases log the session OUT, and a logged-out
    // `l3_dump_state` reports `currentAccountToxId` as EMPTY. The old code only
    // read it from the dump, so `tox.isNotEmpty` was false, the relogin branch
    // was a SILENT no-op (no print at all), and the sweep ended
    // `endClean=false` every time. That is not cosmetic: `endClean` counts as a
    // failure, which made `sweep_keyed_gaps` abort the whole `rui-android-main`
    // chain before `sweep_chat` ever ran.
    final tox = (toxId != null && toxId.isNotEmpty)
        ? toxId
        : (st['currentAccountToxId']?.toString() ?? '');
    if (tox.isNotEmpty) {
      try {
        if (!await _quickLoginNoPassword(inst, tox)) {
          print('[sweep] keyed-gaps normalize: relogin returned false for '
              '${_shortId(tox)}');
        }
      } on Object catch (e) {
        print('[sweep] keyed-gaps normalize: relogin failed: $e');
      }
    } else {
      print('[sweep] keyed-gaps normalize: no account id available to relogin '
          'with (logged out and none captured) — endClean will be false');
    }
    st = await inst.dumpState();
  }
  if (st['sessionReady'] == true) {
    try {
      await returnToChatsHome(inst, rounds: 4);
    } on Object catch (e) {
      print('[sweep] keyed-gaps normalize: return home best-effort: $e');
    }
  }
  return (await inst.dumpState())['sessionReady'] == true;
}

// ===========================================================================
// Shared helpers
// ===========================================================================

/// Poll until [key] is no longer resolvable through the ELEMENT-TREE walk
/// (`ui_key_center`). The `waitKeyGone` counterpart goes through flutter_skill's
/// interactive-element index, which never surfaces a `KeyedSubtree` or a bare
/// `Icon` — exactly the widgets this batch's state-encoded keys sit on — so a
/// `waitKeyGone` on them would report "gone" while the widget is on screen.
Future<bool> _kgWaitKeyCenterGone(
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

/// Tap [tapKey] until [expectKey] resolves through `ui_key_center`, up to
/// [attempts] times.
///
/// WHY A RETRY IS NOT A WEAKENING. The assertion is unchanged — the case still
/// requires the state-encoded key to FLIP, and this returns false if it never
/// does. What it removes is the harness's own coordinate-tap flakiness: a
/// `tapKeyCenter` on a suffix `IconButton` reports success as soon as it has
/// dispatched ONE `tapAt` at the resolved centre, but a synthetic pointer on a
/// device can be swallowed (live-observed 2026-08-16 on iPad: the confirm
/// visibility toggle flipped on one run and not on the very next, with BOTH
/// taps lost so the trailing "hidden again" assertions passed vacuously).
/// Re-tapping until the observable moves is the same rule
/// `sendComposerMessage` already uses for Enter-to-send.
Future<bool> _kgTapUntilKeyCenter(
  Inst inst,
  String tapKey,
  String expectKey, {
  int attempts = 3,
  int settleSecs = 4,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    // Drop the soft keyboard FIRST. Every caller here taps a control that sits
    // right beside a text field it has just typed into, and the IME is an OS
    // surface the widget geometry does not know about: `ui_key_center` happily
    // reports the toggle's centre while the keyboard covers that exact point,
    // and the dispatched tap is swallowed. Live on iPad 2026-08-16: three
    // consecutive taps on `register_confirm_visibility_toggle` changed nothing
    // (and the run right before it, with no IME up, flipped on the first tap).
    await inst.hideKeyboard();
    if (!await inst.tapKeyCenter(tapKey, timeoutSecs: 6)) {
      print('[pair] _kgTapUntilKeyCenter: "$tapKey" not tappable');
      return false;
    }
    if (await inst.waitKeyCenter(expectKey, timeoutSecs: settleSecs)) {
      return true;
    }
    print(
      '[pair] _kgTapUntilKeyCenter: "$tapKey" tap ${attempt + 1}/$attempts did '
      'not surface "$expectKey" — retrying',
    );
  }
  return false;
}

/// Tap the TOPMOST element whose visible text equals [text].
///
/// `_tapTextCenter` taps the FIRST match in tree order, which is wrong for the
/// unkeyed confirmation dialogs on the Applications page: the IRC card's own
/// "Uninstall" button and the confirm dialog's "Uninstall" action carry the same
/// label, and the card renders EARLIER in the tree. Tapping the first would land
/// on the widget covered by the modal barrier (a silent no-op). Elements are
/// reported in tree order, so the LAST positive-bounds match is the action on
/// the route the user actually sees — the same `.last` rule `tapKeyCenter` uses
/// for stacked duplicate keys.
Future<bool> _kgTapTextTopmost(
  Inst inst,
  String text, {
  int timeoutSecs = 8,
}) async {
  if (!await inst.waitText(text, timeoutSecs: timeoutSecs)) return false;
  for (var attempt = 0; attempt < 5; attempt++) {
    final r = await inst.skill('interactiveStructured', const {});
    final data = r['data'];
    final elements = data is Map ? data['elements'] : null;
    ({double x, double y})? target;
    if (elements is List) {
      for (final e in elements) {
        if (e is! Map || e['text']?.toString() != text) continue;
        final b = e['bounds'];
        if (b is! Map) continue;
        final w = (b['w'] as num?)?.toDouble() ?? 0;
        final h = (b['h'] as num?)?.toDouble() ?? 0;
        if (w <= 0 || h <= 0) continue;
        target = (
          x: ((b['x'] as num?)?.toDouble() ?? 0) + w / 2,
          y: ((b['y'] as num?)?.toDouble() ?? 0) + h / 2,
        );
      }
    }
    if (target != null) {
      await inst.tapAt(target.x, target.y);
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

// ===========================================================================
// add_group_type_selector_hint_switches
// ===========================================================================
/// Drive the REAL create-group TYPE SELECTOR (`add_group_type_selector`) through
/// all three segments and assert the per-type HINT text under it swaps each time.
///
/// WHY THE HINT IS THE ASSERTION. `SegmentedButton.selected` is internal state
/// with no keyed readout; the three `add_group_type_*_segment` keys are on
/// KeyedSubtree label wrappers and are mounted for every selection, so they can
/// only prove "the selector rendered" (which `group_create_type_selector_surface`
/// already does). `_groupTypeHint(_selectedGroupType)` renders a DIFFERENT
/// sentence per type, so the hint appearing AND the previous one disappearing is
/// a genuine observable of `onSelectionChanged` having run.
///
/// Nothing is created: the dialog is closed with its own keyed X button, so the
/// case leaves no group and no conversation behind.
Future<bool?> _kgAddGroupTypeSelectorHint(Inst inst) async {
  const label = 'add_group_type_selector_hint_switches';
  const publicHint =
      'Public group — discoverable on the DHT and joinable by anyone with '
      'the chat ID.';
  const privateHint =
      'Private group — invitation-only, not announced on the DHT.';
  const conferenceHint =
      'Legacy conference — older protocol, no roles or persistence.';

  await inst.foreground();
  final opened = await inst.l3('l3_open_add_group_dialog');
  if (opened['ok'] != true) {
    print('[pair] $label: l3_open_add_group_dialog failed: $opened');
    return false;
  }
  if (!await inst.waitKey('add_group_create_name_input', timeoutSecs: 12)) {
    print('[pair] $label: the AddGroupDialog never mounted');
    return false;
  }
  try {
    if (inst.isMobileShell) {
      // The create card sits below the join card; on a phone the selector is
      // under the fold, so its render-box centre is off-viewport and a
      // coordinate tap would miss.
      await _revealDialogKey(inst, 'add_group_type_selector');
    }
    final selectorMounted = await inst.waitKeyCenter(
      'add_group_type_selector',
      timeoutSecs: 8,
    );
    if (!selectorMounted) {
      await inst.shot('/tmp/ui_kg_type_selector_absent_${inst.name}.png');
      print('[pair] $label: add_group_type_selector did not resolve');
      return false;
    }
    // Default selection is 'group' (Public) — assert the baseline hint before
    // touching anything, so a hint that never changes cannot pass.
    final publicFirst = await inst.waitText(publicHint, timeoutSecs: 6);

    Future<bool> pick(String segmentKey, String expect, String gone) async {
      if (inst.isMobileShell) {
        await _revealDialogKey(inst, segmentKey);
      }
      if (!await inst.tryTapKey(segmentKey) &&
          !await inst.tapKeyAt(segmentKey)) {
        print('[pair] $label: segment $segmentKey was not tappable');
        return false;
      }
      final shown = await inst.waitText(expect, timeoutSecs: 6);
      final swapped = await inst.waitTextGone(gone, timeoutSecs: 4);
      if (!shown || !swapped) {
        print(
          '[pair] $label: after $segmentKey shown=$shown previousGone=$swapped',
        );
      }
      return shown && swapped;
    }

    final toPrivate = await pick(
      'add_group_type_private_segment',
      privateHint,
      publicHint,
    );
    final toConference = await pick(
      'add_group_type_conference_segment',
      conferenceHint,
      privateHint,
    );
    final backToPublic = await pick(
      'add_group_type_public_segment',
      publicHint,
      conferenceHint,
    );
    await inst.shot('/tmp/ui_kg_type_selector_${inst.name}.png');
    print(
      '[pair] $label: selector=$selectorMounted publicFirst=$publicFirst '
      'private=$toPrivate conference=$toConference backToPublic=$backToPublic',
    );
    return publicFirst && toPrivate && toConference && backToPublic;
  } finally {
    // Close WITHOUT creating anything. The keyed X exists precisely because
    // mobile has no host Escape key.
    if (await inst.keyCenter('add_group_close_button') != null) {
      await inst.tapKeyCenter('add_group_close_button', timeoutSecs: 6);
    }
    await inst.waitKeyGone('add_group_create_name_input', timeoutSecs: 6);
  }
}
