#!/usr/bin/env bash
# Launch A + B iOS Simulator Toxee instances for real-App UI automation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_IOS_RUNTIME_ROOT:-$MCP_DIR/.ios_runtime}"
PAIR_JSON="$RUNTIME_ROOT/pair.json"
VM_PROBE_DART="$MCP_DIR/probe_vm_service.dart"
FIXTURE_RESTORE_MODE="${TOXEE_FIXTURE_C_RESTORE:-}"
SKIP_VM_PROBE="${TOXEE_IOS_SKIP_VM_PROBE:-0}"
DEVICE_TYPE="${TOXEE_IOS_DEVICE_TYPE:-phone}"

if [[ -n "$FIXTURE_RESTORE_MODE" ]]; then
    echo "launch_ios_fixture_c_pair.sh: TOXEE_FIXTURE_C_RESTORE is not implemented for iOS yet ($FIXTURE_RESTORE_MODE)" >&2
    exit 66
fi

wait_for_instance_json() {
    local path="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [[ "$elapsed" -lt "$timeout" ]]; do
        if [[ -f "$path" ]] && jq -e '.ws_uri | length > 0' "$path" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "launch_ios_fixture_c_pair.sh: timed out waiting for instance json: $path" >&2
    return 1
}

probe_vm_service_retry() {
    local ws_uri="$1"
    local timeout="${2:-20}"
    local elapsed=0
    while [[ "$elapsed" -lt "$timeout" ]]; do
        if dart run "$VM_PROBE_DART" "$ws_uri"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "launch_ios_fixture_c_pair.sh: timed out probing VM service: $ws_uri" >&2
    return 1
}

select_simulators() {
    if [[ -n "${TOXEE_IOS_SIMULATOR_ID_A:-}" && -n "${TOXEE_IOS_SIMULATOR_ID_B:-}" ]]; then
        printf '%s\n%s\n' "$TOXEE_IOS_SIMULATOR_ID_A" "$TOXEE_IOS_SIMULATOR_ID_B"
        return 0
    fi
    local selected=()
    local row name udid state
    while IFS= read -r row; do
        IFS='|' read -r name udid state <<<"$row"
        [[ -z "$udid" ]] && continue
        if [[ "$DEVICE_TYPE" == "any" || ("$DEVICE_TYPE" == "tablet" && "$name" == *iPad*) || ("$DEVICE_TYPE" == "phone" && "$name" != *iPad*) ]]; then
            selected+=("$udid")
            if [[ "${#selected[@]}" -ge 2 ]]; then
                break
            fi
        fi
    done < <(xcrun simctl list devices available \
        | sed -nE 's/^[[:space:]]*([^()]+)[[:space:]]+\(([0-9A-F-]{36})\)[[:space:]]+\((Booted|Shutdown)\).*/\1|\2|\3/p')
    [[ "${#selected[@]}" -ge 2 ]] || return 1
    printf '%s\n%s\n' "${selected[0]}" "${selected[1]}"
}

write_pair_json() {
    /usr/bin/python3 - "$RUNTIME_ROOT/A/instance.json" "$RUNTIME_ROOT/B/instance.json" "$PAIR_JSON" <<'PY'
import json
import sys

a_file, b_file, out_file = sys.argv[1:4]
with open(a_file) as fa:
    a = json.load(fa)
with open(b_file) as fb:
    b = json.load(fb)

doc = {
    "format_version": 1,
    "instances": {"A": a, "B": b},
    "fixture_restore": {
        "mode": None,
        "report": None,
        "restored": None,
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

mkdir -p "$RUNTIME_ROOT"
rm -rf "$RUNTIME_ROOT/A" "$RUNTIME_ROOT/B" "$PAIR_JSON"

SIMULATORS=()
while IFS= read -r sim_id; do
    [[ -n "$sim_id" ]] && SIMULATORS+=("$sim_id")
done < <(select_simulators) || true
if [[ "${#SIMULATORS[@]}" -lt 2 ]]; then
    echo "launch_ios_fixture_c_pair.sh: need two available iOS simulators for A/B (or set TOXEE_IOS_SIMULATOR_ID_A/B)" >&2
    exit 66
fi
if [[ "${SIMULATORS[0]}" == "${SIMULATORS[1]}" ]]; then
    echo "launch_ios_fixture_c_pair.sh: A/B simulator IDs must differ" >&2
    exit 66
fi

# sim↔sim Tox connectivity needs exactly ONE TCP relay (same-host UDP loopback
# between two sandboxed sim apps doesn't deliver). A is the designated relay on
# TOXEE_IOS_TCP_RELAY_PORT (default 3389); B connects to it as a client below.
# Both sims share the host network stack, so enabling a relay on BOTH makes the
# second tox_new fail with TOX_ERR_NEW_PORT_ALLOC — hence A only.
TOXEE_IOS_RUNTIME_ROOT="$RUNTIME_ROOT" \
    TOXEE_IOS_SIMULATOR_ID="${SIMULATORS[0]}" \
    TOXEE_IOS_TCP_RELAY_PORT="${TOXEE_IOS_TCP_RELAY_PORT:-3389}" \
    "$MCP_DIR/launch_toxee_ios_instance.sh" A
wait_for_instance_json "$RUNTIME_ROOT/A/instance.json"
A_WS_URI="$(jq -r '.ws_uri' "$RUNTIME_ROOT/A/instance.json")"
if [[ "$SKIP_VM_PROBE" != "1" ]]; then
    probe_vm_service_retry "$A_WS_URI"
fi

# B ALSO runs a relay, on a DIFFERENT host port (A's + 1), so it doesn't contend
# with A's. A backgrounded sim that runs a Tox TCP relay (a listening server with
# continuous DHT/relay network I/O) keeps getting RunningBoard background grace —
# which is why the relay peer A survives sustained driving while a plain client
# peer is killed. Giving B its own relay extends the same survival to B.
TOXEE_IOS_RUNTIME_ROOT="$RUNTIME_ROOT" \
    TOXEE_IOS_SIMULATOR_ID="${SIMULATORS[1]}" \
    TOXEE_IOS_TCP_RELAY_PORT="$(( ${TOXEE_IOS_TCP_RELAY_PORT:-3389} + 1 ))" \
    "$MCP_DIR/launch_toxee_ios_instance.sh" B
wait_for_instance_json "$RUNTIME_ROOT/B/instance.json"
B_WS_URI="$(jq -r '.ws_uri' "$RUNTIME_ROOT/B/instance.json")"
if [[ "$SKIP_VM_PROBE" != "1" ]]; then
    probe_vm_service_retry "$A_WS_URI"
    probe_vm_service_retry "$B_WS_URI"
fi

write_pair_json

echo "OK: launched iOS Fixture C pair"
echo "pair json: $PAIR_JSON"
echo "A ws_uri: $(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
echo "B ws_uri: $(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"
