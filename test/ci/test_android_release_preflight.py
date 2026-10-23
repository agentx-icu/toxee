"""Real aapt2/apksigner/JAR fixtures; not an installable native app qualification."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile

from test_android_native_artifact import elf


ROOT = Path(__file__).resolve().parents[2]
PASSWORD = "fixture-only-password"


class AndroidReleasePreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
        if not sdk:
            raise RuntimeError("Android SDK required; run this suite in the Android build job")
        cls.sdk = Path(sdk)
        versions = sorted((cls.sdk / "build-tools").iterdir(), key=lambda p: tuple(
            int(n) for n in re.findall(r"\d+", p.name)))
        cls.tools = versions[-1]
        cls.temp = tempfile.TemporaryDirectory(prefix="toxee Android release signing ")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.key = cls.directory / "upload.p12"
        cls.run_tool(["keytool", "-genkeypair", "-keystore", cls.key, "-storepass", PASSWORD,
                      "-alias", "upload", "-keyalg", "RSA", "-keysize", "2048",
                      "-validity", "30", "-dname", "CN=toxee-upload-fixture", "-noprompt"])
        cert = subprocess.run(["keytool", "-exportcert", "-keystore", str(cls.key),
                               "-storepass", PASSWORD, "-alias", "upload"],
                              check=True, capture_output=True).stdout
        cls.fingerprint = hashlib.sha256(cert).hexdigest()
        manifest = cls.directory / "AndroidManifest.xml"
        manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
package="com.toxee.app" android:versionCode="1" android:versionName="1.0">
<uses-sdk android:minSdkVersion="23" android:targetSdkVersion="36"/>
<application android:hasCode="false" android:label="Signing fixture"/></manifest>''')
        unsigned = cls.directory / "unsigned.apk"
        cls.run_tool([cls.tools / "aapt2", "link", "-I", cls.sdk / "platforms/android-36/android.jar",
                      "--manifest", manifest, "-o", unsigned])
        cls.bundle = cls.directory / "release.aab"
        with zipfile.ZipFile(unsigned, "a", compression=zipfile.ZIP_DEFLATED) as apk, \
                zipfile.ZipFile(cls.bundle, "w", compression=zipfile.ZIP_DEFLATED) as aab:
            aab.writestr("BundleConfig.pb", b"synthetic signature fixture")
            aab.writestr("base/manifest/AndroidManifest.xml", b"synthetic signature fixture")
            for name in ("libapp.so", "libflutter.so", "libtim2tox_ffi.so"):
                apk.writestr(f"lib/arm64-v8a/{name}", elf())
                aab.writestr(f"base/lib/arm64-v8a/{name}", elf())
        cls.apk = cls.directory / "release.apk"
        cls.run_tool([cls.tools / "apksigner", "sign", "--ks", cls.key,
                      "--ks-pass", f"pass:{PASSWORD}", "--out", cls.apk, unsigned])
        cls.run_tool(["jarsigner", "-keystore", cls.key, "-storepass", PASSWORD,
                      cls.bundle, "upload"])

    @staticmethod
    def run_tool(command):
        result = subprocess.run([str(v) for v in command], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def invoke(self, expected, distribution=True):
        destination = self.directory / "report"
        return subprocess.run([
            "python3", str(ROOT / "tool/ci/android_release_preflight.py"),
            "--apk", str(self.apk), "--aab", str(self.bundle),
            "--report-dir", str(destination), "--application-id", "com.toxee.app",
            "--min-target-sdk", "36", "--abis", "arm64-v8a",
            *(["--distribution"] if distribution else [])],
            env={**os.environ, "ANDROID_SIGNING_CERT_SHA256": expected,
                 "TOXEE_REQUIRE_SIGNING": "0"}, capture_output=True, text=True)

    def test_final_apk_signature_manifest_and_signed_bundle_are_verified(self):
        result = self.invoke(self.fingerprint)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads((self.directory / "report/android-preflight.json").read_text())
        self.assertEqual(report["actual_upload_certificate_sha256"], self.fingerprint)
        self.assertEqual(report["apk_identity"]["target_sdk"], 36)
        self.assertFalse(report["apk_identity"]["debuggable"])
        self.assertEqual(report["mode"], "distribution")

    def test_real_wrong_apk_signer_is_rejected(self):
        result = self.invoke("0" * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Wrong APK", result.stderr)

    def test_distribution_without_expected_identity_fails_before_sdk_commands(self):
        result = self.invoke("")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ANDROID_SIGNING_CERT_SHA256", result.stderr)

    def package(self, expected, invalid=False):
        with tempfile.TemporaryDirectory(prefix="toxee package entry ") as temp:
            repo = Path(temp)
            scripts = repo / "tool/ci"
            scripts.mkdir(parents=True)
            for name in ("package_artifacts.sh", "common.sh", "android_release_preflight.py",
                         "android_native_artifact.py", "VerifyAndroidBundle.java"):
                shutil.copy2(ROOT / "tool/ci" / name, scripts / name)
            (repo / "pubspec.yaml").write_text("version: 1.0.0+1\n")
            for source, destination in (
                    (self.apk, repo / "build/app/outputs/flutter-apk/app-release.apk"),
                    (self.bundle, repo / "build/app/outputs/bundle/release/app-release.aab")):
                destination.parent.mkdir(parents=True, exist_ok=True)
                if invalid:
                    destination.write_text("not even a ZIP")
                else:
                    shutil.copy2(source, destination)
            result = subprocess.run([
                "bash", str(scripts / "package_artifacts.sh"), "--target", "android"],
                env={**os.environ, "TOXEE_REQUIRE_SIGNING": "1",
                     "ANDROID_SIGNING_CERT_SHA256": expected}, capture_output=True, text=True)
            outputs = list((repo / "dist/android").glob("*.apk"))
            return result, len(outputs)

    def test_distribution_packager_itself_verifies_real_signed_artifacts(self):
        result, count = self.package(self.fingerprint)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(count, 1)

    def test_distribution_packager_cannot_bypass_missing_expected_identity(self):
        result, count = self.package("")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ANDROID_SIGNING_CERT_SHA256", result.stderr)
        self.assertEqual(count, 0)

    def test_distribution_packager_cannot_copy_invalid_archives(self):
        result, count = self.package(self.fingerprint, invalid=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, 0)


if __name__ == "__main__":
    unittest.main()
