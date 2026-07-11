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
    cp -f "$1" "$2"
  fi
}

shopt -s dotglob nullglob
for e in "$SRC"/*; do
  n="$(basename "$e")"
  case "$n" in .git|build|.dart_tool|Thumbs.db|.|..) continue ;; esac
  if [ "$n" = "$PLAT" ] && [ -d "$e" ]; then
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
