#!/usr/bin/env python3
"""Archive iOS without account changes; optionally export with existing owner signing.

No upload, automatic provisioning, device registration or credential creation.
See doc/operations/STORE_READINESS.md for owner inputs.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import uuid


BUNDLE_ID = "com.toxee.app"


def fingerprint(value):
    result = value.replace(":", "").upper()
    if not re.fullmatch(r"[0-9A-F]{40}", result):
        raise ValueError("An existing owner certificate SHA-1 (40 hex digits) is required")
    return result


def export_options(path, team, certificate):
    value = plistlib.loads(path.read_bytes())
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("Owner Team ID must contain ten uppercase letters/digits")
    expected = {"method": "app-store-connect", "destination": "export",
                "signingStyle": "manual", "teamID": team,
                "signingCertificate": fingerprint(certificate)}
    if not isinstance(value, dict) or any(value.get(key) != item for key, item in expected.items()):
        raise ValueError("ExportOptions must explicitly select local App Store export, manual signing, owner team and certificate SHA-1")
    profiles = value.get("provisioningProfiles")
    if (not isinstance(profiles, dict) or set(profiles) != {BUNDLE_ID}
            or not isinstance(profiles[BUNDLE_ID], str) or not profiles[BUNDLE_ID].strip()):
        raise ValueError("ExportOptions must name the existing profile for com.toxee.app only")
    if value.get("testFlightInternalTestingOnly"):
        raise ValueError("An internal-only TestFlight export is not an App Store candidate")
    return value


def profile_evidence(profile, entitlements, team, certificate, expected_profile=None):
    if expected_profile and expected_profile not in (profile.get("Name"), profile.get("UUID")):
        raise ValueError("Exported profile differs from the owner's selected profile")
    if profile.get("TeamIdentifier") != [team]:
        raise ValueError("Exported profile team does not match the owner")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
        raise ValueError("Device/enterprise profile is not an App Store distribution profile")
    expiration = profile.get("ExpirationDate")
    now = datetime.datetime.now(datetime.timezone.utc)
    if not isinstance(expiration, datetime.datetime) or expiration.replace(tzinfo=datetime.timezone.utc) <= now:
        raise ValueError("Exported provisioning profile is expired or has no expiry")
    declared = profile.get("Entitlements", {})
    identifier = declared.get("application-identifier", "")
    if (not isinstance(identifier, str) or not identifier.endswith("." + BUNDLE_ID)
            or "*" in identifier or declared.get("get-task-allow") is not False
            or entitlements.get("get-task-allow") is not False
            or entitlements.get("application-identifier") != identifier
            or declared.get("com.apple.developer.team-identifier") != team
            or entitlements.get("com.apple.developer.team-identifier") != team):
        raise ValueError("Exported distribution entitlements do not match profile, app and owner team")
    certificates = profile.get("DeveloperCertificates", [])
    if not isinstance(certificates, list) or not any(
            isinstance(item, bytes) and hashlib.sha1(item).hexdigest().upper() == certificate
            for item in certificates):
        raise ValueError("Owner certificate is not bound to the exported profile")
    return {"uuid": profile.get("UUID"), "team": team, "application_identifier": identifier,
            "expires": expiration.isoformat() + "Z", "certificate_sha1": certificate}


def run(command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def distribution_authority(display):
    authorities = [line.removeprefix("Authority=") for line in display.splitlines()
                   if line.startswith("Authority=")]
    if not authorities or not authorities[0].startswith(("Apple Distribution: ", "iPhone Distribution: ")):
        raise ValueError("Exported app does not use an Apple distribution signing certificate")
    return authorities[0]


def commands(repo, output, options):
    archive = ["xcodebuild", "-workspace", str(repo / "ios/Runner.xcworkspace"),
               "-scheme", "Runner", "-configuration", "Release", "-sdk", "iphoneos",
               "-destination", "generic/platform=iOS", "-archivePath", str(output / "Runner.xcarchive"),
               "archive", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="]
    export = ["xcodebuild", "-exportArchive", "-archivePath", str(output / "Runner.xcarchive"),
              "-exportPath", str(output / "ipa"), "-exportOptionsPlist", str(options)]
    return archive, export


def inspect_app(repo, app, output):
    # Reuse the same final-native and declaration gates as package CI.
    info = plistlib.loads((app / "Info.plist").read_bytes())
    entry = info["CFBundleExecutable"]
    if not isinstance(entry, str) or not entry or entry in (".", "..") or Path(entry).name != entry:
        raise ValueError("Invalid app executable name")
    executable = app / entry
    if (not executable.is_file() or not executable.resolve().is_relative_to(app.resolve())
            or not executable.stat().st_mode & 0o111):
        raise ValueError("App executable must be an executable regular file inside the app")
    if list(app.rglob("*.appex")) or list(app.rglob("*.app")):
        raise ValueError("Additional signed targets need a reviewed profile policy")
    run([sys.executable, str(repo / "tool/ci/native_payload.py"), str(app), "--format", "macho",
         "--arch", "arm64", "--entry", entry, "--report", str(output / "native-inventory.json")])
    run([sys.executable, str(repo / "tool/ci/apple_release_preflight.py"), "--app", str(app),
         "--platform", "ios", "--bundle-id", BUNDLE_ID, "--source-info", str(repo / "ios/Runner/Info.plist"),
         "--report", str(output / "apple-preflight.json")])
    run(["bash", str(repo / "tool/ci/assert_no_test_hooks.sh"), str(app / "Frameworks/tim2tox_ffi.framework")])
    if not (app / "Frameworks/tim2tox_ffi.framework/tim2tox_ffi").is_file():
        raise ValueError("Archive is missing the embedded Tim2Tox framework")


def inspect_archive(repo, output):
    archive = output / "Runner.xcarchive"
    applications = archive / "Products/Applications"
    app = applications / "Runner.app"
    if not app.is_dir() or list(applications.iterdir()) != [app]:
        raise ValueError("Xcode archive must contain exactly one expected application")
    # Tar preserves links, so every retained product/dSYM link must remain
    # usable after the archive is extracted in a different directory.
    root = archive.resolve()
    for path in archive.rglob("*"):
        if not path.is_symlink():
            continue
        try:
            resolved = path.resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise ValueError(f"Xcode archive contains an invalid link: {path}") from error
        if path.readlink().is_absolute() or not resolved.is_relative_to(root):
            raise ValueError(f"Xcode archive link is not portable inside the archive: {path}")
    inspect_app(repo, app, output / "archive-evidence")


def inspect_export(repo, output, team, certificate, expected_profile):
    ipas = list((output / "ipa").glob("*.ipa"))
    if len(ipas) != 1:
        raise ValueError("Expected exactly one newly exported IPA")
    ipa = ipas[0]
    with tempfile.TemporaryDirectory(prefix="inspect-", dir=output) as directory:
        extracted = Path(directory)
        run(["ditto", "-x", "-k", str(ipa), str(extracted)])
        apps = list((extracted / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Exported IPA must contain exactly one application")
        app = apps[0]
        inspect_app(repo, app, output / "export-evidence")
        run(["codesign", "--verify", "--deep", "--strict", str(app)])
        authority = distribution_authority(run(["codesign", "--display", "--verbose=4", str(app)],
                                               capture_output=True, text=True).stderr)
        entitlements = plistlib.loads(run(["codesign", "--display", "--entitlements", ":-", str(app)],
                                         capture_output=True).stdout)
        profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")],
                                    capture_output=True).stdout)
        evidence = profile_evidence(profile, entitlements, team, certificate, expected_profile)
        prefix = extracted / "certificate-"
        run(["codesign", "--display", "--extract-certificates", str(prefix), str(app)], capture_output=True)
        actual = hashlib.sha1(Path(str(prefix) + "0").read_bytes()).hexdigest().upper()
        if actual != certificate:
            raise ValueError("Actual exported app signer does not match the approved owner certificate")
        chain = sorted(extracted.glob("certificate-*"))
        run(["security", "verify-cert", "-p", "codeSign", "-L", "-R", "offline",
             *[arg for path in chain for arg in ("-c", str(path))]], capture_output=True)
    evidence.update({"ipa": str(ipa.name), "ipa_sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
                     "signing_authority": authority,
                     "scope": "Local export and signature/profile checks; store acceptance and device qualification remain pending"})
    (output / "export-evidence/distribution.json").write_text(json.dumps(evidence, indent=2) + "\n")


def build(repo, output, options, team, certificate, unsigned):
    # Never reuse an earlier IPA/archive after a failed export.
    output.mkdir(parents=True, exist_ok=False)
    if not unsigned:
        # Snapshot the validated policy; a later edit of the owner's input must
        # not switch this in-flight operation from local export to upload.
        policy = export_options(options, team, certificate)
        options = output / "ExportOptions.plist"
        options.write_bytes(plistlib.dumps(policy))
    archive, export = commands(repo, output, options)
    run(["flutter", "build", "ios", "--release", "--no-codesign", "--config-only"], cwd=repo)
    run(archive, cwd=repo)
    inspect_archive(repo, output)
    if unsigned:
        (output / "UNSIGNED-ARCHIVE.txt").write_text(
            "Unsigned archive validation only. This is not an exported or store-submittable IPA.\n")
        return
    run(export, cwd=repo)
    inspect_export(repo, output, team, certificate, policy["provisioningProfiles"][BUNDLE_ID])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unsigned-archive", action="store_true")
    parser.add_argument("--team-id")
    parser.add_argument("--certificate-sha1")
    parser.add_argument("--export-options", type=Path)
    parser.add_argument("--output", type=Path, help="New evidence/archive directory; must not already exist")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    try:
        if args.unsigned_archive:
            if args.export_options or args.team_id or args.certificate_sha1:
                raise ValueError("Unsigned validation does not accept distribution inputs")
            certificate, options = None, None
        else:
            if not all((args.team_id, args.certificate_sha1, args.export_options)):
                raise ValueError("Distribution export requires owner team, existing certificate SHA-1 and ExportOptions.plist")
            certificate = fingerprint(args.certificate_sha1)
            options = args.export_options.resolve()
            export_options(options, args.team_id, certificate)
        output = args.output.resolve() if args.output else repo / "build/ios/store-readiness" / uuid.uuid4().hex
        build(repo, output, options, args.team_id, certificate, args.unsigned_archive)
        print(f"{'Unsigned archive validated' if args.unsigned_archive else 'Local export verified'}: {output}")
        return 0
    except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException, subprocess.SubprocessError) as error:
        print(f"iOS store preparation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
