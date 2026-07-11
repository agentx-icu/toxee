# One-time environment bootstrap for the win11_ltsc VM test host (vmtest campaign):
# probes the MSVC toolset, then installs vcpkg + the tim2tox native deps
# (libsodium, pthreads, opus, libvpx) for arm64-windows. Idempotent.
#
#   powershell -ExecutionPolicy Bypass -File \\Mac\Home\chat-uikit\toxee-vmtest-win\tool\vmtest\win_bootstrap_env.ps1
$ErrorActionPreference = "Continue"
function Log([string]$m) { Write-Host "[win-bootstrap] $m" }

$VcpkgRoot = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { "C:\vcpkg" }
$Triplet   = if ($env:TOXEE_VCPKG_TRIPLET) { $env:TOXEE_VCPKG_TRIPLET } else { "arm64-windows" }

Log "share write probe (informational):"
try {
  Set-Content -Path "\\Mac\Home\chat-uikit\toxee-vmtest-win\.share_write_test" -Value "x" -ErrorAction Stop
  Remove-Item "\\Mac\Home\chat-uikit\toxee-vmtest-win\.share_write_test" -Force
  Log "share WRITE OK"
} catch { Log "share is READ-ONLY for the guest ($($_.Exception.Message))" }

Log "MSVC host/target toolsets present:"
$msvc = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC"
if (Test-Path $msvc) {
  Get-ChildItem $msvc -Directory | ForEach-Object {
    $v = $_.FullName
    foreach ($h in @("Hostx64", "HostARM64", "Hostarm64")) {
      foreach ($t in @("x64", "arm64")) {
        if (Test-Path "$v\bin\$h\$t\cl.exe") { Log "  cl: $($_.Name) $h\$t" }
      }
    }
  }
} else { Log "  MSVC dir not found at $msvc" }

if (-not (Test-Path "$VcpkgRoot\vcpkg.exe")) {
  if (-not (Test-Path $VcpkgRoot)) {
    Log "cloning vcpkg to $VcpkgRoot..."
    git clone --depth 1 https://github.com/microsoft/vcpkg $VcpkgRoot 2>&1 | Select-Object -Last 2
  }
  Log "bootstrapping vcpkg..."
  & "$VcpkgRoot\bootstrap-vcpkg.bat" -disableMetrics 2>&1 | Select-Object -Last 3
}

if (Test-Path "$VcpkgRoot\vcpkg.exe") {
  Log "installing libsodium/pthreads/opus/libvpx ($Triplet) - this can take 20-60 min..."
  & "$VcpkgRoot\vcpkg.exe" install "libsodium:$Triplet" "pthreads:$Triplet" "opus:$Triplet" "libvpx:$Triplet" 2>&1 |
    Select-Object -Last 20
  Log "vcpkg install rc=$LASTEXITCODE"
  & "$VcpkgRoot\vcpkg.exe" list 2>&1 | Select-String "sodium|pthread|opus|vpx"
} else {
  Log "vcpkg bootstrap FAILED - see output above"
}
Log "DONE"
