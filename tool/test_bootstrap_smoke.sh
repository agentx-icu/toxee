#!/usr/bin/env bash
# Smoke test for bootstrap: verify existing state offline, or refresh the vendored SDK.
# Contract boundary: this script assumes the existing Tim2Tox and UIKit submodule
# checkouts are present. It does not prove a clean clone, submodule deinit/reset,
# or first-time submodule registration; those are separate bootstrap operations.
# The default path refreshes the existing vendor checkout and pub overrides only.
# The command returns the bootstrap command's exact status.
# With --test-missing-patch: temporarily break the active series to assert offline verification fails.
set -euo pipefail
cd "$(dirname "$0")/.."
export GIT_MASTER=1

RESTORE_SERIES=""
RESTORE_BACKUP=""
TEMP_FILES=()

restore_series() {
  if [ -n "$RESTORE_SERIES" ] && [ -n "$RESTORE_BACKUP" ] && [ -f "$RESTORE_BACKUP" ]; then
    if ! mv -f "$RESTORE_BACKUP" "$RESTORE_SERIES"; then
      return 1
    fi
  fi
  RESTORE_SERIES=""
  RESTORE_BACKUP=""
  return 0
}

cleanup_missing_patch_test() {
  local exit_status=$?
  local restore_status=0
  local temp_file
  trap - EXIT HUP INT TERM
  set +e
  restore_series
  restore_status=$?
  for temp_file in "${TEMP_FILES[@]}"; do
    if [ "$restore_status" -ne 0 ] && [ "$temp_file" = "$RESTORE_BACKUP" ]; then
      continue
    fi
    rm -f "$temp_file"
  done
  if [ "$restore_status" -ne 0 ]; then
    echo "Failed to restore patch series after missing-patch test; recover from $RESTORE_BACKUP" >&2
    exit_status=1
  fi
  exit "$exit_status"
}

run_offline_check() {
  local output_file="$1"
  local command_status
  set +e
  dart run tool/bootstrap_deps.dart --offline-check-only 2>&1 | tee -a "$output_file"
  command_status=${PIPESTATUS[0]}
  set -e
  return "$command_status"
}

test_missing_patch() {
  local baseline_output
  local candidate
  local candidate_output
  local candidate_text
  local backup
  local missing_patch="bootstrap-smoke-missing-patch-$$.patch"
  local expected_rejection="bootstrap_deps: offline-check: patch series declares missing patch: $missing_patch"
  local -a series_candidates

  trap cleanup_missing_patch_test EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  baseline_output="$(mktemp "${TMPDIR:-/tmp}/toxee-bootstrap-baseline.XXXXXX")"
  TEMP_FILES+=("$baseline_output")
  if ! run_offline_check "$baseline_output"; then
    echo "Cannot run missing-patch test: baseline offline verification failed" >&2
    exit 1
  fi

  shopt -s nullglob
  series_candidates=(third_party/tim2tox/patches/tencent_cloud_chat_sdk/*/series)
  shopt -u nullglob
  if [ "${#series_candidates[@]}" -eq 0 ]; then
    echo "No Tencent Cloud Chat SDK patch series found" >&2
    exit 1
  fi

  for candidate in "${series_candidates[@]}"; do
    if [ -e "$(dirname "$candidate")/$missing_patch" ]; then
      echo "Injected missing patch already exists: $missing_patch" >&2
      exit 1
    fi

    backup="$(mktemp "${candidate}.bootstrap-smoke.XXXXXX")"
    TEMP_FILES+=("$backup")
    cp -p "$candidate" "$backup"
    RESTORE_SERIES="$candidate"
    RESTORE_BACKUP="$backup"
    printf '\n%s\n' "$missing_patch" >> "$candidate"

    candidate_output="$(mktemp "${TMPDIR:-/tmp}/toxee-bootstrap-candidate.XXXXXX")"
    TEMP_FILES+=("$candidate_output")
    printf 'Injected missing patch: %s (%s)\n' "$missing_patch" "$candidate"

    if run_offline_check "$candidate_output"; then
      restore_series
      continue
    fi

    restore_series
    candidate_text="$(<"$candidate_output")"
    if [[ "$candidate_text" != *"$expected_rejection"* ]]; then
      echo "Offline bootstrap failed for an unrelated reason while testing $candidate" >&2
      exit 1
    fi

    echo "Bootstrap correctly rejected missing patch $missing_patch from active series $candidate."
    exit 0
  done

  echo "No discovered patch series affected offline bootstrap verification" >&2
  exit 1
}

if [ "${1:-}" = "--test-missing-patch" ]; then
  test_missing_patch
fi

if [ "${1:-}" = "--offline-check-only" ]; then
  exec dart run tool/bootstrap_deps.dart --offline-check-only
fi

# Remove generated artifacts
rm -rf third_party/tencent_cloud_chat_sdk
rm -f pubspec_overrides.yaml

exec dart run tool/bootstrap_deps.dart
