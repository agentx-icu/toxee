#!/usr/bin/env bash
# Scenarios: S69
# Class: 2proc-l3
# Run the S69 "call network drop (two processes)" L3 gate.
#
# Modes (first positional arg, default `synthetic`):
#   synthetic  Drives A's reconnect path via the l3_call_action `network_drop`
#              action (CallServiceManager.markReconnecting()). A2 is lenient
#              (transient can be missed by 1s polling); A3 ended is the hard
#              gate.
#   real-kill  Kills B's process mid-call and asserts A's peer-transport
#              WATCHDOG detects the loss on its own (A2 reconnecting is HARD
#              here — it is the behavior under test), then ends after the 8s
#              grace (A3). c-toxcore's offline detection takes tens of
#              seconds, so this mode is slower.
set -euo pipefail

MODE="${1:-synthetic}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
PAIR_JSON="$MCP_DIR/.multi_instance_runtime/pair.json"
PAIR_MANIFEST="$MCP_DIR/fixtures/paired_for_e2e_manifest.json"

cleanup() {
    "$MCP_DIR/stop_fixture_c_pair.sh" || true
}
trap cleanup EXIT INT TERM

cd "$REPO_ROOT"
"$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

echo "[network-drop] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

extra_args=()
if [[ "$MODE" == "real-kill" ]]; then
    b_pid="$(jq -r '.instances.B.pid' "$PAIR_JSON")"
    [[ -n "$b_pid" && "$b_pid" != "null" ]] || { echo "[network-drop] ERROR: no B pid in $PAIR_JSON"; exit 1; }
    extra_args+=(--real-kill-pid "$b_pid")
fi

# ${arr[@]+...} guard: macOS bash 3.2 treats an EMPTY array expansion as an
# unbound variable under `set -u`.
dart run tool/mcp_test/drive_fixture_c_network_drop.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST" ${extra_args[@]+"${extra_args[@]}"}

echo "[network-drop] S69 PASS ($MODE)"
