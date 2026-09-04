# Dot-sourced by the Windows instance launcher/stoppers.
#
# Resolves the live process an instance.json describes ONLY if it is still the
# process that was launched: the pid must exist, its executable must be the
# recorded `exe`, and (when recorded) its start time must match `start_time`
# within 2 s - the same pid/start-time/cmdline triple the POSIX twin checks.
# Windows reuses pids, so a bare `Get-Process -Id` check could hand a foreign
# process to `taskkill /F /T`.
function Get-ToxeeInstanceProcess($doc) {
  $procPid = 0
  try { $procPid = [int]$doc.pid } catch { return $null }
  if ($procPid -le 0) { return $null }
  $p = Get-Process -Id $procPid -ErrorAction SilentlyContinue
  if (-not $p) { return $null }
  # The recorded exe is mandatory: a record without it (legacy/malformed) can
  # only match by pid, which is exactly the reuse hazard this guards against.
  $exe = [string]$doc.exe
  if (-not $exe) { return $null }
  $path = $null
  try { $path = $p.Path } catch { $path = $null }
  if (-not $path -or ($path -ne $exe)) { return $null }
  $recorded = [string]$doc.start_time
  if ($recorded) {
    try {
      $st = [datetime]::Parse($recorded, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
      if ([math]::Abs(($p.StartTime - $st).TotalSeconds) -gt 2) { return $null }
    } catch { return $null }
  }
  return $p
}

# ISO-8601 (round-trip) start time of a pid, or "" when unavailable.
function Get-ProcessStartTimeIso([int]$procPid) {
  try { return (Get-Process -Id $procPid -ErrorAction Stop).StartTime.ToString('o') } catch { return '' }
}
