#!/usr/bin/env bash
# Echo peer fixture — Phase 1 contract smoke.
#
# Verifies the assertions about the echo peer binary that DO NOT require a
# running toxee app:
#
#   1. State directory honored — ECHO_PEER_STATE_DIR redirects all persistent
#      writes into the directory we point at (default would write under
#      ~/Library/Application Support/tim2tox on macOS).
#   2. ID stability across restart — bringing the same state dir back up
#      produces the same Tox hex address.
#   5. Teardown discipline — SIGTERM stops the peer within 5s; no zombies
#      left under `pgrep -f echo_peer_src/build/echo_peer`.
#   6. Format contract recording — writes build/mcp_test/echo_peer_contract.json
#      with the observed id_length, id emit format, stream, and timings.
#   7. Tracked contract immutability — source-state checksum remains unchanged.
#
# Assertions 3 (AddFriend handshake) and 4 (echo arrival) are DEFERRED to a
# follow-up phase that will wire up `MCP_BINDING=marionette ./run_toxee.sh`
# + the AddFriend dialog driving. They need toxee + marionette running, which
# is a separate orchestration concern.
#
# Exit 0 iff all 5 toxee-independent assertions PASS. Exit 1 on any FAIL.
#
# Reference: /tmp/codex_round7/echo_peer_v2.3.md "Phase 1 — Contract smoke".
set -euo pipefail

# -------------- Configuration ----------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PEER_BIN="${ECHO_PEER_BIN:-$REPO_ROOT/tool/mcp_test/echo_peer_src/build/echo_peer}"
CONTRACT_OUT="${ECHO_PEER_CONTRACT_OUT:-$REPO_ROOT/build/mcp_test/echo_peer_contract.json}"
TRACKED_CONTRACT="$REPO_ROOT/tool/mcp_test/echo_peer_contract.json"

ID_PREFIX='ECHO_PEER_TOX_ID:'
ID_EMIT_LINE_FORMAT="${ID_PREFIX} <id>"
# id_emit_stream is DERIVED from observation (see assertion 1), not hard-coded.
# Contract requires "stdout"; "stderr" or "both" indicates a regression.
ID_EMIT_STREAM=""

# Generous: cold DHT bootstrap + Tox profile generation should fit well
# inside 30s on M-series. CI machines might need more — bump via env if so.
ID_WAIT_SECS="${ECHO_PEER_ID_WAIT_SECS:-30}"
TEARDOWN_WAIT_SECS="${ECHO_PEER_TEARDOWN_WAIT_SECS:-5}"

# -------------- TTY-aware colors -------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    C_GREEN="$(tput setaf 2)"
    C_RED="$(tput setaf 1)"
    C_YELLOW="$(tput setaf 3)"
    C_DIM="$(tput dim)"
    C_RST="$(tput sgr0)"
else
    C_GREEN=""
    C_RED=""
    C_YELLOW=""
    C_DIM=""
    C_RST=""
fi

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_ASSERTIONS=5

declare -a PASS_NAMES=()
declare -a FAIL_NAMES=()

pass() {
    local name="$1"
    PASS_COUNT=$((PASS_COUNT + 1))
    PASS_NAMES+=("$name")
    printf '%s  PASS  %s%s\n' "${C_GREEN}" "$name" "${C_RST}"
}

fail() {
    local name="$1"
    local msg="${2:-}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_NAMES+=("$name")
    printf '%s  FAIL  %s%s\n' "${C_RED}" "$name" "${C_RST}"
    if [[ -n "$msg" ]]; then
        printf '        %s\n' "$msg"
    fi
}

note() {
    printf '%s        %s%s\n' "${C_DIM}" "$1" "${C_RST}"
}

# -------------- Workspace --------------------------------------------------
TMP_ROOT="${TMPDIR:-/tmp}/echo_peer_contract_smoke.$$"
mkdir -p "$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
RUN1_STDOUT="$TMP_ROOT/run1.stdout.log"
RUN1_STDERR="$TMP_ROOT/run1.stderr.log"
RUN2_STDOUT="$TMP_ROOT/run2.stdout.log"
RUN2_STDERR="$TMP_ROOT/run2.stderr.log"
BASELINE_PIDS=""
CONTRACT_TMP=""

cleanup() {
    # Always best-effort kill anything we spawned. We tag children with the
    # binary path so pgrep doesn't catch peers from other concurrent runs.
    if [[ -n "${PEER_PID:-}" ]] && kill -0 "$PEER_PID" 2>/dev/null; then
        kill -KILL "$PEER_PID" 2>/dev/null || true
    fi
    if [[ -n "$CONTRACT_TMP" ]]; then
        rm -f "$CONTRACT_TMP"
    fi
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

CONTRACT_PARENT="$(dirname "$CONTRACT_OUT")"
if ! mkdir -p "$CONTRACT_PARENT" 2>/dev/null; then
    fail "preflight" "contract_output_parent status=create_failed"
    exit 1
fi
if ! CONTRACT_PARENT="$(cd "$CONTRACT_PARENT" 2>/dev/null && pwd -P)"; then
    fail "preflight" "contract_output_parent status=unavailable"
    exit 1
fi
CONTRACT_OUT="$CONTRACT_PARENT/$(basename "$CONTRACT_OUT")"
TRACKED_PARENT="$(cd "$(dirname "$TRACKED_CONTRACT")" && pwd -P)"
TRACKED_CONTRACT="$TRACKED_PARENT/$(basename "$TRACKED_CONTRACT")"
if [[ "$CONTRACT_OUT" == "$TRACKED_CONTRACT" ]]; then
    fail "preflight" "contract_output status=tracked_path_rejected"
    exit 1
fi
if [[ ! -f "$TRACKED_CONTRACT" ]]; then
    fail "preflight" "tracked_contract status=missing"
    exit 1
fi
TRACKED_CONTRACT_CHECKSUM_BEFORE="$(shasum -a 256 "$TRACKED_CONTRACT" | cut -d ' ' -f1)"

# -------------- Pre-flight --------------------------------------------------
echo "Echo peer contract smoke"
echo "  binary status: configured"
echo "  state isolation: enabled"
echo "  contract output: external"
echo

if [[ ! -x "$PEER_BIN" ]]; then
    fail "preflight" "echo_peer_binary status=missing_or_not_executable"
    echo
    printf 'Contract smoke: %sFAIL (preflight)%s\n' "${C_RED}" "${C_RST}"
    exit 1
fi
BASELINE_PIDS="$(pgrep -f "^${PEER_BIN}( |$)" 2>/dev/null || true)"

# -------------- Helpers ----------------------------------------------------

# Launch the peer with a given state dir, capturing stdout and stderr into
# SEPARATE files so the contract's dedicated-stdout assertion is actually
# verifiable. A regression that moved ECHO_PEER_TOX_ID to stderr would have
# silently passed when both streams were merged.
# Globals set: PEER_PID
launch_peer() {
    local state_dir="$1"
    local stdout_file="$2"
    local stderr_file="$3"
    mkdir -p "$state_dir"
    : > "$stdout_file"
    : > "$stderr_file"
    ECHO_PEER_STATE_DIR="$state_dir" "$PEER_BIN" >"$stdout_file" 2>"$stderr_file" &
    PEER_PID=$!
}

# Wait up to N seconds for `ECHO_PEER_TOX_ID:` to appear in log_file.
# Returns 0 on success, 1 on timeout. Also echoes the ms it took.
wait_for_id_line() {
    local log_file="$1"
    local max_secs="$2"
    local start_ms
    start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
    local deadline=$((max_secs * 10))   # 100ms steps
    local i=0
    while (( i < deadline )); do
        if grep -q "^${ID_PREFIX}" "$log_file" 2>/dev/null; then
            local end_ms
            end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
            echo $((end_ms - start_ms))
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    echo "-1"
    return 1
}

# Extract the tox ID hex from a log file (post-emit).
extract_id() {
    local log_file="$1"
    grep -m1 "^${ID_PREFIX}" "$log_file" | sed -E "s|^${ID_PREFIX} *||" | tr -d '\r\n'
}

# Stop the peer with SIGTERM, wait up to max_secs for exit, return ms it took
# (or -1 on timeout). Caller is responsible for setting/clearing PEER_PID.
stop_peer_and_time() {
    local max_secs="$1"
    local pid="${PEER_PID:-}"
    if [[ -z "$pid" ]]; then echo "-1"; return 1; fi
    local start_ms
    start_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
    kill -TERM "$pid" 2>/dev/null || true
    local deadline=$((max_secs * 10))
    local i=0
    while (( i < deadline )); do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || true
            local end_ms
            end_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
            PEER_PID=""
            echo $((end_ms - start_ms))
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    # Force-kill fallback
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    PEER_PID=""
    echo "-1"
    return 1
}

# Capture the "ms-since-start" timestamp of the first regular file under a dir.
# Returns -1 if none. Used to record state_dir_first_write_ms.
state_dir_first_write_ms() {
    local state_dir="$1"
    local start_ms="$2"
    # find -newer with the start file gives us files written after launch.
    local first_file
    first_file="$(find "$state_dir" -type f 2>/dev/null | head -n1 || true)"
    if [[ -z "$first_file" ]]; then echo "-1"; return; fi
    # macOS stat -f%B = creation time in epoch seconds.
    local mtime_s
    mtime_s="$(stat -f %m "$first_file" 2>/dev/null || stat -c %Y "$first_file" 2>/dev/null || echo 0)"
    local mtime_ms=$((mtime_s * 1000))
    if (( mtime_ms < start_ms )); then echo 0; return; fi
    echo $((mtime_ms - start_ms))
}

new_peer_pids_since_baseline() {
    local current
    current="$(pgrep -f "^${PEER_BIN}( |$)" 2>/dev/null || true)"
    /usr/bin/python3 - "$BASELINE_PIDS" "$current" <<'PY'
import sys
baseline = {line.strip() for line in sys.argv[1].splitlines() if line.strip()}
current = [line.strip() for line in sys.argv[2].splitlines() if line.strip()]
for pid in current:
    if pid not in baseline:
        print(pid)
PY
}

# -------------- Assertion 1: state directory honored -----------------------
RUN1_START_MS="$(python3 -c 'import time; print(int(time.time()*1000))')"
launch_peer "$STATE_DIR" "$RUN1_STDOUT" "$RUN1_STDERR"
note "peer_launch status=started"

ID_EMIT_MS="$(wait_for_id_line "$RUN1_STDOUT" "$ID_WAIT_SECS")" || true
if [[ "$ID_EMIT_MS" == "-1" ]]; then
    # Did it land on stderr instead? That's a contract regression worth calling out.
    if grep -q "^${ID_PREFIX}" "$RUN1_STDERR" 2>/dev/null; then
        fail "1. state_directory_honored" \
             "CONTRACT REGRESSION: '${ID_PREFIX}' arrived on STDERR, not STDOUT. Tail of stderr:"
        tail -n 20 "$RUN1_STDERR" | sed -E "s|^${ID_PREFIX}.*|${ID_PREFIX} <redacted>|; s/^/        /"
    else
        fail "1. state_directory_honored" \
             "no '${ID_PREFIX}' line in ${ID_WAIT_SECS}s on either stream; tail of stdout / stderr:"
        echo "        --- stdout ---"
        tail -n 20 "$RUN1_STDOUT" | sed -E "s|^${ID_PREFIX}.*|${ID_PREFIX} <redacted>|; s/^/        /"
        echo "        --- stderr ---"
        tail -n 20 "$RUN1_STDERR" | sed -E "s|^${ID_PREFIX}.*|${ID_PREFIX} <redacted>|; s/^/        /"
    fi
    exit 1
fi
# Stream-leak guard: ID line MUST be on stdout only. If it also shows up on
# stderr (e.g. someone added a duplicate logger), that breaks the dedicated-
# stream contract and downstream parsers that follow stdout alone.
if grep -q "^${ID_PREFIX}" "$RUN1_STDERR" 2>/dev/null; then
    fail "1. state_directory_honored" \
         "CONTRACT REGRESSION: '${ID_PREFIX}' emitted on BOTH stdout AND stderr"
    exit 1
fi
ID_EMIT_STREAM="stdout"
PEER_ID_V1="$(extract_id "$RUN1_STDOUT")"
ID_LENGTH="${#PEER_ID_V1}"

STATE_FILE_COUNT="$(find "$STATE_DIR" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
if [[ ! "$PEER_ID_V1" =~ ^[[:xdigit:]]{76}$ ]]; then
    fail "1. state_directory_honored" \
         "identity status=invalid length=$ID_LENGTH"
elif [[ "$STATE_FILE_COUNT" -ge 1 ]]; then
    pass "1. state_directory_honored"
    note "state_entry_count=${STATE_FILE_COUNT}"
    note "id length: ${ID_LENGTH} chars (emit took ${ID_EMIT_MS}ms)"
else
    fail "1. state_directory_honored" \
         "state_entry_count=0 after_identity_emit=true"
fi

STATE_DIR_FIRST_WRITE_MS="$(state_dir_first_write_ms "$STATE_DIR" "$RUN1_START_MS")"

# -------------- Assertion 5 (part 1): SIGTERM exits within 5s --------------
# We deliberately do the teardown timing now (before run 2) so the first
# instance is fully gone before we re-launch.
TEARDOWN_MS="$(stop_peer_and_time "$TEARDOWN_WAIT_SECS")" || true
if [[ "$TEARDOWN_MS" == "-1" ]]; then
    fail "5. teardown_discipline" \
         "peer did not exit within ${TEARDOWN_WAIT_SECS}s of SIGTERM (force-killed)"
else
    # Only treat NEW residual peers from THIS smoke as a failure. Another
    # shell may legitimately have its own echo peer running already; that
    # should not fail or be killed by this isolated contract check.
    sleep 0.5
    STRAGGLERS="$(new_peer_pids_since_baseline)"
    if [[ -n "$STRAGGLERS" ]]; then
        # Defensive sweep: SIGKILL only the new residuals we introduced.
        # shellcheck disable=SC2086
        kill -KILL $STRAGGLERS 2>/dev/null || true
        STRAGGLER_COUNT="$(printf '%s\n' "$STRAGGLERS" | wc -l | tr -d ' ')"
        fail "5. teardown_discipline" \
             "residual_peer_count=$STRAGGLER_COUNT killed=true"
    else
        pass "5. teardown_discipline"
        note "exited in ${TEARDOWN_MS}ms; no zombies"
    fi
fi

# -------------- Assertion 2: ID stability across restart -------------------
launch_peer "$STATE_DIR" "$RUN2_STDOUT" "$RUN2_STDERR"
note "peer_relaunch status=started same_state=true"
ID_EMIT_MS_V2="$(wait_for_id_line "$RUN2_STDOUT" "$ID_WAIT_SECS")" || true
if [[ "$ID_EMIT_MS_V2" == "-1" ]]; then
    if grep -q "^${ID_PREFIX}" "$RUN2_STDERR" 2>/dev/null; then
        fail "2. id_stability_across_restart" \
             "CONTRACT REGRESSION on restart: '${ID_PREFIX}' arrived on STDERR, not STDOUT"
    else
        fail "2. id_stability_across_restart" \
             "second run never emitted ${ID_PREFIX} on either stream; tail of stdout:"
        tail -n 20 "$RUN2_STDOUT" | sed -E "s|^${ID_PREFIX}.*|${ID_PREFIX} <redacted>|; s/^/        /"
    fi
elif grep -q "^${ID_PREFIX}" "$RUN2_STDERR" 2>/dev/null; then
    fail "2. id_stability_across_restart" \
         "CONTRACT REGRESSION on restart: '${ID_PREFIX}' emitted on BOTH streams"
else
    PEER_ID_V2="$(extract_id "$RUN2_STDOUT")"
    if [[ "$PEER_ID_V1" == "$PEER_ID_V2" ]]; then
        pass "2. id_stability_across_restart"
        note "identity_match=true length=${#PEER_ID_V2}"
    else
        fail "2. id_stability_across_restart" \
             "identity_match=false v1_length=${#PEER_ID_V1} v2_length=${#PEER_ID_V2}"
    fi
fi

# Stop run 2 (don't double-count teardown).
stop_peer_and_time "$TEARDOWN_WAIT_SECS" > /dev/null || true

# -------------- Assertion 6: format contract recording ---------------------
# Capture observed values for the contract JSON. Write atomically.
CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if (( PASS_COUNT >= 3 )); then
    # Only emit the contract JSON if at least the ID emit + restart + teardown
    # assertions passed. Otherwise the values would be polluting future work.
    CONTRACT_TMP="${CONTRACT_OUT}.tmp.$$"
    cat >"$CONTRACT_TMP" <<JSON
{
  "format_version": 1,
  "captured_at": "${CAPTURED_AT}",
  "id_length": ${ID_LENGTH},
  "id_emit_line_format": "${ID_EMIT_LINE_FORMAT}",
  "id_emit_stream": "${ID_EMIT_STREAM}",
  "start_to_id_emit_ms": ${ID_EMIT_MS},
  "state_dir_first_write_ms": ${STATE_DIR_FIRST_WRITE_MS},
  "teardown_ms": ${TEARDOWN_MS}
}
JSON
    mv "$CONTRACT_TMP" "$CONTRACT_OUT"
    CONTRACT_TMP=""
    pass "6. format_contract_recording"
    note "contract_recorded=true"
else
    fail "6. format_contract_recording" \
         "skipped because earlier assertions FAILed (id capture/restart values invalid)"
fi

TRACKED_CONTRACT_CHECKSUM_AFTER="$(shasum -a 256 "$TRACKED_CONTRACT" | cut -d ' ' -f1)"
if [[ "$TRACKED_CONTRACT_CHECKSUM_BEFORE" == "$TRACKED_CONTRACT_CHECKSUM_AFTER" ]]; then
    pass "7. tracked_contract_unchanged"
    note "tracked_contract_unchanged=true"
else
    fail "7. tracked_contract_unchanged" \
         "tracked_contract_unchanged=false"
fi

# -------------- Summary -----------------------------------------------------
echo
TOTAL_RUN=$((PASS_COUNT + FAIL_COUNT))
if (( FAIL_COUNT == 0 )); then
    printf '%sContract smoke: PASS (%d/%d toxee-independent assertions)%s\n' \
        "${C_GREEN}" "$PASS_COUNT" "$TOTAL_ASSERTIONS" "${C_RST}"
    exit 0
else
    printf '%sContract smoke: FAIL (%d PASS / %d FAIL of %d)%s\n' \
        "${C_RED}" "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL_ASSERTIONS" "${C_RST}"
    printf 'failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
