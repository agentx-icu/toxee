#!/usr/bin/env python3
"""Run two isolated native peers; never accept skipped tests as success."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--harness", type=Path, help="Prepared Flutter project with test dependencies")
    parser.add_argument("--native-lib", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout", type=int, default=420)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    harness = (args.harness or project).resolve()
    library = args.native_lib.resolve(strict=True)
    output = args.output or Path(tempfile.mkdtemp(prefix="toxee-location-network-"))
    output.mkdir(parents=True, exist_ok=True)
    exchange = Path(tempfile.mkdtemp(prefix="exchange-", dir=output)).resolve()
    test = project / "test/native/location_network_peer_test.dart"
    processes = {}
    logs = {}
    seen = set()
    timed_out = False
    try:
        for role in ("alice", "bob"):
            env = os.environ.copy()
            env.update({
                "TOXEE_LOCATION_PEER_ROLE": role,
                "TOXEE_LOCATION_PEER_EXCHANGE": str(exchange),
                "TOXEE_LOCATION_NATIVE_LIB": str(library),
                "RUN_VIRTUAL": "0",
                "PARALLEL_WORKERS": "2",
            })
            logs[role] = (output / f"{role}.log").open("w")
            processes[role] = subprocess.Popen(
                ["flutter", "test", "--no-pub", str(test), "--reporter", "expanded"],
                cwd=harness,
                env=env,
                stdout=logs[role],
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            print(f"Started {role}; runner PID {processes[role].pid}", flush=True)
        deadline = time.monotonic() + args.timeout
        while any(process.poll() is None for process in processes.values()):
            for marker in sorted(exchange.glob("*.json")):
                if marker.name not in seen:
                    seen.add(marker.name)
                    print(f"Verified phase: {marker.stem}", flush=True)
            if time.monotonic() >= deadline:
                timed_out = True
                break
            # A peer cannot complete if the other has already failed.
            if any(process.poll() not in (None, 0) for process in processes.values()):
                break
            time.sleep(0.25)
    finally:
        for process in processes.values():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
        for log in logs.values():
            log.close()

    statuses = {role: process.returncode for role, process in processes.items()}
    passed = not timed_out and len(statuses) == 2 and all(code == 0 for code in statuses.values())
    peers = {}
    for role in ("alice", "bob"):
        for step in ("passed", "endpoint", "discovered", "location-received",
                     "group-ready", "group-location-sent", "group-location-received"):
            marker = exchange / f"{role}.{step}.json"
            if not marker.exists():
                passed = False
                continue
            peers.setdefault(role, {})[step] = json.loads(marker.read_text())
    if passed:
        passed = peers["alice"]["endpoint"]["pid"] != peers["bob"]["endpoint"]["pid"]
        passed = passed and all(peer["passed"]["nativePackets"] > 0 for peer in peers.values())
    result = {
        "passed": passed,
        "processExitCodes": statuses,
        "timedOut": timed_out,
        "transport": "Real native Tox sockets between two independent processes on loopback UDP",
        "locationSource": "Fixed synthetic test coordinates; no OS GPS claim",
        "library": str(library),
        "librarySha256": hashlib.sha256(library.read_bytes()).hexdigest(),
        "exchange": str(exchange),
        "peers": peers,
    }
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"Result: {'PASS' if passed else 'FAIL'}; exit codes {statuses}", flush=True)
    print(f"Artifacts: {output.resolve()}", flush=True)
    if not passed:
        for role in ("alice", "bob"):
            log = output / f"{role}.log"
            if log.exists():
                print(f"{role} log tail:\n" + "\n".join(log.read_text(errors="replace").splitlines()[-35:]))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
