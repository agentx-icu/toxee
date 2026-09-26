#!/usr/bin/env bash
#
# assert_no_test_hooks.sh — fail when a native binary that is about to be
# PACKAGED still carries the auto_tests-only FFI hooks.
#
# WHY THIS EXISTS (it is not a duplicate of the CMake gate)
# --------------------------------------------------------
# `tim2tox_ffi_mm6_send_crafted_challenge` forges an MM-6 identity challenge
# that claims another member's per-group key. It is an attack primitive with no
# product use, and it is compiled in only under
# -DTIM2TOX_ENABLE_TEST_HOOKS=ON (third_party/tim2tox/CMakeLists.txt, OFF by
# default; third_party/tim2tox/build_ffi.sh turns it ON because the auto_tests
# need it).
#
# Configuring every app build tree with the option OFF is necessary but NOT
# sufficient, because packaging accepts PREBUILT binaries:
#   * Gradle packages whatever sits in android/app/src/main/jniLibs/<abi>/,
#   * Xcode embeds whatever tim2tox_ffi.framework / libtim2tox_ffi.dylib was
#     staged (TIM2TOX_IOS_FRAMEWORK_PATH / TIM2TOX_IOS_DYLIB_PATH),
#   * tool/ci/build_tim2tox.sh's own sync paths (TIM2TOX_ANDROID_LIB_DIR) copy
#     a library nobody in this repo configured,
#   * the desktop run scripts happily reuse a library left in the build tree.
# None of those paths ever ran CMake, so the only check that can speak for them
# is one that looks at the bytes. That is this script.
#
# Usage:
#   assert_no_test_hooks.sh <binary-or-dir> [more...]
#
# A directory argument is expanded to the tim2tox FFI binaries inside it
# (.framework bundles, jniLibs trees, build/native-artifacts/<target>); a
# directory holding none of them is an error, not a pass.
#
# Env:
#   TIM2TOX_NM  explicit nm-like tool to use first (e.g. the NDK's llvm-nm).
#
# Inspection method, in order, per file: an nm-like tool (`TIM2TOX_NM`, then the
# NDK's llvm-nm for .so files, then `nm`, then `llvm-nm`) reading -g and -D; if
# none of them can read the file, a `grep -a` whole-file byte scan; `strings`
# only if grep is missing too (it is the weakest — see the note at that branch).
# Every run says which method it used.
#
# Exit status: 0 = every file inspected and clean. 1 = a file exports the hook,
# a file is missing/unreadable, or NO method could inspect it. There is
# deliberately no "could not check, assuming fine" outcome: a gate that can be
# satisfied by being unable to look is not a gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/ci/common.sh
source "$SCRIPT_DIR/common.sh"

# THE single definition of the forbidden export on the toxee side. Every caller
# (build_all.sh, tool/ci/build_tim2tox.sh, the packaging workflows) goes through
# this script precisely so this string is written down exactly once here.
FORBIDDEN_SYMBOL="tim2tox_ffi_mm6_send_crafted_challenge"

usage() {
  cat <<EOF
Usage: assert_no_test_hooks.sh <binary-or-directory> [more...]

Fails if any inspected native binary exports $FORBIDDEN_SYMBOL
(the auto_tests-only MM-6 crafted-challenge hook).
EOF
}

# The NDK's llvm-nm, when this host has an NDK at all. Android .so files are
# ELF, so a plain `nm` can read them too, but on a macOS host `nm` is the
# Mach-O one from Xcode and refuses ELF outright — that is exactly the "cannot
# inspect" case this script must not treat as a pass.
find_ndk_nm() {
  local candidate sdk_root ndk found
  for candidate in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    [[ -n "$candidate" && -d "$candidate" ]] || continue
    found="$(ls "$candidate"/toolchains/llvm/prebuilt/*/bin/llvm-nm 2>/dev/null | head -n 1 || true)"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return 0
    fi
  done
  for sdk_root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}"; do
    [[ -n "$sdk_root" && -d "$sdk_root/ndk" ]] || continue
    while IFS= read -r ndk; do
      found="$(ls "$ndk"/toolchains/llvm/prebuilt/*/bin/llvm-nm 2>/dev/null | head -n 1 || true)"
      if [[ -n "$found" ]]; then
        printf '%s\n' "$found"
        return 0
      fi
    done < <(find "$sdk_root/ndk" -mindepth 1 -maxdepth 1 -type d | sort -Vr)
  done
  return 0
}

# Ordered list of nm-like tools to try for one file. Android .so files get the
# NDK's llvm-nm first (see find_ndk_nm); everything else gets the host nm.
nm_tools_for() {
  local file="$1"
  local -a tools=()
  local ndk_nm=""

  if [[ -n "${TIM2TOX_NM:-}" ]]; then
    tools+=("${TIM2TOX_NM}")
  fi
  if [[ "$file" == *.so || "$file" == *.so.* ]]; then
    ndk_nm="$(find_ndk_nm)"
    # Spelled out rather than `[[ ... ]] && tools+=(...)`: under `set -e` a
    # trailing AND-list whose test fails takes the whole function/block down.
    if [[ -n "$ndk_nm" ]]; then
      tools+=("$ndk_nm")
    fi
  fi
  tools+=(nm llvm-nm)
  printf '%s\n' "${tools[@]}"
}

# Every tim2tox FFI binary under a directory argument.
expand_dir() {
  local dir="$1"
  find "$dir" -type f \
    \( -name 'libtim2tox_ffi.so' \
    -o -name 'libtim2tox_ffi.dylib' \
    -o -name 'tim2tox_ffi.dll' \
    -o -name 'tim2tox_ffi' \) | sort
}

# Inspect ONE regular file. Dies on a hook hit, on an unreadable file, or when
# no method could read it at all.
check_file() {
  local file="$1"
  local label="${2:-$file}"

  [[ -f "$file" ]] || ci_die "$label: file missing, cannot verify it is hook-free: $file"
  [[ -r "$file" ]] || ci_die "$label: file not readable, cannot verify it is hook-free: $file"
  [[ -s "$file" ]] || ci_die "$label: file is empty, cannot verify it is hook-free: $file"

  local tool syms method=""
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    command -v "$tool" >/dev/null 2>&1 || continue
    # No `nm | grep` pipeline: grep's early exit SIGPIPEs nm and `set -o
    # pipefail` turns that into a false clean result. Capture instead.
    # -g (external/global) plus -D (ELF dynamic) so a stripped .so, whose
    # exports live only in .dynsym, is still covered.
    syms="$({ "$tool" -g "$file" 2>/dev/null; "$tool" -D "$file" 2>/dev/null; } || true)"
    if [[ -n "$syms" ]]; then
      method="$(command -v "$tool") -g/-D"
      break
    fi
  done < <(nm_tools_for "$file")

  # No nm-like tool could read this file (Windows Git Bash has no nm; a macOS
  # host `nm` cannot read an Android ELF). Export names are stored as plain
  # ASCII in the ELF .dynstr / Mach-O symbol table / PE export directory, so a
  # whole-file byte scan is a serviceable substitute — and it errs towards
  # failing, since it also matches a non-exported occurrence.
  #
  # `grep -a`, NOT `strings`: macOS /usr/bin/strings scans loadable sections
  # only and does NOT see the Mach-O symbol table even with -a. Measured
  # 2026-09-26 on a hook-ENABLED libtim2tox_ffi.dylib: `nm -g` found the symbol
  # and `grep -a` found it, `strings -a | grep` found nothing. A fallback that
  # answers "clean" for a hook-enabled dylib is worse than no fallback, so
  # strings is used only if grep itself is missing, never in preference to it.
  if [[ -z "$method" ]] && command -v grep >/dev/null 2>&1; then
    if grep -aq -- "$FORBIDDEN_SYMBOL" "$file"; then
      ci_die "$label: FORBIDDEN test hook $FORBIDDEN_SYMBOL found (method: grep -a whole-file byte scan) in $file. This binary was built with -DTIM2TOX_ENABLE_TEST_HOOKS=ON and must never be packaged."
    fi
    ci_log "$label: hook-free, $FORBIDDEN_SYMBOL absent (method: grep -a whole-file byte scan; no nm-like tool could read this file)"
    return 0
  fi

  if [[ -z "$method" ]] && command -v strings >/dev/null 2>&1; then
    syms="$(strings -a "$file" 2>/dev/null || true)"
    if [[ -n "$syms" ]]; then
      method="strings -a (last resort: no nm-like tool and no grep; on Mach-O this can MISS symbol-table names)"
    fi
  fi

  if [[ -z "$method" ]]; then
    ci_die "$label: no nm/llvm-nm/grep/strings method could inspect $file — refusing to report it hook-free"
  fi

  if [[ "$syms" == *"$FORBIDDEN_SYMBOL"* ]]; then
    ci_die "$label: FORBIDDEN test hook $FORBIDDEN_SYMBOL is present (method: $method) in $file. This binary was built with -DTIM2TOX_ENABLE_TEST_HOOKS=ON and must never be packaged. Rebuild with the option OFF (or delete the staged artifact) and re-run."
  fi
  ci_log "$label: hook-free, $FORBIDDEN_SYMBOL absent (method: $method)"
}

main() {
  if [[ $# -eq 0 ]]; then
    usage >&2
    ci_die "at least one binary or directory is required"
  fi
  case "${1:-}" in
    --help|-h)
      usage
      exit 0
      ;;
  esac

  local arg checked=0 file
  for arg in "$@"; do
    if [[ -d "$arg" ]]; then
      local -a files=()
      while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
      done < <(expand_dir "$arg")
      [[ ${#files[@]} -gt 0 ]] || \
        ci_die "$arg: directory contains no tim2tox FFI binary to inspect — refusing to report a clean check"
      for file in "${files[@]}"; do
        check_file "$file" "$(basename "$arg")/$(basename "$file")"
        checked=$((checked + 1))
      done
    else
      check_file "$arg"
      checked=$((checked + 1))
    fi
  done
  ci_log "test-hook check passed for $checked binary/binaries"
}

main "$@"
