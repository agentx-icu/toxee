[简体中文](./HYBRID_ARCHITECTURE.zh-CN.md)

# toxee Hybrid Architecture
> Language: [Chinese](HYBRID_ARCHITECTURE.md) | [English](HYBRID_ARCHITECTURE.md)

This document is the **authoritative** description of the hybrid architecture: responsibility split, recommended init order, and message/history/session/file/call paths. Overall architecture overview: [ARCHITECTURE.md](ARCHITECTURE.md); maintainer view and design constraints: [MAINTAINER_ARCHITECTURE.md](MAINTAINER_ARCHITECTURE.md).

This document describes the hybrid architecture currently used by toxee: the underlying calls are still based on the binary replacement path, and historical messages, calls, some custom callbacks and expansion capabilities are supplemented by `Tim2ToxSdkPlatform`.

## 1. Architecture Overview

toxee is not a pure binary replacement, but a **mixed mode**:

- **Binary replacement**: The dynamic library is replaced from `dart_native_imsdk` to `libtim2tox_ffi`, and most C++ callbacks are dispatched through NativeLibraryManager
- **Hybrid Platform**: `Tim2ToxSdkPlatform` is set by `SessionRuntimeCoordinator.ensureInitialized()` when `instance is! Tim2ToxSdkPlatform`; on auto-login this is called from `AppBootstrapCoordinator.boot()` before entering HomePage, on manual login from the login page calling `boot(service)` or from `HomePage._initAfterSessionReady()`; must be done by or before first screen for historical queries, some SDK calls and C++ special callbacks

**Important**: Tim2ToxSdkPlatform must be set, otherwise C++ callbacks such as clearHistoryMessage, groupQuitNotification, groupChatIdStored, etc. cannot be executed correctly.

## 2. Recommended initialization sequence

**Conceptual order** (logical dependencies):

```
1. FfiChatService.init() #Initialize Tox and local persistence
2. FfiChatService.login() #Restore selfId and connection status
3. FfiChatService.updateSelfProfile() # Synchronize nickname/signature
4. FakeUIKit.startWithFfi(service) # Establish the adaptation layer and call manager
5. TIMManager.instance.initSDK() # Set UIKit side _isInitSDK
6. FfiChatService.startPolling() # Poll native events, files and ToxAV
7. HomePage settings Tim2ToxSdkPlatform # enable the Platform path and custom callbacks
8. Initialize BinaryReplacementHistoryHook, call bridge and plug-in
```

**Actual execution sequence** (consistent with the code):

1. **main()**: Call `setNativeLibraryName('tim2tox_ffi')` via `AppBootstrap.initialize()` → `LoggingBootstrap.initialize()` (see `lib/bootstrap/logging_bootstrap.dart`); do not set Platform.
2. **_StartupGate._decide()** (auto-login path): Complete `init()`, `login()`, `updateSelfProfile()` via `AccountService.initializeServiceForAccount(..., startPolling: false)`; then `AppBootstrapCoordinator.boot(service)` runs `SessionRuntimeCoordinator.ensureInitialized()` (FakeUIKit + Platform) → `TimSdkInitializer.ensureInitialized()` → `service.startPolling()` → wait for connection/timeout → load friends → navigate to `HomePage(service)`.
3. **After login success on LoginPage** (manual login path): With an existing account, use `AccountService.initializeServiceForAccount(..., startPolling: false)`; legacy path (no toxId) is manual `init()` → `login()` → `updateSelfProfile()` (no startPolling here). Then the caller runs `AppBootstrapCoordinator.boot(service)` (SessionRuntime + TIM init + startPolling) and navigates to `HomePage(service)`.
4. **HomePage.initState()**: Via `_initAfterSessionReady()`, call `SessionRuntimeCoordinator.ensureInitialized()` (idempotent; no-op if already run in boot); if FakeUIKit not started then `startWithFfi(widget.service)`, if Platform is not `Tim2ToxSdkPlatform` set it and mount `onGroupMessageReceivedForUnread`; then after `TimSdkInitializer.ensureInitialized()` completes, initialize `BinaryReplacementHistoryHook`, UIKit group/friend listeners, and sticker / textTranslate / soundToText plug-ins.

**Note**: **Platform is set** inside `SessionRuntimeCoordinator.ensureInitialized()`; on auto-login this runs before HomePage (in boot); on manual login it runs when the login page calls `boot(service)` or, if not, on first `HomePage._initAfterSessionReady()`. `BinaryReplacementHistoryHook` is initialized in HomePage after `TimSdkInitializer.ensureInitialized()` completes; `CallServiceManager` depends on `Tim2ToxSdkPlatform` already being set to register the signaling listener.

**Division of Responsibilities**:

- **FfiChatService.init**: Responsible for Tox core initialization
- **TIMManager.initSDK**: Set the SDK layer `_isInitSDK` flag and call C++ DartInitSDK (shares the same underlying instance with FfiChatService)
- **Platform settings**: must be done in HomePage or earlier, for use by getHistoryMessageList, clearHistoryMessage, etc.

## 3. Functional process

### 3.1 Message sending

| Path | Description |
|------|------|
| **Main Path** | FakeChatMessageProvider → FakeMessageManager.sendText/sendFile → FfiChatService |
| **Alternate path** | If the code goes to V2TimMessageManager.sendMessage and Platform has been set → Tim2ToxSdkPlatform → FfiChatService |

Currently UIKit message input goes through the ChatMessageProvider, so all is actually sent via the FfiChatService.

### 3.2 Message history

| Path | Description |
|------|------|
| **Provider layer** | FakeChatMessageProvider._loadHistoryForConversation → FakeMessageManager.getHistory → FfiChatService.getHistory |
| **SDK layer** | tencent_cloud_chat_common and so on call getHistoryMessageListV2 → if Platform=Tim2ToxSdkPlatform → FfiChatService.getHistory |

Both paths end up at FfiChatService/MessageHistoryPersistence.

### 3.3 Conversations and Friends

All pass through the FakeUIKit adaptation layer and use FfiChatService (getFriendList, getFriendApplications, knownGroups) directly without going through Platform or NativeLibraryManager.

### 3.4 File transfer

- **Send**: FakeMessageManager.sendFile → FfiChatService.sendFile
- **Receive**: C++ OnFileRecv → file_request enqueue → FfiChatService.startPolling consumption → acceptFile
- **Progress**: FfiChatService.progressUpdates stream → FakeChatMessageProvider

`startPolling()` must be explicitly called by the startup process after service login, otherwise `file_request`, connection status and ToxAV events cannot be consumed.

### 3.5 Call and expansion capabilities

- **Call**: `FakeUIKit.startWithFfi()` creates `CallServiceManager`; `HomePage.initState()` calls its `initialize()` after the Platform is set up, and then strings together `ToxAVService`, `CallBridgeService` and `TUICallKitAdapter`
- **Sticker plug-in**: `HomePage.initState()` attempts to register synchronously before the message component is registered; if `selfId` is not ready yet, it will be registered after the connection is successful.
- **Text Translation/Speech to Text**: Lazy registration on demand in HomePage
- **LAN Bootstrap / IRC**: The entrance is on the client side, managed by `LanBootstrapServiceManager` and `IrcAppManager` respectively. For specific implementation, see the extended document

## 4. Callback process and division of labor

### 4.1 C++ callback path

```
C++ (dart_compat_layer / callback_bridge)
  → Dart_PostCObject
  → NativeLibraryManager._handleGlobalCallback
  → Route by instance_id:
     - instance_id != 0 → Platform.dispatchInstanceGlobalCallback (multiple instances)
     - instance_id == 0 → _sdkListener、_advancedMsgListener、_friendshipListener、_groupListener
```

### 4.2 Division of labor between C++ callbacks and FfiChatService streams

| Source | Purpose | Description |
|------|------|------|
| **C++ ReceiveNewMessage** | _advancedMsgListener dispatched to TIMMessageManager via NativeLibraryManager | The main entry for new messages under binary replacement; BinaryReplacementHistoryHook wraps the listener for persistence |
| **FfiChatService.messages** | stream generated by _onNativeEvent inside FfiChatService | Old-style events (type 0/1/10/11, etc.) from FfiChatService, which may overlap with the C++ layer |
| **FfiChatService.connectionStatusStream** | Connection status | Independent of C++ callbacks |

**Note**: In binary replacement mode, new messages are mainly dispatched by the C++ ReceiveNewMessage callback through NativeLibraryManager. FfiChatService._onNativeEvent mainly handles the old event protocol maintained by itself. The division of labor between the two is different to avoid duplication of processing.

### 4.3 Dependence of special callbacks on Platform

The following callbacks in NativeLibraryManager rely on Platform to be Tim2ToxSdkPlatform, otherwise ffiService cannot be accessed:

- `clearHistoryMessage`: Clear history
- `groupQuitNotification`: Group exit notification
- `groupChatIdStored`: group chat_id persistence

These callbacks are handled by **NativeLibraryManager._handleGlobalCallback** dispatched to **Tim2ToxSdkPlatform._handleCustomCallback** via **dispatchInstanceGlobalCallback** when **platform != null && platform.isCustomPlatform** is detected. If Platform is not set or the type does not match, these callbacks will fail silently.

## 5. Data flow overview

```
┌─────────────────────────────────────────────────────────────────┐
│ Message sending │
│  Message Input → FakeChatMessageProvider → FfiChatService        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ History loading │
│  FakeMessageManager.getHistory ──────┐                          │
│  V2TimMessageManager.getHistoryMessageListV2 ──→ Platform ──┐   │
│ (When the SDK layer isCustomPlatform==true, go to Platform) ↓ │
│                                         FfiChatService.getHistory│
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Callback │
│  C++ → NativeLibraryManager → TIMMessageManager listeners       │
│                            → BinaryReplacementHistoryHook        │
│ C++ special callback → Platform.ffiService (requires Platform=Tim2ToxSdkPlatform) │
└─────────────────────────────────────────────────────────────────┘
```

## 6. Differences from pure binary replacement

| Project | Pure Binary Replacement (Documentation Description) | Current Mixing Scheme |
|------|--------------------------|--------------|
| Platform settings | Do not set | **Required** Tim2ToxSdkPlatform |
| History query | C++ DartGetC2CHistoryMessageList | Platform → FfiChatService.getHistory |
| Special callback | Unable to execute | Depends on Platform.ffiService |
| Main path for sending messages | NativeLibraryManager.DartSendMessage | FakeChatMessageProvider → FfiChatService |

## 7. Related documents

- [ARCHITECTURE.md](ARCHITECTURE.md): Overall architecture
- [IMPLEMENTATION_DETAILS.md](MAINTAINER_ARCHITECTURE.md): Implementation details
- [CALLING_AND_EXTENSIONS.md](../reference/CALLING_AND_EXTENSIONS.md): Calling, plugins, LAN Bootstrap and IRC extensions
- [../../third_party/tim2tox/doc/architecture/BINARY_REPLACEMENT.md](../../third_party/tim2tox/doc/architecture/BINARY_REPLACEMENT.md): Binary replacement mechanism
