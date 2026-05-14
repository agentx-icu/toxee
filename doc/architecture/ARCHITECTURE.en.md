# toxee Architecture
> Language: [Chinese](ARCHITECTURE.md) | [English](ARCHITECTURE.en.md)

This document describes the **overall client architecture and data flow** (overview). Hybrid architecture responsibilities and the **recommended initialization order** are authoritative in [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.en.md) or [MAINTAINER_ARCHITECTURE.md](MAINTAINER_ARCHITECTURE.md); maintainer view and "easy-to-break spots" are in [MAINTAINER_ARCHITECTURE.md](MAINTAINER_ARCHITECTURE.md).

## Contents

1. [Overview](#overview)
2. [Overall architecture](#overall-architecture)
3. [Core Component](#core-components)
4. [Data flow](#data-flow)
5. [Interface Adapter](#interface-adapter)
6. [Adaptation layer](#adaptation-layer)
7. [Initialization process](#initialization-process)
8. [Key Design Decisions](#key-design-decisions)
9. [Persistence Solution](#7-unified-persistence-solution)

## Overview

toxee is a sample Flutter chat client based on Tim2Tox. It shows how to integrate Tim2Tox into Tencent Cloud Chat UIKit to achieve fully decentralized P2P chat functionality.

### Latest updates

- ✅ **Modular Architecture**: Tim2Tox FFI layer has been fully modularized, split from the original 3200+ line single file into 13 functional modules
- ✅ **Build Optimization**: Built using DEBUG mode, including complete debugging symbols for easy debugging
- ✅ **Log System**: A unified log system that supports real-time viewing of application logs
- ✅ **Stability Verification**: The application can run stably with no crash reports
- ✅ **Unified persistence solution**: Platform interface solution and binary replacement solution use the same persistence code, and the data format is exactly the same
- ✅ **Multiple instance support**: Tim2Tox now supports the creation of multiple independent Tox instances (mainly used for testing scenarios). toxee uses the default instance without special configuration.

### Design principles

1. **Tim2Tox independence**: Tim2Tox (`tim2tox_dart`) is completely independent and does not rely on any client code
2. **Interface abstraction**: Inject client dependencies through interfaces to achieve dependency inversion
3. **Adapter mode**: The client maps the Tim2Tox interface to a specific implementation through the adapter
4. **UIKit first**: Use UIKit components as much as possible and only write necessary adaptation code

## Overall architecture

toxee actually maintains three conceptual integration forms:

- **Pure Binary Replacement**: Set only `setNativeLibraryName('tim2tox_ffi')`
- **Platform interface solution**: only route SDK calls through `Tim2ToxSdkPlatform`
- **Hybrid Architecture**: Binary replacement is responsible for most Native calls, `Tim2ToxSdkPlatform` is responsible for historical messages, custom callbacks, calls and some extension capabilities

The current client is using a **hybrid architecture**.

### Currently used solution: hybrid architecture

**Features**:
- The dynamic library is replaced with `libtim2tox_ffi`, and the C++ callback is dispatched by NativeLibraryManager.
- **Required**: `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform`. This is installed by `SessionRuntimeCoordinator.ensureInitialized()` (the runtime only assigns when `instance is! Tim2ToxSdkPlatform`). The coordinator is called from `AppBootstrapCoordinator.boot()` — both auto-login (`_StartupGate` → `StartupSessionUseCase`) and manual login (`LoginPage` → `LoginUseCase`) run `boot()` **before** navigating to `HomePage`. `HomePage._initAfterSessionReady()` calls the coordinator again as an idempotent safety net. The Platform must be installed by the first screen, otherwise history queries and C++ special callbacks (`clearHistoryMessage`, `groupQuitNotification`, `groupChatIdStored`) fail silently.
- Message sending, session/friend data go directly to `FfiChatService` via `FakeUIKit`.
- `CallServiceManager` is built inside `FakeUIKit.startWithFfi`; its `initialize()` is called at the end of `SessionRuntimeCoordinator.ensureInitialized()` (after Platform is set). Sticker / text-translate / sound-to-text plug-ins are registered in `HomePage._initAfterSessionReady()`.

See [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.en.md) for details.

**Call path**:
```
UIKit SDK
  ↓
TIMManager.instance
  ↓
NativeLibraryManager (native SDK call path)
  ↓
bindings.DartXXX(...) (FFI dynamic symbol lookup)
  ↓
libtim2tox_ffi.dylib (replaced dynamic library)
  ↓
dart_compat_layer.cpp (Dart* function implementation)
  ↓
V2TIM*Manager (C++ API implementation)
  ↓
ToxManager (Tox core)
  ↓
c-toxcore (P2P communication)
```

### Alternative: Platform interface solution

**Features**:
- Requires setting `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(...)`
- Use the advanced service layer (FfiChatService) to provide richer functions
- Need to modify Dart layer code

**Call path**:
```
UIKit SDK
  ↓
TencentCloudChatSdkPlatform.instance (Tim2ToxSdkPlatform)
  ↓
FfiChatService (advanced service layer)
  ↓
Tim2ToxFfi (FFI binding)
  ↓
tim2tox_ffi_* (C FFI interface)
  ↓
V2TIM*Manager (C++ API implementation)
  ↓
ToxManager (Tox core)
  ↓
c-toxcore (P2P communication)
```

### Architecture diagram (hybrid / current solution)

```
┌─────────────────────────────────────────────────────────────┐
│                    toxee                        │
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   UI Layer   │  │ Adapter Layer│  │  Utils Layer │      │
│  │              │  │              │  │              │      │
│  │ - UIKit      │  │ - Interface  │  │ - Prefs      │      │
│  │   Components │  │   Adapters   │  │ - Logger      │      │
│  │ - Custom UI  │  │              │  │ - Bootstrap   │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                  │                  │              │
│         └──────────────────┴──────────────────┘              │
│                            │                                  │
│         ┌──────────────────▼──────────────────┐              │
│         │      Data Adapter Layer              │              │
│         │  ┌──────────────────────────────┐  │              │
│         │  │  lib/sdk_fake/               │  │              │
│         │  │  - fake_im.dart              │  │              │
│         │  │  - fake_managers.dart        │  │              │
│         │  │  - fake_provider.dart         │  │              │
│         │  │  - fake_uikit_core.dart      │  │              │
│         │  └──────────────────────────────┘  │              │
│         └──────────────────┬──────────────────┘              │
└─────────────────────────────┼───────────────────────────────┘
                              │
        ┌─────────────────────▼─────────────────────┐
        │ Tencent Cloud Chat SDK (native calling method) │
        │  ┌──────────────────────────────────────┐  │
        │  │  TIMManager.instance                │  │
        │  │  NativeLibraryManager               │  │
        │  │  bindings.DartXXX(...)              │  │
        │  └──────────────┬───────────────────────┘  │
        └─────────────────┼─────────────────────────┘
                          │
        ┌─────────────────▼─────────────────┐
        │    libtim2tox_ffi.dylib           │
        │ (replaced dynamic library) │
        │  ┌──────────────────────────────┐ │
        │  │  dart_compat_layer.cpp       │ │
        │ │ (Dart* function implementation) │ │
        │  └──────────────┬───────────────┘ │
        └─────────────────┼─────────────────┘
                          │
        ┌─────────────────▼─────────────────┐
        │         Tim2Tox (C/C++)            │
        │  ┌──────────┐  ┌──────────────┐   │
        │  │ FFI C/C++│  │ C++ Core     │   │
        │  │          │  │              │   │
        │  │ tim2tox_ │  │ V2TIM*Impl   │   │
        │  │ ffi      │  │              │   │
        │  └────┬─────┘  └──────┬───────┘   │
        └───────┼───────────────┼────────────┘
                │               │
        ┌───────▼───────────────▼───────┐
        │      Tox (c-toxcore)          │
        └───────────────────────────────┘
```

## Integration solution comparison

### Solution 1: Pure binary replacement solution

**Implementation**:
- Change the dynamic library name from `dart_native_imsdk` to `tim2tox_ffi` in `native_library_manager.dart`
- **NO SET** `TencentCloudChatSdkPlatform.instance`
- Use `TIMManager.instance` → `NativeLibraryManager` → Dart* function directly

**Call path**:
```
UIKit SDK
  ↓
TIMManager.instance.initSDK()
  ↓
NativeLibraryManager.bindings.DartInitSDK(...)
  ↓
FFI dynamically looks for symbols 'DartInitSDK' (in libtim2tox_ffi.dylib)
  ↓
dart_compat_layer.cpp::DartInitSDK()
  ↓
V2TIMManager::GetInstance()->InitSDK(...)
  ↓
ToxManager::getInstance().init(...)
  ↓
tox_new() (c-toxcore)
```

**Advantages**:
- ✅ **Minimal access points**: In theory, just replace the dynamic library and call `setNativeLibraryName(...)` in advance
- ✅ **Full Compatibility**: Function signature and callback format exactly match the native SDK
- ✅ **Easy to Deploy**: Just replace the dynamic library file
- ✅ **Low workload**: Only implement functions that are actually used (about 68)

**Restrictions**:
- Function signature must exactly match the native SDK
- The JSON format must be completely consistent with the native SDK
- Relies on the callback mechanism of Dart API DL

**Key Documents**:
- tencent_cloud_chat_sdk package (after bootstrap at `third_party/tencent_cloud_chat_sdk`) — `lib/native_im/bindings/native_library_manager.dart` for dynamic library loading
- `tim2tox/ffi/dart_compat_layer.cpp` - Dart* function implementation
- `tim2tox/ffi/callback_bridge.cpp` - callback bridging mechanism

### Solution 2: Platform interface solution (alternative)

**Implementation**:
- Settings `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(...)`
- Use the advanced service layer (FfiChatService) to provide richer functions
- Need to modify Dart layer code

**Call path**:
```
UIKit SDK
  ↓
TencentCloudChatSdkPlatform.instance.sendMessage()
  ↓
Tim2ToxSdkPlatform.sendMessage()
  ↓
ChatMessageProvider.sendText() / sendImage() / sendFile()
  ↓
FakeChatMessageProvider.sendText() / sendImage() / sendFile()
  ↓
FfiChatService.sendText() / sendGroupText() / sendFile() / sendGroupFile()
  ↓
tim2tox_ffi_send_c2c_text() / tim2tox_ffi_send_group_text()
  ↓
V2TIMMessageManagerImpl::SendMessage(...)
  ↓
ToxManager::SendMessage(...)
  ↓
tox_friend_send_message() (c-toxcore)
```

**Advantages**:
- ✅ **Rich functions**: The advanced service layer provides message history, polling, status management, etc.
- ✅ **Strong flexibility**: You can customize the implementation logic
- ✅ **Easy to Expand**: Custom functions can be added

**Restrictions**:
- Need to modify Dart layer code
- Need to maintain Platform interface implementation
- Large workload (need to implement more interfaces)

**Key Documents**:
- `tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart` - Platform interface implementation
- `tim2tox/dart/lib/service/ffi_chat_service.dart` - Advanced service layer
- `toxee/lib/sdk_fake/` - Data adaptation layer

### Option 3: Hybrid architecture (currently used)

**Implementation**:
- `setNativeLibraryName('tim2tox_ffi')` runs inside `AppBootstrap.initialize()` → `LoggingBootstrap.initialize()` from `main()`.
- `_StartupGate` / `LoginPage` create and log in `FfiChatService` via `AccountService.initializeServiceForAccount(..., startPolling: false)`.
- Once login succeeds, the caller runs `AppBootstrapCoordinator.boot(service)`, which calls `SessionRuntimeCoordinator.ensureInitialized()` (this is where `Tim2ToxSdkPlatform` is installed and `FakeUIKit.startWithFfi` runs), then `TimSdkInitializer.ensureInitialized()` (calls `TIMManager.instance.initSDK()`), then `service.startPolling()`.
- `HomePage._initAfterSessionReady()` registers `BinaryReplacementHistoryHook`, group/friend listeners, UIKit `ChatDataProvider` / `ChatMessageProvider` registries, and the sticker / text-translate / sound-to-text plug-ins.

**Features**:
- Retain binary replacement links and be compatible with UIKit’s Native calling habits
- Use Platform path to complete historical messages, custom callback, signaling / ToxAV bridging and expansion capabilities
- It is the production access method for the actual operation of the current code base.

### Suggestions for plan selection

**Currently used**: Hybrid architecture

**Reason for selection**:
1. While retaining UIKit compatibility and advanced capabilities
2. There are clear access points for historical messages, group exit cleaning, chat_id persistence and calls.
3. More in line with the current client’s account system, extensions and desktop capabilities

**When to use the Platform interface scheme**:
1. When doing minimal verification or isolated debugging, pure binary replacement can be considered
2. When doing independent SDK encapsulation or non-current client access, you can consider the pure Platform interface solution
3. It is recommended to continue to use the hybrid architecture for client production.

## Core components

### 1. Tim2Tox layer (`tim2tox_dart` package)

Tim2Tox upstream repo: [https://github.com/anonymoussoft/tim2tox](https://github.com/anonymoussoft/tim2tox). In toxee it is used as a submodule at `third_party/tim2tox`.

#### 1.1 FFI binding layer (`lib/ffi/`)

**Responsibilities**: Provide Dart FFI binding and directly call the C FFI library

**Main categories**:
- `Tim2ToxFfi`: FFI binding class, encapsulates all C FFI function calls**Key methods**:
- `init()`: Initialize FFI library
- `login()`: Login
- `sendMessage()`: Send message
- `getFriendList()`: Get friends list
- `addFriend()`: Add friends
- Wait...

#### 1.2 Service Layer (`lib/service/`)

**Responsibilities**: Provide advanced service API, manage message history, polling, status, etc.

**Main categories**:
- `FfiChatService`: Core service category

**Key Features**:
- Message history management
- event polling
- Friend status management
- File transfer management
- Offline message queue

**Dependency Injection**:
- `ExtendedPreferencesService`: Preferences
- `LoggerService`: Log
- `BootstrapService`: Bootstrap node

#### 1.3 SDK Platform layer (`lib/sdk/`)

**Responsibilities**: Implement the `TencentCloudChatSdkPlatform` interface and route UIKit SDK calls to tim2tox

**Main categories**:
- `Tim2ToxSdkPlatform`: SDK Platform implementation

**Key Features**:
- Implement all V2TIM APIs
- Manage SDK lifecycle
- Handle messages, friends, and group operations
- Event notification

**Dependency Injection**:
- `FfiChatService`: Core Services
- `EventBusProvider`: event bus (optional)
- `ConversationManagerProvider`: Session Manager (optional)

#### 1.4 Abstract interface layer (`lib/interfaces/`)

**Responsibilities**: Define injectable dependency interfaces

**Interface List**:
- `PreferencesService` / `ExtendedPreferencesService`: Preference interface
- `LoggerService`: Log interface
- `BootstrapService`: Bootstrap node interface
- `EventBus` / `EventBusProvider`: event bus interface
- `ConversationManagerProvider`: Session manager interface

### 2. Client layer

#### 2.1 Interface Adapter Layer (`lib/adapters/`)

**Responsibilities**: Implement the abstract interface of Tim2Tox and map the Tim2Tox interface to the client specific implementation

**Adapter List**:

1. **SharedPreferencesAdapter**
   - Implementation: `ExtendedPreferencesService`
   - Use: `SharedPreferences`
   - Function: Store all preference data

2. **AppLoggerAdapter**
   - Implementation: `LoggerService`
   - Use: `AppLogger`
   - Function: Logging

3. **BootstrapNodesAdapter**
   - Implementation: `BootstrapService`
   - Use: `BootstrapNodes` + `SharedPreferences`
   - Function: Bootstrap node management

4. **EventBusAdapter**
   - Implementation: `EventBusProvider`
   - Use: `FakeEventBus`
   - Function: Provide event bus instance

5. **ConversationManagerAdapter**
   - Implementation: `ConversationManagerProvider`
   - Use: `FakeConversationManager`
   - Function: Provide session management function

#### 2.2 Data Adaptation Layer (`lib/sdk_fake/`)

**Responsibilities**: Convert the tim2tox data model to the format expected by UIKit

**Main components**:

1. **FakeIM** (`fake_im.dart`)
   - Event bus manager
   - Subscribe to `FfiChatService` events
   - Issue `FakeConversation`, `FakeMessage` and other events
   - Manage conversation lists, contact lists, etc.

2. **FakeManagers** (`fake_managers.dart`)
   - `FakeConversationManager`: Session Management
   - `FakeMessageManager`: Message management
   - `FakeContactManager`: Contact management

3. **FakeProviders** (`fake_provider.dart`, `fake_msg_provider.dart`)
   - `FakeChatDataProvider`: implements `ChatDataProvider`, providing session data
   - `FakeChatMessageProvider`: Implement `ChatMessageProvider` to handle message sending

4. **FakeUIKitCore** (`fake_uikit_core.dart`)
   - `FakeUIKit`: UIKit core adapter
   - Manage all Fake components
   - Provide a unified initialization entrance

5. **FakeEventBus** (`fake_event_bus.dart`)
   - Event bus implementation
   - Support typed event subscription and publishing

6. **FakeModels** (`fake_models.dart`)
   - Client-specific data model
   - Compatible with Tim2Tox’s `Fake*` model

#### 2.3 UI layer (`lib/ui/`)

**Responsibilities**: User interface components.

**Main components**:
- `login_page.dart`: Login/Registration page
- `home_page.dart`: Main page, including UIKit integration
- `settings/`: Settings page
- `applications/`: Friend application page
- Other custom UI components

**UIKit component usage**:
- `TencentCloudChatConversation`: Conversation list
- `TencentCloudChatMessage`: Message page
- `TencentCloudChatContact`: Contact page
- Wait...

#### 2.4 Tool Layer (`lib/util/`)

**Responsibilities**: Client-specific utility classes

**Main Tools**:
- `prefs.dart`: Preference management (SharedPreferences package)
- `logger.dart`: Log system
- `bootstrap_nodes.dart`: Bootstrap node configuration
- `tox_utils.dart`: Tox ID tool function
- `theme_controller.dart`: Theme management
- `locale_controller.dart`: Language management

## Data flow

### SDK calling path

Under the current hybrid architecture, different operations take different paths:

- **Message sending, conversation/friends**: via **FakeUIKit → FfiChatService** (not via Platform). For example: FakeChatMessageProvider → FfiChatService.sendMessage; FakeConversationManager/FakeContactManager directly uses FfiChatService.getFriendList, knownGroups, etc.
- **History loading**: When the SDK layer `platform.isCustomPlatform == true` (that is, Tim2ToxSdkPlatform has been set), `getHistoryMessageListV2` waits for **TencentCloudChatSdkPlatform.instance → Tim2ToxSdkPlatform → FfiChatService.getHistory / MessageHistoryPersistence**.

```
Messaging/Conversation/Friends:
  UIKit → FakeUIKit (FakeChatMessageProvider / FakeManagers) → FfiChatService → Tim2ToxFfi → tim2tox_ffi → toxcore

Historical query (when isCustomPlatform):
  UIKit SDK (getHistoryMessageListV2) → TencentCloudChatSdkPlatform.instance (Tim2ToxSdkPlatform)
    → FfiChatService.getHistory / MessageHistoryPersistence
```**IMPORTANT NOTE**:
- Under all non-Web platforms (Windows/Linux/macOS/Android/iOS), historical queries and other calls that require Platform must be routed to `Tim2ToxSdkPlatform` after setting Tim2ToxSdkPlatform.
- The tencent_cloud_chat_sdk package (after bootstrap at `third_party/tencent_cloud_chat_sdk`) has been modified so that when `isCustomPlatform` it takes the Platform path, completely removing the dependence on the native IM SDK (except for the Web platform)
- Message IDs uniformly use the `timestamp_userID` format (millisecond timestamp) to ensure uniqueness and consistency

### Message sending path

Sending paths for text messages and file messages:

```
UIKit Message Input
  ↓
ChatMessageProvider (FakeChatMessageProvider)
  ↓
Offline detection (check if a contact is online)
  ├─ If offline → mark as failed immediately → save to persistent storage → display failure status
  └─ If online → Continue sending process
  ↓
FfiChatService.sendMessage()
  ↓
Tim2ToxFfi.sendMessage()
  ↓
tim2tox_ffi (C)
  ↓
tim2tox (C++)
  ↓
toxcore
  ↓
Timeout detection (using Future.timeout)
  ├─ Text messages: 5 second timeout
  ├─ File message: dynamically calculated based on file size (basic 60 seconds + file size/100KB/s)
  └─ If timeout → Mark as failed → Save to persistent storage → Update UI state
```

**Failure message handling mechanism**:
1. **Offline detection**: Check whether the contact is online before sending. If offline, mark it as failed immediately.
2. **Timeout mechanism**: Use `Future.timeout` to implement dynamic timeout and adjust the timeout according to message type and size
3. **Persistent Storage**: Failure messages are saved to `SharedPreferences` and managed using `TencentCloudChatFailedMessagePersistence`
4. **Status Recovery**: Automatically restore the failed message status from the persistent storage after the client restarts.

### Message history persistence

**Unified persistence solution**:
- ✅ **Both plans share the same persistence code**: `MessageHistoryPersistence` and `OfflineMessageQueuePersistence`
- ✅ **Data format is completely consistent**: same JSON format and file structure
- ✅ **Binary replacement solution is implemented through Hook**: `BinaryReplacementHistoryHook` automatically intercepts messages and saves them
- ✅ **Platform interface solution is used directly**: `FfiChatService` directly calls the persistence service

**Storage location**:
- Message history: `<Application Support Directory>/chat_history/<conversationId>.json`
- Offline message queue: `<Application Support Directory>/offline_message_queue.json`

**Persistence Service**:
- `MessageHistoryPersistence`: Unified message history persistence service
  - Automatic saving and loading
  - Supports session level history
  - Memory management (retain up to 1000 items)
  - Automatic recovery after application restart
- `OfflineMessageQueuePersistence`: Unified offline message queue persistence service
  - Manage offline message queue
  - Automatically cleared after the app is restarted (to prevent repeated sending)

**Binary replacement scheme Hook**:
- `BinaryReplacementHistoryHook`: wrapper `V2TimAdvancedMsgListener`, automatically save received messages
- `BinaryMessageManagerWrapper`: Optional wrapper class that intercepts historical queries and reads from the persistence service

For detailed instructions, please refer to: [reference/IMPLEMENTATION_DETAILS.md](../reference/IMPLEMENTATION_DETAILS.en.md)’s message processing chapter, and [HYBRID_ARCHITECTURE.md](./HYBRID_ARCHITECTURE.en.md)’s callback division of labor instructions.

### Message receiving path

Message and event receiving paths:

```
toxcore
  ↓
tim2tox (C++)
  ↓
tim2tox_ffi (C)
  ↓
FfiChatService (polling event)
  ↓
[Two paths]:
  1. SDK Events:
     Tim2ToxSdkPlatform
       ↓
     UIKit SDK Listeners
       ↓
     UI Updates

  2. Data Streams:
     FakeIM (Subscribe to FfiChatService)
       ↓
     FakeEventBus (publish event)
       ↓
     FakeManagers (handling events)
       ↓
     FakeProviders (provide data)
       ↓
     UIKit Controllers
       ↓
     UI Updates
```

### File receiving path

File reception involves multiple levels of event processing and status management:

```
toxcore file transfer protocol
  ↓
tim2tox (C++) - OnFileRecv callback
  ↓
tim2tox_ffi (C) - Send file_request event to polling queue
  ↓
FfiChatService (adaptive polling event)
  ├─ Adaptive Polling interval
  │ ├─ File transfer period: 50ms (very frequent)
  │ ├─ Active period (activity in the last 2 seconds): 200ms
  │ └─ Idle period: 1000ms (reduces CPU usage)
  │
  ├─ file_request event
  │ ├─ Create pending message (msgID: timestamp_userID, unified format)
  │ ├─ Set temporary path (/tmp/receiving_<filename>)
  │ ├─ Track file transfer progress (_fileReceiveProgress)
  │ └─ Automatically accept file transfers (if images or small files)
  │
  ├─ acceptFileTransfer (call fileControlNative)
  │ └─ Notifies the C++ layer that the file transfer is accepted
  │
  ├─ progress_recv event (per data block)
  │ ├─ Update _fileReceiveProgress
  │ ├─ Send to _progressCtrl stream
  │ └─ If received >= total, call _handleFileDone directly (without waiting for the file_done event)
  │
  └─ file_done event (file completed)
      ├─Call _handleFileDone for unified processing
      ├─ Fallback: If the message does not exist, find or create a pending message
      ├─ Move files to final location (avatars or Downloads)
      └─ Update message path and status
  ↓
FakeChatMessageProvider (subscribe to progressUpdates stream)
  ├─ Match message (by path, filename or msgID)
  ├─ fileElem/imageElem of update message
  │ ├─ update path
  │ └─ Update localUrl (when file is complete)
  └─ Notification UI updates
  ↓
UIKit display files
  ├─ Check hasLocal (via imageList[].localUrl)
  ├─ If completed: show file
  └─ If receiving: show progress
```

**Key components**:

1. **Event Queue** (`tim2tox_ffi.cpp`):
   - `file_request`: File transfer request
   - `progress_recv`: Receive progress updates
   - `file_done`: File reception completed

2. **Status Tracking** (`tim2tox/dart/lib/service/ffi_chat_service.dart`):
   - `_fileReceiveProgress`: Track file reception progress (`(uid, fileNumber)` → progress information)
   - `_pendingFileTransfers`: Track pending file transfers
   - `_msgIDToFileTransfer`: Mapping of message ID to file transfer

3. **Progress Update** (`fake_msg_provider.dart`):
   - `_fileProgress`: Track message progress (`msgID` → Progress information)
   - Subscribe to `progressUpdates` stream to update message elements

**Message ID format**:
- File receiving message: `timestamp_userID` (unified format with other messages)
- For example: `1765459900999_10F189D746EF383F1A731AFDBE72FCA99289E817721D5F25C1C67D8B351E034F`
- Ensure uniqueness and traceability and simplify message matching logic

**Path Management**:
- Temporary path: `/tmp/receiving_<filename>` (receiving)
- Final path:
  - Picture: `<appDir>/avatars/<basename>_<timestamp><ext>`
  - Other files: `<Downloads>/<filename>`

**Auto-Accept Policy**:
- Avatar file (kind == 1): automatically accepted
- Image files: automatically accepted
- Small files (< user-configured threshold, default 30MB): automatically accepted
- Large files: require manual acceptance by the user (via UIKit's download button)

**File reception failure handling**:
- After the client is restarted, the `_cancelPendingFileTransfers` method will mark all pending receiving files as failed (`isPending=false`)
- Keep the message record but no longer display the loading status to prevent the UI from spinning in circles
- Clean all file transfer tracking data (`_fileReceiveProgress`, `_pendingFileTransfers`, `_msgIDToFileTransfer`)

## Interface adapter

### Adapter design pattern

The client maps the abstract interface of Tim2Tox to a concrete implementation through the adapter pattern:

```
Tim2Tox Interface           Client Implementation
─────────────────          ─────────────────────
ExtendedPreferencesService → SharedPreferencesAdapter → SharedPreferences
LoggerService             → AppLoggerAdapter         → AppLogger
BootstrapService          → BootstrapNodesAdapter     → BootstrapNodes
EventBusProvider          → EventBusAdapter           → FakeEventBus
ConversationManagerProvider → ConversationManagerAdapter → FakeConversationManager
```

### Adapter implementation example

#### SharedPreferencesAdapter

```dart
class SharedPreferencesAdapter implements ExtendedPreferencesService {
  final SharedPreferences _prefs;
  
  @override
  Future<String?> getString(String key) async => _prefs.getString(key);
  
  @override
  Future<void> setString(String key, String value) => 
      _prefs.setString(key, value);
  
  // ...implement all required methods
}
```

#### EventBusAdapter

```dart
class EventBusAdapter implements EventBusProvider {
  final FakeEventBus _eventBus;
  
  EventBusAdapter(this._eventBus);
  
  @override
  EventBus get eventBus => _eventBus;
}
```

## Adaptation layer

### FakeIM - Event Bus Manager

**Responsibilities**:
- Subscribe to `FfiChatService`'s events
- Convert tim2tox events to UIKit format
- Post event via `FakeEventBus`

**Key methods**:
- `start()`: Start event subscription
- `_refreshConversations()`: Refresh session list
- `_emitContacts()`: Send contact event
- `_seedHistory()`: Initialize message history

### FakeManagers - Manager

**FakeConversationManager**:
- Manage session list
- Handle session updates
- Manage unread count

**FakeMessageManager**:
- Manage message history
- Handle message status
- Manage message recipients

**FakeContactManager**:
- Manage contact list
- Handle contact updates

### FakeProviders - Data providers

**FakeChatDataProvider**:
- Implement `ChatDataProvider` interface
- Provide session data stream
- Provide unread count stream

**FakeChatMessageProvider**:
- Implement `ChatMessageProvider` interface
- Handle message sending
- Supports message types such as text, pictures, files, etc.

## Initialization process

### Recommended initialization sequence (hybrid architecture)

A hybrid architecture is currently used. The conceptual sequence is: `FfiChatService.init` → `login` → `updateSelfProfile` → `SessionRuntimeCoordinator.ensureInitialized` (installs `FakeUIKit` + `Tim2ToxSdkPlatform`, then `CallServiceManager.initialize()`) → `TimSdkInitializer.ensureInitialized` (`TIMManager.initSDK`) → `FfiChatService.startPolling` → `HomePage._initAfterSessionReady` registers `BinaryReplacementHistoryHook`, group/friend listeners, UIKit providers, and plug-ins. See [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.en.md) for the authoritative details.

### Complete initialization sequence

**Automatic login path (_StartupGate)** (consistent with code):

```
main()
   ├─ AppBootstrap.initialize()
   │    ├─ LoggingBootstrap.initialize()  // setNativeLibraryName('tim2tox_ffi'); do not set Platform
   │    ├─ PrefsBootstrap.initialize()
   │    ├─ AppRuntimeBootstrap.initialize()
   │    └─ DesktopShellBootstrap.initializeIfNeeded()
   └─ EchoUIKitApp → _StartupGate

_StartupGate._runStartup() / StartupSessionUseCase.execute (automatic login)
   ├─ AccountService.initializeServiceForAccount(toxId, ..., startPolling: false)
   │    ├─ FfiChatService(prefs, logger, bootstrap, historyDirectory, ...)
   │    ├─ service.init(profileDirectory)
   │    ├─ service.login(...)
   │    └─ service.updateSelfProfile(...)
   ├─ AppBootstrapCoordinator.boot(service)
   │    ├─ SessionRuntimeCoordinator(service).ensureInitialized()
   │    │    ├─ FakeUIKit.instance.startWithFfi(service)
   │    │    ├─ TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(...)
   │    │    └─ FakeUIKit.instance.callServiceManager?.initialize()
   │    ├─ TimSdkInitializer.ensureInitialized()    // TIMManager.initSDK
   │    └─ service.startPolling()
   ├─ Wait on connectionStatusStream or timeout
   ├─ Preload friend and contact status
   └─ Navigate to HomePage(service)
```

**Manual login path (LoginPage / LoginUseCase)**:

```
1. main()
   └─ AppBootstrap.initialize()  // same as auto-login path

2. LoginPage
   ├─ User input nickname / status / bootstrap node
   ├─ LoginUseCase.execute(...) → AccountService.initializeServiceForAccount(..., startPolling: false)
   ├─ AppBootstrapCoordinator.boot(service)   // SessionRuntime + TIM init + startPolling
   └─ Navigate to HomePage(service)

3. HomePage.initState() → unawaited(_initAfterSessionReady())
   ├─ SessionRuntimeCoordinator(service).ensureInitialized()  // idempotent
   ├─ TimSdkInitializer.ensureInitialized().then((_) {
   │    ├─ _initBinaryReplacementPersistenceHook()
   │    ├─ initGroupListener / initFriendListener
   │  })
   ├─ Register ChatDataProviderRegistry, ChatMessageProviderRegistry, etc.
   └─ Register sticker / textTranslate / soundToText plug-ins
```

### Initialization code example

In practice almost all of the work below is done by `SessionRuntimeCoordinator.ensureInitialized()` (installed by `AppBootstrapCoordinator.boot()` before `HomePage`); `HomePage` only needs to register providers, the history hook, and listeners.

```dart
// lib/runtime/session_runtime_coordinator.dart (sketch — see source for the real flow)
Future<void> ensureInitialized() async {
  if (!FakeUIKit.instance.isStarted) {
    FakeUIKit.instance.startWithFfi(service);
  }

  if (TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform) {
    final eventBusAdapter = EventBusAdapter(FakeUIKit.instance.eventBusInstance);
    final conversationManagerAdapter = ConversationManagerAdapter(
      FakeUIKit.instance.conversationManager!,
    );
    TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
      ffiService: service,
      eventBusProvider: eventBusAdapter,
      conversationManagerProvider: conversationManagerAdapter,
    );
  }

  await FakeUIKit.instance.callServiceManager?.initialize();
}
```

```dart
// lib/ui/home_page.dart (sketch — see lib/ui/home_page_bootstrap.dart for the real flow)
@override
void initState() {
  super.initState();
  unawaited(_initAfterSessionReady());
}

Future<void> _initAfterSessionReady() async {
  await SessionRuntimeCoordinator(service: widget.service).ensureInitialized();

  await TimSdkInitializer.ensureInitialized();
  _initBinaryReplacementPersistenceHook();
  TencentCloudChat.instance.chatSDKInstance.groupSDK.initGroupListener();
  TencentCloudChat.instance.chatSDKInstance.contactSDK.initFriendListener();

  ChatDataProviderRegistry.provider ??= FakeChatDataProvider(ffiService: widget.service);
  ChatMessageProviderRegistry.provider ??= FakeChatMessageProvider();
  // sticker / textTranslate / soundToText plug-in registration follows
}
```

## Key Design Decisions

### 1. Tim2Tox is completely independent

**Decision**: Tim2Tox (`tim2tox_dart`) does not rely on any client code

**Reason**:
- Improve reusability
- Easy to test
- Clear separation of duties

**Implementation**:
- All client dependencies are injected through the interface
- Tim2Tox only defines the interface and does not implement specific logic

### 2. Adapter mode

**Decision**: Use adapter mode to connect Tim2Tox and the client

**Reason**:
- Decouple Tim2Tox and client implementation
- Support different client implementations
- Easy to test and replace

**Implementation**:
- Tim2Tox defines abstract interface
- Client implements adapter class
- Adapter maps interface calls to concrete implementations

### 3. Event bus architecture

**Decision**: Use event bus for inter-component communication

**Reason**:
- Decoupled components
- Support asynchronous event processing
- Easy to expand

**Implementation**:
- `FakeEventBus`: Client event bus implementation
- `FakeIM`: Subscribe to `FfiChatService` and publish events
- `FakeManagers`: Subscribe to events and update status

### 4. Dual data path

**Decision**: Support both SDK Events and Data Streams data paths

**Reason**:
- SDK Events: Notify UIKit SDK listeners directly
- Data Streams: Provides data streams through event bus to support more flexible UI updates

**Implementation**:
- `Tim2ToxSdkPlatform`: Implement SDK Events
- `FakeIM` + `FakeProviders`: Implement Data Streams

### 5. Lazy initialization

**Decision**: Install the SDK `Platform` only after `FfiChatService.init/login` finishes — driven by `SessionRuntimeCoordinator.ensureInitialized()` from `AppBootstrapCoordinator.boot()`.

**Reason**:
- The platform must hold the exact same `FfiChatService` instance used elsewhere; that instance only exists after `AccountService.initializeServiceForAccount(...)` returns.
- Avoid being overwritten by `TencentCloudChatSdkWeb` (which installs itself during plug-in registration).
- Give the platform access to fully-built `FakeUIKit` adapters (event bus, conversation manager).

**Implementation**:
- `main()` does not set the Platform — `LoggingBootstrap.initialize()` only sets `setNativeLibraryName('tim2tox_ffi')`.
- `SessionRuntimeCoordinator.ensureInitialized()` installs `Tim2ToxSdkPlatform` when `TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform`. It runs in `AppBootstrapCoordinator.boot()` before navigation and idempotently again from `HomePage._initAfterSessionReady()`.
- **`BinaryReplacementHistoryHook`** is installed by `HomePage._initBinaryReplacementPersistenceHook()` after `TimSdkInitializer.ensureInitialized()` completes.

### 6. Failure message handling mechanism

**Decision**: Implement a complete failure message processing process, including timeout detection, offline detection, persistent storage and state recovery

**Reason**:
- Provide a good user experience and clearly indicate message sending failure
- Ensure failure messages are still visible after client restart
- Avoid message loss

**Implementation**:
- **Timeout mechanism**: Use `Future.timeout` to implement dynamic timeout
  - Text messages: 5 second timeout
  - File message: dynamically calculated based on file size (base 60 seconds + file size/100KB/s, maximum 300 seconds)
- **Offline Detection**: Check whether the contact is online before sending, if offline, mark it as failed immediately
- **Persistent Storage**: Use `TencentCloudChatFailedMessagePersistence` to save failure messages to `SharedPreferences`
- **Status Recovery**: After the client restarts, restore the failed message status from the persistent storage to ensure that the failed message is displayed correctly in the chat window and session list

### 7. Unified persistence solution

**Decision**: Platform interface solution and binary replacement solution use the same persistence code

**Reason**:
- Ensure that the data formats of the two solutions are completely consistent
- Both schemes can read each other’s saved data
- Seamless data migration when switching plans
- Code reuse and easy maintenance

**Implementation**:
- **Unified persistence service**:
  - `MessageHistoryPersistence`: Message history persistence service
  - `OfflineMessageQueuePersistence`: Offline message queue persistence service
  - `MessageConverter`: Bidirectional conversion tool between V2TimMessage and ChatMessage
- **Platform interface solution**:
  - `FfiChatService` uses persistence service directly
  - Automatically save messages as they are received and sent
- **Binary Replacement Solution**:
  - `BinaryReplacementHistoryHook`: wrap message listener and automatically save received messages
  - `BinaryMessageManagerWrapper`: optional packaging class, intercepting historical queries
  - Use the same persistence service and data format

**Data format**:
- Message history: JSON format, including conversationId and messages array
- Offline message queue: JSON format, mapping of peerId to message list
- Storage location: `<Application Support Directory>/chat_history/` and `offline_message_queue.json`

For detailed instructions, please refer to: Persistent storage chapter in [reference/IMPLEMENTATION_DETAILS.md](../reference/IMPLEMENTATION_DETAILS.en.md).

### 8. Group/Conference recovery mechanism

**Decision**: Implement a recovery mechanism that distinguishes between Group and Conference types

**Reason**:
- Group and Conference use different Tox APIs and have different recovery methods
- The Group type supports `chat_id` persistence and can be actively restored
- Conference type relies on savedata for automatic recovery and needs to be manually matched

**Implementation**:
- **Type Persistence**:
  - Store `groupType` ("group" or "conference") when creating a group
  - Store via `tim2tox_ffi_set_group_type` to `SharedPreferences`
  - Read via `tim2tox_ffi_get_group_type_from_storage` during recovery

- **Group type recovery**:
  - Read `chat_id` from storage
  - Call `tox_group_join(chat_id)` to actively recover
  - After success, the `onGroupSelfJoin` callback will be triggered to rebuild the mapping.
  - **Advantages**: Active recovery, does not rely on savedata, can be restored even if savedata is lost

- **Conference type restoration**:
  - Tox automatically restores from savedata during initialization
  - Query `tox_conference_get_chatlist()` to obtain restored conferences
  - matches unmapped `conference_number` to `group_id`
  - **Limitations**: Completely dependent on savedata, if savedata is lost it cannot be restored

- **Recovery Timing**:
  - Try recovery immediately when `InitSDK()`
  - Try recovery again after the network connection is established (`HandleSelfConnectionStatus`)
  - Wait for the Tox connection to be established before rejoining (make sure the network is available)

**Recovery Process**:

#### Group type recovery process
```
1. RejoinKnownGroups() is called
   ↓
2. Get all knownGroups from Dart layer
   ↓
3. For each group_id:
   a. Check groupType (read from storage)
   b. If it is "group" type:
      - Read chat_id from storage
      - Convert hex string to binary
      - Call tox_group_join(chat_id)
      - Wait for onGroupSelfJoin callback
      - Rebuild mapping in HandleGroupSelfJoin
```

#### Conference type recovery process
```
1. Load savedata when Tox is initialized
   ↓
2. Conferences are automatically restored from savedata
   ↓
3. RejoinKnownGroups() is called
   ↓
4. Query tox_conference_get_chatlist() to obtain the restored conferences
   ↓
5. For each group_id:
   a. Check groupType (read from storage)
   b. If it is "conference" type:
      - Find unmapped conference_number
      - Map conference_number to group_id
      - Rebuild mapping relationship
```

**Key code location**:
- `tim2tox/source/V2TIMManagerImpl.cpp::RejoinKnownGroups()`
-`tim2tox/source/V2TIMManagerImpl.cpp::InitSDK()`
- `tim2tox/source/V2TIMManagerImpl.cpp::HandleSelfConnectionStatus()`
-`tim2tox/ffi/tim2tox_ffi.cpp::tim2tox_ffi_set_group_type()`

### 9. SDK initialization process

**Decision**: Properly initialize the SDK when the client starts, ensuring all components are initialized in the correct order

**Reason**:
- Make sure the SDK is initialized after the UIKit plugin is registered
- Avoid being overwritten by default platforms (such as `TencentCloudChatSdkWeb`)
- Make sure all dependent services are ready

**Initialization process**:

#### 1. User login stage

```
LoginPage._login() / LoginUseCase.execute()
  ↓
AccountService.initializeServiceForAccount(toxId, ..., startPolling: false)
  ├─ FfiChatService.init(profileDirectory)
  ├─ FfiChatService.login(...)
  └─ FfiChatService.updateSelfProfile(...)
  ↓
AppBootstrapCoordinator.boot(service)
  ├─ SessionRuntimeCoordinator(service).ensureInitialized()  // FakeUIKit + Tim2ToxSdkPlatform + CallServiceManager.initialize()
  ├─ TimSdkInitializer.ensureInitialized()                   // TIMManager.initSDK
  └─ service.startPolling()
  ↓
Navigator.pushReplacement(HomePage(service: service))
```

#### 2. HomePage initialization phase

```
HomePage.initState() → unawaited(_initAfterSessionReady())
  ↓
SessionRuntimeCoordinator(service).ensureInitialized()       // idempotent re-run
  ↓
TimSdkInitializer.ensureInitialized().then((_) {
  ├─ _initBinaryReplacementPersistenceHook()  // when selfId is empty, listens to connectionStatusStream and then _setupPersistenceHook
  ├─ initGroupListener()
  └─ initFriendListener()
})
  ↓
ChatDataProviderRegistry / ChatMessageProviderRegistry registration
  ↓
addUsedComponent, sticker / textTranslate / soundToText plug-ins, EventBus wiring
```

**Key points**:
- The Platform is installed by `SessionRuntimeCoordinator.ensureInitialized()` — `AppBootstrapCoordinator.boot()` runs it before navigating to `HomePage` on both login paths; `_initAfterSessionReady()` re-runs it idempotently as a safety net.
- `BinaryReplacementHistoryHook` is set up in `_initBinaryReplacementPersistenceHook()` after `TimSdkInitializer.ensureInitialized()` resolves.
- `TIMManager.instance.initSDK()` is called by `TimSdkInitializer` exactly once; do not call it directly.
- All UIKit registration and state setup must happen after SDK initialization.

**Differences from standard process**:
- Standard process uses `TencentCloudChat.controller.initUIKit()` unified management initialization
- toxee uses a binary replacement solution and requires manual initialization of each component.
- Does not rely on standard `TUILogin.instance.login()` process

**Key code location**:
- `toxee/lib/ui/login_page.dart:_login()`
- `toxee/lib/ui/home_page.dart:initState()`
-`tim2tox/dart/lib/service/ffi_chat_service.dart:init()`

### 10. Unified message ID format

**Decision**: Uniformly use the `timestamp_userID` format (millisecond timestamp) to generate message IDs

**Reason**:
- Ensure the uniqueness of the message ID
- Facilitates message matching and status updates
- Avoid message matching problems caused by using temporary IDs (such as `created_temp_id`)

**Implementation**:
- `Tim2ToxSdkPlatform` uses `ffiService.selfId` to generate message ID
- `setAdditionalInfoForMessage` ensures that all message IDs use a unified format
- Remove dependency on `created_temp_id`

### 11. Tim2tox interface is compatible with auto_tests single instance

**Decision**: toxee uses a single instance (instance_id=0), which has interface differences with the multi-instance mode of `tim2tox/auto_tests`.

**Interface differences**:
- **auto_tests only**: `registerInstanceForPolling`, `runWithInstanceAsync`, `createTestInstance`, etc. are designed for multi-node testing and do not need to be used by toxee
- **Shared interface**: `getFriendList`, `getFriendApplications`, `startPolling`, `knownGroups`, etc. are compatible with single instances; `getFriendApplications()` uses `getFriendApplicationsForInstance(0, ...)` internally to correctly return the default instance data

**Platform detection**: HomePage uses `TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform` to determine whether Platform needs to be set. The SDK internally (V2TimManager, V2TimMessageManager) uses `platform.isCustomPlatform` to decide whether to take the Platform path to avoid the vulnerability of relying on `runtimeType.toString()`.

**Regression Verification**: After the tim2tox interface is updated, scenarios such as friend application list, session list update, file transfer, etc. need to be verified. For details, see [reference/IMPLEMENTATION_DETAILS.md - Tim2tox interface compatibility and regression verification](../reference/IMPLEMENTATION_DETAILS.en.md#tim2tox-interface-compatibility-and-regression-verification).

## Extended Guide

### Add new features

1. **Add functionality in Tim2Tox**:
   - Implement V2TIM API in C++ layer
   - Add C interface in FFI layer
   - Added FFI binding and service API in Dart layer

2. **Use new features in the client**:
   - Use directly via `Tim2ToxSdkPlatform` (if implemented)
   - Or subscribe to events via `FakeIM` and update the UI

### Custom adapter

If you need to use a different implementation, just create a new adapter:

```dart
class MyCustomPreferencesAdapter implements ExtendedPreferencesService {
  // Use custom storage implementation
  // ...
}
```

Then on initialization use:

```dart
final ffiService = FfiChatService(
  preferencesService: MyCustomPreferencesAdapter(),
  // ...
);
```

## Summary

toxee shows how to integrate Tim2Tox into a Flutter app. Through the adapter pattern and interface abstraction, Tim2Tox and the client are completely decoupled, allowing Tim2Tox to be reused by any Flutter client.

Key takeaways:
- Tim2Tox is completely independent, injecting dependencies through interfaces
- The client implements the interface through the adapter
- Use event bus for inter-component communication
- Support dual data paths (SDK Events + Data Streams)
