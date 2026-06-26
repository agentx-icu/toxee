#!/usr/bin/env bash
# Launch one iOS Simulator Toxee instance for real-App UI automation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_IOS_RUNTIME_ROOT:-$MCP_DIR/.ios_runtime}"
INSTANCE_NAME="${1:-A}"
DEVICE_TYPE="${TOXEE_IOS_DEVICE_TYPE:-phone}"
SIMULATOR_ID="${TOXEE_IOS_SIMULATOR_ID:-}"
BUILD_MODE="${TOXEE_IOS_BUILD_MODE:-debug}"
VM_URI_TIMEOUT_SECS="${TOXEE_IOS_VM_URI_TIMEOUT_SECS:-90}"
INSTANCE_JSON_WRITER="$MCP_DIR/_write_toxee_instance_json.py"
IOS_PBXPROJ="$REPO_ROOT/ios/Runner.xcodeproj/project.pbxproj"

INSTANCE_DIR="$RUNTIME_ROOT/$INSTANCE_NAME"
BUILD_DIR="$INSTANCE_DIR/build"
STDIO_LOG="$BUILD_DIR/toxee_ios_stdio.log"
VM_URI_FILE="$BUILD_DIR/vm_service_uri.txt"
JSON_FILE="$INSTANCE_DIR/instance.json"
APP_SUPPORT_DIR="$INSTANCE_DIR/app_support"
APP_SUPPORT_LOG="$APP_SUPPORT_DIR/flutter_client.log"
DEFAULT_SUPPORT_LOG="$APP_SUPPORT_LOG"

mkdir -p "$BUILD_DIR" "$APP_SUPPORT_DIR"
: >"$STDIO_LOG"
rm -f "$VM_URI_FILE" "$JSON_FILE"

if [[ -z "$SIMULATOR_ID" ]]; then
  while IFS= read -r row; do
    IFS='|' read -r name udid state <<<"$row"
    [[ -z "$udid" ]] && continue
    if [[ "$DEVICE_TYPE" == "any" || ("$DEVICE_TYPE" == "tablet" && "$name" == *iPad*) || ("$DEVICE_TYPE" == "phone" && "$name" != *iPad*) ]]; then
      SIMULATOR_ID="$udid"
      break
    fi
  done < <(xcrun simctl list devices available \
    | sed -nE 's/^[[:space:]]*([^()]+)[[:space:]]+\(([0-9A-F-]{36})\)[[:space:]]+\((Booted|Shutdown)\).*/\1|\2|\3/p')
fi

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "launch_toxee_ios_instance.sh: no iOS simulator matched device type $DEVICE_TYPE" >&2
  exit 66
fi

# Belt-and-suspenders: disable macOS App Nap for the Simulator.
defaults write com.apple.iphonesimulator NSAppSleepDisabled -bool YES >/dev/null 2>&1 || true
# Simulator foregrounding policy:
#   default  -> `open -g`: attach the GUI WITHOUT taking focus / topping the
#               window (honors the user directive 不抢宿主机鼠标、不置顶模拟器窗口).
#               Fine for short interactions, BUT iOS reclaims a backgrounded sim
#               app after ~2-3 min, which kills any multi-minute sweep mid-run.
#               App Nap disable + caffeinate do NOT prevent this — it is the iOS
#               app lifecycle (a backgrounded Simulator backgrounds its apps),
#               not macOS App Nap.
#   KEEP_FRONT -> `open -a`: keep the Simulator frontmost so BOTH sim apps stay
#               alive for the whole run. Required to drive a full sweep to green.
#               Real-UI driving is still VM-service only (no per-action osascript
#               re-topping or mouse-steal), so the window is brought up ONCE here
#               and never grabbed again during the run.
if [[ -n "${TOXEE_IOS_KEEP_SIMULATOR_FRONT:-}" ]]; then
  open -a Simulator >/dev/null 2>&1 || true
else
  open -g -a Simulator >/dev/null 2>&1 || true
fi
xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null 2>&1 || true

BUNDLE_ID="$(awk -F'=' '
  /PRODUCT_BUNDLE_IDENTIFIER = / && $0 !~ /RunnerTests/ {
    gsub(/[ ;]/, "", $2);
    print $2;
    exit
  }' "$IOS_PBXPROJ")"
if [[ -n "$BUNDLE_ID" ]]; then
  xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

MCP_BINDING="${MCP_BINDING:-skill}" TOXEE_L3_TEST="${TOXEE_L3_TEST:-true}" \
  TOXEE_APP_SUPPORT_DIR="$APP_SUPPORT_DIR" \
  TOXEE_LOG_DIR="$BUILD_DIR" \
  TOXEE_SHARED_PREFS_PREFIX="toxee_ios_${INSTANCE_NAME}." \
  TOXEE_TCCF_GLOBAL_SUBDIR="ios/$INSTANCE_NAME/tccfglobal" \
  TOXEE_DISABLE_NOTIFICATION_PERMISSION_PROMPT="${TOXEE_DISABLE_NOTIFICATION_PERMISSION_PROMPT:-true}" \
  "$REPO_ROOT/run_toxee_ios.sh" --action deploy --mode "$BUILD_MODE" \
  --simulator-id "$SIMULATOR_ID" >>"$STDIO_LOG" 2>&1

# LAUNCH_METHOD:
#   flutter (default) — `flutter run --machine`. Simple, but its resident debug
#     connection to the Simulator is FRAGILE under sustained real-UI driving: it
#     eventually emits "Lost connection to device" + app.stop, tearing down the
#     app's Dart VM service (the Runner process survives but its port goes
#     refused), which strands any direct-VM-service driver mid-sweep.
#   simctl — launch the (already built+installed) app directly via
#     `xcrun simctl launch`. There is NO flutter daemon to lose connection, so
#     the VM service stays up for the whole run. The VM service URI (with auth
#     token) is read from the device log stream, where the Dart VM announces it.
LAUNCH_METHOD="${TOXEE_IOS_LAUNCH_METHOD:-flutter}"
vm_uri=""
if [[ "$LAUNCH_METHOD" == "simctl" ]]; then
  if [[ -z "$BUNDLE_ID" ]]; then
    echo "launch_toxee_ios_instance.sh: simctl launch needs a bundle id" >&2
    exit 1
  fi
  STREAM_LOG="$BUILD_DIR/devlog_stream.txt"
  : >"$STREAM_LOG"
  xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  # Stream the device log BEFORE launch so the VM-service announce isn't missed.
  xcrun simctl spawn "$SIMULATOR_ID" log stream --style compact \
    --predicate 'eventMessage CONTAINS "Dart VM service is listening"' \
    >"$STREAM_LOG" 2>>"$STDIO_LOG" &
  STREAM_PID=$!
  disown "$STREAM_PID" 2>/dev/null || true
  sleep 2
  # Pass an optional native env var into the launched app (SIMCTL_CHILD_<VAR> →
  # <VAR> in the app's environment, read by getenv in C++). Used to make this
  # sim act as a Tox TCP relay (TOX_TCP_RELAY_PORT) so a sim↔sim pair can connect
  # without a macOS peer.
  if [[ -n "${TOXEE_IOS_TCP_RELAY_PORT:-}" ]]; then
    export SIMCTL_CHILD_TOX_TCP_RELAY_PORT="$TOXEE_IOS_TCP_RELAY_PORT"
  fi
  launch_out="$(xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" 2>>"$STDIO_LOG")"
  echo "$launch_out" >>"$STDIO_LOG"
  LAUNCH_PID="$(printf '%s' "$launch_out" | grep -oE '[0-9]+$' | head -1)"
  elapsed=0
  while [[ "$elapsed" -lt "$VM_URI_TIMEOUT_SECS" ]]; do
    vm_uri="$(grep -oE 'http://127\.0\.0\.1:[0-9]+(/[A-Za-z0-9_=-]+)?/?' "$STREAM_LOG" 2>/dev/null | head -1 || true)"
    [[ -n "$vm_uri" ]] && break
    sleep 1
    elapsed=$((elapsed + 1))
  done
  kill "$STREAM_PID" 2>/dev/null || true
  if [[ -z "$vm_uri" ]]; then
    echo "launch_toxee_ios_instance.sh: timed out waiting for VM URI (simctl); see $STREAM_LOG" >&2
    exit 1
  fi
else
  nohup bash -c '
    cd "$1"
    export TOXEE_APP_SUPPORT_DIR="$2"
    export TOXEE_LOG_DIR="$3"
    exec flutter run -d "$4" --debug --machine \
      --dart-define=FLUTTER_BUILD_MODE=debug \
      --dart-define=MCP_BINDING=skill \
      --dart-define=TOXEE_L3_TEST=true \
      --dart-define=TOXEE_APP_SUPPORT_DIR="$5" \
      --dart-define=TOXEE_LOG_DIR="$6" \
      --dart-define=TOXEE_SHARED_PREFS_PREFIX="$7" \
      --dart-define=TOXEE_TCCF_GLOBAL_SUBDIR="$8" \
      --dart-define=TOXEE_DISABLE_NOTIFICATION_PERMISSION_PROMPT="$9" \
      --use-application-binary build/ios/iphonesimulator/Runner.app
  ' bash "$REPO_ROOT" "$APP_SUPPORT_DIR" "$BUILD_DIR" "$SIMULATOR_ID" \
      "$APP_SUPPORT_DIR" "$BUILD_DIR" "toxee_ios_${INSTANCE_NAME}." \
      "ios/$INSTANCE_NAME/tccfglobal" \
      "${TOXEE_DISABLE_NOTIFICATION_PERMISSION_PROMPT:-true}" \
      >>"$STDIO_LOG" 2>&1 </dev/null &
  LAUNCH_PID=$!
  disown "$LAUNCH_PID" 2>/dev/null || true

  elapsed=0
  while [[ "$elapsed" -lt "$VM_URI_TIMEOUT_SECS" ]]; do
    if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
      echo "launch_toxee_ios_instance.sh: flutter run exited before VM URI; see $STDIO_LOG" >&2
      exit 1
    fi
    vm_uri="$(grep -oE 'http://127\.0\.0\.1:[0-9]+(/[A-Za-z0-9_=-]+)?/?' "$STDIO_LOG" 2>/dev/null | head -1 || true)"
    [[ -n "$vm_uri" ]] && break
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [[ -z "$vm_uri" ]]; then
    echo "launch_toxee_ios_instance.sh: timed out waiting for VM URI; see $STDIO_LOG" >&2
    exit 1
  fi
fi

vm_uri="${vm_uri%/}"
ws_uri="${vm_uri/http:/ws:}/ws"
printf '%s\n' "$ws_uri" >"$VM_URI_FILE"
start_time="$(ps -p "$LAUNCH_PID" -o lstart= | sed 's/^ *//')"
cmdline="$(ps -p "$LAUNCH_PID" -o args= | sed 's/^ *//')"

python3 "$INSTANCE_JSON_WRITER" \
  --json-file "$JSON_FILE" \
  --instance-name "$INSTANCE_NAME" \
  --pid "$LAUNCH_PID" \
  --start-time "${start_time:-unknown}" \
  --cmdline "${cmdline:-flutter run ios}" \
  --home-override-dir "$INSTANCE_DIR/home" \
  --app-support-override-dir "$APP_SUPPORT_DIR" \
  --shared-prefs-prefix "toxee_ios_${INSTANCE_NAME}." \
  --tccf-global-subdir "ios/$INSTANCE_NAME/tccfglobal" \
  --build-dir "$BUILD_DIR" \
  --stdio-log "$STDIO_LOG" \
  --vm-uri-file "$VM_URI_FILE" \
  --vm-uri "$vm_uri" \
  --ws-uri "$ws_uri" \
  --app-support-log "$APP_SUPPORT_LOG" \
  --default-support-log "$DEFAULT_SUPPORT_LOG"

echo "OK: launched iOS $INSTANCE_NAME pid=$LAUNCH_PID ws_uri=$ws_uri simulator=$SIMULATOR_ID"
echo "json: $JSON_FILE"
