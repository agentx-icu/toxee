# toxee 架构
> 语言 / Language: [中文](ARCHITECTURE.md) | [English](ARCHITECTURE.en.md)

本文描述客户端**整体架构与数据流**，为概览。混合架构的职责与**推荐初始化顺序**以 [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.md) 或 [MAINTAINER_ARCHITECTURE.md](MAINTAINER_ARCHITECTURE.md) 为权威；维护者视角与「最容易改坏的地方」见 [MAINTAINER_ARCHITECTURE.md](MAINTAINER_ARCHITECTURE.md)。

## 目录

1. [概述](#概述)
2. [整体架构](#整体架构)
3. [核心组件](#核心组件)
4. [数据流](#数据流)
5. [接口适配器](#接口适配器)
6. [适配层](#适配层)
7. [初始化流程](#初始化流程)
8. [关键设计决策](#关键设计决策)
9. [持久化方案](#持久化方案)

## 概述

toxee 是一个基于 Tim2Tox 的示例 Flutter 聊天客户端。它展示了如何将 Tim2Tox 集成到 Tencent Cloud Chat UIKit 中，实现完全去中心化的 P2P 聊天功能。

### 最新更新

- ✅ **模块化架构**: Tim2Tox FFI 层已完全模块化，从原来的3200+行单文件拆分为13个功能模块
- ✅ **构建优化**: 使用 DEBUG 模式构建，包含完整调试符号，便于调试
- ✅ **日志系统**: 统一的日志系统，支持实时查看应用日志
- ✅ **稳定性验证**: 应用可以稳定运行，无崩溃报告
- ✅ **统一持久化方案**: Platform接口方案和二进制替换方案使用同一份持久化代码，数据格式完全一致
- ✅ **多实例支持**: Tim2Tox 现在支持创建多个独立的 Tox 实例（主要用于测试场景），toxee 使用默认实例，无需特殊配置

### 设计原则

1. **Tim2Tox 独立性**: Tim2Tox (`tim2tox_dart`) 完全独立，不依赖任何客户端代码
2. **接口抽象**: 通过接口注入客户端依赖，实现依赖反转
3. **适配器模式**: 客户端通过适配器将 Tim2Tox 接口映射到具体实现
4. **UIKit 优先**: 尽可能使用 UIKit 组件，只编写必要的适配代码

## 整体架构

toxee 实际维护的是三种概念上的集成形态：

- **纯二进制替换**：只设置 `setNativeLibraryName('tim2tox_ffi')`
- **Platform 接口方案**：只通过 `Tim2ToxSdkPlatform` 路由 SDK 调用
- **混合架构**：二进制替换负责大多数 Native 调用，`Tim2ToxSdkPlatform` 负责历史消息、自定义 callback、通话和部分扩展能力

当前客户端使用的是**混合架构**。

### 当前使用的方案：混合架构

**特点**：
- 动态库替换为 `libtim2tox_ffi`，C++ 回调经 NativeLibraryManager 派发
- **必须设置** `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform`：由 `SessionRuntimeCoordinator.ensureInitialized()` 在满足 `instance is! Tim2ToxSdkPlatform` 时设置；自动登录路径在 `AppBootstrapCoordinator.boot()` 中（进入 HomePage 之前）调用，手动登录路径在 `HomePage._initAfterSessionReady()` 中调用；必须在首屏或更早完成，供历史查询及 clearHistoryMessage、groupQuitNotification 等 C++ 特殊回调使用
- 消息发送、会话/好友数据经 FakeUIKit 直接走 FfiChatService
- `CallServiceManager`、TUICallKit 适配、贴纸/翻译/语音插件在 HomePage 阶段接入

详见 [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.md)。

**调用路径**：
```
UIKit SDK
  ↓
TIMManager.instance
  ↓
NativeLibraryManager (原生 SDK 的调用方式)
  ↓
bindings.DartXXX(...) (FFI 动态查找符号)
  ↓
libtim2tox_ffi.dylib (替换后的动态库)
  ↓
dart_compat_layer.cpp (Dart* 函数实现)
  ↓
V2TIM*Manager (C++ API 实现)
  ↓
ToxManager (Tox 核心)
  ↓
c-toxcore (P2P 通信)
```

### 备选方案：Platform 接口方案

**特点**：
- 需要设置 `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(...)`
- 使用高级服务层（FfiChatService）提供更丰富的功能
- 需要修改 Dart 层代码

**调用路径**：
```
UIKit SDK
  ↓
TencentCloudChatSdkPlatform.instance (Tim2ToxSdkPlatform)
  ↓
FfiChatService (高级服务层)
  ↓
Tim2ToxFfi (FFI 绑定)
  ↓
tim2tox_ffi_* (C FFI 接口)
  ↓
V2TIM*Manager (C++ API 实现)
  ↓
ToxManager (Tox 核心)
  ↓
c-toxcore (P2P 通信)
```

### 架构图（混合架构 / 当前方案）

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
        │   Tencent Cloud Chat SDK (原生调用方式)     │
        │  ┌──────────────────────────────────────┐  │
        │  │  TIMManager.instance                │  │
        │  │  NativeLibraryManager               │  │
        │  │  bindings.DartXXX(...)              │  │
        │  └──────────────┬───────────────────────┘  │
        └─────────────────┼─────────────────────────┘
                          │
        ┌─────────────────▼─────────────────┐
        │    libtim2tox_ffi.dylib           │
        │  (替换后的动态库)                  │
        │  ┌──────────────────────────────┐ │
        │  │  dart_compat_layer.cpp       │ │
        │  │  (Dart* 函数实现)             │ │
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

## 集成方案对比

### 方案一：纯二进制替换方案

**实现方式**：
- 在 `native_library_manager.dart` 中将动态库名称从 `dart_native_imsdk` 改为 `tim2tox_ffi`
- **不设置** `TencentCloudChatSdkPlatform.instance`
- 直接使用 `TIMManager.instance` → `NativeLibraryManager` → Dart* 函数

**调用路径**：
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
  ↓
tox_new() (c-toxcore)
```

**优势**：
- ✅ **最少接入点**：理论上只需替换动态库并提前调用 `setNativeLibraryName(...)`
- ✅ **完全兼容**：函数签名和回调格式完全匹配原生 SDK
- ✅ **易于部署**：只需替换动态库文件
- ✅ **工作量少**：只实现实际使用的函数（约 68 个）

**限制**：
- 函数签名必须完全匹配原生 SDK
- JSON 格式必须与原生 SDK 完全一致
- 依赖 Dart API DL 的回调机制

**关键文件**：
- tencent_cloud_chat_sdk 包（bootstrap 后位于 `third_party/tencent_cloud_chat_sdk`）内的 `lib/native_im/bindings/native_library_manager.dart` — 动态库加载
- `tim2tox/ffi/dart_compat_layer.cpp` - Dart* 函数实现
- `tim2tox/ffi/callback_bridge.cpp` - 回调桥接机制

### 方案二：Platform 接口方案（备选）

**实现方式**：
- 设置 `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(...)`
- 使用高级服务层（FfiChatService）提供更丰富的功能
- 需要修改 Dart 层代码

**调用路径**：
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

**优势**：
- ✅ **功能丰富**：高级服务层提供消息历史、轮询、状态管理等
- ✅ **灵活性强**：可以自定义实现逻辑
- ✅ **易于扩展**：可以添加自定义功能

**限制**：
- 需要修改 Dart 层代码
- 需要维护 Platform 接口实现
- 工作量较大（需要实现更多接口）

**关键文件**：
- `tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart` - Platform 接口实现
- `tim2tox/dart/lib/service/ffi_chat_service.dart` - 高级服务层
- `toxee/lib/sdk_fake/` - 数据适配层

### 方案三：混合架构（当前使用）

**实现方式**：
- `setNativeLibraryName('tim2tox_ffi')` 由 `main()` → `AppBootstrap.initialize()` → `LoggingBootstrap.initialize()` 设置；
- `_StartupGate` / `LoginPage` 通过 `AccountService.initializeServiceForAccount(..., startPolling: false)` 创建并登录 `FfiChatService`；
- 登录成功后调用 `AppBootstrapCoordinator.boot(service)`：依次执行 `SessionRuntimeCoordinator.ensureInitialized()`（在此处安装 `Tim2ToxSdkPlatform`、启动 `FakeUIKit`、调用 `CallServiceManager.initialize()`）、`TimSdkInitializer.ensureInitialized()`（`TIMManager.initSDK`）、`service.startPolling()`；
- `HomePage._initAfterSessionReady()` 注册 `BinaryReplacementHistoryHook`、群组/好友监听、UIKit `ChatDataProvider` / `ChatMessageProvider` 与贴纸 / 翻译 / 语音插件。

**特点**：
- 保留二进制替换链路，兼容 UIKit 的 Native 调用习惯
- 用 Platform 路径补齐历史消息、自定义 callback、signaling / ToxAV 桥接和扩展能力
- 是当前代码库真实运行的生产接入方式

### 方案选择建议

**当前使用**：混合架构

**选择原因**：
1. 同时保留 UIKit 兼容性与高级能力
2. 历史消息、群退出清理、chat_id 持久化和通话都已有明确接入点
3. 更符合当前客户端的账号体系、扩展插件和桌面能力

**何时使用 Platform 接口方案**：
1. 做最小验证或隔离调试时，可以考虑纯二进制替换
2. 做独立 SDK 封装或非当前客户端接入时，可以考虑纯 Platform 接口方案
3. 客户端生产形态建议继续沿用混合架构

## 核心组件

### 1. Tim2Tox 层 (`tim2tox_dart` 包)

Tim2Tox 上游仓库：[https://github.com/anonymoussoft/tim2tox](https://github.com/anonymoussoft/tim2tox)。toxee 中通过 submodule 使用于 `third_party/tim2tox`。

#### 1.1 FFI 绑定层 (`lib/ffi/`)

**职责**: 提供 Dart FFI 绑定，直接调用 C FFI 库

**主要类**:
- `Tim2ToxFfi`: FFI 绑定类，封装所有 C FFI 函数调用

**关键方法**:
- `init()`: 初始化 FFI 库
- `login()`: 登录
- `sendMessage()`: 发送消息
- `getFriendList()`: 获取好友列表
- `addFriend()`: 添加好友
- 等等...

#### 1.2 服务层 (`lib/service/`)

**职责**: 提供高级服务 API，管理消息历史、轮询、状态等

**主要类**:
- `FfiChatService`: 核心服务类

**关键功能**:
- 消息历史管理
- 事件轮询
- 好友状态管理
- 文件传输管理
- 离线消息队列

**依赖注入**:
- `ExtendedPreferencesService`: 偏好设置
- `LoggerService`: 日志
- `BootstrapService`: Bootstrap 节点

#### 1.3 SDK Platform 层 (`lib/sdk/`)

**职责**: 实现 `TencentCloudChatSdkPlatform` 接口，将 UIKit SDK 调用路由到 tim2tox

**主要类**:
- `Tim2ToxSdkPlatform`: SDK Platform 实现

**关键功能**:
- 实现所有 V2TIM API
- 管理 SDK 生命周期
- 处理消息、好友、群组操作
- 事件通知

**依赖注入**:
- `FfiChatService`: 核心服务
- `EventBusProvider`: 事件总线（可选）
- `ConversationManagerProvider`: 会话管理器（可选）

#### 1.4 抽象接口层 (`lib/interfaces/`)

**职责**: 定义可注入的依赖接口

**接口列表**:
- `PreferencesService` / `ExtendedPreferencesService`: 偏好设置接口
- `LoggerService`: 日志接口
- `BootstrapService`: Bootstrap 节点接口
- `EventBus` / `EventBusProvider`: 事件总线接口
- `ConversationManagerProvider`: 会话管理器接口

### 2. 客户端层

#### 2.1 接口适配器层 (`lib/adapters/`)

**职责**: 实现 Tim2Tox 的抽象接口，将 Tim2Tox 接口映射到客户端具体实现

**适配器列表**:

1. **SharedPreferencesAdapter**
   - 实现: `ExtendedPreferencesService`
   - 使用: `SharedPreferences`
   - 功能: 存储所有偏好设置数据

2. **AppLoggerAdapter**
   - 实现: `LoggerService`
   - 使用: `AppLogger`
   - 功能: 日志记录

3. **BootstrapNodesAdapter**
   - 实现: `BootstrapService`
   - 使用: `BootstrapNodes` + `SharedPreferences`
   - 功能: Bootstrap 节点管理

4. **EventBusAdapter**
   - 实现: `EventBusProvider`
   - 使用: `FakeEventBus`
   - 功能: 提供事件总线实例

5. **ConversationManagerAdapter**
   - 实现: `ConversationManagerProvider`
   - 使用: `FakeConversationManager`
   - 功能: 提供会话管理功能

#### 2.2 数据适配层 (`lib/sdk_fake/`)

**职责**: 将 tim2tox 数据模型转换为 UIKit 期望的格式

**主要组件**:

1. **FakeIM** (`fake_im.dart`)
   - 事件总线管理器
   - 订阅 `FfiChatService` 事件
   - 发出 `FakeConversation`、`FakeMessage` 等事件
   - 管理会话列表、联系人列表等

2. **FakeManagers** (`fake_managers.dart`)
   - `FakeConversationManager`: 会话管理
   - `FakeMessageManager`: 消息管理
   - `FakeContactManager`: 联系人管理

3. **FakeProviders** (`fake_provider.dart`, `fake_msg_provider.dart`)
   - `FakeChatDataProvider`: 实现 `ChatDataProvider`，提供会话数据
   - `FakeChatMessageProvider`: 实现 `ChatMessageProvider`，处理消息发送

4. **FakeUIKitCore** (`fake_uikit_core.dart`)
   - `FakeUIKit`: UIKit 核心适配器
   - 管理所有 Fake 组件
   - 提供统一的初始化入口

5. **FakeEventBus** (`fake_event_bus.dart`)
   - 事件总线实现
   - 支持类型化事件订阅和发布

6. **FakeModels** (`fake_models.dart`)
   - 客户端特定的数据模型
   - 与 Tim2Tox 的 `Fake*` 模型兼容

#### 2.3 UI 层 (`lib/ui/`)

**职责**: 用户界面组件

**主要组件**:
- `login_page.dart`: 登录/注册页面
- `home_page.dart`: 主页面，包含 UIKit 集成
- `settings/`: 设置页面
- `applications/`: 好友申请页面
- 其他自定义 UI 组件

**UIKit 组件使用**:
- `TencentCloudChatConversation`: 会话列表
- `TencentCloudChatMessage`: 消息页面
- `TencentCloudChatContact`: 联系人页面
- 等等...

#### 2.4 工具层 (`lib/util/`)

**职责**: 客户端特定的工具类

**主要工具**:
- `prefs.dart`: 偏好设置管理（SharedPreferences 封装）
- `logger.dart`: 日志系统
- `bootstrap_nodes.dart`: Bootstrap 节点配置
- `tox_utils.dart`: Tox ID 工具函数
- `theme_controller.dart`: 主题管理
- `locale_controller.dart`: 语言管理

## 数据流

### SDK 调用路径

当前混合架构下，不同操作走不同路径：

- **消息发送、会话/好友**：经 **FakeUIKit → FfiChatService**（不经过 Platform）。例如：FakeChatMessageProvider → FfiChatService.sendMessage；FakeConversationManager/FakeContactManager 直接使用 FfiChatService.getFriendList、knownGroups 等。
- **历史加载**：当 SDK 层 `platform.isCustomPlatform == true`（即已设置 Tim2ToxSdkPlatform）时，`getHistoryMessageListV2` 等走 **TencentCloudChatSdkPlatform.instance → Tim2ToxSdkPlatform → FfiChatService.getHistory / MessageHistoryPersistence**。

```
消息发送 / 会话 / 好友:
  UIKit → FakeUIKit (FakeChatMessageProvider / FakeManagers) → FfiChatService → Tim2ToxFfi → tim2tox_ffi → toxcore

历史查询 (isCustomPlatform 时):
  UIKit SDK (getHistoryMessageListV2) → TencentCloudChatSdkPlatform.instance (Tim2ToxSdkPlatform)
    → FfiChatService.getHistory / MessageHistoryPersistence
```

**重要说明**：
- 所有非Web平台（Windows/Linux/macOS/Android/iOS）下，历史查询等需 Platform 的调用在设置 Tim2ToxSdkPlatform 后路由到 `Tim2ToxSdkPlatform`
- tencent_cloud_chat_sdk 包（bootstrap 后位于 `third_party/tencent_cloud_chat_sdk`）已修改为 `isCustomPlatform` 时走 Platform 路径，完全移除了对原生 IM SDK 的依赖（除了 Web 平台）
- 消息ID统一使用 `timestamp_userID` 格式（毫秒级时间戳），确保唯一性和一致性

### 消息发送路径

文本消息和文件消息的发送路径：

```
UIKit Message Input
  ↓
ChatMessageProvider (FakeChatMessageProvider)
  ↓
离线检测（检查联系人是否在线）
  ├─ 如果离线 → 立即标记为失败 → 保存到持久化存储 → 显示失败状态
  └─ 如果在线 → 继续发送流程
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
超时检测（使用 Future.timeout）
  ├─ 文本消息：5秒超时
  ├─ 文件消息：根据文件大小动态计算（基础60秒 + 文件大小/100KB/s）
  └─ 如果超时 → 标记为失败 → 保存到持久化存储 → 更新UI状态
```

**失败消息处理机制**：
1. **离线检测**：发送前检查联系人是否在线，如果离线立即标记为失败
2. **超时机制**：使用 `Future.timeout` 实现动态超时，根据消息类型和大小调整超时时间
3. **持久化存储**：失败消息保存到 `SharedPreferences`，使用 `TencentCloudChatFailedMessagePersistence` 管理
4. **状态恢复**：客户端重启后自动从持久化存储恢复失败消息状态

### 消息历史持久化

**统一持久化方案**：
- ✅ **两种方案共享同一份持久化代码**：`MessageHistoryPersistence` 和 `OfflineMessageQueuePersistence`
- ✅ **数据格式完全一致**：相同的JSON格式和文件结构
- ✅ **二进制替换方案通过Hook实现**：`BinaryReplacementHistoryHook` 自动拦截消息并保存
- ✅ **Platform接口方案直接使用**：`FfiChatService` 直接调用持久化服务

**存储位置**：
- 消息历史：`<Application Support Directory>/chat_history/<conversationId>.json`
- 离线消息队列：`<Application Support Directory>/offline_message_queue.json`

**持久化服务**：
- `MessageHistoryPersistence`：统一的消息历史持久化服务
  - 自动保存和加载
  - 支持会话级别的历史记录
  - 内存管理（最多保留1000条）
  - 应用重启后自动恢复
- `OfflineMessageQueuePersistence`：统一的离线消息队列持久化服务
  - 管理离线消息队列
  - 应用重启后自动清空（防止重复发送）

**二进制替换方案Hook**：
- `BinaryReplacementHistoryHook`：包装 `V2TimAdvancedMsgListener`，自动保存接收的消息
- `BinaryMessageManagerWrapper`：可选包装类，拦截历史查询并从持久化服务读取

详细说明请参考：[reference/IMPLEMENTATION_DETAILS.md](../reference/IMPLEMENTATION_DETAILS.md) 的消息处理章节，以及 [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.md) 的回调分工说明。

### 消息接收路径

消息和事件的接收路径：

```
toxcore
  ↓
tim2tox (C++)
  ↓
tim2tox_ffi (C)
  ↓
FfiChatService (轮询事件)
  ↓
[两条路径]:
  1. SDK Events:
     Tim2ToxSdkPlatform
       ↓
     UIKit SDK Listeners
       ↓
     UI Updates

  2. Data Streams:
     FakeIM (订阅 FfiChatService)
       ↓
     FakeEventBus (发布事件)
       ↓
     FakeManagers (处理事件)
       ↓
     FakeProviders (提供数据)
       ↓
     UIKit Controllers
       ↓
     UI Updates
```

### 文件接收路径

文件接收涉及多个层次的事件处理和状态管理：

```
toxcore 文件传输协议
  ↓
tim2tox (C++) - OnFileRecv 回调
  ↓
tim2tox_ffi (C) - 发送 file_request 事件到 polling queue
  ↓
FfiChatService (自适应轮询事件)
  ├─ 自适应Polling间隔
  │   ├─ 文件传输期间：50ms（非常频繁）
  │   ├─ 活跃期间（最近2秒有活动）：200ms
  │   └─ 空闲期间：1000ms（减少CPU使用）
  │
  ├─ file_request 事件
  │   ├─ 创建 pending 消息（msgID: timestamp_userID，统一格式）
  │   ├─ 设置临时路径（/tmp/receiving_<filename>）
  │   ├─ 跟踪文件传输进度（_fileReceiveProgress）
  │   └─ 自动接受文件传输（如果是图片或小文件）
  │
  ├─ acceptFileTransfer (调用 fileControlNative)
  │   └─ 通知 C++ 层接受文件传输
  │
  ├─ progress_recv 事件（每个数据块）
  │   ├─ 更新 _fileReceiveProgress
  │   ├─ 发送到 _progressCtrl stream
  │   └─ 如果 received >= total，直接调用 _handleFileDone（不等待 file_done 事件）
  │
  └─ file_done 事件（文件完成）
      ├─ 调用 _handleFileDone 统一处理
      ├─ Fallback: 如果消息不存在，查找或创建 pending 消息
      ├─ 移动文件到最终位置（avatars 或 Downloads）
      └─ 更新消息路径和状态
  ↓
FakeChatMessageProvider (订阅 progressUpdates stream)
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

**关键组件**：

1. **事件队列** (`tim2tox_ffi.cpp`):
   - `file_request`: 文件传输请求
   - `progress_recv`: 接收进度更新
   - `file_done`: 文件接收完成

2. **状态跟踪** (`tim2tox/dart/lib/service/ffi_chat_service.dart`):
   - `_fileReceiveProgress`: 跟踪文件接收进度（`(uid, fileNumber)` → 进度信息）
   - `_pendingFileTransfers`: 跟踪待处理的文件传输
   - `_msgIDToFileTransfer`: 消息ID到文件传输的映射

3. **进度更新** (`fake_msg_provider.dart`):
   - `_fileProgress`: 跟踪消息进度（`msgID` → 进度信息）
   - 订阅 `progressUpdates` stream 更新消息元素

**消息ID格式**：
- 文件接收消息：`timestamp_userID`（与其他消息统一格式）
- 例如：`1765459900999_10F189D746EF383F1A731AFDBE72FCA99289E817721D5F25C1C67D8B351E034F`
- 确保唯一性和可追溯性，简化消息匹配逻辑

**路径管理**：
- 临时路径：`/tmp/receiving_<filename>`（接收中）
- 最终路径：
  - 图片：`<appDir>/avatars/<basename>_<timestamp><ext>`
  - 其他文件：`<Downloads>/<filename>`

**自动接受策略**：
- 头像文件（kind == 1）：自动接受
- 图片文件：自动接受
- 小文件（< 用户配置的阈值，默认30MB）：自动接受
- 大文件：需要用户手动接受（通过 UIKit 的下载按钮）

**文件接收失败处理**：
- 客户端重启后，`_cancelPendingFileTransfers` 方法会标记所有pending的接收文件为失败（`isPending=false`）
- 保留消息记录但不再显示loading状态，防止UI一直转圈
- 清理所有文件传输跟踪数据（`_fileReceiveProgress`、`_pendingFileTransfers`、`_msgIDToFileTransfer`）

## 接口适配器

### 适配器设计模式

客户端通过适配器模式将 Tim2Tox 的抽象接口映射到具体实现：

```
Tim2Tox Interface           Client Implementation
─────────────────          ─────────────────────
ExtendedPreferencesService → SharedPreferencesAdapter → SharedPreferences
LoggerService             → AppLoggerAdapter         → AppLogger
BootstrapService          → BootstrapNodesAdapter     → BootstrapNodes
EventBusProvider          → EventBusAdapter           → FakeEventBus
ConversationManagerProvider → ConversationManagerAdapter → FakeConversationManager
```

### 适配器实现示例

#### SharedPreferencesAdapter

```dart
class SharedPreferencesAdapter implements ExtendedPreferencesService {
  final SharedPreferences _prefs;
  
  @override
  Future<String?> getString(String key) async => _prefs.getString(key);
  
  @override
  Future<void> setString(String key, String value) => 
      _prefs.setString(key, value);
  
  // ... 实现所有必需方法
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

## 适配层

### FakeIM - 事件总线管理器

**职责**: 
- 订阅 `FfiChatService` 的事件
- 将 tim2tox 事件转换为 UIKit 格式
- 通过 `FakeEventBus` 发布事件

**关键方法**:
- `start()`: 启动事件订阅
- `_refreshConversations()`: 刷新会话列表
- `_emitContacts()`: 发出联系人事件
- `_seedHistory()`: 初始化消息历史

### FakeManagers - 管理器

**FakeConversationManager**:
- 管理会话列表
- 处理会话更新
- 管理未读计数

**FakeMessageManager**:
- 管理消息历史
- 处理消息状态
- 管理消息接收者

**FakeContactManager**:
- 管理联系人列表
- 处理联系人更新

### FakeProviders - 数据提供者

**FakeChatDataProvider**:
- 实现 `ChatDataProvider` 接口
- 提供会话数据流
- 提供未读计数流

**FakeChatMessageProvider**:
- 实现 `ChatMessageProvider` 接口
- 处理消息发送
- 支持文本、图片、文件等消息类型

## 初始化流程

### 推荐初始化顺序（混合架构）

当前使用的是混合架构。概念顺序为：`FfiChatService.init` → `login` → `updateSelfProfile` → `SessionRuntimeCoordinator.ensureInitialized`（安装 `FakeUIKit` + `Tim2ToxSdkPlatform`，并调用 `CallServiceManager.initialize()`）→ `TimSdkInitializer.ensureInitialized`（`TIMManager.initSDK`）→ `FfiChatService.startPolling` → `HomePage._initAfterSessionReady` 注册 `BinaryReplacementHistoryHook`、群组/好友监听、UIKit Providers 与插件。详见 [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.md)。

### 完整初始化序列

**自动登录路径（_StartupGate）**（与代码一致）：

```
main()
   ├─ AppBootstrap.initialize()
   │    ├─ LoggingBootstrap.initialize()   // setNativeLibraryName('tim2tox_ffi')，不设置 Platform
   │    ├─ PrefsBootstrap.initialize()
   │    ├─ AppRuntimeBootstrap.initialize()
   │    └─ DesktopShellBootstrap.initializeIfNeeded()
   └─ EchoUIKitApp → _StartupGate

_StartupGate._runStartup() / StartupSessionUseCase.execute（自动登录）
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
   ├─ 等待 connectionStatusStream 或超时
   ├─ 预加载好友与联系人状态
   └─ 导航到 HomePage(service)
```

**手动登录路径（LoginPage / LoginUseCase）**：

```
1. main()
   └─ AppBootstrap.initialize()   // 与自动登录路径一致

2. LoginPage
   ├─ 用户输入昵称 / 状态 / Bootstrap 节点
   ├─ LoginUseCase.execute(...) → AccountService.initializeServiceForAccount(..., startPolling: false)
   ├─ AppBootstrapCoordinator.boot(service)   // SessionRuntime + TIM init + startPolling
   └─ 导航到 HomePage(service)

3. HomePage.initState() → unawaited(_initAfterSessionReady())
   ├─ SessionRuntimeCoordinator(service).ensureInitialized()   // 幂等
   ├─ TimSdkInitializer.ensureInitialized().then((_) {
   │    ├─ _initBinaryReplacementPersistenceHook()
   │    ├─ initGroupListener / initFriendListener
   │  })
   ├─ 注册 ChatDataProviderRegistry、ChatMessageProviderRegistry 等
   └─ 注册 sticker / textTranslate / soundToText 等扩展插件
```

### 初始化代码示例

实际上下面的工作几乎全部由 `SessionRuntimeCoordinator.ensureInitialized()` 完成（在进入 `HomePage` 之前由 `AppBootstrapCoordinator.boot()` 调用）；`HomePage` 只需注册 Provider、history hook 与监听器。

```dart
// lib/runtime/session_runtime_coordinator.dart（示意 — 详见源码）
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
// lib/ui/home_page.dart（示意 — 实际流程详见 lib/ui/home_page_bootstrap.dart）
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
  // sticker / textTranslate / soundToText 插件注册随后进行
}
```

## 关键设计决策

### 1. Tim2Tox 完全独立

**决策**: Tim2Tox (`tim2tox_dart`) 不依赖任何客户端代码

**原因**:
- 提高可复用性
- 便于测试
- 清晰的职责分离

**实现**:
- 所有客户端依赖通过接口注入
- Tim2Tox 只定义接口，不实现具体逻辑

### 2. 适配器模式

**决策**: 使用适配器模式连接 Tim2Tox 和客户端

**原因**:
- 解耦 Tim2Tox 和客户端实现
- 支持不同的客户端实现方式
- 便于测试和替换

**实现**:
- Tim2Tox 定义抽象接口
- 客户端实现适配器类
- 适配器将接口调用映射到具体实现

### 3. 事件总线架构

**决策**: 使用事件总线进行组件间通信

**原因**:
- 解耦组件
- 支持异步事件处理
- 便于扩展

**实现**:
- `FakeEventBus`: 客户端事件总线实现
- `FakeIM`: 订阅 `FfiChatService` 并发布事件
- `FakeManagers`: 订阅事件并更新状态

### 4. 双重数据路径

**决策**: 同时支持 SDK Events 和 Data Streams 两种数据路径

**原因**:
- SDK Events: 直接通知 UIKit SDK 监听器
- Data Streams: 通过事件总线提供数据流，支持更灵活的 UI 更新

**实现**:
- `Tim2ToxSdkPlatform`: 实现 SDK Events
- `FakeIM` + `FakeProviders`: 实现 Data Streams

### 5. 延迟初始化

**决策**: 在 `FfiChatService.init/login` 完成之后由 `SessionRuntimeCoordinator.ensureInitialized()`（在 `AppBootstrapCoordinator.boot()` 中调用）安装 SDK Platform。

**原因**:
- Platform 必须持有与其它组件完全一致的 `FfiChatService` 实例，而该实例只有在 `AccountService.initializeServiceForAccount(...)` 返回后才存在。
- 避免被 `TencentCloudChatSdkWeb`（在插件注册过程中自动安装自身）覆盖。
- 能拿到 `FakeUIKit` 内已构建好的事件总线与会话管理适配器。

**实现**:
- `main()` 不设置 Platform，仅由 `LoggingBootstrap.initialize()` 调用 `setNativeLibraryName('tim2tox_ffi')`。
- `SessionRuntimeCoordinator.ensureInitialized()` 在 `instance is! Tim2ToxSdkPlatform` 时安装 `Tim2ToxSdkPlatform`。它由 `AppBootstrapCoordinator.boot()` 在导航之前调用，并在 `HomePage._initAfterSessionReady()` 中幂等地再次执行。
- **BinaryReplacementHistoryHook** 在 `TimSdkInitializer.ensureInitialized()` 完成后由 `HomePage._initBinaryReplacementPersistenceHook()` 安装。

### 6. 失败消息处理机制

**决策**: 实现完整的失败消息处理流程，包括超时检测、离线检测、持久化存储和状态恢复

**原因**:
- 提供良好的用户体验，明确显示消息发送失败
- 确保失败消息在客户端重启后仍然可见
- 避免消息丢失

**实现**:
- **超时机制**：使用 `Future.timeout` 实现动态超时
  - 文本消息：5秒超时
  - 文件消息：根据文件大小动态计算（基础60秒 + 文件大小/100KB/s，最大300秒）
- **离线检测**：发送前检查联系人是否在线，如果离线立即标记为失败
- **持久化存储**：使用 `TencentCloudChatFailedMessagePersistence` 将失败消息保存到 `SharedPreferences`
- **状态恢复**：客户端重启后，从持久化存储恢复失败消息状态，确保失败消息在聊天窗口和会话列表中正确显示

### 7. 统一持久化方案

**决策**: Platform接口方案和二进制替换方案使用同一份持久化代码

**原因**:
- 确保两种方案的数据格式完全一致
- 两种方案可以互相读取对方保存的数据
- 切换方案时数据无缝迁移
- 代码复用，易于维护

**实现**:
- **统一持久化服务**：
  - `MessageHistoryPersistence`：消息历史持久化服务
  - `OfflineMessageQueuePersistence`：离线消息队列持久化服务
  - `MessageConverter`：V2TimMessage 与 ChatMessage 的双向转换工具
- **Platform接口方案**：
  - `FfiChatService` 直接使用持久化服务
  - 消息接收和发送时自动保存
- **二进制替换方案**：
  - `BinaryReplacementHistoryHook`：包装消息监听器，自动保存接收的消息
  - `BinaryMessageManagerWrapper`：可选包装类，拦截历史查询
  - 使用相同的持久化服务和数据格式

**数据格式**:
- 消息历史：JSON格式，包含conversationId和messages数组
- 离线消息队列：JSON格式，peerId到消息列表的映射
- 存储位置：`<Application Support Directory>/chat_history/` 和 `offline_message_queue.json`

详细说明请参考：[reference/IMPLEMENTATION_DETAILS.md](../reference/IMPLEMENTATION_DETAILS.md) 中的持久化存储章节。

### 8. Group/Conference 恢复机制

**决策**: 实现区分 Group 和 Conference 类型的恢复机制

**原因**:
- Group 和 Conference 使用不同的 Tox API，恢复方式不同
- Group 类型支持 `chat_id` 持久化，可以主动恢复
- Conference 类型依赖 savedata 自动恢复，需要手动匹配

**实现**:
- **类型持久化**：
  - 创建群组时存储 `groupType`（"group" 或 "conference"）
  - 通过 `tim2tox_ffi_set_group_type` 存储到 `SharedPreferences`
  - 恢复时通过 `tim2tox_ffi_get_group_type_from_storage` 读取

- **Group 类型恢复**：
  - 从存储读取 `chat_id`
  - 调用 `tox_group_join(chat_id)` 主动恢复
  - 成功后会触发 `onGroupSelfJoin` 回调重建映射
  - **优势**：主动恢复，不依赖 savedata，即使 savedata 丢失也能恢复

- **Conference 类型恢复**：
  - Tox 初始化时从 savedata 自动恢复
  - 查询 `tox_conference_get_chatlist()` 获取已恢复的 conferences
  - 匹配未映射的 `conference_number` 到 `group_id`
  - **限制**：完全依赖 savedata，如果 savedata 丢失则无法恢复

- **恢复时机**：
  - `InitSDK()` 时立即尝试恢复
  - 网络连接建立后再次尝试恢复（`HandleSelfConnectionStatus`）
  - 等待 Tox 连接建立后再重新加入（确保网络可用）

**恢复流程**：

#### Group 类型恢复流程
```
1. RejoinKnownGroups() 被调用
   ↓
2. 从 Dart 层获取所有 knownGroups
   ↓
3. 对每个 group_id：
   a. 检查 groupType（从存储读取）
   b. 如果是 "group" 类型：
      - 从存储读取 chat_id
      - 转换 hex 字符串为二进制
      - 调用 tox_group_join(chat_id)
      - 等待 onGroupSelfJoin 回调
      - 在 HandleGroupSelfJoin 中重建映射
```

#### Conference 类型恢复流程
```
1. Tox 初始化时加载 savedata
   ↓
2. Conferences 自动从 savedata 恢复
   ↓
3. RejoinKnownGroups() 被调用
   ↓
4. 查询 tox_conference_get_chatlist() 获取已恢复的 conferences
   ↓
5. 对每个 group_id：
   a. 检查 groupType（从存储读取）
   b. 如果是 "conference" 类型：
      - 查找未映射的 conference_number
      - 将 conference_number 映射到 group_id
      - 重建映射关系
```

**关键代码位置**:
- `tim2tox/source/V2TIMManagerImpl.cpp::RejoinKnownGroups()`
- `tim2tox/source/V2TIMManagerImpl.cpp::InitSDK()`
- `tim2tox/source/V2TIMManagerImpl.cpp::HandleSelfConnectionStatus()`
- `tim2tox/ffi/tim2tox_ffi.cpp::tim2tox_ffi_set_group_type()`

### 9. SDK 初始化流程

**决策**: 在客户端启动时正确初始化 SDK，确保所有组件按正确顺序初始化

**原因**:
- 确保 SDK 在 UIKit 插件注册之后初始化
- 避免被默认平台（如 `TencentCloudChatSdkWeb`）覆盖
- 确保所有依赖服务已准备就绪

**初始化流程**：

#### 1. 用户登录阶段

```
LoginPage._login() / LoginUseCase.execute()
  ↓
AccountService.initializeServiceForAccount(toxId, ..., startPolling: false)
  ├─ FfiChatService.init(profileDirectory)
  ├─ FfiChatService.login(...)
  └─ FfiChatService.updateSelfProfile(...)
  ↓
AppBootstrapCoordinator.boot(service)
  ├─ SessionRuntimeCoordinator(service).ensureInitialized()   // FakeUIKit + Tim2ToxSdkPlatform + CallServiceManager.initialize()
  ├─ TimSdkInitializer.ensureInitialized()                    // TIMManager.initSDK
  └─ service.startPolling()
  ↓
Navigator.pushReplacement(HomePage(service: service))
```

#### 2. HomePage 初始化阶段

```
HomePage.initState() → unawaited(_initAfterSessionReady())
  ↓
SessionRuntimeCoordinator(service).ensureInitialized()       // 幂等再执行一次
  ↓
TimSdkInitializer.ensureInitialized().then((_) {
  ├─ _initBinaryReplacementPersistenceHook()  // selfId 为空时监听 connectionStatusStream 再 _setupPersistenceHook
  ├─ initGroupListener()
  └─ initFriendListener()
})
  ↓
注册 ChatDataProviderRegistry、ChatMessageProviderRegistry 等
  ↓
addUsedComponent、sticker / textTranslate / soundToText 插件、EventBus 接线
```

**关键点**：
- Platform 由 `SessionRuntimeCoordinator.ensureInitialized()` 安装 —— `AppBootstrapCoordinator.boot()` 在导航之前调用；`_initAfterSessionReady()` 幂等地再次执行作为兜底。
- `BinaryReplacementHistoryHook` 在 `TimSdkInitializer.ensureInitialized()` 解析完成后由 `_initBinaryReplacementPersistenceHook()` 安装。
- `TIMManager.instance.initSDK()` 由 `TimSdkInitializer` 仅调用一次，不要直接调用。
- 所有 UIKit 注册与状态设置必须发生在 SDK 初始化之后。

**与标准流程的差异**：
- 标准流程使用 `TencentCloudChat.controller.initUIKit()` 统一管理初始化
- toxee 使用二进制替换方案，需要手动初始化各个组件
- 不依赖标准的 `TUILogin.instance.login()` 流程

**关键代码位置**:
- `toxee/lib/ui/login_page.dart:_login()`
- `toxee/lib/ui/home_page.dart:initState()`
- `tim2tox/dart/lib/service/ffi_chat_service.dart:init()`

### 10. 消息ID统一格式

**决策**: 统一使用 `timestamp_userID` 格式（毫秒级时间戳）生成消息ID

**原因**:
- 确保消息ID的唯一性
- 便于消息匹配和状态更新
- 避免使用临时ID（如 `created_temp_id`）导致的消息匹配问题

**实现**:
- `Tim2ToxSdkPlatform` 使用 `ffiService.selfId` 生成消息ID
- `setAdditionalInfoForMessage` 确保所有消息ID都使用统一格式
- 移除对 `created_temp_id` 的依赖

### 11. Tim2tox 接口与 auto_tests 单实例兼容

**决策**: toxee 使用单实例（instance_id=0），与 `tim2tox/auto_tests` 的多实例模式存在接口差异。

**接口差异**:
- **auto_tests 专用**：`registerInstanceForPolling`、`runWithInstanceAsync`、`createTestInstance` 等为多节点测试设计，toxee 无需使用
- **共用接口**：`getFriendList`、`getFriendApplications`、`startPolling`、`knownGroups` 等与单实例兼容；`getFriendApplications()` 内部使用 `getFriendApplicationsForInstance(0, ...)` 正确返回默认实例数据

**Platform 检测**：HomePage 使用 `TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform` 判断是否需要设置 Platform。SDK 内部（V2TimManager、V2TimMessageManager）使用 `platform.isCustomPlatform` 决定是否走 Platform 路径，避免依赖 `runtimeType.toString()` 的脆弱性。

**回归验证**：tim2tox 接口更新后，需验证好友申请列表、会话列表更新、文件传输等场景。详见 [reference/IMPLEMENTATION_DETAILS.md - Tim2tox 接口兼容性与回归验证](../reference/IMPLEMENTATION_DETAILS.md#tim2tox-接口兼容性与回归验证)。

## 扩展指南

### 添加新功能

1. **在 Tim2Tox 中添加功能**:
   - 在 C++ 层实现 V2TIM API
   - 在 FFI 层添加 C 接口
   - 在 Dart 层添加 FFI 绑定和服务 API

2. **在客户端中使用新功能**:
   - 通过 `Tim2ToxSdkPlatform` 直接使用（如果已实现）
   - 或通过 `FakeIM` 订阅事件并更新 UI

### 自定义适配器

如果需要使用不同的实现，只需创建新的适配器：

```dart
class MyCustomPreferencesAdapter implements ExtendedPreferencesService {
  // 使用自定义存储实现
  // ...
}
```

然后在初始化时使用：

```dart
final ffiService = FfiChatService(
  preferencesService: MyCustomPreferencesAdapter(),
  // ...
);
```

## 总结

toxee 展示了如何将 Tim2Tox 集成到 Flutter 应用中。通过适配器模式和接口抽象，实现了 Tim2Tox 和客户端的完全解耦，使得 Tim2Tox 可以被任何 Flutter 客户端复用。

关键要点：
- Tim2Tox 完全独立，通过接口注入依赖
- 客户端通过适配器实现接口
- 使用事件总线进行组件间通信
- 支持双重数据路径（SDK Events + Data Streams）
