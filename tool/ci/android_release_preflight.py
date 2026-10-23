#!/usr/bin/env python3
"""Hash-bound Android release preflight, separate from Play console approval."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from android_native_artifact import inspect_archive


def run(command):
    result = subprocess.run([str(part) for part in command], text=True,
                            capture_output=True, timeout=180,
                            env={**os.environ, "LC_ALL": "C", "LANG": "C"})
    if result.returncode:
        raise ValueError(f"{Path(str(command[0])).name} rejected artifact: "
                         f"{result.stdout[-2000:]} {result.stderr[-2000:]}")
    return result.stdout


def build_tool(name):
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    if not sdk:
        raise ValueError("ANDROID_SDK_ROOT or ANDROID_HOME is required")
    directory = Path(sdk) / "build-tools"
    versions = sorted((p for p in directory.iterdir() if p.is_dir()),
                      key=lambda p: tuple(int(n) for n in re.findall(r"\d+", p.name)))
    for version in reversed(versions):
        candidate = version / name
        if candidate.is_file():
            return candidate
    raise ValueError(f"Android SDK build tool missing: {name}")


def expected_certificate(value, distribution):
    fingerprint = re.sub(r"[\s:]", "", value).lower()
    if fingerprint and not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
        raise ValueError("ANDROID_SIGNING_CERT_SHA256 must be an upload certificate SHA256")
    if distribution and not fingerprint:
        raise ValueError("Distribution requires ANDROID_SIGNING_CERT_SHA256")
    return fingerprint


def apk_identity(badging, application_id, minimum_target, distribution):
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)'", badging, re.M)
    target = re.search(r"^targetSdkVersion:'(\d+)'", badging, re.M)
    minimum = re.search(r"^(?:minSdkVersion|sdkVersion):'(\d+)'", badging, re.M)
    if not package or package[1] != application_id or int(package[2]) < 1:
        raise ValueError("Final APK application ID or versionCode is invalid")
    if not target or not minimum or int(target[1]) < minimum_target:
        raise ValueError("Final APK target SDK does not meet selected submission threshold")
    debuggable = "application-debuggable" in badging
    if distribution and debuggable:
        raise ValueError("Distribution APK is debuggable")
    return {"application_id": package[1], "version_code": int(package[2]),
            "minimum_sdk": int(minimum[1]), "target_sdk": int(target[1]),
            "debuggable": debuggable,
            "permissions": re.findall(r"^uses-permission[^:]*: name='([^']+)'", badging, re.M)}


def apk_signer(output, expected, distribution):
    fingerprints = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$",
                              output, re.M)
    if len(fingerprints) != 1:
        raise ValueError("Exactly one verified current APK signer is required")
    fingerprint = fingerprints[0].lower()
    if expected and fingerprint != expected:
        raise ValueError("Wrong APK signing certificate")
    if distribution and re.search(r"certificate DN:.*CN=Android\s*Debug(?:,|$)", output, re.I | re.M):
        raise ValueError("Android debug certificate is not distribution signing")
    return fingerprint


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--aab", required=True, type=Path)
    parser.add_argument("--report-dir", required=True, type=Path)
    parser.add_argument("--application-id", required=True)
    parser.add_argument("--min-target-sdk", required=True, type=int)
    parser.add_argument("--abis", required=True, nargs="+")
    parser.add_argument("--distribution", action="store_true")
    args = parser.parse_args()
    distribution = args.distribution or os.environ.get("TOXEE_REQUIRE_SIGNING") == "1"
    try:
        expected = expected_certificate(os.environ.get("ANDROID_SIGNING_CERT_SHA256", ""), distribution)
        apk = inspect_archive(args.apk, "apk", args.abis)
        bundle = inspect_archive(args.aab, "aab", args.abis)
        identity = apk_identity(run([build_tool("aapt2"), "dump", "badging", args.apk]),
                                args.application_id, args.min_target_sdk, distribution)
        fingerprint = apk_signer(run([build_tool("apksigner"), "verify", "--verbose",
                                      "--print-certs", args.apk]), expected, distribution)
        # JAR signatures cover the contents, whereas keytool -printcert alone
        # only reports a certificate and cannot detect a modified/unsigned entry.
        java = Path(__file__).with_name("VerifyAndroidBundle.java")
        bundle_signing = json.loads(run(["java", java, args.aab, expected or "-",
                                         "distribution" if distribution else "development"]))
        if bundle_signing["certificate_sha256"] != fingerprint:
            raise ValueError("APK and AAB upload signers differ")
        report = {"mode": "distribution" if distribution else "development",
                  "expected_upload_certificate_sha256": expected or None,
                  "actual_upload_certificate_sha256": fingerprint,
                  "apk_identity": identity, "apk": apk, "aab": bundle,
                  "aab_signature": bundle_signing,
                  "remaining_evidence": ["bundletool/Play delivered-APK manifest and device filtering",
                                         "16 KB device loading with fallback disabled",
                                         "signed update from previous release",
                                         "privacy/UGC/console and review approval"]}
        args.report_dir.mkdir(parents=True, exist_ok=True)
        (args.report_dir / "android-preflight.json").write_text(json.dumps(report, indent=2) + "\n")
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Android release preflight failed: {error}", file=sys.stderr)
        return 1
    print(f"Android {report['mode']} artifact preflight passed; report: {args.report_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
