// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

const _skillNs = 'ext.flutter.flutter_skill';
const _mcpNs = 'ext.mcp.toolkit';
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
  final int pid;
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
      final pairFile = File('tool/mcp_test/.multi_instance_runtime/pair.json');
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
      final resp = await vm.callServiceExtension(
        method,
        isolateId: iso,
        args: strArgs,
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
    final r = await Process.run('osascript', [
      '-e',
      'tell application "System Events" to set frontmost of '
          '(first process whose unix id is $pid) to true',
    ]);
    if (r.exitCode != 0) {
      print('[$name] WARN foreground failed: ${r.stderr}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
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
    final r = await l3('l3_force_home_root', {'tab': tab});
    if (r['ok'] != true) {
      if (r['error'] == 'non_test_account') navToolsUnavailable = true;
      throw DriveError('[$name] l3_force_home_root failed: $r');
    }
  }

  Future<bool> openAddFriendDialogViaL3() async {
    final r = await l3('l3_open_add_friend_dialog');
    return r['ok'] == true;
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

  /// Focus a (possibly TextFormField-wrapped) field by key, then type into the
  /// focused editable.
  Future<void> focusType(String key, String text) async {
    await tapKey(key);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final r = await skill('enterText', {'text': text});
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
    if (!await waitKey(key, timeoutSecs: timeoutSecs)) return false;
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
        // Scan ALL same-key matches and tap the first with positive bounds — a
        // stale/offstage earlier match (e.g. a stacked dialog or an IndexedStack
        // branch) must not mask a later visible copy.
        for (final e in elements) {
          if (e is! Map || e['key'] != key) continue;
          final b = e['bounds'];
          if (b is! Map) continue;
          final x = (b['x'] as num?) ?? 0;
          final y = (b['y'] as num?) ?? 0;
          final w = (b['w'] as num?) ?? 0;
          final h = (b['h'] as num?) ?? 0;
          if (w <= 0 || h <= 0) continue; // unsized/off-screen — try next match
          await tapAt(x + w / 2, y + h / 2);
          return true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  // --- Pointer-event primitives (Batch-0 ui_drive_tools). flutter_skill has no
  // scroll/drag/right-click; these route through the app's ui_* service
  // extensions, which dispatch REAL pointer events into the production gesture
  // pipeline. ---

  /// One mouse-wheel scroll at [key]'s center (dy positive scrolls down).
  Future<void> scrollAt(String key, {double dx = 0, required double dy}) async {
    final r = await l3('ui_scroll_at', {
      'key': key,
      'dx': '$dx',
      'dy': '$dy',
    });
    if (r['ok'] != true) {
      throw DriveError('[$name] ui_scroll_at "$key" failed: $r');
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

  /// Right-click (secondary tap) at [key]'s center — opens the desktop chat
  /// message context menu / conversation-row menu.
  Future<void> secondaryTapKey(String key) async {
    final r = await l3('ui_secondary_tap', {'key': key});
    if (r['ok'] != true) {
      throw DriveError('[$name] ui_secondary_tap "$key" failed: $r');
    }
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
    final r = await Process.run('osascript', ['-e', script]);
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

  Future<void> osaType(String text) =>
      _osa('tell application "System Events" to keystroke "$text"');
  Future<void> osaReturn() =>
      _osa('tell application "System Events" to key code 36');
  Future<void> osaEscape() =>
      _osa('tell application "System Events" to key code 53');

  /// Send Cmd+Ctrl+F — the global conversation-search shortcut
  /// (`_OpenSearchIntent` in home_page.dart, the only entry to the search
  /// overlay; there is no visible search button). A genuine OS key chord, so the
  /// production `Shortcuts`/`Actions` path runs.
  Future<void> osaSearchShortcut() => _osa(
        'tell application "System Events" to keystroke "f" using '
        '{command down, control down}',
      );
  Future<void> osaClear() async {
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
    await File(path).writeAsBytes(base64Decode(img));
    print('[$name] shot -> $path');
  }
}
