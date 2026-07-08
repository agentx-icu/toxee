# toxee 全面 Code Review — 子任务 Prompt 模板

> 生成日期：2026-05-20
> 配套清单：[`2026-05-20-feature-inventory.md`](./2026-05-20-feature-inventory.md)
> 用途：每条 prompt 可直接交给 `feature-dev:code-reviewer` 或 `general-purpose` agent。

## 使用建议

- **依赖顺序**：Batch 1 优先（揭示混合架构问题，可能放大其他 batch 的问题面）；Batch 6 可独立先跑；2/3/4/5 互不依赖，可并行。
- **agent 选型**：建议用 `feature-dev:code-reviewer`（自带 confidence-based 过滤）。对 1/2/3 三个核心 batch 可额外跑一遍 `/codex challenge` 作 second opinion。
- **结果汇总**：每个 batch 返回的 markdown finding 列表建议写到 `doc/reviews/2026-05-20-batch-N-findings.md`，最后做 cross-batch dedup + 优先级排序。

## 统一执行规范

1. **先读权威文档再读代码**：至少先看 `doc/architecture/HYBRID_ARCHITECTURE.en.md` 与 `doc/architecture/MAINTAINER_ARCHITECTURE.en.md`；涉及启动/FFI 再补 `test/ffi_audit/README.md`。
2. **先确认工作树状态**：建议先看 `git status --short` / `git diff --stat`，避免把用户未提交的实验性改动当成“既有行为”。
3. **可以也应该读测试**：测试不是金科玉律，但它们能快速暴露作者的意图、回归面和已知脆弱区。
4. **third_party 不是免责区**：`third_party/tim2tox`、`third_party/chat-uikit-flutter` 都是可维护边界内代码；不要写“因为是第三方所以只能绕过”。
5. **跨 batch 问题按根因归属**：例如 UI 症状由启动顺序破坏导致，应主记在 Batch 1，并在其他 batch 只留简短 handoff note，避免重复计数。
6. **finding 以行为风险为先**：优先抓竞态、状态泄漏、初始化/销毁顺序、持久化一致性、权限/协议边界、用户可见错乱；不要用“代码风格不统一”充数。
7. **文件清单是入口，不是上限**：如果调用链继续延伸到 `part` 文件、`lib/ui/home/`、`lib/ui/login/`、`third_party/tim2tox` 或关联测试，请继续跟进去。

## 严重度口径（建议）

- **critical**：数据损坏、账号/会话串线、不可恢复的历史丢失、明显安全边界失守、主流程完全不可用
- **high**：高概率功能错误、跨会话泄漏、重复/漏写历史、通话/通知状态机卡死、构建或发布流程实质失效
- **medium**：有条件触发但影响真实用户或维护者、错误恢复不完整、幂等性/资源释放缺口、测试/文档与实现严重漂移
- **low**：局部可见缺陷、可维护性风险、复杂度/结构问题，短期不一定直接造成故障

---

## 共用前言（每个 batch prompt 开头复用）

```
你正在为 toxee 做代码 review。toxee 是 Flutter chat 客户端，把 Tencent Cloud Chat UIKit
跑在 Tox P2P 网络上（不是 Tencent Cloud IM）。它依赖一个外部框架 Tim2Tox
（third_party/tim2tox，源 agentx-icu/tim2tox），通过两条路径把 UIKit 调用桥到 Tox：

1. **二进制替换路径**：main() 调用 setNativeLibraryName('tim2tox_ffi')，让 UIKit
   的 SDK 调用走 libtim2tox_ffi 而不是 dart_native_imsdk。
2. **Platform 路径**：Tim2ToxSdkPlatform 被注册为 TencentCloudChatSdkPlatform.instance，
   把 history、clearHistoryMessage、group/quit 回调、calling、polling、Bootstrap 等
   stateful 流量路由到 Dart 侧的 FfiChatService。

**核心不变量**：两条路径必须共存且互不重复写历史/触发同一回调。该不变量由
BinaryReplacementHistoryHook 强制；当前它在
SessionRuntimeCoordinator.ensureInitialized() 中与 Platform/runtime 原子安装，
而不是由 HomePage 单独安装。
启动顺序（不可随意变）：FfiChatService.init → login → updateSelfProfile →
SessionRuntimeCoordinator.ensureInitialized()（FakeUIKit.startWithFfi + 安装 Platform +
CallServiceManager.initialize + BinaryReplacementHistoryHook + badge runtime）→
TIMManager.initSDK → startPolling → HomePage 再做 UIKit listener/provider/plugin 注册。

权威文档：doc/architecture/HYBRID_ARCHITECTURE.en.md、
doc/architecture/MAINTAINER_ARCHITECTURE.en.md。
项目约束：flutter analyze 严格 lints（avoid_print、unawaited_futures、
use_build_context_synchronously、cancel_subscriptions、close_sinks 等）；
lib/ 下文件 >500 LOC 会被 tool/check_complexity.dart 警告。
工作目录：/Users/bin.gao/chat-uikit/toxee。
本仓库 user 是 fork owner，third_party/tim2tox 和 third_party/chat-uikit-flutter
都可直接改（不要把 finding 写成"它是第三方所以不能改"）。
```

---

## Batch 1 — 核心混合架构（域 A + 域 P）

**目标**：覆盖启动顺序与适配层这两层最容易破坏混合架构不变量的代码。

```
（粘贴共用前言）

## 本批 review 范围

启动编排与混合架构胶水层。重点是"启动顺序"和"两条路径之间的胶水"。

### 文件清单
- lib/main.dart
- lib/bootstrap/ 全部（app_bootstrap.dart, logging_bootstrap.dart, prefs_bootstrap.dart,
  app_runtime_bootstrap.dart, desktop_shell_bootstrap.dart, 等）
- lib/runtime/session_runtime_coordinator.dart
- lib/runtime/tim_sdk_initializer.dart
- lib/util/app_bootstrap_coordinator.dart
- lib/startup/ 全部（startup_session_use_case.dart, startup_step.dart, _StartupGate）
- lib/auth/login_use_case.dart
- lib/adapters/ 全部
- lib/sdk_fake/ 全部（fake_uikit_core.dart, fake_im.dart, fake_msg_provider.dart,
  fake_msg_provider_mapping.dart, fake_msg_provider_routing.dart, fake_managers.dart,
  fake_provider.dart, uikit_data_facade.dart 等）
- lib/ui/home_page.dart, lib/ui/home_page_bootstrap.dart, lib/ui/home_page_plugins.dart,
  lib/ui/home_page_persistence.dart, lib/ui/home/ 全部
- third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart（重点）

### 建议顺手核对测试
- test/runtime/session_runtime_coordinator_test.dart
- test/session_runtime_lifecycle_test.dart
- test/tim2tox_binary_replacement_hook_generation_test.dart
- test/ffi_audit/ 下各 surface 测试

## Review 重点

1. **启动顺序破坏**：是否有路径在 SessionRuntimeCoordinator 完成前调用 UIKit /
   TIMManager / FfiChatService 的 stateful API？是否有 unawaited 的 init future
   被后续步骤当成已完成？
2. **双路径协调**：BinaryReplacementHistoryHook 的去重逻辑（msgID + 内容窗口 2s）
   是否覆盖所有消息类型？standalone 安装 + 延迟 `updateSelfId()` 的窗口期是否会
   重复、漏写或误判 self message？m- 前缀过滤逻辑是否正确？generation counter
   X8 的实现是否真的防住跨会话泄漏？
3. **重初始化幂等性**：登出后 SessionRuntimeCoordinator.ensureInitialized()
   再次调用是否真的幂等？FakeUIKit / Platform / Hook 是否会有残留状态、流订阅、
   定时器、回调注册？
4. **Adapter 一致性**：5 个 adapter（Preferences/ConversationManager/EventBus/Logger/
   Bootstrap）的契约是否和 Tim2Tox 上游一致？是否有 silent fallback 屏蔽了错误？
5. **Lint 警示**：unawaited Future、未关闭的 StreamSubscription、close_sinks、
   use_build_context_synchronously 在该层尤其敏感（会泄漏跨会话）。
6. **logger 早期初始化**：runZonedGuarded、FlutterError.onError、
   PlatformDispatcher.instance.onError、_routePrintToLogger、stderr fallback 的
   完整性，是否能在 logger 自身 StackOverflow 时存活？

## 输出格式

每条 finding：
- **[严重度 critical/high/medium/low] 标题**
- 位置：file:line（或 line range）
- 现象：1-2 句
- 风险：为什么这是问题（结合不变量）
- 建议修法：1-3 句
- 置信度：high / medium / low

只报告 confidence ≥ medium 的问题。先严重后轻微。文末给一条"全局观察"段（≤150 字）。

## 超出范围

不要 review 消息收发逻辑、UI 设置项、通话、构建脚本。这些有专门 batch。
```

---

## Batch 2 — 消息域（域 D + E + F + G + H + I）

```
（粘贴共用前言）

## 本批 review 范围

消息收发、历史持久化、会话、媒体/文件、好友、群组——所有用户能直接感知的"chat
功能"。这是混合架构里最容易出现 binary/Platform 双写或漏写的区域。

### 文件清单
- lib/sdk_fake/ 中与消息/会话/好友/群相关的部分（fake_msg_provider.dart,
  fake_msg_provider_mapping.dart, fake_msg_provider_routing.dart,
  fake_msg_provider_file_progress.dart, fake_managers.dart, fake_provider.dart,
  fake_im.dart 等）
- third_party/tim2tox/dart/lib/utils/message_history_persistence.dart（重点）
- third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart（重点）
- lib/ui/add_friend_dialog.dart
- lib/ui/add_group_dialog.dart
- lib/ui/group/group_member_list_wrapper.dart
- lib/ui/contact/contact_builder_override.dart
- lib/ui/group/group_builder_override.dart
- lib/ui/search/custom_search.dart
- lib/util/prefs.dart 中与 friend/group/conversation/pinned/quitGroups 相关的部分

### 建议顺手核对测试
- test/tim2tox_history_cache_single_source_test.dart
- test/tim2tox_get_history_pagination_test.dart
- test/tim2tox_delete_messages_test.dart
- test/sdk_fake/*.dart、test/fake_conversation_manager_*、test/friend_asset_cleanup_test.dart

## Review 重点

1. **历史一致性**：appendHistory 的 200ms 防抖 + 去重 + 1000 条内存上限是否会丢消息？
   原子写 + .bak + fsync 在 crash 时能否保证不破坏文件？路径占位符
   ({{fileRecv}}/{{avatars}}/{{downloads}}/{{userDownloads}}) 在跨设备恢复时是否完备？
2. **去重边界**：内容匹配 2s 窗口在高频消息或重复内容时是否会误判？
   updateFilePathSafely 的 try/catch 是否覆盖所有真实磁盘错误？
3. **会话列表来源协调**：getConversationList 从 Tox friend list + Prefs.localFriends
   + ffi.knownGroups + Prefs.getQuitGroups() 合并，是否存在"看得见但删不掉"或
   "删掉了又冒出来"的边界？pending friend 过滤是否正确？
4. **未读计数**：基于 lastViewTimestamp 计算未读，时区/系统时间回拨/多设备时间漂移
   是否会让计数为负或永远不归零？
5. **群组类型**：Tox new-API（public/private group）与 legacy conference 路径
   是否完整分流？group file transfer 拒绝是否所有入口都覆盖？
6. **好友请求**：64/76 字符 Tox ID 校验、921 字 message 上限、30s pending buffer
   TTL、15s 冷启宽限——是否所有入口都走同一校验？
7. **资源清理**：好友删除时头像清理、会话删除时历史清空、退群时 quitGroups
   记录——是否有遗漏导致幽灵数据？
8. **流泄漏**：FakeChatMessageProvider 的 broadcast 流、文件 progress 流、
   头像 update 流——退出 chat 页时是否取消订阅？
9. **去重 vs Hook 协调**：FakeMsgProvider 与 BinaryReplacementHistoryHook 都在
   "首次落历史"路径上，能不能严格证明没有双写或漏写？

## 输出格式

同 Batch 1。额外注意：涉及 message_history_persistence.dart 的 finding 要
明确标注影响范围（仅 toxee？还是 Tim2Tox 上游？修复点在哪个 repo）。

## 超出范围

不要 review 启动/账户、通话、UI 设置、构建脚本。
```

---

## Batch 3 — 通话与通知（域 J + K）

```
（粘贴共用前言）

## 本批 review 范围

音视频通话生命周期、信令、ToxAV、通知/角标、wakelock/亮度 副作用。

### 文件清单
- lib/call/ 全部（含 call_service_manager.dart, call_state_notifier.dart,
  call_effects_listener.dart, call_overlay*.dart, in_call_view.dart,
  incoming_call_view.dart, outgoing_call_view.dart, call_floating_widget.dart,
  ringtone_player.dart, permission_helper.dart, call_quality_estimator.dart,
  call_codec_profile.dart, audio_handler.dart, video_handler.dart 等）
- lib/notifications/badge_service.dart
- lib/notifications/notification_message_listener.dart
- lib/notifications/notification_service.dart
- third_party/tim2tox/dart/lib/service/call_bridge_service.dart
- third_party/tim2tox/dart/lib/service/tuicallkit_adapter.dart
- third_party/tim2tox/dart/lib/service/toxav_service.dart（路径以代码为准）
- test/call_bridge_service_test.dart（用来理解期望行为）

### 建议顺手核对测试
- test/call_bridge_service_test.dart
- test/call_and_history_regression_test.dart
- test/call_*、test/call_effects_policy_test.dart

## Review 重点

1. **信令 / ToxAV 状态机一致性**：发起→响铃→接听→inCall→ended 各阶段的
   "信令侧状态"与"ToxAV 侧状态"在异常（对方挂、超时、网络丢失）下是否会卡死？
   8s reconnecting 窗口超时后是否真的会回收所有资源？
2. **资源生命周期**：AudioHandler/VideoHandler 的 startCapture/stopCapture
   是否成对？切麦/切摄像头的瞬态是否会泄漏 capture session？
   call_effects_listener 的 wakelock/亮度/后台播放在 idle 时是否一定释放？
3. **权限边界**：permission_helper 在 iOS/Android/Windows 行为差异；
   Android 13+ 通知权限只在第一次消息通知时请求是否合理；macOS/iOS
   由 NotificationService init 统一请求是否会卡启动？
4. **铃声**：合成 WAV 在蓝牙/扬声器切换、音量为 0、系统勿扰下行为；
   start/stop 是否在所有 reject/hangup/timeout 路径都正确？
5. **未接来电历史**：onCallRecordNeeded → _emitCallRecord 在所有终止路径
   都触发？endReason 在拒接/超时/取消/对方挂上是否区分正确？
6. **CallStateNotifier**：toggleMute/toggleVideo/toggleSpeaker 是仅 UI 状态
   还是真的影响底层？mute 是否真的不发音频帧？文档与实现一致吗？
7. **质量估计与码率自适应**：CallQualityEstimator 在 reconnecting 期间
   是否暂停更新？CodecProfile 3 档切换的滞回是否会抖动？
8. **通知**：Android inbox style 的 per-conversation 堆积（5 条上限）
   是否会丢失？点击通知冷启动跳会话的 deep-link 路径是否完整？
9. **角标**：BadgeService 200ms 防抖在登出/切账户时是否清零？
   订阅 FakeIM.topicUnread 是否取消？
10. **测试覆盖**：call_bridge_service_test.dart 覆盖的场景与代码实际分支
    的 gap。

## 输出格式

同 Batch 1。额外要求：对每条 finding 标注"信令侧 / ToxAV 侧 / UI 侧 / 副作用侧"
归属，方便修复定位。

## 超出范围

不要 review 消息/历史、账户、UI 设置（非通话）、构建脚本。
```

---

## Batch 4 — 账户与网络入口（域 B + C）

```
（粘贴共用前言）

## 本批 review 范围

账户生命周期（注册/登录/导入/导出/切换/删除）、密码加密、Bootstrap 节点策略、
LAN bootstrap、配对（pairing）。

### 文件清单
- lib/auth/login_use_case.dart
- lib/ui/login_page.dart
- lib/ui/login/login_page_controller.dart
- lib/ui/login_settings_page.dart
- lib/ui/register_page.dart
- lib/ui/profile_page.dart, lib/ui/profile/profile_avatar_picker.dart
- lib/util/account_service.dart
- lib/util/account_switcher.dart
- lib/util/account_export_service.dart 和 lib/util/account_export/ 子目录
- lib/util/prefs.dart 中与 account/password/pbkdf2/bootstrap 相关部分
- lib/util/bootstrap_nodes.dart 等
- lib/util/lan_bootstrap_service.dart
- lib/ui/settings/bootstrap_settings_section.dart
- lib/ui/settings/bootstrap_nodes_page.dart
- lib/ui/settings/account 相关 section
- lib/ui/pairing/ 全部
- lib/models/account_summary.dart

### 建议顺手核对测试
- test/auth/login_use_case_test.dart
- test/account_export/account_export_roundtrip_test.dart
- test/account_reconciliation_test.dart
- test/restore_from_tox_test.dart、test/pairing/*.dart

## Review 重点

1. **密码加密**：PBKDF2-SHA256 150k 迭代是否当前推荐？salt 长度、derived key
   长度、存储位置、verify 时的恒定时比较——是否有时序攻击面？密码强度策略？
2. **账户删除**：deleteAccountCompletely 与 deleteAccountWithoutService 的
   "差不多但又不一样"逻辑——文件、目录、Prefs key、密码盐、UIKit 失败缓存
   是否全部覆盖？登录页删除走 without-service 版本是否会留残留？
3. **账户切换**：teardownCurrentSession → initializeServiceForAccount 切换中
   失败的回滚？切换中崩溃后的恢复？lastLoginTime 在切换失败时仍更新吗？
4. **账户导出/导入**：加密档案的密钥派生、文件格式版本号、跨版本兼容、
   PasswordRequiredException 的传播路径。
5. **Tox ID 处理**：64 vs 76 字符（含 checksum）的统一校验入口；
   normalize 是否一致；展示截断是否会被混淆攻击（同前缀 ID）？
6. **Bootstrap 模式**：移动端强制 'lan'→'auto' 的转换在所有入口都做了吗？
   设置变更后是否需要重连？_kPreLanBootstrapNode 保存/恢复在异常路径
   是否会"忘记"恢复？
7. **自动节点获取**：BootstrapNodesService.fetchNodes 失败时是否非阻塞？
   远程节点服务被劫持/返回恶意节点的风险面？签名/校验？
8. **LAN bootstrap**：仅桌面，UDP 广播的安全边界（绑定接口、信任假设）；
   probe/扫描在多网卡环境表现。
9. **配对**：QR + SAS 6 位 + .tox blob 的协议——SAS 短码暴力难度、
   MITM 防护、传输信道、blob 加密；客户端/主机超时清理。
10. **profile 编辑**：updateSelfProfile 同步 FfiChatService 与 Prefs 的顺序，
    部分失败下是否会不一致？头像文件命名/路径迁移。

## 输出格式

同 Batch 1。涉及密码学/网络协议的 finding 注明威胁模型假设
（本地攻击者 / 网络中间人 / 服务端不可信）。

## 超出范围

不要 review 消息/通话/UI 主题/构建脚本。
```

---

## Batch 5 — UI、平台壳、插件、扩展（域 L + M + N + O）

```
（粘贴共用前言）

## 本批 review 范围

UI 框架、主页骨架、设置页、主题/语言、桌面端壳、托盘、插件注册（贴纸/翻译/
语音转文字）、IRC 应用接入。

### 文件清单
- lib/ui/home_page.dart, lib/ui/home_page_bootstrap.dart,
  lib/ui/home_page_plugins.dart, lib/ui/home_page_persistence.dart
- lib/ui/home/ 全部
- lib/ui/settings/ 全部
- lib/ui/search/custom_search.dart
- lib/ui/profile_page.dart, lib/ui/profile/profile_avatar_picker.dart（UI 角度，非账户角度）
- lib/ui/startup_loading_screen.dart, lib/ui/upgrade_required_screen.dart
- lib/util/theme_controller.dart 或类似 AppTheme
- lib/util/locale_controller.dart 或类似 AppLocale
- lib/util/responsive_layout.dart
- lib/util/app_theme_config.dart, lib/util/app_spacing.dart
- lib/util/app_tray.dart
- lib/bootstrap/desktop_shell_bootstrap.dart
- lib/i18n/, lib/l10n/ 全部
- lib/ui/applications/ 全部
- lib/ui/contact/contact_builder_override.dart
- lib/ui/group/group_builder_override.dart

### 建议顺手核对测试
- test/first_run_wizard_test.dart
- test/widget_test.dart
- test/prefs_cross_platform_polish_test.dart
- test/user_profile_call_actions_test.dart

## Review 重点

1. **响应式布局**：desktop/tablet/phone 三档切换的断点；旋转屏 / 窗口拖动
   resize 实时表现；master-detail 在 phone 上的导航回退。
2. **主题/语言切换**：AppTheme.set 同步 TencentCloudChat.controller.setBrightnessMode
   的顺序与失败处理；zh_Hans/Hant scriptCode 精确匹配在所有入口（包括启动时
   解析系统 locale）是否一致；切换后已渲染 widget 是否能正确重建。
3. **设置项落地**：通知音、自动接受好友/群邀请、下载目录、自动下载阈值——
   每个开关的"立即生效路径"是否真的到了底层 service，还是只更新 Prefs？
4. **WindowManager**：保存/恢复窗口位置在多屏断开、坐标越界、
   最小化时关闭的边界；onWindowClose 的 prevent close 行为是否正确。
5. **托盘**：未读数嵌入图标在 Windows/Linux/macOS 的差异；icon byte 生成
   开销与刷新频率；点击/右键菜单回调。
6. **插件注册时机**：home_page_plugins 的"同步/异步双路注册"——selfId 未就绪
   时的 fallback 是否会注册两次？退出账户时插件是否注销？
7. **localizations**：5 种语言资源完整度、占位符一致性、RTL（阿拉伯文）布局。
8. **自定义搜索**：incremental cache 在大数据量下的内存上限、关键词高亮的
   正确性、跨会话搜索性能。
9. **复杂度**：home_page.dart、settings_page_build.dart 是否接近或超过 500 LOC？
   如果超，建议拆分方向。
10. **IRC 应用页**：当前侧栏 disabled——是否有 dead code、过时引用、
    遗留 stream 订阅？

## 输出格式

同 Batch 1。UI 类 finding 鼓励附"可见症状（用户怎么看到 bug）"一句话。

## 超出范围

不要 review 消息/通话/账户/Bootstrap 节点策略/构建脚本。
```

---

## Batch 6 — 工程基础设施（域 Q）

```
（粘贴共用前言）

## 本批 review 范围

构建、工具链、CI、补丁机制、git hooks、复杂度检查、Release 发布。
此 batch 专注"工程能力"层，与 lib/ 源码不变量无关。

### 文件清单
- tool/ 全部（bootstrap_deps.dart, check_complexity.dart, install_git_hooks.sh,
  verify_submodule_remote.sh, refresh_sdk_patch.sh, verify_bootstrap_local.sh,
  test_bootstrap_smoke.sh, test_ci_packaging.sh）
- tool/ci/ 全部（build_tim2tox.sh, package_artifacts.sh, common.sh,
  publish_release.sh, prepare_ios_signing.sh, apply_sdk_patches.dart 等）
- tool/git-hooks/pre-push
- .github/workflows/ 全部（analyze.yml, build-packages.yml, auto_tests.yml,
  auto_tests_nightly.yml, bootstrap_fresh.yml）
- build_all.sh, run_toxee.sh, run_toxee_ios.sh, run_toxee_ios_device.sh,
  run_toxee_android.sh
- tool/vendor_state.json
- pubspec.yaml, pubspec_overrides.yaml（注意它是 bootstrap 生成的）
- analysis_options.yaml

### 建议顺手核对测试
- test/repo_hygiene_test.dart
- tool/test_bootstrap_smoke.sh
- tool/test_ci_packaging.sh

## Review 重点

1. **Bootstrap 流程完整性**：bootstrap_deps.dart 的步骤顺序在某一步失败时
   能否安全 resume？vendor_state.json + patches sha256 校验能否检测出
   "补丁文件被本地修改但 lock 未更新"？--force vs --offline-check-only
   语义清晰吗？
2. **pubspec_overrides.yaml 写入**：mtime guard 是否真的避免无谓 churn？
   并发运行 bootstrap 的安全性？
3. **Pre-push hook**：verify_submodule_remote.sh 在 bash 3.2 兼容的前提下，
   ls-remote / fetch 的失败模式覆盖（私有 repo、SSH key 不可用、
   网络超时）；是否容易绕过？
4. **补丁维护**：refresh_sdk_patch.sh 仅支持单补丁系列——多补丁场景下
   的 fallback / 报错；apply_sdk_patches.dart 的 sha 校验、apply 顺序、
   失败回滚。
5. **CI 构建矩阵**：build-packages.yml 的 6 目标 × 多架构是否真的能并行
   出包？失败一个 job 不阻塞其他（fail-fast: false）+ publish job
   依赖所有平台——单点失败下 release 行为？最近几次 round 7/8 的 patch
   是否说明 Linux ARM64 / Windows ARM64 仍不稳定？
6. **原生构建**：build_tim2tox.sh 对每个平台的 NDK / Xcode / MSVC / vcpkg
   路径假设；TIM2TOX_ANDROID_ABIS、TIM2TOX_WINDOWS_ARCH 等 override
   的文档化程度；libsodium bundling 的版本固定与校验。
7. **打包**：package_artifacts.sh 的 DEB/RPM 元数据、MSI 签名、PKG
   product id、APK/AAB 签名、IPA resign 流程；RPATH 修正（patchelf）的
   完整性。
8. **复杂度门禁**：check_complexity.dart 当前 warn-only，CLAUDE.md 说
   "长期方向是 enforcement"——评估现在 lib/ 已有多少 >500 LOC 文件，
   切到 enforcement 是否可行。
9. **Lint 配置**：analysis_options.yaml 与 CI 命令 `flutter analyze lib tool
   --no-fatal-warnings --no-fatal-infos` 之间，是否存在"本地 pass 但 CI fail"
   或反之的可能？
10. **自动测试 Tier**：auto_tests.yml (Tier 2 PR-blocking) 的 phase 选择
    （1-8,10,12-14）覆盖率与 nightly Tier 3 的差异；30min 超时是否合理；
    虚拟时钟 vs 墙钟的失败模式区分。
11. **iOS 签名 / Release 发布**：secrets 处理、keychain 清理、tag 解析、
    prerelease flag 的端到端可用性。

## 输出格式

同 Batch 1。Finding 额外标注"CI-only / Developer-only / User-facing"
便于优先级判断。

## 超出范围

不要 review lib/ 源码任何业务逻辑。
```
