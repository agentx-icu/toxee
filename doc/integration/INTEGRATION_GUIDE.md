# toxee 集成
> 语言 / Language: [中文](INTEGRATION_GUIDE.md) | [English](INTEGRATION_GUIDE.en.md)


本文档说明如何把 [Tim2Tox](https://github.com/agentx-icu/tim2tox) 集成到 Flutter 应用，包括接口适配器实现、初始化流程和最佳实践。

## 目录

- [概述](#概述)
- [快速开始](#快速开始)
- [接口适配器实现](#接口适配器实现)
- [初始化流程](#初始化流程)
- [使用示例](#使用示例)
- [最佳实践](#最佳实践)

## 概述

toxee 展示了如何将 [Tim2Tox](https://github.com/agentx-icu/tim2tox) 集成到 Flutter 应用中。集成过程包括：

1. **实现接口适配器**: 将 Tim2Tox 的抽象接口映射到客户端的具体实现
2. **初始化服务**: 创建和初始化 FfiChatService
3. **设置 SDK Platform**: 将 UIKit SDK 调用路由到 tim2tox
4. **使用 UIKit 组件**: 正常使用 Tencent Cloud Chat UIKit 组件

## 快速开始

### 最小集成示例

```dart
import 'package:tim2tox_dart/tim2tox_dart.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. 创建接口适配器
final prefs = await SharedPreferences.getInstance();
final prefsAdapter = SharedPreferencesAdapter(prefs);
final loggerAdapter = AppLoggerAdapter();
final bootstrapAdapter = BootstrapNodesAdapter(prefs);

// 2. 创建服务
final ffiService = FfiChatService(
  preferencesService: prefsAdapter,
  loggerService: loggerAdapter,
  bootstrapService: bootstrapAdapter,
);

// 3. 初始化服务
await ffiService.init();

// 4. 设置 SDK Platform
TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
  ffiService: ffiService,
);

// 5. 使用 UIKit
// 现在可以正常使用 Tencent Cloud Chat UIKit 组件
```

## 接口适配器实现

Tim2Tox 通过接口注入客户端依赖，客户端需要实现以下接口适配器。

### 必需接口

#### ExtendedPreferencesService

偏好设置服务，用于持久化数据。

**实现示例** (`lib/adapters/shared_prefs_adapter.dart`):

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

日志服务，用于输出日志。

**实现示例** (`lib/adapters/logger_adapter.dart`):

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

Bootstrap 节点服务，用于 Tox 网络连接。

**实现示例** (`lib/adapters/bootstrap_adapter.dart`):

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

### 可选接口

#### EventBusProvider

事件总线提供者，用于组件间通信。

**实现示例** (`lib/adapters/event_bus_adapter.dart`):

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

会话管理器提供者，用于会话管理。

**实现示例** (`lib/adapters/conversation_manager_adapter.dart`):

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

## 初始化流程

### 完整初始化示例（简化版，与 toxee 实际启动链不同）

以下为**独立应用最小示例**，与 toxee 实际流程不同：toxee 中 FfiChatService 由 AccountService.initializeServiceForAccount 或 LoginUseCase 创建并 init/login，通过 `widget.service` 传入 HomePage；Platform 由 SessionRuntimeCoordinator.ensureInitialized() 设置；登录成功后由调用方执行 AppBootstrapCoordinator.boot(service) 再进入 HomePage。实际入口与顺序见 [混合架构](../architecture/HYBRID_ARCHITECTURE.md)、[维护者视角](../architecture/MAINTAINER_ARCHITECTURE.md)。

在 `lib/ui/home_page.dart` 的 `initState()` 中（仅作参考）：

```dart
@override
void initState() {
  super.initState();
  _initializeTim2Tox();
}

Future<void> _initializeTim2Tox() async {
  try {
    // 1. 初始化 FakeUIKit（这会初始化 conversationManager）
    FakeUIKit.instance.startWithFfi(widget.service);
    
    // 2. 创建接口适配器
    final prefs = await SharedPreferences.getInstance();
    final prefsAdapter = SharedPreferencesAdapter(prefs);
    final loggerAdapter = AppLoggerAdapter();
    final bootstrapAdapter = BootstrapNodesAdapter(prefs);
    final eventBusAdapter = EventBusAdapter(FakeUIKit.instance.eventBusInstance);
    final conversationManagerAdapter = ConversationManagerAdapter(
      FakeUIKit.instance.conversationManager!,
    );
    
    // 3. 创建服务
    final ffiService = FfiChatService(
      preferencesService: prefsAdapter,
      loggerService: loggerAdapter,
      bootstrapService: bootstrapAdapter,
    );
    
    // 4. 初始化服务
    await ffiService.init();
    
    // 5. 设置 SDK Platform
    TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
      ffiService: ffiService,
      eventBusProvider: eventBusAdapter,
      conversationManagerProvider: conversationManagerAdapter,
    );
    
    // 6. 监听消息
    ffiService.messages.listen((message) {
      // 处理接收到的消息
    });
    
    // 7. 监听连接状态
    ffiService.connectionStatusStream.listen((connected) {
      // 处理连接状态变化
    });
    
  } catch (e) {
    print('Failed to initialize tim2tox: $e');
  }
}
```

### 初始化步骤详解

#### 步骤 1: 初始化 FakeUIKit

```dart
FakeUIKit.instance.startWithFfi(widget.service);
```

这会初始化：
- `FakeConversationManager`: 会话管理器
- `FakeEventBus`: 事件总线
- 其他 Fake 组件

#### 步骤 2: 创建接口适配器

将所有抽象接口映射到具体实现：

```dart
final prefsAdapter = SharedPreferencesAdapter(prefs);
final loggerAdapter = AppLoggerAdapter();
final bootstrapAdapter = BootstrapNodesAdapter(prefs);
final eventBusAdapter = EventBusAdapter(FakeUIKit.instance.eventBusInstance);
final conversationManagerAdapter = ConversationManagerAdapter(
  FakeUIKit.instance.conversationManager!,
);
```

#### 步骤 3: 创建服务

```dart
final ffiService = FfiChatService(
  preferencesService: prefsAdapter,
  loggerService: loggerAdapter,
  bootstrapService: bootstrapAdapter,
);
```

#### 步骤 4: 初始化服务

```dart
await ffiService.init();
```

这会：
- 加载 FFI 库
- 初始化 Tox 实例
- 设置回调
- 启动消息轮询

#### 步骤 5: 设置 SDK Platform

```dart
TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
  ffiService: ffiService,
  eventBusProvider: eventBusAdapter,
  conversationManagerProvider: conversationManagerAdapter,
);
```

这会将所有 UIKit SDK 调用路由到 tim2tox。

## 使用示例

在 toxee 中，登录与发消息实际经 **FfiChatService** 与 **Fake\*** Provider（AccountService、LoginUseCase、FakeChatMessageProvider、FakeMessageManager）完成；以下为 SDK 原生 API 用法示例，仅供理解接口时参考。

### 登录

```dart
// 通过 UIKit SDK 登录
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

### 发送消息

```dart
// 创建文本消息
final message = await TencentImSDKPlugin.v2TIMManager
    .getMessageManager()
    .createTextMessage(text: 'Hello, World!');

// 发送消息
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

### 接收消息

```dart
// 添加消息监听
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

### 获取好友列表

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

### 添加好友

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

## 最佳实践

### 1. 错误处理

始终检查 API 调用的返回码：

```dart
final result = await someApiCall();
if (result.code != 0) {
  // 处理错误
  print('Error: ${result.code} - ${result.desc}');
  // 显示用户友好的错误消息
}
```

### 2. 异步操作

所有 SDK 操作都是异步的，使用 `await` 等待结果：

```dart
// 正确
final result = await apiCall();

// 错误
apiCall().then((result) {
  // 处理结果
});
```

### 3. 监听器管理

及时移除不再需要的监听器：

```dart
final listener = V2TimAdvancedMsgListener(...);
TencentImSDKPlugin.v2TIMManager
    .getMessageManager()
    .addAdvancedMsgListener(listener: listener);

// 在不需要时移除
@override
void dispose() {
  TencentImSDKPlugin.v2TIMManager
      .getMessageManager()
      .removeAdvancedMsgListener(listener: listener);
  super.dispose();
}
```

### 4. 资源清理

在 toxee 中，账号级别的清理统一由 `AccountService.teardownCurrentSession` 处理 —— 它会调用 `SessionRuntimeCoordinator.disposeRuntime()` 释放 `FakeUIKit`、将 `TencentCloudChatSdkPlatform.instance` 还原为默认的 `MethodChannel` 实现，并清空 UIKit 的 `ChatDataProviderRegistry` / `ChatMessageProviderRegistry`。退出登录、切换账号或应用退出时都应走这条路径，而不是直接调用 `TencentImSDKPlugin.v2TIMManager.logout()`：

```dart
import 'package:toxee/util/account_service.dart';

await AccountService.teardownCurrentSession(
  service: ffiService,
  reEncryptProfile: true,  // 释放内存中的密钥前重新加密磁盘上的 profile
);
```

如果你是在不使用 toxee 适配层的最小集成场景（见本文档最上面的最小示例），同样需要做对应的清理：dispose 自建的 `FfiChatService`，把 `TencentCloudChatSdkPlatform.instance` 重置回 `MethodChannelTencentCloudChatSdkPlatform()`（以便后续 UIKit 调用回落到默认 method-channel 实现），并清除已注册的 Provider。

旧示例仅供独立参考（不再推荐）：

```dart
@override
void dispose() {
  // 登出
  TencentImSDKPlugin.v2TIMManager.logout();
  
  // 反初始化 SDK
  TencentImSDKPlugin.v2TIMManager.unInitSDK();
  
  super.dispose();
}
```

### 5. 状态管理

使用 Provider 或其他状态管理方案管理应用状态：

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

### 6. 性能优化

- 使用分页加载大量数据
- 缓存常用数据
- 避免频繁的 API 调用
- 使用 Stream 而不是轮询

### 7. 日志记录

启用日志以便调试：

```dart
// 在初始化时设置日志级别
TencentImSDKPlugin.v2TIMManager.initSDK(
  sdkAppID: 123456,
  logLevel: LogLevelEnum.V2TIM_LOG_DEBUG,
);
```

## 相关文档

- [toxee 构建与部署](../operations/BUILD_AND_DEPLOY.md) - 详细构建步骤
- [故障排除](../TROUBLESHOOTING.md) - 常见问题解答
- [主 README](../../README.zh-CN.md) - 项目概述
- [Tim2Tox](https://github.com/agentx-icu/tim2tox) 文档（[本地索引](../../third_party/tim2tox/doc/README.md)）
