import importlib.util
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

from test_android_native_artifact import elf


SOURCE = Path(__file__).resolve().parents[2] / "tool/ci/native_payload.py"
spec = importlib.util.spec_from_file_location("native_payload", SOURCE)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class DesktopNativePayloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="toxee native inventory ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "toxee").write_bytes(elf())

    def check(self):
        return native.check_tree(self.root, "elf", "arm64", "toxee")

    def test_every_plugin_is_checked_not_only_the_main_app(self):
        (self.root / "plugin.so").write_bytes(elf())
        self.assertEqual(len(self.check()), 2)
        (self.root / "plugin.so").write_bytes(elf(machine=62))
        with self.assertRaisesRegex(ValueError, "architecture"):
            self.check()

    def test_required_main_executable_cannot_be_arbitrary_text(self):
        (self.root / "toxee").write_text("not an executable")
        (self.root / "plugin.so").write_bytes(elf())
        with self.assertRaisesRegex(ValueError, "main executable"):
            self.check()

    def test_corrupt_versioned_shared_library_is_rejected(self):
        (self.root / "libcodec.so.1").write_bytes(b"broken")
        with self.assertRaisesRegex(ValueError, "missing native"):
            self.check()

    def test_dangling_runtime_symlink_is_rejected(self):
        (self.root / "libcodec.so").symlink_to("missing.so.1")
        with self.assertRaisesRegex(ValueError, "Dangling"):
            self.check()

    def test_symlink_cannot_hide_dependency_on_developer_machine(self):
        (self.root / "external.so").symlink_to(Path(self.temp.name).parent / "not-in-payload")
        with self.assertRaisesRegex(ValueError, "outside root"):
            self.check()

    def test_elf_machine_must_match_32_or_64_bit_class(self):
        payload = bytearray(elf())
        payload[4] = 1
        (self.root / "plugin.so").write_bytes(payload)
        with self.assertRaisesRegex(ValueError, "class/header"):
            self.check()

    def test_pe_header_cannot_point_inside_dos_header(self):
        payload = bytearray(100)
        payload[:2] = b"MZ"
        struct.pack_into("<I", payload, 60, 4)
        payload[4:8] = b"PE\0\0"
        with self.assertRaisesRegex(ValueError, "bounds"):
            native.verify(payload, "pe", "arm64", "plugin.dll")

    def test_truncated_64_bit_macho_header_is_rejected(self):
        payload = bytes.fromhex("cffaedfe") + struct.pack("<I", 0x100000C) + bytes(20)
        with self.assertRaisesRegex(ValueError, "Truncated"):
            native.verify(payload, "macho", "arm64", "plugin.dylib")

    def test_fat_macho_table_must_match_actual_slice(self):
        thin = bytes.fromhex("cffaedfe") + struct.pack("<I", 0x100000C) + bytes(24)
        fat = bytes.fromhex("cafebabe") + struct.pack(">I", 1)
        fat += struct.pack(">IIIII", 0x1000007, 0, 28, len(thin), 0) + thin
        with self.assertRaisesRegex(ValueError, "contradicts"):
            native.verify(fat, "macho", "x86_64", "Framework")

    def test_windows_flutter_snapshot_is_elf_but_must_match_target_cpu(self):
        header = bytearray(88)
        header[:2] = b"MZ"
        struct.pack_into("<I", header, 60, 64)
        header[64:68] = b"PE\0\0"
        struct.pack_into("<H", header, 68, 0xAA64)
        (self.root / "toxee.exe").write_bytes(header)
        (self.root / "toxee").unlink()
        data = self.root / "data"
        data.mkdir()
        snapshot = data / "app.so"
        snapshot.write_bytes(elf())
        result = native.check_tree(self.root, "pe", "arm64", "toxee.exe", flutter_windows=True)
        self.assertEqual(len(result), 2)
        snapshot.write_bytes(elf(machine=62))
        with self.assertRaisesRegex(ValueError, "architecture"):
            native.check_tree(self.root, "pe", "arm64", "toxee.exe", flutter_windows=True)
        snapshot.write_bytes(elf())
        (self.root / "plugin.dll").write_bytes(elf())
        with self.assertRaisesRegex(ValueError, "Expected pe"):
            native.check_tree(self.root, "pe", "arm64", "toxee.exe", flutter_windows=True)

    def test_packager_rechecks_appended_windows_runtime_before_signing(self):
        for runtime_machine, reaches_signing in ((0xAA64, True), (0x8664, False)):
            with self.subTest(runtime_machine=runtime_machine), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                scripts = root / "tool/ci"
                scripts.mkdir(parents=True)
                for name in ("package_artifacts.sh", "common.sh", "native_payload.py"):
                    shutil.copy2(SOURCE.parent / name, scripts / name)
                runner = root / "build/windows/arm64/runner/Release"
                runner.mkdir(parents=True)
                native_dir = root / "build/native-artifacts/windows"
                native_dir.mkdir(parents=True)
                (runner / "data").mkdir()
                (runner / "data/app.so").write_bytes(elf())
                for path, machine in ((runner / "toxee.exe", 0xAA64),
                                      (native_dir / "libvpx.dll", runtime_machine)):
                    header = bytearray(88)
                    header[:2] = b"MZ"
                    struct.pack_into("<I", header, 60, 64)
                    header[64:68] = b"PE\0\0"
                    struct.pack_into("<H", header, 68, machine)
                    path.write_bytes(header)
                commands = root / "bin"
                commands.mkdir()
                signer = commands / "powershell.exe"
                signer.write_text('#!/bin/sh\ntouch "$FIXTURE_SIGNING_MARKER"\nexit 73\n')
                signer.chmod(0o755)
                marker = root / "reached-signing"
                result = subprocess.run(["bash", str(scripts / "package_artifacts.sh"),
                                         "--target", "windows"], capture_output=True, text=True,
                                        env={**os.environ, "PATH": f"{commands}:{os.environ['PATH']}",
                                             "TOXEE_PACKAGE_ARCH": "ARM64",
                                             "FIXTURE_SIGNING_MARKER": str(marker)})
                self.assertEqual(marker.exists(), reaches_signing, result.stdout + result.stderr)
                if reaches_signing:
                    self.assertEqual(result.returncode, 73)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("architecture", result.stderr)


if __name__ == "__main__":
    unittest.main()
