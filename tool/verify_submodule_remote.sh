#!/usr/bin/env bash
# verify_submodule_remote.sh
#
# Refuse to let a toxee push leave a dangling submodule pointer.
#
# For each submodule recorded in the superproject HEAD, confirm that the pinned
# SHA is reachable on the submodule's remote. A pointer is "reachable" if either
#   (a) `git ls-remote <url>` lists the SHA at the tip of any ref, or
#   (b) `git -C <path> fetch origin <sha>:refs/_remotes/_check/<sha>` succeeds —
#       which means the SHA is reachable from some branch on the remote, even
#       if it is not itself a tip.
#
# Exit 0 when every submodule is clean, 1 when any pointer is dangling.
# Designed to be called from the pre-push hook in tool/git-hooks/pre-push.
#
# Compatible with bash 3.2 (macOS default) — no associative arrays.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PREFIX="verify_submodule_remote:"

# Explicit bypass for environments that can't tolerate the network probe
# (e.g. workflow steps before checkout completes). CI itself MUST run the
# full check via a dedicated workflow — see .github/workflows/submodule_verify.yml.
if [ "${TOXEE_HOOK_CI_BYPASS:-}" = "1" ]; then
  echo "$PREFIX TOXEE_HOOK_CI_BYPASS=1 — skipping remote reachability check."
  exit 0
fi
if [ "${CI:-}" = "true" ]; then
  echo "$PREFIX CI=true detected (informational) — running full check anyway."
fi

# Bound remote calls so a hung DNS / SSH handshake can't wedge the push.
export GIT_TERMINAL_PROMPT=0
GIT_NET_OPTS=(-c "http.timeout=15" -c "core.sshCommand=ssh -o ConnectTimeout=10 -o BatchMode=yes")

if [ ! -f .gitmodules ]; then
  echo "$PREFIX no .gitmodules — nothing to verify."
  exit 0
fi

# Parse submodule path/url pairs from .gitmodules into a single TSV stream:
#   <name>\t<path>\t<url>
# git config --get-regexp prints lines like:
#   submodule.<name>.path third_party/tim2tox
#   submodule.<name>.url  https://github.com/agentx-icu/tim2tox.git
ENTRIES_FILE="$(mktemp -t verify_submod_entries.XXXXXX)"
trap 'rm -f "$ENTRIES_FILE"' EXIT

git config -f .gitmodules --get-regexp '^submodule\..*\.(path|url)$' 2>/dev/null \
  | awk '
      {
        key = $1
        $1 = ""
        sub(/^ /, "")
        val = $0
        # key looks like submodule.<name>.<field>
        field = key
        sub(/.*\./, "", field)
        name = key
        sub(/^submodule\./, "", name)
        sub(/\.(path|url)$/, "", name)
        if (field == "path") paths[name] = val
        else if (field == "url") urls[name] = val
        order[name] = 1
      }
      END {
        for (n in order) {
          if (paths[n] != "" && urls[n] != "") {
            printf "%s\t%s\t%s\n", n, paths[n], urls[n]
          }
        }
      }
    ' > "$ENTRIES_FILE"

if [ ! -s "$ENTRIES_FILE" ]; then
  echo "$PREFIX no submodules declared — nothing to verify."
  exit 0
fi

CHECKED=0
FAILED=0
FAILURE_LINES_FILE="$(mktemp -t verify_submod_fail.XXXXXX)"
trap 'rm -f "$ENTRIES_FILE" "$FAILURE_LINES_FILE"' EXIT

while IFS=$'\t' read -r name sub_path sub_url_cfg; do
  [ -z "${name:-}" ] && continue
  [ -z "${sub_path:-}" ] && continue
  [ -z "${sub_url_cfg:-}" ] && continue

  # Read recorded SHA + mode from HEAD tree.
  tree_line="$(git ls-tree HEAD -- "$sub_path" || true)"
  if [ -z "$tree_line" ]; then
    echo "$PREFIX warning: '$sub_path' not in HEAD tree; skipping." >&2
    continue
  fi

  mode="$(echo "$tree_line" | awk '{print $1}')"
  if [ "$mode" != "160000" ]; then
    # Not actually a submodule entry (gitlink); skip silently.
    continue
  fi

  sha="$(echo "$tree_line" | awk '{print $3}')"
  if [ -z "$sha" ]; then
    echo "$PREFIX warning: could not read SHA for '$sub_path'; skipping." >&2
    continue
  fi

  # Prefer the submodule's own origin remote URL (handles user-customised origins);
  # fall back to .gitmodules URL.
  url="$sub_url_cfg"
  if [ -d "$sub_path/.git" ] || [ -f "$sub_path/.git" ]; then
    if remote_url="$(git -C "$sub_path" remote get-url origin 2>/dev/null)"; then
      if [ -n "$remote_url" ]; then
        url="$remote_url"
      fi
    fi
  fi

  CHECKED=$((CHECKED + 1))

  # Step 1: cheap ls-remote check (SHA at tip of some ref).
  if git "${GIT_NET_OPTS[@]}" ls-remote "$url" 2>/dev/null | grep -F -q "$sha"; then
    continue
  fi

  # Step 2: ask the submodule's own working clone to fetch the SHA.
  # Only possible if the submodule dir is initialised.
  if [ -d "$sub_path/.git" ] || [ -f "$sub_path/.git" ]; then
    tmp_ref="refs/_remotes/_check/$sha"
    if git "${GIT_NET_OPTS[@]}" -C "$sub_path" fetch --quiet origin "$sha:$tmp_ref" 2>/dev/null; then
      git -C "$sub_path" update-ref -d "$tmp_ref" 2>/dev/null || true
      continue
    fi
    git -C "$sub_path" update-ref -d "$tmp_ref" 2>/dev/null || true
  fi

  FAILED=$((FAILED + 1))
  printf "%s submodule '%s' pinned to %s, not reachable on %s. Push the submodule branch first.\n" \
    "$PREFIX" "$sub_path" "$sha" "$url" >> "$FAILURE_LINES_FILE"
done < "$ENTRIES_FILE"

if [ "$FAILED" -gt 0 ]; then
  cat "$FAILURE_LINES_FILE" >&2
  exit 1
fi

echo "$PREFIX All $CHECKED submodule pointers reachable on their remotes."
exit 0
