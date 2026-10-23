function Assert-WindowsRuntimeModules {
  param(
    [Parameter(Mandatory)][object[]]$Modules,
    [Parameter(Mandatory)][string]$InstallRoot
  )
  $allowed = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'windows_runtime_files.txt'))
  # Windows owns msvcp_win.dll and other unversioned OS runtime components.
  # Versioned MSVC redistributables must instead be reviewed and app-local.
  $runtimeModules = @($Modules | Where-Object {
    $_.ModuleName -match '^(msvcp|vcruntime|concrt|vccorlib)[0-9][\w.]*\.dll$'
  })
  foreach ($name in @('msvcp140.dll', 'vcruntime140.dll')) {
    if ($name -notin @($runtimeModules | ForEach-Object { $_.ModuleName })) {
      throw "Required CRT was not loaded: $name"
    }
  }
  foreach ($module in $runtimeModules) {
    if ($module.ModuleName.ToLowerInvariant() -notin $allowed) {
      throw "Installed app loaded unreviewed CRT: $($module.ModuleName)"
    }
    if ([IO.Path]::GetDirectoryName($module.FileName) -ne $InstallRoot) {
      throw "Installed app loaded CRT outside its own directory: $($module.FileName)"
    }
    Write-Host "[ci] Installed app-local CRT loaded: $($module.FileName)"
  }
}
