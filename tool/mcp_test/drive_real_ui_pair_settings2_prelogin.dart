// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Split out of drive_real_ui_pair_settings2.dart (which is at its complexity
// pin): the ONE sweep_settings2 case that drives the PRE-LOGIN settings surface
// (LoginSettingsPage -> BootstrapSettingsSection with `service: null`) rather
// than the logged-in SettingsPage. It is also the only case in that sweep that
// really logs out, so it runs LAST and restores the session itself.

/// case 13 — settings_prelogin_bootstrap_node_test: log out to the LoginPage,
/// open the LOGIN-PAGE settings (LoginSettingsPage → BootstrapSettingsSection
/// with `service: null`) and drive the REAL Test button BOTH WAYS.
///
/// WHY THIS CASE EXISTS. Every other bootstrap case here runs against the
/// LOGGED-IN settings page, where `service != null`. Nothing in the harness ever
/// opened `LoginSettingsPage`, so the pre-login half of the same widget was
/// completely uncovered — and it was broken: the Test button answered
/// "Cannot send a bootstrap request before login" and probed nothing. That is
/// the single surface a user who CANNOT CONNECT can reach, so the feature was
/// missing exactly when it was needed.
///
/// WHY IT IS BIDIRECTIONAL. A probe that always says "unreachable" would still
/// satisfy a negative-only assertion while being just as broken as the excuse
/// string it replaced. So this case pins BOTH directions against the SAME
/// public key, changing only the port:
///   * NEGATIVE — 127.0.0.1:1 must come back "Node unreachable".
///   * POSITIVE — 127.0.0.1:<B's real DHT UDP port> must come back
///     "Node reachable".
/// The positive target is peer B's own live Tox DHT endpoint, read from its
/// `l3_dht_info` tool, so the check is hermetic: no public bootstrap node, no
/// internet dependency, and the two verdicts are separated by a single field.
/// Because the SAME pubkey is used for both, a pass also proves the probe is
/// keyed on real reachability rather than on descriptor validity.
///
/// Runs LAST (it logs out) and restores the session with a no-password quick
/// login in a `finally`, so a failure here cannot strand the pair logged out.
Future<bool> _settingsPreloginBootstrapNodeTest(
  Inst inst,
  Inst? peer,
  String peerNick,
) async {
  if (peer == null) {
    print('[pair] prelogin_bootstrap: no peer instance — cannot build a '
        'REACHABLE target, refusing to run a negative-only check');
    return false;
  }
  // B is launched-but-IDLE in this sweep — it sits on the login screen with no
  // Tox instance, so its DHT endpoint is 0/empty until it is actually logged
  // in. Bring it home first; that is what makes it a genuinely reachable node.
  await ensureHome(peer, peerNick);
  await peer.waitState(
    (s) => s['isConnected'] == true,
    label: '$peerNick connected',
    timeoutSecs: 90,
  );
  // B's live DHT endpoint: the reachable half of the differential. Read BEFORE
  // logging A out (B is untouched by that, but fail fast if it is unusable).
  final dht = await peer.l3('l3_dht_info');
  final peerPort = (dht['udpPort'] as num?)?.toInt() ?? 0;
  final peerKey = (dht['dhtId']?.toString() ?? '').trim();
  if (peerKey.length != 64) {
    print('[pair] prelogin_bootstrap: peer DHT id unusable '
        '(keyLen=${peerKey.length})');
    return false;
  }
  // TOX_FORCE_TCP_ONLY. The iOS fixture-C pair defaults to it
  // (launch_ios_fixture_c_pair.sh: TOXEE_IOS_FORCE_TCP_ONLY:-1) because
  // same-host UDP loopback between two sim apps is silently dropped. With no
  // UDP socket there is NO reachable-over-UDP target to point at, so the
  // "reachable" half is genuinely unconstructible here. Do NOT fake it: assert
  // the verdict this environment CAN prove — that the probe reports the UDP
  // constraint rather than libelling every node as unreachable — and say
  // plainly that the reachable direction was not exercised.
  final udpAvailable = peerPort > 0;
  if (!udpAvailable) {
    print('[pair] prelogin_bootstrap: peer has NO UDP port (TCP-only pair) — '
        'reachable-direction NOT provable in this environment; asserting the '
        'udp-unavailable verdict instead. Re-run with '
        'TOXEE_IOS_FORCE_TCP_ONLY=0 to exercise the reachable half.');
  }

  final toxId = await _logoutToLoginPage(inst);
  if (toxId.isEmpty) {
    print('[pair] prelogin_bootstrap: logout to login page failed');
    return false;
  }

  var settingsOpened = false;
  var manualMode = false;
  var formShown = false;
  var deadVerdict = false;
  var liveVerdict = false;
  var excuseShown = true;
  try {
    await inst.foreground();
    if (!await inst.tapKeyCenter('login_page_settings_button',
        timeoutSecs: 8)) {
      await inst.tryTapKey('login_page_settings_button');
    }
    settingsOpened = await inst.waitKey(
      'settings_bootstrap_mode_manual',
      timeoutSecs: 12,
    );
    if (!settingsOpened) {
      print('[pair] prelogin_bootstrap: LoginSettingsPage did not open');
      return false;
    }

    manualMode = await _setBootstrapMode(
      inst,
      'settings_bootstrap_mode_manual',
      'manual',
    );
    if (!manualMode) {
      print('[pair] prelogin_bootstrap: could not enter manual mode');
      return false;
    }

    // Expand the manual form. SINGLE-FIRE the toggle (see case 7).
    if (!await _settingsScrollTo(inst, 'manual_node_input_button')) {
      print('[pair] prelogin_bootstrap: expand button never reached');
      return false;
    }
    if (!await inst.tapKeyCenter('manual_node_input_button')) {
      await inst.tryTapKey('manual_node_input_button');
    }
    formShown = await inst.waitKey('manual_node_host_field', timeoutSecs: 8);
    if (!formShown) {
      print('[pair] prelogin_bootstrap: manual form did not expand');
      return false;
    }
    await inst.scrollAt(_settingsScrollKey, dy: 300);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    const udpMsg = 'Node test needs UDP; this device is running TCP-only';
    // NEGATIVE half: same host + same key, a port nothing listens on.
    deadVerdict = await _preloginProbeVerdict(
      inst,
      host: '127.0.0.1',
      port: '1',
      pubkey: peerKey,
      expect: udpAvailable ? 'Node unreachable' : udpMsg,
      label: udpAvailable ? 'dead' : 'dead(udp-less)',
    );
    // POSITIVE half: B's real DHT port. Only constructible with UDP.
    //
    // FALLBACK, and why it is not test-rigging: sim<->sim UDP loopback is
    // documented in ToxManager.cpp as "silently dropped" on this host class,
    // so a negative here does NOT distinguish "the probe cannot ever say
    // reachable" (a real bug) from "this sandbox drops loopback UDP" (an
    // environment limit). A genuinely reachable PUBLIC node disambiguates it.
    // Whichever target answers is printed, so the evidence stays unambiguous.
    liveVerdict = udpAvailable
        ? await _preloginProbeVerdict(
            inst,
            host: '127.0.0.1',
            port: '$peerPort',
            pubkey: peerKey,
            expect: 'Node reachable',
            label: 'live-loopback',
          )
        : await _preloginProbeVerdict(
            inst,
            host: '127.0.0.1',
            port: '33445',
            pubkey: peerKey,
            expect: udpMsg,
            label: 'live(udp-less)',
          );
    if (udpAvailable && !liveVerdict) {
      final pub = await _firstOnlinePublicNode();
      if (pub == null) {
        print('[pair] prelogin_bootstrap: loopback UDP gave no reachable '
            'verdict and no public node could be fetched — cannot tell a '
            'probe bug from a sandbox UDP-loopback drop');
      } else {
        print('[pair] prelogin_bootstrap: loopback gave no reachable verdict; '
            'retrying against PUBLIC node ${pub.host}:${pub.port}');
        liveVerdict = await _preloginProbeVerdict(
          inst,
          host: pub.host,
          port: '${pub.port}',
          pubkey: pub.pubkey,
          expect: 'Node reachable',
          label: 'live-public',
        );
      }
    }
    // The defect this case exists for. Must be gone, not merely rare.
    excuseShown = await inst.waitText(
      'Cannot send a bootstrap request before login',
      timeoutSecs: 2,
    );
  } finally {
    // Restore: leave the login settings page, then re-enter the session so the
    // sweep's teardown (and any later batch) sees a logged-in shell. This also
    // proves the ephemeral probe instance did not poison the Tox singleton.
    await inst.tryTapKey('login_settings_back_button');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!await _quickLoginNoPassword(inst, toxId)) {
      print('[pair] prelogin_bootstrap: WARNING re-login after case failed');
    }
  }

  print(
    '[pair] settings_prelogin_bootstrap_node_test: opened=$settingsOpened '
    'manualMode=$manualMode form=$formShown '
    'deadVerdict(unreachable)=$deadVerdict liveVerdict(reachable)=$liveVerdict '
    'peerPort=$peerPort excuseShown=$excuseShown (expect false)',
  );
  return settingsOpened &&
      manualMode &&
      formShown &&
      deadVerdict &&
      liveVerdict &&
      !excuseShown;
}

/// Fill the manual node form with one descriptor, tap the REAL Test button and
/// require [expect] to appear. Waits for the PREVIOUS verdict to clear first so
/// a stale pill from the other half can never satisfy this one.
Future<bool> _preloginProbeVerdict(
  Inst inst, {
  required String host,
  required String port,
  required String pubkey,
  required String expect,
  required String label,
}) async {
  const other = <String, String>{
    'Node unreachable': 'Node reachable',
    'Node reachable': 'Node unreachable',
  };
  // Editing any field invalidates a prior probe result (the production
  // `_invalidateManualNodeProbe`), so the pill from the other half is torn down
  // by the fills below — but wait it out explicitly rather than assuming.
  await inst.waitTextGone(expect, timeoutSecs: 6);

  await _nudgeIntoBand(inst, 'manual_node_host_field');
  await _fillFieldViaKeystrokes(inst, 'manual_node_host_field', host);
  if (await inst.waitKey('manual_node_port_field', timeoutSecs: 4)) {
    await _nudgeIntoBand(inst, 'manual_node_port_field');
    await _fillFieldViaKeystrokes(inst, 'manual_node_port_field', port);
  }
  if (await inst.waitKey('manual_node_pubkey_field', timeoutSecs: 4)) {
    await _nudgeIntoBand(inst, 'manual_node_pubkey_field');
    await _fillFieldViaKeystrokes(inst, 'manual_node_pubkey_field', pubkey);
  }
  // DISMISS THE SOFT KEYBOARD FIRST (narrow shell only in effect, harmless
  // elsewhere). The three fills above leave the IME up; it covers the bottom of
  // a phone screen and SWALLOWS taps aimed at controls there, while the element
  // tree keeps reporting those controls at their UNOBSCURED coordinates — so the
  // Test-button tap reports success and the probe never runs. That is exactly
  // the `onScreen="none-of-the-known-verdicts"` red: live on iPhone 2026-08-16
  // the screenshot showed all three fields correctly filled, the caret still in
  // the public-key field, and the Test button below the visible fold. The band
  // cache is dropped with it because a band measured with the IME up is wrong
  // for the resized viewport. iPad never hit this — it has the viewport to
  // spare, which is why this case had only ever been exercised there.
  await inst.hideKeyboard();
  _settingsBandCache.remove(inst.name);
  await _nudgeIntoBand(inst, 'manual_node_test_button');
  if (!await inst.tapKeyCenter('manual_node_test_button')) {
    await inst.tryTapKey('manual_node_test_button');
  }
  // The pre-login probe stands up an ephemeral Tox instance before it can
  // answer, so allow a wide window. The dead half must burn the full probe
  // timeout, so this has to outlast BootstrapNodeProbe.defaultTimeout.
  final got = await inst.waitText(expect, timeoutSecs: 60);
  final opposite = got || other[expect] == null
      ? false
      : await inst.waitText(other[expect]!, timeoutSecs: 2);
  // DIAGNOSIS, not an assertion. `BootstrapVerdictUi.pillFor` can render FOUR
  // distinct states and a bare `got=false` cannot tell them apart — which left
  // the live Android failure (2026-08-16) undiagnosable from the log alone.
  // Report whichever one is actually on screen so the next reader gets the
  // answer instead of another round-trip. 'unavailable' in particular means
  // `BootstrapProbeUnavailable` — the probe INSTANCE failed to start, which is
  // our defect, not the node's, and is a different bug from a UDP-less device.
  var actual = 'none-of-the-known-verdicts';
  var fieldsSeen = '';
  if (!got) {
    for (final candidate in const [
      'Node reachable',
      'Node unreachable',
      'Node test needs UDP; this device is running TCP-only',
      'Node test unavailable on this device',
      'Cannot send a bootstrap request before login',
      // The SIXTH outcome, and the one the five-string list could not name:
      // `_testManualNode` bails out with this snackbar BEFORE it probes
      // anything when a field is empty / the pubkey is not 64 hex / the port
      // does not parse. On a narrow shell the three fields are filled by
      // scroll-then-keystroke, so a fill that silently missed lands here — a
      // HARNESS defect that reads exactly like a dead probe.
      'Please enter valid node information (host, port, and public key)',
    ]) {
      if (await inst.waitText(candidate, timeoutSecs: 1)) {
        actual = candidate;
        break;
      }
    }
    // Whether the FORM is even still mounted, and what it holds. A verdict
    // cannot render if the section scrolled away or the fields never took the
    // text; this separates "probe answered nothing" from "we never asked".
    for (final k in const [
      'manual_node_host_field',
      'manual_node_port_field',
      'manual_node_pubkey_field',
      'manual_node_test_button',
    ]) {
      fieldsSeen += '${k.split('_')[2]}=${await inst.keyCenter(k) != null} ';
    }
    await inst.shot('/tmp/ui_prelogin_bootstrap_${label}_${inst.name}.png');
  }
  print('[pair] prelogin_bootstrap[$label]: $host:$port -> '
      'expected="$expect" got=$got opposite=$opposite'
      '${got ? '' : ' onScreen="$actual" form[$fieldsSeen]'}');
  return got;
}

/// First ONLINE IPv4 node from nodes.tox.chat, or null. Used only to tell a
/// probe bug apart from this sandbox's UDP-loopback drop (see the caller).
Future<({String host, int port, String pubkey})?>
_firstOnlinePublicNode() async {
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final req = await client.getUrl(Uri.parse('https://nodes.tox.chat/json'));
    final resp = await req.close();
    final body = await resp.transform(const Utf8Decoder()).join();
    client.close();
    final nodes = (jsonDecode(body) as Map<String, dynamic>)['nodes'];
    if (nodes is! List) return null;
    for (final n in nodes) {
      if (n is! Map) continue;
      final up = n['status_udp'] == true;
      final host = (n['ipv4'] ?? '').toString();
      final port = (n['port'] as num?)?.toInt() ?? 0;
      final key = (n['public_key'] ?? '').toString();
      if (up && host.isNotEmpty && host != '-' && port > 0 &&
          key.length == 64) {
        return (host: host, port: port, pubkey: key);
      }
    }
  } catch (e) {
    print('[pair] prelogin_bootstrap: public node fetch failed: $e');
  }
  return null;
}
