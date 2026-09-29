[English](./MOBILE_DEVICE_FEATURES.md)

# 移动端设备特性兼容清单

> 起草 2026-09-26。姊妹文档：[PLATFORM_SUPPORT](./PLATFORM_SUPPORT.zh-CN.md)、
> [MOBILE_BACKGROUND](../architecture/MOBILE_BACKGROUND.zh-CN.md)。

toxee 同时面向 iOS / iPadOS / Android。手机和平板上有一批桌面端不存在的设备特性
（音频路由、距离传感器、屏幕旋转、分屏、后台挂起、网络切换……），它们会影响聊天、
通话和布局的正确性。本文列出这些特性，逐项给出**是否需要在 toxee 适配**的结论和
当前实现状态。

**这是一份长期约束，不是一次性审计。** 任何新功能或 bugfix 在设计和评审时，都要对照
[§ 新功能评审检查表](#新功能评审检查表) 过一遍（见仓库根目录 `CLAUDE.md` 的
"Mobile parity" 条款）。

## 分级与状态约定

| 级别 | 含义 |
|---|---|
| **P0** | 必须适配。不做会让核心功能（收发消息、通话、布局可用性）出错，或平台/商店强制要求 |
| **P1** | 应当适配。常见使用场景下体验明显受损，排入近期计划 |
| **P2** | 可选。增强体验或小众场景，有需求时再做 |
| **不适配** | 与 toxee 的 P2P / 单实例架构冲突，或收益远小于成本；原因写明，避免反复讨论 |

| 状态 | 含义 |
|---|---|
| ✅ 已实现 | 代码中有对应实现（列出位置） |
| ◐ 部分 | 只覆盖了部分平台或部分场景 |
| ❌ 未实现 | 代码中没有相关处理 |
| 🔍 待实测 | 代码看起来已处理，但未在真机上验证过 |
| ⛔ 阻塞 | 修复需要当前环境无法提供的条件（如真机 + 耳机），方案已写好 |

状态基于 2026-09-26 `master`（40b0cd9）的静态代码核验，并经 codex 复审修订；"已实现"不等于"已在真机上验证"。fork 指 `third_party/chat-uikit-flutter`。

---

## 1. 通话 · 音频

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| A1 | 扬声器 / 听筒切换（外放开关） | P0 | ✅ | `lib/call/audio_devices.dart`、`lib/call/call_audio_route_sheet.dart`；原生 `ios/Runner/CallAudioChannel.swift`、`android/.../CallAudioChannel.kt` |
| A2 | 默认路由：语音→听筒、视频→外放、已连耳机→耳机 | P0 | ◐ ⛔ | 方案见 CALL_AUDIO_ROUTING_PLAN，阻塞于真机。初始路由只在听筒 / 扬声器间选择（`CallAudioChannel.swift:136`、`CallAudioChannel.kt:345`），已连接耳机时是否优先耳机未显式处理 |
| A3 | 蓝牙耳机 / 车载：通话中连上、断开时自动切换 | P0 | ❌ ⛔ | 方案见 [CALL_AUDIO_ROUTING_PLAN](../architecture/CALL_AUDIO_ROUTING_PLAN.md)，阻塞于真机验证（模拟器无法提供耳机）。2026-09-26 已先修：Android 12+ 路由清单改用 `availableCommunicationDevices`（不再列出 A2DP）、识别 BLE Audio / 助听器、处理 `setCommunicationDevice` 失败；iOS 路由事件改在主线程发出。原状况：原生侧只上报设备变化事件（iOS `routeChangeNotification`、Android `AudioDeviceCallback` `CallAudioChannel.kt:78`），Dart 侧（`call_service_manager.dart:1360`）只提示并更新距离传感器，不会主动切到新设备；iOS 的系统默认行为需实测 |
| A4 | 有线 / USB-C 耳机插拔 | P0 | ❌ ⛔ | 同 A3 |
| A5 | 距离传感器：贴耳熄屏防误触 | P0 | ✅ | iOS `CallAudioChannel.swift:132`（`isProximityMonitoringEnabled`）；Android `CallAudioChannel.kt:233-253`（proximity wakelock）。群通话页有意不启用（`call_service_manager_busy.dart:303`） |
| A6 | 音频中断：系统来电、闹钟、Siri、其他 App 抢占音频焦点，结束后恢复 | P0 | ✅ | iOS `interruptionNotification`（`CallAudioChannel.swift:86`）；Android `OnAudioFocusChangeListener`（`CallAudioChannel.kt:48`）；群通话 `av_conference_session_bridge.dart` 的 `interrupted` 状态 |
| A7 | 回声消除 / 降噪 / 自动增益（外放时尤其关键） | P0 | ◐ | 录音已请求回声消除和降噪（`audio_handler.dart:70`），iOS 用 `voiceChat` 模式（`CallAudioChannel.swift:91`）；自动增益没有实现证据，AEC 实际效果需真机外放实测 |
| A8 | 通话结束后确实释放麦克风 / 摄像头（状态栏隐私指示灯熄灭） | P0 | 🔍 | `call_service_manager_native.dart:209`；指示灯残留即资源泄漏 |
| A9 | 静音键 / 勿扰 / 专注模式对来电铃声、消息提示音的影响 | P1 | ◐ | 2026-09-26 评审：Android `playIncomingRingtone`（`CallAudioChannel.kt:260`）显式按 `ringerMode` 处理：静音不响、振动只振动、否则在 `STREAM_RING` 上响铃；勿扰模式下的行为未验证。iOS 来电通常走 CallKit；CallKit 报告失败时回退到 App 内铃声。它原先用 audioplayers 的默认 `playback` 类别，无视静音键——**2026-09-27 已修复**：iOS 也改为原生响铃（`ios/Runner/CallAudioChannel.swift` 的 `IncomingRinger`，与 Android 一样走 `playIncomingRingtone`）：应用在前台时循环播放系统提示音，遵守静音键和铃声音量（是否振动取决于设置），且完全不动全 App 共用的音频会话（因此否决了把 audioplayers 改为 `soloAmbient`）。系统提示音无法让后台应用保持运行，iOS 也不允许后台再启动音频，所以原有的 audioplayers 循环同时以静音运行，应用离开屏幕时取消静音——此时与以前一样不遵守静音键（CallKit 不可用的地区如中国大陆，这就是主要铃声）。启动过程中的停止现在会生效。已在 iOS 模拟器验证（前台原生 + 静音循环、后台循环全音量、正常停止）；静音键本身需真机验证。通知音由通知渠道与勿扰管理 |
| A10 | 通话中音量键调的是通话音量而非媒体音量 | P1 | ✅ 🔍 | 2026-09-26 评审：由平台处理——通话期间音频模式为 `MODE_IN_COMMUNICATION`，AOSP `AudioService.getActiveStreamType` 在该模式下把未指定流的音量键映射到 `STREAM_VOICE_CALL`（蓝牙 SCO 时为其流）；toxee 未设 `volumeControlStream`，正走此默认路径。iOS 的 `voiceChat` 会话同理。离线对端无法发起通话，未实测 |
| A11 | 录音、播放、通话三方共用 AVAudioSession 时的类别冲突（`record` / `audioplayers` / 通话） | P1 | ◐ | `audio_devices.dart:133` 只补救了 PCM 播放器改写会话类别的情况；语音消息录音 / `audioplayers` 播放与通话交错时未覆盖 |
| A12 | 语音消息播放时贴耳自动切听筒 | P2 | ❌ | 常见 IM 体验，非必需 |

## 2. 通话 · 视频 / 摄像头

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| V1 | 前后摄像头翻转 | P0 | ✅ | `lib/call/video_handler.dart:165-182,669`、`call_camera_switch_controller.dart`、`in_call_view.dart:216` |
| V2 | 前置画面镜像（本地预览镜像、发给对端不镜像） | P0 | ✅ | `lib/call/call_video_transform.dart` |
| V3 | 设备旋转时视频帧的旋转角 | P0 | ✅ | `call_video_transform.dart:108-133` |
| V4 | 切后台后摄像头被系统停采，回前台后恢复；对端显示"视频已暂停"而不是卡帧 | P0 | ◐ | 停采与回前台重启已实现（`call_service_manager.dart:506`）；对端只显示最后一帧或通用占位（`in_call_view.dart:256`），没有"视频已暂停"状态 |
| V5 | iPad 多任务（Split View / Slide Over / 台前调度）下摄像头被系统禁用 | P1 | ◐ | 2026-09-27 评审。**已修复——toxee 自己关掉了相机**：通话在 `AppLifecycleState.inactive` 时挂起相机，也就是应用仍在屏幕上、只是失去焦点时（iPad 分屏 / 台前调度的另一半、Android 多窗口、桌面点了别的窗口、下拉控制中心），对方画面随之定格。现在只在应用离开屏幕时挂起（`cameraMayRunIn`，`call_video_lifecycle_controller.dart`）。**已修复——没有说明**：iPadOS 仍中断相机时（多任务、相机被占用、系统压力），本地预览说明原因而不是变黑（`ios/Runner/AppDelegate.swift` 中的 `ToxeeCameraMultitasking` → `lib/call/camera_availability.dart`）。**仍未解决**：真正在 iPad 多任务时保持相机，需要在会话启动前设置 `isMultitaskingCameraAccessEnabled`——只有相机插件能做到（camera_avfoundation 0.9.21+2 没做）——且 `isMultitaskingCameraAccessSupported` 可能需要 `voip` 后台模式或多任务相机 entitlement（部署目标 15.5）；需在 iPad 上确认。对方不会被告知视频为何暂停 |
| V6 | 外接摄像头（iPad USB-C、Android UVC） | P2 | ◐ | 没有相反镜头时按列表轮到下一个设备（`video_handler.dart:170`），外接摄像头可被轮到，但无专门处理 |
| V7 | 人物居中 Center Stage | P2 | 🔍 | 是否默认生效与 App 的后台模式 / 采集配置有关，并非一定无需代码；需在支持的 iPad 上实测 |
| V8 | 变焦、闪光灯 | 不适配 | — | 通话场景不需要 |

## 3. 屏幕与布局

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| L1 | 安全区：刘海、灵动岛、挖孔、圆角、Home 指示条 | P0 | ✅ | 大量 `SafeArea` / `viewPadding` |
| L2 | Android 15+ 强制 edge-to-edge（targetSdk ≥ 35） | P0 | ◐ | `targetSdk = flutter.targetSdkVersion`（36）。2026-09-26 在 API 36 模拟器横竖屏检查：会话列表、聊天、设置、账户信息页内容均未被状态栏 / 导航栏 / 挖孔遮挡；其余页面未逐一检查 |
| L3 | 手机横屏、iPad 四向旋转（Info.plist 已声明，iPad 含倒置） | P0 | ◐ | 2026-09-26 Android 手机横屏实测：列表、聊天、设置可用（键盘问题见 L10，旋转帧问题见 L4a）；iPad 未测。已声明即承诺；聊天、通话、设置、登录页都要能用。旋转不重建 Activity（`configChanges` 含 `orientation|screenSize`） |
| L4 | 运行中跨越响应式断点：旋转 / 分屏导致单栏 ↔ 主从双栏切换时，当前会话、输入草稿、通话界面不丢 | P0 | ◐ | 2026-09-26 修复（会话与草稿）：原先跨过 800 断点只切换 UIKit 布局模式，双栏里打开的会话在切到单栏时丢失、单栏推入的聊天页在切到双栏时整屏盖住双栏。现由 `lib/ui/home/master_detail_transition.dart` + `lib/navigation/root_route_tracker.dart` 迁移"实际可见"的那个会话（被其他页面盖住时不动）。API 36 手机模拟器旋转双向实测通过，草稿保留。共享 Dart 逻辑，iPad / 桌面窗口缩放走同一路径但未实测；通话界面跨断点未验证 |
| L5 | iPad Split View / Slide Over / 台前调度（窗口任意尺寸下核心界面可用） | P0 | 🔍 | Info.plist 无 `UIRequiresFullScreen`，多任务默认开启。该键在 iPadOS 26 起已弃用，**不应靠它关闭多任务**，而应保证任意宽度可用。布局按宽度响应，理论可用，未实测 |
| L6 | Android 分屏 / 自由窗口 / 小窗（各厂商，窗口任意尺寸下核心界面可用） | P0 | ◐ 🔍 | 2026-09-26 在 API 36 模拟器上用 `wm size` 模拟 320dp 宽、半屏高度，并实测横竖屏旋转：布局正常、会话与草稿保留（见 L4）。未测真正的多窗口分屏与各厂商小窗。 Manifest 未声明 `resizeableActivity`（默认可分屏）。targetSdk 36 的应用在最小宽度 ≥ 600dp 的设备上，Android 16 会忽略方向和可调整尺寸限制（16 上还可临时退出，之后的版本不行）；`targetSdk = flutter.targetSdkVersion`（`build.gradle.kts:60`）。同 L5，按宽度响应，未实测 |
| L7 | 多窗口 / 多 Scene（iPad 多 Scene、Android 多实例窗口） | 不适配 | — | toxee 是单 Tox 实例（见 `CLAUDE.md` Singleton flow）。共享同一会话的多窗口理论可行，但收益小、改动大；保持不声明 `UIApplicationSupportsMultipleScenes` |
| L7a | 防止重复启动争用同一 profile（Android 多次唤起 Activity、多实例窗口） | P1 | ✅ | 2026-09-26 实测确认缺陷：App 在后台时以 `FLAG_ACTIVITY_MULTIPLE_TASK` 启动，同进程出现第二个 MainActivity 和 Flutter 引擎，对同一原生实例再次登录。修复：`SessionOwnerChannel.kt` + `lib/bootstrap/single_session_guard.dart`——进程内首个 Activity / 引擎认领会话（原生 onCreate 与 Dart main 在任何 Tox 初始化前），后来者把启动 intent（如锁屏来电）转交所有者、把所有者任务调到前台并关闭自己。`launchMode` 保持 `singleTop`：试过 `singleTask`，从启动器重入会清掉其上的文件选择器。第二个实例的 Flutter 引擎与插件仍会启动，守卫挡住的是 Tox 会话初始化。API 36 复测：同一命令后仅一个 MainActivity、仅一次登录；打开文件选择器后从启动器重入，选择器保留。文件选择器盖在 MainActivity 上时来电（系统此时会另建实例），来电 intent 交给所有者，但原先只把任务调到前台，来电界面仍被选择器遮住——2026-09-27 已修复：MainActivity 记录自己以 startActivityForResult 打开的界面（选择器、相机、SAF），收到经授权的来电 intent 时用 `finishActivity` 关闭它们（各自收到取消结果，如同按返回）。已在 Android 16 模拟器通过仅调试版可用的入口验证（toxee 任务里的文件选择器被关闭，MainActivity 回到顶端）；端到端来电路径需真实来电 |
| L4a | 旋转跨越断点的那一帧：主从布局控件先按新宽度布局一次（UIKit 布局模式在帧后才切换），右侧面板的标题行和输入行水平溢出 40 / 52 px，下一帧恢复 | P2 | ✅ | **2026-09-29 已修复。** 同一个决定有两份过时的副本：toxee 在帧后回调中切换 UIKit 的布局模式，而 UIKit 会话组件把模式缓存在 State 里，只靠异步送达的变更事件刷新。现在 `MasterDetailTransition.onBuild` 在跨越断点的那次 build 中、UIKit 子树布局之前就切换模式（UIKit 尚未就绪时仍走帧后重试；迁移已打开的会话仍在帧后），fork 的 `TencentCloudChatConversation` 在 build 时从配置读取模式。已在 API 36 手机模拟器复现：右侧面板打开会话时每次横屏 → 竖屏都会溢出（40 / 36 px）；修复后四轮均无溢出，会话双向保留。窄 → 宽方向也不再闪现一帧单栏列表。共享 Dart 代码：手机、平板、分屏和桌面窗口缩放同样适用 |
| L8 | 折叠屏：展开 / 折叠时尺寸变化 | P1 | 🔍 | 本质同 L4；`configChanges` 含 `smallestScreenSize|screenLayout`，不会重建 |
| L9 | 折叠屏铰链避让、Flex 半折模式 | P2 | ❌ | 无 `DisplayFeature` 处理 |
| L10 | 软键盘：弹出遮挡、横屏键盘、iPad 悬浮 / 分离键盘 | P0 | ◐ | 2026-09-26 修复：手机横屏双栏右栏弹出键盘后窗格只剩约 125dp，标题栏 + 输入框放不下，溢出 19px。fork `tencent_cloud_chat_message_layout.dart` 的 desktopBuilder 现在：有软键盘且窗格低于标题栏 + 输入框时收起标题栏（左侧列表仍可见），并在此时把输入框高度约束在正文内（桌面输入框会撑满有限高度，故只在有软键盘的压缩态约束）。模拟器实测修复，回归测试 `mobile_composer_real_ui_test.dart`（无修复时失败）。竖屏键盘正常。iPad 悬浮 / 分离键盘未测（Flutter iOS 对悬浮键盘通常不报 inset） |
| L11 | 系统字体缩放 / 辅助功能大字体 | P1 | ✅ | **2026-09-29 已全面检查**：Android 最大字号（字体缩放 2.0，API 36 模拟器）下走查了会话列表、聊天、附件面板、联系人及其子页面、好友资料、添加联系人对话框、全部设置页和应用页。任何地方都没有 RenderFlex 溢出；修复了截断或拆开单词的地方：附件面板（“Cam” / “era”）和联系人页面的“返回”（“Ba…”）现在随字号变宽；好友资料的发消息 / 语音 / 视频卡片在单词放不下时改为整行竖排（“mes” / “sage”）；账号管理的按钮改为换行而不是“Export A…”；三处完全不随系统字号缩放的 `RichText`（搜索高亮、Bootstrap 模式说明）改为 `Text.rich`；节点地址在端口前换行，而不是断在端口中间。保持原设计：底部导航标签（Flutter 的 `BottomNavigationBar` 不缩放它们，长按可显示）和应用卡片两行描述（网格行高已随字号缩放）。共享 Dart 代码，iOS 动态字体走同一路径 |
| L12 | 深色模式跟随系统 | P1 | ✅ | `lib/main.dart:269-285`（`ThemeMode.system`） |
| L13 | 通话期间屏幕常亮 | P0 | ✅ | `lib/call/call_effects_listener.dart:70,88`（`WakelockPlus`） |

## 4. 后台与生命周期

P2P 客户端在移动端最根本的限制在这里，详见 [MOBILE_BACKGROUND](../architecture/MOBILE_BACKGROUND.zh-CN.md)。

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| B1 | 切后台后保持 Tox 连接 | P0 | ✅ Android / ◐ iOS | Android 前台服务 `ToxPollingService`（常驻模式 API 34+ 用 `specialUse`、以下用 `dataSync`；通话时 `phoneCall|microphone|camera`），被系统停掉后回前台自动恢复（见 B8）；iOS 只有 `audio` + `fetch` 后台模式和 `BGAppRefreshTask`（`BackgroundTaskController.swift`），属尽力而为 |
| B2 | App 已终止后仍能收到消息和来电（推送唤醒） | 不适配 | — | 需要 APNs / FCM / PushKit 服务端，与纯 P2P 架构冲突（MOBILE_BACKGROUND 有详细论证）。应在产品层面向用户说明。区分：App 仍存活但被挂起时，iOS 还有偶发的 BG refresh，但不能承诺实时收信 |
| B3 | 后台 / 锁屏可接听的来电界面 | P0 | ✅ | iOS CallKit（`CallKitProvider.swift`，App 存活时）；Android 全屏通知（`notification_channels.dart:83`、`notification_service.dart:755`） |
| B3a | Android `ConnectionService`：蓝牙按键接听、车机集成 | P2 | ❌ | 未接入 |
| B4 | 生命周期：`paused` / `detached` 时落盘 profile | P0 | ✅ | `lib/ui/home_page.dart:613-617`；`inactive` 会被控制中心、来电等频繁触发，有意不处理 |
| B5 | 厂商后台管控（MIUI / EMUI / ColorOS 自启动、电池优化白名单）、Doze | P1 | ◐ | 设置 → 后台与通知显示 toxee 是否已免除电池优化，并提供「允许」（`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`，不可用时退到白名单列表页）；回到前台时重新读取状态（`NotificationAccessChannel.kt`、`lib/ui/settings/background_settings_section.dart`）。Play 政策：直接请求（`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`）面向无法依赖 FCM 高优先级消息的聊天 / 通话应用——toxee 没有推送服务器；上架时重新核对现行政策，若被拒就去掉该权限（列表页兜底不需要它）。仍未解决：厂商自启动页（MIUI / EMUI / ColorOS）没有公开 intent，没有通用修法 |
| B6 | Android 进程被回收后的冷启动恢复（回到原会话） | P1 | ✅ | 2026-09-27 复现：后台被系统回收后，toxee 自动登录回到会话列表，原来打开的会话丢失。已修复（`lib/ui/home/open_chat_restoration.dart`）：把当前显示的会话写进 Flutter 的状态恢复数据——系统只在它自己回收进程后交还，用户划掉或重启后不会——每次导航后和应用转为 inactive 时写入并立即刷新。会话就绪后只对同一账号重新打开；若启动时路由了通知（通知优先）或恢复的拍摄（M9）要打开它自己的会话，则不恢复。iOS：storyboard 加 `restorationIdentifier`（保留 FlutterAppDelegate 的恢复校验）。已在 Android 16 模拟器验证：回收后重新进入回到该会话；从最近任务划掉则回到会话列表 |
| B7 | 低电量模式 / 省电模式下降低轮询与视频码率 | P2 | ❌ | |
| B8 | `dataSync` 前台服务时长限制：targetSdk ≥ 35 的应用在后台时每 24 小时累计 6 小时（回到前台会重置额度），超时后的 `onTimeout` 处理与降级 | P0 | ✅ 🔍 | 2026-09-26 修复：常驻模式 API 34+ 改用无时长限制的 `specialUse`；实现 API 35 `onTimeout` 及时停止；`startForeground` 被拒时降级或停止；Dart `RuntimeForegroundService.ensureRunning` 回前台时查询原生实际状态并重放最后请求的模式（通话中保持通话模式）。待 API 36 真机 / 模拟器验证 |
| B9 | iOS 设备锁定后的数据保护：后台期间 profile / 消息落盘能否读写 | P1 | ✅ | 2026-09-27 评审。**文件**：未设置保护级别，资料、历史、离线队列与偏好使用 iOS 默认级别（开机首次解锁后即可访问，锁屏时也可）；首次解锁前 iOS 不会运行后台任务。将来若改用更严格级别，必须在原子 rename 前给每个新建的 `tox_profile.tox.tmp` 设置。**钥匙串——修复一个安全漏洞**：条目为 `WhenUnlocked`，而 flutter_secure_storage 9.2.4 会把锁屏时的读取错误变成「不存在」（它带 `kSecAttrSynchronizable` 重试并返回该结果），因此锁屏后台启动时，自动登录关卡可能把有密码的账号当成无密码，打开被系统回收时留下的已解密资料。现在只要插件说「没有值」，iOS 就直接问钥匙串（`toxee/keychain_probe`，与插件相同的查询、不重试）：只有真正的「不存在」才算没有，其他一律视为不可用，关卡按有密码处理；无密码账号锁屏时仍可自动登录。已在 iOS 模拟器验证探测结果（missing / found）；锁屏读取本身需真机。IRC 频道密码锁屏时读不到（带密码的频道解锁后再加入） |

## 5. 网络

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| N1 | Wi-Fi ↔ 蜂窝切换、IP 变化后的快速重连（尤其通话中） | P1 | 🔍 | **2026-09-29 已实现，恢复时长未实测。** 之前没有网络监听，唯一的额外 bootstrap 是回前台*且已断线*时（`home_page.dart` `_refreshBootstrapOnResume`；断线监听只驱动横幅）。与 codex 讨论后在无实测的前提下决定实现（一次补发只是几次 `tox_bootstrap` / `tox_add_tcp_relay`，不重启 Tox）：原生默认网络监听——Android `registerDefaultNetworkCallback`（API 23 用 INTERNET 回调重读 `activeNetwork`；已加 `ACCESS_NETWORK_STATE`），iOS `NWPathMonitor`（在用接口类型 + 其地址 + 网关）——交给 `NetworkChangeReBootstrapper`（`lib/util/network_change_rebootstrapper.dart`）：忽略首个快照，只有“可用且路径变化”才算（离线取消待办，恢复在线算变化），3 s 防抖，同时只跑一个、间隔 ≥ 30 s 且保留一次尾随，会话销毁即停止（进行中的补发检查 `isLive`）。补发（`BootstrapNodeEnsurer.reapplyForNetworkChange`）**不**以 `isConnected` 为前提（IP 变化后状态滞后）：已保存节点、内置节点、再拉在线列表。策略有单测；APK 可编译，iOS 监听代码类型检查通过；无设备，切换行为与恢复时长收益未验证。toxcore 层限制：onion bootstrap 条目与 TCP 中继按节点公钥只保留第一个地址（见 N2 / N3） |
| N2 | 蜂窝网络屏蔽 UDP、对称 NAT：TCP relay 兜底 | P0 | 🔍 | 2026-09-26 评审（codex 复核）：`add_bootstrap_node` 依次对 UDP 端口、443、3389 调 `tox_add_tcp_relay`（`tim2tox_ffi.cpp:3600-3605`），但 toxcore 按公钥去重 relay（`TCP_connection.c:1361-1364`），首次添加成功的那个端口即 UDP 端口生效，后两个被拒。nodes.tox.chat 2026-09-25 快照中公布了 TCP 端口的节点，其 UDP 端口都在 `tcp_ports` 里，这些节点选中的端口正确，**未改代码**（例外见 N2a）。仍待验证的是连通性本身：Android 设 `debug.toxee.force_tcp_only=1`（桌面 / iOS 用环境变量 `TOX_FORCE_TCP_ONLY`）后在真实网络上确认能连上。2026-09-26 在构建 Mac 的 API 36 模拟器上未能判定：TCP-only 与 UDP 对照组 5 分钟内都未连上，到 144.217.167.73 的 33445 / 3389 均 `Connection refused`。下次须在已确认 relay 可达的网络上：启动前设开关、核对日志中"TCP-only mode enabled"、同网络跑 UDP 对照组、确认连接状态为 TCP |
| N2a | 节点的 TCP 端口不包含其 UDP 端口时选错 relay 端口；已保存节点只存 host/port/pubkey | P2 | ❌ | 线上快照中没有，但内置回退列表有一个（`bootstrap_nodes.dart:294`：UDP 43334、TCP `[3389, 33445]`），其 TCP relay 实际不可用。回退列表只在拉取节点列表失败时使用。要修需按节点选单个端口并把"未知 / 无 TCP / 端口列表"持久化进 prefs（先应用的已保存节点会占住该公钥） |
| N3 | IPv6-only / NAT64 网络 | P0（若上架 App Store） | 🔍 | **2026-09-29 代码已修复，未在 NAT64 网络实测**（此环境没有）。IPv6 已开启（`V2TIMManagerImpl` / `ToxManager` 默认 `ipv6_enabled` 为真），主机名走 `getaddrinfo(AF_UNSPEC)`（DNS64 可用）。问题在于：toxcore 自己解析 IPv4 *字面量*并以 `::ffff:a.b.c.d` 发送，在无 CLAT 的纯 IPv6 网络（Apple 审核网络）不可达；toxee 又只 bootstrap 节点的 IPv4——首次启动的 4 个内置节点有 3 个在此不可用。修复：tim2tox `add_bootstrap_node` 与探测用的 `dht_send_nodes_request` 对 IPv4 字面量先试 NAT64 合成地址（Apple `getaddrinfo(AI_DEFAULT)`，`source/Nat64Synthesis.h`，有 gtest），再试字面量本身（toxcore 每个公钥只保留第一个 onion/TCP 地址）；任一候选成功即成功（FFI ABI 不变）。toxee 对节点公布的每个地址都 bootstrap（`BootstrapNode.bootstrapHosts`，先 IPv4 后 IPv6）。Android：IPv4 字面量依赖网络是否运行 CLAT；否则只有节点的 IPv6（排第二）增加一个 DHT 目标。遗留：NAT64 → IPv4 切换后该公钥的 onion bootstrap 条目仍是合成地址（靠 DHT 学到的节点 + N1 的补发恢复）；纯 IPv6 手机仍连不上只有 IPv4 的 DHT 节点（toxcore 限制）；中继端口去重见 N2 / N2a。局域网配对绑定 `0.0.0.0`（仅局域网，不在范围内） |
| N4 | iOS 本地网络权限（局域网发现、LAN 配对） | P0 | ✅ | `NSLocalNetworkUsageDescription`、Bonjour `_tox._tcp` |
| N5 | 蜂窝流量控制（文件自动接收、视频码率） | P2 | ❌ | |

## 6. 权限与隐私

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| P1 | 运行时权限：相机、麦克风、相册、通知（Android 13+）；拒绝后的提示与跳转设置 | P0 | ◐ | `permission_handler`。2026-09-26 API 36 实测麦克风（语音消息）：首次拒绝无任何反馈；第二次拒绝起弹"权限被拒绝 / 去设置"对话框（fork `tencent_cloud_chat_permission_handlers.dart`）。相机 / 相册共用该 handler，未逐一实测。通知权限见 P1a |
| P1a | 通知权限被拒：Android 上消息通知与来电全屏通知不再发出（iOS 消息提醒受限，来电走 CallKit）；用户拒绝时不知道后果 | P1 | ◐ | 2026-09-26 先修两个缺陷：启动时的权限请求被错误的 API 版本判断跳过（Android 13 算成 API 32）；拒绝结果整会话缓存，去系统设置开启后仍不发通知直到重启——现在回前台只读重查。另修 L3 禁止弹窗开关在 Android 无效。随后加入 `NotificationAccessMonitor`（`lib/notifications/notification_access.dart`）：区分总开关 / 来电渠道 / Android 14+ 全屏意图 / 消息渠道 / 其余渠道 / iOS 横幅关闭 / iOS provisional，权限请求结束与每次回前台即刷新；聊天标签顶部常驻提示条（`notification_access_banner.dart`，7 种语言）按状态说明并直达对应系统设置页。API 36 实测：拒绝后出现提示，设置里开启后返回即消失。iOS 未实测 |
| P1b | 首次拒绝权限时静默无反馈；麦克风在原状态为拒绝、本次授予时仍返回失败（需再按一次） | P2 | ✅ | **2026-09-29 已修复**（fork `TencentCloudChatPermissionHandler.requestPermission`）。是否静默原由一个持久化的「每个权限字符串首次拒绝」缓存决定，因此权限已被封禁（Android「不再询问」、iOS 设置中关闭）时，只要该字符串没在 App 内被拒过，点按就毫无反应——已在 Android 模拟器上用相机复现。现在拒绝时是否弹「去设置」对话框，取决于从权限状态推断系统是否询问过（尽力而为的判断）：请求前已被封禁或受限，或系统未询问就直接拒绝（Android：请求前后 rationale 标志都为 false；首次提示被点外部关掉时标志也是如此，同样弹出说明——该标志无法区分二者，弹出说明是更安全的一侧——不能靠 App 生命周期判断，因为即便如此 Android 也会为一个不可见的 GrantPermissionsActivity 暂停 App）时弹出；用户刚在系统提示里拒绝的，不再叠加第二个对话框。已在 Android 模拟器验证：在系统提示中第一次、第二次拒绝都不再弹框，之后的点按给出说明；麦克风在提示中授权后显示提示语，下一次按住即可录音。iOS 的 `restricted` 不再算作已授权。麦克风：触发系统提示的那次按压仍不录音（手指已随提示离开），但现在会显示「按住录音，松开发送」提示；以指针取消或 App 被打断（系统弹窗、来电界面、通知栏）结束的按压会丢弃录音，而不是让它继续录。共享 Dart 代码，Android 与 iOS 同样适用 |
| P2 | 使用中权限被收回（去设置里关掉再回到 App） | P1 | ✅ | **2026-09-29 已在 API 36 模拟器验证**：收回已授予的运行时权限会杀掉进程，与 iOS 相同——麦克风（聊天打开时）和相机（P1b 复现过程中）均已观察到。任务被替换，下次启动干净地回到会话列表、没有残留状态，下次使用时重新请求（被封禁的由 P1b 给出说明）。收回本未授予的权限不产生任何变化。未实测：通话中收回（此处无 Tox 连接）——同样会因进程被杀而结束通话 |
| P3 | Keychain / Keystore 安全存储；iOS 卸载重装后 Keychain 残留 | P1 | ◐ | `flutter_secure_storage`；重装后残留旧密码数据与新安装状态不一致的情况需确认 |
| P4 | 敏感页防截屏 / 录屏、App 切换器快照模糊（私钥 / profile 导出、二维码） | P2 | ❌ | 无 `FLAG_SECURE`；属于产品决策 |
| P5 | 生物识别解锁（Face ID / 指纹） | P2 | ❌ | |
| P6 | iOS "部分照片"授权、Android 14 部分媒体访问 | P2 | 🔍 | 选择器基于系统 picker，一般无需完整相册权限 |
| P7 | iOS 剪贴板读取的"允许粘贴"弹窗 | P2 | 🔍 | `pasteboard` 读图时触发 |

## 7. 媒体与文件

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| M1 | 从相册 / 相机选择图片视频 | P0 | ✅ | `file_picker`、`camera` |
| M2 | HEIC / HEVC 等 iOS 默认格式发给桌面端（Windows / Linux 可能无法显示） | P1 | ✅ | 发送端转换，按内容判断（不看文件名）（`lib/util/outgoing_media.dart`，通道 `toxee/media_transcode`），两条发送路径都覆盖（toxee `_sendMedia`；UIKit 粘贴 / 拖放经 fork 的 `outgoingMediaPreparer`，在气泡生成之前）；转换失败则不发送，绝不改发原文件。**照片**：HEIC / HEIF → JPEG，去掉 GPS、保留方向（iOS / macOS 用 ImageIO；Android 9+ 用 ImageDecoder）。**视频**：HEVC（探测编码）→ H.264 / AAC MP4（iOS / macOS 用 AVAssetExportSession 1080p 尺寸预设，HDR 映射为 SDR；Android 用 Media3 Transformer，编码器可降级），发送前核验输出为 H.264 且有真实帧；转换时显示带「取消」的进度对话框（取消即静默停止发送）。Windows / Linux / Android 9 以下的照片：没有转换器，也不会拍出 HEIC。接收端 `.heif` 按图片处理 |
| M3 | 保存到相册 | P1 | ✅ | 手机上媒体查看器的「保存」把收到的图片 / 视频直接存进相册（Android MediaStore `Pictures/Toxee` / `Movies/Toxee`；iOS Photos，按文件导入，GIF / HEIC 原格式保留）。类型按文件头字节判断（收到的文件常无扩展名；`lib/util/gallery_saver.dart`）；相册失败或权限被拒会报错，不会转去别处；只有相册收不了的内容（如 iOS 上的 WebM）才走保存对话框。fork 接缝：`MessageViewerMediaSaver.defaultGallerySaver`。桌面仍用目录选择器。文件消息没有「保存」操作（经系统打开，见 M4） |
| M4 | iOS "文件" App 共享、Android SAF 选择器 | P1 | ◐ | `UIFileSharingEnabled`；Android SAF 已知有误触锁死问题 |
| M5 | 存储空间不足时接收大文件 | P1 | ✅ | **2026-09-29 已修复**（tim2tox 原生 + Dart，toxee 提示）。之前：写失败只置标志，传输照样跑完、每块都写失败，半成品一直占着空间，Dart 收不到任何事件；`fflush` 错误被忽略（可能带着空洞“成功”）；用户只在 180 s 无进度后看到无原因的失败气泡；被杀进程留下的半成品永不清理；完成时*复制*文件（需要第二份空间）。现在：放不下（文件 + 16 MiB）时事先拒绝接收（`file_control` → -7，带类型的 `FileControlException`；手动下载保留可重试）；写或 flush 失败（ENOSPC / EDQUOT → `no_space`）立即取消传输、删除半成品并向 Dart 发 `file_recv_failed:`；对方取消也会关闭并删除接收文件；`.<文件>.t2t-receiving` 标记覆盖到 Dart 完成落地为止，残留标记在下次会话启动时清扫；落地优先 rename，否则复制到唯一的 `.toxee-part` 暂存再改名到原子预留的文件名，失败即清理；所有情况都进入 `FfiChatService.fileReceiveFailures` → 本地化提示（`FileReceiveFailureNotifier`，六种语言）。已验证：gtest（含真实写满的 5 MB `hdiutil` 卷，write+flush 判为 `no_space`）、Dart 单测、组件测试、tim2tox auto_tests 阶段 1/3/8/12/14（含文件传输）全绿。未验证：真机传输中途写满（无设备）。iOS `statvfs` 不计可清除空间，事先检查可能偏保守。遗留：跨卷暂存复制期间崩溃会在 Downloads 留下 `.toxee-part`（无法证明归属，不自动删除）。原生 + Dart 共用：Android、iOS 一致 |
| M6 | 大图 / 视频缩略图的内存占用（移动端内存小，易被系统杀） | P1 | ✅ | **2026-09-29 已修复。** 以下位置按原图全分辨率解码（1200 万像素约 48 MB，4800 万约 190 MB；屏幕上的图不受 `ImageCache` 上限约束）：每个聊天图片气泡、全屏查看器、UIKit 头像（会话列表、消息行；好友头像最大 10 MiB 自动接收）、通话头像、回复预览、二维码卡片头像（且从不 dispose）。新增 fork `TencentCloudChatBoundedImage`：按控件物理尺寸解码并保持宽高比（头像用 cover——toxee 头像原先同时设 `cacheWidth`+`cacheHeight` 会把非方图压扁；查看器用 fit：屏幕 2 倍、每边 ≤ 4096、≤ 1600 万像素），从不放大，并有硬像素上限（气泡 200 万）防极端长条；缓存键带文件大小 + 修改时间，解码失败自动逐出（气泡的解码重试照常工作）。已有上限 / 保持不变：恢复拍摄对话框、视频快照气泡、原生视频缩略图生成（≤ 1280 px）、本地生成的二维码。单测 + 组件测试验证（尺寸计算、真实解码、失败恢复、同路径重写、气泡 / 头像 / 通话头像的 provider）；未在真机实测内存。Dart 共用：Android、iOS 一致 |
| M7 | 扫码（横屏 / 分屏下的取景） | P1 | ◐ | `mobile_scanner` |
| M8 | 从其他 App 分享到 toxee（Share Extension / `ACTION_SEND`） | P2 | ❌ | 功能新增 |
| M9 | 调用系统相机 / 选择器期间 App 进程被回收，返回后结果丢失 | P1 | ✅ | 仅 Android（iOS 选择器在本进程内）。**相机：已修复**——打开系统相机前记下目标聊天；进程被回收后，选择器遗留的结果转存到所属账号的存储（`lib/util/camera_capture_recovery.dart`），重新打开该聊天并弹窗展示照片 / 视频与收件人：发送或丢弃，不会未经确认就发出；期间再次被回收仍保留，其他账号看不到，退出登录 / 删除账号 / 24 小时后丢弃。**文件选择：2026-09-29 已修复**——file_picker 无法把结果交给重建的进程（其请求码取自对象哈希，选择状态随进程一起消失），所选文件就此丢失；已在 API 36 模拟器上于 DocumentsUI 打开期间杀进程复现。`android/.../LostFilePickChannel.kt` 为文档选择请求打标（每个进程一个随机令牌，用来区分已死进程发起的请求），复制到缓存前先持久化读取授权和 URI（复制中途再被回收会续传），并一直保留到 Dart 记录完毕（`CameraCaptureRecovery.stageFilePick`）：同一个对话框按文件名把它提供给同一聊天，以原文件名发送。已在模拟器验证：杀进程 → 选择 → 重启 → 弹窗 → 以 `m9_probe.txt` 发出；正常选择不留任何状态。toxee 在移动端关闭了相册选项，文件选择器是唯一的另一个选择入口。已知缺口：被回收进程留下的选择器无法被来电关闭（L7a 只跟踪本进程的请求）。B8 的前台服务已让此类回收更少发生 |

## 8. 通知与系统集成

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| S1 | 本地通知、角标 | P0 | ✅ | `flutter_local_notifications`、`app_badge_plus`、`lib/notifications/` |
| S2 | 锁屏通知隐藏消息内容的选项 | P1 | ✅ | 设置 → 后台与通知 →「通知中隐藏消息内容」，默认关，整机生效，全平台。隐藏时消息通知只显示「Toxee / 新消息」，不带头像，且不再合并多行（开关打开前合并的行含真实内容）；打开时撤回已发出的消息通知，包括上一个进程发出的（`notification_service_privacy.dart`）；读不到设置时按隐藏处理，保存失败则开关回退（`lib/notifications/notification_privacy.dart`）。好友请求 / 群邀请 / 通话通知不属于消息内容，保持原样 |
| S3 | 振动 / 触感反馈 | P1 | ✅ | |
| S4 | 视频通话画中画（切后台继续小窗） | P2 | ❌ | iOS 需 `AVPictureInPictureVideoCallViewController` + 多任务摄像头授权，Android 需 `supportsPictureInPicture`，原生工作量大 |
| S5 | 通话中的灵动岛 / Live Activity、Android 进行中通话通知 | P2 | ◐ | Android 前台服务通知已存在 |
| S6 | 深链接（`tox:` URI 加好友、`tox://pair` 配对） | P2 | ❌ | 有 `tox://pair` 解析（`lib/util/pairing/pairing_url.dart`），但 Manifest 只有启动入口，iOS 无 `CFBundleURLSchemes`，没有接入系统 |
| S6a | 主屏快捷方式、小组件 | P2 | ❌ | |
| S7 | iOS 通信通知（带头像）、Android 会话气泡 | P2 | ❌ | |

## 9. 输入与交互

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| I1 | 长按菜单与系统文本选择菜单不冲突 | P0 | ◐ | 已修过一轮，见 iPhone narrow-shell 记录 |
| I2 | 系统返回：Android 预测性返回、iOS 边缘右滑，与路由栈 / 弹窗的交互 | P0 | ◐ | 已开启 `enableOnBackInvokedCallback="true"`。2026-09-26 API 36 实测：左边缘返回手势与返回键从聊天回到列表；弹出菜单只关闭菜单；设置子页只退一层；非聊天标签返回切到聊天标签；根页面"再按一次退出"。通话界面下的返回与 iOS 右滑未测 |
| I3 | iPad 外接键盘：回车发送、快捷键 | P1 | ◐ | 移动端输入组件已处理实体键盘回车发送、组合键换行（fork `tencent_cloud_chat_message_input_mobile.dart:794`）；其他快捷键未核实 |
| I4 | iPad 鼠标 / 触控板悬停、右键菜单、拖放文件进聊天 | P2 | ❌ | |
| I5 | 读屏（VoiceOver / TalkBack） | P1 | ◐ | 2026-09-27 对主聊天流程做 TalkBack 审计（Android 16 模拟器，无障碍树）：聊天页返回键、对方头像、语音 / 视频通话按钮，输入栏的「+」附件、表情 / 贴纸与发送按钮，图片气泡与发送者头像，以及会话列表的主题切换与「+」都没有名称——其中「+」（附件）和图片气泡根本无法激活（只有按下 / 抬起处理）。已用 tooltip / `Semantics` 与现有本地化文案修复（fork 的消息头、输入栏、图片气泡、发送者头像、会话列表 AppBar；toxee 的 `NewEntryButton`）；依赖按下位置的操作在控件中心补发一次点击。修复后审计范围内的控件都有名称，发送按钮读作「Send」。**2026-09-29 第二轮审计**（会话列表、聊天、联系人及子页面、好友与本人资料、添加联系人、全部设置页、应用页；无障碍树加 Flutter 语义树）：每个会话行前都有一个无名称的焦点（SwipeActionCell 的手势检测器总是暴露一个空操作的点击），且整行被读作「图片」——现合并为一个节点，读屏时无法滑出的滑动操作（置顶、更多）作为该节点的自定义操作提供（TalkBack 的操作菜单、VoiceOver 的转子）；消息列表有一个无名称的点击区域（收起键盘），每条已发消息的状态勾也无名称——前者已排除，状态勾读作「已送达 / 已读」（发送失败的仍是「重试」按钮；阿拉伯语的「已读」原是祈使句，已改为状态）；设置里的开关（自动登录、自动接受好友、通知声音）和好友资料的免打扰 / 置顶 / 拉黑开关读不出标题——行已合并；设置子页面的返回按钮、错误横幅的关闭、IRC 对话框的密码显隐、好友资料的修改备注按钮以及本人头像（「更换头像」，七种语言）都没有名称。修复后这些页面上可操作的控件都有名称；输入框保留占位提示，TalkBack 会朗读。仍未完成：用 TalkBack / VoiceOver 实际朗读走一遍（不只看两棵树），以及通话页面（需要真实通话） |
| I6 | 系统 12 / 24 小时制 | P1 | ✅ | 2026-09-26 修复：fork `tencent_cloud_chat_intl.dart` 的消息时间、会话列表时间与 `formatDateTime` 在有 context 时读取 `MediaQuery.alwaysUse24HourFormat`，24 小时制下用 `Hm`，否则保持语言惯例。回归测试 `test/uikit_runtime_locale_regression_test.dart`；API 36 实测系统 24 小时制下显示 03:01 |

## 10. 其他

| # | 特性 | 级别 | 状态 | 说明 / 位置 |
|---|---|---|---|---|
| O1 | RTL 语言布局镜像 | P1 | ✅ | `ar.lproj` 等六种语言 |
| O2 | 发热降频时的视频编码自适应 | P2 | ❌ | |
| O3 | CPU 架构：arm64 真机 + 模拟器 | P0 | ✅ | Android `abiFilters` 按 FFI 产物过滤 |

---

## 新功能评审检查表

新功能或 bugfix 在设计和评审时逐项作答，每项写 **已验证 / 待处理 / 不适用（附理由）** 之一：

1. **尺寸**：在 320pt 宽、iPad 分屏 1/3 宽、横屏、以及运行中跨越响应式断点时都可用；状态（草稿、选中会话、滚动位置）不丢。（L3–L6、L8）
2. **安全区与键盘**：内容不被刘海、Home 指示条、edge-to-edge 系统栏或软键盘遮挡。（L1、L2、L10）
3. **大字体与读屏**：最大字体档位下不溢出；新增控件有语义标签。（L11、I5）
4. **生命周期**：进行到一半时切后台、被挂起、被系统杀掉，不丢数据、不卡在中间状态；回前台能恢复。（B1、B4、B6、V4、M9）
5. **后台时长**：依赖后台运行的逻辑考虑了 Android 前台服务时长限制和 iOS 挂起。（B1、B8）
6. **音频**：播放或录制声音时，与通话、系统来电、蓝牙 / 有线耳机、静音键不冲突。（A1–A11）
7. **摄像头**：多任务或后台时摄像头不可用，有明确状态。（V4、V5）
8. **权限**：用到的权限被拒绝、永久拒绝、中途收回时有提示和出路；通知权限被拒时来电仍有入口。（P1、P2、B3）
9. **网络**：切换网络、弱网、只有 TCP relay、IPv6-only 时仍可用。（N1–N3）
10. **跨平台对端**：发出的数据（图片 / 视频格式、文件、元数据）桌面端对端能处理。（M2）
11. **单实例**：设计不假设同时存在多个窗口或多个 Tox 实例。（L7、L7a）
12. **移动端对等**：修的 bug 在 iOS / Android 上是否同样存在，已一并修复或说明为何不适用（`CLAUDE.md` Mobile parity）。

## 已知不一致

- （已解决 2026-09-26）`MOBILE_BACKGROUND` 曾描述 `voip` 后台模式，该模式已在 `285c6f7` 中移除；文档已更正。
