// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 2 of the real-UI sweep campaign — "Self profile" (8 cases, single
// instance, one launch). See tool/mcp_test/REAL_UI_SWEEP_CAMPAIGN.md.
//
// Every case drives the REAL self-profile widgets of ONE live instance (A; B is
// launched-but-idle). The self profile is an OVERLAY: tapping the persistent
// sidebar user-avatar InkWell (UiKeys.sidebarUserAvatar == 'sidebar_user_avatar')
// fires `_openProfile` → `showSelfProfile`, which on desktop is a `showDialog`
// hosting the editable `ProfilePage` (profile_page.dart). The overlay carries
// these keyed affordances:
//   profile_edit_toggle           IconButton — toggles `_editMode` (TOGGLE; must
//                                 be SINGLE-FIRED, a double-fire is a net no-op)
//   profile_nickname_field        editable nickname TextField (edit mode only)
//   profile_status_field          editable status TextField (edit mode only)
//   profile_save_button           FilledButton — runs `_handleSave` (setState)
//   profile_tox_id_copy_button    TextButton.icon — `_copyToxId` → clipboard
//   profile_qr_copy_button        QR-card copy — `_copyQrImage` (desktop only,
//                                 mounts AFTER the QR FutureBuilder resolves)
//   profile_tox_id_selectable_text  SelectableText showing the real 76-hex toxId
//   profile_close_button          dialog/route dismiss IconButton (Batch-2
//                                 production-key addition for deterministic close)
//
// Assertions read the REAL side-effect: an l3_dump_state field (nickname /
// statusMessage) for the persisting edits, plus a real UI signal (the overlay
// mounting, edit fields appearing/disappearing, the copy snackbars). The
// nickname/status edits (cases 15/16) RESTORE the original registered values at
// case end so a later batch that asserts the registered nick is not poisoned.
//
// AVATAR cases 19/20 are SKIPPED — see _profileAvatarPickerOpens / the campaign
// doc: the self-profile avatar tap opens the NATIVE NSOpenPanel directly (no
// in-app default-avatar grid/picker surface exists — the "default avatars" of
// commit 5867fdc are a registration-time fallback INSTALLER, not a chooser UI),
// and the l3 avatar-pick override (l3_set_avatar_pick_path / l3_pick_avatar) is
// TEST-ACCOUNT-gated so it is refused on the fresh non-test real-UI account AND
// would be a forbidden l3 bypass of the asserted action anyway.

/// Open the self-profile overlay by tapping the persistent sidebar user-avatar
/// InkWell, then wait for the overlay landmark (the edit toggle, which only
/// renders when `isEditable:true` — i.e. the self profile). Robust against a
/// transient backgrounded window: re-foreground + re-tap a few rounds.
Future<bool> _openSelfProfile(Inst inst) async {
  for (var round = 0; round < 4; round++) {
    await inst.foreground();
    if (await inst.waitKey('profile_edit_toggle', timeoutSecs: 2)) return true;
    // The sidebar avatar lives in the persistent left rail on every home tab.
    // SINGLE-FIRE it (one coordinate tapAt): flutter_skill's `tap` double-fires
    // (synthetic pointer + a direct _tryInvokeCallback), and `_openProfile` →
    // `showSelfProfile` has NO re-entry guard, so a double-fire could stack TWO
    // profile dialogs (then close+ESC would only unwind one). tapKeyCenter
    // dispatches exactly one pointer tap → one _openProfile → one showDialog.
    //
    // NO double-fire `tryTapKey` fallback (codex): tapKeyCenter already retries
    // bounds resolution 5×/~1s, and the avatar is an always-onstage, sized
    // sidebar element — if its bounds genuinely can't resolve on this frame, the
    // outer loop re-foregrounds and retries tapKeyCenter on the next round
    // rather than risking a stacked-dialog artifact via a double-firing tap.
    final tapped = await inst.tapKeyCenter('sidebar_user_avatar', timeoutSecs: 4);
    if (tapped && await inst.waitKey('profile_edit_toggle', timeoutSecs: 6)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  await inst.shot('/tmp/ui_profile_noopen_${inst.name}.png');
  return false;
}

/// Dismiss the self-profile overlay deterministically via the keyed close
/// button (Batch-2 production-key addition). SINGLE-FIRE: the close button pops
/// the dialog route, and flutter_skill's double-fire `tap` would pop the page
/// underneath (the flutter_skill_double_tap_blank hazard) — so tap its CENTER
/// once. Falls back to ESC. Returns whether the overlay closed (edit toggle
/// gone). Best-effort; never throws.
Future<bool> _closeSelfProfile(Inst inst) async {
  await inst.foreground();
  if (!await inst.waitKey('profile_edit_toggle', timeoutSecs: 1)) {
    return true; // already closed
  }
  if (await inst.tapKeyCenter('profile_close_button', timeoutSecs: 4)) {
    if (await inst.waitKeyGone('profile_edit_toggle', timeoutSecs: 4)) {
      return true;
    }
  }
  // ESC fallback (a focused dialog may swallow it; best-effort).
  try {
    await inst.osaEscape();
  } on DriveError {
    // best-effort only
  }
  return inst.waitKeyGone('profile_edit_toggle', timeoutSecs: 4);
}

/// Enter edit mode on an already-open self profile: SINGLE-FIRE the edit toggle
/// (it flips `_editMode = !_editMode`, so a double-fire is a net no-op), then
/// wait for the editable nickname field to mount. Returns whether edit mode was
/// entered.
Future<bool> _enterProfileEditMode(Inst inst) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    if (await inst.waitKey('profile_nickname_field', timeoutSecs: 1)) {
      return true;
    }
    if (!await inst.tapKeyCenter('profile_edit_toggle', timeoutSecs: 4)) {
      return false;
    }
    if (await inst.waitKey('profile_nickname_field', timeoutSecs: 3)) {
      return true;
    }
    // A spurious double-toggle (even count) could have closed it again; retry.
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

/// case 13 — profile_open_sidebar_avatar (S104): tap the real sidebar avatar →
/// the self-profile overlay mounts. Asserts the overlay landmark (edit toggle,
/// which is only rendered for the editable self profile) AND the real resolved
/// identity surface (the keyed Tox-ID SelectableText is present), then closes
/// the overlay so the next case starts from the home shell.
///
/// IMPORTANT (codex P1): close any pre-existing overlay FIRST and assert the
/// closed precondition, so a dirty session (a leftover open profile) cannot
/// false-PASS this case without the avatar tap ever firing. `_openSelfProfile`
/// short-circuits when the overlay is already up, so the precondition close is
/// what makes the tap load-bearing here.
Future<bool> _profileOpenSidebarAvatar(Inst inst) async {
  await _closeSelfProfile(inst);
  await inst.foreground();
  final closedBefore = await inst.waitKeyGone('profile_edit_toggle', timeoutSecs: 4);
  if (!closedBefore) {
    print('[pair] profile_open_sidebar_avatar: could not close pre-existing overlay');
    return false;
  }
  final opened = await _openSelfProfile(inst);
  // The Tox-ID panel proves the editable ProfilePage rendered fully (not just
  // the toggle) with the resolved identity threaded in.
  final toxIdShown =
      opened &&
      await inst.waitKey('profile_tox_id_selectable_text', timeoutSecs: 4);
  final copyShown =
      opened &&
      await inst.waitKey('profile_tox_id_copy_button', timeoutSecs: 2);
  final closed = await _closeSelfProfile(inst);
  print(
    '[pair] profile_open_sidebar_avatar: closedBefore=$closedBefore '
    'opened=$opened toxIdShown=$toxIdShown copyShown=$copyShown closed=$closed',
  );
  return closedBefore && opened && toxIdShown && copyShown && closed;
}

/// case 14 — profile_edit_toggle_roundtrip (S101): enter edit mode (fields
/// mount) then exit (fields unmount). Asserts both legs of the bidirectional
/// `_editMode` toggle on the REAL overlay, then closes it.
Future<bool> _profileEditToggleRoundtrip(Inst inst) async {
  if (!await _openSelfProfile(inst)) {
    print('[pair] profile_edit_toggle_roundtrip: overlay did not open');
    return false;
  }
  // ON: edit fields mount.
  final entered = await _enterProfileEditMode(inst);
  final saveShown =
      entered && await inst.waitKey('profile_save_button', timeoutSecs: 3);
  // OFF: SINGLE-FIRE the toggle again (now showing the close/cancel icon) →
  // fields unmount.
  var exited = false;
  if (entered) {
    if (await inst.tapKeyCenter('profile_edit_toggle', timeoutSecs: 4)) {
      exited = await inst.waitKeyGone('profile_nickname_field', timeoutSecs: 4);
    }
  }
  final saveGone =
      exited && await inst.waitKeyGone('profile_save_button', timeoutSecs: 3);
  // The toggle itself must still be present (read-only mode, overlay not
  // dismissed).
  final toggleStays = await inst.waitKey('profile_edit_toggle', timeoutSecs: 2);
  final closed = await _closeSelfProfile(inst);
  print(
    '[pair] profile_edit_toggle_roundtrip: entered=$entered saveShown=$saveShown '
    'exited=$exited saveGone=$saveGone toggleStays=$toggleStays closed=$closed',
  );
  return entered &&
      saveShown &&
      exited &&
      saveGone &&
      toggleStays &&
      closed;
}

/// Type [value] into the keyed edit [fieldKey] (clears first), then SINGLE-FIRE
/// the save button and wait for [stateField] in l3_dump_state to equal [value].
/// Returns whether the value persisted. The save button runs `_handleSave`
/// (setState, no Navigator.pop), so a double-fire would be harmless — but
/// tapKeyCenter keeps the convention and avoids a press race.
Future<bool> _editProfileFieldAndSave(
  Inst inst,
  String fieldKey,
  String value,
  String stateField,
) async {
  if (!await inst.waitKey(fieldKey, timeoutSecs: 3)) return false;
  // Type via REAL OS keystrokes (focusType = tapKeyCenter focus + osaClear +
  // osaType), NOT a synthetic `enterText`. The synthetic path drives the macOS
  // engine's `-[FlutterTextInputPlugin setEditingState:]`, which INTERMITTENTLY
  // SIGSEGVs the whole app when typing into these overlay edit TextFields
  // (observed killing instance A on the self-profile status field — the FATAL
  // backtrace's frame 2 is setEditingState). focusType replaces the field
  // content with genuine keystrokes through AppKit's normal key path, which
  // never touches setEditingState.
  await inst.focusType(fieldKey, value);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  // The save FilledButton's label is the localized "Save Contact" text and
  // flutter_skill does NOT propagate its ValueKey onto the rendered text leaf,
  // so `interactiveStructured` reports it with key:null and `tapKeyCenter`
  // (which matches by key over interactiveStructured) can't find its bounds.
  // Fall back to `tapKeyAt`, which resolves the keyed FilledButton's RenderBox
  // center via ui_drive_tools (ui_key_center) and taps there.
  if (!await inst.tapKeyCenter('profile_save_button', timeoutSecs: 4)) {
    if (!await inst.tapKeyAt('profile_save_button')) {
      print('[pair] profile edit: save button not tappable');
      return false;
    }
  }
  return _waitStringState(inst, stateField, value);
}

/// case 15 — profile_edit_nickname_persists (S8): open the self profile, enter
/// edit mode, type a fresh nickname into the REAL field, Save → dump `nickname`
/// reflects it. RESTORES the original registered nickname at the end (poison
/// guard — later batches assert the registered nick).
Future<bool> _profileEditNicknamePersists(Inst inst) async {
  if (!await _openSelfProfile(inst)) {
    print('[pair] profile_edit_nickname_persists: overlay did not open');
    return false;
  }
  final original = (await inst.dumpState())['nickname']?.toString() ?? '';
  if (original.isEmpty) {
    print('[pair] profile_edit_nickname_persists: original nickname empty');
    await _closeSelfProfile(inst);
    return false;
  }
  if (!await _enterProfileEditMode(inst)) {
    print('[pair] profile_edit_nickname_persists: could not enter edit mode');
    await _closeSelfProfile(inst);
    return false;
  }
  // A distinct nickname that differs from `original` and stays under the
  // 12-CJK / 24-ASCII length cap (profileTextLength) so the save button is
  // enabled.
  final target = original == 'RuiNick2' ? 'RuiNick3' : 'RuiNick2';
  final saved = await _editProfileFieldAndSave(
    inst,
    'profile_nickname_field',
    target,
    'nickname',
  );
  // RESTORE the original nickname so later batches see the registered value.
  // The save flips _editMode off; re-enter edit mode to restore.
  var restored = true;
  if (saved) {
    if (await _enterProfileEditMode(inst)) {
      restored = await _editProfileFieldAndSave(
        inst,
        'profile_nickname_field',
        original,
        'nickname',
      );
    } else {
      restored = false;
    }
  }
  final closed = await _closeSelfProfile(inst);
  print(
    '[pair] profile_edit_nickname_persists: original="$original" '
    'target="$target" saved=$saved restored=$restored closed=$closed',
  );
  return saved && restored && closed;
}

/// case 16 — profile_edit_status_persists (S8): same as case 15 but for the
/// status message field → dump `statusMessage` reflects it. RESTORES the
/// original status (poison guard). The seed account's status may be empty ('')
/// — l3_dump_state coerces null→'' — so the restore re-applies whatever it was.
Future<bool> _profileEditStatusPersists(Inst inst) async {
  if (!await _openSelfProfile(inst)) {
    print('[pair] profile_edit_status_persists: overlay did not open');
    return false;
  }
  final original = (await inst.dumpState())['statusMessage']?.toString() ?? '';
  if (!await _enterProfileEditMode(inst)) {
    print('[pair] profile_edit_status_persists: could not enter edit mode');
    await _closeSelfProfile(inst);
    return false;
  }
  // A distinct status under the 24-CJK / 48-ASCII cap so save stays enabled.
  final target = original == 'rui status 2' ? 'rui status 3' : 'rui status 2';
  final saved = await _editProfileFieldAndSave(
    inst,
    'profile_status_field',
    target,
    'statusMessage',
  );
  // RESTORE. If the original was empty, the field must be cleared; enterText
  // with '' followed by save persists '' (dump coerces null→'').
  var restored = true;
  if (saved) {
    if (await _enterProfileEditMode(inst)) {
      restored = await _editProfileFieldAndSave(
        inst,
        'profile_status_field',
        original,
        'statusMessage',
      );
    } else {
      restored = false;
    }
  }
  final closed = await _closeSelfProfile(inst);
  print(
    '[pair] profile_edit_status_persists: original="$original" '
    'target="$target" saved=$saved restored=$restored closed=$closed',
  );
  return saved && restored && closed;
}

/// case 17 — profile_copy_toxid_snackbar (S102): tap the keyed Tox-ID copy
/// button → the production `_copyToxId` writes the toxId to the clipboard and
/// shows the "ID copied to clipboard" success snackbar. Asserts the snackbar
/// (the real UI signal of the handler running), then closes the overlay. The
/// cross-process clipboard ground truth (pbpaste) stays out of scope per S102's
/// promotion note (the hermetic L1 gate covers the Clipboard.setData payload).
Future<bool> _profileCopyToxIdSnackbar(Inst inst) async {
  if (!await _openSelfProfile(inst)) {
    print('[pair] profile_copy_toxid_snackbar: overlay did not open');
    return false;
  }
  // Clear any lingering "ID copied to clipboard" toast from a prior case so the
  // assertion below proves THIS tap raised it (success snackbars live ~3s; case
  // 18 asserts the SAME text — see _profileQrCopy). Best-effort, bounded.
  await inst.waitTextGone('ID copied to clipboard', timeoutSecs: 5);
  // The copy button is a TextButton.icon (not a toggle / not route-popping) so
  // a double-fire is harmless; tapKeyCenter keeps the single-tap convention.
  final tapped = await inst.tapKeyCenter(
    'profile_tox_id_copy_button',
    timeoutSecs: 4,
  );
  final snackbar =
      tapped && await inst.waitText('ID copied to clipboard', timeoutSecs: 8);
  final closed = await _closeSelfProfile(inst);
  print(
    '[pair] profile_copy_toxid_snackbar: tapped=$tapped snackbar=$snackbar '
    'closed=$closed',
  );
  return tapped && snackbar && closed;
}

/// case 18 — profile_qr_copy (S103): tap the QR-card copy button → the
/// production `_copyQrImage` copies the QR image and shows the same "ID copied
/// to clipboard" snackbar. The QR copy button only MOUNTS after ProfilePage's
/// QR FutureBuilder resolves (real canvas→PNG generation), which DOES complete
/// in the live app (unlike a widget test), so we wait for it. On desktop the
/// production `enableCopy` gate is true; on Android/iOS/Linux it is hidden — so
/// this case is desktop-only by construction (the harness host is macOS).
Future<bool> _profileQrCopy(Inst inst) async {
  if (!await _openSelfProfile(inst)) {
    print('[pair] profile_qr_copy: overlay did not open');
    return false;
  }
  // The QR copy button appears only once the QR card image finishes generating
  // — give it a generous bounded wait so a broken QR pipeline FAILS (not hangs).
  final qrShown = await inst.waitKey('profile_qr_copy_button', timeoutSecs: 20);
  // CRITICAL (codex P1): case 17 raised the SAME "ID copied to clipboard"
  // snackbar moments ago (success toasts live ~3s). Wait for it to DISMISS
  // before tapping QR-copy so the assertion below proves the QR tap raised a
  // FRESH toast — not case 17's stale one. Bounded so a stuck toast FAILS.
  if (qrShown &&
      !await inst.waitTextGone('ID copied to clipboard', timeoutSecs: 8)) {
    print('[pair] profile_qr_copy: prior copy snackbar never dismissed');
    await _closeSelfProfile(inst);
    return false;
  }
  final tapped =
      qrShown &&
      await inst.tapKeyCenter('profile_qr_copy_button', timeoutSecs: 4);
  final snackbar =
      tapped && await inst.waitText('ID copied to clipboard', timeoutSecs: 8);
  final closed = await _closeSelfProfile(inst);
  print(
    '[pair] profile_qr_copy: qrShown=$qrShown tapped=$tapped '
    'snackbar=$snackbar closed=$closed',
  );
  return qrShown && tapped && snackbar && closed;
}

// Smallest valid 1x1 PNGs (distinct bytes so the two cases pick DIFFERENT
// images and each apply is observably a change). Base64 of a 1x1 red / blue PNG.
const _avatarPngRedB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const _avatarPngBlueB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

/// Read the persisted self-avatar path from the dump (added to l3_dump_state).
Future<String> _selfAvatarPath(Inst inst) async =>
    (await inst.dumpState())['selfAvatarPath']?.toString() ?? '';

/// Drive the REAL self-profile "change avatar" affordance (the camera InkWell,
/// `profile_avatar_edit_button`) with the native picker replaced by a
/// deterministic in-sandbox image via the test-account `l3_set_avatar_pick_path`
/// seam (the SAME real-control-plus-deterministic-input recipe the attachment
/// case uses). Asserts the dump's `selfAvatarPath` changed to a fresh path.
/// Returns true/false (HARD), or null (SKIP) only if the account can't be
/// test-marked. Caller must have the self-profile overlay OPEN.
Future<bool?> _driveAvatarChange(
  Inst inst, {
  required String pngB64,
  required String fileName,
  required String label,
}) async {
  final marked = await inst.markAccountTest();
  if (!marked) {
    print('[pair] $label: SKIP — could not test-mark account for avatar seam');
    return null;
  }
  try {
    final before = await _selfAvatarPath(inst);
    final set = await inst.l3('l3_set_avatar_pick_path', {
      'contentB64': pngB64,
      'fileName': fileName,
    });
    if (set['ok'] != true) {
      print('[pair] $label: FAIL — avatar seam set failed $set');
      return false;
    }
    await inst.foreground();
    // Tap the REAL camera "change avatar" affordance on the editable self
    // profile → _pickAvatar → pickAndPersistAvatar → the L3-aware picker returns
    // the materialized image and persists it.
    if (!await inst.tapKeyCenter('profile_avatar_edit_button', timeoutSecs: 6) &&
        !await inst.tryTapKey('profile_avatar_edit_button')) {
      print('[pair] $label: FAIL — avatar edit affordance not tappable');
      return false;
    }
    // Poll until the persisted path changes to a fresh value.
    var after = before;
    for (var i = 0; i < 20 && (after.isEmpty || after == before); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      after = await _selfAvatarPath(inst);
    }
    final changed = after.isNotEmpty && after != before;
    print('[pair] $label: before="$before" after="$after" changed=$changed');
    return changed;
  } finally {
    try {
      await inst.l3('l3_set_avatar_pick_path', {'path': ''});
    } on DriveError {
      // best-effort clear
    }
    await inst.unmarkAccountTest();
  }
}

/// case 19 — profile_avatar_picker_opens (S79): drive the REAL avatar-change
/// camera affordance; the picker returns a deterministic in-sandbox image (test
/// seam) so the self avatar actually changes. HARD: `selfAvatarPath` flips.
Future<bool?> _profileAvatarPickerOpens(Inst inst) async {
  if (!await _openSelfProfile(inst)) {
    print('[pair] profile_avatar_picker_opens: FAIL — self profile did not open');
    return false;
  }
  return _driveAvatarChange(
    inst,
    pngB64: _avatarPngRedB64,
    fileName: 'rui_avatar_1.png',
    label: 'profile_avatar_picker_opens',
  );
}

/// case 20 — profile_avatar_select_default_applies (S79): re-drive the real
/// avatar-change affordance with a DIFFERENT image → the apply persists a new
/// (distinct) path, proving re-selection applies. (There is no default-avatar
/// GRID in the app; the faithful runnable assertion is that selecting a new
/// avatar image applies + persists.) HARD: `selfAvatarPath` flips to a new path.
Future<bool?> _profileAvatarSelectDefaultApplies(Inst inst) async {
  if (!await _openSelfProfile(inst)) {
    print(
      '[pair] profile_avatar_select_default_applies: FAIL — self profile did '
      'not open',
    );
    return false;
  }
  return _driveAvatarChange(
    inst,
    pngB64: _avatarPngBlueB64,
    fileName: 'rui_avatar_2.png',
    label: 'profile_avatar_select_default_applies',
  );
}

/// Best-effort between-cases normalizer: dismiss any lingering self-profile
/// overlay so a failed case mid-overlay does not poison the next case (which
/// expects to open the overlay fresh from the home shell). Idempotent; never
/// throws.
Future<void> _normalizeProfileBetweenCases(Inst inst) async {
  try {
    await _closeSelfProfile(inst);
  } on DriveError catch (e) {
    print('[sweep] profile normalize: best-effort failed (ignored): ${e.message}');
  }
}

/// sweep_profile — Batch 2: chain all 8 self-profile cases on ONE launch. Cases
/// 13–18 are HARD gates; cases 19/20 are SKIPs (no in-app avatar surface — see
/// the case bodies). Order: open (13) → edit toggle roundtrip (14) → nickname
/// edit+restore (15) → status edit+restore (16) → copy toxid (17) → QR copy (18)
/// → avatar SKIPs (19/20). The edit cases RESTORE the original nick/status so a
/// later batch asserting the registered nick is not poisoned. Prints
/// `[sweep] <case>: PASS|FAIL|SKIP(<reason>)` per case + final counts; exits
/// non-zero if any HARD case fails.
Future<int> runProfileSweep(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
    timeoutSecs: 90,
  );
  // Start from a clean home shell: close any leftover profile overlay so the
  // first case (open-from-avatar) is a genuine fresh open, not a no-op on a
  // pre-mounted dialog (codex P1).
  await _normalizeProfileBetweenCases(inst);
  // (caseId, runner). A bool runner is a HARD gate; a null return is a SKIP.
  final cases = <MapEntry<String, Future<bool?> Function()>>[
    MapEntry(
      'profile_open_sidebar_avatar',
      () => _profileOpenSidebarAvatar(inst),
    ),
    MapEntry(
      'profile_edit_toggle_roundtrip',
      () => _profileEditToggleRoundtrip(inst),
    ),
    MapEntry(
      'profile_edit_nickname_persists',
      () => _profileEditNicknamePersists(inst),
    ),
    MapEntry(
      'profile_edit_status_persists',
      () => _profileEditStatusPersists(inst),
    ),
    MapEntry(
      'profile_copy_toxid_snackbar',
      () => _profileCopyToxIdSnackbar(inst),
    ),
    MapEntry('profile_qr_copy', () => _profileQrCopy(inst)),
    MapEntry(
      'profile_avatar_picker_opens',
      () => _profileAvatarPickerOpens(inst),
    ),
    MapEntry(
      'profile_avatar_select_default_applies',
      () => _profileAvatarSelectDefaultApplies(inst),
    ),
  ];

  var passed = 0;
  var failed = 0;
  var skipped = 0;
  for (final entry in cases) {
    bool? ok;
    String? failDetail;
    try {
      ok = await entry.value();
    } on PermissionBlockedError {
      rethrow; // surfaces as BLOCKED(78) at the driver level
    } on DriveError catch (e) {
      ok = false;
      failDetail = 'DriveError: ${e.message}';
    }
    if (ok == null) {
      skipped++;
      print('[sweep] ${entry.key}: SKIP(no-in-app-avatar-surface)');
    } else if (ok) {
      passed++;
      print('[sweep] ${entry.key}: PASS');
    } else {
      failed++;
      print(
        '[sweep] ${entry.key}: FAIL'
        '${failDetail != null ? ' ($failDetail)' : ''}',
      );
    }
    // Cross-case poison guard: a case that failed mid-overlay would leave the
    // profile dialog mounted, blocking the next case's open. Best-effort close.
    await _normalizeProfileBetweenCases(inst);
  }
  print(
    '[sweep] sweep_profile RESULTS: $passed PASS / $failed FAIL / '
    '$skipped SKIP (${cases.length} total)',
  );
  await inst.shot('/tmp/ui_profile_sweep_${inst.name}.png');
  return failed == 0 ? 0 : 1;
}
