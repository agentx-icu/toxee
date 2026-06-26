#!/usr/bin/env bash
# Launch A=macOS (Tox TCP relay) + B=iOS-Simulator for cross-platform real-UI
# two-process driving.
#
# WHY this topology (proven 2026-06-25): two iOS sims can't both be the active
# device — the backgrounded one is RBS-killed under sustained VM-service driving.
# A SOLE sim, by contrast, is always the active device and survives indefinitely
# (verified: ~150s of dump_state hammering, Simulator backgrounded, no kill). So
# the only single-Mac topology that runs the full alternating sweep is ONE sim
# (always active, never dies) + the peer on macOS (a normal app, never dies).
#
# Same-host macOS↔sim Tox P2P can't use UDP (loopback to the sandboxed apps
# doesn't deliver), so the macOS node runs a Tox TCP relay server via
# TOX_TCP_RELAY_PORT; the iOS client already probes 3389 in add_bootstrap_node.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
ROOT="${TOXEE_MIXED_RUNTIME_ROOT:-$MCP_DIR/.mixed_runtime}"
RELAY_PORT="${TOX_TCP_RELAY_PORT:-3389}"
SIM_B="${TOXEE_IOS_SIMULATOR_ID:-}"

# B must be the SOLE booted sim so it is always the active device. Shut down all
# other booted sims; keep (or pick) one for B.
BOOTED=()
while IFS= read -r udid; do
  [[ -n "$udid" ]] && BOOTED+=("$udid")
done < <(xcrun simctl list devices booted 2>/dev/null \
  | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p')
if [[ -z "$SIM_B" ]]; then
  # prefer an already-booted phone sim; else the first available phone sim
  if [[ "${#BOOTED[@]}" -ge 1 ]]; then SIM_B="${BOOTED[0]}"; fi
fi
if [[ "${#BOOTED[@]}" -gt 0 ]]; then
  for udid in "${BOOTED[@]}"; do
    [[ -z "$udid" ]] && continue
    if [[ "$udid" != "$SIM_B" ]]; then
      echo "shutting down extra sim $udid (B must be the sole/active device)"
      xcrun simctl shutdown "$udid" 2>/dev/null || true
    fi
  done
fi
if [[ -z "$SIM_B" ]]; then
  echo "launch_mixed: no sim for B; set TOXEE_IOS_SIMULATOR_ID" >&2; exit 66
fi
xcrun simctl bootstatus "$SIM_B" -b >/dev/null 2>&1 || xcrun simctl boot "$SIM_B" 2>/dev/null || true

rm -rf "$ROOT/A" "$ROOT/B"; mkdir -p "$ROOT"
# Clear the shared macOS defaults so A starts from a blank login state (mirrors
# launch_fixture_c_pair.sh; a stale account_list otherwise skips the register UI).
defaults delete com.toxee.app >/dev/null 2>&1 || true
killall cfprefsd >/dev/null 2>&1 || true

echo "=== launch A = macOS relay (port $RELAY_PORT) ==="
TOX_TCP_RELAY_PORT="$RELAY_PORT" TOXEE_MULTI_RUNTIME_ROOT="$ROOT" \
  "$MCP_DIR/launch_toxee_instance.sh" A
A_WS="$(jq -r '.ws_uri' "$ROOT/A/instance.json")"
A_PID="$(jq -r '.pid' "$ROOT/A/instance.json")"

echo "=== launch B = iOS sim ($SIM_B) ==="
TOXEE_IOS_LAUNCH_METHOD=simctl TOXEE_IOS_RUNTIME_ROOT="$ROOT" \
  TOXEE_IOS_SIMULATOR_ID="$SIM_B" \
  "$MCP_DIR/launch_toxee_ios_instance.sh" B
B_WS="$(jq -r '.ws_uri' "$ROOT/B/instance.json")"
B_PID="$(jq -r '.pid' "$ROOT/B/instance.json")"

echo "OK: launched mixed macOS(A)+iOS-sim(B) pair"
echo "A_WS=$A_WS"
echo "A_PID=$A_PID"
echo "B_WS=$B_WS"
echo "B_PID=$B_PID"
echo "SIM_B=$SIM_B"
echo -n "relay listening on $RELAY_PORT: "
lsof -nP -iTCP:"$RELAY_PORT" -sTCP:LISTEN 2>/dev/null | grep -iq toxee && echo "YES" || echo "NO (WARN)"
