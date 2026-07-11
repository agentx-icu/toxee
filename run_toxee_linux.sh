#!/usr/bin/env bash
#
# Build + launch ONE debug Toxee Linux instance with the L3 test surface
# compiled in (`--dart-define=TOXEE_L3_TEST=true`) and surface its Dart VM
# service URI for the L3 MCP harness (tool/mcp_test/run_l3_scenarios.dart).
#
# Sibling of run_toxee.sh (macOS) and run_toxee_ios.sh (iOS Simulator). The L3
# runner is platform-agnostic — it attaches to ANY reachable VM service whose
# app was built with the L3 dart-define — so the ONLY thing missing for Linux
# was a launcher that (1) builds with the define and (2) writes the ws URI to
# the known location (build/vm_service_uri.txt). This is that launcher.
#
# Unlike macOS (run_toxee.sh hand-bundles the FFI dylib), the Linux desktop
# CMake (linux/CMakeLists.txt) already installs libtim2tox_ffi.so + libsodium
# into the runner bundle's lib/ dir, so a plain `flutter run -d linux` produces
# a working, FFI-loaded binary. We use `flutter run` (not a direct-binary
# launch) because it reliably announces the VM service URI on stdout regardless
# of GTK/console quirks. For L3 (short, deterministic, single-process runs) the
# flutter daemon's resident connection is not a problem.
#
# Usage:
#   ./run_toxee_linux.sh [--mode debug] [--skip-native] [--skip-pub-get] \
#                        [--run-l3 [-- <extra run_l3_scenarios.dart args>]]
#
#   (no --run-l3)  Build + launch + write build/vm_service_uri.txt, then return
#                  while the app keeps running. Attach the suite yourself:
#                      dart run tool/mcp_test/run_l3_scenarios.dart \
#                          "$(cat build/vm_service_uri.txt)" --class=l3-gate
#                  Stop the app:  kill "$(cat build/toxee_linux_flutter.pid)"
#
#   --run-l3       After the URI is captured, run the hermetic L3 partition
#                  (--class=l3-gate) against it and tear the app down. Anything
#                  after a literal `--` is forwarded to run_l3_scenarios.dart.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_APP_DIR="$SCRIPT_DIR"
BUILD_DIR="$FLUTTER_APP_DIR/build"
STDIO_LOG="$BUILD_DIR/toxee_linux_stdio.log"
VM_URI_FILE="$BUILD_DIR/vm_service_uri.txt"
PID_FILE="$BUILD_DIR/toxee_linux_flutter.pid"

MODE="debug"
MCP_BINDING="${MCP_BINDING:-skill}"
TOXEE_L3_TEST="${TOXEE_L3_TEST:-true}"
SKIP_NATIVE="false"
SKIP_PUB_GET="false"
RUN_L3="false"
VM_URI_TIMEOUT_SECS="${TOXEE_LINUX_VM_URI_TIMEOUT_SECS:-300}"
declare -a L3_EXTRA_ARGS=()

# Colors
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
  sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ----- CLI flags -----------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)          MODE="${2:-}"; shift 2 ;;
    --skip-native)   SKIP_NATIVE="true"; shift ;;
    --skip-pub-get)  SKIP_PUB_GET="true"; shift ;;
    --run-l3)        RUN_L3="true"; shift ;;
    --)              shift; L3_EXTRA_ARGS=("$@"); break ;;
    --help|-h)       usage; exit 0 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

case "$MODE" in debug) ;; *)
  error "L3 needs a debug build: kDebugMode tree-shakes the L3 tool surface out of"
  error "profile/release (lib/ui/testing/l3_debug_tools.dart). --mode must be debug."; exit 1 ;;
esac
case "$MCP_BINDING" in skill|marionette|stock) ;; *)
  error "Invalid MCP_BINDING='$MCP_BINDING'. Allowed: skill|marionette|stock."; exit 1 ;;
esac

mkdir -p "$BUILD_DIR"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { error "Missing command: $1"; exit 1; }; }
require_cmd flutter
require_cmd dart
[[ -f "$FLUTTER_APP_DIR/pubspec.yaml" ]] || { error "Flutter app not found: $FLUTTER_APP_DIR"; exit 1; }

# ----- Bootstrap + native FFI ---------------------------------------
if [[ -L "$FLUTTER_APP_DIR/third_party" || ! -w "$FLUTTER_APP_DIR/third_party" ]]; then
  # Share-shim checkout (third_party symlinks into a read-only host share):
  # the full bootstrap may try to re-vendor/patch it. Validate only, loudly.
  info "Shim checkout detected - bootstrap offline check only"
  (cd "$FLUTTER_APP_DIR" && dart tool/bootstrap_deps.dart --offline-check-only) \
    >> "$BUILD_DIR/bootstrap.log" 2>&1 \
    || { error "bootstrap offline check failed; see $BUILD_DIR/bootstrap.log"; exit 1; }
else
  (cd "$FLUTTER_APP_DIR" && dart run tool/bootstrap_deps.dart) >> "$BUILD_DIR/bootstrap.log" 2>&1 || true
fi

if [[ "$SKIP_NATIVE" != "true" ]]; then
  info "Building tim2tox Linux FFI (tool/ci/build_tim2tox.sh --target linux)..."
  if [[ -x "$FLUTTER_APP_DIR/tool/ci/build_tim2tox.sh" ]]; then
    (cd "$FLUTTER_APP_DIR" && bash tool/ci/build_tim2tox.sh --target linux) \
      >> "$BUILD_DIR/native_build_linux.log" 2>&1 || {
        warn "Native FFI build reported a failure; continuing — flutter build will"
        warn "fail explicitly if libtim2tox_ffi.so is genuinely missing."
        warn "See $BUILD_DIR/native_build_linux.log"
      }
  else
    warn "tool/ci/build_tim2tox.sh missing; assuming the .so is already built."
  fi
fi

if [[ "$SKIP_PUB_GET" != "true" ]]; then
  if [[ ! -f "$FLUTTER_APP_DIR/pubspec.lock" ]] \
     || [[ "$FLUTTER_APP_DIR/pubspec.yaml" -nt "$FLUTTER_APP_DIR/pubspec.lock" ]] \
     || { [[ -f "$FLUTTER_APP_DIR/pubspec_overrides.yaml" ]] \
          && [[ "$FLUTTER_APP_DIR/pubspec_overrides.yaml" -nt "$FLUTTER_APP_DIR/pubspec.lock" ]]; }; then
    info "Running flutter pub get..."
    (cd "$FLUTTER_APP_DIR" && flutter pub get) >> "$BUILD_DIR/flutter_linux_build.log" 2>&1
  fi
fi

# ----- Headless fallback: private Xvfb display ------------------------
# Mirrors launch_linux_fixture_c_pair.sh: on an SSH/CI host with no $DISPLAY
# the GTK app cannot open a surface; L3 driving is synthetic VM-service input,
# which needs a live surface but not a physical screen.
if [[ -z "${DISPLAY:-}" ]]; then
  if command -v Xvfb >/dev/null 2>&1; then
    export DISPLAY=":99"
    if ! ls /tmp/.X11-unix/X99 >/dev/null 2>&1; then
      info "No \$DISPLAY - starting Xvfb $DISPLAY (1920x1080)"
      Xvfb "$DISPLAY" -screen 0 1920x1080x24 >/dev/null 2>&1 &
      echo $! > "$BUILD_DIR/xvfb.pid"
      sleep 1
    fi
  else
    warn "No \$DISPLAY and no Xvfb - flutter run -d linux will fail to open a surface."
  fi
fi

# ----- Launch via `flutter run -d linux` -----------------------------
: > "$STDIO_LOG"
rm -f "$VM_URI_FILE" "$PID_FILE"

FLUTTER_PID=""
cleanup_on_fail() {
  if [[ -n "$FLUTTER_PID" ]] && kill -0 "$FLUTTER_PID" 2>/dev/null; then
    kill "$FLUTTER_PID" 2>/dev/null || true
  fi
}
trap cleanup_on_fail EXIT

info "Launching Linux app (flutter run -d linux, $MODE, MCP_BINDING=$MCP_BINDING, TOXEE_L3_TEST=$TOXEE_L3_TEST)..."
# nohup keeps the app alive after this script returns (no --run-l3), mirroring
# the iOS launcher. Output is teed to STDIO_LOG for URI extraction.
nohup flutter run -d linux --"$MODE" \
  --dart-define=FLUTTER_BUILD_MODE="$MODE" \
  --dart-define=MCP_BINDING="$MCP_BINDING" \
  --dart-define=TOXEE_L3_TEST="$TOXEE_L3_TEST" \
  >> "$STDIO_LOG" 2>&1 < /dev/null &
FLUTTER_PID=$!
echo "$FLUTTER_PID" > "$PID_FILE"
disown "$FLUTTER_PID" 2>/dev/null || true

# ----- Capture the Dart VM service URI -------------------------------
vm_uri=""
elapsed=0
while [[ "$elapsed" -lt "$VM_URI_TIMEOUT_SECS" ]]; do
  if ! kill -0 "$FLUTTER_PID" 2>/dev/null; then
    error "flutter run exited before the VM service URI appeared; see $STDIO_LOG"
    exit 1
  fi
  vm_uri="$(grep -oE 'http://127\.0\.0\.1:[0-9]+(/[A-Za-z0-9_=-]+)?/?' "$STDIO_LOG" 2>/dev/null | head -1 || true)"
  [[ -n "$vm_uri" ]] && break
  sleep 1
  elapsed=$((elapsed + 1))
done
if [[ -z "$vm_uri" ]]; then
  error "Timed out after ${VM_URI_TIMEOUT_SECS}s waiting for the VM service URI; see $STDIO_LOG"
  exit 1
fi

vm_uri="${vm_uri%/}"
ws_uri="${vm_uri/http:/ws:}/ws"
printf '%s\n' "$ws_uri" > "$VM_URI_FILE"

echo ""
info "VM Service: $vm_uri/"
info "WS URI:     $ws_uri  ->  $VM_URI_FILE"
info "App pid (flutter run): $FLUTTER_PID  ->  $PID_FILE"

# ----- Optionally run the hermetic L3 partition + tear down ----------
if [[ "$RUN_L3" == "true" ]]; then
  echo ""
  info "Running hermetic L3 partition (--class=l3-gate)..."
  set +e
  (cd "$FLUTTER_APP_DIR" && dart run tool/mcp_test/run_l3_scenarios.dart \
      "$ws_uri" --class=l3-gate "${L3_EXTRA_ARGS[@]+"${L3_EXTRA_ARGS[@]}"}")
  l3_rc=$?
  set -e
  info "Tearing down Linux app (pid $FLUTTER_PID)..."
  kill "$FLUTTER_PID" 2>/dev/null || true
  FLUTTER_PID=""   # already handled; skip the EXIT-trap kill
  trap - EXIT
  exit "$l3_rc"
fi

# Launch-only: leave the app running for the harness to attach to.
FLUTTER_PID=""   # don't let the EXIT trap kill the app we intentionally left up
trap - EXIT
echo ""
info "App left running. Attach the L3 suite with:"
echo "    dart run tool/mcp_test/run_l3_scenarios.dart \"\$(cat $VM_URI_FILE)\" --class=l3-gate"
info "Stop it with:  kill \"\$(cat $PID_FILE)\""
