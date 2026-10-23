#!/usr/bin/env python3
"""Inspect built Apple declarations/signatures; console/privacy review is separate."""

import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys


def metadata(app, platform, bundle_id, source_info):
    base = app / "Contents" if platform == "macos" else app
    info = plistlib.loads((base / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != bundle_id:
        raise ValueError("Built bundle identifier does not match selected app record")
    source = plistlib.loads(source_info.read_bytes())
    usage = {key: info.get(key) for key in source if key.startswith("NS") and key.endswith("UsageDescription")}
    if not usage or any(not isinstance(value, str) or not value.strip() for value in usage.values()):
        raise ValueError("Built app is missing a source-declared privacy purpose string")
    own_manifest = base / "Resources/PrivacyInfo.xcprivacy" if platform == "macos" else app / "PrivacyInfo.xcprivacy"
    if not own_manifest.is_file():
        raise ValueError("Built app-owned PrivacyInfo.xcprivacy is missing")
    manifests = []
    for path in sorted(app.rglob("PrivacyInfo.xcprivacy")):
        value = plistlib.loads(path.read_bytes())
        if not isinstance(value, dict):
            raise ValueError(f"Malformed privacy manifest: {path}")
        apis = value.get("NSPrivacyAccessedAPITypes", [])
        if not isinstance(apis, list) or any(
                not isinstance(api, dict) or not api.get("NSPrivacyAccessedAPIType")
                or not isinstance(api.get("NSPrivacyAccessedAPITypeReasons"), list)
                or not api["NSPrivacyAccessedAPITypeReasons"]
                or any(not isinstance(reason, str) or not reason for reason in api["NSPrivacyAccessedAPITypeReasons"])
                for api in apis):
            raise ValueError(f"Malformed required-reason declaration: {path}")
        manifests.append({"path": str(path.relative_to(app)), "declaration": value})
    return {"bundle_id": bundle_id, "version": info.get("CFBundleShortVersionString"),
            "build": info.get("CFBundleVersion"), "usage_strings": usage,
            "build_sdk": {key: info.get(key) for key in (
                "DTXcode", "DTXcodeBuild", "DTSDKName", "DTSDKBuild", "MinimumOSVersion", "LSMinimumSystemVersion")},
            "privacy_manifests": manifests}


def signed_entitlements(app, platform):
    verified = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)],
                              capture_output=True, text=True)
    if verified.returncode:
        if platform == "ios":
            present = subprocess.run(["codesign", "--display", str(app)], capture_output=True)
            if present.returncode == 0:
                raise ValueError("Signed iOS app failed signature integrity verification")
            return {"signature": "unsigned development validation", "entitlements": None}
        raise ValueError("Final macOS app signature verification failed")
    displayed = subprocess.run(["codesign", "--display", "--entitlements", ":-", str(app)],
                               capture_output=True, check=True)
    entitlements = plistlib.loads(displayed.stdout) if displayed.stdout.strip() else {}
    if platform == "macos":
        if entitlements.get("com.apple.security.get-task-allow"):
            raise ValueError("Final macOS release retains get-task-allow")
        if entitlements.get("com.apple.security.app-sandbox") is not True:
            raise ValueError("Final macOS app lost its declared sandbox")
        for capability in ("network.client", "network.server", "device.camera", "device.audio-input"):
            if entitlements.get("com.apple.security." + capability) is not True:
                raise ValueError(f"Final macOS app lost functional entitlement: {capability}")
    return {"signature": "cryptographically verified; publisher/store approval not established",
            "entitlements": entitlements}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--platform", choices=("ios", "macos"), required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--source-info", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = metadata(args.app, args.platform, args.bundle_id, args.source_info)
        report.update(signed_entitlements(args.app, args.platform))
        report["remaining_evidence"] = ["SDK/API reason and collection-owner audit",
                                         "privacy report and store disclosures",
                                         "actual distribution identity/provisioning and exported archive",
                                         "review access, device tests and store approval"]
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.SubprocessError) as error:
        print(f"Apple preflight rejected: {error}", file=sys.stderr)
        return 1
    print(f"Apple built-declaration preflight passed: {args.app.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
