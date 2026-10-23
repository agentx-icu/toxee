#!/usr/bin/env python3
"""Install final DEB in clean Ubuntu 24.04; exercise only X11 software-rendered startup.

No SDK, host desktop/data mounts, privileged container, store credentials or upload.
The GUI runs as the image's existing unprivileged nobody user. This does not
qualify RPM/Wayland/hardware, distribution signing or previous-version upgrades.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import signal
import subprocess
import sys
import tarfile
import time
import uuid


APPS = {
    "toxee": ("com.toxee.app.desktop", "libtim2tox_ffi.so"),
    "morsecq": ("icu.agentx.morsecq.desktop", None),
    "ditmesh": ("icu.agentx.ditmesh.desktop", "libtim2tox_ffi.so"),
}
ARCHES = {"x86_64": ("amd64", "x86_64"), "aarch64": ("arm64", "aarch64")}

CONTAINER_FUNCTIONS = r'''
copy_evidence() {
  local source="$1" target="$2" item status=0
  # Copy children, never the bind-mounted directory's own metadata. `cp -a
  # source/. target/` changed the host-owned root to root:root in actual CI.
  while IFS= read -r -d '' item; do
    cp -R -- "$item" "$target/" || status=$?
  done < <(find "$source" -mindepth 1 -maxdepth 1 -print0)
  return "$status"
}

inspect_dependency() {
  local file="$1" entry="$2" private_lib="$3" report="$4" status=0
  local output
  output="$(mktemp)"
  if [[ "$file" == "$entry" ]]; then
    printf '\n== %s (application loader; no LD_LIBRARY_PATH) ==\n' "$file" >> "$report"
    env -u LD_LIBRARY_PATH ldd "$file" > "$output" 2>&1 || status=$?
  else
    # A standalone plugin has no knowledge of the engine already loaded by
    # the executable. Inspect its closure against this package's private lib
    # directory only. This setting is never exported to the actual GUI launch.
    printf '\n== %s (private DSO closure: %s) ==\n' "$file" "$private_lib" >> "$report"
    env LD_LIBRARY_PATH="$private_lib" ldd "$file" > "$output" 2>&1 || status=$?
  fi
  cat "$output" >> "$report"
  if grep -Eq '=>[[:space:]]+not found|version .* not found' "$output"; then
    cat "$output"; rm -f "$output"
    echo 'Unresolved dependency before harness install' >&2; return 1
  fi
  if [[ "$status" != 0 ]] && ! grep -Eq 'not a dynamic executable|statically linked' "$output"; then
    cat "$output"; rm -f "$output"
    echo 'Dependency inspection failed' >&2; return 1
  fi
  rm -f "$output"
}
'''

# Do not install harness packages until the package's own dependency closure has
# been inspected. Otherwise X/WM/Python dependencies could conceal missing Depends.
SETUP = r'''set -euo pipefail
app="$1"; arch="$2"; expected_sha="$3"; logical_arch="$4"
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
mkdir -p /tmp/linux-smoke-evidence
''' + CONTAINER_FUNCTIONS + r'''
finish() {
  rc=$?; copy_status=0
  copy_evidence /tmp/linux-smoke-evidence /evidence || copy_status=$?
  if [[ "$rc" == 0 ]]; then rc="$copy_status"; fi
  exit "$rc"
}
trap finish EXIT
exec > >(tee /tmp/linux-smoke-evidence/container.log) 2>&1
printf '%s  /input/app.deb\n' "$expected_sha" | sha256sum -c -
cat /etc/os-release > /tmp/linux-smoke-evidence/os-release.txt
uname -a > /tmp/linux-smoke-evidence/kernel.txt
test "$(. /etc/os-release; printf '%s' "$ID:$VERSION_ID")" = ubuntu:24.04
test "$(dpkg --print-architecture)" = "$arch"
test "$(uname -m)" = "$logical_arch"
test "$(dpkg-deb -f /input/app.deb Package)" = "$app"
test "$(dpkg-deb -f /input/app.deb Architecture)" = "$arch"
dpkg-deb -f /input/app.deb > /tmp/linux-smoke-evidence/deb-control.txt
dpkg-query -W > /tmp/linux-smoke-evidence/packages-before-install.txt
apt-get update
apt-get install -y --no-install-recommends /input/app.deb
test "$(dpkg-query -W -f='${Status}' "$app")" = 'install ok installed'
dpkg-query -W > /tmp/linux-smoke-evidence/packages-before-harness.txt
entry="/opt/$app/$app"
test -x "$entry"
test -f "/opt/$app/lib/libflutter_linux_gtk.so"
if [[ "$app" != morsecq ]]; then test -f "/opt/$app/lib/libtim2tox_ffi.so"; fi
inspect_dependency "$entry" "$entry" "/opt/$app/lib" /tmp/linux-smoke-evidence/ldd-before-harness.txt
while IFS= read -r -d '' file; do
  [[ "$file" != "$entry" ]] || continue
  magic="$(od -An -tx1 -N4 "$file" | tr -d ' \n')"
  if [[ "$magic" == 7f454c46 ]]; then
    inspect_dependency "$file" "$entry" "/opt/$app/lib" /tmp/linux-smoke-evidence/ldd-before-harness.txt
  fi
done < <(find "/opt/$app" -type f -print0)
if [[ "$app" == morsecq || "$app" == ditmesh ]]; then
  for tool in parecord pactl gdbus; do command -v "$tool"; done
fi
apt-get install -y --no-install-recommends python3 xvfb twm x11-utils dbus-x11 libgl1-mesa-dri xfonts-base fonts-dejavu-core
dpkg-query -W > /tmp/linux-smoke-evidence/packages-after-harness.txt
install -d -o nobody -g nogroup -m 700 /tmp/linux-smoke-user
for dir in data config cache runtime; do
  install -d -o nobody -g nogroup -m 700 "/tmp/linux-smoke-user/$dir"
done
chmod 777 /tmp/linux-smoke-evidence
set +e
runuser -u nobody -- env \
  XDG_DATA_HOME=/tmp/linux-smoke-user/data \
  XDG_CONFIG_HOME=/tmp/linux-smoke-user/config \
  XDG_CACHE_HOME=/tmp/linux-smoke-user/cache \
  XDG_RUNTIME_DIR=/tmp/linux-smoke-user/runtime \
  dbus-run-session -- python3 /checks/check.py --inside --app "$app" --architecture "$logical_arch"
gui_status=$?
apt-get remove -y "$app"
remove_status=$?
python3 /checks/check.py --uninstalled --app "$app" --architecture "$logical_arch"
check_status=$?
set -e
test "$gui_status" = 0 && test "$remove_status" = 0 && test "$check_status" = 0
'''


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, **kwargs)


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def package_inventory(package):
    """Read data.tar without extracting paths supplied by an archive."""
    process = subprocess.Popen(["dpkg-deb", "--fsys-tarfile", str(package)], stdout=subprocess.PIPE)
    result = {}
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
            for member in archive:
                name = member.name.removeprefix("./")
                path = PurePosixPath(name)
                if name in ("", "."):
                    continue
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("Unsafe package path")
                if member.isdir():
                    continue
                if name in result:
                    raise ValueError("Duplicate package path")
                item = {"mode": member.mode & 0o7777}
                if member.isfile():
                    stream = archive.extractfile(member)
                    digest = hashlib.sha256()
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(block)
                    item.update(kind="file", sha256=digest.hexdigest())
                elif member.issym():
                    item.update(kind="symlink", target=member.linkname)
                else:
                    raise ValueError("Unsupported package file type")
                result[name] = item
    finally:
        process.stdout.close()
        if process.wait() != 0:
            raise ValueError("Could not read final package data")
    if not result:
        raise ValueError("Final DEB has no files")
    return result


def verify_installed(app, expected, arch=None, root=Path("/")):
    entry = f"opt/{app}/{app}"
    desktop, _ = APPS[app]
    for name in (entry, f"usr/bin/{app}", f"usr/share/applications/{desktop}"):
        if expected.get(name, {}).get("kind") != "file":
            raise ValueError(f"Package omitted required file: {name}")
    if not any(name.startswith("usr/share/icons/hicolor/") for name in expected):
        raise ValueError("Package omitted hicolor icons")
    for name, item in expected.items():
        path = root / name
        if item["kind"] == "symlink":
            if not path.is_symlink() or os.readlink(path) != item["target"]:
                raise ValueError(f"Installed symlink differs: {name}")
        elif not path.is_file() or path.is_symlink() or sha256(path) != item["sha256"]:
            raise ValueError(f"Installed file differs from final DEB: {name}")
        if arch and item["kind"] == "file":
            with path.open("rb") as stream:
                header = stream.read(20)
            if header[:4] == b"\x7fELF":
                machine = int.from_bytes(header[18:20], "little" if header[5] == 1 else "big")
                if header[4] != 2 or machine != {"x86_64": 62, "aarch64": 183}[arch]:
                    raise ValueError(f"Wrong installed ELF CPU: {name}")
        if path.lstat().st_mode & 0o7777 != item["mode"]:
            raise ValueError(f"Installed mode differs: {name}")
    actual = {str(path.relative_to(root)) for path in (root / f"opt/{app}").rglob("*")
              if path.is_symlink() or path.is_file()}
    wanted = {name for name in expected if name.startswith(f"opt/{app}/")}
    if actual != wanted:
        raise ValueError("Installed application file set differs from final DEB")
    if not os.access(root / f"usr/bin/{app}", os.X_OK):
        raise ValueError("Installed launcher is not executable for the GUI user")


def matching_window(pid, env):
    tree = run(["xwininfo", "-root", "-tree"], env=env, capture_output=True, text=True).stdout
    for window in re.findall(r"^\s+(0x[0-9a-f]+)\s", tree, re.M | re.I):
        props = run(["xprop", "-id", window, "_NET_WM_PID", "WM_PROTOCOLS"],
                    env=env, capture_output=True, text=True).stdout
        if re.search(rf"_NET_WM_PID\(CARDINAL\) = {pid}\s*$", props, re.M):
            info = run(["xwininfo", "-id", window], env=env, capture_output=True, text=True).stdout
            if "Map State: IsViewable" in info and "WM_DELETE_WINDOW" in props:
                return int(window, 16), info + props
    return None


def close_window(window):
    """Send the ICCCM WM_DELETE_WINDOW request; never destroy or kill to pass."""
    class Data(ctypes.Union):
        _fields_ = [("b", ctypes.c_char * 20), ("s", ctypes.c_short * 10), ("l", ctypes.c_long * 5)]
    class Client(ctypes.Structure):
        _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                    ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
                    ("format", ctypes.c_int), ("data", Data)]
    class Event(ctypes.Union):
        _fields_ = [("xclient", Client), ("pad", ctypes.c_long * 24)]
    x11 = ctypes.CDLL("libX11.so.6")
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    x11.XInternAtom.restype = ctypes.c_ulong
    x11.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.POINTER(Event)]
    x11.XFlush.argtypes = [ctypes.c_void_p]
    x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
    display = x11.XOpenDisplay(None)
    if not display:
        raise ValueError("Could not open the private X display")
    try:
        event = Event()
        event.xclient.type = 33
        event.xclient.send_event = 1
        event.xclient.display = display
        event.xclient.window = window
        event.xclient.message_type = x11.XInternAtom(display, b"WM_PROTOCOLS", 0)
        event.xclient.format = 32
        event.xclient.data.l[0] = x11.XInternAtom(display, b"WM_DELETE_WINDOW", 0)
        if not x11.XSendEvent(display, window, 0, 0, ctypes.byref(event)):
            raise ValueError("WM_DELETE_WINDOW could not be delivered")
        x11.XFlush(display)
    finally:
        x11.XCloseDisplay(display)


def gui_check(app, arch):
    evidence = Path("/tmp/linux-smoke-evidence")
    expected = package_inventory(Path("/input/app.deb"))
    save(evidence / "installed-files.json", expected)
    verify_installed(app, expected, arch)
    if os.geteuid() == 0:
        raise ValueError("The GUI check must run unprivileged")
    env = dict(os.environ, DISPLAY=":88", GDK_BACKEND="x11", LIBGL_ALWAYS_SOFTWARE="1")
    os.environ["DISPLAY"] = env["DISPLAY"]
    processes, logs = [], []
    app_process = None
    try:
        for name, command in (("xvfb", ["Xvfb", ":88", "-screen", "0", "1280x800x24", "-nolisten", "tcp", "-ac"]),
                              ("twm", ["twm", "-f", "/tmp/linux-smoke-user/twmrc"])):
            if name == "twm":
                Path("/tmp/linux-smoke-user/twmrc").write_text(
                    'RandomPlacement\nNoGrabServer\nTitleFont "fixed"\nResizeFont "fixed"\n'
                    'MenuFont "fixed"\nIconFont "fixed"\nIconManagerFont "fixed"\n')
                deadline = time.monotonic() + 10
                while subprocess.run(["xdpyinfo"], env=env, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL).returncode and time.monotonic() < deadline:
                    time.sleep(.2)
            log = (evidence / f"{name}.log").open("w")
            logs.append(log)
            processes.append(subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT))
        log = (evidence / "application.log").open("w")
        logs.append(log)
        app_process = subprocess.Popen([f"/usr/bin/{app}"], cwd="/tmp/linux-smoke-user", env=env,
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + 45
        window = None
        while time.monotonic() < deadline:
            if app_process.poll() is not None:
                raise ValueError(f"Installed app exited before startup: {app_process.returncode}")
            if Path(f"/proc/{app_process.pid}/exe").resolve() == Path(f"/opt/{app}/{app}").resolve():
                window = matching_window(app_process.pid, env)
                if window:
                    break
            time.sleep(.25)
        if not window:
            raise ValueError("No visible, closable window for the installed app PID")
        time.sleep(10)
        if app_process.poll() is not None:
            raise ValueError("Installed app exited during startup")
        if any(process.poll() is not None for process in processes):
            raise ValueError("The private X server or window manager exited during startup")
        maps = Path(f"/proc/{app_process.pid}/maps").read_text()
        required = [f"/opt/{app}/lib/libflutter_linux_gtk.so"]
        if APPS[app][1]:
            required.append(f"/opt/{app}/lib/{APPS[app][1]}")
        mapped = {line.split(maxsplit=5)[5].strip() for line in maps.splitlines() if len(line.split(maxsplit=5)) == 6}
        for module in required:
            if str(Path(module).resolve()) not in mapped:
                raise ValueError(f"The installed PID did not load its packaged module: {module}")
        (evidence / "application-maps.txt").write_text(maps)
        (evidence / "application-window.txt").write_text(window[1])
        close_window(window[0])
        if app_process.wait(timeout=20) != 0:
            raise ValueError("Installed app did not exit successfully after WM_DELETE_WINDOW")
        try:
            os.killpg(app_process.pid, 0)
        except ProcessLookupError:
            pass
        else:
            raise ValueError("Installed application left a process in its launch group")
        verify_installed(app, expected, arch)
        save(evidence / "gui-result.json", {"outcome": "passed", "pid": app_process.pid,
             "architecture": arch, "modules": required, "window": "1280x800 X11, scale 1, software renderer",
             "scope": "Fresh Ubuntu24.04 DEB startup/close only; no hardware, account/network flow or upgrade qualification"})
    finally:
        if app_process and app_process.poll() is None:
            os.killpg(app_process.pid, signal.SIGKILL)
            app_process.wait()
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        for log in logs:
            log.close()


def uninstall_check(app):
    evidence = Path("/tmp/linux-smoke-evidence")
    expected = json.loads((evidence / "installed-files.json").read_text())
    for name in expected:
        path = Path("/") / name
        if path.exists() or path.is_symlink():
            raise ValueError(f"Uninstall retained packaged program file: {name}")
    status = subprocess.run(["dpkg-query", "-W", "-f=${Status}", app], capture_output=True, text=True)
    if status.returncode == 0 and "installed" in status.stdout.split():
        raise ValueError("Uninstall retained installed package registration")
    for proc in Path("/proc").glob("[0-9]*/exe"):
        try:
            if str(proc.resolve()).removesuffix(" (deleted)") == f"/opt/{app}/{app}":
                raise ValueError("Uninstall retained an application process")
        except (FileNotFoundError, PermissionError):
            continue
    save(evidence / "uninstall-result.json", {"outcome": "passed", "files_checked": len(expected),
         "scope": "Program files removed; user data retention is a separate policy/upgrade check"})


def host_check(args):
    if platform.system() != "Linux" or platform.machine() != ARCHES[args.architecture][1]:
        raise ValueError("Smoke requires a native matching Linux runner; emulation is not qualification")
    packages = list(args.package_dir.glob("*.deb"))
    if len(packages) != 1:
        raise ValueError("Expected exactly one final DEB in package directory")
    package = packages[0].resolve()
    evidence = args.evidence_dir.resolve()
    if evidence.exists() and any(evidence.iterdir()):
        raise ValueError("Evidence directory must be new or empty")
    evidence.mkdir(parents=True, exist_ok=True)
    arch = ARCHES[args.architecture][0]
    report = {"app": args.app, "deb_sha256": sha256(package), "host_architecture": platform.machine(),
              "container_architecture": arch, "outcome": "failed"}
    container_name = "linux-installed-smoke-" + uuid.uuid4().hex
    # Keep the report host-owned even if evidence export itself later fails.
    save(evidence / "result.json", report)
    primary_error = None
    try:
        run(["docker", "pull", "--platform", f"linux/{arch}", "ubuntu:24.04"], timeout=300)
        image = run(["docker", "image", "inspect", "ubuntu:24.04", "--format", "{{index .RepoDigests 0}}"],
                    capture_output=True, text=True).stdout.strip()
        if not re.fullmatch(r"ubuntu@sha256:[0-9a-f]{64}", image):
            raise ValueError("Could not pin the pulled official Ubuntu image digest")
        report["image"] = image
        run(["docker", "run", "--rm", "--interactive", "--name", container_name, "--platform", f"linux/{arch}",
             "--mount", f"type=bind,src={package},dst=/input/app.deb,readonly",
             "--mount", f"type=bind,src={Path(__file__).resolve()},dst=/checks/check.py,readonly",
             "--mount", f"type=bind,src={evidence},dst=/evidence", image,
             "bash", "-s", "--", args.app, arch, report["deb_sha256"], args.architecture], input=SETUP, text=True, timeout=720)
        for name in ("gui-result.json", "uninstall-result.json"):
            if json.loads((evidence / name).read_text()).get("outcome") != "passed":
                raise ValueError(f"Missing successful {name}")
        report["outcome"] = "passed"
    except BaseException as error:
        primary_error = error
        report["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        # subprocess timeout/cancellation may kill only the Docker client. The
        # unique name permits cleanup of this invocation's container alone.
        try:
            subprocess.run(["docker", "rm", "-f", container_name], timeout=30,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError):
            pass
        try:
            save(evidence / "result.json", report)
        except OSError as error:
            if primary_error is None:
                raise
            print(f"Also could not update the host report: {error}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", choices=APPS, required=True)
    parser.add_argument("--architecture", choices=ARCHES, required=True)
    parser.add_argument("--package-dir", type=Path)
    parser.add_argument("--evidence-dir", type=Path)
    parser.add_argument("--inside", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--uninstalled", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        if args.inside:
            gui_check(args.app, args.architecture)
        elif args.uninstalled:
            uninstall_check(args.app)
        else:
            if not args.package_dir or not args.evidence_dir:
                parser.error("Host mode requires --package-dir and --evidence-dir")
            host_check(args)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Linux installed smoke failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
