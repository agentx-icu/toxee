// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// REGISTER-PAGE case bodies for `sweep_keyed_gaps`. Split out of
// drive_real_ui_pair_keyed_gaps.dart (which keeps the sweep, the dispatch and
// the shared helpers) so both halves stay under the 500-LOC complexity cap —
// they are one library, so this is organizational only. See that file's header
// for the batch rationale and the production keys added alongside these cases.
//
// SHARED CONTRACT. All four cases run on the LoginPage → RegisterPage:
// `_openRegisterPage` logs a live session out itself (and recovers a failed
// teardown), and every case ends with `_backOutOfRegister`. NO account is ever
// created — none of them submits the form with a valid nickname, so the launch's
// account list is unchanged. `_kgNormalize` relogins afterwards.
//
// INPUT PATH. Only `focusType`, which is real OS paste on macOS/Linux/Windows
// and flutter_skill `enterText` on iOS/Android — never a raw `osa*` chord — so
// these cases are honest on a Simulator/emulator too, which is why
// `sweep_keyed_gaps` is registered in the mobile campaign chains.

// ===========================================================================
// register_status_field_length_guard
// ===========================================================================
/// Drive `register_status_field` — the ONE register input no scenario had ever
/// typed into — and assert its length validator BOTH WAYS.
///
/// OBSERVABLE SIDE EFFECT: `_statusMessageField.decoration.errorText` is
/// non-null exactly while `calculateTextLength(text) > 24`, so the localized
/// "Status message too long" string MOUNTS on the over-long value and UNMOUNTS
/// again on a short one. The flip (not just the appearance) is what proves the
/// field's own `onChanged`/rebuild path ran — a case that only asserted the
/// error appearing would still pass against a field permanently stuck in error.
///
/// The typed value is also read back through `getTextValue` so an input path
/// that silently dropped the paste cannot green the case on a stale error.
///
/// THE OVER-LONG VALUE MUST BE CJK, not ASCII (live-diagnosed 2026-08-16, the
/// first-ever execution of this case). `calculateTextLength`
/// (`lib/util/account_service.dart:160`) weighs a CJK code point 1.0 and every
/// other character 0.5, and the field pins `maxLength: 48`. So the heaviest
/// pure-ASCII value the field can physically hold is 48 * 0.5 == 24.0, which is
/// NOT `> 24` — an ASCII probe can never trip the guard no matter how long it
/// is, and the original 30-char ASCII string scored 15.0. 25 CJK characters
/// score 25.0 and clear the cap while staying well inside `maxLength`.
Future<bool?> _kgRegisterStatusFieldLengthGuard(Inst inst) async {
  const label = 'register_status_field_length_guard';
  const tooLongError = 'Status message too long';
  // 25 CJK characters => calculateTextLength == 25.0 > the 24 cap, and 25 code
  // points is far under the field's maxLength of 48.
  const overLong = '状态消息超长测试用例填充文字内容甲乙丙丁戊己庚辛壬';
  const shortOk = 'RuiKgOk';
  if (!await _openRegisterPage(inst)) {
    print('[pair] $label: RegisterPage did not open');
    return false;
  }
  try {
    await inst.focusType('register_status_field', overLong);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final typedBack =
        (await inst.skill('getTextValue', const {
              'key': 'register_status_field',
            }))['value']
            ?.toString();
    final errorShown = await inst.waitText(tooLongError, timeoutSecs: 6);
    await inst.shot('/tmp/ui_kg_status_too_long_${inst.name}.png');

    await inst.focusType('register_status_field', shortOk);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final errorCleared = await inst.waitTextGone(tooLongError, timeoutSecs: 6);
    final shortTypedBack =
        (await inst.skill('getTextValue', const {
              'key': 'register_status_field',
            }))['value']
            ?.toString();

    // Leave the field empty so a rerun / the next case starts clean.
    await inst.focusType('register_status_field', '');
    print(
      '[pair] $label: typedBack=${typedBack?.length} errorShown=$errorShown '
      'errorCleared=$errorCleared shortTypedBack="$shortTypedBack"',
    );
    return typedBack == overLong &&
        errorShown &&
        errorCleared &&
        shortTypedBack == shortOk;
  } finally {
    await _backOutOfRegister(inst);
  }
}

// ===========================================================================
// register_confirm_match_icon_flips
// ===========================================================================
/// Drive `register_confirm_match_icon` — the check/cancel badge inside the
/// confirm-password field's suffix — through mismatch → match → absent.
///
/// OBSERVABLE SIDE EFFECT, in three steps:
///   1. mismatched confirm → the state-encoded `register_confirm_match_mismatch`
///      wrapper is onstage (and `register_confirm_match_icon` with it);
///   2. confirm retyped to MATCH → `register_confirm_match_ok` is onstage and
///      the mismatch key is GONE — the badge FLIPPED, it did not merely exist;
///   3. confirm cleared → the whole badge unmounts (the widget is guarded by
///      `confirm.isNotEmpty && password.isNotEmpty`).
/// Step 2 is the one a "the icon rendered" case would miss: the icon key alone
/// is identical for check_circle and cancel, which is exactly why the
/// state-encoded sibling key was added.
///
/// The keys sit on a `KeyedSubtree`/`Icon`, which flutter_skill's interactive
/// index does not surface — hence `waitKeyCenter` / `_kgWaitKeyCenterGone`
/// (element-tree walk) rather than `waitKey` / `waitKeyGone`.
Future<bool?> _kgRegisterConfirmMatchIconFlips(Inst inst) async {
  const label = 'register_confirm_match_icon_flips';
  if (!await _openRegisterPage(inst)) {
    print('[pair] $label: RegisterPage did not open');
    return false;
  }
  try {
    await inst.focusType('register_page_password_field', 'RuiKgMatch1!');
    await inst.focusType(
      'register_page_confirm_password_field',
      'RuiKgMatch2!',
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final mismatchUp = await inst.waitKeyCenter(
      'register_confirm_match_mismatch',
      timeoutSecs: 6,
    );
    final badgeUp = await inst.waitKeyCenter(
      'register_confirm_match_icon',
      timeoutSecs: 4,
    );
    if (!mismatchUp || !badgeUp) {
      await inst.shot('/tmp/ui_kg_confirm_nomismatch_${inst.name}.png');
      print('[pair] $label: mismatch badge never mounted (badge=$badgeUp)');
      return false;
    }

    await inst.focusType(
      'register_page_confirm_password_field',
      'RuiKgMatch1!',
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final okUp = await inst.waitKeyCenter(
      'register_confirm_match_ok',
      timeoutSecs: 6,
    );
    final mismatchGone = await _kgWaitKeyCenterGone(
      inst,
      'register_confirm_match_mismatch',
      timeoutSecs: 6,
    );
    await inst.shot('/tmp/ui_kg_confirm_match_${inst.name}.png');

    // Clearing the confirm field must take the whole badge back out of the tree.
    await inst.focusType('register_page_confirm_password_field', '');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final badgeGone = await _kgWaitKeyCenterGone(
      inst,
      'register_confirm_match_icon',
      timeoutSecs: 6,
    );
    await inst.focusType('register_page_password_field', '');
    print(
      '[pair] $label: mismatchUp=$mismatchUp okUp=$okUp '
      'mismatchGone=$mismatchGone badgeGone=$badgeGone',
    );
    return okUp && mismatchGone && badgeGone;
  } finally {
    await _backOutOfRegister(inst);
  }
}

// ===========================================================================
// register_confirm_visibility_toggle_flips
// ===========================================================================
/// Drive `register_confirm_visibility_toggle` — the confirm field's own
/// show/hide button, distinct from the already-covered password one.
///
/// OBSERVABLE SIDE EFFECT: `obscureText` is not readable through the field's
/// value, so the flip is observed through the state-suffixed icon key
/// `register_confirm_visibility_icon_{obscured,visible}` — the same seam the
/// shipped `register_password_visibility_toggle` case uses.
///
/// EXTRA ASSERTION (the reason this is not a copy of the password case): the two
/// toggles own SEPARATE state (`_passwordObscure` vs `_confirmPasswordObscure`).
/// So while the confirm field is revealed, the PASSWORD field must still report
/// `obscured`. A regression that collapsed both onto one flag would pass a
/// single-field assertion and fail this one.
Future<bool?> _kgRegisterConfirmVisibilityToggleFlips(Inst inst) async {
  const label = 'register_confirm_visibility_toggle_flips';
  if (!await _openRegisterPage(inst)) {
    print('[pair] $label: RegisterPage did not open');
    return false;
  }
  try {
    // Give BOTH fields content so the case is faithful to a user revealing a
    // typed confirmation (the toggle itself works either way).
    await inst.focusType('register_page_password_field', 'RuiKgVis1!');
    await inst.focusType('register_page_confirm_password_field', 'RuiKgVis1!');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final startObscured = await inst.waitKeyCenter(
      'register_confirm_visibility_icon_obscured',
      timeoutSecs: 6,
    );
    if (!startObscured) {
      await inst.shot('/tmp/ui_kg_confirm_vis_absent_${inst.name}.png');
      print('[pair] $label: the confirm field did not start obscured');
      return false;
    }
    // The toggle is a suffix IconButton; a single synthetic tapAt on it is
    // live-observed to be occasionally swallowed on a Simulator, which would
    // leave BOTH legs of the flip vacuously "true" (never revealed => still
    // obscured). Tap until the state key actually moves — the flip itself
    // stays the hard assertion.
    final revealed = await _kgTapUntilKeyCenter(
      inst,
      'register_confirm_visibility_toggle',
      'register_confirm_visibility_icon_visible',
    );
    // Independence check while the confirm field is revealed.
    final passwordStillObscured =
        await inst.keyCenter('register_password_visibility_icon_obscured') !=
        null;
    final hiddenAgain = await _kgTapUntilKeyCenter(
      inst,
      'register_confirm_visibility_toggle',
      'register_confirm_visibility_icon_obscured',
    );
    final visibleGone = await _kgWaitKeyCenterGone(
      inst,
      'register_confirm_visibility_icon_visible',
      timeoutSecs: 6,
    );
    await inst.shot('/tmp/ui_kg_confirm_vis_${inst.name}.png');
    await inst.focusType('register_page_confirm_password_field', '');
    await inst.focusType('register_page_password_field', '');
    print(
      '[pair] $label: startObscured=$startObscured revealed=$revealed '
      'passwordStillObscured=$passwordStillObscured '
      'hiddenAgain=$hiddenAgain visibleGone=$visibleGone',
    );
    return revealed &&
        passwordStillObscured &&
        hiddenAgain &&
        visibleGone;
  } finally {
    await _backOutOfRegister(inst);
  }
}

// ===========================================================================
// register_strength_segments_ramp
// ===========================================================================
/// Drive `register_password_strength_bar` and its four
/// `register_strength_segment_<i>` segments across the FULL 0→4 ramp.
///
/// WHY THIS IS NOT A DUPLICATE OF `register_password_strength_flips`. That case
/// reads the CAPTION Text ("Weak"/"Strong") and only pins two of the five
/// rungs. The bar container and the four segments themselves were never
/// asserted at all — their fill state is a `BoxDecoration.color`, invisible to a
/// key-driving harness. The state-encoded sibling keys
/// `register_strength_segment_<i>_{filled,empty}` added with this case make the
/// SEGMENTS observable, so this case pins every rung the widget can render:
///
///   ""          → 0 filled   (caption absent, bar still mounted)
///   "abc"       → 1 filled   (len < 6)
///   "abcdefg"   → 2 filled   (len >= 6, no upper/digit)
///   "Abcdefg1"  → 3 filled   (len >= 8 + upper + digit)
///   "Abcdef1!"  → 4 filled   (… + special)
///   ""          → back to 0  (the ramp is reversible, not one-way latched)
///
/// Nothing is submitted, so no account is created.
Future<bool?> _kgRegisterStrengthSegmentsRamp(Inst inst) async {
  const label = 'register_strength_segments_ramp';
  if (!await _openRegisterPage(inst)) {
    print('[pair] $label: RegisterPage did not open');
    return false;
  }
  try {
    final barUp = await inst.waitKeyCenter(
      'register_password_strength_bar',
      timeoutSecs: 8,
    );
    if (!barUp) {
      await inst.shot('/tmp/ui_kg_strength_nobar_${inst.name}.png');
      print('[pair] $label: the strength bar never mounted');
      return false;
    }
    // Start from a known-empty field: the sweep may have run a prior case that
    // left a password behind.
    await inst.focusType('register_page_password_field', '');
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final rungs = <String, int>{
      '': 0,
      'abc': 1,
      'abcdefg': 2,
      'Abcdefg1': 3,
      'Abcdef1!': 4,
    };
    var allOk = true;
    final report = <String>[];
    Future<bool> assertRung(String password, int expected) async {
      if (password.isNotEmpty) {
        await inst.focusType('register_page_password_field', password);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      var ok = true;
      for (var i = 0; i < 4; i++) {
        final want = i < expected ? 'filled' : 'empty';
        final other = i < expected ? 'empty' : 'filled';
        final wantOk = await inst.waitKeyCenter(
          'register_strength_segment_${i}_$want',
          timeoutSecs: 4,
        );
        // The two variants are mutually exclusive by construction; asserting the
        // other one is ABSENT catches a stale frame that still carries both.
        final otherGone =
            await inst.keyCenter('register_strength_segment_${i}_$other') ==
            null;
        if (!wantOk || !otherGone) ok = false;
      }
      report.add('"$password"->$expected:${ok ? 'ok' : 'BAD'}');
      return ok;
    }

    for (final entry in rungs.entries) {
      if (!await assertRung(entry.key, entry.value)) allOk = false;
    }
    // Reversibility: back to empty must return every segment to `empty`.
    await inst.focusType('register_page_password_field', '');
    final reversible = await assertRung('', 0);
    await inst.shot('/tmp/ui_kg_strength_segments_${inst.name}.png');
    print(
      '[pair] $label: bar=$barUp ramp=${report.join(' ')} '
      'reversible=$reversible',
    );
    return allOk && reversible;
  } finally {
    await _backOutOfRegister(inst);
  }
}
