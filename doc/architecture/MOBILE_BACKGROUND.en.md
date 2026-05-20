# Mobile background, calls, and the PushKit limitation

> Generated 2026-05-20. Sibling: `doc/architecture/HYBRID_ARCHITECTURE.en.md`.

This document is the source of truth for what toxee does (and does not) do
when the app is backgrounded or terminated on Android / iOS, and what the
realistic ceiling is for a pure-P2P chat client.

## Tl;dr

| Scenario | Android | iOS |
|---|---|---|
| App foregrounded | Works | Works |
| App backgrounded, screen on | Works (foreground service keeps polling) | Works (~few min — VoIP + audio background mode + BG refresh keep socket warm) |
| App backgrounded, screen off | Works | Best-effort (iOS suspends after a brief window; BGAppRefreshTask gives sporadic CPU time) |
| App force-quit by user | Stops | Stops |
| Phone rebooted, app not launched | Stops | Stops |

**There is no path to true "terminated-app call receive" on iOS without a
server.** This is a fundamental limitation of Apple's platform model, not a
gap in toxee. See [PushKit limitation](#why-pure-terminated-app-call-receive-is-impossible-on-ios) below.

## iOS implementation

Three pieces work together to extend background lifetime:

### 1. `voip` background mode (`Info.plist` `UIBackgroundModes`)
Lets the existing Tox socket survive entering background for "as long as
the OS allows" (in practice, a few minutes; depends on memory pressure and
other apps). Important: in iOS 13+ the `voip` background mode by itself
does NOT wake a terminated app — it only extends the socket lifetime while
the app is already running.

### 2. `audio` background mode
Keeps the AVAudioSession running so a call already in progress (or the
ringtone for an inbound invite that arrived while still alive) can play
without being interrupted by backgrounding.

### 3. `BGAppRefreshTask` (`fetch` background mode)
Implemented in `ios/Runner/BackgroundTaskController.swift`. iOS may give
the app brief (~30 sec) CPU slices to pump Tox state — see
`lib/call/bg_refresh_bridge.dart` for the Dart-side handler. The schedule
is opportunistic and entirely controlled by iOS based on user-usage signals;
there is no SLA and no way to ask for "every N minutes".

### 4. CallKit (`ios/Runner/CallKitProvider.swift`)
Surfaces an iOS-native call UI on the lock screen, with proper audio routing
(speaker/bluetooth/AirPods), Apple Watch glance, and CarPlay support.

CallKit is wired through `lib/call/callkit_bridge.dart` and is called from
`CallServiceManager` on every ringing/inCall/ended transition. CallKit-side
"Answer" / "End" / "Mute" actions drive the same `acceptCall` / `hangUp` /
`toggleMute` paths the in-app UI uses, so call state stays single-sourced.

UUID mapping: CallKit requires a UUID per call session, but Tox invite IDs
are not UUIDs. The mapping (Tox invite ID ↔ CallKit UUID) lives in the
native `CallKitProvider`; Dart only ever sees the Tox invite ID. This keeps
the two namespaces decoupled.

## Android implementation

Lives in the parallel work under `android/`. Briefly:
- Manifest declares `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_PHONE_CALL` /
  `USE_FULL_SCREEN_INTENT`.
- The foreground service keeps the polling loop alive indefinitely; the OS
  will not freeze the app as long as the persistent notification is shown.
- `ConnectionService` integration would surface a system call UI but is not
  currently implemented.

## Why pure terminated-app call receive is impossible on iOS

iOS will not wake a terminated app for incoming traffic on a long-lived
socket. The only mechanism Apple provides to wake a terminated app for a
call is **PushKit** (VoIP push notifications), and PushKit requires:

1. A server-side component that holds an APNs key/cert.
2. That server to *receive* a signal from the caller (e.g. an HTTP webhook)
   indicating "this device should be woken to receive a call".
3. The server to fire a VoIP push to APNs targeting the callee's device.
4. The push to arrive within a few seconds of the call attempt.

**Tox is fully P2P. There is no server to do step 2 or 3.** A Tox call
attempt is a direct UDP packet sent via the DHT routing layer; the
recipient must be running and listening to receive it. There is no
intermediary that could fire a VoIP push.

The same reasoning rules out FCM (Firebase Cloud Messaging) for Android
terminated-app delivery: FCM also needs an APNs-style relay sender.

### Workarounds users can apply

- **Enable Background App Refresh** for toxee in iOS Settings → General →
  Background App Refresh → Toxee. Without this, even `BGAppRefreshTask`
  gets zero CPU.
- **Keep the app in the recents stack** (don't force-quit). The OS is much
  more likely to grant background CPU to recently-used apps than to ones
  swiped away.
- **Pair multiple devices** (see `doc/architecture/HYBRID_ARCHITECTURE.en.md`
  pairing flow). At least one device staying alive can relay missed-call
  metadata when the other comes back online.

### What would unlock terminated-app receive

A first-party toxee relay server. Conceptually:
- The user pairs their device with the relay (one-time setup).
- The relay holds a persistent socket to the Tox network on the user's
  behalf, plus an APNs/FCM key for the user's devices.
- On incoming call, relay sends a VoIP push to wake the device.
- Device wakes, connects to Tox, accepts the call directly P2P.

This is a non-trivial product addition (server infra, key management, privacy
model — at minimum the relay sees that *a call* arrived even if it can't see
content) and out of scope for the current direction. Documented here so the
trade-off is explicit and future agents don't re-implement the placeholder.

## Code pointers

- iOS:
  - `ios/Runner/Info.plist` — declarations
  - `ios/Runner/AppDelegate.swift` — wires both bridges
  - `ios/Runner/CallKitProvider.swift` — CallKit + audio session handoff
  - `ios/Runner/BackgroundTaskController.swift` — BGAppRefreshTask scheduling
- Dart:
  - `lib/call/callkit_bridge.dart` — Dart-side CallKit MethodChannel
  - `lib/call/bg_refresh_bridge.dart` — Dart-side BG refresh handler
  - `lib/call/call_service_manager.dart` — call state machine; calls into
    `CallKitBridge` on every ringing/inCall/ended transition
- Tests: `test/call/callkit_bridge_test.dart`
