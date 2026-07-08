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

    if [[ -f "$json" ]] && command -v jq >/dev/null 2>&1; then
        local device_id
        device_id="$(jq -r '.device_id // empty' "$json" 2>/dev/null || true)"
        if [[ -n "$device_id" ]] && command -v adb >/dev/null 2>&1; then
            adb -s "$device_id" shell am force-stop "$APP_PACKAGE_ID" >/dev/null 2>&1 || true
            adb -s "$device_id" reverse --remove "tcp:$IRC_LOOPBACK_PORT" >/dev/null 2>&1 || true
        fi
    fi
}

stop_android_instance B
stop_android_instance A
rm -f "$RUNTIME_ROOT/pair.json"

echo "OK: stopped Android Fixture C pair"
