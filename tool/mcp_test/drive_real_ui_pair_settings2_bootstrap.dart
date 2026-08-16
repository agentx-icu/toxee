// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Split out of drive_real_ui_pair_settings2.dart (which is at its
// `tool/.complexity_baseline.txt` pin) along the same seam
// drive_real_ui_pair_settings2_prelogin.dart already uses: the sweep_settings2
// cases that drive the BOOTSTRAP-NODE surface (BootstrapSettingsSection:
// mode selector, manual-node form, the real Test button) rather than the
// generic settings controls. `_prelogin` holds the logged-OUT half of the same
// surface; this file holds the logged-IN half.


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
  await _openSettingsRoot(inst);
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
  await _openSettingsRoot(inst);
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
  // On the narrow shell this runs INSIDE the pushed Bootstrap sub-page, so it
  // must nudge that list, not the (offstage) root index.
  await inst.scrollAt(_settingsActiveScrollKey(inst), dy: 300);
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
  // The tap is a HARD gate: `_testManualNode` shows a SnackBar on EVERY path, so
  // "no SnackBar" means the press never reached the button. Reporting the band
  // state + resolved centre turns that into a diagnosis instead of a bare false.
  // Close the soft keyboard FIRST: the three fills above left a field focused,
  // and on a phone the IME then covers the bottom of the screen — including the
  // Test button, which still reports its normal (unobscured) centre. Tapping it
  // then hits the keyboard and the case fails with "no SnackBar".
  await inst.hideKeyboard();
  final testInBand1 = await _nudgeIntoBand(inst, 'manual_node_test_button');
  var tapped1 = await inst.tapKeyCenter('manual_node_test_button');
  if (!tapped1) tapped1 = await inst.tryTapKey('manual_node_test_button');
  print(
    '[pair] bootstrap_manual_add half1: inBand=$testInBand1 '
    'cy=${await _keyedCenterY(inst, 'manual_node_test_button')} '
    'tapped=$tapped1',
  );
  final invalidShown = await inst.waitText(invalidMsg, timeoutSecs: 8);

  // Differential half 2 — a valid 64-hex pubkey ⇒ the SAME control must get past
  // validation to a real verdict, unreachable unless host+port+pubkey are all
  // sitting in the real controllers.
  await inst.waitTextGone(invalidMsg, timeoutSecs: 12);
  await _nudgeIntoBand(inst, 'manual_node_pubkey_field');
  await _fillFieldViaKeystrokes(inst, 'manual_node_pubkey_field', pubkey);
  // Same IME dismissal as half 1 — the pubkey fill just re-opened the keyboard.
  await inst.hideKeyboard();
  final testInBand2 = await _nudgeIntoBand(inst, 'manual_node_test_button');
  var tapped2 = await inst.tapKeyCenter('manual_node_test_button');
  if (!tapped2) tapped2 = await inst.tryTapKey('manual_node_test_button');
  print(
    '[pair] bootstrap_manual_add half2: inBand=$testInBand2 tapped=$tapped2',
  );
  // The validator answers synchronously (~1 frame), the probe verdict does not:
  // look for a repeat refusal FIRST, then wait out the verdict (which survives
  // the SnackBar — the _StatusPill keeps rendering it in the form).
  final stillInvalid = await inst.waitText(invalidMsg, timeoutSecs: 3);
  // ACCEPTABLE VERDICTS (tightened 2026-08-14): a REAL probe result only — the
  // former "Test unavailable before login" escape made this case immune to the
  // defect it should catch. PRODUCTION en labels; flutter_skill matches EXACTLY.
  //
  // UDP-LESS PAIRS (added 2026-08-16, live Android). A DHT getnodes request is
  // UDP-only, and `BootstrapNodeProbe._runIsolatedProbe` returns
  // `udpUnavailable` — never a node verdict — when its instance bound no UDP
  // socket (`session.udpPort == 0`). On the Android/Windows/Linux pairs the
  // launcher sets `debug.toxee.force_tcp_only=1`, which `ToxManager::initialize`
  // reads at EVERY `tox_new` (`read_harness_knob`), including the probe's own
  // `create_test_instance_ex` instance — so "Node unreachable"/"Node reachable"
  // are structurally unreachable there and this case was a guaranteed FAIL.
  //
  // This is NOT an escape hatch: the environment is DETECTED from the live
  // `l3_dht_info` udpPort (the same signal `_settingsPreloginBootstrapNodeTest`
  // already uses for the same constraint), and the UDP-less branch asserts a
  // STRICTER product contract, not a weaker one — the probe must report the UDP
  // constraint AND must NOT libel the node as unreachable. `BootstrapVerdictUi`
  // documents that exact rule (`resultFor`: udpUnavailable -> 'udp', and
  // `isNegative`: only 'failed' is a real negative), so a regression that
  // rendered a UDP-less probe as "Node unreachable" still reds this case.
  // Whichever direction was exercised is printed, so the evidence is unambiguous.
  const udpMsg = 'Node test needs UDP; this device is running TCP-only';
  var probeUdpPort = 0;
  try {
    probeUdpPort = ((await inst.l3('l3_dht_info'))['udpPort'] as num?)
            ?.toInt() ??
        0;
  } on DriveError catch (e) {
    print('[pair] bootstrap_manual_add: l3_dht_info warn: ${e.message}');
  }
  final bool verdictShown;
  final bool libelled;
  if (probeUdpPort > 0) {
    var v = await inst.waitText('Node unreachable', timeoutSecs: 25);
    if (!v) v = await inst.waitText('Node reachable', timeoutSecs: 2);
    verdictShown = v;
    libelled = false;
  } else {
    verdictShown = await inst.waitText(udpMsg, timeoutSecs: 25);
    // The negative leg of the UDP-less differential: a good node must not be
    // blamed for a local constraint.
    libelled = await inst.waitText('Node unreachable', timeoutSecs: 2);
  }
  print(
    '[pair] settings_bootstrap_manual_add_node: manualMode=$manualMode '
    'host=$hostShown port=$portShown pubkey=$pubkeyShown test=$testShown '
    'invalidShown=$invalidShown verdictShown=$verdictShown '
    'stillInvalid=$stillInvalid (expect false) '
    'probeUdpPort=$probeUdpPort '
    'direction=${probeUdpPort > 0 ? 'real-node-verdict' : 'udp-unavailable'} '
    'libelledAsUnreachable=$libelled (expect false) '
    'hostReadback=${hostReadback ?? 'n/a'}',
  );
  return manualMode &&
      hostShown &&
      portShown &&
      pubkeyShown &&
      testShown &&
      // Both presses must actually have been dispatched (a resolve failure here
      // used to be swallowed by the best-effort fallback).
      tapped1 &&
      tapped2 &&
      invalidShown &&
      verdictShown &&
      !libelled &&
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
  await _openSettingsRoot(inst);
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
