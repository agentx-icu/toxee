// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Narrow-shell (iPhone / Android) settings navigation for "Settings sweep 2".
//
// Split out of drive_real_ui_pair_settings2.dart to keep that file under its
// tool/.complexity_baseline.txt pin. This half owns ONLY the phone-shaped
// concern: the settings root is an INDEX of section tiles that push each
// section onto its own route, so a target control has to be navigated to
// before it can be scrolled to. Every helper here no-ops on the wide shell
// (desktop + iPad), which renders the same sections inline.

const _settingsMobileSectionScrollKey = 'settings_mobile_section_scroll_view';
const _settingsMobileBackKey = 'settings_mobile_section_back_button';

// --- NARROW-SHELL (iPhone / Android) settings navigation ---------------------
//
// ROOT CAUSE (Android, 2026-08-15 — first Android run of this sweep; the same
// bug was latent on iPhone): `ResponsiveLayout.isMobile` splits the settings
// page in TWO layouts. The WIDE shell (desktop + iPad) renders every section
// INLINE in the keyed root ListView, which is what this driver assumed. The
// NARROW shell renders `_buildMobileSettingsIndex` — a root list of SECTION
// TILES — and pushes each section onto its OWN route
// (`_pushMobileSettingsSection`). So `settings_theme_segment`,
// `settings_download_limit_field`, the bootstrap rows etc. are simply NOT in
// the root list: `_keyedCenterY` returned null and `_scrollKeyIntoBand` burned
// its whole step budget reporting "never reached" for controls that a user
// reaches with one extra tap. One cause, all 12 Android failures.
//
// Fix: before scrolling for a target, ENTER the sub-page that owns it (and
// leave the previous one). The controls are real and the assertions are
// unchanged — this only adds the navigation tap the narrow shell requires.
// Desktop/iPad are untouched: every helper below no-ops on `!isMobileShell`.

/// The section tile that owns [key] on the narrow shell, or null when [key]
/// lives on the settings ROOT index (or needs no sub-page).
String? _mobileSettingsSectionFor(String key) {
  // Bootstrap sub-page: the mode radios plus the whole manual-node form.
  if (key.startsWith('settings_bootstrap_') || key.startsWith('manual_node_')) {
    return 'settings_mobile_bootstrap_section';
  }
  switch (key) {
    // GlobalSettingsView.appearance — theme + language ONLY.
    case 'settings_theme_segment':
    case 'settings_language_selector':
    case 'settings_language_option_zh_Hans':
    case 'settings_language_option_en':
      return 'settings_mobile_appearance_section';
    // GlobalSettingsView.general — notification sound + download limit.
    case 'settings_notification_sound_switch':
    case 'settings_download_limit_field':
    case 'settings_download_limit_save_button':
      return 'settings_mobile_general_section';
    // _buildMobileAccountInfoCard.
    case 'settings_copy_tox_id_button':
    case 'settings_auto_login_switch':
      return 'settings_mobile_account_info_section';
    // _buildMobileAccountManagementCard.
    case 'settings_export_account_button':
    case 'settings_set_password_button':
    case 'settings_logout_button':
      return 'settings_mobile_account_management_section';
  }
  return null;
}

/// Which mobile settings sub-page each instance is currently parked on (null =
/// the root index). Reset by [_settingsResetMobileSectionState] on every
/// `_openSettings`, which always lands back on the root.
final _settingsMobileSection = <String, String>{};

void _settingsResetMobileSectionState(Inst inst) {
  _settingsMobileSection.remove(inst.name);
  // The sub-page viewport differs from the root one, so a band measured in a
  // sub-page must never be reused after leaving it.
  _settingsBandCache.remove(inst.name);
}

/// The scrollable to drive for this instance right now: the pushed sub-page's
/// ListView when parked in a section, else the root index list. The two carry
/// DIFFERENT keys on purpose (the root stays mounted under the pushed route).
String _settingsActiveScrollKey(Inst inst) =>
    _settingsMobileSection[inst.name] == null
    ? _settingsScrollKey
    : _settingsMobileSectionScrollKey;

/// Per-instance cache of the shell width class (fixed for a run): one
/// `l3_dump_state` round-trip instead of one per navigation step.
final _settingsWideCache = <String, bool>{};

Future<bool> _settingsIsWideCached(Inst inst) async {
  final cached = _settingsWideCache[inst.name];
  if (cached != null) return cached;
  final wide = await _settingsIsWide(inst);
  _settingsWideCache[inst.name] = wide;
  return wide;
}

/// Pop back to the settings root index from a pushed sub-page.
Future<void> _settingsLeaveMobileSection(Inst inst) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    if (!await inst.waitKey(_settingsMobileBackKey, timeoutSecs: 2)) break;
    if (!await inst.tapKeyCenter(_settingsMobileBackKey)) {
      await inst.tapKeyAt(_settingsMobileBackKey);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  _settingsResetMobileSectionState(inst);
}

/// Ensure the narrow shell is parked on the sub-page that owns [targetKey].
/// No-op (true) on the wide shell, and for root-level targets. Returns false
/// only when the owning section tile could not be opened.
Future<bool> _settingsEnterMobileSection(Inst inst, String targetKey) async {
  if (!inst.isMobileShell) return true;
  // iPad reports `isMobileShell` (platform == ios) yet renders the WIDE settings
  // layout: every section is INLINE on one page and there is no index of
  // drill-in tiles to enter. Without this the helper hunted for
  // `settings_mobile_*_section` keys that do not exist there and reported
  // "could not open section" for widgets that were already on screen.
  if (await _settingsIsWideCached(inst)) return true;
  final want = _mobileSettingsSectionFor(targetKey);
  final current = _settingsMobileSection[inst.name];
  if (want == null) {
    // Root-level target: make sure we are not still inside a sub-page.
    if (current != null) await _settingsLeaveMobileSection(inst);
    return true;
  }
  if (current == want) return true;
  // FLAT settings surface — a NARROW shell with no drill-in index at all.
  // `LoginSettingsPage` (lib/ui/login_settings_page.dart) renders
  // GlobalSettingsSection + BootstrapSettingsSection INLINE inside one
  // SingleChildScrollView; it has no `settings_mobile_*_section` tiles, because
  // there is nothing to drill into. Without this branch the helper hunted for a
  // tile that does not exist and returned "could not open section" for a control
  // that was already in the tree — the live Android/iPhone failure of
  // `settings_prelogin_bootstrap_node_test` (the case's own `waitKey(
  // 'settings_bootstrap_mode_manual')` had ALREADY succeeded one step earlier).
  //
  // Discriminated on the SECTION TILE's absence, not on the target's presence:
  // the tile is missing only on a flat page, whereas a target can resolve
  // off-stage on the logged-in index too. So this cannot swallow a genuine
  // navigation failure on the drill-in layout — there the tile resolves and the
  // normal path below runs unchanged.
  if (!await inst.waitKey(want, timeoutSecs: 2) &&
      await inst.waitKey(targetKey, timeoutSecs: 2)) {
    if (current != null) _settingsResetMobileSectionState(inst);
    return true;
  }
  if (current != null) await _settingsLeaveMobileSection(inst);
  for (var attempt = 0; attempt < 3; attempt++) {
    // The tile can itself be below the fold on the root index — bring it in
    // via the ROOT list before tapping (guarded against recursion: a section
    // tile never maps to a section itself).
    await _scrollKeyIntoBand(inst, want);
    if (await inst.tapKeyCenter(want) || await inst.tapKeyAt(want)) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (await inst.waitKey(_settingsMobileBackKey, timeoutSecs: 5)) {
        _settingsMobileSection[inst.name] = want;
        _settingsBandCache.remove(inst.name);
        return true;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  print(
    '[pair] settings mobile: could not open section "$want" for "$targetKey"',
  );
  return false;
}

/// Every case's entry point: land on the settings ROOT with the narrow-shell
/// sub-page bookkeeping cleared. A previous case can leave the app parked on a
/// pushed section route, which sits OVER the shell and would swallow the
/// settings-tab tap, so pop back out before the normal open.
Future<void> _openSettingsRoot(Inst inst) async {
  if (inst.isMobileShell && _settingsMobileSection[inst.name] != null) {
    await _settingsLeaveMobileSection(inst);
  }
  await _openSettings(inst);
  _settingsResetMobileSectionState(inst);
}

/// Narrow-shell twin of [_settingsSurfaceSections]. The root is an INDEX of
/// section tiles, so "every section renders" is asserted as: the four index
/// tiles are present, AND the two sections whose headers only exist one level
/// down really do render when opened. Deliberately NOT weaker than the wide
/// shell — it additionally proves the owning CONTROL mounts (`Language` ->
/// `settings_language_selector`, `Auto Download Size Limit` ->
/// `settings_download_limit_field`), which the header-only desktop check does
/// not.
Future<bool> _settingsSurfaceSectionsMobile(Inst inst) async {
  final accountInfo = await inst.waitText('Account Info', timeoutSecs: 6);
  final appearance = await inst.waitText('Appearance', timeoutSecs: 3);
  final general = await inst.waitText('General', timeoutSecs: 3);
  final bootstrap = await inst.waitText('Bootstrap Nodes', timeoutSecs: 3);

  // Appearance sub-page owns the Language selector.
  final languageReached = await _settingsScrollTo(
    inst,
    'settings_language_selector',
  );
  final language =
      languageReached &&
      (await inst.waitText('Language', timeoutSecs: 3) ||
          await _scrollToText(inst, 'Language'));

  // General sub-page owns the auto-download size limit.
  final downloadField = await _settingsScrollTo(
    inst,
    'settings_download_limit_field',
  );
  final downloadHeader =
      downloadField &&
      (await inst.waitText('Auto Download Size Limit', timeoutSecs: 3) ||
          await _scrollToText(inst, 'Auto Download Size Limit'));

  // Leave the last sub-page so the next case starts from the root index.
  await _settingsLeaveMobileSection(inst);
  print(
    '[pair] settings_surface_sections(mobile): accountInfo=$accountInfo '
    'appearance=$appearance general=$general bootstrap=$bootstrap '
    'language=$language downloadField=$downloadField '
    'downloadHeader=$downloadHeader',
  );
  return accountInfo &&
      appearance &&
      general &&
      bootstrap &&
      language &&
      downloadField &&
      downloadHeader;
}

// ---------------------------------------------------------------------------
// Measured viewport band (narrow-shell geometry).
// ---------------------------------------------------------------------------

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
  // Measure the scrollable we are ACTUALLY on: inside a pushed mobile section
  // that is the sub-page ListView, whose viewport sits below an AppBar and so
  // has a different centre than the root index.
  final centre = await inst.keyCenter(_settingsActiveScrollKey(inst));
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
