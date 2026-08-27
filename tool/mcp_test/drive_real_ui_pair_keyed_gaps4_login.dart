// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Keyed-gaps batch #4 — the LOGIN-PAGE half. Spine and dispatch live in
// `drive_real_ui_pair_keyed_gaps4.dart`; this file holds only the case body so
// each part stays under the 500-LOC complexity cap.

/// The nickname of the throwaway account this case provisions and then deletes.
/// Deliberately distinct from `_p1SecondNick` so it can never be confused with
/// (or reused by) `_p1AccountDeleteFullFlow`'s account-#2 holder.
const _kg4ThrowawayNick = 'KG4DeleteProbe';

// ===========================================================================
// case — login_account_delete_confirm_removes_card
// ===========================================================================
/// `login_delete_account_confirm_button` — the LoginPage's delete-account
/// confirm action (lib/ui/login_page.dart:862). Its CANCEL twin is driven by
/// `login_account_delete_cancel` (sweep_account_conf_extra) and its input by
/// `login_delete_account_confirm_input`, but the confirm itself had never been
/// pressed by any scenario, so the whole destructive branch of this dialog was
/// dark.
///
/// WHY IT IS NOT ALREADY COVERED BY `_p1AccountDeleteFullFlow`. That helper
/// deletes through **Settings** (`settings_delete_account_confirm_button`),
/// i.e. `AccountService` with a LIVE service for the logged-in account. This
/// path is `AccountService.deleteAccountWithoutService(toxId:)` — a different
/// entry point, reached while LOGGED OUT, with a different confirmation branch
/// (no running service means no password is set on a fresh account, so the
/// dialog takes the confirm-WORD arm rather than the password arm).
///
/// WHAT IS ASSERTED — a real, irreversible state change plus its negative
/// control:
///   1. a throwaway account is provisioned through the REAL RegisterPage and
///      its saved-account card is present on the LoginPage;
///   2. the wrong-word guard holds: submitting an obviously wrong confirmation
///      word leaves the dialog OPEN and the card intact
///      (`inputController.text.trim().toLowerCase() != 'delete'` returns early
///      WITHOUT popping) — this is the leg that proves the confirm button is
///      really running the handler and not just closing a dialog;
///   3. after typing the required word, the confirm removes the card:
///      `login_page_account_card:<throwaway>` UNMOUNTS and stays gone;
///   4. the PRIMARY account's card is untouched, and A logs back into it — so
///      the sweep ends where it started.
///
/// SINGLE INSTANCE, `result=no-friend`: B is never touched, no friendship is
/// formed or deleted, and the only account removed is the one this case created
/// seconds earlier.
///
/// HARNESS HAZARD honoured: `login_delete_account_confirm_button` pops its
/// dialog, so it is driven with `tapKeyCenter` (one synthetic tap at the
/// element centre). flutter_skill's `tap` fires an on-screen dialog button
/// TWICE — the second pop would unwind the LoginPage itself and leave an empty
/// Navigator.
Future<bool?> _kg4LoginDeleteConfirm(Inst a, String nickA) async {
  const label = 'login_account_delete_confirm_removes_card';
  const deleteOption = 'login_account_management_delete_option';
  const confirmInput = 'login_delete_account_confirm_input';
  const confirmButton = 'login_delete_account_confirm_button';

  await ensureHome(a, nickA);
  final primaryTox =
      (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (primaryTox.isEmpty) {
    print('[pair] $label: could not read the primary account tox id');
    return false;
  }
  if ((await _logoutToLoginPage(a)).isEmpty) {
    print('[pair] $label: could not reach the LoginPage');
    return false;
  }
  final throwawayTox = await _p1RegisterSecondAccount(a, _kg4ThrowawayNick);
  if (throwawayTox.isEmpty) {
    print('[pair] $label: could not provision the throwaway account');
    return false;
  }
  if (throwawayTox == primaryTox) {
    print('[pair] $label: refusing — the throwaway IS the primary account');
    return false;
  }
  if ((await _logoutToLoginPage(a)) != throwawayTox) {
    print('[pair] $label: post-register logout did not land on the LoginPage');
    return false;
  }

  final cardKey = 'login_page_account_card:$throwawayTox';
  final primaryCardKey = 'login_page_account_card:$primaryTox';
  var wrongWordHeld = false;
  var cardGone = false;
  try {
    if (!await _waitForAccountCard(a, throwawayTox)) {
      print('[pair] $label: the throwaway account card never rendered');
      return false;
    }
    // --- open the per-card management menu -> Delete ---
    await a.longPressKey(cardKey);
    if (!await a.waitKey(deleteOption, timeoutSecs: 8)) {
      await a.shot('/tmp/ui_kg4_login_nomenu_${a.name}.png');
      print(
        '[pair] $label: the account-management menu did not open on a '
        'long-press of $cardKey',
      );
      return false;
    }
    if (!await a.tapKeyCenter(deleteOption, timeoutSecs: 8)) {
      print('[pair] $label: the Delete option could not be tapped');
      return false;
    }
    if (!await a.waitKey(confirmInput, timeoutSecs: 12)) {
      await a.shot('/tmp/ui_kg4_login_nodialog_${a.name}.png');
      print('[pair] $label: the delete-confirm dialog did not open');
      return false;
    }

    // --- leg 2: the WRONG word must NOT delete anything ---
    if (!await a.focusType(confirmInput, 'nope')) {
      print('[pair] $label: could not type into the confirm input');
      return false;
    }
    await a.tapKeyCenter(confirmButton, timeoutSecs: 8);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final dialogStillUp = await a.waitKey(confirmInput, timeoutSecs: 4);
    final cardStillThere = await a.waitKey(cardKey, timeoutSecs: 4);
    wrongWordHeld = dialogStillUp && cardStillThere;
    if (!wrongWordHeld) {
      await a.shot('/tmp/ui_kg4_login_wrongword_${a.name}.png');
      print(
        '[pair] $label: FAIL — the wrong-word guard did not hold '
        '(dialogStillUp=$dialogStillUp cardStillThere=$cardStillThere). The '
        'confirm handler returns early without popping when the typed word is '
        'not "delete"; a dialog that closed anyway means the guard was '
        'bypassed.',
      );
      // Fall through: the throwaway account still has to be cleaned up.
    }

    // --- leg 3: the RIGHT word deletes it ---
    if (dialogStillUp) {
      // `focusType` sets the field ATOMICALLY on every platform (osaClear +
      // paste on macOS, synthetic `enterText` elsewhere), so the wrong word is
      // REPLACED rather than appended — no `osaClear`, which would be a silent
      // no-op on an iOS Simulator and leave "nopedelete" in the field.
      if (!await a.focusType(confirmInput, 'delete')) {
        print('[pair] $label: could not type the confirmation word');
        return false;
      }
      if (!await a.tapKeyCenter(confirmButton, timeoutSecs: 8)) {
        print('[pair] $label: the confirm button could not be tapped');
        return false;
      }
    }
    cardGone = await a.waitKeyGone(cardKey, timeoutSecs: 20);
    await a.shot('/tmp/ui_kg4_login_deleted_${a.name}.png');
  } finally {
    // Always return to the primary account, whatever happened above — the
    // launch is reused by the next sweep.
    final backOnPrimary = await _quickLoginNoPassword(a, primaryTox);
    if (!backOnPrimary) {
      print('[pair] $label: WARNING — could not log back into the primary');
    }
  }

  final primaryIntact =
      (await a.dumpState())['currentAccountToxId']?.toString() == primaryTox;
  print(
    '[pair] $label: wrongWordHeld=$wrongWordHeld cardGone=$cardGone '
    'primaryIntact=$primaryIntact (primaryCard=$primaryCardKey)',
  );
  if (!cardGone) {
    print(
      '[pair] $label: the throwaway account "$_kg4ThrowawayNick" '
      '($throwawayTox) may still be on disk — a later run will see an extra '
      'saved-account card',
    );
  }
  return wrongWordHeld && cardGone && primaryIntact;
}

/// The SINGLE-instance login half. One case today; it lives in its own sweep
/// because it logs out, provisions a throwaway account and deletes it, which is
/// a `result=no-friend` contract the two-process sweep above does not have.
Future<int> runKeyedGaps4LoginSweep(Inst a, String nickA) async {
  final tally = _MobileShellTally('sweep_keyed_gaps4_login');
  await tally.run(
    'login_account_delete_confirm_removes_card',
    () => _kg4RunLoginCase(a, nickA),
  );
  await _msLandHome(a, 'sweep_keyed_gaps4_login');
  return tally.finish();
}
