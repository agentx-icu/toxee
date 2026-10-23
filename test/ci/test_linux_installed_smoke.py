"""Checker regressions only; these fixtures are not installed-app evidence."""
import importlib.util
import io
import json
import os
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

    def test_evidence_copy_preserves_existing_host_directory_metadata(self):
        source = self.root / "container-evidence"
        target = self.root / "host-evidence"
        source.mkdir()
        target.mkdir(mode=0o700)
        (source / "failure.log").write_text("original dependency failure\n")
        source.chmod(0o755)
        before = target.stat()
        subprocess.run(["bash", "-c", smoke.CONTAINER_FUNCTIONS + '\ncopy_evidence "$1" "$2"',
                        "--", str(source), str(target)], check=True)
        after = target.stat()
        self.assertEqual((before.st_uid, before.st_gid, before.st_mode),
                         (after.st_uid, after.st_gid, after.st_mode))
        self.assertEqual((target / "failure.log").read_text(), "original dependency failure\n")
        (target / "result.json").write_text('{"outcome":"failed"}')

    def dependency_fixture(self):
        tools = self.root / "tools"
        tools.mkdir()
        fake = tools / "ldd"
        fake.write_text('''#!/bin/bash
if [[ "$1" == */runner ]]; then
  [[ -z "${LD_LIBRARY_PATH+x}" ]] || exit 97
  if [[ "${FAKE_ENTRY_BROKEN:-}" == 1 ]]; then
    echo 'libflutter_linux_gtk.so => not found'; exit 0
  fi
elif [[ "${LD_LIBRARY_PATH:-}" != "$EXPECTED_PRIVATE" || ! -f "$EXPECTED_PRIVATE/libflutter_linux_gtk.so" ]]; then
  echo 'libflutter_linux_gtk.so => not found'; exit 0
fi
echo "libflutter_linux_gtk.so => $EXPECTED_PRIVATE/libflutter_linux_gtk.so"
if [[ "${FAKE_SYSTEM_MISSING:-}" == 1 ]]; then echo 'librequired.so => not found'; fi
''')
        fake.chmod(0o755)
        private = self.root / "installed/lib"
        private.mkdir(parents=True)
        (private / "libflutter_linux_gtk.so").write_bytes(b"context fixture, not a real ELF")
        env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                   EXPECTED_PRIVATE=str(private), LD_LIBRARY_PATH="/untrusted/host/path")
        entry = self.root / "installed/runner"
        plugin = private / "plugin.so"
        report = self.root / "dependencies.log"
        script = smoke.CONTAINER_FUNCTIONS + '''
set -e
inspect_dependency "$1" "$1" "$3" "$4"
inspect_dependency "$2" "$1" "$3" "$4"
test "$LD_LIBRARY_PATH" = /untrusted/host/path
'''
        return ["bash", "-c", script, "--", str(entry), str(plugin), str(private), str(report)], env, private

    def test_entry_is_unmodified_and_private_dso_gets_only_package_context(self):
        command, env, _ = self.dependency_fixture()
        subprocess.run(command, env=env, check=True, capture_output=True, text=True)

    def test_actual_entry_or_system_dependency_failure_is_not_hidden(self):
        command, env, _ = self.dependency_fixture()
        for flag in ("FAKE_ENTRY_BROKEN", "FAKE_SYSTEM_MISSING"):
            with self.subTest(flag=flag):
                result = subprocess.run(command, env=dict(env, **{flag: "1"}), capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unresolved dependency", result.stderr)

    def test_missing_private_engine_is_not_hidden_by_context(self):
        command, env, private = self.dependency_fixture()
        (private / "libflutter_linux_gtk.so").unlink()
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unresolved dependency", result.stderr)

    def runtime_loader_fixture(self, arch="x86_64"):
        tools = self.root / "loader-tools"
        tools.mkdir(exist_ok=True)
        for name, script in {
            "ldconfig": '''#!/bin/bash
test "$1" = -p || exit 98
cat "$FIXTURE_LOADER_CACHE"
''',
            "ldd": '''#!/bin/bash
[[ -z "${LD_LIBRARY_PATH+x}" ]] || exit 97
if [[ "$(basename "$1")" == "${FAKE_BROKEN_SONAME:-}" ]]; then
  echo 'librequired.so => not found'
else
  echo 'libc.so.6 => /fixture/libc.so.6 (0x1)'
fi
''',
        }.items():
            command = tools / name
            command.write_text(script)
            command.chmod(0o755)
        cache = self.root / "fixture-ldconfig.txt"
        entries = []
        for soname in ("libEGL.so.1", "libGL.so.1", "libGLESv2.so.2"):
            library = self.root / soname
            data = bytearray(64)
            data[:6] = b"\x7fELF\x02\x01"
            data[18:20] = {"x86_64": 62, "aarch64": 183}[arch].to_bytes(2, "little")
            library.write_bytes(data)
            entries.append(f"\t{soname} (libc6) => {library}\n")
        cache.write_text("3 libs found in cache\n" + "".join(entries))
        report = self.root / "runtime-loaders.txt"
        env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                   FIXTURE_LOADER_CACHE=str(cache), LD_LIBRARY_PATH="/untrusted/host/path")
        script = smoke.CONTAINER_FUNCTIONS + '\ninspect_runtime_loaders "$1" "$2"'
        command = ["bash", "-c", script, "--", arch, str(report)]
        return command, env, cache, report

    def test_all_three_native_runtime_loaders_and_their_closures_pass(self):
        for arch in ("x86_64", "aarch64"):
            with self.subTest(architecture=arch):
                command, env, _, report = self.runtime_loader_fixture(arch)
                subprocess.run(command, env=env, check=True, capture_output=True, text=True)
                self.assertEqual(report.read_text().count("native loader context; no LD_LIBRARY_PATH"), 3)

    def test_missing_any_runtime_loader_is_rejected_before_harness(self):
        command, env, cache, report = self.runtime_loader_fixture()
        complete = cache.read_text()
        for soname in ("libEGL.so.1", "libGL.so.1", "libGLESv2.so.2"):
            with self.subTest(missing=soname):
                # A similarly named SONAME must not satisfy the exact lookup.
                cache.write_text(complete.replace(soname + " (", soname + ".other ("))
                result = subprocess.run(command, env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(soname + " => MISSING before harness", report.read_text())

    def test_runtime_loader_with_unresolved_dependency_is_rejected(self):
        command, env, _, _ = self.runtime_loader_fixture()
        for soname in ("libEGL.so.1", "libGL.so.1", "libGLESv2.so.2"):
            with self.subTest(broken=soname):
                result = subprocess.run(command, env=dict(env, FAKE_BROKEN_SONAME=soname),
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unresolved dependency", result.stderr)

    def test_cached_runtime_loader_must_exist_and_match_native_cpu(self):
        command, env, _, _ = self.runtime_loader_fixture()
        library = self.root / "libEGL.so.1"
        data = bytearray(library.read_bytes())
        data[18:20] = (183).to_bytes(2, "little")
        library.write_bytes(data)
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("native ELF CPU", result.stderr)
        library.unlink()
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MISSING before harness", result.stderr)

    def test_secondary_report_error_preserves_the_primary_failure(self):
        args = self.host_args()
        original_save = smoke.save
        saves = 0

        def write_report(path, value):
            nonlocal saves
            saves += 1
            if saves > 1:
                raise PermissionError("secondary export permissions")
            original_save(path, value)

        error_output = io.StringIO()
        with patch.object(smoke.platform, "system", return_value="Linux"), \
                patch.object(smoke.platform, "machine", return_value="x86_64"), \
                patch.object(smoke, "run", side_effect=ValueError("primary dependency cause")), \
                patch.object(smoke.subprocess, "run"), patch.object(smoke, "save", side_effect=write_report), \
                patch.object(smoke.sys, "stderr", error_output):
            with self.assertRaisesRegex(ValueError, "primary dependency cause"):
                smoke.host_check(args)
        self.assertIn("secondary export permissions", error_output.getvalue())
        self.assertEqual(json.loads((args.evidence_dir / "result.json").read_text())["outcome"], "failed")


if __name__ == "__main__":
    unittest.main()
