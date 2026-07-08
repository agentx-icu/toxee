# toxee 实现细节
> 语言 / Language: [中文](IMPLEMENTATION_DETAILS.md) | [English](IMPLEMENTATION_DETAILS.en.md)

本文为实现细节总览，按模块跳转见下方目录（可视为总索引）。

## 目录

1. [集成方案](#集成方案)
2. [接口适配器实现](#接口适配器实现)
3. [数据适配层实现](#数据适配层实现)
4. [初始化流程详解](#初始化流程详解)
5. [消息处理流程](#消息处理流程)
6. [事件处理流程](#事件处理流程)
7. [文件传输实现](#文件传输实现)
8. [好友管理实现](#好友管理实现)
9. [群组管理实现](#群组管理实现)
10. [账号与会话生命周期](#账号与会话生命周期)
11. [通话与扩展能力](#通话与扩展能力)
12. [Tim2tox 接口兼容性与回归验证](#tim2tox-接口兼容性与回归验证)

另见 [architecture/HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.md) 了解混合架构的完整流程与回调分工，另可参考 [ACCOUNT_AND_SESSION.md](ACCOUNT_AND_SESSION.md) 查看账号与会话生命周期。

## 集成方案

toxee 当前使用**二进制替换 + 混合 Platform** 方案来集成 Tim2Tox（上游仓库 [https://github.com/agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)）。另见 [architecture/HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.md)。

**多实例支持说明**：
- toxee 使用默认 Tox 实例（通过 `V2TIMManagerImpl::GetInstance()`）
- 无需创建测试实例，直接使用 `TIMManager.instance` 即可
- 多实例功能主要用于自动化测试场景（如 `tim2tox/auto_tests`）
- 参见 [Tim2Tox](https://github.com/agentx-icu/tim2tox) [多实例支持文档](../../third_party/tim2tox/doc/development/MULTI_INSTANCE_SUPPORT.md) 了解详细信息

### 当前方案：混合架构

**实现位置**: 
- tencent_cloud_chat_sdk 包（bootstrap 后位于 `third_party/tencent_cloud_chat_sdk`）内的 `lib/native_im/bindings/native_library_manager.dart` — 动态库加载
- `toxee/lib/main.dart` — 通过 `AppBootstrap.initialize()` → `LoggingBootstrap.initialize()` 调用 `setNativeLibraryName('tim2tox_ffi')`（实际调用在 `lib/bootstrap/logging_bootstrap.dart`），不设置 Platform；实际入口为 EchoUIKitApp → _StartupGate
- Platform 由 `SessionRuntimeCoordinator.ensureInitialized()` 设置（`lib/runtime/session_runtime_coordinator.dart`）；自动登录在 `AppBootstrapCoordinator.boot()` 中（进入 HomePage 前）调用，手动登录在登录页调用 `boot(service)` 或 HomePage._initAfterSessionReady() 时调用。HomePage 内再执行 _initTIMManagerSDK、_initBinaryReplacementPersistenceHook 等

**关键代码**:
```dart
// lib/bootstrap/logging_bootstrap.dart（在 main() 启动链最早阶段由 AppBootstrap.initialize() 调用）
// BINARY REPLACEMENT MODE: 确保后续任何 SDK/FFI 调用都加载 tim2tox 动态库
setNativeLibraryName('tim2tox_ffi');

// tencent_cloud_chat_sdk 包内 native_library_manager.dart（通过 setNativeLibraryName 使用）
// const String _libName = 'tim2tox_ffi'; final DynamicLibrary _dylib = DynamicLibrary.open(...);

// SessionRuntimeCoordinator.ensureInitialized()（混合架构必需：设置 Platform）
if (TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform) {
  TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
    ffiService: service,
    eventBusProvider: eventBusAdapter,
    conversationManagerProvider: conversationManagerAdapter,
  );
}
// HomePage 内：TimSdkInitializer.ensureInitialized().then((_) {
//   _initBinaryReplacementPersistenceHook(); initGroupListener(); initFriendListener();
// });
```

**调用路径**:
```
UIKit SDK
  ↓
TIMManager.instance.initSDK()
  ↓
NativeLibraryManager.bindings.DartInitSDK(...)
  ↓
FFI 动态查找符号 'DartInitSDK' (在 libtim2tox_ffi.dylib 中)
  ↓
dart_compat_layer.cpp::DartInitSDK()
  ↓
V2TIMManager::GetInstance()->InitSDK(...)
  ↓
ToxManager::getInstance().init(...)
```

**特点与代价**：大部分调用仍走 NativeLibraryManager → Dart*，与现有 SDK 调用习惯兼容；历史、特殊回调、轮询、消息发送主路径等由 Dart 侧（FfiChatService、Platform、BinaryReplacementHistoryHook）承担，需在正确时机设置 Platform 与 Hook（自动登录在 boot 中、手动登录在登录页调用 boot(service) 或 HomePage 内 ensureInitialized），并保证 startPolling 在 SessionRuntimeCoordinator.ensureInitialized 之后调用。

### 备选方案：Platform 接口方案

**实现位置**: 
- `tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart` - Platform 接口实现
- `tim2tox/dart/lib/service/ffi_chat_service.dart` - 高级服务层

**关键代码**:
```dart
// 需要设置 Platform instance
TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
  ffiService: ffiService,
  eventBusProvider: eventBusAdapter,
  conversationManagerProvider: convAdapter,
);
```

**调用路径**:
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

**优势**:
- ✅ 功能丰富（消息历史、轮询、状态管理等）
- ✅ 灵活性强（可以自定义实现）
- ✅ 易于扩展

**详细说明**: 参见 [Tim2Tox](https://github.com/agentx-icu/tim2tox) [架构](../../third_party/tim2tox/doc/architecture/ARCHITECTURE.md) 和 [二进制替换](../../third_party/tim2tox/doc/architecture/BINARY_REPLACEMENT.md)

## 接口适配器实现

### SharedPreferencesAdapter

**位置**: `lib/adapters/shared_prefs_adapter.dart`

**实现**: `ExtendedPreferencesService`

**关键方法**:

```dart
class SharedPreferencesAdapter implements ExtendedPreferencesService {
  final SharedPreferences _prefs;
  
  // 基础方法
  @override
  Future<String?> getString(String key) async => _prefs.getString(key);
  
  @override
  Future<void> setString(String key, String value) => 
      _prefs.setString(key, value);
  
  // 扩展方法 - 群组相关
  @override
  Future<String?> getGroupName(String groupId) => 
      getString('group_name_$groupId');
  
  @override
  Future<void> setGroupName(String groupId, String name) => 
      setString('group_name_$groupId', name);
  
  // 扩展方法 - 好友相关
  @override
  Future<String?> getFriendNickname(String friendId) => 
      getString('friend_nickname_$friendId');
  
  // ... 更多方法
}
```

**存储键名约定**:
- 群组名称: `group_name_<groupId>`
- 群组头像: `group_avatar_<groupId>`
- 好友昵称: `friend_nickname_<friendId>`
- 好友状态消息: `friend_status_msg_<friendId>`
- 好友头像: `friend_avatar_path_<friendId>`
- 本地好友列表: `local_friends`
- Bootstrap 节点: `current_bootstrap_host/port/pubkey`

### AppLoggerAdapter

**位置**: `lib/adapters/logger_adapter.dart`

**实现**: `LoggerService`

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

**位置**: `lib/adapters/bootstrap_adapter.dart`

**实现**: `BootstrapService`

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

**位置**: `lib/adapters/event_bus_adapter.dart`

**实现**: `EventBusProvider`

```dart
class EventBusAdapter implements EventBusProvider {
  final FakeEventBus _eventBus;
  
  EventBusAdapter(this._eventBus);
  
  @override
  EventBus get eventBus => _eventBus;
}
```

### ConversationManagerAdapter

**位置**: `lib/adapters/conversation_manager_adapter.dart`

**实现**: `ConversationManagerProvider`

```dart
class ConversationManagerAdapter implements ConversationManagerProvider {
  final FakeConversationManager _conversationManager;
  
  ConversationManagerAdapter(this._conversationManager);
  
  @override
  Future<List<framework_models.FakeConversation>> getConversationList() async {
    final clientConvs = await _conversationManager.getConversationList();
    // 转换客户端 FakeConversation 到 framework FakeConversation
    return clientConvs.map((conv) => framework_models.FakeConversation(
      conversationID: conv.conversationID,
      title: conv.title,
      faceUrl: conv.faceUrl,
      unreadCount: conv.unreadCount,
      isGroup: conv.isGroup,
      isPinned: conv.isPinned,
    )).toList();
  }
  
  // ... 其他方法
}
```

## 数据适配层实现

### FakeIM - 事件总线管理器

**位置**: `lib/sdk_fake/fake_im.dart`

**职责**:
- 订阅 `FfiChatService` 的事件
- 将 tim2tox 事件转换为 UIKit 格式
- 通过 `FakeEventBus` 发布事件

**初始化流程**:

```dart
void start() {
  // 延迟初始化，确保 Tox 已恢复好友列表
  Future.delayed(const Duration(milliseconds: 2000), () async {
    // 重试机制：如果好友列表为空，等待并重试
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
    
    // 启动定时刷新
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshConversations();
      _emitContacts();
    });
  });
}
```

**关键方法**:

1. **`_refreshConversations()`**: 刷新会话列表
   - 从 `FfiChatService` 获取好友列表
   - 从 `FfiChatService` 获取最后一条消息
   - 创建 `FakeConversation` 对象
   - 通过事件总线发布

2. **`_emitContacts()`**: 发出联系人事件
   - 从 `FfiChatService` 获取好友列表
   - 创建 `FakeUser` 对象
   - 通过事件总线发布

3. **`_seedHistory()`**: 初始化消息历史
   - 从 `FfiChatService` 获取所有会话的历史消息
   - 创建 `FakeMessage` 对象
   - 通过事件总线发布

### FakeConversationManager

**位置**: `lib/sdk_fake/fake_managers.dart`

**职责**:
- 管理会话列表
- 处理会话更新
- 管理未读计数

**关键方法**:

```dart
Future<List<FakeConversation>> getConversationList() async {
  final friends = await _ffi.getFriendList();
  final pinned = await Prefs.getPinned();
  _pinned = pinned;
  
  // 获取待处理的好友申请
  final pendingApps = await _ffi.getFriendApplications();
  final pendingFriendIds = pendingApps.map((a) => a.userId).toSet();
  
  // 构建会话列表
  final conversations = <FakeConversation>[];
  
  for (final friend in friends) {
    // 跳过待处理的好友申请
    if (pendingFriendIds.contains(friend.userId)) continue;
    
    // 获取最后一条消息
    final lastMsg = _ffi.lastMessages[friend.userId];
    
    // 创建会话对象
    final conv = FakeConversation(
      conversationID: 'c2c_${friend.userId}',
      title: friend.nickName,
      faceUrl: friend.avatarPath,
      unreadCount: 0, // 由 FakeIM 更新
      isGroup: false,
      isPinned: _pinned.contains('c2c_${friend.userId}'),
    );
    
    conversations.add(conv);
  }
  
  return conversations;
}
```

### FakeChatDataProvider

**位置**: `lib/sdk_fake/fake_provider.dart`

**职责**:
- 实现 `ChatDataProvider` 接口
- 提供会话数据流
- 提供未读计数流

**关键实现**:

```dart
class FakeChatDataProvider implements ChatDataProvider {
  final _convCtrl = StreamController<List<V2TimConversation>>.broadcast();
  final _unreadCtrl = StreamController<int>.broadcast();
  
  FakeChatDataProvider({required FfiChatService ffiService}) {
    // 订阅 FakeIM 的会话事件
    FakeUIKit.instance.eventBusInstance
        .on<FakeConversation>(FakeIM.topicConversation)
        .listen((conv) {
      // 转换为 V2TimConversation 并发出
      _updateConversation(conv);
    });
    
    // 订阅未读计数事件
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

**位置**: `lib/sdk_fake/fake_msg_provider.dart`

**职责**:
- 实现 `ChatMessageProvider` 接口
- 处理消息发送
- 支持多种消息类型

**关键实现**:

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
      // C2C 消息
      await ffi.sendText(userID, text);
    } else if (groupID != null) {
      // 群组消息
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
    // 检查朋友是否在线（仅 C2C）
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
    
    // 发送文件
    if (groupID != null) {
      await ffi.sendGroupFile(groupID, filePath);
    } else {
      await ffi.sendFile(userID!, filePath);
    }
  }
}
```

## 初始化流程详解

### 推荐初始化顺序（混合架构）

**概念顺序**（逻辑依赖）：`FfiChatService.init` → `login` → `updateSelfProfile` → `FakeUIKit.startWithFfi` → `TIMManager.initSDK` → `startPolling` → `HomePage` 设置 `Tim2ToxSdkPlatform` → 初始化 `BinaryReplacementHistoryHook`、通话桥与插件。

**实际执行顺序**（与代码一致）：
1. **main()**：`setNativeLibraryName('tim2tox_ffi')`，不设置 Platform。
2. **_StartupGate._decide()**（自动登录）：优先通过 `AccountService.initializeServiceForAccount(..., startPolling: false)` 完成 `init()`、`login()`、`updateSelfProfile()`；随后执行 `FakeUIKit.startWithFfi(service)` → `_initTIMManagerSDK()` → `service.startPolling()` → 等待连接/超时 → 预加载好友信息 → 导航到 `HomePage(service)`。
3. **HomePage.initState()**：若 FakeUIKit 未启动则 startWithFfi；若 `instance is! Tim2ToxSdkPlatform` 则设置 Tim2ToxSdkPlatform；接着初始化 `CallServiceManager`；然后执行 `_initTIMManagerSDK().then(_initBinaryReplacementPersistenceHook)`，在 then 内再执行 `initGroupListener`、`initFriendListener`。

BinaryReplacementHistoryHook 在 _initTIMManagerSDK 完成后的 then 中初始化（依赖 MessageHistoryPersistence、selfId；selfId 为空时监听 connectionStatusStream 后再 _setupPersistenceHook）。详见 [architecture/HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.md)。

### 1. main() 函数

**位置**: `lib/main.dart`

**关键步骤**：`main()` 负责日志初始化、统一 C++/Dart 日志文件、主题和语言恢复、桌面窗口初始化，以及 `setNativeLibraryName('tim2tox_ffi')`。它**不设置** `TencentCloudChatSdkPlatform.instance`。应用入口为 `EchoUIKitApp`，首页为 `_StartupGate`。

### 2. _StartupGate._decide()（自动登录）

**位置**: `lib/main.dart`（_StartupGate 状态类）

**关键步骤**（自动登录路径）：
- 先检查昵称、自动登录开关和 bootstrap 配置
- 若存在账号，调用 `AccountService.initializeServiceForAccount(..., startPolling: false)` 完成 `init()`、`login()`、`updateSelfProfile()`
- 若是旧账号兼容路径，则手动创建 `FfiChatService`
- `FakeUIKit.instance.startWithFfi(service)` 提前启动会话、联系人、消息和通话子系统
- 调用 `_initTIMManagerSDK()`
- 调用 `service.startPolling()`，随后等待连接或超时
- 连接成功后预加载好友状态和联系人数据，再导航到 `HomePage`

### 3. LoginPage（用户未自动登录时）

**位置**: `lib/ui/login_page.dart`

用户从登录页登录时，已有账号优先走 `AccountService.initializeServiceForAccount(...)`，旧账号兼容路径才直接手动执行 `init()` / `login()` / `updateSelfProfile()` / `startPolling()`。随后调用 `_initTIMManagerSDK()` 并导航到 `HomePage`。HomePage 内同样会设置 Platform、初始化通话桥并挂接 `BinaryReplacementHistoryHook`。

### 4. HomePage.initState()

**位置**: `lib/ui/home_page.dart`

**关键步骤**：
- 若 `!FakeUIKit.instance.isStarted` 则 `FakeUIKit.startWithFfi(widget.service)`
- 若 `TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform` 则创建 EventBusAdapter、ConversationManagerAdapter，并设置 `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(ffiService: widget.service, ...)`
- 初始化 `FakeUIKit.instance.callServiceManager`，启用 TUICallKit 到 ToxAV 的桥接
- `_initTIMManagerSDK().then((_) { _initBinaryReplacementPersistenceHook(); initGroupListener(); initFriendListener(); })`
- 注册 ChatDataProviderRegistry、ChatMessageProviderRegistry 等
- 在 message 组件注册前后补齐 sticker / textTranslate / soundToText 插件

**_initBinaryReplacementPersistenceHook**：从 `widget.service.messageHistoryPersistence` 与 `widget.service.selfId` 获取依赖；若 selfId 为空则监听 `connectionStatusStream`，连接成功且 selfId 非空后再调用 _setupPersistenceHook。_setupPersistenceHook 内执行 `BinaryReplacementHistoryHook.initialize(persistence, selfId)`，并用 `BinaryReplacementHistoryHook.wrapListener` 包装当前 TIMMessageManager 的 _advancedMsgListener，实现 C++ 新消息回调的自动持久化。

## 消息处理流程

### 发送文本消息

```
1. 用户在 UIKit Message 组件中输入文本
   ↓
2. UIKit 调用 ChatMessageProvider.sendText()
   ↓
3. FakeChatMessageProvider.sendText()
   ↓
4. 离线检测（检查联系人是否在线）
   ├─ 如果离线 → 立即标记为失败 → 保存到持久化存储 → 显示失败状态
   └─ 如果在线 → 继续发送流程
   ↓
5. FfiChatService.sendText() / sendGroupText()
   ↓
6. tim2tox FFI 导出函数
   ↓
7. tim2tox_ffi (C FFI)
   ↓
8. Tim2Tox (C++)
   ↓
9. toxcore
   ↓
10. 超时检测（使用 Future.timeout，文本消息5秒）
    ├─ 如果成功 → 更新消息状态为成功
    └─ 如果超时 → 标记为失败 → 保存到持久化存储 → 更新UI状态
```

**关键特性**：
- **离线检测**：发送前检查联系人是否在线，如果离线立即失败
- **超时机制**：使用 `Future.timeout` 实现动态超时（文本消息5秒）
- **持久化存储**：失败消息保存到 `SharedPreferences`
- **消息ID**：统一使用 `timestamp_userID` 格式（毫秒级时间戳）

### 接收文本消息

```
1. toxcore 接收到消息
   ↓
2. tim2tox (C++) 处理消息
   ↓
3. tim2tox_ffi (C) 将消息加入事件队列
   ↓
4. FfiChatService 轮询事件队列
   ↓
5. FfiChatService 解析消息事件
   ↓
6. [两条路径]:
   
   a. SDK Events:
      Tim2ToxSdkPlatform.onRecvNewMessage()
         ↓
      UIKit SDK Listeners
         ↓
      UI Updates
   
   b. Data Streams:
      FakeIM 订阅 FfiChatService 事件
         ↓
      FakeIM 创建 FakeMessage
         ↓
      FakeEventBus 发布事件
         ↓
      FakeMessageManager 处理事件
         ↓
      FakeChatDataProvider 更新数据
         ↓
      UIKit Controllers 更新 UI
```

### 失败消息恢复流程

```
1. 客户端启动 / 切换会话
   ↓
2. 加载消息历史（从 FfiChatService）
   ↓
3. 从持久化存储加载失败消息（TencentCloudChatFailedMessagePersistence）
   ↓
4. 合并历史消息和失败消息
   ↓
5. 检查消息状态：
   ├─ 如果消息在失败列表中 → 无条件标记为失败
   └─ 恢复消息内容（如 textElem）
   ↓
6. 更新消息列表和会话列表
   ↓
7. UI 显示失败消息状态
```

**关键实现**：
- `_loadHistoryForConversation`：加载历史时检查失败消息持久化存储
- `_restoreFailedMessages`：恢复失败消息状态
- `_mapConv`：会话列表更新时检查失败消息，确保最新失败消息显示在会话列表

### 递归防护机制

**实现位置**: `chat-uikit-flutter/tencent_cloud_chat_common/lib/data/message/tencent_cloud_chat_message_data.dart:858-894`

在 `onReceiveNewMessage` 方法中，当消息已存在时，需要触发 SDK 回调以更新会话的 `lastMessage`。这可能导致递归调用，因为：

1. `onReceiveNewMessage` 被注册为 SDK 的 `onRecvNewMessage` 回调
2. 当消息已存在时，代码调用 `listener.onRecvNewMessage(newMessage)`
3. 这会触发 SDK 的回调，再次调用 `onReceiveNewMessage`
4. 形成无限递归，导致堆栈溢出

**防护机制**：

使用 `_processingMessageIds` Set 来跟踪正在处理的消息ID，防止递归：

```dart
// 防止递归：如果消息正在处理中，跳过回调
final messageId = newMessage.msgID ?? newMessage.id ?? '';
final messageIdAlt = newMessage.id ?? newMessage.msgID ?? '';

// 检查任一ID是否正在处理
if (messageId.isNotEmpty && _processingMessageIds.contains(messageId)) {
  return; // 跳过递归调用
}
if (messageIdAlt.isNotEmpty && messageIdAlt != messageId && 
    _processingMessageIds.contains(messageIdAlt)) {
  return; // 跳过递归调用
}

// 如果两个ID都为空，无法防止递归，直接跳过
if (messageId.isEmpty && messageIdAlt.isEmpty) {
  return;
}

try {
  // 标记消息为正在处理（同时标记两个ID，如果不同）
  if (messageId.isNotEmpty) {
    _processingMessageIds.add(messageId);
  }
  if (messageIdAlt.isNotEmpty && messageIdAlt != messageId) {
    _processingMessageIds.add(messageIdAlt);
  }
  
  // 调用 SDK 回调
  listener.onRecvNewMessage(newMessage);
} finally {
  // 清理标记
  if (messageId.isNotEmpty) {
    _processingMessageIds.remove(messageId);
  }
  if (messageIdAlt.isNotEmpty && messageIdAlt != messageId) {
    _processingMessageIds.remove(messageIdAlt);
  }
}
```

**关键设计**：
- **双重ID检查**：同时检查 `msgID` 和 `id` 两个字段，因为某些情况下它们可能不同
- **空ID保护**：如果两个ID都为空，无法防止递归，直接跳过回调
- **finally 清理**：确保即使发生异常，标记也会被清理，避免永久阻塞

## 事件处理流程

### C++ 回调与 FfiChatService streams 的分工

在混合架构下，新消息与事件有两条来源：

| 来源 | 用途 | 说明 |
|------|------|------|
| **C++ ReceiveNewMessage** | 经 NativeLibraryManager 派发到 TIMMessageManager 的 _advancedMsgListener | 二进制替换下新消息的主入口；BinaryReplacementHistoryHook 包装 listener 做持久化 |
| **FfiChatService.messages** | FfiChatService 内部 _onNativeEvent 产生的 stream | 来自 FfiChatService 的旧式事件协议，与 C++ 层分工不同 |

两者分工明确，避免重复处理。详见 [HYBRID_ARCHITECTURE.md - 回调流程与分工](../architecture/HYBRID_ARCHITECTURE.md#四回调流程与分工)。

### 事件订阅

```dart
// FakeIM 订阅 FfiChatService 事件
void start() {
  // 订阅消息事件
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
  
  // 订阅好友状态事件
  _ffi.onFriendStatusChanged.listen((status) {
    // 更新好友状态
    _emitContacts();
  });
}
```

### 事件发布

```dart
// FakeEventBus 发布事件
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

### 事件消费

```dart
// FakeConversationManager 订阅会话事件
void start() {
  _convSub = _bus.on<FakeConversation>(FakeIM.topicConversation).listen((c) {
    for (final l in _listeners) {
      l.onNewConversation?.call([c]);
      l.onConversationChanged?.call([c]);
    }
  });
}
```

## 文件传输实现

### 发送文件

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

  // Tox 群组层当前不支持文件/图片/视频传输，必须快速失败。
  if (groupID != null && groupID.isNotEmpty) {
    throw StateError('Group file transfer is not supported in toxee');
  }

  // C2C 离线文件由 FfiChatService.sendFile 统一处理：
  // 好友离线时写入 offline_message_queue.json，并在会话中显示 pending 气泡；
  // 好友上线后由 drain 逻辑重放。
  await mgr.sendFile(conv, filePath);
}
```

HomePage 自定义图片/视频入口也直接委托 `widget.service.sendFile(userId, pickedPath)`。UI 层不再用 `getFriendList()` 做离线预判，避免把本应进入离线队列的媒体发送误报为失败。

### 接收文件

文件接收流程涉及多个层次和事件，以下是完整的实现：

#### 1. C++ 层事件生成 (`tim2tox/ffi/tim2tox_ffi.cpp`)

**`OnFileRecv` 回调**（文件传输请求）:
```cpp
ToxManager::getInstance().setFileRecvCallback([](uint32_t friend_number, uint32_t file_number, uint32_t kind, uint64_t file_size, const uint8_t* filename, size_t filename_length) {
    // 发送 file_request 事件到 polling queue
    // 格式: file_request:<uid>:<file_number>:<size>:<kind>:<filename>
    // kind: 0=DATA, 1=AVATAR
    snprintf(line, sizeof(line), "file_request:%s:%u:%llu:%u:%s", 
             sender_hex.c_str(), file_number, file_size, kind, name.c_str());
    G.simple_listener.enqueue_text_line(line);
});
```

**`OnRecvFileData` 回调**（文件数据接收）:
```cpp
ToxManager::getInstance().setFileRecvChunkCallback([](uint32_t friend_number, uint32_t file_number, uint64_t position, const uint8_t* data, size_t length) {
    // 写入文件数据
    fwrite(data, 1, length, fp);
    fflush(fp);
    
    // 发送进度更新事件
    // 格式: progress_recv:<uid>:<received>:<total>:<path>
    if (length > 0) {
        snprintf(line, sizeof(line), "progress_recv:%s:%llu:%llu:%s", 
                 sender_hex.c_str(), received, total, path.c_str());
        G.simple_listener.enqueue_text_line(line);
    }
    
    // 文件完成时 (length == 0)
    if (length == 0) {
        // 发送 file_done 事件
        // 格式: file_done:<uid>:<kind>:<path>
        snprintf(line, sizeof(line), "file_done:%s:%u:%s", 
                 sender_hex.c_str(), file_kind, full.c_str());
        G.simple_listener.enqueue_text_line(line);
    }
});
```

#### 2. Dart 层事件处理 (`tim2tox/dart/lib/service/ffi_chat_service.dart`)

**Polling 接收事件**:
```dart
// startPolling() 中的事件处理循环
_poller = Timer(pollInterval, () {
  final n = _ffi.pollText(buf, 4096);
  if (n > 0) {
    final s = buf.cast<pkgffi.Utf8>().toDartString();
    
    if (s.startsWith('file_request:')) {
      // 处理文件传输请求
      _handleFileRequest(s);
    } else if (s.startsWith('progress_recv:')) {
      // 处理接收进度更新
      _handleProgressRecv(s);
    } else if (s.startsWith('file_done:')) {
      // 处理文件接收完成
      _handleFileDone(s);
    }
  }
  scheduleNextPoll();
});
```

**`file_request` 事件处理**:
```dart
// 格式: file_request:<uid>:<file_number>:<size>:<kind>:<filename>
if (s.startsWith('file_request:')) {
  final parts = s.split(':');
  final uid = parts[1];
  final fileNumber = int.tryParse(parts[2]) ?? 0;
  final fileSize = int.tryParse(parts[3]) ?? 0;
  final fileKind = int.tryParse(parts[4]) ?? 0;
  final fileName = parts.sublist(5).join(':');
  
  // 1. 创建 pending 消息（仅非头像文件，kind == 0）
  if (fileKind == 0) {
    // 使用统一的消息ID格式：timestamp_userID（与其他消息保持一致）
    final normalizedUid = uid.length > 64 ? _normalizeFriendId(uid) : uid;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final msgID = '${timestamp}_$normalizedUid';
    final tempPath = '/tmp/receiving_$fileName';
    final msg = ChatMessage(
      msgID: msgID,
      fromUserId: uid,
      filePath: tempPath,
      fileName: fileName,
      isPending: true, // 标记为接收中
    );
    
    // 2. 跟踪文件传输进度
    _fileReceiveProgress[(uid, fileNumber)] = (
      received: 0,
      total: fileSize,
      msgID: msgID,
      fileName: fileName,
      tempPath: tempPath,
      actualPath: null,
    );
    
    // 3. 添加到历史记录和消息流
    _appendHistory(uid, msg);
    _messages.add(msg);
  }
  
  // 4. 自动接受文件传输
  final isImage = _detectKind(fileName) == 'image';
  if (fileKind == 1 || isImage || fileSize < autoAcceptThreshold) {
    await acceptFileTransfer(uid, fileNumber);
  }
}
```

**`progress_recv` 事件处理**:
```dart
// 格式: progress_recv:<uid>:<received>:<total>:<path>
if (s.startsWith('progress_recv:')) {
  final parts = s.split(':');
  final uid = parts[1];
  final received = int.tryParse(parts[2]) ?? 0;
  final total = int.tryParse(parts[3]) ?? 0;
  final path = parts.sublist(4).join(':');
  
  // 1. 更新进度流（供 FakeChatMessageProvider 使用）
  _progressCtrl.add((peerId: uid, path: path, received: received, total: total, isSend: false));
  
  // 2. 更新文件接收进度跟踪
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
        actualPath: path, // 更新实际路径
      );
      foundMsgID = entry.value.msgID;
      foundFileNumber = entry.key.$2;
      break;
    }
  }
  
  // 3. 如果文件传输完成（received >= total），直接调用 _handleFileDone
  // 这样不需要等待 file_done 事件，可以更快地更新消息状态
  if (total > 0 && received >= total && path.isNotEmpty && path.startsWith('/')) {
    await _handleFileDone(uid, 0, path, foundFileNumber, foundMsgID);
  }
}
```

**`file_done` 事件处理**:
```dart
// 格式: file_done:<uid>:<kind>:<path>
if (s.startsWith('file_done:')) {
  final parts = s.split(':');
  final uid = parts[1];
  final fileKind = int.tryParse(parts[2]) ?? 0;
  final path = parts.sublist(3).join(':');
  
  if (fileKind == 0) {
    // 调用统一的文件完成处理函数
    // 如果路径为空或无效，会尝试从 _fileReceiveProgress 中查找完整路径
    await _handleFileDone(uid, fileKind, path, null, null);
  }
}

// _handleFileDone 统一处理文件完成逻辑
Future<void> _handleFileDone(String uid, int fileKind, String path, 
    int? fileNumber, String? existingMsgID) async {
  // 1. 如果路径无效，尝试从 _fileReceiveProgress 中查找
  if (path.isEmpty || !path.startsWith('/')) {
    // ... 从 _fileReceiveProgress 查找完整路径的逻辑 ...
  }
  
  // 2. 如果 existingMsgID 为空，尝试通过 fallback 机制查找或创建消息
  if (existingMsgID == null) {
    // Fallback: 查找最近的 pending 文件消息
    // 如果找不到，创建新消息（处理 file_request 事件未接收的情况）
    // ... fallback 逻辑 ...
  }
  
  // 3. 移动文件到最终位置（使用 _extractFileNameFromPath 提取原始文件名）
  final fileName = _extractFileNameFromPath(path);
  final kind = _detectKind(fileName);
  String finalPath;
  if (kind == 'image') {
    finalPath = await _moveImageToAvatarsDir(path, fileName);
  } else {
    finalPath = await _moveFileToDownloads(path, fileName);
  }
  
  // 4. 更新消息路径和状态
  // ... 更新逻辑 ...
}
```

#### 3. FakeChatMessageProvider 进度更新 (`toxee/lib/sdk_fake/fake_msg_provider.dart`)

**订阅进度更新**:
```dart
// 在构造函数中订阅 progressUpdates stream
ffi.progressUpdates.listen((progress) {
  if (!progress.isSend && progress.path != null) {
    // 查找对应的消息（通过路径、文件名或 msgID 匹配）
    for (final entry in _buffers.entries) {
      for (final msg in entry.value) {
        final isFileMatch = msg.fileElem != null && (
          msg.fileElem!.path == progress.path ||
          msg.fileElem!.path?.startsWith('/tmp/receiving_') == true ||
          msg.msgID?.startsWith('file_recv_') == true ||
          // ... 文件名匹配逻辑 ...
        );
        final isImageMatch = msg.imageElem != null && (
          // ... 类似的匹配逻辑 ...
        );
        
        if (isFileMatch || isImageMatch) {
          // 1. 更新进度跟踪
          _fileProgress[msg.msgID] = (
            received: progress.received,
            total: progress.total,
            path: progress.path,
          );
          
          // 2. 更新消息元素
          if (msg.fileElem != null) {
            msg.fileElem = V2TimFileElem(
              path: progress.path,
              localUrl: (progress.received >= progress.total) ? progress.path : null,
            );
          }
          
          if (msg.imageElem != null) {
            // 创建 imageList 并设置 localUrl
            final imageList = <V2TimImage?>[];
            if (progress.received >= progress.total && progress.path != null) {
              final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
              thumbImage.localUrl = progress.path;
              imageList.add(thumbImage);
              // ... 添加原始图片 ...
            }
            msg.imageElem = V2TimImageElem(
              path: progress.path,
              imageList: imageList.isNotEmpty ? imageList : null,
            );
          }
          
          // 3. 通知 UI 更新
          _ctrls[convID]?.add([msg]);
        }
      }
    }
  }
});
```

#### 4. 完整流程图

```
发送方发送文件
  ↓
toxcore 文件传输协议
  ↓
接收方 C++ 层 (tim2tox_ffi.cpp)
  ├─ OnFileRecv 回调
  │   └─ 发送 file_request 事件到 polling queue
  │
  ├─ acceptFileTransfer (Dart 调用 fileControlNative)
  │   └─ 接受文件传输，开始接收数据
  │
  ├─ OnRecvFileData 回调（每个数据块）
  │   ├─ 写入文件数据
  │   └─ 发送 progress_recv 事件到 polling queue
  │
  └─ OnRecvFileData 回调（length == 0，文件完成）
      └─ 发送 file_done 事件到 polling queue
  ↓
Dart 层 Polling (tim2tox/dart/lib/service/ffi_chat_service.dart)
  ├─ 接收 file_request 事件
  │   ├─ 创建 pending 消息（msgID: timestamp_userID，统一格式）
  │   ├─ 设置临时路径（/tmp/receiving_<filename>）
  │   ├─ 跟踪文件传输进度
  │   └─ 自动接受文件传输（如果是图片或小文件）
  │
  ├─ 接收 progress_recv 事件
  │   ├─ 更新 _fileReceiveProgress
  │   ├─ 发送到 _progressCtrl stream
  │   └─ 如果 received >= total，直接调用 _handleFileDone（不等待 file_done 事件）
  │
  └─ 接收 file_done 事件
      ├─ 调用 _handleFileDone 统一处理
      ├─ Fallback: 如果消息不存在，查找或创建 pending 消息
      ├─ 移动文件到最终位置（avatars 或 Downloads）
      └─ 更新消息路径和状态
  ↓
FakeChatMessageProvider (fake_msg_provider.dart)
  ├─ 订阅 progressUpdates stream
  ├─ 匹配消息（通过路径、文件名或 msgID）
  ├─ 更新消息的 fileElem/imageElem
  │   ├─ 更新 path
  │   └─ 更新 localUrl（当文件完成时）
  └─ 通知 UI 更新
  ↓
UIKit 显示文件
  ├─ 检查 hasLocal（通过 imageList[].localUrl）
  ├─ 如果完成：显示文件
  └─ 如果接收中：显示进度
```

#### 5. 关键实现细节

**消息ID格式**:
- 文件接收消息：`timestamp_userID`（与其他消息统一格式）
- 例如：`1765459900999_10F189D746EF383F1A731AFDBE72FCA99289E817721D5F25C1C67D8B351E034F`
- 确保唯一性和可追溯性，简化消息匹配逻辑

**路径管理**:
- 临时路径：`/tmp/receiving_<filename>`（接收中）
- 最终路径：
  - 图片：`<appDir>/avatars/<basename>_<timestamp><ext>`
  - 其他文件：`<Downloads>/<filename>`

**进度跟踪**:
- `_fileReceiveProgress`: 跟踪文件接收进度（`(uid, fileNumber)` → 进度信息）
- `_fileProgress` (FakeChatMessageProvider): 跟踪消息进度（`msgID` → 进度信息）

**自动接受策略**:
- 头像文件（kind == 1）：自动接受
- 图片文件：自动接受
- 小文件（< 用户配置的阈值，默认30MB）：自动接受
- 大文件：需要用户手动接受（通过 UIKit 的下载按钮）

**消息匹配逻辑**:
- 通过 `fileNumber` 和 `uid` 匹配（最准确）
- 通过文件名和文件大小匹配（回退方案）
- 通过路径匹配（临时路径或最终路径）
- 使用 `_extractFileNameFromPath` 辅助函数从带ID前缀的路径中提取原始文件名
  - 支持格式：`ID_fileNumber_chunkSize_originalFileName`
  - 自动移除ID前缀，提取原始文件名用于匹配

#### 6. 自适应Polling机制

**实现位置**: `tim2tox/dart/lib/service/ffi_chat_service.dart` (自适应polling机制)

为了优化文件传输性能和减少CPU使用，实现了自适应polling间隔机制：

- **文件传输期间**: 50ms（非常频繁，确保事件及时处理）
  - 当 `_fileReceiveProgress` 或 `_pendingFileTransfers` 不为空时触发
- **活跃期间**: 200ms（最近2秒内有活动）
  - 用于处理其他实时事件
- **空闲期间**: 1000ms（默认间隔，减少CPU使用）
  - 当没有活动时使用

这种机制确保了文件传输的及时性，同时在不传输文件时减少资源消耗。

#### 7. 文件接收失败处理

**实现位置**: `tim2tox/dart/lib/service/ffi_chat_service.dart` (文件接收失败处理)

当客户端退出或重启后，可能存在未完成的文件接收（pending状态）。`_cancelPendingFileTransfers` 方法会：

1. **遍历所有历史消息**，查找pending的接收文件消息
2. **标记为失败**（`isPending=false`）而不是删除，保留消息记录
3. **清理跟踪数据**：清除 `_fileReceiveProgress`、`_pendingFileTransfers` 和 `_msgIDToFileTransfer`
4. **保存更新后的历史**，确保重启后不会继续显示loading状态

这样可以防止UI一直显示转圈，同时保留失败的文件消息记录。

#### 8. Fallback机制

**实现位置**: `tim2tox/dart/lib/service/ffi_chat_service.dart` (Fallback机制)

如果 `file_request` 事件未被接收（可能由于polling延迟或其他原因），在 `file_done` 事件处理中实现了fallback机制：

1. **查找最近的pending消息**：通过检查 `isPending=true` 和 `filePath` 以 `/tmp/receiving_` 开头
2. **更新现有消息**：如果找到匹配的pending消息，更新其路径和状态
3. **创建新消息**：如果找不到，创建新的消息记录（处理完全错过 `file_request` 的情况）

这确保了即使 `file_request` 事件丢失，文件接收仍然能够正常完成。

#### 9. 已知问题和限制

**问题 1: 文件路径更新时机**
- **现象**: `file_done` 事件处理是异步的，文件移动可能需要时间
- **影响**: UI 可能在文件移动完成前尝试访问文件，导致显示失败
- **缓解措施**: `progress_recv` 在完成时直接调用 `_handleFileDone`，减少延迟

**问题 2: 文件传输超时**
- **现象**: 如果文件传输过程中断或超时，消息可能一直保持pending状态
- **影响**: UI 会一直显示loading状态
- **缓解措施**: 客户端重启后通过 `_cancelPendingFileTransfers` 标记为失败

**限制 3: 群组媒体/文件传输**
- **现象**: Tox group/conference 当前没有可用的文件传输通道
- **影响**: 群聊图片、视频和文件不会进入 pending 队列
- **缓解措施**: `FakeChatMessageProvider.sendImage/sendFile` 在 `groupID` 存在时快速失败，避免 UI 留下永远不会完成的发送气泡

## 好友管理实现

### 添加好友

```dart
// Tim2ToxSdkPlatform.addFriend()
@override
Future<V2TimFriendOperationResult> addFriend({
  required String userID,
  String? remark,
  String? wording,
}) async {
  // 调用 FfiChatService
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

### 接受好友申请

```dart
// Tim2ToxSdkPlatform.acceptFriendApplication()
@override
Future<V2TimFriendOperationResult> acceptFriendApplication({
  required V2TimFriendApplication application,
}) async {
  await ffiService.acceptFriendRequest(application.userID);

  // 发出好友添加事件
  _notifyFriendListAdded([application.userID]);

  return V2TimFriendOperationResult(
    resultCode: 0,
    resultInfo: 'success',
    userID: application.userID,
  );
}
```

好友申请列表会把用户“忽略/关闭”的申请记录为 `<userId>|<wording>` 指纹，用于过滤重复 wording。接受好友申请时必须先确认 FFI `acceptFriendRequest` 成功；成功后再清理该 `userId` 下所有 dismissed 指纹，保证同一联系人重新申请或申请 wording 变化时不会被旧忽略状态挡住。

## 群组管理实现

### 创建群组

```dart
// Tim2ToxSdkPlatform.createGroup()
@override
Future<V2TimGroupInfoResult> createGroup({
  required String groupType,
  required String groupName,
  List<String>? memberList,
}) async {
  // 调用 FfiChatService
  final groupID = await ffiService.createGroup(groupName);
  
  if (groupID != null) {
    // 创建群组信息
    final groupInfo = V2TimGroupInfo(
      groupID: groupID,
      groupName: groupName,
      groupType: GroupType.Work,
    );
    
    // 保存群组名称到偏好设置
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

### 获取群组列表

```dart
// Tim2ToxSdkPlatform.getGroupList()
@override
Future<V2TimGroupInfoResult> getGroupList() async {
  final groups = ffiService.knownGroups;
  final groupInfoList = <V2TimGroupInfo>[];
  
  for (final groupID in groups) {
    // 从偏好设置获取群组名称和头像
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

## 消息失败处理

### 超时机制

**实现位置**：`chat-uikit-flutter/tencent_cloud_chat_message/lib/model/tencent_cloud_chat_message_data_tools.dart`

**超时时间**：
- 文本消息：5秒
- 文件消息：根据文件大小动态计算（基础60秒 + 文件大小/100KB/s，最大300秒）

**实现方式**：
```dart
final timeoutSeconds = TencentCloudChatFailedMessagePersistence.getTimeoutSeconds(messageInfo);
final sendMsgRes = await sendMessageFuture.timeout(
  Duration(seconds: timeoutSeconds),
  onTimeout: () => V2TimValueCallback(code: -1, desc: 'Message send timeout', data: messageInfo),
);
```

### 离线检测

**实现位置**：
- `chat-uikit-flutter/tencent_cloud_chat_message/lib/model/tencent_cloud_chat_message_separate_data.dart`
- `toxee/lib/sdk_fake/fake_msg_provider.dart`

**检测逻辑**：
- 发送前检查联系人是否在线
- 如果离线，立即标记为失败，无需等待超时
- 适用于所有消息类型

### 持久化存储

**实现位置**：`chat-uikit-flutter/tencent_cloud_chat_common/lib/utils/tencent_cloud_chat_failed_message_persistence.dart`

**存储方式**：
- 使用 `SharedPreferences` 存储失败消息
- 按会话（`conversationKey`）组织失败消息列表
- 保存消息的完整信息（ID、内容、时间戳等）

### 状态恢复

**恢复时机**：
1. 客户端启动时
2. 加载消息历史时
3. 切换会话时

**恢复逻辑**：
- 从持久化存储加载失败消息
- 将失败消息添加到消息列表
- 标记消息状态为 `V2TIM_MSG_STATUS_SEND_FAIL`
- 恢复消息内容（如 `textElem`）
- 更新会话列表的 `lastMessage`

## 消息ID管理

### 统一格式

所有消息ID使用 `timestamp_userID` 格式（毫秒级时间戳）：

**格式**：`<timestamp>_<userID>`

**示例**：`1766503112612_1F583DEE2E26AFAF21825AA24D16C55487C9151A267C8FE34B47151B1A784F3D50425B616B2B`

### ID生成

1. **Tim2ToxSdkPlatform**：创建消息时使用 `ffiService.selfId` 生成
2. **setAdditionalInfoForMessage**：确保所有消息ID使用统一格式，替换 `created_temp_id` 和 `unknown`

## 持久化存储

### 概述

toxee 使用两种主要的持久化存储方式：

1. **SharedPreferences**: 用于存储配置、缓存和元数据
2. **文件系统**: 用于存储 Tox 配置文件、聊天记录、头像和下载文件

### 存储位置

```
<Application Support Directory>/
├── tim2tox/
│   └── tox_profile_<toxId>.tox          # Tox 配置文件（每个账号一个）
├── chat_history/
│   └── <conversationId>.json            # 聊天记录（每个会话一个文件）
├── offline_message_queue.json           # 离线消息队列
├── avatars/                              # 头像文件目录
│   ├── self_avatar<ext>                 # 自己头像
│   └── <basename>_<timestamp><ext>      # 好友头像
└── file_recv/                            # 临时文件接收目录（C++ 层使用）
```

**Application Support Directory 路径示例**：
- **macOS**: `~/Library/Application Support/com.example.toxee/`
- **Windows**: `%APPDATA%\com.example.toxee\`
- **Linux**: `~/.local/share/com.example.toxee/`

### 统一持久化方案

**重要更新**：已实现统一的持久化逻辑，Platform接口方案和二进制替换方案现在使用同一份持久化代码（`MessageHistoryPersistence`、`OfflineMessageQueuePersistence`），数据格式完全一致。

#### 消息历史持久化

**存储位置**：
- 目录：`<Application Support Directory>/chat_history/`
- 文件命名：`<conversationId>.json`（conversationId 中的非法字符会被替换为 `_`）

**存储格式**：
```json
{
  "conversationId": "10F189D746EF383F1A731AFDBE72FCA99289E817721D5F25C1C67D8B351E034F",
  "messages": [
    {
      "text": "消息内容",
      "fromUserId": "发送者ID",
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

**持久化触发时机**：
- 接收新消息时（`c2c:` 事件）
- 接收群组消息时（`gtext:` 事件）
- 发送消息成功时
- 文件接收完成时
- 消息状态更新时（如 `isPending` 从 `true` 变为 `false`）

**内存管理**：
- 限制内存中最多保留 1000 条消息
- 超出限制时自动删除最旧的消息
- 异步保存，不阻塞当前操作

**初始化时加载**：
- 应用启动时，`FfiChatService.init()` 会调用 `_loadAllHistories()`
- 扫描 `chat_history` 目录下的所有 `.json` 文件
- 逐个加载并恢复到 `_historyById` 内存映射中
- 加载时会标记所有 `isPending=true` 的历史消息为 `isPending=false`（防止重启后重复发送）

#### 二进制替换方案的持久化

**实现方式**：
- `BinaryReplacementHistoryHook`：包装 `V2TimAdvancedMsgListener`，自动保存接收的消息
- `BinaryMessageManagerWrapper`：可选包装类，拦截历史查询并从持久化服务读取
- 使用相同的持久化服务和数据格式

**关键代码位置**：
- `tim2tox/dart/lib/utils/binary_replacement_history_hook.dart`
- `tim2tox/dart/lib/utils/message_history_persistence.dart`

#### Platform接口方案的持久化

**实现方式**：
- `FfiChatService` 直接使用持久化服务
- 消息接收和发送时自动保存
- 使用相同的持久化服务和数据格式

**关键代码位置**：
- `tim2tox/dart/lib/service/ffi_chat_service.dart`
- `tim2tox/dart/lib/utils/message_history_persistence.dart`

### Tox 配置存储

**存储位置**：
- 路径：`<Application Support Directory>/tim2tox/tox_profile_<toxId>.tox`

**文件格式**：
- 二进制 .tox 格式（兼容 qTox）
- 包含 Tox 实例的完整状态（密钥对、好友列表、群组信息、DHT 节点信息等）

**加密支持**：
- 支持密码加密（使用 Tox 标准加密）
- 加密后大小：原始大小 + 80 字节

### SharedPreferences 存储内容

**群组相关**：
- `known_groups`: 已知群组 ID 列表
- `quit_groups`: 已退出群组 ID 列表
- `group_chat_id_<groupId>`: 群组 chat_id
- `group_name_<groupId>`: 群组名称
- `group_avatar_<groupId>`: 群组头像路径
- `group_type_<groupId>`: 群组类型（"group" 或 "conference"）

**好友相关**：
- `friend_nickname_<friendId>`: 好友昵称
- `friend_status_msg_<friendId>`: 好友状态消息

**账号相关**：
- `accounts`: 账号列表
- `current_account`: 当前账号 ID

**其他**：
- `self_nickname`: 自己的昵称
- `self_status_msg`: 自己的状态消息
- `self_avatar_path`: 自己的头像路径

### 数据清理和迁移

**清理时机**：
- 退出群组时：删除对应的历史文件和离线消息队列
- 删除会话时：删除对应的历史文件
- 账号切换时：清理旧账号的数据（可选）

**迁移支持**：
- 两种方案的数据格式完全一致，可以互相读取
- 切换方案时数据无缝迁移

## 账号与会话生命周期

### AccountService 的职责

`AccountService` 现在是账号生命周期的统一入口，覆盖：

- 账号初始化：解析账号目录、恢复 profile、创建 `FfiChatService`
- 会话启动：执行 `init()`、`login()`、`updateSelfProfile()`，并按需决定是否立刻 `startPolling()`
- 会话销毁：按顺序销毁 `FakeUIKit`、`Tim2ToxSdkPlatform`、Provider registry、IRC 缓存和 `FfiChatService`
- 账号切换与退出：确保旧账号的静态状态和 listener 被清空，避免跨账号串数据

自动登录、手动登录、账号切换现在不再是三套独立的初始化逻辑，而是共用 `AccountService`，只在“是否延迟 startPolling”和“是否等待连接完成”上有差异。

### 账号存储模型

每个账号拥有独立目录和运行态资源：

- `tox_profile.tox`：账号 profile
- `chat_history/`：按账号隔离的历史消息目录
- `offline_message_queue.json`：离线队列
- `avatars/`：头像缓存
- `file_recv/`：文件接收目录

自动登录路径使用 `startPolling: false`，目的是让 `_StartupGate` 自己控制连接等待、好友预加载和首屏跳转时机。

完整 `.zip` 备份会携带 profile、历史、离线队列、头像目录和 `metadata.json`。头像路径在导出时改写为 `@account_data/...`，导入时再映射到当前机器的账号目录；导入前会预检 `chat_history/` 和 `avatars/` 条目，拒绝越界路径、Windows drive 前缀和反斜杠路径，避免恶意归档写出账号目录或留下部分恢复状态。

## 通话与扩展能力

### 通话系统

客户端通话链路由三层组成：

- `FakeUIKit.startWithFfi()`：创建 `CallStateNotifier` 和 `CallServiceManager`
- `HomePage.initState()`：在 `Tim2ToxSdkPlatform` 设置完成后调用 `callServiceManager.initialize()`
- `CallServiceManager`：串联 `ToxAVService`、`CallBridgeService`、`TUICallKitAdapter` 与 TUICore 注册

当前支持两条通话路径：

- **Signaling 路径**：UIKit 发起通话 → `TUICallKitAdapter` 创建 invite → `CallBridgeService` 处理接受/拒绝/超时 → `ToxAVService` 建立媒体流
- **Native ToxAV 路径**：直接接收来自 qTox 等外部 ToxAV 呼叫，使用 `native_av_<friendNumber>` 形式的 inviteID 映射到 UI 层

通话结束时，`FakeUIKit` 会把通话记录写入 `FfiChatService` 历史，并同步注入 event bus 与 UIKit messageData，保证历史和当前会话都能看到通话记录。

### 插件与扩展

HomePage 还负责扩展能力的接入：

- `sticker`：优先在 message 组件注册前同步接入；若 `selfId` 尚未就绪，则在连接成功后补注册
- `textTranslate` / `soundToText`：懒注册
- `LanBootstrapServiceManager`：桌面端本地 Bootstrap 服务管理
- `IrcAppManager`：IRC 动态库加载、频道与群组映射、自动重连入口

更完整的链路说明见 [CALLING_AND_EXTENSIONS.md](CALLING_AND_EXTENSIONS.md)。

## Tim2tox 接口兼容性与回归验证

### 与 auto_tests 的接口差异

toxee 使用**单实例**（instance_id=0），而 `tim2tox/auto_tests` 使用**多实例**。以下接口为 auto_tests 专用，toxee 无需使用：

- `FfiChatService.registerInstanceForPolling(instanceId)`：多节点轮询注册
- `runWithInstanceAsync` / `runWithInstance`：多实例上下文切换
- `createTestInstance` / `destroyTestInstance`：测试实例创建与销毁

toxee 直接使用的接口（`getFriendList`、`getFriendApplications`、`startPolling`、`knownGroups` 等）与 tim2tox 当前实现兼容。`getFriendApplications()` 内部使用 `getFriendApplicationsForInstance(0, ...)`，单实例下行为正确。

回调 Future 桥接使用 `NativeLibraryManager.addTimCallback2Map(...)` 和 `addTimValueCallback2Map(...)`。这组名称覆盖当前 bootstrap 后的 SDK API；不要再调用旧文档/旧补丁中出现的 `timCallback2Future` / `timValueCallback2Future` 名称，否则在 8.8/8.9 之间切换 SDK 时容易出现 analyzer 或运行期不兼容。

### 回归验证清单

在 tim2tox 接口更新后，建议验证以下场景：

| 场景 | 验证项 | 说明 |
|------|--------|------|
| **好友申请列表** | 待处理申请正确展示 | 使用 `FfiChatService.getFriendApplications()`，确认 instance_id=0 时返回正确 |
| **会话列表更新** | 发送/接收消息后会话列表刷新 | 依赖 Tim2ToxSdkPlatform 的 `onConversationChanged` 通知 |
| **文件传输** | 发送、接收、进度、取消 | 依赖 `startPolling()` 消费 file_request，已在 main.dart 显式调用 |

运行应用后，依次验证：添加好友申请 → 接受/拒绝 → 会话列表；发送 C2C 消息 → 会话置顶；发送/接收文件 → 进度显示与取消。

## 总结

toxee 的实现展示了如何：

1. **通过适配器模式**连接 Tim2Tox 和客户端
2. **使用事件总线**进行组件间通信
3. **实现双重数据路径**（SDK Events + Data Streams）
4. **处理各种消息类型**（文本、图片、文件等）
5. **管理好友和群组**
6. **实现完整的失败消息处理机制**（离线检测、超时检测、持久化存储、状态恢复）
7. **统一消息ID格式**（`timestamp_userID`）

关键实现要点：
- 所有客户端依赖通过接口注入
- 适配器将 Tim2Tox 接口映射到具体实现
- 事件总线解耦组件
- 延迟初始化确保正确的初始化顺序
- 失败消息持久化确保状态不丢失
- 统一消息ID格式确保消息匹配正确

详见本文“失败消息恢复流程”小节与 [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) 了解失败消息处理与排查方法。
