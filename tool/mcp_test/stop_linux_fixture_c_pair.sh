#!/usr/bin/env bash
# Tear down the Linux Fixture C pair started by launch_linux_fixture_c_pair.sh:
# kill both instances (pair.json pids + pid files + path-scoped pkill sweep)
# and the private Xvfb display if the launcher started one.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_ROOT="${TOXEE_LINUX_RUNTIME_ROOT:-$REPO_ROOT/build/linux_runtime}"
PAIR_JSON="$RUNTIME_ROOT/pair.json"

if [[ -f "$PAIR_JSON" ]] && command -v jq >/dev/null 2>&1; then
    for pid in $(jq -r '.instances[].pid // empty' "$PAIR_JSON" 2>/dev/null); do
        kill "$pid" 2>/dev/null || true
    done
fi
for pf in "$RUNTIME_ROOT/A/toxee.pid" "$RUNTIME_ROOT/B/toxee.pid"; do
    [[ -f "$pf" ]] && kill "$(cat "$pf")" 2>/dev/null || true
done
pkill -f "$REPO_ROOT/build/linux/.*/debug/bundle/toxee" 2>/dev/null || true
sleep 1
pkill -9 -f "$REPO_ROOT/build/linux/.*/debug/bundle/toxee" 2>/dev/null || true

if [[ -f "$RUNTIME_ROOT/xvfb.pid" ]]; then
    kill "$(cat "$RUNTIME_ROOT/xvfb.pid")" 2>/dev/null || true
    rm -f "$RUNTIME_ROOT/xvfb.pid"
fi
echo "stopped Linux Fixture C pair (runtime root: $RUNTIME_ROOT)"
