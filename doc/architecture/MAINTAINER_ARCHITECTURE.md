# toxee 维护者视角：混合架构设计

> 语言 / Language: [中文](MAINTAINER_ARCHITECTURE.md) | [English](MAINTAINER_ARCHITECTURE.en.md)

> 本文档面向**维护者**，说明混合架构的成因、职责划分、调用链与修改边界。用户使用与快速上手见 [主 README](../../README.zh-CN.md)；文档索引见 [doc/README](../README.md)。与 [ARCHITECTURE.md](ARCHITECTURE.md)（整体概览）、[HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.md)（混合架构权威描述）并列；**初始化顺序与混合架构职责以本文或 HYBRID_ARCHITECTURE 为权威**。

## 目录

- [1. 架构目标](#1-架构目标)
- [2. 设计约束](#2-设计约束)
- [3. 分层设计](#3-分层设计)
- [4. 核心模块职责](#4-核心模块职责)
- [5. 初始化时序](#5-初始化时序)
- [6. 消息发送路径](#6-消息发送路径)
- [7. 历史消息与特殊回调路径](#7-历史消息与特殊回调路径)
- [8. 文件传输与事件轮询](#8-文件传输与事件轮询)
- [9. 持久化与状态恢复](#9-持久化与状态恢复)
- [10. 扩展插件与通话桥的接入位置](#10-扩展插件与通话桥的接入位置)
- [11. 为什么这是当前最合适的方案](#11-为什么这是当前最合适的方案)
- [12. 未来可演进方向](#12-未来可演进方向)
- [最容易改坏的地方](#最容易改坏的地方)
- [阅读源码的推荐入口顺序](#阅读源码的推荐入口顺序)

---

## 1. 架构目标

| 目标 | 说明 |
|------|------|
| **承接 UIKit 调用习惯** | 业务与 UIKit 仍通过 `TIMManager.instance`、各 Manager、Listener 调用与接收回调；底层由 Tim2Tox 实现，不要求重写 UI 或业务调用方式。 |
| **历史与扩展由 Dart 侧统一承载** | 消息历史在 Dart 持久化（C++ 无落库）；clearHistoryMessage、groupQuitNotification、groupChatIdStored 等需访问 FfiChatService 的“特殊回调”必须经 Platform 派发。 |
| **最小化与 SDK 的绑定** | 能走“换库不换接口”的路径（NativeLibraryManager → Dart*）的尽量走；仅把“必须由 Dart 实现或必须拿到 ffiService”的能力交给 Platform。 |
| **单点会话生命周期** | 账号切换/登出时，FakeUIKit、Platform、FfiChatService、轮询、Provider 注册需一致拆建，避免跨账号状态泄漏。 |

---

## 2. 设计约束

| 约束类型 | 说明 |
|----------|------|
| **兼容性要求** | SDK 的 `NativeLibraryManager` 通过 FFI 动态查找 `Dart*` 符号；库名由 `setNativeLibraryName('tim2tox_ffi')` 指定后，所有经 TIMManager 发起的调用都会进入 tim2tox 的 dart_compat_*，**不能**在 main 里就设 Platform 而期望“全部走 Platform”——SDK 内部仍会先走 Native 路径，只有 isCustomPlatform 时部分接口才路由到 Platform。 |
| **兼容性要求** | C++ 回调格式（globalCallback/apiCallback JSON）与 NativeLibraryManager._handleNativeMessage 的约定一致；特殊回调（clearHistoryMessage 等）依赖 NativeLibraryManager 在 platform != null && isCustomPlatform 时派发到 Platform.dispatchInstanceGlobalCallback，**因此 Platform 必须在首屏（HomePage）或更早设置**，否则这些回调静默失败。 |
| **工程权衡** | Platform 由 **SessionRuntimeCoordinator.ensureInitialized()** 设置；该调用在自动登录路径来自 AppBootstrapCoordinator.boot()（在进入 HomePage 之前），在手动登录路径来自登录页调用 boot(service) 或 HomePage._initAfterSessionReady()。不在 main() 设置：FfiChatService 在启动门或登录页才创建，同一实例须同时交给 FakeUIKit 与 Tim2ToxSdkPlatform。 |
| **工程权衡** | startPolling() 在 **AppBootstrapCoordinator.boot()** 中调用（即 init/login 与 FakeUIKit/Platform 就绪之后），保证 C++ 事件队列由已注册的 FfiChatService 消费；若在 init 后立即 startPolling 而尚未设置 Platform/FakeUIKit，file_request 等事件会丢失或无法关联到 UI。 |

---

## 3. 分层设计

### 3.1 分层图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  UI 层 (lib/ui/)                                                             │
│  HomePage, LoginPage, 会话/设置/Bootstrap 等；使用 UIKit 组件 + 少量自定义    │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│  Provider / 数据注册层                                                         │
│  ChatDataProviderRegistry.provider = FakeChatDataProvider                     │
│  ChatMessageProviderRegistry.provider = FakeChatMessageProvider               │
│  调用方：UIKit 内部取 provider 做 getHistory、sendText、loadConversation 等    │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│  适配层 (lib/sdk_fake/)                                                       │
│  FakeUIKit, FakeMessageManager, FakeConversationManager, FakeChatMessageProvider│
│  将 FfiChatService/EventBus 数据转为 UIKit 所需的 Fake* 与 V2Tim 形态          │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│  会话运行时 (lib/runtime/) + Tim2Tox Dart 层                                  │
│  SessionRuntimeCoordinator：FakeUIKit.startWithFfi + Platform 设置 + CallServiceManager │
│  FfiChatService：init/login/startPolling/getHistory/send*/messages/connectionStatusStream │
│  Tim2ToxSdkPlatform：TencentCloudChatSdkPlatform 实现，委托给 ffiService     │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       │
        ┌─────────────────────────────┴─────────────────────────────┐
        │  SDK 调用入口（二选一或同时存在）                            │
        │  A: TIMManager → NativeLibraryManager → Dart* → libtim2tox_ffi │
        │  B: getHistoryMessageListV2 等 → Platform → Tim2ToxSdkPlatform → FfiChatService │
        └─────────────────────────────┬─────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│  Tim2Tox C++ (third_party/tim2tox)：V2TIM*Manager, ToxManager, c-toxcore    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 双路径与能力归属（对比表）

| 能力 | NativeLibraryManager 路径（二进制替换） | Tim2ToxSdkPlatform / FfiChatService 路径 |
|------|----------------------------------------|------------------------------------------|
| initSDK / Login | ✅ TIMManager.initSDK → DartInitSDK；FfiChatService.init/login 内部调 tim2tox_ffi_*，与 Dart* 共用同一 C++ 实例 | 仅 FfiChatService 负责调用 tim2tox_ffi_init/login；SDK 的 initSDK 仍走 Native |
| 新消息回调 | ✅ C++ OnRecvNewMessage → SendCallbackToDart → NativeLibraryManager._handleGlobalCallback → _advancedMsgListener | FfiChatService.messages stream 来自 poll 解析（c2c/gtext 等），与 C++ 回调分工，避免重复 |
| 历史拉取 | ❌ C++ 无持久化历史，DartGetC2CHistoryMessageList 等返回空或未实现 | ✅ getHistoryMessageListV2 → Platform → FfiChatService.getHistory → MessageHistoryPersistence |
| clearHistoryMessage | ❌ 需 ffiService，Native 路径无法执行 | ✅ 由 NativeLibraryManager 派发到 Platform._handleCustomCallback → ffiService |
| groupQuitNotification / groupChatIdStored | ❌ 同上 | ✅ 同上 |
| 消息发送（当前实现） | 可走 DartSendMessage，但 toxee 消息输入走 ChatMessageProvider | ✅ FakeChatMessageProvider → FakeMessageManager.sendText/sendFile → FfiChatService |
| 好友/会话列表 | 可走 DartGetFriendList 等 | ✅ FakeUIKit 直接读 FfiChatService.getFriendList、knownGroups 等，不经过 Platform |
| 连接状态 | C++ 可回调 | ✅ FfiChatService.connectionStatusStream 来自 poll 的 conn:success/failed |
| 文件传输 | C++ 回调 file_request；接收端需在 Dart 侧 accept | ✅ startPolling 消费 file_request；FfiChatService.acceptFileTransfer；进度 progressUpdates → FakeChatMessageProvider |
| 通话 / signaling | 部分走 Native listener | ✅ CallServiceManager、ToxAVService、CallBridgeService 在 Platform 设置后初始化，依赖 ffiService |

---

## 4. 核心模块职责

### 4.1 LoggingBootstrap

| 项 | 内容 |
|----|------|
| **所在目录** | `lib/bootstrap/logging_bootstrap.dart` |
| **直接职责** | 在 main 最早设置 AppLogger 路径、C++ 日志文件（Tim2ToxFfi.setLogFile）、**setNativeLibraryName('tim2tox_ffi')**，确保后续任何 SDK/FFI 调用都加载 tim2tox 动态库。 |
| **上游调用者** | `AppBootstrap.initialize()`（由 main 调用）。 |
| **下游依赖** | AppLogger、Tim2ToxFfi.open()、tencent_cloud_chat_sdk 的 NativeLibraryManager（通过 setNativeLibraryName 影响其后续 DynamicLibrary.open 的库名）。 |
| **典型问题** | 未在首行执行或库名拼写错误，导致仍加载原生 IM SDK 库或符号找不到。 |
| **修改风险** | 高。改库名或移除 setNativeLibraryName 会破坏二进制替换路径；调整顺序可能使后续 Logger/FFI 未就绪。 |

### 4.2 FfiChatService

| 项 | 内容 |
|----|------|
| **所在目录** | `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart`（Tim2Tox 包内） |
| **直接职责** | Tox 生命周期（init/login）、轮询（startPolling）、消息发送（sendText/sendGroupText/sendFile）、历史（getHistory ↔ MessageHistoryPersistence）、Stream（messages、connectionStatusStream、progressUpdates、fileRequests）、多实例注册。 |
| **上游调用者** | toxee：AccountService.initializeServiceForAccount、SessionRuntimeCoordinator、FakeUIKit（FakeMessageManager/FakeConversationManager/FakeIM 等）、Tim2ToxSdkPlatform、BinaryReplacementHistoryHook。 |
| **下游依赖** | Tim2ToxFfi（tim2tox_ffi_*）、ExtendedPreferencesService、LoggerService、BootstrapService、MessageHistoryPersistence、OfflineMessageQueuePersistence。 |
| **典型问题** | 未调用 startPolling 导致 file_request/conn 事件不消费；多账号下用错 profile 路径或 historyDirectory。 |
| **修改风险** | 高。接口为 Tim2Tox 与 toxee 的契约；增删 Stream 或方法会波及 Fake* 与 Platform 实现。 |

### 4.3 Tim2ToxSdkPlatform

| 项 | 内容 |
|----|------|
| **所在目录** | `third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart` |
| **直接职责** | 实现 TencentCloudChatSdkPlatform：getHistoryMessageListV2、clearHistoryMessage、deleteConversation 等路由到 ffiService；customCallbackHandler 处理 clearHistoryMessage、groupQuitNotification、groupChatIdStored 等 C++ 派发过来的特殊回调。 |
| **上游调用者** | SDK 内部（当 isCustomPlatform == true 时）；NativeLibraryManager._handleGlobalCallback 在检测到需 custom 处理时派发到 platform.dispatchInstanceGlobalCallback。 |
| **下游依赖** | FfiChatService、EventBusProvider、ConversationManagerProvider（可选）。 |
| **典型问题** | Platform 未设置或晚于首屏，getHistoryMessageList 走空实现或特殊回调静默丢失。 |
| **修改风险** | 中高。SDK 版本升级可能新增/变更 Platform 方法签名；customCallbackHandler 的 key 与 C++ 约定一致，改错会导致回调不执行。 |

### 4.4 FakeUIKit

| 项 | 内容 |
|----|------|
| **所在目录** | `lib/sdk_fake/fake_uikit_core.dart` |
| **直接职责** | startWithFfi(service) 时创建 FakeIM、FakeConversationManager、FakeMessageManager、FakeContactManager、FakeChatMessageProvider、CallServiceManager，并挂接 EventBus；将 FfiChatService 暴露给各 Fake* 与 Provider。 |
| **上游调用者** | SessionRuntimeCoordinator.ensureInitialized()、HomePage._initAfterSessionReady（若 coordinator 未先跑）。 |
| **下游依赖** | FfiChatService、FakeEventBus、CallStateNotifier。 |
| **典型问题** | 在未 login 或未 init 的 service 上 startWithFfi；dispose 后仍被访问导致空引用。 |
| **修改风险** | 高。FakeUIKit 为单例，dispose 后需与 AccountService.teardown 一致；新增 Fake* 或 Provider 需同步注册到 UIKit 的 Registry。 |

### 4.5 SessionRuntimeCoordinator

| 项 | 内容 |
|----|------|
| **所在目录** | `lib/runtime/session_runtime_coordinator.dart` |
| **直接职责** | ensureInitialized()：若 FakeUIKit 未启动则 startWithFfi(service)；若 Platform 非 Tim2ToxSdkPlatform 则创建并设置 Tim2ToxSdkPlatform、挂 onGroupMessageReceivedForUnread；然后 CallServiceManager.initialize()。disposeRuntime()：FakeUIKit.dispose、Platform 还原为 MethodChannel。 |
| **上游调用者** | AppBootstrapCoordinator.boot()、HomePage._initAfterSessionReady()、AccountService.teardownCurrentSession()（调 disposeRuntime）。 |
| **下游依赖** | FfiChatService、FakeUIKit、Tim2ToxSdkPlatform、EventBusAdapter、ConversationManagerAdapter。 |
| **典型问题** | 多次 ensureInitialized 并发时依赖 _initializing 串行化；dispose 后再次 ensure 会重建，需保证 service 为新会话。 |
| **修改风险** | 中。顺序变更会影响 Platform 与 FakeUIKit 谁先就绪；CallServiceManager 必须在 Platform 设置后 initialize。 |

### 4.6 HomePage（initState / _initAfterSessionReady）

| 项 | 内容 |
|----|------|
| **所在目录** | `lib/ui/home_page.dart`、`lib/ui/home_page_bootstrap.dart`（part） |
| **直接职责** | initState 中 unawaited(_initAfterSessionReady())；其内先 SessionRuntimeCoordinator.ensureInitialized()，再 TimSdkInitializer.ensureInitialized()，然后 _initBinaryReplacementPersistenceHook()、注册 group/friend listener、ChatDataProviderRegistry/ChatMessageProviderRegistry、贴纸/翻译/语音插件、connectionStatus 等监听。 |
| **上游调用者** | 启动门或登录页导航到 HomePage(service) 后由 Flutter 框架调用 initState。 |
| **下游依赖** | FfiChatService（widget.service）、SessionRuntimeCoordinator、TimSdkInitializer、BinaryReplacementHistoryHook、FakeUIKit、TencentCloudChat 各组件 register。 |
| **典型问题** | _initTIMManagerSDK 与 _initBinaryReplacementPersistenceHook 顺序颠倒会导致 Hook 在 TIMManager 尚未 init 时挂载失败；插件在 selfId 为空时注册失败需依赖连接成功后补注册。 |
| **修改风险** | 高。HomePage 是“会话就绪后”的集中初始化点，顺序与 [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.md) 一致；删减或调序需同步文档与回归测试。 |

### 4.7 FakeChatMessageProvider / FakeMessageManager

| 项 | 内容 |
|----|------|
| **所在目录** | `lib/sdk_fake/fake_msg_provider.dart`、`lib/sdk_fake/fake_managers.dart` |
| **直接职责** | Provider：实现 ChatMessageProvider，供 UIKit 拉历史（getHistory）、发消息（sendText/sendFile）、收 progress 与消息流。Manager：getHistory(conversationID) 调 ffi.getHistory(id)；sendText/sendFile 调 ffi.sendText/sendFile，并 emit FakeMessage 或从 history 取最后一条做本地 echo。 |
| **上游调用者** | UIKit 消息组件通过 ChatMessageProviderRegistry.provider 取到 FakeChatMessageProvider；FakeUIKit.messageProvider 被同一 Provider 引用。 |
| **下游依赖** | FfiChatService（getHistory、sendText、sendGroupText、sendFile、progressUpdates、messages）。 |
| **典型问题** | conversationID 与 FfiChatService 的 id 规范不一致（c2c_/group_ 前缀剥离）；群消息本地 echo 与 ffi.messages 重复需避免双份。 |
| **修改风险** | 中高。getHistory/sendText 的调用链被多处使用；ID 规范化需与 FfiChatService.getHistory、MessageHistoryPersistence 一致。 |

### 4.8 BinaryReplacementHistoryHook

| 项 | 内容 |
|----|------|
| **所在目录** | `third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart`（Tim2Tox 包内） |
| **直接职责** | 包装 V2TimAdvancedMsgListener：在 OnRecvNewMessage 时把消息写入 FfiChatService/MessageHistoryPersistence，避免“仅二进制替换时历史为空”；与 Platform 路径共用同一持久化，避免重复写入。 |
| **上游调用者** | HomePage._initBinaryReplacementPersistenceHook() 在 TIMManager init 完成后注册到 SDK。 |
| **下游依赖** | FfiChatService（同一实例）、MessageHistoryPersistence。 |
| **典型问题** | 未安装则 C++ 收到的新消息不落库；安装时机晚于首条消息会导致首条丢失。 |
| **修改风险** | 中。Hook 与 Platform 的 getHistory 必须读同一份持久化；逻辑变更需兼顾二进制替换与混合两种用法。 |

### 4.9 AppBootstrapCoordinator / TimSdkInitializer

| 项 | 内容 |
|----|------|
| **所在目录** | `lib/util/app_bootstrap_coordinator.dart`、`lib/runtime/tim_sdk_initializer.dart` |
| **直接职责** | boot(service)：SessionRuntimeCoordinator.ensureInitialized() → TimSdkInitializer.ensureInitialized() → service.startPolling()。TimSdkInitializer：TIMManager.instance.initSDK(...) 仅一次。 |
| **上游调用者** | StartupSessionUseCase.execute（自动登录路径）、LoginUseCase（登录成功后）；HomePage 内 _initAfterSessionReady 也会调 SessionRuntimeCoordinator 与 TimSdkInitializer。 |
| **下游依赖** | FfiChatService、SessionRuntimeCoordinator、TIMManager。 |
| **典型问题** | startPolling 晚于 HomePage 打开会导致首屏一段时间无连接状态；initSDK 重复调用需幂等。 |
| **修改风险** | 中。boot 顺序固定为 FakeUIKit+Platform → TIM init → startPolling；改动会影响连接与事件消费时机。 |

---

## 5. 初始化时序

### 5.1 时序步骤（与代码一致）

```
main()
  ├─ WidgetsFlutterBinding.ensureInitialized()
  ├─ AppBootstrap.initialize()
  │    ├─ LoggingBootstrap.initialize()   // 日志路径、setNativeLibraryName('tim2tox_ffi')、FFI setLogFile
  │    ├─ PrefsBootstrap.initialize()
  │    ├─ AppRuntimeBootstrap.initialize()  // 主题、语言、UIKit theme
  │    └─ DesktopShellBootstrap.initializeIfNeeded()
  └─ 根据 result 进入 _StartupGate 或登录页

_StartupGate._decide()（自动登录）
  ├─ Prefs 检查 nickname / autoLogin
  ├─ 若需 Bootstrap：BootstrapNodesService.fetchNodes / Prefs.setCurrentBootstrapNode
  ├─ AccountService.initializeServiceForAccount(toxId, ..., startPolling: false)
  │    ├─ FfiChatService 构造（prefs, logger, bootstrap, historyDirectory, ...）
  │    ├─ service.init(profileDirectory)
  │    ├─ service.login(...)
  │    ├─ service.updateSelfProfile(...)
  │    └─ 不在这里 startPolling
  ├─ AppBootstrapCoordinator.boot(service)
  │    ├─ SessionRuntimeCoordinator(service).ensureInitialized()
  │    │    ├─ FakeUIKit.instance.startWithFfi(service)
  │    │    ├─ TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(ffiService: service, ...)
  │    │    └─ FakeUIKit.instance.callServiceManager?.initialize()
  │    ├─ TimSdkInitializer.ensureInitialized()  // TIMManager.initSDK
  │    └─ service.startPolling()
  ├─ 等待 connectionStatusStream 或超时
  ├─ loadFriends(service)
  └─ 导航到 HomePage(service)

HomePage.initState()
  └─ unawaited(_initAfterSessionReady())
       ├─ SessionRuntimeCoordinator(service).ensureInitialized()  // 幂等
       ├─ TimSdkInitializer.ensureInitialized().then((_) {
       │    ├─ _initBinaryReplacementPersistenceHook()
       │    ├─ initGroupListener / initFriendListener
       │  })
       ├─ ChatDataProviderRegistry.provider = FakeChatDataProvider(...)
       ├─ ChatMessageProviderRegistry.provider = FakeChatMessageProvider()
       ├─ basic.addUsedComponent(Conversation/Message/Contact/Search...)
       ├─ connectionStatusStream.listen(...)、插件注册、EventBus 订阅等
       └─ ...
```

### 5.2 为什么顺序不能随意改

| 顺序约束 | 原因 |
|----------|------|
| setNativeLibraryName 必须在任何 SDK/FFI 调用之前 | NativeLibraryManager 在首次使用时会 DynamicLibrary.open(库名)；之后 TIMManager.initSDK 等都会解析到 libtim2tox_ffi 的 Dart* 符号。 |
| FfiChatService.init/login 必须在 startWithFfi 与 Platform 之前 | FakeUIKit 和 Tim2ToxSdkPlatform 都持有同一 FfiChatService 实例；该实例必须先完成 init/login，否则 getHistory、sendText、startPolling 行为未定义。 |
| Platform 必须在 getHistoryMessageList / clearHistoryMessage 被调用之前设置 | SDK 内部按 isCustomPlatform 决定是否走 Platform；首屏或会话切换会拉历史，若此时 Platform 不是 Tim2ToxSdkPlatform，则历史为空或清空无效。 |
| startPolling 必须在 SessionRuntimeCoordinator.ensureInitialized 之后 | 轮询消费的 file_request、conn 等需要 FfiChatService 已就绪且 FakeUIKit 已 start；若先 poll 再设置 Platform，部分事件可能无法关联到当前 UI。 |
| _initBinaryReplacementPersistenceHook 必须在 TimSdkInitializer.ensureInitialized 之后 | Hook 包装的 listener 要注册到已 init 的 TIMManager 的 messageManager；否则监听器未挂上，C++ 新消息不会落库。 |
| CallServiceManager.initialize 必须在 Platform 设置之后 | 通话桥需要向 Platform 侧注册 signaling 等能力，依赖 Tim2ToxSdkPlatform 已设置。 |

---

## 6. 消息发送路径

- **主路径（当前 toxee）**：UIKit 消息输入 → ChatMessageProvider.sendText/sendFile → **FakeChatMessageProvider** → **FakeMessageManager.sendText/sendFile** → **FfiChatService.sendText/sendGroupText/sendFile** → tim2tox_ffi_send_c2c_text / send_group_text / send_file → V2TIMMessageManagerImpl → ToxManager → c-toxcore。
- **备用路径**：若业务直接调 V2TimMessageManager.sendMessage 且 Platform 已设，则 SDK 可能路由到 Tim2ToxSdkPlatform.sendMessage → FfiChatService。当前 UI 走 Provider，因此主路径即 Fake* → FfiChatService。

```
UIKit Message Input
       │
       ▼
ChatMessageProviderRegistry.provider (FakeChatMessageProvider)
       │
       ▼
FakeMessageManager.sendText(conversationID, text) / sendFile(...)
       │
       ▼
FfiChatService.sendText(uid, text) / sendGroupText(gid, text) / sendFile(...)
       │
       ▼
Tim2ToxFfi (tim2tox_ffi_send_c2c_text / send_group_text / send_file)
       │
       ▼
libtim2tox_ffi → V2TIMMessageManagerImpl → ToxManager → c-toxcore
```

---

## 7. 历史消息与特殊回调路径

### 7.1 历史拉取

- **Provider 路径**：FakeChatMessageProvider._loadHistoryForConversation → FakeMessageManager.getHistory(conversationID) → **FfiChatService.getHistory(id)** → MessageHistoryPersistence.getHistory(normalizedId)。
- **SDK 路径**：tencent_cloud_chat_common 等调用 getHistoryMessageListV2；当 isCustomPlatform 且 Platform 为 Tim2ToxSdkPlatform 时 → **Tim2ToxSdkPlatform.getHistoryMessageListV2** → **FfiChatService.getHistory** → 同一 MessageHistoryPersistence。两条路径最终都到 FfiChatService/MessageHistoryPersistence，保证一份数据。

### 7.2 特殊回调（clearHistoryMessage、groupQuitNotification、groupChatIdStored）

- C++ 通过 SendCallbackToDart 发到 NativeLibraryManager；_handleGlobalCallback 内若 platform != null && platform.isCustomPlatform，则 **dispatchInstanceGlobalCallback** → **Tim2ToxSdkPlatform._handleCustomCallback**，内部根据 callback 类型调 ffiService.clearHistoryMessage、处理群退出或 chat_id 存储。
- 若 Platform 未设置或非 Tim2ToxSdkPlatform，这些回调**静默失败**（无法访问 ffiService）。

```
C++ (groupQuitNotification / clearHistoryMessage / ...)
  → SendCallbackToDart
  → NativeLibraryManager._handleGlobalCallback
  → if (platform != null && isCustomPlatform) platform.dispatchInstanceGlobalCallback(...)
  → Tim2ToxSdkPlatform._handleCustomCallback
  → ffiService.clearHistoryMessage / 群退出处理 / chat_id 持久化
```

---

## 8. 文件传输与事件轮询

- **发送**：FakeMessageManager.sendFile(conversationID, filePath) → FfiChatService.sendFile(uid, filePath) / sendGroupFile(gid, filePath)。
- **接收**：C++ OnFileRecv 将 file_request 入队 → **FfiChatService.startPolling()** 每轮 poll_text 解析到 file_request: → 解析出 peerId/fileNumber 等 → acceptFileTransfer 或推 fileRequests stream；FakeChatMessageProvider 监听 fileRequests 与 progressUpdates，更新 UI。
- **轮询**：startPolling() 启动定时器，每轮调用 tim2tox_ffi_poll_text(instance_id, buffer, len)，解析 conn:success/failed、c2c:、gtext:、file_request:、file_done: 等，更新 connectionStatusStream、messages、file 状态；多实例时按 _knownInstanceIds 轮询。若未调用 startPolling，则 file_request 与连接状态不会更新。

---

## 9. 持久化与状态恢复

- **历史**：MessageHistoryPersistence（Tim2Tox 包）按会话 id 存 List<ChatMessage>；由 FfiChatService.getHistory 读、BinaryReplacementHistoryHook 与 _appendHistory 写；目录由 FfiChatService 构造时 historyDirectory 决定（toxee 用 AccountService 提供的 per-account 路径）。
- **账号/会话**：Prefs 存 current_account_tox_id、nickname、bootstrap 等；AccountService.initializeServiceForAccount 根据 toxId 决定 profile 与 history 目录；teardownCurrentSession 时 SessionRuntimeCoordinator.disposeRuntime、Provider 清空、FfiChatService.dispose、必要时 profile 重加密。
- **Bootstrap**：BootstrapNodesAdapter 读 Prefs；FfiChatService.init 末尾 _loadAndApplySavedBootstrapNode() 调用 tim2tox_ffi_add_bootstrap_node。

---

## 10. 扩展插件与通话桥的接入位置

- **通话**：FakeUIKit.startWithFfi 时创建 CallServiceManager(service, callStateNotifier)；SessionRuntimeCoordinator.ensureInitialized() 末尾 CallServiceManager.initialize()（依赖 Platform 已设）；ToxAVService、CallBridgeService、TUICallKitAdapter 等在此链路上挂接。
- **贴纸/翻译/语音**：HomePage._initAfterSessionReady 内，在注册 Message 组件前后 _tryRegisterStickerPluginSync / _ensureStickerPluginRegistered；若 selfId 未就绪则在 connectionStatusStream 首次 connected 时补注册。
- **局域网 Bootstrap / IRC**：入口在客户端设置页等，由 LanBootstrapServiceManager、IrcAppManager 等管理；与 FfiChatService 的 Bootstrap 配置及 Tim2Tox IRC 能力对接，详见 [reference/CALLING_AND_EXTENSIONS.md](../reference/CALLING_AND_EXTENSIONS.md)。

---

## 11. 为什么这是当前最合适的方案

| 方案 | 优点 | 缺点 | 结论 |
|------|------|------|------|
| **纯二进制替换** | 业务零改动、部署简单（换库即可） | 历史在 C++ 无实现，getHistoryMessageList 空；clearHistoryMessage、groupQuitNotification、groupChatIdStored 无法执行；轮询与 FfiChatService 状态（连接、文件进度）无法与 UIKit 对接 | 仅适合“能接受无历史、无清空、无群回调”的极简验证 |
| **纯 Platform** | 所有能力都可经 FfiChatService 实现 | SDK 内大量接口需 Platform 实现，与 SDK 版本强绑定；TIMManager.initSDK 等仍会走 Native 路径，需同时保证 Native 库为 tim2tox 且 Platform 覆盖所有调用点，实现与维护成本高 | 当前 SDK 路由与 Tim2Tox 实现范围下不采用 |
| **混合架构（当前）** | 大部分调用仍走 NativeLibraryManager → Dart*，兼容现有 SDK 习惯；仅历史、特殊回调、轮询、发送主路径等“必须 Dart 侧”的能力走 Platform/FfiChatService；BinaryReplacementHistoryHook 补足二进制替换下的历史落库 | 需保证 Platform 与 Hook 在正确时机设置；两路径共享同一 FfiChatService 与持久化，需约定不重复写 | 在兼容性、功能完整性与实现成本之间取得平衡，故为当前方案 |

---

## 12. 未来可演进方向

- **SDK 升级**：若官方增加“全 Platform 模式”或更多 isCustomPlatform 路由，可评估将更多接口迁到 Platform，逐步减少对 Dart* 符号的依赖。
- **初始化集中化**：将 HomePage 内部分初始化（如插件、Listener）抽到 SessionRuntimeCoordinator 或单独 Coordinator，减少 HomePage 体积与顺序耦合。
- **多账号/多实例 UI**：当前 toxee 单账号；若需多账号切换或多 Tox 实例 UI，需在 teardown/ensure 与 FfiChatService 实例、Provider 注册、轮询注册表之间做更严格的隔离与测试。

---

## 最容易改坏的地方

1. **在 main 或早于 FfiChatService 创建时设置 TencentCloudChatSdkPlatform.instance**  
   会导致 Platform 拿不到 ffiService 或拿到错误实例；getHistoryMessageList、clearHistoryMessage 等失败或静默。

2. **调整 SessionRuntimeCoordinator.ensureInitialized 与 startPolling 的顺序**  
   若先 startPolling 再 ensureInitialized，轮询到的事件可能早于 FakeUIKit/Platform 就绪，file_request、conn 等无法正确关联到 UI 或 ffiService。

3. **在未调用 TimSdkInitializer.ensureInitialized 之前注册 BinaryReplacementHistoryHook**  
   TIMManager 未 init 时 listener 注册可能无效，C++ 新消息不会写入历史。

4. **登出/账号切换时只 dispose FfiChatService 而不调用 SessionRuntimeCoordinator.disposeRuntime()**  
   FakeUIKit、Platform 未还原，下一账号会沿用旧 Platform 或旧 FakeUIKit 引用，造成跨账号状态或崩溃。

5. **修改 FakeMessageManager.getHistory 的 conversationID → id 的剥离规则**  
   若与 FfiChatService.getHistory(normalizedId) 或 MessageHistoryPersistence 的 key 不一致，会导致历史错会话或为空。

6. **在 HomePage 之外重复设置 TencentCloudChatSdkPlatform.instance 为新的 Tim2ToxSdkPlatform**  
   若未与当前 FfiChatService 一致，特殊回调和 getHistory 会指向错误实例。

7. **移除或提前 setNativeLibraryName('tim2tox_ffi')**  
   会恢复加载原生 IM SDK 库，TIMManager 调用不再进入 Tim2Tox，行为完全错乱。

---

## 阅读源码的推荐入口顺序

1. **入口与库名**：`lib/main.dart` → `lib/bootstrap/app_bootstrap.dart` → `lib/bootstrap/logging_bootstrap.dart`（setNativeLibraryName、AppLogger、FFI setLogFile）。
2. **启动门与会话创建**：`lib/startup/startup_session_use_case.dart`（execute）→ `lib/util/account_service.dart`（initializeServiceForAccount）→ `lib/util/app_bootstrap_coordinator.dart`（boot）→ `lib/runtime/session_runtime_coordinator.dart`（ensureInitialized）、`lib/runtime/tim_sdk_initializer.dart`。
3. **FakeUIKit 与 Platform**：`lib/sdk_fake/fake_uikit_core.dart`（startWithFfi）→ `lib/runtime/session_runtime_coordinator.dart`（设置 Tim2ToxSdkPlatform）→ `third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart`（getHistoryMessageListV2、_handleCustomCallback）。
4. **消息与历史**：`lib/sdk_fake/fake_msg_provider.dart`（sendText、sendFile、_loadHistoryForConversation）→ `lib/sdk_fake/fake_managers.dart`（FakeMessageManager.getHistory、sendText、sendFile）→ `third_party/tim2tox/dart/lib/service/ffi_chat_service.dart`（getHistory、sendText、messages、startPolling）。
5. **HomePage 初始化**：`lib/ui/home_page.dart`（initState）→ `lib/ui/home_page_bootstrap.dart`（_initAfterSessionReady、_initBinaryReplacementPersistenceHook）。
6. **特殊回调与 Hook**：`third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart`；SDK 侧 NativeLibraryManager._handleGlobalCallback / dispatchInstanceGlobalCallback（在 tencent_cloud_chat_sdk 包内）。
7. **拆会话**：`lib/util/account_service.dart`（teardownCurrentSession）→ `lib/runtime/session_runtime_coordinator.dart`（disposeRuntime）。

---

## 相关文档

- [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.md) — 混合架构流程与回调分工
- [ARCHITECTURE.md](ARCHITECTURE.md) — 客户端整体架构与数据流
- [reference/ACCOUNT_AND_SESSION.md](../reference/ACCOUNT_AND_SESSION.md) — 账号与会话生命周期
- [reference/IMPLEMENTATION_DETAILS.md](../reference/IMPLEMENTATION_DETAILS.md) — 实现细节与消息/事件处理
- [Tim2Tox](https://github.com/agentx-icu/tim2tox) [架构](../../third_party/tim2tox/doc/architecture/ARCHITECTURE.md) — 兼容层分层与双路径
