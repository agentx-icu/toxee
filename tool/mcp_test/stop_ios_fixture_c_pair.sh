#!/usr/bin/env bash
# Stop the A/B iOS pair previously launched by launch_ios_fixture_c_pair.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_IOS_RUNTIME_ROOT:-$MCP_DIR/.ios_runtime}"
IOS_PBXPROJ="$REPO_ROOT/ios/Runner.xcodeproj/project.pbxproj"

BUNDLE_ID="$(awk -F'=' '
  /PRODUCT_BUNDLE_IDENTIFIER = / && $0 !~ /RunnerTests/ {
    gsub(/[ ;]/, "", $2); print $2; exit
  }' "$IOS_PBXPROJ" 2>/dev/null || true)"

# TERMINATE THE GUEST APP ON ITS OWN SIMULATOR, not just the host-side pid.
#
# A simctl-launched app is a CoreSimulator guest process: signalling the host
# pid does not reliably tear it down, and `stop_toxee_instance.sh` then removes
# the instance json anyway — so the app kept running with nothing left pointing
# at it. That matters because the pair pins FIXED host ports (the Tox TCP relay
# on 3389/3390, see launch_ios_fixture_c_pair.sh): a survivor holds the relay
# socket and the NEXT pair's `tox_new` dies with TOX_ERR_NEW_PORT_ALLOC, which
# surfaces in the app as "initWithPath failed" and kills registration.
#
# `launch_toxee_ios_instance.sh` already terminates + uninstalls on the
# simulator IT is about to use, so a relaunch on the SAME device was always
# safe. The leak only appeared when the device type CHANGED (a rui-ios-* phone
# campaign followed by a rui-ipad-* one, or vice versa): the new launch cleans
# the iPad sims while the previous pair is still alive on the iPhone sims.
# Measured 2026-08-16 — a leftover iPhone A held `TCP *:3389 (LISTEN)` and made
# a whole iPad campaign fail at registration on both attempts.
#
# The simulator UDID is recovered from the recorded `cmdline`
# (".../Devices/<UDID>/data/..."), so this only ever targets a simulator this
# runtime root actually launched. Everything here is best-effort: a missing or
# stale json simply skips.
terminate_guest_app() {
    local name="$1"
    local json="$RUNTIME_ROOT/$name/instance.json"
    [[ -f "$json" ]] || return 0
    [[ -n "$BUNDLE_ID" ]] || return 0
    local cmdline udid
    cmdline="$(/usr/bin/python3 -c \
        'import json,sys;print(json.load(open(sys.argv[1])).get("cmdline",""))' \
        "$json" 2>/dev/null || true)"
    udid="$(printf '%s' "$cmdline" | sed -n 's|.*/Devices/\([0-9A-Fa-f-]\{36\}\)/.*|\1|p')"
    [[ -n "$udid" ]] || return 0
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

terminate_guest_app B
terminate_guest_app A

TOXEE_MULTI_RUNTIME_ROOT="$RUNTIME_ROOT" "$MCP_DIR/stop_toxee_instance.sh" B || true
TOXEE_MULTI_RUNTIME_ROOT="$RUNTIME_ROOT" "$MCP_DIR/stop_toxee_instance.sh" A || true
rm -f "$RUNTIME_ROOT/pair.json"

echo "OK: stopped iOS Fixture C pair"
