#!/usr/bin/env bash
# Cross-platform product-screenshot pipeline — one command, four platforms.
#
#   ./tool/screenshots/capture.sh [--platforms desktop,android,ipad,ios]
#                                 [--build] [--reset] [--help]
#
# For EACH platform it launches one real toxee instance with the L3 debug
# surface (MCP_BINDING=skill + TOXEE_L3_TEST=true), resolves its Dart VM-service
# ws URI, then drives capture_product_screenshots.dart, which seeds demo data
# locally (no peer/P2P) and captures the 5 light-theme scenes:
#   c2c · group_chat · new_application · self_profile · settings
# into ./screenshot/<platform>/.
#
#   --platforms <list>  comma list of: desktop android ipad ios (default: all)
#   --build             force-rebuild each selected platform before launching
#   --reset             wipe the macOS seed root before running (desktop only)
#   --sync-site         downscale captured shots into doc/product/assets/<platform>/
#
# Targets (override via env):
#   TOXEE_SHOT_ANDROID_SERIAL   adb serial      (default: first emulator)
#   TOXEE_SHOT_IOS_UDID         iPhone simulator (default: booted iPhone, else iPhone 16 Pro)
#   TOXEE_SHOT_IPAD_UDID        iPad simulator   (default: booted iPad,  else iPad Pro 13-inch (M4))
#
# While a platform is captured, don't steal focus from the macOS window (the
# desktop scene walk owns the foreground; mobile sims render off-screen).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
SEED_ROOT="$REPO_ROOT/tool/screenshots/_seed_runtime"
OUT_ROOT="$REPO_ROOT/screenshot"
DRIVER="$REPO_ROOT/tool/screenshots/capture_product_screenshots.dart"
APP_BUNDLE="$REPO_ROOT/build/macos/Build/Products/Debug/Toxee.app"
DART_DEFINES=(--dart-define=FLUTTER_BUILD_MODE=debug --dart-define=MCP_BINDING=skill --dart-define=TOXEE_L3_TEST=true)
VM_URI_TIMEOUT="${TOXEE_SHOT_VM_URI_TIMEOUT:-180}"

SITE_ASSETS="$REPO_ROOT/doc/product/assets"
PLATFORMS="desktop,android,ipad,ios"
BUILD=0
RESET=0
SYNC_SITE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --platforms) PLATFORMS="${2:-}"; shift 2 ;;
    --platforms=*) PLATFORMS="${1#*=}"; shift ;;
    --build) BUILD=1; shift ;;
    --reset) RESET=1; shift ;;
    --sync-site) SYNC_SITE=1; shift ;;
    --help|-h) sed -n '2,30p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${GREEN}[capture]${NC} $*"; }
warn() { echo -e "${YELLOW}[capture]${NC} $*"; }
err()  { echo -e "${RED}[capture]${NC} $*" >&2; }
step() { echo -e "${CYAN}==>${NC} $*"; }

# shellcheck source=../mcp_test/_multi_instance_lib.sh
. "$MCP_DIR/_multi_instance_lib.sh"
mkdir -p "$OUT_ROOT"

# Backstop cleanup: each platform tears down its own launch on the normal path,
# but a `set -e` abort or Ctrl-C between launch and teardown would otherwise
# leak the macOS app / `flutter run` / simctl-launch process. Track launched
# pids and kill any survivors on exit.
declare -a _BG_PIDS=()
_track_pid() { [[ -n "${1:-}" ]] && _BG_PIDS+=("$1"); }
_cleanup() {
  local p
  for p in ${_BG_PIDS[@]+"${_BG_PIDS[@]}"}; do
    [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
  done
}
trap _cleanup EXIT INT TERM

# Parse the first http://127.0.0.1:PORT/TOKEN/ from a log file → ws URI, waiting
# up to <timeout>s for it to appear. Echoes the ws URI, or returns 1 on timeout.
wait_for_vm_ws() {
  local log="$1" timeout="$2" elapsed=0 http=""
  while [[ "$elapsed" -lt "$timeout" ]]; do
    http="$(grep -oE 'http://127\.0\.0\.1:[0-9]+(/[A-Za-z0-9_=-]+)?/?' "$log" 2>/dev/null | head -1 || true)"
    [[ -n "$http" ]] && break
    sleep 1; elapsed=$((elapsed + 1))
  done
  [[ -z "$http" ]] && return 1
  http="${http%/}"
  echo "${http/http:/ws:}/ws"
}

run_driver() {  # <platform> <ws-uri> [extra driver args...]
  local platform="$1" ws="$2"; shift 2
  step "driving $platform → screenshot/$platform/"
  (cd "$REPO_ROOT" && dart run "$DRIVER" \
      --platform "$platform" --ws-uri "$ws" --out "$OUT_ROOT/$platform" "$@")
}

# --sync-site: downscale a platform's captured scenes into the COMMITTED product
# assets (screenshot/ itself is gitignored). Phones are already small (kept
# native); wide shots are downscaled to keep the repo light.
sync_site() {
  local platform="$1" dst="$SITE_ASSETS/$platform" w=1024 s src
  mkdir -p "$dst"
  case "$platform" in android|ios) w=0 ;; esac
  for s in c2c group_chat new_application self_profile settings; do
    src="$OUT_ROOT/$platform/$s.png"
    [[ -f "$src" ]] || { warn "sync-site: $platform/$s.png missing — committed asset left stale"; continue; }
    if [[ "$w" -gt 0 ]]; then
      sips --resampleWidth "$w" "$src" --out "$dst/$s.png" >/dev/null 2>&1
    else
      cp "$src" "$dst/$s.png"
    fi
  done
  echo "    synced $platform ($(ls "$dst"/*.png 2>/dev/null | wc -l | tr -d ' ') assets)"
}

# ───────────────────────────── desktop (macOS) ──────────────────────────────
capture_desktop() {
  if [[ "$RESET" == "1" ]]; then
    step "reset: wiping macOS seed root + container leftovers"
    rm -rf "$SEED_ROOT/Shot"
    # The launcher keeps app-support (profile/history) under the sandbox
    # container, not the seed root — clear it too or a reset leaves stale data.
    rm -rf "$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/multi_instance/Shot"
  fi
  build_macos() { (cd "$REPO_ROOT" && MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh "$@"); }
  if [[ "$BUILD" == "1" || ! -x "$APP_BUNDLE/Contents/MacOS/Toxee" ]]; then
    step "building macOS debug app (L3 surface)"
    build_macos
  fi
  # Self-heal the Xcode debug-dylib split: the main stub links
  # @rpath/Toxee.debug.dylib; an incremental build can leave the stub stale
  # while that dylib is missing, so dyld aborts at launch (direct-exec, not via
  # `open`). Detect it and force ONE clean rebuild that regenerates the dylib.
  local exe="$APP_BUNDLE/Contents/MacOS/Toxee"
  if [[ -x "$exe" ]] \
     && otool -L "$exe" 2>/dev/null | grep -q 'Toxee\.debug\.dylib' \
     && [[ ! -f "$APP_BUNDLE/Contents/MacOS/Toxee.debug.dylib" ]]; then
    warn "macOS debug-dylib missing from bundle — forcing a clean rebuild"
    build_macos --clean
  fi
  step "launching macOS instance"
  TOXEE_MULTI_RUNTIME_ROOT="$SEED_ROOT" TOXEE_APP_BUNDLE="$APP_BUNDLE" \
    "$MCP_DIR/launch_toxee_instance.sh" Shot
  local json="$SEED_ROOT/Shot/instance.json" ws pid
  ws="$(jq -r '.ws_uri // empty' "$json")"
  pid="$(jq -r '.pid // empty' "$json")"
  _track_pid "$pid"
  [[ -z "$ws" ]] && { err "desktop: no ws_uri in $json"; return 1; }
  local rc=0
  run_driver desktop "$ws" --pid "$pid" || rc=$?
  [[ -n "$pid" ]] && _mi_stop_with_grace "$pid" 5 || true
  return $rc
}

# ───────────────────────────── android ──────────────────────────────────────
capture_android() {
  local serial="${TOXEE_SHOT_ANDROID_SERIAL:-}"
  # Auto-default to an EMULATOR only — this run does `pm clear com.toxee.app`,
  # so never auto-target (and wipe) a connected physical device. Targeting a
  # real device is opt-in via TOXEE_SHOT_ANDROID_SERIAL.
  [[ -z "$serial" ]] && serial="$(adb devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/{print $1; exit}')"
  [[ -z "$serial" ]] && { err "android: no emulator running (start one, or set TOXEE_SHOT_ANDROID_SERIAL to a device you're OK clearing — the run does \`pm clear\`)"; return 1; }
  if ! find "$REPO_ROOT/android/app/src/main/jniLibs" -name libtim2tox_ffi.so 2>/dev/null | grep -q .; then
    step "android: building FFI .so (tool/build_android_ffi.sh)"
    (cd "$REPO_ROOT" && bash tool/build_android_ffi.sh)
  fi
  # Build the debug APK with the L3 surface, then install + launch via adb and
  # read the VM-service URI from LOGCAT. (Driving `flutter run` headlessly is
  # unreliable: it block-buffers its stdout to a pipe, and under a pty it stops
  # on SIGTTIN when backgrounded. `am start` + logcat + `adb forward` is
  # deterministic.)
  step "android: building debug APK (L3 surface)"
  (cd "$REPO_ROOT" && flutter build apk --debug "${DART_DEFINES[@]}") || {
    err "android: APK build failed"; return 1; }
  local apk="$REPO_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
  [[ -f "$apk" ]] || { err "android: APK missing ($apk)"; return 1; }
  step "android: install + launch on $serial"
  adb -s "$serial" install -r "$apk" >/dev/null 2>&1 || { err "android: install failed"; return 1; }
  adb -s "$serial" shell am force-stop com.toxee.app >/dev/null 2>&1 || true
  # Clear app data for a deterministic fresh-account seed each run (the mobile
  # equivalent of the desktop --reset; avoids stale-account / auto-login races).
  adb -s "$serial" shell pm clear com.toxee.app >/dev/null 2>&1 || true
  local log="$REPO_ROOT/build/screenshot_android_logcat.log"
  mkdir -p "$(dirname "$log")"; : >"$log"
  adb -s "$serial" logcat -c >/dev/null 2>&1 || true
  adb -s "$serial" logcat >>"$log" 2>&1 &
  local lc=$!; _track_pid "$lc"
  adb -s "$serial" shell am start -n com.toxee.app/.MainActivity >/dev/null 2>&1 || true
  local rc=0 ws="" port=""
  if ws="$(wait_for_vm_ws "$log" "$VM_URI_TIMEOUT")"; then
    # The URI port is the emulator's internal localhost port — forward it so the
    # host-side driver can reach it.
    port="$(printf '%s' "$ws" | sed -nE 's#.*:([0-9]+)/.*#\1#p')"
    [[ -n "$port" ]] && adb -s "$serial" forward "tcp:$port" "tcp:$port" >/dev/null 2>&1 || true
    sleep 2  # let the forward settle before the driver connects
    run_driver android "$ws" || rc=$?
    [[ -n "$port" ]] && adb -s "$serial" forward --remove "tcp:$port" >/dev/null 2>&1 || true
  else
    err "android: VM URI not seen in ${VM_URI_TIMEOUT}s (see $log)"; rc=1
  fi
  kill "$lc" 2>/dev/null || true; wait "$lc" 2>/dev/null || true
  adb -s "$serial" shell am force-stop com.toxee.app >/dev/null 2>&1 || true
  return $rc
}

# ───────────────────────────── iOS / iPad simulators ────────────────────────
IOS_APP_BUILT=0
ios_build_and_inject() {
  [[ "$IOS_APP_BUILT" == "1" && "$BUILD" != "1" ]] && return 0
  # iOS-SIMULATOR artifacts only — NOT build/ffi/libtim2tox_ffi.dylib, which is
  # the macOS host dylib and cannot load on the simulator. The loader
  # (_openIOS) prefers Frameworks/tim2tox_ffi.framework/tim2tox_ffi, with
  # Frameworks/libtim2tox_ffi.dylib (build/ios-sim/) as the fallback.
  local fw="$REPO_ROOT/third_party/tim2tox/build/ios/tim2tox_ffi.framework"
  local dylib="$REPO_ROOT/third_party/tim2tox/build/ios-sim/libtim2tox_ffi.dylib"
  if [[ ! -d "$fw" ]]; then
    step "ios: building simulator FFI (tool/build_ios_sim_ffi.sh)"
    (cd "$REPO_ROOT" && bash tool/build_ios_sim_ffi.sh)
  fi
  step "ios: flutter build ios --simulator --debug (L3 surface)"
  (cd "$REPO_ROOT" && flutter build ios --simulator --debug "${DART_DEFINES[@]}")
  local appdir="$REPO_ROOT/build/ios/iphonesimulator/Runner.app"
  [[ -d "$appdir" ]] || { err "ios: built app missing: $appdir"; return 1; }
  mkdir -p "$appdir/Frameworks"
  if [[ -d "$fw" ]]; then
    rm -rf "$appdir/Frameworks/tim2tox_ffi.framework"
    cp -R "$fw" "$appdir/Frameworks/"
    codesign --force --sign - "$appdir/Frameworks/tim2tox_ffi.framework" 2>/dev/null || true
  fi
  if [[ -f "$dylib" ]]; then
    cp "$dylib" "$appdir/Frameworks/libtim2tox_ffi.dylib"
    codesign --force --sign - "$appdir/Frameworks/libtim2tox_ffi.dylib" 2>/dev/null || true
  fi
  IOS_APP_BUILT=1
}

# name|udid|state rows for available simulators (portable; no gawk).
sim_rows() {
  xcrun simctl list devices available \
    | sed -nE 's/^[[:space:]]*(.+[^ ])[[:space:]]+\(([0-9A-Fa-f-]{36})\)[[:space:]]+\((Booted|Shutdown)\).*/\1|\2|\3/p'
}

# Boot (if needed) + echo a simulator UDID. <kind: phone|tablet> <want-udid> <default-name>
resolve_sim() {
  local kind="$1" want="$2" default_name="$3" udid="" name u state
  if [[ -n "$want" ]]; then
    udid="$want"
  else
    while IFS='|' read -r name u state; do
      [[ -z "$u" ]] && continue
      if [[ "$name" == *iPad* ]]; then [[ "$kind" != "tablet" ]] && continue
      else [[ "$kind" != "phone" ]] && continue; fi
      if [[ "$state" == "Booted" ]]; then udid="$u"; break; fi
    done < <(sim_rows)
    if [[ -z "$udid" ]]; then
      udid="$(sim_rows | grep -F "$default_name|" | head -1 | cut -d'|' -f2)"
    fi
  fi
  [[ -z "$udid" ]] && return 1
  open -a Simulator >/dev/null 2>&1 || true
  if ! xcrun simctl list devices | grep "$udid" | grep -q Booted; then
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  fi
  echo "$udid"
}

capture_ios_like() {  # <platform: ios|ipad> <kind: phone|tablet> <want-udid> <default-name>
  local platform="$1" kind="$2" want="$3" default_name="$4"
  ios_build_and_inject || return 1
  local appdir="$REPO_ROOT/build/ios/iphonesimulator/Runner.app" bundle_id udid
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$appdir/Info.plist" 2>/dev/null || echo com.toxee.app)"
  udid="$(resolve_sim "$kind" "$want" "$default_name")" \
    || { err "$platform: no $kind simulator (set its UDID env or boot one)"; return 1; }
  step "$platform: install + launch on sim $udid"
  # Uninstall first for a deterministic fresh-account seed each run (the iOS
  # equivalent of the desktop --reset / Android `pm clear`).
  xcrun simctl uninstall "$udid" "$bundle_id" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$appdir"
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  # The iOS engine logs the VM-service URI to os_log (not the app's stdout), so
  # stream the unified log filtered for it, THEN launch the app. The simulator
  # shares the host's localhost, so the captured 127.0.0.1:PORT (with its auth
  # token) is reachable directly — no port-forward needed (unlike Android).
  local log="$REPO_ROOT/build/screenshot_${platform}_run.log"
  mkdir -p "$(dirname "$log")"; : >"$log"
  ( xcrun simctl spawn "$udid" log stream --style compact \
      --predicate 'eventMessage CONTAINS "Dart VM service"' >>"$log" 2>&1 ) &
  local slog=$! rc=0 ws=""
  _track_pid "$slog"
  sleep 2  # let the log stream attach before the app logs its URI
  xcrun simctl launch "$udid" "$bundle_id" >/dev/null 2>&1 || true
  if ws="$(wait_for_vm_ws "$log" "$VM_URI_TIMEOUT")"; then
    run_driver "$platform" "$ws" || rc=$?
  else
    err "$platform: VM URI not seen in ${VM_URI_TIMEOUT}s (see $log)"; rc=1
  fi
  kill "$slog" 2>/dev/null || true; wait "$slog" 2>/dev/null || true
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  return $rc
}

# ───────────────────────────── main ─────────────────────────────────────────
declare -a OK=() FAIL=()
IFS=',' read -r -a SELECTED <<< "$PLATFORMS"
for platform in "${SELECTED[@]}"; do
  platform="$(echo "$platform" | tr -d ' ')"
  [[ -z "$platform" ]] && continue
  echo ""
  info "════════ $platform ════════"
  rc=0
  case "$platform" in
    desktop) capture_desktop || rc=$? ;;
    android) capture_android || rc=$? ;;
    ios)     capture_ios_like ios phone "${TOXEE_SHOT_IOS_UDID:-}" "iPhone 16 Pro" || rc=$? ;;
    ipad)    capture_ios_like ipad tablet "${TOXEE_SHOT_IPAD_UDID:-}" "iPad Pro 13-inch (M4)" || rc=$? ;;
    *) err "unknown platform: $platform"; rc=64 ;;
  esac
  if [[ "$rc" == "0" ]]; then OK+=("$platform"); else FAIL+=("$platform"); fi
done

echo ""
info "════════ done ════════"
[[ ${#OK[@]}   -gt 0 ]] && info "captured: ${OK[*]} → $OUT_ROOT/<platform>/"
if [[ "$SYNC_SITE" == "1" && ${#OK[@]} -gt 0 ]]; then
  step "syncing curated assets → $SITE_ASSETS/<platform>/"
  for p in ${OK[@]+"${OK[@]}"}; do sync_site "$p"; done
fi
[[ ${#FAIL[@]} -gt 0 ]] && { err "failed: ${FAIL[*]}"; exit 1; }
echo ""
info "✅ screenshots in $OUT_ROOT for: ${OK[*]}"
