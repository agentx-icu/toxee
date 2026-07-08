#!/usr/bin/env bash
# Launch A + B Android Toxee instances for real-App UI automation.
#
# Sibling of launch_fixture_c_pair.sh (macOS) / launch_ios_fixture_c_pair.sh
# (iOS Simulator). It produces the SAME pair.json contract the unified runner
# (fixture_c_unified_runner.dart) consumes: per-instance ws_uri + pid, plus a
# fixture_restore block. The two instances run on TWO distinct adb devices /
# emulators; `flutter run --machine` builds, installs, auto-forwards each
# device's Dart VM service to the host, and announces the host-side ws URI.
#
# Topology: the unified runner + the real-UI driver (drive_real_ui_pair.dart)
# run ON THIS HOST and attach to the forwarded ws URIs over 127.0.0.1. The driver
# resolves each Inst's platform from TOXEE_REAL_UI_PLATFORM=android and drives
# purely via synthetic flutter_skill / L3 RPC (no host osascript — the apps live
# on devices). For irc_join_channel_loopback_live the host-side LocalIrcServer is
# reached from the device via `adb reverse tcp:<port> tcp:<port>` (set up below).
#
# Scope / honest limits:
#   - No paired_for_e2e RESTORE on Android yet: pushing a snapshot into a device's
#     sandboxed app-data dir needs run-as/root, so friendship-dependent scenarios
#     are out of scope here (the IRC cases this launcher targets are no-friend).
#     A restore request fails fast with a clear message rather than silently
#     launching an un-restored pair.
#   - The native libirc_client.so is not built for Android, so the
#     irc_join_channel_loopback_live JOIN (which needs the native socket) cannot
#     complete live until that .so is built + placed in jniLibs; the portable
#     irc_join_channel_real_controls case (pure Dart/Prefs) needs no native lib.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_ANDROID_RUNTIME_ROOT:-$MCP_DIR/.android_runtime}"
PAIR_JSON="$RUNTIME_ROOT/pair.json"
APP_PACKAGE_ID="com.toxee.app"
JNI_LIBS_DIR="$REPO_ROOT/android/app/src/main/jniLibs"
FIXTURE_RESTORE_MODE="${TOXEE_FIXTURE_C_RESTORE:-}"
MCP_BINDING="${MCP_BINDING:-skill}"
TOXEE_L3_TEST="${TOXEE_L3_TEST:-true}"
MODE="${TOXEE_ANDROID_MODE:-debug}"
VM_URI_TIMEOUT_SECS="${TOXEE_ANDROID_VM_URI_TIMEOUT_SECS:-360}"
# Fixed loopback IRC port to adb-reverse so the device can reach the host-side
# LocalIrcServer. Matches _androidIrcLoopbackPort in fixture_c_unified_runner.dart.
IRC_LOOPBACK_PORT="${TOXEE_IRC_LOOPBACK_PORT:-16667}"

command -v flutter >/dev/null 2>&1 || { echo "launch_android_fixture_c_pair.sh: flutter not found on PATH" >&2; exit 66; }
command -v adb >/dev/null 2>&1 || { echo "launch_android_fixture_c_pair.sh: adb not found on PATH" >&2; exit 66; }
command -v jq >/dev/null 2>&1 || { echo "launch_android_fixture_c_pair.sh: jq required" >&2; exit 66; }

if [[ -n "$FIXTURE_RESTORE_MODE" ]]; then
    echo "launch_android_fixture_c_pair.sh: TOXEE_FIXTURE_C_RESTORE=$FIXTURE_RESTORE_MODE is not supported on Android" >&2
    echo "  (restoring a paired snapshot into a sandboxed device app-data dir needs run-as/root;" >&2
    echo "   only no-friend real-UI scenarios — e.g. the IRC cases — are wired for Android today)." >&2
    exit 66
fi

if [[ "$MODE" != "debug" ]]; then
    # kDebugMode tree-shakes the L3 + flutter_skill driving surface out of
    # profile/release, so the driver could never attach.
    echo "launch_android_fixture_c_pair.sh: only --debug is supported (L3 surface is debug-only)" >&2
    exit 66
fi

if ! find "$JNI_LIBS_DIR" -type f -name 'libtim2tox_ffi.so' 2>/dev/null | grep -q .; then
    echo "launch_android_fixture_c_pair.sh: missing tim2tox Android FFI library under $JNI_LIBS_DIR/<abi>/libtim2tox_ffi.so" >&2
    echo "  Build it first: tool/build_android_ffi.sh (see run_toxee_android.sh --ffi-lib-dir)." >&2
    exit 66
fi

mkdir -p "$RUNTIME_ROOT"
rm -rf "$RUNTIME_ROOT/A" "$RUNTIME_ROOT/B" "$PAIR_JSON"

# Partial-launch guard: under `set -e`, a failed B launch (after A is up) exits
# the script and would otherwise leak the running A instance. On any non-zero
# exit, tear the pair down (no-op when nothing was launched yet).
cleanup_on_fail() {
    local rc=$?
    if [[ "$rc" -ne 0 ]]; then
        bash "$MCP_DIR/stop_android_fixture_c_pair.sh" >/dev/null 2>&1 || true
    fi
}
trap cleanup_on_fail EXIT

# --- device selection: two distinct adb devices (override via env) -------------
select_android_devices() {
    if [[ -n "${TOXEE_ANDROID_DEVICE_ID_A:-}" && -n "${TOXEE_ANDROID_DEVICE_ID_B:-}" ]]; then
        printf '%s\n%s\n' "$TOXEE_ANDROID_DEVICE_ID_A" "$TOXEE_ANDROID_DEVICE_ID_B"
        return 0
    fi
    adb devices | awk 'NR>1 && $2=="device" {print $1}'
}

DEVICES=()
while IFS= read -r dev; do
    [[ -n "$dev" ]] && DEVICES+=("$dev")
done < <(select_android_devices) || true
if [[ "${#DEVICES[@]}" -lt 2 ]]; then
    echo "launch_android_fixture_c_pair.sh: need two connected Android devices/emulators for A/B" >&2
    echo "  (or set TOXEE_ANDROID_DEVICE_ID_A / TOXEE_ANDROID_DEVICE_ID_B). Saw: ${DEVICES[*]:-none}" >&2
    exit 66
fi
if [[ "${DEVICES[0]}" == "${DEVICES[1]}" ]]; then
    echo "launch_android_fixture_c_pair.sh: A/B device ids must differ" >&2
    exit 66
fi

# flutter pub get if needed (mirrors run_toxee_android.sh).
if [[ ! -f "$REPO_ROOT/pubspec.lock" ]] || [[ "$REPO_ROOT/pubspec.yaml" -nt "$REPO_ROOT/pubspec.lock" ]]; then
    (cd "$REPO_ROOT" && flutter pub get) >/dev/null 2>&1 || true
fi

# --- per-instance launch -------------------------------------------------------
# Launches `flutter run -d <device> --debug --machine` for one instance, captures
# the host-forwarded ws URI from the --machine JSON stream (app.debugPort ->
# {"wsUri":"ws://127.0.0.1:<host-port>/.../ws"}), records the flutter-run pid,
# sets up the IRC adb-reverse, and writes instance.json.
launch_android_instance() {
    local name="$1" device_id="$2"
    local inst_dir="$RUNTIME_ROOT/$name"
    local build_dir="$inst_dir/build"
    local stdio_log="$build_dir/flutter_run.log"
    local pid_file="$build_dir/flutter_run.pid"
    mkdir -p "$build_dir"
    : >"$stdio_log"

    adb -s "$device_id" shell am force-stop "$APP_PACKAGE_ID" >/dev/null 2>&1 || true
    # adb reverse so the device's 127.0.0.1:<port> tunnels to this host's
    # LocalIrcServer (used by irc_join_channel_loopback_live). Harmless for other
    # scenarios (the port is simply unused).
    adb -s "$device_id" reverse "tcp:$IRC_LOOPBACK_PORT" "tcp:$IRC_LOOPBACK_PORT" >/dev/null 2>&1 \
        || echo "launch_android_fixture_c_pair.sh: WARN adb reverse failed on $device_id (IRC loopback may be unreachable)" >&2

    nohup flutter run -d "$device_id" --"$MODE" --machine \
        --dart-define=FLUTTER_BUILD_MODE="$MODE" \
        --dart-define=MCP_BINDING="$MCP_BINDING" \
        --dart-define=TOXEE_L3_TEST="$TOXEE_L3_TEST" \
        >>"$stdio_log" 2>&1 </dev/null &
    local flutter_pid=$!
    echo "$flutter_pid" >"$pid_file"
    disown "$flutter_pid" 2>/dev/null || true

    local ws_uri="" elapsed=0
    while [[ "$elapsed" -lt "$VM_URI_TIMEOUT_SECS" ]]; do
        if ! kill -0 "$flutter_pid" 2>/dev/null; then
            echo "launch_android_fixture_c_pair.sh: $name flutter run exited before the VM URI appeared; see $stdio_log" >&2
            return 1
        fi
        ws_uri="$(grep -oE '"wsUri":"ws://[^"]+"' "$stdio_log" 2>/dev/null \
            | head -1 | sed -E 's/.*"wsUri":"([^"]*)".*/\1/' || true)"
        [[ -n "$ws_uri" ]] && break
        sleep 1
        elapsed=$((elapsed + 1))
    done
    if [[ -z "$ws_uri" ]]; then
        echo "launch_android_fixture_c_pair.sh: $name timed out after ${VM_URI_TIMEOUT_SECS}s waiting for the VM URI; see $stdio_log" >&2
        kill "$flutter_pid" 2>/dev/null || true
        return 1
    fi

    local vm_uri="${ws_uri%/ws}"
    vm_uri="${vm_uri/ws:/http:}"
    /usr/bin/python3 - "$inst_dir/instance.json" "$name" "$flutter_pid" "$device_id" \
        "$inst_dir" "$stdio_log" "$vm_uri" "$ws_uri" <<'PY'
import json, sys
out, name, pid, device_id, home_dir, stdio_log, vm_uri, ws_uri = sys.argv[1:9]
doc = {
    "format_version": 1,
    "instance_name": name,
    "pid": int(pid),
    "device_id": device_id,
    "home_override_dir": home_dir,
    "stdio_log": stdio_log,
    "vm_uri": vm_uri,
    "ws_uri": ws_uri,
    "app_support_log_exists": False,
}
with open(out, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
    echo "[android] $name pid=$flutter_pid device=$device_id ws_uri=$ws_uri"
}

# Launch A then B SEQUENTIALLY: the first `flutter run` does the full build; the
# second is incremental, so they never race the shared build dir.
launch_android_instance A "${DEVICES[0]}"
launch_android_instance B "${DEVICES[1]}"

# --- pair.json (same schema as the macOS/iOS launchers) ------------------------
/usr/bin/python3 - "$RUNTIME_ROOT/A/instance.json" "$RUNTIME_ROOT/B/instance.json" "$PAIR_JSON" <<'PY'
import json, sys
a_file, b_file, out_file = sys.argv[1:4]
with open(a_file) as fa: a = json.load(fa)
with open(b_file) as fb: b = json.load(fb)
doc = {
    "format_version": 1,
    "platform": "android",
    "instances": {"A": a, "B": b},
    "fixture_restore": {"mode": None, "report": None, "restored": None},
    "checks": {
        "distinct_pids": a["pid"] != b["pid"],
        "distinct_ws_uris": a["ws_uri"] != b["ws_uri"],
        "distinct_vm_ports": a["vm_uri"] != b["vm_uri"],
        "distinct_devices": a["device_id"] != b["device_id"],
    },
}
with open(out_file, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY

echo "OK: launched Android Fixture C pair"
echo "pair json: $PAIR_JSON"
echo "A ws_uri: $(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
echo "B ws_uri: $(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"
