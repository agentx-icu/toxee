param(
  [ValidateSet('x64', 'arm64')][string]$Architecture,
  [string[]]$Paths
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Read the actual PE machine field instead of trusting runner labels or paths.
# This also works on non-Windows hosts, so corrupt/mixed fixtures are testable.
function Assert-WindowsArchitecture {
  param(
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory)][string[]]$Paths
  )
  $expected = if ($Architecture -eq 'arm64') { 0xaa64 } else { 0x8664 }
  if ($Paths.Count -eq 0) { throw 'No Windows binaries provided for architecture verification' }
  foreach ($path in $Paths) {
    $stream = [IO.File]::OpenRead($path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
      if ($stream.Length -lt 64) { throw "truncated DOS header: $path" }
      if ($reader.ReadUInt16() -ne 0x5a4d) { throw "invalid DOS signature: $path" }
      $stream.Position = 60
      $offset = $reader.ReadUInt32()
      if ($offset -lt 64 -or $offset -gt ($stream.Length - 6)) {
        throw "invalid PE header offset: $path"
      }
      $stream.Position = $offset
      if ($reader.ReadUInt32() -ne 0x4550) { throw "invalid PE signature: $path" }
      $machine = $reader.ReadUInt16()
      if ($machine -ne $expected) {
        throw ('architecture mismatch: {0}; expected {1} (0x{2:x4}), got 0x{3:x4}' -f $path, $Architecture, $expected, $machine)
      }
      Write-Host "[ci] PE $Architecture verified: $path"
    } finally {
      $reader.Dispose()
      $stream.Dispose()
    }
  }
}

function Assert-WindowsInstallerArchitecture {
  param(
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory)][string]$Template
  )
  $platform = $Template.Split(';')[0].Trim()
  if ($platform -ine $Architecture) {
    throw "MSI architecture mismatch: expected $Architecture, got Template '$Template'"
  }
  Write-Host "[ci] MSI $Architecture Template verified: $Template"
}

if ($MyInvocation.InvocationName -ne '.') {
  Assert-WindowsArchitecture -Architecture $Architecture -Paths $Paths
}
