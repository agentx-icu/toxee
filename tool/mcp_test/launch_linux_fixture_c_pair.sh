#!/usr/bin/env bash
# Launch A + B Linux Toxee instances for real-App UI automation, producing the
# pair.json contract the unified runner (fixture_c_unified_runner.dart)
# consumes. Linux sibling of launch_windows_fixture_c_pair.ps1 — same model:
#
#   * build the app ONCE (`flutter build linux --debug`, with the L3 + skill
#     dart-defines baked in); the Linux desktop CMake already bundles
#     libtim2tox_ffi.so into the runner bundle's lib/;
#   * launch BOTH instances' bundle/toxee directly from that single build. Each
#     launch gets a FIXED, distinct Dart VM-service port +
#     `disable-service-auth-codes` (deterministic ws://127.0.0.1:<port>/ws) and
#     per-instance TOXEE_APP_SUPPORT_DIR / TOXEE_SHARED_PREFS_PREFIX /
#     TOXEE_TCCF_GLOBAL_SUBDIR so the instances share no account/profile/prefs
#     state;
#   * TOXEE_FIXTURE_C_RESTORE=paired|paired_for_e2e restores the A/B fixture
#     trees (tox_profile.tox + JSON chat history — platform-portable files) via
#     restore_fixture_c_pair.sh into the per-instance support dirs BEFORE
#     launch, so friendship-dependent real-UI scenarios can run on Linux (the
#     drivers boot them via l3_boot_existing_account);
#   * TOXEE_PAIR_TCP_ONLY=1 mirrors the macOS launcher's same-host TCP-only
#     mode (A becomes a localhost TCP relay) for NGC/group traffic determinism;
#   * headless hosts (SSH, no $DISPLAY): a throwaway Xvfb display is started
#     automatically — real-UI driving is synthetic flutter_skill RPC, which
#     needs a live GTK surface but not a physical screen.
#
# The runtime root defaults under build/ (always locally writable, including on
# a share-shim checkout where tool/ is a read-only symlink into the Mac share).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_LINUX_RUNTIME_ROOT:-$REPO_ROOT/build/linux_runtime}"
PAIR_JSON="$RUNTIME_ROOT/pair.json"
PROBE_DART="tool/mcp_test/probe_vm_service.dart"
MCP_BINDING="${MCP_BINDING:-skill}"
L3_TEST="${TOXEE_L3_TEST:-true}"
VM_PORT_A="${TOXEE_LINUX_VM_PORT_A:-8201}"
VM_PORT_B="${TOXEE_LINUX_VM_PORT_B:-8202}"
URI_TIMEOUT="${TOXEE_LINUX_VM_URI_TIMEOUT_SECS:-90}"
RESTORE_MODE="${TOXEE_FIXTURE_C_RESTORE:-}"
SKIP_BUILD="${TOXEE_LINUX_SKIP_BUILD:-0}"
RESTORE_ROOT="$RUNTIME_ROOT/support"
RESTORE_REPORT="$RESTORE_ROOT/fixture_c_pair_restore.json"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

command -v flutter >/dev/null 2>&1 || die "flutter not found on PATH"
command -v dart >/dev/null 2>&1    || die "dart not found on PATH"
command -v jq >/dev/null 2>&1      || die "jq missing"
[[ "$VM_PORT_A" != "$VM_PORT_B" ]] || die "A/B VM-service ports must differ"

mkdir -p "$RUNTIME_ROOT"

# ----- Teardown strays + clean per-instance state -------------------------
for pf in "$RUNTIME_ROOT/A/toxee.pid" "$RUNTIME_ROOT/B/toxee.pid"; do
    if [[ -f "$pf" ]]; then
        kill "$(cat "$pf")" 2>/dev/null || true
    fi
done
pkill -f "$REPO_ROOT/build/linux/.*/debug/bundle/toxee" 2>/dev/null || true
sleep 1
rm -rf "$RUNTIME_ROOT/A" "$RUNTIME_ROOT/B" "$PAIR_JSON"

# Clear toxee's SHARED shared_preferences store so each launch starts from a
# clean account state: savedAccountToxIds + the toxee_a./toxee_b.-prefixed keys
# live in the real XDG data dir (shared_preferences_linux), NOT under the
# TOXEE_APP_SUPPORT_DIR override, so they otherwise survive a wipe and a
# relaunch finds a saved account whose profile is gone (sc_load_account_fail).
rm -f "$HOME/.local/share/toxee/shared_preferences.json" \
      "$HOME/.local/share/com.toxee.app/shared_preferences.json" 2>/dev/null || true

# ----- Fixed VM-service ports must be free ---------------------------------
for p in "$VM_PORT_A" "$VM_PORT_B"; do
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$p\$"; then
        die "VM-service port $p is already in use (the fixed-port probe must not attach to a foreign VM)"
    fi
done

# ----- Optional paired fixture restore -------------------------------------
if [[ "$RESTORE_MODE" == "paired" || "$RESTORE_MODE" == "paired_for_e2e" ]]; then
    info "Restoring '$RESTORE_MODE' fixture into $RESTORE_ROOT"
    TOXEE_FIXTURE_C_RESTORE_ROOT="$RESTORE_ROOT" \
    TOXEE_FIXTURE_C_RESTORE_REPORT="$RESTORE_REPORT" \
        bash "$MCP_DIR/restore_fixture_c_pair.sh"
elif [[ -n "$RESTORE_MODE" ]]; then
    die "unsupported TOXEE_FIXTURE_C_RESTORE=$RESTORE_MODE (paired|paired_for_e2e)"
fi

# ----- Headless fallback: private Xvfb display ------------------------------
XVFB_PID=""
if [[ -z "${DISPLAY:-}" ]]; then
    if command -v Xvfb >/dev/null 2>&1; then
        export DISPLAY=":99"
        if ! ls /tmp/.X11-unix/X99 >/dev/null 2>&1; then
            info "No \$DISPLAY - starting Xvfb $DISPLAY (1920x1080)"
            Xvfb "$DISPLAY" -screen 0 1920x1080x24 >/dev/null 2>&1 &
            XVFB_PID=$!
            echo "$XVFB_PID" > "$RUNTIME_ROOT/xvfb.pid"
            sleep 1
        fi
    else
        warn "No \$DISPLAY and no Xvfb - the GTK app will fail to open a surface"
    fi
    # Headless keyring: flutter_secure_storage (libsecret) retries forever on a
    # locked session keyring, wedging the first widget build (blank window,
    # zero elements). Empty-password unlocked keyring = standard headless-CI
    # recipe; gated to the no-DISPLAY branch to keep real desktops untouched.
    if command -v gnome-keyring-daemon >/dev/null 2>&1; then
        rm -f "$HOME/.local/share/keyrings/"*.keyring 2>/dev/null || true
        keyring_env="$(printf '' | gnome-keyring-daemon --replace --unlock --components=secrets 2>/dev/null || true)"
        [[ -n "$keyring_env" ]] && eval "$keyring_env" && export GNOME_KEYRING_CONTROL 2>/dev/null || true
        info "Headless keyring unlocked for libsecret"
    fi
fi

# ----- Bootstrap + build ONCE ----------------------------------------------
cd "$REPO_ROOT"
if [[ -L "$REPO_ROOT/third_party" || ! -w "$REPO_ROOT/third_party" ]]; then
    # Share-shim checkout: third_party symlinks into the (read-only) host
    # share — the full bootstrap may try to re-vendor/patch it. Validate only,
    # and FAIL LOUDLY so stale deps can't hide until build time.
    info "Shim checkout detected - bootstrap offline check only"
    dart tool/bootstrap_deps.dart --offline-check-only > "$RUNTIME_ROOT/bootstrap.log" 2>&1 \
        || die "bootstrap offline check failed; see $RUNTIME_ROOT/bootstrap.log"
else
    (dart run tool/bootstrap_deps.dart || true) > "$RUNTIME_ROOT/bootstrap.log" 2>&1
fi
if [[ "$SKIP_BUILD" != "1" ]]; then
    info "flutter build linux --debug (MCP_BINDING=$MCP_BINDING, TOXEE_L3_TEST=$L3_TEST)..."
    flutter build linux --debug \
        --dart-define=FLUTTER_BUILD_MODE=debug \
        --dart-define=MCP_BINDING="$MCP_BINDING" \
        --dart-define=TOXEE_L3_TEST="$L3_TEST" > "$RUNTIME_ROOT/build.log" 2>&1 \
        || die "flutter build linux failed; see $RUNTIME_ROOT/build.log"
fi
EXE="$(find "$REPO_ROOT/build/linux" -type f -path '*/debug/bundle/toxee' 2>/dev/null | head -1)"
[[ -n "$EXE" && -x "$EXE" ]] || die "built bundle toxee not found under build/linux (see $RUNTIME_ROOT/build.log)"
info "Built bundle runner: $EXE"

# Optional native IRC library: the Dart loader resolves libirc_client.so next
# to the executable (lib/util/irc_app_manager.dart). Built via
# `tool/ci/build_tim2tox.sh --target linux --with-irc`; without it the
# irc_join_channel_loopback_live JOIN cannot complete (the pure-Dart
# irc_join_channel_real_controls scenario is unaffected).
IRC_SO="$REPO_ROOT/build/native-artifacts/linux/libirc_client.so"
if [[ -f "$IRC_SO" ]]; then
    cp -f "$IRC_SO" "$(dirname "$EXE")/"
    info "Bundled libirc_client.so next to the runner"
else
    warn "libirc_client.so not found at $IRC_SO - live IRC JOIN unavailable"
fi

# ----- Same-host TCP-only mode (mirrors the macOS launcher) -----------------
A_TCP_ENV=(); B_TCP_ENV=()
if [[ "${TOXEE_PAIR_TCP_ONLY:-}" == "1" || "${TOXEE_PAIR_TCP_ONLY:-}" == "true" ]]; then
    A_TCP_ENV=(TOX_FORCE_TCP_ONLY=1 TOX_TCP_RELAY_PORT="${TOXEE_PAIR_TCP_RELAY_PORT:-3389}")
    B_TCP_ENV=(TOX_FORCE_TCP_ONLY=1)
    info "TCP-only same-host mode ON (A relay port ${TOXEE_PAIR_TCP_RELAY_PORT:-3389})"
fi

launch_instance() { # name port tcp_env...
    local name="$1" port="$2"; shift 2
    local inst="$RUNTIME_ROOT/$name"
    local support
    if [[ -n "$RESTORE_MODE" ]]; then
        support="$RESTORE_ROOT/$name"
    else
        support="$inst/app_support"
    fi
    local stdio="$inst/toxee_stdio.log"
    local name_lower
    name_lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    mkdir -p "$inst" "$support"
    : > "$stdio"

    env "$@" \
        TOXEE_APP_SUPPORT_DIR="$support" \
        TOXEE_SHARED_PREFS_PREFIX="toxee_${name_lower}." \
        TOXEE_TCCF_GLOBAL_SUBDIR="multi_instance/$name/tccfglobal" \
        TOXEE_LOG_DIR="$inst" \
        FLUTTER_ENGINE_SWITCHES=2 \
        FLUTTER_ENGINE_SWITCH_1="vm-service-port=$port" \
        FLUTTER_ENGINE_SWITCH_2="disable-service-auth-codes" \
        nohup "$EXE" >> "$stdio" 2>&1 < /dev/null &
    local pid=$!
    echo "$pid" > "$inst/toxee.pid"

    # With disable-service-auth-codes the ws URI is deterministic; probe it,
    # falling back to grepping stdio in case a future engine keeps the token.
    local ws="ws://127.0.0.1:$port/ws"
    local elapsed=0 ok=0
    while [[ "$elapsed" -lt "$URI_TIMEOUT" ]]; do
        kill -0 "$pid" 2>/dev/null || die "$name toxee exited before its VM service came up; see $stdio"
        if dart run "$PROBE_DART" "$ws" >/dev/null 2>&1; then ok=1; break; fi
        local seen
        seen="$(grep -oE 'http://127\.0\.0\.1:[0-9]+(/[A-Za-z0-9_=-]+)?/?' "$stdio" 2>/dev/null | head -1 || true)"
        if [[ -n "$seen" ]]; then
            seen="${seen%/}"
            local alt="${seen/http:/ws:}/ws"
            if dart run "$PROBE_DART" "$alt" >/dev/null 2>&1; then ws="$alt"; ok=1; break; fi
        fi
        sleep 1; elapsed=$((elapsed + 1))
    done
    [[ "$ok" == "1" ]] || die "$name VM service not reachable within ${URI_TIMEOUT}s on port $port; see $stdio"

    local vm_uri="${ws/ws:/http:}"; vm_uri="${vm_uri%/ws}"
    local log_exists=false
    [[ -f "$support/flutter_client.log" ]] && log_exists=true
    jq -n \
        --arg name "$name" --argjson pid "$pid" --arg inst "$inst" \
        --arg stdio "$stdio" --arg vm "$vm_uri" --arg ws "$ws" \
        --argjson logx "$log_exists" \
        '{format_version: 1, instance_name: $name, pid: $pid,
          home_override_dir: $inst, stdio_log: $stdio,
          vm_uri: $vm, ws_uri: $ws, app_support_log_exists: $logx}' \
        > "$inst/instance.json"
    info "$name pid=$pid ws_uri=$ws"
}

teardown_partial() {
    warn "launch failed - tearing down any partial pair"
    bash "$MCP_DIR/stop_linux_fixture_c_pair.sh" >/dev/null 2>&1 || true
}
trap teardown_partial ERR

launch_instance A "$VM_PORT_A" ${A_TCP_ENV[@]+"${A_TCP_ENV[@]}"}
launch_instance B "$VM_PORT_B" ${B_TCP_ENV[@]+"${B_TCP_ENV[@]}"}

restored_json=null
if [[ -n "$RESTORE_MODE" && -f "$RESTORE_REPORT" ]]; then
    restored_json="$(cat "$RESTORE_REPORT")"
fi
jq -n \
    --slurpfile a "$RUNTIME_ROOT/A/instance.json" \
    --slurpfile b "$RUNTIME_ROOT/B/instance.json" \
    --arg mode "$RESTORE_MODE" --arg report "$RESTORE_REPORT" \
    --argjson restored "$restored_json" \
    '{format_version: 1, platform: "linux",
      instances: {A: $a[0], B: $b[0]},
      fixture_restore: {
        mode: (if $mode == "" then null else $mode end),
        report: (if $restored == null then null else $report end),
        restored: $restored},
      checks: {
        distinct_pids: ($a[0].pid != $b[0].pid),
        distinct_ws_uris: ($a[0].ws_uri != $b[0].ws_uri),
        distinct_vm_ports: ($a[0].vm_uri != $b[0].vm_uri)}}' \
    > "$PAIR_JSON"
trap - ERR

echo ""
info "OK: launched Linux Fixture C pair"
info "pair json: $PAIR_JSON"
info "A ws_uri: $(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
info "B ws_uri: $(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"
