// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Real OS input primitives for [Inst], and their synthetic substitutes.
//
// SPLIT OUT of drive_real_ui_pair_inst.dart, which sat exactly at its
// `tool/.complexity_baseline.txt` pin and therefore could not absorb the
// `clearActiveConversation` recovery it needed. The seam is a real one: every
// member here is an INPUT primitive that either (a) drives genuine OS events
// through osascript on macOS, or (b) takes the documented synthetic /
// L3-seam substitute on a platform osascript cannot reach
// ([Inst._usesSyntheticInput]: iOS, Android, Windows, Linux). Nothing here
// asserts product behaviour.
//
// It is an EXTENSION rather than a second half of the class because Dart has no
// partial classes; being in the same library (a `part`) keeps access to Inst's
// private members (`_osa`, `_usesSyntheticInput`, `_proc`, ...) unchanged.

/// Windows REAL OS input — the Windows twin of the macOS osascript layer.
///
/// OPT-IN via `TOXEE_WIN_OS_INPUT=1`, because it only works when the driver
/// runs INSIDE the Windows console session (session 1 — e.g. launched through
/// an interactive scheduled task, see `tool/vmtest/win_run_interactive.ps1`):
/// foreground switching and `SendInput` need the interactive window station,
/// and an SSH session (session 0) has none. When set, every `osa*` primitive
/// below drives GENUINE OS events through `tool/mcp_test/win_os_input.ps1`
/// (foreground the pid, type/paste/chord) exactly like macOS, so the cases
/// whose premise IS the keystroke — Enter-to-send through `FocusNode.onKey`,
/// Shift+Enter newline, `@` mention trigger, "typed but not sent" — are honest
/// on Windows instead of substituted (`_isHeadlessRealUi` still decides window
/// geometry, blank shell recovery and timing; those stay on the l3 seams).
/// Without the flag Windows keeps the documented synthetic-substitute
/// contract, byte-for-byte.
///
/// Two Windows facts shape the helper (probe runs 9-18 on win11_ltsc):
///  * `WScript.Shell.SendKeys` / `keybd_event` inject virtual keys with scan
///    code 0. Flutter's Windows embedder maps every such key to the SAME
///    physical key (0x1600000000); the first key-up mismatches the recorded
///    logical key, `HardwareKeyboard` asserts, and every later KeyDown is
///    rejected before text input — NOTHING typed ever lands. The helper sends
///    real scan codes through `SendInput`, holding Shift across shifted runs
///    (toggling it per key still dropped characters).
///  * `AppActivate(pid)` returns true without changing the foreground when
///    another window (the peer instance, launched last) holds the input lock,
///    and on an already-foreground window it moves Win32 focus from the
///    FLUTTERVIEW child to the runner frame. `Set-ToxeeForeground` verifies
///    with `GetForegroundWindow` (AttachThreadInput bypass) and
///    `FocusFlutterView` puts focus back on the engine view.
///
/// The three Cmd+Ctrl chords (search / new conversation / settings) keep their
/// l3 seams even with the flag: the app binds them with `meta` (= the Windows
/// key), which is not worth pressing through the OS.
bool get _winOsInput =>
    _realUiPlatform == 'windows' &&
    Platform.isWindows &&
    (Platform.environment['TOXEE_WIN_OS_INPUT'] ?? '').trim() == '1';

/// Absolute path of the PowerShell helper (the driver runs from the repo root).
String get _winHelperPath =>
    '${Directory.current.path}\\tool\\mcp_test\\win_os_input.ps1';

/// Run a PowerShell snippet with a hard timeout, serialized on the same chain
/// as osascript so two instances' key events can never interleave (SendInput
/// goes to whatever window is foreground — the activate + keys must be
/// atomic). `-EncodedCommand` because `-Command <text>` re-parses the text and
/// strips embedded double quotes.
Future<ProcessResult> _winPsRun(String script, {int timeoutSecs = 40}) {
  final encoded = base64Encode(_utf16le(script));
  return _serializeOsa(() async {
    // Process.start + kill: a plain Process.run(...).timeout() would release
    // the serialized chain while the stuck PowerShell kept running and could
    // inject its keys into whatever window is foreground later.
    final proc = await Process.start('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      encoded,
    ]);
    final out = proc.stdout.transform(utf8.decoder).join();
    final err = proc.stderr.transform(utf8.decoder).join();
    try {
      final code = await proc.exitCode.timeout(Duration(seconds: timeoutSecs));
      return ProcessResult(proc.pid, code, await out, await err);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      return ProcessResult(
        proc.pid,
        124,
        '',
        'powershell timed out after ${timeoutSecs}s (killed)',
      );
    }
  });
}

List<int> _utf16le(String s) {
  final out = <int>[];
  for (final u in s.codeUnits) {
    out
      ..add(u & 0xff)
      ..add(u >> 8);
  }
  return out;
}

/// PowerShell single-quoted literal (only `'` needs doubling).
String _psLiteral(String s) => "'${s.replaceAll("'", "''")}'";

extension InstOsInput on Inst {
  // --- Windows real OS input primitives (see [_winOsInput]). ---

  /// Foreground this instance's window for real (`Enter-ToxeeInput`: verified
  /// foreground + focus on the FLUTTERVIEW child + stuck modifiers released),
  /// then run [body] with the helper's `Send-Scan*` functions in scope. Throws
  /// on activation failure — keys sent to a window that is NOT ours would land
  /// in the peer instance.
  Future<void> _winRun(String body, {String what = 'win input'}) async {
    final appPid = this.pid; // see _osaForProcess: `pid` alone is dart:io's
    final r = await _winPsRun(
      '. ${_psLiteral(_winHelperPath)}\n'
      'Enter-ToxeeInput -ProcessId $appPid | Out-Null\n'
      '$body\n',
    );
    if (r.exitCode != 0) {
      throw DriveError(
        '[$name] $what failed (exit ${r.exitCode}): ${'${r.stderr}'.trim()}',
      );
    }
  }

  /// Type [text] as genuine scan-coded key presses. 25 ms per key: the
  /// embedder redispatches unhandled keys asynchronously and loses characters
  /// injected faster (measured: 6 ms kept 1 of 8 shifted chars, 20 ms all).
  Future<void> _winScanText(String text) => _winRun(
    'Send-ScanText -Text ${_psLiteral(text)} -DelayMs 25 | Out-Null\n'
    'Start-Sleep -Milliseconds 150',
    what: 'type',
  );

  /// Press one named key (`ENTER`, `ESC`, `HOME`, ... or a single character)
  /// with optional modifiers (`ctrl`, `shift`, `alt`).
  Future<void> _winScanKey(String key, {List<String> mods = const []}) =>
      _winRun(
        'Send-ScanKey -Name ${_psLiteral(key)}'
        '${mods.isEmpty ? '' : ' -Modifiers ${mods.join(',')}'}\n'
        'Start-Sleep -Milliseconds 120',
        what: 'key $key',
      );

  /// Clipboard + Ctrl+V — the atomic paste, same rationale as [osaPaste].
  Future<void> _winPaste(String text) => _winRun(
    'Set-Clipboard -Value ${_psLiteral(text)}\n'
    'Start-Sleep -Milliseconds 120\n'
    'Send-ScanKey -Name v -Modifiers ctrl\nStart-Sleep -Milliseconds 150',
    what: 'paste',
  );

  // --- Real OS input (foreground window). The desktop chat composer is an
  // ExtendedTextField whose ExtendedEditableText cannot be driven by synthetic
  // enterText, and Enter-to-send rides the legacy FocusNode.onKey RawKeyEvent
  // path — both need genuine OS events. ---
  Future<void> _osa(String script) async {
    // Every osa* wrapper below now branches EXPLICITLY on [_usesSyntheticInput]
    // to its synthetic/L3 substitute (iOS included — it used to reach this line
    // and lose the action silently), so this is purely a defensive net for a
    // FUTURE wrapper whose author forgets that branch: skipping beats firing a
    // stray host keystroke into whatever is frontmost. A skip here means a
    // MISSING branch, never an intended no-op.
    if (_usesSyntheticInput) return;
    if (_winOsInput || _linuxOsInput) {
      // No osascript on Windows/Linux: reaching here means a wrapper has no
      // branch for that backend. Loud, so the gap is fixed rather than
      // silently skipped.
      throw DriveError(
        '[$name] osascript reached under real-OS-input mode — '
        'wrapper lacks a ${_winOsInput ? 'Windows' : 'Linux'} branch: $script',
      );
    }
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

  // `this.pid`, NOT `pid`: inside an EXTENSION an unqualified identifier is
  // resolved in the lexical (library) scope BEFORE the on-type's implicit
  // `this` members, and `dart:io` exports a top-level `pid` — the DRIVER's own
  // process id. (Verified: `AppActivate(<driver pid>)` failed on Windows; on
  // macOS the wrong `tell process` went unnoticed because `keystroke` lands in
  // the frontmost app regardless of which process is addressed.)
  Future<void> _osaForProcess(String action) => _osa(
    'tell application "System Events" to tell '
    '(first process whose unix id is ${this.pid}) to $action',
  );

  Future<void> osaType(String text) async {
    if (_winOsInput) {
      await _winScanText(text);
      return;
    }
    if (_linuxOsInput) {
      await _linuxType(text);
      return;
    }
    if (_usesSyntheticInput) {
      // Synthetic text entry — sets the focused EditableText's value in one shot
      // (verbatim on Windows/Linux/Android, no SIGSEGV unlike macOS). iOS shares
      // it: already its route via [focusType] / [focusTypeSynthetic].
      await skill('enterText', {'text': text});
      return;
    }
    // Escape backslash and double-quote for the AppleScript string literal so
    // arbitrary field text (now the primary typing path via [focusType]) types
    // verbatim rather than breaking the script. `!`, `@`, `.`, `-`, digits and
    // letters need no escaping inside an AppleScript string.
    final escaped = text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    await _osaForProcess('keystroke "$escaped"');
  }

  /// Place [text] on the macOS clipboard (via `pbcopy`) and paste it into the
  /// focused field with Cmd+V. ATOMIC — unlike `keystroke`, paste never drops
  /// characters, so long strings (Tox ids, 76 chars) land verbatim. Used by
  /// [focusType] for any text at/above [_osaPasteThreshold].
  Future<void> osaPaste(String text) async {
    if (_winOsInput) {
      await _winPaste(text);
      return;
    }
    if (_linuxOsInput) {
      await _linuxPaste(text);
      return;
    }
    if (_usesSyntheticInput) {
      // enterText IS an atomic paste (whole value, one onChanged), no clipboard
      // involved. iOS MUST come here: the `pbcopy` below writes the *host*
      // pasteboard and the Cmd+V lands in the frontmost macOS app, leaving the
      // device's field empty while the driver reported success.
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
    await _osaForProcess('keystroke "v" using command down');
  }

  Future<void> osaReturn() async {
    if (_winOsInput) {
      await _winScanKey('ENTER');
      return;
    }
    if (_linuxOsInput) {
      await _linuxKey('Return');
      return;
    }
    if (_usesSyntheticInput) {
      // The desktop composer's Enter-to-send rides FocusNode.onKey
      // (RawKeyDownEvent), un-reachable by synthetic enterText and by any
      // headless OS key injection. `l3_composer_send` invokes the EXACT same
      // `_submitDesktopSend()` the real Enter triggers (real field text + real
      // inputMethods.sendTextMessage). See the fork composer seam. iOS too: it
      // has no Return to synthesize and its mobile composer sends via the send
      // button, but the seam submits the composer's REAL text either way — so
      // osaReturn actually sends there instead of silently dropping.
      await l3('l3_composer_send');
      return;
    }
    await _osaForProcess('key code 36');
  }

  /// Shift+Enter — the desktop composer maps Shift/Alt/Ctrl/Meta+Enter to
  /// INSERT a newline (no send); see `_handleKeyEvent` in
  /// tencent_cloud_chat_message_input_desktop.dart. A genuine OS chord so the
  /// production RawKeyEvent path runs (synthetic enterText can't reach it).
  Future<void> osaShiftReturn() async {
    if (_winOsInput) {
      await _winScanKey('ENTER', mods: const ['shift']);
      return;
    }
    if (_linuxOsInput) {
      await _linuxKey('shift+Return');
      return;
    }
    if (_usesSyntheticInput) {
      // Multiline insert (Shift+Enter) has no pure-synthetic equivalent; the few
      // multiline cases must enterText the full "a\nb" body in one shot instead.
      // Documented NO-OP, branched EXPLICITLY (iOS included) rather than left to
      // [_osa]'s net, so it reads as the deliberate contract it is: "no chord
      // exists — the caller supplies the newline in the text".
      return;
    }
    await _osaForProcess('key code 36 using shift down');
  }

  Future<void> osaEscape() async {
    if (_winOsInput) {
      await _winScanKey('ESC');
      return;
    }
    if (_linuxOsInput) {
      await _linuxKey('Escape');
      return;
    }
    if (_usesSyntheticInput) {
      // Best-effort dismiss (close search/overlay/dialog) via the navigation
      // hook — the synthetic-input equivalent of Escape. iOS has no Escape key
      // and its mobile shell dismisses by pop anyway, so this is the closest
      // production path; before, the iOS overlay just stayed open and the next
      // assertion ran against the wrong screen.
      await popToRoot();
      return;
    }
    await _osaForProcess('key code 53');
  }

  /// Send Cmd+Ctrl+F — the global conversation-search shortcut
  /// (`_OpenSearchIntent` in home_page.dart, the only entry to the search
  /// overlay; there is no visible search button). A genuine OS key chord, so the
  /// production `Shortcuts`/`Actions` path runs.
  Future<void> osaSearchShortcut() async {
    if (_usesSyntheticInput || _winOsInput || _linuxOsInput) {
      // No usable OS chord on ANY of these: iOS has no Cmd+Ctrl+F at all,
      // Windows binds `meta` to the shell's own key, and on Linux the chord
      // reaches the X server but the app does not act on it (evidence in
      // drive_real_ui_pair_inst_linux_input.dart) — open the same overlay
      // through its l3 intent seam instead.
      await l3('l3_open_global_search');
      return;
    }
    await _osaForProcess('keystroke "f" using {command down, control down}');
  }

  /// Send Cmd+Ctrl+N — the "new conversation" shortcut (`_NewConversationIntent`
  /// in home_page.dart) which opens the Add-Friend dialog. Genuine OS chord so the
  /// production `Shortcuts`/`Actions` path runs (mirrors [osaSearchShortcut]).
  Future<void> osaNewConversationShortcut() async {
    if (_usesSyntheticInput || _winOsInput || _linuxOsInput) {
      // As [osaSearchShortcut]: chord undeliverable, use the l3 intent seam.
      await l3('l3_open_add_friend_dialog');
      return;
    }
    await _osaForProcess('keystroke "n" using {command down, control down}');
  }

  /// Send Cmd+Ctrl+, — the "open settings" shortcut (`_OpenSettingsIntent` in
  /// home_page.dart) which switches the home shell to the Settings tab
  /// (`setState(() => _index = 3)`).
  Future<void> osaOpenSettingsShortcut() async {
    if (_usesSyntheticInput || _winOsInput || _linuxOsInput) {
      // Synthetic-input equivalent: jump the home shell to the Settings tab. Use
      // the self-healing forceHomeRoot (not a raw l3_force_home_root call) so a
      // non-test app-entry account doesn't silently no-op the gated tool. iOS
      // included: its bottom nav lands on the SAME tab index, so the
      // post-condition `homeShellTab == 'settings'` matches the desktop chord's.
      await forceHomeRoot(tab: 'settings');
      await waitState(
        (s) => s['homeShellTab'] == 'settings',
        label: 'homeShellTab==settings',
        timeoutSecs: 6,
      );
      return;
    }
    await _osaForProcess('keystroke "," using {command down, control down}');
  }

  /// Place [text] on the host/device clipboard WITHOUT pasting — for cases that
  /// then exercise an in-app "Paste" control. Every non-macOS target uses the
  /// app-side seam because host `pbcopy` writes a pasteboard the app process
  /// cannot see — a foreign window-station, a device/emulator, or (iOS
  /// Simulator) a pasteboard whose host sync is an opt-in Simulator setting with
  /// debounced, unreliable propagation.
  Future<void> setClipboard(String text) async {
    if (_linuxOsInput) {
      // Same X display as the app: the real CLIPBOARD selection, which the
      // in-app paste button reads through Flutter's Clipboard.getData.
      await _linuxRun(['clipboard', _b64(text)], what: 'set clipboard');
      return;
    }
    if (_winOsInput) {
      // Same desktop session as the app: the real OS clipboard, which the
      // in-app paste button reads through Flutter's Clipboard.getData.
      final r = await _winPsRun('Set-Clipboard -Value ${_psLiteral(text)}');
      if (r.exitCode != 0) {
        throw DriveError('[$name] Set-Clipboard failed: ${r.stderr}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return;
    }
    if (_usesSyntheticInput || isAndroid) {
      // Set the clipboard from INSIDE the app (Flutter Clipboard.setData) so the
      // in-app paste button reads it deterministically, with no host round-trip.
      // `isAndroid` stays alongside: [_isHeadlessRealUi] reads the GLOBAL
      // platform for android, `isAndroid` is per-instance (a heterogeneous pair
      // can carry an Android peer under a macOS global).
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
    if (_linuxOsInput) {
      await _linuxRun(['clear'], what: 'clear');
      return;
    }
    if (_winOsInput) {
      // Select everything by CARET MOVEMENT (Ctrl+End → Ctrl+Shift+Home →
      // Backspace): works for single- AND multi-line editables through plain
      // navigation keys, and unlike Ctrl+A it never depends on a select-all
      // shortcut binding. One activation, so a peer's activate can't split it.
      await _winRun(
        'Send-ScanKey -Name END -Modifiers ctrl\nStart-Sleep -Milliseconds 60\n'
        'Send-ScanKey -Name HOME -Modifiers ctrl,shift\n'
        'Start-Sleep -Milliseconds 60\n'
        'Send-ScanKey -Name BACKSPACE\nStart-Sleep -Milliseconds 90',
        what: 'clear',
      );
      return;
    }
    if (_usesSyntheticInput) {
      // enterText replaces the focused field's whole value, so an empty string
      // clears it (the Cmd+A + Delete equivalent). iOS included: neither half of
      // that chord reaches the device, so the field kept its old text and the
      // next entry APPENDED — the very corruption osaClear exists to prevent.
      await skill('enterText', {'text': ''});
      return;
    }
    await _osaForProcess('keystroke "a" using command down');
    await _osaForProcess('key code 51');
  }
}
