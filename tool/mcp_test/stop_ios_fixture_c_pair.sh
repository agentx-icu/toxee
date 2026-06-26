#!/usr/bin/env bash
# Stop the A/B iOS pair previously launched by launch_ios_fixture_c_pair.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_IOS_RUNTIME_ROOT:-$MCP_DIR/.ios_runtime}"

TOXEE_MULTI_RUNTIME_ROOT="$RUNTIME_ROOT" "$MCP_DIR/stop_toxee_instance.sh" B || true
TOXEE_MULTI_RUNTIME_ROOT="$RUNTIME_ROOT" "$MCP_DIR/stop_toxee_instance.sh" A || true
rm -f "$RUNTIME_ROOT/pair.json"

echo "OK: stopped iOS Fixture C pair"
