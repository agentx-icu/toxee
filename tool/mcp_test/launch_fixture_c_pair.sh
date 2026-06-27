#!/usr/bin/env bash
# Launch A + B for the Fixture C multi-instance spike.
#
# Scope for this disposable harness:
#   - start A and B as separate OS processes
#   - record different VM URIs / ws URIs
#   - report whether HOME override yielded per-instance support logs
#   - provide a single teardown entry point
#
# It does NOT yet drive friend-add / ping-pong. The emitted pair.json is the
# hand-off contract for a future MCP step.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_MULTI_RUNTIME_ROOT:-$MCP_DIR/.multi_instance_runtime}"
PAIR_JSON="$RUNTIME_ROOT/pair.json"
APP_BUNDLE="${TOXEE_APP_BUNDLE:-$REPO_ROOT/build/macos/Build/Products/Debug/Toxee.app}"
COPIES_DIR="$RUNTIME_ROOT/app_copies"
VM_PROBE_DART="$MCP_DIR/probe_vm_service.dart"
CONTAINER_MULTI_ROOT="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/multi_instance"
FIXTURE_RESTORE_MODE="${TOXEE_FIXTURE_C_RESTORE:-}"
FIXTURE_RESTORE_REPORT="$CONTAINER_MULTI_ROOT/fixture_c_pair_restore.json"
REQUESTED_LAUNCH_METHOD="${TOXEE_MULTI_LAUNCH_METHOD:-}"
ALLOW_OPEN_FALLBACK="${TOXEE_MULTI_ALLOW_OPEN_FALLBACK:-1}"
POST_PROBE_STABILITY_SECS="${TOXEE_MULTI_POST_PROBE_STABILITY_SECS:-8}"
SKIP_VM_PROBE="${TOXEE_MULTI_SKIP_VM_PROBE:-0}"

# Restored-fixture launches currently prioritize VM attach stability over the
# direct-binary path: on this host, a restored direct launch can probe cleanly
# and still die shortly afterward, while LaunchServices (`open`) remains alive
# long enough for the restored-boot drivers to do real work. Keep direct as the
# global default, but switch restored pair launches to `open` unless the caller
# explicitly overrides the method.
if [[ -n "$FIXTURE_RESTORE_MODE" && -z "$REQUESTED_LAUNCH_METHOD" ]]; then
    export TOXEE_MULTI_LAUNCH_METHOD=open
    REQUESTED_LAUNCH_METHOD="open"
fi

wait_for_instance_json() {
    local path="$1"
    local timeout="${2:-20}"
    local elapsed=0
    while [[ "$elapsed" -lt "$timeout" ]]; do
        if [[ -f "$path" ]] && jq -e '.ws_uri | length > 0' "$path" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "launch_fixture_c_pair.sh: timed out waiting for instance json: $path" >&2
    return 1
}

probe_vm_service_retry() {
    local ws_uri="$1"
    local timeout="${2:-15}"
    local elapsed=0
    while [[ "$elapsed" -lt "$timeout" ]]; do
        if dart run "$VM_PROBE_DART" "$ws_uri"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "launch_fixture_c_pair.sh: timed out probing VM service: $ws_uri" >&2
    return 1
}

verify_post_probe_stability() {
    if [[ "$SKIP_VM_PROBE" == "1" ]]; then
        return 0
    fi
    local a_json="$1"
    local b_json="$2"
    local wait_secs="${3:-0}"
    local a_pid
    local b_pid
    local a_ws
    local b_ws
    a_pid="$(jq -r '.pid' "$a_json")"
    b_pid="$(jq -r '.pid' "$b_json")"
    a_ws="$(jq -r '.ws_uri' "$a_json")"
    b_ws="$(jq -r '.ws_uri' "$b_json")"
    if [[ "$wait_secs" -gt 0 ]]; then
        sleep "$wait_secs"
    fi
    kill -0 "$a_pid"
    kill -0 "$b_pid"
    probe_vm_service_retry "$a_ws"
    probe_vm_service_retry "$b_ws"
}

write_pair_json() {
    /usr/bin/python3 - "$RUNTIME_ROOT/A/instance.json" "$RUNTIME_ROOT/B/instance.json" "$PAIR_JSON" "$FIXTURE_RESTORE_MODE" "$FIXTURE_RESTORE_REPORT" <<'PY'
import json
import os
import sys

a_file, b_file, out_file, fixture_restore_mode, fixture_restore_report = sys.argv[1:6]
with open(a_file) as fa:
    a = json.load(fa)
with open(b_file) as fb:
    b = json.load(fb)
restore = None
if fixture_restore_mode in {"paired", "paired_for_e2e"} and os.path.exists(fixture_restore_report):
    with open(fixture_restore_report) as fr:
        restore = json.load(fr)

doc = {
    "format_version": 1,
    "instances": {"A": a, "B": b},
    "fixture_restore": {
        "mode": fixture_restore_mode or None,
        "report": fixture_restore_report if restore is not None else None,
        "restored": restore,
    },
    "checks": {
        "distinct_pids": a["pid"] != b["pid"],
        "distinct_ws_uris": a["ws_uri"] != b["ws_uri"],
        "distinct_vm_ports": a["vm_uri"] != b["vm_uri"],
        "home_override_dirs_differ": a["home_override_dir"] != b["home_override_dir"],
        "app_support_log_exists_in_a_home": a["app_support_log_exists"],
        "app_support_log_exists_in_b_home": b["app_support_log_exists"],
    },
}
with open(out_file, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
}

launch_pair_once() (
    set -euo pipefail
    mkdir -p "$RUNTIME_ROOT"
    mkdir -p "$COPIES_DIR"
    rm -rf "$RUNTIME_ROOT/A" "$RUNTIME_ROOT/B"
    rm -rf "$CONTAINER_MULTI_ROOT/A" "$CONTAINER_MULTI_ROOT/B"
    # Disposable spike harness: clear the shared macOS defaults domain so both
    # instances start from a blank login state. Without this, a previous run's
    # shared `account_list` can turn the register page into a saved-account page
    # before the pair driver ever starts.
    defaults delete com.toxee.app >/dev/null 2>&1 || true
    killall cfprefsd >/dev/null 2>&1 || true

    if [[ "$FIXTURE_RESTORE_MODE" == "paired" || "$FIXTURE_RESTORE_MODE" == "paired_for_e2e" ]]; then
        TOXEE_FIXTURE_C_RESTORE_ROOT="$CONTAINER_MULTI_ROOT" \
            "$MCP_DIR/restore_fixture_c_pair.sh"
    fi

    # Same-host TCP-only mode (opt-in via TOXEE_PAIR_TCP_ONLY=1). On a single host
    # two sandboxed Toxee processes cannot reliably exchange NGC group traffic over
    # UDP loopback (c-toxcore gcc_send_packet early-returns UDP-only once a link is
    # inferred "direct", and same-host outbound UDP loopback is black-holed). Force
    # both peers TCP-only and make A a localhost TCP relay (port 3389, which B's
    # add_bootstrap_node already probes) so group/conference delivery is
    # deterministic. Empty when not opted in → identical to the previous default.
    A_TCP_ENV=()
    B_TCP_ENV=()
    if [[ "${TOXEE_PAIR_TCP_ONLY:-}" == "1" || "${TOXEE_PAIR_TCP_ONLY:-}" == "true" ]]; then
        A_TCP_ENV=(TOX_FORCE_TCP_ONLY=1 TOX_TCP_RELAY_PORT="${TOXEE_PAIR_TCP_RELAY_PORT:-3389}")
        B_TCP_ENV=(TOX_FORCE_TCP_ONLY=1)
        echo "launch_fixture_c_pair.sh: TCP-only same-host mode ON (A relay port ${TOXEE_PAIR_TCP_RELAY_PORT:-3389})" >&2
    fi

    env ${A_TCP_ENV[@]+"${A_TCP_ENV[@]}"} "$MCP_DIR/launch_toxee_instance.sh" A
    wait_for_instance_json "$RUNTIME_ROOT/A/instance.json"
    A_WS_URI="$(jq -r '.ws_uri' "$RUNTIME_ROOT/A/instance.json")"
    if [[ "$SKIP_VM_PROBE" != "1" ]]; then
        probe_vm_service_retry "$A_WS_URI"
    fi
    # Empirically, launching both instances from the exact same .app path leaves the
    # direct-launch VM service attach path unhealthy (`Connection closed before full
    # header was received`). A physical copy for B avoids that collision and keeps
    # the rest of the harness unchanged.
    APP_B_COPY="$COPIES_DIR/ToxeeB-$(date +%s)-$$.app"
    /usr/bin/ditto "$APP_BUNDLE" "$APP_B_COPY"
    env ${B_TCP_ENV[@]+"${B_TCP_ENV[@]}"} TOXEE_APP_BUNDLE="$APP_B_COPY" "$MCP_DIR/launch_toxee_instance.sh" B
    wait_for_instance_json "$RUNTIME_ROOT/B/instance.json"
    B_WS_URI="$(jq -r '.ws_uri' "$RUNTIME_ROOT/B/instance.json")"
    if [[ "$SKIP_VM_PROBE" != "1" ]]; then
        probe_vm_service_retry "$A_WS_URI"
        probe_vm_service_retry "$B_WS_URI"
    fi
    verify_post_probe_stability \
        "$RUNTIME_ROOT/A/instance.json" \
        "$RUNTIME_ROOT/B/instance.json" \
        "$POST_PROBE_STABILITY_SECS"
    write_pair_json

    echo "OK: launched Fixture C pair"
    echo "pair json: $PAIR_JSON"
    echo "A ws_uri: $(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
    echo "B ws_uri: $(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"
)

set +e
launch_pair_once
launch_rc=$?
set -e

if [[ "$launch_rc" -ne 0 ]]; then
    if [[ "$ALLOW_OPEN_FALLBACK" != "0" && "$REQUESTED_LAUNCH_METHOD" != "open" ]]; then
        echo "WARN: pair launch became unhealthy with method=${REQUESTED_LAUNCH_METHOD:-direct}; retrying with TOXEE_MULTI_LAUNCH_METHOD=open" >&2
        "$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true
        exec env TOXEE_MULTI_LAUNCH_METHOD=open TOXEE_MULTI_ALLOW_OPEN_FALLBACK=0 "$0"
    fi
    exit "$launch_rc"
fi
