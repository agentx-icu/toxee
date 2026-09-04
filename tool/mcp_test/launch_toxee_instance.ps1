<#
.SYNOPSIS
  Relaunch ONE Windows Toxee instance of the A/B pair (relaunch scenarios).

.DESCRIPTION
  Windows twin of launch_toxee_instance.sh, used by the real-UI relaunch cases
  (sweep_p1_relaunch / presence_dot_relaunch) after stop_toxee_instance.ps1.
  It does NOT build and does NOT wipe state: it re-reads the instance's
  recorded contract from <runtime>\<name>\instance.json (exe, fixed VM-service
  port, per-instance support dir, TCP-only topology — written by
  launch_windows_fixture_c_pair.ps1) and starts the same toxee.exe with the
  same environment, so the relaunched process autologs into the account the
  stopped one owned. Rewrites instance.json with the new pid / ws_uri.

  Usage: powershell -ExecutionPolicy Bypass -File launch_toxee_instance.ps1 <A|B>
#>
param([Parameter(Mandatory = $true)] [string]$Name)
$ErrorActionPreference = "Continue"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$RuntimeRoot = if ($env:TOXEE_WINDOWS_RUNTIME_ROOT) { $env:TOXEE_WINDOWS_RUNTIME_ROOT } else { Join-Path $RepoRoot "build\windows_runtime" }
$InstDir     = Join-Path $RuntimeRoot $Name
$Json        = Join-Path $InstDir "instance.json"
$ProbeDart   = "tool/mcp_test/probe_vm_service.dart"
$UriTimeout  = if ($env:TOXEE_WINDOWS_VM_URI_TIMEOUT_SECS) { [int]$env:TOXEE_WINDOWS_VM_URI_TIMEOUT_SECS } else { 90 }

function Write-NoBom([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Json)) { throw "launch_toxee_instance.ps1: $Json missing - the pair launcher must have run first" }
$doc = Get-Content $Json -Raw | ConvertFrom-Json
$exe        = [string]$doc.exe
$vmPort     = [int]$doc.vm_port
$supportDir = [string]$doc.support_dir
if (-not $exe -or -not (Test-Path $exe)) { throw "launch_toxee_instance.ps1: recorded exe missing: '$exe'" }
if ($vmPort -le 0) { throw "launch_toxee_instance.ps1: recorded vm_port missing in $Json" }
if (-not $supportDir) { throw "launch_toxee_instance.ps1: recorded support_dir missing in $Json" }
. (Join-Path $ScriptDir "win_instance_identity.ps1")
# Identity-checked: a reused pid (toxee exited on its own) must not block the relaunch.
if (Get-ToxeeInstanceProcess $doc) {
  throw "launch_toxee_instance.ps1: $Name pid $($doc.pid) is still running - stop it first"
}

$stdio    = Join-Path $InstDir "toxee_stdio.log"
$stdioErr = Join-Path $InstDir "toxee_stdio.err"
New-Item -ItemType Directory -Force -Path $supportDir | Out-Null
Set-Content -Path $stdio -Value "" -Encoding ascii
Set-Content -Path $stdioErr -Value "" -Encoding ascii

# Same per-instance env the pair launcher used (see launch_windows_fixture_c_pair.ps1).
$env:FLUTTER_ENGINE_SWITCHES   = "2"
$env:FLUTTER_ENGINE_SWITCH_1   = "vm-service-port=$vmPort"
$env:FLUTTER_ENGINE_SWITCH_2   = "disable-service-auth-codes"
$env:TOXEE_APP_SUPPORT_DIR     = $supportDir
$env:TOXEE_SHARED_PREFS_PREFIX = "toxee_$($Name.ToLower())."
$env:TOXEE_LOG_DIR             = $InstDir
$env:TOXEE_TCCF_GLOBAL_SUBDIR  = "multi_instance/$Name/tccfglobal"
if ([bool]$doc.tcp_only) {
  $env:TOX_FORCE_TCP_ONLY = "1"
  if ([string]$doc.tcp_relay_port) { $env:TOX_TCP_RELAY_PORT = [string]$doc.tcp_relay_port } else { Remove-Item Env:\TOX_TCP_RELAY_PORT -ErrorAction SilentlyContinue }
} else {
  Remove-Item Env:\TOX_FORCE_TCP_ONLY, Env:\TOX_TCP_RELAY_PORT -ErrorAction SilentlyContinue
}

Push-Location $RepoRoot
try {
  $proc = Start-Process -FilePath $exe -RedirectStandardOutput $stdio -RedirectStandardError $stdioErr -PassThru -WindowStyle Normal
  $candidate = "ws://127.0.0.1:$vmPort/ws"
  $deadline = (Get-Date).AddSeconds($UriTimeout)
  $ws = $null
  while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
      throw "$Name toxee.exe exited before the VM service came up; see $stdio / $stdioErr"
    }
    & dart run $ProbeDart $candidate 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ws = $candidate; break }
    Start-Sleep -Seconds 1
  }
  if (-not $ws) { throw "$Name VM service did not become reachable within ${UriTimeout}s on port $vmPort" }
  $doc.pid = $proc.Id
  $doc | Add-Member -NotePropertyName start_time -NotePropertyValue (Get-ProcessStartTimeIso $proc.Id) -Force
  $doc.ws_uri = $ws
  $doc.vm_uri = "http://127.0.0.1:$vmPort"
  Write-NoBom $Json ($doc | ConvertTo-Json -Depth 5)
  Write-Host "OK: relaunched $Name pid=$($proc.Id) ws_uri=$ws"
}
finally {
  Pop-Location
}
