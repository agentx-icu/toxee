#!/usr/bin/env bash
# install_git_hooks.sh — point this clone at the in-tree hook directory.
#
# Sets core.hooksPath to tool/git-hooks so the pre-push submodule guard
# (and any future hooks) survive a fresh `git clone`. This is per-clone
# state; rerun after re-cloning.
#
# To undo: git config --unset core.hooksPath

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HOOKS_DIR="tool/git-hooks"

if [ ! -d "$HOOKS_DIR" ]; then
  echo "install_git_hooks: $HOOKS_DIR not found at $ROOT" >&2
  exit 1
fi

git config core.hooksPath "$HOOKS_DIR"

echo "install_git_hooks: core.hooksPath -> $HOOKS_DIR"
echo "install_git_hooks: active hooks:"
for h in "$HOOKS_DIR"/*; do
  [ -f "$h" ] || continue
  if [ -x "$h" ]; then
    echo "  - $(basename "$h")"
  else
    echo "  - $(basename "$h") (not executable; run: chmod +x $h)"
  fi
done
echo
echo "To undo: git config --unset core.hooksPath"
