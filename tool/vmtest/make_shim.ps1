# Windows twin of make_shim.sh: materialize a local C: "build shim" view of the
# Parallels-share checkout so the VM builds WITHOUT copying sources.
#   * directories -> symlinks back to the share (needs local-to-remote symlink
#     evaluation enabled, the Win11 default; creation works with Developer Mode
#     or an elevated token),
#   * top-level files -> real copies (tools rewrite files via rename(), which
#     would replace a file-symlink),
#   * build\, .dart_tool\, windows\flutter\ephemeral stay real/local — the
#     flutter tool writes there and .plugin_symlinks cannot live on the share.
# Idempotent: re-run to refresh copied files; existing links are kept.
#
#   powershell -ExecutionPolicy Bypass -File make_shim.ps1 -Src \\Mac\Home\chat-uikit\toxee-vmtest-win -Dst C:\vmtest\toxee-win
param(
  [Parameter(Mandatory = $true)] [string]$Src,
  [Parameter(Mandatory = $true)] [string]$Dst,
  [string]$Platform = "windows"
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path (Join-Path $Src "pubspec.yaml"))) { throw "$Src does not look like the repo root" }
New-Item -ItemType Directory -Force -Path $Dst | Out-Null

$SkipTop = @(".git", "build", ".dart_tool", "Thumbs.db")

function Link-OrCopy([string]$srcEntry, [string]$dstEntry) {
  if (Test-Path -LiteralPath $srcEntry -PathType Container) {
    if (-not (Test-Path -LiteralPath $dstEntry)) {
      New-Item -ItemType SymbolicLink -Path $dstEntry -Target $srcEntry | Out-Null
    }
  } else {
    Copy-Item -LiteralPath $srcEntry -Destination $dstEntry -Force
  }
}

foreach ($e in (Get-ChildItem -LiteralPath $Src -Force)) {
  $n = $e.Name
  if ($SkipTop -contains $n) { continue }
  if ($n -eq $Platform -and $e.PSIsContainer) {
    # Platform runner dir: real dir; flutter\ real (generated_* written locally),
    # flutter\ephemeral left absent for the flutter tool to create locally.
    $platDst = Join-Path $Dst $n
    New-Item -ItemType Directory -Force -Path $platDst | Out-Null
    foreach ($e2 in (Get-ChildItem -LiteralPath $e.FullName -Force)) {
      if ($e2.Name -eq "flutter" -and $e2.PSIsContainer) {
        $flDst = Join-Path $platDst "flutter"
        New-Item -ItemType Directory -Force -Path $flDst | Out-Null
        foreach ($e3 in (Get-ChildItem -LiteralPath $e2.FullName -Force)) {
          if ($e3.Name -eq "ephemeral") { continue }
          Link-OrCopy $e3.FullName (Join-Path $flDst $e3.Name)
        }
      } else {
        Link-OrCopy $e2.FullName (Join-Path $platDst $e2.Name)
      }
    }
  } else {
    Link-OrCopy $e.FullName (Join-Path $Dst $n)
  }
}
New-Item -ItemType Directory -Force -Path (Join-Path $Dst "build"), (Join-Path $Dst ".dart_tool") | Out-Null
Write-Host "[make_shim] shim ready: $Dst (sources -> $Src)"
