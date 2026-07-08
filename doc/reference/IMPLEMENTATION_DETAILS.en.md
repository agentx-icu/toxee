# toxee Implementation Details
> Language: [Chinese](IMPLEMENTATION_DETAILS.md) | [English](IMPLEMENTATION_DETAILS.en.md)


## Contents

1. [Integrated solution](#integration-solution)
2. [Interface Adapter Implementation](#interface-adapter-implementation)
3. [Data adaptation layer implementation](#data-adaptation-layer-implementation)
4. [Detailed explanation of initialization process](#detailed-explanation-of-initialization-process)
5. [Message processing flow](#message-processing-process)
6. [Event processing flow](#event-handling-process)
7. [File transfer implementation](#file-transfer-implementation)
8. [Friend Management Implementation](#friends-management-implementation)
9. [Group management implementation](#group-management-implementation)
10. [Account and session lifecycle](#account-and-session-lifecycle)
11. [Calling and expansion capabilities](#calling-and-expansion-capabilities)
12. [Tim2tox interface compatibility and regression verification](#tim2tox-interface-compatibility-and-regression-verification)

Also see [HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.en.md) to learn about the complete process and callback division of the hybrid architecture, and [ACCOUNT_AND_SESSION.md](ACCOUNT_AND_SESSION.en.md) to view the account and session lifecycle.

## Integration solution

toxee currently uses the **Binary Replacement + Hybrid Platform** scheme to integrate Tim2Tox (upstream repo [https://github.com/agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)). See also [HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.en.md).

**Multiple instance support instructions**:
- toxee uses default Tox instance (via `V2TIMManagerImpl::GetInstance()`)
- No need to create a test instance, just use `TIMManager.instance` directly
- The multi-instance function is mainly used in automated testing scenarios (such as `tim2tox/auto_tests`)
- See [Tim2Tox](https://github.com/agentx-icu/tim2tox) [multi-instance support documentation](../../third_party/tim2tox/doc/development/MULTI_INSTANCE_SUPPORT.en.md) for details

### Current solution: hybrid architecture

**Implementation location**:
- tencent_cloud_chat_sdk package (after bootstrap at `third_party/tencent_cloud_chat_sdk`) — `lib/native_im/bindings/native_library_manager.dart` for dynamic library loading
- `toxee/lib/main.dart` — calls `setNativeLibraryName('tim2tox_ffi')` via `AppBootstrap.initialize()` → `LoggingBootstrap.initialize()` (actual call in `lib/bootstrap/logging_bootstrap.dart`); does not set Platform; actual entrance is EchoUIKitApp → _StartupGate
- Platform is set by `SessionRuntimeCoordinator.ensureInitialized()` (`lib/runtime/session_runtime_coordinator.dart`); on auto-login from `AppBootstrapCoordinator.boot()` before HomePage, on manual login when the login page calls `boot(service)` or from HomePage._initAfterSessionReady(). HomePage then runs _initTIMManagerSDK, _initBinaryReplacementPersistenceHook, etc.

**Key code**:
```dart
// lib/bootstrap/logging_bootstrap.dart (called earliest in main() via AppBootstrap.initialize())
// BINARY REPLACEMENT MODE: ensure all later SDK/FFI calls load tim2tox dynamic library
setNativeLibraryName('tim2tox_ffi');

// SessionRuntimeCoordinator.ensureInitialized() (required for hybrid: sets Platform)
if (TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform) {
  TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
    ffiService: service,
    eventBusProvider: eventBusAdapter,
    conversationManagerProvider: conversationManagerAdapter,
  );
}
// In HomePage: TimSdkInitializer.ensureInitialized().then((_) {
//   _initBinaryReplacementPersistenceHook(); initGroupListener(); initFriendListener();
// });
```

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
```

**Characteristics and trade-offs**: Most calls still go through NativeLibraryManager → Dart*, compatible with existing SDK usage; history, special callbacks, polling, and the main message-send path are handled on the Dart side (FfiChatService, Platform, BinaryReplacementHistoryHook). Platform and Hook must be set at the right time (auto-login in boot; manual login: login page calls `boot(service)` or HomePage runs ensureInitialized), and startPolling must be called after SessionRuntimeCoordinator.ensureInitialized.

### Alternative: Platform interface solution

**Implementation location**:
- `tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart` - Platform interface implementation
- `tim2tox/dart/lib/service/ffi_chat_service.dart` - Advanced Service Tier

**Key code**:
```dart
// Need to set up Platform instance
TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
  ffiService: ffiService,
  eventBusProvider: eventBusAdapter,
  conversationManagerProvider: convAdapter,
);
```

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
```

**Advantages**:
- ✅ Rich functions (message history, polling, status management, etc.)
- ✅ Strong flexibility (can be customized)
- ✅ Easy to expand

**Details**: See [Tim2Tox](https://github.com/agentx-icu/tim2tox) [Architecture](../../third_party/tim2tox/doc/architecture/ARCHITECTURE.en.md) and [Binary Replacement](../../third_party/tim2tox/doc/architecture/BINARY_REPLACEMENT.en.md)

## Interface adapter implementation

### SharedPreferencesAdapter

**Location**: `lib/adapters/shared_prefs_adapter.dart`

**Implementation**: `ExtendedPreferencesService`

**Key methods**:

```dart
class SharedPreferencesAdapter implements ExtendedPreferencesService {
  final SharedPreferences _prefs;
  
  // basic method
  @override
  Future<String?> getString(String key) async => _prefs.getString(key);
  
  @override
  Future<void> setString(String key, String value) => 
      _prefs.setString(key, value);
  
  // Extension Methods - Group Related
  @override
  Future<String?> getGroupName(String groupId) => 
      getString('group_name_$groupId');
  
  @override
  Future<void> setGroupName(String groupId, String name) => 
      setString('group_name_$groupId', name);
  
  // Extension methods - Friends related
  @override
  Future<String?> getFriendNickname(String friendId) => 
      getString('friend_nickname_$friendId');
  
  // ... more methods
}
```

**Storage key name convention**:
- Group name: `group_name_<groupId>`
- Group avatar: `group_avatar_<groupId>`
- Friend nickname: `friend_nickname_<friendId>`
- Friend status message: `friend_status_msg_<friendId>`
- Friend avatar: `friend_avatar_path_<friendId>`
- Local friend list: `local_friends`
- Bootstrap node: `current_bootstrap_host/port/pubkey`

### AppLoggerAdapter

**Location**: `lib/adapters/logger_adapter.dart`

**Implementation**: `LoggerService`

```dart
class AppLoggerAdapter implements LoggerService {
  @override
  void log(String message) => AppLogger.log(message);
  
  @override
  void logError(String message, Object error, StackTrace stack) =>
      AppLogger.logError(message, error, stack);
  
  @override
  void logWarning(String message) => AppLogger.logWarning(message);
  
  @override
  void logDebug(String message) => AppLogger.logDebug(message);
}
```

### BootstrapNodesAdapter

**Location**: `lib/adapters/bootstrap_adapter.dart`

**Implementation**: `BootstrapService`

```dart
class BootstrapNodesAdapter implements BootstrapService {
  final SharedPreferences _prefs;
  
  @override
  Future<String?> getBootstrapHost() => 
      _prefs.getString('current_bootstrap_host');
  
  @override
  Future<int?> getBootstrapPort() => 
      Future.value(_prefs.getInt('current_bootstrap_port'));
  
  @override
  Future<String?> getBootstrapPublicKey() => 
      _prefs.getString('current_bootstrap_pubkey');
  
  @override
  Future<void> setBootstrapNode({
    required String host,
    required int port,
    required String publicKey,
  }) async {
    await _prefs.setString('current_bootstrap_host', host);
    await _prefs.setInt('current_bootstrap_port', port);
    await _prefs.setString('current_bootstrap_pubkey', publicKey);
  }
}
```

### EventBusAdapter

**Location**: `lib/adapters/event_bus_adapter.dart`

**Implementation**: `EventBusProvider`

```dart
class EventBusAdapter implements EventBusProvider {
  final FakeEventBus _eventBus;
  
  EventBusAdapter(this._eventBus);
  
  @override
  EventBus get eventBus => _eventBus;
}
```

### ConversationManagerAdapter

**Location**: `lib/adapters/conversation_manager_adapter.dart`

**Implementation**: `ConversationManagerProvider`

```dart
class ConversationManagerAdapter implements ConversationManagerProvider {
  final FakeConversationManager _conversationManager;
  
  ConversationManagerAdapter(this._conversationManager);
  
  @override
  Future<List<framework_models.FakeConversation>> getConversationList() async {
    final clientConvs = await _conversationManager.getConversationList();
    // Convert client FakeConversation to framework FakeConversation
    return clientConvs.map((conv) => framework_models.FakeConversation(
      conversationID: conv.conversationID,
      title: conv.title,
      faceUrl: conv.faceUrl,
      unreadCount: conv.unreadCount,
      isGroup: conv.isGroup,
      isPinned: conv.isPinned,
    )).toList();
  }
  
  // ... other methods
}
```

## Data adaptation layer implementation

### FakeIM - Event Bus Manager

**Location**: `lib/sdk_fake/fake_im.dart`

**Responsibilities**:
- Subscribe to `FfiChatService`'s events
- Convert tim2tox events to UIKit format
- Post event via `FakeEventBus`

**Initialization process**:

```dart
void start() {
  // Lazy initialization to ensure Tox has restored friends list
  Future.delayed(const Duration(milliseconds: 2000), () async {
    // Retry mechanism: If the friend list is empty, wait and try again
    int retries = 0;
    while (retries < maxRetries) {
      final friends = await ffi.getFriendList();
      if (friends.isNotEmpty || retries >= maxRetries - 1) {
        _refreshConversations();
        _emitContacts();
        _seedHistory();
        break;
      }
      retries++;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    // Start scheduled refresh
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshConversations();
      _emitContacts();
    });
  });
}
```

**Key methods**:

1. **`_refreshConversations()`**: Refresh the conversation list
   - Get friends list from `FfiChatService`
   - Get the last message from `FfiChatService`
   - Create `FakeConversation` object
   - Publish via event bus

2. **`_emitContacts()`**: Send contact event
   - Get friend list from `FfiChatService`
   - Create `FakeUser` object
   - Publish via event bus

3. **`_seedHistory()`**: Initialize message history
   - Get historical messages of all conversations from `FfiChatService`
   - Create `FakeMessage` object
   - Publish via event bus

### FakeConversationManager

**Location**: `lib/sdk_fake/fake_managers.dart`

**Responsibilities**:
- Manage session list
- Handle session updates
- Manage unread count

**Key methods**:

```dart
Future<List<FakeConversation>> getConversationList() async {
  final friends = await _ffi.getFriendList();
  final pinned = await Prefs.getPinned();
  _pinned = pinned;
  
  // Get pending friend requests
  final pendingApps = await _ffi.getFriendApplications();
  final pendingFriendIds = pendingApps.map((a) => a.userId).toSet();
  
  // Build conversation list
  final conversations = <FakeConversation>[];
  
  for (final friend in friends) {
    // Skip pending friend requests
    if (pendingFriendIds.contains(friend.userId)) continue;
    
    // Get the last message
    final lastMsg = _ffi.lastMessages[friend.userId];
    
    // Create session object
    final conv = FakeConversation(
      conversationID: 'c2c_${friend.userId}',
      title: friend.nickName,
      faceUrl: friend.avatarPath,
      unreadCount: 0, // Updated by FakeIM
      isGroup: false,
      isPinned: _pinned.contains('c2c_${friend.userId}'),
    );
    
    conversations.add(conv);
  }
  
  return conversations;
}
```

### FakeChatDataProvider

**Location**: `lib/sdk_fake/fake_provider.dart`

**Responsibilities**:
- Implement `ChatDataProvider` interface
- Provide session data stream
- Provide unread count stream

**Key Implementation**:

```dart
class FakeChatDataProvider implements ChatDataProvider {
  final _convCtrl = StreamController<List<V2TimConversation>>.broadcast();
  final _unreadCtrl = StreamController<int>.broadcast();
  
  FakeChatDataProvider({required FfiChatService ffiService}) {
    // Subscribe to FakeIM's session events
    FakeUIKit.instance.eventBusInstance
        .on<FakeConversation>(FakeIM.topicConversation)
        .listen((conv) {
      // Convert to V2TimConversation and emit
      _updateConversation(conv);
    });
    
    // Subscribe to unread count events
    FakeUIKit.instance.eventBusInstance
        .on<FakeUnreadTotal>(FakeIM.topicUnread)
        .listen((unread) {
      _unreadCtrl.add(unread.total);
    });
  }
  
  @override
  Stream<List<V2TimConversation>> conversationStream() => _convCtrl.stream;
  
  @override
  Stream<int> totalUnreadCountStream() => _unreadCtrl.stream;
}
```

### FakeChatMessageProvider

**Location**: `lib/sdk_fake/fake_msg_provider.dart`

**Responsibilities**:
- Implement `ChatMessageProvider` interface
- Handle message sending
- Supports multiple message types

**Key Implementation**:

```dart
class FakeChatMessageProvider implements ChatMessageProvider {
  @override
  Future<void> sendText({
    String? userID,
    String? groupID,
    required String text,
  }) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) return;
    
    if (userID != null && groupID == null) {
      // C2C messages
      await ffi.sendText(userID, text);
    } else if (groupID != null) {
      // Group message
      await ffi.sendGroupText(groupID, text);
    }
  }
  
  @override
  Future<void> sendFile({
    String? userID,
    String? groupID,
    required String filePath,
    String? fileName,
  }) async {
    // Check if friend is online (C2C only)
    if (userID != null && groupID == null) {
      final friends = await ffi.getFriendList();
      final friend = friends.firstWhere(
        (f) => compareToxIds(f.userId, userID),
        orElse: () => (userId: userID, nickName: '', online: false),
      );
      if (!friend.online) {
        throw Exception("Friend is offline. Cannot send file.");
      }
    }
    
    // Send file
    if (groupID != null) {
      await ffi.sendGroupFile(groupID, filePath);
    } else {
      await ffi.sendFile(userID!, filePath);
    }
  }
}
```

## Detailed explanation of initialization process

### Recommended initialization sequence (hybrid architecture)

**Conceptual order** (logical dependencies): `FfiChatService.init` → `login` → `updateSelfProfile` → `FakeUIKit.startWithFfi` → `TIMManager.initSDK` → `startPolling` → `HomePage` Setup `Tim2ToxSdkPlatform` → Initialize `BinaryReplacementHistoryHook`, talk bridge and plug-in.**Actual execution sequence** (consistent with the code):
1. **main()**: `setNativeLibraryName('tim2tox_ffi')`, Platform is not set.
2. **_StartupGate._decide()** (automatic login): First complete `init()`, `login()`, `updateSelfProfile()` through `AccountService.initializeServiceForAccount(..., startPolling: false)`; then execute `FakeUIKit.startWithFfi(service)` → `_initTIMManagerSDK()` → `service.startPolling()` → Wait for connection/timeout → Preload friend information → Navigate to `HomePage(service)`.
3. **HomePage.initState()**: If FakeUIKit is not started, startWithFfi; if `instance is! Tim2ToxSdkPlatform`, set Tim2ToxSdkPlatform; then initialize `CallServiceManager`; then execute `_initTIMManagerSDK().then(_initBinaryReplacementPersistenceHook)`, and then execute `initGroupListener` and `initFriendListener`.

BinaryReplacementHistoryHook is initialized in then after _initTIMManagerSDK is completed (depends on MessageHistoryPersistence, selfId; when selfId is empty, listen to connectionStatusStream and then _setupPersistenceHook). See [HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.en.md) for details.

### 1. main() function

**Location**: `lib/main.dart`

**Key Steps**: `main()` is responsible for log initialization, unified C++/Dart log files, theme and language recovery, desktop window initialization, and `setNativeLibraryName('tim2tox_ffi')`. It **does not set** `TencentCloudChatSdkPlatform.instance`. The application entrance is `EchoUIKitApp`, and the home page is `_StartupGate`.

### 2. _StartupGate._decide() (automatic login)

**Location**: `lib/main.dart` (_StartupGate status class)

**Key steps** (automatic login path):
- First check the nickname, automatic login switch and bootstrap configuration
- If an account exists, call `AccountService.initializeServiceForAccount(..., startPolling: false)` to complete `init()`, `login()`, `updateSelfProfile()`
- If it is an old account compatible path, create `FfiChatService` manually
- `FakeUIKit.instance.startWithFfi(service)` starts conversations, contacts, messages and call subsystems in advance
- Call `_initTIMManagerSDK()`
- Call `service.startPolling()`, then wait for connection or timeout
- Preload friend status and contact data after successful connection, then navigate to `HomePage`

### 3. LoginPage (when the user does not log in automatically)

**Location**: `lib/ui/login_page.dart`

When the user logs in from the login page, the existing account will take priority to `AccountService.initializeServiceForAccount(...)`, and the compatible path of the old account will be directly executed manually `init()` / `login()` / `updateSelfProfile()` / `startPolling()`. Then call `_initTIMManagerSDK()` and navigate to `HomePage`. HomePage will also set up Platform, initialize the call bridge and hook up `BinaryReplacementHistoryHook`.

### 4. HomePage.initState()

**Location**: `lib/ui/home_page.dart`

**Key Steps**:
- if `!FakeUIKit.instance.isStarted` then `FakeUIKit.startWithFfi(widget.service)`
- If `TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform`, create EventBusAdapter, ConversationManagerAdapter, and set `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(ffiService: widget.service, ...)`
- Initialize `FakeUIKit.instance.callServiceManager`, enable TUICallKit to ToxAV bridging
-`_initTIMManagerSDK().then((_) { _initBinaryReplacementPersistenceHook(); initGroupListener(); initFriendListener(); })`
- Register ChatDataProviderRegistry, ChatMessageProviderRegistry, etc.
- Complete sticker / textTranslate / soundToText plugins before and after message component registration

**_initBinaryReplacementPersistenceHook**: Obtain dependencies from `widget.service.messageHistoryPersistence` and `widget.service.selfId`; if selfId is empty, listen to `connectionStatusStream`, and then call _setupPersistenceHook after the connection is successful and selfId is not empty. Execute `BinaryReplacementHistoryHook.initialize(persistence, selfId)` in _setupPersistenceHook, and wrap the _advancedMsgListener of the current TIMMessageManager with `BinaryReplacementHistoryHook.wrapListener` to achieve automatic persistence of C++ new message callbacks.

## Message processing process

### Send text message

```
1. The user enters text in the UIKit Message component
   ↓
2. UIKit calls ChatMessageProvider.sendText()
   ↓
3. FakeChatMessageProvider.sendText()
   ↓
4. Offline detection (check whether the contact is online)
   ├─ If offline → mark as failed immediately → save to persistent storage → display failure status
   └─ If online → Continue sending process
   ↓
5. FfiChatService.sendText() / sendGroupText()
   ↓
6. tim2tox FFI export function
   ↓
7. tim2tox_ffi (C FFI)
   ↓
8. Tim2Tox (C++)
   ↓
9. toxcore
   ↓
10. Timeout detection (using Future.timeout, text message 5 seconds)
    ├─ If successful → Update message status to successful
    └─ If timeout → Mark as failed → Save to persistent storage → Update UI state
```

**Key Features**:
- **Offline Detection**: Check whether the contact is online before sending, if offline it will fail immediately
- **Timeout mechanism**: Use `Future.timeout` to implement dynamic timeout (5 seconds for text messages)
- **Persistence Storage**: Failure messages are saved to `SharedPreferences`
- **Message ID**: uniformly use `timestamp_userID` format (millisecond timestamp)

### Receive text messages

```
1. toxcore receives the message
   ↓
2. tim2tox (C++) processing messages
   ↓
3. tim2tox_ffi (C) adds the message to the event queue
   ↓
4. FfiChatService polls event queue
   ↓
5. FfiChatService parses message events
   ↓
6. [Two paths]:
   
   a. SDK Events:
      Tim2ToxSdkPlatform.onRecvNewMessage()
         ↓
      UIKit SDK Listeners
         ↓
      UI Updates
   
   b. Data Streams:
      FakeIM subscribes to FfiChatService events
         ↓
      FakeIM creates FakeMessage
         ↓
      FakeEventBus publish events
         ↓
      FakeMessageManager handles events
         ↓
      FakeChatDataProvider update data
         ↓
      UIKit Controllers update UI
```

### Failed message recovery process

```
1. Client starts/switches session
   ↓
2. Load message history (from FfiChatService)
   ↓
3. Failed to load messages from persistent storage (TencentCloudChatFailedMessagePersistence)
   ↓
4. Merge historical messages and failure messages
   ↓
5. Check the message status:
   ├─ If the message is in the failure list → mark as failed unconditionally
   └─Restore message content (such as textElem)
   ↓
6. Update message list and conversation list
   ↓
7. UI displays failure message status
```

**Key Implementation**:
- `_loadHistoryForConversation`: Check failure message persistence storage when loading history
- `_restoreFailedMessages`: restore failed message status
- `_mapConv`: Check the failure message when the session list is updated to ensure that the latest failure message is displayed in the session list

### Recursion protection mechanism

**Implementation location**: `chat-uikit-flutter/tencent_cloud_chat_common/lib/data/message/tencent_cloud_chat_message_data.dart:858-894`

In the `onReceiveNewMessage` method, when the message already exists, the SDK callback needs to be triggered to update the session's `lastMessage`. This can lead to recursive calls because:

1. `onReceiveNewMessage` is registered as the `onRecvNewMessage` callback of the SDK
2. When the message already exists, the code calls `listener.onRecvNewMessage(newMessage)`
3. This will trigger the SDK callback and call `onReceiveNewMessage` again
4. Forming infinite recursion, causing stack overflow

**Protection Mechanism**:

Use `_processingMessageIds` Set to track the message ID being processed and prevent recursion:

```dart
// Prevent recursion: skip callback if message is in progress
final messageId = newMessage.msgID ?? newMessage.id ?? '';
final messageIdAlt = newMessage.id ?? newMessage.msgID ?? '';

// Check if either ID is being processed
if (messageId.isNotEmpty && _processingMessageIds.contains(messageId)) {
  return; // Skip recursive calls
}
if (messageIdAlt.isNotEmpty && messageIdAlt != messageId && 
    _processingMessageIds.contains(messageIdAlt)) {
  return; // Skip recursive calls
}

// If both IDs are empty, recursion cannot be prevented and skipped directly.
if (messageId.isEmpty && messageIdAlt.isEmpty) {
  return;
}

try {
  // Mark message as being processed (mark both IDs if different)
  if (messageId.isNotEmpty) {
    _processingMessageIds.add(messageId);
  }
  if (messageIdAlt.isNotEmpty && messageIdAlt != messageId) {
    _processingMessageIds.add(messageIdAlt);
  }
  
  // Call SDK callback
  listener.onRecvNewMessage(newMessage);
} finally {
  // clean mark
  if (messageId.isNotEmpty) {
    _processingMessageIds.remove(messageId);
  }
  if (messageIdAlt.isNotEmpty && messageIdAlt != messageId) {
    _processingMessageIds.remove(messageIdAlt);
  }
}
```

**Key Design**:
- **Double ID Check**: Check both `msgID` and `id` fields because in some cases they may be different
- **Empty ID Protection**: If both IDs are empty, recursion cannot be prevented and the callback is skipped directly
- **finally cleanup**: ensure that even if an exception occurs, the mark will be cleaned up to avoid permanent blocking

## Event handling process

### Division of labor between C++ callbacks and FfiChatService streams

In a hybrid architecture, new messages and events come from two sources:

| Source | Purpose | Description |
|------|------|------|
| **C++ ReceiveNewMessage** | _advancedMsgListener dispatched to TIMMessageManager via NativeLibraryManager | The main entry for new messages under binary replacement; BinaryReplacementHistoryHook wraps the listener for persistence |
| **FfiChatService.messages** | stream generated by _onNativeEvent inside FfiChatService | Old-style event protocol from FfiChatService, different from C++ layer division of labor |

There is a clear division of labor between the two to avoid duplication of processing. For details, see [HYBRID_ARCHITECTURE.md - Callback process and division of labor](../architecture/HYBRID_ARCHITECTURE.en.md#4-callback-process-and-division-of-labor).

### Event Subscription

```dart
// FakeIM subscribes to FfiChatService events
void start() {
  // Subscribe to message events
  _ffi.onMessage.listen((msg) {
    final fakeMsg = FakeMessage(
      msgID: msg.msgID,
      conversationID: msg.conversationID,
      fromUser: msg.fromUserId,
      text: msg.text,
      timestampMs: msg.timestamp.millisecondsSinceEpoch,
    );
    _bus.emit(FakeIM.topicMessage, fakeMsg);
  });
  
  // Subscribe to friend status events
  _ffi.onFriendStatusChanged.listen((status) {
    // Update friend status
    _emitContacts();
  });
}
```

### Event release

```dart
// FakeEventBus publish events
class FakeEventBus implements EventBus {
  final Map<String, StreamController> _controllers = {};
  
  @override
  Stream<T> on<T>(String topic) {
    _controllers[topic] ??= StreamController<T>.broadcast();
    return _controllers[topic]!.stream.cast<T>();
  }
  
  @override
  void emit<T>(String topic, T event) {
    _controllers[topic]?.add(event);
  }
}
```

### Event consumption

```dart
// FakeConversationManager subscribes to session events
void start() {
  _convSub = _bus.on<FakeConversation>(FakeIM.topicConversation).listen((c) {
    for (final l in _listeners) {
      l.onNewConversation?.call([c]);
      l.onConversationChanged?.call([c]);
    }
  });
}
```

## File transfer implementation

### Send file

```dart
// FakeChatMessageProvider.sendFile()
Future<void> sendFile({
  String? userID,
  String? groupID,
  required String filePath,
  String? fileName,
}) async {
  final conv = groupID != null ? 'group_$groupID' : 'c2c_$userID';
  final mgr = FakeUIKit.instance.messageManager;
  if (mgr == null) return;

  // The current Tox group layer does not support file/image/video transfer,
  // so group media must fail fast.
  if (groupID != null && groupID.isNotEmpty) {
    throw StateError('Group file transfer is not supported in toxee');
  }

  // C2C offline files are handled by FfiChatService.sendFile: offline sends
  // are persisted to offline_message_queue.json, shown as pending bubbles,
  // and replayed by the drain logic when the friend comes online.
  await mgr.sendFile(conv, filePath);
}
```

The custom image/video picker in HomePage also delegates directly to `widget.service.sendFile(userId, pickedPath)`. The UI layer no longer pre-checks `getFriendList()` for offline status, which prevents valid offline media sends from being surfaced as immediate failures instead of queued transfers.

### Receive files

The file receiving process involves multiple levels and events. The following is the complete implementation:

#### 1. C++ layer event generation (`tim2tox/ffi/tim2tox_ffi.cpp`)

**`OnFileRecv` callback** (file transfer request):
```cpp
ToxManager::getInstance().setFileRecvCallback([](uint32_t friend_number, uint32_t file_number, uint32_t kind, uint64_t file_size, const uint8_t* filename, size_t filename_length) {
    // Send file_request event to polling queue
    // Format: file_request:<uid>:<file_number>:<size>:<kind>:<filename>
    // kind: 0=DATA, 1=AVATAR
    snprintf(line, sizeof(line), "file_request:%s:%u:%llu:%u:%s", 
             sender_hex.c_str(), file_number, file_size, kind, name.c_str());
    G.simple_listener.enqueue_text_line(line);
});
```

**`OnRecvFileData` callback** (file data reception):
```cpp
ToxManager::getInstance().setFileRecvChunkCallback([](uint32_t friend_number, uint32_t file_number, uint64_t position, const uint8_t* data, size_t length) {
    // Write file data
    fwrite(data, 1, length, fp);
    fflush(fp);
    
    // Send progress update event
    // Format: progress_recv:<uid>:<received>:<total>:<path>
    if (length > 0) {
        snprintf(line, sizeof(line), "progress_recv:%s:%llu:%llu:%s", 
                 sender_hex.c_str(), received, total, path.c_str());
        G.simple_listener.enqueue_text_line(line);
    }
    
    // When the file is complete (length == 0)
    if (length == 0) {
        // Send file_done event
        // Format: file_done:<uid>:<kind>:<path>
        snprintf(line, sizeof(line), "file_done:%s:%u:%s", 
                 sender_hex.c_str(), file_kind, full.c_str());
        G.simple_listener.enqueue_text_line(line);
    }
});
```

#### 2. Dart layer event processing (`tim2tox/dart/lib/service/ffi_chat_service.dart`)

**Polling receiving event**:
```dart
// Event handling loop in startPolling()
_poller = Timer(pollInterval, () {
  final n = _ffi.pollText(buf, 4096);
  if (n > 0) {
    final s = buf.cast<pkgffi.Utf8>().toDartString();
    
    if (s.startsWith('file_request:')) {
      // Handle file transfer requests
      _handleFileRequest(s);
    } else if (s.startsWith('progress_recv:')) {
      // Handle receiving progress updates
      _handleProgressRecv(s);
    } else if (s.startsWith('file_done:')) {
      // Processing file reception completed
      _handleFileDone(s);
    }
  }
  scheduleNextPoll();
});
```

**`file_request` event handling**:
```dart
// Format: file_request:<uid>:<file_number>:<size>:<kind>:<filename>
if (s.startsWith('file_request:')) {
  final parts = s.split(':');
  final uid = parts[1];
  final fileNumber = int.tryParse(parts[2]) ?? 0;
  final fileSize = int.tryParse(parts[3]) ?? 0;
  final fileKind = int.tryParse(parts[4]) ?? 0;
  final fileName = parts.sublist(5).join(':');
  
  // 1. Create pending message (only non-avatar files, kind == 0)
  if (fileKind == 0) {
    // Use unified message ID format: timestamp_userID (consistent with other messages)
    final normalizedUid = uid.length > 64 ? _normalizeFriendId(uid) : uid;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final msgID = '${timestamp}_$normalizedUid';
    final tempPath = '/tmp/receiving_$fileName';
    final msg = ChatMessage(
      msgID: msgID,
      fromUserId: uid,
      filePath: tempPath,
      fileName: fileName,
      isPending: true, // Mark as receiving
    );
    
    // 2. Track file transfer progress
    _fileReceiveProgress[(uid, fileNumber)] = (
      received: 0,
      total: fileSize,
      msgID: msgID,
      fileName: fileName,
      tempPath: tempPath,
      actualPath: null,
    );
    
    // 3. Add to history and message flow
    _appendHistory(uid, msg);
    _messages.add(msg);
  }
  
  // 4. Automatically accept file transfers
  final isImage = _detectKind(fileName) == 'image';
  if (fileKind == 1 || isImage || fileSize < autoAcceptThreshold) {
    await acceptFileTransfer(uid, fileNumber);
  }
}
```

**`progress_recv` event handling**:
```dart
// Format: progress_recv:<uid>:<received>:<total>:<path>
if (s.startsWith('progress_recv:')) {
  final parts = s.split(':');
  final uid = parts[1];
  final received = int.tryParse(parts[2]) ?? 0;
  final total = int.tryParse(parts[3]) ?? 0;
  final path = parts.sublist(4).join(':');
  
  // 1. Update progress flow (for use by FakeChatMessageProvider)
  _progressCtrl.add((peerId: uid, path: path, received: received, total: total, isSend: false));
  
  // 2. Update file reception progress tracking
  String? foundMsgID;
  int? foundFileNumber;
  for (final entry in _fileReceiveProgress.entries) {
    if (entry.key.$1 == uid && (entry.value.actualPath == path || entry.value.tempPath == path)) {
      _fileReceiveProgress[entry.key] = (
        received: received,
        total: total,
        msgID: entry.value.msgID,
        fileName: entry.value.fileName,
        tempPath: entry.value.tempPath,
        actualPath: path, // Update actual path
      );
      foundMsgID = entry.value.msgID;
      foundFileNumber = entry.key.$2;
      break;
    }
  }
  
  // 3. If the file transfer is completed (received >= total), call _handleFileDone directly
  // This eliminates the need to wait for the file_done event and can update the message status faster
  if (total > 0 && received >= total && path.isNotEmpty && path.startsWith('/')) {
    await _handleFileDone(uid, 0, path, foundFileNumber, foundMsgID);
  }
}
```

**`file_done` event handling**:
```dart
// Format: file_done:<uid>:<kind>:<path>
if (s.startsWith('file_done:')) {
  final parts = s.split(':');
  final uid = parts[1];
  final fileKind = int.tryParse(parts[2]) ?? 0;
  final path = parts.sublist(3).join(':');
  
  if (fileKind == 0) {
    // Call the unified file completion processing function
    // If the path is empty or invalid, an attempt will be made to find the full path from _fileReceiveProgress
    await _handleFileDone(uid, fileKind, path, null, null);
  }
}

// _handleFileDone handles file completion logic in a unified manner
Future<void> _handleFileDone(String uid, int fileKind, String path, 
    int? fileNumber, String? existingMsgID) async {
  // 1. If the path is invalid, try to find it from _fileReceiveProgress
  if (path.isEmpty || !path.startsWith('/')) {
    // ... logic to find full path from _fileReceiveProgress ...
  }
  
  // 2. If existingMsgID is empty, try to find or create a message through the fallback mechanism
  if (existingMsgID == null) {
    // Fallback: Find recent pending file messages
    // If not found, create a new message (handles the case where the file_request event is not received)
    // ... fallback logic ...
  }
  
  // 3. Move the file to its final location (use _extractFileNameFromPath to extract the original file name)
  final fileName = _extractFileNameFromPath(path);
  final kind = _detectKind(fileName);
  String finalPath;
  if (kind == 'image') {
    finalPath = await _moveImageToAvatarsDir(path, fileName);
  } else {
    finalPath = await _moveFileToDownloads(path, fileName);
  }
  
  // 4. Update message path and status
  // ... update logic ...
}
```

#### 3. FakeChatMessageProvider progress update (`toxee/lib/sdk_fake/fake_msg_provider.dart`)

**Subscription Progress Update**:
```dart
// Subscribe to progressUpdates stream in constructor
ffi.progressUpdates.listen((progress) {
  if (!progress.isSend && progress.path != null) {
    // Find the corresponding message (match by path, filename or msgID)
    for (final entry in _buffers.entries) {
      for (final msg in entry.value) {
        final isFileMatch = msg.fileElem != null && (
          msg.fileElem!.path == progress.path ||
          msg.fileElem!.path?.startsWith('/tmp/receiving_') == true ||
          msg.msgID?.startsWith('file_recv_') == true ||
          // ... file name matching logic ...
        );
        final isImageMatch = msg.imageElem != null && (
          // ... Similar matching logic ...
        );
        
        if (isFileMatch || isImageMatch) {
          // 1. Update progress tracking
          _fileProgress[msg.msgID] = (
            received: progress.received,
            total: progress.total,
            path: progress.path,
          );
          
          // 2. Update message elements
          if (msg.fileElem != null) {
            msg.fileElem = V2TimFileElem(
              path: progress.path,
              localUrl: (progress.received >= progress.total) ? progress.path : null,
            );
          }
          
          if (msg.imageElem != null) {
            // Create imageList and set localUrl
            final imageList = <V2TimImage?>[];
            if (progress.received >= progress.total && progress.path != null) {
              final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
              thumbImage.localUrl = progress.path;
              imageList.add(thumbImage);
              // ... add original image ...
            }
            msg.imageElem = V2TimImageElem(
              path: progress.path,
              imageList: imageList.isNotEmpty ? imageList : null,
            );
          }
          
          // 3. Notify UI updates
          _ctrls[convID]?.add([msg]);
        }
      }
    }
  }
});
```

#### 4. Complete flow chart

```
Sender sends file
  ↓
toxcore file transfer protocol
  ↓
Receiver C++ layer (tim2tox_ffi.cpp)
  ├─ OnFileRecv callback
  │ └─ Send file_request event to polling queue
  │
  ├─ acceptFileTransfer (Dart calls fileControlNative)
  │ └─ Accept file transfer and start receiving data
  │
  ├─ OnRecvFileData callback (each data block)
  │ ├─ Write file data
  │ └─ Send progress_recv event to polling queue
  │
  └─ OnRecvFileData callback (length == 0, file completed)
      └─ Send file_done event to polling queue
  ↓
Dart layer Polling (tim2tox/dart/lib/service/ffi_chat_service.dart)
  ├─ Receive file_request event
  │ ├─ Create pending message (msgID: timestamp_userID, unified format)
  │ ├─ Set temporary path (/tmp/receiving_<filename>)
  │ ├─ Track file transfer progress
  │ └─ Automatically accept file transfers (if images or small files)
  │
  ├─Receive progress_recv event
  │ ├─ Update _fileReceiveProgress
  │ ├─ Send to _progressCtrl stream
  │ └─ If received >= total, call _handleFileDone directly (without waiting for the file_done event)
  │
  └─ Receive file_done event
      ├─Call _handleFileDone for unified processing
      ├─ Fallback: If the message does not exist, find or create a pending message
      ├─ Move files to final location (avatars or Downloads)
      └─ Update message path and status
  ↓
FakeChatMessageProvider (fake_msg_provider.dart)
  ├─ Subscribe to progressUpdates stream
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

#### 5. Key implementation details

**Message ID format**:
- File receiving message: `timestamp_userID` (unified format with other messages)
- For example: `1765459900999_10F189D746EF383F1A731AFDBE72FCA99289E817721D5F25C1C67D8B351E034F`
- Ensure uniqueness and traceability and simplify message matching logic

**Path Management**:
- Temporary path: `/tmp/receiving_<filename>` (receiving)
- Final path:
  - Picture: `<appDir>/avatars/<basename>_<timestamp><ext>`
  - Other files: `<Downloads>/<filename>`

**Progress Tracking**:
- `_fileReceiveProgress`: Track file reception progress (`(uid, fileNumber)` → progress information)
- `_fileProgress` (FakeChatMessageProvider): Track message progress (`msgID` → progress information)

**Auto-Accept Policy**:
- Avatar file (kind == 1): automatically accepted
- Image files: automatically accepted
- Small files (< user-configured threshold, default 30MB): automatically accepted
- Large files: require manual acceptance by the user (via UIKit's download button)

**Message matching logic**:
- Matches via `fileNumber` and `uid` (most accurate)
- Match by file name and file size (fallback solution)
- Match by path (temporary path or final path)
- Use the `_extractFileNameFromPath` helper function to extract raw filenames from ID-prefixed paths
  - Supported format: `ID_fileNumber_chunkSize_originalFileName`
  - Automatically remove ID prefix and extract original file name for matching

#### 6. Adaptive Polling mechanism

**Implementation location**: `tim2tox/dart/lib/service/ffi_chat_service.dart` (adaptive polling mechanism)

In order to optimize file transfer performance and reduce CPU usage, an adaptive polling interval mechanism is implemented:

- **File transfer period**: 50ms (very frequent to ensure timely processing of events)
  - Triggered when `_fileReceiveProgress` or `_pendingFileTransfers` is not empty
- **Activity period**: 200ms (there is activity in the last 2 seconds)
  - Used to handle other real-time events
- **Idle period**: 1000ms (default interval, reduces CPU usage)
  - Used when there is no activity

This mechanism ensures the timeliness of file transfers while reducing resource consumption when files are not being transferred.

#### 7. File reception failure processing

**Implementation location**: `tim2tox/dart/lib/service/ffi_chat_service.dart` (File reception failure processing)

When the client exits or restarts, there may be unfinished file reception (pending status). `_cancelPendingFileTransfers` method will:

1. **Traverse all historical messages** and find pending received file messages
2. **Mark as failed** (`isPending=false`) instead of deleting, keep the message record
3. **Clean tracking data**: Clear `_fileReceiveProgress`, `_pendingFileTransfers` and `_msgIDToFileTransfer`
4. **Save the updated history** to ensure that the loading status will not continue to be displayed after restarting

This prevents the UI from always showing circles while retaining a record of failed file messages.

#### 8. Fallback mechanism

**Implementation location**: `tim2tox/dart/lib/service/ffi_chat_service.dart` (Fallback mechanism)

If the `file_request` event is not received (perhaps due to polling delay or other reasons), a fallback mechanism is implemented in the `file_done` event handling:

1. **Find recent pending messages**: By checking `isPending=true` and `filePath` start with `/tmp/receiving_`
2. **Update existing message**: If a matching pending message is found, update its path and status
3. **Create new message**: If not found, create a new message record (to handle the situation where `file_request` is completely missed)

This ensures that even if the `file_request` event is lost, file reception still completes normally.

#### 9. Known issues and limitations

**Question 1: File path update timing**
- **Phenomenon**: `file_done` event processing is asynchronous, file movement may take time
- **Impact**: The UI may try to access the file before the file move is completed, causing display failure
- **Mitigation**: `progress_recv` directly calls `_handleFileDone` on completion to reduce delays

**Issue 2: File transfer timeout**
- **Phenomena**: If the file transfer process is interrupted or times out, the message may remain pending.
- **Impact**: UI will always display loading status
- **Mitigation**: Marked as failed via `_cancelPendingFileTransfers` after client restart

**Limitation 3: Group media/file transfer**
- **Phenomenon**: The current Tox group/conference layer has no usable file-transfer channel.
- **Impact**: Group images, videos, and files do not enter the pending queue.
- **Mitigation**: `FakeChatMessageProvider.sendImage/sendFile` fail fast when `groupID` is present, preventing the UI from keeping a send bubble that can never complete.

## Friends management implementation

### Add friends

```dart
// Tim2ToxSdkPlatform.addFriend()
@override
Future<V2TimFriendOperationResult> addFriend({
  required String userID,
  String? remark,
  String? wording,
}) async {
  // Call FfiChatService
  final result = await ffiService.addFriend(
    userId: userID,
    message: wording ?? 'Hello',
  );
  
  if (result) {
    return V2TimFriendOperationResult(
      resultCode: 0,
      resultInfo: 'success',
      userID: userID,
    );
  } else {
    return V2TimFriendOperationResult(
      resultCode: -1,
      resultInfo: 'failed',
      userID: userID,
    );
  }
}
```

### Accept friend request

```dart
// Tim2ToxSdkPlatform.acceptFriendApplication()
@override
Future<V2TimFriendOperationResult> acceptFriendApplication({
  required V2TimFriendApplication application,
}) async {
  await ffiService.acceptFriendRequest(application.userID);

  // Send friend-added event
  _notifyFriendListAdded([application.userID]);

  return V2TimFriendOperationResult(
    resultCode: 0,
    resultInfo: 'success',
    userID: application.userID,
  );
}
```

Friend applications that the user dismisses are tracked with `<userId>|<wording>` fingerprints so repeated wording can be hidden. Accepting a request must first succeed through FFI `acceptFriendRequest`; only then are all dismissed fingerprints for that `userId` cleared, so a future application from the same contact, or a changed wording, is not blocked by stale dismissal state.

## Group management implementation

### Create a group

```dart
// Tim2ToxSdkPlatform.createGroup()
@override
Future<V2TimGroupInfoResult> createGroup({
  required String groupType,
  required String groupName,
  List<String>? memberList,
}) async {
  // Call FfiChatService
  final groupID = await ffiService.createGroup(groupName);
  
  if (groupID != null) {
    // Create group information
    final groupInfo = V2TimGroupInfo(
      groupID: groupID,
      groupName: groupName,
      groupType: GroupType.Work,
    );
    
    // Save group name to preferences
    await _prefs?.setGroupName(groupID, groupName);
    
    return V2TimGroupInfoResult(
      resultCode: 0,
      resultInfo: 'success',
      groupInfo: groupInfo,
    );
  } else {
    return V2TimGroupInfoResult(
      resultCode: -1,
      resultInfo: 'failed',
    );
  }
}
```

### Get group list

```dart
// Tim2ToxSdkPlatform.getGroupList()
@override
Future<V2TimGroupInfoResult> getGroupList() async {
  final groups = ffiService.knownGroups;
  final groupInfoList = <V2TimGroupInfo>[];
  
  for (final groupID in groups) {
    // Get group name and avatar from preferences
    final groupName = await _prefs?.getGroupName(groupID);
    final groupAvatar = await _prefs?.getGroupAvatar(groupID);
    
    final groupInfo = V2TimGroupInfo(
      groupID: groupID,
      groupType: GroupType.Work,
      groupName: groupName ?? groupID,
      faceUrl: groupAvatar,
    );
    
    groupInfoList.add(groupInfo);
  }
  
  return V2TimGroupInfoResult(
    resultCode: 0,
    resultInfo: 'success',
    groupInfoList: groupInfoList,
  );
}
```

## Message failure handling

### Timeout mechanism

**Implementation location**: `chat-uikit-flutter/tencent_cloud_chat_message/lib/model/tencent_cloud_chat_message_data_tools.dart`

**Timeout**:
- Text message: 5 seconds
- File message: dynamically calculated based on file size (base 60 seconds + file size/100KB/s, maximum 300 seconds)

**Implementation**:
```dart
final timeoutSeconds = TencentCloudChatFailedMessagePersistence.getTimeoutSeconds(messageInfo);
final sendMsgRes = await sendMessageFuture.timeout(
  Duration(seconds: timeoutSeconds),
  onTimeout: () => V2TimValueCallback(code: -1, desc: 'Message send timeout', data: messageInfo),
);
```

### Offline detection

**Implementation location**:
- `chat-uikit-flutter/tencent_cloud_chat_message/lib/model/tencent_cloud_chat_message_separate_data.dart`
- `toxee/lib/sdk_fake/fake_msg_provider.dart`**Detection logic**:
- Check if the contact is online before sending
- If offline, mark as failed immediately without waiting for timeout
- Works with all message types

### Persistent storage

**Implementation location**: `chat-uikit-flutter/tencent_cloud_chat_common/lib/utils/tencent_cloud_chat_failed_message_persistence.dart`

**Storage method**:
- Use `SharedPreferences` to store failure messages
- List of failed messages organized by session (`conversationKey`)
- Save complete information of the message (ID, content, timestamp, etc.)

### Status recovery

**Recovery time**:
1. When the client starts
2. When loading message history
3. When switching sessions

**Restore logic**:
- Loading failure message from persistent storage
- Add failure message to message list
- Mark message status as `V2TIM_MSG_STATUS_SEND_FAIL`
- Recover message content (such as `textElem`)
- `lastMessage` who updated the conversation list

## Message ID management

### Unified format

All message IDs use `timestamp_userID` format (millisecond timestamps):

**Format**: `<timestamp>_<userID>`

**Example**: `1766503112612_1F583DEE2E26AFAF21825AA24D16C55487C9151A267C8FE34B47151B1A784F3D50425B616B2B`

### ID generation

1. **Tim2ToxSdkPlatform**: Use `ffiService.selfId` to generate messages when creating messages
2. **setAdditionalInfoForMessage**: Ensure that all message IDs use a unified format, replace `created_temp_id` and `unknown`

## Persistent storage

### Overview

toxee uses two main methods of persistent storage:

1. **SharedPreferences**: used to store configuration, cache and metadata
2. **File System**: used to store Tox configuration files, chat records, avatars and download files

### Storage location

```
<Application Support Directory>/
├── tim2tox/
│ └── tox_profile_<toxId>.tox # Tox configuration file (one for each account)
├── chat_history/
│ └── <conversationId>.json # Chat records (one file per conversation)
├── offline_message_queue.json # Offline message queue
├── avatars/ # Avatar file directory
│ ├── self_avatar<ext> # Self avatar
│ └── <basename>_<timestamp><ext> # Friend avatar
└── file_recv/ # Temporary file receiving directory (used by C++ layer)
```

**Application Support Contents path example**:
- **macOS**: `~/Library/Application Support/com.example.toxee/`
- **Windows**: `%APPDATA%\com.example.toxee\`
- **Linux**: `~/.local/share/com.example.toxee/`

### Unified persistence solution

**Important update**: Unified persistence logic has been implemented. The Platform interface solution and binary replacement solution now use the same persistence code (`MessageHistoryPersistence`, `OfflineMessageQueuePersistence`), and the data format is completely consistent.

#### Message history persistence

**Storage location**:
- Catalog: `<Application Support Directory>/chat_history/`
- File naming: `<conversationId>.json` (illegal characters in conversationId will be replaced by `_`)

**Storage format**:
```json
{
  "conversationId": "10F189D746EF383F1A731AFDBE72FCA99289E817721D5F25C1C67D8B351E034F",
  "messages": [
    {
      "text": "Message content",
      "fromUserId": "Sender ID",
      "isSelf": true,
      "timestamp": "2024-01-01T12:00:00.000Z",
      "groupId": null,
      "filePath": "/path/to/file",
      "fileName": "filename.ext",
      "mediaKind": "image",
      "isPending": false,
      "isReceived": true,
      "isRead": true,
      "msgID": "1765459900999_10F189D746EF383F1A731AFDBE72FCA99289E817721D5F25C1C67D8B351E034F"
    }
  ]
}
```

**Persistence trigger timing**:
- When receiving new messages (`c2c:` event)
- When receiving group messages (`gtext:` event)
- When the message is sent successfully
- When file reception is completed
- When the message status is updated (for example, `isPending` changes from `true` to `false`)

**Memory Management**:
- Limit retention of up to 1000 messages in memory
- Automatically delete oldest messages when limit is exceeded
- Asynchronous saving, does not block the current operation

**Loaded on initialization**:
- When the application starts, `FfiChatService.init()` will call `_loadAllHistories()`
- Scan all `.json` files in the `chat_history` directory
- Load and restore into `_historyById` memory map one by one
- When loading, all historical messages of `isPending=true` will be marked as `isPending=false` (to prevent repeated sending after restarting)

#### Persistence of binary replacement solution

**Implementation**:
- `BinaryReplacementHistoryHook`: wrapper `V2TimAdvancedMsgListener`, automatically save received messages
- `BinaryMessageManagerWrapper`: Optional wrapper class that intercepts historical queries and reads from the persistence service
- Use the same persistence service and data format

**Key code location**:
-`tim2tox/dart/lib/utils/binary_replacement_history_hook.dart`
- `tim2tox/dart/lib/utils/message_history_persistence.dart`

#### Persistence of Platform interface solution

**Implementation**:
- `FfiChatService` uses persistence service directly
- Automatically save messages as they are received and sent
- Use the same persistence service and data format

**Key code location**:
- `tim2tox/dart/lib/service/ffi_chat_service.dart`
-`tim2tox/dart/lib/utils/message_history_persistence.dart`

### Tox configuration storage

**Storage location**:
- Path: `<Application Support Directory>/tim2tox/tox_profile_<toxId>.tox`

**File Format**:
- Binary .tox format (compatible with qTox)
- Contains the complete status of the Tox instance (key pair, friend list, group information, DHT node information, etc.)

**Encryption Support**:
- Supports password encryption (using Tox standard encryption)
- Encrypted size: original size + 80 bytes

### SharedPreferences storage content

**Group related**:
- `known_groups`: List of known group IDs
- `quit_groups`: Exited from group ID list
- `group_chat_id_<groupId>`: group chat_id
- `group_name_<groupId>`: Group name
- `group_avatar_<groupId>`: Group avatar path
- `group_type_<groupId>`: Group type ("group" or "conference")

**Friend related**:
- `friend_nickname_<friendId>`: Friend’s nickname
- `friend_status_msg_<friendId>`: Friend status message

**Account related**:
- `accounts`: Account list
- `current_account`: Current account ID

**Other**:
- `self_nickname`: own nickname
- `self_status_msg`: own status message
- `self_avatar_path`: Your own avatar path

### Data cleaning and migration

**Cleaning time**:
- When exiting the group: Delete the corresponding history files and offline message queue
- When deleting a session: Delete the corresponding history file
- When switching accounts: clear the data of the old account (optional)

**Migration Support**:
- The data formats of the two solutions are completely consistent and can be read from each other
- Seamless data migration when switching plans

## Account and session lifecycle

### Responsibilities of AccountService

`AccountService` is now a unified entrance to the account lifecycle, covering:

- Account initialization: parse account directory, restore profile, create `FfiChatService`
- Session startup: execute `init()`, `login()`, `updateSelfProfile()`, and decide whether to `startPolling()` immediately as needed
- Session destruction: destroy `FakeUIKit`, `Tim2ToxSdkPlatform`, Provider registry, IRC cache and `FfiChatService` in order
- Account switching and exit: ensure that the static status and listener of the old account are cleared to avoid cross-account data cross-talk

Automatic login, manual login, and account switching are no longer three independent sets of initialization logic, but share `AccountService`, with only differences in "whether to delay startPolling" and "whether to wait for the connection to complete."

### Account storage model

Each account has an independent directory and running resources:

- `tox_profile.tox`: account profile
- `chat_history/`: Contents of historical messages isolated by account
- `offline_message_queue.json`: offline queue
- `avatars/`: Avatar cache
- `file_recv/`: file receiving directory

The automatic login path uses `startPolling: false`. The purpose is to let `_StartupGate` control the connection waiting, friend preloading and first screen jump timing.

Full `.zip` backups carry the profile, history, offline queue, avatar directory, and `metadata.json`. Avatar paths are rewritten to `@account_data/...` during export and mapped back to the current machine's account directory during import. Import preflights `chat_history/` and `avatars/` entries and rejects escaping paths, Windows drive prefixes, and backslash paths, preventing malicious archives from writing outside the account directory or leaving partially restored profile data.

## Calling and expansion capabilities

### Call systemThe client call link consists of three layers:

- `FakeUIKit.startWithFfi()`: Create `CallStateNotifier` and `CallServiceManager`
- `HomePage.initState()`: Call `callServiceManager.initialize()` after `Tim2ToxSdkPlatform` is set up
- `CallServiceManager`: Concatenate `ToxAVService`, `CallBridgeService`, `TUICallKitAdapter` with TUICore registration

Currently two call paths are supported:

- **Signaling path**: UIKit initiates a call → `TUICallKitAdapter` creates invite → `CallBridgeService` handles acceptance/rejection/timeout → `ToxAVService` creates media stream
- **Native ToxAV path**: Directly receive external ToxAV calls from qTox and other external ToxAV calls, use the inviteID in the form of `native_av_<friendNumber>` to map to the UI layer

When the call ends, `FakeUIKit` will write the call record into the `FfiChatService` history, and simultaneously inject the event bus and UIKit messageData to ensure that both the history and the current session can see the call record.

### Plug-ins and extensions

HomePage is also responsible for access to extended capabilities:

- `sticker`: Give priority to synchronously accessing the message component before registering it; if `selfId` is not ready yet, it will be registered after the connection is successful.
- `textTranslate` / `soundToText`: lazy registration
- `LanBootstrapServiceManager`: Local Bootstrap service management on desktop
- `IrcAppManager`: IRC dynamic library loading, channel and group mapping, automatic reconnection entrance

See [CALLING_AND_EXTENSIONS.md](CALLING_AND_EXTENSIONS.en.md) for a more complete link description.

## Tim2tox interface compatibility and regression verification

### Interface differences with auto_tests

toxee uses **single instance** (instance_id=0), while `tim2tox/auto_tests` uses **multiple instances**. The following interfaces are dedicated to auto_tests and do not need to be used by toxee:

- `FfiChatService.registerInstanceForPolling(instanceId)`: Multi-node polling registration
- `runWithInstanceAsync`/`runWithInstance`: multi-instance context switching
- `createTestInstance` / `destroyTestInstance`: test instance creation and destruction

The interfaces used directly by toxee (`getFriendList`, `getFriendApplications`, `startPolling`, `knownGroups`, etc.) are compatible with the current implementation of tim2tox. `getFriendApplications()` uses `getFriendApplicationsForInstance(0, ...)` internally and behaves correctly in a single instance.

Callback Future bridging uses `NativeLibraryManager.addTimCallback2Map(...)` and `addTimValueCallback2Map(...)`. These names match the SDK API produced by the current bootstrap flow; avoid the older `timCallback2Future` / `timValueCallback2Future` names because they can break analyzer or runtime compatibility when switching between SDK 8.8 and 8.9 layouts.

### Regression verification checklist

After the tim2tox interface is updated, it is recommended to verify the following scenarios:

| Scenario | Verification items | Description |
|------|--------|------|
| **Friend application list** | Pending applications are displayed correctly | Use `FfiChatService.getFriendApplications()` to confirm that instance_id=0 returns correctly |
| **Session list update** | Session list refresh after sending/receiving message | Rely on `onConversationChanged` notification of Tim2ToxSdkPlatform |
| **File transfer** | Send, receive, progress, cancel | Depend on `startPolling()` to consume file_request, which has been explicitly called in main.dart |

After running the application, verify in sequence: add friend application → accept/reject → conversation list; send C2C message → stick conversation to top; send/receive files → progress display and cancellation.

## Summary

The implementation of toxee shows how to:

1. **Connect Tim2Tox and the client through adapter mode**
2. **Use event bus** for inter-component communication
3. **Implement dual data paths** (SDK Events + Data Streams)
4. **Process various message types** (text, pictures, files, etc.)
5. **Manage friends and groups**
6. **Implement a complete failure message processing mechanism** (offline detection, timeout detection, persistent storage, state recovery)
7. **Unified Message ID Format** (`timestamp_userID`)

Key implementation points:
- All client dependencies are injected through the interface
- Adapter maps Tim2Tox interface to concrete implementation
- Event bus decoupling components
- Lazy initialization ensures correct initialization sequence
- Failure message persistence ensures that status is not lost
- Unified message ID format ensures correct message matching

For details, please refer to the "Failed Message Recovery Process" section of this article and [TROUBLESHOOTING.md](../TROUBLESHOOTING.en.md) to learn how to handle and troubleshoot failed messages.
