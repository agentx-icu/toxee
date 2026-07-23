#!/usr/bin/env bash
# Stop the A/B pair previously launched by launch_fixture_c_pair.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_MULTI_RUNTIME_ROOT:-$MCP_DIR/.multi_instance_runtime}"
COPIES_DIR="$RUNTIME_ROOT/app_copies"

# shellcheck source=_multi_instance_lib.sh
. "$MCP_DIR/_multi_instance_lib.sh"

"$MCP_DIR/stop_toxee_instance.sh" B || true
"$MCP_DIR/stop_toxee_instance.sh" A || true

# Teardown owns the app copy launch_fixture_c_pair.sh dittoed for B. Leaving it
# behind is not just ~185M of disk per run: a copy that outlives its run holds
# DHT bootstrap port 33446, and the next campaign's loopback DHT then never
# converges ("A never received B's friend request" → 0 cases run).
_mi_gc_app_copies "$COPIES_DIR" 0

# B runs from `app_copies/ToxeeB-*.app/...`, NOT `Debug/Toxee.app/...`, so a
# Debug-only pattern reports "no orphans" while a copy-backed one is still alive
# holding the port. Match both harness paths — and only those, so an unrelated
# or installed Toxee is never flagged.
orphans="$(pgrep -fl 'Debug/Toxee\.app|app_copies/Toxee' 2>/dev/null || true)"
if [[ -n "$orphans" ]]; then
    echo "WARN: pgrep still sees harness Toxee processes after pair stop:" >&2
    printf '%s\n' "$orphans" >&2
else
    echo "OK: no harness Toxee processes remain"
fi
