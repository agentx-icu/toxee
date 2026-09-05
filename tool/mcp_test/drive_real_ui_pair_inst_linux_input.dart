// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// LINUX real OS input for [Inst] — the xdotool/XTEST backend behind
// `TOXEE_LINUX_OS_INPUT=1`.
//
// SPLIT OUT of drive_real_ui_pair_inst_os_input.dart for the same reason that
// file was split out of drive_real_ui_pair_inst.dart: adding a third backend
// pushed it past its `tool/.complexity_baseline.txt` cap. The seam is the same
// one, one level down — the osa* wrappers (which stay next to the macOS and
// Windows code) branch here for the Linux primitives, and nothing in this file
// asserts product behaviour.

/// Linux REAL OS input — the Linux twin of the macOS osascript layer.
///
/// OPT-IN via `TOXEE_LINUX_OS_INPUT=1`. Unlike Windows this needs NO
/// interactive console session: XTEST reaches an Xvfb display from an SSH
/// session just as well as a physical one, so the same campaigns run headless.
/// It is opt-in only because it adds two host prerequisites (`xdotool`, and an
/// app whose GDK backend is pinned to x11 — see `_linux_headless_env.sh`);
/// without the flag Linux keeps the documented synthetic-substitute contract
/// byte-for-byte.
///
/// The three global chords (`SingleActivator(..., meta: true, control: true)`)
/// stay on their l3 intent seams here, exactly as on Windows — NOT because the
/// key event cannot be delivered, but because the app never acts on it. Chain
/// of evidence (2026-09-05, Ubuntu 24.04 ARM64 / Xvfb):
///
///  * `xev` shows XTEST delivering the chord PERFECTLY at the X level:
///    Super_L down (state -> 0x40 = Mod4), Control_L down (0x44), then `f`
///    with state 0x44.
///  * Ctrl and Shift from the SAME helper do reach Flutter — [osaClear]'s
///    `ctrl+End` / `ctrl+shift+Home` selection is what makes real-input
///    registration type a correct nickname.
///  * `search_empty_state` (sweep_p1_chat) nevertheless FAILED on both
///    attempts with "search overlay did not open" under the real chord, and
///    PASSES on the identical launch through the l3 seam.
///
/// So SOMETHING between the X wire and the `Shortcuts` widget drops the chord,
/// and the `meta` half is the obvious suspect (X11 carries Super on Mod4 while
/// GDK's META mask is Mod1 here — `xmodmap -pm`: `mod1 Alt_L, Alt_R, Meta_L`).
/// That mechanism is NOT proven: Flutter maps Super to
/// `LogicalKeyboardKey.meta*` and `SingleActivator` matches on
/// `HardwareKeyboard.logicalKeysPressed`, not on a GDK mask, so focus context
/// or modifier-state synchronisation are equally live explanations. Settling it
/// needs a key-event dump from inside the app.
///
/// What IS settled is the part that matters here: the chord does not work, so
/// the harness must not pretend otherwise by driving one the app never acts on.
/// It also raises a PRODUCT question — `home_page.dart` binds four shortcuts as
/// `SingleActivator(key, meta: true, control: true)` under the comment
/// "Setting both `meta` and `control` ... works for macOS and Win/Linux without
/// a per-platform branch". `SingleActivator` ANDs those flags, so on Linux the
/// binding literally is Ctrl+Super+<key>, which is not a platform convention
/// and (per the run above) does not fire. Choosing the right Windows/Linux
/// bindings is a UX call, left open deliberately.
bool get _linuxOsInput =>
    _realUiPlatform == 'linux' &&
    Platform.isLinux &&
    (Platform.environment['TOXEE_LINUX_OS_INPUT'] ?? '').trim() == '1';

/// True when the TARGET is the Linux desktop and the driver runs on it — i.e.
/// the X session the app renders on is reachable from here. Distinct from
/// [_linuxOsInput], which additionally demands the OPT-IN key-injection flag:
/// the CLIPBOARD is readable/writable whenever the app and the driver share a
/// display, whether or not this run injects keys.
bool get _linuxRealUiHost => _realUiPlatform == 'linux' && Platform.isLinux;

/// Read the X CLIPBOARD selection — the Linux answer to `pbpaste` /
/// `Get-Clipboard`. Goes through the helper because it is the piece that knows
/// which display the app renders on (the driver's own environment has none).
/// Returns '' when the selection is empty or unowned; callers poll.
Future<String> linuxClipboardGet() async {
  final r = await _linuxHelperRun(const ['clipget', '0']);
  if (r.exitCode != 0) return '';
  return '${r.stdout}'.trimRight();
}

/// Seed the X CLIPBOARD selection (the `pbcopy` / `clip` equivalent).
Future<void> linuxClipboardSet(String text) async {
  await _linuxHelperRun(['clipboard', '0', _b64(text)]);
}

/// Absolute path of the xdotool helper (the driver runs from the repo root).
String get _linuxHelperPath =>
    '${Directory.current.path}/tool/mcp_test/linux_os_input.sh';

/// Run one helper verb with a hard timeout, serialized on the same chain as
/// osascript / the Windows helper: XTEST keys go to whatever window holds the
/// X input focus, so "focus + keys" must be atomic across the two instances.
Future<ProcessResult> _linuxHelperRun(
  List<String> args, {
  int timeoutSecs = 40,
}) {
  return _serializeOsa(() async {
    // Process.start + kill, not Process.run().timeout(): a plain timeout would
    // release the chain while a stuck xdotool kept the focus it grabbed.
    final proc = await Process.start('bash', [_linuxHelperPath, ...args]);
    // Collect with their OWN timeout, not just `exitCode`'s: an X11 selection
    // owner (`xclip -i`) survives the helper and would inherit these pipes, so
    // a join() on them can outlive the process that "exited". Losing a few
    // bytes of diagnostics beats wedging the driver.
    final out = proc.stdout
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 2), onTimeout: () => '');
    final err = proc.stderr
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 2), onTimeout: () => '');
    try {
      final code = await proc.exitCode.timeout(Duration(seconds: timeoutSecs));
      return ProcessResult(proc.pid, code, await out, await err);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      return ProcessResult(
        proc.pid,
        124,
        '',
        'xdotool helper timed out after ${timeoutSecs}s (killed)',
      );
    }
  });
}

/// Text crosses the process boundary base64-encoded, for the same reason the
/// Windows helper uses `-EncodedCommand`: arbitrary field text (Tox ids,
/// quotes, `@`, newlines) must survive argv unchanged.
String _b64(String s) => base64Encode(utf8.encode(s));

extension InstLinuxInput on Inst {
  // --- Linux real OS input primitives (see [_linuxOsInput]). ---

  /// Run one helper verb against THIS instance's X window. `this.pid`, not
  /// `pid` — see the comment on [_osaForProcess] (an unqualified `pid` in an
  /// extension resolves to `dart:io`'s, the DRIVER's own process id).
  Future<void> _linuxRun(
    List<String> args, {
    String what = 'linux input',
  }) async {
    final argv = [args.first, '${this.pid}', ...args.skip(1)];
    var r = await _linuxHelperRun(argv);
    if (r.exitCode == 3) {
      // Exit 3 = the process lives but has no mapped window, which on this app
      // most plausibly means it hid itself to the tray (`setPreventClose(true)`
      // turns a window close into a hide). Ask it to come back through the
      // production window_manager seam and retry ONCE. Best-effort: the tool is
      // test-account gated, so on a freshly registered account it just refuses
      // and the original error stands.
      try {
        await l3('l3_window_state', {'state': 'show'});
      } catch (_) {
        // keep the original failure
      }
      r = await _linuxHelperRun(argv);
    }
    if (r.exitCode != 0) {
      throw DriveError(
        '[$name] $what failed (exit ${r.exitCode}): ${'${r.stderr}'.trim()}',
      );
    }
  }

  Future<void> _linuxType(String text) =>
      _linuxRun(['type', _b64(text)], what: 'type');

  /// Press one xdotool keyspec (`Return`, `shift+Return`, `ctrl+v`,
  /// `super+ctrl+f`, ...).
  Future<void> _linuxKey(String keyspec) =>
      _linuxRun(['key', keyspec], what: 'key $keyspec');

  Future<void> _linuxPaste(String text) =>
      _linuxRun(['paste', _b64(text)], what: 'paste');

  /// Foreground this instance for a REAL-OS-input backend: Windows verifies
  /// the foreground window, Linux raises + focuses the X window. Shared so
  /// [Inst.foreground] needs a single branch for both (see the header of this
  /// file for why the line budget matters).
  Future<void> _osInputForeground() => _winOsInput
      ? _winRun('', what: 'foreground')
      : _linuxRun(const ['focus'], what: 'foreground');
}
