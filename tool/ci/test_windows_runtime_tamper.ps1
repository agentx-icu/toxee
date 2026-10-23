param([Parameter(Mandatory)][string]$RuntimeDirectory)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'microsoft_runtime_signature.ps1')
$source = Join-Path $RuntimeDirectory 'msvcp140.dll'
Assert-MicrosoftRuntimeSignature -Path $source
$temp = Join-Path ([IO.Path]::GetTempPath()) ('toxee-runtime-tamper-' + [guid]::NewGuid())
[void](New-Item -ItemType Directory -Path $temp)
$oldThumbprint = $env:WINDOWS_SIGN_CERT_SHA1
$oldRequire = $env:TOXEE_REQUIRE_SIGNING
$global:ToxeeTamperToolReached = $false
function Get-Command {
  param([string]$Name, [string]$ErrorAction)
  $global:ToxeeTamperToolReached = $true
  throw 'Tampered Microsoft CRT must fail before signing tool discovery'
}
try {
  $copy = Join-Path $temp 'msvcp140.dll'
  Copy-Item -LiteralPath $source -Destination $copy
  $bytes = [IO.File]::ReadAllBytes($copy)
  $pe = [BitConverter]::ToInt32($bytes, 60)
  $section = $pe + 24 + [BitConverter]::ToUInt16($bytes, $pe + 20)
  $payload = [BitConverter]::ToUInt32($bytes, $section + 20)
  if ($payload -lt ($section + 40) -or $payload -ge $bytes.Length) { throw 'Invalid fixture PE section bounds' }
  $bytes[$payload] = $bytes[$payload] -bxor 1
  [IO.File]::WriteAllBytes($copy, $bytes)
  if ((Get-AuthenticodeSignature -LiteralPath $copy).Status -eq 'Valid') { throw 'Tampering did not invalidate real signature' }
  # A public dummy fingerprint exercises strict intent, never a real key.
  $env:WINDOWS_SIGN_CERT_SHA1 = '0' * 40
  $env:TOXEE_REQUIRE_SIGNING = '1'
  $rejected = $false
  try { & (Join-Path $PSScriptRoot 'sign_windows_artifacts.ps1') -InputPath $copy }
  catch { $rejected = $_.Exception.Message -like '*original Microsoft signature*' }
  if (-not $rejected -or $global:ToxeeTamperToolReached) { throw 'Tampered CRT reached owner signing path' }
  Write-Host '[ci] Real signed Microsoft CRT mutation rejected before signing-tool discovery'
} finally {
  $env:WINDOWS_SIGN_CERT_SHA1 = $oldThumbprint
  $env:TOXEE_REQUIRE_SIGNING = $oldRequire
  Remove-Item -LiteralPath $temp -Recurse -Force
}
