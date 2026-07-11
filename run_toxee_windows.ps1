<#
.SYNOPSIS
  Build + launch ONE debug Toxee Windows instance with the L3 test surface and
  surface its Dart VM service URI for the L3 MCP harness.

.DESCRIPTION
  Windows sibling of run_toxee.sh (macOS) / run_toxee_linux.sh / run_toxee_ios.sh.
  The L3 runner (tool/mcp_test/run_l3_scenarios.dart) is platform-agnostic - it
  attaches to ANY reachable VM service whose app was built with
  --dart-define=TOXEE_L3_TEST=true. The only thing missing for Windows was a
  launcher that builds with that define and writes the ws URI to the known
  location (build\vm_service_uri.txt). This is that launcher.

  The Windows desktop CMake (windows/CMakeLists.txt) already installs
  tim2tox_ffi.dll + libsodium.dll next to the runner, so `flutter run -d windows`
  produces a working, FFI-loaded binary. We use `flutter run` (not a direct
  toxee.exe launch) because the flutter tool reliably announces the VM service
  URI regardless of the GUI-subsystem console-attach quirks of a raw launch.

.PARAMETER Mode
  Flutter build mode. debug only: kDebugMode tree-shakes the L3 tool surface out
  of profile/release (lib/ui/testing/l3_debug_tools.dart), so profile/release
  builds would launch fine but every L3 tool call would fail.

.PARAMETER SkipNative
  Skip the tim2tox_ffi.dll native build (assume it is already present).

.PARAMETER SkipPubGet
  Skip `flutter pub get`.

.PARAMETER RunL3
  After the URI is captured, run the hermetic L3 partition (--class=l3-gate)
  against it and tear the app down. Without -RunL3 the app is left running and
  you attach the suite yourself.

.PARAMETER L3Extra
  Remaining args are forwarded to run_l3_scenarios.dart (only with -RunL3).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File run_toxee_windows.ps1 -RunL3

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File run_toxee_windows.ps1
  # then, in the repo:
  #   dart run tool/mcp_test/run_l3_scenarios.dart (Get-Content build\vm_service_uri.txt) --class=l3-gate
  #   taskkill /F /T /PID (Get-Content build\toxee_windows_flutter.pid)
#>
param(
  [ValidateSet("debug")] [string]$Mode = "debug",
  [switch]$SkipNative,
  [switch]$SkipPubGet,
  [switch]$RunL3,
  [Parameter(ValueFromRemainingArguments = $true)] $L3Extra
)

# NB: "Continue", not "Stop". Under Stop, PowerShell 5.1 promotes ANY native
# command's stderr line into a terminating error — so a harmless best-effort
# warning (e.g. bootstrap_deps.dart printing "not a git repository" on a non-git
# checkout) would abort the launcher. Control flow here uses explicit `throw`
# (which always terminates) and $LASTEXITCODE checks instead.
$ErrorActionPreference = "Continue"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir     = $ScriptDir
$BuildDir   = Join-Path $AppDir "build"
$StdioLog   = Join-Path $BuildDir "toxee_windows_stdio.log"
$VmUriFile  = Join-Path $BuildDir "vm_service_uri.txt"
$PidFile    = Join-Path $BuildDir "toxee_windows_flutter.pid"

$McpBinding = if ($env:MCP_BINDING) { $env:MCP_BINDING } else { "skill" }
$L3Test     = if ($env:TOXEE_L3_TEST) { $env:TOXEE_L3_TEST } else { "true" }
$TimeoutSecs = if ($env:TOXEE_WINDOWS_VM_URI_TIMEOUT_SECS) { [int]$env:TOXEE_WINDOWS_VM_URI_TIMEOUT_SECS } else { 360 }

if ($McpBinding -notin @("skill", "marionette", "stock")) {
  throw "Invalid MCP_BINDING='$McpBinding'. Allowed: skill|marionette|stock."
}

function Write-NoBom([string]$Path, [string]$Text) {
  # PowerShell 5.1 Out-File defaults to UTF-16; the Unix-side readers expect
  # plain ASCII/UTF-8 with no BOM. Write bytes directly.
  [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Info([string]$m)  { Write-Host "[INFO] $m"  -ForegroundColor Green }
function Warn([string]$m)  { Write-Host "[WARN] $m"  -ForegroundColor Yellow }
function Fail([string]$m)  { Write-Host "[ERROR] $m" -ForegroundColor Red }

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "flutter not found on PATH." }
if (-not (Get-Command dart -ErrorAction SilentlyContinue))    { throw "dart not found on PATH." }
if (-not (Test-Path (Join-Path $AppDir "pubspec.yaml")))      { throw "Flutter app not found: $AppDir" }

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$BootstrapLog = Join-Path $BuildDir "bootstrap.log"
$NativeLog    = Join-Path $BuildDir "native_build_windows.log"
$PubGetLog    = Join-Path $BuildDir "flutter_windows_build.log"
Push-Location $AppDir
try {
  # ----- Bootstrap + native FFI --------------------------------------
  # (PS 5.1 cannot redirect to a parenthesized expression, so log paths are
  #  precomputed variables and merged streams are piped to Out-File.)
  $tpLink = (Get-Item (Join-Path $AppDir "third_party") -ErrorAction SilentlyContinue).LinkType
  if ($tpLink) {
    # Share-shim checkout: third_party symlinks into the host share — the full
    # bootstrap could re-vendor/patch the shared worktree. Validate only, loudly.
    Info "Shim checkout detected - bootstrap offline check only"
    & dart tool/bootstrap_deps.dart --offline-check-only 2>&1 | Out-File -FilePath $BootstrapLog -Encoding ascii
    if ($LASTEXITCODE -ne 0) { throw "bootstrap offline check failed; see $BootstrapLog" }
  } else {
    & dart run tool/bootstrap_deps.dart 2>&1 | Out-File -FilePath $BootstrapLog -Encoding ascii
  }

  if (-not $SkipNative) {
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash) {
      Info "Building tim2tox Windows FFI (bash tool/ci/build_tim2tox.sh --target windows)..."
      & bash tool/ci/build_tim2tox.sh --target windows 2>&1 | Out-File -FilePath $NativeLog -Encoding ascii
      if ($LASTEXITCODE -ne 0) {
        Warn "Native FFI build reported a non-zero exit; continuing - flutter build will"
        Warn "fail explicitly if tim2tox_ffi.dll is genuinely missing. See build\native_build_windows.log"
      }
    } else {
      Warn "bash not found; skipping native FFI build (tool/ci/build_tim2tox.sh is bash-based)."
      Warn "Ensure tim2tox_ffi.dll already exists, or run the build under Git Bash, then re-run with -SkipNative."
    }
  }

  if (-not $SkipPubGet) {
    Info "Running flutter pub get..."
    & flutter pub get 2>&1 | Out-File -FilePath $PubGetLog -Encoding ascii
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed; see $PubGetLog" }
  }

  # ----- Launch via `flutter run -d windows` -------------------------
  $StdioErr = "$StdioLog.err"
  Remove-Item $VmUriFile, $PidFile -ErrorAction SilentlyContinue
  Set-Content -Path $StdioLog -Value "" -Encoding ascii
  Set-Content -Path $StdioErr -Value "" -Encoding ascii

  $flutterCmd = (Get-Command flutter).Source   # full path to flutter.bat
  # We launch cmd.exe (a real executable, so Start-Process redirection works)
  # which in turn runs flutter.bat. Passing the args as an ARRAY lets
  # Start-Process quote each element correctly; using its own
  # -RedirectStandardOutput/-Error (NOT a manual `>` inside the command) avoids
  # the PS 5.1 pitfall where a single space-containing command string gets
  # re-quoted and the redirection is lost. stdout/stderr MUST be separate files.
  $procArgs = @("/c", $flutterCmd,
    "run", "-d", "windows", "--$Mode",
    "--dart-define=FLUTTER_BUILD_MODE=$Mode",
    "--dart-define=MCP_BINDING=$McpBinding",
    "--dart-define=TOXEE_L3_TEST=$L3Test"
  )
  Info "Launching Windows app (flutter run -d windows, $Mode, MCP_BINDING=$McpBinding, TOXEE_L3_TEST=$L3Test)..."
  $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $procArgs `
            -RedirectStandardOutput $StdioLog -RedirectStandardError $StdioErr `
            -PassThru -WindowStyle Hidden
  Write-NoBom $PidFile ([string]$proc.Id)

  # ----- Capture the Dart VM service URI -----------------------------
  # flutter prints "A Dart VM Service ... is available at: http://127.0.0.1:.../"
  # to stdout, but grep both streams to be safe.
  $uriRegex = 'http://127\.0\.0\.1:\d+(/[A-Za-z0-9_=-]+)?/?'
  $deadline = (Get-Date).AddSeconds($TimeoutSecs)
  $vmUri = $null
  while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { throw "flutter run exited before the VM service URI appeared; see $StdioLog / $StdioErr" }
    $m = Select-String -Path $StdioLog, $StdioErr -Pattern $uriRegex -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m) { $vmUri = $m.Matches[0].Value; break }
    Start-Sleep -Seconds 1
  }
  if (-not $vmUri) { throw "Timed out after ${TimeoutSecs}s waiting for the VM service URI; see $StdioLog / $StdioErr" }

  $vmUri = $vmUri.TrimEnd('/')
  $wsUri = ($vmUri -replace '^http:', 'ws:') + "/ws"
  Write-NoBom $VmUriFile "$wsUri`n"

  Write-Host ""
  Info "VM Service: $vmUri/"
  Info "WS URI:     $wsUri  ->  $VmUriFile"
  Info "App pid (cmd/flutter run): $($proc.Id)  ->  $PidFile"

  if ($RunL3) {
    Write-Host ""
    # Fresh-state hosts have no seeded account, so the session preflight
    # (seeded echo conversation) fails before any gate runs. The register
    # driver is idempotent (skips when the session is already ready).
    Info "Ensuring L3 seed account + echo conversation (idempotent)..."
    & dart run tool/mcp_test/drive_l3_register.dart $wsUri echo_live_test --seed-echo
    if ($LASTEXITCODE -ne 0) { Warn "L3 register/seed step failed - the session preflight will likely fail." }
    Info "Running hermetic L3 partition (--class=l3-gate)..."
    # --skip=L3-self-id: bound to the on-disk echo_seeded fixture account's
    # exact toxId; a register-seeded fresh host can never satisfy it.
    $l3Args = @("run", "tool/mcp_test/run_l3_scenarios.dart", $wsUri, "--class=l3-gate", "--skip=L3-self-id")
    if ($L3Extra) { $l3Args += $L3Extra }
    & dart @l3Args
    $rc = $LASTEXITCODE
    Info "Tearing down Windows app (pid $($proc.Id))..."
    & taskkill /F /T /PID $proc.Id 2>$null | Out-Null
    exit $rc
  }

  Write-Host ""
  Info "App left running. Attach the L3 suite with:"
  Write-Host "    dart run tool/mcp_test/run_l3_scenarios.dart (Get-Content $VmUriFile) --class=l3-gate"
  Info "Stop it with:  taskkill /F /T /PID (Get-Content $PidFile)"
}
finally {
  Pop-Location
}
