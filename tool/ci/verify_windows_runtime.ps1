param(
  [Parameter(Mandatory)][string]$InputPath,
  [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Architecture,
  [string]$Report
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'assert_windows_architecture.ps1') -Architecture $Architecture
. (Join-Path $PSScriptRoot 'microsoft_runtime_signature.ps1')
$allowed = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'windows_runtime_files.txt'))
$item = Get-Item -LiteralPath $InputPath
$root = if ($item.PSIsContainer) { $item.FullName } else { $item.Directory.FullName }
$files = @(if ($item.PSIsContainer) {
  Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Name.ToLowerInvariant() -in $allowed }
} else { $item })
if ($files.Count -eq 0) { throw 'No app-local MSVC runtime files found' }
$evidence = @()
foreach ($file in $files) {
  if ($file.Name.ToLowerInvariant() -notin $allowed) { throw "Unreviewed CRT name: $($file.Name)" }
  Assert-MicrosoftRuntimeSignature -Path $file.FullName
  Assert-WindowsArchitecture -Architecture $Architecture -Paths @($file.FullName)
  $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
  $evidence += [ordered]@{ name = $file.Name; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash;
    signer = $signature.SignerCertificate.Subject; certificateSha1 = $signature.SignerCertificate.Thumbprint }
}
if ($item.PSIsContainer) {
  $required = @('msvcp140.dll', 'vcruntime140.dll', 'msvcp140_atomic_wait.dll')
  if ($Architecture -eq 'x64') { $required += 'vcruntime140_1.dll' }
  foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) { throw "Missing app-local runtime: $name" }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $root 'MICROSOFT_RUNTIME_NOTICE.txt') -PathType Leaf)) {
    throw 'MSVC runtime redistribution notice is missing'
  }
  $dumpbin = (Get-Command dumpbin.exe -ErrorAction Stop).Source
  foreach ($binary in Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { $_.Extension -in '.exe', '.dll' }) {
    $dependencies = & $dumpbin /nologo /dependents $binary.FullName
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect runtime imports: $($binary.Name)" }
    foreach ($line in $dependencies) {
      if ($line -match '^\s*((?:msvcp|vcruntime|concrt|vccorlib)[\w.]*\.dll)\s*$') {
        $name = $Matches[1].ToLowerInvariant()
        if ($name -notin $allowed -or -not (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) {
          throw "Unresolved app-local runtime import $name in $($binary.Name)"
        }
      }
    }
  }
}
if ($Report) {
  $evidence | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Report -Encoding utf8
}
Write-Host "[ci] Microsoft app-local CRT verified: $($files.Count) files, target $Architecture"
