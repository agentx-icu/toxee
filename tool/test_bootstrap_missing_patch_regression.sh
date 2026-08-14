#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

REAL_DART="$(command -v dart)"
REAL_CP="$(command -v cp)"
REAL_GIT="$(command -v git)"
REAL_MV="$(command -v mv)"
REAL_RM="$(command -v rm)"
SHIM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/toxee-bootstrap-regression.XXXXXX")"
SERIES_FILES=()
SERIES_SNAPSHOTS=()
ACTIVE_SERIES=""

restore_series_snapshots() {
  local index
  local restore_status=0
  local -a backup_residue
  if [ "${#SERIES_SNAPSHOTS[@]}" -eq 0 ]; then
    return 0
  fi
  for index in "${!SERIES_FILES[@]}"; do
    "$REAL_CP" -p "${SERIES_SNAPSHOTS[$index]}" "${SERIES_FILES[$index]}" || restore_status=1
  done
  if [ "$restore_status" -eq 0 ]; then
    shopt -s nullglob
    backup_residue=(third_party/tim2tox/patches/tencent_cloud_chat_sdk/*/series.bootstrap-smoke.*)
    shopt -u nullglob
    if [ "${#backup_residue[@]}" -ne 0 ]; then
      "$REAL_RM" -f "${backup_residue[@]}"
    fi
  fi
  return "$restore_status"
}

cleanup() {
  local exit_status=$?
  local restore_status=0
  trap - EXIT HUP INT TERM
  set +e
  restore_series_snapshots
  restore_status=$?
  if [ "$restore_status" -eq 0 ]; then
    "$REAL_RM" -rf "$SHIM_DIR"
  else
    echo "FAIL: regression cleanup could not restore patch-series snapshots in $SHIM_DIR" >&2
    exit_status=1
  fi
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

export BOOTSTRAP_REGRESSION_REAL_DART="$REAL_DART"
export BOOTSTRAP_REGRESSION_REAL_CP="$REAL_CP"
export BOOTSTRAP_REGRESSION_REAL_GIT="$REAL_GIT"
export BOOTSTRAP_REGRESSION_REAL_MV="$REAL_MV"
export BOOTSTRAP_REGRESSION_REAL_RM="$REAL_RM"
export BOOTSTRAP_REGRESSION_NETWORK_ATTEMPT="$SHIM_DIR/network-attempted"
export BOOTSTRAP_REGRESSION_DESTRUCTIVE_ATTEMPT="$SHIM_DIR/destructive-attempted"
export GIT_MASTER=1

cat >"$SHIM_DIR/dart" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = "--offline-check-only" ]; then
    if [ "${BOOTSTRAP_REGRESSION_MODE:-}" = "offline-propagation" ]; then
      echo "bootstrap-regression: injected offline failure" >&2
      exit 92
    fi
    for series in third_party/tim2tox/patches/tencent_cloud_chat_sdk/*/series; do
      if [[ "$(<"$series")" == *"bootstrap-smoke-missing-patch-"* ]]; then
        if [ "${BOOTSTRAP_REGRESSION_MODE:-}" = "unrelated-failure" ]; then
          echo "bootstrap-regression: injected unrelated offline failure" >&2
          exit 89
        fi
        if [ "${BOOTSTRAP_REGRESSION_MODE:-}" = "signal" ]; then
          echo "bootstrap-regression: terminating smoke test while series is perturbed" >&2
          kill -TERM "$PPID"
          exit 143
        fi
      fi
    done
    exec "$BOOTSTRAP_REGRESSION_REAL_DART" "$@"
  fi
done
: >"$BOOTSTRAP_REGRESSION_NETWORK_ATTEMPT"
echo "bootstrap-regression: refused network-capable dart invocation: dart $*" >&2
exit 86
EOF

cat >"$SHIM_DIR/git" <<'EOF'
#!/usr/bin/env bash
if [ "${GIT_MASTER:-}" != "1" ]; then
  echo "bootstrap-regression: child git call missing GIT_MASTER=1" >&2
  exit 87
fi
if [ "${BOOTSTRAP_REGRESSION_MODE:-}" = "normal-integrity" ]; then
  case "$*" in
    "submodule sync --recursive"|\
    "submodule update --init --recursive"|\
    "-C third_party/chat-uikit-flutter fetch origin v2"|\
    "-C third_party/chat-uikit-flutter checkout -B v2 FETCH_HEAD")
      exit 0
      ;;
  esac
fi
case " $* " in
  *" submodule "*|*" clone "*|*" fetch "*|*" pull "*|*" push "*|*" checkout "*|*" switch ")
    : >"$BOOTSTRAP_REGRESSION_DESTRUCTIVE_ATTEMPT"
    echo "bootstrap-regression: refused mutating or remote git invocation during missing-patch test: git $*" >&2
    exit 88
    ;;
esac
exec "$BOOTSTRAP_REGRESSION_REAL_GIT" "$@"
EOF

cat >"$SHIM_DIR/cp" <<'EOF'
#!/usr/bin/env bash
if [ "${BOOTSTRAP_REGRESSION_MODE:-}" = "copy-failure" ]; then
  destination="${!#}"
  case "$destination" in
    */series.bootstrap-smoke.*)
      echo "bootstrap-regression: injected patch-series backup copy failure" >&2
      exit 91
      ;;
  esac
fi
exec "$BOOTSTRAP_REGRESSION_REAL_CP" "$@"
EOF

cat >"$SHIM_DIR/rm" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    third_party/tencent_cloud_chat_sdk|pubspec_overrides.yaml|third_party/tim2tox|third_party/chat-uikit-flutter)
      : >"$BOOTSTRAP_REGRESSION_DESTRUCTIVE_ATTEMPT"
      echo "bootstrap-regression: refused destructive cleanup before missing-patch test: rm $*" >&2
      exit 93
      ;;
  esac
done
exec "$BOOTSTRAP_REGRESSION_REAL_RM" "$@"
EOF

cat >"$SHIM_DIR/mv" <<'EOF'
#!/usr/bin/env bash
if [ "${BOOTSTRAP_REGRESSION_MODE:-}" = "restore-failure" ]; then
  for arg in "$@"; do
    case "$arg" in
      */series.bootstrap-smoke.*)
        echo "bootstrap-regression: injected patch-series restore mv failure" >&2
        exit 90
        ;;
    esac
  done
fi
exec "$BOOTSTRAP_REGRESSION_REAL_MV" "$@"
EOF

chmod +x "$SHIM_DIR/cp" "$SHIM_DIR/dart" "$SHIM_DIR/git" "$SHIM_DIR/mv" "$SHIM_DIR/rm"

shopt -s nullglob
SERIES_FILES=(third_party/tim2tox/patches/tencent_cloud_chat_sdk/*/series)
shopt -u nullglob
if [ "${#SERIES_FILES[@]}" -eq 0 ]; then
  echo "FAIL: no patch series available for regression test" >&2
  exit 1
fi
for index in "${!SERIES_FILES[@]}"; do
  snapshot="$SHIM_DIR/series-$index.snapshot"
  "$REAL_CP" -p "${SERIES_FILES[$index]}" "$snapshot"
  SERIES_SNAPSHOTS+=("$snapshot")
done
while IFS= read -r line; do
  if [[ "$line" =~ \"version\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    ACTIVE_SERIES="third_party/tim2tox/patches/tencent_cloud_chat_sdk/${BASH_REMATCH[1]}/series"
    break
  fi
done <third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json
if [ -z "$ACTIVE_SERIES" ] || [ ! -f "$ACTIVE_SERIES" ]; then
  echo "FAIL: could not resolve the active patch series from the SDK lock" >&2
  exit 1
fi
SERIES_BEFORE="$(cksum "${SERIES_FILES[@]}")"

set +e
COPY_FAILURE_OUTPUT="$(BOOTSTRAP_REGRESSION_MODE=copy-failure PATH="$SHIM_DIR:$PATH" \
  bash tool/test_bootstrap_smoke.sh --test-missing-patch 2>&1)"
COPY_FAILURE_STATUS=$?
set -e
printf '%s\n' "$COPY_FAILURE_OUTPUT"
if [ "$COPY_FAILURE_STATUS" -ne 91 ]; then
  echo "FAIL: backup copy failure exited $COPY_FAILURE_STATUS instead of 91" >&2
  exit 1
fi
if [[ "$COPY_FAILURE_OUTPUT" != *"injected patch-series backup copy failure"* ]]; then
  echo "FAIL: missing-patch smoke test did not expose the injected backup copy failure" >&2
  exit 1
fi
if [ "$(cksum "${SERIES_FILES[@]}")" != "$SERIES_BEFORE" ]; then
  echo "FAIL: backup copy failure changed a patch series" >&2
  exit 1
fi
shopt -s nullglob
COPY_FAILURE_RESIDUE=(third_party/tim2tox/patches/tencent_cloud_chat_sdk/*/series.bootstrap-smoke.*)
shopt -u nullglob
if [ "${#COPY_FAILURE_RESIDUE[@]}" -ne 0 ]; then
  echo "FAIL: backup copy failure left residue: ${COPY_FAILURE_RESIDUE[*]}" >&2
  exit 1
fi

set +e
OFFLINE_FAILURE_OUTPUT="$(BOOTSTRAP_REGRESSION_MODE=offline-propagation PATH="$SHIM_DIR:$PATH" \
  bash tool/test_bootstrap_smoke.sh --offline-check-only 2>&1)"
OFFLINE_FAILURE_STATUS=$?
set -e
printf '%s\n' "$OFFLINE_FAILURE_OUTPUT"
if [ "$OFFLINE_FAILURE_STATUS" -ne 92 ]; then
  echo "FAIL: offline smoke exited $OFFLINE_FAILURE_STATUS instead of 92" >&2
  exit 1
fi
if [[ "$OFFLINE_FAILURE_OUTPUT" != *"injected offline failure"* ]]; then
  echo "FAIL: offline smoke did not propagate the injected failure diagnostic" >&2
  exit 1
fi
if [ -f "$BOOTSTRAP_REGRESSION_DESTRUCTIVE_ATTEMPT" ]; then
  echo "FAIL: offline smoke attempted a destructive command" >&2
  exit 1
fi
if [ -f "$BOOTSTRAP_REGRESSION_NETWORK_ATTEMPT" ]; then
  echo "FAIL: offline smoke attempted a network-capable bootstrap" >&2
  exit 1
fi
if [ "$(cksum "${SERIES_FILES[@]}")" != "$SERIES_BEFORE" ]; then
  echo "FAIL: offline smoke changed a patch series" >&2
  exit 1
fi

MISSING_SERIES_BACKUP="$SHIM_DIR/active-series.missing"
"$REAL_MV" "$ACTIVE_SERIES" "$MISSING_SERIES_BACKUP"
"$REAL_RM" -f "$BOOTSTRAP_REGRESSION_NETWORK_ATTEMPT" "$BOOTSTRAP_REGRESSION_DESTRUCTIVE_ATTEMPT"
set +e
MISSING_SERIES_OFFLINE_OUTPUT="$(PATH="$SHIM_DIR:$PATH" \
  bash tool/test_bootstrap_smoke.sh --offline-check-only 2>&1)"
MISSING_SERIES_OFFLINE_STATUS=$?
MISSING_SERIES_NORMAL_OUTPUT="$(BOOTSTRAP_REGRESSION_MODE=normal-integrity PATH="$SHIM_DIR:$PATH" \
  "$REAL_DART" run tool/bootstrap_deps.dart 2>&1)"
MISSING_SERIES_NORMAL_STATUS=$?
"$REAL_MV" "$MISSING_SERIES_BACKUP" "$ACTIVE_SERIES"
MISSING_SERIES_RESTORE_STATUS=$?
set -e
printf '%s\n' "$MISSING_SERIES_OFFLINE_OUTPUT"
printf '%s\n' "$MISSING_SERIES_NORMAL_OUTPUT"
if [ "$MISSING_SERIES_RESTORE_STATUS" -ne 0 ]; then
  echo "FAIL: could not restore the active series after the missing-series checks" >&2
  exit 1
fi
EXPECTED_MISSING_OFFLINE="bootstrap_deps: offline-check: patch series is missing while vendor_state.patches_sha256 records expected patches"
EXPECTED_MISSING_NORMAL="bootstrap_deps: patch series is missing while vendor_state.patches_sha256 records expected patches"
EXPECTED_EMPTY_NORMAL="bootstrap_deps: patch series is empty or comment-only; refusing to treat it as valid"
EXPECTED_EMPTY_OFFLINE="bootstrap_deps: offline-check: patch series is empty or comment-only; refusing to treat it as valid"
if [ "$MISSING_SERIES_OFFLINE_STATUS" -eq 0 ] || [[ "$MISSING_SERIES_OFFLINE_OUTPUT" != *"$EXPECTED_MISSING_OFFLINE"* ]]; then
  echo "FAIL: offline bootstrap did not reject a missing expected patch series" >&2
  exit 1
fi
if [ "$MISSING_SERIES_NORMAL_STATUS" -eq 0 ] || [[ "$MISSING_SERIES_NORMAL_OUTPUT" != *"$EXPECTED_MISSING_NORMAL"* ]]; then
  echo "FAIL: normal bootstrap did not fail closed for a missing expected patch series" >&2
  exit 1
fi
if [[ "$MISSING_SERIES_NORMAL_OUTPUT" == *"Bootstrap complete."* ]] || \
  [[ "$MISSING_SERIES_NORMAL_OUTPUT" == *"Downloading tencent_cloud_chat_sdk"* ]]; then
  echo "FAIL: normal bootstrap continued after detecting a missing expected patch series" >&2
  exit 1
fi
if [ -f "$BOOTSTRAP_REGRESSION_NETWORK_ATTEMPT" ] || \
  [ -f "$BOOTSTRAP_REGRESSION_DESTRUCTIVE_ATTEMPT" ]; then
  echo "FAIL: missing-series integrity checks attempted network or destructive setup" >&2
  exit 1
fi
if [ "$(cksum "${SERIES_FILES[@]}")" != "$SERIES_BEFORE" ]; then
  echo "FAIL: missing-series integrity checks did not restore every patch series" >&2
  exit 1
fi

EMPTY_SERIES_BACKUP="$SHIM_DIR/active-series.empty"
"$REAL_MV" "$ACTIVE_SERIES" "$EMPTY_SERIES_BACKUP"

run_empty_series_check() {
  local series_contents=$1
  local expected_output=$2
  local expected_status=$3
  local run_label=$4
  local output
  local status

  printf '%s' "$series_contents" >"$ACTIVE_SERIES"
  set +e
  output="$(PATH="$SHIM_DIR:$PATH" bash tool/test_bootstrap_smoke.sh --offline-check-only 2>&1)"
  status=$?
  set -e
  printf '%s\n' "$output"
  if [ "$status" -eq 0 ] || [[ "$output" != *"$expected_output"* ]]; then
    echo "FAIL: $run_label did not reject an empty or comment-only expected patch series" >&2
    exit 1
  fi

  set +e
  output="$(BOOTSTRAP_REGRESSION_MODE=normal-integrity PATH="$SHIM_DIR:$PATH" \
    "$REAL_DART" run tool/bootstrap_deps.dart 2>&1)"
  status=$?
  set -e
  printf '%s\n' "$output"
  if [ "$status" -eq 0 ] || [[ "$output" != *"$expected_status"* ]]; then
    echo "FAIL: $run_label did not fail closed in the normal integrity path" >&2
    exit 1
  fi

  "$REAL_RM" -f "$ACTIVE_SERIES"
  "$REAL_MV" "$EMPTY_SERIES_BACKUP" "$ACTIVE_SERIES"

  if [ "$(cksum "${SERIES_FILES[@]}")" != "$SERIES_BEFORE" ]; then
    echo "FAIL: $run_label did not restore every patch series" >&2
    exit 1
  fi
}

run_empty_series_check "" "$EXPECTED_EMPTY_OFFLINE" "$EXPECTED_EMPTY_NORMAL" "empty-series check"

COMMENT_ONLY_SERIES=$'# comment-only active series\n# still empty\n'
"$REAL_MV" "$ACTIVE_SERIES" "$EMPTY_SERIES_BACKUP"
run_empty_series_check "$COMMENT_ONLY_SERIES" "$EXPECTED_EMPTY_OFFLINE" "$EXPECTED_EMPTY_NORMAL" "comment-only-series check"

set +e
OUTPUT="$(PATH="$SHIM_DIR:$PATH" bash tool/test_bootstrap_smoke.sh --test-missing-patch 2>&1)"
STATUS=$?
set -e
printf '%s\n' "$OUTPUT"

if [ "$STATUS" -ne 0 ]; then
  echo "FAIL: missing-patch smoke test exited $STATUS" >&2
  exit 1
fi
if [ -f "$BOOTSTRAP_REGRESSION_NETWORK_ATTEMPT" ]; then
  echo "FAIL: missing-patch smoke test accepted an unrelated network-capable bootstrap failure" >&2
  exit 1
fi
if [[ "$OUTPUT" =~ Injected\ missing\ patch:\ (bootstrap-smoke-missing-patch-[0-9]+\.patch) ]]; then
  INJECTED_PATCH="${BASH_REMATCH[1]}"
else
  echo "FAIL: missing-patch smoke test output did not identify the injected patch" >&2
  exit 1
fi
EXPECTED_DIAGNOSTIC="bootstrap_deps: offline-check: patch series declares missing patch: $INJECTED_PATCH"
if [[ "$OUTPUT" != *"$EXPECTED_DIAGNOSTIC"* ]]; then
  echo "FAIL: missing-patch smoke test did not show Bootstrap's exact missing-entry diagnostic" >&2
  exit 1
fi
if [ "$(cksum "${SERIES_FILES[@]}")" != "$SERIES_BEFORE" ]; then
  echo "FAIL: missing-patch smoke test did not restore every patch series after success" >&2
  exit 1
fi

set +e
RESTORE_FAILURE_OUTPUT="$(BOOTSTRAP_REGRESSION_MODE=restore-failure PATH="$SHIM_DIR:$PATH" \
  bash tool/test_bootstrap_smoke.sh --test-missing-patch 2>&1)"
RESTORE_FAILURE_STATUS=$?
set -e
printf '%s\n' "$RESTORE_FAILURE_OUTPUT"
if [ "$RESTORE_FAILURE_STATUS" -eq 0 ]; then
  echo "FAIL: missing-patch smoke test swallowed the injected restore mv failure" >&2
  exit 1
fi
if [[ "$RESTORE_FAILURE_OUTPUT" != *"Failed to restore patch series after missing-patch test"* ]]; then
  echo "FAIL: missing-patch smoke test did not report the restore mv failure" >&2
  exit 1
fi
shopt -s nullglob
RESTORE_FAILURE_BACKUPS=(third_party/tim2tox/patches/tencent_cloud_chat_sdk/*/series.bootstrap-smoke.*)
shopt -u nullglob
if [ "${#RESTORE_FAILURE_BACKUPS[@]}" -eq 0 ]; then
  echo "FAIL: restore failure deleted the recoverable patch-series backup" >&2
  exit 1
fi
for backup in "${RESTORE_FAILURE_BACKUPS[@]}"; do
  if [ ! -f "$backup" ]; then
    echo "FAIL: restore failure backup is not recoverable: $backup" >&2
    exit 1
  fi
done
if ! restore_series_snapshots; then
  echo "FAIL: regression could not restore patch series after the fake mv failure" >&2
  exit 1
fi
if [ "$(cksum "${SERIES_FILES[@]}")" != "$SERIES_BEFORE" ]; then
  echo "FAIL: outer regression cleanup did not restore every patch series after mv failure" >&2
  exit 1
fi

set +e
FAILURE_OUTPUT="$(BOOTSTRAP_REGRESSION_MODE=unrelated-failure PATH="$SHIM_DIR:$PATH" \
  bash tool/test_bootstrap_smoke.sh --test-missing-patch 2>&1)"
FAILURE_STATUS=$?
set -e
printf '%s\n' "$FAILURE_OUTPUT"
if [ "$FAILURE_STATUS" -eq 0 ] || [[ "$FAILURE_OUTPUT" != *"Offline bootstrap failed for an unrelated reason"* ]]; then
  echo "FAIL: missing-patch smoke test accepted the injected unrelated failure" >&2
  exit 1
fi
if [ "$(cksum "${SERIES_FILES[@]}")" != "$SERIES_BEFORE" ]; then
  echo "FAIL: missing-patch smoke test did not restore every patch series after failure" >&2
  exit 1
fi

set +e
SIGNAL_OUTPUT="$(BOOTSTRAP_REGRESSION_MODE=signal PATH="$SHIM_DIR:$PATH" \
  bash tool/test_bootstrap_smoke.sh --test-missing-patch 2>&1)"
SIGNAL_STATUS=$?
set -e
printf '%s\n' "$SIGNAL_OUTPUT"
if [ "$SIGNAL_STATUS" -ne 143 ]; then
  echo "FAIL: signal-path smoke test exited $SIGNAL_STATUS instead of 143" >&2
  exit 1
fi
if [ "$(cksum "${SERIES_FILES[@]}")" != "$SERIES_BEFORE" ]; then
  echo "FAIL: missing-patch smoke test did not restore every patch series after signal" >&2
  exit 1
fi

shopt -s nullglob
RESIDUE=(third_party/tim2tox/patches/tencent_cloud_chat_sdk/*/series.bak \
  third_party/tim2tox/patches/tencent_cloud_chat_sdk/*/series.bootstrap-smoke.*)
shopt -u nullglob
if [ "${#RESIDUE[@]}" -ne 0 ]; then
  echo "FAIL: missing-patch smoke test left backup residue: ${RESIDUE[*]}" >&2
  exit 1
fi

echo "PASS: missing-patch smoke test rejected the injected patch and restored all series paths."
