#!/usr/bin/env bash
# Materialize a local "build shim" view of a (possibly read-only) Parallels
# share checkout, so a VM can build WITHOUT copying the sources:
#   * directories are symlinked back to the share (single source of truth on
#     the Mac — edits there are visible instantly),
#   * small top-level files are real copies (some tools rewrite files via
#     rename(), which would silently replace a file-symlink with a local file),
#   * the dirs the flutter tool must WRITE (build/, .dart_tool/,
#     <platform>/flutter/ephemeral) stay real local dirs — that is also where
#     plugin symlinks land, which the share filesystem cannot hold.
# Idempotent: re-run to refresh the copied files (existing links are kept).
#
#   make_shim.sh <share-repo-root> <dest> [platform]     platform: linux (default)
set -euo pipefail
SRC="${1:?usage: make_shim.sh <share-repo-root> <dest> [platform]}"
DST="${2:?usage: make_shim.sh <share-repo-root> <dest> [platform]}"
PLAT="${3:-linux}"

[ -f "$SRC/pubspec.yaml" ] || { echo "ERROR: $SRC does not look like the repo root" >&2; exit 1; }
mkdir -p "$DST"

link_or_copy() { # $1 = src entry, $2 = dst entry
  if [ -d "$1" ]; then
    [ -e "$2" ] || [ -L "$2" ] || ln -s "$1" "$2"
  else
    case "$1" in
      # Executable entrypoints are never rewritten by tools — symlink them so
      # launcher fixes on the Mac apply immediately (a stale copied
      # run_toxee_linux.sh silently ran without the L3 seed pre-step).
      *.sh|*.ps1)
        rm -f "$2" 2>/dev/null || true
        ln -s "$1" "$2"
        ;;
      *)
        cp -f "$1" "$2"
        ;;
    esac
  fi
}

shopt -s dotglob nullglob
# Migration: earlier shim versions symlinked lib/ wholesale; it must now be a
# real dir (flutter gen-l10n rewrites lib/i18n on pub get/build, and the share
# is read-only for guests).
[ -L "$DST/lib" ] && rm "$DST/lib"
for e in "$SRC"/*; do
  n="$(basename "$e")"
  case "$n" in .git|build|.dart_tool|Thumbs.db|.|..) continue ;; esac
  if [ "$n" = "lib" ] && [ -d "$e" ]; then
    # lib/: real dir; children symlinked, EXCEPT lib/i18n which gen-l10n
    # rewrites at pub-get/build time — that subtree is a real local copy (its
    # content is generated-from-arb and committed, so a copy is safe and the
    # regen is idempotent).
    mkdir -p "$DST/lib"
    for e2 in "$e"/*; do
      n2="$(basename "$e2")"
      if [ "$n2" = "i18n" ] && [ -d "$e2" ]; then
        rm -rf "$DST/lib/i18n"
        cp -r "$e2" "$DST/lib/i18n"
      else
        link_or_copy "$e2" "$DST/lib/$n2"
      fi
    done
  elif [ "$n" = "$PLAT" ] && [ -d "$e" ]; then
    # Platform runner dir: real dir; inner entries linked/copied, except
    # flutter/ (real dir whose generated_* files must be locally writable)
    # and flutter/ephemeral (left absent — the flutter tool creates it and
    # fills it with plugin symlinks, which must live on a local filesystem).
    mkdir -p "$DST/$n"
    for e2 in "$e"/*; do
      n2="$(basename "$e2")"
      if [ "$n2" = "flutter" ] && [ -d "$e2" ]; then
        mkdir -p "$DST/$n/flutter"
        for e3 in "$e2"/*; do
          n3="$(basename "$e3")"
          [ "$n3" = "ephemeral" ] && continue
          link_or_copy "$e3" "$DST/$n/flutter/$n3"
        done
      else
        link_or_copy "$e2" "$DST/$n/$n2"
      fi
    done
  else
    link_or_copy "$e" "$DST/$n"
  fi
done
mkdir -p "$DST/build" "$DST/.dart_tool"
echo "[make_shim] shim ready: $DST (sources -> $SRC)"
