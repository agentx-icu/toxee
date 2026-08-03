[English](./HYBRID_ARCHITECTURE.md)

# toxee 混合架构
> 语言 / Language: [中文](HYBRID_ARCHITECTURE.md) | [English](HYBRID_ARCHITECTURE.md)

本文为混合架构的**权威文档**：职责划分、推荐初始化顺序、消息/历史/会话/文件/通话路径以此为准。整体架构概览见 [ARCHITECTURE.md](ARCHITECTURE.md)，维护者视角与设计约束见 [MAINTAINER_ARCHITECTURE.md](MAINTAINER_ARCHITECTURE.md)。

本文档描述 toxee 当前使用的混合架构：底层调用仍以二进制替换路径为主，历史消息、通话、部分自定义回调和扩展能力通过 `Tim2ToxSdkPlatform` 补足。

## 一、架构概览

toxee 并非纯二进制替换，而是**混合模式**：

- **二进制替换**：动态库从 `dart_native_imsdk` 替换为 `libtim2tox_ffi`，大部分 C++ 回调经 NativeLibraryManager 派发
- **混合 Platform**：由 `SessionRuntimeCoordinator.ensureInitialized()` 在满足 `instance is! Tim2ToxSdkPlatform` 时设置 `Tim2ToxSdkPlatform`；自动登录路径在 `AppBootstrapCoordinator.boot()` 中（进入 HomePage 之前）调用，手动登录路径在 `HomePage._initAfterSessionReady()` 中调用；必须在首屏或更早完成，用于历史查询、部分 SDK 调用及 C++ 特殊回调

**重要**：必须设置 Tim2ToxSdkPlatform，否则 clearHistoryMessage、groupQuitNotification、groupChatIdStored 等 C++ 回调无法正确执行。

## 二、推荐初始化顺序

**概念顺序**（逻辑依赖关系）：

```
1. FfiChatService.init()                  # 初始化 Tox 与本地持久化
2. FfiChatService.login()                # 恢复 selfId 与连接状态
3. FfiChatService.updateSelfProfile()    # 同步昵称/签名
4. FakeUIKit.startWithFfi(service)       # 建立适配层和通话管理器
5. TIMManager.instance.initSDK()         # 设置 UIKit 侧 _isInitSDK
6. FfiChatService.startPolling()         # 轮询 native 事件、文件和 ToxAV
7. HomePage 设置 Tim2ToxSdkPlatform      # 启用 Platform 路径与自定义 callback
8. 初始化 BinaryReplacementHistoryHook、通话桥与插件
```

**实际执行顺序**（与代码一致）：

1. **main()**：通过 `AppBootstrap.initialize()` → `LoggingBootstrap.initialize()` 调用 `setNativeLibraryName('tim2tox_ffi')`（见 `lib/bootstrap/logging_bootstrap.dart`），不设置 Platform。
2. **_StartupGate._decide()**（自动登录路径）：通过 `AccountService.initializeServiceForAccount(..., startPolling: false)` 完成 `init()`、`login()`、`updateSelfProfile()`；随后 `AppBootstrapCoordinator.boot(service)` 执行 `SessionRuntimeCoordinator.ensureInitialized()`（FakeUIKit + Platform）→ `TimSdkInitializer.ensureInitialized()` → `service.startPolling()` → 等待连接/超时 → 加载好友信息 → 导航到 `HomePage(service)`。
3. **LoginPage 登录成功后**（手动登录路径）：有账号时走 `AccountService.initializeServiceForAccount(..., startPolling: false)`；旧账号兼容路径为手动 `init()` → `login()` → `updateSelfProfile()`（均不在此处调用 startPolling）。随后调用方执行 `AppBootstrapCoordinator.boot(service)`（SessionRuntime + TIM init + startPolling），再导航到 `HomePage(service)`。
4. **HomePage.initState()**：通过 `_initAfterSessionReady()` 调用 `SessionRuntimeCoordinator.ensureInitialized()`（幂等：若已在 boot 中执行则跳过）；若 FakeUIKit 未启动则 `startWithFfi(widget.service)`，若 Platform 非 `Tim2ToxSdkPlatform` 则设置并挂载 `onGroupMessageReceivedForUnread`；随后在 `TimSdkInitializer.ensureInitialized()` 完成后初始化 `BinaryReplacementHistoryHook`、UIKit 的 group/friend listener，以及 sticker / textTranslate / soundToText 插件。

**说明**：**Platform 由 SessionRuntimeCoordinator.ensureInitialized() 设置**；自动登录时在进入 HomePage 之前（boot 中）已完成，手动登录时在登录页调用 `boot(service)` 时完成，或若未调用 boot 则首次在 HomePage._initAfterSessionReady() 中完成。`BinaryReplacementHistoryHook` 在 `TimSdkInitializer.ensureInitialized()` 完成后于 HomePage 内初始化；`CallServiceManager` 依赖已设置好的 `Tim2ToxSdkPlatform` 来注册 signaling listener。

**职责划分**：

- **FfiChatService.init**：负责 Tox 核心初始化
- **TIMManager.initSDK**：设置 SDK 层 `_isInitSDK` 标志，并调用 C++ DartInitSDK（与 FfiChatService 共享同一底层实例）
- **Platform 设置**：必须在 HomePage 或更早完成，供 getHistoryMessageList、clearHistoryMessage 等使用

## 三、功能流程

### 3.1 消息发送

| 路径 | 说明 |
|------|------|
| **主路径** | FakeChatMessageProvider → FakeMessageManager.sendText/sendFile → FfiChatService |
| **备用路径** | 若代码走 V2TimMessageManager.sendMessage 且 Platform 已设置 → Tim2ToxSdkPlatform → FfiChatService |

当前 UIKit 消息输入走 ChatMessageProvider，因此实际发送全部经 FfiChatService。

### 3.2 消息历史

| 路径 | 说明 |
|------|------|
| **Provider 层** | FakeChatMessageProvider._loadHistoryForConversation → FakeMessageManager.getHistory → FfiChatService.getHistory |
| **SDK 层** | tencent_cloud_chat_common 等调用 getHistoryMessageListV2 → 若 Platform=Tim2ToxSdkPlatform → FfiChatService.getHistory |

两条路径最终都到 FfiChatService/MessageHistoryPersistence。

### 3.3 会话与好友

全部经 FakeUIKit 适配层，直接使用 FfiChatService（getFriendList、getFriendApplications、knownGroups），不经过 Platform 或 NativeLibraryManager。

### 3.4 文件传输

- **发送**：FakeMessageManager.sendFile → FfiChatService.sendFile
- **接收**：C++ OnFileRecv → file_request 入队 → FfiChatService.startPolling 消费 → acceptFile
- **进度**：FfiChatService.progressUpdates stream → FakeChatMessageProvider

`startPolling()` 必须在服务登录后由启动流程显式调用，否则 `file_request`、连接状态和 ToxAV 事件都无法被消费。

### 3.5 通话与扩展能力

- **通话**：`FakeUIKit.startWithFfi()` 创建 `CallServiceManager`；`HomePage.initState()` 在 Platform 设置完成后调用其 `initialize()`，随后串起 `ToxAVService`、`CallBridgeService` 和 `TUICallKitAdapter`
- **贴纸插件**：`HomePage.initState()` 在 message 组件注册前尝试同步注册；若 `selfId` 尚未就绪，则在连接成功后补注册
- **文本翻译 / 语音转文字**：在 HomePage 中按需懒注册
- **局域网 Bootstrap / IRC**：入口在客户端侧，分别由 `LanBootstrapServiceManager` 与 `IrcAppManager` 管理，具体实现见扩展文档

## 四、回调流程与分工

### 4.1 C++ 回调路径

```
C++ (dart_compat_layer / callback_bridge)
  → Dart_PostCObject
  → NativeLibraryManager._handleGlobalCallback
  → 按 instance_id 路由：
     - instance_id != 0 → Platform.dispatchInstanceGlobalCallback（多实例）
     - instance_id == 0 → _sdkListener、_advancedMsgListener、_friendshipListener、_groupListener
```

### 4.2 C++ 回调与 FfiChatService streams 的分工

| 来源 | 用途 | 说明 |
|------|------|------|
| **C++ ReceiveNewMessage** | 经 NativeLibraryManager 派发到 TIMMessageManager 的 _advancedMsgListener | 二进制替换下新消息的主入口；BinaryReplacementHistoryHook 包装 listener 做持久化 |
| **FfiChatService.messages** | FfiChatService 内部 _onNativeEvent 产生的 stream | 来自 FfiChatService 的旧式事件（type 0/1/10/11 等），与 C++ 层可能重叠 |
| **FfiChatService.connectionStatusStream** | 连接状态 | 独立于 C++ 回调 |

**注意**：在二进制替换模式下，新消息主要由 C++ 的 ReceiveNewMessage 回调经 NativeLibraryManager 派发。FfiChatService._onNativeEvent 主要处理其自身维护的旧式事件协议。两者分工不同，避免重复处理。

### 4.3 特殊回调对 Platform 的依赖

NativeLibraryManager 中以下回调**依赖 Platform 为 Tim2ToxSdkPlatform**，否则无法访问 ffiService：

- `clearHistoryMessage`：清空历史
- `groupQuitNotification`：群退出通知
- `groupChatIdStored`：群 chat_id 持久化

这些回调由 **NativeLibraryManager._handleGlobalCallback** 在检测到 **platform != null && platform.isCustomPlatform** 时，通过 **dispatchInstanceGlobalCallback** 派发到 **Tim2ToxSdkPlatform._handleCustomCallback** 处理。若 Platform 未设置或类型不符，这些回调会静默失败。

## 五、数据流总览

```
┌─────────────────────────────────────────────────────────────────┐
│                        消息发送                                   │
│  Message Input → FakeChatMessageProvider → FfiChatService        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        历史加载                                   │
│  FakeMessageManager.getHistory ──────┐                          │
│  V2TimMessageManager.getHistoryMessageListV2 ──→ Platform ──┐   │
│  （SDK 层 isCustomPlatform==true 时走 Platform）         ↓   │
│                                         FfiChatService.getHistory│
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        回调                                       │
│  C++ → NativeLibraryManager → TIMMessageManager listeners       │
│                            → BinaryReplacementHistoryHook        │
│  C++ 特殊回调 → Platform.ffiService（需 Platform=Tim2ToxSdkPlatform）│
└─────────────────────────────────────────────────────────────────┘
```

## 六、与纯二进制替换的差异

| 项目 | 纯二进制替换（文档描述） | 当前混合方案 |
|------|--------------------------|--------------|
| Platform 设置 | 不设置 | **必须设置** Tim2ToxSdkPlatform |
| 历史查询 | C++ DartGetC2CHistoryMessageList | Platform → FfiChatService.getHistory |
| 特殊回调 | 无法执行 | 依赖 Platform.ffiService |
| 消息发送主路径 | NativeLibraryManager.DartSendMessage | FakeChatMessageProvider → FfiChatService |

## 七、相关文档

- [ARCHITECTURE.md](ARCHITECTURE.md)：整体架构
- [reference/IMPLEMENTATION_DETAILS.md](MAINTAINER_ARCHITECTURE.md)：实现细节
- [reference/CALLING_AND_EXTENSIONS.md](../reference/CALLING_AND_EXTENSIONS.md)：通话、插件、局域网 Bootstrap 与 IRC 扩展
- [../../third_party/tim2tox/doc/architecture/BINARY_REPLACEMENT.md](../../third_party/tim2tox/doc/architecture/BINARY_REPLACEMENT.md)：二进制替换机制
