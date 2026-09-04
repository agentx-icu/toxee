#!/usr/bin/env bash
# Stop ONE debug Toxee instance previously launched by launch_toxee_instance.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_MULTI_RUNTIME_ROOT:-$MCP_DIR/.multi_instance_runtime}"
INSTANCE_NAME="${1:-}"

if [[ -z "$INSTANCE_NAME" ]]; then
    echo "usage: stop_toxee_instance.sh <instance-name>" >&2
    exit 64
fi

# shellcheck source=_multi_instance_lib.sh
. "$MCP_DIR/_multi_instance_lib.sh"

JSON_FILE="$RUNTIME_ROOT/$INSTANCE_NAME/instance.json"
# Absent instance.json still means "not running"; the retired copy keeps the
# launch contract (tcp_only / tcp_relay_port) so a relaunch can restore it —
# same as the Windows twin, which rewrites instance.json in place.
retire_json() { mv -f "$JSON_FILE" "$JSON_FILE.stopped" 2>/dev/null || rm -f "$JSON_FILE"; }
STOP_WAIT_SECS="${TOXEE_MULTI_STOP_WAIT_SECS:-5}"

if [[ ! -f "$JSON_FILE" ]]; then
    echo "OK: nothing to stop for $INSTANCE_NAME"
    exit 0
fi

pid="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pid",""))' "$JSON_FILE" 2>/dev/null || true)"
start_time="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("start_time",""))' "$JSON_FILE" 2>/dev/null || true)"
cmdline="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("cmdline",""))' "$JSON_FILE" 2>/dev/null || true)"

if [[ -z "$pid" || -z "$start_time" || -z "$cmdline" ]]; then
    retire_json
    echo "WARN: cleared malformed json for $INSTANCE_NAME" >&2
    exit 0
fi

reason="$(_mi_validate_triple "$pid" "$start_time" "$cmdline")"
if [[ "$reason" != "ok" ]]; then
    retire_json
    echo "WARN: recorded process for $INSTANCE_NAME no longer matches (${reason}); cleared stale json" >&2
    exit 0
fi

if ! _mi_stop_with_grace "$pid" "$STOP_WAIT_SECS"; then
    retire_json
    echo "stop_toxee_instance.sh: pid $pid survived SIGKILL" >&2
    exit 1
fi

retire_json
echo "OK: stopped $INSTANCE_NAME pid=$pid"
