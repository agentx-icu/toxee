param([Parameter(Mandatory=$true)][string]$MsiPath)
$ErrorActionPreference = 'Stop'
$msi = (Resolve-Path $MsiPath).Path
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
  $app = Start-Process $exe -WorkingDirectory $installRoot -PassThru
  Start-Sleep -Seconds 12
  if ($app.HasExited) { throw "Installed application exited at startup: $($app.ExitCode)" }
  if (-not $app.CloseMainWindow()) { throw 'Installed app did not expose a closable main window' }
  if (-not $app.WaitForExit(20000)) { throw 'Installed app did not exit after window close' }
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
