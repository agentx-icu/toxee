#!/usr/bin/env bash
# Echo peer fixture — Phase 3 helpers regression tests.
#
# Codex Round 13 required these two regressions in addition to the existing
# echo_peer_contract_smoke.sh:
#
#   Regression #1 — `stop` during cold `ensure` before JSON write
#     Verifies that a `stop` racing a mid-launch `ensure` blocks on the lock
#     (NOT short-circuiting on missing json), so we never end up with the
#     fixture still running after a "successful" stop. Loops 5x; the property
#     to confirm is that we NEVER observe 2+ peer processes at any time.
#
#   Regression #2 — `ensure` timeout with a peer that never emits the ID line
#     Verifies that a failed startup is reaped with grace + SIGKILL before the
#     lock is released, and that the lock dir is gone (next ensure does not
#     block). Uses /bin/sleep as a stand-in for "binary that never emits".
#
# Designed to run from a clean state (no echo_peer.json, no lock dir, no live
# peer). The script makes a best-effort to leave the workspace in a clean
# state on exit.
#
# Reference: codex Round 13 findings Z4/Z5/Z6/Z7/Z8 + required regression tests.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
ENSURE_SH="$MCP_DIR/ensure_echo_peer.sh"
STOP_SH="$MCP_DIR/stop_echo_peer.sh"
JSON_FILE="$MCP_DIR/echo_peer.json"
LOCK_DIR="$MCP_DIR/.echo_peer.lock"
PEER_BIN_DEFAULT="$MCP_DIR/echo_peer_src/build/echo_peer"
PROTOCOL_TEST_BIN="$MCP_DIR/echo_peer_src/build/echo_peer_protocol_test"
DRIFT_SH="$MCP_DIR/echo_peer_drift_check.sh"
TMP_DRIFT_ROOT=""

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
declare -a FAIL_NAMES=()

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '%s  PASS  %s%s\n' "${C_GREEN}" "$1" "${C_RST}"
}
fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_NAMES+=("$1")
    printf '%s  FAIL  %s%s\n' "${C_RED}" "$1" "${C_RST}"
    if [[ -n "${2:-}" ]]; then
        printf '        %s\n' "$2"
    fi
}
note() {
    printf '%s        %s%s\n' "${C_DIM}" "$1" "${C_RST}"
}

# -------------- Workspace reset --------------------------------------------
# Make sure no leftover peer / lock / json before we start a scenario.
reset_workspace() {
    if [[ -f "$JSON_FILE" ]]; then
        ECHO_PEER_VERBOSE=1 "$STOP_SH" >/dev/null 2>&1 || true
    fi
    rm -f "$JSON_FILE"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    # Defensive: SIGKILL any straggler peer matching the default bin path.
    local stragglers=""
    stragglers="$(pgrep -f "$PEER_BIN_DEFAULT" 2>/dev/null || true)"
    if [[ -n "$stragglers" ]]; then
        # shellcheck disable=SC2086
        kill -KILL $stragglers 2>/dev/null || true
        sleep 0.5
    fi
    return 0
}

# Count live processes matching the peer binary path. Excludes greps and
# our wrapper scripts (they contain the path in their argv).
# Note: pgrep returns 1 on no-match, which under `set -o pipefail` would
# kill the script via `set -e`. We tolerate that explicitly.
count_live_peers() {
    local bin="$1"
    local out
    out="$(pgrep -f "^${bin}( |$)" 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        echo 0
    else
        echo "$out" | wc -l | tr -d ' '
    fi
}

cleanup_all() {
    if [[ -n "$TMP_DRIFT_ROOT" ]]; then
        rm -rf "$TMP_DRIFT_ROOT"
    fi
    reset_workspace
}
trap cleanup_all EXIT

# -------------- Pre-flight -------------------------------------------------
echo "Echo peer helpers regression"
echo "  ensure status: configured"
echo "  stop status: configured"
echo "  peer status: configured"
echo

[[ -x "$ENSURE_SH" ]] || { fail "preflight" "ensure status=missing"; exit 1; }
[[ -x "$STOP_SH"   ]] || { fail "preflight" "stop status=missing"; exit 1; }
[[ -x "$PEER_BIN_DEFAULT" ]] || { fail "preflight" "peer status=missing"; exit 1; }
[[ -x "$PROTOCOL_TEST_BIN" ]] || { fail "preflight" "protocol_test status=missing"; exit 1; }

reset_workspace

# -------------- Regression #1: stop during cold ensure ---------------------
# Goal: with a fresh state (no json), launch `ensure` in the background and,
# within ~50ms, launch `stop` in the background. `stop` MUST block on the
# lock; we must never observe 2+ live peer processes at any time.
#
# We poll the live peer count rapidly while ensure+stop run. The invariant we
# enforce is `max_live <= 1`. After both processes finish, we ALSO require
# that the workspace converges to a sane state: either 0 peers + no json (the
# common case where stop tore down what ensure brought up) or 1 peer + valid
# json (rare race where stop arrived AFTER ensure finished and was a separate
# successful stop — but in that case `stop` would also have removed the json).
# So the converged state should always be 0 peers + no json.
ITERATIONS=5
R1_PASS=0
R1_FAIL=0
declare -a R1_MAX_OBSERVED=()

for i in $(seq 1 "$ITERATIONS"); do
    reset_workspace

    # Quick read on ensure: it forks the peer detached, so the peer survives
    # even if ensure exits. We don't care about its exit code for this test —
    # we only care that during ensure+stop racing we never see >1 peer.
    "$ENSURE_SH" >/dev/null 2>&1 &
    ensure_bg=$!

    # ~50ms race window before launching stop — short enough to catch the
    # pre-json-write window with high probability.
    sleep 0.05
    ECHO_PEER_VERBOSE=1 "$STOP_SH" >/dev/null 2>&1 &
    stop_bg=$!

    # Poll live peer count while both are running. Hard cap at 60s so a
    # hanging ensure doesn't wedge the whole test.
    max_observed=0
    poll_count=0
    while kill -0 "$ensure_bg" 2>/dev/null || kill -0 "$stop_bg" 2>/dev/null; do
        c="$(count_live_peers "$PEER_BIN_DEFAULT")"
        if (( c > max_observed )); then
            max_observed="$c"
        fi
        poll_count=$((poll_count + 1))
        if (( poll_count > 600 )); then
            note "iteration $i hit 60s timeout; killing background jobs"
            kill -KILL "$ensure_bg" "$stop_bg" 2>/dev/null || true
            break
        fi
        sleep 0.1
    done
    wait "$ensure_bg" 2>/dev/null || true
    wait "$stop_bg" 2>/dev/null || true

    # After stop returns, macOS can still momentarily surface the just-reaped
    # pid through pgrep. Give the final observation a short bounded settle
    # window so we don't turn a successful stop into a flaky false positive.
    final=999
    for _ in 1 2 3 4 5; do
        sleep 0.2
        final="$(count_live_peers "$PEER_BIN_DEFAULT")"
        if (( final == 0 )); then
            break
        fi
    done
    if (( final > max_observed )); then
        max_observed="$final"
    fi
    R1_MAX_OBSERVED+=("$max_observed")

    # Invariant 1: never observed 2+ peers.
    if (( max_observed >= 2 )); then
        fail "regression#1 iter=$i" \
             "saw $max_observed concurrent peers; expected <= 1"
        R1_FAIL=$((R1_FAIL + 1))
        # Clean up before next iter.
        reset_workspace
        continue
    fi

    # Invariant 2: converged state — 0 peers AND no json. (Stop always wins
    # eventually: either it stopped what ensure spawned, or it skipped because
    # ensure failed; either way json should be gone and no peer running.)
    if (( final != 0 )); then
        fail "regression#1 iter=$i" \
             "final live peer count=$final (expected 0); residual peer left running"
        R1_FAIL=$((R1_FAIL + 1))
        reset_workspace
        continue
    fi
    if [[ -f "$JSON_FILE" ]]; then
        fail "regression#1 iter=$i" \
             "json still present after stop converged"
        R1_FAIL=$((R1_FAIL + 1))
        reset_workspace
        continue
    fi

    R1_PASS=$((R1_PASS + 1))
    note "iter $i: max_observed=$max_observed, final=0, json cleared"
done

if (( R1_FAIL == 0 )); then
    pass "regression#1: stop-during-cold-ensure (5x)"
    note "max-observed-peers per iter: ${R1_MAX_OBSERVED[*]}"
else
    fail "regression#1: stop-during-cold-ensure (5x)" \
         "$R1_PASS pass / $R1_FAIL fail; max-observed: ${R1_MAX_OBSERVED[*]}"
fi

# -------------- Regression #2: ensure timeout reaps fake peer --------------
# Goal: point ECHO_PEER_BIN at a binary that never emits ECHO_PEER_TOX_ID.
# With a short ECHO_PEER_START_TIMEOUT_SECS, ensure should time out, kill
# the peer it spawned (5s grace + SIGKILL), release the lock, and exit
# non-zero. After the timeout: no leftover fake-peer process, and the next
# ensure does not block on the lock.

reset_workspace

# We need a fake peer that (a) is executed with no args (ensure_echo_peer.sh
# invokes `$PEER_BIN` bare), (b) stays alive long enough that the ensure
# timeout fires, and (c) never prints ECHO_PEER_TOX_ID. A tiny wrapper that
# execs `sleep 600` fits all three.
FAKE_BIN="$(mktemp /tmp/r2.fake_peer.XXXXXX.sh)"
cat >"$FAKE_BIN" <<'SH'
#!/bin/sh
# Never emits ECHO_PEER_TOX_ID; sleeps long enough that ensure's timeout fires.
exec sleep 600
SH
chmod +x "$FAKE_BIN"

R2_BEFORE_FAKES="$(count_live_peers "$FAKE_BIN")"
R2_BEFORE_SLEEPS="$({ pgrep -f '^sleep 600$' 2>/dev/null || true; } | wc -l | tr -d ' ')"

start_ms="$(/usr/bin/python3 -c 'import time; print(int(time.time()*1000))')"

# Wrap the fake binary in a tiny shim so the argv matches `<bin> 600`
# consistently regardless of how the shell mangles env.
ENSURE_OUT="$(mktemp /tmp/r2.ensure.out.XXXXXX)"
ENSURE_ERR="$(mktemp /tmp/r2.ensure.err.XXXXXX)"
set +e
ECHO_PEER_BIN="$FAKE_BIN" \
ECHO_PEER_START_TIMEOUT_SECS=3 \
ECHO_PEER_LAUNCH_FAIL_GRACE_SECS=5 \
    "$ENSURE_SH" >"$ENSURE_OUT" 2>"$ENSURE_ERR"
ensure_rc=$?
set -e

end_ms="$(/usr/bin/python3 -c 'import time; print(int(time.time()*1000))')"
elapsed_ms=$((end_ms - start_ms))

R2_REASONS=()

# Expect non-zero exit (timeout error).
if (( ensure_rc == 0 )); then
    R2_REASONS+=("ensure unexpectedly succeeded (rc=$ensure_rc)")
fi

# Expect bounded duration: at least START_TIMEOUT (3s) + grace overhead, but
# well under 60s. We allow up to 20s to leave room for slow ps loops.
if (( elapsed_ms < 2500 )); then
    R2_REASONS+=("ensure returned too fast (${elapsed_ms}ms); expected >= ~3000ms timeout")
fi
if (( elapsed_ms > 20000 )); then
    R2_REASONS+=("ensure took too long (${elapsed_ms}ms); expected <= 20000ms")
fi

# Expect: no leftover fake-peer process AND no leftover `sleep 600` that the
# fake peer wrapper exec'd into. Both are checked because `exec sleep 600`
# replaces argv, so pgrep on the fake bin path may miss the descendant.
sleep 0.5
R2_AFTER_FAKES="$(count_live_peers "$FAKE_BIN")"
R2_AFTER_SLEEPS="$({ pgrep -f '^sleep 600$' 2>/dev/null || true; } | wc -l | tr -d ' ')"
if (( R2_AFTER_FAKES > R2_BEFORE_FAKES )); then
    leak=$((R2_AFTER_FAKES - R2_BEFORE_FAKES))
    R2_REASONS+=("$leak leftover fake-peer process(es) after ensure timed out (before=$R2_BEFORE_FAKES, after=$R2_AFTER_FAKES)")
fi
if (( R2_AFTER_SLEEPS > R2_BEFORE_SLEEPS )); then
    leak=$((R2_AFTER_SLEEPS - R2_BEFORE_SLEEPS))
    R2_REASONS+=("$leak leftover 'sleep 600' descendant(s) after ensure timed out (before=$R2_BEFORE_SLEEPS, after=$R2_AFTER_SLEEPS)")
    # Defensive: clean up what we leaked.
    pkill -KILL -f '^sleep 600$' 2>/dev/null || true
fi

# Expect: lock dir released — verify the next ensure does not block.
if [[ -d "$LOCK_DIR" ]]; then
    R2_REASONS+=("lock_released=false")
fi

# Belt-and-suspenders: try acquiring + releasing the lock with mkdir directly.
if mkdir "$LOCK_DIR" 2>/dev/null; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
else
    R2_REASONS+=("could not re-acquire lock dir after ensure failure")
fi

if (( ${#R2_REASONS[@]} == 0 )); then
    pass "regression#2: ensure-timeout-reaps-fake-peer"
    note "ensure exited rc=$ensure_rc in ${elapsed_ms}ms; 0 leftover sleeps; lock released"
else
    fail "regression#2: ensure-timeout-reaps-fake-peer" \
         "$(printf '%s; ' "${R2_REASONS[@]}")"
    R2_STDERR_LINE_COUNT="$(wc -l < "$ENSURE_ERR" | tr -d ' ')"
    note "stderr_line_count=$R2_STDERR_LINE_COUNT"
fi

rm -f "$ENSURE_OUT" "$ENSURE_ERR" "$FAKE_BIN"

# -------------- Regression #3: stale json is recovered, not fatal ----------
# Goal: a dead/stale echo_peer.json must NOT trip set -e and abort ensure
# before the stale-cleanup path runs. ensure_echo_peer.sh documents this helper
# as "echoes ok/reason, exit code always 0"; a stale triple should therefore
# be handled as data, not as a fatal shell status.

reset_workspace

cat >"$JSON_FILE" <<JSON
{
  "format_version": 1,
  "pid": 999999,
  "start_time": "Sat May 30 00:00:00 2026",
  "cmdline": "$PEER_BIN_DEFAULT",
  "state_dir": "$MCP_DIR/echo_peer_state",
  "peer_id": "stale",
  "stdout_log": "$MCP_DIR/echo_peer.stdout.log",
  "stderr_log": "$MCP_DIR/echo_peer.stderr.log",
  "started_at": "2026-05-30T00:00:00Z"
}
JSON

R3_OUT="$(mktemp /tmp/r3.ensure.out.XXXXXX)"
R3_ERR="$(mktemp /tmp/r3.ensure.err.XXXXXX)"
set +e
"$ENSURE_SH" >"$R3_OUT" 2>"$R3_ERR"
ensure_rc=$?
set -e

R3_REASONS=()
if (( ensure_rc != 0 )); then
    R3_REASONS+=("ensure exited rc=$ensure_rc on stale json (expected recovery + rc=0)")
fi
if [[ ! -f "$JSON_FILE" ]]; then
    R3_REASONS+=("state_record_rewritten=false")
else
    fresh_pid="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pid",""))' "$JSON_FILE" 2>/dev/null || true)"
    if [[ -z "$fresh_pid" || "$fresh_pid" == "999999" ]]; then
      R3_REASONS+=("state_record_fresh=false")
    elif ! kill -0 "$fresh_pid" 2>/dev/null; then
      R3_REASONS+=("recorded_process_alive=false")
    fi
fi

if (( ${#R3_REASONS[@]} == 0 )); then
    pass "regression#3: stale-json-recovers"
    note "ensure rewrote stale json and launched a live peer"
else
    fail "regression#3: stale-json-recovers" \
         "$(printf '%s; ' "${R3_REASONS[@]}")"
    R3_STDOUT_LINE_COUNT="$(wc -l < "$R3_OUT" | tr -d ' ')"
    R3_STDERR_LINE_COUNT="$(wc -l < "$R3_ERR" | tr -d ' ')"
    note "stdout_line_count=$R3_STDOUT_LINE_COUNT stderr_line_count=$R3_STDERR_LINE_COUNT"
fi

rm -f "$R3_OUT" "$R3_ERR"
reset_workspace

# -------------- Regression #4: C-FFI text/application framing --------------
set +e
R4_OUTPUT="$($PROTOCOL_TEST_BIN 2>&1)"
R4_RC=$?
set -e
if (( R4_RC == 0 )); then
    pass "regression#4: C-FFI protocol framing"
    note "$R4_OUTPUT"
else
    fail "regression#4: C-FFI protocol framing" "$R4_OUTPUT"
fi

# -------------- Regression #5: drift guard rejects injected violations ------
TMP_DRIFT_ROOT="$(mktemp -d -t echo_peer_drift.XXXXXX)"
cleanup_drift() {
    rm -rf "$TMP_DRIFT_ROOT"
    TMP_DRIFT_ROOT=""
}

DRIFT_SOURCE_DIR="$TMP_DRIFT_ROOT/echo_peer_src"
cp -R "$MCP_DIR/echo_peer_src" "$DRIFT_SOURCE_DIR"

R5_REASONS=()

run_drift_check() {
    local source_dir="$1"
    local peer_bin="$2"
    local protocol_test_bin="$3"
    ECHO_PEER_SOURCE_DIR="$source_dir" \
        ECHO_PEER_BIN="$peer_bin" \
        ECHO_PEER_PROTOCOL_TEST_BIN="$protocol_test_bin" \
        "$DRIFT_SH" >/dev/null 2>&1
}

set +e
run_drift_check "$DRIFT_SOURCE_DIR" "$PEER_BIN_DEFAULT" "$PROTOCOL_TEST_BIN"
R5_RC=$?
set -e
if (( R5_RC != 0 )); then
    R5_REASONS+=("canonical boundary check failed")
fi

expect_drift_failure() {
    local name="$1"
    local source_dir="$2"
    local peer_bin="$3"
    local protocol_test_bin="$4"
    set +e
    run_drift_check "$source_dir" "$peer_bin" "$protocol_test_bin"
    local result=$?
    set -e
    if (( result == 0 )); then
        R5_REASONS+=("$name was not rejected")
    fi
}

expect_drift_failure \
    "missing_echo_peer" \
    "$DRIFT_SOURCE_DIR" \
    "$TMP_DRIFT_ROOT/missing_echo_peer" \
    "$PROTOCOL_TEST_BIN"
expect_drift_failure \
    "missing_protocol_test" \
    "$DRIFT_SOURCE_DIR" \
    "$PEER_BIN_DEFAULT" \
    "$TMP_DRIFT_ROOT/missing_protocol_test"

expect_drift_rejection() {
    local name="$1"
    local file="$2"
    local injection="$3"
    local case_dir="$TMP_DRIFT_ROOT/$name"
    cp -R "$DRIFT_SOURCE_DIR" "$case_dir"
    printf '\n%s\n' "$injection" >> "$case_dir/$file"
    set +e
    run_drift_check "$case_dir" "$PEER_BIN_DEFAULT" "$PROTOCOL_TEST_BIN"
    local result=$?
    set -e
    if (( result == 0 )); then
        R5_REASONS+=("$name was not rejected")
    fi
}

expect_drift_rejection "v2tim" "echo_peer.cpp" \
    '// regression injection: V2TIMManager'
expect_drift_rejection "tox_manager" "echo_peer.cpp" \
    '// regression injection: ToxManager'
expect_drift_rejection "tox_api" "echo_peer.cpp" \
    '// regression injection: tox_friend_get_public_key('
expect_drift_rejection "alternate_include" "CMakeLists.txt" \
    'target_include_directories(echo_peer PRIVATE "${TIM2TOX_ROOT}/include")'
expect_drift_rejection "alternate_link" "CMakeLists.txt" \
    'target_link_libraries(echo_peer PRIVATE tim2tox)'

cleanup_drift

if (( ${#R5_REASONS[@]} == 0 )); then
    pass "regression#5: drift-guard canonical and isolated negative cases"
else
    fail "regression#5: drift-guard rejects injected direct-core and link/include violations" \
         "$(printf '%s; ' "${R5_REASONS[@]}")"
fi

# -------------- Summary -----------------------------------------------------
echo
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if (( FAIL_COUNT == 0 )); then
    printf '%sHelpers regression: PASS (%d/%d)%s\n' \
        "${C_GREEN}" "$PASS_COUNT" "$TOTAL" "${C_RST}"
    exit 0
else
    printf '%sHelpers regression: FAIL (%d PASS / %d FAIL of %d)%s\n' \
        "${C_RED}" "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL" "${C_RST}"
    printf 'failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
