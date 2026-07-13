#!/bin/bash

# Android mobile/tablet package/deploy/run script for toxee.
# Style aligned with run_toxee.sh.

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLUTTER_APP_DIR="$SCRIPT_DIR"
BUILD_DIR="$FLUTTER_APP_DIR/build/android_mobile"
FLUTTER_BUILD_LOG="$BUILD_DIR/flutter_android_build.log"
DEPLOY_LOG="$BUILD_DIR/flutter_android_deploy.log"
APP_PACKAGE_ID="com.toxee.app"
JNI_LIBS_DIR="$FLUTTER_APP_DIR/android/app/src/main/jniLibs"

ACTION="run"                # package | deploy | run | l3
MODE="debug"                # debug | profile | release
DEVICE_TYPE="phone"         # phone | tablet | any
DEVICE_ID=""
FFI_LIB_DIR="${TIM2TOX_ANDROID_LIB_DIR:-}"
LIST_DEVICES="false"
SKIP_PUB_GET="false"
RUN_L3="false"              # with --action l3: run the suite then tear down
MCP_BINDING="${MCP_BINDING:-skill}"
TOXEE_L3_TEST="${TOXEE_L3_TEST:-true}"
VM_URI_FILE="$FLUTTER_APP_DIR/build/vm_service_uri.txt"
L3_STDIO_LOG="$BUILD_DIR/android_l3_stdio.log"
L3_PID_FILE="$BUILD_DIR/android_l3_flutter.pid"
VM_URI_TIMEOUT_SECS="${TOXEE_ANDROID_VM_URI_TIMEOUT_SECS:-300}"
declare -a L3_EXTRA_ARGS=()

ANDROID_ABIS=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")

mkdir -p "$BUILD_DIR"

# Bootstrap dependencies so pubspec_overrides and third_party are ready
(cd "$FLUTTER_APP_DIR" && dart run tool/bootstrap_deps.dart) >> "$BUILD_DIR/bootstrap.log" 2>&1 || true

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# UI helpers
# ============================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Android package/deploy/run script for phone/tablet.

Options:
  --action <package|deploy|run|l3> Action to execute (default: run)
                                  l3 = build with the L3 test surface
                                  (--dart-define=TOXEE_L3_TEST=true), launch via
                                  `flutter run --machine` (which auto-forwards the
                                  device VM service to the host), and write the
                                  host ws URI to build/vm_service_uri.txt for
                                  tool/mcp_test/run_l3_scenarios.dart to attach.
  --mode <debug|profile|release>  Flutter build mode (default: debug)
  --device-type <phone|tablet|any>
                                  Target Android device type (default: phone)
  --device-id <id>                Explicit adb device id (overrides --device-type)
  --ffi-lib-dir <dir>             Directory containing per-ABI tim2tox libs:
                                  <dir>/<abi>/libtim2tox_ffi.so
  --list-devices                  List connected Android devices and exit
  --skip-pub-get                  Skip flutter pub get step
  --run-l3                        (with --action l3) run the hermetic L3 partition
                                  (--class=l3-gate) then tear the app down
  --                              everything after is forwarded to
                                  run_l3_scenarios.dart (with --run-l3)
  --help                          Show this help

Examples:
  $(basename "$0") --action package --mode release
  $(basename "$0") --action deploy --device-type tablet
  $(basename "$0") --action run --device-id emulator-5554
  $(basename "$0") --action l3 --run-l3
EOF
}

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ============================================================
# Argument parsing
# ============================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      ACTION="${2:-}"; shift 2;;
    --mode)
      MODE="${2:-}"; shift 2;;
    --device-type)
      DEVICE_TYPE="${2:-}"; shift 2;;
    --device-id)
      DEVICE_ID="${2:-}"; shift 2;;
    --ffi-lib-dir)
      FFI_LIB_DIR="${2:-}"; shift 2;;
    --list-devices)
      LIST_DEVICES="true"; shift;;
    --skip-pub-get)
      SKIP_PUB_GET="true"; shift;;
    --run-l3)
      RUN_L3="true"; shift;;
    --)
      shift; L3_EXTRA_ARGS=("$@"); break;;
    --help|-h)
      usage; exit 0;;
    *)
      error "Unknown option: $1"
      usage
      exit 1;;
  esac
done

case "$ACTION" in
  package|deploy|run|l3) ;;
  *)
    error "Invalid --action: $ACTION"
    usage
    exit 1;;
esac

case "$MODE" in
  debug|profile|release) ;;
  *)
    error "Invalid --mode: $MODE"
    usage
    exit 1;;
esac

case "$DEVICE_TYPE" in
  phone|tablet|any) ;;
  *)
    error "Invalid --device-type: $DEVICE_TYPE"
    usage
    exit 1;;
esac

# ============================================================
# Preflight
# ============================================================

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Missing command: $cmd"
    exit 1
  fi
}

preflight_checks() {
  require_cmd flutter
  require_cmd adb
  if [[ ! -f "$FLUTTER_APP_DIR/pubspec.yaml" ]]; then
    error "Flutter app not found: $FLUTTER_APP_DIR"
    exit 1
  fi
}

prepare_flutter_deps() {
  if [[ "$SKIP_PUB_GET" == "true" ]]; then
    warn "Skipping flutter pub get (--skip-pub-get)"
    return
  fi
  if [[ ! -f "$FLUTTER_APP_DIR/pubspec.lock" ]] || \
     [[ "$FLUTTER_APP_DIR/pubspec.yaml" -nt "$FLUTTER_APP_DIR/pubspec.lock" ]] || \
     { [[ -f "$FLUTTER_APP_DIR/pubspec_overrides.yaml" ]] && \
       [[ "$FLUTTER_APP_DIR/pubspec_overrides.yaml" -nt "$FLUTTER_APP_DIR/pubspec.lock" ]]; }; then
    info "Running flutter pub get..."
    (cd "$FLUTTER_APP_DIR" && flutter pub get) >>"$FLUTTER_BUILD_LOG" 2>&1
  fi
}

# ============================================================
# Device selection
# ============================================================

get_connected_android_devices() {
  adb devices | awk 'NR>1 && $2=="device" {print $1}'
}

classify_android_device() {
  local device_id="$1"
  local size density min_px smallest_dp

  size="$(adb -s "$device_id" shell wm size 2>/dev/null | tr -d '\r' | awk -F': ' '/Physical size/ {print $2; exit}')"
  density="$(adb -s "$device_id" shell wm density 2>/dev/null | tr -d '\r' | awk -F': ' '/Physical density/ {print $2; exit}')"

  if [[ -z "$size" || -z "$density" ]]; then
    echo "unknown"
    return
  fi
  if ! [[ "$density" =~ ^[0-9]+$ ]]; then
    echo "unknown"
    return
  fi

  min_px="$(awk -F'x' '{if ($1 < $2) print $1; else print $2}' <<<"$size")"
  if ! [[ "$min_px" =~ ^[0-9]+$ ]]; then
    echo "unknown"
    return
  fi

  smallest_dp="$(awk -v px="$min_px" -v den="$density" 'BEGIN {printf "%.0f", (px*160)/den}')"
  if [[ "$smallest_dp" -ge 600 ]]; then
    echo "tablet"
  else
    echo "phone"
  fi
}

list_android_devices() {
  local d device_class count="0"
  if [[ -z "$(get_connected_android_devices)" ]]; then
    warn "No connected Android devices."
    return
  fi
  echo -e "${CYAN}Connected Android devices:${NC}"
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    count=$((count + 1))
    device_class="$(classify_android_device "$d")"
    echo "  $d  [$device_class]"
  done < <(get_connected_android_devices)
  if [[ "$count" -eq 0 ]]; then
    warn "No connected Android devices."
  fi
}

SELECTED_DEVICE_ID=""
SELECTED_DEVICE_CLASS=""

select_android_device() {
  local d c has_any="false"
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    has_any="true"
    break
  done < <(get_connected_android_devices)
  if [[ "$has_any" != "true" ]]; then
    error "No connected Android devices found."
    exit 1
  fi

  if [[ -n "$DEVICE_ID" ]]; then
    while IFS= read -r d; do
      [[ -z "$d" ]] && continue
      if [[ "$d" == "$DEVICE_ID" ]]; then
        SELECTED_DEVICE_ID="$d"
        SELECTED_DEVICE_CLASS="$(classify_android_device "$d")"
        return
      fi
    done < <(get_connected_android_devices)
    error "Requested device id not found: $DEVICE_ID"
    exit 1
  fi

  if [[ "$DEVICE_TYPE" == "any" ]]; then
    while IFS= read -r d; do
      [[ -z "$d" ]] && continue
      SELECTED_DEVICE_ID="$d"
      SELECTED_DEVICE_CLASS="$(classify_android_device "$SELECTED_DEVICE_ID")"
      return
    done < <(get_connected_android_devices)
  fi

  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    c="$(classify_android_device "$d")"
    if [[ "$c" == "$DEVICE_TYPE" ]]; then
      SELECTED_DEVICE_ID="$d"
      SELECTED_DEVICE_CLASS="$c"
      return
    fi
  done < <(get_connected_android_devices)

  error "No Android device matched --device-type=$DEVICE_TYPE"
  list_android_devices
  exit 1
}

# ============================================================
# FFI library preparation
# ============================================================

prepare_android_ffi_libs() {
  mkdir -p "$JNI_LIBS_DIR"

  if [[ -n "$FFI_LIB_DIR" ]]; then
    if [[ ! -d "$FFI_LIB_DIR" ]]; then
      error "--ffi-lib-dir is not a directory: $FFI_LIB_DIR"
      exit 1
    fi
    info "Syncing tim2tox Android FFI libs from: $FFI_LIB_DIR"
    local abi src dst copied="0"
    for abi in "${ANDROID_ABIS[@]}"; do
      src="$FFI_LIB_DIR/$abi/libtim2tox_ffi.so"
      dst="$JNI_LIBS_DIR/$abi/libtim2tox_ffi.so"
      if [[ -f "$src" ]]; then
        mkdir -p "$JNI_LIBS_DIR/$abi"
        cp "$src" "$dst"
        copied="1"
      fi
    done
    if [[ "$copied" == "0" ]]; then
      error "No libtim2tox_ffi.so found in $FFI_LIB_DIR/<abi>/"
      exit 1
    fi
  fi

  if ! find "$JNI_LIBS_DIR" -type f -name "libtim2tox_ffi.so" | grep -q .; then
    error "Missing tim2tox Android FFI library."
    echo "Expected at least one of:"
    for abi in "${ANDROID_ABIS[@]}"; do
      echo "  $JNI_LIBS_DIR/$abi/libtim2tox_ffi.so"
    done
    echo ""
    echo "Provide --ffi-lib-dir <dir> where <dir>/<abi>/libtim2tox_ffi.so exists."
    exit 1
  fi
}

# ============================================================
# Build / deploy / run
# ============================================================

build_android_apk() {
  : >"$FLUTTER_BUILD_LOG"
  info "Building Android APK ($MODE)..."
  (cd "$FLUTTER_APP_DIR" && flutter build apk --"$MODE" --dart-define=FLUTTER_BUILD_MODE="$MODE") >>"$FLUTTER_BUILD_LOG" 2>&1
  info "Build completed."
}

apk_output_path() {
  case "$MODE" in
    debug) echo "$FLUTTER_APP_DIR/build/app/outputs/flutter-apk/app-debug.apk" ;;
    profile) echo "$FLUTTER_APP_DIR/build/app/outputs/flutter-apk/app-profile.apk" ;;
    release) echo "$FLUTTER_APP_DIR/build/app/outputs/flutter-apk/app-release.apk" ;;
  esac
}

deploy_android_apk() {
  local apk_path
  apk_path="$(apk_output_path)"
  if [[ ! -f "$apk_path" ]]; then
    warn "APK not found, building first: $apk_path"
    build_android_apk
  fi

  select_android_device
  : >"$DEPLOY_LOG"
  info "Deploying APK to $SELECTED_DEVICE_ID ($SELECTED_DEVICE_CLASS)..."
  adb -s "$SELECTED_DEVICE_ID" install -r "$apk_path" >>"$DEPLOY_LOG" 2>&1
  info "Deploy completed."
}

launch_android_app() {
  select_android_device
  info "Launching $APP_PACKAGE_ID on $SELECTED_DEVICE_ID..."
  adb -s "$SELECTED_DEVICE_ID" shell am force-stop "$APP_PACKAGE_ID" >/dev/null 2>&1 || true
  adb -s "$SELECTED_DEVICE_ID" shell monkey -p "$APP_PACKAGE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1

  local pid
  pid="$(adb -s "$SELECTED_DEVICE_ID" shell pidof -s "$APP_PACKAGE_ID" 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "$pid" ]]; then
    echo ""
    echo -e "${GREEN}Tailing logcat for PID $pid (Ctrl+C to stop)...${NC}"
    adb -s "$SELECTED_DEVICE_ID" logcat --pid="$pid"
  else
    warn "Could not get process PID; falling back to package-name grep."
    adb -s "$SELECTED_DEVICE_ID" logcat | grep --line-buffered "$APP_PACKAGE_ID"
  fi
}

# ============================================================
# L3 launch (build with the test surface + capture the host VM URI)
# ============================================================

run_android_l3() {
  case "$MCP_BINDING" in
    skill|marionette|stock) ;;
    *) error "Invalid MCP_BINDING='$MCP_BINDING'. Allowed: skill|marionette|stock."; exit 1;;
  esac
  if [[ "$MODE" != "debug" ]]; then
    error "L3 needs a debug build: kDebugMode tree-shakes the L3 tool surface out of"
    error "profile/release (lib/ui/testing/l3_debug_tools.dart). Use --mode debug."
    exit 1
  fi

  select_android_device
  mkdir -p "$(dirname "$VM_URI_FILE")"
  : >"$L3_STDIO_LOG"
  rm -f "$VM_URI_FILE" "$L3_PID_FILE"

  info "Launching $APP_PACKAGE_ID on $SELECTED_DEVICE_ID via flutter run --machine"
  info "  ($MODE, MCP_BINDING=$MCP_BINDING, TOXEE_L3_TEST=$TOXEE_L3_TEST)..."
  # `flutter run --machine` builds + installs + adb-forwards the device VM
  # service to the host and emits the host-side ws URI in its JSON event
  # stream (app.debugPort -> params.wsUri). nohup keeps the app alive after
  # this script returns (launch-only mode).
  nohup flutter run -d "$SELECTED_DEVICE_ID" --"$MODE" --machine \
    --dart-define=FLUTTER_BUILD_MODE="$MODE" \
    --dart-define=MCP_BINDING="$MCP_BINDING" \
    --dart-define=TOXEE_L3_TEST="$TOXEE_L3_TEST" \
    >>"$L3_STDIO_LOG" 2>&1 </dev/null &
  local flutter_pid=$!
  echo "$flutter_pid" >"$L3_PID_FILE"
  disown "$flutter_pid" 2>/dev/null || true

  local ws_uri="" elapsed=0
  while [[ "$elapsed" -lt "$VM_URI_TIMEOUT_SECS" ]]; do
    if ! kill -0 "$flutter_pid" 2>/dev/null; then
      error "flutter run exited before the VM service URI appeared; see $L3_STDIO_LOG"
      exit 1
    fi
    # app.debugPort emits {"wsUri":"ws://127.0.0.1:<host-port>/<token>/ws"}.
    ws_uri="$(grep -oE '"wsUri":"ws://[^"]+"' "$L3_STDIO_LOG" 2>/dev/null \
      | head -1 | sed -E 's/.*"wsUri":"([^"]*)".*/\1/' || true)"
    [[ -n "$ws_uri" ]] && break
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if [[ -z "$ws_uri" ]]; then
    error "Timed out after ${VM_URI_TIMEOUT_SECS}s waiting for the VM service URI; see $L3_STDIO_LOG"
    kill "$flutter_pid" 2>/dev/null || true
    exit 1
  fi

  printf '%s\n' "$ws_uri" >"$VM_URI_FILE"
  echo ""
  info "WS URI: $ws_uri  ->  $VM_URI_FILE"
  info "App pid (flutter run): $flutter_pid  ->  $L3_PID_FILE"

  if [[ "$RUN_L3" == "true" ]]; then
    echo ""
    # Fresh-state devices/emulators have no seeded account at all, so the
    # session preflight (L3-session-settings asserts the seeded echo
    # conversation) fails before any gate runs. The register driver is
    # idempotent — it skips registration when the session is already ready and
    # only tops up the echo seed when missing. (Same block as run_toxee_linux.sh.)
    info "Ensuring L3 seed account + echo conversation (idempotent)..."
    if ! (cd "$FLUTTER_APP_DIR" && dart run tool/mcp_test/drive_l3_register.dart \
        "$ws_uri" echo_live_test --seed-echo); then
      warn "L3 register/seed step failed — the session preflight will likely fail."
    fi
    info "Running hermetic L3 partition (--class=l3-gate)..."
    set +e
    # --skip=L3-self-id: bound to the on-disk echo_seeded fixture account's
    # exact toxId; a register-seeded fresh device can never satisfy it (see
    # drive_l3_register.dart header). Explicit SKIP keeps the report honest.
    (cd "$FLUTTER_APP_DIR" && dart run tool/mcp_test/run_l3_scenarios.dart \
        "$ws_uri" --class=l3-gate --skip=L3-self-id \
        "${L3_EXTRA_ARGS[@]+"${L3_EXTRA_ARGS[@]}"}")
    local l3_rc=$?
    set -e
    info "Tearing down Android app (pid $flutter_pid)..."
    kill "$flutter_pid" 2>/dev/null || true
    # flutter run's SIGTERM doesn't guarantee the device app stops before the host
    # process exits; force-stop it so a repeat run doesn't collide with stale state.
    adb -s "$SELECTED_DEVICE_ID" shell am force-stop "$APP_PACKAGE_ID" >/dev/null 2>&1 || true
    exit "$l3_rc"
  fi

  echo ""
  info "App left running. Attach the L3 suite with:"
  echo "    dart run tool/mcp_test/run_l3_scenarios.dart \"\$(cat $VM_URI_FILE)\" --class=l3-gate"
  info "Stop it with:  kill \"\$(cat $L3_PID_FILE)\""
}

# ============================================================
# Main
# ============================================================

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Toxee — Android Mobile/Tablet       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"

preflight_checks

if [[ "$LIST_DEVICES" == "true" ]]; then
  list_android_devices
  exit 0
fi

prepare_flutter_deps
prepare_android_ffi_libs

case "$ACTION" in
  package)
    build_android_apk
    info "APK: $(apk_output_path)"
    ;;
  deploy)
    deploy_android_apk
    ;;
  run)
    build_android_apk
    deploy_android_apk
    launch_android_app
    ;;
  l3)
    run_android_l3
    ;;
esac
