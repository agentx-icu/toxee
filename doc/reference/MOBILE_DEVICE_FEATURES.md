[中文](./MOBILE_DEVICE_FEATURES.zh-CN.md)

# Mobile device feature compatibility checklist

> Drafted 2026-09-26. Siblings: [PLATFORM_SUPPORT](./PLATFORM_SUPPORT.md),
> [MOBILE_BACKGROUND](../architecture/MOBILE_BACKGROUND.md).

toxee targets iOS / iPadOS / Android as well as desktop. Phones and tablets have
device features that desktops don't (audio routing, the proximity sensor,
rotation, split screen, background suspension, network handover, ...), and they
affect whether chat, calls and layout behave correctly. This document lists
them and, per item, states **whether toxee needs to adapt to it** and where the
implementation stands today.

**This is a standing constraint, not a one-off audit.** Every new feature or
bugfix is checked against the [review checklist](#review-checklist-for-new-work)
at design and review time (see the "Mobile parity" clause in the root
`CLAUDE.md`).

## Priority and status legend

| Priority | Meaning |
|---|---|
| **P0** | Must adapt. Without it a core function (messaging, calls, usable layout) breaks, or a platform/store rule requires it |
| **P1** | Should adapt. A common usage scenario is noticeably degraded; schedule soon |
| **P2** | Optional. An enhancement or a niche scenario; do it when there is demand |
| **Won't adapt** | Conflicts with toxee's P2P / single-instance architecture, or the cost far exceeds the benefit; the reason is written down so it isn't re-litigated |

| Status | Meaning |
|---|---|
| ✅ Implemented | The code implements it (location given) |
| ◐ Partial | Only some platforms or some scenarios are covered |
| ❌ Missing | No handling in the code |
| 🔍 Needs device test | The code appears to handle it, but it hasn't been verified on a real device |

Status reflects a static code check of `master` at 2026-09-26 (40b0cd9),
revised after a codex review. "Implemented" does not mean "verified on a
device". "fork" means `third_party/chat-uikit-flutter`.

---

## 1. Calls · audio

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| A1 | Speaker / earpiece toggle | P0 | ✅ | `lib/call/audio_devices.dart`, `lib/call/call_audio_route_sheet.dart`; native `ios/Runner/CallAudioChannel.swift`, `android/.../CallAudioChannel.kt` |
| A2 | Default route: voice → earpiece, video → speaker, headset connected → headset | P0 | ◐ | The initial route only chooses earpiece vs speaker (`CallAudioChannel.swift:136`, `CallAudioChannel.kt:345`); preferring an already-connected headset isn't handled explicitly |
| A3 | Bluetooth headset / car kit: switch automatically when it connects or disconnects mid-call | P0 | ❌ | Native code only reports device-change events (iOS `routeChangeNotification`, Android `AudioDeviceCallback` `CallAudioChannel.kt:78`); Dart (`call_service_manager.dart:1360`) only shows a hint and updates the proximity sensor, and never selects the new device. iOS system default behaviour needs a device test |
| A4 | Wired / USB-C headset plug and unplug | P0 | ❌ | Same as A3 |
| A5 | Proximity sensor: screen off at the ear, no cheek taps | P0 | ✅ | iOS `CallAudioChannel.swift:132` (`isProximityMonitoringEnabled`); Android `CallAudioChannel.kt:233-253` (proximity wakelock). Deliberately off on the group-call page (`call_service_manager_busy.dart:303`) |
| A6 | Audio interruptions: phone call, alarm, Siri, another app taking audio focus; resume afterwards | P0 | ✅ | iOS `interruptionNotification` (`CallAudioChannel.swift:86`); Android `OnAudioFocusChangeListener` (`CallAudioChannel.kt:48`); group calls: `interrupted` state in `av_conference_session_bridge.dart` |
| A7 | Echo cancellation / noise suppression / auto gain (critical on speaker) | P0 | ◐ | Recording requests echo cancellation and noise suppression (`audio_handler.dart:70`); iOS uses `voiceChat` mode (`CallAudioChannel.swift:91`). No evidence of auto gain; actual AEC quality on speaker needs a device test |
| A8 | Microphone / camera actually released after the call (status-bar privacy indicator goes off) | P0 | 🔍 | `call_service_manager_native.dart:209`; a lingering indicator means a resource leak |
| A9 | Silent switch / Do Not Disturb / Focus vs ringtones and message sounds | P1 | 🔍 | iOS calls via CallKit are handled by the system; the in-app ringtone and Android must be checked to honour silent mode |
| A10 | Volume keys adjust call volume, not media volume, during a call | P1 | ❌ | Android only sets communication mode; `MainActivity` doesn't set `volumeControlStream = STREAM_VOICE_CALL` |
| A11 | Category conflicts when recording, playback and calls share AVAudioSession (`record` / `audioplayers` / call) | P1 | ◐ | `audio_devices.dart:133` only repairs the PCM player overwriting the session category; voice-message recording / `audioplayers` playback interleaved with a call isn't covered |
| A12 | Switch voice-message playback to the earpiece when held to the ear | P2 | ❌ | Common IM nicety, not required |

## 2. Calls · video / camera

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| V1 | Front / back camera flip | P0 | ✅ | `lib/call/video_handler.dart:165-182,669`, `call_camera_switch_controller.dart`, `in_call_view.dart:216` |
| V2 | Front-camera mirroring (local preview mirrored, outgoing frames not) | P0 | ✅ | `lib/call/call_video_transform.dart` |
| V3 | Frame rotation as the device rotates | P0 | ✅ | `call_video_transform.dart:108-133` |
| V4 | Camera stopped by the OS in background and restarted on resume; the peer sees "video paused" rather than a frozen frame | P0 | ◐ | Stop and restart on resume are implemented (`call_service_manager.dart:506`); the peer only sees the last frame or a generic placeholder (`in_call_view.dart:256`), there is no "video paused" state |
| V5 | Camera disabled by iPadOS during multitasking (Split View / Slide Over / Stage Manager) | P1 | ❌ | Capture failure only resets the capturing flag and logs (`video_handler.dart:443-447`); there is no user-facing "camera unavailable" state. Check and enable `AVCaptureSession.isMultitaskingCameraAccessSupported/Enabled` (older systems need an entitlement, tied to the `voip` background mode, while `Info.plist` only has `audio` and `fetch`); at minimum show an unavailable state instead of black video |
| V6 | External cameras (iPad USB-C, Android UVC) | P2 | ◐ | When there's no opposite lens the switch cycles to the next device in the list (`video_handler.dart:170`), so an external camera can be reached, but it gets no dedicated handling |
| V7 | Center Stage | P2 | 🔍 | Whether it is on by default depends on the app's background modes / capture setup, so it is not necessarily zero-code; test on a supported iPad |
| V8 | Zoom, flash | Won't adapt | — | Not needed for calls |

## 3. Screen and layout

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| L1 | Safe areas: notch, Dynamic Island, punch-hole, rounded corners, home indicator | P0 | ✅ | Widespread `SafeArea` / `viewPadding` |
| L2 | Android 15+ enforced edge-to-edge (targetSdk ≥ 35) | P0 | 🔍 | `targetSdk = flutter.targetSdkVersion`; content behind the status / navigation bars must be checked page by page |
| L3 | Phone landscape, iPad in all four orientations (declared in Info.plist, iPad includes upside-down) | P0 | ◐ | Declaring them is a commitment: chat, call, settings and login must all work. Rotation doesn't recreate the Activity (`configChanges` includes `orientation|screenSize`) |
| L4 | Crossing a responsive breakpoint at runtime: rotation / split screen switching single-pane ↔ master-detail keeps the open conversation, the draft and the call UI | P0 | ◐ | `lib/util/responsive_layout.dart` (600 / 720 / 800 / 1024 breakpoints). Known narrow-shell issues are recorded separately |
| L5 | iPad Split View / Slide Over / Stage Manager (core screens usable at any window size) | P0 | 🔍 | No `UIRequiresFullScreen` in Info.plist, so multitasking is on. That key is deprecated as of iPadOS 26 — **don't use it to opt out**; make every width usable instead. Layout is width-driven so it should work, but it's untested |
| L6 | Android split screen / freeform / pop-up windows (per OEM; core screens usable at any window size) | P0 | 🔍 | No `resizeableActivity` in the manifest (resizable by default). For apps targeting API 36 on devices with smallest width ≥ 600dp, Android 16 ignores orientation and resizability restrictions (a temporary opt-out exists on 16 only); `targetSdk = flutter.targetSdkVersion` (`build.gradle.kts:60`). Same as L5: width-driven, untested |
| L7 | Multiple windows / scenes (iPad multi-scene, Android multi-instance windows) | Won't adapt | — | toxee is a single Tox instance (see `CLAUDE.md` Singleton flow). Several windows sharing one session is possible in principle, but the benefit is small and the change large; keep `UIApplicationSupportsMultipleScenes` undeclared |
| L7a | Prevent a second launch from contending for the same profile (Android re-launching the Activity, multi-instance windows) | P1 | 🔍 | `launchMode="singleTop"` (`AndroidManifest.xml:61`) doesn't fully prevent new tasks / instances; confirm a second Activity doesn't initialise Tox again |
| L8 | Foldables: size change on fold / unfold | P1 | 🔍 | Essentially L4; `configChanges` includes `smallestScreenSize|screenLayout`, so no recreation |
| L9 | Foldable hinge avoidance, tabletop (Flex) mode | P2 | ❌ | No `DisplayFeature` handling |
| L10 | Soft keyboard: occlusion, landscape keyboard, iPad floating / split keyboard | P0 | ◐ | Android `adjustResize`; composer, emoji panel and keyboard transitions need device tests |
| L11 | System font scaling / accessibility large text | P1 | ◐ | Some pages size with `textScalerOf`; overflow at the largest setting hasn't been swept |
| L12 | Dark mode follows the system | P1 | ✅ | `lib/main.dart:269-285` (`ThemeMode.system`) |
| L13 | Keep the screen on during calls | P0 | ✅ | `lib/call/call_effects_listener.dart:70,88` (`WakelockPlus`) |

## 4. Background and lifecycle

This is where a P2P client hits its hardest limits on mobile; see
[MOBILE_BACKGROUND](../architecture/MOBILE_BACKGROUND.md).

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| B1 | Keep the Tox connection alive in background | P0 | ◐ | Android foreground service `ToxPollingService` (`dataSync|phoneCall|microphone|camera`), but subject to B8's time limit; iOS only has the `audio` + `fetch` background modes and `BGAppRefreshTask` (`BackgroundTaskController.swift`), which is best-effort |
| B2 | Receive messages and calls after the app is terminated (push wake-up) | Won't adapt | — | Needs an APNs / FCM / PushKit server, which conflicts with pure P2P (argued in MOBILE_BACKGROUND). Explain it to users at the product level. Distinguish: while the app is alive but suspended, iOS still grants occasional BG refresh, but real-time delivery can't be promised |
| B3 | Answerable incoming-call UI in background / on the lock screen | P0 | ✅ | iOS CallKit (`CallKitProvider.swift`, while the app is alive); Android full-screen notification (`notification_channels.dart:83`, `notification_service.dart:755`) |
| B3a | Android `ConnectionService`: answer from Bluetooth buttons, car integration | P2 | ❌ | Not integrated |
| B4 | Lifecycle: persist the profile on `paused` / `detached` | P0 | ✅ | `lib/ui/home_page.dart:613-617`; `inactive` fires for Control Center, incoming calls, etc. and is deliberately ignored |
| B5 | OEM background restrictions (MIUI / EMUI / ColorOS auto-start, battery-optimisation allow-list), Doze | P1 | ❌ | OEM policies may still kill the foreground service. At least provide an entry that guides users to allow-list the app (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` or the OEM settings page) |
| B6 | Cold-start recovery after Android reclaims the process (back to the conversation) | P1 | 🔍 | Auto-login exists (`_StartupGate`); restoring the page stack is unverified |
| B7 | Reduce polling and video bitrate in Low Power / battery saver mode | P2 | ❌ | |
| B8 | `dataSync` foreground-service time limit: for apps targeting API 35+, 6 h cumulative per 24 h while in background (returning to foreground resets the budget); `onTimeout` handling and fallback | P0 | ❌ | `ToxPollingService` runs as `dataSync` indefinitely and doesn't implement `onTimeout`; not stopping at the timeout is treated as an error by the system |
| B9 | iOS data protection while the device is locked: can the profile / messages be read and written in background | P1 | 🔍 | Relies on the default protection class (`lib/util/app_paths.dart:80`) |

## 5. Network

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| N1 | Fast reconnect after Wi-Fi ↔ cellular handover / IP change (especially mid-call) | P1 | ◐ | No runtime network-change listener (no `NWPathMonitor` / `ConnectivityManager.NetworkCallback`); extra bootstrap happens on resume or disconnect (`home_page.dart:625`). toxcore recovers on its own but may take tens of seconds; measure recovery time before deciding whether to trigger it proactively |
| N2 | UDP blocked on cellular, symmetric NAT: TCP relay fallback | P0 | ◐ | TCP relays are added, but using the node's UDP port plus fixed 443 / 3389 (`tim2tox_ffi.cpp:3590`) — the node list's `tcpPorts` are **not used** (`bootstrap_node_ensurer.dart:136`); test on a real cellular network |
| N3 | IPv6-only / NAT64 networks | P0 (if shipped on the App Store) | 🔍 | The App Store requires apps to support IPv6-only networks. Node address selection prefers IPv4 (`bootstrap_nodes.dart:36`) and the built-in list contains IPv4 literals; test bootstrap under DNS64 / NAT64 |
| N4 | iOS Local Network permission (LAN discovery, LAN pairing) | P0 | ✅ | `NSLocalNetworkUsageDescription`, Bonjour `_tox._tcp` |
| N5 | Cellular data controls (file auto-accept, video bitrate) | P2 | ❌ | |

## 6. Permissions and privacy

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| P1 | Runtime permissions: camera, microphone, photos, notifications (Android 13+); messaging and a path to Settings when denied | P0 | ◐ | `permission_handler`; behaviour of each entry point under "denied / permanently denied" needs checking |
| P2 | Permission revoked while in use (turned off in Settings, then back to the app) | P1 | 🔍 | iOS kills the process on revocation; Android doesn't necessarily |
| P3 | Keychain / Keystore storage; Keychain leftovers after reinstall on iOS | P1 | ◐ | `flutter_secure_storage`; stale password data vs a fresh install needs checking |
| P4 | Screenshot / recording protection on sensitive pages, blurred app-switcher snapshot (key / profile export, QR code) | P2 | ❌ | No `FLAG_SECURE`; a product decision |
| P5 | Biometric unlock (Face ID / fingerprint) | P2 | ❌ | |
| P6 | iOS limited photo access, Android 14 partial media access | P2 | 🔍 | Pickers are system pickers and usually don't need full library access |
| P7 | iOS "Allow Paste" prompt on clipboard reads | P2 | 🔍 | Triggered when `pasteboard` reads images |

## 7. Media and files

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| M1 | Pick photos / videos from the library or camera | P0 | ✅ | `file_picker`, `camera` |
| M2 | HEIC / HEVC (iOS defaults) sent to desktop peers (Windows / Linux may not display them) | P1 | ❌ | The send path passes the picked file straight to `sendFile` (`home_page.dart:892`) with no transcoding; `.heic` is only recognised by extension (`ffi_chat_service.dart:8310`). HEVC video often lives in `.mov`, so compatibility can't be judged by extension. With P2P there's no server-side transcoding — it must happen on the sender |
| M3 | Save to the photo library | P1 | ◐ | Only the personal QR code uses the photo-library channel (`profile_qr_controller.dart:99`); "save" on received chat media goes through a file-save picker (fork `tencent_cloud_chat_message_viewer.dart:115`), not the library |
| M4 | iOS Files app sharing, Android SAF picker | P1 | ◐ | `UIFileSharingEnabled`; the Android SAF picker has a known mis-tap lockout |
| M5 | Receiving large files when storage is low | P1 | 🔍 | Failure must be reported clearly and partial files cleaned up |
| M6 | Memory use of large images / video thumbnails (low memory, easily killed) | P1 | 🔍 | |
| M7 | QR scanning (viewfinder in landscape / split screen) | P1 | ◐ | `mobile_scanner` |
| M8 | Share into toxee from other apps (Share Extension / `ACTION_SEND`) | P2 | ❌ | New feature |
| M9 | Process reclaimed while the system camera / picker is open; result lost on return | P1 | 🔍 | Camera goes through `image_picker` (fork `tencent_cloud_chat_message_camera.dart:33`); no `retrieveLostData` recovery path seen |

## 8. Notifications and system integration

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| S1 | Local notifications, badge | P0 | ✅ | `flutter_local_notifications`, `app_badge_plus`, `lib/notifications/` |
| S2 | Option to hide message content in lock-screen notifications | P1 | ❌ | |
| S3 | Vibration / haptics | P1 | ✅ | |
| S4 | Picture-in-picture for video calls | P2 | ❌ | iOS needs `AVPictureInPictureVideoCallViewController` plus multitasking camera access, Android needs `supportsPictureInPicture`; substantial native work |
| S5 | Dynamic Island / Live Activity during calls, Android ongoing-call notification | P2 | ◐ | The Android foreground-service notification exists |
| S6 | Deep links (`tox:` URI to add a friend, `tox://pair` pairing) | P2 | ❌ | `tox://pair` is parsed (`lib/util/pairing/pairing_url.dart`), but the manifest only has the launcher entry and iOS has no `CFBundleURLSchemes`; not wired to the OS |
| S6a | Home-screen shortcuts, widgets | P2 | ❌ | |
| S7 | iOS communication notifications (with avatars), Android conversation bubbles | P2 | ❌ | |

## 9. Input and interaction

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| I1 | Long-press menus don't fight the system text-selection menu | P0 | ◐ | One round of fixes landed (iPhone narrow-shell work) |
| I2 | System back: Android predictive back, iOS edge swipe, vs route stack / dialogs | P0 | 🔍 | `enableOnBackInvokedCallback="true"` is on; back from the call UI and stacked dialogs needs device tests |
| I3 | iPad hardware keyboard: Enter to send, shortcuts | P1 | ◐ | The mobile composer handles hardware Enter-to-send and modifier+Enter for a newline (fork `tencent_cloud_chat_message_input_mobile.dart:794`); other shortcuts unverified |
| I4 | iPad pointer / trackpad hover, right-click menus, drag-and-drop files into chat | P2 | ❌ | |
| I5 | Screen readers (VoiceOver / TalkBack) | P1 | ◐ | Only scattered semantics labels (e.g. `home_widgets.dart:302`); whether the main chat flow is completable with a screen reader is unverified |
| I6 | System 12 / 24-hour time | P1 | ❌ | Message times use the locale's `DateFormat.jm` (fork `tencent_cloud_chat_intl.dart:150`) and ignore the system preference; should use `MediaQuery.alwaysUse24HourFormat` |

## 10. Other

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| O1 | RTL layout mirroring | P1 | ✅ | `ar.lproj` among six languages |
| O2 | Adaptive video encoding under thermal throttling | P2 | ❌ | |
| O3 | CPU architectures: arm64 devices + simulators | P0 | ✅ | Android `abiFilters` follow the FFI build outputs |

---

## Review checklist for new work

Answer every item at design and review time with **verified / to do / not
applicable (with reason)**:

1. **Size**: usable at 320pt wide, in iPad 1/3 split, in landscape, and when crossing a responsive breakpoint at runtime; state (draft, selected conversation, scroll position) survives. (L3–L6, L8)
2. **Safe areas and keyboard**: nothing hidden behind the notch, home indicator, edge-to-edge system bars or the soft keyboard. (L1, L2, L10)
3. **Large text and screen readers**: no overflow at the largest text size; new controls have semantics labels. (L11, I5)
4. **Lifecycle**: backgrounded, suspended or killed midway — no data loss, no stuck intermediate state, recovers on resume. (B1, B4, B6, V4, M9)
5. **Background time**: logic that relies on running in background accounts for Android foreground-service limits and iOS suspension. (B1, B8)
6. **Audio**: playing or recording sound doesn't conflict with calls, system calls, Bluetooth / wired headsets or the silent switch. (A1–A11)
7. **Camera**: a clear state when the camera is unavailable in multitasking or background. (V4, V5)
8. **Permissions**: messaging and a way out when a permission is denied, permanently denied or revoked mid-use; incoming calls still have an entry when notifications are denied. (P1, P2, B3)
9. **Network**: still works across network handover, on weak networks, with only TCP relays, and on IPv6-only networks. (N1–N3)
10. **Cross-platform peers**: data sent (image / video formats, files, metadata) can be handled by desktop peers. (M2)
11. **Single instance**: the design doesn't assume several windows or several Tox instances. (L7, L7a)
12. **Mobile parity**: whether the bug being fixed also exists on iOS / Android, and it is fixed there too or the reason it doesn't apply is stated (`CLAUDE.md` Mobile parity).

## Known inconsistencies

- `MOBILE_BACKGROUND` "iOS implementation §1" still describes the `voip`
  background mode, but it was removed from `Info.plist` in `285c6f7`
  (fix(call): harden mobile incoming-call surfaces); only `audio` + `fetch`
  remain. `Info.plist` is authoritative; that document needs updating.
