#!/bin/bash

# Debug build script for toxee
# Builds the app in DEBUG mode and launches it once (no source watching, no auto-restart).

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TIM2TOX_DIR="$SCRIPT_DIR/third_party/tim2tox"
TIM2TOX_BUILD_DIR="$TIM2TOX_DIR/build"
TIM2TOX_EXAMPLE_BUILD_DIR="$TIM2TOX_DIR/example/build"
FFI_LIB="$TIM2TOX_BUILD_DIR/ffi/libtim2tox_ffi.dylib"
IRC_LIB="$TIM2TOX_EXAMPLE_BUILD_DIR/libirc_client.dylib"
FLUTTER_APP_DIR="$SCRIPT_DIR"
BUILD_DIR="$SCRIPT_DIR/build"
CLIENT_LOG="$BUILD_DIR/flutter_client.log"
NATIVE_BUILD_LOG="$BUILD_DIR/native_build.log"
FLUTTER_BUILD_LOG="$BUILD_DIR/flutter_build.log"
APP_BUNDLE="$FLUTTER_APP_DIR/build/macos/Build/Products/Debug/Toxee.app"
APP_EXE_DIR="$APP_BUNDLE/Contents/MacOS"
APP_EXECUTABLE="$APP_EXE_DIR/Toxee"
APP_SUPPORT_LOG="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/flutter_client.log"

mkdir -p "$BUILD_DIR"

# ----- CLI flags -----------------------------------------------------
CLEAN=false
SKIP_BOOTSTRAP=false
SKIP_PUB_GET=false
for arg in "$@"; do
  case "$arg" in
    --clean)          CLEAN=true ;;
    --skip-bootstrap) SKIP_BOOTSTRAP=true ;;
    --skip-pub-get)   SKIP_PUB_GET=true ;;
    --help|-h)
      cat <<EOF
Usage: $0 [--clean] [--skip-bootstrap] [--skip-pub-get]

  --clean           Wipe Flutter build cache before building (slow).
  --skip-bootstrap  Skip dart run tool/bootstrap_deps.dart.
  --skip-pub-get    Skip the cache-aware pub get probe entirely.
EOF
      exit 0 ;;
    *)
      echo "Unknown option: $arg (use --help)" >&2
      exit 1 ;;
  esac
done

# Bootstrap dependencies so pubspec_overrides and third_party are ready.
# bootstrap_deps.dart is itself cache-aware (sha256+patches_sha256), but skip
# the whole probe when the caller knows nothing changed.
if [[ "$SKIP_BOOTSTRAP" != "true" ]]; then
  (cd "$FLUTTER_APP_DIR" && dart run tool/bootstrap_deps.dart) >> "$BUILD_DIR/bootstrap.log" 2>&1 || true
fi

# Process IDs
APP_PID=""
TAIL_PID=""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# Cleanup
# ============================================================

cleanup() {
  local pids=("$TAIL_PID" "$APP_PID")
  for pid in "${pids[@]}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT INT TERM

# ============================================================
# Helper functions
# ============================================================

# Run cmake configure with standard debug flags
cmake_configure() {
  local build_dir="$1" source_dir="$2"
  shift 2
  (cd "$build_dir" && cmake "$source_dir" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_FLAGS_DEBUG="-g -O0" \
    -DCMAKE_C_FLAGS_DEBUG="-g -O0" \
    "$@") >> "$NATIVE_BUILD_LOG" 2>&1
}

# Find a Homebrew library file
find_brew_lib() {
  local pkg="$1" lib_name="$2"
  if [[ -n "${BREW_PREFIX_ROOT:-}" ]]; then
    local pkg_prefix
    pkg_prefix=$(brew --prefix "$pkg" 2>/dev/null || true)
    if [[ -n "$pkg_prefix" && -f "$pkg_prefix/lib/$lib_name" ]]; then
      echo "$pkg_prefix/lib/$lib_name"; return
    fi
  fi
  local path
  for path in "/opt/homebrew/opt/$pkg/lib/$lib_name" "/usr/local/opt/$pkg/lib/$lib_name"; do
    [[ -f "$path" ]] && { echo "$path"; return; }
  done
}

# Bundle a dylib dependency into the app and rewrite install_name
bundle_dylib() {
  local dylib_in_bundle="$1" dep_pattern="$2" brew_pkg="$3"
  local extra_search="${4:-}"

  local dep_old
  dep_old=$(otool -L "$dylib_in_bundle" | awk "/$dep_pattern/ {print \$1; exit}" || true)
  [[ -z "$dep_old" ]] && return 0

  local dep_name dep_src
  dep_name="$(basename "$dep_old")"
  dep_src=$(find_brew_lib "$brew_pkg" "$dep_name")

  if [[ -z "$dep_src" && -n "$extra_search" && -f "$extra_search/$dep_name" ]]; then
    dep_src="$extra_search/$dep_name"
  fi
  if [[ -z "$dep_src" || ! -f "$dep_src" ]]; then
    echo -e "${YELLOW}Warning: Could not find $dep_name${NC}"; return 0
  fi

  chmod +w "$APP_EXE_DIR/$dep_name" 2>/dev/null || true
  rm -f "$APP_EXE_DIR/$dep_name" 2>/dev/null || true
  cp "$dep_src" "$APP_EXE_DIR/" || { echo -e "${YELLOW}Warning: Failed to copy $dep_name${NC}"; return 0; }

  install_name_tool -change "$dep_old" "@loader_path/$dep_name" "$dylib_in_bundle" >> "$FLUTTER_BUILD_LOG" 2>&1 || true
  ad_hoc_sign_dylib "$APP_EXE_DIR/$dep_name"
  echo -e "${GREEN}  Bundled $dep_name${NC}"
}

ad_hoc_sign_dylib() {
  local dylib="$1"
  [[ -f "$dylib" ]] || return 0
  if ! command -v codesign >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: codesign not found; $dylib may fail to load on macOS${NC}"
    return 0
  fi
  codesign --force --sign - "$dylib" >> "$FLUTTER_BUILD_LOG" 2>&1 || {
    echo -e "${YELLOW}Warning: Failed to ad-hoc sign $(basename "$dylib")${NC}"
    return 0
  }
}

# ============================================================
# Build functions
# ============================================================

build_native() {
  echo -e "${YELLOW}==> Building native libraries (DEBUG)...${NC}"
  # Ensure tim2tox submodules (e.g. c-toxcore) are initialized
  if [[ -f "$TIM2TOX_DIR/.gitmodules" ]] && { [[ -d "$TIM2TOX_DIR/.git" ]] || [[ -f "$TIM2TOX_DIR/.git" ]]; }; then
    (cd "$TIM2TOX_DIR" && git submodule update --init --recursive)
  fi
  mkdir -p "$TIM2TOX_BUILD_DIR" "$TIM2TOX_EXAMPLE_BUILD_DIR"
  : > "$NATIVE_BUILD_LOG"

  # Configure tim2tox if needed
  local cmake_ffi_args=(-DBUILD_FFI=ON -DBUILD_TOXAV=ON -DMUST_BUILD_TOXAV=ON -DDHT_BOOTSTRAP=ON -DBOOTSTRAP_DAEMON=ON)
  local needs_configure=false

  if [[ ! -f "$TIM2TOX_BUILD_DIR/CMakeCache.txt" ]] || \
     [[ "$TIM2TOX_DIR/CMakeLists.txt" -nt "$TIM2TOX_BUILD_DIR/CMakeCache.txt" ]]; then
    needs_configure=true
  elif ! grep -q "BUILD_FFI:BOOL=ON" "$TIM2TOX_BUILD_DIR/CMakeCache.txt" 2>/dev/null || \
       ! grep -q "BUILD_TOXAV:BOOL=ON" "$TIM2TOX_BUILD_DIR/CMakeCache.txt" 2>/dev/null || \
       ! grep -q "MUST_BUILD_TOXAV:BOOL=ON" "$TIM2TOX_BUILD_DIR/CMakeCache.txt" 2>/dev/null || \
       ! grep -q "DHT_BOOTSTRAP:BOOL=ON" "$TIM2TOX_BUILD_DIR/CMakeCache.txt" 2>/dev/null || \
       ! grep -q "BOOTSTRAP_DAEMON:BOOL=ON" "$TIM2TOX_BUILD_DIR/CMakeCache.txt" 2>/dev/null; then
    echo -e "${YELLOW}    Reconfiguring to enable required build options (e.g. BUILD_FFI)...${NC}"
    needs_configure=true
  fi
  if [[ "$needs_configure" == "true" ]]; then
    cmake_configure "$TIM2TOX_BUILD_DIR" "$TIM2TOX_DIR" "${cmake_ffi_args[@]}"
  fi
  if ! (cd "$TIM2TOX_BUILD_DIR" && make -j"$(sysctl -n hw.ncpu)" tim2tox_ffi) >> "$NATIVE_BUILD_LOG" 2>&1; then
    echo -e "${RED}Native build failed (tim2tox_ffi). Last 30 lines of $NATIVE_BUILD_LOG:${NC}"
    tail -30 "$NATIVE_BUILD_LOG"
    return 1
  fi

  # Build IRC client library
  if [[ ! -f "$TIM2TOX_EXAMPLE_BUILD_DIR/CMakeCache.txt" ]] || \
     [[ "$TIM2TOX_DIR/example/CMakeLists.txt" -nt "$TIM2TOX_EXAMPLE_BUILD_DIR/CMakeCache.txt" ]]; then
    cmake_configure "$TIM2TOX_EXAMPLE_BUILD_DIR" "$TIM2TOX_DIR/example"
  fi
  (cd "$TIM2TOX_EXAMPLE_BUILD_DIR" && make -j"$(sysctl -n hw.ncpu)" irc_client) >> "$NATIVE_BUILD_LOG" 2>&1

  # Verify
  for lib in "$FFI_LIB" "$IRC_LIB"; do
    if [[ ! -f "$lib" ]]; then
      echo -e "${RED}Build artifacts missing: $lib${NC}"; return 1
    fi
  done
  echo -e "${GREEN}    Native libraries built successfully.${NC}"
}

build_flutter() {
  : > "$FLUTTER_BUILD_LOG"

  # pub get only when the lock file is missing or older than the spec files.
  # bootstrap_deps.dart now writes pubspec_overrides.yaml in-place only when
  # content changes, so its mtime is a reliable cache-busting signal.
  if [[ "$SKIP_PUB_GET" != "true" ]]; then
    local need_pub_get=false
    if [[ ! -f "$FLUTTER_APP_DIR/pubspec.lock" ]]; then
      need_pub_get=true
    elif [[ "$FLUTTER_APP_DIR/pubspec.yaml" -nt "$FLUTTER_APP_DIR/pubspec.lock" ]]; then
      need_pub_get=true
    elif [[ -f "$FLUTTER_APP_DIR/pubspec_overrides.yaml" && \
            "$FLUTTER_APP_DIR/pubspec_overrides.yaml" -nt "$FLUTTER_APP_DIR/pubspec.lock" ]]; then
      need_pub_get=true
    fi
    if [[ "$need_pub_get" == "true" ]]; then
      echo -e "${YELLOW}    Resolving Flutter dependencies...${NC}"
      (cd "$FLUTTER_APP_DIR" && flutter pub get) >> "$FLUTTER_BUILD_LOG" 2>&1
    fi
  fi

  # Ensure macOS project exists
  if [[ ! -d "$FLUTTER_APP_DIR/macos" ]]; then
    echo -e "${YELLOW}    Adding macOS desktop support...${NC}"
    (cd "$FLUTTER_APP_DIR" && flutter create . --platforms=macos) >> "$FLUTTER_BUILD_LOG" 2>&1
  fi

  # Only force a clean rebuild when the app bundle is missing (cold start)
  # or the user passes --clean. Trust Flutter's incremental build otherwise:
  # mtime changes on pubspec.yaml from git operations no longer trigger a
  # wipe-and-rebuild that re-downloads every dependency.
  local needs_clean=false
  if [[ ! -d "$APP_BUNDLE" ]] || [[ ! -f "$APP_EXECUTABLE" ]]; then
    needs_clean=true
  elif [[ "$CLEAN" == "true" ]]; then
    needs_clean=true
    echo -e "${YELLOW}    --clean requested, wiping build cache...${NC}"
  fi

  if [[ "$needs_clean" == "true" ]]; then
    echo -e "${YELLOW}==> Clean Flutter build...${NC}"
    (cd "$FLUTTER_APP_DIR" && flutter clean) >> "$FLUTTER_BUILD_LOG" 2>&1
    rm -rf "$APP_BUNDLE" || true
    mkdir -p "$BUILD_DIR"
    : > "$FLUTTER_BUILD_LOG"
  fi

  # MCP_BINDING is a debug-only switch for the AI-UI-debug MCP comparison
  # (see doc/research/MCP_COMPARISON_TEST_PLAN.en.md). Forwarded to flutter build as a
  # --dart-define so lib/main.dart picks the right binding at startup.
  # Defaults to "skill" (current behavior) when the env var is unset.
  # Whitelist the accepted values and use an array to avoid word-split
  # injection if MCP_BINDING contains spaces or extra flags.
  local -a flutter_build_args=(build macos --debug --dart-define=FLUTTER_BUILD_MODE=debug)
  if [[ -n "${MCP_BINDING:-}" ]]; then
    case "${MCP_BINDING}" in
      skill|marionette|stock)
        flutter_build_args+=("--dart-define=MCP_BINDING=${MCP_BINDING}")
        echo -e "${YELLOW}    MCP_BINDING=${MCP_BINDING}${NC}"
        # Enable the L3 test-only debug MCP tool surface (deterministic send,
        # state dump — see lib/ui/testing/l3_debug_tools.dart). Gated by
        # kDebugMode too, so it never reaches profile/release. Opt out with
        # TOXEE_L3_TEST=false.
        flutter_build_args+=("--dart-define=TOXEE_L3_TEST=${TOXEE_L3_TEST:-true}")
        echo -e "${YELLOW}    TOXEE_L3_TEST=${TOXEE_L3_TEST:-true}${NC}"
        ;;
      *)
        echo -e "${RED}    Invalid MCP_BINDING='${MCP_BINDING}'. Allowed: skill|marionette|stock.${NC}" >&2
        return 1
        ;;
    esac
  fi

  echo -e "${YELLOW}==> Building Flutter app (DEBUG)...${NC}"
  (cd "$FLUTTER_APP_DIR" && flutter "${flutter_build_args[@]}") >> "$FLUTTER_BUILD_LOG" 2>&1

  if [[ ! -d "$APP_EXE_DIR" ]]; then
    echo -e "${RED}macOS app bundle not found at ${APP_BUNDLE}${NC}"; return 1
  fi
  echo -e "${GREEN}    Built: $APP_BUNDLE${NC}"
}

bundle_libs() {
  echo -e "${YELLOW}==> Bundling native libraries...${NC}"
  cp "$FFI_LIB" "$APP_EXE_DIR/"
  cp "$IRC_LIB" "$APP_EXE_DIR/"

  local ffi_dylib="$APP_EXE_DIR/libtim2tox_ffi.dylib"
  local irc_dylib="$APP_EXE_DIR/libirc_client.dylib"

  # Bundle libsodium (needed by both FFI and IRC)
  local sodium_old
  sodium_old=$(otool -L "$ffi_dylib" | awk '/libsodium\..*dylib/ {print $1; exit}')
  [[ -z "$sodium_old" ]] && sodium_old=$(otool -L "$irc_dylib" | awk '/libsodium\..*dylib/ {print $1; exit}')
  if [[ -n "$sodium_old" ]]; then
    local sodium_name sodium_src
    sodium_name="$(basename "$sodium_old")"
    sodium_src=$(find_brew_lib "libsodium" "$sodium_name")
    [[ -z "$sodium_src" && -f "$TIM2TOX_BUILD_DIR/toxcore_build/$sodium_name" ]] && \
      sodium_src="$TIM2TOX_BUILD_DIR/toxcore_build/$sodium_name"
    if [[ -n "$sodium_src" && -f "$sodium_src" ]]; then
      chmod +w "$APP_EXE_DIR/$sodium_name" 2>/dev/null || true
      rm -f "$APP_EXE_DIR/$sodium_name" 2>/dev/null || true
      cp "$sodium_src" "$APP_EXE_DIR/" || true
      install_name_tool -change "$sodium_old" "@loader_path/$sodium_name" "$ffi_dylib" >> "$FLUTTER_BUILD_LOG" 2>&1 || true
      install_name_tool -change "$sodium_old" "@loader_path/$sodium_name" "$irc_dylib" >> "$FLUTTER_BUILD_LOG" 2>&1 || true
      ad_hoc_sign_dylib "$APP_EXE_DIR/$sodium_name"
      echo -e "${GREEN}  Bundled $sodium_name${NC}"
    fi
  fi

  # Bundle opus and vpx (toxav dependencies)
  bundle_dylib "$ffi_dylib" 'libopus\..*dylib' "opus"
  bundle_dylib "$ffi_dylib" 'libvpx\..*dylib'  "libvpx"

  bundle_dylib "$irc_dylib" 'libssl\..*dylib' "openssl@3"
  bundle_dylib "$irc_dylib" 'libcrypto\..*dylib' "openssl@3"
  local ssl_name crypto_name ssl_dylib crypto_dylib
  ssl_name=$(otool -L "$irc_dylib" | awk '/@loader_path\/libssl\..*dylib/ {print $1; exit}' | xargs basename 2>/dev/null || true)
  crypto_name=$(otool -L "$irc_dylib" | awk '/@loader_path\/libcrypto\..*dylib/ {print $1; exit}' | xargs basename 2>/dev/null || true)
  ssl_dylib="$APP_EXE_DIR/$ssl_name"
  if [[ -f "$ssl_dylib" ]]; then
    local crypto_old
    crypto_old=$(otool -L "$ssl_dylib" | awk '/libcrypto\..*dylib/ {print $1; exit}' || true)
    if [[ -n "$crypto_old" && -n "$crypto_name" ]]; then
      install_name_tool -change "$crypto_old" "@loader_path/$crypto_name" "$ssl_dylib" >> "$FLUTTER_BUILD_LOG" 2>&1 || true
    fi
    ad_hoc_sign_dylib "$ssl_dylib"
  fi
  crypto_dylib="$APP_EXE_DIR/$crypto_name"
  ad_hoc_sign_dylib "$ffi_dylib"
  ad_hoc_sign_dylib "$irc_dylib"
  ad_hoc_sign_dylib "$crypto_dylib"
}

# ============================================================
# App lifecycle
# ============================================================

stop_app() {
  if [[ -n "$TAIL_PID" ]] && kill -0 "$TAIL_PID" 2>/dev/null; then
    kill "$TAIL_PID" 2>/dev/null || true
    wait "$TAIL_PID" 2>/dev/null || true
    TAIL_PID=""
  fi
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
  fi
}

launch_app() {
  export TIM2TOX_FFI_PATH="$FFI_LIB"
  export DYLD_FALLBACK_LIBRARY_PATH="$APP_EXE_DIR:${DYLD_FALLBACK_LIBRARY_PATH:-}"
  export TOXEE_LOG_DIR="$FLUTTER_APP_DIR/build"

  # Clear log files; ensure App Support log dir exists (sandbox path may not exist yet)
  : > "$CLIENT_LOG"
  mkdir -p "$(dirname "$APP_SUPPORT_LOG")"
  : > "$APP_SUPPORT_LOG"

  # Engine switches: tell the Dart engine to (1) bind the VM service on a
  # free port and announce it, and (2) skip the auth token so the
  # advertised URI is `http://127.0.0.1:<port>/<bare-token>/ws`. On macOS
  # the desktop embedder routes process argv into `dartEntrypointArguments`
  # — NOT into engine switches — so command-line flags don't work; the
  # canonical mechanism is the `FLUTTER_ENGINE_SWITCHES` env var family
  # (see `engine_switches.cc`). Per codex Round 4 review P1.
  # Debug-only + 127.0.0.1-bound, so disabling auth codes here is the
  # documented L3 fallback path, not a production exposure.
  export FLUTTER_ENGINE_SWITCHES=2
  export FLUTTER_ENGINE_SWITCH_1="vm-service-port=0"
  export FLUTTER_ENGINE_SWITCH_2="disable-service-auth-codes"

  # Dedicated stdout/stderr capture for the Dart VM service URI
  # announcement. The macOS embedder prints "flutter: The Dart VM service
  # is listening on http://127.0.0.1:<port>/" to STDOUT (not stderr,
  # contra Round 4 review's initial guess; empirically confirmed via
  # direct-binary test). We can't share `$APP_SUPPORT_LOG` because the
  # in-app `AppLogger` probe (`logging_bootstrap.dart:45`) does an
  # exclusive `writeAsStringSync('test', FileMode.write)` on
  # `flutter_client.log` which truncates anything we redirected there.
  # Tee both streams into both the dedicated archive AND the AppLogger
  # log so the existing dev-loop `tail -f` keeps showing early engine +
  # `stderr.writeln` diagnostics (per codex Round 4 P2).
  local stdio_log="$BUILD_DIR/toxee_stdio.log"
  local vm_uri_file="$BUILD_DIR/vm_service_uri.txt"
  : > "$stdio_log"
  # Always clear the stale URI file so a failed launch doesn't leave a
  # zombie URI for the next session to pick up (codex Round 4 P2).
  rm -f "$vm_uri_file"

  echo -e "${YELLOW}==> Launching app (DEBUG)...${NC}"
  # tee stdout + stderr into $stdio_log for URI extraction; the dev-loop
  # log is still maintained in parallel by AppLogger's own writes.
  "$APP_EXECUTABLE" > >(tee -a "$stdio_log") 2> >(tee -a "$stdio_log" >&2) &
  APP_PID=$!

  sleep 2

  # Symlink log for convenience
  if [[ -f "$APP_SUPPORT_LOG" ]]; then
    rm -f "$CLIENT_LOG"
    ln -s "$APP_SUPPORT_LOG" "$CLIENT_LOG" 2>/dev/null || \
      cp "$APP_SUPPORT_LOG" "$CLIENT_LOG" 2>/dev/null || true
  fi

  # Bring window to front
  sleep 1
  osascript -e 'tell application "System Events" to set frontmost of process "Toxee" to true' >/dev/null 2>&1 || true

  # Start tailing log
  local tail_log="$CLIENT_LOG"
  [[ -f "$APP_SUPPORT_LOG" ]] && tail_log="$APP_SUPPORT_LOG"
  tail -f "$tail_log" &
  TAIL_PID=$!

  # Surface the Dart VM service URI for L3 MCP harnesses. The engine
  # prints the full announcement (`flutter: The Dart VM service is
  # listening on http://127.0.0.1:<port>/[<token>/]`) to stdout within
  # ~5s of launch. Capture the FULL URI including any auth-code path
  # segment, in case `disable-service-auth-codes` didn't take effect.
  local vm_uri=""
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    vm_uri=$(grep -oE "http://127\.0\.0\.1:[0-9]+(/[A-Za-z0-9_=-]+)?/?" \
        "$stdio_log" 2>/dev/null | head -1)
    if [[ -n "$vm_uri" ]]; then break; fi
    sleep 1
  done

  echo ""
  echo -e "${GREEN}Logs:${NC}"
  echo "  Native build:   $NATIVE_BUILD_LOG"
  echo "  Flutter build:  $FLUTTER_BUILD_LOG"
  echo "  Client:         $CLIENT_LOG"
  echo "  Engine stdio:   $stdio_log"
  echo ""
  if [[ -n "$vm_uri" ]]; then
    # Normalize trailing slash, then derive ws URI directly from the full
    # http URI (including any auth-code path segment).
    vm_uri="${vm_uri%/}"
    local ws_uri="${vm_uri/http:/ws:}/ws"
    echo -e "${GREEN}VM Service:${NC} $vm_uri/"
    echo -e "${GREEN}WS URI:${NC}     $ws_uri"
    # Park the URI in a known location for MCP harnesses. Consumers:
    # `marionette.connect(uri=...)`,
    # `arenukvern.fmt_connect_debug_app({mode:'uri', uri:'...'})`.
    echo "$ws_uri" > "$vm_uri_file"
  else
    echo -e "${YELLOW}VM Service URI not found in stderr after 15s; check ${stderr_log}${NC}"
    echo -e "${YELLOW}(URI file ${vm_uri_file} was cleared at launch and not rewritten.)${NC}"
  fi
  echo ""
  echo -e "${YELLOW}  Debugger:     lldb -p $APP_PID${NC}"
  echo -e "${YELLOW}  Symbolicate:  atos -arch arm64 -o $APP_EXECUTABLE -l <load_addr> <crash_addr>${NC}"
  echo ""
}

# ============================================================
# Main
# ============================================================

# Set up Homebrew paths
BREW_PREFIX_ROOT=""
if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX_ROOT=$(brew --prefix)
  export PKG_CONFIG_PATH="${BREW_PREFIX_ROOT}/opt/opus/lib/pkgconfig:${BREW_PREFIX_ROOT}/opt/libvpx/lib/pkgconfig:${BREW_PREFIX_ROOT}/opt/libconfig/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CMAKE_PREFIX_PATH="${BREW_PREFIX_ROOT}/opt/opus:${BREW_PREFIX_ROOT}/opt/libvpx:${BREW_PREFIX_ROOT}/opt/libconfig:${CMAKE_PREFIX_PATH:-}"
fi

# Preflight checks
if [[ ! -f "$FLUTTER_APP_DIR/pubspec.yaml" ]]; then
  echo -e "${RED}Flutter app not found at ${FLUTTER_APP_DIR}${NC}"; exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo -e "${RED}Flutter is not installed or not in PATH.${NC}"
  echo "Please install Flutter SDK and ensure 'flutter' is in PATH, then re-run."
  exit 1
fi

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Toxee — DEBUG Build                 ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Build native, Flutter, bundle libs, launch once
build_native

if ! build_flutter; then
  echo -e "${RED}==> Flutter build failed! Check: $FLUTTER_BUILD_LOG${NC}"
  exit 1
fi
bundle_libs

# Build-only mode for harnesses that launch the app themselves (e.g. the
# product-screenshot pipeline tool/screenshots/capture.sh, which needs the
# MCP_BINDING/TOXEE_L3_TEST dart-defines compiled in but manages its own
# multi-instance launches via tool/mcp_test/launch_toxee_instance.sh).
if [[ "${TOXEE_BUILD_ONLY:-0}" == "1" ]]; then
  echo -e "${GREEN}==> TOXEE_BUILD_ONLY=1 — build complete, skipping launch.${NC}"
  exit 0
fi

launch_app

# Wait for app to exit (no source watching)
wait "$APP_PID" 2>/dev/null || true
APP_EXIT=$?
APP_PID=""

# Stop tail
if [[ -n "$TAIL_PID" ]] && kill -0 "$TAIL_PID" 2>/dev/null; then
  kill "$TAIL_PID" 2>/dev/null || true
  wait "$TAIL_PID" 2>/dev/null || true
  TAIL_PID=""
fi

echo ""
if [[ "$APP_EXIT" -eq 0 ]]; then
  echo -e "${GREEN}==> App exited normally (code 0).${NC}"
else
  echo -e "${RED}==> App exited with code $APP_EXIT.${NC}"
fi
exit "${APP_EXIT:-0}"
