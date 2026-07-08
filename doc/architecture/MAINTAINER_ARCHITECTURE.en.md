# toxee maintainer view: hybrid architecture design

> Language: [Chinese](MAINTAINER_ARCHITECTURE.md) | [English](MAINTAINER_ARCHITECTURE.en.md)

This document is for **maintainers**: it explains why the hybrid architecture exists, responsibility split, call chains, and modification boundaries. For using the app and quick start, see [Main README](../../README.md) and [doc/README](../README.en.md). It sits alongside [ARCHITECTURE.md](ARCHITECTURE.en.md) (overview) and [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.en.md) (authoritative hybrid description). **Init order and hybrid responsibilities are authoritative in this doc or HYBRID_ARCHITECTURE.**

## Contents

- [1. Architecture goals](#1-architecture-goals)
- [2. Design constraints](#2-design-constraints)
- [3. Layering](#3-layering)
- [4. Core module responsibilities](#4-core-module-responsibilities)
- [5. Initialization order](#5-initialization-order)
- [6. Message send path](#6-message-send-path)
- [7. History and special callbacks](#7-history-message-and-special-callback-paths)
- [8. File transfer and event polling](#8-file-transfer-and-event-polling)
- [9. Persistence and state restore](#9-persistence-and-state-restore)
- [10. Extension plugins and call bridge](#10-extension-plugins-and-call-bridge)
- [11. Why this is the current best fit](#11-why-this-is-the-current-best-fit)
- [12. Future evolution](#12-future-evolution)
- [Easy-to-break spots](#easy-to-break-spots)
- [Recommended source reading order](#recommended-source-reading-order)

---

## 1. Architecture goals

| Goal | Description |
|------|-------------|
| **Preserve UIKit call style** | App and UIKit still use `TIMManager.instance`, Managers, Listeners; Tim2Tox implements the bottom; no UI or call-site rewrite. |
| **History and extensions in Dart** | Message history is persisted in Dart (C++ has no DB); special callbacks (clearHistoryMessage, groupQuitNotification, groupChatIdStored) that need FfiChatService must go through Platform. |
| **Minimize SDK coupling** | Prefer “swap library, keep API” (NativeLibraryManager → Dart*); only “must be Dart or need ffiService” goes through Platform. |
| **Single-session lifecycle** | On account switch/logout, FakeUIKit, Platform, FfiChatService, polling, Provider registration must be torn down together to avoid cross-account state. |

---

## 2. Design constraints

| Constraint | Description |
|------------|-------------|
| **Compatibility** | SDK’s `NativeLibraryManager` resolves `Dart*` via FFI; after `setNativeLibraryName('tim2tox_ffi')`, all TIMManager calls go to tim2tox dart_compat_*. You **cannot** set Platform in main and expect “everything via Platform”—SDK still uses Native path first; only when isCustomPlatform do some APIs route to Platform. |
| **Compatibility** | C++ callback format (globalCallback/apiCallback JSON) must match NativeLibraryManager._handleNativeMessage. Special callbacks (e.g. clearHistoryMessage) are dispatched only when platform != null && isCustomPlatform to Platform.dispatchInstanceGlobalCallback; **Platform must be set by first screen (HomePage) or earlier**, or those callbacks fail silently. |
| **Trade-off** | Platform is set by **SessionRuntimeCoordinator.ensureInitialized()**; that is called on auto-login from AppBootstrapCoordinator.boot() (before entering HomePage), on manual login from the login page calling boot(service) or from HomePage._initAfterSessionReady(). Not set in main(): FfiChatService is created in _StartupGate or login; the **same instance** must be given to FakeUIKit and Tim2ToxSdkPlatform. |
| **Trade-off** | startPolling() is called in **AppBootstrapCoordinator.boot()** (after init/login and FakeUIKit/Platform are ready) so the C++ event queue is consumed by the registered FfiChatService; if startPolling runs before Platform/FakeUIKit, file_request etc. can be lost or not tied to UI. |

---

## 3. Layering

### 3.1 Layer diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  UI (lib/ui/)                                                                │
│  HomePage, LoginPage, conversation/settings/Bootstrap; UIKit + minimal custom│
└─────────────────────────────────────┬───────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│  Provider / data registration                                                │
│  ChatDataProviderRegistry.provider = FakeChatDataProvider                     │
│  ChatMessageProviderRegistry.provider = FakeChatMessageProvider               │
│  UIKit uses provider for getHistory, sendText, loadConversation               │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│  Adapter layer (lib/sdk_fake/)                                                │
│  FakeUIKit, FakeMessageManager, FakeConversationManager, FakeChatMessageProvider│
│  Maps FfiChatService/EventBus to Fake* and V2Tim for UIKit                   │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│  Session runtime (lib/runtime/) + Tim2Tox Dart                               │
│  SessionRuntimeCoordinator: FakeUIKit.startWithFfi + Platform + CallServiceManager│
│  FfiChatService: init/login/startPolling/getHistory/send*/messages/connectionStatusStream│
│  Tim2ToxSdkPlatform: TencentCloudChatSdkPlatform impl, delegates to ffiService│
└──────────────────────────────────────┬───────────────────────────────────────┘
        ┌─────────────────────────────┴─────────────────────────────┐
        │  SDK entry (one or both)                                    │
        │  A: TIMManager → NativeLibraryManager → Dart* → libtim2tox_ffi│
        │  B: getHistoryMessageListV2 etc → Platform → Tim2ToxSdkPlatform → FfiChatService│
        └─────────────────────────────┬─────────────────────────────┘
┌──────────────────────────────────────┴──────────────────────────────────────┐
│  Tim2Tox C++ (third_party/tim2tox): V2TIM*Manager, ToxManager, c-toxcore    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Dual paths and ownership

| Capability | NativeLibraryManager (binary replacement) | Tim2ToxSdkPlatform / FfiChatService |
|------------|--------------------------------------------|-------------------------------------|
| initSDK / Login | ✅ TIMManager.initSDK → DartInitSDK; FfiChatService.init/login call tim2tox_ffi_*, same C++ instance | FfiChatService does tim2tox_ffi_init/login; SDK initSDK still Native |
| New message callback | ✅ C++ OnRecvNewMessage → SendCallbackToDart → NativeLibraryManager._handleGlobalCallback → _advancedMsgListener | FfiChatService.messages from poll (c2c/gtext); split with C++ to avoid duplicate |
| History | ❌ C++ has no persisted history; DartGetC2CHistoryMessageList etc. empty/unimpl | ✅ getHistoryMessageListV2 → Platform → FfiChatService.getHistory → MessageHistoryPersistence |
| clearHistoryMessage | ❌ Needs ffiService; Native path cannot do it | ✅ Dispatched by NativeLibraryManager to Platform._handleCustomCallback → ffiService |
| groupQuitNotification / groupChatIdStored | ❌ Same | ✅ Same |
| Message send (current) | Could use DartSendMessage; toxee input uses ChatMessageProvider | ✅ FakeChatMessageProvider → FakeMessageManager.sendText/sendFile → FfiChatService |
| Friends/conversation list | Could use DartGetFriendList | ✅ FakeUIKit reads FfiChatService.getFriendList, knownGroups; no Platform |
| Connection status | C++ can callback | ✅ FfiChatService.connectionStatusStream from poll conn:success/failed |
| File transfer | C++ callback file_request; receiver must accept in Dart | ✅ startPolling consumes file_request; FfiChatService.acceptFileTransfer; progressUpdates → FakeChatMessageProvider |
| Call / signaling | Partly Native listener | ✅ CallServiceManager, ToxAVService, CallBridgeService init after Platform set; depend on ffiService |

---

## 4. Core module responsibilities

### 4.1 LoggingBootstrap

| Item | Content |
|------|---------|
| **Location** | `lib/bootstrap/logging_bootstrap.dart` |
| **Role** | Set AppLogger path and C++ log file (Tim2ToxFfi.setLogFile), **setNativeLibraryName('tim2tox_ffi')** as early as possible in main so all later SDK/FFI uses load tim2tox. |
| **Callers** | `AppBootstrap.initialize()` (from main). |
| **Dependencies** | AppLogger, Tim2ToxFfi.open(), tencent_cloud_chat_sdk NativeLibraryManager (setNativeLibraryName affects DynamicLibrary.open). |
| **Typical issues** | Not run first or wrong lib name → wrong SDK loaded or symbol not found. |
| **Change risk** | High. Changing lib name or removing setNativeLibraryName breaks binary replacement; reordering can leave Logger/FFI not ready. |

### 4.2 FfiChatService

| Item | Content |
|------|---------|
| **Location** | `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart` |
| **Role** | Tox lifecycle (init/login), polling (startPolling), send (sendText/sendGroupText/sendFile), history (getHistory ↔ MessageHistoryPersistence), Streams (messages, connectionStatusStream, progressUpdates, fileRequests), multi-instance registration. |
| **Callers** | toxee: AccountService.initializeServiceForAccount, SessionRuntimeCoordinator, FakeUIKit (FakeMessageManager etc.), Tim2ToxSdkPlatform, BinaryReplacementHistoryHook. |
| **Dependencies** | Tim2ToxFfi (tim2tox_ffi_*), ExtendedPreferencesService, LoggerService, BootstrapService, MessageHistoryPersistence, OfflineMessageQueuePersistence. |
| **Typical issues** | Not calling startPolling → file_request/conn not consumed; wrong profile/historyDirectory for multi-account. |
| **Change risk** | High. Interface is contract between Tim2Tox and toxee; adding/removing Streams or methods affects Fake* and Platform. |

### 4.3 Tim2ToxSdkPlatform

| Item | Content |
|------|---------|
| **Location** | `third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart` |
| **Role** | Implements TencentCloudChatSdkPlatform: getHistoryMessageListV2, clearHistoryMessage, deleteConversation etc. route to ffiService; customCallbackHandler for clearHistoryMessage, groupQuitNotification, groupChatIdStored from C++. |
| **Callers** | SDK (when isCustomPlatform == true); NativeLibraryManager._handleGlobalCallback dispatches to platform.dispatchInstanceGlobalCallback when custom handling needed. |
| **Dependencies** | FfiChatService, EventBusProvider, ConversationManagerProvider (optional). |
| **Typical issues** | Platform not set or set after first screen → getHistoryMessageList empty or special callbacks lost. |
| **Change risk** | Medium–high. SDK upgrades may change Platform method signatures; customCallbackHandler keys must match C++; wrong key → callback not run. |

### 4.4 FakeUIKit

| Item | Content |
|------|---------|
| **Location** | `lib/sdk_fake/fake_uikit_core.dart` |
| **Role** | startWithFfi(service) creates FakeIM, FakeConversationManager, FakeMessageManager, FakeContactManager, FakeChatMessageProvider, CallServiceManager, wires EventBus; exposes FfiChatService to Fake* and Providers. |
| **Callers** | SessionRuntimeCoordinator.ensureInitialized(), HomePage._initAfterSessionReady (if coordinator not run first). |
| **Dependencies** | FfiChatService, FakeEventBus, CallStateNotifier. |
| **Typical issues** | startWithFfi on service before login/init; use after dispose → null. |
| **Change risk** | High. FakeUIKit is singleton; after dispose must align with AccountService.teardown; new Fake* or Provider must be registered in UIKit Registry. |

### 4.5 SessionRuntimeCoordinator

| Item | Content |
|------|---------|
| **Location** | `lib/runtime/session_runtime_coordinator.dart` |
| **Role** | ensureInitialized(): if FakeUIKit not started then startWithFfi(service); if Platform is not Tim2ToxSdkPlatform then create/set it and onGroupMessageReceivedForUnread; then CallServiceManager.initialize(). disposeRuntime(): FakeUIKit.dispose, restore Platform to MethodChannel. |
| **Callers** | AppBootstrapCoordinator.boot(), HomePage._initAfterSessionReady(), AccountService.teardownCurrentSession() (calls disposeRuntime). |
| **Dependencies** | FfiChatService, FakeUIKit, Tim2ToxSdkPlatform, EventBusAdapter, ConversationManagerAdapter. |
| **Typical issues** | Concurrent ensureInitialized serialized by _initializing; after dispose, ensure again rebuilds—must use new session service. |
| **Change risk** | Medium. Order changes affect when Platform vs FakeUIKit is ready; CallServiceManager must initialize after Platform set. |

### 4.6 HomePage (initState / _initAfterSessionReady)

| Item | Content |
|------|---------|
| **Location** | `lib/ui/home_page.dart`, `lib/ui/home_page_bootstrap.dart` (part) |
| **Role** | initState calls unawaited(_initAfterSessionReady()): SessionRuntimeCoordinator.ensureInitialized(), TimSdkInitializer.ensureInitialized(), then _initBinaryReplacementPersistenceHook(), group/friend listeners, ChatDataProviderRegistry/ChatMessageProviderRegistry, sticker/translate/voice plugins, connectionStatus listeners. |
| **Callers** | Navigation from startup gate or login to HomePage(service); Flutter calls initState. |
| **Dependencies** | FfiChatService (widget.service), SessionRuntimeCoordinator, TimSdkInitializer, BinaryReplacementHistoryHook, FakeUIKit, TencentCloudChat registrations. |
| **Typical issues** | Reordering _initTIMManagerSDK and _initBinaryReplacementPersistenceHook can make Hook attach before TIMManager init; plugins may fail when selfId empty and need re-register on connect. |
| **Change risk** | High. HomePage is the post-session init hub; order must match [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.en.md); changes need doc and regression tests. |

### 4.7 FakeChatMessageProvider / FakeMessageManager

| Item | Content |
|------|---------|
| **Location** | `lib/sdk_fake/fake_msg_provider.dart`, `lib/sdk_fake/fake_managers.dart` |
| **Role** | Provider: implements ChatMessageProvider for UIKit (getHistory, sendText/sendFile, progress and message stream). Manager: getHistory(conversationID) → ffi.getHistory(id); sendText/sendFile → ffi.sendText/sendFile, emit FakeMessage or use last history for local echo. |
| **Callers** | UIKit message UI via ChatMessageProviderRegistry.provider; FakeUIKit.messageProvider. |
| **Dependencies** | FfiChatService (getHistory, sendText, sendGroupText, sendFile, progressUpdates, messages). |
| **Typical issues** | conversationID vs FfiChatService id (c2c_/group_ prefix); duplicate local echo and ffi.messages. |
| **Change risk** | Medium–high. getHistory/sendText used in many places; ID normalization must match FfiChatService.getHistory and MessageHistoryPersistence. |

### 4.8 BinaryReplacementHistoryHook

| Item | Content |
|------|---------|
| **Location** | `third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart` |
| **Role** | Wraps V2TimAdvancedMsgListener: OnRecvNewMessage writes to FfiChatService/MessageHistoryPersistence so “binary-replace-only” still has history; shares same persistence with Platform path to avoid double write. |
| **Callers** | HomePage._initBinaryReplacementPersistenceHook() after TIMManager init. |
| **Dependencies** | FfiChatService (same instance), MessageHistoryPersistence. |
| **Typical issues** | Not installed → C++ new messages not persisted; late install → first message lost. |
| **Change risk** | Medium. Hook and Platform getHistory must read same persistence; changes must work for both binary-replace and hybrid. |

### 4.9 AppBootstrapCoordinator / TimSdkInitializer

| Item | Content |
|------|---------|
| **Location** | `lib/util/app_bootstrap_coordinator.dart`, `lib/runtime/tim_sdk_initializer.dart` |
| **Role** | boot(service): SessionRuntimeCoordinator.ensureInitialized() → TimSdkInitializer.ensureInitialized() → service.startPolling(). TimSdkInitializer: TIMManager.instance.initSDK(...) once. |
| **Callers** | StartupSessionUseCase.execute (auto-login), LoginUseCase (after login); HomePage _initAfterSessionReady also uses SessionRuntimeCoordinator and TimSdkInitializer. |
| **Dependencies** | FfiChatService, SessionRuntimeCoordinator, TIMManager. |
| **Typical issues** | startPolling after HomePage open → no connection status for a while; initSDK must be idempotent. |
| **Change risk** | Medium. boot order is fixed: FakeUIKit+Platform → TIM init → startPolling; changes affect connection and event consumption. |

---

## 5. Initialization order

### 5.1 Sequence (matches code)

```
main()
  ├─ WidgetsFlutterBinding.ensureInitialized()
  ├─ AppBootstrap.initialize()
  │    ├─ LoggingBootstrap.initialize()   // log path, setNativeLibraryName('tim2tox_ffi'), FFI setLogFile
  │    ├─ PrefsBootstrap.initialize()
  │    ├─ AppRuntimeBootstrap.initialize()
  │    └─ DesktopShellBootstrap.initializeIfNeeded()
  └─ _StartupGate or login

_StartupGate._decide() (auto-login)
  ├─ Prefs: nickname / autoLogin
  ├─ BootstrapNodesService / Prefs if needed
  ├─ AccountService.initializeServiceForAccount(toxId, ..., startPolling: false)
  │    ├─ FfiChatService( prefs, logger, bootstrap, historyDirectory, ... )
  │    ├─ service.init(profileDirectory)
  │    ├─ service.login(...)
  │    ├─ service.updateSelfProfile(...)
  │    └─ no startPolling here
  ├─ AppBootstrapCoordinator.boot(service)
  │    ├─ SessionRuntimeCoordinator(service).ensureInitialized()
  │    │    ├─ FakeUIKit.instance.startWithFfi(service)
  │    │    ├─ TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(ffiService: service, ...)
  │    │    └─ FakeUIKit.instance.callServiceManager?.initialize()
  │    ├─ TimSdkInitializer.ensureInitialized()
  │    └─ service.startPolling()
  ├─ Wait connectionStatusStream or timeout
  ├─ loadFriends(service)
  └─ Navigate to HomePage(service)

HomePage.initState()
  └─ unawaited(_initAfterSessionReady())
       ├─ SessionRuntimeCoordinator(service).ensureInitialized()  // idempotent
       ├─ TimSdkInitializer.ensureInitialized().then((_) {
       │    ├─ _initBinaryReplacementPersistenceHook()
       │    ├─ initGroupListener / initFriendListener
       │  })
       ├─ ChatDataProviderRegistry.provider = FakeChatDataProvider(...)
       ├─ ChatMessageProviderRegistry.provider = FakeChatMessageProvider()
       ├─ basic.addUsedComponent(Conversation/Message/Contact/Search...)
       └─ connectionStatusStream.listen(...), plugins, EventBus...
```

### 5.2 Why order matters

| Constraint | Reason |
|------------|--------|
| setNativeLibraryName before any SDK/FFI use | NativeLibraryManager opens library on first use; TIMManager.initSDK etc. then resolve Dart* from libtim2tox_ffi. |
| FfiChatService.init/login before startWithFfi and Platform | FakeUIKit and Tim2ToxSdkPlatform share the same FfiChatService; it must be init/login’d before getHistory, sendText, startPolling. |
| Platform set before getHistoryMessageList / clearHistoryMessage | SDK routes by isCustomPlatform; first screen or conversation switch pulls history; if Platform is not Tim2ToxSdkPlatform, history is empty or clear no-op. |
| startPolling after SessionRuntimeCoordinator.ensureInitialized | Poll consumes file_request, conn etc.; FfiChatService and FakeUIKit must be ready; poll before Platform → events not tied to UI. |
| _initBinaryReplacementPersistenceHook after TimSdkInitializer.ensureInitialized | Hook registers listener on messageManager; TIMManager must be init’d or listener not attached, C++ messages not persisted. |
| CallServiceManager.initialize after Platform set | Call bridge registers signaling etc. on Platform; needs Tim2ToxSdkPlatform. |

---

## 6. Message send path

- **Main path (toxee)**: UIKit input → ChatMessageProvider.sendText/sendFile → **FakeChatMessageProvider** → **FakeMessageManager.sendText/sendFile** → **FfiChatService.sendText/sendGroupText/sendFile** → tim2tox_ffi_send_c2c_text / send_group_text / send_file → V2TIMMessageManagerImpl → ToxManager → c-toxcore.
- **Fallback**: If code calls V2TimMessageManager.sendMessage and Platform is set, SDK may route to Tim2ToxSdkPlatform.sendMessage → FfiChatService. Current UI uses Provider, so main path is Fake* → FfiChatService.

---

## 7. History message and special callback paths

### 7.1 History

- **Provider**: FakeChatMessageProvider._loadHistoryForConversation → FakeMessageManager.getHistory(conversationID) → **FfiChatService.getHistory(id)** → MessageHistoryPersistence.getHistory(normalizedId).
- **SDK**: getHistoryMessageListV2; when isCustomPlatform and Platform is Tim2ToxSdkPlatform → **Tim2ToxSdkPlatform.getHistoryMessageListV2** → **FfiChatService.getHistory** → same MessageHistoryPersistence.

### 7.2 Special callbacks (clearHistoryMessage, groupQuitNotification, groupChatIdStored)

- C++ → SendCallbackToDart → NativeLibraryManager; _handleGlobalCallback when platform != null && platform.isCustomPlatform → **dispatchInstanceGlobalCallback** → **Tim2ToxSdkPlatform._handleCustomCallback** → ffiService.clearHistoryMessage, group quit, chat_id persist.
- If Platform not set or not Tim2ToxSdkPlatform, these callbacks **fail silently**.

---

## 8. File transfer and event polling

- **Send**: FakeMessageManager.sendFile → FfiChatService.sendFile / sendGroupFile.
- **Receive**: C++ OnFileRecv enqueues file_request → **FfiChatService.startPolling()** parses file_request: → acceptFileTransfer or fileRequests stream; FakeChatMessageProvider listens fileRequests and progressUpdates.
- **Polling**: startPolling() runs timer, tim2tox_ffi_poll_text; parses conn:success/failed, c2c:, gtext:, file_request:, file_done:; updates connectionStatusStream, messages, file state. Without startPolling, file_request and connection status do not update.

---

## 9. Persistence and state restore

- **History**: MessageHistoryPersistence (Tim2Tox) stores by conversation id; FfiChatService.getHistory reads; BinaryReplacementHistoryHook and _appendHistory write; directory from FfiChatService historyDirectory (toxee uses AccountService per-account path).
- **Account/session**: Prefs current_account_tox_id, nickname, bootstrap; AccountService.initializeServiceForAccount sets profile and history dirs; teardownCurrentSession → SessionRuntimeCoordinator.disposeRuntime, clear Providers, FfiChatService.dispose, re-encrypt profile if needed.
- **Bootstrap**: BootstrapNodesAdapter reads Prefs; FfiChatService.init ends with _loadAndApplySavedBootstrapNode() → tim2tox_ffi_add_bootstrap_node.

---

## 10. Extension plugins and call bridge

- **Calls**: FakeUIKit.startWithFfi creates CallServiceManager(service, callStateNotifier); SessionRuntimeCoordinator.ensureInitialized() ends with CallServiceManager.initialize() (after Platform set); ToxAVService, CallBridgeService, TUICallKitAdapter attached there.
- **Sticker/translate/voice**: HomePage._initAfterSessionReady registers Message component and _tryRegisterStickerPluginSync / _ensureStickerPluginRegistered; if selfId not ready, register on first connectionStatusStream connected.
- **LAN Bootstrap / IRC**: Settings etc.; LanBootstrapServiceManager, IrcAppManager; see [reference/CALLING_AND_EXTENSIONS.md](../reference/CALLING_AND_EXTENSIONS.en.md).

---

## 11. Why this is the current best fit

| Option | Pros | Cons | Conclusion |
|--------|------|------|------------|
| **Pure binary replacement** | No app change, simple deploy | No history in C++, getHistoryMessageList empty; clearHistoryMessage, groupQuitNotification, groupChatIdStored not possible; polling and FfiChatService state not wired to UIKit | Only for minimal “no history, no clear, no group callbacks” demos |
| **Pure Platform** | All capabilities via FfiChatService | Many SDK APIs need Platform impl, tight SDK coupling; TIMManager.initSDK still Native; must keep Native lib as tim2tox and Platform covers all; high impl and maintenance cost | Not used with current SDK routing and Tim2Tox scope |
| **Hybrid (current)** | Most calls still NativeLibraryManager → Dart*, keeps SDK usage; only history, special callbacks, polling, main send path go through Platform/FfiChatService; BinaryReplacementHistoryHook fills history for binary path | Must set Platform and Hook at right time; both paths share same FfiChatService and persistence, no double write | Balances compatibility, feature set, and cost; current choice |

---

## 12. Future evolution

- **SDK upgrade**: If upstream adds “full Platform mode” or more isCustomPlatform routes, consider moving more to Platform and reducing Dart* reliance.
- **Init centralization**: Move some HomePage init (plugins, listeners) to SessionRuntimeCoordinator or a dedicated coordinator to shrink HomePage and ordering coupling.
- **Multi-account / multi-instance UI**: toxee is single-account; multi-account or multi-Tox UI needs stricter teardown/ensure and FfiChatService instance, Provider registration, poll registry isolation and tests.

---

## Easy-to-break spots

1. **Setting TencentCloudChatSdkPlatform.instance in main or before FfiChatService is created**  
   Platform has no ffiService or wrong instance; getHistoryMessageList, clearHistoryMessage etc. fail or no-op.

2. **Changing order of SessionRuntimeCoordinator.ensureInitialized and startPolling**  
   If startPolling before ensureInitialized, polled events may arrive before FakeUIKit/Platform ready; file_request, conn not tied to UI or ffiService.

3. **Registering BinaryReplacementHistoryHook before TimSdkInitializer.ensureInitialized**  
   TIMManager not init → listener registration may be no-op; C++ new messages not written to history.

4. **On logout/account switch only disposing FfiChatService without SessionRuntimeCoordinator.disposeRuntime()**  
   FakeUIKit and Platform not reset; next account reuses old Platform or FakeUIKit → cross-account state or crash.

5. **Changing FakeMessageManager.getHistory conversationID → id stripping**  
   Must match FfiChatService.getHistory(normalizedId) and MessageHistoryPersistence keys or history wrong or empty.

6. **Setting TencentCloudChatSdkPlatform.instance to a new Tim2ToxSdkPlatform elsewhere than HomePage**  
   If not aligned with current FfiChatService, special callbacks and getHistory use wrong instance.

7. **Removing or moving setNativeLibraryName('tim2tox_ffi') earlier**  
   Loads original IM SDK again; TIMManager no longer goes through Tim2Tox; behavior wrong.

---

## Recommended source reading order

1. **Entry and lib name**: `lib/main.dart` → `lib/bootstrap/app_bootstrap.dart` → `lib/bootstrap/logging_bootstrap.dart` (setNativeLibraryName, AppLogger, FFI setLogFile).
2. **Startup and session**: `lib/startup/startup_session_use_case.dart` (execute) → `lib/util/account_service.dart` (initializeServiceForAccount) → `lib/util/app_bootstrap_coordinator.dart` (boot) → `lib/runtime/session_runtime_coordinator.dart` (ensureInitialized), `lib/runtime/tim_sdk_initializer.dart`.
3. **FakeUIKit and Platform**: `lib/sdk_fake/fake_uikit_core.dart` (startWithFfi) → `lib/runtime/session_runtime_coordinator.dart` (set Tim2ToxSdkPlatform) → `third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart` (getHistoryMessageListV2, _handleCustomCallback).
4. **Messages and history**: `lib/sdk_fake/fake_msg_provider.dart` (sendText, sendFile, _loadHistoryForConversation) → `lib/sdk_fake/fake_managers.dart` (FakeMessageManager.getHistory, sendText, sendFile) → `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart` (getHistory, sendText, messages, startPolling).
5. **HomePage init**: `lib/ui/home_page.dart` (initState) → `lib/ui/home_page_bootstrap.dart` (_initAfterSessionReady, _initBinaryReplacementPersistenceHook).
6. **Special callbacks and Hook**: `third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart`; SDK NativeLibraryManager._handleGlobalCallback / dispatchInstanceGlobalCallback (in tencent_cloud_chat_sdk).
7. **Teardown**: `lib/util/account_service.dart` (teardownCurrentSession) → `lib/runtime/session_runtime_coordinator.dart` (disposeRuntime).

---

## Related docs

- [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.en.md) — Hybrid flow and callback split
- [ARCHITECTURE.md](ARCHITECTURE.en.md) — Overall architecture and data flow
- [reference/ACCOUNT_AND_SESSION.md](../reference/ACCOUNT_AND_SESSION.en.md) — Account and session lifecycle
- [reference/IMPLEMENTATION_DETAILS.md](../reference/IMPLEMENTATION_DETAILS.en.md) — Implementation details and message/event handling
- [Tim2Tox](https://github.com/agentx-icu/tim2tox) [architecture](../../third_party/tim2tox/doc/architecture/ARCHITECTURE.md) — Compatibility layer and dual path
