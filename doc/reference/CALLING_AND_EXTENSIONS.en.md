# toxee Calling and Extensions
> Language: [Chinese](CALLING_AND_EXTENSIONS.md) | [English](CALLING_AND_EXTENSIONS.en.md)


This document describes the extension capabilities that have been implemented in toxee but are not part of the basic chat link: audio and video calls, UIKit plugins, LAN Bootstrap and IRC integration.

## 1. Call structure

The current client call implementation relies on three levels:

- `FakeUIKit.startWithFfi()` creates `CallStateNotifier` and `CallServiceManager`
- `HomePage.initState()` calls `callServiceManager.initialize()` after `Tim2ToxSdkPlatform` is set up
- `CallServiceManager.initialize()` initializes `ToxAVService`, `CallBridgeService`, `TUICallKitAdapter` in sequence, and registers to TUICore through `registerToxAVWithTUICore()`

This means that the calling system dependency `Tim2ToxSdkPlatform` is in place; otherwise the signaling listener cannot be mounted correctly.

## 2. Two call paths

### 2.1 Signaling path

This is the main path for UIKit triggers:

1. The user clicks the audio and video call button in UIKit
2. TUICore transfers the call to `TUICallKitAdapter`
3. `TUICallKitAdapter` creates signaling invite through `Tim2ToxSdkPlatform.invite()`
4. If the friend `friendNumber` can be parsed, call `ToxAVService.startCall()` synchronously.
5. `CallBridgeService` is responsible for handling signaling events such as acceptance, rejection, cancellation, timeout, etc.
6. `CallStateNotifier` drives call UI and suspension layer

### 2.2 Native ToxAV path

This is a path reserved for compatibility with external ToxAV calls such as qTox:

1. `ToxAVService` directly receives native callback
2. `CallServiceManager` maps it to inviteID in the form of `native_av_<friendNumber>`
3. The UI still enters the unified incoming call/conversation state machine through `CallStateNotifier`

Therefore, the client supports both the UIKit signaling path and the pure ToxAV direct path.

## 3. Write call records

When the call ends, `CallServiceManager` will call back `FakeUIKit.onCallRecordNeeded`. Then `FakeUIKit` will:

- Construct call records with custom message format
- Write `FfiChatService` history to ensure that historical message queries are visible
- Emit real-time events via event bus
- Inject UIKit `messageData` to ensure that the currently opened session is refreshed immediately

This ensures that "history traceability" and "current session real-time refresh" are established at the same time.

## 4. UIKit plug-in access

### 4.1 Sticker

- Registered in `HomePage.initState()` prior to message component
- If `selfId` is not ready yet, it will be re-registered after the connection is successful.
- This can prevent message input from not getting `StickerPluginInstance` during initialization

### 4.2 textTranslate / soundToText

- Lazy registration on demand in HomePage
- The registration status is controlled by `_textTranslatePluginRegistered` and `_soundToTextPluginRegistered` to avoid repeated access

## 5. LAN Bootstrap

`LanBootstrapServiceManager` is responsible for the local Bootstrap service on the desktop:

- Automatically detect the available LAN IP of this machine
- Create an independent test instance as a Bootstrap service node
- Expose local IP, UDP port and DHT public key to UI
- Allow clients to quickly interconnect within the LAN

This part is not a necessary ability for basic chat, but it is important for desktop LAN debugging and demonstration.

## 6. IRC integration

`IrcAppManager` is responsible for the IRC extension:

- Dynamically load `libirc_client.dylib`
- Create/restore corresponding Tox group for IRC channel
- Maintain `channel -> groupId` mapping
- Call `FfiChatService.connectIrcChannel()` / `disconnectIrcChannel()` / `unloadIrcLibrary()`

The client UI is only responsible for installation status, channel entry and interaction. The real IRC network sending and receiving is still implemented in the tim2tox side dynamic library.

## 7. ToxAV build matrix & runtime availability

Calling only works when `libtim2tox_ffi` is compiled with `BUILD_TOXAV`
(opus + libvpx). Since 2026-07, **ToxAV is ON by default and fail-loud** in
every build path — historically it was opt-in (`--toxav`) and every shipped
artifact silently contained a no-op calling stub.

| Build path | ToxAV | Codec source |
|---|---|---|
| `run_toxee.sh` / `build_ffi.sh` (macOS dev) | ON | Homebrew opus/libvpx, bundled via `bundle_dylib` |
| `tool/ci/build_tim2tox.sh` (all five targets, incl. `build-packages.yml` releases) | ON by default; `--no-toxav` opts out | linux: apt `libopus-dev libvpx-dev`; macos: brew; windows: vcpkg `opus`/`libvpx`; android/ios: pinned-source cross-compile via `tool/ci/build_av_deps.sh` |
| `tool/build_android_ffi.sh`, `tool/build_ios_sim_ffi.sh` (dev loops) | ON by default (`TOXAV=0` opts out) | `tool/ci/build_av_deps.sh` |

Guard rails:

- Runtime probe `tim2tox_ffi_av_is_available()` → `CallAvBackend.isAvailable`
  → `CallServiceManager.isCallingAvailable`. The UI only surfaces call
  buttons when the loaded library has a real backend (`setUseCallKit`), so a
  stub or pre-probe library hides calling instead of silently failing.
- Marker symbol `tim2tox_ffi_av_backend_toxav` is exported only by real
  builds; `tool/ci/package_artifacts.sh` refuses to package artifacts
  without it (escape hatch: `TOXEE_ALLOW_STUB_AV=1`, never for releases).
- Video-call entry points additionally gate on
  `CallMediaCapabilities.supportsVideoCapture()` (`useVideoCall` in the
  UIKit fork): Windows/Linux have no camera capture backend, so they are
  voice-only until one is implemented.

## 8. Related documents

- [HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.en.md)
- [IMPLEMENTATION_DETAILS.md](IMPLEMENTATION_DETAILS.en.md)
- [../../third_party/tim2tox/doc/integration/TOXAV_AND_SIGNALING.en.md](../../third_party/tim2tox/doc/integration/TOXAV_AND_SIGNALING.en.md)
