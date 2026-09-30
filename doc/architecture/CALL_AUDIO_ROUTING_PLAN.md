# Call audio routing — plan for headset-aware default and auto-switching

> Status: **planned, blocked on real-device testing** (2026-09-26).
> Checklist items: A2 / A3 / A4 in
> [MOBILE_DEVICE_FEATURES](../reference/MOBILE_DEVICE_FEATURES.md).
> Reviewed by codex (analysis round: NEEDS-CHANGES; the requirements below
> incorporate its findings).

## Problem

- **A2 — default route ignores a connected headset.** When a call starts
  with no route chosen, both platforms force a built-in device:
  - iOS `applyPreferredRoute` (`ios/Runner/CallAudioChannel.swift`) maps
    "no preference" to `earpiece` (override `.none` +
    `setPreferredInput(builtInMic)`) or `speaker`
    (`overrideOutputAudioPort(.speaker)`). Pinning the built-in mic can pull
    an HFP headset off the call, since HFP input and output move together;
    the exact resulting output needs a device check.
  - Android `applyPreferredRoute` (`CallAudioChannel.kt`) calls
    `setCommunicationDevice(earpiece | speaker)`, which overrides a connected
    headset.
- **A3 / A4 — no automatic switching.** Device add / remove only emits
  `routeChanged` (Android `AudioDeviceCallback`, iOS
  `routeChangeNotification`); Dart (`call_service_manager.dart`
  `routeChanged` case) only shows a notice and re-syncs the proximity
  sensor. Nothing moves the call to a newly connected headset, and a stale
  explicit selection survives the device disappearing.

Already fixed separately (2026-09-26): Android route list now comes from
`availableCommunicationDevices` on API 31+ (no A2DP entries), BLE Audio
headsets and hearing aids are recognised, `setCommunicationDevice` failures
(false / `IllegalArgumentException`) are handled, and iOS emits route events
on the main thread.

## Design requirements

1. **Three intents, not one preference field.** Distinguish *default*
   (nothing chosen), *automatic* (the app picked a headset), and *user
   explicit* (route sheet or system call UI). Today both platforms store any
   `setRoute` into `preferredRouteId`, so an automatic decision executed
   through it would become a sticky preference. Add an explicit
   "clear / automatic" operation on the native side.
2. **Native owns facts, Dart owns intent.** Native reports the available
   routes, the *reason* for a route change (iOS
   `AVAudioSessionRouteChangeReason`: new device available / old device
   unavailable vs. override / category change; Android device add / remove
   vs. `OnCommunicationDeviceChangedListener`), and whether a route request
   succeeded. Dart keeps the product intent and decides at exactly two
   moments: **once when the call's audio session activates** (so a headset
   already connected is chosen — this is A2), and **on device add / remove**.
   Never on every `routeChanged` — otherwise a route chosen in the CallKit
   system UI (with the headset set unchanged) would be yanked back. Wire
   CallKit's audio-session activation (currently ignored in
   `callkit_bridge.dart`) into the first moment.
   **Recognising a system-UI choice:** there is no reliable platform signal —
   iOS `.override` / `.routeConfigurationChange` mean an app override and a
   port-configuration change, not "the user picked this in the CallKit UI".
   Determine on device which notifications a CallKit route pick produces.
   Until that is known, the conservative rule is: native tracks its own
   in-flight requests, and a route change that is neither a device
   add / remove nor its own request is left alone (the system-UI choice
   stands for now) and reported as the current route; whether it also
   becomes a stored *user explicit* intent is decided after the experiment.
3. **Correct route inventory first.** iOS enumerates `availableInputs` only,
   so headphones without a mic and output-only Bluetooth devices are
   invisible, and a Bluetooth output can be mis-mapped to the built-in mic's
   `input:` id. The policy must only return ids that are present and
   selectable, with a fallback on devices without an earpiece (iPad).
4. **One precedence rule.** A headset that connects during the call always
   wins and clears any user-explicit choice (this is what the system phone
   app does). At activation with several headsets already connected, wired
   beats Bluetooth (plugging in is the stronger signal). With no headset:
   the user-explicit choice if its device is present, else speaker for video
   and group calls, earpiece for voice (speaker where there is no earpiece).
   When the active headset disconnects and another is still connected, move
   to the remaining one (most recently connected first).
   The earlier draft ("wired before Bluetooth" and "newest first")
   contradicted itself when a Bluetooth headset joins while wired is
   present; the mid-call "newest wins" rule resolves that.
5. **Sequencing and failure.** Route requests go through the same per-call
   queue as activate / deactivate (`call_service_manager.dart` session
   queue) with a generation check, so nothing lands after hang-up. A refused
   request must not re-trigger in a loop ("desired == selected" is not
   enough); bound retries for devices not yet ready and for pre-API-31 SCO,
   which connects asynchronously.
   Native returns accepted / refused for every request, and a refusal leaves
   the previous route in place: today Android's `routeToEarpiece` clears the
   current communication device before trying the earpiece and sets
   `isSpeakerphoneOn` regardless of the result, so a failure can land on a
   route nobody chose. If the previous route's device is gone too, try the
   next candidate in rule 4's order once each; if every candidate is refused,
   accept the route the system chose and report it.
6. **All call types.** Group calls (`call_service_manager_busy.dart`
   `activateSession(preferSpeaker: true)`) get the same default / auto
   behaviour (speaker default, headset auto-switch) but keep the proximity
   sensor off. Sync the proximity sensor after the route settles.
7. **iOS `.defaultToSpeaker`.** Apple's documentation is inconsistent about
   how it interacts with a connected headset; decide the video-call default
   from device experiments, not from docs.

## Device test matrix (required before merge)

| Scenario | iPhone | Android 12+ | Android ≤ 11 |
|---|---|---|---|
| Voice call start, BT headset connected → headset | | | |
| Video call start, wired headset connected → headset | | | |
| Headphones without mic (wired) during a voice call | | | |
| BT headset connects mid-call → moves to it | | | |
| BT headset disconnects mid-call → earpiece (voice) / speaker (video) | | | |
| Wired plug / unplug mid-call | | | |
| User picks speaker in the route sheet, then BT connects | | | |
| Route chosen in the CallKit UI is not overridden | | n/a | n/a |
| Group call: headset auto-switch, proximity stays off | | | |
| Rapid connect / disconnect; request refused; after hang-up nothing changes | | | |

Emulators and the iOS simulator cannot present Bluetooth or wired headsets,
so this needs physical devices and headsets.
