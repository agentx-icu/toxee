[简体中文](STORE_READINESS.zh-CN.md)

# Store release readiness

Policy review: **2026-10-23 (Asia/Shanghai)**. Applies the updated
[cross-platform checklist](https://github.com/agentx-icu/cross-platform-app-checklist),
particularly P4 (privacy/permissions), P8 (conditional commercial rules), P9
(store policy), W4 (desktop distribution), and X6 (release evidence).
This supplements the [65-item audit](../reference/CROSS_PLATFORM_AUDIT_2026_10_22.md).
An inventory or successful CI run establishes the checks described below;
store readiness still requires the owner's declarations and device evidence.

## Implemented checks

| Scope | Status and evidence | Remaining qualification |
| --- | --- | --- |
| Android final APK/AAB | **Verified by automated checks**: every native library's ELF ABI and load-segment alignment; required app/Flutter/Tim2Tox libraries per selected ABI; 16 KB ZIP offsets for uncompressed APK libraries; final APK merged identity, target SDK, permissions and debuggable flag; actual APK signature and every AAB entry's JAR signature. Reports include artifact/library SHA-256. | AAB ZIP offsets do not establish the alignment of Play-delivered APKs. Use bundletool/Play delivery, review device filtering and merged AAB declarations, and exercise native loading on a real 16 KB device with compatibility fallback disabled. |
| Android distribution intent | **Verified gate** in Gradle and the local packager as well as CI: configured upload-certificate SHA-256, no debug signer, matching actual APK/AAB signer, complete signing inputs. Invalid ZIPs, unsigned/tampered entries, missing identity and wrong signer fail. | Owner supplies approved upload key and console identity. Play App Signing's delivery certificate is a separate identity. |
| Windows MSI | **Verified gate**: all final staged EXE/DLL architecture checks, including runtime DLLs copied after the Flutter build; owned code/installer must match the configured publisher thumbprint when signing is enabled; valid third-party signatures are preserved. MSI smoke checks all installed PE files, startup, repair and uninstall. | Trusted publisher certificate, final signed-installer trust evidence, previous-version update/data-preservation test and store listing. Development jobs can remain unsigned. |
| macOS PKG / built iOS app | **Verified checks**: all built native images match the selected architecture; built app-owned and SDK privacy manifests are inventoried; source-declared permission strings and actual bundle ID are checked. Final macOS signatures and functional sandbox entitlements are checked, and get-task-allow is rejected. A signed iOS app with corrupt signatures cannot pass as an unsigned build. Reports retain actual SDK metadata and declarations. | API-reason/collection audit, publisher identity, archive/export, provisioning, privacy report and device tests. Ad-hoc signing establishes integrity only. |
| Linux DEB/RPM | **Verified gate**: every staged native object matches the selected architecture; missing/corrupt shared libraries and external/dangling runtime symlinks fail. | Clean-distribution installation, upgrade/uninstall, signing/metadata and channel-specific sandbox qualification. |
| iOS distribution entry | **Verified restriction**: TOXEE_REQUIRE_SIGNING=1 refuses the development IPA packager. | Implement and qualify an owner-approved Xcode archive/export flow before using this channel for App Store submissions. A certificate alone does not make the existing zip-based IPA an App Store export. |

The regression fixtures cover real aapt2/apksigner/JDK signature operations,
real compiled macOS signing, and controlled corrupt/mismatched payloads. Synthetic
ELF/JAR fixtures test the inspectors; they do not establish app installability.
CI retains native-inventory.json, android-preflight.json and apple-preflight.json
in the corresponding platform artifact where those checks run.

## Reproduce Android distribution preflight

Normal PR builds are development verification artifacts. The manual workflow input
`android_distribution=true` requires these repository inputs:

- Secrets: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD,
  ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD.
- Variable: ANDROID_SIGNING_CERT_SHA256, the owner's expected upload certificate
  SHA-256, as 64 hex digits or colon-separated hex. Never put the private key or
  passwords in a report, issue or PR.

After producing the final signed APK/AAB, the equivalent local entry is:

```bash
ANDROID_HOME=/path/to/android-sdk \
ANDROID_SIGNING_CERT_SHA256=<expected-upload-certificate-sha256> \
TOXEE_REQUIRE_SIGNING=1 \
  bash tool/ci/package_artifacts.sh --target android --mode release
```

Use an exported environment variable instead of the angle-bracket placeholder.
The current gate expects com.toxee.app, arm64-v8a and target SDK >=36. Local
qualification may explicitly set TOXEE_ANDROID_ABIS (space-separated) and
TOXEE_ANDROID_MIN_TARGET_SDK; changing them requires reviewing the selected
channel's current policy. CI deliberately fixes its own ABI/SDK arguments.
As reviewed today, normal phone Play submissions require API 36; an owner-console
extension is conditional. The current 16 KB enforcement page identifies
2027-02-01 as the update-blocking date. Re-check both official sources before a
future submission; do not freeze a deadline into an evergreen claim.

For Windows, configure WINDOWS_SIGN_CERT_SHA1 and an already installed private-key
certificate with signtool. TOXEE_REQUIRE_SIGNING=1 refuses missing signing identity.
For direct macOS distribution, the existing packager uses
MACOS_DEVELOPER_ID_APPLICATION_CERT, MACOS_DEVELOPER_ID_INSTALLER_CERT and
MACOS_NOTARYTOOL_PROFILE; strict mode requires the signing/notarization path.
Those identities and Developer ID notarization are distinct from Mac App Store
signing and provisioning.

## Channel decisions and owner handoff

No channel below is marked ready for submission. For each chosen channel, the
release owner must retain console screenshots/exports, exact submitted hashes,
review date and approver. Optional channels require a decision before extra
packaging work; their absence is not a claim of compliance.

| Channel | Current evidence / status | Owner's next action and acceptance evidence |
| --- | --- | --- |
| Apple App Store: iOS / iPadOS | **To do / needs device**. Built declarations and native inventory; CI IPA is development/device validation. | Select legal publisher, team, app record and matching bundle ID; qualify archive/export and distribution provisioning, current Xcode/SDK acceptance, privacy labels and required-reason report, age/content rating, encryption classification, review notes and a working review/demo/bootstrap path. Record real iPhone/iPad install/update/deletion and denied-permission behavior. Do not infer encryption exemption from the presence of Tox. |
| Mac App Store | **To do**. Current PKG is a direct-distribution path. | Select MAS signing/provisioning, audit sandbox and entitlements for this app, validate store package and installation, supply the same applicable Apple metadata/privacy/review evidence. Replace the com.example copyright placeholder with the owner's approved legal text. |
| Google Play | **To do / needs device**. Strict upload-signature and native checks are available. | Register owner/package, verify upload vs Play App Signing identities, finish Data safety and privacy URL, account-deletion resource if applicable, target audience/rating, app-access instructions and permission declarations. Inspect bundletool/Play-delivered APKs, test 16 KB native loading, background calling and upgrade from the previous release on devices. |
| Huawei AppGallery / Xiaomi / OPPO and other selected Android stores | **Conditional / to do**. Signed APK preflight can be reused. | Name actual region/store and publisher, then check that store's current signing/update-identity rules, SDK/permission disclosures, privacy entry points, screenshots/ratings/review access, and any applicable entity/filing requirements. Record the console decision; Play approval does not establish these channels' approval. |
| Microsoft Store: hosted non-game MSI/EXE | **To do**. MSI build/smoke and signing checks exist. | Select this route explicitly; supply immutable versioned HTTPS offline installer URL, trusted-CA installer and included-code signature evidence, documented silent switches, clean install/update/uninstall and store listing/privacy/support metadata. Validate the currently applicable hosted-installer policy. |
| Microsoft Store: MSIX | **Conditional / to do**. No MSIX packaging/submission flow exists. | Decide whether to add MSIX; qualify package identity, manifest/capabilities, architecture, installation/update and console listing. Store re-signing requirements differ from hosted MSI; do not require purchasing a private distribution certificate solely for a Store-signed MSIX. |
| Direct macOS / Windows / Linux | **Development artifacts; owner qualification to do**. Existing PKG/MSI/DEB/RPM routes. | Retain final signatures/notarization/trust checks as applicable, installer hashes, minimum OS/architecture evidence, clean-machine and previous-version update/uninstall results. |
| Flathub / Snap | **Conditional / to do**. DEB/RPM are not store manifests or sandbox approval. | Owner selects channel and maintains the submission, AppStream/snap metadata, desktop integration, runtime/base, permissions and sandbox tests. Under current Flathub policy a human is responsible for submission manifests and submission PRs; this change creates neither. |
| WinGet / Homebrew / F-Droid | **Conditional / to do**. No new feed is introduced. | First choose the distribution model and validate its official eligibility, reproducibility/source rules, installer checksums and update ownership against the actual package. |

## Privacy, communication and review-access blockers

Toxee has account deletion and contact blocking code; this audit does not replace
those with a claim that peer-to-peer apps are exempt from store policy. The owner
must verify the complete user journey, data left on peers/backups, and any
applicable external account-deletion resource. Confirm accessible privacy/support
URLs from inside the app and the selected stores, including localizations, and
approve the SDK/data-flow inventory against the actual collection/transmission.

For user-generated communication, document and test the applicable report/block/
filter and response/contact process, terms acceptance, age/audience controls and
review access. Existing blocking alone is not a complete moderation declaration.
Do not invent an abuse endpoint, legal entity, policy URL or reviewer credentials.
P8 billing/ads/third-party-primary-login rules are **not applicable to the present
feature set** (no billing, advertising or third-party primary sign-in); re-open
that assessment if any of those features or regions are added.

Mobile review items 1–11 retain the existing behavior and device-test limitations;
item 12 checks both Android and iOS artifact paths. See the dated record in
[MOBILE_DEVICE_FEATURES.md](../reference/MOBILE_DEVICE_FEATURES.md). The unaffected
checklist IDs retain their previous audit state, not a new blanket verified status.

## Primary sources and verification commands

- [Android 16 KB requirements](https://developer.android.com/guide/practices/page-sizes)
- [Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
- [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Microsoft Store policies](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies)
- [Checklist channel references](https://github.com/agentx-icu/cross-platform-app-checklist/blob/master/references/stores.md)

```bash
python3 -m unittest discover -s test/ci -p 'test_android*.py'  # SDK + JDK 17 required
python3 -m unittest discover -s test/ci -p 'test_desktop_native_payload.py'
python3 -m unittest discover -s test/ci -p 'test_apple_release_preflight.py'
pwsh -NoProfile -File tool/ci/test_windows_signing_policy.ps1
flutter test test/ci/macos_signing_native_test.dart test/ci/macos_packaging_test.dart test/cross_platform_packaging_test.dart
```

CI compatibility follow-up: Android build-tools 35 and 37 were both exercised with real signed fixtures; scheme-labelled signer reports retain the same owner-certificate checks. Flutter Windows `data/app.so` is an ELF AOT snapshot loaded by the engine. Only that canonical path has an explicit format exception; its CPU must still match the selected Windows target, while EXE/DLL files remain PE. The checker also passed against all 17 native images of a real Flutter Windows x64 CI artifact.

Native-linking correction: the final APK inspection on the earlier PR head rejected the actual libtim2tox_ffi.so built by CI's NDK 27.3 because its PT_LOAD alignment was 4 KB. Both native build entry points now request flexible page sizes and explicitly set both max-page-size and common-page-size to 16384. Newly built and externally supplied staged FFI libraries receive an ELF/ABI/alignment check before Gradle packaging. A cached 4 KB prebuilt must be rebuilt from source; changing its ZIP placement cannot repair its ELF alignment. Use `ABIS=arm64-v8a NDK=/path/to/complete/ndk bash tool/build_android_ffi.sh` to rebuild the local staged library.

Local verification used NDK 27.0: its default shared-library output was rejected, and the same CMake fixture with the explicit settings passed. A complete release Tim2Tox/ToxAV rebuild also passed all three PT_LOAD segments at 16384, the actual ToxAV marker and the hook-free gate (staged SHA-256 `951d0a7fbb4a2d1cdc0612a88bd11be102cbac4c37e2143b8fbff1b3d62fab8e`). This is native artifact evidence; the final APK/AAB CI and real 16 KB device test remain distinct. The Android suite now has 33 tests, including staged ELF rejection, and the existing packaging regressions cover rejection of 4 KB prebuilt libraries even with the calling-stub opt-out.

Android ABI selection: the final CI APK exposed an unexpected vendor-only armeabi-v7a library despite the arm64 Flutter target. Flutter 3.41 pre-populates build-type ABI filters, which override the staged-FFI filter in defaultConfig. The project now [disables Flutter's automatic ABI filtering](https://docs.flutter.dev/release/breaking-changes/default-abi-filters-android) and clears/sets its own filters from staged FFI libraries. Stage only the requested ABIs; the final APK/AAB inventory still rejects extra ABIs or missing app/engine/FFI libraries. The current release path uses one APK and one AAB; split APKs are not qualified by this change.

A local release APK (52.9 MB) and AAB (40.2 MB) were rebuilt after that correction. Both contain exactly nine arm64-v8a native libraries; complete native/alignment and APK/AAB signature verification passed with JDK 17.0.20 and build-tools 37. The final APK is non-debuggable, com.toxee.app, version code 1, minSdk 24 and targetSdk 36. The same development certificate signs both; this is not an owner-approved store signing identity. APK SHA-256: `2207fe90f23b52a1f4263be7c4537a25426666c8f5023375e5dcf204d50b3b5e`; AAB SHA-256: `a8f1e0188d9fbea0ef9abb304d670377fdb7560996345abb10387436c4163054`.

Windows Tox runtime: full payload inspection exposed x64-only ImSDK.dll and dart_native_imsdk.dll in the ARM64 package. AppBootstrap awaits LoggingBootstrap, which fixes the Dart native library name to tim2tox_ffi before SDK use; the reviewed vendor Windows plugin is an empty registration shim. The app-owned CMake policy retains that compiled shim and other plugin payloads while removing the unused vendor runtime/import libraries on both Windows targets, including stale copies from incremental installs. Reviewed native-source/build hashes require an explicit policy review on SDK changes, including future dynamic loading. Host CMake fixtures compile the actual shim sources, install and load it, and invoke its C registration entry without either vendor DLL. Native Windows builds and complete final-payload architecture checks remain required in CI; these host fixtures do not substitute for Windows device/installer qualification.
