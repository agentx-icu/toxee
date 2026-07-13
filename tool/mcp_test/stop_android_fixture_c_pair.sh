#!/usr/bin/env bash
# Stop the A/B Android pair previously launched by launch_android_fixture_c_pair.sh.
#
# Kills each instance's `flutter run` host process, force-stops the app on its
# device, removes the IRC adb-reverse, and deletes pair.json.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_ANDROID_RUNTIME_ROOT:-$MCP_DIR/.android_runtime}"
APP_PACKAGE_ID="com.toxee.app"
IRC_LOOPBACK_PORT="${TOXEE_IRC_LOOPBACK_PORT:-16667}"
TCP_RELAY_PORT="${TOXEE_ANDROID_TCP_RELAY_PORT:-3389}"

stop_android_instance() {
    local name="$1"
    local inst_dir="$RUNTIME_ROOT/$name"
    local pid_file="$inst_dir/build/flutter_run.pid"
    local json="$inst_dir/instance.json"

    if [[ -f "$pid_file" ]]; then
        local pid
        pid="$(cat "$pid_file" 2>/dev/null || true)"
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
        fi
    fi

    local device_id=""
    if [[ -f "$json" ]] && command -v jq >/dev/null 2>&1; then
        device_id="$(jq -r '.device_id // empty' "$json" 2>/dev/null || true)"
    fi
    # Fallback (codex P1): a launch that died before writing instance.json has
    # already applied setprop/tunnel side effects — the launcher persists the
    # device id first, so the cleanup below still reaches the right device.
    if [[ -z "$device_id" && -f "$inst_dir/device_id.txt" ]]; then
        device_id="$(cat "$inst_dir/device_id.txt" 2>/dev/null || true)"
    fi
    if [[ -n "$device_id" ]] && command -v adb >/dev/null 2>&1; then
        adb -s "$device_id" shell am force-stop "$APP_PACKAGE_ID" >/dev/null 2>&1 || true
        adb -s "$device_id" reverse --remove "tcp:$IRC_LOOPBACK_PORT" >/dev/null 2>&1 || true
        # Clear the Tox harness knobs (system properties persist until the
        # device reboots — a lingering force_tcp_only would silently change
        # LATER single-instance runs on the same device, e.g. --action l3)
        # and drop the relay tunnels the launcher set up.
        adb -s "$device_id" shell setprop debug.toxee.force_tcp_only '' >/dev/null 2>&1 || true
        adb -s "$device_id" shell setprop debug.toxee.tcp_relay_port '' >/dev/null 2>&1 || true
        adb -s "$device_id" forward --remove "tcp:$TCP_RELAY_PORT" >/dev/null 2>&1 || true
        adb -s "$device_id" reverse --remove "tcp:$TCP_RELAY_PORT" >/dev/null 2>&1 || true
    fi
}

stop_android_instance B
stop_android_instance A
rm -f "$RUNTIME_ROOT/pair.json"

echo "OK: stopped Android Fixture C pair"
