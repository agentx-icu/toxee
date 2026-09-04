<#
.SYNOPSIS
  Stop ONE Windows Toxee instance of the A/B pair (relaunch scenarios).

.DESCRIPTION
  Windows twin of stop_toxee_instance.sh. Reads <runtime>\<name>\instance.json
  for the toxee.exe pid and kills its process tree. The instance.json is KEPT
  (unlike the .sh, which removes it): launch_toxee_instance.ps1 re-reads the
  recorded exe / VM port / support dir from it to bring the SAME instance back.
  Best-effort: a missing json / already-dead process is not an error.

  Usage: powershell -ExecutionPolicy Bypass -File stop_toxee_instance.ps1 <A|B>
#>
param([Parameter(Mandatory = $true)] [string]$Name)
$ErrorActionPreference = "Continue"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$RuntimeRoot = if ($env:TOXEE_WINDOWS_RUNTIME_ROOT) { $env:TOXEE_WINDOWS_RUNTIME_ROOT } else { Join-Path $RepoRoot "build\windows_runtime" }
$Json        = Join-Path (Join-Path $RuntimeRoot $Name) "instance.json"
. (Join-Path $ScriptDir "win_instance_identity.ps1")

if (-not (Test-Path $Json)) { Write-Host "OK: nothing to stop for $Name"; exit 0 }
$doc = Get-Content $Json -Raw | ConvertFrom-Json
$procPid = [int]$doc.pid
$proc = Get-ToxeeInstanceProcess $doc
if (-not $proc -and $procPid -gt 0 -and (Get-Process -Id $procPid -ErrorAction SilentlyContinue)) {
  # The recorded pid now belongs to ANOTHER process (pid reuse after toxee
  # exited on its own): never kill it. Forget the pid so a relaunch is not
  # refused by the "still running" preflight.
  Write-Host "WARN: $Name pid $procPid is no longer the launched toxee.exe (pid reused); not killing"
  $doc.pid = 0
  [System.IO.File]::WriteAllText($Json, ($doc | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
  exit 0
}
if ($proc) {
  & taskkill /F /T /PID $procPid 2>$null | Out-Null
  # Wait for the process to actually go away so the relaunch can reuse the
  # fixed VM-service port (a still-exiting process would fail the port preflight).
  for ($i = 0; $i -lt 50; $i++) {
    if (-not (Get-Process -Id $procPid -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 200
  }
}
Write-Host "OK: stopped $Name pid=$procPid"
exit 0
