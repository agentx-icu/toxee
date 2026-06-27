#!/usr/bin/env bash
# Launch ONE debug Toxee.app process for the Fixture C spike.
#
# This is a disposable local harness, not the final reusable fixture layer.
# Its job is to make one instance observable:
#   - per-instance runtime dir
#   - per-instance stdio log
#   - per-instance VM service URI file
#   - recorded pid/start_time/cmdline triple for safe teardown
#
# It does NOT prove full sandbox separation. It does record whether a HOME
# override resulted in a private container tree under the instance runtime.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_MULTI_RUNTIME_ROOT:-$MCP_DIR/.multi_instance_runtime}"
INSTANCE_NAME="${1:-}"
HOST_HOME="${HOME}"
INSTANCE_JSON_WRITER="$MCP_DIR/_write_toxee_instance_json.py"

if [[ -z "$INSTANCE_NAME" ]]; then
    echo "usage: launch_toxee_instance.sh <instance-name>" >&2
    exit 64
fi

# shellcheck source=_multi_instance_lib.sh
. "$MCP_DIR/_multi_instance_lib.sh"

APP_BUNDLE="${TOXEE_APP_BUNDLE:-$REPO_ROOT/build/macos/Build/Products/Debug/Toxee.app}"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Toxee"
APP_EXE_DIR="$APP_BUNDLE/Contents/MacOS"
FFI_LIB="${TIM2TOX_FFI_PATH:-$REPO_ROOT/third_party/tim2tox/build/ffi/libtim2tox_ffi.dylib}"
DEFAULT_SUPPORT_LOG="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/flutter_client.log"
VM_URI_TIMEOUT_SECS="${TOXEE_MULTI_VM_URI_TIMEOUT_SECS:-45}"
POST_START_STABILIZE_SECS="${TOXEE_MULTI_POST_START_STABILIZE_SECS:-2}"
# `direct` preserves the DHT/friend reachability path used by Fixture C.
# `open` is available for LaunchServices experiments, but currently does not
# provide reliable ping/pong delivery between the paired instances.
LAUNCH_METHOD="${TOXEE_MULTI_LAUNCH_METHOD:-direct}"

INSTANCE_DIR="$RUNTIME_ROOT/$INSTANCE_NAME"
HOME_OVERRIDE_DIR="$INSTANCE_DIR/home"
SANDBOX_APP_SUPPORT_ROOT="$HOST_HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app"
APP_SUPPORT_OVERRIDE_DIR="${TOXEE_INSTANCE_APP_SUPPORT_DIR:-$SANDBOX_APP_SUPPORT_ROOT/multi_instance/$INSTANCE_NAME}"
INSTANCE_NAME_LOWER="$(printf '%s' "$INSTANCE_NAME" | tr '[:upper:]' '[:lower:]')"
SHARED_PREFS_PREFIX="toxee_${INSTANCE_NAME_LOWER}."
TCCF_GLOBAL_SUBDIR="multi_instance/${INSTANCE_NAME}/tccfglobal"
BUILD_DIR="$INSTANCE_DIR/build"
STDIO_LOG="$BUILD_DIR/toxee_stdio.log"
VM_URI_FILE="$BUILD_DIR/vm_service_uri.txt"
JSON_FILE="$INSTANCE_DIR/instance.json"
APP_SUPPORT_LOG="$APP_SUPPORT_OVERRIDE_DIR/flutter_client.log"
APP_SUPPORT_LOG_DIR="$APP_SUPPORT_OVERRIDE_DIR/logs"
PRE_LAUNCH_APP_LOGS_FILE="$BUILD_DIR/prelaunch_app_logs.txt"

mkdir -p "$BUILD_DIR" "$HOME_OVERRIDE_DIR" "$APP_SUPPORT_OVERRIDE_DIR" "$APP_SUPPORT_LOG_DIR"
[[ -x "$APP_EXECUTABLE" ]] || {
    echo "launch_toxee_instance.sh: app executable missing: $APP_EXECUTABLE" >&2
    exit 66
}
[[ -f "$FFI_LIB" ]] || {
    echo "launch_toxee_instance.sh: FFI dylib missing: $FFI_LIB" >&2
    exit 66
}

: > "$STDIO_LOG"
rm -f "$VM_URI_FILE"
BASELINE_PIDS="$(_mi_pids_for_executable "$APP_EXECUTABLE")"
find "$APP_SUPPORT_LOG_DIR" -maxdepth 1 -type f -name 'app_*.log' -print \
    >"$PRE_LAUNCH_APP_LOGS_FILE" 2>/dev/null || true

cleanup_on_fail() {
    if [[ -n "${LAUNCHED_PID:-}" ]]; then
        _mi_stop_with_grace "$LAUNCHED_PID" 5 || true
        LAUNCHED_PID=""
    fi
}
trap cleanup_on_fail EXIT

if [[ "$LAUNCH_METHOD" == "open" && "$(uname -s)" == "Darwin" ]]; then
    open -n -g "$APP_BUNDLE" \
        --stdout "$STDIO_LOG" \
        --stderr "$STDIO_LOG" \
        --env "HOME=$HOME_OVERRIDE_DIR" \
        --env "TOXEE_APP_SUPPORT_DIR=$APP_SUPPORT_OVERRIDE_DIR" \
        --env "TOXEE_SHARED_PREFS_PREFIX=$SHARED_PREFS_PREFIX" \
        --env "TOXEE_TCCF_GLOBAL_SUBDIR=$TCCF_GLOBAL_SUBDIR" \
        --env "TIM2TOX_FFI_PATH=$FFI_LIB" \
        --env "TOX_FORCE_TCP_ONLY=${TOX_FORCE_TCP_ONLY:-}" \
        --env "TOX_TCP_RELAY_PORT=${TOX_TCP_RELAY_PORT:-}" \
        --env "DYLD_FALLBACK_LIBRARY_PATH=$APP_EXE_DIR:${DYLD_FALLBACK_LIBRARY_PATH:-}" \
        --env "TOXEE_LOG_DIR=$BUILD_DIR" \
        --env "FLUTTER_ENGINE_SWITCHES=2" \
        --env "FLUTTER_ENGINE_SWITCH_1=vm-service-port=0" \
        --env "FLUTTER_ENGINE_SWITCH_2=disable-service-auth-codes"
    LAUNCHED_PID=""
else
    # `trap '' HUP` in a subshell was not enough here: once the launcher shell
    # exited, the direct-launched GUI process still died within a few seconds on
    # macOS. `nohup` keeps the debug app alive after this script returns so the
    # later VM attach / restored-boot probes connect to a real, persistent pid.
    env \
        HOME="$HOME_OVERRIDE_DIR" \
        TOXEE_APP_SUPPORT_DIR="$APP_SUPPORT_OVERRIDE_DIR" \
        TOXEE_SHARED_PREFS_PREFIX="$SHARED_PREFS_PREFIX" \
        TOXEE_TCCF_GLOBAL_SUBDIR="$TCCF_GLOBAL_SUBDIR" \
        TIM2TOX_FFI_PATH="$FFI_LIB" \
        TOX_FORCE_TCP_ONLY="${TOX_FORCE_TCP_ONLY:-}" \
        TOX_TCP_RELAY_PORT="${TOX_TCP_RELAY_PORT:-}" \
        DYLD_FALLBACK_LIBRARY_PATH="$APP_EXE_DIR:${DYLD_FALLBACK_LIBRARY_PATH:-}" \
        TOXEE_LOG_DIR="$BUILD_DIR" \
        FLUTTER_ENGINE_SWITCHES=2 \
        FLUTTER_ENGINE_SWITCH_1="vm-service-port=0" \
        FLUTTER_ENGINE_SWITCH_2="disable-service-auth-codes" \
        /usr/bin/nohup "$APP_EXECUTABLE" >>"$STDIO_LOG" 2>&1 </dev/null &
    LAUNCHED_PID=$!
fi

elapsed=0
vm_uri=""
while [[ "$elapsed" -lt "$VM_URI_TIMEOUT_SECS" ]]; do
    if [[ -z "$LAUNCHED_PID" ]]; then
        new_pids="$(_mi_new_pids_since_baseline "$APP_EXECUTABLE" "$BASELINE_PIDS")"
        if [[ -n "$new_pids" ]]; then
            LAUNCHED_PID="$(printf '%s\n' "$new_pids" | head -1)"
        fi
    fi
    if [[ -n "$LAUNCHED_PID" ]] && ! kill -0 "$LAUNCHED_PID" 2>/dev/null; then
        echo "launch_toxee_instance.sh: Toxee exited before VM URI was observed; see $STDIO_LOG" >&2
        exit 1
    fi
    vm_uri="$(grep -oE 'http://127\.0\.0\.1:[0-9]+(/[A-Za-z0-9_=-]+)?/?' "$STDIO_LOG" 2>/dev/null | head -1 || true)"
    if [[ -n "$vm_uri" ]]; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

if [[ -z "$vm_uri" ]]; then
    echo "launch_toxee_instance.sh: timed out after ${VM_URI_TIMEOUT_SECS}s waiting for VM URI; see $STDIO_LOG" >&2
    exit 1
fi

if [[ -z "$LAUNCHED_PID" ]]; then
    new_pids="$(_mi_new_pids_since_baseline "$APP_EXECUTABLE" "$BASELINE_PIDS")"
    if [[ -n "$new_pids" ]]; then
        LAUNCHED_PID="$(printf '%s\n' "$new_pids" | head -1)"
    fi
fi
if [[ -z "$LAUNCHED_PID" ]]; then
    echo "launch_toxee_instance.sh: VM URI appeared but launched pid could not be resolved for $APP_EXECUTABLE" >&2
    exit 1
fi

if [[ "$POST_START_STABILIZE_SECS" -gt 0 ]]; then
    sleep "$POST_START_STABILIZE_SECS"
    if ! kill -0 "$LAUNCHED_PID" 2>/dev/null; then
        echo "launch_toxee_instance.sh: Toxee died during post-start stabilization; see $STDIO_LOG" >&2
        exit 1
    fi
fi

vm_uri="${vm_uri%/}"
ws_uri="${vm_uri/http:/ws:}/ws"
printf '%s\n' "$ws_uri" > "$VM_URI_FILE"

start_time="$(_mi_ps_lstart "$LAUNCHED_PID")"
cmdline="$(_mi_ps_args "$LAUNCHED_PID")"
if [[ -z "$start_time" || -z "$cmdline" ]]; then
    echo "launch_toxee_instance.sh: could not capture process triple for pid $LAUNCHED_PID" >&2
    exit 1
fi

actual_app_support_log="$(/usr/bin/python3 - "$APP_SUPPORT_LOG_DIR" "$PRE_LAUNCH_APP_LOGS_FILE" <<'PY'
import glob
import os
import sys
import time

log_dir, baseline_file = sys.argv[1:3]
baseline = set()
if os.path.exists(baseline_file):
    with open(baseline_file, encoding="utf-8") as fh:
        baseline = {line.strip() for line in fh if line.strip()}

def newest(paths):
    return max(paths, key=lambda p: os.stat(p).st_mtime)

deadline = time.time() + 8
selected = ""
while time.time() < deadline:
    files = glob.glob(os.path.join(log_dir, "app_*.log"))
    if files:
        new_files = [path for path in files if path not in baseline]
        selected = newest(new_files) if new_files else newest(files)
        if new_files:
            break
    time.sleep(0.25)

if selected:
    print(selected)
PY
)"
if [[ -n "$actual_app_support_log" ]]; then
    APP_SUPPORT_LOG="$actual_app_support_log"
fi

python3 "$INSTANCE_JSON_WRITER" \
    --json-file "$JSON_FILE" \
    --instance-name "$INSTANCE_NAME" \
    --pid "$LAUNCHED_PID" \
    --start-time "$start_time" \
    --cmdline "$cmdline" \
    --home-override-dir "$HOME_OVERRIDE_DIR" \
    --app-support-override-dir "$APP_SUPPORT_OVERRIDE_DIR" \
    --shared-prefs-prefix "$SHARED_PREFS_PREFIX" \
    --tccf-global-subdir "$TCCF_GLOBAL_SUBDIR" \
    --build-dir "$BUILD_DIR" \
    --stdio-log "$STDIO_LOG" \
    --vm-uri-file "$VM_URI_FILE" \
    --vm-uri "$vm_uri" \
    --ws-uri "$ws_uri" \
    --app-support-log "$APP_SUPPORT_LOG" \
    --default-support-log "$DEFAULT_SUPPORT_LOG"

LAUNCHED_PID=""
trap - EXIT

echo "OK: launched $INSTANCE_NAME pid=$(jq -r '.pid' "$JSON_FILE") ws_uri=$(jq -r '.ws_uri' "$JSON_FILE")"
echo "json: $JSON_FILE"
