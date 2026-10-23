import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import warnings
import zipfile


SCRIPT = Path(__file__).resolve().parents[2] / "tool/ci/android_native_artifact.py"


def elf(machine=183, alignment=16384):
    ident = b"\x7fELF\x02\x01\x01" + bytes(9)
    header = struct.pack("<HHIQQQIHHHHHH", 3, machine, 1, 0, 64, 0, 0,
                         64, 56, 1, 0, 0, 0)
    segment = struct.pack("<IIQQQQQQ", 1, 5, 0, 0, 0, 120, 120, alignment)
    return ident + header + segment


class AndroidNativeArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("native_artifact", SCRIPT)
        cls.checker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.checker)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="toxee Android artifact ")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "release artifact.zip"

    def archive(self, kind="apk", payload=None, names=None, aligned=True,
                compressed=False, abi="arm64-v8a"):
        payload = elf() if payload is None else payload
        names = names or ("libapp.so", "libflutter.so", "libtim2tox_ffi.so")
        with zipfile.ZipFile(self.path, "w") as archive:
            for name in names:
                prefix = "base/lib" if kind == "aab" else "lib"
                entry = zipfile.ZipInfo(f"{prefix}/{abi}/{name}")
                entry.compress_type = (zipfile.ZIP_DEFLATED if compressed
                                       else zipfile.ZIP_STORED)
                if aligned and not compressed:
                    offset = archive.fp.tell() + 30 + len(entry.filename.encode())
                    padding = (-offset - 4) % 16384
                    entry.extra = struct.pack("<HH", 0xCAFE, padding) + bytes(padding)
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    archive.writestr(entry, payload)

    def check(self, kind="apk"):
        return self.checker.inspect_archive(self.path, kind, ["arm64-v8a"])

    def test_actual_archive_inventory_has_all_native_libraries_and_hash(self):
        self.archive()
        result = self.check()
        self.assertEqual(len(result["libraries"]), 3)
        self.assertEqual(len(result["sha256"]), 64)
        self.assertEqual(result["abis"], ["arm64-v8a"])

    def test_bundle_native_elf_is_checked_without_apk_zip_alignment_rule(self):
        self.archive(kind="aab", aligned=False, compressed=True)
        self.assertEqual(len(self.check("aab")["libraries"]), 3)

    def test_compressed_apk_native_payload_does_not_require_zip_mmap_alignment(self):
        self.archive(aligned=False, compressed=True)
        self.assertEqual(len(self.check()["libraries"]), 3)

    def test_every_native_library_requires_16k_load_alignment(self):
        self.archive(payload=elf(alignment=4096))
        with self.assertRaisesRegex(ValueError, "16 KB"):
            self.check()

    def test_native_machine_must_match_abi_directory(self):
        self.archive(payload=elf(machine=62))
        with self.assertRaisesRegex(ValueError, "machine"):
            self.check()

    def test_missing_ffi_is_not_a_usable_release(self):
        self.archive(names=["libapp.so", "libflutter.so"])
        with self.assertRaisesRegex(ValueError, "libtim2tox_ffi"):
            self.check()

    def test_unexpected_abi_is_rejected(self):
        self.archive(abi="x86_64", payload=elf(machine=62))
        with self.assertRaisesRegex(ValueError, "ABI"):
            self.check()

    def test_truncated_elf_is_rejected(self):
        self.archive(payload=elf()[:70])
        with self.assertRaisesRegex(ValueError, "truncated|bounds"):
            self.check()

    def test_non_elf_is_rejected(self):
        self.archive(payload=b"not a native library")
        with self.assertRaisesRegex(ValueError, "ELF"):
            self.check()

    def test_no_load_segment_is_rejected(self):
        payload = bytearray(elf())
        struct.pack_into("<I", payload, 64, 0)
        self.archive(payload=payload)
        with self.assertRaisesRegex(ValueError, "LOAD"):
            self.check()

    def test_uncompressed_apk_library_must_be_16k_zip_aligned(self):
        self.archive(aligned=False)
        with self.assertRaisesRegex(ValueError, "ZIP"):
            self.check()

    def test_duplicate_native_names_are_rejected(self):
        self.archive(names=["libapp.so", "libapp.so"])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.check()


if __name__ == "__main__":
    unittest.main()
