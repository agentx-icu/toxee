#!/usr/bin/env bash
# Shared helpers for the disposable Fixture C multi-instance spike harness.
#
# This library intentionally mirrors the echo-peer helpers' "record a process
# triple and only signal the recorded process" discipline so repeated spike
# runs do not kill unrelated Toxee processes.

_mi_normalize_args() {
    printf '%s' "${1:-}" | awk '{$1=$1; print}'
}

_mi_ps_lstart() {
    local pid="$1"
    ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

_mi_ps_args() {
    local pid="$1"
    ps -p "$pid" -o args= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

_mi_pids_for_executable() {
    local executable="$1"
    /usr/bin/python3 - "$executable" <<'PY'
import subprocess
import sys

executable = sys.argv[1]
try:
    out = subprocess.check_output(["ps", "ax", "-o", "pid=", "-o", "args="], text=True)
except Exception:
    sys.exit(0)
for line in out.splitlines():
    stripped = line.strip()
    if not stripped:
        continue
    pid, _, args = stripped.partition(" ")
    args = args.strip()
    if args == executable or args.startswith(executable + " "):
        print(pid)
PY
}

_mi_new_pids_since_baseline() {
    local executable="$1"
    local baseline="${2:-}"
    local current
    current="$(_mi_pids_for_executable "$executable")"
    /usr/bin/python3 - "$baseline" "$current" <<'PY'
import sys

baseline = {line.strip() for line in sys.argv[1].splitlines() if line.strip()}
current = [line.strip() for line in sys.argv[2].splitlines() if line.strip()]
for pid in current:
    if pid not in baseline:
        print(pid)
PY
}

_mi_validate_triple() {
    local pid="${1:-}"
    local expected_lstart="${2:-}"
    local expected_cmdline="${3:-}"
    if [[ -z "$pid" || -z "$expected_lstart" || -z "$expected_cmdline" ]]; then
        echo "missing_inputs"
        return 1
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "pid_dead"
        return 1
    fi
    local live_lstart live_args norm_live norm_expected
    live_lstart="$(_mi_ps_lstart "$pid")"
    live_args="$(_mi_ps_args "$pid")"
    if [[ -z "$live_lstart" || -z "$live_args" ]]; then
        echo "ps_empty"
        return 1
    fi
    if [[ "$live_lstart" != "$expected_lstart" ]]; then
        echo "lstart_mismatch"
        return 1
    fi
    norm_live="$(_mi_normalize_args "$live_args")"
    norm_expected="$(_mi_normalize_args "$expected_cmdline")"
    if [[ "$norm_live" != "$norm_expected" ]]; then
        echo "cmdline_mismatch"
        return 1
    fi
    echo "ok"
    return 0
}

# Reclaim the disposable per-launch app copies (`ToxeeB-<epoch>-<pid>.app`) that
# launch_fixture_c_pair.sh dittos for B. Each is a full ~185M bundle and every
# launch mints a fresh path, so without a GC they accumulate forever.
#
# Follows this library's "only touch what you can prove is dead" rule: a copy
# still backing a live process is kept, never yanked out from under it. Copies
# with a FIXED name (presence's `ToxeeB.app`) are reused in place rather than
# accumulating, and deliberately do not match the pattern.
# $2 is the min-age window in seconds (default 60): a bundle mid-`ditto` has no
# process yet, so liveness alone would green-light deleting it while it is still
# being written. A copy skipped for being young is simply reclaimed on the next
# pass. Teardown passes 0 — stop_fixture_c_pair.sh already assumes exclusivity
# (it kills A and B out of the shared runtime root), so nothing of ours can be
# mid-launch by the time it sweeps.
_mi_gc_app_copies() {
    local copies_dir="${1:-}"
    local min_age_secs="${2:-${TOXEE_MULTI_GC_MIN_AGE_SECS:-60}}"
    if [[ -z "$copies_dir" || ! -d "$copies_dir" ]]; then
        return 0
    fi
    local now copy mtime reclaimed=0
    now="$(date +%s)"
    for copy in "$copies_dir"/Toxee[AB]-*.app; do
        [[ -d "$copy" ]] || continue
        mtime="$(stat -f %m "$copy" 2>/dev/null || echo 0)"
        if [[ "$mtime" -gt 0 && $((now - mtime)) -lt "$min_age_secs" ]]; then
            echo "gc: skipping app copy $(basename "$copy") (<${min_age_secs}s old)" >&2
            continue
        fi
        if [[ -n "$(_mi_pids_for_executable "$copy/Contents/MacOS/Toxee")" ]]; then
            echo "gc: keeping in-use app copy $(basename "$copy")" >&2
            continue
        fi
        rm -rf "$copy"
        reclaimed=$((reclaimed + 1))
    done
    if [[ "$reclaimed" -gt 0 ]]; then
        echo "gc: reclaimed $reclaimed stale app copy/copies from $copies_dir" >&2
    fi
    return 0
}

_mi_stop_with_grace() {
    local pid="${1:-}"
    local grace_secs="${2:-5}"
    if [[ -z "$pid" ]]; then
        return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    kill -TERM "$pid" 2>/dev/null || true
    local waited=0
    while [[ "$waited" -lt "$grace_secs" ]] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
        sleep 1
    fi
    if kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    return 0
}
