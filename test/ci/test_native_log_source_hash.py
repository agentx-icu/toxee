"""Source identity must survive Windows code pages, not arbitrary byte changes."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "native_log_retention", ROOT / "tool/ci/test_native_log_retention.py")
RETENTION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RETENTION)


class NativeLogSourceHash(unittest.TestCase):
    # UTF-8 C++ comment containing the same multibyte class as the pinned source.
    CONTENT = b"// \xe6\x97\xa5\xe5\xbf\x97\nvoid append();\n"

    def test_windows_default_codepage_does_not_change_source_identity(self):
        expected = hashlib.sha256(self.CONTENT).hexdigest()
        original_open = io.open

        def windows_open(file, mode="r", buffering=-1, encoding=None,
                         errors=None, newline=None, closefd=True, opener=None):
            if "b" not in mode:
                encoding = "cp1252"
            return original_open(file, mode, buffering, encoding=encoding,
                                 errors=errors, newline=newline,
                                 closefd=closefd, opener=opener)

        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source.cpp"
            source.write_bytes(self.CONTENT)
            with patch("io.open", side_effect=windows_open):
                # The old default-decode/re-encode path demonstrably fails.
                self.assertNotEqual(
                    hashlib.sha256(source.read_text().encode()).hexdigest(), expected)
                self.assertEqual(RETENTION.source_digest(source), expected)

    def test_only_crlf_conversion_is_accepted(self):
        expected = hashlib.sha256(self.CONTENT).hexdigest()
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source.cpp"
            source.write_bytes(self.CONTENT.replace(b"\n", b"\r\n"))
            self.assertEqual(RETENTION.source_digest(source), expected)
            source.write_bytes(self.CONTENT.replace(b"\n", b"\r"))
            self.assertNotEqual(RETENTION.source_digest(source), expected)
            source.write_bytes(self.CONTENT.replace(b"append", b"remove"))
            self.assertNotEqual(RETENTION.source_digest(source), expected)


if __name__ == "__main__":
    unittest.main()
