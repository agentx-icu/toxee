#!/usr/bin/env bash
# Stop ONE Linux Toxee instance of the A/B pair (relaunch scenarios).
#
# Linux twin of `stop_toxee_instance.ps1`. Reads `<runtime>/<name>/instance.json`
# for the pid and kills it. The instance.json is KEPT (unlike the macOS `.sh`,
# which removes it): `launch_toxee_linux_instance.sh` re-reads the recorded exe
# / VM port / support dir from it to bring the SAME instance back.
# Best-effort: a missing json / already-dead process is not an error.
#
#   stop_toxee_linux_instance.sh <A|B>
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_ROOT="${TOXEE_LINUX_RUNTIME_ROOT:-$REPO_ROOT/build/linux_runtime}"
NAME="${1:?usage: stop_toxee_linux_instance.sh <A|B>}"
JSON="$RUNTIME_ROOT/$NAME/instance.json"

[[ -f "$JSON" ]] || { echo "OK: nothing to stop for $NAME"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq missing" >&2; exit 1; }

PID="$(jq -r '.pid // 0' "$JSON")"
EXE="$(jq -r '.exe // ""' "$JSON")"

if [[ "$PID" -gt 0 ]] && kill -0 "$PID" 2>/dev/null; then
    # Identity check before killing: after the instance exits on its own the
    # pid can be REUSED by an unrelated process (the Windows twin learned this
    # the hard way). Only kill a live pid whose /proc/<pid>/exe is our bundle.
    live_exe="$(readlink -f "/proc/$PID/exe" 2>/dev/null || true)"
    if [[ -n "$EXE" && "$live_exe" != "$(readlink -f "$EXE")" ]]; then
        echo "WARN: $NAME pid $PID is no longer the launched toxee (pid reused); not killing"
        tmp="$JSON.tmp"
        jq '.pid = 0' "$JSON" > "$tmp" && mv "$tmp" "$JSON"
        exit 0
    fi
    kill "$PID" 2>/dev/null || true
    # Wait for it to actually go away: the relaunch reuses the FIXED
    # VM-service port, and a still-exiting process fails that preflight.
    for _ in $(seq 1 50); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.2
    done
    kill -9 "$PID" 2>/dev/null || true
fi
rm -f "$RUNTIME_ROOT/$NAME/toxee.pid"
echo "OK: stopped $NAME pid=$PID"
exit 0
