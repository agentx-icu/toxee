"""Checker regressions only; these fixtures are not installed-app evidence."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch


source = Path(__file__).with_name("linux_installed_smoke.py")
if not source.is_file():
    source = Path(__file__).resolve().parents[2] / "tool/ci/linux_installed_smoke.py"
spec = importlib.util.spec_from_file_location("linux_smoke", source)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class FakeDpkg:
    def __init__(self, archive):
        self.stdout = io.BytesIO(archive)

    def wait(self):
        return 0


class LinuxInstalledSmokeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        files = {"opt/morsecq/morsecq": b"runner", "usr/bin/morsecq": b"#!/bin/sh\n",
                 "usr/share/applications/icu.agentx.morsecq.desktop": b"[Desktop Entry]\n",
                 "usr/share/icons/hicolor/64x64/apps/morsecq.png": b"icon"}
        self.expected = {}
        for name, data in files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            path.chmod(0o755 if name.endswith("morsecq") else 0o644)
            self.expected[name] = {"kind": "file", "mode": path.stat().st_mode & 0o7777,
                                   "sha256": smoke.sha256(path)}

    def verify(self, arch=None):
        smoke.verify_installed("morsecq", self.expected, arch, self.root)

    def test_exact_inventory_passes_then_content_tamper_fails(self):
        self.verify()
        (self.root / "opt/morsecq/morsecq").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "differs"):
            self.verify()

    def test_missing_desktop_or_icon_fails(self):
        del self.expected["usr/share/applications/icu.agentx.morsecq.desktop"]
        with self.assertRaisesRegex(ValueError, "required"):
            self.verify()

    def test_extra_file_and_directory_disguised_runner_fail(self):
        extra = self.root / "opt/morsecq/unexpected.dll"
        extra.write_bytes(b"extra")
        with self.assertRaisesRegex(ValueError, "file set"):
            self.verify()
        extra.unlink()
        runner = self.root / "opt/morsecq/morsecq"
        runner.unlink()
        runner.mkdir()
        with self.assertRaisesRegex(ValueError, "differs"):
            self.verify()

    def test_wrong_cpu_fails_even_when_deb_hash_matches(self):
        library = self.root / "opt/morsecq/libwrong.so"
        data = bytearray(64)
        data[:6] = b"\x7fELF\x02\x01"
        data[18:20] = (183).to_bytes(2, "little")
        library.write_bytes(data)
        self.expected["opt/morsecq/libwrong.so"] = {"kind": "file", "mode": 0o644,
                                                   "sha256": smoke.sha256(library)}
        with self.assertRaisesRegex(ValueError, "CPU"):
            self.verify("x86_64")

    def test_mode_and_symlink_replacement_fail(self):
        runner = self.root / "opt/morsecq/morsecq"
        runner.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "mode"):
            self.verify()
        runner.unlink()
        runner.symlink_to(self.root / "usr/bin/morsecq")
        with self.assertRaisesRegex(ValueError, "differs"):
            self.verify()

    def test_package_tar_content_and_unsafe_path(self):
        for name, okay in (("./opt/morsecq/morsecq", True), ("../outside", False)):
            stream = io.BytesIO()
            with tarfile.open(fileobj=stream, mode="w") as archive:
                info = tarfile.TarInfo(name)
                info.mode, info.size = 0o755, 6
                archive.addfile(info, io.BytesIO(b"runner"))
            with patch.object(smoke.subprocess, "Popen", return_value=FakeDpkg(stream.getvalue())):
                if okay:
                    inventory = smoke.package_inventory(Path("fixture.deb"))
                    self.assertEqual(inventory["opt/morsecq/morsecq"]["sha256"],
                                     self.expected["opt/morsecq/morsecq"]["sha256"])
                else:
                    with self.assertRaisesRegex(ValueError, "Unsafe"):
                        smoke.package_inventory(Path("fixture.deb"))

    def test_native_runner_guard_rejects_emulation_before_docker(self):
        with patch.object(smoke.platform, "system", return_value="Linux"), \
                patch.object(smoke.platform, "machine", return_value="x86_64"), \
                patch.object(smoke, "run") as command:
            args = type("Args", (), {"architecture": "aarch64"})()
            with self.assertRaisesRegex(ValueError, "native matching"):
                smoke.host_check(args)
            command.assert_not_called()

    def host_args(self):
        package_dir = self.root / "packages"
        package_dir.mkdir()
        (package_dir / "fixture.deb").write_bytes(b"final fixture bytes")
        return type("Args", (), {"architecture": "x86_64", "app": "morsecq", "package_dir": package_dir,
                                 "evidence_dir": self.root / "evidence"})()

    def test_docker_keeps_setup_stdin_open_and_cleans_only_its_container(self):
        args = self.host_args()
        commands = []

        def command(argv, **kwargs):
            commands.append(argv)
            if argv[:3] == ["docker", "image", "inspect"]:
                return subprocess.CompletedProcess(argv, 0, "ubuntu@sha256:" + "a" * 64 + "\n")
            if argv[:2] == ["docker", "run"]:
                self.assertIn("--interactive", argv)
                self.assertEqual(kwargs["input"], smoke.SETUP)
                for name in ("gui-result.json", "uninstall-result.json"):
                    (args.evidence_dir / name).write_text('{"outcome":"passed"}')
            return subprocess.CompletedProcess(argv, 0)

        with patch.object(smoke.platform, "system", return_value="Linux"), \
                patch.object(smoke.platform, "machine", return_value="x86_64"), \
                patch.object(smoke, "run", side_effect=command), \
                patch.object(smoke.subprocess, "run") as cleanup:
            smoke.host_check(args)
        docker = next(cmd for cmd in commands if cmd[:2] == ["docker", "run"])
        name = docker[docker.index("--name") + 1]
        self.assertTrue(name.startswith("linux-installed-smoke-"))
        self.assertEqual(cleanup.call_args.args[0], ["docker", "rm", "-f", name])
        self.assertEqual(json.loads((args.evidence_dir / "result.json").read_text())["outcome"], "passed")

    def test_docker_timeout_cleans_container_and_cannot_be_a_pass(self):
        args = self.host_args()
        container_name = None

        def command(argv, **kwargs):
            nonlocal container_name
            if argv[:3] == ["docker", "image", "inspect"]:
                return subprocess.CompletedProcess(argv, 0, "ubuntu@sha256:" + "a" * 64 + "\n")
            if argv[:2] == ["docker", "run"]:
                container_name = argv[argv.index("--name") + 1]
                raise subprocess.TimeoutExpired(argv, 1)
            return subprocess.CompletedProcess(argv, 0)

        with patch.object(smoke.platform, "system", return_value="Linux"), \
                patch.object(smoke.platform, "machine", return_value="x86_64"), \
                patch.object(smoke, "run", side_effect=command), \
                patch.object(smoke.subprocess, "run") as cleanup:
            with self.assertRaises(subprocess.TimeoutExpired):
                smoke.host_check(args)
        self.assertEqual(cleanup.call_args.args[0], ["docker", "rm", "-f", container_name])
        self.assertEqual(json.loads((args.evidence_dir / "result.json").read_text())["outcome"], "failed")


if __name__ == "__main__":
    unittest.main()
