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
extension InstOsInput on Inst {
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

  Future<void> _osaForProcess(String action) => _osa(
    'tell application "System Events" to tell '
    '(first process whose unix id is $pid) to $action',
  );

  Future<void> osaType(String text) async {
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
    if (_usesSyntheticInput) {
      // No OS chord is deliverable (iOS has no Cmd+Ctrl+F at all); open the same
      // overlay through its l3 intent seam.
      await l3('l3_open_global_search');
      return;
    }
    await _osaForProcess('keystroke "f" using {command down, control down}');
  }

  /// Send Cmd+Ctrl+N — the "new conversation" shortcut (`_NewConversationIntent`
  /// in home_page.dart) which opens the Add-Friend dialog. Genuine OS chord so the
  /// production `Shortcuts`/`Actions` path runs (mirrors [osaSearchShortcut]).
  Future<void> osaNewConversationShortcut() async {
    if (_usesSyntheticInput) {
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
    if (_usesSyntheticInput) {
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
  }}
