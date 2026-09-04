<#
.SYNOPSIS
  Run a command INSIDE the Windows console session (session 1) from an SSH
  session (session 0), wait for it, and stream its log — the channel the
  Windows real-UI campaigns need for REAL OS input.

.DESCRIPTION
  An OpenSSH session on Windows lives in session 0: no interactive window
  station, no mapped drives (Y:), and `WScript.Shell.AppActivate` / `SendKeys`
  / `Set-Clipboard` cannot reach the desktop. The console session (the logged-in
  user, `query session` -> "console ... Active") has all of that. This script
  registers a ONE-SHOT interactive scheduled task (`/IT`) that runs the given
  command as the logged-in user in that session, redirecting stdout/stderr to
  -LogPath, then polls until a done-marker appears (or -TimeoutMinutes elapses)
  and tails the log. Exit code = the command's exit code (read from the marker).

  Requirements: the user must be logged in at the VM console (locked is fine as
  long as the session is Active; SendKeys needs the session unlocked). Run
  `query session` to check.

.PARAMETER Command
  PowerShell command text to run in the console session (a script invocation,
  e.g. "dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui
  --real-ui-platform=windows --real-ui-campaign=rui-win-os-input").
.PARAMETER WorkingDirectory
  Directory to `Set-Location` before running -Command (the shim checkout).
.PARAMETER LogPath
  Where the command's combined stdout/stderr lands. Also used for the marker
  (<LogPath>.done) and the generated wrapper script (<LogPath>.ps1).
.PARAMETER EnvFile
  Optional .ps1 dot-sourced inside the console session before -Command (put
  `$env:...` assignments there — PATH, VCPKG_ROOT, TOXEE_WIN_OS_INPUT=1, …).
.PARAMETER TimeoutMinutes
  Max wait. On timeout the task is left running (kill it with `schtasks /End`
  or by pid); exit code 124.
.PARAMETER TaskName
  Scheduled-task name (one task per concurrent run).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\vmtest\win_run_interactive.ps1 `
    -WorkingDirectory C:\vmtest\toxee-win -EnvFile C:\vmtest\env.ps1 `
    -LogPath C:\vmtest\logs\rui-win-os-input.log -TimeoutMinutes 90 `
    -Command "dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-platform=windows --real-ui-campaign=rui-win-os-input"
#>
param(
  [Parameter(Mandatory = $true)] [string]$Command,
  [Parameter(Mandatory = $true)] [string]$LogPath,
  [string]$WorkingDirectory = (Get-Location).Path,
  [string]$EnvFile = "",
  [int]$TimeoutMinutes = 120,
  [string]$TaskName = "toxee_rui_interactive"
)
$ErrorActionPreference = "Continue"

$logDir = Split-Path -Parent $LogPath
if ($logDir) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$marker  = "$LogPath.done"
$wrapper = "$LogPath.ps1"
Remove-Item $marker, $LogPath -ErrorAction SilentlyContinue

# The wrapper runs in the console session. Everything it prints goes to the
# log; the marker carries the command's exit code so the caller can relay it.
$envLine = if ($EnvFile) { ". '$($EnvFile.Replace("'", "''"))'" } else { "" }
@"
`$ErrorActionPreference = 'Continue'
Set-Location '$($WorkingDirectory.Replace("'", "''"))'
$envLine
`$rc = 1
try {
  & { $Command } *>&1 | Out-File -FilePath '$($LogPath.Replace("'", "''"))' -Encoding utf8 -Append
  `$rc = `$LASTEXITCODE
  if (`$null -eq `$rc) { `$rc = 0 }
} catch {
  "WRAPPER EXCEPTION: `$(`$_.Exception.Message)" | Out-File -FilePath '$($LogPath.Replace("'", "''"))' -Encoding utf8 -Append
  `$rc = 1
}
Set-Content -Path '$($marker.Replace("'", "''"))' -Value "`$rc" -Encoding ascii
"@ | Set-Content -Path $wrapper -Encoding utf8

$tr = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$wrapper`""
& schtasks /Create /F /TN $TaskName /SC ONCE /ST 00:00 /IT /TR $tr 2>&1 | Where-Object { $_ -match "SUCCESS|ERROR" } | Write-Host
& schtasks /Run /TN $TaskName 2>&1 | Where-Object { $_ -match "SUCCESS|ERROR" } | Write-Host

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$printed = 0
while ((Get-Date) -lt $deadline) {
  if (Test-Path $marker) { break }
  Start-Sleep -Seconds 5
  # Stream new log lines so an SSH caller sees progress.
  if (Test-Path $LogPath) {
    $lines = @(Get-Content $LogPath -ErrorAction SilentlyContinue)
    if ($lines.Count -gt $printed) {
      $lines[$printed..($lines.Count - 1)] | ForEach-Object { Write-Host $_ }
      $printed = $lines.Count
    }
  }
}
& schtasks /Delete /F /TN $TaskName 2>&1 | Out-Null
if (-not (Test-Path $marker)) {
  Write-Host "[win_run_interactive] TIMEOUT after $TimeoutMinutes min (task may still be running)"
  exit 124
}
if (Test-Path $LogPath) {
  $lines = @(Get-Content $LogPath -ErrorAction SilentlyContinue)
  if ($lines.Count -gt $printed) { $lines[$printed..($lines.Count - 1)] | ForEach-Object { Write-Host $_ } }
}
$rc = [int](Get-Content $marker -ErrorAction SilentlyContinue | Select-Object -First 1)
Write-Host "[win_run_interactive] command exit=$rc log=$LogPath"
exit $rc
