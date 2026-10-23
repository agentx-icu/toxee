param(
  [Parameter(Mandatory=$true)][string]$MsiPath,
  [Parameter(Mandatory=$true)][ValidateSet('x64', 'arm64')][string]$ExpectedArchitecture
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'assert_windows_architecture.ps1')
$msi = (Resolve-Path $MsiPath).Path
# Inspect the generated database's SummaryInformation Template (property 7),
# rather than treating the architecture in its filename as evidence.
$installer = New-Object -ComObject WindowsInstaller.Installer
$summary = $null
try {
  $summary = $installer.GetType().InvokeMember('SummaryInformation', 'GetProperty', $null, $installer, @($msi, 0))
  $template = $summary.GetType().InvokeMember('Property', 'GetProperty', $null, $summary, @(7))
  Assert-WindowsInstallerArchitecture -Architecture $ExpectedArchitecture -Template $template
} finally {
  if ($summary) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($summary) }
  [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer)
}
$installRoot = Join-Path $env:RUNNER_TEMP ('toxee-installed-smoke-' + [guid]::NewGuid().ToString('N'))
$app = $null
$installed = $false
function Invoke-Msi([string[]]$Arguments) {
  $process = Start-Process msiexec.exe -ArgumentList $Arguments -Wait -PassThru
  if ($process.ExitCode -notin 0, 3010) { throw "msiexec failed: $($process.ExitCode)" }
}
try {
  Invoke-Msi @('/i', "`"$msi`"", '/qn', '/norestart', "INSTALL_ROOT=`"$installRoot`"")
  $installed = $true
  $exe = Join-Path $installRoot 'toxee.exe'
  if (-not (Test-Path $exe)) { throw 'MSI did not install the executable at INSTALL_ROOT' }
  foreach ($required in @('flutter_windows.dll', 'tim2tox_ffi.dll')) {
    if (-not (Test-Path (Join-Path $installRoot $required))) { throw "MSI omitted $required" }
  }
  $nativeFiles = @(Get-ChildItem -LiteralPath $installRoot -File -Recurse |
    Where-Object { $_.Extension -in '.exe', '.dll' } | ForEach-Object { $_.FullName })
  Assert-WindowsArchitecture -Architecture $ExpectedArchitecture -Paths $nativeFiles
  & (Join-Path $PSScriptRoot 'verify_windows_runtime.ps1') -InputPath $installRoot -Architecture $ExpectedArchitecture
  $app = Start-Process $exe -WorkingDirectory $installRoot -PassThru
  Start-Sleep -Seconds 12
  if ($app.HasExited) { throw "Installed application exited at startup: $($app.ExitCode)" }
  $runtimeModules = @($app.Modules | Where-Object { $_.ModuleName -match '^(msvcp|vcruntime|concrt).*\.dll$' })
  foreach ($name in @('msvcp140.dll', 'vcruntime140.dll')) {
    if ($name -notin @($runtimeModules | ForEach-Object { $_.ModuleName })) { throw "Required CRT was not loaded: $name" }
  }
  foreach ($module in $runtimeModules) {
    if ([IO.Path]::GetDirectoryName($module.FileName) -ne $installRoot) {
      throw "Installed app loaded CRT outside its own directory: $($module.FileName)"
    }
    Write-Host "[ci] Installed app-local CRT loaded: $($module.FileName)"
  }
  if (-not $app.CloseMainWindow()) { throw 'Installed app did not expose a closable main window' }
  if (-not $app.WaitForExit(20000)) { throw 'Installed app did not exit after window close' }
  if ($app.ExitCode -ne 0) { throw "Installed app crashed on close: $($app.ExitCode)" }
  # Same-version repair exercises MSI ownership; a previous-release upgrade
  # requires supplying a previous artifact in the release qualification matrix.
  Invoke-Msi @('/i', "`"$msi`"", '/qn', '/norestart', 'REINSTALL=ALL', 'REINSTALLMODE=vomus')
  Invoke-Msi @('/x', "`"$msi`"", '/qn', '/norestart')
  $installed = $false
  if (Test-Path $exe) { throw 'Uninstall left the packaged executable installed' }
} finally {
  if ($app -and -not $app.HasExited) { Stop-Process -Id $app.Id -Force }
  if ($installed) { Invoke-Msi @('/x', "`"$msi`"", '/qn', '/norestart') }
}
