"""Actual library ordering-index integrity and recovery; isolated local files only."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


def worker(library, options):
    path, payload, expected = options
    native = ctypes.CDLL(str(library))
    configure = native.tim2tox_ffi_log_configure_owned
    configure.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_uint64)]
    configure.restype = ctypes.c_int32
    append = native.tim2tox_ffi_log_append_owned
    append.argtypes = [ctypes.c_uint64, ctypes.c_void_p, ctypes.c_size_t]
    append.restype = ctypes.c_int32
    release = native.tim2tox_ffi_log_release_owned
    release.argtypes = [ctypes.c_uint64]
    release.restype = ctypes.c_int32
    generation = ctypes.c_uint64()
    status = configure(os.fsencode(path), ctypes.byref(generation))
    assert status == int(expected), (status, expected)
    if status == 0:
        body = payload.encode()
        assert generation.value and append(generation.value, body, len(body)) == 0
        assert release(generation.value) == 0
    else:
        assert generation.value == 0


def claim(library, path, payload="new-record\n", expected=0):
    result = subprocess.run([sys.executable, __file__, str(library), "--worker",
                             str(path), payload, str(expected)], capture_output=True)
    assert result.returncode == 0, result.stderr.decode(errors="replace")


def checksum(slot):
    value = 14695981039346656037
    for byte in slot[:504]:
        value = ((value ^ byte) * 1099511628211) & ((1 << 64) - 1)
    return value


def mutate_slots(path, mutation):
    data = bytearray(path.read_bytes())
    assert len(data) == 1024
    for start in (0, 512):
        slot = data[start:start + 512]
        mutation(slot)
        struct.pack_into("<Q", slot, 504, checksum(slot))
        data[start:start + 512] = slot
    path.write_bytes(data)


def verify(library, root, fault_probe=None):
    report = {}
    directory = root / "same-time-low-suffix"
    directory.mkdir()
    marker = b"RECENT-ARCHIVE\n"
    for number in range(2, 11):
        (directory / f"app_100_{number}.log").write_bytes(f"old-{number}\n".encode())
    (directory / "app_100.log").write_bytes(marker + b"x" * (10485760 - len(marker)))
    for p in directory.glob("*.log"):
        os.utime(p, ns=(1700000000000000000,) * 2)
    claim(library, directory / "app_100.log")
    assert len(list(directory.glob("*.log"))) == 10
    assert sum(p.read_bytes().startswith(marker) for p in directory.glob("*.log")) == 1
    report["same_timestamp_legacy_2_through_10_keeps_recent_archive"] = "passed"

    directory = root / "repeated-rotation"
    directory.mkdir()
    active = directory / "app_100.log"
    for number in range(16):
        marker = f"retained-{number:02d}\n".encode()
        active.write_bytes(marker + b"x" * (10485760 - len(marker)))
        for p in directory.glob("*.log"):
            os.utime(p, ns=(1700000000000000000 - number * 1000000000,) * 2)
        claim(library, active)
        assert len(list(directory.glob("*.log"))) <= 10
        assert all(p.stat().st_size <= 10485760 for p in directory.glob("*.log"))
    retained = {p.read_bytes()[:12].decode().strip() for p in directory.glob("*.log") if p != active}
    assert retained == {f"retained-{number:02d}" for number in range(7, 16)}
    report["sixteen_restart_rotations_numeric_suffix_reuse_and_clock_rollback"] = "passed"

    directory = root / "short-session-rollback"
    directory.mkdir()
    names = [f"app_{200 - number}.log" for number in range(12)]
    for number, name in enumerate(names):
        claim(library, directory / name, f"short-{number}\n")
        for p in directory.glob("*.log"):
            os.utime(p, ns=(1700000000000000000,) * 2)
    assert {p.name for p in directory.glob("*.log")} == set(names[-10:])
    directory = root / "reclaimed-custom"
    directory.mkdir()
    for number in range(1, 11):
        claim(library, directory / f"app_{number}.log", f"original-{number}\n")
    claim(library, directory / "app_1.log", "reclaimed-latest\n")
    claim(library, directory / "app_11.log", "last\n")
    assert b"reclaimed-latest" in (directory / "app_1.log").read_bytes()
    assert len(list(directory.glob("*.log"))) == 10
    report["short_sessions_and_reclaimed_custom_active_have_persistent_order"] = "passed"
    for damaged in (0, 1):
        directory = root / f"one-slot-{damaged}"
        directory.mkdir()
        first = directory / "app_1.log"
        claim(library, first, "preserved\n")
        lock = directory / ".app.log.sink-lock"
        identity = lock.stat().st_ino
        data = bytearray(lock.read_bytes())
        data[damaged * 512 + 50] ^= 1
        lock.write_bytes(data)
        claim(library, directory / "app_2.log")
        assert first.read_bytes() == b"preserved\n" and lock.stat().st_ino == identity
        repaired = lock.read_bytes()
        assert len(repaired) == 1024 and repaired[:512] == repaired[512:]
    report["either_single_slot_recovers_without_lock_inode_replacement"] = "passed"

    for case in ("both-corrupt", "partial-size", "duplicate-id", "duplicate-rank",
                 "counter-below-rank", "counter-overflow", "generation-overflow"):
        directory = root / case
        directory.mkdir()
        claim(library, directory / "app_1.log", "old-one\n")
        claim(library, directory / "app_2.log", "old-two\n")
        lock = directory / ".app.log.sink-lock"
        original = {p.name: p.read_bytes() for p in directory.glob("*.log")}
        if case == "both-corrupt":
            data = bytearray(lock.read_bytes())
            data[50] ^= 1
            data[562] ^= 1
            lock.write_bytes(data)
        elif case == "partial-size":
            lock.write_bytes(lock.read_bytes()[:512])
        else:
            def mutation(slot):
                if case == "duplicate-id":
                    slot[56:72] = slot[32:48]
                elif case == "duplicate-rank":
                    slot[72:80] = slot[48:56]
                elif case == "counter-below-rank":
                    struct.pack_into("<Q", slot, 16, 0)
                elif case == "counter-overflow":
                    struct.pack_into("<Q", slot, 16, (1 << 64) - 1)
                else:
                    struct.pack_into("<Q", slot, 8, (1 << 64) - 1)
            mutate_slots(lock, mutation)
        claim(library, directory / "app_3.log", expected=3)
        assert not (directory / "app_3.log").exists()
        assert original == {p.name: p.read_bytes() for p in directory.glob("*.log")}
    report["bad_slots_semantic_duplicates_and_overflow_fail_closed"] = "passed"

    directory = root / "external-replacement"
    directory.mkdir()
    active = directory / "app_1.log"
    claim(library, active, "original\n")
    replacement = directory / "replacement"
    replacement.write_bytes(b"unknown-restored-content\n")
    replacement.replace(active)
    claim(library, directory / "app_2.log", expected=3)
    assert active.read_bytes() == b"unknown-restored-content\n"
    # Explicit harness owner action after confirmed process exit; the native
    # refusal itself does not delete restored data or reset its index.
    active.unlink()
    claim(library, directory / "app_2.log", "explicit-reclaim\n")
    assert (directory / "app_2.log").read_bytes() == b"explicit-reclaim\n"
    empty = directory / "app_3.log"
    empty.touch()
    claim(library, empty, "bound-before-body\n")
    report["unknown_nonempty_refused_explicit_delete_reclaim_and_empty_recovery"] = "passed"

    directory = root / "overfull-preupgrade"
    directory.mkdir()
    for number in range(1, 16):
        p = directory / f"app_{number}.log"
        p.write_text(f"legacy-{number}\n", encoding="utf-8")
        os.utime(p, ns=(1700000000000000000,) * 2)
    claim(library, directory / "app_99.log", "newest\n")
    assert {p.name for p in directory.glob("*.log")} == {
        "app_99.log", *(f"app_{number}.log" for number in range(7, 16))}
    assert (directory / ".app.log.sink-lock").stat().st_size == 1024
    report["initial_overfull_legacy_natural_order_and_unchanged_budget"] = "passed"

    if fault_probe:
        for mode in ("flush", "partial", "second-partial"):
            directory = root / f"fault-{mode}"
            directory.mkdir()
            old = directory / "app_1.log"
            old.write_bytes(b"legacy-must-not-change\n")
            target = directory / "app_2.log"
            subprocess.run([str(fault_probe), str(target), mode], check=True)
            assert not target.exists() and old.read_bytes() == b"legacy-must-not-change\n"
            if mode in ("flush", "second-partial"):
                claim(library, target, "recovered-valid-slot\n")
            else:
                claim(library, target, expected=3)
        directory = root / "victim-replaced"
        directory.mkdir()
        for number in range(1, 11):
            claim(library, directory / f"app_{number}.log", f"record-{number}\n")
        subprocess.run([str(fault_probe), str(directory / "app_11.log"), "victim-replaced"], check=True)
        assert (directory / "app_1.log").read_bytes() == b"record-2\n"
        assert (directory / "saved-original").read_bytes() == b"record-1\n"
        assert not (directory / "app_11.log").exists()
        report["actual_partial_flush_failures_and_ranked_victim_swap"] = "passed"
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("library", type=Path)
    parser.add_argument("--worker", nargs=3)
    parser.add_argument("--fault-probe", type=Path)
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    if args.worker:
        worker(args.library, args.worker)
        return
    assert args.evidence is not None
    before = hashlib.sha256(args.library.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="toxee-log-order-") as temporary:
        report = verify(args.library, Path(temporary).resolve(), args.fault_probe)
    assert hashlib.sha256(args.library.read_bytes()).hexdigest() == before
    args.evidence.write_text(json.dumps({"library_sha256": before, "checks": report,
                                        "outcome": "passed"}, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
