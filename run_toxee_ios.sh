#!/bin/bash

# iOS (simulator) mobile/tablet package/deploy/run script for toxee.
# Style aligned with run_toxee.sh.

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_APP_DIR="$SCRIPT_DIR"
BUILD_DIR="$FLUTTER_APP_DIR/build/ios_mobile"
FLUTTER_BUILD_LOG="$BUILD_DIR/flutter_ios_build.log"
DEPLOY_LOG="$BUILD_DIR/flutter_ios_deploy.log"
IOS_PBXPROJ="$FLUTTER_APP_DIR/ios/Runner.xcodeproj/project.pbxproj"

ACTION="run"                  # package | deploy | run
MODE="debug"                  # debug | profile | release
DEVICE_TYPE="phone"           # phone | tablet | any
SIMULATOR_ID=""
FFI_FRAMEWORK_PATH="${TIM2TOX_IOS_FRAMEWORK_PATH:-}"   # .../tim2tox_ffi.framework
FFI_DYLIB_PATH="${TIM2TOX_IOS_DYLIB_PATH:-}"           # .../libtim2tox_ffi.dylib
LIST_DEVICES="false"
SKIP_PUB_GET="false"
SKIP_POD_INSTALL="false"

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

iOS simulator package/deploy/run script for phone/tablet.

Options:
  --action <package|deploy|run>   Action to execute (default: run)
  --mode <debug|profile|release>  Flutter build mode (default: debug)
  --device-type <phone|tablet|any>
                                  Target iOS simulator device type (default: phone)
  --simulator-id <id>             Explicit simulator UDID (overrides --device-type)
  --ffi-framework <path>          Path to tim2tox_ffi.framework
  --ffi-dylib <path>              Path to libtim2tox_ffi.dylib
  --list-devices                  List available iOS simulators and exit
  --skip-pub-get                  Skip flutter pub get step
  --skip-pod-install              Skip pod install step
  --help                          Show this help

Examples:
  $(basename "$0") --action package --mode release
  $(basename "$0") --action deploy --device-type tablet
  $(basename "$0") --action run --simulator-id <UDID>

Notes:
  - This script targets iOS Simulator (iPhone/iPad) for mobile/tablet validation.
  - For real-device deployment, keep using Xcode signing + flutter run/install.
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
    --simulator-id)
      SIMULATOR_ID="${2:-}"; shift 2;;
    --ffi-framework)
      FFI_FRAMEWORK_PATH="${2:-}"; shift 2;;
    --ffi-dylib)
      FFI_DYLIB_PATH="${2:-}"; shift 2;;
    --list-devices)
      LIST_DEVICES="true"; shift;;
    --skip-pub-get)
      SKIP_PUB_GET="true"; shift;;
    --skip-pod-install)
      SKIP_POD_INSTALL="true"; shift;;
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
  if [[ "$OSTYPE" != darwin* ]]; then
    error "iOS script must run on macOS."
    exit 1
  fi
  require_cmd flutter
  require_cmd xcrun
  if [[ "$SKIP_POD_INSTALL" != "true" ]]; then
    require_cmd pod
  fi
  if [[ ! -f "$FLUTTER_APP_DIR/pubspec.yaml" ]]; then
    error "Flutter app not found: $FLUTTER_APP_DIR"
    exit 1
  fi
}

prepare_flutter_deps() {
  if [[ "$SKIP_PUB_GET" == "true" ]]; then
    warn "Skipping flutter pub get (--skip-pub-get)"
  else
    if [[ ! -f "$FLUTTER_APP_DIR/pubspec.lock" ]] || \
       [[ "$FLUTTER_APP_DIR/pubspec.yaml" -nt "$FLUTTER_APP_DIR/pubspec.lock" ]] || \
       { [[ -f "$FLUTTER_APP_DIR/pubspec_overrides.yaml" ]] && \
         [[ "$FLUTTER_APP_DIR/pubspec_overrides.yaml" -nt "$FLUTTER_APP_DIR/pubspec.lock" ]]; }; then
      info "Running flutter pub get..."
      (cd "$FLUTTER_APP_DIR" && flutter pub get) >>"$FLUTTER_BUILD_LOG" 2>&1
    fi
  fi

  if [[ "$SKIP_POD_INSTALL" == "true" ]]; then
    warn "Skipping pod install (--skip-pod-install)"
    return
  fi

  local pod_lock="$FLUTTER_APP_DIR/ios/Podfile.lock"
  if [[ ! -f "$pod_lock" ]] || [[ "$FLUTTER_APP_DIR/ios/Podfile" -nt "$pod_lock" ]]; then
    info "Running pod install..."
    (cd "$FLUTTER_APP_DIR/ios" && pod install) >>"$FLUTTER_BUILD_LOG" 2>&1
  fi
}

# ============================================================
# Simulator selection
# ============================================================

simulator_rows() {
  # Name capture is greedy up to the UDID (not `[^()]+`), so device names that
  # themselves contain parentheses — e.g. "iPad Pro 11-inch (M4)" or
  # "iPad mini (A17 Pro)" — are parsed correctly instead of being skipped.
  xcrun simctl list devices available \
    | sed -nE 's/^[[:space:]]*(.+)[[:space:]]+\(([0-9A-F-]{36})\)[[:space:]]+\((Booted|Shutdown)\).*/\1|\2|\3/p'
}

simulator_type_from_name() {
  local name="$1"
  if [[ "$name" == *iPad* ]]; then
    echo "tablet"
  else
    echo "phone"
  fi
}

list_ios_simulators() {
  local row name udid state kind
  echo -e "${CYAN}Available iOS simulators:${NC}"
  while IFS='|' read -r name udid state; do
    [[ -z "$udid" ]] && continue
    kind="$(simulator_type_from_name "$name")"
    echo "  $udid  [$kind]  $name ($state)"
  done < <(simulator_rows)
}

SELECTED_SIMULATOR_ID=""
SELECTED_SIMULATOR_NAME=""
SELECTED_SIMULATOR_STATE=""

select_simulator() {
  local row name udid state kind
  local first_match_id="" first_match_name="" first_match_state=""

  if [[ -n "$SIMULATOR_ID" ]]; then
    while IFS='|' read -r name udid state; do
      if [[ "$udid" == "$SIMULATOR_ID" ]]; then
        SELECTED_SIMULATOR_ID="$udid"
        SELECTED_SIMULATOR_NAME="$name"
        SELECTED_SIMULATOR_STATE="$state"
        return
      fi
    done < <(simulator_rows)
    error "Specified simulator id not found: $SIMULATOR_ID"
    exit 1
  fi

  while IFS='|' read -r name udid state; do
    [[ -z "$udid" ]] && continue
    kind="$(simulator_type_from_name "$name")"
    if [[ "$DEVICE_TYPE" == "any" || "$kind" == "$DEVICE_TYPE" ]]; then
      if [[ "$state" == "Booted" ]]; then
        SELECTED_SIMULATOR_ID="$udid"
        SELECTED_SIMULATOR_NAME="$name"
        SELECTED_SIMULATOR_STATE="$state"
        return
      fi
      if [[ -z "$first_match_id" ]]; then
        first_match_id="$udid"
        first_match_name="$name"
        first_match_state="$state"
      fi
    fi
  done < <(simulator_rows)

  if [[ -n "$first_match_id" ]]; then
    SELECTED_SIMULATOR_ID="$first_match_id"
    SELECTED_SIMULATOR_NAME="$first_match_name"
    SELECTED_SIMULATOR_STATE="$first_match_state"
    return
  fi

  error "No simulator matched --device-type=$DEVICE_TYPE"
  list_ios_simulators
  exit 1
}

ensure_simulator_booted() {
  select_simulator
  info "Using simulator: $SELECTED_SIMULATOR_NAME ($SELECTED_SIMULATOR_ID)"
  open -a Simulator >/dev/null 2>&1 || true
  if [[ "$SELECTED_SIMULATOR_STATE" != "Booted" ]]; then
    info "Booting simulator..."
    xcrun simctl boot "$SELECTED_SIMULATOR_ID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$SELECTED_SIMULATOR_ID" -b >/dev/null 2>&1 || true
  fi
}

# ============================================================
# FFI injection
# ============================================================

ios_app_bundle_path() {
  echo "$FLUTTER_APP_DIR/build/ios/iphonesimulator/Runner.app"
}

resolve_ffi_framework_path() {
  local candidates=()
  if [[ -n "$FFI_FRAMEWORK_PATH" ]]; then
    candidates+=("$FFI_FRAMEWORK_PATH")
  fi
  candidates+=(
    "$FLUTTER_APP_DIR/third_party/tim2tox/build/ios/tim2tox_ffi.framework"
    "$FLUTTER_APP_DIR/third_party/tim2tox/build/tim2tox_ffi.framework"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c" && -f "$c/tim2tox_ffi" ]]; then
      echo "$c"
      return
    fi
  done
}

resolve_ffi_dylib_path() {
  local candidates=()
  if [[ -n "$FFI_DYLIB_PATH" ]]; then
    candidates+=("$FFI_DYLIB_PATH")
  fi
  candidates+=(
    "$FLUTTER_APP_DIR/third_party/tim2tox/build/ffi/libtim2tox_ffi.dylib"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      echo "$c"
      return
    fi
  done
}

inject_ios_ffi_artifacts() {
  local app_bundle frameworks_dir framework_src dylib_src
  app_bundle="$(ios_app_bundle_path)"
  frameworks_dir="$app_bundle/Frameworks"
  mkdir -p "$frameworks_dir"

  framework_src="$(resolve_ffi_framework_path || true)"
  dylib_src="$(resolve_ffi_dylib_path || true)"

  if [[ -n "$framework_src" ]]; then
    info "Injecting framework: $framework_src"
    rm -rf "$frameworks_dir/tim2tox_ffi.framework"
    cp -R "$framework_src" "$frameworks_dir/"
    # Re-sign with an ad-hoc signature so the simulator loader accepts the
    # freshly copied framework (the original signature is invalidated by cp).
    codesign --force --sign - "$frameworks_dir/tim2tox_ffi.framework" 2>/dev/null || true
  fi

  if [[ -n "$dylib_src" ]]; then
    info "Injecting dylib: $dylib_src"
    cp "$dylib_src" "$frameworks_dir/libtim2tox_ffi.dylib"
    # Re-sign ad-hoc after copy; same reason as the framework above.
    codesign --force --sign - "$frameworks_dir/libtim2tox_ffi.dylib" 2>/dev/null || true
  fi

  if [[ ! -d "$frameworks_dir/tim2tox_ffi.framework" && ! -f "$frameworks_dir/libtim2tox_ffi.dylib" ]]; then
    error "Missing iOS tim2tox FFI artifact in app bundle."
    echo "Provide one of:"
    echo "  --ffi-framework /path/to/tim2tox_ffi.framework"
    echo "  --ffi-dylib /path/to/libtim2tox_ffi.dylib"
    echo ""
    echo "Environment variables also supported:"
    echo "  TIM2TOX_IOS_FRAMEWORK_PATH"
    echo "  TIM2TOX_IOS_DYLIB_PATH"
    exit 1
  fi
}

ios_bundle_id() {
  awk -F'=' '
    /PRODUCT_BUNDLE_IDENTIFIER = / && $0 !~ /RunnerTests/ {
      gsub(/[ ;]/, "", $2);
      print $2;
      exit
    }' "$IOS_PBXPROJ"
}

# ============================================================
# Build / deploy / run
# ============================================================

build_ios_simulator_app() {
  : >"$FLUTTER_BUILD_LOG"
  info "Building iOS simulator app ($MODE)..."
  local -a flutter_build_args=(
    build ios --simulator --"$MODE"
    --dart-define=FLUTTER_BUILD_MODE="$MODE"
  )
  if [[ -n "${MCP_BINDING:-}" ]]; then
    case "${MCP_BINDING}" in
      skill|marionette|stock)
        flutter_build_args+=("--dart-define=MCP_BINDING=${MCP_BINDING}")
        flutter_build_args+=("--dart-define=TOXEE_L3_TEST=${TOXEE_L3_TEST:-true}")
        info "MCP_BINDING=${MCP_BINDING} TOXEE_L3_TEST=${TOXEE_L3_TEST:-true}"
        ;;
      *)
        error "Invalid MCP_BINDING='${MCP_BINDING}'. Allowed: skill|marionette|stock."
        exit 2
        ;;
    esac
  fi
  for define_name in \
    TOXEE_APP_SUPPORT_DIR \
    TOXEE_LOG_DIR \
    TOXEE_SHARED_PREFS_PREFIX \
    TOXEE_TCCF_GLOBAL_SUBDIR \
    TOXEE_DISABLE_NOTIFICATION_PERMISSION_PROMPT; do
    if [[ -n "${!define_name:-}" ]]; then
      flutter_build_args+=("--dart-define=${define_name}=${!define_name}")
    fi
  done
  (cd "$FLUTTER_APP_DIR" && flutter "${flutter_build_args[@]}") >>"$FLUTTER_BUILD_LOG" 2>&1

  local app_bundle
  app_bundle="$(ios_app_bundle_path)"
  if [[ ! -d "$app_bundle" ]]; then
    error "Built app bundle not found: $app_bundle"
    exit 1
  fi
  inject_ios_ffi_artifacts
  info "Build completed: $app_bundle"
}

deploy_ios_simulator_app() {
  local app_bundle
  app_bundle="$(ios_app_bundle_path)"
  if [[ ! -d "$app_bundle" ]]; then
    warn "iOS app bundle not found, building first."
    build_ios_simulator_app
  fi

  ensure_simulator_booted
  : >"$DEPLOY_LOG"
  info "Installing app to simulator..."
  xcrun simctl install "$SELECTED_SIMULATOR_ID" "$app_bundle" >>"$DEPLOY_LOG" 2>&1
  info "Deploy completed."
}

run_ios_simulator_app() {
  deploy_ios_simulator_app

  local bundle_id
  bundle_id="$(ios_bundle_id)"
  if [[ -z "$bundle_id" ]]; then
    error "Failed to resolve iOS bundle id from $IOS_PBXPROJ"
    exit 1
  fi

  info "Launching $bundle_id..."
  xcrun simctl terminate "$SELECTED_SIMULATOR_ID" "$bundle_id" >/dev/null 2>&1 || true
  xcrun simctl launch "$SELECTED_SIMULATOR_ID" "$bundle_id" >/dev/null

  echo ""
  echo -e "${GREEN}Tailing iOS simulator logs (Ctrl+C to stop)...${NC}"
  xcrun simctl spawn "$SELECTED_SIMULATOR_ID" log stream --style compact \
    --predicate 'process == "Runner" OR process == "Toxee"'
}

# ============================================================
# Main
# ============================================================

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Toxee — iOS Mobile/Tablet Simulator  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"

preflight_checks

if [[ "$LIST_DEVICES" == "true" ]]; then
  list_ios_simulators
  exit 0
fi

prepare_flutter_deps

case "$ACTION" in
  package)
    build_ios_simulator_app
    ;;
  deploy)
    build_ios_simulator_app
    deploy_ios_simulator_app
    ;;
  run)
    build_ios_simulator_app
    run_ios_simulator_app
    ;;
esac
