"""Signature-report variants observed in Android build-tools 35 and 37."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tool/ci"))
from android_release_preflight import apk_signer


class AndroidSignerReportTests(unittest.TestCase):
    fingerprint = "a1" * 32

    def report(self, prefix, fingerprint=None, count=1):
        return (f"Number of signers: {count}\n{prefix} certificate SHA-256 digest: "
                f"{fingerprint or self.fingerprint}\n")

    def test_old_and_scheme_labelled_signers(self):
        for prefix in ("Signer #1", "V3.0 Signer:", "V3.2 Signer:",
                       "Signer (minSdkVersion=33, maxSdkVersion=2147483647)"):
            with self.subTest(prefix=prefix):
                self.assertEqual(apk_signer(self.report(prefix), self.fingerprint, True),
                                 self.fingerprint)

    def test_same_certificate_across_verified_schemes(self):
        report = self.report("V3.0 Signer:") + self.report("V3.2 Signer:").split("\n", 1)[1]
        self.assertEqual(apk_signer(report, self.fingerprint, True), self.fingerprint)

    def test_multiple_or_rotated_certificates_are_not_a_single_upload_identity(self):
        for report in (self.report("Signer #1", count=2),
                       self.report("V3.0 Signer:") + self.report("V3.2 Signer:", "b2" * 32).split("\n", 1)[1]):
            with self.subTest(report=report), self.assertRaises(ValueError):
                apk_signer(report, self.fingerprint, True)

    def test_source_stamp_cannot_substitute_for_upload_signer(self):
        with self.assertRaises(ValueError):
            apk_signer(self.report("Source Stamp Signer"), self.fingerprint, True)

    def test_scheme_labelled_debug_identity_is_rejected(self):
        report = self.report("V3.0 Signer:") + "V3.0 Signer: certificate DN: CN=Android Debug, O=Android\n"
        with self.assertRaisesRegex(ValueError, "debug"):
            apk_signer(report, self.fingerprint, True)


if __name__ == "__main__":
    unittest.main()
