// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 3 of the real-UI sweep campaign — "Login / register" (9 cases, single
// instance, one launch). See tool/mcp_test/REAL_UI_SWEEP_CAMPAIGN.md.
//
// State-machine care is the whole game here: the sweep starts from a fresh
// registered HomePage (ensureHome), then drives login + register surfaces that
// MUTATE the session/account state, and must END CLEAN — logged into the
// PRIMARY account, NO password, autoLogin intact. The chosen order:
//
//   logout (serves 21+22) ->
//   22 login_register_open_back  (on LoginPage: Register CTA -> RegisterPage -> back)
//   21 login_account_card_renders (the saved-account card shows nick + tox prefix)
//   26 login_restore_entry_opens  (SKIP — native NSOpenPanel only, no in-app surface)
//   23 register_empty_nickname_error   (RegisterPage validation; NO account created)
//   24 register_password_mismatch_error (RegisterPage validation; NO account created)
//   25 register_password_strength_flips (RegisterPage strength caption weak->strong)
//   quick-login back to the primary account (no password) -> HomePage
//   27 login_password_wrong_error   (set pw via settings, logout, WRONG pw -> error, stays)
//   28 login_password_correct_unlocks (CORRECT pw -> HomePage; then REMOVE the password)
//   29 account_switch_second_account  (register account #2, then switch back to primary)
//
// PASSWORD-RESTORE ANSWER (the brief's open question): the PRODUCTION settings
// UI CAN clear a password. `_showSetPasswordDialog` accepts an EMPTY new+confirm
// (hint "Leave empty to remove password"); on empty input `_setAccountPassword`
// routes to `AccountService.removeAccountPassword` and shows the "Password
// removed" snackbar. So case 28 unlocks with the correct password, then opens
// the settings change-password dialog and submits EMPTY fields to restore the
// no-password state. The sweep therefore ends with the primary account
// password-free (verified via the no-prompt quick-login at the very end).
//
// CASE 26 is a SKIP: the login "Restore from .tox file" card
// (UiKeys.loginPageRestoreFromToxFile) calls `_restoreFromToxFile` ->
// `LoginPageController.restoreFromToxFile`, which opens the native
// `FilePicker.platform.pickFiles` DIRECTLY — there is NO in-app pre-picker /
// options surface to assert mounting. The login "settings" entry
// (login_page_settings_button) opens LoginSettingsPage, which is the
// bootstrap/global settings page, NOT a restore/import surface. The native panel
// cannot be driven headless and there is no test-account l3 override here, so
// case 26 returns null (SKIP) — never a fake pass. (Hermetic coverage of the
// real restore handler lives in login_restore_import_settings_real_ui_test.dart,
// which injects a controller seam.)

const _b3PrimaryPassword = 'RuiSweepB3Pw1!';
const _b3SecondNick = 'RuiSweepB3';

/// On the LoginPage, wait for THIS account's saved-account card to render and
/// return whether it appeared. The async saved-account-list load only pumps
/// while the window is foreground (a backgrounded window stalls it), so
/// re-foreground each round. Mirrors `_settingsLogoutRelogin`'s recovery loop.
Future<bool> _waitForAccountCard(
  Inst inst,
  String toxId, {
  int rounds = 15,
}) async {
  final cardKey = 'login_page_account_card:$toxId';
  for (var round = 0; round < rounds; round++) {
    await inst.foreground();
    final loggedOut = (await inst.dumpState())['sessionReady'] != true;
    if (loggedOut && await inst.waitKey(cardKey, timeoutSecs: 2)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  return false;
}

/// Logout the current session via the real Settings -> Logout -> confirm flow,
/// landing on the LoginPage with THIS account's saved-account card present.
/// Returns the current account's toxId (empty on failure). Reuses the
/// single-fire confirm discipline (`tapKeyCenter`) from `_settingsLogoutRelogin`
/// so the double-fire blank-screen hazard cannot fire.
Future<String> _logoutToLoginPage(Inst inst) async {
  final toxId =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxId.isEmpty) {
    print('[pair] logout: no current toxId');
    return '';
  }
  if (_isIosRealUi) {
    if (!await _openMobileAccountManagement(inst)) {
      print('[pair] logout: Account Management section did not open');
      return '';
    }
  } else {
    await _openSettings(inst);
  }
  // The logout opener is BELOW the fold of the settings ListView (_openSettings
  // leaves the list scrolled to the TOP). A bare tapKey is flaky: when the
  // button sits beyond flutter_skill's cacheExtent it isn't built, so the tap
  // lands on nothing and the confirm dialog never opens ("logout: confirm
  // dialog did not open"). Scroll it into the visible band first, then
  // center-tap its resolved position (tryTapKey fallback).
  if (!_isIosRealUi &&
      !await _settingsScrollTo(inst, 'settings_logout_button')) {
    print('[pair] logout: logout button not in band');
  }
  if (!await inst.tapKeyCenter('settings_logout_button', timeoutSecs: 6)) {
    await inst.tryTapKey('settings_logout_button');
  }
  if (!await inst.waitKey('settings_logout_confirm_button', timeoutSecs: 8)) {
    print('[pair] logout: confirm dialog did not open');
    return '';
  }
  if (!await inst.tapKeyCenter('settings_logout_confirm_button')) {
    print('[pair] logout: confirm button not tappable');
    return '';
  }
  if (!await _waitForAccountCard(inst, toxId)) {
    await inst.foreground();
    await inst.shot('/tmp/ui_b3_logout_${inst.name}.png');
    print(
      '[pair] logout: account card never rendered (tox=${_shortId(toxId)})',
    );
    return '';
  }
  return toxId;
}

/// Quick-login the saved-account card for [toxId] on a NO-PASSWORD account and
/// wait for the session to be ready (HomePage). Returns whether it logged in.
Future<bool> _quickLoginNoPassword(Inst inst, String toxId) async {
  final cardKey = 'login_page_account_card:$toxId';
  if (!await inst.waitKey(cardKey, timeoutSecs: 6)) {
    if (!await _waitForAccountCard(inst, toxId)) {
      print('[pair] quick-login: card $cardKey not present');
      return false;
    }
  }
  // Use flutter_skill's key `tap` (NOT tapKeyCenter): a raw `tapAt` at the card
  // center does NOT reliably fire the card's `InkWell.onTap` (live-verified: the
  // single pointer tap left sessionReady=false, while the key `tap` logged in),
  // because `tap` additionally invokes the widget callback directly via
  // `_tryInvokeCallback`. The original SINGLE-FIRE concern (double-firing
  // `_quickLogin` opening a 2nd password prompt) does NOT apply here: this is the
  // NO-PASSWORD account, so the worst case is a 2nd idempotent `_login()` while
  // the first is already in flight. (The PASSWORD quick-login in case 28 keeps
  // its own single-fire discipline — it does not go through this helper.)
  if (!await inst.tryTapKey(cardKey)) {
    print('[pair] quick-login: card $cardKey not tappable');
    return false;
  }
  await inst.foreground();
  final ready = await _waitBoolState(
    inst,
    'sessionReady',
    true,
    timeoutSecs: 40,
  );
  // Land on the home shell so the next case can re-open Settings cleanly.
  if (ready) {
    await inst.foreground();
    await inst.waitKey('new_entry_menu_button', timeoutSecs: 15);
  }
  print('[pair] quick-login no-password (${_shortId(toxId)}): ready=$ready');
  return ready;
}

/// case 22 — login_register_open_back (S4): on the LoginPage, tap the "Register
/// new account" CTA -> the RegisterPage mounts (its keyed nickname field), then
/// tap the AppBar back button -> we are back on the LoginPage (the saved-account
/// card or the Register CTA is showing again). NO account is created (we never
/// submit). PRECONDITION: already on the LoginPage (the sweep logs out first).
Future<bool> _loginRegisterOpenBack(Inst inst) async {
  await inst.foreground();
  // Open RegisterPage via the real "Register new account" action. Prefer the
  // keyed card (reliable hit-testing on the wide desktop layout, where a by-text
  // tap can land on the card's label without triggering its InkWell); fall back
  // to the text tap.
  if (!await inst.tapKeyCenter('login_page_register_account_card',
          timeoutSecs: 6) &&
      !await _tryTapText(inst, 'Register new account')) {
    print('[pair] register_open_back: Register CTA not tappable');
    return false;
  }
  final opened = await inst.waitKey(
    'register_page_nickname_field',
    timeoutSecs: 10,
  );
  if (!opened) {
    print('[pair] register_open_back: RegisterPage did not mount');
    return false;
  }
  // Back out via the keyed AppBar back button (single-fire: it pops the route,
  // and a double-fire would pop the LoginPage underneath -> blank).
  var backed = false;
  if (await inst.tapKeyCenter('register_back_button', timeoutSecs: 6)) {
    backed = await inst.waitKeyGone(
      'register_page_nickname_field',
      timeoutSecs: 6,
    );
  }
  // Back on the LoginPage: the Register CTA text is visible again (proves we
  // returned to the login surface, not a blank Navigator).
  final onLogin =
      backed && await inst.waitText('Register new account', timeoutSecs: 6);
  print(
    '[pair] login_register_open_back: opened=$opened backed=$backed '
    'onLogin=$onLogin',
  );
  return opened && backed && onLogin;
}

/// case 21 — login_account_card_renders (S2): on the LoginPage, the primary
/// account's saved-account card renders showing the registered NICKNAME and the
/// first 8 hex of its Tox ID (the card prints "User ID: <prefix>…"). Asserts the
/// keyed card is present AND both the nickname Text and the tox-prefix Text are
/// onstage. PRECONDITION: logged out (the sweep logs out first); [toxId]/[nick]
/// are the primary account's.
Future<bool> _loginAccountCardRenders(
  Inst inst,
  String toxId,
  String nick,
) async {
  await inst.foreground();
  final cardKey = 'login_page_account_card:$toxId';
  final cardShown =
      await inst.waitKey(cardKey, timeoutSecs: 6) ||
      await _waitForAccountCard(inst, toxId);
  if (!cardShown) {
    print('[pair] account_card_renders: card $cardKey not present');
    return false;
  }
  final nickShown = await inst.waitText(nick, timeoutSecs: 6);
  // The card renders "User ID: <first8hex>…"; assert the prefix substring is
  // onstage. waitText needs the EXACT Text data, so match the whole label the
  // card builds: "User ID: <prefix>…".
  final prefix = toxId.length >= 8 ? toxId.substring(0, 8) : toxId;
  final idLabelShown = await inst.waitText('User ID: $prefix…', timeoutSecs: 4);
  print(
    '[pair] login_account_card_renders: card=$cardShown nick=$nickShown '
    '(want "$nick") idLabel=$idLabelShown (prefix=$prefix)',
  );
  return cardShown && nickShown && idLabelShown;
}

/// case 26 — login_restore_entry_opens (S9/S71): SKIP. The "Restore from .tox
/// file" card (UiKeys.loginPageRestoreFromToxFile) opens the NATIVE
/// FilePicker.platform.pickFiles directly (LoginPageController.restoreFromToxFile)
/// — there is NO in-app pre-picker / options surface to assert mounting, and the
/// login "settings" entry opens LoginSettingsPage (bootstrap/global settings,
/// NOT a restore surface). The native panel cannot be driven headless and there
/// is no test-account l3 override here, so this returns null (SKIP) rather than
/// a fake pass. See the header comment for the full rationale + the hermetic
/// controller-seam coverage in login_restore_import_settings_real_ui_test.dart.
Future<bool?> _loginRestoreEntryOpens(Inst inst) async {
  print(
    '[pair] login_restore_entry_opens: SKIP — restore card opens the native '
    'NSOpenPanel directly (no in-app pre-picker surface; login settings entry '
    'is bootstrap/global settings only)',
  );
  return null;
}

/// Open the RegisterPage from the LoginPage (idempotent: returns true if already
/// on it). Foregrounds + retries the Register CTA a few rounds.
Future<bool> _openRegisterPage(Inst inst) async {
  for (var round = 0; round < 4; round++) {
    await inst.foreground();
    if (await inst.waitKey('register_page_nickname_field', timeoutSecs: 2)) {
      return true;
    }
    if (await _tryTapText(inst, 'Register new account')) {
      if (await inst.waitKey('register_page_nickname_field', timeoutSecs: 6)) {
        return true;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  return false;
}

/// Back out of the RegisterPage to the LoginPage via the keyed AppBar back
/// button (single-fire). Best-effort; returns whether the nickname field is gone.
Future<bool> _backOutOfRegister(Inst inst) async {
  await inst.foreground();
  if (!await inst.waitKey('register_page_nickname_field', timeoutSecs: 1)) {
    return true; // already off the RegisterPage
  }
  if (await inst.tapKeyCenter('register_back_button', timeoutSecs: 6)) {
    if (await inst.waitKeyGone(
      'register_page_nickname_field',
      timeoutSecs: 6,
    )) {
      return true;
    }
  }
  try {
    await inst.osaEscape();
  } on DriveError {
    // best-effort
  }
  return inst.waitKeyGone('register_page_nickname_field', timeoutSecs: 4);
}

/// case 23 — register_empty_nickname_error (S4): on the RegisterPage, leave the
/// nickname EMPTY and tap Register -> the form validator surfaces the
/// "Nickname cannot be empty" inline error and NO account is created (validate()
/// short-circuits `_register` before the FFI register call). Asserts the error
/// text AND that we are still on the RegisterPage (session NOT ready). Backs out
/// to the LoginPage at the end.
Future<bool> _registerEmptyNicknameError(Inst inst) async {
  if (!await _openRegisterPage(inst)) {
    print('[pair] register_empty_nickname: RegisterPage did not open');
    return false;
  }
  // Make sure the nickname field is empty (clear it via real OS keys after a
  // focus tap; a fresh RegisterPage starts empty, but be robust to reuse).
  await inst.tapKey('register_page_nickname_field');
  await Future<void>.delayed(const Duration(milliseconds: 250));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort
  }
  // The Register button is ENABLED on an empty nickname (its disable condition
  // only checks length caps), so tapping fires _register -> _formKey.validate()
  // -> the nickname validator returns the empty error. tapKey (single fire
  // off-screen safe; it does not pop a route).
  await inst.tapKey('register_page_register_button');
  final errorShown = await inst.waitText(
    'Nickname cannot be empty',
    timeoutSecs: 8,
  );
  // Still on the RegisterPage (no navigation), session NOT ready (no account
  // was created).
  final stillOnRegister = await inst.waitKey(
    'register_page_nickname_field',
    timeoutSecs: 3,
  );
  final notLoggedIn = (await inst.dumpState())['sessionReady'] != true;
  final backed = await _backOutOfRegister(inst);
  print(
    '[pair] register_empty_nickname_error: error=$errorShown '
    'stillOnRegister=$stillOnRegister notLoggedIn=$notLoggedIn backed=$backed',
  );
  return errorShown && stillOnRegister && notLoggedIn && backed;
}

/// case 24 — register_password_mismatch_error (S4): on the RegisterPage, type a
/// throwaway nickname + MISMATCHED password/confirm and tap Register -> the
/// confirm-password validator surfaces "Passwords do not match" inline and NO
/// account is created (validate() short-circuits before the FFI register call).
/// Asserts the error AND still-on-RegisterPage + session NOT ready, then backs
/// out. The nickname is non-empty so the empty-nickname guard doesn't mask the
/// password error; nothing is created because validate() returns false.
Future<bool> _registerPasswordMismatchError(Inst inst) async {
  if (!await _openRegisterPage(inst)) {
    print('[pair] register_password_mismatch: RegisterPage did not open');
    return false;
  }
  await inst.focusType('register_page_nickname_field', 'RuiTmp');
  await inst.focusType('register_page_password_field', 'PasswordOne1!');
  await inst.focusType('register_page_confirm_password_field', 'PasswordTwo2!');
  await inst.tapKey('register_page_register_button');
  final errorShown = await inst.waitText(
    'Passwords do not match',
    timeoutSecs: 8,
  );
  final stillOnRegister = await inst.waitKey(
    'register_page_nickname_field',
    timeoutSecs: 3,
  );
  final notLoggedIn = (await inst.dumpState())['sessionReady'] != true;
  final backed = await _backOutOfRegister(inst);
  print(
    '[pair] register_password_mismatch_error: error=$errorShown '
    'stillOnRegister=$stillOnRegister notLoggedIn=$notLoggedIn backed=$backed',
  );
  return errorShown && stillOnRegister && notLoggedIn && backed;
}

/// case 25 — register_password_strength_flips (S4): on the RegisterPage, type a
/// WEAK password -> the strength caption reads "Weak"; type a STRONG password ->
/// it flips to "Strong". The caption (UiKeys-less keyed Text
/// `register_password_strength_label`, a Batch-3 production a11y addition) is the
/// text-matchable signal of the weak->strong ramp (the colored segments alone are
/// not text-matchable by widget-driving automation). NO account is created
/// (typing only). Clears the password fields + backs out at the end so case 23's
/// rerun starts clean.
Future<bool> _registerPasswordStrengthFlips(Inst inst) async {
  if (!await _openRegisterPage(inst)) {
    print('[pair] register_password_strength: RegisterPage did not open');
    return false;
  }
  // Weak: a short all-lowercase password -> strength 1 -> caption "Weak". Type
  // via focusType (REAL keystrokes; the synthetic enterText path SIGSEGVs the
  // macOS engine's setEditingState AND its osaClear+enterText combo did not
  // reliably REPLACE the field, so the strong password was computed against
  // stale content and never reached "Strong").
  await inst.focusType('register_page_password_field', 'abc');
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final weakShown = await inst.waitText('Weak', timeoutSecs: 6);
  // Strong: upper + digit + special, >= 8 chars -> strength 4 -> caption
  // "Strong". focusType clears (Cmd+A, Delete) then types, so it REPLACES.
  await inst.focusType('register_page_password_field', 'Abcdef1!');
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final strongShown = await inst.waitText('Strong', timeoutSecs: 6);
  // The "Weak" caption must be GONE once the password is strong (proves the
  // caption FLIPPED, not just that "Strong" also appeared somewhere).
  final weakGone = await inst.waitTextGone('Weak', timeoutSecs: 4);
  // Clear the field so a rerun / back-out leaves no typed password.
  await inst.tapKey('register_page_password_field');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort
  }
  final backed = await _backOutOfRegister(inst);
  print(
    '[pair] register_password_strength_flips: weak=$weakShown '
    'strong=$strongShown weakGone=$weakGone backed=$backed',
  );
  return weakShown && strongShown && weakGone && backed;
}

/// Set a KNOWN password on the current (logged-in) account via the real Settings
/// set/change-password dialog. Returns whether the success snackbar fired AND
/// the dialog closed. Mirrors `_settingsPassword` but uses a deterministic
/// password so the later wrong/correct cases can supply it.
/// Open the Settings set/change-password dialog with a SINGLE tap (codex P2):
/// `settings_set_password_button`'s onPressed (`_setAccountPassword`) has no
/// reentrancy guard, so flutter_skill's double-firing `tapKey` could stack two
/// dialogs. After scrolling it on-screen, single-fire via `tapKeyCenter`; if the
/// bounds can't resolve (still below the fold), fall back to `tapKey` (whose
/// direct off-screen `_tryInvokeCallback` fires exactly once). Returns whether
/// the dialog's keyed field appeared.
Future<bool> _openSetPasswordDialog(Inst inst) async {
  if (_isIosRealUi) {
    if (!await _openMobileAccountManagement(inst)) {
      print('[pair] set_password: Account Management section did not open');
      return false;
    }
  } else {
    await _openSettings(inst);
  }
  final onScreen = _isIosRealUi
      ? await inst.waitKey('settings_set_password_button', timeoutSecs: 4)
      : await _settingsScrollTo(inst, 'settings_set_password_button');
  if (onScreen) {
    if (await inst.tapKeyCenter(
      'settings_set_password_button',
      timeoutSecs: 4,
    )) {
      if (await inst.waitKey(
        'settings_set_password_new_field',
        timeoutSecs: 8,
      )) {
        return true;
      }
    }
  } else {
    print('[pair] set_password: button below fold -> single off-screen tapKey');
  }
  // Fallback: below-fold single-fire opener (direct callback fires once).
  await inst.tapKey('settings_set_password_button');
  return inst.waitKey('settings_set_password_new_field', timeoutSecs: 8);
}

Future<bool> _setKnownPassword(Inst inst, String pw) async {
  if (!await _openSetPasswordDialog(inst)) {
    print('[pair] set_password: dialog did not open');
    return false;
  }
  await inst.focusType('settings_set_password_new_field', pw);
  await inst.focusType('settings_set_password_confirm_field', pw);
  if (!await inst.tapKeyCenter('settings_set_password_save_button')) {
    print('[pair] set_password: save button not tappable');
    return false;
  }
  // Real PBKDF2 runs on the live isolate (~25s budget per the settings recipe).
  final saved = await inst.waitText(
    'Password set successfully',
    timeoutSecs: 30,
  );
  final dialogClosed = await inst.waitKeyGone(
    'settings_set_password_new_field',
    timeoutSecs: 8,
  );
  print('[pair] set_password: saved=$saved dialogClosed=$dialogClosed');
  return saved && dialogClosed;
}

/// Remove the password from the current (logged-in) account via the real
/// Settings change-password dialog: open it and submit EMPTY new+confirm fields
/// -> production routes to AccountService.removeAccountPassword and shows the
/// "Password removed" snackbar. Returns whether the snackbar fired AND the
/// dialog closed (restoring the no-password state). This is the production
/// password-clearing surface (hint text: "Leave empty to remove password").
Future<bool> _removePasswordViaSettings(Inst inst) async {
  if (!await _openSetPasswordDialog(inst)) {
    print('[pair] remove_password: dialog did not open');
    return false;
  }
  // Leave BOTH fields empty (clear them in case the dialog pre-filled), then
  // Save -> empty password == remove.
  await inst.tapKey('settings_set_password_new_field');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort
  }
  await inst.tapKey('settings_set_password_confirm_field');
  await Future<void>.delayed(const Duration(milliseconds: 200));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort
  }
  if (!await inst.tapKeyCenter('settings_set_password_save_button')) {
    print('[pair] remove_password: save button not tappable');
    return false;
  }
  final removed = await inst.waitText('Password removed', timeoutSecs: 30);
  final dialogClosed = await inst.waitKeyGone(
    'settings_set_password_new_field',
    timeoutSecs: 8,
  );
  print('[pair] remove_password: removed=$removed dialogClosed=$dialogClosed');
  return removed && dialogClosed;
}

/// Type [pw] into the saved-account quick-login PASSWORD dialog and confirm via
/// OK. The dialog field carries the Batch-3 key `login_quick_password_field`
/// (autofocused), so focusType reaches it. The OK button has no key — tap the
/// "OK" label (single-fire `_tapTextCenter`; OK calls popDialogIfCurrent(value),
/// not a page pop, so even a double-fire would be safe, but we keep one tap).
Future<bool> _enterQuickLoginPassword(Inst inst, String pw) async {
  if (!await inst.waitKey('login_quick_password_field', timeoutSecs: 10)) {
    print('[pair] quick_login_pw: password dialog did not open');
    return false;
  }
  await inst.focusType('login_quick_password_field', pw);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (!await _tapTextCenter(inst, 'OK')) {
    print('[pair] quick_login_pw: OK button not tappable');
    return false;
  }
  return true;
}

/// case 27 — login_password_wrong_error (S2b): set a KNOWN password on the
/// primary account (Settings), logout, tap the saved-account card -> the
/// password prompt opens; enter a WRONG password + OK -> production verifies it,
/// fails, surfaces the "Invalid password" error, and STAYS on the LoginPage
/// (session NOT ready, the card is still present). Leaves the password SET (case
/// 28 unlocks + removes it). Returns the primary toxId via [outToxId] (a single-
/// element list) so the caller threads it to case 28.
Future<bool> _loginPasswordWrongError(Inst inst, List<String> outToxId) async {
  // 1) Set a known password while logged in.
  if (!await _setKnownPassword(inst, _b3PrimaryPassword)) {
    print('[pair] password_wrong: could not set the known password');
    return false;
  }
  // 2) Logout to the LoginPage.
  final toxId = await _logoutToLoginPage(inst);
  if (toxId.isEmpty) {
    print('[pair] password_wrong: logout did not reach LoginPage');
    return false;
  }
  outToxId
    ..clear()
    ..add(toxId);
  // 3) Tap the card -> the password prompt opens (the account now has a pw).
  // Use flutter_skill's key `tap` (a raw tapAt does NOT fire the card InkWell;
  // see _quickLoginNoPassword). The double-fire that `tap` would normally cause
  // is now harmless: production `_quickLogin` has a re-entrancy guard
  // (`_quickLoginInProgress`) so the 2nd invocation is dropped and only ONE
  // password prompt opens.
  final cardKey = 'login_page_account_card:$toxId';
  if (!await inst.tryTapKey(cardKey)) {
    print('[pair] password_wrong: card not tappable');
    return false;
  }
  await inst.foreground();
  // 4) Enter a WRONG password.
  if (!await _enterQuickLoginPassword(inst, 'totally-wrong-password')) {
    print('[pair] password_wrong: could not enter the wrong password');
    return false;
  }
  // 5) "Invalid password" error surfaces AND we stay logged out on the
  // LoginPage (card still present, session NOT ready). The wrong-password path
  // pops the prompt with null (no re-prompt loop), so the dialog must be GONE —
  // assert that, else the card "still present" check is reading the card behind
  // a stuck modal (a false pass). A stuck dialog FAILS this case (bounded).
  final errorShown = await inst.waitText('Invalid password', timeoutSecs: 10);
  final dialogDismissed = await inst.waitKeyGone(
    'login_quick_password_field',
    timeoutSecs: 8,
  );
  await inst.foreground();
  final stillLoggedOut = (await inst.dumpState())['sessionReady'] != true;
  final cardStillThere =
      stillLoggedOut && await inst.waitKey(cardKey, timeoutSecs: 4);
  print(
    '[pair] login_password_wrong_error: error=$errorShown '
    'dialogDismissed=$dialogDismissed stillLoggedOut=$stillLoggedOut '
    'cardStillThere=$cardStillThere',
  );
  return errorShown && dialogDismissed && stillLoggedOut && cardStillThere;
}

/// case 28 — login_password_correct_unlocks (S2b): with the password still SET
/// (from case 27) and on the LoginPage, tap the saved-account card -> the
/// password prompt opens; enter the CORRECT password + OK -> the session
/// unlocks to HomePage (sessionReady). Then REMOVE the password via the Settings
/// change-password dialog (empty fields -> "Password removed") so the sweep ends
/// in the no-password state. Returns whether unlock + removal both succeeded.
Future<bool> _loginPasswordCorrectUnlocks(Inst inst, String toxId) async {
  if (toxId.isEmpty) {
    print('[pair] password_correct: no toxId threaded from case 27');
    return false;
  }
  // A stray dialog (e.g. case 27's prompt) must be dismissed first so this case
  // genuinely re-opens the prompt. The wrong-password path already returned
  // (popped) the dialog with null, so the card should be tappable again.
  final cardKey = 'login_page_account_card:$toxId';
  if (!await _waitForAccountCard(inst, toxId)) {
    print('[pair] password_correct: card not present pre-tap');
    return false;
  }
  // Use flutter_skill's key `tap` (a raw tapAt does NOT fire the card InkWell);
  // the double-fire is harmless thanks to production's _quickLoginInProgress
  // re-entrancy guard (only one password prompt opens).
  if (!await inst.tryTapKey(cardKey)) {
    print('[pair] password_correct: card not tappable');
    return false;
  }
  await inst.foreground();
  if (!await _enterQuickLoginPassword(inst, _b3PrimaryPassword)) {
    print('[pair] password_correct: could not enter the correct password');
    return false;
  }
  final unlocked = await _waitBoolState(
    inst,
    'sessionReady',
    true,
    timeoutSecs: 40,
  );
  if (unlocked) {
    await inst.foreground();
    await inst.waitKey('new_entry_menu_button', timeoutSecs: 15);
  }
  if (!unlocked) {
    print(
      '[pair] password_correct: session did not unlock with the correct pw',
    );
    return false;
  }
  // RESTORE the no-password state via the production remove-password surface,
  // then PROVE it via the authoritative dump field (the snackbar alone is not
  // sufficient — codex). `removed` is the snackbar signal; `pwGone` is the
  // ground truth that the account is now password-free.
  final removed = await _removePasswordViaSettings(inst);
  final pwGone = await _waitBoolState(
    inst,
    'currentAccountHasPassword',
    false,
    timeoutSecs: 8,
  );
  // pwGone alone can become true after an UNINTENDED logout/session loss (no
  // current account => currentAccountHasPassword==false). Require the session to
  // STILL be on THIS account (codex): sessionReady + the same toxId. Together
  // these prove "still logged into this account, now password-free".
  final finalState = await inst.dumpState();
  final stillThisAccount =
      finalState['sessionReady'] == true &&
      (finalState['currentAccountToxId']?.toString() ?? '') == toxId;
  print(
    '[pair] login_password_correct_unlocks: unlocked=$unlocked '
    'passwordRemovedSnackbar=$removed passwordGone=$pwGone '
    'stillThisAccount=$stillThisAccount',
  );
  // Require the unlock AND the verified-no-password end state ON this account.
  return unlocked && pwGone && stillThisAccount;
}

/// Dismiss the first-run backup wizard (shown after a brand-new registration)
/// if it is present, via its KEYED buttons + SINGLE-FIRE taps (codex P2): tap
/// `firstRunBackupWizard.laterButton` -> the dismiss-confirm dialog -> its keyed
/// `firstRunBackupWizard.confirmDismissButton`. Both buttons pop via
/// `popDialogIfCurrent` (so a stray double-pop is already absorbed), and
/// tapKeyCenter fires exactly one pointer tap, so there is no stacked/stuck
/// dialog hazard. Best-effort + bounded; returns whether the wizard is gone.
Future<bool> _dismissFirstRunWizardIfPresent(Inst inst) async {
  await inst.foreground();
  // The wizard renders the "Save your account file" headline + the keyed Later
  // button. If neither is present, there is no wizard to dismiss.
  if (!await inst.waitKey('firstRunBackupWizard.laterButton', timeoutSecs: 6) &&
      !await inst.waitText('Save your account file', timeoutSecs: 2)) {
    return true; // no wizard
  }
  // Open the dismiss-confirm dialog (single-fire the keyed Later button).
  if (!await inst.tapKeyCenter(
    'firstRunBackupWizard.laterButton',
    timeoutSecs: 6,
  )) {
    print('[pair] wizard: Later button not tappable');
    return false;
  }
  // Confirm the dismissal (single-fire the keyed confirm button).
  if (!await inst.tapKeyCenter(
    'firstRunBackupWizard.confirmDismissButton',
    timeoutSecs: 8,
  )) {
    print('[pair] wizard: confirm-dismiss button not tappable');
    return false;
  }
  final gone = await inst.waitKeyGone(
    'firstRunBackupWizard.laterButton',
    timeoutSecs: 8,
  );
  print('[pair] wizard: dismissed=$gone');
  return gone;
}

/// case 29 — account_switch_second_account (S3/S72): from the logged-in PRIMARY
/// HomePage, logout -> on the LoginPage register a SECOND account (the campaign's
/// ONLY extra account, nick 'RuiSweepB3') via the real Register flow -> land on
/// its HomePage (dump currentAccountToxId == the NEW account, != primary). Then
/// logout again and quick-login the PRIMARY saved-account card (no password) ->
/// dump currentAccountToxId flips BACK to the primary. Asserts the toxId switched
/// AWAY from and BACK to the primary (both directions). Ends logged into the
/// PRIMARY account.
Future<bool> _accountSwitchSecondAccount(Inst inst, String primaryToxId) async {
  if (primaryToxId.isEmpty) {
    print('[pair] account_switch: empty primary toxId');
    return false;
  }
  // 1) Logout to the LoginPage.
  final loggedOutTox = await _logoutToLoginPage(inst);
  if (loggedOutTox != primaryToxId) {
    print(
      '[pair] account_switch: logout toxId ${_shortId(loggedOutTox)} != '
      'primary ${_shortId(primaryToxId)}',
    );
    return false;
  }
  // 2) Register the second account via the real Register flow.
  if (!await _openRegisterPage(inst)) {
    print('[pair] account_switch: RegisterPage did not open');
    return false;
  }
  await inst.focusType('register_page_nickname_field', _b3SecondNick);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('register_page_register_button');
  await inst.foreground();
  final secondReady = await _waitBoolState(
    inst,
    'sessionReady',
    true,
    timeoutSecs: 60,
  );
  if (!secondReady) {
    print('[pair] account_switch: second account did not boot');
    return false;
  }
  // Dismiss the first-run backup wizard so navigation reaches HomePage.
  await _dismissFirstRunWizardIfPresent(inst);
  await inst.foreground();
  await inst.waitKey('new_entry_menu_button', timeoutSecs: 25);
  final secondTox =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  final switchedAway = secondTox.isNotEmpty && secondTox != primaryToxId;
  if (!switchedAway) {
    print(
      '[pair] account_switch: did NOT switch away — secondTox='
      '${_shortId(secondTox)} primary=${_shortId(primaryToxId)}',
    );
    return false;
  }
  print(
    '[pair] account_switch: on second account ${_shortId(secondTox)} '
    '(nick $_b3SecondNick)',
  );
  // 3) Switch BACK: logout the second account, then quick-login the primary
  // saved-account card (no password). The primary card must be present in the
  // saved-accounts list.
  final loggedOutSecond = await _logoutToLoginPage(inst);
  if (loggedOutSecond != secondTox) {
    print(
      '[pair] account_switch: second logout toxId '
      '${_shortId(loggedOutSecond)} != ${_shortId(secondTox)}',
    );
    return false;
  }
  if (!await _quickLoginNoPassword(inst, primaryToxId)) {
    print('[pair] account_switch: could not quick-login back to primary');
    return false;
  }
  final backTox =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  final switchedBack = backTox == primaryToxId;
  print(
    '[pair] account_switch_second_account: switchedAway=$switchedAway '
    'switchedBack=$switchedBack (primary=${_shortId(primaryToxId)} '
    'second=${_shortId(secondTox)} back=${_shortId(backTox)})',
  );
  return switchedAway && switchedBack;
}

/// Best-effort between-cases normalizer for the login sweep: if a case left us
/// stranded on the RegisterPage (a failed back-out) or on a quick-login password
/// dialog, dismiss it so the next case starts from a clean LoginPage / HomePage.
/// Idempotent; never throws.
Future<void> _normalizeLoginBetweenCases(Inst inst) async {
  try {
    await inst.foreground();
    // Stranded on the RegisterPage? Back out.
    if (await inst.waitKey('register_page_nickname_field', timeoutSecs: 1)) {
      await _backOutOfRegister(inst);
    }
    // A lingering quick-login password dialog? ESC it.
    if (await inst.waitKey('login_quick_password_field', timeoutSecs: 1)) {
      try {
        await inst.osaEscape();
      } on DriveError {
        // best-effort
      }
      await inst.waitKeyGone('login_quick_password_field', timeoutSecs: 3);
    }
  } on DriveError catch (e) {
    print(
      '[sweep] login normalize: best-effort failed (ignored): ${e.message}',
    );
  }
}

/// Best-effort END-STATE restore for the login sweep (codex P1): the password
/// cases (27/28) mutate account state (set a password) and the account-switch
/// case (29) logs out / registers a second account. If ANY of those FAILS
/// mid-way, the sweep would otherwise end DIRTY — still logged out, still
/// password-protected, or stranded on a second account. This guarantees the
/// documented end state: logged into the PRIMARY account, NO password, autoLogin
/// intact. Returns whether the end state is verified clean; never throws.
///
/// Steps (each idempotent / no-op when already satisfied):
///  1. Dismiss any stray RegisterPage / password dialog.
///  2. If logged into a DIFFERENT account (a stuck second account), log out.
///  3. If on the LoginPage, quick-login the primary card (the primary may be
///     password-protected if case 28 failed to remove it — try with the known
///     Batch-3 password; if that's wrong because no pw was set, the no-password
///     quick-login path is taken instead).
///  4. Once on the primary HomePage, remove any leftover password.
/// NEVER THROWS (codex P1): the entire body is wrapped so it is safe to call
/// from a `finally` even when the sweep aborted on an unexpected DriveError.
/// Returns true only when the end state is VERIFIED clean: logged into the
/// PRIMARY account AND autoLogin intact AND no leftover password was detected
/// (the password-remove either reported removal or was a benign no-op).
Future<bool> _ensureCleanPrimaryEnd(
  Inst inst,
  String primaryToxId,
  String primaryNick,
) async {
  try {
    await _normalizeLoginBetweenCases(inst);
    await inst.foreground();
    var st = await inst.dumpState();
    // Logged into a NON-primary account (stuck on the 2nd account)? Log out.
    if (st['sessionReady'] == true &&
        (st['currentAccountToxId']?.toString() ?? '') != primaryToxId) {
      print('[sweep] end-clean: logged into a non-primary account -> logout');
      await _logoutToLoginPage(inst);
      st = await inst.dumpState();
    }
    // On the LoginPage? Quick-login the primary. It MAY be password-protected
    // (case 28 failed to remove it) — tap the card, and if a password prompt
    // appears, supply the known Batch-3 password; otherwise the no-password path
    // already logs in.
    if (st['sessionReady'] != true) {
      if (await _waitForAccountCard(inst, primaryToxId)) {
        // SINGLE-FIRE the card (codex) so a double-fire can't stack prompts.
        await inst.tapKeyCenter(
          'login_page_account_card:$primaryToxId',
          timeoutSecs: 6,
        );
        await inst.foreground();
        // If a password prompt opened, satisfy it with the known password.
        if (await inst.waitKey('login_quick_password_field', timeoutSecs: 4)) {
          await _enterQuickLoginPassword(inst, _b3PrimaryPassword);
        }
        await _waitBoolState(inst, 'sessionReady', true, timeoutSecs: 40);
        await inst.foreground();
        await inst.waitKey('new_entry_menu_button', timeoutSecs: 15);
      }
    }
    st = await inst.dumpState();
    // Whether we are on the primary BEFORE the password-removal step (gates the
    // attempt only — NOT the verdict).
    final onPrimaryPre =
        st['sessionReady'] == true &&
        (st['currentAccountToxId']?.toString() ?? '') == primaryToxId;
    // Remove any leftover password so the account ends password-free. When a
    // password WAS set, `_removePasswordViaSettings` returns true ("Password
    // removed" snackbar); when there was none, the empty-empty save is a benign
    // no-op that may NOT raise that snackbar — so its false return is AMBIGUOUS
    // (real failure vs already-none). We therefore do NOT trust the snackbar for
    // the verdict: we read the AUTHORITATIVE `currentAccountHasPassword` from the
    // dump AFTER the attempt (codex R2-P3). passwordCleared == true iff the
    // account is verifiably password-free.
    if (onPrimaryPre) {
      try {
        final removed = await _removePasswordViaSettings(inst);
        print('[sweep] end-clean: removePassword snackbar=$removed');
      } on DriveError catch (e) {
        print(
          '[sweep] end-clean: password-remove best-effort failed: ${e.message}',
        );
      }
      try {
        await returnToChatsHome(inst, rounds: 4);
      } on DriveError catch (e) {
        print('[sweep] end-clean: returnToChatsHome best-effort: ${e.message}');
      }
    }
    // Recompute the verdict from the FINAL dump (codex P2): a logout / switch /
    // read-failure DURING cleanup must not leave a stale-true onPrimary. All
    // three end-state facts (on primary, autoLogin, no password) are read from
    // the SAME final snapshot.
    final finalState = await inst.dumpState();
    final onPrimary =
        finalState['sessionReady'] == true &&
        (finalState['currentAccountToxId']?.toString() ?? '') == primaryToxId;
    final autoLogin = finalState['autoLogin'] == true;
    // AUTHORITATIVE no-password check: clean iff the dump reports no stored
    // password verifier. (When there is no session this is false too, but
    // `onPrimary` already gates that.)
    final passwordCleared = finalState['currentAccountHasPassword'] != true;
    final clean = onPrimary && autoLogin && passwordCleared;
    print(
      '[sweep] end-clean: onPrimaryPre=$onPrimaryPre onPrimary=$onPrimary '
      'autoLogin=$autoLogin passwordCleared=$passwordCleared clean=$clean '
      '(primary=${_shortId(primaryToxId)} nick "$primaryNick")',
    );
    return clean;
  } on PermissionBlockedError catch (e) {
    print('[sweep] end-clean: BLOCKED (osascript perm): ${e.message}');
    return false;
  } on DriveError catch (e) {
    print('[sweep] end-clean: aborted (best-effort, ignored): ${e.message}');
    return false;
  } catch (e) {
    print('[sweep] end-clean: unexpected error (ignored): $e');
    return false;
  }
}

/// sweep_login — Batch 3: chain all 9 login/register cases on ONE launch.
///
/// State machine (ends CLEAN: logged into the PRIMARY account, NO password,
/// autoLogin intact):
///   ensureHome (registers the PRIMARY account if the launch is fresh) ->
///   logout (serves 21+22) -> 22 register-open-back -> 21 account-card-renders ->
///   26 restore-entry (SKIP) -> 23/24/25 register validation (NO accounts) ->
///   quick-login back to primary -> 27 wrong-password (sets pw, logs out, error) ->
///   28 correct-password (unlocks, then REMOVES the password) ->
///   29 account-switch (register #2, switch back to primary).
///
/// Prints `[sweep] <case>: PASS|FAIL|SKIP(<reason>)` per case + final counts;
/// exits non-zero if any HARD case fails (26 is the only SKIP).
Future<int> runLoginSweep(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
    timeoutSecs: 90,
  );
  final primaryToxId =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (primaryToxId.isEmpty) {
    print('[sweep] sweep_login: no primary toxId after ensureHome');
    return 1;
  }
  final primaryNick = (await inst.dumpState())['nickname']?.toString() ?? nick;
  print(
    '[sweep] sweep_login: primary=${_shortId(primaryToxId)} '
    '(nick "$primaryNick")',
  );

  var passed = 0;
  var failed = 0;
  var skipped = 0;
  final results = <String, String>{};

  Future<void> hard(String id, Future<bool> Function() run) async {
    bool ok;
    String? detail;
    try {
      ok = await run();
    } on PermissionBlockedError {
      rethrow; // surfaces as BLOCKED(78) at the driver level
    } on DriveError catch (e) {
      ok = false;
      detail = 'DriveError: ${e.message}';
    }
    if (ok) {
      passed++;
      results[id] = 'PASS';
      print('[sweep] $id: PASS');
    } else {
      failed++;
      results[id] = 'FAIL';
      print('[sweep] $id: FAIL${detail != null ? ' ($detail)' : ''}');
    }
    await _normalizeLoginBetweenCases(inst);
  }

  // Run all 9 cases inside a try so the END-STATE GUARD in the finally ALWAYS
  // runs — even if a case throws an unexpected DriveError / PermissionBlocked
  // that escapes `hard()` (it rethrows PermissionBlockedError) or an early
  // abort. This is what makes "ends CLEAN" hold regardless of mid-sweep failures
  // (codex P1).
  try {
    // --- Logout once (serves cases 21 + 22; lands on the LoginPage). ---
    final loggedOutTox = await _logoutToLoginPage(inst);
    if (loggedOutTox != primaryToxId) {
      print(
        '[sweep] sweep_login: initial logout failed (tox '
        '${_shortId(loggedOutTox)} != primary) — marking remaining cases failed',
      );
      // Don't early-return (that would skip the finally's cleanup intent and the
      // RESULTS line); record a hard failure and fall through so the finally
      // still restores the end state.
      failed++;
      results['initial_logout'] = 'FAIL';
    } else {
      // 22 — register open/back (on the LoginPage).
      await hard(
        'login_register_open_back',
        () => _loginRegisterOpenBack(inst),
      );
      // 21 — saved-account card renders (still on the LoginPage).
      await hard(
        'login_account_card_renders',
        () => _loginAccountCardRenders(inst, primaryToxId, primaryNick),
      );
      // 26 — restore entry (SKIP — native picker only).
      {
        final skip = await _loginRestoreEntryOpens(inst);
        if (skip == null) {
          skipped++;
          results['login_restore_entry_opens'] = 'SKIP';
          print('[sweep] login_restore_entry_opens: SKIP(native-picker-only)');
        } else if (skip) {
          passed++;
          results['login_restore_entry_opens'] = 'PASS';
          print('[sweep] login_restore_entry_opens: PASS');
        } else {
          failed++;
          results['login_restore_entry_opens'] = 'FAIL';
          print('[sweep] login_restore_entry_opens: FAIL');
        }
        await _normalizeLoginBetweenCases(inst);
      }
      // 23/24/25 — register validation (NO accounts created; all back out).
      await hard(
        'register_empty_nickname_error',
        () => _registerEmptyNicknameError(inst),
      );
      await hard(
        'register_password_mismatch_error',
        () => _registerPasswordMismatchError(inst),
      );
      await hard(
        'register_password_strength_flips',
        () => _registerPasswordStrengthFlips(inst),
      );

      // --- Quick-login back to the PRIMARY account (no password) so the
      // password cases can set/clear a password while logged in. ---
      if (!await _quickLoginNoPassword(inst, primaryToxId)) {
        print(
          '[sweep] sweep_login: could not quick-login back to primary before '
          'the password cases — remaining cases will FAIL cleanly',
        );
      }

      // 27 — wrong password (sets a pw, logs out, wrong pw -> error, stays).
      final toxHolder = <String>[];
      await hard(
        'login_password_wrong_error',
        () => _loginPasswordWrongError(inst, toxHolder),
      );
      // Enforce the 27->28 toxId handoff (codex P2): case 27 captures the
      // logged-out primary toxId into `toxHolder`. It MUST equal primaryToxId;
      // if 27 produced a different (or no) toxId, the threading is broken —
      // surface that as a FAIL on 28 rather than silently falling back to
      // primaryToxId and hiding the bug.
      final threadedTox = toxHolder.isNotEmpty ? toxHolder.first : '';
      if (threadedTox != primaryToxId) {
        print(
          '[sweep] login_password_correct_unlocks: 27->28 toxId handoff broken '
          '(threaded=${_shortId(threadedTox)} != primary '
          '${_shortId(primaryToxId)})',
        );
      }
      // 28 — correct password (unlocks -> HomePage; then REMOVES the password).
      // Pass the THREADED toxId (empty if 27 failed to capture it) so a broken
      // handoff makes 28 fail its empty-toxId guard rather than false-pass on
      // primaryToxId.
      await hard(
        'login_password_correct_unlocks',
        () => _loginPasswordCorrectUnlocks(inst, threadedTox),
      );

      // 29 — account switch (register #2, switch back to primary). MUST run with
      // the primary logged-in + password-free (case 28 restored that).
      await hard(
        'account_switch_second_account',
        () => _accountSwitchSecondAccount(inst, primaryToxId),
      );
    }
  } finally {
    // END-STATE GUARD (codex P1): regardless of which cases failed (or threw),
    // restore the documented clean end state — logged into the PRIMARY account,
    // NO password, autoLogin intact — so a partial run does not leave the launch
    // dirty. Best-effort recovery (no-throw), NOT a pass/fail gate (the per-case
    // results above are the source of truth); the result is logged for the
    // run-phase operator.
    final endClean = await _ensureCleanPrimaryEnd(
      inst,
      primaryToxId,
      primaryNick,
    );
    print(
      '[sweep] sweep_login RESULTS: $passed PASS / $failed FAIL / $skipped SKIP '
      '($results) | endClean=$endClean',
    );
    try {
      await inst.shot('/tmp/ui_login_sweep_${inst.name}.png');
    } on DriveError {
      // best-effort
    }
  }
  return failed == 0 ? 0 : 1;
}
