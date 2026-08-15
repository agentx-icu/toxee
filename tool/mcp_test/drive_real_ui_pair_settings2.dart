// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 1 of the real-UI sweep campaign — "Settings sweep 2" (12 cases, single
// instance, one launch). See tool/mcp_test/REAL_UI_GATES.md.
//
// Every case drives the REAL settings widgets of ONE live instance (A; B is
// launched-but-idle) and asserts a REAL side-effect: an l3_dump_state field
// (themeMode / languageCode / autoDownloadSizeLimit / bootstrapNodeMode /
// autoLogin / notificationSound / sessionReady) AND/OR a real UI signal.
// Mutating cases restore the prior value; logout_cancel runs LAST (dangerous
// dialog) and only taps Cancel. Lower sections can sit below the fold, so the
// driver wheel-scrolls the keyed root ListView (UiKeys.settingsScrollView) to
// bring a target into the MEASURED visible band ([_settingsBand]) first.

const _settingsScrollKey = 'settings_scroll_view';

/// Poll l3_dump_state until a top-level field equals [want] (string compare; no
/// throw) — the string-valued twin of `_waitBoolState`.
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

/// SINGLE-FIRE tap on a widget matched by visible [text] — the text-matched twin
/// of `Inst.tapKeyCenter`. flutter_skill's `tapText` fires the callback TWICE,
/// which on a TOGGLE (the locale row's `_languageExpanded` InkWell) is a net
/// no-op, and these labels carry no key. False (no throw) when nothing matches.
Future<bool> _tapTextCenter(
  Inst inst,
  String text, {
  int timeoutSecs = 6,
}) async {
  if (!await inst.waitText(text, timeoutSecs: timeoutSecs)) return false;
  for (var attempt = 0; attempt < 5; attempt++) {
    final r = await inst.skill('interactiveStructured', const {});
    final data = r['data'];
    final elements = data is Map ? data['elements'] : null;
    if (elements is List) {
      for (final e in elements) {
        if (e is! Map) continue;
        // Match the element whose visible text equals `text`.
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

// DESKTOP band (live macOS window 1280x800): a settings widget is tappable only
// when its CENTER lands within it. A ListView keeps OFF-screen children MOUNTED
// (cacheExtent), so a plain `waitKey` is true even for a target scrolled OUT of
// the viewport (the auto-login switch at y ~ -334 was "found" yet untappable);
// we verify the real on-screen y instead.
const double _settingsViewTop = 90;
const double _settingsViewBottom = 700;
// A bottom-anchored LAST element (the manual-node expand button while the form
// is collapsed) can never enter the reading band: at max scroll extent nothing
// below it can pull it up. So on a STALL, accept it up to this extended bottom.
const double _settingsViewBottomMax = 770;

// MOBILE fallback band — the iPhone-tuned constants, used ONLY when the live
// viewport probe cannot resolve the settings ListView. They are also the FLOOR
// of the measured band, so a measurement can only ever widen it.
const double _settingsMobileViewTop = 80;
const double _settingsMobileViewBottom = 620;
const double _settingsMobileViewBottomMax = 690;
// The settings ListView is inside a SafeArea, so its top edge is the status-bar
// inset (~24pt on the notch-less iPads, more on a notched iPhone). Only the
// STALL bound leans on this estimate; the reading bound does not.
const double _settingsMobileSafeAreaTop = 24;

/// Per-instance cache of the measured mobile band (geometry is fixed per run).
final _settingsBandCache =
    <String, ({double top, double bottom, double maxBottom})>{};

/// The visible band a settings widget must be scrolled into — MEASURED off the
/// live shell instead of assumed.
///
/// ROOT CAUSE (iPad, 2026-08-14): the WIDE shell renders every settings section
/// INLINE in one ListView (settings_page.dart's non-`isMobile` branch →
/// `_buildSettingsChildren`: Account / Global / Bootstrap cards) and a tablet
/// viewport is roughly twice the 620/690 constants tuned on an 844pt iPhone.
/// Targets in its LOWER half (download-limit field, bootstrap mode radios,
/// manual-node expand button) are fully ON SCREEN yet below the assumed bottom,
/// with little or no scroll extent left to pull them up — so
/// `_scrollKeyIntoBand` burned its step budget and reported "never reached" for
/// widgets a user can see and touch. One cause, five iPad failures.
///
/// Fix: derive the band from the REAL viewport. `settings_scroll_view` is keyed
/// on the ListView itself, so `ui_key_center` resolves its viewport RenderBox
/// centre EXACTLY — and the reading `bottom` IS that centre: a target at/above
/// it sits in the viewport's TOP HALF, hence certainly on-screen and
/// hit-testable, with no dependence on the screen height (unreadable on iOS). An
/// ESTIMATED bottom is not good enough — a live probe showed a mid-scroll
/// position ~1100 that passed a `2*cy - inset` estimate yet was clipped, so
/// `tapAt` there reported "Tap successful" and changed nothing. Targets that
/// cannot come that high (bottom-anchored rows) are covered by the STALL rule
/// below, which fires only once scrolling has run out of extent — i.e. when the
/// target already sits at its topmost achievable position. DESKTOP IS UNTOUCHED
/// (same constants as always): a live LAYOUT reading, never a platform name.
Future<({double top, double bottom, double maxBottom})> _settingsBand(
  Inst inst,
) async {
  if (!inst.isMobileShell) {
    return (
      top: _settingsViewTop,
      bottom: _settingsViewBottom,
      maxBottom: _settingsViewBottomMax,
    );
  }
  final cached = _settingsBandCache[inst.name];
  if (cached != null) return cached;
  final centre = await inst.keyCenter(_settingsScrollKey);
  // Not onstage yet — keep the historical constants and do NOT cache, so a later
  // call (after _openSettings) still gets a real measurement.
  if (centre == null) {
    return (
      top: _settingsMobileViewTop,
      bottom: _settingsMobileViewBottom,
      maxBottom: _settingsMobileViewBottomMax,
    );
  }
  // Both floored by the legacy constants so a measurement can only widen — never
  // narrow — what already worked on the phone shells.
  final maxBottom = 2 * centre.y - _settingsMobileSafeAreaTop - 30;
  final band = (
    top: _settingsMobileViewTop,
    bottom: centre.y > _settingsMobileViewBottom
        ? centre.y
        : _settingsMobileViewBottom,
    maxBottom: maxBottom > _settingsMobileViewBottomMax
        ? maxBottom
        : _settingsMobileViewBottomMax,
  );
  _settingsBandCache[inst.name] = band;
  print(
    '[pair] settings band ${inst.name}: viewportCentreY=${centre.y} '
    'top=${band.top} bottom=${band.bottom} maxBottom=${band.maxBottom}',
  );
  return band;
}

/// The on-screen center-y of the keyed widget: `interactiveStructured` bounds
/// (exact for switches / fields / buttons / radios), falling back to the
/// READ-ONLY `ui_key_center` primitive for NON-interactive keyed anchors (e.g.
/// the `settings_theme_segment` SizedBox). Null only when the key resolves
/// nowhere onstage.
Future<double?> _keyedCenterY(Inst inst, String key) async {
  final r = await inst.skill('interactiveStructured', const {});
  final data = r['data'];
  final elements = data is Map ? data['elements'] : null;
  if (elements is List) {
    for (final e in elements) {
      if (e is! Map || e['key'] != key) continue;
      final b = e['bounds'];
      if (b is! Map) continue;
      final y = (b['y'] as num?) ?? 0;
      final h = (b['h'] as num?) ?? 0;
      if (h <= 0) continue;
      return y + h / 2;
    }
  }
  // Non-interactive keyed anchor: resolve its center via the read-only primitive.
  final c = await inst.keyCenter(key);
  return c?.y;
}

/// Fill a keyed plain TextField via a REAL pointer focus + REAL OS input,
/// avoiding the synthetic `enterText` → `FlutterTextInputPlugin setEditingState:`
/// path that SIGSEGVs the macOS engine. NOT best-effort:
/// `_settingsBootstrapManualAddNode` gates on the production Test button READING
/// these values back. These are PLAIN TextFields, so the synthetic `enterText`
/// substitution the headless/iOS shells apply to `osa*` does reach them.
Future<void> _fillFieldViaKeystrokes(Inst inst, String key, String text) async {
  // Tap the field at its CURRENT on-screen center. Deliberately does NOT reset
  // the scroll first: a `dy:-6000` reset COLLAPSES the just-expanded manual-node
  // form, tearing down the very fields we're about to fill. The caller
  // guarantees the field is already in band.
  if (!await inst.tapKeyCenter(key)) {
    await inst.tapKeyAt(key);
  }
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await inst.osaClear();
  // PASTE, don't keystroke: under a CJK host input source keystroke letters
  // enter the IME composition and commit as hanzi. Paste is atomic + IME-immune.
  await inst.osaPaste(text);
  await Future<void>.delayed(const Duration(milliseconds: 150));
}

/// Nudge the settings ListView DOWN in SMALL steps until [key]'s REAL on-screen
/// center lands in the measured band. NOT [_settingsScrollTo]: its `dy:-6000`
/// reset COLLAPSES the just-expanded manual-node form. Downward only — for
/// widgets that appear BELOW an expander we just opened.
Future<bool> _nudgeIntoBand(Inst inst, String key, {int steps = 8}) async {
  final band = await _settingsBand(inst);
  for (var i = 0; i <= steps; i++) {
    final cy = await _keyedCenterY(inst, key);
    if (cy != null && cy >= band.top && cy <= band.bottom) return true;
    await inst.scrollAt(_settingsScrollKey, dy: 140);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

/// Bring a below/above-fold settings widget into the VISIBLE viewport by
/// wheel-scrolling the keyed settings ListView.
Future<bool> _settingsScrollTo(Inst inst, String targetKey) =>
    _scrollKeyIntoBand(inst, targetKey);

/// Scroll the settings ListView so the keyed [targetKey]'s on-screen center-y
/// lands inside the visible band ([_settingsBand], or an explicit
/// [topBand]/[bottomBand] override). Resets to the TOP first (so a target above
/// the current offset is reachable downward), then steps down checking the REAL
/// on-screen y via [_keyedCenterY] — NOT `waitKey`, which a ListView keeps true
/// for off-screen mounted children.
Future<bool> _scrollKeyIntoBand(
  Inst inst,
  String targetKey, {
  double? topBand,
  double? bottomBand,
}) async {
  await inst.foreground();
  final band = await _settingsBand(inst);
  final top = topBand ?? band.top;
  final bottom = bottomBand ?? band.bottom;
  // The stall escape hatch applies only to the DEFAULT band: an explicit
  // bottomBand is a caller's deliberate tightening (language-selector headroom)
  // and must not be widened back out underneath it.
  final maxBottom = bottomBand == null ? band.maxBottom : bottom;
  await inst.scrollAt(_settingsScrollKey, dy: -6000);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  // Steps smaller than the band height so a target can't jump from below it
  // straight to above it between checks (the "never reached" overshoot).
  double? prevCy;
  var stalledScans = 0;
  final maxSteps = inst.isMobileShell ? 45 : 30;
  final scrollDelta = inst.isMobileShell ? 110.0 : 160.0;
  for (var step = 0; step < maxSteps; step++) {
    final cy = await _keyedCenterY(inst, targetKey);
    if (cy != null && cy >= top && cy <= bottom) return true;
    // STALL = max scroll extent: a bottom-anchored element stops moving. After
    // two scans with no progress, accept it up to the extended bottom.
    if (cy != null && prevCy != null && (cy - prevCy).abs() < 4) {
      stalledScans++;
      if (stalledScans >= 2 && cy >= top && cy <= maxBottom) {
        return true;
      }
      if (stalledScans >= 4) break; // pinned at max extent — stop burning steps
    } else {
      stalledScans = 0;
    }
    prevCy = cy;
    await inst.scrollAt(_settingsScrollKey, dy: scrollDelta);
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final cy = await _keyedCenterY(inst, targetKey);
  // Final acceptance also honours the extended bottom for a bottom-anchored row.
  final ok = cy != null && cy >= top && cy <= maxBottom;
  if (!ok) {
    // cy null = UNMOUNTED key; otherwise a widget parked outside the band.
    print(
      '[pair] scrollIntoBand "$targetKey": NOT reached (cy=$cy '
      'band=$top..$bottom maxBottom=$maxBottom)',
    );
  }
  return ok;
}

/// case 1 — settings_surface_sections: open Settings, scroll the whole page, and
/// assert every top-level section HEADER renders (Account Info / Appearance /
/// Language / Auto Download Size Limit / Bootstrap Nodes).
Future<bool> _settingsSurfaceSections(Inst inst) async {
  await _openSettings(inst);
  final accountInfo = await inst.waitText('Account Info', timeoutSecs: 6);
  // Appearance + Language are in the GlobalSettingsSection (mid page).
  final appearance =
      await inst.waitText('Appearance', timeoutSecs: 2) ||
      await _scrollToText(inst, 'Appearance');
  final language =
      await inst.waitText('Language', timeoutSecs: 2) ||
      await _scrollToText(inst, 'Language');
  // Lower still — scroll the keyed download-limit field onstage, then assert
  // BOTH the field AND its SectionHeader (the key alone wouldn't prove it).
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

/// Wheel-scroll the settings list so [text] becomes visible. A ListView keeps
/// OFF-screen children MOUNTED, so `waitText` is true for a SectionHeader still
/// below the fold — best-effort, for NON-tappable headers only (a "the section
/// exists" probe); a tappable target must go through [_scrollKeyIntoBand].
Future<bool> _scrollToText(Inst inst, String text, {int maxSteps = 16}) async {
  await inst.foreground();
  await inst.scrollAt(_settingsScrollKey, dy: -6000);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (await inst.waitText(text, timeoutSecs: 1)) return true;
  for (var step = 0; step < maxSteps; step++) {
    await inst.scrollAt(_settingsScrollKey, dy: 280);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (await inst.waitText(text, timeoutSecs: 1)) return true;
  }
  return false;
}

/// Tap the theme SegmentedButton's [label] segment ("System"|"Light"|"Dark") by
/// its visible label, after bringing the keyed Appearance anchor onstage.
Future<bool> _tapThemeSegment(Inst inst, String label) async {
  // A ButtonSegment's label Text is not surfaced by `interactiveStructured`.
  // flutter_skill's `tap{text}` DOES match it, but computes the tap from the
  // widget's tree position — an OFF-screen y for a child mounted in the ListView
  // cacheExtent → silent miss. So bring the keyed wrapper `settings_theme_segment`
  // into the band first, then tap the label (a segment double-fire is harmless).
  if (!await _settingsScrollTo(inst, 'settings_theme_segment')) {
    print('[pair] theme: could not bring the theme segment into view');
  }
  for (var attempt = 0; attempt < 4; attempt++) {
    await inst.foreground();
    try {
      await inst.tapText(label, retries: 1);
      return true;
    } on DriveError {
      await _settingsScrollTo(inst, 'settings_theme_segment');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
  return false;
}

/// case 2 — settings_theme_dark (S57): tap the real "Dark" theme segment → dump
/// themeMode persists 'dark' AND the label is still rendered. Case 3 restores.
Future<bool> _settingsThemeDark(Inst inst) async {
  await _openSettings(inst);
  final before = (await inst.dumpState())['themeMode']?.toString() ?? 'system';
  final tapped = await _tapThemeSegment(inst, 'Dark');
  final persisted = tapped && await _waitStringState(inst, 'themeMode', 'dark');
  // Real-UI signal: the Appearance card survived the rebuild.
  final labelVisible = await inst.waitText('Dark', timeoutSecs: 4);
  print(
    '[pair] settings_theme_dark: before=$before tapped=$tapped '
    'persisted=$persisted labelVisible=$labelVisible',
  );
  return tapped && persisted && labelVisible;
}

/// case 3 — settings_theme_light_back (S57): revert to "Light" → dump themeMode
/// persists 'light' and the UI re-renders. Leaves a deterministic light mode.
Future<bool> _settingsThemeLightBack(Inst inst) async {
  await _openSettings(inst);
  final tapped = await _tapThemeSegment(inst, 'Light');
  final persisted =
      tapped && await _waitStringState(inst, 'themeMode', 'light');
  final labelVisible = await inst.waitText('Light', timeoutSecs: 4);
  print(
    '[pair] settings_theme_light_back: tapped=$tapped '
    'persisted=$persisted labelVisible=$labelVisible',
  );
  return tapped && persisted && labelVisible;
}

/// Park the keyed language selector row HIGH so its expanded option list (which
/// renders BELOW the row) stays on screen. Explicit band, not the measured one.
Future<bool> _anchorLanguageSelector(Inst inst) => _scrollKeyIntoBand(
  inst,
  'settings_language_selector',
  topBand: 110,
  bottomBand: 300,
);

/// case 4 — settings_locale_zh_roundtrip (S38): expand the Language selector,
/// pick 简体中文 → dump languageCode == 'zh_Hans' AND the Chinese Appearance
/// header (外观) is visible; then revert to English (the native option labels are
/// locale-invariant) BEFORE any later English-text assertion can be poisoned.
Future<bool> _settingsLocaleZhRoundtrip(Inst inst) async {
  await _openSettings(inst);
  // Anchor the collapsed selector row HIGH (an explicit band, not the measured
  // one) so the dropdown OPTIONS that render BELOW it on expand stay on screen —
  // the "option not tappable" failure was the 简体中文 row below the fold.
  await _anchorLanguageSelector(inst);
  // Expand, then choose 简体中文. SINGLE-FIRE: the selector InkWell toggles
  // `_languageExpanded`, so a double-fire would open AND re-close it.
  var expanded = false;
  for (var attempt = 0; attempt < 4 && !expanded; attempt++) {
    if (!await inst.tapKeyAt('settings_language_selector')) {
      await _anchorLanguageSelector(inst);
      if (!await inst.tapKeyAt('settings_language_selector')) break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expanded = await inst.waitText('简体中文', timeoutSecs: 2);
  }
  if (!expanded) {
    print('[pair] settings_locale_zh: could not expand language selector');
    return false;
  }
  // The option InkWell's label Text isn't surfaced by interactiveStructured, so
  // drive the production option key via tapKeyAt (resolveKeyCenter + tapAt).
  var zhTapped = await inst.tapKeyAt('settings_language_option_zh_Hans');
  if (!zhTapped) {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    zhTapped = await inst.tapKeyAt('settings_language_option_zh_Hans');
  }
  if (!zhTapped) {
    print('[pair] settings_locale_zh: 简体中文 option not tappable');
    return false;
  }
  // Prefs persists the locale as `${languageCode}_${scriptCode}` (underscore),
  // so the dump reports 'zh_Hans' — NOT the BCP-47 'zh-Hans' hyphen form.
  final zhPersisted = await _waitStringState(inst, 'languageCode', 'zh_Hans');
  // Chinese label assertion: the Appearance header now reads "外观".
  await inst.foreground();
  final zhLabelVisible =
      await inst.waitText('外观', timeoutSecs: 6) ||
      await _scrollToText(inst, '外观');
  print(
    '[pair] settings_locale_zh: zhPersisted=$zhPersisted '
    'zhLabelVisible=$zhLabelVisible',
  );
  // Revert to English. The option labels are NATIVE names (literal 'English' /
  // '简体中文'), unchanged by locale, so tapping "English" works while in Chinese.
  await _anchorLanguageSelector(inst);
  var reverted = false;
  for (var attempt = 0; attempt < 4 && !reverted; attempt++) {
    // Expand (single-fire) the now-Chinese-labelled selector, then pick English.
    if (!await inst.tapKeyAt('settings_language_selector')) {
      await _anchorLanguageSelector(inst);
      if (!await inst.tapKeyAt('settings_language_selector')) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        continue;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // Only proceed if the option list actually opened (English option shows),
    // then tap the keyed English option (settings_language_option_en).
    if (await inst.waitText('English', timeoutSecs: 2) &&
        await inst.tapKeyAt('settings_language_option_en')) {
      reverted = await _waitStringState(inst, 'languageCode', 'en');
    }
    if (!reverted) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
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

/// case 5 — settings_download_limit_edit (S98): bring the keyed field onstage,
/// clear it, type a value, tap Save → dump autoDownloadSizeLimit reflects it.
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
  // Focus via flutter_skill's tap{key}, which ESTABLISHES the text input
  // connection (a raw tapAt does NOT, and enterText without one SIGSEGVs macOS's
  // FlutterTextInputPlugin). RETRY the whole cycle: under 2-process foreground
  // contention the enterText or the save tap intermittently doesn't land.
  var saved = false;
  for (var attempt = 0; attempt < 3 && !saved; attempt++) {
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
      continue;
    }
    // The Save button is a FilledButton (no text input) — tapKeyCenter is safe.
    await inst.tapKeyCenter('settings_download_limit_save_button');
    saved = await _waitFieldWhere(
      inst,
      'autoDownloadSizeLimit',
      (v) => _stateInt(v) == target,
      timeoutSecs: 10,
    );
  }
  // Restore the prior cap and ENFORCE it (an un-restored value poisons reruns).
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
    await inst.tapKeyCenter('settings_download_limit_save_button');
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

/// Drive the real bootstrap-mode control to [mode] and wait for the dump
/// bootstrapNodeMode to reflect it, bringing the keyed control onstage first.
///
/// The control differs by shell: `BootstrapSettingsSection` builds three
/// `RadioListTile`s only `if (PlatformUtils.isDesktop)`, and a two-segment
/// `SegmentedButton` (manual | auto — no LAN) everywhere else, whose keys sit on
/// a `KeyedSubtree` around each segment LABEL. A live probe confirms a
/// coordinate tap at that label's resolved centre flips the mode in ~15ms — as
/// long as the centre is genuinely on screen, which [_settingsBand]'s
/// viewport-centre bottom now guarantees.
Future<bool> _setBootstrapMode(Inst inst, String key, String mode) async {
  var everTapped = false;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (!await _settingsScrollTo(inst, key)) {
      print(
        '[pair] bootstrap mode: tile "$key" never reached (attempt $attempt)',
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      continue;
    }
    // tapKeyCenter taps the live on-screen centre; tapKeyAt (resolveKeyCenter)
    // is the fallback when interactiveStructured doesn't surface the tile.
    if (await inst.tapKeyCenter(key) || await inst.tapKeyAt(key)) {
      everTapped = true;
    }
    if (await _waitStringState(
      inst,
      'bootstrapNodeMode',
      mode,
      timeoutSecs: 6,
    )) {
      return true;
    }
  }
  // Grace window for a late tap — but ONLY when the real control was driven.
  // Without this guard the helper answered TRUE whenever the mode ALREADY
  // equalled [mode]: on iPad the tiles were never reached, yet auto0/backAuto
  // reported true because the default IS 'auto' — a false green.
  if (!everTapped) return false;
  return _waitStringState(inst, 'bootstrapNodeMode', mode, timeoutSecs: 4);
}

/// case 6 — settings_bootstrap_mode_cycle (S99/S85): cycle the bootstrap mode
/// control auto→manual→(lan)→auto, asserting the dump bootstrapNodeMode after
/// each real tap. Ends on 'auto' (the default, leaving a known state).
///
/// LAN is a DESKTOP-ONLY product feature: the LAN radio lives only in the
/// `PlatformUtils.isDesktop` branch of `_buildModeRow`, and
/// `_setBootstrapNodeMode` hard-returns on `'lan'` off desktop. So that leg is
/// SKIPPED (reason printed) when the shell ships no LAN control — gated on the
/// mode row being MOUNTED (`toAuto0` proves it) so an unreachable widget can't
/// masquerade as an absent one, and still FAILING on desktop.
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
  final lanShipped =
      !toAuto0 ||
      !inst.isMobileShell ||
      await inst.waitKey('settings_bootstrap_mode_lan', timeoutSecs: 3);
  final toLan = lanShipped
      ? await _setBootstrapMode(inst, 'settings_bootstrap_mode_lan', 'lan')
      : true;
  final backAuto = await _setBootstrapMode(
    inst,
    'settings_bootstrap_mode_auto',
    'auto',
  );
  print(
    '[pair] settings_bootstrap_mode_cycle: auto0=$toAuto0 manual=$toManual '
    'lan=${lanShipped ? toLan : 'SKIP(no LAN control on this shell)'} '
    'backAuto=$backAuto',
  );
  return toAuto0 && toManual && toLan && backAuto;
}

/// case 7 — settings_bootstrap_manual_add_node (S89): switch to manual mode,
/// expand the manual node form, fill host/port/pubkey via real input → the
/// production Test button READS BACK the typed values.
///
/// NOTE on scope: "Set as Current Node" only appears AFTER a live
/// `addBootstrapNode` test SUCCEEDS (needs real DHT reachability), so the
/// bounded assertion is that the real form mounts and accepts input on a
/// persisted bootstrapNodeMode→manual. Leaves the form EXPANDED for case 8.
///
/// VALUE READBACK (2026-08-14): key PRESENCE alone would pass even when a fill
/// landed NOTHING, and no API reads a TextField's value back — so the readback
/// rides the PRODUCTION control. `_testManualNode` reads
/// `_manualHostController.text` & co. and SnackBars `invalidNodeInfo` unless
/// host+port+valid-64-hex-pubkey are all present. Hence the DIFFERENTIAL: Test
/// with the pubkey CLEARED must say "invalid", then Test with every field filled
/// must reach a real verdict — only reachable if the typed bytes really are in
/// the controllers. The text readback below is a breadcrumb, never the gate.
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
  // Expand the form. The button TOGGLES `_manualInputExpanded`, so a
  // double-firing `tapKey` would open AND close it — bring it onstage then
  // SINGLE-FIRE via tapKeyCenter.
  if (!await _settingsScrollTo(inst, 'manual_node_input_button')) {
    print('[pair] bootstrap_manual_add: expand button never reached');
    return false;
  }
  if (!await inst.tapKeyCenter('manual_node_input_button')) {
    print('[pair] bootstrap_manual_add: expand button not tappable');
    return false;
  }
  final hostShown = await inst.waitKey(
    'manual_node_host_field',
    timeoutSecs: 6,
  );
  if (!hostShown) {
    print('[pair] bootstrap_manual_add: host field did not appear');
    return false;
  }
  // The expanded form renders BELOW the (bottom-anchored) expand toggle, so the
  // host field can be just under the fold. Nudge DOWN a little (a small delta,
  // NOT a `_settingsScrollTo` reset — the top-reset collapses the form), then
  // settle it into the MEASURED band instead of trusting the fixed 300px guess
  // (no-op when already in band, so desktop is unchanged).
  await inst.scrollAt(_settingsScrollKey, dy: 300);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await _nudgeIntoBand(inst, 'manual_node_host_field');
  // Fill via REAL focus + input (see _fillFieldViaKeystrokes). All three fields
  // are filled: the port is pinned rather than trusted to its 33445 default, and
  // the pubkey is CLEARED first so the invalid half of the differential is
  // deterministic even when a saved current node pre-populated the controllers.
  const host = 'tox.example.org';
  const pubkey =
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  const invalidMsg =
      'Please enter valid node information (host, port, and public key)';
  await _fillFieldViaKeystrokes(inst, 'manual_node_host_field', host);
  final portShown = await inst.waitKey(
    'manual_node_port_field',
    timeoutSecs: 4,
  );
  if (portShown) {
    await _nudgeIntoBand(inst, 'manual_node_port_field');
    await _fillFieldViaKeystrokes(inst, 'manual_node_port_field', '33445');
  }
  final pubkeyShown = await inst.waitKey(
    'manual_node_pubkey_field',
    timeoutSecs: 4,
  );
  if (pubkeyShown) {
    await _nudgeIntoBand(inst, 'manual_node_pubkey_field');
    await _fillFieldViaKeystrokes(inst, 'manual_node_pubkey_field', '');
  }
  final testShown = await inst.waitKey(
    'manual_node_test_button',
    timeoutSecs: 4,
  );
  // Breadcrumb only: some flutter_skill builds report a TextField's LABEL here
  // rather than its value, so this can never be the gate.
  final hostReadback = await _keyedText(inst, 'manual_node_host_field');

  // Differential half 1 — pubkey empty ⇒ the production validator must refuse.
  await _nudgeIntoBand(inst, 'manual_node_test_button');
  if (!await inst.tapKeyCenter('manual_node_test_button')) {
    await inst.tryTapKey('manual_node_test_button');
  }
  final invalidShown = await inst.waitText(invalidMsg, timeoutSecs: 8);

  // Differential half 2 — a valid 64-hex pubkey ⇒ the SAME control must get past
  // validation to a real verdict, unreachable unless host+port+pubkey are all
  // sitting in the real controllers.
  await inst.waitTextGone(invalidMsg, timeoutSecs: 12);
  await _nudgeIntoBand(inst, 'manual_node_pubkey_field');
  await _fillFieldViaKeystrokes(inst, 'manual_node_pubkey_field', pubkey);
  await _nudgeIntoBand(inst, 'manual_node_test_button');
  if (!await inst.tapKeyCenter('manual_node_test_button')) {
    await inst.tryTapKey('manual_node_test_button');
  }
  // The validator answers synchronously (~1 frame), the probe verdict does not:
  // look for a repeat refusal FIRST, then wait out the verdict (which survives
  // the SnackBar — the _StatusPill keeps rendering it in the form).
  final stillInvalid = await inst.waitText(invalidMsg, timeoutSecs: 3);
  var verdictShown = await inst.waitText('Node test failed', timeoutSecs: 20);
  for (final t in const [
    'Node test successful',
    'Test unavailable before login',
  ]) {
    if (verdictShown) break;
    verdictShown = await inst.waitText(t, timeoutSecs: 2);
  }
  print(
    '[pair] settings_bootstrap_manual_add_node: manualMode=$manualMode '
    'host=$hostShown port=$portShown pubkey=$pubkeyShown test=$testShown '
    'invalidShown=$invalidShown verdictShown=$verdictShown '
    'stillInvalid=$stillInvalid (expect false) '
    'hostReadback=${hostReadback ?? 'n/a'}',
  );
  return manualMode &&
      hostShown &&
      portShown &&
      pubkeyShown &&
      testShown &&
      invalidShown &&
      verdictShown &&
      !stillInvalid;
}

/// case 8 — settings_bootstrap_manual_remove_node (S89): collapse the manual
/// node form via the production toggle → the form ROW (host/port/pubkey fields)
/// is GONE.
///
/// NOTE on scope: BootstrapSettingsSection has NO per-node remove affordance
/// (manual mode only overwrites the current node). The closest real "remove the
/// row" surface is the manual input EXPAND toggle — tapping it again collapses
/// the form so its fields leave the tree. We assert that GONE transition (the
/// inverse of case 7), then restore mode→auto.
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
  // Restore mode→auto and ENFORCE it (a failed restore would leave the pair in
  // manual mode → state-poisoning false pass).
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

/// Real pointer tap on the keyed Switch until the dump [field] reaches [want].
/// One tap is not enough: foreground contention drops taps, and a Switch
/// resolved at a not-yet-settled scroll position swallows the hit (the observed
/// iPad `notificationSound flipped=false`).
Future<bool> _driveSwitchTo(
  Inst inst,
  String key,
  String field,
  bool want,
) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    if (!await _settingsScrollTo(inst, key)) {
      print('[pair] switch "$key": never reached (attempt $attempt)');
      continue;
    }
    if (!await inst.tapKeyCenter(key)) {
      print('[pair] switch "$key": center not tappable (attempt $attempt)');
      continue;
    }
    if (await _waitBoolState(inst, field, want, timeoutSecs: 6)) return true;
  }
  return false;
}

/// cases 9 + 10 — settings_autologin_toggle_hard (S96) and
/// settings_notifsound_toggle_hard (S97): scroll the real Switch onstage, tap
/// its CENTER (flutter_skill's synthetic tap doesn't reliably toggle a Material
/// Switch) → the dump field flips; tap back → restores.
Future<bool> _settingsSwitchToggleHard(
  Inst inst,
  String caseId,
  String key,
  String field,
) async {
  await _openSettings(inst);
  final before = (await inst.dumpState())[field] == true;
  final flipped = await _driveSwitchTo(inst, key, field, !before);
  final restored = flipped
      ? await _driveSwitchTo(inst, key, field, before)
      : true;
  print('[pair] $caseId: before=$before flipped=$flipped restored=$restored');
  return flipped && restored;
}

Future<bool> _settingsAutologinToggleHard(Inst inst) =>
    _settingsSwitchToggleHard(
      inst,
      'settings_autologin_toggle_hard',
      'settings_auto_login_switch',
      'autoLogin',
    );

Future<bool> _settingsNotifSoundToggleHard(Inst inst) =>
    _settingsSwitchToggleHard(
      inst,
      'settings_notifsound_toggle_hard',
      'settings_notification_sound_switch',
      'notificationSound',
    );

/// case 11 — settings_password_mismatch_error (S40): open the set-password
/// dialog, type MISMATCHED new/confirm values, tap Save → the production handler
/// snackbars "Passwords do not match" and the dialog STAYS OPEN (early return,
/// no Navigator.pop). Asserts both. ESC dismisses without setting a password, so
/// no later case inherits a password-protected account.
Future<bool> _settingsPasswordMismatchError(Inst inst) async {
  await _openSettings(inst);
  // Below-fold opener: tapKey still opens the dialog via its direct
  // _tryInvokeCallback even off-screen, so a failed scroll is not fatal.
  if (!await _settingsScrollTo(inst, 'settings_set_password_button')) {
    print('[pair] password_mismatch: set-password button below fold (ok)');
  }
  await inst.tapKey('settings_set_password_button');
  if (!await inst.waitKey('settings_set_password_new_field', timeoutSecs: 8)) {
    print('[pair] password_mismatch: dialog did not open');
    return false;
  }
  await inst.focusType('settings_set_password_new_field', 'RuiPwAAAA1');
  await inst.focusType('settings_set_password_confirm_field', 'RuiPwBBBB2');
  // Save pops ONLY when the values match; on a mismatch it snackbars and returns
  // without popping, so re-tapping is safe. Foreground + re-tap until the
  // snackbar shows (a center-tap can silently miss on the headless Windows VM).
  // The text is LOCALIZED, so accept any shipped variant.
  const variants = [
    'Passwords do not match', // en
    '密码不匹配', // zh
    '密碼不匹配', // zh_Hant
  ];
  var snackbar = false;
  for (var attempt = 0; attempt < 4 && !snackbar; attempt++) {
    await inst.foreground();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!await inst.tapKeyCenter('settings_set_password_save_button')) {
      print('[pair] password_mismatch: save button not tappable');
      return false;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!snackbar && DateTime.now().isBefore(deadline)) {
      for (final v in variants) {
        if (await inst.waitText(v, timeoutSecs: 1)) {
          snackbar = true;
          break;
        }
      }
    }
  }
  // The dialog must STILL be open (its keyed field present) — proves the
  // mismatch short-circuited before the pop.
  final dialogStays = await inst.waitKey(
    'settings_set_password_new_field',
    timeoutSecs: 4,
  );
  // Dismiss WITHOUT setting a password (ESC) so the account stays password-free.
  // ESC can be eaten by focus state, so fall back to the keyed Cancel button and
  // ENFORCE that the dialog is gone — a stray dialog would poison case 12.
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
/// CANCEL → the dialog closes and sessionReady stays true (no teardown). Runs
/// LAST because it opens the dangerous logout dialog; only ever taps Cancel.
Future<bool> _settingsLogoutCancel(Inst inst) async {
  await _openSettings(inst);
  final wasReady = (await inst.dumpState())['sessionReady'] == true;
  // Below-fold opener (fires once via direct callback).
  if (!await _settingsScrollTo(inst, 'settings_logout_button')) {
    print('[pair] logout_cancel: logout button below fold (ok)');
  }
  // tapKeyCenter (live bounds + exact-centre tapAt), with a tapKey fallback
  // whose direct callback fires even slightly off-screen.
  if (!await inst.tapKeyCenter('settings_logout_button')) {
    await inst.tapKey('settings_logout_button');
  }
  if (!await inst.waitKey('settings_logout_confirm_button', timeoutSecs: 8)) {
    print('[pair] logout_cancel: confirm dialog did not open');
    return false;
  }
  // SINGLE-FIRE the keyed Cancel: a dialog pop button must not double-fire (the
  // first pop closes the dialog, a second fired mid-dismiss pops the page
  // underneath). Fall back to the "Cancel" label only if the key can't resolve.
  // RE-TAP while the dialog is still up: a centre tap intermittently doesn't
  // land under foreground contention (observed `dialogClosed=false` on one of
  // two iPad runs), and each round re-checks that the dialog is still there.
  var dialogClosed = false;
  for (var attempt = 0; attempt < 3 && !dialogClosed; attempt++) {
    await inst.foreground();
    if (!await inst.tapKeyCenter('settings_logout_cancel_button')) {
      if (!await _tryTapText(inst, 'Cancel')) {
        print('[pair] logout_cancel: Cancel button not tappable');
        return false;
      }
    }
    // Dialog gone (confirm button no longer in the tree) AND session intact.
    dialogClosed = await inst.waitKeyGone(
      'settings_logout_confirm_button',
      timeoutSecs: 6,
    );
  }
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
/// English and bootstrap mode back to auto IF a prior case left them mutated.
/// The sweep keeps running after a failed case, so a stuck-in-zh locale would
/// false-FAIL later English-text cases. Never throws.
Future<void> _normalizeBetweenCases(Inst inst) async {
  try {
    final st = await inst.dumpState();
    if (st['languageCode']?.toString() != 'en') {
      print(
        '[sweep] normalize: locale is ${st['languageCode']} -> reverting en',
      );
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
/// (ESC-dismiss); logout_cancel LAST (Cancel only). Prints `[sweep] <case>:
/// PASS|FAIL` per case + final counts; exits non-zero if any HARD case fails.
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
    // Cross-case poison guard: re-normalize locale→en + bootstrap→auto so a
    // later English-text case isn't false-failed by leftover state.
    await _normalizeBetweenCases(inst);
  }
  print(
    '[sweep] sweep_settings2 RESULTS: $passed PASS / $failed FAIL '
    '(${cases.length} total)',
  );
  await inst.shot('/tmp/ui_settings_sweep2_${inst.name}.png');
  return failed == 0 ? 0 : 1;
}
