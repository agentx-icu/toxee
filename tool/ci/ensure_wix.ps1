$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Fixed official wix3141rtm asset 158158052. GitHub reports no asset digest for
# this older release; SHA256 was computed from its official HTTPS release ZIP.
$script:WixArchiveUri = 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip'
$script:WixArchiveSha256 = '6ac824e1642d6f7277d0ed7ea09411a508f6116ba6fae0aa5f2c7daa2ff43d31'

function Find-WixBin([string[]]$Patterns) {
  foreach ($pattern in $Patterns) {
    foreach ($directory in @(Get-Item -Path $pattern -ErrorAction SilentlyContinue)) {
      if ($directory.PSIsContainer -and
          (Test-Path -LiteralPath (Join-Path $directory.FullName 'candle.exe')) -and
          (Test-Path -LiteralPath (Join-Path $directory.FullName 'light.exe'))) {
        return $directory.FullName
      }
    }
  }
  return $null
}

function Expand-VerifiedWixArchive(
  [string]$Archive, [string]$Destination, [string]$ExpectedSha256
) {
  if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $ExpectedSha256) {
    throw 'WiX archive SHA256 mismatch; refusing to extract it'
  }
  # Replace only our verified staging directory, never mix old DLLs into it.
  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
  }
  Expand-Archive -LiteralPath $Archive -DestinationPath $Destination
  foreach ($tool in @('candle.exe', 'light.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Destination $tool))) {
      throw "WiX archive is missing $tool"
    }
  }
  return $Destination
}

function Invoke-WixProbe(
  [string]$Executable, [string[]]$Arguments = @('-?'), [int]$TimeoutSeconds = 30
) {
  $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -PassThru -NoNewWindow
  try {
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      $process.Kill($true)
      $process.WaitForExit()
      throw "WiX probe timed out: $Executable"
    }
    if ($process.ExitCode -ne 0) {
      throw "WiX probe exited with code $($process.ExitCode): $Executable"
    }
  } finally {
    $process.Dispose()
  }
}

function Initialize-WixForCi {
  $patterns = @(
    'C:\Program Files (x86)\WiX Toolset v3.*\bin',
    'C:\Program Files\WiX Toolset v3.*\bin',
    'C:\ProgramData\chocolatey\lib\wixtoolset\tools\*\bin',
    'C:\ProgramData\chocolatey\lib\wixtoolset\tools\bin'
  )
  $existing = Find-WixBin -Patterns $patterns
  if ($existing) {
    try {
      foreach ($tool in @('candle.exe', 'light.exe')) {
        Invoke-WixProbe -Executable (Join-Path $existing $tool)
      }
      Write-Host "Using installed WiX at: $existing"
      Add-Content -LiteralPath $env:GITHUB_PATH -Value $existing -Encoding utf8
      return
    } catch {
      Write-Warning "Installed WiX is unusable; using the pinned portable tools: $_"
    }
  }

  # Chocolatey's WiX dependency tries to enable NetFx3 on ARM runners and can
  # block for the entire job. WiX 3.14.1 tools target CLR4; no installer is needed.
  $archive = Join-Path $env:RUNNER_TEMP 'toxee-wix314-binaries.zip'
  $destination = Join-Path $env:RUNNER_TEMP 'toxee-wix-3.14.1'
  Invoke-WebRequest -Uri $script:WixArchiveUri -OutFile $archive -TimeoutSec 120 -MaximumRetryCount 2 -RetryIntervalSec 2
  $directory = Expand-VerifiedWixArchive -Archive $archive -Destination $destination -ExpectedSha256 $script:WixArchiveSha256
  foreach ($tool in @('candle.exe', 'light.exe')) {
    Invoke-WixProbe -Executable (Join-Path $directory $tool)
  }
  Write-Host "Using verified portable WiX at: $directory"
  Add-Content -LiteralPath $env:GITHUB_PATH -Value $directory -Encoding utf8
}

if ($MyInvocation.InvocationName -ne '.') { Initialize-WixForCi }
