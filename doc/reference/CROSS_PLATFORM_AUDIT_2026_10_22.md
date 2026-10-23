[简体中文](CROSS_PLATFORM_AUDIT_2026_10_22.zh-CN.md)

# Cross-platform audit and fixes — 2026-10-22

Baseline: toxee `fde59b44`, UIKit `bae30b7`, tim2tox `beb6e6a`.
The original static findings were independently checked before implementation.
CONFIRMED/PARTLY/REJECTED adjudicate the finding, not release readiness.
No Claude review or RTK was used. Implemented code and device verification are
separate: a debug build never establishes store/distribution compliance.

| Finding | Verdict | Implementation and remaining verification |
|---|---|---|
| 1 Apple privacy, P0 submission | PARTLY | App/native-framework required-reason manifests added (disk space E174.1, file timestamps C617.1; app UserDefaults CA92.1). macOS app includes manifest. iOS archive/privacy report, SDK-owner audit, privacy labels and App Store Connect still required. Missing encryption key triggers a questionnaire, not automatic rejection; no exemption answer was fabricated. |
| 1b macOS distribution, P0 | PARTLY | Sign all native images/nested frameworks inside-out after mutations, then app, installer and optional notarytool/staple. Strict distribution mode requires identities/profile. Ad-hoc Mach-O fixture passes strict codesign verification. Developer ID credentials, quarantined downloaded packages and both architectures remain unverified. |
| 2 desktop ownership, P1 | CONFIRMED | Claim kernel lock before bootstrap writes; lock inode is never unlinked. Atomic metadata sidecar avoids Windows mandatory byte-lock reads. A second process yields/activates; early activation waits for shell readiness. Subprocess contention/activation/crash-release tests pass. Windows/Linux UI activation still needs hosts. Independently isolated app-support stores that manually share an external custom profile root need extra coordination. |
| 3 hidden camera, P1 macOS | PARTLY | Eligibility and explicit stop branch preserve desktop hidden capture; mobile hidden/paused/detached still suspend, inactive remains eligible. Existing Windows/Linux no-capture capability gates remain. Unit policy and macOS build pass; physical camera/two-peer minimize-hide-restore test remains. |
| 4 HomePage shortcuts, P1 | CONFIRMED | Four commands use Cmd on macOS and Ctrl on Windows/Linux. Eight widget key/action tests reject the wrong modifier and trigger once. Mobile shortcut/menu expansion is a separate feature. |
| 5 quit/checkpoint, P1 | PARTLY | Caption close/framework quit share an awaited idempotent coordinator. Geometry checkpoint failure can cancel/retry before account teardown begins. Destructive teardown is joined without a deadline; completion failures are logged and exit continues, avoiding a page backed by a disposed account. This does not establish that failed writes persisted. Delayed real-dispose and throwing runtime-hook regressions cover both cases; mobile detached keeps its best-effort bound. Native Windows WM_ENDSESSION and Linux session-manager/SIGTERM coverage remain; arbitrary process death has no final-callback guarantee. |
| 6 Android permissions, P0 submission | PARTLY | Remove unused READ_MEDIA_IMAGES/VIDEO/AUDIO, preserve capped legacy access. REJECTED removal of MANAGE_OWN_CALLS: current phoneCall FGS requires it. Source/call tests pass. Merged APK/AAB inspection, API34+ background capture and Play Console forms remain. |
| 7 macOS folder access, P1 | PARTLY | Retain/resolve/refresh scoped bookmarks, probe writability, hold every granted URL until window/process exit so asynchronous/native transfers keep old-folder access. Failed restoration clears custom preference and surfaces default-folder fallback. Channel/prefs tests, Swift typecheck and app build pass. Sandbox release selection outside Downloads, relaunch, moved/revoked folders and switching mid-transfer remain unverified. No speculative profile-root UI added. |
| 8 Windows notifications, P1 | CONFIRMED | Plugin 17.2.4→19.5.0, five locked dependencies; stable AUMID/GUID, normal toasts, incoming-call attention/cancellation. Plugin registers activation. Android minimum stays 23. Notification regression tests pass with explicit unit-test registrant. Windows installed toasts/clicks/settings need a host. |
| 9 abuse reporting/Nearby, P0 submission | PARTLY | Unresolved. Reporting needs an operational receiver/response process. Nearby keys are ephemeral; persisting one cannot implement person-level permanent blocking. Exposing stable identity changes privacy/protocol and needs a product decision. No fake moderation receiver or permanent-block claim added. |
| 10 offscreen restore, P1 | CONFIRMED | Validate caption reachability against enumerated work areas, support negative coordinates, clamp size/position and react to display changes. Geometry tests pass. External-monitor removal/reconnect, mixed-DPI Windows and compositor-controlled Wayland placement need hosts. |
| 11 maximized geometry, P2 | CONFIRMED | Save normal bounds separately; skip minimized/fullscreen/maximized and startup-restoration geometry. Fake-window maximize/exit tests pass. Native snap/tiling/fullscreen/relaunch checks remain. |
| 12 Linux decoration, P1 | PARTLY | Keep native decorations on Linux; suppress duplicate Flutter controls/insets. REJECTED claim that all snapping was lost. Actual non-GNOME X11 resize/menu and GNOME/Wayland integration need Linux WM sessions. |
| 13 network recovery, P2 | PARTLY | macOS NWPathMonitor/path identity/wake events reuse existing session debounce/throttle. Swift typecheck/build pass. REJECTED desktop-never-resumes claim: shared resume recovery already existed. Windows/Linux native watchers and measured Wi-Fi/sleep recovery remain. |
| 14 Linux identity, P2 | CONFIRMED | Install com.toxee.app.desktop; StartupWMClass follows program identity, Icon=toxee still matches installed icons. REJECTED invalid GApplication ID toxee alternative. Metadata tests pass; real X11 WM_CLASS/Wayland grouping need Linux. |
| 15 optional hardware/ABI, P2 | PARTLY | Camera/autofocus/microphone/location features optional; source tests pass. Merged badging and hardware-absent/device behavior remain. Release ABI stays arm64; x86/arm32 requires matching native artifacts/support decision. This does not imply Android TV support. |
| 16 release logging, P2 | CONFIRMED | Implicit CWD/build logs restricted to debug; existing explicit compile-time harness policy retained and release runtime overrides stay disabled. Mobile was already excluded. Packaged release launch from writable/read-only CWD remains a smoke check. |
| 17 Linux package/baseline, P1 | PARTLY | DEB shlibdeps/private-library lookup enabled; RPM automatic requirements preserved. Old distro claims corrected to actual Ubuntu24.04 build baseline, Android23, iOS15.5. CMake/source tests pass. Merged #141 actually qualifies native Ubuntu24.04 x64/ARM64 final DEB metadata/dependency closure and clean installed window/engine/FFI/exit0/uninstall. RPM/Wayland/other distributions and previous-version upgrades remain; macOS bundled-library effective minimum is still unproven. |
| 18 Windows distribution, P1 | PARTLY | Configurable Authenticode before MSI creation, then sign/verify MSI; valid vendor signatures preserved. Merged #141 actually passes Windows AMD64/ARM64 app-local CRT/signature/import gates and installed MSI launch/close exit0/repair/relaunch/uninstall on the native hosts. Certificate provisioning, previous-release upgrade and downloaded/SmartScreen tests remain. Same-version repair is not an upgrade test. |
| B7 history, P1 | CONFIRMED | tim2tox 5341e64 guards primary/backup/direct-save/bulk-load/merge at persistence source, leaves future-version bytes in place and propagates typed upgrade errors through service startup. Unsupported versions are not retried; ordinary disk retry remains. 34 history schema/write-failure/rebind/concurrency/resilience tests pass. Explicit whole-store/account deletion remains a separately authorized destructive operation. Shared Dart covers mobile. |
| B7 account prefs, P1 | CONFIRMED | Reject future account schemas; preflight global/account versions before migration/LAN recovery mutates preferences. Reuse localized upgrade screen. Migration/bootstrap tests preserve data and stamps. Shared Dart covers all hosts. |

## Full checklist disposition

Existing evidence in [MOBILE_DEVICE_FEATURES](MOBILE_DEVICE_FEATURES.md) remains
qualified by its date/device. The following records every checklist group without
turning old simulator evidence into new device verification.

| IDs | Status / remaining checks |
|---|---|
| L1–L7 | Existing emulator/simulator layout evidence; iPad floating keyboard, native desktop resizing/call breakpoint and iPadOS26 controls need devices. |
| L8 | Fold/tabletop DisplayFeature layout remains unimplemented. |
| D1–D4,D6 | Existing scale/theme/locale evidence; Dynamic Type, fractional/mixed DPI, desktop bold text and long/RTL strings need the full matrix. |
| D5,D7 | Linux identity changed above; jump-highlight reduced-motion/static cue is fixed through the tracked UIKit overlay; OS preference propagation and other animations still need qualification. |
| I1,I2,I4–I7 | Existing mobile evidence plus desktop key fix. Caption controls now have tooltip/semantics names; drag strip double-click maximizes. Touch-target measurement, Narrator/Orca, iPad pointer/menu and Windows snap flyout remain. |
| I3 | Existing mobile IME/Enter evidence retained; desktop normal-Enter now reads the current controller through the draft coordinator; do not treat the old typing-race note as a reproduced failure. Right-control paste and key-up resource handling are fixed by the tracked overlay and real-key regressions; modified-Enter selection remains an unconfirmed candidate needing a fixture. |
| I8,I9 | Verified HTTPS/custom tox: handlers and incoming/outgoing OS share entry points remain absent features. |
| B1–B3,B5–B7 | Shared lifecycle/ownership/geometry/schema fixes above; existing mobile interruption/death/picker evidence retained. |
| B4,B8 | Mobile background design retained; desktop path/session-end gaps above. Server-version/sync-conflict reconciliation B8 is N/A to Tox. |
| P1–P6 | Changes above; existing denial/revocation/picker/keychain/backup evidence retained. Linux without Secret Service remains a host check. |
| P7–P9 | Sensitive-export screenshot/app-switcher protection remains unimplemented. Purchases P8 N/A. UGC/deletion/store metadata need operational evidence. |
| M1–M5 | Existing routing/interruptions/formats/decode/low-storage evidence retained; Bluetooth/headsets/privacy-indicator release need physical devices. |
| M6–M8 | Windows backend added, taskbar badge remains TODO. Hardware/ABI gaps above. Screen/system audio capture M8 N/A. |
| W1–W4 | Changes above. Relative XDG is fixed by the follow-up W3 change with real Linux process tests. Roaming AppData migration, optional tox: registration and shared external-profile-root coordination remain separately classified. Apple-silicon iPad/visionOS availability/data continuity is undecided. |
| F1–F3 | No measured release startup/size/frame/thermal budgets. Contact polling skips hidden/paused and unchanged contacts do not rebuild. The desktop UI-only 2s LAN status poll now stops while hidden/paused/detached, refreshes on visibility restoration and coalesces slow reads. Actual energy/thermal/low-power qualification remains. |
| X1–X9 | Existing evidence stays dated/qualified. No full layout/touch-target/device/network lab or all-platform installed artifact sweep here. Merged [#141](https://github.com/agentx-icu/toxee/pull/141) actually passed Windows AMD64/ARM64 installed MSI lifecycle and native Ubuntu24.04 x64/ARM64 DEB install/window/maps/exit0/uninstall, plus an Xcode26 unsigned archive. Formal owner signing, other distributions/Wayland/upgrades, complete symbol/native-crash verification and device coverage remain. |

## Follow-up source audit and remaining engineering (2026-10-23)

The 65-item table above retains device qualifications. These are concrete remaining
causes, not a claim that everything left needs certificates. [Store readiness](../operations/STORE_READINESS.md)
records the current W3/X9/I2 fixes and owner-material locations. #141 merged as
`2a0934495682ff36f0b833893860ce0daf1583ec`; its actual installed/unsigned-archive
checks must not be relabelled as pending code merely because this older report
predates their CI. A new follow-up PR still needs its own final-head checks.

| IDs | Classification / exact source evidence | Smallest remaining action and boundary |
| --- | --- | --- |
| W3 | **Code fixed in follow-up:** `lib/util/app_paths.dart:getProfileStorageRoot` accepted relative XDG_DATA_HOME and could rename legacy accounts into CWD. | Absolute validation retains HOME/platform fallback, custom roots, old bytes and migration. Real native Linux child processes cover relative/absolute/unset/no-HOME; final-head CI qualifies execution. Windows APPDATA is an existing roaming policy, not the same defect. |
| X9 | **Partially code fixed:** `lib/main.dart` hooks previously followed AppBootstrap; `lib/util/logger.dart` accepted arbitrary bodies/exception values and canonical custom paths bypassed rotation. | Current early hooks and static-category production boundary are exercised with marker-secret child-process output and actual stripped-AOT capture-point symbolication. Caller Type/StackTrace objects are never evaluated; this does not identify the original throw frame. The separate native ofstream defect is now fixed by the source-pinned single-owner sink and generation C ABI: shared ten × 10 MiB ledger, 64 KiB UTF-8 records, close-before-delete, no unsafe Dart file fallback, real over-budget pristine-source reproduction and >120 MiB concurrent/cross-session source regressions. Final CI evidence qualifies its actual OS/architecture. Native reporter and complete exact-build symbol archives remain **code work**, followed by installed release fault tests. Existing short-lived compute/Isolate.run workers already return errors through Futures; forced-fault/original worker-stack and SDK/plugin/native-thread qualification remain, rather than an assumed missing persistent-worker listener. A remote service is not a prerequisite. |
| I2 | **macOS code fixed in follow-up:** `macos/Runner/Base.lproj/MainMenu.xib` Preferences lacked action, although Home Cmd+, worked. | Reuse Home settings via owner/ready/current-route channel. iPadOS26 native core-command menus are **separate code work**; existing `home_page.dart` Search/Settings actions can be bridged to current-scene UICommand. Native compilation and real device/menu/accessibility qualification are separate. |
| D7 | **Local code/test verified:** tracked UIKit overlay replaces reduced-motion flashing with a bounded static highlight and cancels owned timers/callbacks. | Five actual base-widget tests cover normal/static motion, runtime changes in both directions, original completion deadline and disposal. Bootstrap checks pinned revision plus patch/before/after hashes; eight real-source fixtures cover application and fail-closed drift. Native OS setting propagation and the remaining animation inventory need platform qualification. |
| I3 | **Local code/test verified / separate candidate:** tracked desktop input overlay accepts both control keys and both meta keys only on RawKeyDown. `_submitDesktopSend` already reads controller text and uses draftCoordinator. | Four actual composer/key tests verify a single resource read and a single framework plain-text paste, with no key-up read. Modified-Enter selection remains an unconfirmed candidate; reproduce before changing it. The old normal-Enter race is not reproduced. IME/hardware keyboard qualification still needs the OS matrix. |
| W2,B4 | **Native code work:** Windows runner/plugin and Flutter42d3d75 engine WindowsLifecycleManager handle WM_CLOSE, without WM_QUERYENDSESSION/WM_ENDSESSION; Linux `my_application_shutdown` adds no save bridge and app has no SIGTERM/session-manager handler. | Feed supported OS session-end requests into existing DesktopWindowState.prepareToExit/checkpoint with idempotence and platform deadlines, then exercise native logoff/session shutdown. Normal close/quit is already tested and installed exit0 passed. SIGKILL/power loss has no guaranteed final callback; preserve continuous persistence. |
| X8,B4 | **Native code work:** `network_change_rebootstrapper.dart:platformSnapshots/startForSession` explicitly excludes Windows/Linux; their native watchers are absent. Existing resume re-bootstrap and the shared 3 s debounce/30 s throttle already work. | Windows IP Helper/power notifications and Linux GNetworkMonitor/sleep/resume feed the existing session-bound policy, without new services or app permissions. Unit/native tests first, then real Wi-Fi/handover/sleep qualification. |
| F3 | **UI polling code fixed in this follow-up:** `ForegroundUiPoller` pauses the Home 2 s UI status read while hidden/paused/detached, refreshes when visible and coalesces in-flight reads; the 15 s contact poll already distinguishes resumed/inactive. | Lifecycle, slow-read, teardown and error regressions cover the UI observer. P2P/LAN/call service behavior is preserved. Installed-window behavior and energy/thermal/low-power qualification still require declared target devices and measurements. |
| L8 | **Code work + UX/device qualification:** no DisplayFeature/occluding-hinge layout in app sources; width-only fold fixtures do not exercise hinges. | Avoid occluded panes and preserve draft/selection under synthetic display-feature changes before claiming fold support. Tabletop/two-pane allocation needs a defined product layout and physical foldable qualification; these do not make basic hinge avoidance non-engineering. |
| P7 | **Product decision:** `MOBILE_DEVICE_FEATURES.md` permission-table P4 explicitly calls sensitive-export capture protection a product decision; no approved sensitive-surface policy or FLAG_SECURE/capture-response implementation was found. | Owner defines protected surfaces and screenshot/recording/app-switcher behavior, then implement platform-specific protection and test real capture. Do not block every screen or invent universal prevention. |
| W3,W4,I8 | **Storage design/code + channel choice:** APPDATA remains roaming; shared user-selected external profile roots lack cross-process ownership; verified tox:/HTTPS OS registration is absent. | Design migration/recovery/ownership without moving existing accounts opportunistically. OS link entry points depend on selecting promised schemes/domains and, for verified HTTPS, owner-controlled association hosting; no new optional channel is fabricated. |
| I9,M6 | **Product scope + existing platform limits:** OS inbound share targets are not shipped; Windows badge is explicitly conditional in `badge_service.dart`, while notifications use WinRT. | Choose supported incoming content/notification surface before adding new behavior. Existing outgoing clipboard/share flows still require host qualification. Absence alone does not authorize a new share extension or taskbar feature. |
| P1–P6,P9,W4,X6 | **Owner material/operational evidence + devices:** declarations/inspectors exist; formal signing, privacy/API-reason answers, store text/assets, UGC operations and previous-release data-preserving upgrades are unqualified. | Use the platform/purpose/console/public-ID/secure-environment handoff table. Do not collect keys/passwords, submit stores, deploy association files or create permissions/accounts. |
| L1–L7,D1–D6,I1,I4–I7,B1–B3,B5–B7,M1–M7,F1–F2,X1–X7 | **Existing partial evidence / measurement and device matrix:** no new definite failure is established merely by the unexecuted combinations. | Keep exact old tests/date/settings; add reproducible cases if a concrete defect appears. Run native DPI/RTL/large-text/readers/touch/permissions/media/16KB/upgrade and release-performance scenarios. Missing objective budgets require product targets; existing source-level gaps listed above remain code work. |
| P8,B8,M8 | **Not applicable to current features:** no purchases, Tox server-version reconciliation or screen/system-audio capture is shipped. | Reopen only if those product features are introduced. |

Shared Dart fixes cover iOS/Android; desktop windows/locks have no mobile window
counterpart, and the Android engine-owner guard is preserved.

## Validation and release boundary

macOS debug app build and standalone new-Swift typecheck passed. A signing fixture
passed codesign deep/strict verification. Plists/Xcode project syntax, shell syntax,
regression tests, analysis and complexity gate are recorded in the handoff. Existing
plugin/Xcode warnings are not release validation. No release, notarized package,
store submission, hardware camera/headset or installed Windows/Linux run is claimed.

Production signing identities/notarization profile, UGC operations/privacy decision,
extra ABIs, Windows/Linux path/session-end integration and device matrix remain
unresolved. Never count “needs device” or a configured CI step as a completed run.

Final local regression: 328 selected cross-platform/notification/bootstrap/call/schema/history/network/WinRT tests passed; 39 additional localization/shortcut/exit tests passed; 34 independent tim2tox-related tests passed. `flutter analyze lib tool --no-fatal-warnings --no-fatal-infos` has no errors (existing warning/info findings remain); `dart run tool/check_complexity.dart` passed.

macOS automatic last-window termination is disabled so Cocoa cannot race Dart preventClose/checkpoint. Successful windowManager.destroy still invokes NSApp.terminate. A source declaration regression covers the parity fix; real Cmd+Q/close remains a host check.

Quit follow-up: 25 window-state/session-shutdown/account-lifecycle tests pass,
including delayed disposal beyond the old ten-second deadline and failure after
destructive teardown. Analysis of the four touched Dart files has no issues;
the complexity gate passes. These tests do not prove failed writes persisted.

macOS packaging CI follow-up: job 119902022028 built the release app, then failed
to execute the mode-100644 signing helper. Packaging now invokes it with Bash,
matching the other CI helpers. Regressions run the packaging entry point with a
644 helper and cover signing failure propagation. A real SDK 26.4 Mach-O fixture
passes ad-hoc strict verification and PKG creation; Developer ID/notarization and
clean installed release validation remain separate requirements. Mobile signing
uses a separate packaging path and is unaffected.

The first PR CI run exposed a second signing-order failure on x86_64 (job
119912161238): signing CFBundleExecutable directly makes codesign inspect its
containing bundle before unsigned siblings are ready. arm64's linker-provided
ad-hoc signatures had hidden this case. The signer now defers declared bundle
entry points, signs loose native code, then nested bundles inside-out, then the
outer app with release entitlements. Inode comparison follows framework
Versions/Current links; absent executable keys are not guessed. Final deep/strict
verification is retained; signing does not use --deep.

Four real macOS fixtures remove all initial signatures and cover both CPU
architectures, nested apps/frameworks, optional executable keys, standalone
helpers and paths containing spaces. All four fail with the old signer and pass
after the fix; the combined packaging suite passes all ten tests. Reproduce with
`SDKROOT="$(xcrun --sdk macosx26.4 --show-sdk-path)" flutter test --no-pub test/ci/macos_signing_native_test.dart test/ci/macos_packaging_test.dart test/cross_platform_packaging_test.dart`.
Both macOS package jobs now run these native/order regressions before app build.
CI evidence must refer to the final PR head, not the superseded first run.

The full Linux coverage run then found one legacy policy test still assuming
mobile hidden-camera behavior for its desktop host (3110 passed, one failed).
The test now covers the complete mobile/desktop state table explicitly; an
adjacent controller test also selects its desktop policy explicitly. Production
camera behavior is unchanged and its documentation now states the distinction.

Windows ARM64 provisioning also stalled in Chocolatey's optional DotNet3.5
deployment; old job 119912160586 remained there until the next push canceled it.
Provisioning now reuses installed, working tools or fetches
the [official WiX 3.14.1 portable release](https://github.com/wixtoolset/wix3/releases/tag/wix3141rtm)
with bounded retries and a pinned SHA256. That older GitHub asset has no API
digest; the pinned value was independently computed from the official release
ZIP: `6ac824e1642d6f7277d0ed7ea09411a508f6116ba6fae0aa5f2c7daa2ff43d31`.
The executables contain CLR4 metadata; actual bounded candle/light help probes
and the subsequent MSI/install smoke remain mandatory on both Windows runners.
Seven provisioning regressions exercise archive integrity, missing tools,
resolved paths, exit failures and process timeouts; they do not substitute for
running the real Windows tools. Mobile packaging is unaffected by this helper.

After provisioning succeeded, Windows ARM64 job 119945606703 exposed STL1011 in
the notification FFI plugin. Its reviewed 1.0.3 archive requests C++17 and includes
WinRT; the existing ordinary-plugin workaround did not cover FFI targets. The
initial C++20 override passed a standard-selection fixture but real AMD64 job
119961024434 rejected the plugin's legacy ATL::CW2A conversions with C2440.
The final compatibility rule therefore retains C++17 and uses the define adopted
by [upstream 3.1.1](https://raw.githubusercontent.com/MaikuB/flutter_local_notifications/flutter_local_notifications_windows-v3.1.1/flutter_local_notifications_windows/src/CMakeLists.txt),
only on this target under MSVC 19.51 or later. This is migration debt until the
plugin no longer needs the experimental header. Six CMake/compiler-gating and
artifact tests cover the affected compiler input, older/non-MSVC inputs, unrelated
targets, missing targets and expiry; six existing WinRT tests also pass locally.
These host-compiler fixtures do not compile the actual WinRT/ATL plugin; Windows
CI remains the required full-source validation.

The same log explicitly reported x64 Dart fallback. On 2026-10-22, the pinned
3.41.9 engine's Windows ARM64 Dart/release archives returned 404; the equivalent
[3.44.0 engine archive](https://storage.googleapis.com/flutter_infra_release/flutter/4c525dac5ebe5971c5708ef73558ed8edcf4a362/windows-arm64-release/windows-arm64-flutter.zip)
and Dart archive returned 200. [Flutter's upstream discussion](https://github.com/flutter/flutter/issues/186730)
also explains the native Dart architecture's control over the Windows target.
Only the ARM64 job therefore uses 3.44.0, with framework commit
`559ffa3f75e7402d65a8def9c28389a9b2e6fe42` checked before execution; other jobs retain
Flutter 3.41.9. LUCI_CONTEXT preserves
the pinned release's engine.version on the shallow stable checkout. A streaming
PE-header gate rejects a non-ARM64 Dart and rejects mismatched app, Flutter engine
or Tim2Tox binaries before packaging. Eleven PE/MSI regression cases cover valid
x64/ARM64, mixed machines, invalid signatures/offsets, truncation, missing files
and MSI Template mismatches. The installer explicitly maps each supported machine
to [CPack's WiX architecture](https://cmake.org/cmake/help/latest/cpack_gen/wix.html#variable:CPACK_WIX_ARCHITECTURE)
and 64-bit file semantics rather than relying on the compiler-free project's
default. Three generated-CPackConfig fixtures first failed, then passed for both
machines and rejection of an unknown machine. The installed smoke reads the
actual MSI SummaryInformation Template and checks the installed binaries' PE
machines before launch/close/repair/uninstall.
Actual ARM64 build, MSI creation and installed smoke must still pass on the final
head. PR runs intentionally skip the tag/manual-only GitHub Release publication.

The real ARM64 build also reproduced Flutter 3.44's removal of
ExtendSelectionByPageIntent in extended_text_field 16.0.2. The official
[17.0.0 release](https://pub.dev/packages/extended_text_field/versions/17.0.0)
removes the obsolete binding while its existing adjacent-page action
retains keyboard page selection. Its declared Flutter minimum remains 3.24 and
its extended_text_library dependency is unchanged. Both the manifest and generated
bootstrap overrides now select exactly 17.0.0; actual bootstrap/pub resolution and
package_config confirm this, and the lock changes only that package to the
official archive hash `495b8cc6b4a66b5323d71afe1df1c5f08b716fdc925e4339aeaa14a2f0cf65a9`.
Override generation was extracted to a small module so the bootstrap complexity
ratchet shrinks rather than growing. On Flutter 3.41.9, 86 real input tests pass;
independent Flutter 3.44 checks pass 44 input tests, both new Windows/macOS
Shift+PageDown/Up selection variants and a full app Dart-kernel build. The same
isolated 3.44 tree first reproduced the four missing-intent errors with 16.0.2.
Kernel success is not a Windows native/MSI or physical IME qualification claim.


Store-specific follow-up (2026-10-23): [readiness, implemented gates and owner blockers](../operations/STORE_READINESS.md). Unaffected IDs retain the states above.
