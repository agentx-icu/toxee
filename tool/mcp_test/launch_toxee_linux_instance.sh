#!/usr/bin/env bash
# Relaunch ONE Linux Toxee instance of the A/B pair (relaunch scenarios).
#
# Linux twin of `launch_toxee_instance.ps1` (Windows) — used by the real-UI
# relaunch cases (sweep_p1_relaunch / presence_dot_relaunch) after
# `stop_toxee_linux_instance.sh`. It does NOT build and does NOT wipe state:
# it re-reads the instance's recorded contract from
# `<runtime>/<name>/instance.json` (exe, fixed VM-service port, per-instance
# support dir, TCP-only topology — written by
# `launch_linux_fixture_c_pair.sh`) and starts the same bundle executable with
# the same environment, so the relaunched process autologs into the account the
# stopped one owned. Rewrites instance.json with the new pid / ws_uri.
#
# Before this existed, `_instanceCtl` fell through to the macOS `.sh`
# launchers on Linux: they look for `Toxee.app` and write under `tool/` (a
# read-only share symlink on a shim checkout), so every relaunch case failed or
# was skipped on Linux.
#
#   launch_toxee_linux_instance.sh <A|B>
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_LINUX_RUNTIME_ROOT:-$REPO_ROOT/build/linux_runtime}"
NAME="${1:?usage: launch_toxee_linux_instance.sh <A|B>}"
INST="$RUNTIME_ROOT/$NAME"
JSON="$INST/instance.json"
PROBE_DART="tool/mcp_test/probe_vm_service.dart"
URI_TIMEOUT="${TOXEE_LINUX_VM_URI_TIMEOUT_SECS:-90}"

die() { echo "[ERROR] launch_toxee_linux_instance.sh: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq missing"
[[ -f "$JSON" ]] || die "$JSON missing - the pair launcher must have run first"

EXE="$(jq -r '.exe // ""' "$JSON")"
VM_PORT="$(jq -r '.vm_port // 0' "$JSON")"
SUPPORT="$(jq -r '.support_dir // ""' "$JSON")"
TCP_ONLY="$(jq -r 'if .tcp_only == true then "1" else "" end' "$JSON")"
RELAY_PORT="$(jq -r '.tcp_relay_port // ""' "$JSON")"
OLD_PID="$(jq -r '.pid // 0' "$JSON")"

[[ -x "$EXE" ]]          || die "recorded exe missing or not executable: '$EXE'"
[[ "$VM_PORT" -gt 0 ]]   || die "recorded vm_port missing in $JSON"
[[ -n "$SUPPORT" ]]      || die "recorded support_dir missing in $JSON"

# A pid can be REUSED after the instance exited on its own, so check that the
# live process is actually this executable before refusing to relaunch.
if [[ "$OLD_PID" -gt 0 ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    if [[ "$(readlink -f "/proc/$OLD_PID/exe" 2>/dev/null || true)" == "$(readlink -f "$EXE")" ]]; then
        die "$NAME pid $OLD_PID is still running - stop it first"
    fi
fi

# Same headless prerequisites the pair launcher established (X display pinned
# to x11, Secret Service): a relaunched instance that lands on Wayland has no
# X window for the OS-input layer, and one without a writable default keyring
# collection wedges its GTK platform thread on the first secure-storage read.
# shellcheck source=tool/mcp_test/_linux_headless_env.sh
source "$MCP_DIR/_linux_headless_env.sh"
toxee_linux_headless_env "$RUNTIME_ROOT" || die "headless session prerequisites failed"

# The relaunch reuses the FIXED VM-service port, and the probe below cannot
# tell "our new instance" from "someone else already listening there" — a
# still-exiting predecessor or a foreign process would be attached to as if it
# were the relaunched app. Wait for the port to actually be free first.
if command -v ss >/dev/null 2>&1; then
    for _ in $(seq 1 25); do
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$VM_PORT\$" || break
        sleep 0.4
    done
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$VM_PORT\$"; then
        die "VM-service port $VM_PORT is still in use; refusing to relaunch $NAME onto a foreign VM"
    fi
else
    # No `ss` means the check cannot be made — say so rather than letting a
    # silent failure read as "the port is free".
    echo "[WARN] ss(8) missing: cannot verify VM-service port $VM_PORT is free" >&2
fi

STDIO="$INST/toxee_stdio.log"
NAME_LOWER="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"
mkdir -p "$INST" "$SUPPORT"
: > "$STDIO"

TCP_ENV=()
if [[ -n "$TCP_ONLY" ]]; then
    TCP_ENV=(TOX_FORCE_TCP_ONLY=1)
    [[ -n "$RELAY_PORT" ]] && TCP_ENV+=(TOX_TCP_RELAY_PORT="$RELAY_PORT")
fi

cd "$REPO_ROOT"
env ${TCP_ENV[@]+"${TCP_ENV[@]}"} \
    TOXEE_APP_SUPPORT_DIR="$SUPPORT" \
    TOXEE_SHARED_PREFS_PREFIX="toxee_${NAME_LOWER}." \
    TOXEE_TCCF_GLOBAL_SUBDIR="multi_instance/$NAME/tccfglobal" \
    TOXEE_LOG_DIR="$INST" \
    FLUTTER_ENGINE_SWITCHES=2 \
    FLUTTER_ENGINE_SWITCH_1="vm-service-port=$VM_PORT" \
    FLUTTER_ENGINE_SWITCH_2="disable-service-auth-codes" \
    nohup "$EXE" >> "$STDIO" 2>&1 < /dev/null &
PID=$!
echo "$PID" > "$INST/toxee.pid"

WS="ws://127.0.0.1:$VM_PORT/ws"
elapsed=0; ok=0
while [[ "$elapsed" -lt "$URI_TIMEOUT" ]]; do
    kill -0 "$PID" 2>/dev/null || die "$NAME toxee exited before its VM service came up; see $STDIO"
    if dart run "$PROBE_DART" "$WS" >/dev/null 2>&1; then ok=1; break; fi
    sleep 1; elapsed=$((elapsed + 1))
done
[[ "$ok" == "1" ]] || die "$NAME VM service not reachable within ${URI_TIMEOUT}s on port $VM_PORT; see $STDIO"

tmp="$JSON.tmp"
jq --argjson pid "$PID" --arg ws "$WS" --arg vm "http://127.0.0.1:$VM_PORT" \
   '.pid = $pid | .ws_uri = $ws | .vm_uri = $vm' "$JSON" > "$tmp" && mv "$tmp" "$JSON"

echo "OK: relaunched $NAME pid=$PID ws_uri=$WS"
