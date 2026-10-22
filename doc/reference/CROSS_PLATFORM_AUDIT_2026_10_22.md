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
| 17 Linux package/baseline, P1 | PARTLY | DEB shlibdeps/private-library lookup enabled; RPM automatic requirements preserved. Old distro claims corrected to actual Ubuntu24.04 build baseline, Android23, iOS15.5. CMake/source tests pass. Actual DEB/RPM metadata, GLIBC/GLIBCXX/CXXABI and clean installed launches remain. macOS bundled-library effective minimum is still unproven. |
| 18 Windows distribution, P1 | PARTLY | Configurable Authenticode before MSI creation, then sign/verify MSI; valid vendor signatures preserved. Release CI adds actual MSI install/launch/close/repair/uninstall. PowerShell scripts not run on this Mac. Certificate provisioning, previous-release upgrade and downloaded/SmartScreen tests remain. Same-version repair is not an upgrade test. |
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
| D5,D7 | Linux identity changed above; fork jump-highlight reduced-motion behavior remains upstream work. |
| I1,I2,I4–I7 | Existing mobile evidence plus desktop key fix. Caption controls now have tooltip/semantics names; drag strip double-click maximizes. Touch-target measurement, Narrator/Orca, iPad pointer/menu and Windows snap flyout remain. |
| I3 | Existing mobile IME/Enter evidence retained; separate desktop composer typing race/right-control paste path need upstream checks. |
| I8,I9 | Verified HTTPS/custom tox: handlers and incoming/outgoing OS share entry points remain absent features. |
| B1–B3,B5–B7 | Shared lifecycle/ownership/geometry/schema fixes above; existing mobile interruption/death/picker evidence retained. |
| B4,B8 | Mobile background design retained; desktop path/session-end gaps above. Server-version/sync-conflict reconciliation B8 is N/A to Tox. |
| P1–P6 | Changes above; existing denial/revocation/picker/keychain/backup evidence retained. Linux without Secret Service remains a host check. |
| P7–P9 | Sensitive-export screenshot/app-switcher protection remains unimplemented. Purchases P8 N/A. UGC/deletion/store metadata need operational evidence. |
| M1–M5 | Existing routing/interruptions/formats/decode/low-storage evidence retained; Bluetooth/headsets/privacy-indicator release need physical devices. |
| M6–M8 | Windows backend added, taskbar badge remains TODO. Hardware/ABI gaps above. Screen/system audio capture M8 N/A. |
| W1–W4 | Changes above. Roaming AppData, absolute-XDG validation, tox: registration and shared external-profile-root coordination remain. Apple-silicon iPad/visionOS availability/data continuity is undecided. |
| F1–F3 | No measured release startup/size/frame/thermal budgets. Contact polling skips hidden/paused and unchanged contacts do not rebuild. Desktop 2s status poll and low-power/thermal adaptation remain. |
| X1–X9 | Existing evidence stays dated/qualified. No full layout/touch-target/device/network lab or all-platform installed artifact sweep here. Windows installed CI added but not executed. Release/symbol/crash verification remains required. |

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
