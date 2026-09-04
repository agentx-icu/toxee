# Windows OS-input helpers for the real-UI driver (dot-source this file):
# real foreground switching + scan-coded key injection. Used by
# drive_real_ui_pair_inst_os_input.dart (TOXEE_WIN_OS_INPUT=1) and by the
# diagnostic probe_win_composer_input.dart.
#
# `WScript.Shell.AppActivate(pid)` returns $true even when Windows' foreground
# lock (SetForegroundWindow is only honoured for the process that received the
# last input) merely FLASHED the taskbar button — every SendKeys then lands in
# whatever window really is foreground. With a two-instance pair that is the
# OTHER toxee (B is launched last, so it sits on top of A). These helpers report
# the real foreground window and force ours, trying the known lock bypasses in
# order and verifying each with GetForegroundWindow().
# The C# below is compiled ONCE into a cached assembly keyed by its own hash:
# every driver step is a fresh powershell process, and `Add-Type
# -TypeDefinition` re-ran csc.exe each time (5-20 s on the emulated VM, which
# is how a plain foreground step hit the driver's 25 s timeout).
$script:ToxeeU32Source = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ToxeeU32 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool alt);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern IntPtr GetFocus();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string cls, string title);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
  // Real left click at a LOGICAL (Flutter) point of the engine view of h.
  // Returns "screenX,screenY,scale" for the log.
  public static string ClickView(IntPtr h, double lx, double ly) {
    IntPtr view = FlutterView(h); if (view == IntPtr.Zero) view = h;
    RECT r; GetWindowRect(view, out r);
    double scale = GetDpiForWindow(view) / 96.0;
    int sx = r.L + (int)Math.Round(lx * scale), sy = r.T + (int)Math.Round(ly * scale);
    SetCursorPos(sx, sy);
    System.Threading.Thread.Sleep(60);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);   // LEFTDOWN
    System.Threading.Thread.Sleep(40);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);   // LEFTUP
    return sx + "," + sy + "," + scale;
  }
  // ---- scan-code key injection -------------------------------------------
  // WScript.Shell.SendKeys / keybd_event inject VIRTUAL keys with scan code 0.
  // Flutter's Windows embedder derives the PHYSICAL key from the scan code, so
  // every such key becomes PhysicalKeyboardKey 0x1600000000; the first key-up
  // then mismatches the logical key the framework recorded for that physical
  // key, HardwareKeyboard asserts (debug builds), the key stays "pressed" and
  // EVERY later KeyDown is rejected before it reaches text input. Real
  // keyboards send scan codes — so does this.
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code, uint mapType);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern short VkKeyScanW(char c);
  static bool IsExtended(ushort vk) {
    switch (vk) {
      case 0x21: case 0x22: case 0x23: case 0x24: case 0x25: case 0x26: case 0x27: case 0x28:
      case 0x2D: case 0x2E: case 0x6F: case 0xA3: case 0xA5: case 0x5B: case 0x5C: case 0x2C: case 0x90:
        return true;
      default: return false;
    }
  }
  public static void KeyScan(ushort vk, bool up) {
    var i = new INPUT(); i.type = 1;
    i.u.ki.wVk = vk; i.u.ki.wScan = (ushort)MapVirtualKeyW(vk, 0);
    // KEYEVENTF_SCANCODE (0x8): the OS derives the VK from wScan through the
    // layout exactly like a physical key, and the scan code reaches Flutter's
    // embedder in lParam. EXTENDEDKEY (0x1) for the E0-prefixed keys.
    i.u.ki.dwFlags = 0x8u | (IsExtended(vk) ? 0x1u : 0u) | (up ? 0x2u : 0u);
    SendInput(1, new[] { i }, Marshal.SizeOf(typeof(INPUT)));
  }
  static void Unicode(char c, bool up) {
    var i = new INPUT(); i.type = 1;
    i.u.ki.wScan = c; i.u.ki.dwFlags = 0x4u | (up ? 0x2u : 0u);   // KEYEVENTF_UNICODE
    SendInput(1, new[] { i }, Marshal.SizeOf(typeof(INPUT)));
  }
  static void SetMods(int held, int want) {
    // Release first, then press — order matters for ctrl+shift chords.
    if ((held & 1) != 0 && (want & 1) == 0) KeyScan(0xA0, true);
    if ((held & 2) != 0 && (want & 2) == 0) KeyScan(0xA2, true);
    if ((held & 4) != 0 && (want & 4) == 0) KeyScan(0xA4, true);
    if ((held & 1) == 0 && (want & 1) != 0) KeyScan(0xA0, false);
    if ((held & 2) == 0 && (want & 2) != 0) KeyScan(0xA2, false);
    if ((held & 4) == 0 && (want & 4) != 0) KeyScan(0xA4, false);
    if (held != want) System.Threading.Thread.Sleep(20);
  }
  // Release every modifier we might have left down (also clears a stuck
  // modifier in the target's HardwareKeyboard state).
  public static void ReleaseMods() { SetMods(7, 0); }
  // Tap vk with modifier scan keys held. mods: 1=shift 2=ctrl 4=alt (VkKeyScan layout).
  public static void Chord(int mods, ushort vk) {
    SetMods(0, mods);
    KeyScan(vk, false); System.Threading.Thread.Sleep(10); KeyScan(vk, true); System.Threading.Thread.Sleep(10);
    SetMods(mods, 0);
  }
  // Type text through the current layout, holding shift ACROSS consecutive
  // shifted characters like a human would: toggling shift around every key
  // dropped characters and left Flutter's modifier state stuck (probe run 16).
  // Chars with no key fall back to the unicode packet.
  public static int SendText(string text, int delayMs) {
    int n = 0, held = 0;
    foreach (char c in text) {
      if (c == '\n') { SetMods(held, 0); held = 0; Chord(0, 0x0D); n++; continue; }
      short r = VkKeyScanW(c);
      if (r == -1) { SetMods(held, 0); held = 0; Unicode(c, false); Unicode(c, true); }
      else {
        int want = (r >> 8) & 7;
        SetMods(held, want); held = want;
        KeyScan((ushort)(r & 0xFF), false); System.Threading.Thread.Sleep(delayMs); KeyScan((ushort)(r & 0xFF), true);
      }
      n++;
      System.Threading.Thread.Sleep(delayMs);
    }
    SetMods(held, 0);
    return n;
  }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  // "hwnd|visible|class|title;..." for every top-level window owned by pid.
  public static string ListWindows(uint pid) {
    var sb = new StringBuilder();
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == pid) {
        var t = new StringBuilder(256); GetWindowTextW(h, t, 256);
        var c = new StringBuilder(256); GetClassNameW(h, c, 256);
        sb.Append(h.ToInt64()).Append('|').Append(IsWindowVisible(h)).Append('|')
          .Append(c).Append('|').Append(t).Append(';');
      }
      return true;
    }, IntPtr.Zero);
    return sb.ToString();
  }
  // The documented lock bypass: attach our input queue to the current
  // foreground thread's, so SetForegroundWindow is honoured.
  public static bool ForegroundViaAttach(IntPtr h) {
    IntPtr fg = GetForegroundWindow();
    uint fgPid; uint fgThread = GetWindowThreadProcessId(fg, out fgPid);
    uint me = GetCurrentThreadId();
    bool attached = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true);
    try {
      BringWindowToTop(h);
      SetForegroundWindow(h);
      SetActiveWindow(h);
    } finally {
      if (attached) AttachThreadInput(me, fgThread, false);
    }
    if (GetForegroundWindow() != h) return false;
    // Keyboard focus must sit on the engine's child view (class FLUTTERVIEW),
    // not on the runner's top-level frame — that is where WM_CHAR is consumed.
    FocusFlutterView(h);
    return true;
  }
  public static IntPtr FlutterView(IntPtr h) { return FindWindowExW(h, IntPtr.Zero, "FLUTTERVIEW", null); }
  // Which window has keyboard focus on h's thread ("hwnd|class").
  public static string FocusOf(IntPtr h) {
    uint pid; uint t = GetWindowThreadProcessId(h, out pid);
    uint me = GetCurrentThreadId();
    bool attached = t != 0 && t != me && AttachThreadInput(me, t, true);
    IntPtr f;
    try { f = GetFocus(); } finally { if (attached) AttachThreadInput(me, t, false); }
    var c = new StringBuilder(256); GetClassNameW(f, c, 256);
    return f.ToInt64() + "|" + c;
  }
  public static bool FocusFlutterView(IntPtr h) {
    IntPtr view = FlutterView(h);
    if (view == IntPtr.Zero) return false;
    uint pid; uint t = GetWindowThreadProcessId(h, out pid);
    uint me = GetCurrentThreadId();
    bool attached = t != 0 && t != me && AttachThreadInput(me, t, true);
    try { SetFocus(view); } finally { if (attached) AttachThreadInput(me, t, false); }
    return true;
  }
  // The other classic: a synthetic ALT press makes *us* the last-input
  // process, which unlocks SetForegroundWindow for this call.
  public static bool ForegroundViaAlt(IntPtr h) {
    KeyScan(0xA4, false); KeyScan(0xA4, true);      // LAlt tap, WITH scan code
    SetForegroundWindow(h);
    return GetForegroundWindow() == h;
  }
}
"@
if (-not ([System.Management.Automation.PSTypeName]'ToxeeU32').Type) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($script:ToxeeU32Source))) -replace '-', '').Substring(0, 16)
  $cacheDir = Join-Path $env:LOCALAPPDATA 'toxee_win_os_input'
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  $dll = Join-Path $cacheDir "ToxeeU32_$hash.dll"
  if (-not (Test-Path $dll)) {
    Add-Type -TypeDefinition $script:ToxeeU32Source -OutputAssembly $dll -ErrorAction Stop
  }
  Add-Type -Path $dll -ErrorAction Stop
}

function Get-ForegroundPid {
  $h = [ToxeeU32]::GetForegroundWindow()
  $p = [uint32]0
  [ToxeeU32]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
  return [int]$p
}

# One line describing where we are and what is in front: session id, the
# foreground window's process, and every top-level window of $ProcessId.
function Get-ForegroundDiag([int]$ProcessId) {
  $fg = Get-ForegroundPid
  $fgName = (Get-Process -Id $fg -ErrorAction SilentlyContinue).ProcessName
  $sid = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
  $target = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  $tsid = if ($target) { $target.SessionId } else { '?' }
  $mwh = if ($target) { $target.MainWindowHandle } else { '?' }
  $wins = [ToxeeU32]::ListWindows([uint32]$ProcessId)
  $focus = if ($target -and $mwh -ne 0) { [ToxeeU32]::FocusOf([IntPtr]$mwh) } else { '?' }
  return "session=$sid fg=$fg($fgName) target=$ProcessId(session=$tsid mwh=$mwh focus=$focus) windows=[$wins]"
}

# Bring the main window of $ProcessId to the real foreground. Returns the name
# of the strategy that worked ('' when none did; the caller treats '' as
# failure). Strategies, cheapest first; each verified via GetForegroundWindow.
function Set-ToxeeForeground([int]$ProcessId, [int]$Retries = 2) {
  $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $proc) { return '' }
  for ($i = 0; $i -lt $Retries; $i++) {
    if ((Get-ForegroundPid) -eq $ProcessId) { return 'already' }
    $proc.Refresh()
    $h = $proc.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 200; continue }
    if ([ToxeeU32]::IsIconic($h)) { [ToxeeU32]::ShowWindow($h, 9) | Out-Null }  # SW_RESTORE
    [ToxeeU32]::SwitchToThisWindow($h, $true)
    Start-Sleep -Milliseconds 120
    if ((Get-ForegroundPid) -eq $ProcessId) { return 'switch' }
    if ([ToxeeU32]::ForegroundViaAttach($h)) { Start-Sleep -Milliseconds 80; return 'attach' }
    if ([ToxeeU32]::ForegroundViaAlt($h)) { Start-Sleep -Milliseconds 80; return 'alt' }
    # Push the current foreground window out of the way, then take over.
    $fgh = [ToxeeU32]::GetForegroundWindow()
    if ($fgh -ne $h -and $fgh -ne [IntPtr]::Zero) {
      [ToxeeU32]::ShowWindow($fgh, 6) | Out-Null   # SW_MINIMIZE
      Start-Sleep -Milliseconds 150
      [ToxeeU32]::SetForegroundWindow($h) | Out-Null
      Start-Sleep -Milliseconds 120
      if ((Get-ForegroundPid) -eq $ProcessId) { return 'minimize-other' }
    }
    $ws = New-Object -ComObject WScript.Shell
    $ws.AppActivate($ProcessId) | Out-Null
    Start-Sleep -Milliseconds 200
    if ((Get-ForegroundPid) -eq $ProcessId) { return 'appactivate' }
  }
  return ''
}

# Named keys for Send-ScanKey (plus any single character, resolved through the
# keyboard layout).
$script:ToxeeVk = @{
  ENTER = 0x0D; RETURN = 0x0D; TAB = 0x09; ESC = 0x1B; ESCAPE = 0x1B; BACKSPACE = 0x08
  DEL = 0x2E; DELETE = 0x2E; HOME = 0x24; END = 0x23; LEFT = 0x25; UP = 0x26; RIGHT = 0x27
  DOWN = 0x28; PGUP = 0x21; PGDN = 0x22; SPACE = 0x20; INS = 0x2D
  F1 = 0x70; F2 = 0x71; F3 = 0x72; F4 = 0x73; F5 = 0x74; F6 = 0x75; F7 = 0x76; F8 = 0x77
  F9 = 0x78; F10 = 0x79; F11 = 0x7A; F12 = 0x7B
}

# Type [Text] as real scan-coded key presses (see ToxeeU32 notes).
function Send-ScanText([string]$Text, [int]$DelayMs = 6) {
  return [ToxeeU32]::SendText($Text, $DelayMs)
}

# Press one key (name from $ToxeeVk or a single character) with optional
# modifiers: any of 'shift','ctrl','alt'.
function Send-ScanKey([string]$Name, [string[]]$Modifiers = @()) {
  $mods = 0
  foreach ($m in $Modifiers) {
    switch ($m.ToLower()) { 'shift' { $mods = $mods -bor 1 } 'ctrl' { $mods = $mods -bor 2 } 'alt' { $mods = $mods -bor 4 } }
  }
  $key = $Name.ToUpper()
  if ($script:ToxeeVk.ContainsKey($key)) { $vk = [uint16]$script:ToxeeVk[$key] }
  elseif ($Name.Length -eq 1) {
    $r = [ToxeeU32]::VkKeyScanW([char]$Name)
    if ($r -eq -1) { throw "Send-ScanKey: no key for '$Name' in this layout" }
    $vk = [uint16]($r -band 0xFF)
    $mods = $mods -bor (($r -shr 8) -band 7)
  } else { throw "Send-ScanKey: unknown key name '$Name'" }
  [ToxeeU32]::Chord($mods, $vk)
}

# Real mouse click at a LOGICAL point of $ProcessId's Flutter view.
function Click-FlutterView([int]$ProcessId, [double]$X, [double]$Y) {
  $h = [IntPtr](Get-Process -Id $ProcessId).MainWindowHandle
  return [ToxeeU32]::ClickView($h, $X, $Y)
}

# Foreground $ProcessId, clear stuck modifiers and put keyboard focus on its
# Flutter view — the preamble every driver input step runs. Throws when the
# window cannot be brought to the real foreground (keys would land elsewhere).
function Enter-ToxeeInput([int]$ProcessId) {
  [ToxeeU32]::ReleaseMods()
  $s = Set-ToxeeForeground -ProcessId $ProcessId
  if (-not $s) { throw ("foreground($ProcessId) failed: " + (Get-ForegroundDiag -ProcessId $ProcessId)) }
  [ToxeeU32]::FocusFlutterView([IntPtr](Get-Process -Id $ProcessId).MainWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 120
  return $s
}
