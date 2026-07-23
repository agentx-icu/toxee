#!/bin/bash

# iOS real-device package/deploy/run script for toxee.
# Includes signing-aware post-build FFI injection + re-sign.

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_APP_DIR="$SCRIPT_DIR"
BUILD_DIR="$FLUTTER_APP_DIR/build/ios_device"
FLUTTER_BUILD_LOG="$BUILD_DIR/flutter_ios_device_build.log"
DEPLOY_LOG="$BUILD_DIR/flutter_ios_device_deploy.log"
SIGN_LOG="$BUILD_DIR/flutter_ios_device_sign.log"
IOS_PBXPROJ="$FLUTTER_APP_DIR/ios/Runner.xcodeproj/project.pbxproj"

ACTION="run"                  # package | deploy | run
MODE="debug"                  # debug | profile | release
DEVICE_TYPE="phone"           # phone | tablet | any
DEVICE_ID=""
FFI_FRAMEWORK_PATH="${TIM2TOX_IOS_FRAMEWORK_PATH:-}"   # .../tim2tox_ffi.framework
FFI_DYLIB_PATH="${TIM2TOX_IOS_DYLIB_PATH:-}"           # .../libtim2tox_ffi.dylib
SIGNING_IDENTITY=""           # optional override
LIST_DEVICES="false"
SKIP_PUB_GET="false"
SKIP_POD_INSTALL="false"
SKIP_RESIGN="false"
SKIP_LAUNCH="false"

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
# Helpers
# ============================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

iOS real-device package/deploy/run script.

Options:
  --action <package|deploy|run>   Action to execute (default: run)
  --mode <debug|profile|release>  Flutter build mode (default: debug)
  --device-type <phone|tablet|any>
                                  Target iOS real device type (default: phone)
  --device-id <udid>              Explicit real device UDID (overrides --device-type)
  --ffi-framework <path>          Path to tim2tox_ffi.framework (arm64 device build)
  --ffi-dylib <path>              Path to libtim2tox_ffi.dylib (arm64 device build)
  --sign-identity <identity>      Optional codesign identity override
  --list-devices                  List connected iOS real devices and exit
  --skip-pub-get                  Skip flutter pub get
  --skip-pod-install              Skip pod install
  --skip-resign                   Skip post-injection re-sign (not recommended)
  --skip-launch                   Deploy only, don't launch app
  --help                          Show this help

Examples:
  $(basename "$0") --action package --mode release
  $(basename "$0") --action deploy --device-type tablet
  $(basename "$0") --action run --device-id 00008110-001C1D0A3A91801E

Notes:
  - Requires Xcode signing configuration to be valid (Team/cert/profile).
  - If you inject tim2tox FFI artifacts, app is re-signed automatically.
EOF
}

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Missing command: $cmd"
    exit 1
  fi
}

is_device_line() {
  local line="$1"
  [[ -z "$line" ]] && return 1
  [[ "$line" == *"Simulator"* ]] && return 1
  [[ "$line" == *"MacBook"* ]] && return 1
  [[ "$line" == *"Mac ("* ]] && return 1
  [[ "$line" == *"Apple TV"* ]] && return 1
  return 0
}

device_kind_from_name() {
  local name="$1"
  if [[ "$name" == *"iPad"* ]]; then
    echo "tablet"
  else
    echo "phone"
  fi
}

# Parse lines like:
#   Bin's iPhone (17.5.1) (00008110-001C1D0A3A91801E)
extract_udid_from_line() {
  local line="$1"
  sed -nE 's/^.*\(([A-Za-z0-9-]+)\)[[:space:]]*$/\1/p' <<<"$line"
}

extract_name_from_line() {
  local line="$1"
  sed -E 's/[[:space:]]+\([0-9.]+\)[[:space:]]+\([A-Za-z0-9-]+\)[[:space:]]*$//' <<<"$line"
}

ios_app_bundle_path() {
  echo "$FLUTTER_APP_DIR/build/ios/iphoneos/Runner.app"
}

ios_bundle_id() {
  awk -F'=' '
    /PRODUCT_BUNDLE_IDENTIFIER = / && $0 !~ /RunnerTests/ {
      gsub(/[ ;]/, "", $2);
      print $2;
      exit
    }' "$IOS_PBXPROJ"
}

preflight_checks() {
  if [[ "$OSTYPE" != darwin* ]]; then
    error "This script must run on macOS."
    exit 1
  fi
  require_cmd flutter
  require_cmd xcrun
  require_cmd codesign
  if [[ "$SKIP_POD_INSTALL" != "true" ]]; then
    require_cmd pod
  fi
  if [[ ! -f "$FLUTTER_APP_DIR/pubspec.yaml" ]]; then
    error "Flutter app not found: $FLUTTER_APP_DIR"
    exit 1
  fi
  if ! xcrun devicectl help >/dev/null 2>&1; then
    error "xcrun devicectl is not available. Update Xcode command line tools."
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
# Real device selection
# ============================================================

physical_device_lines() {
  local in_devices="false" line
  xcrun xctrace list devices 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" == "== Devices ==" ]]; then
      in_devices="true"
      continue
    fi
    if [[ "$line" == "== Simulators ==" ]]; then
      break
    fi
    if [[ "$in_devices" == "true" ]]; then
      line="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$line")"
      is_device_line "$line" && echo "$line"
    fi
  done
}

list_real_devices() {
  local line udid name kind count="0"
  echo -e "${CYAN}Connected iOS real devices:${NC}"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    udid="$(extract_udid_from_line "$line")"
    name="$(extract_name_from_line "$line")"
    kind="$(device_kind_from_name "$name")"
    if [[ -n "$udid" ]]; then
      echo "  $udid  [$kind]  $name"
      count=$((count + 1))
    fi
  done < <(physical_device_lines)
  if [[ "$count" -eq 0 ]]; then
    warn "No connected iOS real devices."
  fi
}

SELECTED_DEVICE_ID=""
SELECTED_DEVICE_NAME=""
SELECTED_DEVICE_KIND=""

select_real_device() {
  local line udid name kind

  if [[ -n "$DEVICE_ID" ]]; then
    while IFS= read -r line; do
      udid="$(extract_udid_from_line "$line")"
      [[ -z "$udid" ]] && continue
      if [[ "$udid" == "$DEVICE_ID" ]]; then
        name="$(extract_name_from_line "$line")"
        kind="$(device_kind_from_name "$name")"
        SELECTED_DEVICE_ID="$udid"
        SELECTED_DEVICE_NAME="$name"
        SELECTED_DEVICE_KIND="$kind"
        return
      fi
    done < <(physical_device_lines)
    error "Requested --device-id not found: $DEVICE_ID"
    exit 1
  fi

  while IFS= read -r line; do
    udid="$(extract_udid_from_line "$line")"
    name="$(extract_name_from_line "$line")"
    [[ -z "$udid" || -z "$name" ]] && continue
    kind="$(device_kind_from_name "$name")"
    if [[ "$DEVICE_TYPE" == "any" || "$kind" == "$DEVICE_TYPE" ]]; then
      SELECTED_DEVICE_ID="$udid"
      SELECTED_DEVICE_NAME="$name"
      SELECTED_DEVICE_KIND="$kind"
      return
    fi
  done < <(physical_device_lines)

  error "No iOS real device matched --device-type=$DEVICE_TYPE"
  list_real_devices
  exit 1
}

# ============================================================
# FFI resolution + post-build injection
# ============================================================

resolve_ffi_framework_path() {
  local candidates=()
  if [[ -n "$FFI_FRAMEWORK_PATH" ]]; then
    candidates+=("$FFI_FRAMEWORK_PATH")
  fi
  candidates+=(
    "$FLUTTER_APP_DIR/third_party/tim2tox/build/ios-device/tim2tox_ffi.framework"
    "$FLUTTER_APP_DIR/third_party/tim2tox/build/ios/tim2tox_ffi.framework"
    "$FLUTTER_APP_DIR/third_party/tim2tox/build/tim2tox_ffi.framework"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c" && -f "$c/tim2tox_ffi" ]]; then
      # build_ios_sim_ffi.sh writes the SIMULATOR framework to the same
      # build/ios/ path. Packaging a simulator slice into an iphoneos (real
      # device) app crashes at launch, so skip any IOSSIMULATOR-platform binary.
      if vtool -show-build "$c/tim2tox_ffi" 2>/dev/null | grep -qi "IOSSIMULATOR"; then
        echo "resolve_ffi_framework_path: skipping simulator framework at $c" >&2
        continue
      fi
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

warn_if_not_arm64_binary() {
  local bin_path="$1"
  if command -v lipo >/dev/null 2>&1; then
    local info_out
    info_out="$(lipo -info "$bin_path" 2>/dev/null || true)"
    if [[ -n "$info_out" && "$info_out" != *"arm64"* ]]; then
      warn "Binary may not contain arm64 slice: $bin_path"
      warn "lipo -info => $info_out"
    fi
  fi
}

inject_ios_device_ffi_artifacts() {
  local app_bundle frameworks_dir framework_src dylib_src injected="false"
  app_bundle="$(ios_app_bundle_path)"
  frameworks_dir="$app_bundle/Frameworks"
  mkdir -p "$frameworks_dir"

  framework_src="$(resolve_ffi_framework_path || true)"
  dylib_src="$(resolve_ffi_dylib_path || true)"

  if [[ -n "$framework_src" ]]; then
    info "Injecting framework: $framework_src"
    warn_if_not_arm64_binary "$framework_src/tim2tox_ffi"
    rm -rf "$frameworks_dir/tim2tox_ffi.framework"
    cp -R "$framework_src" "$frameworks_dir/"
    injected="true"
  fi

  if [[ -n "$dylib_src" ]]; then
    info "Injecting dylib: $dylib_src"
    warn_if_not_arm64_binary "$dylib_src"
    cp "$dylib_src" "$frameworks_dir/libtim2tox_ffi.dylib"
    injected="true"
  fi

  if [[ "$injected" != "true" ]]; then
    error "No iOS tim2tox FFI artifact found for injection."
    echo "Provide one of:"
    echo "  --ffi-framework /path/to/tim2tox_ffi.framework"
    echo "  --ffi-dylib /path/to/libtim2tox_ffi.dylib"
    echo ""
    echo "Or set environment vars:"
    echo "  TIM2TOX_IOS_FRAMEWORK_PATH"
    echo "  TIM2TOX_IOS_DYLIB_PATH"
    exit 1
  fi
}

# ============================================================
# Re-sign after injection
# ============================================================

detect_signing_identity_from_app() {
  local app_bundle="$1"
  # Pick the first Authority as identity if no explicit override.
  codesign -dvv "$app_bundle" 2>&1 | awk -F= '/^Authority=/{print $2; exit}'
}

extract_entitlements() {
  local app_bundle="$1"
  local out="$2"
  codesign -d --entitlements :- "$app_bundle" >"$out" 2>/dev/null || true
}

resign_ios_app_bundle() {
  local app_bundle frameworks_dir identity entitlements_file
  app_bundle="$(ios_app_bundle_path)"
  frameworks_dir="$app_bundle/Frameworks"
  entitlements_file="$BUILD_DIR/Runner.entitlements.plist"
  : >"$SIGN_LOG"

  identity="$SIGNING_IDENTITY"
  if [[ -z "$identity" ]]; then
    identity="$(detect_signing_identity_from_app "$app_bundle" || true)"
  fi
  if [[ -z "$identity" ]]; then
    error "Failed to detect signing identity from app. Use --sign-identity explicitly."
    exit 1
  fi

  info "Re-sign identity: $identity"
  extract_entitlements "$app_bundle" "$entitlements_file"

  # Sign nested frameworks/dylibs first.
  if [[ -d "$frameworks_dir" ]]; then
    local fw binary dylib
    for fw in "$frameworks_dir"/*.framework; do
      [[ -d "$fw" ]] || continue
      binary="$fw/$(basename "$fw" .framework)"
      if [[ -f "$binary" ]]; then
        codesign --force --sign "$identity" --timestamp=none "$binary" >>"$SIGN_LOG" 2>&1
      fi
      codesign --force --sign "$identity" --timestamp=none "$fw" >>"$SIGN_LOG" 2>&1
    done
    for dylib in "$frameworks_dir"/*.dylib; do
      [[ -f "$dylib" ]] || continue
      codesign --force --sign "$identity" --timestamp=none "$dylib" >>"$SIGN_LOG" 2>&1
    done
  fi

  # Sign app.
  if [[ -s "$entitlements_file" ]]; then
    codesign --force --sign "$identity" --entitlements "$entitlements_file" --timestamp=none "$app_bundle" >>"$SIGN_LOG" 2>&1
  else
    codesign --force --sign "$identity" --timestamp=none "$app_bundle" >>"$SIGN_LOG" 2>&1
  fi

  codesign --verify --deep --strict "$app_bundle" >>"$SIGN_LOG" 2>&1
  info "Re-sign completed."
}

# ============================================================
# Build / deploy / run
# ============================================================

build_ios_device_app() {
  : >"$FLUTTER_BUILD_LOG"
  info "Building iOS real-device app ($MODE, codesign enabled)..."

  # Pre-resolve FFI artifacts so the Xcode "Embed tim2tox_ffi" phase (fail-loud
  # on device builds) cooperates with this script's documented custom-artifact
  # injection (--ffi-framework / --ffi-dylib):
  #   framework resolved  -> export TIM2TOX_IOS_FRAMEWORK_PATH (phase embeds it)
  #   dylib-only          -> export TOXEE_FFI_POSTBUILD_INJECT=1 (phase warns;
  #                          inject_ios_device_ffi_artifacts installs the dylib)
  #   neither             -> phase fails loud: the app is broken without FFI.
  local pre_framework pre_dylib
  pre_framework="$(resolve_ffi_framework_path || true)"
  pre_dylib="$(resolve_ffi_dylib_path || true)"
  if [[ -n "$pre_framework" ]]; then
    export TIM2TOX_IOS_FRAMEWORK_PATH="$pre_framework"
  elif [[ -n "$pre_dylib" ]]; then
    export TOXEE_FFI_POSTBUILD_INJECT=1
  fi

  (cd "$FLUTTER_APP_DIR" && flutter build ios --"$MODE" --dart-define=FLUTTER_BUILD_MODE="$MODE") >>"$FLUTTER_BUILD_LOG" 2>&1

  local app_bundle
  app_bundle="$(ios_app_bundle_path)"
  if [[ ! -d "$app_bundle" ]]; then
    error "Built app bundle not found: $app_bundle"
    exit 1
  fi

  inject_ios_device_ffi_artifacts

  if [[ "$SKIP_RESIGN" == "true" ]]; then
    warn "Skipping re-sign (--skip-resign). Installation may fail due to invalid signature."
  else
    resign_ios_app_bundle
  fi

  info "Build package ready: $app_bundle"
}

install_to_real_device() {
  local app_bundle
  app_bundle="$(ios_app_bundle_path)"
  if [[ ! -d "$app_bundle" ]]; then
    warn "App bundle not found, building first."
    build_ios_device_app
  fi

  select_real_device
  : >"$DEPLOY_LOG"
  info "Installing to $SELECTED_DEVICE_NAME ($SELECTED_DEVICE_ID)..."
  xcrun devicectl device install app --device "$SELECTED_DEVICE_ID" "$app_bundle" >>"$DEPLOY_LOG" 2>&1
  info "Install completed."
}

launch_on_real_device() {
  select_real_device
  local bundle_id
  bundle_id="$(ios_bundle_id)"
  if [[ -z "$bundle_id" ]]; then
    error "Failed to resolve bundle identifier from $IOS_PBXPROJ"
    exit 1
  fi

  info "Launching $bundle_id on $SELECTED_DEVICE_NAME..."
  xcrun devicectl device process launch --device "$SELECTED_DEVICE_ID" "$bundle_id" --terminate-existing >/dev/null
  info "Launch requested."
}

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
    --ffi-framework)
      FFI_FRAMEWORK_PATH="${2:-}"; shift 2;;
    --ffi-dylib)
      FFI_DYLIB_PATH="${2:-}"; shift 2;;
    --sign-identity)
      SIGNING_IDENTITY="${2:-}"; shift 2;;
    --list-devices)
      LIST_DEVICES="true"; shift;;
    --skip-pub-get)
      SKIP_PUB_GET="true"; shift;;
    --skip-pod-install)
      SKIP_POD_INSTALL="true"; shift;;
    --skip-resign)
      SKIP_RESIGN="true"; shift;;
    --skip-launch)
      SKIP_LAUNCH="true"; shift;;
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
# Main
# ============================================================

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Toxee — iOS Real Device             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"

preflight_checks

if [[ "$LIST_DEVICES" == "true" ]]; then
  list_real_devices
  exit 0
fi

prepare_flutter_deps

case "$ACTION" in
  package)
    build_ios_device_app
    ;;
  deploy)
    build_ios_device_app
    install_to_real_device
    ;;
  run)
    build_ios_device_app
    install_to_real_device
    if [[ "$SKIP_LAUNCH" != "true" ]]; then
      launch_on_real_device
    else
      warn "Skipping launch (--skip-launch)"
    fi
    ;;
esac

