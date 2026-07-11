<#
.SYNOPSIS
  Launch A + B Windows Toxee instances for real-App UI automation, producing the
  pair.json contract the unified runner (fixture_c_unified_runner.dart) consumes.

.DESCRIPTION
  Windows sibling of launch_fixture_c_pair.sh (macOS) / launch_ios_fixture_c_pair.sh
  (iOS). Run the unified runner ON the Windows host with --real-ui-platform=windows;
  it invokes this script to bring up TWO toxee.exe instances on this same host,
  then drives them via the real-UI driver (drive_real_ui_pair.dart) over the local
  VM service. Because the runner, driver, both apps, AND the loopback IRC server all
  live on this one host, the IRC loopback case reaches 127.0.0.1 directly with no
  reverse-forwarding (unlike Android).

  Mechanism (mirrors the macOS direct-launch path):
    * build the app ONCE (`flutter build windows --debug`, with the L3 + skill
      dart-defines baked in), and copy any FFI runtime deps (pthreadVC3.dll,
      libsodium.dll) next to the built exe;
    * launch BOTH instances' toxee.exe directly from that single shared Debug dir
      (NOT per-instance copies: copying broke tim2tox_ffi.dll's transitive dep
      resolution -> LoadLibrary error 126; the build finishes before either
      launch, so the shared read-only exe is never write-locked). Each launch gets
      a FIXED, distinct Dart VM-service port + `disable-service-auth-codes` (so the
      ws URI is deterministically ws://127.0.0.1:<port>/ws) and per-instance
      TOXEE_APP_SUPPORT_DIR / TOXEE_SHARED_PREFS_PREFIX so the two instances do not
      share account/profile/prefs state;
    * probe each VM service to confirm it is live (falling back to grepping the
      app's stdout for the actual URI if the no-auth assumption ever changes).

  Honest limits:
    * paired_for_e2e RESTORE is not wired here yet (the IRC cases this targets are
      no-friend); a restore request fails fast.
    * the irc_join_channel_loopback_live JOIN needs the native libirc_client.dll
      (the C++ in third_party/tim2tox is cross-platform but not yet built/bundled
      for Windows). If a libirc_client.dll is found under build\native-artifacts\
      windows\ it is copied next to each toxee.exe; otherwise a WARN is printed and
      that one scenario cannot complete its live JOIN. irc_join_channel_real_controls
      (pure Dart/Prefs) needs no native lib.
#>
param(
  [switch]$SkipNative,
  [switch]$SkipPubGet
)

# PS 5.1: "Continue", not "Stop" - a benign native stderr line must not abort.
$ErrorActionPreference = "Continue"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$RuntimeRoot = if ($env:TOXEE_WINDOWS_RUNTIME_ROOT) { $env:TOXEE_WINDOWS_RUNTIME_ROOT } else { Join-Path $ScriptDir ".windows_runtime" }
$PairJson    = Join-Path $RuntimeRoot "pair.json"
# Relative (resolved under the Push-Location $RepoRoot below) so `dart run` picks
# up the repo's package config, matching the .sh launchers' proven invocation.
$ProbeDart   = "tool/mcp_test/probe_vm_service.dart"
$McpBinding  = if ($env:MCP_BINDING) { $env:MCP_BINDING } else { "skill" }
$L3Test      = if ($env:TOXEE_L3_TEST) { $env:TOXEE_L3_TEST } else { "true" }
$VmPortA     = if ($env:TOXEE_WINDOWS_VM_PORT_A) { [int]$env:TOXEE_WINDOWS_VM_PORT_A } else { 8201 }
$VmPortB     = if ($env:TOXEE_WINDOWS_VM_PORT_B) { [int]$env:TOXEE_WINDOWS_VM_PORT_B } else { 8202 }
$UriTimeout  = if ($env:TOXEE_WINDOWS_VM_URI_TIMEOUT_SECS) { [int]$env:TOXEE_WINDOWS_VM_URI_TIMEOUT_SECS } else { 90 }
$IrcDllSrc   = Join-Path $RepoRoot "build\native-artifacts\windows\libirc_client.dll"

function Info([string]$m) { Write-Host "[INFO] $m"  -ForegroundColor Green }
function Warn([string]$m) { Write-Host "[WARN] $m"  -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host "[ERROR] $m" -ForegroundColor Red }

function Write-NoBom([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

# paired_for_e2e restore is implemented via restore_fixture_c_pair.ps1 (the
# PowerShell twin of the macOS .sh restore); the fixture trees are portable
# plain files and the drivers boot them via l3_boot_existing_account.
$RestoreMode   = $env:TOXEE_FIXTURE_C_RESTORE
$RestoreRoot   = Join-Path $RuntimeRoot "support"
$RestoreReport = Join-Path $RestoreRoot "fixture_c_pair_restore.json"
if ($RestoreMode -and $RestoreMode -notin @("paired", "paired_for_e2e")) {
  throw "unsupported TOXEE_FIXTURE_C_RESTORE=$RestoreMode (paired|paired_for_e2e)"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "flutter not found on PATH." }
if (-not (Get-Command dart -ErrorAction SilentlyContinue))    { throw "dart not found on PATH." }
if ($VmPortA -eq $VmPortB) { throw "A/B VM-service ports must differ (got $VmPortA)." }

New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
# Kill any stray toxee.exe left by a crashed prior run - both legacy per-instance
# copies (under the runtime root) and the build-dir runner the instances launch
# from now. Otherwise a stale instance would still hold a fixed VM-service port
# (the probe would attach to the wrong instance) AND lock the exe so the rebuild
# below can't overwrite it.
$BuildRunnerParent = Join-Path $RepoRoot "build\windows"
Get-Process toxee -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -and ($_.Path.StartsWith($RuntimeRoot) -or $_.Path.StartsWith($BuildRunnerParent)) } |
  ForEach-Object { & taskkill /F /T /PID $_.Id 2>$null | Out-Null }
Remove-Item -Recurse -Force (Join-Path $RuntimeRoot "A"), (Join-Path $RuntimeRoot "B"), $PairJson -ErrorAction SilentlyContinue

# Clear toxee's shared_preferences so each launch starts from a CLEAN account
# state. The per-instance wipe above clears the PROFILE store (which honors
# TOXEE_APP_SUPPORT_DIR), but savedAccountToxIds + the toxee_a./toxee_b.-prefixed
# prefs live in the SHARED shared_preferences.json under the REAL %APPDATA% (NOT
# the override), so they otherwise survive -> a relaunch finds a saved account
# whose profile was wiped (sc_load_account_fail) and registration flakes. Both
# instances re-register fresh, so removing the shared file is safe here.
Get-Item -Path (Join-Path $env:APPDATA '*\toxee\shared_preferences.json') -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

# ----- Optional paired fixture restore (before launch) ----------------------
if ($RestoreMode) {
  Info "Restoring '$RestoreMode' fixture into $RestoreRoot"
  & (Join-Path $ScriptDir "restore_fixture_c_pair.ps1") -RestoreRoot $RestoreRoot -ReportPath $RestoreReport
  if (-not (Test-Path $RestoreReport)) { throw "fixture restore did not produce $RestoreReport" }
}

# Preflight: the fixed VM-service ports MUST be free, otherwise the deterministic
# ws://127.0.0.1:<port>/ws probe could attach to a FOREIGN Dart VM that happens to
# hold the port (a wrong-instance pair.json). A TcpListener bind is the portable
# "is this port free" probe (no NetTCPIP module dependency).
function Test-PortFree([int]$port) {
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    $listener.Start(); $listener.Stop(); return $true
  } catch { return $false }
}
foreach ($p in @($VmPortA, $VmPortB)) {
  if (-not (Test-PortFree $p)) {
    throw "VM-service port $p is already in use; pick free ports via TOXEE_WINDOWS_VM_PORT_A/B or stop the process holding it (the fixed-port probe must not attach to a foreign VM)."
  }
}

Push-Location $RepoRoot
try {
  $BuildLog = Join-Path $RuntimeRoot "build.log"

  # ----- Bootstrap + native FFI (tim2tox_ffi.dll) --------------------------
  & dart run tool/bootstrap_deps.dart 2>&1 | Out-File -FilePath (Join-Path $RuntimeRoot "bootstrap.log") -Encoding ascii
  if (-not $SkipNative) {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) {
      Info "Building tim2tox Windows FFI (bash tool/ci/build_tim2tox.sh --target windows)..."
      & bash tool/ci/build_tim2tox.sh --target windows 2>&1 | Out-File -FilePath (Join-Path $RuntimeRoot "native_build.log") -Encoding ascii
      if ($LASTEXITCODE -ne 0) { Warn "Native FFI build returned non-zero; the flutter build will fail explicitly if tim2tox_ffi.dll is genuinely missing." }
    } else {
      Warn "bash not found; skipping native FFI build. Ensure tim2tox_ffi.dll already exists or pass -SkipNative after building it."
    }
  }

  if (-not $SkipPubGet) {
    Info "flutter pub get..."
    & flutter pub get 2>&1 | Out-File -FilePath $BuildLog -Encoding ascii
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed; see $BuildLog" }
  }

  # ----- Build the app ONCE (defines baked in) -----------------------------
  Info "flutter build windows --debug (MCP_BINDING=$McpBinding, TOXEE_L3_TEST=$L3Test)..."
  & flutter build windows --debug `
      --dart-define=FLUTTER_BUILD_MODE=debug `
      --dart-define=MCP_BINDING=$McpBinding `
      --dart-define=TOXEE_L3_TEST=$L3Test 2>&1 | Out-File -FilePath $BuildLog -Append -Encoding ascii
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed; see $BuildLog" }

  # Locate the Debug runner dir (build\windows\<arch>\runner\Debug) holding toxee.exe.
  $exe = Get-ChildItem -Path (Join-Path $RepoRoot "build\windows") -Recurse -Filter "toxee.exe" -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -match "\\runner\\Debug\\toxee.exe$" } | Select-Object -First 1
  if (-not $exe) { throw "Built toxee.exe not found under build\windows\**\runner\Debug\. See $BuildLog" }
  $debugDir = $exe.Directory.FullName
  Info "Built runner dir: $debugDir"

  # tim2tox_ffi.dll has runtime DLL deps (pthreadVC3.dll, libsodium.dll) that sit
  # next to the BUILT FFI but that the windows CMake install does not all place
  # beside toxee.exe. `flutter run` resolves them via PATH; a direct Start-Process
  # launch does not, so DynamicLibrary.open fails with "module not found" (126).
  # Copy any missing ones next to the exe so the FFI loads under direct launch.
  $ffiDepDirs = @(
    (Join-Path $RepoRoot "build\native-artifacts\windows"),
    (Join-Path $RepoRoot "third_party\tim2tox\build\ci-windows\ffi\Release"),
    (Join-Path $RepoRoot "third_party\tim2tox\build\ffi")
  )
  foreach ($dep in @("pthreadVC3.dll", "libsodium.dll")) {
    if (Test-Path (Join-Path $debugDir $dep)) { continue }
    foreach ($d in $ffiDepDirs) {
      $src = Join-Path $d $dep
      if (Test-Path $src) { Copy-Item -Force $src (Join-Path $debugDir $dep); Info "bundled FFI dep $dep"; break }
    }
  }
  # OpenSSL runtime for libirc_client.dll (captured next to it by
  # `build_tim2tox.sh --target windows --with-irc`; a missing import DLL makes
  # the IRC library fail to load with error 126).
  Get-ChildItem -Path (Join-Path $RepoRoot "build\native-artifacts\windows") `
      -Filter "lib*-3*.dll" -ErrorAction SilentlyContinue |
    ForEach-Object { Copy-Item -Force $_.FullName (Join-Path $debugDir $_.Name); Info "bundled IRC dep $($_.Name)" }

  if (-not (Test-Path $IrcDllSrc)) {
    Warn "libirc_client.dll not found at $IrcDllSrc - irc_join_channel_loopback_live cannot complete its live JOIN until it is built/bundled (irc_join_channel_real_controls is unaffected)."
  }

  function Start-ToxeeInstance([string]$name, [int]$vmPort) {
    $instDir   = Join-Path $RuntimeRoot $name
    # A restored launch points the instance at the restored fixture tree so
    # l3_boot_existing_account finds the profile + history on first boot.
    $supportDir = if ($RestoreMode) { Join-Path $RestoreRoot $name } else { Join-Path $instDir "app_support" }
    $stdio     = Join-Path $instDir "toxee_stdio.log"
    $stdioErr  = Join-Path $instDir "toxee_stdio.err"
    New-Item -ItemType Directory -Force -Path $supportDir | Out-Null
    # Launch from the ORIGINAL built Debug dir, NOT a per-instance copy. Copying
    # the runner dir broke tim2tox_ffi.dll's transitive dependency resolution
    # (LoadLibrary error 126 from the copy), whereas the FFI loads cleanly from the
    # build dir. We build ONCE up front and never rebuild between A and B, so the
    # two instances sharing the read-only exe + dlls is safe; per-instance state is
    # isolated via the env below, and the VM ports differ. An optional native IRC
    # lib (if built) is dropped next to the shared exe so both instances see it.
    if (Test-Path $IrcDllSrc) { Copy-Item -Force $IrcDllSrc (Join-Path $debugDir "libirc_client.dll") }
    Set-Content -Path $stdio -Value "" -Encoding ascii
    Set-Content -Path $stdioErr -Value "" -Encoding ascii

    # Per-instance runtime env (inherited by the child at spawn). The fixed VM
    # port + disabled auth codes make the ws URI deterministic; the app-support /
    # prefs-prefix overrides isolate the two instances' account/profile/prefs.
    $env:FLUTTER_ENGINE_SWITCHES   = "2"
    $env:FLUTTER_ENGINE_SWITCH_1   = "vm-service-port=$vmPort"
    $env:FLUTTER_ENGINE_SWITCH_2   = "disable-service-auth-codes"
    $env:TOXEE_APP_SUPPORT_DIR     = $supportDir
    $env:TOXEE_SHARED_PREFS_PREFIX = "toxee_$($name.ToLower())."
    $env:TOXEE_LOG_DIR             = $instDir
    $env:TOXEE_TCCF_GLOBAL_SUBDIR  = "multi_instance/$name/tccfglobal"

    $proc = Start-Process -FilePath (Join-Path $debugDir "toxee.exe") `
              -RedirectStandardOutput $stdio -RedirectStandardError $stdioErr `
              -PassThru -WindowStyle Normal
    return @{ name = $name; pid = $proc.Id; vmPort = $vmPort; stdio = $stdio; stdioErr = $stdioErr; instDir = $instDir }
  }

  function Resolve-WsUri($inst) {
    # Strategy 1: with disable-service-auth-codes the URI carries no token, so the
    # ws URI is deterministic. Probe it.
    $candidate = "ws://127.0.0.1:$($inst.vmPort)/ws"
    $deadline = (Get-Date).AddSeconds($UriTimeout)
    while ((Get-Date) -lt $deadline) {
      if (-not (Get-Process -Id $inst.pid -ErrorAction SilentlyContinue)) {
        throw "$($inst.name) toxee.exe exited before the VM service came up; see $($inst.stdio) / $($inst.stdioErr)"
      }
      & dart run $ProbeDart $candidate 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { return $candidate }
      # Strategy 2 fallback: grep stdout/stderr for the actual URI (in case a
      # future engine keeps the auth-code path segment).
      $m = Select-String -Path $inst.stdio, $inst.stdioErr -Pattern "http://127\.0\.0\.1:$($inst.vmPort)(/[A-Za-z0-9_=-]+)?/?" -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($m) {
        $http = $m.Matches[0].Value.TrimEnd('/')
        $ws = ($http -replace '^http:', 'ws:') + "/ws"
        & dart run $ProbeDart $ws 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $ws }
      }
      Start-Sleep -Seconds 1
    }
    throw "$($inst.name) VM service did not become reachable within ${UriTimeout}s on port $($inst.vmPort); see $($inst.stdio) / $($inst.stdioErr)"
  }

  function Write-InstanceJson($inst, [string]$wsUri) {
    $vmUri = ($wsUri -replace '^ws:', 'http:') -replace '/ws$', ''
    $doc = [ordered]@{
      format_version        = 1
      instance_name         = $inst.name
      pid                   = $inst.pid
      home_override_dir     = $inst.instDir
      stdio_log             = $inst.stdio
      vm_uri                = $vmUri
      ws_uri                = $wsUri
      app_support_log_exists = $false
    }
    Write-NoBom (Join-Path $inst.instDir "instance.json") ($doc | ConvertTo-Json -Depth 5)
  }

  # Launch A then B (sequential; both run from the single shared Debug dir -
  # isolation is via the per-instance env + distinct VM ports, not the exe path).
  $a = Start-ToxeeInstance "A" $VmPortA
  $aWs = Resolve-WsUri $a
  Write-InstanceJson $a $aWs
  Info "A pid=$($a.pid) ws_uri=$aWs"

  $b = Start-ToxeeInstance "B" $VmPortB
  $bWs = Resolve-WsUri $b
  Write-InstanceJson $b $bWs
  Info "B pid=$($b.pid) ws_uri=$bWs"

  # ----- pair.json (same schema as the macOS/iOS launchers) ----------------
  $pair = [ordered]@{
    format_version  = 1
    platform        = "windows"
    instances       = [ordered]@{
      A = (Get-Content (Join-Path $a.instDir "instance.json") -Raw | ConvertFrom-Json)
      B = (Get-Content (Join-Path $b.instDir "instance.json") -Raw | ConvertFrom-Json)
    }
    fixture_restore = [ordered]@{
      mode     = $(if ($RestoreMode) { $RestoreMode } else { $null })
      report   = $(if ($RestoreMode -and (Test-Path $RestoreReport)) { $RestoreReport } else { $null })
      restored = $(if ($RestoreMode -and (Test-Path $RestoreReport)) { Get-Content $RestoreReport -Raw | ConvertFrom-Json } else { $null })
    }
    checks          = [ordered]@{
      distinct_pids    = ($a.pid -ne $b.pid)
      distinct_ws_uris = ($aWs -ne $bWs)
      distinct_vm_ports = ($VmPortA -ne $VmPortB)
    }
  }
  Write-NoBom $PairJson ($pair | ConvertTo-Json -Depth 8)

  Write-Host ""
  Info "OK: launched Windows Fixture C pair"
  Info "pair json: $PairJson"
  Info "A ws_uri: $aWs"
  Info "B ws_uri: $bWs"
}
catch {
  # A partial launch (e.g. A came up, B failed) would leak the running A. Tear
  # the pair down before re-raising so a stray instance doesn't hold a port.
  Warn "launch failed: $($_.Exception.Message) - tearing down any partial pair"
  & (Join-Path $ScriptDir "stop_windows_fixture_c_pair.ps1") 2>$null | Out-Null
  throw
}
finally {
  Pop-Location
}
