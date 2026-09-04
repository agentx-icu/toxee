<#
.SYNOPSIS
  Prepare the Windows VM to build + run toxee from the Mac share: shim checkout,
  MSVC environment, one pair launch (builds tim2tox_ffi.dll + the app), stop.

.DESCRIPTION
  The vmtest workflow on the win11_ltsc Parallels VM (see
  tool/mcp_test/REAL_UI_TWO_PROCESS.md "Windows — aligned with macOS"):
    1. make_shim.ps1 materializes -Dst from the share -Src (sources symlinked,
       build/, .dart_tool/ and every <platform>\flutter\ephemeral local);
    2. vcvarsall (host ARM64 -> x64 tools when present) is imported and CC/CXX
       pinned to cl — otherwise CMake picks whatever c++ is first on PATH
       (Strawberry Perl's MinGW g++ on this VM, which fails on std::thread::id);
    3. a stale native CMake cache configured with another compiler is dropped
       (a cache pins its compiler regardless of CC/CXX);
    4. launch_windows_fixture_c_pair.ps1 builds the native FFI + the app and
       launches A/B once (proves the toolchain end-to-end), then the pair is
       stopped.
  Idempotent; re-run after edits on the Mac side. Everything lives under -Dst\build
  (local disk) — nothing is written into the Mac tree over the share.

  Run from an SSH session or the console; it needs no interactive desktop.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File \\Mac\bin.gao\chat-uikit\toxee\tool\vmtest\win_setup_shim.ps1
  powershell -ExecutionPolicy Bypass -File ...\win_setup_shim.ps1 -NoLaunch   # shim + env only
#>
param(
  [string]$Src = '\\Mac\bin.gao\chat-uikit\toxee',
  [string]$Dst = 'C:\vmtest\toxee-win',
  [string]$VcpkgRoot = 'C:\vcpkg',
  [string]$WindowsArch = 'x64',
  [switch]$NoLaunch
)
$ErrorActionPreference = "Continue"

function Import-VcVars {
  $msvc = Get-ChildItem "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
  $vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
  if (-not (Test-Path $vcvars)) { throw "vcvarsall.bat not found ($vcvars) - install VS 2022 Build Tools (Desktop C++)" }
  $hostArm = $msvc -and (Test-Path (Join-Path $msvc.FullName "bin\HostARM64\$WindowsArch\cl.exe"))
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -and $hostArm) { "arm64_amd64" } else { "amd64" }
  if ($WindowsArch -eq 'arm64') { $arch = 'arm64' }
  Write-Host "[win-setup] vcvarsall $arch"
  $vcEnv = & cmd /c "`"$vcvars`" $arch >nul 2>&1 && set"
  foreach ($line in $vcEnv) {
    if ($line -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:$($matches[1])" -Value $matches[2] }
  }
  $env:CC = 'cl'
  $env:CXX = 'cl'
  Write-Host "[win-setup] cl: $((Get-Command cl -ErrorAction SilentlyContinue).Source)"
}

Import-VcVars
$env:PATH = "C:\Program Files\Git\bin;C:\Program Files\Git\cmd;C:\dev\flutter\bin;C:\Strawberry\c\bin;" + $env:PATH
$env:VCPKG_ROOT = $VcpkgRoot
$env:TIM2TOX_WINDOWS_ARCH = $WindowsArch
# bash-style path: build_tim2tox.sh runs under Git Bash.
$env:TIM2TOX_NATIVE_BUILD_ROOT = ('/' + $Dst.Substring(0, 1).ToLower() + $Dst.Substring(2).Replace('\', '/') + '/build/tim2tox-native')
$env:MCP_BINDING = 'skill'
$env:TOXEE_L3_TEST = 'true'
$env:TOXEE_PAIR_TCP_ONLY = '1'

& git config --global --add safe.directory '*' 2>&1 | Out-Null
Write-Host "[win-setup] shim $Dst <- $Src"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Src 'tool\vmtest\make_shim.ps1') -Src $Src -Dst $Dst 2>&1 | Select-Object -Last 1

$cache = Join-Path $Dst 'build\tim2tox-native\ci-windows\CMakeCache.txt'
if ((Test-Path $cache) -and -not (Select-String -Path $cache -Pattern 'CMAKE_CXX_COMPILER:FILEPATH=.*cl\.exe' -Quiet)) {
  Write-Host "[win-setup] dropping stale native CMake cache (non-MSVC compiler)"
  Remove-Item -Recurse -Force (Join-Path $Dst 'build\tim2tox-native')
}
if ($NoLaunch) { Write-Host "[win-setup] env ready (no launch)"; exit 0 }

Set-Location $Dst
$launchLog = Join-Path $Dst 'build\win_setup_launch.log'
New-Item -ItemType Directory -Force -Path (Join-Path $Dst 'build') | Out-Null
Write-Host "[win-setup] launching pair once (builds native FFI + app) -> $launchLog"
# Redirect through cmd, NOT a PowerShell pipeline: the launched toxee.exe
# children inherit the console handles and a pipeline would wait for them.
& cmd /c "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Dst\tool\mcp_test\launch_windows_fixture_c_pair.ps1`" > `"$launchLog`" 2>&1"
$rc = $LASTEXITCODE
Get-Content $launchLog -Tail 8
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dst 'tool\mcp_test\stop_windows_fixture_c_pair.ps1') 2>&1 | Select-Object -Last 1
$dll = Join-Path $Dst 'build\windows\x64\runner\Debug\tim2tox_ffi.dll'
Write-Host ("[win-setup] launcher rc={0} tim2tox_ffi.dll={1} C: free={2} GB" -f $rc, (Test-Path $dll), [math]::Round((Get-PSDrive C).Free / 1GB, 1))
exit $rc
