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
# ...and the C++ method the wrapper calls. It was gated one commit AFTER the
# wrapper, so a binary built in between exports no C symbol and still carries
# this one — on Linux it stays callable, and a check that looked only for the
# wrapper reported such a binary clean (codex 2026-09-27). The name is matched as
# a substring so it is found whether the tool prints it mangled
# (_ZN16V2TIMManagerImpl23Mm6SendCraftedChallenge...) or demangled, and whether
# the platform prefixes an underscore.
FORBIDDEN_CXX_SYMBOL="Mm6SendCraftedChallenge"
FORBIDDEN_NAMES=("$FORBIDDEN_SYMBOL" "$FORBIDDEN_CXX_SYMBOL")

# First forbidden name present in "$1", or empty when none is.
first_forbidden_in() {
  local haystack="$1" name
  for name in "${FORBIDDEN_NAMES[@]}"; do
    if [[ "$haystack" == *"$name"* ]]; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 0
}

usage() {
  cat <<EOF
Usage: assert_no_test_hooks.sh <binary-or-directory> [more...]

Fails if any inspected native binary exports $FORBIDDEN_SYMBOL or the C++
method $FORBIDDEN_CXX_SYMBOL behind it (the auto_tests-only MM-6
crafted-challenge hook).
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
  # -type f OR -type l: a STAGED LIBRARY IS OFTEN A SYMLINK, and skipping it
  # meant its bytes were never checked while the caller's "does this directory
  # hold a library" guard also stopped asking (codex 2026-09-27). check_file
  # resolves the link and fails on a broken one.
  find "$dir" \( -type f -o -type l \) \
    \( -name 'libtim2tox_ffi.so' \
    -o -name 'libtim2tox_ffi.so.*' \
    -o -name 'libtim2tox_ffi.dylib' \
    -o -name 'tim2tox_ffi.dll' \
    -o -name 'tim2tox_ffi' \) | sort
}

# Inspect ONE file. Dies on a hook hit, on an unreadable file, on a broken or
# uninspectable symlink, or when no method could read it at all.
check_file() {
  local file="$1"
  local label="${2:-$file}"

  # A staged library is often a symlink. Resolve it and inspect the TARGET's
  # bytes, and fail on a dangling one rather than skip it (codex 2026-09-27).
  if [[ -L "$file" ]]; then
    local target
    target="$(cd "$(dirname "$file")" 2>/dev/null && readlink "$(basename "$file")" 2>/dev/null || true)"
    [[ -n "$target" ]] || ci_die "$label: cannot read the symlink to verify it is hook-free: $file"
    [[ -e "$file" ]] || ci_die "$label: symlink is broken (-> $target), cannot verify it is hook-free: $file"
    label="$label (symlink -> $target)"
  fi

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
    local name rc
    for name in "${FORBIDDEN_NAMES[@]}"; do
      grep -aq -- "$name" "$file"
      rc=$?
      # 0 = found, 1 = absent, ANYTHING ELSE = grep could not read the file.
      # Treating 2 as "absent" is how an unreadable binary got reported clean.
      if [[ $rc -eq 0 ]]; then
        ci_die "$label: FORBIDDEN test hook $name found (method: grep -a whole-file byte scan) in $file. This binary was built with -DTIM2TOX_ENABLE_TEST_HOOKS=ON and must never be packaged."
      elif [[ $rc -ne 1 ]]; then
        ci_die "$label: grep could not read $file (exit $rc) — refusing to report it hook-free"
      fi
    done
    ci_log "$label: hook-free, no forbidden hook symbol (method: grep -a whole-file byte scan; no nm-like tool could read this file)"
    return 0
  fi

  # NO `strings` fallback. macOS strings reads loadable sections and not the
  # symbol table — measured 2026-09-26 on a hook-ENABLED dylib, where `nm -g`
  # and `grep -a` both found the symbol and `strings -a | grep` found nothing.
  # An inspection that can answer "clean" for a hook-enabled binary is worse
  # than none, so when neither an nm-like tool nor grep can read the file this
  # fails closed (codex 2026-09-27).
  if [[ -z "$method" ]]; then
    ci_die "$label: no nm/llvm-nm/grep method could inspect $file — refusing to report it hook-free (strings is deliberately NOT accepted: on Mach-O it misses symbol-table names)"
  fi

  local hit
  hit="$(first_forbidden_in "$syms")"
  if [[ -n "$hit" ]]; then
    ci_die "$label: FORBIDDEN test hook $hit is present (method: $method) in $file. This binary was built with -DTIM2TOX_ENABLE_TEST_HOOKS=ON and must never be packaged. Rebuild with the option OFF (or delete the staged artifact) and re-run."
  fi
  ci_log "$label: hook-free, no forbidden hook symbol (method: $method)"
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
