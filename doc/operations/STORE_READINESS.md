[简体中文](STORE_READINESS.zh-CN.md)

# Store release readiness

Policy review: **2026-10-23 (Asia/Shanghai)**. Applies the updated
[cross-platform checklist](https://github.com/agentx-icu/cross-platform-app-checklist),
particularly P4 (privacy/permissions), P8 (conditional commercial rules), P9
(store policy), W4 (desktop distribution), and X6 (release evidence).
This supplements the [65-item audit](../reference/CROSS_PLATFORM_AUDIT_2026_10_22.md).
An inventory or successful CI run establishes the checks described below;
store readiness still requires the owner's declarations and device evidence.

## UIKit motion and paste (D7 / I3)

The tracked `tool/uikit_overlays` patch is applied by bootstrap only after checking the UIKit revision, patch and before/after source SHA-256. Drift or partial application fails without resetting local work; offline verification does not write. Shared jump-to-message highlighting uses a bounded static cue under reduced motion. Changing the preference cancels flashing without extending the completion deadline; disposing a row cancels timers and delayed provider callbacks. Desktop left/right Ctrl or Cmd+V reads resources only on key-down. Flutter's existing PasteTextIntent remains the sole plain-text insertion; key-up no longer reads resources again. Actual UIKit widget timing/disposal and real-key regressions, plus real-source patch fixtures, pass. Shared highlighting reaches phone, tablet and desktop; paste remains desktop-only. OS setting propagation, physical keyboard/IME, native selection menus and other animations still need platform qualification; this does not complete all D7/I3.

## Existing macOS Preferences action (I2)

The shipped MainMenu.xib had a Preferences… item without an action; the existing Flutter Cmd+, shortcut already opened the settings tab. The native item now invokes that same action through toxee/desktop_menu. It is enabled only for an initialized account's current Home route, disabled while covered/disposed, and carries a route-owner token so a queued command cannot cross account replacement. Four real widget/channel lifecycle cases plus the eight existing shortcut cases pass. A real macOS debug app build compiles Swift and the connected XIB. This is not evidence of iPadOS 26 native command coverage or an installed release accessibility/menu sweep; those remain separate work.

## Local production diagnostics (X9, partial)

Framework/dispatcher hooks are installed before session ownership and bootstrap; the guarded zone also captures binding failures. Production Dart logs accept closed origins, static exception categories and bounded internally captured VM package/dart locations or AOT build IDs/addresses. Arbitrary messages, exception values, framework context/collectors and SDK print bodies are omitted, including console and logger-failure paths. Debug binding buffers, presentation and harness bodies remain available. Up to 32 early records (24 allowed stack lines each) are flushed when the sink opens; failure fallback cannot re-enter the logger. Type/runtimeType getters and caller-supplied StackTrace objects are never evaluated. `stack=capture_point` identifies the logger capture location, not the original throw origin; original exception stacks remain debug-only. A failed console/stderr writer cannot escape the handler, and a failed console sink is disabled while file output continues.

The existing Dart retention limits remain ten app log files and 10 MB segments. Canonical explicit app_<timestamp>.log paths now receive the same rotation as the implicit default; arbitrary custom fixture names retain their documented append behavior. `test/util/production_diagnostics_test.dart` exercises the boundary and retention. `python3 tool/ci/test_production_diagnostics.py` inspects actual child-process stdout/stderr with a marker secret and symbolizes a real stripped Dart AOT trace from its exact symbols. These shared-code checks are not an installed release crash test on every OS.

**Still engineering work:** Tim2Tox's V2TIMLog has its own mutex-protected std::ofstream and only a set-log-file FFI export; its SDK OnLog listener is not the V2TIMLog writer. Dart renaming/reopening cannot rotate that retained native descriptor, and periodic file stats cannot bound concurrent native writes. Native sink ownership/bounded retention, spawned-worker forwarding, native crash capture, complete exact-build symbol archives and installed release fault/symbolication tests remain open. They do not inherently require a remote service. No upload or new telemetry service is added.

## Linux profile storage (W3)

A relative XDG_DATA_HOME is ignored, as required by the XDG base-directory contract. The existing HOME/.local/share fallback (or platform Application Support without HOME), explicit absolute overrides, user-selected roots and one-time legacy migration are preserved. `python3 tool/ci/test_linux_profile_paths.py` runs four real native-Linux child-process environments, checks existing account bytes and idempotence, and rejects any migration into the working directory. These cases are a separate hard CI step; local macOS path tests alone do not qualify Linux behavior.

## Implemented checks

| Scope | Status and evidence | Remaining qualification |
| --- | --- | --- |
| Android final APK/AAB | **Verified by automated checks**: every native library's ELF ABI and load-segment alignment; required app/Flutter/Tim2Tox libraries per selected ABI; 16 KB ZIP offsets for uncompressed APK libraries; final APK merged identity, target SDK, permissions and debuggable flag; actual APK signature and every AAB entry's JAR signature. Reports include artifact/library SHA-256. | AAB ZIP offsets do not establish the alignment of Play-delivered APKs. Use bundletool/Play delivery, review device filtering and merged AAB declarations, and exercise native loading on a real 16 KB device with compatibility fallback disabled. |
| Android distribution intent | **Verified gate** in Gradle and the local packager as well as CI: configured upload-certificate SHA-256, no debug signer, matching actual APK/AAB signer, complete signing inputs. Invalid ZIPs, unsigned/tampered entries, missing identity and wrong signer fail. | Owner supplies approved upload key and console identity. Play App Signing's delivery certificate is a separate identity. |
| Windows MSI | Final staged EXE/DLL architecture and publisher gates remain. The app-local MSVC CRT gate additionally requires vendor signatures, complete runtime imports and loaded modules from the installed directory; Windows CI must exercise it on both machines. MSI smoke covers installed PE files, startup, repair and uninstall. | Trusted publisher certificate, redistribution rights, final signed-installer trust evidence, previous-version update/data-preservation test and store listing. Development jobs can remain unsigned; bundled Microsoft CRTs must retain valid vendor signatures. |
| macOS PKG / built iOS app | **Verified checks**: all built native images match the selected architecture; built app-owned and SDK privacy manifests are inventoried; source-declared permission strings and actual bundle ID are checked. Final macOS signatures and functional sandbox entitlements are checked, and get-task-allow is rejected. A signed iOS app with corrupt signatures cannot pass as an unsigned build. Reports retain actual SDK metadata and declarations. | API-reason/collection audit, publisher identity, archive/export, provisioning, privacy report and device tests. Ad-hoc signing establishes integrity only. |
| Linux DEB/RPM | **Verified inventory gate**: staged native objects, architecture and runtime links. A separate clean Ubuntu 24.04 container gate now installs the final DEB, checks dependency closure before harness installation, compares installed bytes/modes, launches as nobody, observes the same PID's X11 window and engine/FFI maps, gracefully closes and uninstalls. Final CI evidence is required per native architecture. | RPM and other distributions, Wayland, hardware, previous-version upgrade, signing and channel sandbox qualification remain separate. |
| iOS distribution entry | **Verified restriction**: TOXEE_REQUIRE_SIGNING=1 refuses the development IPA packager. A separate local-only archive/export entry validates explicit manual export policy and the exported signature/profile identity. | Qualify a real owner-signed export and device installation. An unsigned archive or the existing zip-based IPA is not an App Store export. |

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

### Native desktop prerequisites and installed evidence

PR #140's ARM64 payload inventory had 23 native images and no MSVC CRT. Actual
PE imports required MSVCP140/VCRUNTIME140, plus MSVCP140_ATOMIC_WAIT from Tim2Tox;
the hosted runner's preinstalled tools masked that missing app-local dependency.
CMake now selects release CRTs from the configured toolchain's target-specific
VCToolsRedistDir (or CMake's InstallRequiredSystemLibraries), rejects missing,
debug, ambiguous and wrong-CPU inputs, and installs a redistribution notice.
Before and after signing, the final package verifies the original Microsoft
Authenticode signatures and every PE's runtime import closure. The installed
smoke checks that loaded CRT modules come from the app directory, preserving
vendor signatures instead of re-signing Microsoft's files with the publisher key.
The standalone signing entry also rejects invalid/unsigned/non-Microsoft CRTs
before tool discovery and keeps CRTs out of its re-sign branch. Windows CI mutates
a copy of a real signed runtime to verify rejection without invoking a signer.
Read-only PKCS7 inspection of Microsoft's official redists found two precise
publisher CNs: `Microsoft Corporation` (ARM64) and `Microsoft Windows Software
Compatibility Publisher` (x64). Both also require the exact Microsoft Corporation
organization and a Valid Windows Authenticode result. The inspected x64 installer
SHA-256 was `cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b`.
Offline certificate extraction alone does not establish signature trust.
Installed close requires exit code zero. The runner explicitly destroys the
controller through OnDestroy before COM teardown, clearing its client pointer
before native-window callbacks can re-enter Flutter during controller disposal;
font-change handling also tolerates that cleared pointer. Both Windows targets
must prove the actual installed shutdown in the latest PR head's CI.

ARM64 is deliberate: the official Microsoft ARM64 redistributable inspected on
2026-10-23 contains ARM64X MSVCP/VCRUNTIME/atomic-wait DLLs and an EC-only
vcruntime140_1.dll. Native ARM64 imports in the prior package do not reference
that EC-only supplement, so it is excluded; x64 still requires the three DLLs
listed by Flutter. The inspected ARM64X CRTs retain raw PE Machine AA64, while
that EC-only supplement has raw Machine 8664. The original strict AA64 gate is
unchanged; no general mixed-machine exception is introduced. CRT filenames are
reviewed and every included CRT must have a valid Microsoft signature.
The downloaded reference installer SHA-256 was
`5139e1440c3a20b92153a4db561c069a0175aaf76c276c3e5b6f56099edcf4b0`;
CI uses its own compiler-selected redist, not that downloaded installer. Windows
10/11 supplies the Universal CRT. See [Flutter Windows distribution](https://docs.flutter.dev/platform-integration/windows/building#building-your-own-zip-file-for-windows),
[Microsoft redistribution](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files)
and [ARM64X compatibility](https://learn.microsoft.com/en-us/windows/arm/arm64x-pe).
The owner must confirm the applicable Visual Studio redistribution rights;
successful copying/signature verification does not grant a license.

Both Linux package jobs run the clean-container DEB gate on their native
x86_64/aarch64 hosts, with no SDK or host desktop/data mounted. Its JSON/logs
retain the exact DEB/image identity, package dependencies, installed hashes,
window/PID/maps and uninstall result, including on failure. Xvfb software
rendering proves this bounded Ubuntu/X11 startup path; it does not establish
RPM/Wayland, real GPU/audio/camera/network behavior or an old-version upgrade.
DSO dependency inspection may use only the installed app's private library
directory to model companions already loaded by the engine; the actual GUI
launch has no LD_LIBRARY_PATH override and must map the installed engine/FFI.
The first clean installations exposed a missing libEGL loader: both architectures
aborted before a window appeared. DEB now explicitly requires libegl1/libgl1/libgles2
and RPM declares their SONAMEs, because libepoxy uses dlopen and static shlibdeps
cannot discover them. The final native DEB gate must verify the corrected package;
the RPM declaration does not establish an installed RPM result.
Before installing the harness, the gate resolves the exact three loader SONAMEs,
checks their real files/native architecture and dependency closure, and records
the result. Harness-provided graphics packages cannot satisfy this earlier gate.
Linux caption close still awaits the application's window/account checkpoint;
after success it uses Flutter's SystemNavigator.pop application-quit path. This
avoids window_manager synchronously destroying the GTK/GL view during engine
shutdown ([upstream report](https://github.com/leanflutter/window_manager/issues/585)).
MethodChannel regressions check pending saves, cancellation/retry and duplicate
close coalescing; final native DEB smoke still requires real exit code zero.

### Local iOS archive and manual export

After the normal dependency bootstrap and staging a hook-free device Tim2Tox
framework, run `python3 tool/ci/ios_store_export.py --unsigned-archive` for an
unsigned Xcode archive. The iOS package job runs this path and retains the
archive, dSYMs and inspection reports for seven days. It is **not a signed or
store-submittable IPA**. Keep any build selected for release beyond CI expiry.

For an owner-controlled environment with an existing installed Apple Distribution
certificate/private key and App Store provisioning profile, supply an approved
ExportOptions.plist and run:

```bash
python3 tool/ci/ios_store_export.py --team-id ABCDE12345 \
  --certificate-sha1 OWNER_CERTIFICATE_SHA1 \
  --export-options /secure/local/ExportOptions.plist
```

Replace the public IDs/fingerprint placeholders. The plist must explicitly set
`method=app-store-connect`, `destination=export`, `signingStyle=manual`, the same
`teamID`, `signingCertificate` as the exact 40-hex SHA-1, and one
`provisioningProfiles` mapping from `com.toxee.app` to the existing profile name
or UUID. No example signing team, profile or legal owner is approved by this doc.
The entry snapshots the policy before building and rejects existing output
directories, preventing stale IPA reuse. It validates archive and exported native
payload/declarations, signature integrity, profile expiry, explicit app/team
entitlements, disabled debugging, and the actual signer certificate bound to the
profile. Device/ad-hoc/enterprise profiles and internal-only exports are rejected.
The archive must contain only the expected application; its declared executable
must be a regular file inside the bundle with executable permissions. The native
inventory also checks its actual Mach-O header and architecture.
The archive root must be a real directory. All retained links, including dSYMs, must resolve internally and use
relative targets so the tar remains usable after extraction elsewhere.

The entry uses unsigned `flutter build ios --config-only` and direct Xcode archive
and export commands. It never passes automatic provisioning/device-registration
flags and does not upload. Calling signed `flutter build ipa` directly can pass
those flags; do not use it to enforce this task's no-account-change boundary.
Inspect `archive-evidence` and `export-evidence/distribution.json`; fixture policy
tests do not establish real signing or App Store approval. Xcode's supported export
keys were checked with local Xcode 26.4.1 `xcodebuild -help` on 2026-10-23.

This store-preparation entry requires built `DTXcode` metadata for Xcode 26+
and `DTSDKName=iphoneos26+` for both unsigned archives and exported applications.
The two version floors are independent. Missing, malformed, simulator or old metadata
fails before the export command or distribution evidence can succeed. CI uses
`macos-26`, explicitly selects an installed Xcode 26+ through `DEVELOPER_DIR`,
and checks its actual iPhoneOS SDK before building; it does not change the global
Xcode selection or install a toolchain. An earlier hosted compatibility archive
recorded Xcode 16.4 / iPhoneOS 18.5 and does not meet the current store floor.
The ordinary development IPA path is separate. This minimum follows Apple's
[submission requirements](https://developer.apple.com/news/upcoming-requirements/)
reviewed on 2026-10-23; future submissions still need a fresh policy review.
The newer hosted Xcode also rejected the generated framework identifier's
underscore. The build now emits `org.toxee.tim2tox-ffi`; framework/executable
names and the runtime load path remain `tim2tox_ffi`.

Local unsigned-archive verification on 2026-10-23 used Flutter 3.41.9, Xcode
26.4.1 (17E202), iphoneos26.4 (23E252), app 0.1.0+1, minimum iOS 15.5. It
passed the real Xcode archive command and inspected all 45 arm64 native images,
built declarations/privacy manifests and the hook-free embedded Tim2Tox framework.
That local run reused the existing device FFI binary; CI rebuilds it from the
pinned source. Nineteen export-policy/failure/bundle-boundary regressions, five Apple metadata
regressions and eleven native-payload regressions pass. No owner-signed export,
store upload or device installation was performed.

The former advisory analyzer returned exit 1 for 62 warnings and 189 infos even
while GitHub displayed success. Its 251 normalized findings exactly matched
merged #140; none originated in the native changes. Source fixes now address
async error ownership, lifecycle/context guards and the remaining diagnostics,
with existing dependency versions retained. The same full-scope strict command
`flutter analyze lib tool test integration_test` is a failing CI gate, with no
continue-on-error, ignored rules or reduced scope. Local zero-diagnostic output
does not replace final-head CI, behavioral regressions or physical-device tests.
The coverage job sets `TOXEE_TESTS_NEED_NATIVE=1` after staging the real FFI,
so encrypted-password cancellation must execute instead of taking the optional
native-test skip. macOS-only signing cases remain platform-specific and are
executed on macOS; Linux coverage does not establish those checks.

| Checklist IDs | Status | Evidence and remaining qualification |
| --- | --- | --- |
| P1, P4 | verified (inspection gates); to do (owner audit) | Built Apple metadata/native inspection runs on archive and export; SDK/API reasons, data disclosures and selected console answers still require owner review. |
| W4, X6 | verified (unsigned archive and policy gates); to do (distribution) | Real unsigned Xcode archive above; negative tests reject upload, automatic signing, wrong team/profile/certificate, expiry, development/device/enterprise identity and stale output. Real manual signed export/install remains untested. |
| X9 | verified (bounded Dart capture-point diagnostics); to do (native/installed qualification) | Static categories and internal capture-point AOT symbolize regression above; original exception stacks are debug-only. Archive/dSYMs retained for seven days do not by themselves establish native reporter coverage, all-binary symbol match or controlled installed release crash symbolication. |
| X4 | needs device | Owner signs/exports, installs and upgrades on iPhone/iPad, then exercises permissions, network/media and preserved user data. |
| X5 | verified (change scope); parity qualification retained | Platform packaging gates and analyzer-required async/lifecycle corrections are covered by their regressions and final native CI. Android retains its final-artifact gate; this does not establish general feature parity. |
| L*, D*, I*, B*, M*, F* | existing audit states retained | Async/lifecycle safety corrections do not establish layout, input, media, performance or device qualification. Existing full-audit limitations remain; mobile checklist item 12 gains archive evidence, not formal release qualification. |

### Materials the release owner must supply

Public identifiers, URLs and certificate fingerprints may be recorded in release
evidence. Private keys, passwords, tokens and reviewer credentials stay only in
the owner's secure environment or the store's designated secret fields. No secret
is requested in this repository or PR.

| Platform/channel | Material and purpose | Where the owner obtains or confirms it | Blocked step |
| --- | --- | --- | --- |
| Apple iOS/iPadOS and MAS | Legal publisher, Team ID, app record and bundle ID; public IDs bind package to owner | Apple Developer **Account → Membership details**; **Certificates, Identifiers & Profiles → Identifiers**; App Store Connect **My Apps → app → App Information** | Real owner identity/export and console configuration |
| Apple iOS/iPadOS | Existing Apple Distribution certificate SHA-1, matching App Store profile and approved manual ExportOptions | Apple Developer **Certificates, Identifiers & Profiles → Certificates / Profiles**; Keychain Access **My Certificates** for the installed key's fingerprint; owner-managed Xcode archive export options | Signed local export, device installation/update; private key/password only configured locally |
| Direct macOS | Existing Developer ID Application/Installer identities and notarytool profile | Apple Developer **Certificates**; Keychain Access **My Certificates**; owner's already configured notarytool keychain profile | Trusted PKG signing, notarization, quarantined-download test |
| Google Play/Android stores | Permanent package record, approved upload-certificate SHA-256 and distinct delivery-certificate SHA-256 | Play Console **app → Test and release → Setup → App signing**; other chosen store's app/signature console; owner-held upload keystore | Strict distribution APK/AAB and signed upgrade; private keystore/passwords only in owner environment or existing GitHub Actions secret fields |
| Microsoft hosted MSI/EXE | Publisher/product record, existing trusted code-signing identity thumbprint, immutable HTTPS installer URL | Partner Center **Apps and games → product**; owner's certificate provider/store and certificate manager; owner-approved download hosting | Trusted PE/MSI signing and hosted-installer certification; key/token only in secure signing host |
| Windows CRT redistribution | Applicable licensed-toolchain redistribution rights/terms; approve unmodified Microsoft release-runtime delivery | Owner's Visual Studio license records and the applicable Microsoft [2022](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution) / [2026](https://learn.microsoft.com/en-us/visualstudio/releases/2026/redistribution) redistribution list | Legal release qualification; the code/signature gate does not grant rights or accept agreements |
| Microsoft MSIX (optional) | Chosen package Identity Name, Publisher and store record | Partner Center **product → Product identity** | Separate MSIX implementation/qualification; Store signing does not require buying a private distribution certificate |
| All selected stores | Approved privacy/support/deletion URLs, SDK/data-flow disclosure, legal copyright, age/audience answers, localized listing text/screenshots, review instructions and UGC contact/response process | Owner's approved public pages and legal/operations records; App Store Connect **App Privacy / App Information / App Review**; Play Console **Policy and programs → App content / Store presence**; Partner Center submission **Properties / Age ratings / Store listings / Certification notes** | Owner declarations, review access and policy review; reviewer credentials only in store's secure review fields |
| China Android channels (conditional) | Region, publisher verification and applicable APP filing/sector materials | Selected channel's developer console and owner's filing/legal records | Channel-specific eligibility; do not infer applicability from another store |
| Flathub/Snap/feeds (optional) | Channel decision, name/app ID ownership, human-maintained submission materials and sandbox evidence | Respective publisher console and official submission process | Channel-specific packaging/review; Flathub manifests and submission PR work remain human-owned |
| Every actual release | Exact artifact hash/version, console-selected regions/track, previous signed build and physical-device results | CI artifacts plus owner-held release archive and store testing tracks/device lab | Install/update/data preservation, permission/network/media and real 16 KB tests; no account material substitutes for these checks |

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
python3 -m unittest discover -s test/ci -p 'test_ios_store_export.py'
python3 -m unittest discover -s test/ci -p 'test_msvc_runtime.py'
python3 -m unittest discover -s test/ci -p 'test_linux_installed_smoke.py'
pwsh -NoProfile -File tool/ci/test_windows_runtime_policy.ps1
pwsh -NoProfile -File tool/ci/test_windows_signing_policy.ps1
flutter test test/ci/macos_signing_native_test.dart test/ci/macos_packaging_test.dart test/cross_platform_packaging_test.dart
```

CI compatibility follow-up: Android build-tools 35 and 37 were both exercised with real signed fixtures; scheme-labelled signer reports retain the same owner-certificate checks. Flutter Windows `data/app.so` is an ELF AOT snapshot loaded by the engine. Only that canonical path has an explicit format exception; its CPU must still match the selected Windows target, while EXE/DLL files remain PE. The checker also passed against all 17 native images of a real Flutter Windows x64 CI artifact.

Native-linking correction: the final APK inspection on the earlier PR head rejected the actual libtim2tox_ffi.so built by CI's NDK 27.3 because its PT_LOAD alignment was 4 KB. Both native build entry points now request flexible page sizes and explicitly set both max-page-size and common-page-size to 16384. Newly built and externally supplied staged FFI libraries receive an ELF/ABI/alignment check before Gradle packaging. A cached 4 KB prebuilt must be rebuilt from source; changing its ZIP placement cannot repair its ELF alignment. Use `ABIS=arm64-v8a NDK=/path/to/complete/ndk bash tool/build_android_ffi.sh` to rebuild the local staged library.

Local verification used NDK 27.0: its default shared-library output was rejected, and the same CMake fixture with the explicit settings passed. A complete release Tim2Tox/ToxAV rebuild also passed all three PT_LOAD segments at 16384, the actual ToxAV marker and the hook-free gate (staged SHA-256 `951d0a7fbb4a2d1cdc0612a88bd11be102cbac4c37e2143b8fbff1b3d62fab8e`). This is native artifact evidence; the final APK/AAB CI and real 16 KB device test remain distinct. The Android suite now has 33 tests, including staged ELF rejection, and the existing packaging regressions cover rejection of 4 KB prebuilt libraries even with the calling-stub opt-out.

Android ABI selection: the final CI APK exposed an unexpected vendor-only armeabi-v7a library despite the arm64 Flutter target. Flutter 3.41 pre-populates build-type ABI filters, which override the staged-FFI filter in defaultConfig. The project now [disables Flutter's automatic ABI filtering](https://docs.flutter.dev/release/breaking-changes/default-abi-filters-android) and clears/sets its own filters from staged FFI libraries. Stage only the requested ABIs; the final APK/AAB inventory still rejects extra ABIs or missing app/engine/FFI libraries. The current release path uses one APK and one AAB; split APKs are not qualified by this change.

A local release APK (52.9 MB) and AAB (40.2 MB) were rebuilt after that correction. Both contain exactly nine arm64-v8a native libraries; complete native/alignment and APK/AAB signature verification passed with JDK 17.0.20 and build-tools 37. The final APK is non-debuggable, com.toxee.app, version code 1, minSdk 24 and targetSdk 36. The same development certificate signs both; this is not an owner-approved store signing identity. APK SHA-256: `2207fe90f23b52a1f4263be7c4537a25426666c8f5023375e5dcf204d50b3b5e`; AAB SHA-256: `a8f1e0188d9fbea0ef9abb304d670377fdb7560996345abb10387436c4163054`.

Windows Tox runtime: full payload inspection exposed x64-only ImSDK.dll and dart_native_imsdk.dll in the ARM64 package. AppBootstrap awaits LoggingBootstrap, which fixes the Dart native library name to tim2tox_ffi before SDK use; the reviewed vendor Windows plugin is an empty registration shim. The app-owned CMake policy retains that compiled shim and other plugin payloads while removing the unused vendor runtime/import libraries on both Windows targets, including stale copies from incremental installs. Reviewed native-source/build hashes require an explicit policy review on SDK changes, including future dynamic loading. Host CMake fixtures compile the actual shim sources, install and load it, and invoke its C registration entry without either vendor DLL. Native Windows builds and complete final-payload architecture checks remain required in CI; these host fixtures do not substitute for Windows device/installer qualification.


## F3 follow-up: visible-window status polling

The existing desktop LAN status UI queried preferences/service state every two seconds even while hidden and could overlap a slow read. `ForegroundUiPoller` now cancels the timer while hidden/paused/detached, refreshes when visible again, keeps visible inactive desktop windows current, and coalesces overlapping ticks into at most one read plus one visibility refresh. Disposal cancels future refreshes. This changes UI observation only; it does not stop P2P, the LAN bootstrap service or calls. Widget regressions exercise lifecycle transitions, slow reads, teardown and error recovery. Installed-window behavior, energy/thermal measurements and low-power qualification remain unverified device work; this does not close all of F3. No account, certificate or new permission is needed.
