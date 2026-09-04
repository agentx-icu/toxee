#!/usr/bin/env bash
# Hermetic regressions for the unified Fixture C / real-UI runner.
#
# These checks never launch Toxee. They validate manifest parsing, filtering,
# grouping, and dry-run command planning before the live two-process runner is
# allowed to mutate local app state.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNNER="$MCP_DIR/fixture_c_unified_runner.dart"

command -v jq >/dev/null 2>&1 || {
    echo "fixture_c_unified_runner_regression.sh: jq is required" >&2
    exit 1
}

PASS_COUNT=0
FAIL_COUNT=0
TMP_ROOT="$(mktemp -d -t fixture_c_unified_runner.XXXXXX)"
cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '  PASS  %s\n' "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '  FAIL  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then
        printf '        %s\n' "$2"
    fi
}

run_runner() {
    (cd "$REPO_ROOT" && dart run tool/mcp_test/fixture_c_unified_runner.dart "$@")
}

run_suite() {
    (cd "$REPO_ROOT" && bash tool/mcp_test/run_fixture_c_suite.sh "$@")
}

run_non_media_alias() {
    (cd "$REPO_ROOT" && bash tool/mcp_test/run_fixture_c_non_media.sh "$@")
}

REAL_DART_BIN="$(command -v dart)"
FAKE_BIN="$TMP_ROOT/fake_bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/bash" <<'FAKE_BASH'
#!/bin/bash
set -euo pipefail
printf 'bash:%s restore=%s\n' "${1:-}" "${TOXEE_FIXTURE_C_RESTORE:-}" >>"$FAKE_LOG"
case "${1:-}" in
    tool/mcp_test/launch_linux_fixture_c_pair.sh)
        if [[ "${FAKE_FAIL_RESTORED_LAUNCH:-0}" == "1" && -n "${TOXEE_FIXTURE_C_RESTORE:-}" ]]; then
            exit 42
        fi
        mkdir -p build/linux_runtime
        cat >build/linux_runtime/pair.json <<JSON
{
  "format_version": 1,
  "instances": {
    "A": {"ws_uri": "ws://fake-a/ws", "pid": 111, "nickname": "FakeAlice"},
    "B": {"ws_uri": "ws://fake-b/ws", "pid": 222, "nickname": "FakeBob"}
  },
  "fixture_restore": {
    "mode": "${TOXEE_FIXTURE_C_RESTORE:-}",
    "report": null,
    "restored": null
  }
}
JSON
        ;;
    tool/mcp_test/stop_linux_fixture_c_pair.sh)
        ;;
    *)
        exec /bin/bash "$@"
        ;;
esac
FAKE_BASH
cat >"$FAKE_BIN/dart" <<'FAKE_DART'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "run" && "${2:-}" == "tool/mcp_test/fixture_c_unified_runner.dart" ]]; then
    exec "$REAL_DART" "$@"
fi
if [[ "${1:-}" == "run" && "${2:-}" == "tool/mcp_test/drive_real_ui_pair.dart" ]]; then
    printf 'dart:%s\n' "$*" >>"$FAKE_LOG"
    attempts=0
    if [[ -f "$FAKE_DRIVER_ATTEMPTS" ]]; then
        attempts="$(<"$FAKE_DRIVER_ATTEMPTS")"
    fi
    attempts=$((attempts + 1))
    printf '%s' "$attempts" >"$FAKE_DRIVER_ATTEMPTS"
    if [[ "${FAKE_DRIVER_FAIL_FIRST:-0}" == "1" && "$attempts" == "1" ]]; then
        exit 1
    fi
    exit 0
fi
exec "$REAL_DART" "$@"
FAKE_DART
chmod +x "$FAKE_BIN/bash" "$FAKE_BIN/dart"

run_runner_with_fake_processes() {
    local fake_log="$1"
    local fake_attempts="$2"
    shift 2
    (cd "$REPO_ROOT" && PATH="$FAKE_BIN:$PATH" \
        REAL_DART="$REAL_DART_BIN" \
        FAKE_LOG="$fake_log" \
        FAKE_DRIVER_ATTEMPTS="$fake_attempts" \
        FAKE_DRIVER_FAIL_FIRST="${FAKE_DRIVER_FAIL_FIRST:-0}" \
        FAKE_FAIL_RESTORED_LAUNCH="${FAKE_FAIL_RESTORED_LAUNCH:-0}" \
        dart run tool/mcp_test/fixture_c_unified_runner.dart "$@")
}

echo "Unified Fixture C runner regressions"
echo "  runner: $RUNNER"
echo

LIST_OUT="$TMP_ROOT/list.out"
if run_runner --list >"$LIST_OUT" 2>"$TMP_ROOT/list.err"; then
    if grep -q 'drive_real_ui_pair.dart' "$LIST_OUT" \
        && grep -q 'run_fixture_c_accept.sh' "$LIST_OUT"; then
        pass "--list includes real-UI and Fixture C entries"
    else
        fail "--list includes real-UI and Fixture C entries" \
            "expected drive_real_ui_pair.dart and run_fixture_c_accept.sh in --list output"
    fi
else
    fail "--list exits 0" "$(cat "$TMP_ROOT/list.err" "$LIST_OUT" 2>/dev/null)"
fi

CAMPAIGN_LIST_OUT="$TMP_ROOT/real_ui_campaigns.out"
if run_runner --list-real-ui-campaigns >"$CAMPAIGN_LIST_OUT" \
    2>"$TMP_ROOT/campaigns.err"; then
    CAMPAIGN_COUNT="$(awk -F'[()]' 'NR==1 {print $2}' "$CAMPAIGN_LIST_OUT")"
    CAMPAIGN_ENTRY_COUNT="$(grep -c '^[a-z0-9][a-z0-9-]*:' "$CAMPAIGN_LIST_OUT" || true)"
    if [[ -n "$CAMPAIGN_COUNT" && "$CAMPAIGN_COUNT" -ge 30 ]]; then
        pass "--list-real-ui-campaigns exposes at least 30 reusable campaigns"
    else
        fail "--list-real-ui-campaigns exposes at least 30 reusable campaigns" \
            "expected >=30 campaigns, got ${CAMPAIGN_COUNT:-missing}"
    fi
    if [[ -n "$CAMPAIGN_COUNT" && "$CAMPAIGN_COUNT" == "$CAMPAIGN_ENTRY_COUNT" ]]; then
        pass "campaign catalog header count matches the discoverability listing"
    else
        fail "campaign catalog header count matches the discoverability listing" \
            "header=${CAMPAIGN_COUNT:-missing} entries=$CAMPAIGN_ENTRY_COUNT"
    fi
    if grep -q '^accepted-friend-inline-full:' "$CAMPAIGN_LIST_OUT" \
        && grep -q '^no-friend-inline-call:' "$CAMPAIGN_LIST_OUT" \
        && grep -q '^inline-call-then-decline:' "$CAMPAIGN_LIST_OUT" \
        && grep -q '^all-expanded:' "$CAMPAIGN_LIST_OUT"; then
        pass "campaign catalog includes representative bucket samples"
    else
        fail "campaign catalog includes representative bucket samples"
    fi

    # The mobile matrix lives in fixture_c_real_ui_mobile_campaigns.dart and is
    # spread into _realUiCampaigns. If the merge ever breaks (rename, dropped
    # import, const/final mishap), the catalog silently loses ~38 entries — this
    # asserts one representative from every family instead of a bare count so
    # the failure names what disappeared.
    MOBILE_MISSING=""
    for name in rui-mobile-shell rui-ios-main rui-ios-profile \
        rui-ios-contacts rui-ipad-main rui-ipad-group-member rui-ipad-p1-chat \
        rui-android-main rui-android-contacts; do
        grep -q "^$name:" "$CAMPAIGN_LIST_OUT" || MOBILE_MISSING="$MOBILE_MISSING $name"
    done
    if [[ -z "$MOBILE_MISSING" ]]; then
        pass "mobile campaign matrix is merged into the catalog"
    else
        fail "mobile campaign matrix is merged into the catalog" \
            "missing:$MOBILE_MISSING"
    fi

    # Sweeps that CANNOT be honest on a device (see the "DELIBERATELY NOT
    # REGISTERED" block in fixture_c_real_ui_mobile_campaigns.dart): peer
    # relaunch shells out to the macOS DESKTOP instance launchers; p2_verify
    # needs an image on the host pasteboard; group_mention asserts the osaType
    # keystroke itself. Registering any of them under a mobile campaign would
    # produce a green run that drove the wrong process or asserted nothing.
    MOBILE_FORBIDDEN=""
    while IFS= read -r line; do
        case "$line" in
            rui-ios-*|rui-ipad-*|rui-android-*|rui-mobile-*) ;;
            *) continue ;;
        esac
        for sweep in sweep_p1_relaunch sweep_p2_keys sweep_p2_verify \
            sweep_group_mention; do
            case "$line" in
                *"$sweep"*)
                    MOBILE_FORBIDDEN="$MOBILE_FORBIDDEN ${line%%:*}/$sweep"
                    ;;
            esac
        done
    done <"$CAMPAIGN_LIST_OUT"
    # Form-factor exclusives must not cross over: sweep_mobile_shell in a
    # rui-ipad-* campaign (or sweep_tablet_layout in an iPhone one) SKIPs every
    # case and only inflates the skip tally.
    while IFS= read -r line; do
        case "$line" in
            rui-ipad-*sweep_mobile_shell*)
                MOBILE_FORBIDDEN="$MOBILE_FORBIDDEN ${line%%:*}/sweep_mobile_shell"
                ;;
            rui-ios-*sweep_tablet_layout*)
                MOBILE_FORBIDDEN="$MOBILE_FORBIDDEN ${line%%:*}/sweep_tablet_layout"
                ;;
        esac
    done <"$CAMPAIGN_LIST_OUT"
    if [[ -z "$MOBILE_FORBIDDEN" ]]; then
        pass "mobile campaigns exclude the un-driveable / wrong-form-factor sweeps"
    else
        fail "mobile campaigns exclude the un-driveable / wrong-form-factor sweeps" \
            "registered anyway:$MOBILE_FORBIDDEN"
    fi
else
    fail "--list-real-ui-campaigns exits 0" \
        "$(cat "$TMP_ROOT/campaigns.err" "$CAMPAIGN_LIST_OUT" 2>/dev/null)"
fi

PLAN_JSON="$TMP_ROOT/non_media_plan.json"
if run_runner --plan-json --tier=non-media >"$PLAN_JSON" 2>"$TMP_ROOT/plan.err"; then
    if jq -e '.groups | length > 0' "$PLAN_JSON" >/dev/null; then
        pass "--plan-json emits groups"
    else
        fail "--plan-json emits groups" "no groups emitted"
    fi
    if jq -e '[.groups[].entries[].script] | index("drive_real_ui_pair.dart")' \
        "$PLAN_JSON" >/dev/null; then
        pass "planning includes 2proc-ui instead of skipping it"
    else
        fail "planning includes 2proc-ui instead of skipping it"
    fi
    if jq -e '[.groups[].entries[] | select(.destructive == true)] | length == 0' \
        "$PLAN_JSON" >/dev/null; then
        pass "destructive entries excluded by default"
    else
        fail "destructive entries excluded by default"
    fi
    if jq -e '.groups[0].mode == "paired-reuse"' "$PLAN_JSON" >/dev/null; then
        pass "paired reusable group is planned first"
    else
        fail "paired reusable group is planned first" \
            "first group should amortize paired_for_e2e launch"
    fi
    if jq -e '
        [.groups[].entries[] | select(.script == "run_fixture_c_accept.sh")][0]
        | .base == "fresh" and .driver == "drive_fixture_c_accept.dart"
    ' "$PLAN_JSON" >/dev/null; then
        pass "plan-json exposes explicit driver/base metadata"
    else
        fail "plan-json exposes explicit driver/base metadata"
    fi
else
    fail "--plan-json exits 0" "$(cat "$TMP_ROOT/plan.err" "$PLAN_JSON" 2>/dev/null)"
fi

DESTRUCTIVE_PLAN="$TMP_ROOT/destructive_plan.json"
if run_runner --plan-json --tier=all --include-destructive >"$DESTRUCTIVE_PLAN" \
    2>"$TMP_ROOT/destructive.err"; then
    if jq -e '[.groups[].entries[] | select(.destructive == true)] | length > 0' \
        "$DESTRUCTIVE_PLAN" >/dev/null; then
        pass "--include-destructive includes destructive entries"
    else
        fail "--include-destructive includes destructive entries"
    fi
else
    fail "--include-destructive plan exits 0" \
        "$(cat "$TMP_ROOT/destructive.err" "$DESTRUCTIVE_PLAN" 2>/dev/null)"
fi

DRY_OUT="$TMP_ROOT/dry_run.out"
if run_runner --dry-run --tier=non-media >"$DRY_OUT" 2>"$TMP_ROOT/dry.err"; then
    if grep -q 'launch_fixture_c_pair.sh' "$DRY_OUT" \
        && grep -q 'drive_fixture_c_pair.dart' "$DRY_OUT"; then
        pass "--dry-run prints launch and driver commands"
    else
        fail "--dry-run prints launch and driver commands" \
            "expected launch_fixture_c_pair.sh and drive_fixture_c_pair.dart"
    fi
else
    fail "--dry-run exits 0" "$(cat "$TMP_ROOT/dry.err" "$DRY_OUT" 2>/dev/null)"
fi

ACCEPT_PLAN="$TMP_ROOT/accept_plan.json"
if run_runner --plan-json --id=run_fixture_c_accept.sh >"$ACCEPT_PLAN" \
    2>"$TMP_ROOT/accept.err"; then
    if jq -e '(.groups | length) == 1 and .groups[0].mode == "fresh-isolated"' \
        "$ACCEPT_PLAN" >/dev/null; then
        pass "fresh friend-request gates stay isolated"
    else
        fail "fresh friend-request gates stay isolated" \
            "run_fixture_c_accept.sh should not be batched into paired reuse"
    fi
else
    fail "fresh accept plan exits 0" "$(cat "$TMP_ROOT/accept.err" "$ACCEPT_PLAN" 2>/dev/null)"
fi

ALL_DRY="$TMP_ROOT/all_dry.out"
if run_runner --dry-run --tier=all >"$ALL_DRY" 2>"$TMP_ROOT/all_dry.err"; then
    if grep -q 'drive_fixture_c_file.dart "\$A_WS" "\$B_WS" --fixture-manifest .* --image' \
        "$ALL_DRY"; then
        pass "image gate reuses file driver with --image"
    else
        fail "image gate reuses file driver with --image"
    fi
else
    fail "all-tier dry-run exits 0" "$(cat "$TMP_ROOT/all_dry.err" "$ALL_DRY" 2>/dev/null)"
fi

REAL_UI_DRY="$TMP_ROOT/real_ui_dry.out"
if run_runner --dry-run --class=2proc-ui >"$REAL_UI_DRY" 2>"$TMP_ROOT/real_ui.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake ' "$REAL_UI_DRY" \
        && grep -q 'drive_real_ui_pair.dart message ' "$REAL_UI_DRY" \
        && grep -q 'drive_real_ui_pair.dart handshake_detail ' "$REAL_UI_DRY" \
        && grep -q 'drive_real_ui_pair.dart decline ' "$REAL_UI_DRY"; then
        pass "real-UI dry-run expands scenario sequence"
    else
        fail "real-UI dry-run expands scenario sequence" \
            "expected handshake/message/handshake_detail/decline commands"
    fi
    LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_DRY" || true)"
    if [[ "$LAUNCH_COUNT" -eq 1 ]]; then
        pass "real-UI default batch reuses a single launch across all codified scenarios"
    else
        fail "real-UI default batch reuses a single launch across all codified scenarios" \
            "expected 1 launch for the 4-scenario batch, but saw $LAUNCH_COUNT"
    fi
    RESET_COUNT="$(grep -c 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_DRY" || true)"
    if [[ "$RESET_COUNT" -eq 2 ]]; then
        pass "real-UI default batch inserts friendship resets between incompatible states"
    else
        fail "real-UI default batch inserts friendship resets between incompatible states" \
            "expected 2 reset_friendship steps, but saw $RESET_COUNT"
    fi
    HANDSHAKE_LINE="$(grep -n 'drive_real_ui_pair.dart handshake ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    MESSAGE_LINE="$(grep -n 'drive_real_ui_pair.dart message ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    RESET1_LINE="$(grep -n 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    DETAIL_LINE="$(grep -n 'drive_real_ui_pair.dart handshake_detail ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    RESET2_LINE="$(grep -n 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_DRY" | tail -n1 | cut -d: -f1)"
    DECLINE_LINE="$(grep -n 'drive_real_ui_pair.dart decline ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    if [[ -n "$HANDSHAKE_LINE" && -n "$MESSAGE_LINE" && -n "$RESET1_LINE" \
        && -n "$DETAIL_LINE" && -n "$RESET2_LINE" && -n "$DECLINE_LINE" \
        && "$HANDSHAKE_LINE" -lt "$MESSAGE_LINE" \
        && "$MESSAGE_LINE" -lt "$RESET1_LINE" \
        && "$RESET1_LINE" -lt "$DETAIL_LINE" \
        && "$DETAIL_LINE" -lt "$RESET2_LINE" \
        && "$RESET2_LINE" -lt "$DECLINE_LINE" ]]; then
        pass "real-UI default batch orders handshake -> message -> reset -> detail -> reset -> decline"
    else
        fail "real-UI default batch orders handshake -> message -> reset -> detail -> reset -> decline"
    fi
else
    fail "real-UI dry-run exits 0" "$(cat "$TMP_ROOT/real_ui.err" "$REAL_UI_DRY" 2>/dev/null)"
fi

REAL_UI_PLAN="$TMP_ROOT/real_ui_plan.json"
if run_runner --plan-json --class=2proc-ui >"$REAL_UI_PLAN" \
    2>"$TMP_ROOT/real_ui_plan.err"; then
    if jq -e '(.groups | length) == 1 and .groups[0].mode == "real-ui"' \
        "$REAL_UI_PLAN" >/dev/null; then
        pass "real-UI plan-json stays in one dedicated group"
    else
        fail "real-UI plan-json stays in one dedicated group" \
            "expected a single real-ui group"
    fi
    if jq -e '
        .groups[0].entries[0].realUiScenarios
        == ["handshake", "message", "handshake_detail", "decline"]
    ' "$REAL_UI_PLAN" >/dev/null; then
        pass "real-UI plan-json records the default reusable scenario batch"
    else
        fail "real-UI plan-json records the default reusable scenario batch"
    fi
    if jq -e '
        [.groups[0].commands[] | select(contains("reset_friendship"))]
        | length == 2
    ' "$REAL_UI_PLAN" >/dev/null; then
        pass "real-UI plan-json exposes friendship-reset maintenance steps"
    else
        fail "real-UI plan-json exposes friendship-reset maintenance steps" \
            "expected 2 reset_friendship commands in plan-json"
    fi
else
    fail "real-UI plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_plan.err" "$REAL_UI_PLAN" 2>/dev/null)"
fi

REAL_UI_ORDERED_DRY="$TMP_ROOT/real_ui_ordered_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-scenario=handshake_detail,message \
    >"$REAL_UI_ORDERED_DRY" 2>"$TMP_ROOT/real_ui_ordered.err"; then
    ORDERED_LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_ORDERED_DRY" || true)"
    ORDERED_DETAIL_LINE="$(grep -n 'drive_real_ui_pair.dart handshake_detail ' "$REAL_UI_ORDERED_DRY" | head -n1 | cut -d: -f1)"
    ORDERED_MESSAGE_LINE="$(grep -n 'drive_real_ui_pair.dart message ' "$REAL_UI_ORDERED_DRY" | head -n1 | cut -d: -f1)"
    if [[ "$ORDERED_LAUNCH_COUNT" -eq 1 && -n "$ORDERED_DETAIL_LINE" && -n "$ORDERED_MESSAGE_LINE" \
        && "$ORDERED_DETAIL_LINE" -lt "$ORDERED_MESSAGE_LINE" ]]; then
        pass "ordered real-UI selection stays on one launch"
    else
        fail "ordered real-UI selection stays on one launch" \
            "expected a single launch with detail before message, but saw $ORDERED_LAUNCH_COUNT launches"
    fi
else
    fail "ordered real-UI dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_ordered.err" "$REAL_UI_ORDERED_DRY" 2>/dev/null)"
fi

REAL_UI_CAMPAIGN_DRY="$TMP_ROOT/real_ui_campaign_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-detail \
    >"$REAL_UI_CAMPAIGN_DRY" 2>"$TMP_ROOT/real_ui_campaign.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake_detail ' "$REAL_UI_CAMPAIGN_DRY" \
        && grep -q 'drive_real_ui_pair.dart message ' "$REAL_UI_CAMPAIGN_DRY" \
        && ! grep -q 'drive_real_ui_pair.dart decline ' "$REAL_UI_CAMPAIGN_DRY"; then
        pass "--real-ui-campaign expands the named merged batch"
    else
        fail "--real-ui-campaign expands the named merged batch"
    fi
else
    fail "real-UI campaign dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_campaign.err" "$REAL_UI_CAMPAIGN_DRY" 2>/dev/null)"
fi

REAL_UI_INLINE_PLAN="$TMP_ROOT/real_ui_inline_plan.json"
if run_runner --plan-json --class=2proc-ui \
    --real-ui-campaign=accepted-friend-inline >"$REAL_UI_INLINE_PLAN" \
    2>"$TMP_ROOT/real_ui_inline.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios == ["handshake", "message"]
    ' "$REAL_UI_INLINE_PLAN" >/dev/null; then
        pass "accepted-friend-inline campaign keeps handshake+message chained"
    else
        fail "accepted-friend-inline campaign keeps handshake+message chained"
    fi
    if jq -e '
        (.groups[0].commands[0] == "tool/mcp_test/launch_fixture_c_pair.sh")
        and ([.groups[0].commands[] | select(contains("reset_friendship"))]
            | length == 0)
    ' "$REAL_UI_INLINE_PLAN" >/dev/null; then
        pass "accepted-friend-inline plan-json reuses one fresh launch without resets"
    else
        fail "accepted-friend-inline plan-json reuses one fresh launch without resets"
    fi
else
    fail "accepted-friend-inline plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_inline.err" "$REAL_UI_INLINE_PLAN" 2>/dev/null)"
fi

REAL_UI_CHAIN_DRY="$TMP_ROOT/real_ui_chain_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-scenario=handshake,message \
    >"$REAL_UI_CHAIN_DRY" 2>"$TMP_ROOT/real_ui_chain.err"; then
    CHAIN_LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_CHAIN_DRY" || true)"
    CHAIN_HANDSHAKE_LINE="$(grep -n 'drive_real_ui_pair.dart handshake ' "$REAL_UI_CHAIN_DRY" | head -n1 | cut -d: -f1)"
    CHAIN_MESSAGE_LINE="$(grep -n 'drive_real_ui_pair.dart message ' "$REAL_UI_CHAIN_DRY" | head -n1 | cut -d: -f1)"
    if [[ "$CHAIN_LAUNCH_COUNT" -eq 1 && -n "$CHAIN_HANDSHAKE_LINE" && -n "$CHAIN_MESSAGE_LINE" \
        && "$CHAIN_HANDSHAKE_LINE" -lt "$CHAIN_MESSAGE_LINE" ]]; then
        pass "handshake+message replay stays on one real-UI launch"
    else
        fail "handshake+message replay stays on one real-UI launch" \
            "expected a single launch with handshake before message, but saw $CHAIN_LAUNCH_COUNT launches"
    fi
else
    fail "real-UI handshake+message dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_chain.err" "$REAL_UI_CHAIN_DRY" 2>/dev/null)"
fi

REAL_UI_MESSAGE_PLAN="$TMP_ROOT/real_ui_message_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-scenario=message \
    >"$REAL_UI_MESSAGE_PLAN" 2>"$TMP_ROOT/real_ui_message.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios == ["message"]
    ' "$REAL_UI_MESSAGE_PLAN" >/dev/null; then
        pass "message-only plan-json narrows to the requested scenario"
    else
        fail "message-only plan-json narrows to the requested scenario"
    fi
    if jq -e '
        (.groups[0].commands | length) == 3
        and .groups[0].commands[0]
            == "TOXEE_FIXTURE_C_RESTORE=paired_for_e2e tool/mcp_test/launch_fixture_c_pair.sh"
    ' "$REAL_UI_MESSAGE_PLAN" >/dev/null; then
        pass "message-only plan-json restores the friended baseline instead of re-handshaking"
    else
        fail "message-only plan-json restores the friended baseline instead of re-handshaking"
    fi
else
    fail "message-only plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_message.err" "$REAL_UI_MESSAGE_PLAN" 2>/dev/null)"
fi

REAL_UI_GROUP_MESSAGE_PLAN="$TMP_ROOT/real_ui_group_message_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-scenario=group_message \
    >"$REAL_UI_GROUP_MESSAGE_PLAN" 2>"$TMP_ROOT/real_ui_group_message.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios == ["group_message"]
    ' "$REAL_UI_GROUP_MESSAGE_PLAN" >/dev/null; then
        pass "group_message plan-json narrows to the requested scenario"
    else
        fail "group_message plan-json narrows to the requested scenario"
    fi
    if jq -e '
        (.groups[0].commands | length) == 3
        and .groups[0].commands[0]
            == "TOXEE_FIXTURE_C_RESTORE=paired_for_e2e tool/mcp_test/launch_fixture_c_pair.sh"
    ' "$REAL_UI_GROUP_MESSAGE_PLAN" >/dev/null; then
        pass "group_message plan-json restores the friended baseline"
    else
        fail "group_message plan-json restores the friended baseline"
    fi
else
    fail "group_message plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_group_message.err" "$REAL_UI_GROUP_MESSAGE_PLAN" 2>/dev/null)"
fi

REAL_UI_RESTORE_RESET_DRY="$TMP_ROOT/real_ui_restore_reset_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-scenario=message,decline \
    >"$REAL_UI_RESTORE_RESET_DRY" 2>"$TMP_ROOT/real_ui_restore_reset.err"; then
    RESTORE_LAUNCH_COUNT="$(grep -c '^TOXEE_FIXTURE_C_RESTORE=paired_for_e2e tool/mcp_test/launch_fixture_c_pair.sh$' "$REAL_UI_RESTORE_RESET_DRY" || true)"
    RESTORED_MESSAGE_COUNT="$(grep -c 'drive_real_ui_pair.dart --boot-restored message ' "$REAL_UI_RESTORE_RESET_DRY" || true)"
    RESET_COUNT="$(grep -c 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_RESTORE_RESET_DRY" || true)"
    BOOTED_DECLINE_COUNT="$(grep -c 'drive_real_ui_pair.dart --boot-restored decline ' "$REAL_UI_RESTORE_RESET_DRY" || true)"
    RESTORE_LINE="$(grep -n '^TOXEE_FIXTURE_C_RESTORE=paired_for_e2e tool/mcp_test/launch_fixture_c_pair.sh$' "$REAL_UI_RESTORE_RESET_DRY" | head -n1 | cut -d: -f1)"
    MESSAGE_LINE="$(grep -n 'drive_real_ui_pair.dart --boot-restored message ' "$REAL_UI_RESTORE_RESET_DRY" | head -n1 | cut -d: -f1)"
    RESET_LINE="$(grep -n 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_RESTORE_RESET_DRY" | head -n1 | cut -d: -f1)"
    DECLINE_LINE="$(grep -n 'drive_real_ui_pair.dart decline ' "$REAL_UI_RESTORE_RESET_DRY" | head -n1 | cut -d: -f1)"
    STOP_LINE="$(grep -n '^tool/mcp_test/stop_fixture_c_pair.sh$' "$REAL_UI_RESTORE_RESET_DRY" | head -n1 | cut -d: -f1)"
    if [[ "$RESTORE_LAUNCH_COUNT" -eq 1 && "$RESTORED_MESSAGE_COUNT" -eq 1 \
        && "$RESET_COUNT" -eq 1 && "$BOOTED_DECLINE_COUNT" -eq 0 \
        && -n "$RESTORE_LINE" && -n "$MESSAGE_LINE" && -n "$RESET_LINE" \
        && -n "$DECLINE_LINE" && -n "$STOP_LINE" \
        && "$RESTORE_LINE" -lt "$MESSAGE_LINE" \
        && "$MESSAGE_LINE" -lt "$RESET_LINE" \
        && "$RESET_LINE" -lt "$DECLINE_LINE" \
        && "$DECLINE_LINE" -lt "$STOP_LINE" ]]; then
        pass "restore -> reset -> no-friend dry-run clears --boot-restored after friendship reset"
    else
        fail "restore -> reset -> no-friend dry-run clears --boot-restored after friendship reset" \
            "expected restore launch, boot-restored message, one reset, plain decline, then stop"
    fi
else
    fail "restore/reset/no-friend dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_restore_reset.err" "$REAL_UI_RESTORE_RESET_DRY" 2>/dev/null)"
fi

REAL_UI_NO_FRIEND_PLAN="$TMP_ROOT/real_ui_no_friend_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-campaign=fresh-no-friend \
    >"$REAL_UI_NO_FRIEND_PLAN" 2>"$TMP_ROOT/real_ui_no_friend.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios == ["decline"]
    ' "$REAL_UI_NO_FRIEND_PLAN" >/dev/null; then
        pass "fresh-no-friend campaign maps to the decline-only branch"
    else
        fail "fresh-no-friend campaign maps to the decline-only branch"
    fi
    if jq -e '
        (.groups[0].commands | length) == 3
        and .groups[0].commands[0] == "tool/mcp_test/launch_fixture_c_pair.sh"
    ' "$REAL_UI_NO_FRIEND_PLAN" >/dev/null; then
        pass "fresh-no-friend plan-json stays on a fresh no-friend launch"
    else
        fail "fresh-no-friend plan-json stays on a fresh no-friend launch"
    fi
else
    fail "fresh-no-friend plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_no_friend.err" "$REAL_UI_NO_FRIEND_PLAN" 2>/dev/null)"
fi

REAL_UI_NO_FRIEND_CALL_PLAN="$TMP_ROOT/real_ui_no_friend_call_plan.json"
if run_runner --plan-json --class=2proc-ui \
    --real-ui-campaign=no-friend-inline-call >"$REAL_UI_NO_FRIEND_CALL_PLAN" \
    2>"$TMP_ROOT/real_ui_no_friend_call.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios
        == ["custom_message", "handshake", "call_voice"]
    ' "$REAL_UI_NO_FRIEND_CALL_PLAN" >/dev/null; then
        pass "no-friend-inline-call campaign preserves the expected custom-message -> handshake -> call chain"
    else
        fail "no-friend-inline-call campaign preserves the expected custom-message -> handshake -> call chain"
    fi
    if jq -e '
        (.groups[0].commands[0] == "tool/mcp_test/launch_fixture_c_pair.sh")
        and ([.groups[0].commands[] | select(contains("reset_friendship"))]
            | length == 0)
    ' "$REAL_UI_NO_FRIEND_CALL_PLAN" >/dev/null; then
        pass "no-friend-inline-call stays on one launch without extra reset maintenance"
    else
        fail "no-friend-inline-call stays on one launch without extra reset maintenance"
    fi
else
    fail "no-friend-inline-call plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_no_friend_call.err" "$REAL_UI_NO_FRIEND_CALL_PLAN" 2>/dev/null)"
fi

REAL_UI_CALL_DRY="$TMP_ROOT/real_ui_call_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-inline-call \
    >"$REAL_UI_CALL_DRY" 2>"$TMP_ROOT/real_ui_call.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake ' "$REAL_UI_CALL_DRY" \
        && grep -q 'drive_real_ui_pair.dart message ' "$REAL_UI_CALL_DRY" \
        && grep -q 'drive_real_ui_pair.dart call_voice ' "$REAL_UI_CALL_DRY"; then
        pass "accepted-friend-inline-call campaign expands call reuse after messaging"
    else
        fail "accepted-friend-inline-call campaign expands call reuse after messaging"
    fi
    CALL_LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_CALL_DRY" || true)"
    if [[ "$CALL_LAUNCH_COUNT" -eq 1 ]]; then
        pass "accepted-friend-inline-call stays on one launch"
    else
        fail "accepted-friend-inline-call stays on one launch" \
            "expected 1 launch but saw $CALL_LAUNCH_COUNT"
    fi
else
    fail "accepted-friend-inline-call dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_call.err" "$REAL_UI_CALL_DRY" 2>/dev/null)"
fi

REAL_UI_CUSTOM_DRY="$TMP_ROOT/real_ui_custom_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-scenario=custom_message \
    >"$REAL_UI_CUSTOM_DRY" 2>"$TMP_ROOT/real_ui_custom.err"; then
    if grep -q 'drive_real_ui_pair.dart custom_message ' "$REAL_UI_CUSTOM_DRY" \
        && ! grep -q 'TOXEE_FIXTURE_C_RESTORE=paired_for_e2e' "$REAL_UI_CUSTOM_DRY"; then
        pass "custom_message scenario stays on a fresh no-friend launch"
    else
        fail "custom_message scenario stays on a fresh no-friend launch"
    fi
else
    fail "custom_message dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_custom.err" "$REAL_UI_CUSTOM_DRY" 2>/dev/null)"
fi

MISSING_PAIR_MANIFEST="$TMP_ROOT/missing_pair_manifest.json"
cat >"$MISSING_PAIR_MANIFEST" <<'JSON'
{
  "fixture_name": "paired_for_e2e",
  "format_version": 1,
  "instances": {
    "A": {"fixture_dir": "definitely_missing_paired_for_e2e_A"},
    "B": {"fixture_dir": "definitely_missing_paired_for_e2e_B"}
  },
  "supported_platforms": ["linux"]
}
JSON
MISSING_PAIR_LOG="$TMP_ROOT/missing_pair_fake.log"
set +e
TOXEE_FIXTURE_C_MANIFEST="$MISSING_PAIR_MANIFEST" \
    FAKE_FAIL_RESTORED_LAUNCH=1 \
    run_runner_with_fake_processes "$MISSING_PAIR_LOG" "$TMP_ROOT/missing_pair_attempts" \
    --class=2proc-ui --real-ui-platform=linux --real-ui-scenario=message \
    >"$TMP_ROOT/missing_pair.out" 2>"$TMP_ROOT/missing_pair.err"
MISSING_PAIR_CODE=$?
set -e
if [[ "$MISSING_PAIR_CODE" -eq 66 ]] \
    && grep -q '\[unified\] paired_for_e2e restore preflight failed' "$TMP_ROOT/missing_pair.err" \
    && grep -q 'tool/mcp_test/fixtures/definitely_missing_paired_for_e2e_A' "$TMP_ROOT/missing_pair.err" \
    && grep -q 'tool/mcp_test/fixtures/definitely_missing_paired_for_e2e_B' "$TMP_ROOT/missing_pair.err" \
    && ! grep -q "$TMP_ROOT" "$TMP_ROOT/missing_pair.err" \
    && ! grep -q 'launch_linux_fixture_c_pair.sh' "$MISSING_PAIR_LOG" 2>/dev/null; then
    pass "missing paired_for_e2e source trees fail before any real-UI launch"
else
    fail "missing paired_for_e2e source trees fail before any real-UI launch" \
        "code=$MISSING_PAIR_CODE err=$(cat "$TMP_ROOT/missing_pair.err" 2>/dev/null) log=$(cat "$MISSING_PAIR_LOG" 2>/dev/null)"
fi

NO_FRIEND_RETRY_LOG="$TMP_ROOT/no_friend_retry_fake.log"
set +e
FAKE_DRIVER_FAIL_FIRST=1 \
    run_runner_with_fake_processes "$NO_FRIEND_RETRY_LOG" "$TMP_ROOT/no_friend_retry_attempts" \
    --class=2proc-ui --real-ui-platform=linux --real-ui-scenario=custom_message \
    >"$TMP_ROOT/no_friend_retry.out" 2>"$TMP_ROOT/no_friend_retry.err"
NO_FRIEND_RETRY_CODE=$?
set -e
NO_FRIEND_FRESH_LAUNCHES="$(grep -c '^bash:tool/mcp_test/launch_linux_fixture_c_pair.sh restore=$' "$NO_FRIEND_RETRY_LOG" || true)"
NO_FRIEND_DRIVER_RUNS="$(grep -c '^dart:run tool/mcp_test/drive_real_ui_pair.dart custom_message ' "$NO_FRIEND_RETRY_LOG" || true)"
if [[ "$NO_FRIEND_RETRY_CODE" -eq 0 \
    && "$NO_FRIEND_FRESH_LAUNCHES" -eq 2 \
    && "$NO_FRIEND_DRIVER_RUNS" -eq 2 ]] \
    && grep -q 'retrying fresh (attempt 1/1)' "$TMP_ROOT/no_friend_retry.out" \
    && ! grep -q 'restore=paired_for_e2e' "$NO_FRIEND_RETRY_LOG"; then
    pass "no-friend real-UI retry relaunches fresh without paired restore"
else
    fail "no-friend real-UI retry relaunches fresh without paired restore" \
        "code=$NO_FRIEND_RETRY_CODE launches=$NO_FRIEND_FRESH_LAUNCHES drivers=$NO_FRIEND_DRIVER_RUNS out=$(cat "$TMP_ROOT/no_friend_retry.out" 2>/dev/null) err=$(cat "$TMP_ROOT/no_friend_retry.err" 2>/dev/null) log=$(cat "$NO_FRIEND_RETRY_LOG" 2>/dev/null)"
fi

SHELL_RECOVERY_SELFTEST="$TMP_ROOT/shell_recovery_selftest.out"
if (cd "$REPO_ROOT" && dart run tool/mcp_test/drive_real_ui_pair.dart --self-test-shell-recovery) \
    >"$SHELL_RECOVERY_SELFTEST" 2>"$TMP_ROOT/shell_recovery_selftest.err"; then
    pass "new-entry shell recovery accepts usable fresh no-friend landmarks"
else
    fail "new-entry shell recovery accepts usable fresh no-friend landmarks" \
        "$(cat "$TMP_ROOT/shell_recovery_selftest.err" "$SHELL_RECOVERY_SELFTEST" 2>/dev/null)"
fi

REAL_UI_EXPANDED_DRY="$TMP_ROOT/real_ui_expanded_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=all-expanded \
    >"$REAL_UI_EXPANDED_DRY" 2>"$TMP_ROOT/real_ui_expanded.err"; then
    if grep -q 'drive_real_ui_pair.dart call_voice ' "$REAL_UI_EXPANDED_DRY" \
        && grep -q 'drive_real_ui_pair.dart custom_message ' "$REAL_UI_EXPANDED_DRY"; then
        pass "all-expanded campaign includes the newly merged reusable cases"
    else
        fail "all-expanded campaign includes the newly merged reusable cases"
    fi
    EXPANDED_LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_EXPANDED_DRY" || true)"
    EXPANDED_RESET_COUNT="$(grep -c 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_EXPANDED_DRY" || true)"
    EXPANDED_CUSTOM_LINE="$(grep -n 'drive_real_ui_pair.dart custom_message ' "$REAL_UI_EXPANDED_DRY" | head -n1 | cut -d: -f1)"
    EXPANDED_RELAUNCH_LINE="$(grep -n '^tool/mcp_test/launch_fixture_c_pair.sh$' "$REAL_UI_EXPANDED_DRY" | tail -n1 | cut -d: -f1)"
    EXPANDED_DETAIL_LINE="$(grep -n 'drive_real_ui_pair.dart handshake_detail ' "$REAL_UI_EXPANDED_DRY" | head -n1 | cut -d: -f1)"
    if [[ "$EXPANDED_LAUNCH_COUNT" -eq 1 && "$EXPANDED_RESET_COUNT" -eq 2 \
        && -n "$EXPANDED_CUSTOM_LINE" && -n "$EXPANDED_DETAIL_LINE" \
        && "$EXPANDED_CUSTOM_LINE" -lt "$EXPANDED_DETAIL_LINE" ]]; then
        pass "all-expanded dry-run keeps custom_message -> handshake_detail on the same launch"
    else
        fail "all-expanded dry-run keeps custom_message -> handshake_detail on the same launch" \
            "expected 1 launch / 2 resets with custom_message before handshake_detail; saw $EXPANDED_LAUNCH_COUNT launch(es) / $EXPANDED_RESET_COUNT reset(s)"
    fi
else
    fail "all-expanded campaign dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_expanded.err" "$REAL_UI_EXPANDED_DRY" 2>/dev/null)"
fi

REAL_UI_EXPANDED_PLAN="$TMP_ROOT/real_ui_expanded_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-campaign=all-expanded \
    >"$REAL_UI_EXPANDED_PLAN" 2>"$TMP_ROOT/real_ui_expanded_plan.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios
        == [
            "handshake",
            "message",
            "message_burst",
            "group_message",
            "conference_message",
            "call_voice",
            "call_reject",
            "custom_message",
            "handshake_detail",
            "decline"
        ]
    ' "$REAL_UI_EXPANDED_PLAN" >/dev/null; then
        pass "all-expanded plan-json preserves the expanded scenario catalog order"
    else
        fail "all-expanded plan-json preserves the expanded scenario catalog order"
    fi
    EXPANDED_PLAN_CMDS="$TMP_ROOT/real_ui_expanded_plan_commands.txt"
    jq -r '.groups[0].commands[]' "$REAL_UI_EXPANDED_PLAN" >"$EXPANDED_PLAN_CMDS"
    EXPANDED_PLAN_LAUNCH_COUNT="$(grep -c '^tool/mcp_test/launch_fixture_c_pair.sh$' "$EXPANDED_PLAN_CMDS" || true)"
    EXPANDED_PLAN_RESET_COUNT="$(grep -c 'reset_friendship ' "$EXPANDED_PLAN_CMDS" || true)"
    EXPANDED_PLAN_CUSTOM_LINE="$(grep -n 'drive_real_ui_pair.dart custom_message ' "$EXPANDED_PLAN_CMDS" | head -n1 | cut -d: -f1)"
    EXPANDED_PLAN_RELAUNCH_LINE="$(grep -n '^tool/mcp_test/launch_fixture_c_pair.sh$' "$EXPANDED_PLAN_CMDS" | tail -n1 | cut -d: -f1)"
    EXPANDED_PLAN_DETAIL_LINE="$(grep -n 'drive_real_ui_pair.dart handshake_detail ' "$EXPANDED_PLAN_CMDS" | head -n1 | cut -d: -f1)"
    if [[ "$EXPANDED_PLAN_LAUNCH_COUNT" -eq 1 && "$EXPANDED_PLAN_RESET_COUNT" -eq 2 \
        && -n "$EXPANDED_PLAN_CUSTOM_LINE" && -n "$EXPANDED_PLAN_DETAIL_LINE" \
        && "$EXPANDED_PLAN_CUSTOM_LINE" -lt "$EXPANDED_PLAN_DETAIL_LINE" ]]; then
        pass "all-expanded plan-json keeps custom_message -> handshake_detail on one launch"
    else
        fail "all-expanded plan-json keeps custom_message -> handshake_detail on one launch"
    fi
else
    fail "all-expanded plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_expanded_plan.err" "$REAL_UI_EXPANDED_PLAN" 2>/dev/null)"
fi

REAL_UI_BURST_DRY="$TMP_ROOT/real_ui_burst_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-inline-burst \
    >"$REAL_UI_BURST_DRY" 2>"$TMP_ROOT/real_ui_burst.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake ' "$REAL_UI_BURST_DRY" \
        && grep -q 'drive_real_ui_pair.dart message_burst ' "$REAL_UI_BURST_DRY"; then
        pass "accepted-friend-inline-burst campaign expands burst messaging reuse"
    else
        fail "accepted-friend-inline-burst campaign expands burst messaging reuse"
    fi
else
    fail "accepted-friend-inline-burst dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_burst.err" "$REAL_UI_BURST_DRY" 2>/dev/null)"
fi

REAL_UI_CALL_REJECT_DRY="$TMP_ROOT/real_ui_call_reject_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-inline-call-reject \
    >"$REAL_UI_CALL_REJECT_DRY" 2>"$TMP_ROOT/real_ui_call_reject.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake ' "$REAL_UI_CALL_REJECT_DRY" \
        && grep -q 'drive_real_ui_pair.dart call_reject ' "$REAL_UI_CALL_REJECT_DRY"; then
        pass "accepted-friend-inline-call-reject campaign expands reject-call reuse"
    else
        fail "accepted-friend-inline-call-reject campaign expands reject-call reuse"
    fi
else
    fail "accepted-friend-inline-call-reject dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_call_reject.err" "$REAL_UI_CALL_REJECT_DRY" 2>/dev/null)"
fi

REAL_UI_CALL_REJECT_PLAN="$TMP_ROOT/real_ui_call_reject_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-scenario=call_reject \
    >"$REAL_UI_CALL_REJECT_PLAN" 2>"$TMP_ROOT/real_ui_call_reject_plan.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios == ["call_reject"]
    ' "$REAL_UI_CALL_REJECT_PLAN" >/dev/null; then
        pass "call_reject plan-json narrows to the requested scenario"
    else
        fail "call_reject plan-json narrows to the requested scenario"
    fi
    if jq -e '
        (.groups[0].commands | length) == 3
        and .groups[0].commands[0]
            == "TOXEE_FIXTURE_C_RESTORE=paired_for_e2e tool/mcp_test/launch_fixture_c_pair.sh"
    ' "$REAL_UI_CALL_REJECT_PLAN" >/dev/null; then
        pass "call_reject plan-json restores the friended baseline"
    else
        fail "call_reject plan-json restores the friended baseline"
    fi
else
    fail "call_reject plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_call_reject_plan.err" "$REAL_UI_CALL_REJECT_PLAN" 2>/dev/null)"
fi

REAL_UI_FULL_DRY="$TMP_ROOT/real_ui_full_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-detail-full \
    >"$REAL_UI_FULL_DRY" 2>"$TMP_ROOT/real_ui_full.err"; then
    if grep -q 'drive_real_ui_pair.dart message_burst ' "$REAL_UI_FULL_DRY" \
        && grep -q 'drive_real_ui_pair.dart call_voice ' "$REAL_UI_FULL_DRY" \
        && grep -q 'drive_real_ui_pair.dart call_reject ' "$REAL_UI_FULL_DRY"; then
        pass "accepted-friend-detail-full campaign chains common chat and call cases"
    else
        fail "accepted-friend-detail-full campaign chains common chat and call cases"
    fi
else
    fail "accepted-friend-detail-full dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_full.err" "$REAL_UI_FULL_DRY" 2>/dev/null)"
fi

SUITE_DRY="$TMP_ROOT/suite_dry.out"
if run_suite --dry-run --tier=non-media >"$SUITE_DRY" 2>"$TMP_ROOT/suite_dry.err"; then
    if grep -q 'drive_fixture_c_pair.dart' "$SUITE_DRY" \
        && grep -q 'drive_real_ui_pair.dart handshake ' "$SUITE_DRY"; then
        pass "run_fixture_c_suite.sh delegates dry-run to the unified runner"
    else
        fail "run_fixture_c_suite.sh delegates dry-run to the unified runner" \
            "expected unified runner dry-run output"
    fi
else
    fail "run_fixture_c_suite.sh dry-run exits 0" \
        "$(cat "$TMP_ROOT/suite_dry.err" "$SUITE_DRY" 2>/dev/null)"
fi

set +e
run_non_media_alias --dry-run --tier=media >"$TMP_ROOT/non_media_alias_bad.out" 2>&1
BAD_ALIAS_CODE=$?
set -e
if [[ "$BAD_ALIAS_CODE" -eq 64 ]]; then
    pass "run_fixture_c_non_media.sh still rejects non-non-media tiers"
else
    fail "run_fixture_c_non_media.sh still rejects non-non-media tiers" \
        "got $BAD_ALIAS_CODE"
fi

set +e
run_runner --tier=bogus >"$TMP_ROOT/bad_tier.out" 2>&1
BAD_TIER_CODE=$?
set -e
if [[ "$BAD_TIER_CODE" -eq 64 ]]; then
    pass "invalid tier exits 64"
else
    fail "invalid tier exits 64" "got $BAD_TIER_CODE"
fi

# The four A/B pair launch/stop scripts the plans reference must exist on disk.
for script in \
    launch_android_fixture_c_pair.sh stop_android_fixture_c_pair.sh \
    launch_windows_fixture_c_pair.ps1 stop_windows_fixture_c_pair.ps1; do
    if [[ -s "$MCP_DIR/$script" ]]; then
        pass "$script exists for the real-UI pair plan"
    else
        fail "$script exists for the real-UI pair plan" "missing or empty: $MCP_DIR/$script"
    fi
done

# Android real-UI now GENERATES + EXECUTES a real two-instance plan (no longer a
# 64-exit blocker). The named IRC loopback scenario must plan launch -> driver
# (with the android pair.json + platform + the fixed IRC loopback port that the
# launcher adb-reverses) -> stop.
ANDROID_IRC_PLAN="$TMP_ROOT/android_irc_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-platform=android \
    --real-ui-scenario=irc_join_channel_loopback_live \
    >"$ANDROID_IRC_PLAN" 2>"$TMP_ROOT/android_irc.err"; then
    ANDROID_CMDS="$TMP_ROOT/android_irc_cmds.txt"
    jq -r '.groups[0].commands[]' "$ANDROID_IRC_PLAN" >"$ANDROID_CMDS" 2>/dev/null || true
    # The IRC loopback port must be on the LAUNCH command itself (the launcher
    # adb-reverses it), matching the live launch env — not only on the driver line.
    if grep -q '^TOXEE_IRC_LOOPBACK_PORT=16667 tool/mcp_test/launch_android_fixture_c_pair.sh$' "$ANDROID_CMDS" \
        && grep -q '^tool/mcp_test/stop_android_fixture_c_pair.sh$' "$ANDROID_CMDS" \
        && grep -q 'TOXEE_REAL_UI_PAIR_JSON=tool/mcp_test/.android_runtime/pair.json' "$ANDROID_CMDS" \
        && grep -q 'TOXEE_REAL_UI_PLATFORM=android' "$ANDROID_CMDS" \
        && grep -q 'drive_real_ui_pair.dart irc_join_channel_loopback_live ' "$ANDROID_CMDS"; then
        pass "android real-UI plan launches the A/B pair + drives the IRC loopback scenario"
    else
        fail "android real-UI plan launches the A/B pair + drives the IRC loopback scenario" \
            "$(cat "$ANDROID_CMDS")"
    fi
else
    fail "android real-UI plan-json exits 0" \
        "$(cat "$TMP_ROOT/android_irc.err" "$ANDROID_IRC_PLAN" 2>/dev/null)"
fi

# Windows real-UI now GENERATES + EXECUTES a real two-instance plan too, invoked
# via PowerShell. The runner, driver, both apps, and the loopback IRC server all
# live on the Windows host, so NO adb-reverse / IRC loopback port is injected.
WINDOWS_IRC_PLAN="$TMP_ROOT/windows_irc_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-platform=windows \
    --real-ui-scenario=irc_join_channel_loopback_live \
    >"$WINDOWS_IRC_PLAN" 2>"$TMP_ROOT/windows_irc.err"; then
    WINDOWS_CMDS="$TMP_ROOT/windows_irc_cmds.txt"
    jq -r '.groups[0].commands[]' "$WINDOWS_IRC_PLAN" >"$WINDOWS_CMDS" 2>/dev/null || true
    if grep -q '^TOXEE_PAIR_TCP_ONLY=1 powershell -ExecutionPolicy Bypass -File tool/mcp_test/launch_windows_fixture_c_pair.ps1$' "$WINDOWS_CMDS" \
        && grep -q '^powershell -ExecutionPolicy Bypass -File tool/mcp_test/stop_windows_fixture_c_pair.ps1$' "$WINDOWS_CMDS" \
        && grep -q 'TOXEE_REAL_UI_PAIR_JSON=build/windows_runtime/pair.json' "$WINDOWS_CMDS" \
        && grep -q 'TOXEE_REAL_UI_PLATFORM=windows' "$WINDOWS_CMDS" \
        && ! grep -q 'TOXEE_IRC_LOOPBACK_PORT' "$WINDOWS_CMDS"; then
        pass "windows real-UI plan launches the A/B pair via PowerShell (host-local IRC, no reverse)"
    else
        fail "windows real-UI plan launches the A/B pair via PowerShell (host-local IRC, no reverse)" \
            "$(cat "$WINDOWS_CMDS")"
    fi
else
    fail "windows real-UI plan-json exits 0" \
        "$(cat "$TMP_ROOT/windows_irc.err" "$WINDOWS_IRC_PLAN" 2>/dev/null)"
fi

# All five platforms now implement paired_for_e2e restore. Android streams the
# portable snapshot into the debug app sandbox via `adb exec-in run-as ... tar`
# (launch_android_fixture_c_pair.sh), so the old planning-time reject is gone
# and a friendship-dependent scenario must PLAN successfully — same as
# Windows/Linux (restore_fixture_c_pair.ps1 / .sh).
for plat in android windows linux; do
    set +e
    run_runner --plan-json --class=2proc-ui --real-ui-platform="$plat" \
        --real-ui-scenario=message >"$TMP_ROOT/${plat}_restore_plan.out" 2>&1
    RESTORE_PLAN_CODE=$?
    set -e
    if [[ "$RESTORE_PLAN_CODE" -eq 0 ]] \
        && grep -q 'paired_for_e2e' "$TMP_ROOT/${plat}_restore_plan.out"; then
        pass "$plat real-UI plans a friendship-dependent scenario (restore implemented)"
    else
        fail "$plat real-UI plans a friendship-dependent scenario (restore implemented)" \
            "got $RESTORE_PLAN_CODE: $(tail -5 "$TMP_ROOT/${plat}_restore_plan.out" 2>/dev/null)"
    fi
done

# A genuinely unknown platform still fails fast (the validation seam is intact).
set +e
run_runner --plan-json --class=2proc-ui --real-ui-platform=plan9 \
    >"$TMP_ROOT/unknown_platform.out" 2>&1
UNKNOWN_PLATFORM_CODE=$?
set -e
if [[ "$UNKNOWN_PLATFORM_CODE" -eq 64 ]] \
    && grep -q 'unknown real-UI platform: plan9' "$TMP_ROOT/unknown_platform.out"; then
    pass "unknown real-UI platform still exits 64"
else
    fail "unknown real-UI platform still exits 64" \
        "got $UNKNOWN_PLATFORM_CODE: $(cat "$TMP_ROOT/unknown_platform.out")"
fi

if run_runner --validate-only >"$TMP_ROOT/validate.out" 2>&1; then
    pass "--validate-only exits 0"
else
    fail "--validate-only exits 0" "$(cat "$TMP_ROOT/validate.out")"
fi

# ---------------------------------------------------------------------------
# Scenario-name drift check (pure text analysis; needs no dart, no Toxee).
#
# `_validRealUiScenarios` in fixture_c_unified_runner.dart is a SECOND,
# hand-maintained copy of the scenario names that drive_real_ui_pair*.dart
# actually dispatches on. Nothing linked the two, so the sets agreeing was pure
# luck. Two failure modes this catches:
#
#   * runner-only name  -> `--real-ui-scenario=<name>` is accepted, the driver
#     has no branch for it, and (before the fall-through reject in
#     drive_real_ui_pair.dart) it silently ran a plain handshake and passed.
#   * unexpected driver-only name -> a scenario exists but is unreachable from
#     the runner. A small set of these is INTENTIONAL (internal utilities,
#     probes, cross-host cases, and the settings_* singles that only run inside
#     settings_sweep); they are allowlisted below and must be updated
#     deliberately, which is exactly the review moment this check exists for.
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
    fail "real-UI scenario-name drift check" "python3 is required"
else
    DRIFT_OUT="$TMP_ROOT/scenario_drift.out"
    set +e
    MCP_DIR="$MCP_DIR" python3 - >"$DRIFT_OUT" 2>&1 <<'PY'
import glob
import os
import re
import sys

mcp = os.environ["MCP_DIR"]

# Driver-only scenario names that are deliberately NOT exposed through the
# runner's --real-ui-scenario surface. Keep this list SHORT and justified.
ALLOWED_DRIVER_ONLY = {
    # Internal runner utility, invoked by name from the runner's own reset step.
    "reset_friendship",
    # Live diagnostics / probes driven by hand, not part of any campaign.
    "probe_home_root",
    "probe_restyle_diag",
    # Cross-host (two physical machines) cases driven by their own launcher.
    "xhost_group_join",
    "xhost_conference",
    "xhost_call",
    # Individual settings cases; the runner exposes the sweep, not the singles.
    "settings_sweep",
    "settings_copy_id",
    "settings_autologin",
    "settings_notification",
    "settings_export_chooser",
    "settings_password",
    "settings_logout_relogin",
    "settings_logout_double_fire",
}


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def strip_line_comments(src):
    return "\n".join(
        line for line in src.splitlines() if not line.lstrip().startswith("//")
    )


def brace_body(text, open_index):
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_index + 1 : i]
    return ""


def quoted(text):
    return set(re.findall(r"'([A-Za-z0-9_]+)'", text))


sources = {
    path: strip_line_comments(read(path))
    for path in glob.glob(os.path.join(mcp, "drive_real_ui_pair*.dart"))
}
# The dispatch chain is drive_real_ui_pair.dart PLUS any part file that owns an
# extracted `Future<int?> dispatchXxx(...)` helper. Those extractions exist
# because drive_real_ui_pair.dart is pinned in tool/.complexity_baseline.txt, so
# whole dispatch blocks get moved into a part file instead of the file being
# re-pinned; reading only the main file would then report every moved scenario
# as "runner accepts a name the driver never dispatches".
dispatch_path = os.path.join(mcp, "drive_real_ui_pair.dart")
dispatch_paths = [dispatch_path] + sorted(
    path
    for path, text in sources.items()
    if path != dispatch_path
    and re.search(r"Future<int\?>\s+dispatch[A-Za-z0-9_]*\(", text)
)
dispatch = "\n".join(sources[path] for path in dispatch_paths)

# 1) Direct `scenario == '<name>'` branches in the dispatch chain.
driver = set(re.findall(r"scenario == '([A-Za-z0-9_]+)'", dispatch))

# 2) `_isXxxCaseScenario(scenario)` predicates -> their backing name set,
#    either an inline `const {...}.contains(scenario)` or `_someSet.contains(...)`.
predicates = sorted(
    name[: -len("(scenario)")]
    for name in set(re.findall(r"_is[A-Za-z0-9]+\(scenario\)", dispatch))
)
unresolved = []
for predicate in predicates:
    resolved = None
    for text in sources.values():
        match = re.search(
            r"bool\s+" + re.escape(predicate) + r"\(String\s+\w+\)\s*=>\s*(.*?);",
            text,
            re.S,
        )
        if not match:
            continue
        body = match.group(1)
        stripped = body.lstrip()
        if "contains" in body and (
            stripped.startswith("const") or stripped.startswith("{")
        ):
            open_index = text.index("{", match.start(1))
            resolved = quoted(brace_body(text, open_index))
            break
        var_match = re.match(r"\s*(_[A-Za-z0-9]+)\.contains", body)
        if var_match:
            var = var_match.group(1)
            for other in sources.values():
                decl = re.search(
                    r"(?:const|final)\s+" + re.escape(var) + r"\s*=\s*(?:<String>)?\{",
                    other,
                )
                if decl:
                    open_index = other.index("{", decl.start())
                    resolved = quoted(brace_body(other, open_index))
                    break
            break
        break
    if resolved is None:
        unresolved.append(predicate)
    else:
        driver |= resolved

runner_src = strip_line_comments(read(os.path.join(mcp, "fixture_c_unified_runner.dart")))
# The catalog is either declared inline in the runner or (current layout)
# aliased to a const in fixture_c_real_ui_scenarios.dart, the same way the
# campaign matrix was split into fixture_c_real_ui_mobile_campaigns.dart. Follow
# the alias rather than pinning this check to one file layout.
catalog_src = runner_src
decl = re.search(r"const _validRealUiScenarios = \{", runner_src)
if not decl:
    alias = re.search(r"const _validRealUiScenarios = ([A-Za-z0-9_]+);", runner_src)
    if not alias:
        print("could not locate _validRealUiScenarios in fixture_c_unified_runner.dart")
        sys.exit(1)
    catalog_src = strip_line_comments(
        read(os.path.join(mcp, "fixture_c_real_ui_scenarios.dart"))
    )
    decl = re.search(
        r"const " + re.escape(alias.group(1)) + r"\s*=\s*(?:<String>)?\{",
        catalog_src,
    )
    if not decl:
        print(
            "could not locate the %s catalog backing _validRealUiScenarios"
            % alias.group(1)
        )
        sys.exit(1)
valid = quoted(brace_body(catalog_src, catalog_src.index("{", decl.start())))

problems = []
if unresolved:
    problems.append(
        "could not resolve dispatch predicate(s): " + ", ".join(unresolved)
    )
if not driver or not valid:
    problems.append("extraction produced an empty set (parser drift?)")

runner_only = sorted(valid - driver)
if runner_only:
    problems.append(
        "runner accepts scenario(s) the driver never dispatches: "
        + ", ".join(runner_only)
    )

driver_only = sorted(driver - valid - ALLOWED_DRIVER_ONLY)
if driver_only:
    problems.append(
        "driver dispatches scenario(s) the runner cannot select "
        "(add to _validRealUiScenarios or to ALLOWED_DRIVER_ONLY here): "
        + ", ".join(driver_only)
    )

stale = sorted(ALLOWED_DRIVER_ONLY - driver)
if stale:
    problems.append(
        "ALLOWED_DRIVER_ONLY lists name(s) the driver no longer dispatches: "
        + ", ".join(stale)
    )

if problems:
    for problem in problems:
        print(problem)
    sys.exit(1)

print(
    "driver dispatch names=%d runner _validRealUiScenarios=%d "
    "(allowlisted driver-only=%d)"
    % (len(driver), len(valid), len(ALLOWED_DRIVER_ONLY))
)
PY
    DRIFT_CODE=$?
    set -e
    if [[ "$DRIFT_CODE" -eq 0 ]]; then
        pass "real-UI scenario names match between runner and driver dispatch"
    else
        fail "real-UI scenario names match between runner and driver dispatch" \
            "$(cat "$DRIFT_OUT")"
    fi
fi

# The driver must REJECT a scenario name that has no dispatch branch instead of
# letting it fall through to the generic add-friend/handshake flow and exiting 0.
# Asserted at the SOURCE level: actually invoking the driver requires two live
# VM services, which this hermetic script must never need.
DRIVER_SRC="$MCP_DIR/drive_real_ui_pair.dart"
if grep -q 'const _genericHandshakeScenarios = <String>{' "$DRIVER_SRC" \
    && grep -q '!_genericHandshakeScenarios.contains(scenario)' "$DRIVER_SRC" \
    && grep -A 8 '!_genericHandshakeScenarios.contains(scenario)' "$DRIVER_SRC" \
        | grep -q 'return 64;'; then
    pass "drive_real_ui_pair.dart guards the generic handshake fall-through (usage 64)"
else
    fail "drive_real_ui_pair.dart guards the generic handshake fall-through (usage 64)" \
        "expected an _genericHandshakeScenarios reject returning 64 in $DRIVER_SRC"
fi

# The runner must keep the SKIP / flaky accountability surface: a counted SKIP
# list, a first-attempt-failure list, and the two opt-in gates. Without these a
# chain that skips (or silently retries) every scenario still reports green.
if grep -q '_realUiSkippedScenarios' "$RUNNER" \
    && grep -q '_realUiFirstAttemptFailures' "$RUNNER" \
    && grep -q "'--fail-on-skip'" "$RUNNER" \
    && grep -q "'--fail-on-flaky'" "$RUNNER"; then
    pass "runner keeps the real-UI SKIP/flaky tallies and --fail-on-skip/--fail-on-flaky gates"
else
    fail "runner keeps the real-UI SKIP/flaky tallies and --fail-on-skip/--fail-on-flaky gates" \
        "expected _realUiSkippedScenarios/_realUiFirstAttemptFailures + both flags in $RUNNER"
fi

# `--fail-on-skip` / `--fail-on-flaky` must be accepted arguments (the runner
# rejects unknown arguments with 64), and must not disturb hermetic planning.
set +e
run_runner --plan-json --class=2proc-ui --fail-on-skip --fail-on-flaky \
    >"$TMP_ROOT/fail_on_skip_plan.json" 2>"$TMP_ROOT/fail_on_skip.err"
FAIL_ON_SKIP_CODE=$?
set -e
if [[ "$FAIL_ON_SKIP_CODE" -eq 0 ]] \
    && jq -e '.groups[0].mode == "real-ui"' "$TMP_ROOT/fail_on_skip_plan.json" >/dev/null; then
    pass "--fail-on-skip/--fail-on-flaky are accepted and leave planning unchanged"
else
    fail "--fail-on-skip/--fail-on-flaky are accepted and leave planning unchanged" \
        "got $FAIL_ON_SKIP_CODE: $(cat "$TMP_ROOT/fail_on_skip.err" 2>/dev/null)"
fi

echo
if (( FAIL_COUNT == 0 )); then
    printf 'Unified Fixture C runner regressions: PASS (%d checks)\n' "$PASS_COUNT"
else
    printf 'Unified Fixture C runner regressions: FAIL (%d failed, %d passed)\n' \
        "$FAIL_COUNT" "$PASS_COUNT"
fi
exit "$FAIL_COUNT"
