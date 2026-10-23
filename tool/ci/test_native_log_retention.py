#!/usr/bin/env python3
"""Actual pinned C++ logger retention regression; no production hooks or network."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

PIN = "5341e64ed62b81a94a311c768a73863a3cffcbb1"
LIMIT = 10 * 1024 * 1024


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, default=Path("third_party/tim2tox"))
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    source = args.source_dir.resolve()
    commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if commit != PIN:
        raise RuntimeError("Native retention fixture requires the exact pinned source")
    compiler = shutil.which("cl") if os.name == "nt" else None
    compiler = compiler or shutil.which("clang++") or shutil.which("g++")
    if not compiler:
        raise RuntimeError("A native C++20 compiler is required")
    report = {"source_commit": commit, "limit_bytes": LIMIT, "maximum_files": 10}
    manifest = json.loads(Path(__file__).resolve().parents[1].joinpath('native_log_overlays/manifest.json').read_text())
    report["source_sha256"] = {}
    for entry in manifest["files"]:
        contents = (source / entry["path"]).read_text().replace("\r\n", "\n").encode()
        digest = hashlib.sha256(contents).hexdigest()
        if digest != entry["after_sha256"]:
            raise RuntimeError("Native retention probe requires the source-verified app overlay")
        report["source_sha256"][entry["path"]] = digest

    # All generated binaries and repetitive log payloads are removed even when
    # the expected pre-fix assertion fails. Retain only the small evidence JSON.
    with tempfile.TemporaryDirectory(prefix="toxee-native-retention-") as temporary:
        root = Path(temporary).resolve()
        # Reproduce the original defect with the actual pristine pinned C++
        # implementation, not a replacement writer. The exact same legacy
        # producer is then run against the source-verified overlay below.
        baseline = root / "baseline"
        baseline.mkdir()
        for name in ["V2TIMLog.h", "V2TIMLog.cpp"]:
            (baseline / name).write_bytes(subprocess.check_output([
                "git", "-C", str(source), "show", f"{PIN}:source/{name}",
            ]))
        producer = Path(__file__).with_name("native_log_retention_probe.cpp").read_text()
        legacy = producer[producer.index("    logger.setLogFile(argv[1]);"):producer.index("\n#ifdef _WIN32\nint wmain")]
        baseline_probe = baseline / "probe.cpp"
        baseline_probe.write_text('#include "V2TIMLog.h"\n#include <array>\nint main(int argc, char** argv) {\n    if (argc != 2) return 2;\n    auto& logger = V2TIMLog::getInstance();\n' + legacy)
        baseline_executable = baseline / ("baseline.exe" if os.name == "nt" else "baseline")
        baseline_sources = [str(baseline / "V2TIMLog.cpp"), str(baseline_probe)]
        if Path(compiler).stem.lower() == "cl":
            baseline_command = [compiler, "/nologo", "/std:c++20", "/EHsc", "/I" + str(baseline), *baseline_sources, "/Fe:" + str(baseline_executable)]
        else:
            baseline_command = [compiler, "-std=c++20", "-pthread", "-I", str(baseline), *baseline_sources, "-o", str(baseline_executable)]
        subprocess.run(baseline_command, check=True, cwd=baseline)
        baseline_log = baseline / "app_1792746000000.log"
        subprocess.run([str(baseline_executable), str(baseline_log)], check=True, timeout=30)
        assert baseline_log.stat().st_size > LIMIT
        report["pristine_source_red"] = {"segment_bytes": baseline_log.stat().st_size, "over_limit": True}
        baseline_log.unlink()
        executable = root / ("retention-probe.exe" if os.name == "nt" else "retention-probe")
        sources = [str(source / "source/V2TIMLog.cpp"), str(Path(__file__).with_name("native_log_retention_probe.cpp").resolve())]
        if Path(compiler).stem.lower() == "cl":
            command = [compiler, "/nologo", "/std:c++20", "/EHsc", "/utf-8", "/I" + str(source / "source"), *sources, "/Fe:" + str(executable)]
        else:
            command = [compiler, "-std=c++20", "-pthread", "-I", str(source / "source"), *sources, "-o", str(executable)]
        subprocess.run(command, check=True, cwd=root)
        active = root / "app_1792746000000.log"
        subprocess.run([str(executable), str(active)], check=True, timeout=30)
        logs = sorted(root.glob("app_*.log"))
        report["segments"] = [{"name": p.name, "bytes": p.stat().st_size} for p in logs]
        report["recent_event_readable"] = any(b"event=retention_final" in p.read_bytes()[-4096:] for p in logs)
        report["total_bytes"] = sum(p.stat().st_size for p in logs)
        report["outcome"] = "passed" if len(logs) <= 10 and all(p.stat().st_size <= LIMIT for p in logs) and report["recent_event_readable"] else "failed"
        args.evidence.parent.mkdir(parents=True, exist_ok=True)
        args.evidence.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
        assert report["outcome"] == "passed", "Actual native logger exceeded the existing 10 MiB segment / ten-file retention budget"

        report["outcome"] = "in_progress"
        args.evidence.write_text(json.dumps(report, indent=2) + "\n")

        def check_ledger(directory, final=True):
            files = sorted(directory.glob("app_*.log"))
            assert len(files) <= 10
            assert all(p.stat().st_size <= LIMIT for p in files)
            assert not list(directory.glob("*.must-not-exist"))
            if final:
                assert any(b"event=retention_final" in p.read_bytes()[-4096:] for p in files)
            return [{"name": p.name, "bytes": p.stat().st_size} for p in files]

        owned = root / "owned"
        owned.mkdir()
        subprocess.run([str(executable), str(owned / "app_1792746000001.log"), "owned"], check=True, timeout=90)
        records = check_ledger(owned)
        assert len(records) == 10, "The actual default-budget producer must cross ten segments"
        assert any(b"event=record_truncated omitted_bytes=" in p.read_bytes()[-100000:] for p in owned.glob("app_*.log"))
        for p in owned.glob("app_*.log"):
            p.read_bytes().decode("utf-8")
        report["concurrent_native_and_dart"] = {"threads": 4, "records": 112000, "segments": records, "utf8": "passed"}

        concurrent = root / "two-processes"
        concurrent.mkdir()
        active_owner = concurrent / "app_1792746050000.log"
        owner = subprocess.Popen([str(executable), str(active_owner), "hold"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            assert owner.stdout.readline().strip() == "READY"
            inode = active_owner.stat().st_ino
            subprocess.run([str(executable), str(concurrent / "app_1792746050001.log"), "busy"], check=True, timeout=10)
            assert active_owner.exists() and active_owner.stat().st_ino == inode
            assert not (concurrent / "app_1792746050001.log").exists()
            # Existing harness instances use separate basename families; both
            # remain usable while the canonical app family is exclusively held.
            for name in ["harness_alice.log", "harness_bob.log"]:
                subprocess.run([str(executable), str(concurrent / name), "basic"], check=True, timeout=10)
                assert b"event=retention_final" in (concurrent / name).read_bytes()
        finally:
            owner.communicate("release\n", timeout=10)
        assert owner.returncode == 0
        subprocess.run([str(executable), str(concurrent / "app_1792746050001.log"), "basic"], check=True, timeout=10)
        report["two_process_owner_and_independent_harness_families"] = "passed"

        overlaps = {}
        for first, second in [("foo.log", "foo_1.log"), ("foo_1_2.log", "foo.log"),
                              ("app_100.log", "app.log"), ("app.log", "app_100.log")]:
            folder = root / ("overlap-" + first)
            folder.mkdir()
            active = folder / first
            owner = subprocess.Popen([str(executable), str(active), "hold"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            try:
                assert owner.stdout.readline().strip() == "READY"
                inode = active.stat().st_ino
                prefix = "app" if first.startswith("app") else "foo"
                for index in range(101, 110):
                    (folder / f"{prefix}_{index}.log").write_text("historical diagnostic\n")
                os.utime(active, (1, 1))
                subprocess.run([str(executable), str(folder / second), "busy"], check=True, timeout=10)
                assert active.exists() and active.stat().st_ino == inode
                assert not (folder / second).exists()
            finally:
                owner.communicate("release\n", timeout=10)
            assert owner.returncode == 0
            subprocess.run([str(executable), str(folder / second), "basic"], check=True, timeout=10)
            assert len(list(folder.glob("*.log"))) <= 10
            overlaps[first + " -> " + second] = "busy_then_reclaim_with_inode_preserved"
        report["overlapping_numeric_family_roots"] = overlaps

        unicode = root / "日志目录"
        unicode.mkdir()
        unicode_log = unicode / "会话日志.log"
        subprocess.run([str(executable), str(unicode_log), "basic"], check=True, timeout=10)
        assert b"event=retention_final" in unicode_log.read_bytes()
        report["unicode_path"] = "passed"

        sessions = root / "sessions"
        sessions.mkdir()
        untouched = sessions / "learning.log"
        untouched.write_bytes(b"learning-file-must-not-change")
        for index in range(12):
            subprocess.run([str(executable), str(sessions / f"app_{1792746100000 + index}.log"), "basic"], check=True, timeout=10)
        assert len(check_ledger(sessions)) == 10
        assert not (sessions / "app_1792746100000.log").exists()
        assert (sessions / "app_1792746100011.log").exists()
        assert untouched.read_bytes() == b"learning-file-must-not-change"
        report["cross_session_count"] = 12

        repaired = root / "legacy-repair"
        repaired.mkdir()
        oversized = repaired / "app_1792746200000.log"
        with oversized.open("wb") as f:
            for _ in range(18):
                f.write(b"r" * (1024 * 1024))
            f.write(b"legacy_recent_marker\n")
        subprocess.run([str(executable), str(oversized), "basic"], check=True, timeout=15)
        check_ledger(repaired)
        assert any(b"legacy_recent_marker" in p.read_bytes()[-4096:] for p in repaired.glob("app_*.log"))
        assert any(b"legacy_prefix_trimmed" in p.read_bytes()[:200] for p in repaired.glob("app_*.log"))
        report["legacy_oversize_repair"] = "passed"

        unsafe = root / "unsafe"
        unsafe.mkdir()
        learning = root / "outside-learning-data"
        learning.write_bytes(b"unchanged-independent-data")
        hardlink = unsafe / "app_1792746300000.log"
        os.link(learning, hardlink)
        subprocess.run([str(executable), str(hardlink), "unsafe"], check=True, timeout=10)
        assert learning.read_bytes() == b"unchanged-independent-data"
        hardlink.unlink()
        link = unsafe / "app_1792746300001.log"
        os.symlink(learning, link)
        subprocess.run([str(executable), str(link), "unsafe"], check=True, timeout=10)
        assert learning.read_bytes() == b"unchanged-independent-data"
        link.unlink()
        alias = root / "parent-link"
        os.symlink(unsafe, alias, target_is_directory=True)
        subprocess.run([str(executable), str(alias / "app_1792746300002.log"), "unsafe"], check=True, timeout=10)
        subprocess.run([str(executable), str(root / "missing-parent/app_1792746300003.log"), "missing"], check=True, timeout=10)
        report["symlink_hardlink_parent_negative"] = "passed"
        if os.name != "nt":
            inventory_probe = root / "inventory-error-probe"
            subprocess.run([compiler, "-std=c++20", "-pthread", "-I", str(source / "source"),
                            str(source / "source/V2TIMLog.cpp"),
                            str(Path(__file__).with_name("native_log_inventory_error_probe.cpp").resolve()),
                            "-o", str(inventory_probe)], check=True, cwd=root)
            inventory = root / "inventory-error"
            inventory.mkdir()
            inventory_log = inventory / "app_1792746500000.log"
            subprocess.run([str(inventory_probe), str(inventory_log)], check=True, timeout=10)
            assert not inventory_log.exists()
            report["failed_directory_enumeration_is_not_eof"] = "passed"
            failure = root / "failure"
            failure.mkdir()
            subprocess.run([str(executable), str(failure / "app_1792746400000.log"), "failure"], check=True, timeout=15)
            report["actual_posix_write_failure_releases_owner"] = "passed"
        report["outcome"] = "passed"
        args.evidence.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
