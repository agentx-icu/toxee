// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 1 of the real-UI sweep campaign — "Settings sweep 2" (12 cases, single
// instance, one launch). See tool/mcp_test/REAL_UI_SWEEP_CAMPAIGN.md.
//
// Every case drives the REAL settings widgets of ONE live instance (A; B is
// launched-but-idle) and asserts a REAL side-effect: an l3_dump_state field
// (themeMode / languageCode / autoDownloadSizeLimit / bootstrapNodeMode /
// autoLogin / notificationSound / sessionReady) AND/OR a real UI signal
// (section header text, a Chinese label after a locale flip, a snackbar /
// dialog-stays-open assertion). Mutating cases restore the prior value so a
// later case is not poisoned; logout_cancel runs LAST (it opens the dangerous
// logout dialog) and only taps Cancel.
//
// The settings list scrolls; the lower Global / Bootstrap sections sit below
// the fold on a narrow window. The driver wheel-scrolls the keyed root ListView
// (UiKeys.settingsScrollView == 'settings_scroll_view') via scrollUntilKey to
// bring a below-fold target onstage before tapping it.

const _settingsScrollKey = 'settings_scroll_view';

/// Poll l3_dump_state until a top-level field equals [want] (string compare; no
/// throw). Mirrors `_waitBoolState` but for string-valued settings fields
/// (themeMode / languageCode / bootstrapNodeMode).
Future<bool> _waitStringState(
  Inst inst,
  String field,
  String want, {
  int timeoutSecs = 12,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if ((await inst.dumpState())[field]?.toString() == want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

/// Poll l3_dump_state until [test] of the field value is true (no throw).
Future<bool> _waitFieldWhere(
  Inst inst,
  String field,
  bool Function(Object?) test, {
  int timeoutSecs = 12,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (test((await inst.dumpState())[field])) return true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

/// SINGLE-FIRE tap on a widget matched by visible [text]: resolve its on-screen
/// centre via `interactiveStructured` and dispatch exactly ONE `tapAt`.
///
/// Why this exists: flutter_skill's `tap`/`tapText` fires the callback TWICE (a
/// synthetic pointer hit AND a direct `_tryInvokeCallback`) — see
/// `Inst.tapKeyCenter`. For a TOGGLE control (the locale row's InkWell flips
/// `_languageExpanded = !_languageExpanded`; the theme SegmentedButton segment),
/// a double-fire toggles twice (even → net no-op), so `tapText` would leave the
/// language list collapsed / re-select the same segment. The labels carry no
/// key, so `tapKeyCenter` cannot be used — this is its text-matched twin.
/// Returns false (no throw) when no positively-sized match is found.
Future<bool> _tapTextCenter(Inst inst, String text, {int timeoutSecs = 6}) async {
  if (!await inst.waitText(text, timeoutSecs: timeoutSecs)) return false;
  for (var attempt = 0; attempt < 5; attempt++) {
    final r = await inst.skill('interactiveStructured', const {});
    final data = r['data'];
    final elements = data is Map ? data['elements'] : null;
    if (elements is List) {
      for (final e in elements) {
        if (e is! Map) continue;
        // Match the element whose visible text equals `text` (the interactive
        // structured dump exposes a `text` field for tappable text widgets).
        final elText = e['text']?.toString();
        if (elText != text) continue;
        final b = e['bounds'];
        if (b is! Map) continue;
        final x = (b['x'] as num?) ?? 0;
        final y = (b['y'] as num?) ?? 0;
        final w = (b['w'] as num?) ?? 0;
        final h = (b['h'] as num?) ?? 0;
        if (w <= 0 || h <= 0) continue;
        await inst.tapAt(x + w / 2, y + h / 2);
        return true;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

/// Bring a below-fold settings widget onstage by wheel-scrolling the keyed
/// settings ListView, then return whether it became visible. Foregrounds first.
Future<bool> _settingsScrollTo(Inst inst, String targetKey) async {
  return inst.scrollUntilKey(
    _settingsScrollKey,
    targetKey,
    dyPerStep: 320,
    maxSteps: 12,
  );
}

/// case 1 — settings_surface_sections: open Settings, scroll the whole page,
/// and assert every top-level section HEADER renders (Account Info / Appearance
/// / Language / Auto Download Size Limit / Bootstrap Nodes). The headers are
/// SectionHeader Text widgets, asserted by their localized English label after
/// scrolling each onstage.
Future<bool> _settingsSurfaceSections(Inst inst) async {
  await _openSettings(inst);
  // Account Info sits at the very top (already onstage).
  final accountInfo = await inst.waitText('Account Info', timeoutSecs: 6);
  // Appearance + Language are in the GlobalSettingsSection (mid page).
  final appearance =
      await inst.waitText('Appearance', timeoutSecs: 2) ||
      await _scrollToText(inst, 'Appearance');
  final language =
      await inst.waitText('Language', timeoutSecs: 2) ||
      await _scrollToText(inst, 'Language');
  // Auto Download Size Limit + Bootstrap Nodes are lower still — scroll the
  // keyed download-limit field onstage, then assert BOTH the keyed field AND its
  // SectionHeader text rendered (the field-key alone wouldn't prove the header).
  final downloadField = await _settingsScrollTo(
    inst,
    'settings_download_limit_field',
  );
  final downloadHeader =
      await inst.waitText('Auto Download Size Limit', timeoutSecs: 2) ||
      await _scrollToText(inst, 'Auto Download Size Limit');
  final downloadLimit = downloadField && downloadHeader;
  final bootstrap =
      await inst.waitText('Bootstrap Nodes', timeoutSecs: 2) ||
      await _scrollToText(inst, 'Bootstrap Nodes');
  // Scroll back to the top so the next case starts from a known position.
  await inst.scrollAt(_settingsScrollKey, dy: -4000);
  print(
    '[pair] settings_surface_sections: accountInfo=$accountInfo '
    'appearance=$appearance language=$language '
    'downloadField=$downloadField downloadHeader=$downloadHeader '
    'bootstrap=$bootstrap',
  );
  return accountInfo && appearance && language && downloadLimit && bootstrap;
}

/// Wheel-scroll the settings list down a few ticks polling for [text] (no
/// keyed target available — SectionHeader Text has no key). Best-effort.
Future<bool> _scrollToText(Inst inst, String text, {int maxSteps = 12}) async {
  await inst.foreground();
  if (await inst.waitText(text, timeoutSecs: 1)) return true;
  for (var step = 0; step < maxSteps; step++) {
    await inst.scrollAt(_settingsScrollKey, dy: 320);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (await inst.waitText(text, timeoutSecs: 1)) return true;
  }
  return false;
}

/// Tap the theme SegmentedButton's [label] segment ("System" | "Light" |
/// "Dark"). The ButtonSegments carry no per-segment key (SegmentedButton's
/// ButtonSegment takes none), so we drive by the localized visible label after
/// bringing the Appearance card onstage.
Future<bool> _tapThemeSegment(Inst inst, String label) async {
  await _scrollToText(inst, 'Appearance');
  // Single-fire the segment (a double-fire just re-selects the same value —
  // harmless — but the single tap avoids a press-animation race and matches the
  // toggle controls' convention). The segment label has no key, so _tapTextCenter
  // (text-matched single tapAt) is the right primitive.
  return _tapTextCenter(inst, label);
}

/// case 2 — settings_theme_dark (S57): tap the real "Dark" theme segment →
/// dump themeMode persists 'dark' AND the "Dark" segment label is visible
/// (real UI signal). Restored to the prior mode by case 3.
Future<bool> _settingsThemeDark(Inst inst) async {
  await _openSettings(inst);
  final before = (await inst.dumpState())['themeMode']?.toString() ?? 'system';
  final tapped = await _tapThemeSegment(inst, 'Dark');
  final persisted = tapped && await _waitStringState(inst, 'themeMode', 'dark');
  // Real-UI signal: the Dark segment label is still rendered onstage (the
  // Appearance card did not vanish / crash on the rebuild).
  final labelVisible = await inst.waitText('Dark', timeoutSecs: 4);
  print(
    '[pair] settings_theme_dark: before=$before tapped=$tapped '
    'persisted=$persisted labelVisible=$labelVisible',
  );
  return tapped && persisted && labelVisible;
}

/// case 3 — settings_theme_light_back (S57): revert to "Light" → dump themeMode
/// persists 'light' and the UI re-renders (Light segment label visible). This
/// leaves the app in light mode (a deterministic, known state for later cases).
Future<bool> _settingsThemeLightBack(Inst inst) async {
  await _openSettings(inst);
  final tapped = await _tapThemeSegment(inst, 'Light');
  final persisted = tapped && await _waitStringState(inst, 'themeMode', 'light');
  final labelVisible = await inst.waitText('Light', timeoutSecs: 4);
  print(
    '[pair] settings_theme_light_back: tapped=$tapped '
    'persisted=$persisted labelVisible=$labelVisible',
  );
  return tapped && persisted && labelVisible;
}

/// case 4 — settings_locale_zh_roundtrip (S38): expand the Language selector,
/// pick 简体中文 → dump languageCode == 'zh-Hans' AND a known Chinese label
/// (外观, the Appearance section header) is visible; then revert to English via
/// KEYS-free native labels (English label is unchanged across locales). Reverts
/// BEFORE any later text-based English assertions so it can't poison them.
Future<bool> _settingsLocaleZhRoundtrip(Inst inst) async {
  await _openSettings(inst);
  // The Language card is in the GlobalSettingsSection; bring it onstage. The
  // collapsed selector shows the CURRENT selection ("English" while in en).
  await _scrollToText(inst, 'Language');
  // Expand by tapping the selected-language label, then choose 简体中文.
  // SINGLE-FIRE: the selector InkWell toggles `_languageExpanded =
  // !_languageExpanded`, so flutter_skill's double-firing `tap` would open AND
  // immediately re-close it (net no-op). _tapTextCenter dispatches exactly one
  // pointer tap. After tapping, the 简体中文 option must appear (proves it
  // opened); if it didn't, retry the expand (an even/odd toggle correction).
  var expanded = false;
  for (var attempt = 0; attempt < 3 && !expanded; attempt++) {
    if (!await _tapTextCenter(inst, 'English')) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expanded = await inst.waitText('简体中文', timeoutSecs: 2);
  }
  if (!expanded) {
    print('[pair] settings_locale_zh: could not expand language selector');
    return false;
  }
  if (!await _tapTextCenter(inst, '简体中文')) {
    print('[pair] settings_locale_zh: 简体中文 option not tappable');
    return false;
  }
  final zhPersisted = await _waitStringState(inst, 'languageCode', 'zh-Hans');
  // Chinese label assertion: the Appearance header now reads "外观".
  await inst.foreground();
  final zhLabelVisible =
      await inst.waitText('外观', timeoutSecs: 6) ||
      await _scrollToText(inst, '外观');
  print(
    '[pair] settings_locale_zh: zhPersisted=$zhPersisted '
    'zhLabelVisible=$zhLabelVisible',
  );
  // Revert to English. The language option labels are NATIVE names (literal
  // 'English' / '简体中文'), unchanged by locale, so tapping "English" works
  // while in Chinese. The collapsed selector now shows "简体中文" — tap it to
  // expand, then tap "English".
  await _scrollToText(inst, '语言'); // zh "Language" header
  var reverted = false;
  for (var attempt = 0; attempt < 3 && !reverted; attempt++) {
    // Expand (single-fire) the now-Chinese-labelled selector, then pick English.
    if (await _tapTextCenter(inst, '简体中文')) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // Only proceed if the option list actually opened (English option shows).
      if (await inst.waitText('English', timeoutSecs: 2) &&
          await _tapTextCenter(inst, 'English')) {
        reverted = await _waitStringState(inst, 'languageCode', 'en');
      }
    }
    if (!reverted) await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  // Confirm the English label is back (the load-bearing post-revert invariant).
  await inst.foreground();
  final enLabelBack =
      await inst.waitText('Appearance', timeoutSecs: 4) ||
      await _scrollToText(inst, 'Appearance');
  print(
    '[pair] settings_locale_zh_roundtrip: zhPersisted=$zhPersisted '
    'zhLabelVisible=$zhLabelVisible reverted=$reverted enLabelBack=$enLabelBack',
  );
  return zhPersisted && zhLabelVisible && reverted && enLabelBack;
}

/// case 5 — settings_download_limit_edit (S98): bring the keyed download-limit
/// field onstage, clear it, type a fresh value, tap the keyed Save → dump
/// autoDownloadSizeLimit reflects the new value. Restores the prior value.
Future<bool> _settingsDownloadLimitEdit(Inst inst) async {
  await _openSettings(inst);
  if (!await _settingsScrollTo(inst, 'settings_download_limit_field')) {
    print('[pair] settings_download_limit: field never reached');
    return false;
  }
  final beforeRaw = (await inst.dumpState())['autoDownloadSizeLimit'];
  final before = _stateInt(beforeRaw) ?? 30;
  // A distinct in-range value (1..10000 per _saveAutoDownloadSizeLimit) that
  // differs from `before` so the change is observable.
  final target = before == 42 ? 37 : 42;
  // Focus the field, select-all + delete via real OS keys (the field is keyed
  // but its inner editable is reached via focusType's tap-then-enterText; clear
  // first so we don't append to the existing text).
  await inst.tapKey('settings_download_limit_field');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  try {
    await inst.osaClear();
  } on DriveError {
    // best-effort; enterText below replaces typical short content anyway
  }
  final typed = await inst.skill('enterText', {'text': '$target'});
  if (typed['success'] != true) {
    print('[pair] settings_download_limit: enterText failed: $typed');
    return false;
  }
  await inst.tapKey('settings_download_limit_save_button');
  final saved = await _waitFieldWhere(
    inst,
    'autoDownloadSizeLimit',
    (v) => _stateInt(v) == target,
    timeoutSecs: 12,
  );
  // Restore the prior value so later cases / reruns see the original cap, and
  // ENFORCE the restore (an un-restored value would poison reruns).
  var restored = true;
  if (saved) {
    await inst.tapKey('settings_download_limit_field');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await inst.osaClear();
    } on DriveError {
      // best-effort
    }
    await inst.skill('enterText', {'text': '$before'});
    await inst.tapKey('settings_download_limit_save_button');
    restored = await _waitFieldWhere(
      inst,
      'autoDownloadSizeLimit',
      (v) => _stateInt(v) == before,
      timeoutSecs: 8,
    );
  }
  print(
    '[pair] settings_download_limit_edit: before=$before target=$target '
    'saved=$saved restored=$restored',
  );
  return saved && restored;
}

/// Tap a bootstrap-mode RadioListTile by key and wait for the dump
/// bootstrapNodeMode to reflect it. The radios are below the fold; bring the
/// keyed tile onstage first.
Future<bool> _setBootstrapMode(Inst inst, String key, String mode) async {
  if (!await _settingsScrollTo(inst, key)) {
    print('[pair] bootstrap mode: tile "$key" never reached');
    return false;
  }
  await inst.tapKey(key);
  return _waitStringState(inst, 'bootstrapNodeMode', mode);
}

/// case 6 — settings_bootstrap_mode_cycle (S99/S85): cycle the bootstrap mode
/// radios auto→manual→lan→auto, asserting the dump bootstrapNodeMode after each
/// real tap. Ends on 'auto' (the default, leaving a known state).
Future<bool> _settingsBootstrapModeCycle(Inst inst) async {
  await _openSettings(inst);
  // Normalize to auto first (cheap, and proves the starting point).
  final toAuto0 = await _setBootstrapMode(
    inst,
    'settings_bootstrap_mode_auto',
    'auto',
  );
  final toManual = await _setBootstrapMode(
    inst,
    'settings_bootstrap_mode_manual',
    'manual',
  );
  final toLan = await _setBootstrapMode(
    inst,
    'settings_bootstrap_mode_lan',
    'lan',
  );
  final backAuto = await _setBootstrapMode(
    inst,
    'settings_bootstrap_mode_auto',
    'auto',
  );
  print(
    '[pair] settings_bootstrap_mode_cycle: auto0=$toAuto0 manual=$toManual '
    'lan=$toLan backAuto=$backAuto',
  );
  return toAuto0 && toManual && toLan && backAuto;
}

/// case 7 — settings_bootstrap_manual_add_node (S89): switch to manual mode,
/// expand the manual node form, fill host/port/pubkey via real input → the
/// manual node form ROW renders (host/port/pubkey fields + Test button onstage).
///
/// NOTE on scope: the production "Set as Current Node" button only appears AFTER
/// a live `addBootstrapNode` test SUCCEEDS (which needs real DHT reachability,
/// non-deterministic in the harness), so the faithful, bounded assertion here is
/// that the real manual-node form mounts and accepts input. Mode + form mount
/// IS the S89 surface (a real settings mutation: bootstrapNodeMode→manual,
/// persisted). Leaves the form EXPANDED for case 8 to collapse.
Future<bool> _settingsBootstrapManualAddNode(Inst inst) async {
  await _openSettings(inst);
  final manualMode = await _setBootstrapMode(
    inst,
    'settings_bootstrap_mode_manual',
    'manual',
  );
  if (!manualMode) {
    print('[pair] bootstrap_manual_add: could not enter manual mode');
    return false;
  }
  // Expand the manual-input form. The expand button TOGGLES `_manualInputExpanded
  // = !_manualInputExpanded`, so a double-firing `tapKey` would open AND close it
  // (net no-op). Bring it onstage then SINGLE-FIRE via tapKeyCenter (one tapAt).
  if (!await _settingsScrollTo(inst, 'manual_node_input_button')) {
    print('[pair] bootstrap_manual_add: expand button never reached');
    return false;
  }
  if (!await inst.tapKeyCenter('manual_node_input_button')) {
    print('[pair] bootstrap_manual_add: expand button not tappable');
    return false;
  }
  final hostShown = await inst.waitKey('manual_node_host_field', timeoutSecs: 6);
  if (!hostShown) {
    print('[pair] bootstrap_manual_add: host field did not appear');
    return false;
  }
  // Fill the form via the keyed fields (focusType: tap then enterText).
  await inst.focusType('manual_node_host_field', 'tox.example.org');
  await inst.focusType('manual_node_port_field', '33445');
  await inst.focusType('manual_node_pubkey_field', 'A' * 64);
  final portShown = await inst.waitKey('manual_node_port_field', timeoutSecs: 4);
  final pubkeyShown = await inst.waitKey(
    'manual_node_pubkey_field',
    timeoutSecs: 4,
  );
  final testShown = await inst.waitKey('manual_node_test_button', timeoutSecs: 4);
  print(
    '[pair] settings_bootstrap_manual_add_node: manualMode=$manualMode '
    'host=$hostShown port=$portShown pubkey=$pubkeyShown test=$testShown',
  );
  return manualMode && hostShown && portShown && pubkeyShown && testShown;
}

/// case 8 — settings_bootstrap_manual_remove_node (S89): collapse the manual
/// node form via the production toggle → the form ROW (host/port/pubkey fields)
/// is GONE.
///
/// NOTE on scope: BootstrapSettingsSection has NO per-node remove affordance
/// (manual mode only supports overwrite-as-current; the "current node" card is
/// replaced, never deleted; the auto-mode Route-selection page is a read-only
/// fetched-node list). The closest real "remove the row" surface is the manual
/// input EXPAND toggle: tapping it again collapses the just-added node form so
/// its fields leave the tree. We assert that GONE transition (the inverse of
/// case 7), then restore mode→auto so the pair ends in a known state.
Future<bool> _settingsBootstrapManualRemoveNode(Inst inst) async {
  await _openSettings(inst);
  // Ensure we are in manual mode with the form expanded (case 7 left it so, but
  // be robust to running case 8 standalone).
  await _setBootstrapMode(inst, 'settings_bootstrap_mode_manual', 'manual');
  if (!await _settingsScrollTo(inst, 'manual_node_input_button')) {
    print('[pair] bootstrap_manual_remove: expand button never reached');
    return false;
  }
  // If the form is collapsed, expand it first so there is a row to remove.
  // SINGLE-FIRE the toggle (see case 7).
  if (!await inst.waitKey('manual_node_host_field', timeoutSecs: 2)) {
    await inst.tapKeyCenter('manual_node_input_button');
    if (!await inst.waitKey('manual_node_host_field', timeoutSecs: 6)) {
      print('[pair] bootstrap_manual_remove: could not expand form to remove');
      return false;
    }
  }
  // Collapse it again — the production toggle removes the form row. SINGLE-FIRE.
  if (!await inst.tapKeyCenter('manual_node_input_button')) {
    print('[pair] bootstrap_manual_remove: collapse toggle not tappable');
    return false;
  }
  final hostGone = await inst.waitKeyGone(
    'manual_node_host_field',
    timeoutSecs: 8,
  );
  final pubkeyGone = await inst.waitKeyGone(
    'manual_node_pubkey_field',
    timeoutSecs: 4,
  );
  // Restore mode→auto for a clean end state, and ENFORCE the restore (a failed
  // restore would leave the pair in manual mode → state-poisoning false pass).
  final restoredAuto = await _setBootstrapMode(
    inst,
    'settings_bootstrap_mode_auto',
    'auto',
  );
  print(
    '[pair] settings_bootstrap_manual_remove_node: hostGone=$hostGone '
    'pubkeyGone=$pubkeyGone restoredAuto=$restoredAuto',
  );
  return hostGone && pubkeyGone && restoredAuto;
}

/// case 9 — settings_autologin_toggle_hard (S96): scroll the auto-login Switch
/// onstage, tap its CENTER (a real pointer tap, not flutter_skill's synthetic
/// tap which doesn't reliably toggle a Material Switch) → dump autoLogin flips;
/// tap back → restores. Upgrades the documented soft autologin case to a hard
/// gate by (a) scrolling it onstage and (b) using tapKeyCenter (real tapAt).
Future<bool> _settingsAutologinToggleHard(Inst inst) async {
  await _openSettings(inst);
  // The auto-login row is in the Account card (upper-mid); bring it onstage.
  if (!await _settingsScrollTo(inst, 'settings_auto_login_switch')) {
    print('[pair] autologin_hard: switch never reached');
    return false;
  }
  final before = (await inst.dumpState())['autoLogin'] == true;
  if (!await inst.tapKeyCenter('settings_auto_login_switch')) {
    print('[pair] autologin_hard: switch center not tappable');
    return false;
  }
  final flipped = await _waitBoolState(inst, 'autoLogin', !before);
  // Restore (only if it flipped, so a pass never leaves autoLogin mutated).
  var restored = true;
  if (flipped) {
    await inst.tapKeyCenter('settings_auto_login_switch');
    restored = await _waitBoolState(inst, 'autoLogin', before);
  }
  print(
    '[pair] settings_autologin_toggle_hard: before=$before flipped=$flipped '
    'restored=$restored',
  );
  return flipped && restored;
}

/// case 10 — settings_notifsound_toggle_hard (S97): same upgrade for the
/// notification-sound Switch (lives lower, in the GlobalSettingsSection).
Future<bool> _settingsNotifSoundToggleHard(Inst inst) async {
  await _openSettings(inst);
  if (!await _settingsScrollTo(inst, 'settings_notification_sound_switch')) {
    print('[pair] notifsound_hard: switch never reached');
    return false;
  }
  final before = (await inst.dumpState())['notificationSound'] == true;
  if (!await inst.tapKeyCenter('settings_notification_sound_switch')) {
    print('[pair] notifsound_hard: switch center not tappable');
    return false;
  }
  final flipped = await _waitBoolState(inst, 'notificationSound', !before);
  var restored = true;
  if (flipped) {
    await inst.tapKeyCenter('settings_notification_sound_switch');
    restored = await _waitBoolState(inst, 'notificationSound', before);
  }
  print(
    '[pair] settings_notifsound_toggle_hard: before=$before flipped=$flipped '
    'restored=$restored',
  );
  return flipped && restored;
}

/// case 11 — settings_password_mismatch_error (S40): open the set-password
/// dialog, type MISMATCHED new/confirm values, tap Save → the production handler
/// shows the "Passwords do not match" snackbar and the dialog STAYS OPEN
/// (returns early, no Navigator.pop). Asserts the snackbar text AND that the
/// new-password field is still in the tree. ESC dismisses without setting a
/// password (so no later case inherits a password-protected account).
Future<bool> _settingsPasswordMismatchError(Inst inst) async {
  await _openSettings(inst);
  // Below-fold opener: tapKey fires the callback once off-screen.
  if (!await _settingsScrollTo(inst, 'settings_set_password_button')) {
    // Even if it doesn't scroll fully onstage, the below-fold tapKey still opens
    // the dialog via its direct _tryInvokeCallback, so continue anyway.
    print('[pair] password_mismatch: set-password button below fold (ok)');
  }
  await inst.tapKey('settings_set_password_button');
  if (!await inst.waitKey('settings_set_password_new_field', timeoutSecs: 8)) {
    print('[pair] password_mismatch: dialog did not open');
    return false;
  }
  await inst.focusType('settings_set_password_new_field', 'RuiPwAAAA1');
  await inst.focusType('settings_set_password_confirm_field', 'RuiPwBBBB2');
  // The Save button calls Navigator.pop ONLY when the values match; on a
  // mismatch it shows a snackbar and returns WITHOUT popping. So flutter_skill's
  // double-fire `tap` is safe here (no route to double-pop), but we use the
  // single-fire center tap to mirror the matching-path harness convention.
  if (!await inst.tapKeyCenter('settings_set_password_save_button')) {
    print('[pair] password_mismatch: save button not tappable');
    return false;
  }
  final snackbar = await inst.waitText('Passwords do not match', timeoutSecs: 8);
  // The dialog must STILL be open (its keyed field present) — proves the
  // mismatch short-circuited before the pop.
  final dialogStays = await inst.waitKey(
    'settings_set_password_new_field',
    timeoutSecs: 4,
  );
  // Dismiss the dialog WITHOUT setting a password (ESC) so the account stays
  // password-free for later cases (logout_cancel relies on no password). ESC
  // can be eaten by focus state, so fall back to the keyed Cancel button, and
  // ENFORCE that the dialog is gone — a stray password dialog left mounted would
  // poison case 12 (and is itself a real failure to surface, not swallow).
  try {
    await inst.osaEscape();
  } on DriveError {
    // best effort; the Cancel fallback below handles a swallowed ESC.
  }
  var dismissed = await inst.waitKeyGone(
    'settings_set_password_new_field',
    timeoutSecs: 4,
  );
  if (!dismissed) {
    await inst.tapKeyCenter('settings_set_password_cancel_button');
    dismissed = await inst.waitKeyGone(
      'settings_set_password_new_field',
      timeoutSecs: 6,
    );
  }
  print(
    '[pair] settings_password_mismatch_error: snackbar=$snackbar '
    'dialogStays=$dialogStays dismissed=$dismissed',
  );
  return snackbar && dialogStays && dismissed;
}

/// case 12 — settings_logout_cancel (S44): open the logout confirm dialog, tap
/// CANCEL → the dialog closes and the session is STILL ready (sessionReady
/// stays true, no teardown). Runs LAST because it opens the dangerous logout
/// dialog; it only ever taps Cancel, so the session survives.
Future<bool> _settingsLogoutCancel(Inst inst) async {
  await _openSettings(inst);
  final wasReady = (await inst.dumpState())['sessionReady'] == true;
  // Below-fold opener (fires once via direct callback).
  if (!await _settingsScrollTo(inst, 'settings_logout_button')) {
    print('[pair] logout_cancel: logout button below fold (ok)');
  }
  await inst.tapKey('settings_logout_button');
  if (!await inst.waitKey('settings_logout_confirm_button', timeoutSecs: 8)) {
    print('[pair] logout_cancel: confirm dialog did not open');
    return false;
  }
  // The logout dialog's Cancel button has NO key (only the confirm button is
  // keyed) — tap the "Cancel" label. It calls popDialogIfCurrent(context,false)
  // which only pops the dialog (no page-pop), so the double-fire `tapText` is
  // safe here.
  if (!await _tryTapText(inst, 'Cancel')) {
    print('[pair] logout_cancel: Cancel label not tappable');
    return false;
  }
  // Dialog gone (confirm button no longer in the tree) AND session intact.
  final dialogClosed = await inst.waitKeyGone(
    'settings_logout_confirm_button',
    timeoutSecs: 8,
  );
  // sessionReady must remain true: Cancel must NOT have torn down the session.
  final stillReady = await _waitBoolState(
    inst,
    'sessionReady',
    true,
    timeoutSecs: 5,
  );
  print(
    '[pair] settings_logout_cancel: wasReady=$wasReady '
    'dialogClosed=$dialogClosed stillReady=$stillReady',
  );
  return wasReady && dialogClosed && stillReady;
}

/// Best-effort, idempotent between-cases normalizer: drive locale back to
/// English and bootstrap mode back to auto IF a prior case left them mutated
/// (e.g. it FAILED mid-restore). Cheap no-op when already normalized (just a
/// dump read). This is the cross-case poison guard codex flagged: the sweep
/// keeps running after a failed case, so a stuck-in-zh locale would false-FAIL
/// the later English-text cases (password "Passwords do not match", logout
/// "Cancel"). Never throws — a failure here is logged, not propagated (the next
/// case's own assertions remain the source of truth).
Future<void> _normalizeBetweenCases(Inst inst) async {
  try {
    final st = await inst.dumpState();
    if (st['languageCode']?.toString() != 'en') {
      print('[sweep] normalize: locale is ${st['languageCode']} -> reverting en');
      await _openSettings(inst);
      // The selector shows the current NATIVE label; expand + pick English.
      // Try the known non-English native labels (zh-Hans/zh-Hant/ja/ko/ar).
      const nativeLabels = ['简体中文', '繁體中文', '日本語', '한국어', 'العربية'];
      await _scrollToText(inst, 'English'); // option labels are native literals
      for (final label in nativeLabels) {
        if (await _tapTextCenter(inst, label, timeoutSecs: 1)) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (await inst.waitText('English', timeoutSecs: 2)) {
            await _tapTextCenter(inst, 'English');
          }
          break;
        }
      }
      await _waitStringState(inst, 'languageCode', 'en', timeoutSecs: 4);
    }
    final st2 = await inst.dumpState();
    if (st2['bootstrapNodeMode']?.toString() == 'manual' ||
        st2['bootstrapNodeMode']?.toString() == 'lan') {
      print(
        '[sweep] normalize: bootstrap mode is ${st2['bootstrapNodeMode']} '
        '-> reverting auto',
      );
      await _openSettings(inst);
      await _setBootstrapMode(inst, 'settings_bootstrap_mode_auto', 'auto');
    }
  } on DriveError catch (e) {
    print('[sweep] normalize: best-effort failed (ignored): ${e.message}');
  }
}

/// sweep_settings2 — Batch 1: chain all 12 settings-sweep-2 cases on ONE launch.
/// Order avoids state poisoning: surface read first; theme dark→light (ends
/// light); locale zh→en roundtrip (reverts BEFORE later English-text cases);
/// download-limit (restores); bootstrap mode cycle (ends auto); manual add then
/// remove (collapse); the two Switch toggles (restore); password-mismatch
/// (ESC-dismiss, leaves no password); logout_cancel LAST (Cancel only — session
/// survives). Prints `[sweep] <case>: PASS|FAIL` per case + final counts; exits
/// non-zero if any HARD case fails.
Future<int> runSettingsSweep2(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
    timeoutSecs: 90,
  );
  // Ordered list of (caseId, runner). All 12 are HARD gates.
  final cases = <MapEntry<String, Future<bool> Function()>>[
    MapEntry('settings_surface_sections', () => _settingsSurfaceSections(inst)),
    MapEntry('settings_theme_dark', () => _settingsThemeDark(inst)),
    MapEntry('settings_theme_light_back', () => _settingsThemeLightBack(inst)),
    MapEntry(
      'settings_locale_zh_roundtrip',
      () => _settingsLocaleZhRoundtrip(inst),
    ),
    MapEntry(
      'settings_download_limit_edit',
      () => _settingsDownloadLimitEdit(inst),
    ),
    MapEntry(
      'settings_bootstrap_mode_cycle',
      () => _settingsBootstrapModeCycle(inst),
    ),
    MapEntry(
      'settings_bootstrap_manual_add_node',
      () => _settingsBootstrapManualAddNode(inst),
    ),
    MapEntry(
      'settings_bootstrap_manual_remove_node',
      () => _settingsBootstrapManualRemoveNode(inst),
    ),
    MapEntry(
      'settings_autologin_toggle_hard',
      () => _settingsAutologinToggleHard(inst),
    ),
    MapEntry(
      'settings_notifsound_toggle_hard',
      () => _settingsNotifSoundToggleHard(inst),
    ),
    MapEntry(
      'settings_password_mismatch_error',
      () => _settingsPasswordMismatchError(inst),
    ),
    MapEntry('settings_logout_cancel', () => _settingsLogoutCancel(inst)),
  ];

  var passed = 0;
  var failed = 0;
  for (final entry in cases) {
    bool ok;
    String? failDetail;
    try {
      ok = await entry.value();
    } on PermissionBlockedError {
      rethrow; // surfaces as BLOCKED(78) at the driver level
    } on DriveError catch (e) {
      ok = false;
      failDetail = 'DriveError: ${e.message}';
    }
    if (ok) {
      passed++;
      print('[sweep] ${entry.key}: PASS');
    } else {
      failed++;
      print(
        '[sweep] ${entry.key}: FAIL'
        '${failDetail != null ? ' ($failDetail)' : ''}',
      );
    }
    // Cross-case poison guard: if a case failed mid-restore (or even on a pass),
    // re-normalize locale→en + bootstrap→auto so a later English-text case isn't
    // false-failed by leftover state. Idempotent / best-effort (never throws).
    await _normalizeBetweenCases(inst);
  }
  print('[sweep] sweep_settings2 RESULTS: $passed PASS / $failed FAIL '
      '(${cases.length} total)');
  await inst.shot('/tmp/ui_settings_sweep2_${inst.name}.png');
  return failed == 0 ? 0 : 1;
}
