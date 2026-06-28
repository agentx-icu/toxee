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
FIXTURES_DIR="$MCP_DIR/fixtures"
FIXTURE_MANIFEST="${TOXEE_FIXTURE_C_MANIFEST:-$FIXTURES_DIR/paired_for_e2e_manifest.json}"

# iOS fixture restore: copy a PRE-PAIRED snapshot (accounts already registered +
# already mutual friends + chat history) into each instance's app_support dir so
# scenarios SKIP registration + friend-add (the drivers boot it via
# l3_boot_existing_account). iOS reuses the portable macOS paired_for_e2e
# snapshot: tox_profile.tox is Tox savedata (keypair + friend list) and the chat
# history is Dart-side JSON — both platform-independent — and launch_toxee_ios_
# instance.sh points the app's TOXEE_APP_SUPPORT_DIR at $RUNTIME_ROOT/<name>/
# app_support, the same support-root contract macOS restore_fixture_c_pair.sh uses.
RESTORE_ENABLED=0
if [[ -n "$FIXTURE_RESTORE_MODE" ]]; then
    case "$FIXTURE_RESTORE_MODE" in
        paired_for_e2e) RESTORE_ENABLED=1 ;;
        *)
            echo "launch_ios_fixture_c_pair.sh: unsupported TOXEE_FIXTURE_C_RESTORE mode for iOS: $FIXTURE_RESTORE_MODE (only paired_for_e2e)" >&2
            exit 66 ;;
    esac
    [[ -f "$FIXTURE_MANIFEST" ]] || {
        echo "launch_ios_fixture_c_pair.sh: fixture manifest missing: $FIXTURE_MANIFEST" >&2
        exit 66
    }
    command -v jq >/dev/null 2>&1 || {
        echo "launch_ios_fixture_c_pair.sh: jq required for fixture restore" >&2
        exit 66
    }
fi

# Copy the paired snapshot for one instance into its app_support dir. Must run
# AFTER the per-instance runtime dir is wiped (below) and BEFORE that instance's
# app boots, so l3_boot_existing_account finds the restored profile.
restore_ios_instance() {
    local name="$1"
    local fixture_dir tox_id friend_id prefix src dest profile_file history_file
    fixture_dir="$(jq -r --arg n "$name" '.instances[$n].fixture_dir // empty' "$FIXTURE_MANIFEST")"
    tox_id="$(jq -r --arg n "$name" '.instances[$n].tox_id // empty' "$FIXTURE_MANIFEST")"
    friend_id="$(jq -r --arg n "$name" '.instances[$n].friend_tox_id // empty' "$FIXTURE_MANIFEST")"
    [[ -n "$fixture_dir" ]] || {
        echo "launch_ios_fixture_c_pair.sh: manifest missing instances.$name.fixture_dir" >&2
        exit 66
    }
    [[ -n "$tox_id" && -n "$friend_id" ]] || {
        echo "launch_ios_fixture_c_pair.sh: manifest missing instances.$name.tox_id/friend_tox_id" >&2
        exit 66
    }
    prefix="${tox_id:0:16}"
    src="$FIXTURES_DIR/$fixture_dir"
    dest="$RUNTIME_ROOT/$name/app_support"
    profile_file="$dest/profiles/p_${prefix}/tox_profile.tox"
    history_file="$dest/account_data/${prefix}/chat_history/${friend_id}.json"
    [[ -d "$src" ]] || {
        echo "launch_ios_fixture_c_pair.sh: fixture source missing for $name: $src" >&2
        exit 66
    }
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
    # Post-copy integrity checks (mirror restore_fixture_c_pair.sh): catch a
    # partial/mislaid snapshot here with a deterministic message instead of a
    # cryptic l3_boot_existing_account failure after launch.
    [[ -f "$profile_file" ]] || {
        echo "launch_ios_fixture_c_pair.sh: $name restore missing profile: $profile_file" >&2
        exit 66
    }
    [[ -f "$history_file" ]] || {
        echo "launch_ios_fixture_c_pair.sh: $name restore missing chat history: $history_file" >&2
        exit 66
    }
    echo "[ios-restore] $name <- $src"
}

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
import os
import sys

a_file, b_file, out_file = sys.argv[1:4]
with open(a_file) as fa:
    a = json.load(fa)
with open(b_file) as fb:
    b = json.load(fb)

restore_mode = os.environ.get("TOXEE_FIXTURE_C_RESTORE") or None

doc = {
    "format_version": 1,
    "instances": {"A": a, "B": b},
    "fixture_restore": {
        "mode": restore_mode,
        "report": None,
        "restored": restore_mode is not None,
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
if [[ "$RESTORE_ENABLED" == "1" ]]; then restore_ios_instance A; fi
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
if [[ "$RESTORE_ENABLED" == "1" ]]; then restore_ios_instance B; fi
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
