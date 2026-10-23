import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "tool/ci/apple_release_preflight.py"
spec = importlib.util.spec_from_file_location("apple_release_preflight", SOURCE)
apple = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apple)


class AppleReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="toxee Apple metadata ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "App.app"
        self.app.mkdir()
        self.info = {"CFBundleIdentifier": "com.toxee.app", "CFBundleVersion": "1",
                     "CFBundleShortVersionString": "1.0", "NSCameraUsageDescription": "Video calls"}
        self.source = self.root / "SourceInfo.plist"
        self.source.write_bytes(plistlib.dumps(self.info))
        self.write_info()
        self.manifest = self.app / "PrivacyInfo.xcprivacy"
        self.manifest.write_bytes(plistlib.dumps({"NSPrivacyAccessedAPITypes": [{
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}]}))

    def write_info(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def check(self):
        return apple.metadata(self.app, "ios", "com.toxee.app", self.source)

    def test_built_app_and_embedded_sdk_manifests_are_inventoried(self):
        sdk = self.app / "Frameworks/SDK.framework"
        sdk.mkdir(parents=True)
        (sdk / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({}))
        report = self.check()
        self.assertEqual(len(report["privacy_manifests"]), 2)
        self.assertEqual(report["usage_strings"]["NSCameraUsageDescription"], "Video calls")

    def test_manifest_in_source_is_insufficient_if_not_bundled(self):
        self.manifest.unlink()
        with self.assertRaisesRegex(ValueError, "app-owned"):
            self.check()

    def test_missing_built_purpose_string_is_rejected(self):
        self.info.pop("NSCameraUsageDescription")
        self.write_info()
        with self.assertRaisesRegex(ValueError, "purpose string"):
            self.check()

    def test_wrong_built_identity_is_rejected(self):
        self.info["CFBundleIdentifier"] = "com.example.wrong"
        self.write_info()
        with self.assertRaisesRegex(ValueError, "identifier"):
            self.check()

    def test_invalid_embedded_sdk_manifest_cannot_be_ignored(self):
        sdk = self.app / "Frameworks/SDK.framework"
        sdk.mkdir(parents=True)
        (sdk / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps({
            "NSPrivacyAccessedAPITypes": [{"NSPrivacyAccessedAPIType": "FileTimestamp",
                                          "NSPrivacyAccessedAPITypeReasons": []}]}))
        with self.assertRaisesRegex(ValueError, "required-reason"):
            self.check()


if __name__ == "__main__":
    unittest.main()
