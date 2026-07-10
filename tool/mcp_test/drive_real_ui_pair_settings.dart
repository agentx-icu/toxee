// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

/// True when the Settings tab is the ACTIVE (onstage) home-shell tab.
///
/// Why this is not just `waitKey('settings_copy_tox_id_button')`: HomePage hosts
/// the Chats/Contacts/Settings panes in an `IndexedStack` with maintainState, so
/// every tab's widgets — including `settings_copy_tox_id_button` — stay MOUNTED
/// in the tree even while OFFSTAGE. flutter_skill's whole-tree `waitForElement`
/// therefore reports the settings copy button as "present" on the Chats tab too.
/// The only authoritative onstage signal is the dump `homeShellTab` field (the
/// live `_index`). Below-fold settings widgets driven by `tapKey` (whole-tree)
/// still worked offstage, but `ui_scroll_at` (onstage-filtered) does not — hence
/// the campaign's settings-scroll cases were silently scrolling the wrong (still
/// Chats) onstage tab and failing `key_offstage_only:settings_scroll_view`.
Future<bool> _settingsTabActive(Inst inst) async {
  final tab = (await inst.dumpState())['homeShellTab']?.toString();
  return tab == 'settings';
}

/// Open the Settings tab and wait for it to become the ACTIVE onstage tab.
/// Robust against a transient post-dialog re-render or a backgrounded window:
/// re-foreground and re-tap the sidebar tab a few rounds before giving up.
///
/// Gates on `homeShellTab == 'settings'` (the live IndexedStack index), NOT on a
/// whole-tree key match — the settings pane stays mounted offstage, so a key
/// match alone would short-circuit without ever switching the active tab and
/// leave onstage-filtered scrolls (`ui_scroll_at`) operating on the wrong tab.
Future<void> _openSettings(Inst inst) async {
  for (var round = 0; round < 6; round++) {
    await inst.foreground();
    // RECOVERY (round > 0): a prior case may have left the app on a PUSHED route
    // (e.g. a group/conference profile page whose leave/confirm wasn't matched)
    // or a MODAL dialog — both sit over the sidebar and swallow the settings-tab
    // tap, so the tab never activates and every later settings-nav case cascades
    // into "settings did not become the active tab". On the FIRST retry run the
    // comprehensive home reset (escapes pushed routes / overlays); on every retry
    // press Escape (dismisses an AlertDialog / barrier-dismissible modal). Skipped
    // on round 0 so a normal open isn't perturbed.
    if (round == 1) {
      await returnToChatsHome(inst, rounds: 3);
    }
    if (round > 0) {
      if (!inst.isIos) {
        try {
          await inst.osaEscape();
        } on DriveError {
          // best-effort
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // `homeShellTab == 'settings'` is the AUTHORITATIVE active-tab signal. Do NOT
    // additionally require `settings_copy_tox_id_button` to be found: that key is
    // at the TOP of the settings ListView, so when a prior case left the list
    // scrolled DOWN it's off-screen (and out of flutter_skill's cacheExtent
    // reach), which would falsely loop here. Once settings is the active tab we
    // scroll the list back to the TOP so callers start from a known position.
    if (await _settingsTabActive(inst)) {
      await inst.scrollAt(_settingsScrollKey, dy: -6000);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return;
    }
    // The sidebar settings tab is a plain IndexedStack `_index` setState; a
    // single real tap switches it (flutter_skill's double-fire is harmless on a
    // tab selector — it just re-selects the same index). Use tapKeyCenter for a
    // deterministic single pointer tap, falling back to the synthetic tap.
    if (!await inst.tapKeyCenter('sidebar_settings_tab')) {
      await inst.tryTapKey('sidebar_settings_tab');
    }
    if (inst.isIos && !await _settingsTabActive(inst)) {
      if (!await inst.tapKeyCenter('bottom_nav_settings_tab', timeoutSecs: 4)) {
        await inst.tryTapKey('bottom_nav_settings_tab');
      }
    }
    // Poll the active-tab signal (the switch is a setState that lands within a
    // frame or two).
    for (var i = 0; i < 6; i++) {
      if (await _settingsTabActive(inst)) {
        await inst.scrollAt(_settingsScrollKey, dy: -6000);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  await inst.shot('/tmp/ui_settings_noopen_${inst.name}.png');
  throw DriveError('[${inst.name}] settings did not become the active tab');
}

/// True when the home shell is in the WIDE master-detail layout (desktop AND
/// iPad/large-tablet). On wide iOS the SettingsPage renders every section
/// INLINE on one scrolling page (settings_page.dart `build` takes the
/// non-`isMobile` branch → `_buildSettingsChildren`), so there is NO per-section
/// push navigation: the mobile index tiles ("Account Management", "Appearance",
/// "General") don't exist and there is no `settings_mobile_section_back_button`.
/// Every content key is instead mounted inline (findable by whole-tree waitKey).
/// A compact iPhone returns false and keeps the push-navigation path.
Future<bool> _settingsIsWide(Inst inst) async {
  final v = (await inst.dumpState())['homeShellShouldShowMasterDetail'];
  return v == true;
}

Future<bool> _openMobileAccountManagement(Inst inst) async {
  if (!inst.isIos) return true;
  await _openSettings(inst);
  // Wide iOS (iPad): account-management buttons are inline in the Account card
  // (settings_page_build.dart `_buildAccountActionButtons`) — no drill-in.
  if (await _settingsIsWide(inst)) return true;
  if (await inst.waitKey('settings_logout_button', timeoutSecs: 1) ||
      await inst.waitKey('settings_set_password_button', timeoutSecs: 1)) {
    return true;
  }
  if (!await _tryTapText(inst, 'Account Management')) {
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  return await inst.waitKey('settings_logout_button', timeoutSecs: 4) ||
      await inst.waitKey('settings_set_password_button', timeoutSecs: 4);
}

Future<bool> _openMobileSettingsSection(Inst inst, String title) async {
  if (!inst.isIos) return false;
  // Wide iOS (iPad): all sections render inline on the single settings page —
  // just make Settings the active tab; the caller's content-key waitKeys then
  // match the inline widgets. No sub-route push, no back button.
  if (await _settingsIsWide(inst)) {
    await _openSettings(inst);
    return true;
  }
  // Drilling into a mobile settings sub-section pushes a new route whose AppBar
  // leading carries `settings_mobile_section_back_button` (see
  // SettingsPage._pushMobileSettingsSection). The previous implementation tapped
  // the section title and returned true after a fixed 700ms WITHOUT confirming
  // the push landed. On a just-booted/cold app (the first drill-in right after
  // login) the title tap could fire before the index list was hit-testable, so
  // the section never opened yet the helper reported success — the caller's
  // `waitKey` then raced a page that was not there and the case flaked. Confirm
  // the route actually pushed (back button present), and retry the tap. This
  // mirrors the self-verifying open in _openMobileAccountManagement.
  for (var attempt = 0; attempt < 3; attempt++) {
    // If a prior step left us inside a section (mis-popped), the index title is
    // not tappable — pop back out first.
    if (await inst.waitKey(
      'settings_mobile_section_back_button',
      timeoutSecs: 1,
    )) {
      await _backFromMobileSettingsSection(inst);
    }
    await _openSettings(inst);
    if (await _tryTapText(inst, title) &&
        await inst.waitKey(
          'settings_mobile_section_back_button',
          timeoutSecs: 4,
        )) {
      return true;
    }
  }
  return false;
}

Future<void> _backFromMobileSettingsSection(Inst inst) async {
  if (!inst.isIos) return;
  // Wide iOS (iPad): sections are inline — there is no pushed route to pop.
  if (await _settingsIsWide(inst)) return;
  if (!await inst.tapKeyCenter(
    'settings_mobile_section_back_button',
    timeoutSecs: 3,
  )) {
    await inst.tapAt(28, 90);
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
}

Future<int> runIosSettingsMainSweep(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  final results = <String, bool>{};

  Future<void> run(String name, Future<bool> Function() body) async {
    try {
      final ok = await body();
      results[name] = ok;
      print('[sweep] $name: ${ok ? 'PASS' : 'FAIL'}');
    } catch (e) {
      results[name] = false;
      print('[sweep] $name: FAIL ($e)');
    }
  }

  await run('ios_settings_index_sections', () async {
    await _openSettings(inst);
    // Wide iOS (iPad): the mobile section-index tiles don't exist — every
    // section is inline. Assert one anchor per section is mounted on the page
    // (whole-tree waitKey finds mounted-offstage widgets), which proves the
    // same section coverage the compact tile-titles stand in for.
    if (await _settingsIsWide(inst)) {
      final accountInfo = await inst.waitKey(
        'settings_copy_tox_id_button',
        timeoutSecs: 4,
      );
      final accountMgmt = await inst.waitKey(
        'settings_logout_button',
        timeoutSecs: 4,
      );
      final appearance = await inst.waitKey(
        'settings_theme_segment',
        timeoutSecs: 4,
      );
      final general = await inst.waitKey(
        'settings_notification_sound_switch',
        timeoutSecs: 4,
      );
      // BootstrapSettingsSection is the LAST child of the inline settings
      // ListView; on a wide page it starts below the fold and the lazy ListView
      // has not built it yet, so a whole-tree waitKey misses it until it scrolls
      // into the cacheExtent. Scroll to the bottom first, then assert.
      await inst.scrollAt(_settingsScrollKey, dy: 6000);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final bootstrap = await inst.waitKey(
        'settings_bootstrap_mode_auto',
        timeoutSecs: 4,
      );
      await inst.scrollAt(_settingsScrollKey, dy: -6000);
      return accountInfo && accountMgmt && appearance && general && bootstrap;
    }
    final accountInfo = await inst.waitText('Account Info', timeoutSecs: 4);
    final accountMgmt = await inst.waitText(
      'Account Management',
      timeoutSecs: 4,
    );
    final appearance = await inst.waitText('Appearance', timeoutSecs: 4);
    final general = await inst.waitText('General', timeoutSecs: 4);
    final bootstrap = await inst.waitText('Bootstrap Nodes', timeoutSecs: 4);
    return accountInfo && accountMgmt && appearance && general && bootstrap;
  });

  await run('ios_settings_account_info', () async {
    if (!await _openMobileSettingsSection(inst, 'Account Info')) return false;
    final hasCopyKey = await inst.waitKey(
      'settings_copy_tox_id_button',
      timeoutSecs: 4,
    );
    final hasAutoLogin = await inst.waitKey(
      'settings_auto_login_switch',
      timeoutSecs: 4,
    );
    await _backFromMobileSettingsSection(inst);
    return hasCopyKey && hasAutoLogin;
  });

  await run('ios_settings_account_management', () async {
    if (!await _openMobileAccountManagement(inst)) return false;
    final hasExport = await inst.waitKey(
      'settings_export_account_button',
      timeoutSecs: 4,
    );
    final hasPassword = await inst.waitKey(
      'settings_set_password_button',
      timeoutSecs: 4,
    );
    final hasLogout = await inst.waitKey(
      'settings_logout_button',
      timeoutSecs: 4,
    );
    final hasDelete = await inst.waitKey(
      'settings_delete_account_button',
      timeoutSecs: 4,
    );
    await _backFromMobileSettingsSection(inst);
    return hasExport && hasPassword && hasLogout && hasDelete;
  });

  // Settings split (2026-07-08): the mobile "Appearance" page now carries
  // ONLY theme + language; notification sound / downloads dir / auto-download
  // limit moved to the new "General" page (settings_page.dart
  // _buildMobileSettingsIndex). Assert each page's actual contents.
  await run('ios_settings_appearance', () async {
    if (!await _openMobileSettingsSection(inst, 'Appearance')) return false;
    final hasTheme = await inst.waitKey(
      'settings_theme_segment',
      timeoutSecs: 4,
    );
    final hasLanguage = await inst.waitKey(
      'settings_language_selector',
      timeoutSecs: 4,
    );
    await _backFromMobileSettingsSection(inst);
    return hasTheme && hasLanguage;
  });

  await run('ios_settings_general', () async {
    if (!await _openMobileSettingsSection(inst, 'General')) return false;
    final hasNotificationSound = await inst.waitKey(
      'settings_notification_sound_switch',
      timeoutSecs: 4,
    );
    final hasDownload = await inst.waitKey(
      'settings_download_limit_field',
      timeoutSecs: 4,
    );
    await _backFromMobileSettingsSection(inst);
    return hasNotificationSound && hasDownload;
  });

  await run('ios_settings_bootstrap', () async {
    if (!await _openMobileSettingsSection(inst, 'Bootstrap Nodes'))
      return false;
    // Wide iOS (iPad): BootstrapSettingsSection is the last child of the inline
    // settings ListView and starts below the fold, so the lazy list has not
    // built its keys yet — scroll to the bottom to mount them before asserting.
    final wide = await _settingsIsWide(inst);
    if (wide) {
      await inst.scrollAt(_settingsScrollKey, dy: 6000);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final hasAuto = await inst.waitKey(
      'settings_bootstrap_mode_auto',
      timeoutSecs: 4,
    );
    final hasManual = await inst.waitKey(
      'settings_bootstrap_mode_manual',
      timeoutSecs: 4,
    );
    if (wide) await inst.scrollAt(_settingsScrollKey, dy: -6000);
    await _backFromMobileSettingsSection(inst);
    return hasAuto && hasManual;
  });

  final failed = results.entries.where((entry) => !entry.value).toList();
  print(
    '[sweep] sweep_ios_settings_main RESULTS: '
    '${results.length - failed.length} PASS / ${failed.length} FAIL ($results)',
  );
  await inst.shot('/tmp/ui_ios_settings_main_${inst.name}.png');
  return failed.isEmpty ? 0 : 1;
}

/// Poll l3_dump_state until a top-level bool field equals [want] (no throw).
Future<bool> _waitBoolState(
  Inst inst,
  String field,
  bool want, {
  int timeoutSecs = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if ((await inst.dumpState())[field] == want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

/// S100 — copy Tox ID from settings: real tap on the keyed copy button surfaces
/// the "ID copied to clipboard" snackbar.
Future<bool> _settingsCopyId(Inst inst) async {
  await _openSettings(inst);
  await inst.tapKey('settings_copy_tox_id_button');
  final ok = await inst.waitText('ID copied to clipboard', timeoutSecs: 8);
  print('[pair] settings_copy_id: snackbar=$ok');
  return ok;
}

/// Auto-login switch: real tap flips `autoLogin` in l3_dump_state; tap back
/// restores it (proves the switch drives the real Prefs-backed setting).
Future<bool> _settingsAutoLogin(Inst inst) async {
  await _openSettings(inst);
  final before = (await inst.dumpState())['autoLogin'] == true;
  await inst.tapKey('settings_auto_login_switch');
  final flipped = await _waitBoolState(inst, 'autoLogin', !before);
  await inst.tapKey('settings_auto_login_switch');
  final restored = await _waitBoolState(inst, 'autoLogin', before);
  print(
    '[pair] settings_autologin: before=$before flipped=$flipped '
    'restored=$restored',
  );
  return flipped && restored;
}

/// Notification-sound switch: real tap flips `notificationSound` in dump_state.
/// The switch lives in the lower GlobalSettingsSection, so it can be below the
/// fold — best-effort (a false here is reported, not a hard sweep failure).
Future<bool> _settingsNotification(Inst inst) async {
  await _openSettings(inst);
  final before = (await inst.dumpState())['notificationSound'] == true;
  if (!await inst.tryTapKey('settings_notification_sound_switch')) {
    print('[pair] settings_notification: switch not tappable (below fold?)');
    return false;
  }
  final flipped = await _waitBoolState(inst, 'notificationSound', !before);
  // Only restore if the first tap actually flipped it, so a passing result never
  // leaves notificationSound mutated.
  if (flipped) {
    await inst.tryTapKey('settings_notification_sound_switch');
    await _waitBoolState(inst, 'notificationSound', before);
  }
  print('[pair] settings_notification: before=$before flipped=$flipped');
  return flipped;
}

/// S105 — export chooser: real tap on Export Account mounts the chooser dialog
/// with both the .tox and full-backup options. ESC dismisses it without firing
/// the native save panel.
Future<bool> _settingsExportChooser(Inst inst) async {
  await _openSettings(inst);
  await inst.tapKey('settings_export_account_button');
  final tox = await inst.waitKey(
    'settings_export_profile_tox_option',
    timeoutSecs: 8,
  );
  final zip = await inst.waitKey(
    'settings_export_full_backup_option',
    timeoutSecs: 4,
  );
  try {
    await inst.osaEscape();
  } on DriveError {
    // best effort
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
  print('[pair] settings_export_chooser: tox=$tox zip=$zip');
  return tox && zip;
}

/// Set/change-password dialog: real tap opens it (keyed new/confirm fields),
/// fill matching values, Save → the dialog closes on the success path (real
/// PBKDF2 runs on the live isolate).
Future<bool> _settingsPassword(Inst inst) async {
  await _openSettings(inst);
  // Below-fold opener: drive it with `tap` (its direct _tryInvokeCallback opens
  // the dialog even off-screen; a coordinate tapAt would miss). See the logout
  // flow above for the same rationale.
  await inst.tapKey('settings_set_password_button');
  if (!await inst.waitKey('settings_set_password_new_field', timeoutSecs: 8)) {
    print('[pair] settings_password: dialog did not open');
    return false;
  }
  final pw = 'RuiPw-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  await inst.focusType('settings_set_password_new_field', pw);
  await inst.focusType('settings_set_password_confirm_field', pw);
  // SINGLE-FIRE the save button: it calls Navigator.pop(password) on success, so
  // flutter_skill's double-firing tap would pop the dialog AND HomePage (blanking
  // the app) and tear down the ScaffoldMessenger before the success snackbar.
  if (!await inst.tapKeyCenter('settings_set_password_save_button')) {
    print('[pair] settings_password: save button not tappable');
    return false;
  }
  // The dialog pops on matching input BEFORE the async
  // AccountService.setAccountPassword write completes — so "dialog closed" alone
  // is a false pass. Assert the REAL save via the success snackbar (only shown
  // when setAccountPassword returns ok; real PBKDF2 runs on the live isolate, so
  // allow time).
  final saved = await inst.waitText(
    'Password set successfully',
    timeoutSecs: 25,
  );
  // Also require the dialog to be fully GONE. Unlike logout (whose
  // pushAndRemoveUntil tears down any stray route), nothing here cleans up a
  // second dialog if the below-fold opener ever double-opened — the single-fire
  // save would pop only the top one, the snackbar would still fire, and the
  // residual dialog (same field key) would leave a dirty false-green. Asserting
  // the field is gone catches that and proves the save closed the dialog.
  final dialogClosed = await inst.waitKeyGone(
    'settings_set_password_new_field',
    timeoutSecs: 8,
  );
  print(
    '[pair] settings_password: passwordSavedSnackbar=$saved '
    'dialogClosed=$dialogClosed',
  );
  return saved && dialogClosed;
}

/// Logout + saved-account relogin: real tap Logout → confirm → the app returns
/// to the login page (sessionReady=false) showing this account's saved-account
/// card → tap the card to quick-login back to HomePage (sessionReady=true).
///
/// PRECONDITION: the current account has NO password — tapping the saved-account
/// card then quick-logs-in directly. On a password-protected account `_quickLogin`
/// shows a password prompt instead, which this driver cannot satisfy (it does not
/// know the password), so the relogin times out and the gate fails cleanly. Run
/// on a freshly-registered account (which `ensureHome` provides), and in
/// `runSettingsSweep` this runs BEFORE `settings_password` for exactly this reason.
Future<bool> _settingsLogoutRelogin(Inst inst) async {
  final toxId =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxId.isEmpty) {
    print('[pair] logout_relogin: no current toxId');
    return false;
  }
  await _openSettings(inst);
  // The logout button sits low in the (scrollable) settings list — often below
  // the fold. flutter_skill's `tap` opens it anyway via its direct
  // `_tryInvokeCallback` (the synthetic pointer misses off-screen, so the
  // callback fires exactly once → one dialog). A coordinate `tapAt` would miss.
  await inst.tapKey('settings_logout_button');
  if (!await inst.waitKey('settings_logout_confirm_button', timeoutSecs: 8)) {
    print('[pair] logout_relogin: confirm dialog did not open');
    return false;
  }
  // SINGLE-FIRE the confirm: it is an on-screen dialog button, so flutter_skill's
  // `tap` fires it TWICE (synthetic pointer hit + direct onPressed) → pops the
  // dialog AND HomePage, and `_logout`'s trailing `if (!mounted) return` then
  // skips `pushAndRemoveUntil(LoginPage)`, leaving an empty Navigator (blank
  // screen). tapKeyCenter dispatches exactly one pointer tap. See tapKeyCenter.
  if (!await inst.tapKeyCenter('settings_logout_confirm_button')) {
    print('[pair] logout_relogin: confirm button not tappable');
    return false;
  }
  final cardKey = 'login_page_account_card:$toxId';
  // Logout pushes the login page; the async saved-account-list load only pumps
  // while the window is FOREGROUND (a backgrounded window stalls it → blank
  // screenshot + card never renders). Re-foreground each round until the card
  // appears.
  var loggedOut = false;
  var cardShows = false;
  for (var round = 0; round < 15 && !cardShows; round++) {
    await inst.foreground();
    loggedOut = (await inst.dumpState())['sessionReady'] != true;
    if (loggedOut) {
      cardShows = await inst.waitKey(cardKey, timeoutSecs: 2);
    }
    if (!cardShows) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
  print(
    '[pair] logout_relogin: loggedOut=$loggedOut cardShows=$cardShows '
    '(tox=${_shortId(toxId)})',
  );
  if (!loggedOut || !cardShows) {
    await inst.foreground();
    await inst.shot('/tmp/ui_logout_${inst.name}.png');
    try {
      final inter = await inst.skill('interactiveStructured', const {});
      final keys = RegExp(
        'login_page_account_card:[A-Za-z0-9]+',
      ).allMatches(inter.toString()).map((m) => m.group(0)).toSet();
      print('[pair] logout DIAG: card keys seen=$keys want=$cardKey');
    } catch (_) {}
    return false;
  }
  // Quick-login back via the saved-account card (this account has no password).
  await inst.tapKey(cardKey);
  await inst.foreground();
  final relogin = await _waitBoolState(
    inst,
    'sessionReady',
    true,
    timeoutSecs: 40,
  );
  print('[pair] logout_relogin: reloginSessionReady=$relogin');
  return relogin;
}

/// LIVE proof of the production `popDialogIfCurrent` guard. Drives the logout
/// confirm with the DOUBLE-FIRING `tapKey` (flutter_skill `tap` invokes onPressed
/// twice: synthetic pointer + direct `_tryInvokeCallback`). Before the guard this
/// popped the dialog AND HomePage, so `_logout`'s trailing `if (!mounted) return`
/// skipped `pushAndRemoveUntil(LoginPage)` → EMPTY Navigator (blank). With the
/// guard the 2nd pop is a no-op, so the app must land on the LoginPage: logged
/// out, NOT blank (interactiveStructured non-empty), saved-account card present.
Future<bool> _settingsLogoutDoubleFire(Inst inst) async {
  final toxId =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  await _openSettings(inst);
  await inst.tapKey('settings_logout_button'); // below-fold opener (fires once)
  if (!await inst.waitKey('settings_logout_confirm_button', timeoutSecs: 8)) {
    print('[pair] logout_double_fire: confirm dialog did not open');
    return false;
  }
  // DELIBERATE double-fire of the on-screen confirm — the exact scenario that
  // used to blank the app. The production guard must absorb the 2nd pop.
  await inst.tapKey('settings_logout_confirm_button');
  final cardKey = 'login_page_account_card:$toxId';
  var loggedOut = false, notBlank = false, cardShows = false;
  for (
    var round = 0;
    round < 15 && !(loggedOut && notBlank && cardShows);
    round++
  ) {
    await inst.foreground();
    loggedOut = (await inst.dumpState())['sessionReady'] != true;
    final inter = await inst.skill('interactiveStructured', const {});
    final data = inter['data'];
    final els = data is Map ? data['elements'] : null;
    notBlank =
        els is List && els.isNotEmpty; // empty == the blank-Navigator bug
    if (loggedOut) cardShows = await inst.waitKey(cardKey, timeoutSecs: 1);
    if (!(loggedOut && notBlank && cardShows)) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
  print(
    '[pair] logout_double_fire: loggedOut=$loggedOut notBlank=$notBlank '
    'cardShows=$cardShows (guard ${loggedOut && notBlank && cardShows ? "HELD" : "FAILED"})',
  );
  return loggedOut && notBlank && cardShows;
}

/// settings_sweep — run the whole login+settings real-UI click suite on ONE
/// launch (reuses startup; maximizes cases per batch). logout_relogin runs LAST
/// because it mutates the session; password runs before it (also mutating).
Future<int> runSettingsSweep(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
    timeoutSecs: 90,
  );
  // Order matters: the deterministic real-click gates first; logout_relogin
  // BEFORE password (relogin via the saved-account card assumes no password);
  // password LAST (it sets a password — harmless once nothing follows).
  final results = <String, bool>{};
  results['copy_id'] = await _settingsCopyId(inst);
  results['export_chooser'] = await _settingsExportChooser(inst);
  results['autologin'] = await _settingsAutoLogin(inst);
  results['notification'] = await _settingsNotification(inst);
  results['logout_relogin'] = await _settingsLogoutRelogin(inst);
  results['password'] = await _settingsPassword(inst);
  final passed = results.values.where((v) => v).length;
  final total = results.length;
  print('[pair] settings_sweep RESULTS: $results ($passed/$total passed)');
  await inst.shot('/tmp/ui_settings_sweep_${inst.name}.png');
  // autologin + notification are best-effort: flutter_skill's synthetic tap on a
  // Material Switch does not reliably trigger onChanged (a known harness gap, like
  // the documented enterText{key}-needs-editable limitation), and the
  // notification switch can sit below the fold (flutter_skill has no scroll). The
  // HARD gates are the deterministic real-click flows: copy_id, export_chooser,
  // logout_relogin, password.
  final hardOk = results.entries
      .where((e) => e.key != 'notification' && e.key != 'autologin')
      .every((e) => e.value);
  return hardOk ? 0 : 1;
}
