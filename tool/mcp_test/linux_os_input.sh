#!/usr/bin/env bash
# REAL OS input for the Linux real-UI pair — the Linux twin of
# `win_os_input.ps1` (Windows) and of the macOS osascript layer.
# Driven from `drive_real_ui_pair_inst_os_input.dart` under
# `TOXEE_LINUX_OS_INPUT=1`; every verb takes the instance's PID and drives its
# X11 window through XTEST (xdotool), i.e. genuine key events that reach
# Flutter's GTK embedder exactly as a human's would.
#
# Why this is simpler than the Windows side:
#
#   * XTEST injects keys with REAL keycodes, so Flutter's embedder sees a
#     coherent down/up pair — none of the scan-code-0 breakage that made
#     `SendKeys` useless on Windows.
#   * There is no window station / session-0 restriction: an SSH session can
#     drive an Xvfb display, so the OS-input campaigns need no interactive
#     console session (the Windows ones do).
#   * XTEST delivers Super+Ctrl chords correctly at the X level (verified with
#     xev) — but the app does not ACT on them, so the three global chords keep
#     their l3 seams here exactly as on Windows. See the header of
#     drive_real_ui_pair_inst_linux_input.dart for the evidence.
#
# Prerequisites the caller must have set up (see `_linux_headless_env.sh`):
# $DISPLAY pointing at the X server the app renders on, and GDK_BACKEND=x11 in
# the APP's environment — without that GDK picks the Wayland backend and the
# app has no X window to drive at all.
#
#   linux_os_input.sh resolve   <pid>
#   linux_os_input.sh focus     <pid>
#   linux_os_input.sh type      <pid> <base64-utf8> [delay_ms]
#   linux_os_input.sh key       <pid> <xdotool-keyspec>       # e.g. shift+Return
#   linux_os_input.sh paste     <pid> <base64-utf8>
#   linux_os_input.sh clipboard <pid> <base64-utf8>           # set only, no paste
#   linux_os_input.sh clipget   <pid>                         # print clipboard
#   linux_os_input.sh clipimage <pid> <png-path>              # image/png selection
#   linux_os_input.sh clear     <pid>
set -uo pipefail

VERB="${1:?usage: linux_os_input.sh <verb> <pid> [...]}"
PID="${2:?missing pid}"
ARG3="${3:-}"
ARG4="${4:-}"

command -v xdotool >/dev/null 2>&1 || { echo "xdotool missing (apt install xdotool)" >&2; exit 2; }

# The driver is spawned by the unified runner from an SSH environment that has
# no $DISPLAY, while the app renders on the Xvfb the LAUNCHER started. The
# launcher records that display under the runtime root; fall back to it rather
# than failing (or, worse, driving a different X server than the app).
if [[ -z "${DISPLAY:-}" ]]; then
    _repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    _display_file="${TOXEE_LINUX_RUNTIME_ROOT:-$_repo_root/build/linux_runtime}/display"
    [[ -r "$_display_file" ]] && export DISPLAY="$(cat "$_display_file")"
fi
[[ -n "${DISPLAY:-}" ]] || { echo "no \$DISPLAY (and no runtime display file)" >&2; exit 2; }

# Resolve the instance's MAIN toplevel. `xdotool search --pid` also returns
# GTK's 10x10 group-leader window and 1x1 helper windows; the real one is the
# widest. (Name matching alone is not enough: the title is "Toxee" only after
# window_manager applies it, and both windows carry the same WM_CLASS.)
_resolve_window_once() {
    local best="" best_w=0 w geom width
    for w in $(xdotool search --pid "$PID" 2>/dev/null); do
        geom="$(xdotool getwindowgeometry --shell "$w" 2>/dev/null || true)"
        [[ -z "$geom" ]] && continue
        width="$(printf '%s\n' "$geom" | sed -n 's/^WIDTH=//p')"
        [[ -z "$width" ]] && continue
        if (( width > best_w )); then best_w="$width"; best="$w"; fi
    done
    # A real app window is at least a few hundred px wide; anything smaller
    # means the toplevel is not mapped yet (or GDK went to Wayland).
    (( best_w >= 200 )) || return 1
    printf '%s' "$best"
}

# RETRY the resolution: a window can be legitimately absent for a moment (the
# second instance is still coming up, a resize is in flight), and a one-shot
# lookup turned that into a dead sweep — one such miss on B during registration
# killed a whole sweep_group2 run (2026-09-05). Six seconds, then a message
# that says WHICH of the two very different failures happened: a dead process,
# or a live process with no mapped window (the app hid to tray, or GDK went to
# Wayland). The old single message blamed GDK for both.
resolve_window() {
    local out i
    for ((i = 0; i < 24; i++)); do
        out="$(_resolve_window_once)" && { printf '%s' "$out"; return 0; }
        kill -0 "$PID" 2>/dev/null || {
            echo "process $PID is not running (the app exited/crashed)" >&2
            return 4
        }
        sleep 0.25
    done
    echo "pid $PID is alive but has no mapped X window >=200px wide" >&2
    echo "(hidden to tray? GDK_BACKEND=x11 set for the app?)" >&2
    return 3
}

# Focus is XSetInputFocus (`windowfocus`), NOT `windowactivate`: activate goes
# through the EWMH `_NET_ACTIVE_WINDOW` message, which needs a window manager —
# and the headless Xvfb the campaigns run on has none. `windowactivate` is
# still attempted first when a WM is present so a run on a real desktop behaves
# like a user click. Modifiers are released first: a chord interrupted by an
# earlier failure would otherwise leave Shift/Ctrl latched into every later key.
enter_input() {
    local win="$1" k
    for k in shift ctrl alt super; do xdotool keyup "$k" 2>/dev/null; done
    if xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id'; then
        xdotool windowactivate --sync "$win" 2>/dev/null || true
    fi
    xdotool windowraise "$win" 2>/dev/null || true
    xdotool windowfocus "$win" 2>/dev/null || true
    # Let the embedder process the FocusIn before keys arrive.
    sleep 0.12
    local focused
    focused="$(xdotool getwindowfocus 2>/dev/null || echo 0)"
    [[ "$focused" == "$win" ]] && return 0
    # Some GTK stacks focus the engine's child window instead of the toplevel,
    # so accept a DESCENDANT of the resolved toplevel — but only that. Accepting
    # "any window of this pid" (the first cut) would have passed on GTK's 10x10
    # group-leader and 1x1 helper windows, the very windows resolve_window
    # rejects: keys would then go nowhere while the helper reported success.
    if _win_is_descendant "$focused" "$win"; then return 0; fi
    echo "focus verification failed (focused=$focused want=$win pid=$PID)" >&2
    return 1
}

# True when $1 is $2 or lies under it in the X window tree.
_win_is_descendant() {
    local node="$1" root="$2" depth=0 parent
    [[ "$node" =~ ^[0-9]+$ ]] || return 1
    while (( depth < 8 )); do
        [[ "$node" == "$root" ]] && return 0
        parent="$(xdotool getwindowparent "$node" 2>/dev/null || true)"
        [[ -z "$parent" || "$parent" == "$node" ]] && return 1
        node="$parent"
        depth=$((depth + 1))
    done
    return 1
}

# Decode straight into a pipe. `$(base64 -d ...)` would be argv-safe but NOT
# byte-exact: command substitution strips every trailing newline, so text
# ending in LF (a multiline composer body) silently lost it.
b64_to() { printf '%s' "$1" | base64 -d; }

# X11 has no clipboard daemon: whoever sets a selection must STAY ALIVE to
# serve it. `xclip -i` therefore forks a server child and the parent exits — and
# that child INHERITS this script's stdout/stderr. The Dart driver reads the
# helper's pipes to EOF, so an inherited pipe means the driver blocks forever
# after the helper has already exited (observed 2026-09-05: a 6-minute hang at
# "registering ... via real UI" with one live `xclip -selection clipboard -i`).
# Redirecting the whole invocation to /dev/null is what closes that loop.
# Takes the BASE64 form and pipes the decoded bytes straight in (see b64_to).
set_clipboard_b64() {
    local enc="$1" rc
    if command -v xclip >/dev/null 2>&1; then
        b64_to "$enc" | xclip -selection clipboard -i >/dev/null 2>&1
        rc=$?
        # The forked server needs a moment to own the selection before a paste
        # asks for it.
        sleep 0.15
        return $rc
    fi
    if command -v xsel >/dev/null 2>&1; then
        b64_to "$enc" | xsel --clipboard --input >/dev/null 2>&1
        rc=$?
        sleep 0.15
        return $rc
    fi
    echo "no xclip/xsel for clipboard access (apt install xclip)" >&2
    return 2
}

# Only the verbs that actually deliver input need a window; the clipboard-only
# verbs are display-scoped, not window-scoped, and must not fail on an instance
# whose window is momentarily unresolvable (or on a synthetic pid).
WIN=""
case "$VERB" in
    clipboard|clipget|clipimage) ;;
    *)
        WIN="$(resolve_window)" || exit $?
        ;;
esac

case "$VERB" in
    resolve)
        printf '%s\n' "$WIN"
        ;;
    focus)
        enter_input "$WIN"
        ;;
    type)
        enter_input "$WIN" || exit 1
        # --clearmodifiers so a stray latched modifier cannot shift the text.
        # 25 ms/key mirrors the Windows backend: the embedder redispatches
        # unhandled keys asynchronously and drops characters typed faster.
        # --file - reads the text from STDIN verbatim (no argv, no command
        # substitution), so a trailing newline survives.
        b64_to "$ARG3" | xdotool type --clearmodifiers --delay "${ARG4:-25}" --file - || exit 1
        sleep 0.15
        ;;
    key)
        enter_input "$WIN" || exit 1
        xdotool key --clearmodifiers -- "$ARG3" || exit 1
        sleep 0.12
        ;;
    paste)
        set_clipboard_b64 "$ARG3" || exit 1
        enter_input "$WIN" || exit 1
        xdotool key --clearmodifiers -- ctrl+v || exit 1
        sleep 0.15
        ;;
    clipboard)
        set_clipboard_b64 "$ARG3" || exit 1
        ;;
    clipget)
        # Read the CLIPBOARD selection. The app itself owns it after an in-app
        # copy (GTK), so this is a genuine OS-level read — the Linux answer to
        # `pbpaste` / `Get-Clipboard`. An empty/unowned selection is not an
        # error: the caller polls.
        if command -v xclip >/dev/null 2>&1; then
            xclip -selection clipboard -o 2>/dev/null || true
        elif command -v xsel >/dev/null 2>&1; then
            xsel --clipboard --output 2>/dev/null || true
        else
            echo "clipget needs xclip or xsel" >&2; exit 2
        fi
        ;;
    clipimage)
        # Image on the clipboard for the real Ctrl+V image-paste case. Same
        # selection-owner lifetime as set_clipboard_b64, and the same reason for
        # the redirect — with an explicit `&` because xclip does NOT fork for a
        # non-text target, it stays in the foreground serving the selection.
        [[ -r "$ARG3" ]] || { echo "clipimage: no such file: $ARG3" >&2; exit 2; }
        command -v xclip >/dev/null 2>&1 || { echo "clipimage needs xclip" >&2; exit 2; }
        xclip -selection clipboard -t image/png -i "$ARG3" >/dev/null 2>&1 </dev/null &
        disown 2>/dev/null || true
        sleep 0.4
        # Prove the selection is actually being served before returning: a
        # silently-dead owner would make the paste a no-op the case then blames
        # on the app.
        xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -q 'image/png' \
            || { echo "clipimage: clipboard does not offer image/png" >&2; exit 1; }
        ;;
    clear)
        # Select-all by CARET MOVEMENT (same rationale as the Windows backend):
        # works for single- and multi-line editables and never depends on a
        # select-all binding being wired.
        enter_input "$WIN" || exit 1
        xdotool key --clearmodifiers -- ctrl+End
        sleep 0.06
        xdotool key --clearmodifiers -- ctrl+shift+Home
        sleep 0.06
        xdotool key --clearmodifiers -- BackSpace
        sleep 0.09
        ;;
    *)
        echo "unknown verb: $VERB" >&2
        exit 2
        ;;
esac
