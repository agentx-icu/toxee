<#
.SYNOPSIS
  Windows twin of restore_fixture_c_pair.sh: restore the paired_for_e2e
  Fixture C A/B disk trees into per-instance support roots.

.DESCRIPTION
  PowerShell-native (no bash/jq dependency) port of the .sh restore. The
  fixture content (profiles/p_<prefix>/tox_profile.tox + account_data/<prefix>/
  chat_history/<friend>.json) is platform-portable plain files; the restored
  accounts are booted by the drivers via l3_boot_existing_account, so no prefs
  seeding is needed. The .sh's macOS plist scrub has no Windows equivalent:
  the group-prefs hygiene keys live in the shared shared_preferences.json,
  which launch_windows_fixture_c_pair.ps1 wipes before every launch anyway.
#>
param(
  [string]$RestoreRoot = $env:TOXEE_FIXTURE_C_RESTORE_ROOT,
  [string]$ReportPath  = $env:TOXEE_FIXTURE_C_RESTORE_REPORT
)
$ErrorActionPreference = "Stop"

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$FixturesDir  = Join-Path $ScriptDir "fixtures"
$ManifestJson = if ($env:TOXEE_FIXTURE_C_MANIFEST) { $env:TOXEE_FIXTURE_C_MANIFEST } else { Join-Path $FixturesDir "paired_for_e2e_manifest.json" }

if (-not $RestoreRoot) { throw "TOXEE_FIXTURE_C_RESTORE_ROOT (or -RestoreRoot) is required on Windows (no container-path default)." }
if (-not $ReportPath)  { $ReportPath = Join-Path $RestoreRoot "fixture_c_pair_restore.json" }
if (-not (Test-Path $ManifestJson)) { throw "manifest missing: $ManifestJson" }

$manifest = Get-Content $ManifestJson -Raw | ConvertFrom-Json
if ("$($manifest.format_version)" -ne "1") { throw "unsupported manifest format_version=$($manifest.format_version)" }
New-Item -ItemType Directory -Force -Path $RestoreRoot | Out-Null

$instances = [ordered]@{}
foreach ($name in @("A", "B")) {
  $data = $manifest.instances.$name
  if (-not $data) { throw "manifest missing instances.$name" }
  $fixtureDir = $data.fixture_dir
  $toxId      = $data.tox_id
  $friendId   = $data.friend_tox_id
  if (-not $fixtureDir -or -not $toxId -or -not $friendId) { throw "manifest instances.$name is incomplete" }
  $prefix = $toxId.Substring(0, 16)
  $src    = Join-Path $FixturesDir $fixtureDir
  $dest   = Join-Path $RestoreRoot $name
  if (-not (Test-Path $src)) { throw "fixture source missing for ${name}: $src" }
  Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Path (Join-Path $src "*") -Destination $dest -Recurse -Force
  $profileFile = Join-Path $dest "profiles\p_$prefix\tox_profile.tox"
  $historyFile = Join-Path $dest "account_data\$prefix\chat_history\$friendId.json"
  if (-not (Test-Path $profileFile)) { throw "$name restore missing profile: $profileFile" }
  if (-not (Test-Path $historyFile)) { throw "$name restore missing chat history: $historyFile" }
  $instances[$name] = [ordered]@{
    tox_id        = $toxId
    nickname      = $data.nickname
    friend_tox_id = $friendId
    support_dir   = $dest
    profile_file  = $profileFile
    history_file  = $historyFile
    restored      = $true
  }
}

$report = [ordered]@{
  format_version = 1
  restored_at    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  manifest       = $ManifestJson
  restore_root   = $RestoreRoot
  instances      = $instances
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
[System.IO.File]::WriteAllText($ReportPath, (($report | ConvertTo-Json -Depth 6) + "`n"),
  (New-Object System.Text.UTF8Encoding($false)))

Write-Host "OK: restored Fixture C paired fixture (windows)"
Write-Host "restore root: $RestoreRoot"
Write-Host "report: $ReportPath"
