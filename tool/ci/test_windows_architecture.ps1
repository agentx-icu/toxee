$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'assert_windows_architecture.ps1')

$taskRoot = Join-Path ([IO.Path]::GetTempPath()) ('toxee PE test ' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $taskRoot | Out-Null
$passed = 0
function New-PeFixture([string]$Name, [uint16]$Machine) {
  $bytes = [byte[]]::new(256)
  $bytes[0] = 0x4d; $bytes[1] = 0x5a
  [BitConverter]::GetBytes([int32]128).CopyTo($bytes, 60)
  $bytes[128] = 0x50; $bytes[129] = 0x45
  [BitConverter]::GetBytes($Machine).CopyTo($bytes, 132)
  $path = Join-Path $taskRoot $Name
  [IO.File]::WriteAllBytes($path, $bytes)
  return $path
}
function Assert-Fails([scriptblock]$Operation, [string]$MessagePattern) {
  try { & $Operation } catch {
    if ($_.Exception.Message -like $MessagePattern) { return }
    throw
  }
  throw "Expected failure matching: $MessagePattern"
}
try {
  $app = New-PeFixture 'app.exe' 0xaa64
  $engine = New-PeFixture 'flutter_windows.dll' 0xaa64
  $ffi = New-PeFixture 'tim2tox_ffi.dll' 0xaa64
  Assert-WindowsArchitecture -Architecture arm64 -Paths @($app, $engine, $ffi)
  $passed++

  $x64 = New-PeFixture 'x64.dll' 0x8664
  Assert-WindowsArchitecture -Architecture x64 -Paths @($x64)
  $passed++
  Assert-Fails { Assert-WindowsArchitecture -Architecture arm64 -Paths @($app, $x64, $ffi) } '*architecture mismatch*x64.dll*'
  $passed++

  $bad = New-PeFixture 'bad-signature.dll' 0xaa64
  $bytes = [IO.File]::ReadAllBytes($bad); $bytes[128] = 0
  [IO.File]::WriteAllBytes($bad, $bytes)
  Assert-Fails { Assert-WindowsArchitecture -Architecture arm64 -Paths @($bad) } '*invalid PE signature*'
  $passed++
  $bytes[0] = 0
  [IO.File]::WriteAllBytes($bad, $bytes)
  Assert-Fails { Assert-WindowsArchitecture -Architecture arm64 -Paths @($bad) } '*invalid DOS signature*'
  $passed++

  $bad = New-PeFixture 'bad-offset.dll' 0xaa64
  $bytes = [IO.File]::ReadAllBytes($bad)
  [BitConverter]::GetBytes([int32]65535).CopyTo($bytes, 60)
  [IO.File]::WriteAllBytes($bad, $bytes)
  Assert-Fails { Assert-WindowsArchitecture -Architecture arm64 -Paths @($bad) } '*invalid PE header offset*'
  $passed++

  $short = Join-Path $taskRoot 'truncated.exe'
  [IO.File]::WriteAllBytes($short, [byte[]]::new(32))
  Assert-Fails { Assert-WindowsArchitecture -Architecture arm64 -Paths @($short) } '*truncated DOS header*'
  $passed++
  Assert-Fails { Assert-WindowsArchitecture -Architecture arm64 -Paths @((Join-Path $taskRoot 'missing.dll')) } '*'
  $passed++

  Assert-WindowsInstallerArchitecture -Architecture x64 -Template 'x64;1033'
  $passed++
  Assert-WindowsInstallerArchitecture -Architecture arm64 -Template 'Arm64;1033'
  $passed++
  Assert-Fails { Assert-WindowsInstallerArchitecture -Architecture arm64 -Template 'Intel;1033' } '*MSI architecture mismatch*'
  $passed++
  Write-Host "Windows architecture regression: $passed tests passed"
} finally {
  Remove-Item -LiteralPath $taskRoot -Recurse -Force
}
