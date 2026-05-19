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

ACTION="run"                # package | deploy | run
MODE="debug"                # debug | profile | release
DEVICE_TYPE="phone"         # phone | tablet | any
DEVICE_ID=""
FFI_LIB_DIR="${TIM2TOX_ANDROID_LIB_DIR:-}"
LIST_DEVICES="false"
SKIP_PUB_GET="false"

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
  --action <package|deploy|run>   Action to execute (default: run)
  --mode <debug|profile|release>  Flutter build mode (default: debug)
  --device-type <phone|tablet|any>
                                  Target Android device type (default: phone)
  --device-id <id>                Explicit adb device id (overrides --device-type)
  --ffi-lib-dir <dir>             Directory containing per-ABI tim2tox libs:
                                  <dir>/<abi>/libtim2tox_ffi.so
  --list-devices                  List connected Android devices and exit
  --skip-pub-get                  Skip flutter pub get step
  --help                          Show this help

Examples:
  $(basename "$0") --action package --mode release
  $(basename "$0") --action deploy --device-type tablet
  $(basename "$0") --action run --device-id emulator-5554
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
    --help|-h)
      usage; exit 0;;
    *)
      error "Unknown option: $1"
      usage
      exit 1;;
  esac
done

case "$ACTION" in
  package|deploy|run) ;;
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
esac
