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
# paired_for_e2e restore (TOXEE_FIXTURE_C_RESTORE=paired_for_e2e): the portable
# snapshot (Tox savedata + Dart-side JSON history — the same one macOS/iOS/
# Windows/Linux restore) is streamed into each DEBUG app's sandboxed app-support
# dir (`files/`) via `adb exec-in run-as com.toxee.app tar -x` AFTER the app is
# installed+running but BEFORE the driver's l3_boot_existing_account reads it
# (a fresh boot idles on the login shell and does not touch profiles/, so the
# post-launch copy is race-free). `run-as` works because the automation build is
# debuggable — no root needed. `pm clear` runs pre-launch so a previous run's
# on-device state can't leak into the restored fixture.
#
# Tox connectivity (friendship scenarios need LIVE A<->B delivery): two
# emulators are each behind their own NAT, so UDP never routes between them.
# Same lever as the Windows/Linux pairs — TCP-only + A as the TCP relay — via
# the `debug.toxee.*` system-property fallbacks read by ToxManager.cpp (an app
# process cannot be handed env vars): A gets debug.toxee.tcp_relay_port, both
# get debug.toxee.force_tcp_only, and the relay is plumbed B-guest ->
# (adb reverse) -> host -> (adb forward) -> A-guest on TOXEE_ANDROID_TCP_RELAY_
# PORT (default 3389 — the port add_bootstrap_node's tcp_add_tcp_relay probe
# already tries, so the driver's wireFullMeshBootstrap needs no android branch).
#
# Scope / honest limits:
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

FIXTURES_DIR="$MCP_DIR/fixtures"
FIXTURE_MANIFEST="$FIXTURES_DIR/paired_for_e2e_manifest.json"
RESTORE_ENABLED=0
if [[ -n "$FIXTURE_RESTORE_MODE" ]]; then
    case "$FIXTURE_RESTORE_MODE" in
        paired_for_e2e) RESTORE_ENABLED=1 ;;
        *)
            echo "launch_android_fixture_c_pair.sh: unsupported TOXEE_FIXTURE_C_RESTORE mode for Android: $FIXTURE_RESTORE_MODE (only paired_for_e2e)" >&2
            exit 66 ;;
    esac
    [[ -f "$FIXTURE_MANIFEST" ]] || {
        echo "launch_android_fixture_c_pair.sh: fixture manifest missing: $FIXTURE_MANIFEST" >&2
        exit 66
    }
fi

# TCP relay topology knob (see header). The relay port must stay on 3389 unless
# the tox_add_tcp_relay probe list in tim2tox_ffi.cpp add_bootstrap_node changes.
TCP_RELAY_PORT="${TOXEE_ANDROID_TCP_RELAY_PORT:-3389}"

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

# Stream the paired snapshot for one instance into the DEBUG app's sandboxed
# app-support dir (files/ == getApplicationSupportDirectory() on Android; the
# profile store is <files>/profiles — AppPaths.getProfileStorageRoot's fallback
# branch). Runs AFTER the app is installed+running (run-as needs the package)
# and BEFORE the driver calls l3_boot_existing_account (which is when the app
# first reads profiles/ — a fresh boot idles on the login shell until then).
restore_android_instance() {
    local name="$1" device_id="$2"
    local fixture_dir tox_id friend_id prefix src
    fixture_dir="$(jq -r --arg n "$name" '.instances[$n].fixture_dir // empty' "$FIXTURE_MANIFEST")"
    tox_id="$(jq -r --arg n "$name" '.instances[$n].tox_id // empty' "$FIXTURE_MANIFEST")"
    friend_id="$(jq -r --arg n "$name" '.instances[$n].friend_tox_id // empty' "$FIXTURE_MANIFEST")"
    [[ -n "$fixture_dir" && -n "$tox_id" && -n "$friend_id" ]] || {
        echo "launch_android_fixture_c_pair.sh: manifest missing instances.$name fields" >&2
        return 1
    }
    prefix="${tox_id:0:16}"
    src="$FIXTURES_DIR/$fixture_dir"
    [[ -d "$src" ]] || {
        echo "launch_android_fixture_c_pair.sh: fixture source missing for $name: $src" >&2
        return 1
    }
    # tar stream avoids /data/local/tmp permission games entirely: the archive
    # is unpacked BY the app uid (run-as) directly into files/.
    if ! tar -C "$src" -cf - . \
        | adb -s "$device_id" exec-in run-as "$APP_PACKAGE_ID" sh -c 'mkdir -p files && tar -xf - -C files'; then
        echo "launch_android_fixture_c_pair.sh: $name restore stream failed (device $device_id)" >&2
        return 1
    fi
    # Post-copy integrity checks (mirror restore_fixture_c_pair.sh / the iOS
    # launcher): catch a partial snapshot with a deterministic message instead
    # of a cryptic l3_boot_existing_account failure mid-scenario.
    local profile_file="files/profiles/p_${prefix}/tox_profile.tox"
    local history_file="files/account_data/${prefix}/chat_history/${friend_id}.json"
    adb -s "$device_id" exec-out run-as "$APP_PACKAGE_ID" sh -c "test -f '$profile_file'" || {
        echo "launch_android_fixture_c_pair.sh: $name restore missing profile: $profile_file" >&2
        return 1
    }
    adb -s "$device_id" exec-out run-as "$APP_PACKAGE_ID" sh -c "test -f '$history_file'" || {
        echo "launch_android_fixture_c_pair.sh: $name restore missing chat history: $history_file" >&2
        return 1
    }
    echo "[android-restore] $name <- $src (device $device_id)"
}

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
    # Persist the device id BEFORE any setprop/tunnel side effect (codex P1):
    # if this launch dies before instance.json is written, the stop script can
    # still find the device and clear the debug.toxee.* props + relay tunnels
    # (system properties persist until the device reboots).
    printf '%s\n' "$device_id" >"$inst_dir/device_id.txt"

    adb -s "$device_id" shell am force-stop "$APP_PACKAGE_ID" >/dev/null 2>&1 || true
    # Deterministic fixture on EVERY launch (codex P1): a no-restore launch must
    # start from a truly fresh app, not inherit a previous run's on-device
    # accounts/friendships — the macOS launcher gets this for free by wiping the
    # per-instance runtime dir; `pm clear` is the device equivalent. Harmless
    # when the package is not installed yet (first ever run). The restored
    # snapshot (when requested) is then the ONLY account store the app can find.
    adb -s "$device_id" shell pm clear "$APP_PACKAGE_ID" >/dev/null 2>&1 || true
    # Tox TCP relay topology (see header): TCP-only on both devices; A hosts the
    # relay. debug.toxee.* system properties are the Android stand-in for the
    # TOX_FORCE_TCP_ONLY / TOX_TCP_RELAY_PORT env vars (ToxManager.cpp
    # read_harness_knob) — set BEFORE the app process starts, cleared by
    # stop_android_fixture_c_pair.sh (properties persist until reboot).
    adb -s "$device_id" shell setprop debug.toxee.force_tcp_only 1 >/dev/null 2>&1 || true
    if [[ "$name" == "A" ]]; then
        adb -s "$device_id" shell setprop debug.toxee.tcp_relay_port "$TCP_RELAY_PORT" >/dev/null 2>&1 || true
        # host:PORT -> A-guest:PORT (B's reverse below completes the chain).
        adb -s "$device_id" forward "tcp:$TCP_RELAY_PORT" "tcp:$TCP_RELAY_PORT" >/dev/null 2>&1 \
            || echo "launch_android_fixture_c_pair.sh: WARN adb forward $TCP_RELAY_PORT failed on $device_id (A relay unreachable from host)" >&2
    else
        adb -s "$device_id" shell setprop debug.toxee.tcp_relay_port '' >/dev/null 2>&1 || true
        # B-guest 127.0.0.1:PORT -> host:PORT (-> A's relay via A's forward), so
        # B's add_bootstrap_node(127.0.0.1,...) relay probe lands on A.
        adb -s "$device_id" reverse "tcp:$TCP_RELAY_PORT" "tcp:$TCP_RELAY_PORT" >/dev/null 2>&1 \
            || echo "launch_android_fixture_c_pair.sh: WARN adb reverse $TCP_RELAY_PORT failed on $device_id (B cannot reach A's relay)" >&2
    fi
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
if [[ "$RESTORE_ENABLED" == "1" ]]; then restore_android_instance A "${DEVICES[0]}"; fi
launch_android_instance B "${DEVICES[1]}"
if [[ "$RESTORE_ENABLED" == "1" ]]; then restore_android_instance B "${DEVICES[1]}"; fi

# --- pair.json (same schema as the macOS/iOS launchers) ------------------------
TOXEE_FIXTURE_C_MANIFEST_RESOLVED="$([[ "$RESTORE_ENABLED" == "1" ]] && echo "$FIXTURE_MANIFEST" || true)" \
TOXEE_FIXTURE_C_RESTORE_EFFECTIVE="$([[ "$RESTORE_ENABLED" == "1" ]] && echo "$FIXTURE_RESTORE_MODE" || true)" \
/usr/bin/python3 - "$RUNTIME_ROOT/A/instance.json" "$RUNTIME_ROOT/B/instance.json" "$PAIR_JSON" <<'PY'
import json, os, sys
a_file, b_file, out_file = sys.argv[1:4]
with open(a_file) as fa: a = json.load(fa)
with open(b_file) as fb: b = json.load(fb)
# Contract (matches launch_ios_fixture_c_pair.sh): fixture_restore.restored is
# a restore-report MAP (the manifest content) or null — never a bool.
restore_mode = os.environ.get("TOXEE_FIXTURE_C_RESTORE_EFFECTIVE") or None
restored = None
manifest_path = os.environ.get("TOXEE_FIXTURE_C_MANIFEST_RESOLVED")
if restore_mode is not None and manifest_path and os.path.exists(manifest_path):
    with open(manifest_path) as fm:
        restored = json.load(fm)
doc = {
    "format_version": 1,
    "platform": "android",
    "instances": {"A": a, "B": b},
    "fixture_restore": {
        "mode": restore_mode,
        "report": manifest_path if restored is not None else None,
        "restored": restored,
    },
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
