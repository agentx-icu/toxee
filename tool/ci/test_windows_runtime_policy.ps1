$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'assert_windows_architecture.ps1')
. (Join-Path $PSScriptRoot 'assert_windows_runtime_modules.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('toxee-runtime-' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
$global:ToxeeFixtureVendorValid = $true
$global:ToxeeFixturePublisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US'
# Policy-only fixtures. Real Microsoft signatures are verified separately in
# both Windows package jobs; these synthetic PE bytes are never distributable.
function Get-AuthenticodeSignature {
  param([string]$LiteralPath)
  return @{ Status = $(if ($global:ToxeeFixtureVendorValid) { 'Valid' } else { 'NotSigned' });
    SignerCertificate = @{ Subject = $global:ToxeeFixturePublisher; Thumbprint = 'FIXTURE' } }
}
function Write-Pe([string]$Path, [uint16]$Machine) {
  $bytes = [byte[]]::new(256)
  $bytes[0] = 0x4d; $bytes[1] = 0x5a
  [BitConverter]::GetBytes([uint32]128).CopyTo($bytes, 60)
  $bytes[128] = 0x50; $bytes[129] = 0x45
  [BitConverter]::GetBytes($Machine).CopyTo($bytes, 132)
  [IO.File]::WriteAllBytes($Path, $bytes)
}
function Assert-Rejected([scriptblock]$Operation) {
  try { & $Operation } catch { return }
  throw 'Expected runtime policy rejection'
}
try {
  $crt = Join-Path $root 'msvcp140.dll'
  Write-Pe $crt 0xaa64
  $report = Join-Path $root 'policy.json'
  & (Join-Path $PSScriptRoot 'verify_windows_runtime.ps1') -InputPath $crt -Architecture arm64 -Report $report
  if (-not (Test-Path $report)) { throw 'Single-file signature/architecture evidence was not written' }
  Assert-Rejected { & (Join-Path $PSScriptRoot 'verify_windows_runtime.ps1') -InputPath $crt -Architecture x64 }
  $global:ToxeeFixtureVendorValid = $false
  Assert-Rejected { & (Join-Path $PSScriptRoot 'verify_windows_runtime.ps1') -InputPath $crt -Architecture arm64 }
  $global:ToxeeFixtureVendorValid = $true
  $global:ToxeeFixturePublisher = 'CN=Other Publisher'
  Assert-Rejected { & (Join-Path $PSScriptRoot 'verify_windows_runtime.ps1') -InputPath $crt -Architecture arm64 }
  $global:ToxeeFixturePublisher = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US'
  $other = Join-Path $root 'arbitrary.dll'
  Write-Pe $other 0xaa64
  Assert-Rejected { & (Join-Path $PSScriptRoot 'verify_windows_runtime.ps1') -InputPath $other -Architecture arm64 }
  Write-Pe $crt 0x8664
  Assert-Rejected { & (Join-Path $PSScriptRoot 'verify_windows_runtime.ps1') -InputPath $crt -Architecture arm64 }
  [IO.File]::WriteAllText($crt, 'corrupt')
  Assert-Rejected { & (Join-Path $PSScriptRoot 'verify_windows_runtime.ps1') -InputPath $crt -Architecture arm64 }
  Write-Host 'Runtime policy: accepted script entry and six rejection cases passed'
  $installed = Join-Path $root 'installed'
  $modules = @('msvcp140.dll', 'vcruntime140.dll') | ForEach-Object {
    [pscustomobject]@{ ModuleName = $_; FileName = Join-Path $installed $_ }
  }
  $systemModule = [pscustomobject]@{ ModuleName = 'msvcp_win.dll'; FileName = Join-Path $root 'system/msvcp_win.dll' }
  Assert-WindowsRuntimeModules -Modules @($modules + $systemModule) -InstallRoot $installed
  foreach ($name in @('msvcp140.dll', 'vcruntime140_1.dll', 'vccorlib140.dll', 'msvcp141.dll')) {
    $outside = [pscustomobject]@{ ModuleName = $name; FileName = Join-Path $root "system/$name" }
    Assert-Rejected { Assert-WindowsRuntimeModules -Modules @($modules + $outside) -InstallRoot $installed }
  }
  Assert-Rejected { Assert-WindowsRuntimeModules -Modules @($systemModule) -InstallRoot $installed }
  Write-Host 'Loaded-module policy: OS runtime accepted and five rejection cases passed'
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force
}
