#!/usr/bin/env pwsh
# Run the real-app-startup integration smokes (integration_test/*_test.dart) on
# Windows desktop, ONE file per `flutter test` invocation.
#
# Usage (from anywhere):
#   powershell -ExecutionPolicy Bypass -File tool\ci\run_windows_smokes.ps1
#   pwsh tool/ci/run_windows_smokes.ps1 -Device windows
#
# ── WHY one-invocation-per-file (not `flutter test integration_test/`) ────────
#
# Each smoke builds a real toxee.exe and launches it. At startup the UIKit
# global cache (`TencentCloudChatCacheGlobal.init`) opens a Hive box under
# `getApplicationDocumentsDirectory()`. The smokes sandbox path_provider with
# `setMockMethodCallHandler('plugins.flutter.io/path_provider')` so the box
# lands in a per-test temp dir — but on Windows that mock is a NO-OP, because
# `path_provider_windows` is an FFI plugin (win32 SHGetKnownFolderPath) with no
# MethodChannel. So on Windows the box escapes the sandbox to the real Documents
# folder with a CONSTANT name (`TCCFGLOBAL-<md5(name)>`).
#
# Under Parallels Desktop the guest's Documents folder is a Mac shared folder
# (prl_fs / "\\Mac\Home\Documents"), a network filesystem whose file lock is not
# released before the next sequential app process launches. So a batched
# `flutter test fileA fileB ...` passes the FIRST file but fails every later one
# with "Unable to start the app on the device" (the new toxee.exe cannot open
# the still-locked global box and dies before the test driver attaches).
#
# Fix: run each file in its own `flutter test` process AND give each launch a
# unique `TOXEE_TCCF_GLOBAL_SUBDIR` (the fork's existing per-instance isolation
# hook, see tencent_cloud_chat_cache_global.dart). Each launch then opens its
# own box directory => no shared lock => all smokes green. A stray-process kill
# + short settle between runs guards against a lingering toxee.exe.
#
# `login_page_states_harness.dart` is intentionally NOT matched (no `_test.dart`
# suffix): it is a shared harness with no `main()`, not a runnable test.

param(
  [string]$Device = "windows"
)

# NOTE: do NOT use `Stop` here. `flutter test` writes benign warnings (Nuget,
# l10n untranslated-message counts, the CMake tim2tox_ffi.dll WARNING) to
# stderr; under Windows PowerShell 5.1 `Stop` promotes a native command's first
# stderr line to a TERMINATING error, which would abort the runner before any
# test runs. We gate purely on $LASTEXITCODE instead.
$ErrorActionPreference = "Continue"

# tool/ci/<this script>  ->  repo root is two levels up.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repoRoot

$files = Get-ChildItem -Path "integration_test" -Filter "*_test.dart" -File | Sort-Object Name
if ($files.Count -eq 0) {
  Write-Error "No integration_test/*_test.dart files found under $repoRoot"
  exit 2
}

$pass = 0
$fail = 0
$failed = @()

foreach ($f in $files) {
  $rel  = "integration_test/" + $f.Name
  $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)

  # Isolate this launch's global Hive box so sequential runs never share a lock.
  $env:TOXEE_TCCF_GLOBAL_SUBDIR = "win_smoke/$name"

  # Defend against a lingering host process holding the previous box open.
  Get-Process toxee -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2

  Write-Host "===== RUN $rel  (TOXEE_TCCF_GLOBAL_SUBDIR=$($env:TOXEE_TCCF_GLOBAL_SUBDIR)) ====="
  # 2>&1 folds flutter's stderr warnings into the success stream so they are
  # captured in the runner's own output and never surface as PS error records.
  & flutter test $rel -d $Device --reporter expanded 2>&1
  if ($LASTEXITCODE -eq 0) {
    $pass++
    Write-Host "RESULT $rel = PASS"
  } else {
    $fail++
    $failed += $rel
    Write-Host "RESULT $rel = FAIL ($LASTEXITCODE)"
  }
}

Remove-Item Env:\TOXEE_TCCF_GLOBAL_SUBDIR -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== WINDOWS SMOKE SUMMARY: pass=$pass fail=$fail ==="
if ($fail -gt 0) {
  Write-Host ("FAILED:`n  " + ($failed -join "`n  "))
  exit 1
}
exit 0
