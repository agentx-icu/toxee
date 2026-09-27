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
| ⛔ Blocked | The fix needs something this environment can't provide (e.g. a real device + headset); the plan is written |

Status reflects a static code check of `master` at 2026-09-26 (40b0cd9),
revised after a codex review. "Implemented" does not mean "verified on a
device". "fork" means `third_party/chat-uikit-flutter`.

---

## 1. Calls · audio

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| A1 | Speaker / earpiece toggle | P0 | ✅ | `lib/call/audio_devices.dart`, `lib/call/call_audio_route_sheet.dart`; native `ios/Runner/CallAudioChannel.swift`, `android/.../CallAudioChannel.kt` |
| A2 | Default route: voice → earpiece, video → speaker, headset connected → headset | P0 | ◐ ⛔ | Plan: CALL_AUDIO_ROUTING_PLAN; blocked on real devices. The initial route only chooses earpiece vs speaker (`CallAudioChannel.swift:136`, `CallAudioChannel.kt:345`); preferring an already-connected headset isn't handled explicitly |
| A3 | Bluetooth headset / car kit: switch automatically when it connects or disconnects mid-call | P0 | ❌ ⛔ | Plan: [CALL_AUDIO_ROUTING_PLAN](../architecture/CALL_AUDIO_ROUTING_PLAN.md); blocked on real devices (emulators have no headsets). Fixed first on 2026-09-26: Android 12+ route list uses `availableCommunicationDevices` (no A2DP entries), BLE Audio / hearing aids recognised, `setCommunicationDevice` failures handled; iOS emits route events on the main thread. Previously: Native code only reports device-change events (iOS `routeChangeNotification`, Android `AudioDeviceCallback` `CallAudioChannel.kt:78`); Dart (`call_service_manager.dart:1360`) only shows a hint and updates the proximity sensor, and never selects the new device. iOS system default behaviour needs a device test |
| A4 | Wired / USB-C headset plug and unplug | P0 | ❌ ⛔ | Same as A3 |
| A5 | Proximity sensor: screen off at the ear, no cheek taps | P0 | ✅ | iOS `CallAudioChannel.swift:132` (`isProximityMonitoringEnabled`); Android `CallAudioChannel.kt:233-253` (proximity wakelock). Deliberately off on the group-call page (`call_service_manager_busy.dart:303`) |
| A6 | Audio interruptions: phone call, alarm, Siri, another app taking audio focus; resume afterwards | P0 | ✅ | iOS `interruptionNotification` (`CallAudioChannel.swift:86`); Android `OnAudioFocusChangeListener` (`CallAudioChannel.kt:48`); group calls: `interrupted` state in `av_conference_session_bridge.dart` |
| A7 | Echo cancellation / noise suppression / auto gain (critical on speaker) | P0 | ◐ | Recording requests echo cancellation and noise suppression (`audio_handler.dart:70`); iOS uses `voiceChat` mode (`CallAudioChannel.swift:91`). No evidence of auto gain; actual AEC quality on speaker needs a device test |
| A8 | Microphone / camera actually released after the call (status-bar privacy indicator goes off) | P0 | 🔍 | `call_service_manager_native.dart:209`; a lingering indicator means a resource leak |
| A9 | Silent switch / Do Not Disturb / Focus vs ringtones and message sounds | P1 | ◐ 🔍 | Reviewed 2026-09-26: Android `playIncomingRingtone` (`CallAudioChannel.kt:260`) honours `ringerMode` explicitly: silent plays nothing, vibrate only vibrates, otherwise it rings on `STREAM_RING`; behaviour under Do Not Disturb unverified. iOS calls normally use CallKit; when reporting to CallKit fails, the in-app ringtone (`lib/call/ringtone_player.dart`) is the fallback and uses the default `playback` category, which **ignores the silent switch** (to do). Simply switching to `soloAmbient` is not safe: audioplayers sets the app-wide session category on iOS, racing the call's `playAndRecord` and never restoring it, which breaks voice-message playback. The right fix is a native iOS fallback ringer looping `AudioServicesPlayAlertSound` (honours the silent switch, leaves the session alone), verified on a device (the simulator has no silent switch and no CallKit). Notification sounds are governed by channels and DND |
| A10 | Volume keys adjust call volume, not media volume, during a call | P1 | ✅ 🔍 | Reviewed 2026-09-26: handled by the platform — during a call the audio mode is `MODE_IN_COMMUNICATION`, and AOSP `AudioService.getActiveStreamType` maps unsuggested volume keys to `STREAM_VOICE_CALL` (or the SCO stream) in that mode; toxee sets no `volumeControlStream`, so it takes that default path. iOS `voiceChat` sessions likewise. Not tested (an offline peer can't be called) |
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
| L2 | Android 15+ enforced edge-to-edge (targetSdk ≥ 35) | P0 | ◐ | `targetSdk = flutter.targetSdkVersion` (36). Checked 2026-09-26 on an API 36 emulator in both orientations: conversation list, chat, settings and account info are not covered by the status / navigation bars or the cutout; other pages not checked one by one |
| L3 | Phone landscape, iPad in all four orientations (declared in Info.plist, iPad includes upside-down) | P0 | ◐ | Android phone landscape tested 2026-09-26: list, chat and settings usable (keyboard: L10, rotation frame: L4a); iPad not tested. Declaring them is a commitment: chat, call, settings and login must all work. Rotation doesn't recreate the Activity (`configChanges` includes `orientation|screenSize`) |
| L4 | Crossing a responsive breakpoint at runtime: rotation / split screen switching single-pane ↔ master-detail keeps the open conversation, the draft and the call UI | P0 | ◐ | Fixed 2026-09-26 (conversation and draft): crossing 800 used to switch only UIKit's layout mode, so a chat opened in master-detail was lost on the way to single-pane, and a pushed chat route covered the whole master-detail shell on the way back. `lib/ui/home/master_detail_transition.dart` + `lib/navigation/root_route_tracker.dart` now move the one conversation actually visible (left alone when another page covers it). Verified both ways by rotating an API 36 phone emulator, draft kept. iPad and desktop window resizes take the same shared-Dart path but were not tested; the call UI across the breakpoint is unverified |
| L5 | iPad Split View / Slide Over / Stage Manager (core screens usable at any window size) | P0 | 🔍 | No `UIRequiresFullScreen` in Info.plist, so multitasking is on. That key is deprecated as of iPadOS 26 — **don't use it to opt out**; make every width usable instead. Layout is width-driven so it should work, but it's untested |
| L6 | Android split screen / freeform / pop-up windows (per OEM; core screens usable at any window size) | P0 | ◐ 🔍 | 2026-09-26 on an API 36 emulator: 320dp width and half height simulated with `wm size`, plus portrait/landscape rotation — layout fine, conversation and draft kept (see L4). True multi-window split and OEM pop-up windows not tested.  No `resizeableActivity` in the manifest (resizable by default). For apps targeting API 36 on devices with smallest width ≥ 600dp, Android 16 ignores orientation and resizability restrictions (a temporary opt-out exists on 16 only); `targetSdk = flutter.targetSdkVersion` (`build.gradle.kts:60`). Same as L5: width-driven, untested |
| L7 | Multiple windows / scenes (iPad multi-scene, Android multi-instance windows) | Won't adapt | — | toxee is a single Tox instance (see `CLAUDE.md` Singleton flow). Several windows sharing one session is possible in principle, but the benefit is small and the change large; keep `UIApplicationSupportsMultipleScenes` undeclared |
| L7a | Prevent a second launch from contending for the same profile (Android re-launching the Activity, multi-instance windows) | P1 | ✅ | Confirmed 2026-09-26: with the app in background, a `FLAG_ACTIVITY_MULTIPLE_TASK` launch created a second MainActivity and Flutter engine in the same process, which logged in again on the same native instance. Fixed: `SessionOwnerChannel.kt` + `lib/bootstrap/single_session_guard.dart` — the first activity / engine in the process claims the session (native onCreate and Dart main, before any Tox work); a later one hands its launch intent (e.g. a lock-screen call) to the owner, brings the owner's task forward and closes itself. `launchMode` stays `singleTop`: `singleTask` was tried, and relaunching from the launcher cleared an open document picker above MainActivity. The second instance's Flutter engine and plugins still start; the guard stops the Tox session start. Re-tested on API 36: after the same command one MainActivity and one login remain; with the document picker open, relaunching from the launcher keeps it. Known gap: an incoming call while the document picker covers MainActivity (the system then creates another instance) hands the call intent to the owner but only brings the task forward, so the picker still hides the call UI — reorder MainActivity to the top for call intents, once calls can be tested |
| L4a | The frame of a breakpoint-crossing rotation: the master-detail widgets lay out once at the new width (UIKit's layout mode switches post-frame) and the right pane's header and input rows overflow horizontally by 40 / 52 px, fixed the next frame | P2 | ❌ | Confirmed 2026-09-26 by log order (overflow precedes `MasterDetailTransition._apply`). A one-frame flicker plus error logs |
| L8 | Foldables: size change on fold / unfold | P1 | 🔍 | Essentially L4; `configChanges` includes `smallestScreenSize|screenLayout`, so no recreation |
| L9 | Foldable hinge avoidance, tabletop (Flex) mode | P2 | ❌ | No `DisplayFeature` handling |
| L10 | Soft keyboard: occlusion, landscape keyboard, iPad floating / split keyboard | P0 | ◐ | Fixed 2026-09-26: with the keyboard up, the right pane of a landscape phone in master-detail has ~125 dp, too little for header + composer, and overflowed by 19 px. The fork's desktopBuilder (`tencent_cloud_chat_message_layout.dart`) now drops the header when a soft keyboard leaves the pane shorter than header + composer (the conversation list stays visible beside it) and, only then, bounds the composer to the body (the desktop composer grows to any finite height, so it is bounded only in the soft-keyboard compact state). Fixed on the emulator; regression test in `mobile_composer_real_ui_test.dart` (fails without the fix). Portrait keyboard fine. iPad floating / split keyboard untested (Flutter on iOS usually reports no inset for them) |
| L11 | System font scaling / accessibility large text | P1 | ◐ | Some pages size with `textScalerOf`; overflow at the largest setting hasn't been swept |
| L12 | Dark mode follows the system | P1 | ✅ | `lib/main.dart:269-285` (`ThemeMode.system`) |
| L13 | Keep the screen on during calls | P0 | ✅ | `lib/call/call_effects_listener.dart:70,88` (`WakelockPlus`) |

## 4. Background and lifecycle

This is where a P2P client hits its hardest limits on mobile; see
[MOBILE_BACKGROUND](../architecture/MOBILE_BACKGROUND.md).

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| B1 | Keep the Tox connection alive in background | P0 | ✅ Android / ◐ iOS | Android foreground service `ToxPollingService` (always-on mode: `specialUse` on API 34+, `dataSync` below; during calls `phoneCall|microphone|camera`), restored on resume if the OS stopped it (see B8); iOS only has the `audio` + `fetch` background modes and `BGAppRefreshTask` (`BackgroundTaskController.swift`), which is best-effort |
| B2 | Receive messages and calls after the app is terminated (push wake-up) | Won't adapt | — | Needs an APNs / FCM / PushKit server, which conflicts with pure P2P (argued in MOBILE_BACKGROUND). Explain it to users at the product level. Distinguish: while the app is alive but suspended, iOS still grants occasional BG refresh, but real-time delivery can't be promised |
| B3 | Answerable incoming-call UI in background / on the lock screen | P0 | ✅ | iOS CallKit (`CallKitProvider.swift`, while the app is alive); Android full-screen notification (`notification_channels.dart:83`, `notification_service.dart:755`) |
| B3a | Android `ConnectionService`: answer from Bluetooth buttons, car integration | P2 | ❌ | Not integrated |
| B4 | Lifecycle: persist the profile on `paused` / `detached` | P0 | ✅ | `lib/ui/home_page.dart:613-617`; `inactive` fires for Control Center, incoming calls, etc. and is deliberately ignored |
| B5 | OEM background restrictions (MIUI / EMUI / ColorOS auto-start, battery-optimisation allow-list), Doze | P1 | ◐ | Settings → Background & notifications shows whether toxee is exempt from battery optimisation and offers **Allow** (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, falling back to the allow-list page); the status re-reads on resume (`NotificationAccessChannel.kt`, `lib/ui/settings/background_settings_section.dart`). Play policy: the direct request (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) is meant for chat / calling apps that cannot rely on FCM high-priority messages — toxee has no push server; re-confirm the current policy at store submission, and drop the permission (the list-page fallback needs none) if it is refused. Still open: OEM auto-start pages (MIUI / EMUI / ColorOS) — no public intent, so no generic fix |
| B6 | Cold-start recovery after Android reclaims the process (back to the conversation) | P1 | 🔍 | Auto-login exists (`_StartupGate`); restoring the page stack is unverified |
| B7 | Reduce polling and video bitrate in Low Power / battery saver mode | P2 | ❌ | |
| B8 | `dataSync` foreground-service time limit: for apps targeting API 35+, 6 h cumulative per 24 h while in background (returning to foreground resets the budget); `onTimeout` handling and fallback | P0 | ✅ 🔍 | Fixed 2026-09-26: the always-on mode uses the uncapped `specialUse` type on API 34+; API 35 `onTimeout` stops promptly; a refused `startForeground` degrades or stops; Dart `RuntimeForegroundService.ensureRunning` asks native for the real state on resume and replays the last requested mode (a call stays in call mode). Pending verification on API 36 |
| B9 | iOS data protection while the device is locked: can the profile / messages be read and written in background | P1 | 🔍 | Relies on the default protection class (`lib/util/app_paths.dart:80`) |

## 5. Network

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| N1 | Fast reconnect after Wi-Fi ↔ cellular handover / IP change (especially mid-call) | P1 | ◐ | No runtime network-change listener (no `NWPathMonitor` / `ConnectivityManager.NetworkCallback`); extra bootstrap happens on resume or disconnect (`home_page.dart:625`). toxcore recovers on its own but may take tens of seconds; measure recovery time before deciding whether to trigger it proactively |
| N2 | UDP blocked on cellular, symmetric NAT: TCP relay fallback | P0 | 🔍 | Reviewed 2026-09-26 (codex-checked): `add_bootstrap_node` calls `tox_add_tcp_relay` on the UDP port, 443 and 3389 (`tim2tox_ffi.cpp:3600-3605`), but toxcore de-duplicates relays by public key (`TCP_connection.c:1361-1364`), so the first successfully added port — the UDP port — takes effect and the other two are rejected. In the 2026-09-25 nodes.tox.chat snapshot every node that publishes TCP ports lists its UDP port among them, so those nodes get the right port; **no code change** (exception: N2a). What still needs verifying is connectivity itself: set `debug.toxee.force_tcp_only=1` on Android (`TOX_FORCE_TCP_ONLY` env on desktop / iOS) and confirm it connects on a real network. Inconclusive on 2026-09-26 (API 36 emulator on the build Mac): neither TCP-only nor the UDP control connected within 5 min, and 144.217.167.73:33445 / 3389 returned `Connection refused`. Next time, on a network where a relay is confirmed reachable: set the switch before launch, check the log for "TCP-only mode enabled", run a UDP control on the same network, and confirm the connection status is TCP |
| N2a | Wrong relay port when a node's TCP ports exclude its UDP port; the saved node stores only host/port/pubkey | P2 | ❌ | None in the live snapshot, but one in the built-in fallback list (`bootstrap_nodes.dart:294`: UDP 43334, TCP `[3389, 33445]`), whose TCP relay is effectively unusable. The fallback list is used only when fetching the node list fails. A fix needs per-node single-port selection and persisting unknown / no-TCP / port list in prefs (the saved node, applied first, claims that public key) |
| N3 | IPv6-only / NAT64 networks | P0 (if shipped on the App Store) | 🔍 | The App Store requires apps to support IPv6-only networks. Node address selection prefers IPv4 (`bootstrap_nodes.dart:36`) and the built-in list contains IPv4 literals; test bootstrap under DNS64 / NAT64 |
| N4 | iOS Local Network permission (LAN discovery, LAN pairing) | P0 | ✅ | `NSLocalNetworkUsageDescription`, Bonjour `_tox._tcp` |
| N5 | Cellular data controls (file auto-accept, video bitrate) | P2 | ❌ | |

## 6. Permissions and privacy

| # | Feature | Priority | Status | Notes / location |
|---|---|---|---|---|
| P1 | Runtime permissions: camera, microphone, photos, notifications (Android 13+); messaging and a path to Settings when denied | P0 | ◐ | `permission_handler`. Tested 2026-09-26 on API 36 with the microphone (voice message): the first denial gives no feedback; from the second, a "Permission denied / Go to Settings" dialog (fork `tencent_cloud_chat_permission_handlers.dart`). Camera / photos share that handler, not tested one by one. Notifications: see P1a |
| P1a | Notification permission denied: on Android message and incoming-call full-screen notifications stop (iOS message alerts are limited; calls use CallKit); the user is not told the consequence when denying | P1 | ◐ | Fixed first on 2026-09-26: the startup request was skipped by a wrong API-level check (Android 13 counted as API 32); a denial was cached for the session, so enabling notifications in system settings did nothing until restart — now re-read on resume. Also fixed the L3 no-prompt switch being ignored on Android. Then added `NotificationAccessMonitor` (`lib/notifications/notification_access.dart`): app switch / incoming-call channel / Android 14+ full-screen intent / message channel / other channels / iOS alerts off / iOS provisional, refreshed when the permission request settles and on every resume; a persistent Chats-tab notice (`notification_access_banner.dart`, 7 languages) explains the state and deep-links the right system settings page. Tested on API 36: it appears after a denial and disappears on return once enabled. iOS untested |
| P1b | The first permission denial is silent; the microphone returns failure even when this request was granted after a previous denial (needs a second press) | P2 | ❌ | fork `tencent_cloud_chat_permission_handlers.dart:120-168` |
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
| S2 | Option to hide message content in lock-screen notifications | P1 | ✅ | Settings → Background & notifications → "Hide message content in notifications", off by default, device-wide, every platform. Hidden message notifications show only "Toxee / New message", no avatar, and never group lines (lines grouped before the switch hold real text); turning it on withdraws message notifications already posted, including a previous process's (`notification_service_privacy.dart`); an unreadable setting hides content, a failed save reverts the switch (`lib/notifications/notification_privacy.dart`). Friend-request / invite / call notifications are not message content and keep their text |
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
| I2 | System back: Android predictive back, iOS edge swipe, vs route stack / dialogs | P0 | ◐ | `enableOnBackInvokedCallback="true"` is on. Tested 2026-09-26 on API 36: edge back gesture and back key return from a chat to the list; a popup menu only closes itself; a settings sub-page pops one level; back on a non-Chats tab switches to Chats; at the root "press back again to exit". Back from the call UI and the iOS edge swipe untested |
| I3 | iPad hardware keyboard: Enter to send, shortcuts | P1 | ◐ | The mobile composer handles hardware Enter-to-send and modifier+Enter for a newline (fork `tencent_cloud_chat_message_input_mobile.dart:794`); other shortcuts unverified |
| I4 | iPad pointer / trackpad hover, right-click menus, drag-and-drop files into chat | P2 | ❌ | |
| I5 | Screen readers (VoiceOver / TalkBack) | P1 | ◐ | Only scattered semantics labels (e.g. `home_widgets.dart:302`); whether the main chat flow is completable with a screen reader is unverified |
| I6 | System 12 / 24-hour time | P1 | ✅ | Fixed 2026-09-26: the fork's `tencent_cloud_chat_intl.dart` message time, conversation-list time and `formatDateTime` read `MediaQuery.alwaysUse24HourFormat` when a context is available and use `Hm` in 24-hour mode, the locale convention otherwise. Regression test in `test/uikit_runtime_locale_regression_test.dart`; on API 36 with 24-hour time the bubble reads 03:01 |

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

- (Resolved 2026-09-26) `MOBILE_BACKGROUND` described the `voip` background mode, removed in `285c6f7`; the document has been corrected.
