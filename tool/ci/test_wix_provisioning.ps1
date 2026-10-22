$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ensure_wix.ps1')

$taskRoot = Join-Path ([IO.Path]::GetTempPath()) ("toxee wix test " + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $taskRoot | Out-Null
$passed = 0
function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
function Assert-Fails([scriptblock]$Operation, [string]$MessagePattern) {
  try { & $Operation } catch {
    if ($_.Exception.Message -like $MessagePattern) { return }
    throw
  }
  throw "Expected failure matching: $MessagePattern"
}
try {
  $source = Join-Path $taskRoot 'source'
  New-Item -ItemType Directory -Path $source | Out-Null
  Set-Content -LiteralPath (Join-Path $source 'candle.exe') -Value 'test compiler'
  Set-Content -LiteralPath (Join-Path $source 'light.exe') -Value 'test linker'
  $archive = Join-Path $taskRoot 'tools.zip'
  Compress-Archive -Path "$source/*" -DestinationPath $archive
  $digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
  $destination = Join-Path $taskRoot 'WiX Toolset v3.14/bin'
  Expand-VerifiedWixArchive -Archive $archive -Destination $destination -ExpectedSha256 $digest | Out-Null
  Assert-True (Test-Path (Join-Path $destination 'candle.exe')) 'compiler was not extracted'
  Assert-True (Test-Path (Join-Path $destination 'light.exe')) 'linker was not extracted'
  $passed++

  $resolved = Find-WixBin -Patterns @((Join-Path $taskRoot 'WiX Toolset v3.*/bin'))
  Assert-True ($resolved -eq (Get-Item -LiteralPath $destination).FullName) 'installed path must resolve wildcards and preserve spaces'
  $passed++

  $sentinel = Join-Path $destination 'retained.txt'
  Set-Content -LiteralPath $sentinel -Value 'keep on verification failure'
  Assert-Fails { Expand-VerifiedWixArchive -Archive $archive -Destination $destination -ExpectedSha256 ('0' * 64) } '*SHA256 mismatch*'
  Assert-True (Test-Path $sentinel) 'hash failure modified the previous tools'
  $passed++

  Remove-Item -LiteralPath (Join-Path $source 'light.exe')
  $incomplete = Join-Path $taskRoot 'incomplete.zip'
  Compress-Archive -Path "$source/*" -DestinationPath $incomplete
  $incompleteHash = (Get-FileHash -LiteralPath $incomplete -Algorithm SHA256).Hash
  Assert-Fails { Expand-VerifiedWixArchive -Archive $incomplete -Destination (Join-Path $taskRoot 'incomplete') -ExpectedSha256 $incompleteHash } '*missing light.exe*'
  $passed++

  # Exercise real process handling, without pretending placeholder ZIP files
  # are Windows executables. The CI provisioning entry probes real WiX later.
  $shellName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
  $shell = Join-Path $PSHOME $shellName
  Invoke-WixProbe -Executable $shell -Arguments @('-NoProfile', '-Command', 'exit 0')
  $passed++
  Assert-Fails { Invoke-WixProbe -Executable $shell -Arguments @('-NoProfile', '-Command', 'exit 7') } '*exited with code 7*'
  $passed++
  Assert-Fails { Invoke-WixProbe -Executable $shell -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10') -TimeoutSeconds 1 } '*timed out*'
  $passed++
  Write-Host "WiX provisioning regression: $passed tests passed"
} finally {
  Remove-Item -LiteralPath $taskRoot -Recurse -Force
}
