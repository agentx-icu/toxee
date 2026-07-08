// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// App-entry extra — high-frequency, low-cost single-instance real-control cases
// surfaced by the 2026-06-12 verify-first review (REAL_APP_UI_TEST_INVENTORY
// §7.5.1). All six drive ONLY A (B is launched-but-idle): the "+" new-entry
// popup, the add-friend Paste button, the two desktop keyboard shortcuts
// (Cmd+Ctrl+N / Cmd+Ctrl+,), the register password-visibility toggle, and the
// login-page Import entry. They mutate no friendship, so they fold into
// sweep_single_app_optimized for launch reuse.
//
// Two cases act on the LoginPage (register visibility + import card); they log
// out first and relogin via the saved account card in a finally, so the launch
// ends logged-in and reusable. The other four act on the live HomePage.

const _appEntryExtraCases = {
  'new_entry_menu_surface',
  'add_friend_paste_clipboard',
  'keyboard_new_conversation_shortcut',
  'keyboard_open_settings_shortcut',
  'irc_join_channel_real_controls',
  'irc_join_channel_loopback_live',
  'register_password_visibility_toggle',
  'login_import_account_card_open',
};

bool _isAppEntryExtraCaseScenario(String scenario) =>
    _appEntryExtraCases.contains(scenario);

Future<int> runAppEntryExtraCase(Inst a, String nickA, String scenario) async {
  await ensureHome(a, nickA);
  var ok = false;
  try {
    ok = switch (scenario) {
      'new_entry_menu_surface' => await _aeeNewEntryMenuSurface(a),
      'add_friend_paste_clipboard' => await _aeeAddFriendPasteClipboard(a),
      'keyboard_new_conversation_shortcut' =>
        await _aeeKeyboardNewConversationShortcut(a),
      'keyboard_open_settings_shortcut' =>
        await _aeeKeyboardOpenSettingsShortcut(a),
      'irc_join_channel_real_controls' => await _aeeIrcJoinChannelRealControls(
        a,
      ),
      'irc_join_channel_loopback_live' => await _aeeIrcJoinChannelLoopbackLive(
        a,
      ),
      'register_password_visibility_toggle' =>
        await _aeeRegisterPasswordVisibilityToggle(a, nickA),
      'login_import_account_card_open' => await _aeeLoginImportAccountCardOpen(
        a,
        nickA,
      ),
      _ => throw ArgumentError(
        'unsupported app-entry-extra scenario: $scenario',
      ),
    };
  } finally {
    await _aeeNormalize(a, nickA);
  }
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runAppEntryExtraSweep(Inst a, String nickA) async {
  await ensureHome(a, nickA);
  var passed = 0;
  var failed = 0;

  Future<void> hard(String name, Future<bool> Function() body) async {
    var ok = false;
    try {
      ok = await body();
    } on PermissionBlockedError {
      rethrow;
    } on Object catch (e, st) {
      ok = false;
      print('[sweep] sweep_app_entry_extra EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _aeeNormalize(a, nickA);
    }
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print('[sweep] sweep_app_entry_extra ${ok ? 'PASS' : 'FAIL'}: $name');
  }

  // HomePage cases first (cheap, no logout), then the two LoginPage cases that
  // log out + relogin — so a relogin failure can't cascade into the home cases.
  await hard('new_entry_menu_surface', () => _aeeNewEntryMenuSurface(a));
  await hard(
    'add_friend_paste_clipboard',
    () => _aeeAddFriendPasteClipboard(a),
  );
  await hard(
    'keyboard_new_conversation_shortcut',
    () => _aeeKeyboardNewConversationShortcut(a),
  );
  await hard(
    'keyboard_open_settings_shortcut',
    () => _aeeKeyboardOpenSettingsShortcut(a),
  );
  await hard(
    'irc_join_channel_real_controls',
    () => _aeeIrcJoinChannelRealControls(a),
  );
  await hard(
    'irc_join_channel_loopback_live',
    () => _aeeIrcJoinChannelLoopbackLive(a),
  );
  await hard(
    'register_password_visibility_toggle',
    () => _aeeRegisterPasswordVisibilityToggle(a, nickA),
  );
  await hard(
    'login_import_account_card_open',
    () => _aeeLoginImportAccountCardOpen(a, nickA),
  );

  final endClean = await _aeeNormalize(a, nickA);
  if (!endClean) failed++;
  print(
    '[sweep] sweep_app_entry_extra summary: passed=$passed failed=$failed '
    'endClean=$endClean',
  );
  return failed == 0 ? 0 : 1;
}

/// End-clean: dismiss any stray add-friend dialog / popup, ensure logged-in on
/// the chats home. The per-case `finally`/`hard` already relogins after a
/// LoginPage case; this is the belt-and-suspenders normalize.
Future<bool> _aeeNormalize(Inst inst, String nickA) async {
  try {
    if (await inst.waitKey('add_friend_id_input', timeoutSecs: 1)) {
      await _closeAddFriendDialog(inst);
    }
  } on Object catch (e) {
    print('[sweep] app-entry normalize: add-friend close best-effort: $e');
  }
  try {
    await inst.osaEscape();
  } on DriveError {
    // best-effort
  }
  // If a LoginPage case left us logged out, recover to HomePage via the saved
  // account card (no-password quick login) before returning to chats.
  var st = await inst.dumpState();
  if (st['sessionReady'] != true) {
    final tox = st['currentAccountToxId']?.toString() ?? '';
    if (tox.isNotEmpty) {
      try {
        await _quickLoginNoPassword(inst, tox);
      } on Object catch (e) {
        print('[sweep] app-entry normalize: recovery relogin failed: $e');
      }
    }
    st = await inst.dumpState();
  }
  if (st['sessionReady'] == true) {
    try {
      await returnToChatsHome(inst, rounds: 4);
    } on Object catch (e) {
      print('[sweep] app-entry normalize: return home best-effort: $e');
    }
  }
  final st2 = await inst.dumpState();
  return st2['sessionReady'] == true;
}

/// new_entry_menu_surface: open the conversation-list "+" popup with a
/// SINGLE-FIRE tap (flutter_skill's double-firing `tap` would call
/// `showButtonMenu()` twice and stack two popup routes) and assert the
/// Add-Contact + Create-Group items render. The Join-IRC item is conditional
/// (only when the IRC plugin wired `onJoinIrcChannel`) — recorded, not required.
Future<bool> _aeeNewEntryMenuSurface(Inst inst) async {
  // Use the SAME proven recipe as _openAddFriendDialog (which passes live):
  // ensureNewEntryShell brings new_entry_menu_button on-stage, and flutter_skill
  // `tap` (tryTapKey) directly invokes its InkWell onTap -> showButtonMenu.
  // (A coordinate tapKeyCenter does NOT trigger showButtonMenu — root cause of
  // the first live FAIL "popup did not open".)
  await ensureNewEntryShell(inst);
  await inst.foreground();

  // Menu items are PopupMenuItems; check flutter_skill first (the proven recipe
  // taps them via tryTapKey, so they ARE surfaced) then the element-tree walk.
  Future<bool> itemPresent(String key) async =>
      await inst.waitKey(key, timeoutSecs: 3) ||
      await inst.waitKeyCenter(key, timeoutSecs: 2);

  var opened = false;
  for (var attempt = 0; attempt < 3 && !opened; attempt++) {
    if (!await inst.tryTapKey('new_entry_menu_button', retries: 2)) {
      await _tryTapText(inst, 'New Chat');
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    opened = await itemPresent('new_entry_add_contact_item');
    if (!opened) await ensureNewEntryShell(inst);
  }
  if (!opened) {
    print('[pair] new_entry_menu_surface: popup did not open');
    return false;
  }

  final addItem = await itemPresent('new_entry_add_contact_item');
  final groupItem = await itemPresent('new_entry_create_group_item');
  final ircItem = await inst.keyCenter('new_entry_join_irc_item') != null;
  await inst.shot('/tmp/ui_app_entry_new_entry_menu_${inst.name}.png');

  // Dismiss the popup (Esc; loop in case flutter_skill's double-fire stacked two
  // menu routes) so the next case starts clean.
  var closed = false;
  for (var i = 0; i < 3 && !closed; i++) {
    try {
      await inst.osaEscape();
    } on DriveError {
      break;
    }
    closed = await inst.waitKeyGone(
      'new_entry_add_contact_item',
      timeoutSecs: 3,
    );
  }
  if (!closed) {
    await inst.tapAt(_sidebarTabX, _sidebarChatsY);
    closed = await inst.waitKeyGone(
      'new_entry_add_contact_item',
      timeoutSecs: 3,
    );
  }

  print(
    '[pair] new_entry_menu_surface: add=$addItem group=$groupItem '
    'irc=$ircItem closed=$closed',
  );
  return addItem && groupItem && closed;
}

/// add_friend_paste_clipboard: seed the macOS clipboard with a deliberately
/// INVALID token, open the add-friend dialog, and tap the REAL Paste button
/// (`_pasteFromClipboard` reads the clipboard into the id field). Submitting then
/// surfaces the malformed-id validator hint — proving the paste filled the field,
/// WITHOUT any FFI add (a valid 76-hex id would attempt a real friend request;
/// the invalid token short-circuits in `_validateToxId` first). Non-destructive.
Future<bool> _aeeAddFriendPasteClipboard(Inst inst) async {
  if (!await _openAddFriendDialog(inst)) {
    print('[pair] add_friend_paste_clipboard: dialog did not open');
    return false;
  }
  const probe = 'rui-paste-probe-not-a-tox-id';
  try {
    await inst.setClipboard(probe);
  } on DriveError catch (e) {
    print(
      '[pair] add_friend_paste_clipboard: setClipboard failed: ${e.message}',
    );
    await _closeAddFriendDialog(inst);
    return false;
  }
  await inst.foreground();
  if (!await inst.tryTapKey('add_friend_paste_button')) {
    print('[pair] add_friend_paste_clipboard: paste button not tappable');
    await _closeAddFriendDialog(inst);
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 400));
  // Submit validates (`_formKey.validate()` -> `_validateToxId`) and stays open;
  // tapKey is single-fire-safe here (no route pop). The message field is
  // pre-filled with the localized default, so `_canSubmit` is satisfied once the
  // paste fills the id field.
  await inst.tapKey('add_friend_submit_button');
  final errorShown = await inst.waitText(
    'Tox address must be 76 hexadecimal characters',
    timeoutSecs: 8,
  );
  final dialogStays = await inst.waitKey('add_friend_id_input', timeoutSecs: 3);

  // Clear the field + close so the next case starts clean.
  await inst.tryTapKey('add_friend_id_input');
  await Future<void>.delayed(const Duration(milliseconds: 150));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort
  }
  final closed = await _closeAddFriendDialog(inst);
  print(
    '[pair] add_friend_paste_clipboard: error=$errorShown '
    'dialogStays=$dialogStays closed=$closed',
  );
  return errorShown && dialogStays && closed;
}

/// keyboard_new_conversation_shortcut: drive the real Cmd+Ctrl+N chord and assert
/// the Add-Friend dialog opens (`_NewConversationIntent` -> `_showAddFriendDialog`),
/// then dismiss. No mouse path is used for the trigger.
Future<bool> _aeeKeyboardNewConversationShortcut(Inst inst) async {
  await returnToChatsHome(inst, rounds: 4);
  // Retry the chord: an osascript keystroke intermittently doesn't reach the
  // app under 2-process foreground contention (the window isn't frontmost the
  // instant the chord fires), so a single send flakes with "dialog did not
  // open". Re-foreground + re-send until the Add-Friend dialog appears.
  var opened = false;
  for (var attempt = 0; attempt < 3 && !opened; attempt++) {
    await inst.foreground();
    try {
      await inst.osaNewConversationShortcut();
    } on DriveError catch (e) {
      print(
        '[pair] keyboard_new_conversation_shortcut: shortcut blocked: ${e.message}',
      );
      return false;
    }
    opened = await inst.waitKey('add_friend_id_input', timeoutSecs: 6);
  }
  await inst.shot('/tmp/ui_app_entry_kbd_newconv_${inst.name}.png');
  if (!opened) {
    print('[pair] keyboard_new_conversation_shortcut: dialog did not open');
    return false;
  }
  var closed = false;
  try {
    await inst.osaEscape();
    closed = await inst.waitKeyGone('add_friend_id_input', timeoutSecs: 4);
  } on DriveError {
    // fall back to the keyed close
  }
  if (!closed) closed = await _closeAddFriendDialog(inst);
  print(
    '[pair] keyboard_new_conversation_shortcut: opened=$opened closed=$closed',
  );
  return opened && closed;
}

/// keyboard_open_settings_shortcut: from the chats tab, drive the real Cmd+Ctrl+,
/// chord and assert the home shell switches to Settings (`_OpenSettingsIntent` ->
/// `_index = 3`, observed via `homeShellTab == 'settings'`). Starts off-settings so
/// the flip is observable, then returns to chats.
Future<bool> _aeeKeyboardOpenSettingsShortcut(Inst inst) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  if (await _settingsTabActive(inst)) {
    print(
      '[pair] keyboard_open_settings_shortcut: already on settings before shortcut',
    );
    return false;
  }
  try {
    await inst.osaOpenSettingsShortcut();
  } on DriveError catch (e) {
    print(
      '[pair] keyboard_open_settings_shortcut: shortcut blocked: ${e.message}',
    );
    return false;
  }
  var onSettings = false;
  for (var i = 0; i < 12 && !onSettings; i++) {
    onSettings = await _settingsTabActive(inst);
    if (onSettings) break;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  await inst.shot('/tmp/ui_app_entry_kbd_settings_${inst.name}.png');
  await returnToChatsHome(inst, rounds: 4);
  print('[pair] keyboard_open_settings_shortcut: onSettings=$onSettings');
  return onSettings;
}

/// irc_join_channel_real_controls: prepare deterministic local IRC installed
/// state through the L3 test seam, then drive the REAL Applications-page Add IRC
/// Channel button and dialog controls. This proves the user-visible IRC join
/// surface is tappable without loading libirc_client or contacting a live server.
Future<bool> _aeeIrcJoinChannelRealControls(Inst inst) async {
  final channel = '#rui-irc-${DateTime.now().microsecondsSinceEpoch}';
  var marked = false;
  try {
    marked = await inst.markAccountTest();
    if (!marked) {
      print('[pair] irc_join_channel_real_controls: markAccountTest failed');
      return false;
    }
    final reset = await inst.l3('l3_irc_set_state', {'reset': true});
    if (reset['ok'] != true) {
      print('[pair] irc_join_channel_real_controls: reset failed $reset');
      return false;
    }
    final prepared = await inst.l3('l3_irc_set_state', {
      'installed': true,
      'server': 'irc.invalid.local',
      'port': 6667,
      'useSasl': false,
      'channels': '[]',
      'localAddOverride': true,
    });
    if (prepared['ok'] != true) {
      print('[pair] irc_join_channel_real_controls: prepare failed $prepared');
      return false;
    }

    await ensureHome(inst, '');
    if (!await inst.tapKeyCenter('sidebar_applications_tab', timeoutSecs: 4)) {
      if (!await inst.tapKeyCenter(
        'bottom_nav_applications_tab',
        timeoutSecs: 4,
      )) {
        print(
          '[pair] irc_join_channel_real_controls: applications tab missing',
        );
        return false;
      }
    }
    if (!await inst.waitKey(
      'applications_irc_add_channel_button',
      timeoutSecs: 10,
    )) {
      print('[pair] irc_join_channel_real_controls: add button missing');
      return false;
    }
    if (!await inst.tapKeyCenter('applications_irc_add_channel_button')) {
      await inst.tapKey('applications_irc_add_channel_button');
    }
    if (!await inst.waitKey(
      'irc_channel_dialog_channel_field',
      timeoutSecs: 8,
    )) {
      print('[pair] irc_join_channel_real_controls: dialog did not open');
      return false;
    }
    await inst.focusType('irc_channel_dialog_channel_field', channel);
    await inst.focusType('irc_channel_dialog_password_field', 'rui-secret');
    await inst.focusType('irc_channel_dialog_nickname_field', 'ruiNick');
    if (!await inst.tapKeyCenter('irc_channel_dialog_join_button')) {
      await inst.tapKey('irc_channel_dialog_join_button');
    }
    final tileKey = 'applications_irc_channel_tile:$channel';
    final tileShown = await inst.waitKey(tileKey, timeoutSecs: 12);
    final state = await inst.dumpState();
    final stateContains = ((state['ircChannels'] as List?) ?? const [])
        .map((e) => e.toString())
        .contains(channel);
    await inst.shot('/tmp/ui_app_entry_irc_join_${inst.name}.png');
    print(
      '[pair] irc_join_channel_real_controls: tile=$tileShown '
      'stateContains=$stateContains channel=$channel',
    );
    return tileShown && stateContains;
  } finally {
    if (marked) {
      try {
        await inst.l3('l3_irc_remove_channel_local', {'channel': channel});
        await inst.l3('l3_irc_set_state', {'reset': true});
      } on Object catch (e) {
        print('[pair] irc_join_channel_real_controls: cleanup failed: $e');
      }
      await inst.unmarkAccountTest();
    }
    await returnToChatsHome(inst, rounds: 4);
  }
}

Future<bool> _aeeIrcJoinChannelLoopbackLive(Inst inst) async {
  final channel = '#rui-live-${DateTime.now().microsecondsSinceEpoch}';
  // Bind host/port come from the driver env so the remote/mobile platforms can
  // pre-forward a KNOWN loopback port (Android `adb reverse`). macOS / iOS /
  // Windows set nothing here -> ephemeral 127.0.0.1, unchanged. The app is told
  // to connect to `server.host:server.port`, which on Android is the device-side
  // 127.0.0.1:<reversed-port> that adb tunnels back to this host.
  final server = await LocalIrcServer.startFromEnv(Platform.environment);
  var marked = false;
  try {
    marked = await inst.markAccountTest();
    if (!marked) {
      print('[pair] irc_join_channel_loopback_live: markAccountTest failed');
      return false;
    }
    final reset = await inst.l3('l3_irc_set_state', {'reset': true});
    if (reset['ok'] != true) {
      print('[pair] irc_join_channel_loopback_live: reset failed $reset');
      return false;
    }

    await ensureHome(inst, '');
    if (!await inst.tapKeyCenter('sidebar_applications_tab', timeoutSecs: 4)) {
      if (!await inst.tapKeyCenter(
        'bottom_nav_applications_tab',
        timeoutSecs: 4,
      )) {
        print(
          '[pair] irc_join_channel_loopback_live: applications tab missing',
        );
        return false;
      }
    }
    if (await inst.waitKey('applications_irc_install_button', timeoutSecs: 4)) {
      if (!await inst.tapKeyCenter('applications_irc_install_button')) {
        await inst.tapKey('applications_irc_install_button');
      }
    }
    if (!await inst.waitKey('applications_irc_server_field', timeoutSecs: 12)) {
      print('[pair] irc_join_channel_loopback_live: config fields missing');
      return false;
    }
    await inst.focusType('applications_irc_server_field', server.host);
    await inst.focusType('applications_irc_port_field', '${server.port}');
    if (!await inst.tapKeyCenter('applications_irc_save_config_button')) {
      await inst.tapKey('applications_irc_save_config_button');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!await inst.tapKeyCenter('applications_irc_add_channel_button')) {
      await inst.tapKey('applications_irc_add_channel_button');
    }
    if (!await inst.waitKey(
      'irc_channel_dialog_channel_field',
      timeoutSecs: 8,
    )) {
      print('[pair] irc_join_channel_loopback_live: dialog did not open');
      return false;
    }
    await inst.focusType('irc_channel_dialog_channel_field', channel);
    await inst.focusType('irc_channel_dialog_password_field', 'rui-secret');
    await inst.focusType('irc_channel_dialog_nickname_field', 'ruiNick');
    if (!await inst.tapKeyCenter('irc_channel_dialog_join_button')) {
      await inst.tapKey('irc_channel_dialog_join_button');
    }

    final joined = await server.waitForCommandContaining('JOIN $channel');
    final tileKey = 'applications_irc_channel_tile:$channel';
    final tileShown = await inst.waitKey(tileKey, timeoutSecs: 12);
    final state = await inst.dumpState();
    final stateContains = ((state['ircChannels'] as List?) ?? const [])
        .map((e) => e.toString())
        .contains(channel);
    await inst.shot('/tmp/ui_app_entry_irc_live_${inst.name}.png');
    print(
      '[pair] irc_join_channel_loopback_live: tile=$tileShown '
      'stateContains=$stateContains joined=$joined channel=$channel '
      'server=${server.host}:${server.port}',
    );
    return tileShown && stateContains;
  } finally {
    if (marked) {
      try {
        await inst.l3('l3_irc_remove_channel_local', {'channel': channel});
        await inst.l3('l3_irc_set_state', {'reset': true});
      } on Object catch (e) {
        print('[pair] irc_join_channel_loopback_live: cleanup failed: $e');
      }
      await inst.unmarkAccountTest();
    }
    await server.dispose();
    await returnToChatsHome(inst, rounds: 4);
  }
}

/// register_password_visibility_toggle: on the RegisterPage, type a password,
/// then tap the visibility toggle and assert the obscure state flips both ways.
/// The flip is observed via the state-suffixed icon key
/// (`register_password_visibility_icon_{obscured|visible}`) added to the icon —
/// the IconButton key stays stable for tapping. Logs out first, relogins in the
/// finally so the launch stays reusable.
Future<bool> _aeeRegisterPasswordVisibilityToggle(
  Inst inst,
  String nickA,
) async {
  // Capture the account id BEFORE logout: production logout clears
  // currentAccountToxId, so a partial logout would leave the end-clean unable to
  // recover (dumpState would report no id). The finally relogins with this id.
  final tox = (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (tox.isEmpty) {
    print('[pair] register_password_visibility_toggle: no current toxId');
    return false;
  }
  var ok = false;
  try {
    if ((await _logoutToLoginPage(inst)).isEmpty) {
      print(
        '[pair] register_password_visibility_toggle: logout to login failed',
      );
      return false;
    }
    if (!await _openRegisterPage(inst)) {
      print(
        '[pair] register_password_visibility_toggle: RegisterPage did not open',
      );
      return false;
    }
    // Give the password field content (the toggle works regardless; this makes the
    // case faithful to a user showing/hiding a typed password).
    await inst.focusType('register_page_password_field', 'RuiVis1!');
    await Future<void>.delayed(const Duration(milliseconds: 250));

    // Field starts obscured (_passwordObscure = true) -> icon key reads 'obscured'.
    final startObscured = await inst.waitKeyCenter(
      'register_password_visibility_icon_obscured',
      timeoutSecs: 5,
    );
    if (!startObscured) {
      print(
        '[pair] register_password_visibility_toggle: initial obscured icon not found',
      );
      return false;
    }
    await inst.tapKeyCenter('register_password_visibility_toggle');
    final flippedVisible = await inst.waitKeyCenter(
      'register_password_visibility_icon_visible',
      timeoutSecs: 5,
    );
    await inst.tapKeyCenter('register_password_visibility_toggle');
    final flippedBack = await inst.waitKeyCenter(
      'register_password_visibility_icon_obscured',
      timeoutSecs: 5,
    );
    await inst.shot('/tmp/ui_app_entry_register_visibility_${inst.name}.png');
    print(
      '[pair] register_password_visibility_toggle: start=$startObscured '
      'visible=$flippedVisible back=$flippedBack',
    );
    ok = startObscured && flippedVisible && flippedBack;
  } finally {
    await _backOutOfRegister(inst);
    var st = await inst.dumpState();
    if (st['sessionReady'] != true) {
      if (!await _quickLoginNoPassword(inst, tox)) {
        print('[pair] register_password_visibility_toggle: relogin failed');
        ok = false;
      }
      st = await inst.dumpState();
    }
    if (st['sessionReady'] == true) {
      await ensureHome(inst, nickA);
    }
  }
  return ok;
}

/// login_import_account_card_open: drive the REAL Import-account card through to
/// its failure path. The native NSOpenPanel is bypassed with the debug-only
/// `l3_set_account_import_pick_path` override (the same seam
/// `restore_import_entry_guard` uses — which only RENDERS the import card and taps
/// RESTORE) pointed at an invalid `.tox`, so tapping the card runs the production
/// `_importToxProfile` -> `runL3AwareAccountImportPicker` -> import-failure ->
/// `login_page_error_banner`. This exercises the real onTap, not a render-only
/// check that would false-pass on a disabled/wrong handler. The override is set
/// and cleared under a temporary test-account marker; the launch ends logged-in.
Future<bool> _aeeLoginImportAccountCardOpen(Inst inst, String nickA) async {
  // Capture the account id BEFORE logout (production logout clears it).
  final tox = (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (tox.isEmpty) {
    print('[pair] login_import_account_card_open: no current toxId');
    return false;
  }
  var ok = false;
  var marked = false;
  final invalidTox = File(
    _portableTmp(
      '/tmp/rui_aee_import_invalid_${DateTime.now().microsecondsSinceEpoch}.tox',
    ),
  );
  try {
    await invalidTox.writeAsString('not a tox profile');
    // The picker override is test-account-gated; mark to SET it, then unmark (the
    // override persists across unmark — same trick as restore_import_entry_guard).
    marked = await inst.markAccountTest();
    if (!marked) {
      print('[pair] login_import_account_card_open: markAccountTest failed');
      return false;
    }
    final override = await inst.l3('l3_set_account_import_pick_path', {
      'path': invalidTox.path,
    });
    if (override['ok'] != true) {
      print('[pair] login_import_account_card_open: override failed $override');
      return false;
    }
    await inst.unmarkAccountTest();
    marked = false;

    if ((await _logoutToLoginPage(inst)) != tox) {
      print('[pair] login_import_account_card_open: logout mismatch');
      return false;
    }
    final importCard = await inst.waitKey(
      'login_page_import_account_card',
      timeoutSecs: 8,
    );
    final tapped =
        importCard && await inst.tapKeyAt('login_page_import_account_card');
    final errorShown =
        tapped &&
        await inst.waitKey('login_page_error_banner', timeoutSecs: 12);
    await inst.shot('/tmp/ui_app_entry_login_import_${inst.name}.png');
    ok = importCard && tapped && errorShown;
    print(
      '[pair] login_import_account_card_open: importCard=$importCard '
      'tapped=$tapped errorShown=$errorShown',
    );
  } finally {
    if (marked) await inst.unmarkAccountTest();
    await _quickLoginNoPassword(inst, tox);
    try {
      final clearMarked = await inst.markAccountTest();
      if (clearMarked) {
        await inst.l3('l3_set_account_import_pick_path', {'path': ''});
        await inst.unmarkAccountTest();
      }
    } on Object catch (e) {
      print('[pair] login_import_account_card_open: clear override failed: $e');
    }
    if ((await inst.dumpState())['sessionReady'] == true) {
      await ensureHome(inst, nickA);
    }
    if (await invalidTox.exists()) {
      await invalidTox.delete();
    }
  }
  return ok;
}
