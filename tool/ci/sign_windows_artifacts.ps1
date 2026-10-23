param([Parameter(Mandatory=$true)][string]$InputPath)
$ErrorActionPreference = 'Stop'
$thumbprint = $env:WINDOWS_SIGN_CERT_SHA1
if (-not $thumbprint) {
  if ($env:TOXEE_REQUIRE_SIGNING -eq '1') { throw 'WINDOWS_SIGN_CERT_SHA1 is required for distribution' }
  Write-Warning 'No Windows signing identity configured; artifacts remain development builds.'
  exit 0
}
if ($thumbprint -notmatch '^[0-9a-fA-F]{40}$') { throw 'WINDOWS_SIGN_CERT_SHA1 must be a certificate SHA1 thumbprint' }
. (Join-Path $PSScriptRoot 'microsoft_runtime_signature.ps1')
if (Test-Path $InputPath -PathType Container) {
  $files = Get-ChildItem $InputPath -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' }
} else { $files = @(Get-Item $InputPath) }
foreach ($file in $files) {
  if ($file.Name -match '^(msvcp|vcruntime|concrt|vccorlib).*\.dll$') {
    # Reject before discovering or invoking a signing tool, even for direct
    # local calls. The publisher key must never replace Microsoft's signature.
    Assert-MicrosoftRuntimeSignature -Path $file.FullName
  }
}
$signTool = (Get-Command signtool.exe -ErrorAction Stop).Source
foreach ($file in $files) {
  if ($file.Name -match '^(msvcp|vcruntime|concrt|vccorlib).*\.dll$') {
    Assert-MicrosoftRuntimeSignature -Path $file.FullName
    & $signTool verify /pa $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Microsoft signature verification failed: $($file.Name)" }
    continue
  }
  # Preserve valid vendor signatures; sign owned/redistributed unsigned code.
  $owned = ($file.Extension -eq '.msi' -or $file.Name -in 'toxee.exe', 'tim2tox_ffi.dll')
  $signature = Get-AuthenticodeSignature $file.FullName
  $wrongOwner = $owned -and ($null -eq $signature.SignerCertificate -or
    $signature.SignerCertificate.Thumbprint -ne $thumbprint)
  if ($signature.Status -ne 'Valid' -or $wrongOwner) {
    & $signTool sign /sha1 $thumbprint /fd SHA256 /tr https://timestamp.digicert.com /td SHA256 $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Signing failed: $($file.Name)" }
  }
  & $signTool verify /pa $file.FullName
  if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $($file.Name)" }
  if ($owned) {
    $finalSignature = Get-AuthenticodeSignature $file.FullName
    if ($finalSignature.Status -ne 'Valid' -or $finalSignature.SignerCertificate.Thumbprint -ne $thumbprint) {
      throw "Owned artifact publisher differs from expected certificate: $($file.Name)"
    }
  }
}
