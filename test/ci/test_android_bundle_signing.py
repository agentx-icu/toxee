import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


SOURCE = Path(__file__).resolve().parents[2] / "tool/ci/VerifyAndroidBundle.java"
PASSWORD = "fixture-only-password"


class AndroidBundleSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for tool in ("java", "javac", "keytool", "jarsigner"):
            if not shutil.which(tool):
                raise RuntimeError(f"JDK 17+ tool required: {tool}")
        cls.temp = tempfile.TemporaryDirectory(prefix="toxee real JAR signing ")
        cls.root = Path(cls.temp.name)
        cls.addClassCleanup(cls.temp.cleanup)
        subprocess.run(["javac", "-d", str(cls.root), str(SOURCE)], check=True,
                       capture_output=True)
        cls.certificates = {}
        for name, subject in (("owner", "CN=toxee-upload-fixture"),
                              ("debug", "CN=Android Debug,O=Android,C=US")):
            key = cls.root / f"{name}.p12"
            subprocess.run(["keytool", "-genkeypair", "-keystore", str(key),
                            "-storetype", "PKCS12", "-storepass", PASSWORD,
                            "-alias", "upload", "-keyalg", "RSA", "-keysize", "2048",
                            "-validity", "30", "-dname", subject, "-noprompt"],
                           check=True, capture_output=True)
            cert = subprocess.run(["keytool", "-exportcert", "-keystore", str(key),
                                   "-storepass", PASSWORD, "-alias", "upload"],
                                  check=True, capture_output=True).stdout
            cls.certificates[name] = (key, hashlib.sha256(cert).hexdigest())

    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.fixture.cleanup)
        self.bundle = Path(self.fixture.name) / "release bundle.aab"
        with zipfile.ZipFile(self.bundle, "w") as archive:
            archive.writestr("BundleConfig.pb", b"fixture bundle config")
            archive.writestr("base/manifest/AndroidManifest.xml", b"fixture manifest")
            archive.writestr("base/assets/message.txt", b"signed payload")

    def sign(self, name="owner"):
        subprocess.run(["jarsigner", "-keystore", str(self.certificates[name][0]),
                        "-storepass", PASSWORD, str(self.bundle), "upload"],
                       check=True, capture_output=True)

    def verify(self, expected=None, mode="distribution"):
        expected = expected or self.certificates["owner"][1]
        return subprocess.run(["java", "-cp", str(self.root), "VerifyAndroidBundle",
                               str(self.bundle), expected, mode], capture_output=True,
                              text=True)

    def test_real_signed_bundle_matches_expected_upload_certificate(self):
        self.sign()
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["certificate_sha256"], self.certificates["owner"][1])
        self.assertEqual(report["signed_entries"], 3)

    def test_wrong_expected_certificate_rejected(self):
        self.sign()
        result = self.verify(self.certificates["debug"][1])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Wrong AAB", result.stderr)

    def test_debug_certificate_rejected_even_when_expected_matches(self):
        self.sign("debug")
        result = self.verify(self.certificates["debug"][1])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("debug certificate", result.stderr)

    def test_explicit_development_mode_accepts_signed_debug_bundle(self):
        self.sign("debug")
        self.assertEqual(self.verify("-", "development").returncode, 0)

    def test_unsigned_bundle_rejected(self):
        self.assertNotEqual(self.verify().returncode, 0)

    def test_distribution_without_owner_certificate_rejected(self):
        self.sign()
        self.assertNotEqual(self.verify("-").returncode, 0)

    def test_signed_payload_tampering_is_rejected(self):
        self.sign()
        with zipfile.ZipFile(self.bundle) as archive:
            contents = {entry.filename: archive.read(entry) for entry in archive.infolist()}
        contents["base/assets/message.txt"] = b"changed after signing"
        with zipfile.ZipFile(self.bundle, "w") as archive:
            for name, data in contents.items():
                archive.writestr(name, data)
        self.assertNotEqual(self.verify().returncode, 0)

    def test_unsigned_resource_added_after_signing_is_rejected(self):
        self.sign()
        with zipfile.ZipFile(self.bundle, "a") as archive:
            archive.writestr("base/assets/unsigned.txt", b"untrusted extra")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsigned", result.stderr)

    def test_meta_inf_resources_do_not_bypass_entry_signature_check(self):
        self.sign()
        with zipfile.ZipFile(self.bundle, "a") as archive:
            archive.writestr("META-INF/services/unsigned", b"not a signature file")
        self.assertNotEqual(self.verify().returncode, 0)


if __name__ == "__main__":
    unittest.main()
