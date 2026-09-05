#!/usr/bin/env bash
# Headless Linux session prerequisites for running the real toxee app, shared by
# `launch_linux_fixture_c_pair.sh`, `launch_toxee_linux_instance.sh` and
# `run_toxee_linux.sh` (each of which used to carry its own copy).
#
# SOURCE it, then call `toxee_linux_headless_env <runtime_root>`. It exports
# DISPLAY / GDK_BACKEND / DBUS_SESSION_BUS_ADDRESS / GNOME_KEYRING_CONTROL for
# the caller, so every process the caller launches afterwards inherits them,
# and RECORDS them in `<runtime_root>/headless.env` so a LATER, separate
# process (the relaunch launcher, spawned by the driver with a bare
# environment) adopts the SAME session instead of building a second one.
#
# Three things a GTK toxee needs that an SSH login does not provide:
#
#   1. An X display. Synthetic flutter_skill input AND xdotool OS input both
#      need a live GTK surface, not a physical screen — Xvfb is enough.
#
#   2. GDK actually USING it. GDK tries Wayland FIRST, and its Wayland backend
#      falls back to the well-known socket name `wayland-0` in $XDG_RUNTIME_DIR
#      when $WAYLAND_DISPLAY is unset — which an SSH session on a machine with
#      a logged-in desktop (any dev workstation, a Parallels VM) has. So the
#      "headless" pair silently opened its windows on the CONSOLE USER'S
#      COMPOSITOR: Xvfb stayed empty (`xwininfo -root -tree` -> 0 children,
#      verified 2026-09-05 by strace'ing the connect() to
#      /run/user/1000/wayland-0), two real windows appeared on someone's
#      desktop, and every X-level operation — xdotool OS input above all — had
#      nothing to attach to. `GDK_BACKEND=x11` is the fix, applied only where X
#      is REQUIRED (we own the Xvfb, or XTEST input is on) so a developer on a
#      Wayland desktop keeps the native session the app really ships as.
#
#   3. A Secret Service with a WRITABLE DEFAULT COLLECTION. flutter_secure_storage
#      (password_verifier's hash+salt) calls libsecret's *_sync API ON THE GTK
#      PLATFORM THREAD; if that store has to create the default collection it
#      returns a Prompt, and with no prompter on a headless box the nested
#      g_main_loop_run NEVER RETURNS. The platform thread is then dead: no
#      platform channel, no VM-service extension — the driver sees every l3_*
#      call time out with "app isolate unresponsive" a minute later, with
#      nothing in the app log to explain it. (Diagnosed 2026-09-05 with a gdb
#      backtrace of the wedged process: secret_password_storev_sync ->
#      g_main_loop_run inside SecretStorage::warmupKeyring.)
#
# The keyring recipe this file replaced — `gnome-keyring-daemon --replace
# --unlock --components=secrets` fed an empty password — LOOKED like it worked
# (exit 0, daemon running, `org.freedesktop.secrets` on the bus) but produced
# ONLY the in-memory `session` collection: no login keyring, no `default`
# alias, so the very first store prompted and hung. Two changes fix it:
#
#   * `--login` mode (the PAM entry point) is what CREATES + unlocks the login
#     keyring and aliases it to `default`; `--unlock` only unlocks one that
#     already exists.
#   * the daemon runs on a PRIVATE session bus with a PRIVATE keyring home
#     under the runtime root, so a headless launch neither hijacks
#     (`--replace`) nor deletes the keyring of a real desktop session logged in
#     on the same machine. The old code did both.
#
# The default collection is PROBED before returning (`ReadAlias("default")`,
# plus a real store when `secret-tool` is installed), so a broken keyring fails
# HERE, loudly, instead of wedging the app one minute later.

# Start Xvfb on :99 when the caller has no $DISPLAY, and pin GDK to X11 where X
# is required. Records the pid under <runtime_root>/xvfb.pid for the stop
# script. Honors an existing $DISPLAY.
_toxee_linux_start_xvfb() {
    local runtime_root="$1"
    if [[ -z "${DISPLAY:-}" || "${TOXEE_LINUX_OS_INPUT:-}" == "1" ]]; then
        export GDK_BACKEND=x11
        unset WAYLAND_DISPLAY
    fi
    [[ -n "${DISPLAY:-}" ]] && return 0
    if ! command -v Xvfb >/dev/null 2>&1; then
        echo "[WARN] no \$DISPLAY and no Xvfb - the GTK app will fail to open a surface" >&2
        return 0
    fi
    export DISPLAY="${TOXEE_LINUX_XVFB_DISPLAY:-:99}"
    if ls "/tmp/.X11-unix/X${DISPLAY#:}" >/dev/null 2>&1; then
        return 0  # someone already serves this display
    fi
    echo "[INFO] No \$DISPLAY - starting Xvfb $DISPLAY (1920x1080)"
    Xvfb "$DISPLAY" -screen 0 1920x1080x24 >/dev/null 2>&1 &
    echo "$!" > "$runtime_root/xvfb.pid"
    sleep 1
}

# True when the session bus in the CURRENT environment exposes a default
# collection that can be written without a prompt — i.e. either a real desktop
# whose keyring is unlocked, or a private session we (or an earlier launcher)
# already built. Used both to skip setup and to validate an adopted session.
_toxee_linux_secret_default_ok() {
    local alias
    alias="$(timeout 8 gdbus call --session \
        -d org.freedesktop.secrets -o /org/freedesktop/secrets \
        -m org.freedesktop.Secret.Service.ReadAlias default 2>/dev/null || true)"
    # "(objectpath '/',)" = no default alias => a store would prompt.
    [[ -n "$alias" && "$alias" != *"'/'"* ]] || return 1
    if command -v secret-tool >/dev/null 2>&1; then
        printf 'probe' | timeout 10 secret-tool store --label=toxee-probe \
            toxee probe >/dev/null 2>&1 || return 1
    fi
    return 0
}

# Adopt the session an earlier launcher recorded, if it is still usable.
# THIS IS WHAT MAKES RELAUNCH WORK: `launch_toxee_linux_instance.sh` runs in a
# fresh shell spawned by the driver, with no DISPLAY and no bus address. Left
# to build its own session it would wipe the private keyring home out from
# under the LIVE peer and hand the relaunched instance a different Secret
# Service — i.e. a different password-verifier store than the account was
# registered against.
_toxee_linux_adopt_env() {
    local runtime_root="$1" env_file="$runtime_root/headless.env"
    [[ -r "$env_file" ]] || return 1
    # Snapshot what we are about to overwrite. A FAILED adoption must leave the
    # environment exactly as it found it: a recorded-but-dead $DISPLAY that
    # survived a failed probe would make _toxee_linux_start_xvfb take its
    # "caller already has a display" early return and the whole setup would
    # then report success against an X server that is gone.
    local had_display="${DISPLAY+set}" had_bus="${DBUS_SESSION_BUS_ADDRESS+set}"
    local had_ctl="${GNOME_KEYRING_CONTROL+set}" had_gdk="${GDK_BACKEND+set}"
    local old_display="${DISPLAY:-}" old_bus="${DBUS_SESSION_BUS_ADDRESS:-}"
    local old_ctl="${GNOME_KEYRING_CONTROL:-}" old_gdk="${GDK_BACKEND:-}"
    _toxee_linux_restore_env() {
        if [[ "$had_display" == set ]]; then export DISPLAY="$old_display"; else unset DISPLAY; fi
        if [[ "$had_bus" == set ]]; then export DBUS_SESSION_BUS_ADDRESS="$old_bus"; else unset DBUS_SESSION_BUS_ADDRESS; fi
        if [[ "$had_ctl" == set ]]; then export GNOME_KEYRING_CONTROL="$old_ctl"; else unset GNOME_KEYRING_CONTROL; fi
        if [[ "$had_gdk" == set ]]; then export GDK_BACKEND="$old_gdk"; else unset GDK_BACKEND; fi
    }
    # shellcheck disable=SC1090
    source "$env_file"
    if [[ -z "${DISPLAY:-}" ]]; then _toxee_linux_restore_env; return 1; fi
    # X server still alive?
    if command -v xdpyinfo >/dev/null 2>&1; then
        if ! timeout 5 xdpyinfo >/dev/null 2>&1; then
            _toxee_linux_restore_env; return 1
        fi
    fi
    if ! _toxee_linux_secret_default_ok; then
        _toxee_linux_restore_env; return 1
    fi
    echo "[INFO] Adopted the headless session recorded in $env_file"
    return 0
}

_toxee_linux_write_env() {
    local runtime_root="$1"
    {
        printf 'export DISPLAY=%q\n' "${DISPLAY:-}"
        [[ -n "${GDK_BACKEND:-}" ]] && printf 'export GDK_BACKEND=%q\n' "$GDK_BACKEND"
        [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && \
            printf 'export DBUS_SESSION_BUS_ADDRESS=%q\n' "$DBUS_SESSION_BUS_ADDRESS"
        [[ -n "${GNOME_KEYRING_CONTROL:-}" ]] && \
            printf 'export GNOME_KEYRING_CONTROL=%q\n' "$GNOME_KEYRING_CONTROL"
        printf 'unset WAYLAND_DISPLAY\n'
    } > "$runtime_root/headless.env"
    # `linux_os_input.sh` reads this when the driver's own env has no $DISPLAY.
    [[ -n "${DISPLAY:-}" ]] && printf '%s' "$DISPLAY" > "$runtime_root/display"
}

# Private session bus + private-home gnome-keyring with an unlocked login
# keyring aliased to `default`. Exports DBUS_SESSION_BUS_ADDRESS so the app
# inherits it; pid/address files under <runtime_root> for the stop script.
_toxee_linux_start_keyring() {
    local runtime_root="$1"
    if ! command -v gnome-keyring-daemon >/dev/null 2>&1; then
        echo "[WARN] gnome-keyring-daemon missing - flutter_secure_storage will hang the" >&2
        echo "[WARN] GTK platform thread on its first store (apt install gnome-keyring)" >&2
        return 0
    fi

    local xdg="$runtime_root/xdg"
    rm -rf "$xdg"
    mkdir -p "$xdg/keyrings"
    chmod 700 "$xdg" "$xdg/keyrings"

    if command -v dbus-daemon >/dev/null 2>&1; then
        # A private bus keeps a headless run from touching (or being disturbed
        # by) a desktop session logged in on the same machine. The address and
        # pid come back on DEDICATED fds — `--print-pid` as a bare flag is a
        # parse error ("Invalid file descriptor"), and the pid is what teardown
        # needs: a forked dbus-daemon does NOT carry its address in argv, so
        # there is nothing for a `pkill -f` to match.
        rm -f "$runtime_root/dbus.address" "$runtime_root/dbus.pid"
        dbus-daemon --session --fork \
            --print-address=3 --print-pid=4 \
            3>"$runtime_root/dbus.address" 4>"$runtime_root/dbus.pid" 2>/dev/null || true
        local addr
        addr="$(cat "$runtime_root/dbus.address" 2>/dev/null | tr -d '[:space:]')"
        if [[ -n "$addr" ]]; then
            export DBUS_SESSION_BUS_ADDRESS="$addr"
        else
            echo "[WARN] dbus-daemon --session failed; using the inherited bus" >&2
            rm -f "$runtime_root/dbus.address" "$runtime_root/dbus.pid"
        fi
    fi

    # --login (not --unlock): the PAM entry point, the only mode that CREATES
    # the login keyring and aliases it to `default`. Empty password = the
    # standard headless recipe; the keyring lives under the runtime root.
    printf '\n' | XDG_DATA_HOME="$xdg" gnome-keyring-daemon --daemonize --login \
        >"$runtime_root/keyring.env" 2>/dev/null || true
    # --start attaches the secrets component to the daemon just started (it
    # prints GNOME_KEYRING_CONTROL=..., prefixed by chatter on some builds, so
    # grep the assignment out rather than eval'ing the whole output).
    XDG_DATA_HOME="$xdg" gnome-keyring-daemon --start --components=secrets \
        >>"$runtime_root/keyring.env" 2>/dev/null || true
    local ctl
    ctl="$(grep -ao 'GNOME_KEYRING_CONTROL=[^ ]*' "$runtime_root/keyring.env" 2>/dev/null | tail -1 || true)"
    [[ -n "$ctl" ]] && export "${ctl?}"
    sleep 1

    if _toxee_linux_secret_default_ok; then
        echo "[INFO] Headless keyring ready (default collection writable, home: $xdg)"
        return 0
    fi
    echo "[ERROR] headless keyring has no writable default collection." >&2
    echo "[ERROR] flutter_secure_storage would block the GTK platform thread forever" >&2
    echo "[ERROR] (every l3_* call then times out as 'app isolate unresponsive')." >&2
    echo "[ERROR] bus=${DBUS_SESSION_BUS_ADDRESS:-<inherited>} keyring_home=$xdg" >&2
    return 1
}

# Public entry point. Safe to call when a real desktop session is present: the
# Xvfb branch is skipped when $DISPLAY is set, and the keyring branch is skipped
# when the session bus already offers a writable default collection.
toxee_linux_headless_env() {
    local runtime_root="${1:?usage: toxee_linux_headless_env <runtime_root>}"
    mkdir -p "$runtime_root"
    # Relaunch path first: reuse the live session rather than replacing it.
    _toxee_linux_adopt_env "$runtime_root" && return 0
    _toxee_linux_start_xvfb "$runtime_root"
    if _toxee_linux_secret_default_ok; then
        echo "[INFO] Session keyring already has a writable default collection"
        _toxee_linux_write_env "$runtime_root"
        return 0
    fi
    _toxee_linux_start_keyring "$runtime_root" || return 1
    _toxee_linux_write_env "$runtime_root"
}

# Kill <pid> only when it is still the process we started. `comm` alone is a
# weak identity (a recycled pid could belong to ANOTHER dbus-daemon/Xvfb — the
# desktop session's, say), so a distinctive fragment of OUR argv must match
# too: the `--print-address=3` we launch the bus with, the `:99` we launch Xvfb
# on. Both survive the fork.
_toxee_linux_kill_recorded() {
    local pid_file="$1" want_comm="$2" want_argv="$3" pid argv
    [[ -r "$pid_file" ]] || return 0
    pid="$(tr -d '[:space:]' < "$pid_file")"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        if [[ "$(cat "/proc/$pid/comm" 2>/dev/null || true)" == "$want_comm" ]]; then
            argv="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
            if [[ -z "$want_argv" || "$argv" == *"$want_argv"* ]]; then
                kill "$pid" 2>/dev/null || true
            fi
        fi
    fi
    rm -f "$pid_file"
}

# Tear down what toxee_linux_headless_env started (idempotent; used by the stop
# scripts). Only pids WE recorded, identity-checked.
toxee_linux_headless_env_stop() {
    local runtime_root="${1:?usage: toxee_linux_headless_env_stop <runtime_root>}"
    # The private bus first: gnome-keyring is its client and exits with it.
    _toxee_linux_kill_recorded "$runtime_root/dbus.pid" dbus-daemon '--print-address=3'
    _toxee_linux_kill_recorded "$runtime_root/xvfb.pid" Xvfb \
        "${TOXEE_LINUX_XVFB_DISPLAY:-:99}"
    rm -f "$runtime_root/dbus.address" "$runtime_root/headless.env" \
          "$runtime_root/display"
}
