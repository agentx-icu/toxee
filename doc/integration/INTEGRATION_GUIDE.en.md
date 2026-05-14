# toxee Integration Guide
> Language: [Chinese](INTEGRATION_GUIDE.md) | [English](INTEGRATION_GUIDE.en.md)


This document explains how to integrate [Tim2Tox](https://github.com/anonymoussoft/tim2tox) into a Flutter application, including interface adapter implementation, initialization process, and best practices.

## Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Interface Adapter Implementation](#interface-adapter-implementation)
- [Initialization process](#initialization-process)
- [Usage example](#usage-example)
- [Best Practice](#best-practices)

## Overview

toxee shows how to integrate [Tim2Tox](https://github.com/anonymoussoft/tim2tox) into a Flutter app. The integration process includes:

1. **Implement interface adapter**: Map the abstract interface of Tim2Tox to the specific implementation of the client
2. **Initialization Service**: Create and initialize FfiChatService
3. **Set up SDK Platform**: Route UIKit SDK calls to tim2tox
4. **Use UIKit components**: Use Tencent Cloud Chat UIKit components normally

## Quick Start

### Minimal integration example

```dart
import 'package:tim2tox_dart/tim2tox_dart.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. Create an interface adapter
final prefs = await SharedPreferences.getInstance();
final prefsAdapter = SharedPreferencesAdapter(prefs);
final loggerAdapter = AppLoggerAdapter();
final bootstrapAdapter = BootstrapNodesAdapter(prefs);

// 2. Create a service
final ffiService = FfiChatService(
  preferencesService: prefsAdapter,
  loggerService: loggerAdapter,
  bootstrapService: bootstrapAdapter,
);

// 3. Initialize service
await ffiService.init();

// 4. Set up SDK Platform
TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
  ffiService: ffiService,
);

// 5. Use UIKit
// The Tencent Cloud Chat UIKit component can now be used normally
```

## Interface adapter implementation

Tim2Tox injects client dependencies through interfaces, and the client needs to implement the following interface adapter.

### Required interface

#### ExtendedPreferencesService

Preferences service for persisting data.

**Implementation example** (`lib/adapters/shared_prefs_adapter.dart`):

```dart
import 'package:tim2tox_dart/interfaces/extended_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesAdapter implements ExtendedPreferencesService {
  final SharedPreferences _prefs;
  
  SharedPreferencesAdapter(this._prefs);
  
  @override
  Future<String?> getString(String key) async => _prefs.getString(key);
  
  @override
  Future<bool> setString(String key, String value) async => 
      await _prefs.setString(key, value);
  
  @override
  Future<int?> getInt(String key) async => _prefs.getInt(key);
  
  @override
  Future<bool> setInt(String key, int value) async => 
      await _prefs.setInt(key, value);
  
  @override
  Future<bool?> getBool(String key) async => _prefs.getBool(key);
  
  @override
  Future<bool> setBool(String key, bool value) async => 
      await _prefs.setBool(key, value);
  
  @override
  Future<List<String>?> getStringList(String key) async => 
      _prefs.getStringList(key);
  
  @override
  Future<bool> setStringList(String key, List<String> value) async => 
      await _prefs.setStringList(key, value);
  
  @override
  Future<bool> remove(String key) async => await _prefs.remove(key);
  
  @override
  Future<bool> clear() async => await _prefs.clear();
}
```

#### LoggerService

Log service, used to output logs.

**Implementation Example** (`lib/adapters/logger_adapter.dart`):

```dart
import 'package:tim2tox_dart/interfaces/logger_service.dart';
import 'package:toxee/util/logger.dart';

class AppLoggerAdapter implements LoggerService {
  @override
  void log(String message) {
    AppLogger.info(message);
  }
  
  @override
  void logError(String message, Object error, StackTrace stack) {
    AppLogger.logError(message, error, stack);
  }
  
  @override
  void logWarning(String message) {
    AppLogger.warn(message);
  }
  
  @override
  void logDebug(String message) {
    AppLogger.debug(message);
  }
}
```

#### BootstrapService

Bootstrap node service for Tox network connection.

**Implementation example** (`lib/adapters/bootstrap_adapter.dart`):

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/interfaces/bootstrap_service.dart';

class BootstrapNodesAdapter implements BootstrapService {
  final SharedPreferences _prefs;

  static const _kCurrentBootstrapHost = 'current_bootstrap_host';
  static const _kCurrentBootstrapPort = 'current_bootstrap_port';
  static const _kCurrentBootstrapPubkey = 'current_bootstrap_pubkey';
  
  BootstrapNodesAdapter(this._prefs);
  
  @override
  Future<String?> getBootstrapHost() async {
    return _prefs.getString(_kCurrentBootstrapHost);
  }

  @override
  Future<int?> getBootstrapPort() async {
    return _prefs.getInt(_kCurrentBootstrapPort);
  }

  @override
  Future<String?> getBootstrapPublicKey() async {
    return _prefs.getString(_kCurrentBootstrapPubkey);
  }

  @override
  Future<void> setBootstrapNode({
    required String host,
    required int port,
    required String publicKey,
  }) async {
    await _prefs.setString(_kCurrentBootstrapHost, host);
    await _prefs.setInt(_kCurrentBootstrapPort, port);
    await _prefs.setString(_kCurrentBootstrapPubkey, publicKey);
  }
}
```

### Optional interface

#### EventBusProvider

Event bus provider for inter-component communication.

**Implementation Example** (`lib/adapters/event_bus_adapter.dart`):

```dart
import 'package:tim2tox_dart/interfaces/event_bus_provider.dart';
import 'package:tim2tox_dart/interfaces/event_bus.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';

class EventBusAdapter implements EventBusProvider {
  final FakeEventBus _eventBus;
  
  EventBusAdapter(this._eventBus);
  
  @override
  EventBus get eventBus => _eventBus;
}
```

#### ConversationManagerProvider

Session manager provider for session management.

**Implementation example** (`lib/adapters/conversation_manager_adapter.dart`):

```dart
import 'package:tim2tox_dart/interfaces/conversation_manager_provider.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';

class ConversationManagerAdapter implements ConversationManagerProvider {
  final FakeConversationManager _conversationManager;
  
  ConversationManagerAdapter(this._conversationManager);
  
  @override
  ConversationManager get conversationManager => _conversationManager;
}
```

## Initialization process

### Complete initialization example (simplified; differs from toxee’s actual flow)

The following is a **minimal standalone example**. It does not match toxee’s real flow: in toxee, FfiChatService is created and init/login are done in AccountService.initializeServiceForAccount or LoginUseCase, then passed into HomePage as `widget.service`; Platform is set by SessionRuntimeCoordinator.ensureInitialized(); after login success the caller runs AppBootstrapCoordinator.boot(service) before navigating to HomePage. For the actual entry points and order, see [Hybrid architecture](../architecture/HYBRID_ARCHITECTURE.en.md) and [Maintainer view](../architecture/MAINTAINER_ARCHITECTURE.en.md).

In `lib/ui/home_page.dart`'s `initState()` (for reference only):

```dart
@override
void initState() {
  super.initState();
  _initializeTim2Tox();
}

Future<void> _initializeTim2Tox() async {
  try {
    // 1. Initialize FakeUIKit (this will initialize conversationManager)
    FakeUIKit.instance.startWithFfi(widget.service);
    
    // 2. Create interface adapter
    final prefs = await SharedPreferences.getInstance();
    final prefsAdapter = SharedPreferencesAdapter(prefs);
    final loggerAdapter = AppLoggerAdapter();
    final bootstrapAdapter = BootstrapNodesAdapter(prefs);
    final eventBusAdapter = EventBusAdapter(FakeUIKit.instance.eventBusInstance);
    final conversationManagerAdapter = ConversationManagerAdapter(
      FakeUIKit.instance.conversationManager!,
    );
    
    // 3. Create services
    final ffiService = FfiChatService(
      preferencesService: prefsAdapter,
      loggerService: loggerAdapter,
      bootstrapService: bootstrapAdapter,
    );
    
    // 4. Initialize service
    await ffiService.init();
    
    // 5. Set up SDK Platform
    TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
      ffiService: ffiService,
      eventBusProvider: eventBusAdapter,
      conversationManagerProvider: conversationManagerAdapter,
    );
    
    // 6. Monitor messages
    ffiService.messages.listen((message) {
      // Process received messages
    });
    
    // 7. Monitor connection status
    ffiService.connectionStatusStream.listen((connected) {
      // Handle connection status changes
    });
    
  } catch (e) {
    print('Failed to initialize tim2tox: $e');
  }
}
```

### Detailed explanation of initialization steps

#### Step 1: Initialize FakeUIKit

```dart
FakeUIKit.instance.startWithFfi(widget.service);
```

This will initialize:
- `FakeConversationManager`: Session Manager
- `FakeEventBus`: event bus
- Other Fake components

#### Step 2: Create interface adapter

Map all abstract interfaces to concrete implementations:

```dart
final prefsAdapter = SharedPreferencesAdapter(prefs);
final loggerAdapter = AppLoggerAdapter();
final bootstrapAdapter = BootstrapNodesAdapter(prefs);
final eventBusAdapter = EventBusAdapter(FakeUIKit.instance.eventBusInstance);
final conversationManagerAdapter = ConversationManagerAdapter(
  FakeUIKit.instance.conversationManager!,
);
```

#### Step 3: Create the service

```dart
final ffiService = FfiChatService(
  preferencesService: prefsAdapter,
  loggerService: loggerAdapter,
  bootstrapService: bootstrapAdapter,
);
```

#### Step 4: Initialize the service

```dart
await ffiService.init();
```

This will:
- Load FFI library
- Initialize Tox instance
- Set callback
- Start message polling

#### Step 5: Set up SDK Platform

```dart
TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
  ffiService: ffiService,
  eventBusProvider: eventBusAdapter,
  conversationManagerProvider: conversationManagerAdapter,
);
```

This will route all UIKit SDK calls to tim2tox.

## Usage example

In toxee, login and sending messages are done via **FfiChatService** and **Fake\*** providers (AccountService, LoginUseCase, FakeChatMessageProvider, FakeMessageManager). The examples below show the SDK’s native API and are for reference only.

### Login

```dart
// Sign in via UIKit SDK
final result = await TencentImSDKPlugin.v2TIMManager.login(
  userID: 'user123',
  userSig: 'userSig',
);

if (result.code == 0) {
  print('Login successful');
} else {
  print('Login failed: ${result.desc}');
}
```

### Send message

```dart
// Create text message
final message = await TencentImSDKPlugin.v2TIMManager
    .getMessageManager()
    .createTextMessage(text: 'Hello, World!');

// Send message
final result = await TencentImSDKPlugin.v2TIMManager
    .getMessageManager()
    .sendMessage(
      message: message,
      receiver: 'friend123',
      groupID: null,
      priority: MessagePriorityEnum.V2TIM_PRIORITY_NORMAL,
    );

if (result.code == 0) {
  print('Message sent: ${result.data?.msgID}');
} else {
  print('Send failed: ${result.desc}');
}
```

### Receive messages

```dart
// Add message listening
TencentImSDKPlugin.v2TIMManager
    .getMessageManager()
    .addAdvancedMsgListener(
      listener: V2TimAdvancedMsgListener(
        onRecvNewMessage: (V2TimMessage message) {
          print('Received message: ${message.textElem?.text}');
        },
      ),
    );
```

### Get friends list

```dart
final result = await TencentImSDKPlugin.v2TIMManager
    .getFriendshipManager()
    .getFriendList();

if (result.code == 0) {
  final friends = result.data ?? [];
  for (final friend in friends) {
    print('Friend: ${friend.userID} - ${friend.friendRemark}');
  }
}
```

### Add friends

```dart
final result = await TencentImSDKPlugin.v2TIMManager
    .getFriendshipManager()
    .addFriend(
      userID: 'user123',
      addType: FriendTypeEnum.V2TIM_FRIEND_TYPE_BOTH,
      remark: 'Alice',
      addWording: 'Hello',
    );

if (result.code == 0) {
  print('Friend request sent');
} else {
  print('Add friend failed: ${result.desc}');
}
```

## Best Practices

### 1. Error handling

Always check the return code of an API call:

```dart
final result = await someApiCall();
if (result.code != 0) {
  // handling errors
  print('Error: ${result.code} - ${result.desc}');
  // Display user-friendly error messages
}
```

### 2. Asynchronous operation

All SDK operations are asynchronous, use `await` to wait for results:

```dart
// correct
final result = await apiCall();

// mistake
apiCall().then((result) {
  // Processing results
});
```

### 3. Listener management

Promptly remove listeners that are no longer needed:

```dart
final listener = V2TimAdvancedMsgListener(...);
TencentImSDKPlugin.v2TIMManager
    .getMessageManager()
    .addAdvancedMsgListener(listener: listener);

// Remove when not needed
@override
void dispose() {
  TencentImSDKPlugin.v2TIMManager
      .getMessageManager()
      .removeAdvancedMsgListener(listener: listener);
  super.dispose();
}
```

### 4. Resource cleanup

In toxee, account-level teardown is centralized in `AccountService.teardownCurrentSession`, which also drives `SessionRuntimeCoordinator.disposeRuntime()` to disposed `FakeUIKit`, restore `TencentCloudChatSdkPlatform.instance` to the default `MethodChannel` implementation, and clear UIKit `ChatDataProviderRegistry` / `ChatMessageProviderRegistry`. Use this path on logout, account switch, or app exit instead of calling `TencentImSDKPlugin.v2TIMManager.logout()` directly:

```dart
import 'package:toxee/util/account_service.dart';

await AccountService.teardownCurrentSession(
  service: ffiService,
  reEncryptProfile: true,  // re-encrypt the on-disk profile before discarding the in-memory key
);
```

If you are integrating Tim2Tox without the toxee adapters (the minimal example at the top of this doc), you still need a matching teardown: dispose your `FfiChatService`, reset `TencentCloudChatSdkPlatform.instance` to `MethodChannelTencentCloudChatSdkPlatform()` (so any later UIKit calls fall back to the method-channel default), and drop your provider registrations.

### 5. Status management

Use a Provider or other state management solution to manage application state:

```dart
class ChatProvider extends ChangeNotifier {
  List<V2TimMessage> _messages = [];
  List<V2TimMessage> get messages => _messages;
  
  void addMessage(V2TimMessage message) {
    _messages.add(message);
    notifyListeners();
  }
}
```

### 6. Performance optimization

- Use pagination to load large amounts of data
- Cache frequently used data
- Avoid frequent API calls
- Use Stream instead of polling

### 7. Logging

Enable logging for debugging:

```dart
// Set log level on initialization
TencentImSDKPlugin.v2TIMManager.initSDK(
  sdkAppID: 123456,
  logLevel: LogLevelEnum.V2TIM_LOG_DEBUG,
);
```

## Related documents

- [toxee Build and Deployment](../operations/BUILD_AND_DEPLOY.en.md) - Detailed build steps
- [Troubleshooting](../TROUBLESHOOTING.en.md) - FAQ
- [Main README](../../README.md) - Project Overview
- [Tim2Tox](https://github.com/anonymoussoft/tim2tox) documentation ([local index](../../third_party/tim2tox/doc/README.en.md))
