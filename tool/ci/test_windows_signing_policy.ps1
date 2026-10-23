# Signing-policy fixtures use controlled Authenticode/signtool adapters.
# Actual trusted-CA signatures still require the publisher's Windows release run.
$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('toxee signing policy ' + [guid]::NewGuid())
[void](New-Item -ItemType Directory $fixtureRoot)
$expected = '1' * 40
$other = '2' * 40
$env:WINDOWS_SIGN_CERT_SHA1 = $expected
$env:TOXEE_TEST_WRONG_SIGNER = '0'
$env:TOXEE_TEST_SIGN_TRACE = Join-Path $fixtureRoot 'trace.txt'
$fakeTool = Join-Path $fixtureRoot 'signtool-fixture.ps1'
@'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
if ($Arguments[0] -eq 'sign') {
  Add-Content $env:TOXEE_TEST_SIGN_TRACE 'sign'
  $value = $env:WINDOWS_SIGN_CERT_SHA1
  if ($env:TOXEE_TEST_WRONG_SIGNER -eq '1') { $value = '2' * 40 }
  Set-Content ($Arguments[-1] + '.signature') $value
}
$global:LASTEXITCODE = 0
'@ | Set-Content $fakeTool
function Get-Command {
  param([string]$Name, [string]$ErrorAction)
  if ($Name -ne 'signtool.exe') { throw "Unexpected tool lookup: $Name" }
  if ($env:TOXEE_TEST_DENY_TOOL_DISCOVERY -eq '1') { throw 'Signing tool discovery must not be reached' }
  return [pscustomobject]@{ Source = $fakeTool }
}
function Get-AuthenticodeSignature {
  param([Alias('LiteralPath')][string]$FilePath)
  if ($env:TOXEE_TEST_CRT_CHANGES -eq '1' -and [IO.Path]::GetFileName($FilePath) -eq 'msvcp140.dll') {
    $global:ToxeeFixtureCrtCalls++
    if ($global:ToxeeFixtureCrtCalls -gt 1) { return [pscustomobject]@{ Status = 'HashMismatch'; SignerCertificate = $null } }
  }
  $sidecar = $FilePath + '.signature'
  if (-not (Test-Path $sidecar)) { return [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null } }
  return [pscustomobject]@{
    Status = 'Valid'
    SignerCertificate = $(if ($env:TOXEE_TEST_NULL_CERT -eq '1') { $null } else {
      [pscustomobject]@{ Thumbprint = (Get-Content $sidecar -Raw).Trim(); Subject = $env:TOXEE_TEST_VENDOR_SUBJECT }
    })
  }
}
function Assert-Case([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
$policy = Join-Path $PSScriptRoot 'sign_windows_artifacts.ps1'
try {
  $app = Join-Path $fixtureRoot 'toxee.exe'
  Set-Content $app 'fixture only'
  Set-Content ($app + '.signature') $other
  & $policy -InputPath $app
  Assert-Case ((Get-Content ($app + '.signature') -Raw).Trim() -eq $expected) 'Wrong owned publisher was preserved'
  Assert-Case (Test-Path $env:TOXEE_TEST_SIGN_TRACE) 'Owned app was not re-signed'
  Remove-Item $env:TOXEE_TEST_SIGN_TRACE

  & $policy -InputPath $app
  Assert-Case (-not (Test-Path $env:TOXEE_TEST_SIGN_TRACE)) 'Matching owner unnecessarily re-signed'

  $vendor = Join-Path $fixtureRoot 'vendor.dll'
  Set-Content $vendor 'fixture only'
  Set-Content ($vendor + '.signature') $other
  & $policy -InputPath $vendor
  Assert-Case (-not (Test-Path $env:TOXEE_TEST_SIGN_TRACE)) 'Valid vendor signature was replaced'

  Set-Content ($app + '.signature') $other
  $env:TOXEE_TEST_WRONG_SIGNER = '1'
  $rejected = $false
  try { & $policy -InputPath $app } catch { $rejected = $_.Exception.Message -like '*publisher differs*' }
  Assert-Case $rejected 'Signer returning success with wrong owner was accepted'

  $env:TOXEE_TEST_WRONG_SIGNER = '0'
  Remove-Item $env:TOXEE_TEST_SIGN_TRACE
  $crt = Join-Path $fixtureRoot 'msvcp140.dll'
  Set-Content $crt 'fixture only'
  Set-Content ($crt + '.signature') $other
  $env:TOXEE_TEST_VENDOR_SUBJECT = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US'
  & $policy -InputPath $crt
  Assert-Case (-not (Test-Path $env:TOXEE_TEST_SIGN_TRACE)) 'Microsoft CRT was re-signed'
  $env:TOXEE_TEST_VENDOR_SUBJECT = 'CN=Microsoft Windows Software Compatibility Publisher, O=Microsoft Corporation, C=US'
  & $policy -InputPath $crt
  Assert-Case (-not (Test-Path $env:TOXEE_TEST_SIGN_TRACE)) 'Microsoft compatibility-publisher CRT was re-signed'
  $env:TOXEE_TEST_DENY_TOOL_DISCOVERY = '1'
  foreach ($case in @('unsigned', 'null-certificate', 'wrong-organization')) {
    $env:TOXEE_TEST_NULL_CERT = '0'
    $env:TOXEE_TEST_VENDOR_SUBJECT = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US'
    Set-Content ($crt + '.signature') $other
    if ($case -eq 'unsigned') { Remove-Item ($crt + '.signature') }
    if ($case -eq 'null-certificate') { $env:TOXEE_TEST_NULL_CERT = '1' }
    if ($case -eq 'wrong-organization') { $env:TOXEE_TEST_VENDOR_SUBJECT = 'CN=Microsoft Corporation, O=Microsoft Corporation Evil, C=US' }
    $rejected = $false
    try { & $policy -InputPath $crt } catch { $rejected = $_.Exception.Message -like '*original Microsoft signature*' }
    Assert-Case $rejected "Unsafe CRT passed pre-sign policy: $case"
    Assert-Case (-not (Test-Path $env:TOXEE_TEST_SIGN_TRACE)) 'Unsafe CRT reached signing tool'
  }
  $env:TOXEE_TEST_DENY_TOOL_DISCOVERY = '0'
  $env:TOXEE_TEST_NULL_CERT = '0'
  $env:TOXEE_TEST_VENDOR_SUBJECT = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US'
  Set-Content ($crt + '.signature') $other
  $global:ToxeeFixtureCrtCalls = 0
  $env:TOXEE_TEST_CRT_CHANGES = '1'
  $rejected = $false
  try { & $policy -InputPath $crt } catch { $rejected = $_.Exception.Message -like '*original Microsoft signature*' }
  Assert-Case $rejected 'CRT changing signature state reached the owner re-sign branch'
  Assert-Case (-not (Test-Path $env:TOXEE_TEST_SIGN_TRACE)) 'CRT changing signature state was re-signed'
  $env:TOXEE_TEST_CRT_CHANGES = '0'

  $env:WINDOWS_SIGN_CERT_SHA1 = ''
  $env:TOXEE_REQUIRE_SIGNING = '1'
  $rejected = $false
  try { & $policy -InputPath $app } catch { $rejected = $_.Exception.Message -like '*required for distribution*' }
  Assert-Case $rejected 'Distribution without expected identity was accepted'
  Write-Host '11 Windows publisher-signing policy cases passed.'
} finally {
  Remove-Item $fixtureRoot -Recurse -Force
}
