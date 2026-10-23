import datetime
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[2] / "tool/ci/ios_store_export.py"
spec = importlib.util.spec_from_file_location("ios_store_export", SOURCE)
store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)


class IosStoreExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="toxee iOS export ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.certificate = b"test certificate bytes, not a signing identity"
        self.fingerprint = hashlib.sha1(self.certificate).hexdigest().upper()
        self.options = {"method": "app-store-connect", "destination": "export",
                        "signingStyle": "manual", "teamID": "ABCDE12345",
                        "signingCertificate": self.fingerprint,
                        "provisioningProfiles": {"com.toxee.app": "owner-profile"}}
        self.path = self.root / "ExportOptions.plist"

    def options_check(self):
        self.path.write_bytes(plistlib.dumps(self.options))
        return store.export_options(self.path, "ABCDE12345", self.fingerprint)

    def profile(self):
        return {"UUID": "fixture", "TeamIdentifier": ["ABCDE12345"],
                "ExpirationDate": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
                + datetime.timedelta(days=1), "DeveloperCertificates": [self.certificate],
                "Entitlements": {"application-identifier": "PREFIX.com.toxee.app",
                                 "com.apple.developer.team-identifier": "ABCDE12345",
                                 "get-task-allow": False}}

    def test_accepts_only_explicit_local_manual_export(self):
        self.assertEqual(self.options_check()["destination"], "export")
        for key, value in (("destination", "upload"), ("signingStyle", "automatic"),
                           ("method", "release-testing"), ("teamID", "OTHER12345"),
                           ("signingCertificate", "Apple Distribution")):
            with self.subTest(key=key):
                previous = self.options[key]
                self.options[key] = value
                with self.assertRaises(ValueError):
                    self.options_check()
                self.options[key] = previous

    def test_missing_export_destination_and_unreviewed_extra_profiles_rejected(self):
        self.options.pop("destination")
        with self.assertRaises(ValueError):
            self.options_check()
        self.options["destination"] = "export"
        self.options["provisioningProfiles"]["com.other.app"] = "other"
        with self.assertRaises(ValueError):
            self.options_check()

    def test_profile_matches_explicit_app_certificate_team_and_expiry(self):
        profile = self.profile()
        entitlement = dict(profile["Entitlements"])
        self.assertEqual(store.profile_evidence(profile, entitlement, "ABCDE12345", self.fingerprint)["uuid"], "fixture")
        with self.assertRaisesRegex(ValueError, "selected profile"):
            store.profile_evidence(profile, entitlement, "ABCDE12345", self.fingerprint, "wrong-profile")
        cases = [({"ProvisionedDevices": ["device"]}, "device"),
                 ({"ProvisionsAllDevices": True}, "enterprise"),
                 ({"ExpirationDate": datetime.datetime(2000, 1, 1)}, "expired"),
                 ({"TeamIdentifier": ["OTHER12345"]}, "team"),
                 ({"DeveloperCertificates": [b"other"]}, "certificate")]
        for update, message in cases:
            with self.subTest(message=message), self.assertRaises(ValueError):
                store.profile_evidence({**profile, **update}, entitlement, "ABCDE12345", self.fingerprint)

    def test_debug_wildcard_and_mismatched_application_entitlements_rejected(self):
        for key, value in (("get-task-allow", True), ("application-identifier", "PREFIX.*"),
                           ("application-identifier", "PREFIX.com.other.app"),
                           ("com.apple.developer.team-identifier", "OTHER12345")):
            with self.subTest(key=key, value=value):
                profile = self.profile()
                profile["Entitlements"][key] = value
                with self.assertRaises(ValueError):
                    store.profile_evidence(profile, profile["Entitlements"], "ABCDE12345", self.fingerprint)
        profile = self.profile()
        with self.assertRaises(ValueError):
            store.profile_evidence(profile, {**profile["Entitlements"], "application-identifier": "OTHER.com.toxee.app"},
                                   "ABCDE12345", self.fingerprint)

    def test_archive_and_export_commands_cannot_register_or_upload(self):
        archive, export = store.commands(self.root, self.root / "output", self.path)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", archive)
        self.assertIn("archive", archive)
        self.assertIn("-exportArchive", export)
        for command in (archive, export):
            self.assertNotIn("-allowProvisioningUpdates", command)
            self.assertNotIn("-allowProvisioningDeviceRegistration", command)

    def test_signing_authority_must_be_distribution_not_development(self):
        self.assertEqual(store.distribution_authority("Authority=Apple Distribution: Owner (ABCDE12345)\nAuthority=Apple Root CA"),
                         "Apple Distribution: Owner (ABCDE12345)")
        for display in ("Signature=adhoc", "Authority=Apple Development: Owner (ABCDE12345)", ""):
            with self.subTest(display=display), self.assertRaises(ValueError):
                store.distribution_authority(display)

    def test_existing_output_is_rejected_before_any_build_command(self):
        with patch.object(store, "run") as runner:
            with self.assertRaises(FileExistsError):
                store.build(self.root, self.root, None, None, None, True)
            runner.assert_not_called()

    def test_empty_and_directory_executable_names_rejected_before_inspection(self):
        app = self.root / "Runner.app"
        app.mkdir()
        for entry in ("", ".", ".."):
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": entry}))
            with self.subTest(entry=entry), patch.object(store, "run") as runner:
                with self.assertRaises(ValueError):
                    store.inspect_app(self.root, app, self.root / "evidence")
                runner.assert_not_called()

    def test_nonexecutable_app_entry_rejected_before_inspection(self):
        app = self.root / "Runner.app"
        app.mkdir()
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Runner"}))
        executable = app / "Runner"
        executable.write_bytes(bytes.fromhex("cffaedfe"))
        executable.chmod(0o644)
        with patch.object(store, "run") as runner:
            with self.assertRaisesRegex(ValueError, "executable regular file"):
                store.inspect_app(self.root, app, self.root / "evidence")
            runner.assert_not_called()

    def test_archive_rejects_additional_products_before_inspection(self):
        applications = self.root / "Runner.xcarchive/Products/Applications"
        (applications / "Runner.app").mkdir(parents=True)
        for name in ("Other.app", "Other.appex", "unreviewed-file"):
            extra = applications / name
            extra.mkdir()
            with self.subTest(name=name), patch.object(store, "inspect_app") as inspect:
                with self.assertRaisesRegex(ValueError, "exactly one"):
                    store.inspect_archive(self.root, self.root)
                inspect.assert_not_called()
            extra.rmdir()

    def test_archive_rejects_dangling_external_and_absolute_links(self):
        archive = self.root / "Runner.xcarchive"
        (archive / "Products/Applications/Runner.app").mkdir(parents=True)
        internal = archive / "symbol-bytes"
        internal.write_bytes(b"fixture symbols, not a dSYM")
        outside = self.root / "outside-symbols"
        outside.write_bytes(b"outside archive")
        link = archive / "symbol-link"
        for target in ("missing-symbols", "../outside-symbols", str(internal)):
            link.symlink_to(target)
            with self.subTest(target=target), patch.object(store, "inspect_app") as inspect:
                with self.assertRaisesRegex(ValueError, "archive.*link"):
                    store.inspect_archive(self.root, self.root)
                inspect.assert_not_called()
            link.unlink()

    def test_archive_accepts_valid_relative_internal_link(self):
        archive = self.root / "Runner.xcarchive"
        app = archive / "Products/Applications/Runner.app"
        app.mkdir(parents=True)
        (archive / "symbol-bytes").write_bytes(b"fixture symbols, not a dSYM")
        (archive / "symbol-link").symlink_to("symbol-bytes")
        with patch.object(store, "inspect_app") as inspect:
            store.inspect_archive(self.root, self.root)
            inspect.assert_called_once_with(self.root, app, self.root / "archive-evidence")

    def test_actual_signer_mismatch_cannot_produce_distribution_evidence(self):
        (self.root / "ipa").mkdir()
        (self.root / "ipa/App.ipa").write_bytes(b"fixture, not an exported application")
        def runner(command, **kwargs):
            result = subprocess.CompletedProcess(command, 0, stdout=b"", stderr=b"")
            if command[0] == "ditto":
                (Path(command[-1]) / "Payload/Runner.app").mkdir(parents=True)
            elif "--verbose=4" in command:
                result.stderr = "Authority=Apple Distribution: Owner (ABCDE12345)\n"
            elif "--entitlements" in command:
                result.stdout = plistlib.dumps(self.profile()["Entitlements"])
            elif command[:2] == ["security", "cms"]:
                result.stdout = plistlib.dumps(self.profile())
            elif "--extract-certificates" in command:
                Path(command[-2] + "0").write_bytes(b"different actual signer")
            return result
        with patch.object(store, "run", side_effect=runner), patch.object(store, "inspect_app"):
            with self.assertRaisesRegex(ValueError, "Actual exported app signer"):
                store.inspect_export(self.root, self.root, "ABCDE12345", self.fingerprint, "fixture")
        self.assertFalse((self.root / "export-evidence/distribution.json").exists())

    def test_config_archive_and_export_failures_propagate_without_verification(self):
        # Real subprocess error propagation is exercised at each command boundary;
        # no mocked success is counted as a signed app or a native archive.
        for failing_call in (1, 2, 3):
            self.options_check()
            output = self.root / str(failing_call)
            with self.subTest(call=failing_call), patch.object(store, "inspect_archive") as inspect:
                calls = []
                def runner(command, **kwargs):
                    calls.append(command)
                    if len(calls) == failing_call:
                        raise subprocess.CalledProcessError(17, command)
                with patch.object(store, "run", side_effect=runner), patch.object(store, "inspect_export") as exported:
                    with self.assertRaises(subprocess.CalledProcessError):
                        store.build(self.root, output, self.path, "ABCDE12345", self.fingerprint, False)
                    exported.assert_not_called()
                    self.assertEqual(len(calls), failing_call)
                    if failing_call <= 2:
                        inspect.assert_not_called()


if __name__ == "__main__":
    unittest.main()
