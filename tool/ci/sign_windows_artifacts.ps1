param([Parameter(Mandatory=$true)][string]$InputPath)
$ErrorActionPreference = 'Stop'
$thumbprint = $env:WINDOWS_SIGN_CERT_SHA1
if (-not $thumbprint) {
  if ($env:TOXEE_REQUIRE_SIGNING -eq '1') { throw 'WINDOWS_SIGN_CERT_SHA1 is required for distribution' }
  Write-Warning 'No Windows signing identity configured; artifacts remain development builds.'
  exit 0
}
$signTool = (Get-Command signtool.exe -ErrorAction Stop).Source
if (Test-Path $InputPath -PathType Container) {
  $files = Get-ChildItem $InputPath -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' }
} else { $files = @(Get-Item $InputPath) }
foreach ($file in $files) {
  # Preserve valid vendor signatures; sign owned/redistributed unsigned code.
  if ((Get-AuthenticodeSignature $file.FullName).Status -ne 'Valid') {
    & $signTool sign /sha1 $thumbprint /fd SHA256 /tr https://timestamp.digicert.com /td SHA256 $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Signing failed: $($file.Name)" }
  }
  & $signTool verify /pa $file.FullName
  if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $($file.Name)" }
}
