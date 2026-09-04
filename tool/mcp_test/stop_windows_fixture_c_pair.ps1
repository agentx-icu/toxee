<#
.SYNOPSIS
  Stop the A/B Windows pair launched by launch_windows_fixture_c_pair.ps1.

.DESCRIPTION
  Reads each instance.json for its toxee.exe pid and taskkills the process tree,
  then removes pair.json. Best-effort: a missing pid / already-dead process is
  not an error.
#>
$ErrorActionPreference = "Continue"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$RuntimeRoot = if ($env:TOXEE_WINDOWS_RUNTIME_ROOT) { $env:TOXEE_WINDOWS_RUNTIME_ROOT } else { Join-Path $RepoRoot "build\windows_runtime" }
$PairJson    = Join-Path $RuntimeRoot "pair.json"
$BuildRunnerParent = Join-Path $RepoRoot "build\windows"

. (Join-Path $ScriptDir "win_instance_identity.ps1")

function Stop-ToxeeInstance([string]$name) {
  $json = Join-Path (Join-Path $RuntimeRoot $name) "instance.json"
  if (Test-Path $json) {
    try {
      # Identity-checked (exe + start time): a reused pid is never killed.
      $proc = Get-ToxeeInstanceProcess (Get-Content $json -Raw | ConvertFrom-Json)
      if ($proc) {
        & taskkill /F /T /PID $proc.Id 2>$null | Out-Null
      }
    } catch {
      # best-effort
    }
  }
}

Stop-ToxeeInstance "B"
Stop-ToxeeInstance "A"
# Backstop: any stray toxee.exe launched from this runtime root (legacy copies)
# OR from the build-dir runner the instances launch from now.
Get-Process toxee -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -and ($_.Path.StartsWith($RuntimeRoot) -or $_.Path.StartsWith($BuildRunnerParent)) } |
  ForEach-Object { & taskkill /F /T /PID $_.Id 2>$null | Out-Null }

Remove-Item $PairJson -ErrorAction SilentlyContinue
Write-Host "[INFO] OK: stopped Windows Fixture C pair"
