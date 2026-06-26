// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

const _skillNs = 'ext.flutter.flutter_skill';
const _mcpNs = 'ext.mcp.toolkit';
final _realUiPlatform =
    (Platform.environment['TOXEE_REAL_UI_PLATFORM'] ?? 'macos').trim();
bool get _isIosRealUi => _realUiPlatform == 'ios';

/// Headless Windows: no host osascript, and OS-level key/paste injection cannot
/// reach the app's window-station, so EVERY input goes through synthetic
/// flutter_skill RPC (`enterText`) + the `l3_composer_send` send seam. Unlike
/// iOS (which runs on a macOS host and still uses osascript for foreground /
/// send / paste), Windows overrides the whole osa* primitive surface below.
bool get _isWindowsRealUi => _realUiPlatform == 'windows';

/// Translate a hardcoded `/tmp/<name>` debug path (screenshots, scratch files)
/// to the host's temp dir so the driver runs on Windows, which has no `/tmp`.
/// Non-`/tmp/` paths pass through unchanged.
String _portableTmp(String path) {
  if (path.startsWith('/tmp/')) {
    return '${Directory.systemTemp.path}'
        '${Platform.pathSeparator}${path.substring('/tmp/'.length)}';
  }
  return path;
}

/// Run osascript with a hard timeout so a hung System Events call (an
/// unresponsive window / stuck modal — System Events is effectively serial, so
/// one wedged call can stall every later one) can't wedge the driver. On
/// timeout returns a failed ProcessResult (exit 124); callers already treat a
/// non-zero exit as a non-fatal osascript failure.
Future<ProcessResult> _osaRun(List<String> args, {int timeoutSecs = 20}) async {
  try {
    return await Process.run(
      'osascript',
      args,
    ).timeout(Duration(seconds: timeoutSecs));
  } on TimeoutException {
    return ProcessResult(
      0,
      124,
      '',
      'osascript timed out after ${timeoutSecs}s',
    );
  }
}

const _sidebarTabX = 50;
const _sidebarChatsY = 220;
const _sidebarContactsY = 288;

class _LocalVmServiceHttpOverrides extends HttpOverrides {
  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    final host = url.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost' || host == '::1') {
      return 'DIRECT';
    }
    return super.findProxyFromEnvironment(url, environment);
  }
}

class DriveError implements Exception {
  DriveError(this.message);
  final String message;
  @override
  String toString() => 'DriveError: $message';
}

class PermissionBlockedError extends DriveError {
  PermissionBlockedError(super.message);
}

bool _isNonTestAccountError(Object e) => '$e'.contains('non_test_account');

class Inst {
  Inst(this.name, this.ws, this.pid);
  final String name;
  String ws;
  int pid;
  late VmService vm;
  late String iso;

  /// Latches true once an l3 navigation tool (e.g. l3_force_home_root) reports
  /// `non_test_account`. An account REGISTERED through the real UI (every fresh
  /// no-friend launch) carries no l3 seed marker, so the mutating nav tools are
  /// refused and each call is dead weight. Shell recovery consults this to skip
  /// the doomed call (and its WARN) instead of burning a recovery round on it.
  bool navToolsUnavailable = false;

  Future<void> connect() async {
    await _refreshWsUriFromRuntime();
    await _connectVmWithRetry();
    // Wait for the skill + l3 extensions to be live.
    await _waitExt('$_skillNs.tap');
    await _waitExt('$_mcpNs.l3_dump_state');
  }

  Future<void> _connectVmWithRetry({int attempts = 15}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        vm = await vmServiceConnectUri(ws);
        final v = await vm.getVM();
        final isos = v.isolates ?? const <IsolateRef>[];
        iso = isos
            .firstWhere(
              (i) => (i.name ?? '').toLowerCase().contains('main'),
              orElse: () => isos.first,
            )
            .id!;
        return;
      } catch (e) {
        lastError = e;
        try {
          await vm.dispose();
        } catch (_) {}
        await _refreshWsUriFromRuntime();
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
        }
      }
    }
    throw DriveError(
      '[$name] failed to connect VM service at $ws after $attempts attempts: '
      '$lastError',
    );
  }

  Future<void> _waitExt(String name, {int timeoutSecs = 60}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final i = await vm.getIsolate(iso);
      if ((i.extensionRPCs ?? const <String>[]).contains(name)) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    throw DriveError('[$name] extension never registered on ${this.name}');
  }

  Future<void> dispose() => vm.dispose();

  Future<void> waitExt(String name, {int timeoutSecs = 60}) =>
      _waitExt(name, timeoutSecs: timeoutSecs);

  Future<void> _reconnect() async {
    print('[$name] VM service connection dropped — reconnecting $ws');
    try {
      await vm.dispose();
    } catch (_) {}
    await _refreshWsUriFromRuntime();
    await _connectVmWithRetry();
  }

  Future<void> _refreshWsUriFromRuntime() async {
    try {
      final pairFile = File(
        Platform.environment['TOXEE_REAL_UI_PAIR_JSON'] ??
            'tool/mcp_test/.multi_instance_runtime/pair.json',
      );
      if (!await pairFile.exists()) return;
      final root =
          jsonDecode(await pairFile.readAsString()) as Map<String, dynamic>;
      final instances =
          (root['instances'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      Map<String, dynamic>? match;
      for (final entry in instances.values) {
        if (entry is! Map) continue;
        final map = entry.cast<String, dynamic>();
        final entryPid = int.tryParse('${map['pid']}');
        if (entryPid == pid) {
          match = map;
          break;
        }
      }
      if (match == null) return;
      final stdioLogPath = match['stdio_log']?.toString();
      if (stdioLogPath == null || stdioLogPath.isEmpty) return;
      final stdioFile = File(stdioLogPath);
      if (!await stdioFile.exists()) return;
      final lines = await stdioFile.readAsLines();
      String? latestVmHttp;
      final vmLinePattern = RegExp(
        r'http://127\.0\.0\.1:\d+(?:/[A-Za-z0-9_=-]+)?/?',
      );
      for (final line in lines.reversed) {
        final match = vmLinePattern.firstMatch(line);
        if (match != null) {
          latestVmHttp = match.group(0);
          break;
        }
      }
      if (latestVmHttp == null || latestVmHttp.isEmpty) return;
      latestVmHttp = latestVmHttp.replaceFirst(RegExp(r'/$'), '');
      final refreshedWs = '${latestVmHttp.replaceFirst('http:', 'ws:')}/ws';
      if (refreshedWs != ws) {
        print(
          '[$name] refreshed VM service URI from runtime: $ws -> $refreshedWs',
        );
        ws = refreshedWs;
      }
    } catch (e) {
      print('[$name] WARN could not refresh VM URI from runtime: $e');
    }
  }

  bool _isDisposedError(Object e) {
    final s = '$e';
    return s.contains('disposed') ||
        s.contains('WebSocket') ||
        s.contains('Connection closed');
  }

  Future<Map<String, dynamic>> _raw(
    String method,
    Map<String, Object?> params,
  ) async {
    final strArgs = <String, String>{
      for (final e in params.entries)
        e.key: e.value is String ? e.value as String : jsonEncode(e.value),
    };
    Future<Map<String, dynamic>> once() async {
      // Hard per-call timeout: a service-extension RPC that the app isolate
      // never answers (a stuck UI thread, a wedged platform-channel call) would
      // otherwise hang this await forever — and EVERY skill/l3/dump/tap goes
      // through here, so the bounded retry loops in the case drivers can't
      // protect against it. Throw a DriveError so best-effort callers (e.g.
      // `_normalizeBetweenCases`) recover and the campaign keeps moving.
      // Derive the per-call timeout. `waitForElement`-style RPCs intentionally
      // BLOCK on the app side for the wait's OWN timeout (passed as the `timeout`
      // ms arg, up to 120s in some cases), so a fixed short timeout would fire
      // mid-wait and mask the real result. Use (the wait's timeout + a 25s
      // margin) for those; a fixed 45s for fast calls (tap/dump/scroll) — long
      // enough to absorb a transiently-busy isolate (e.g. an account-switch
      // teardown+boot) while still catching a genuine multi-minute hang.
      final timeoutArgMs = int.tryParse(strArgs['timeout'] ?? '');
      final callTimeout = timeoutArgMs != null
          ? Duration(milliseconds: timeoutArgMs + 25000)
          : const Duration(seconds: 45);
      final resp = await vm
          .callServiceExtension(method, isolateId: iso, args: strArgs)
          .timeout(
            callTimeout,
            onTimeout: () => throw DriveError(
              '$name: $method timed out after ${callTimeout.inSeconds}s '
              '(app isolate unresponsive)',
            ),
          );
      return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
    }

    try {
      return await once();
    } catch (e) {
      if (!_isDisposedError(e)) rethrow;
      await _reconnect();
      return once();
    }
  }

  Future<Map<String, dynamic>> skill(
    String m, [
    Map<String, Object?> p = const {},
  ]) => _raw('$_skillNs.$m', p);

  Future<Map<String, dynamic>> l3(
    String m, [
    Map<String, Object?> p = const {},
  ]) => _raw('$_mcpNs.$m', p);

  /// macOS-foreground this instance's window. Required before any UI phase.
  Future<void> foreground() async {
    if (_isWindowsRealUi) {
      // Headless Windows drives purely via synthetic flutter_skill RPC, which is
      // window-station / OS-focus independent; bringing the window forward is
      // both unnecessary and impossible from a non-interactive SSH session.
      return;
    }
    final r = await _osaRun([
      '-e',
      'tell application "System Events" to set frontmost of '
          '(first process whose unix id is $pid) to true',
    ]);
    if (r.exitCode != 0) {
      print('[$name] WARN foreground failed: ${r.stderr}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  /// Resize this instance's macOS window to [width]x[height] logical points via
  /// System Events (targeting the window of the process with this [pid], the
  /// same selector [foreground] uses). Returns whether the resize osascript
  /// succeeded (false, no throw, when the window can't be sized — e.g. a
  /// window_manager constraint or a raw-launched window that refuses scripted
  /// resize). Used by the responsive layout-swap case (narrow the window past
  /// the 720pt bottom-nav breakpoint, then restore).
  Future<bool> resizeWindow(num width, num height) async {
    if (_isWindowsRealUi) {
      // No osascript on Windows — drive the app's own window_manager via the
      // l3_window_state seam (setSize + center). Returns whether it applied.
      final r = await l3('l3_window_state', {
        'state': 'bounds',
        'width': '$width',
        'height': '$height',
      });
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return r['ok'] == true;
    }
    await foreground();
    final r = await _osaRun([
      '-e',
      'tell application "System Events" to tell '
          '(first process whose unix id is $pid) to set size of window 1 '
          'to {$width, $height}',
    ]);
    if (r.exitCode != 0) {
      print('[$name] WARN resizeWindow($width,$height) failed: ${r.stderr}');
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return true;
  }

  /// Read this instance's macOS window size as `{w, h}` logical points via
  /// System Events, or null if it can't be read. Lets a resize case verify the
  /// OS actually applied the new bounds (so a refused/clamped resize is detected
  /// rather than silently treated as applied).
  Future<({num w, num h})?> windowSize() async {
    if (_isWindowsRealUi) {
      // Read the live logical size via the app's window_manager seam.
      final r = await l3('l3_window_state', {'state': 'query_bounds'});
      if (r['ok'] != true) return null;
      final w = num.tryParse('${r['width']}');
      final h = num.tryParse('${r['height']}');
      if (w == null || h == null) return null;
      return (w: w, h: h);
    }
    final r = await _osaRun([
      '-e',
      'tell application "System Events" to tell '
          '(first process whose unix id is $pid) to get size of window 1',
    ]);
    if (r.exitCode != 0) return null;
    final out = '${r.stdout}'.trim();
    final parts = out.split(',').map((s) => s.trim()).toList();
    if (parts.length != 2) return null;
    final w = num.tryParse(parts[0]);
    final h = num.tryParse(parts[1]);
    if (w == null || h == null) return null;
    return (w: w, h: h);
  }

  Future<Map<String, dynamic>> dumpState({
    String? userId,
    String? conversationId,
  }) => l3('l3_dump_state', {
    if (userId != null) 'userId': userId,
    if (conversationId != null) 'conversationId': conversationId,
  });

  Future<void> bootExistingAccount(String toxId, String nickname) async {
    final r = await l3('l3_boot_existing_account', {
      'toxId': toxId,
      'nickname': nickname,
    });
    if (r['ok'] != true) {
      throw DriveError('[$name] l3_boot_existing_account failed: $r');
    }
  }

  Future<void> clearActiveConversation() async {
    final r = await l3('l3_clear_active_conversation');
    if (r['ok'] != true) {
      throw DriveError('[$name] l3_clear_active_conversation failed: $r');
    }
  }

  Future<void> forceHomeRoot({String tab = 'chats'}) async {
    var r = await l3('l3_force_home_root', {'tab': tab});
    if (r['ok'] != true &&
        r['error'] == 'non_test_account' &&
        _isWindowsRealUi) {
      // Windows headless cannot recover a drifted/blank shell via real-UI nav
      // (no OS input), so the non-test gate would dead-loop the blank-shell
      // recovery (root-caused live: contacts/app-entry pre-handshake cases drift
      // to a blank shell that only l3_force_home_root can pop back). Temporarily
      // grant the seed marker so the recovery can run, then revoke it so the
      // sweep's privilege state is unchanged. Navigation-stability ONLY — no
      // asserted action depends on this transient grant.
      final marked = await markAccountTest();
      try {
        r = await l3('l3_force_home_root', {'tab': tab});
      } finally {
        if (marked) await unmarkAccountTest();
      }
    }
    if (r['ok'] != true) {
      if (r['error'] == 'non_test_account') navToolsUnavailable = true;
      throw DriveError('[$name] l3_force_home_root failed: $r');
    }
  }

  Future<bool> openAddFriendDialogViaL3() async {
    final r = await l3('l3_open_add_friend_dialog');
    return r['ok'] == true;
  }

  /// Deterministically open the C2C ([userId] = friend pubkey) or group
  /// ([groupId]) chat by driving the SAME production `_openChat` path the
  /// conversation row / profile "Send Message" tile uses (flips to the Chats
  /// tab + binds the desktop master-detail right pane; the production handler
  /// SYNTHESIZES the conversation when no row exists yet, so this works for the
  /// FIRST message). UNGATED (like l3_open_add_friend_dialog / _add_group) so it
  /// works on fresh non-test accounts. NAVIGATION-STABILITY ONLY — every
  /// asserted action (send/recall/search/…) stays a real widget gesture; this
  /// just gets the harness into the chat surface when the multi-tap
  /// contacts→profile→Send-Message dance is unreliable under 2-process
  /// foreground contention. Returns whether the seam reported success.
  Future<bool> openChatViaL3({String? userId, String? groupId}) async {
    final r = await l3('l3_open_chat', {
      if (userId != null) 'userId': userId,
      if (groupId != null) 'groupId': groupId,
    });
    return r['ok'] == true;
  }

  /// Grant the CURRENT (real-UI-registered, non-test) account the L3
  /// seed-account marker so the test-account-gated tools (`l3_send_file`,
  /// `l3_clear_history`, …) act on it. NOTE: the marker authorizes the WHOLE
  /// gated surface, not just seeding — pair with [unmarkAccountTest] in an
  /// end-guard so the launch ends with the same non-test privilege state. The
  /// campaign uses it only to SEED (the asserted UI action stays the real
  /// widget/gesture). Returns whether the account is a test account afterwards.
  Future<bool> markAccountTest() async {
    final r = await l3('l3_mark_current_account_test');
    final ok = r['ok'] == true && r['isTestAccount'] == true;
    // Clear the stale `non_test_account` latch: the account IS a test account
    // now, so the gated nav tools (l3_force_home_root, …) are available again.
    // Without this, a latch set earlier — e.g. during the handshake, which runs
    // on the still-NON-test account and trips forceHomeRoot's non_test_account
    // branch — would wrongly keep `_forceHomeRootAndWait` skipping the
    // deterministic recovery for the WHOLE marked window, leaving only the
    // flaky 2-process UI-landmark recovery (the root cause of "failed to recover
    // to Contacts shell" gating the first-chat-open in every chat sweep).
    if (ok) navToolsUnavailable = false;
    return ok;
  }

  /// Revoke the seed-account marker granted by [markAccountTest] so the launch
  /// ends with the same (non-test) privilege state it started — no hidden grant
  /// left behind for a reused launch. Best-effort (returns whether it succeeded).
  Future<bool> unmarkAccountTest() async {
    try {
      final r = await l3('l3_unmark_current_account_test');
      return r['ok'] == true;
    } on DriveError {
      return false;
    }
  }

  Future<bool> deleteFriendViaL3(String userId) async {
    final r = await l3('l3_delete_friend', {'userId': userId});
    return r['ok'] == true;
  }

  Future<void> tapKey(String key, {int retries = 6}) async {
    for (var i = 0; i < retries; i++) {
      final r = await skill('tap', {'key': key});
      if (r['success'] == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    throw DriveError('[$name] tapKey "$key" failed after $retries tries');
  }

  Future<void> tapText(String text, {int retries = 6}) async {
    for (var i = 0; i < retries; i++) {
      final r = await skill('tap', {'text': text});
      if (r['success'] == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    throw DriveError('[$name] tapText "$text" failed after $retries tries');
  }

  /// Best-effort tap-by-key; returns whether it landed (no throw).
  Future<bool> tryTapKey(String key, {int retries = 3}) async {
    for (var i = 0; i < retries; i++) {
      final r = await skill('tap', {'key': key});
      if (r['success'] == true) return true;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return false;
  }

  /// Focus a (possibly TextFormField-wrapped) plain field by key, then type into
  /// it with REAL OS keystrokes (osascript), NOT a synthetic
  /// `flutter_skill.enterText`.
  ///
  /// **Why osascript and not enterText:** the synthetic `enterText` drives the
  /// macOS Flutter engine's `-[FlutterTextInputPlugin setEditingState:]`, which
  /// INTERMITTENTLY SIGSEGVs the whole app (observed killing instance A on the
  /// manual-node host field AND the self-profile nickname field; the
  /// `[callback_bridge] FATAL: received signal 11` line is just the FFI signal
  /// handler catching the engine crash, frame 2 ==
  /// `-[FlutterTextInputPlugin setEditingState:]`). Real keystrokes go through
  /// AppKit's normal key path — the same crash-free route the desktop composer
  /// uses — so they don't touch setEditingState at all. All `focusType` callers
  /// target plain `TextField`/`TextFormField`s (NOT the ExtendedTextField
  /// composer), where genuine keystrokes land fine.
  ///
  /// Focus is a SINGLE-FIRE `tapKeyCenter` (not the double-firing synthetic
  /// `tap`) to avoid focus thrash; falls back to `tapKey` if the field has no
  /// resolvable bounds yet. Clears any existing content (Cmd+A, Delete) first so
  /// re-entry replaces rather than appends.
  Future<void> focusType(String key, String text) async {
    if (_isIosRealUi || _isWindowsRealUi) {
      await focusTypeSynthetic(key, text);
      return;
    }
    await foreground();
    if (!await tapKeyCenter(key)) {
      await tapKey(key);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await osaClear();
    // ALWAYS paste (clipboard), never keystroke. macOS `System Events keystroke`
    // DROPS / MANGLES characters even on SHORT strings when typed faster than the
    // input plugin drains — verified live: a 76-char Tox ID came back 72 chars,
    // AND an 11-char remark "RuiB4Remark" came back "RuiB4R e mark" (spaces
    // injected). Paste is ATOMIC: it sets the field's controller text in one shot
    // and fires the onChanged listener once with the COMPLETE value, which is
    // exactly what every consumer (search filters, validators, remark/id fields)
    // wants. The legacy length-thresholded keystroke path is gone — it was the
    // root of the self-add / handshake-id corruption and the remark corruption.
    if (text.isEmpty) {
      // osaClear already emptied the field; a paste of "" is a no-op.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return;
    }
    await osaPaste(text);
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  /// Legacy synthetic-enterText focus+type, kept for the rare case a caller
  /// genuinely needs the platform-channel path (none today). PREFER [focusType],
  /// which is crash-safe. See the setEditingState SIGSEGV note above.
  Future<void> focusTypeSynthetic(String key, String text) async {
    await tapKey(key);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Target the field BY KEY first: a focus-less enterText fails ("No focused
    // TextField found") when tapKey couldn't focus the editable (e.g. an
    // off-screen field like the profile status field, vs. the always-visible
    // nickname field). enterText(key:) finds the widget in the tree regardless
    // of focus/visibility. Fall back to the focused-field form.
    var r = await skill('enterText', {'key': key, 'text': text});
    if (r['success'] != true) {
      r = await skill('enterText', {'text': text});
    }
    if (r['success'] != true) {
      throw DriveError('[$name] focusType "$key" enterText failed: $r');
    }
  }

  Future<void> tapAt(num x, num y) async {
    await skill('tapAt', {'x': x, 'y': y});
  }

  /// SINGLE-FIRE tap on a keyed element: resolve its on-screen centre via
  /// `interactiveStructured` and dispatch exactly ONE `tapAt`.
  ///
  /// flutter_skill's `tap` fires the callback TWICE — once via a synthetic
  /// pointer (`_dispatchTap`) and again via a direct `widget.onPressed!()`
  /// (`_tryInvokeCallback`). For a route-popping button (`Navigator.pop(...)`)
  /// that means TWO pops: the first closes the dialog, the second — invoked
  /// while the button is still mounted mid-dismiss — pops the PAGE underneath.
  /// In the logout/password flows that pops HomePage, and the trailing
  /// `if (!mounted) return` then skips the `pushAndRemoveUntil(LoginPage)`,
  /// leaving an EMPTY Navigator (blank screen, zero interactive elements). Use
  /// this for the ON-SCREEN dialog POP buttons (confirm/save/dismiss). NOT for
  /// below-fold openers — a coordinate `tapAt` would miss; drive those with
  /// `tapKey`, whose direct `_tryInvokeCallback` fires once off-screen. See the
  /// flutter_skill_double_tap_blank harness hazard. Returns false (no throw)
  /// when the key is absent or has no usable bounds.
  Future<bool> tapKeyCenter(String key, {int timeoutSecs = 8}) async {
    if (await waitKey(key, timeoutSecs: timeoutSecs)) {
      // `waitKey` proves the element is in the tree, but not that it has been
      // LAID OUT: in the one-frame window after a dialog appears the RenderBox can
      // still be absent, so interactiveStructured reports {x:0,y:0,w:0,h:0}.
      // Re-query a few times so a not-yet-measured button isn't mistaken for
      // "not tappable" (a silent hard-gate failure). The happy path taps on the
      // first attempt, unchanged.
      for (var attempt = 0; attempt < 5; attempt++) {
        final r = await skill('interactiveStructured', const {});
        final data = r['data'];
        final elements = data is Map ? data['elements'] : null;
        if (elements is List) {
          // Scan ALL same-key matches and tap the LAST with positive bounds. The
          // elements are reported in tree order, so when a real-UI sweep stacks
          // routes carrying the same key (a re-opened group profile leaves buried
          // duplicates whose RenderBoxes are still laid out with POSITIVE bounds
          // — flutter_skill has no paint/cover guard), the EARLIER matches are the
          // OLD, covered copies and the LAST is the on-top route the user sees.
          // Tapping the first would land on a covered widget (the mute Switch
          // toggle silently no-ops). Mirrors resolveKeyCenter's `.last` topmost
          // preference. Single-match is unchanged (first == last).
          ({double x, double y})? target;
          for (final e in elements) {
            if (e is! Map || e['key'] != key) continue;
            final b = e['bounds'];
            if (b is! Map) continue;
            final x = (b['x'] as num?) ?? 0;
            final y = (b['y'] as num?) ?? 0;
            final w = (b['w'] as num?) ?? 0;
            final h = (b['h'] as num?) ?? 0;
            if (w <= 0 || h <= 0) continue; // unsized/off-screen — skip
            target = (x: x + w / 2, y: y + h / 2);
          }
          if (target != null) {
            await tapAt(target.x, target.y);
            return true;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    // flutter_skill (waitForElement / interactiveStructured) could NOT see the
    // key OR found no usable bounds. Many real, ONSCREEN keyed widgets are
    // invisible to flutter_skill because their ValueKey is not propagated to the
    // element it reports — e.g. a FloatingActionButton, a non-interactive
    // SelectableText, or a KeyedSubtree wrapper (the group-profile
    // edit-name/id/members keys, the profile save button). Fall back to the
    // ELEMENT-TREE resolver (ui_key_center), which finds ANY onstage sized keyed
    // RenderBox and taps its center. It resolves ONLY onstage widgets, so the
    // coordinate tap stays valid (it never blind-taps a below-fold opener — that
    // returns null here, same as before).
    return tapKeyAt(key);
  }

  // --- Pointer-event primitives (Batch-0 ui_drive_tools). flutter_skill has no
  // scroll/drag/right-click; these route through the app's ui_* service
  // extensions, which dispatch REAL pointer events into the production gesture
  // pipeline. ---

  /// One mouse-wheel scroll at [key]'s center (dy positive scrolls down).
  Future<void> scrollAt(String key, {double dx = 0, required double dy}) async {
    final r = await l3('ui_scroll_at', {'key': key, 'dx': '$dx', 'dy': '$dy'});
    if (r['ok'] != true) {
      throw DriveError('[$name] ui_scroll_at "$key" failed: $r');
    }
  }

  /// One mouse-wheel scroll at raw global coords (dy positive scrolls down).
  /// Use this when the row to scroll on isn't keyed/rendered yet — a coordinate
  /// over the message-list viewport hits whatever Scrollable is under it, so the
  /// scroll lands even when the oldest row is offscreen (a key-center scroll on
  /// an unrendered row would have no RenderBox to resolve).
  Future<void> scrollAtCoords(
    num x,
    num y, {
    double dx = 0,
    required double dy,
  }) async {
    final r = await l3('ui_scroll_at', {
      'x': '$x',
      'y': '$y',
      'dx': '$dx',
      'dy': '$dy',
    });
    if (r['ok'] != true) {
      throw DriveError('[$name] ui_scroll_at ($x,$y) failed: $r');
    }
  }

  /// Touch-drag [key]'s center by (dx,dy) over [steps] moves.
  Future<void> dragBy(
    String key, {
    double dx = 0,
    required double dy,
    int steps = 12,
  }) async {
    final r = await l3('ui_drag', {
      'key': key,
      'dx': '$dx',
      'dy': '$dy',
      'steps': '$steps',
    });
    if (r['ok'] != true) {
      throw DriveError('[$name] ui_drag "$key" failed: $r');
    }
  }

  /// Touch-drag from raw coords (fromX,fromY) by (dx,dy) over [steps] moves — a
  /// real PointerDown/Move/Up sequence. Unlike [scrollAtCoords] (a single
  /// mouse-wheel PointerScrollEvent, which a Flutter ListView can ignore at a
  /// given hit point), a touch drag reliably scrolls the scrollable under the
  /// start point. Used to scroll the group-profile ListView (a wheel event
  /// there did not move it, leaving the clear/leave buttons below the fold).
  Future<void> dragAtCoords(
    num fromX,
    num fromY, {
    double dx = 0,
    required double dy,
    int steps = 12,
  }) async {
    final r = await l3('ui_drag', {
      'fromX': '$fromX',
      'fromY': '$fromY',
      'dx': '$dx',
      'dy': '$dy',
      'steps': '$steps',
    });
    if (r['ok'] != true) {
      throw DriveError('[$name] ui_drag ($fromX,$fromY) failed: $r');
    }
  }

  /// Right-click (secondary tap) at [key]'s center — opens the desktop chat
  /// message context menu / conversation-row menu.
  Future<void> secondaryTapKey(String key) async {
    final r = await l3('ui_secondary_tap', {'key': key});
    if (r['ok'] != true) {
      throw DriveError('[$name] ui_secondary_tap "$key" failed: $r');
    }
  }

  /// Right-click (secondary tap) at raw global coords — use when the keyed row's
  /// geometric center is empty space (e.g. a right-aligned self message bubble,
  /// where the row center is left of the bubble and a center right-click misses
  /// the bubble's Listener).
  Future<void> secondaryTapAt(num x, num y) async {
    final r = await l3('ui_secondary_tap', {'x': '$x', 'y': '$y'});
    if (r['ok'] != true) {
      throw DriveError('[$name] ui_secondary_tap ($x,$y) failed: $r');
    }
  }

  /// Long-press (real touch down → hold → up) at [key]'s center — the MOBILE
  /// trigger twin of [secondaryTapKey] (message / conversation-row context
  /// menus and the login account-card management menu open via long-press).
  /// [holdMs] defaults to 800 ms — past BOTH the 500 ms framework timeout AND
  /// the fork's custom 650 ms conversation-row recognizer
  /// (`TencentCloudChatGesture` → `LongPressGestureRecognizer(duration: 650)`);
  /// a shorter hold would release early and fall through as a TAP (which on a
  /// conversation row navigates).
  Future<void> longPressKey(String key, {int holdMs = 800}) async {
    final r = await l3('ui_long_press', {'key': key, 'holdMs': '$holdMs'});
    if (r['ok'] != true) {
      throw DriveError('[$name] ui_long_press "$key" failed: $r');
    }
  }

  /// READ-ONLY on-screen global center (x,y) of a keyed widget, or null when it
  /// can't be resolved (absent / offstage-only). Works for NON-interactive keyed
  /// anchors (e.g. a SizedBox wrapping a SegmentedButton) that flutter_skill's
  /// interactiveStructured doesn't surface — used to check whether a scroll anchor
  /// is within the visible viewport before tapping a child of it.
  Future<({double x, double y})?> keyCenter(String key) async {
    try {
      final r = await l3('ui_key_center', {'key': key});
      if (r['ok'] != true) return null;
      final x = (r['x'] as num?)?.toDouble();
      final y = (r['y'] as num?)?.toDouble();
      if (x == null || y == null) return null;
      return (x: x, y: y);
    } on DriveError {
      return null;
    }
  }

  /// Single-fire tap at a keyed widget's resolved center via `ui_key_center`
  /// (resolveKeyCenter) + `tapAt`. Unlike [tapKeyCenter] (which reads
  /// flutter_skill's `interactiveStructured` and therefore only finds INTERACTIVE
  /// widgets), this resolves the center of ANY onstage keyed widget — including a
  /// keyed NON-interactive wrapper (a Material/SizedBox around an InkWell /
  /// SegmentedButton). Returns false (no throw) when the key can't be resolved to
  /// an onstage center.
  Future<bool> tapKeyAt(String key) async {
    final c = await keyCenter(key);
    if (c == null) return false;
    await tapAt(c.x, c.y);
    return true;
  }

  /// Scroll [scrollableKey] by [dyPerStep] (negative = wheel up to reveal
  /// earlier content; positive = down) until [targetKey] appears, up to
  /// [maxSteps] wheel ticks. Foregrounds first (like other UI phases). Returns
  /// whether the target became visible. Best-effort: a missing scrollable key
  /// stops the loop and returns false instead of throwing.
  Future<bool> scrollUntilKey(
    String scrollableKey,
    String targetKey, {
    double dyPerStep = -300,
    int maxSteps = 20,
  }) async {
    await foreground();
    if (await waitKey(targetKey, timeoutSecs: 2)) return true;
    for (var step = 0; step < maxSteps; step++) {
      final r = await l3('ui_scroll_at', {
        'key': scrollableKey,
        'dx': '0',
        'dy': '$dyPerStep',
      });
      if (r['ok'] != true) {
        print('[$name] WARN scrollUntilKey stop: ui_scroll_at failed: $r');
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (await waitKey(targetKey, timeoutSecs: 1)) return true;
    }
    return false;
  }

  // --- Real OS input (foreground window). The desktop chat composer is an
  // ExtendedTextField whose ExtendedEditableText cannot be driven by synthetic
  // enterText, and Enter-to-send rides the legacy FocusNode.onKey RawKeyEvent
  // path — both need genuine OS events. ---
  Future<void> _osa(String script) async {
    final r = await _osaRun(['-e', script]);
    if (r.exitCode != 0) {
      final stderrText = '${r.stderr}'.trim();
      final suffix = stderrText.contains('not allowed to send keystrokes')
          ? ' (macOS Accessibility permission missing for osascript/System Events)'
          : '';
      if (stderrText.contains('not allowed to send keystrokes')) {
        throw PermissionBlockedError(
          '[$name] osascript failed (exit ${r.exitCode}): $stderrText$suffix',
        );
      }
      throw DriveError(
        '[$name] osascript failed (exit ${r.exitCode}): $stderrText$suffix',
      );
    }
  }

  Future<void> osaType(String text) async {
    if (_isWindowsRealUi) {
      // Synthetic text entry — sets the focused EditableText's value in one shot
      // (proven to land verbatim on Windows, no SIGSEGV unlike macOS).
      await skill('enterText', {'text': text});
      return;
    }
    // Escape backslash and double-quote for the AppleScript string literal so
    // arbitrary field text (now the primary typing path via [focusType]) types
    // verbatim rather than breaking the script. `!`, `@`, `.`, `-`, digits and
    // letters need no escaping inside an AppleScript string.
    final escaped = text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    await _osa('tell application "System Events" to keystroke "$escaped"');
  }

  /// Place [text] on the macOS clipboard (via `pbcopy`) and paste it into the
  /// focused field with Cmd+V. ATOMIC — unlike `keystroke`, paste never drops
  /// characters, so long strings (Tox ids, 76 chars) land verbatim. Used by
  /// [focusType] for any text at/above [_osaPasteThreshold].
  Future<void> osaPaste(String text) async {
    if (_isWindowsRealUi) {
      await skill('enterText', {'text': text});
      return;
    }
    final proc = await Process.start('pbcopy', const <String>[]);
    proc.stdin.write(text);
    await proc.stdin.close();
    final code = await proc.exitCode;
    if (code != 0) {
      // Fall back to keystroke typing rather than aborting the case.
      await osaType(text);
      return;
    }
    // Brief settle so the pasteboard write is visible to the paste.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await _osa(
      'tell application "System Events" to keystroke "v" using command down',
    );
  }

  Future<void> osaReturn() async {
    if (_isWindowsRealUi) {
      // The desktop composer's Enter-to-send rides FocusNode.onKey
      // (RawKeyDownEvent), un-reachable by synthetic enterText and by any
      // headless OS key injection. `l3_composer_send` invokes the EXACT same
      // `_submitDesktopSend()` the real Enter triggers (real field text + real
      // inputMethods.sendTextMessage). See the fork composer seam.
      await l3('l3_composer_send');
      return;
    }
    await _osa('tell application "System Events" to key code 36');
  }

  /// Shift+Enter — the desktop composer maps Shift/Alt/Ctrl/Meta+Enter to
  /// INSERT a newline (no send); see `_handleKeyEvent` in
  /// tencent_cloud_chat_message_input_desktop.dart. A genuine OS chord so the
  /// production RawKeyEvent path runs (synthetic enterText can't reach it).
  Future<void> osaShiftReturn() async {
    if (_isWindowsRealUi) {
      // Multiline insert (Shift+Enter) has no pure-synthetic equivalent; the few
      // multiline cases must enterText the full "a\nb" body in one shot instead.
      // No-op here so the surrounding flow doesn't error.
      return;
    }
    await _osa(
      'tell application "System Events" to key code 36 using shift down',
    );
  }

  Future<void> osaEscape() async {
    if (_isWindowsRealUi) {
      // Best-effort dismiss (close search/overlay/dialog) via the navigation
      // hook — the headless equivalent of pressing Escape.
      await l3('l3_pop_to_root');
      return;
    }
    await _osa('tell application "System Events" to key code 53');
  }

  /// Send Cmd+Ctrl+F — the global conversation-search shortcut
  /// (`_OpenSearchIntent` in home_page.dart, the only entry to the search
  /// overlay; there is no visible search button). A genuine OS key chord, so the
  /// production `Shortcuts`/`Actions` path runs.
  Future<void> osaSearchShortcut() async {
    if (_isWindowsRealUi) {
      await l3('l3_open_global_search');
      return;
    }
    await _osa(
      'tell application "System Events" to keystroke "f" using '
      '{command down, control down}',
    );
  }

  /// Send Cmd+Ctrl+N — the "new conversation" shortcut (`_NewConversationIntent`
  /// in home_page.dart) which opens the Add-Friend dialog. Genuine OS chord so the
  /// production `Shortcuts`/`Actions` path runs (mirrors [osaSearchShortcut]).
  Future<void> osaNewConversationShortcut() async {
    if (_isWindowsRealUi) {
      await l3('l3_open_add_friend_dialog');
      return;
    }
    await _osa(
      'tell application "System Events" to keystroke "n" using '
      '{command down, control down}',
    );
  }

  /// Send Cmd+Ctrl+, — the "open settings" shortcut (`_OpenSettingsIntent` in
  /// home_page.dart) which switches the home shell to the Settings tab
  /// (`setState(() => _index = 3)`).
  Future<void> osaOpenSettingsShortcut() async {
    if (_isWindowsRealUi) {
      // Headless equivalent: jump the home shell to the Settings tab. Use the
      // self-healing forceHomeRoot (not a raw l3_force_home_root call) so a
      // non-test app-entry account doesn't silently no-op the gated tool.
      await forceHomeRoot(tab: 'settings');
      return;
    }
    await _osa(
      'tell application "System Events" to keystroke "," using '
      '{command down, control down}',
    );
  }

  /// Place [text] on the macOS clipboard via `pbcopy` WITHOUT pasting — for cases
  /// that then exercise an in-app "Paste" control (e.g. the add-friend paste
  /// button's `_pasteFromClipboard`) which reads the clipboard itself. Unlike
  /// [osaPaste] this does NOT send Cmd+V, so the asserted action stays the real
  /// in-app button.
  Future<void> setClipboard(String text) async {
    if (_isWindowsRealUi) {
      // Set the clipboard from INSIDE the app (Flutter Clipboard.setData) so the
      // in-app paste button reads it. A driver-side Set-Clipboard would land in a
      // different Windows window-station and be invisible to the headless app.
      await l3('l3_set_clipboard', {'text': text});
      return;
    }
    final proc = await Process.start('pbcopy', const <String>[]);
    proc.stdin.write(text);
    await proc.stdin.close();
    final code = await proc.exitCode;
    if (code != 0) {
      throw DriveError('[$name] pbcopy failed (exit $code)');
    }
    // Brief settle so the pasteboard write is visible to the in-app reader.
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<void> osaClear() async {
    if (_isWindowsRealUi) {
      // enterText replaces the focused field's whole value, so an empty string
      // clears it (the macOS Cmd+A + Delete equivalent).
      await skill('enterText', {'text': ''});
      return;
    }
    await _osa(
      'tell application "System Events" to keystroke "a" using command down',
    );
    await _osa('tell application "System Events" to key code 51');
  }

  Future<bool> waitKey(String key, {int timeoutSecs = 25}) async {
    final r = await skill('waitForElement', {
      'key': key,
      // flutter_skill's waitForElement timeout is MILLISECONDS
      // (Duration(milliseconds: timeout)). Passing the bare seconds value made
      // every wait a ~Nms single check that only "worked" when the element was
      // already present; a wait on a freshly-triggered async open (e.g. a
      // showDialog field) expired before the first frame. Convert to ms so
      // timeoutSecs actually means seconds.
      'timeout': '${timeoutSecs * 1000}',
    });
    return r['found'] == true;
  }

  /// Poll until a keyed widget is resolvable via `ui_key_center` (the
  /// ELEMENT-TREE walk), not flutter_skill's `waitForElement`. Use this for
  /// keys on NON-interactive / composite widgets that flutter_skill's
  /// interactiveStructured does NOT surface — a `SelectableText`
  /// (`group_profile_id_text`), a `KeyedSubtree` (`group_profile_members_entry`),
  /// a `FloatingActionButton`. Returns true once resolvable, false on timeout.
  Future<bool> waitKeyCenter(String key, {int timeoutSecs = 10}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      if (await keyCenter(key) != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<bool> waitText(String text, {int timeoutSecs = 25}) async {
    final r = await skill('waitForElement', {
      'text': text,
      // See waitKey: flutter_skill expects the timeout in milliseconds.
      'timeout': '${timeoutSecs * 1000}',
    });
    return r['found'] == true;
  }

  /// Poll until a keyed widget is GONE (dialog closed / page changed), via
  /// flutter_skill's purpose-built `waitForGone` (timeout in ms, like waitKey).
  Future<bool> waitKeyGone(String key, {int timeoutSecs = 8}) async {
    final r = await skill('waitForGone', {
      'key': key,
      'timeout': '${timeoutSecs * 1000}',
    });
    return r['gone'] == true;
  }

  /// Poll until a widget with visible [text] is GONE (e.g. a transient SnackBar
  /// has dismissed), via flutter_skill's `waitForGone` text matcher (timeout in
  /// ms, like waitText). Lets a later case avoid false-greening on a stale toast
  /// from an earlier case that asserts the SAME text.
  Future<bool> waitTextGone(String text, {int timeoutSecs = 8}) async {
    final r = await skill('waitForGone', {
      'text': text,
      'timeout': '${timeoutSecs * 1000}',
    });
    return r['gone'] == true;
  }

  /// Poll a top-level dump_state scalar until [test] passes.
  Future<Map<String, dynamic>> waitState(
    bool Function(Map<String, dynamic>) test, {
    int timeoutSecs = 60,
    String label = 'state',
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    Map<String, dynamic> last = const {};
    while (DateTime.now().isBefore(deadline)) {
      last = await dumpState();
      if (test(last)) return last;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw DriveError('[$name] waitState "$label" timed out; last=$last');
  }

  Future<void> shot(String path) async {
    final r = await skill('screenshot');
    final img = r['image'] as String?;
    if (img == null || img.isEmpty) {
      print('[$name] shot empty (window backgrounded?)');
      return;
    }
    final outPath = _portableTmp(path);
    await File(outPath).writeAsBytes(base64Decode(img));
    print('[$name] shot -> $outPath');
  }
}
