# toxee 现有布局与交互审查

日期：2026-10-01。本文件保留实施前审查，行号对应当时版本；当前修复与验证状态见[实施记录](./implementation.zh-CN.md)。状态：候选优化方案，未修改应用代码。与[四套风格设计](./README.zh-CN.md)配套；布局与交互改进应由所有风格共用，经典蓝也适用。

结论：需要优化。优先解决好友申请失败后的列表状态，再改善触摸范围、平板／窄桌面的空间分配、输入区、设置层级与必要文字的可读性。外观切换的保存失败处理应随多风格一起完善。

## 范围与证据

- **当前代码确认**：阅读 Flutter 页面、响应式规则、UIKit 本地分支、SDK 适配及相关测试。文件链接指向本次审查时的实际行号。
- **控件测试复现**：运行既有详情接受按钮测试，真实处理函数收到 SDK 未初始化的 `-1` 后发出失效提示并移除本地申请。此为测试进程中的控件与 SDK 失败路径，未处理用户的真实申请。
- **运行界面观察**：只读查看当前运行的 macOS Toxee 登录页。可见账号列表内部滚动、外层页面滚动，以及「从 .tox 文件恢复」「导入账号」「注册新账号」三个入口。未确认运行包对应的提交版本，因此不将运行包等同于当前源码构建。
- **历史界面参考**：[桌面聊天](../../product/assets/zh/desktop/c2c.png)、[手机聊天](../../product/assets/zh/ios/c2c.png)、[iPad 聊天](../../product/assets/zh/ipad/c2c.png)、[桌面设置](../../product/assets/zh/desktop/settings.png)、[手机设置](../../product/assets/zh/ios/settings.png)、[手机好友申请](../../product/assets/zh/ios/new_application.png)。截图用于理解信息层级，不能单独证明当前版本有缺陷。
- 未登录用户账号、处理真实申请、发送消息或更改设置。聊天、联系人及设置的端到端行为仍需在隔离演示账号中验证。
- P1 表示影响操作结果与重试的交互问题；P2 表示应随本次界面优化处理；P3 表示需要进一步验证的体验建议。

## 现状与优化后（建议）

| 编号／优先级 | 当前问题与证据等级 | 优化后（建议） | 完成标准 |
| --- | --- | --- | --- |
| U01 · P1 | 部分好友申请入口把一般失败当成失效，并从当前列表移除；代码确认，详情接受失败在控件测试中复现 | 成功后更新状态；可重试失败保留申请；处理时禁用重复操作；明确失效才提供清理 | 接受／拒绝的按钮、菜单与详情路径语义一致；失败仍能就地重试 |
| U02 · P2 | 好友申请按钮的检测区域在外层 padding 内，标签还可能缩小；代码结构确认，实际范围待控件测量 | 整个按钮可点击，触摸区域至少 44 × 44；窄屏把操作移到第二行，不缩小用户设置的字号 | 点文字、背景和边缘均触发一次操作；大字号下标签可读 |
| U03 · P2 | 平板／桌面导航固定 200，分栏会话列表使用 330，挤压中等宽度聊天区；代码确认，体验风险 | 按可用宽度选择 72 的紧凑导航及 280–300 的会话列表，保证聊天区容量 | 800–1100 宽度、1–2 倍字号可用；宽窄切换保留会话、草稿与滚动 |
| U04 · P2 | 桌面输入框最少行数等于最大行数，默认固定五行；代码确认 | 从 1–2 行自然增长到 5–6 行；超过上限内部滚动；短窗口减少初始占高 | 短消息留出更多历史；长消息、引用、附件和中文输入不被截断 |
| U05 · P2 | 桌面账号信息与本地账号列表合在大卡片，外观位于其后；代码及历史截图确认 | 设置使用分类导航或清晰独立分组；当前账号摘要与账号管理分离；外观直接可达 | 增加账号不会把外观入口不断推远；手机沿用既有分类入口 |
| U06 · P2 | 会话摘要／时间使用较淡颜色；代码及色值计算确认 | 必要次级文字使用可读颜色，建议元数据 12–13；选中状态同时有形状提示 | 五种风格浅深模式均检查实际前景／背景；系统文字缩放正常 |
| U07 · P2 | 明暗选择先更新全局状态再保存，保存结果缺少处理；代码确认，失败场景待注入验证 | 多风格页使用局部预览与显式应用；保存成功发布全局状态，失败保留待选值并反馈 | 保存异常或返回 false 不伪装成功；重启恢复；连续操作有一致结果 |
| U08 · P3 | 登录恢复与导入入口含义重叠，多个滚动区域增加查找成本；运行观察＋代码确认，需用户验证 | 为 .tox 恢复与 .tox／.zip 导入补充差异说明；保留两个后端流程；验证账号列表可发现性 | 新用户能选对入口；多账号、短屏和大字号能找到目标账号及注册入口 |

## U01：失败后保留好友申请与重试入口

在[列表按钮处理](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_contact/lib/widgets/tencent_cloud_chat_contact_application_list.dart:400)中，接受请求在失败提示后仍执行第 425–427 行的本地删除；拒绝请求的失败分支也在第 452–453 行删除。另一个[菜单拒绝入口](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_contact/lib/widgets/tencent_cloud_chat_contact_application_list.dart:130)在第 154–155 行无条件删除。

[详情接受入口](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_contact/lib/widgets/tencent_cloud_chat_contact_application_info.dart:295)在失败分支第 320–322 行删除；[详情拒绝入口](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_contact/lib/widgets/tencent_cloud_chat_contact_application_info.dart:326)在失败分支第 349–350 行删除。现有[详情按钮测试](../../../test/ui/contact/contact_application_detail_accept_real_ui_test.dart:95)甚至把 SDK 未初始化的失败结果移除申请写成了预期。该断言只能证明按钮连接现行处理函数，不能证明失败后的用户体验正确。修复时应把一般失败保留申请作为回归约束，并分别验证成功与真正失效结果。

[菜单接受入口](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_contact/lib/widgets/tencent_cloud_chat_contact_application_list.dart:96)已经只在成功时删除，这部分应保留，并将相同原则应用到其他路径。[本地删除实现](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_common/lib/data/contact/tencent_cloud_chat_contact_data.dart:91)会移除申请并更新未读数。因此目前风险是**当前列表失去重试入口及未读提示**，并非已经证明服务器上的申请永久丢失；后续刷新可能重新出现。

[SDK 包装](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_common/lib/chat_sdk/components/tencent_cloud_chat_contact_sdk.dart:113)会把一般错误映射为失败结果；[原生适配异常路径](../../../third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:9068)也可返回 `-1`。所有非成功结果并不都能推断成「好友申请失效」。当前处理函数也没有进行中状态或异常收尾。

建议将接受／拒绝统一为「待处理 → 处理中 → 已接受／已拒绝」，失败返回待处理并显示可重试错误。只有可靠的失效结果才显示「申请已失效」，清理由用户明确执行或按经过验证的产品规则处理。详情页、列表按钮与菜单都需检查相同约束；成功后的行移除／已处理提示可以沿用当前产品规则。

## U02：按钮外观与实际点击范围一致

[接受按钮结构](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_contact/lib/widgets/tencent_cloud_chat_contact_application_list.dart:481)是 `Container(padding: …, child: GestureDetector(child: FittedBox(Text)))`，拒绝按钮同样如此。手势检测在带内边距的容器内部，外层背景与内边距没有同一个按钮手势区域。父行还把操作区限制在半行宽，使用 `FittedBox.scaleDown` 避免溢出，会削弱大字号的目的。

[当前接入](../../../lib/ui/home_page_bootstrap.dart:113)只替换申请内容；[按钮 builder 的默认路径](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_contact/lib/tencent_cloud_chat_contact_builders.dart:353)仍使用这一组件。建议采用完整的语义按钮与明确最小高度，保持键盘焦点和禁用状态；必要时申请内容一行、操作一行。实际边缘命中与控件语义应通过 widget 测试确认，本文未声称已在真机复现漏点。

另有[设置账号列表复制按钮](../../../lib/ui/settings/settings_page_build.dart:290)显式使用 32 × 32 的最小约束；建议在触摸布局扩大到至少 44 × 44，保留紧凑的图标视觉尺寸。是否实际达到最小尺寸应测量布局结果，而不是仅凭约束值推断。

## U03：按内容容量分配桌面和平板空间

目前[导航宽度](../../../lib/util/responsive_layout.dart:246)在桌面及平板为 200，只有部分横屏手机使用 72；[主从分栏门槛](../../../lib/util/responsive_layout.dart:288)是窗口宽度 800；[会话列表](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_conversation/lib/desktop/tencent_cloud_chat_conversation_desktop_mode.dart:162)是 `getWidth(330)`。

以 834 宽布局为例，扣除 200 导航、330 列表和 1 分隔后，聊天约 303。若使用 72 导航和 280 列表，则聊天约 481。[当前 UIKit 宽度适配](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_common/lib/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart:105)原样返回传入值。这是容量计算；实际窗口可用宽度、内部 padding 与控件表现仍应测量，不能据此声称已有溢出。

建议试验以下规则，而不是仅按操作系统决定密度：

| 可用宽度 | 导航／会话区建议 | 聊天容量与行为 |
| --- | --- | --- |
| 小于 720 | 保持现有底部四项导航；聊天进入独立页面 | 保留返回、附件、发送、键盘与安全区 |
| 720–799 | 紧凑导航；维持单内容区 | 会话到聊天的切换保留选择与草稿 |
| 800–1099 | 72 紧凑导航；会话列表约 280–300 | 聊天尽量不少于 360；字号／内容使容量不足时退回单内容区 |
| 至少 1100 | 标签导航约 160–200；列表约 300–330 | 保持三栏，避免无意义地拉宽消息行 |

这些数字是候选值，需对 800、834、1024、1100 及大字号实际测量后确定。紧凑导航保留 tooltip、语义标签、未读数字与选中指示。应继续使用[现有宽窄过渡逻辑](../../../lib/ui/home_page_master_detail.dart:9)，不因布局变化重新创建会话、账号或通话实例。已有「所有平板 200」测试是现行产品规则，未来调整时应同步改为验证新的容量规则，不能当成测试已证明体验最优。

## U04：输入区随内容增长

[桌面输入框](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_desktop.dart:1061)把 `minLines` 和 `maxLines` 设为同一值；[默认配置](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_common/lib/components/component_config/tencent_cloud_chat_message_config.dart:178)是五行。固定高度不是功能故障，但对短消息和短窗口会占用更多聊天历史空间。

建议默认 1–2 行，增长到 5–6 行，再内部滚动。快捷发送、换行、中文输入法候选确认及附件／引用等仍遵循现有行为；验收需确保 Enter 不在 IME composing 时误发。消息输入焦点可以通过温和的表面或描边变化识别，同时保持四套风格的几何差异。输入控件、草稿、选择范围与焦点都应保持连续。

## U05：缩短设置中的查找路径

桌面[账号管理](../../../lib/ui/settings/settings_page_build.dart:217)嵌在账号信息卡内；[全局设置](../../../lib/ui/settings/settings_page_build.dart:455)排在整张卡片之后。账号列表已有预览数量和展开限制，因此问题是层级与入口距离，不能声称所有账号始终完整展开。

建议桌面设置页内提供「外观、通用、后台行为、账号信息、账号管理、Bootstrap」分类，或至少把它们拆成独立、可定位的分组。账号头像／名称／在线状态作为简洁摘要；完整 Tox ID、二维码及导出等进入账号信息。手机已使用[分类入口](../../../lib/ui/settings/settings_page_mobile_index.dart:1)和[带返回的可滚动子页](../../../lib/ui/settings/settings_page_mobile_widgets.dart:4)，应沿用这些已有优势。

导出／设密码与退出／删除在视觉上分组，删除继续使用[现有确认](../../../lib/ui/settings/settings_page_widgets.dart:191)。现有按钮已有宽屏 `Wrap` 和窄屏两列布局，本次没有证据表明它们必然横向溢出。

## U06：提高必要次级信息可读性

[颜色定义](../../../lib/util/design_tokens.dart:36)和[会话颜色映射](../../../lib/util/app_theme_config.dart:249)显示，摘要／时间使用 tertiary 色；[摘要渲染](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_conversation/lib/widgets/tencent_cloud_chat_conversation_item.dart:667)和[时间渲染](../../../third_party/chat-uikit-flutter/tencent_cloud_chat_conversation/lib/widgets/tencent_cloud_chat_conversation_item.dart:979)显式使用这些颜色。

字号／颜色核对纠正：底部导航的 `selectedFontSize`／`unselectedFontSize` 参数虽然为 11，但传入的 `labelSmall` [实际定义为 12](../../../lib/ui/app_theme_data.dart:153)。当前 Flutter 的 `BottomNavigationBar` 优先使用标签样式中的字号与颜色，因此不能将导航标签误报为已渲染 11 或必然采用 tertiary 色。`unselectedItemColor` 明确用于图标，标签最终颜色需按有效样式确认。建议统一参数与文字 token 以消除混淆，维持当前 12 的基线。

根据当前不透明色值计算标准相对亮度比，普通背景上的对比为：

| 前景／背景 | 用途 | 对比 |
| --- | --- | --- |
| `#8F959E` / `#FFFFFF` | 浅色 tertiary／普通会话列表 | 3.017:1 |
| `#6B7178` / `#1A1A1A` | 深色 tertiary／普通会话列表 | 3.529:1 |
| `#646A73` / `#FFFFFF` | 现有浅色 secondary 候选 | 5.453:1 |
| `#9AA0A6` / `#1A1A1A` | 现有深色 secondary 候选 | 6.591:1 |

前两项低于本设计为必要普通文字设置的 4.5:1 目标。可优先使用 secondary 层级，再为选中、置顶、悬停等实际表面单独检查。装饰分隔线与禁用内容不一概加深。这里只计算明确色值组合，不是屏幕截图像素或整个应用的可访问性认证。新风格的[对比记录](./contrast-checks.json)不包含现有经典蓝，本项应补足经典蓝的必要文字检查。

## U07：外观预览与持久化结果一致

[AppTheme.set](../../../lib/util/theme_controller.dart:26)先发布 `mode.value` 再保存；[偏好写入](../../../lib/util/prefs.dart:521)未检查 `setString` 的布尔结果；[设置回调](../../../lib/ui/settings/global_settings_section.dart:265)使用 `unawaited`，没有提供进行中或失败反馈。

当前[应用监听](../../../lib/main.dart:255)已经同步 Material 与 UIKit 明暗，不能把本问题描述为必然出现「一半界面变色」。确认的风险是：保存失败时当前外观已变，用户缺少保存失败与重试反馈，重启恢复可能与当前显示不同。该失败场景尚未通过故障注入复现。

多风格页按[既定方案](./README.zh-CN.md)采用局部预览 → 应用 → 保存 → 发布全局状态。保持待选值和当前值分离，保存进行中防止重复提交；失败保留当前外观及待选值，显示可重试提示。若经典蓝现有即时明暗入口继续保留，则也应明确回退或「本次未保存」语义，统一底层保存结果处理。保存成功后继续沿用已有主题同步机制，避免重建业务状态。

## U08：登录入口文案和多账号滚动

运行页同时展示恢复、导入、注册。代码中的 [.tox 恢复](../../../lib/ui/login/login_restore_from_tox.dart:11)有专门的格式过滤、失败原因和成功后预填信息；[导入](../../../lib/ui/login/login_page_controller.dart:175)支持 .tox／.zip。两个流程并非完全重复，不建议直接合并后端或删除恢复入口。

建议补充短说明，例如「从 Tox 配置恢复（.tox）」与「导入账号备份（.tox / .zip）」，并说明恢复后继续登录、导入后如何选择账号。实际文案需对应各自成功行为测试。两条已有流程及账号导入安全约束保持不变。

[账号列表](../../../lib/ui/login_page.dart:889)按视口高度分配 38% 并限制在 220–420，内部列表与外层页面都可以滚动。双滚动是当前观察，不足以判定为缺陷；账号很多时也有控制页面高度的价值。建议优先验证滚轮／触控滚动、选中账号可见性、大字号卡片高度及底部入口可达，再决定采用整页滚动或显式「查看全部账号」。

## 已有机制应保留

- 手机四项底部导航、单聊／设置子页的返回与安全区，避免把三栏桌面硬套到手机。
- 搜索已有桌面列表输入框接入全局搜索，并有键盘入口；不将其误报为「桌面没有可见搜索」。现有自定义搜索有防抖、加载、错误和空结果状态。
- 菜单接受申请已有成功才删除的修复；完整 Tox ID 的复制、二维码及账号删除确认已有实现。
- 明暗已监听系统与应用状态，Material／UIKit 同步机制应复用。
- 现有宽窄切换、通话浮层、长用户名／状态文字与窄消息选择栏测试，继续作为回归保护。

## 本轮自检与后续验收

本轮已执行：

```text
flutter test --no-pub test/util/responsive_layout_device_tiers_test.dart test/util/responsive_layout_desktop_classification_test.dart test/ui/layout_overflow_regression_test.dart --reporter expanded
```

结果：**36 项通过，退出码 0**。覆盖设备／导航分类与分栏门槛，以及横屏、大字号、通话覆盖层、窄 dock、长状态与用户名、消息选择栏等已有回归场景。

另外执行 `flutter test --no-pub test/theme_mode_persistence_test.dart --reporter expanded`，**10 项通过，退出码 0**，覆盖正常保存、无效历史值、冷启动恢复与连续成功保存。这些测试不覆盖好友申请一般失败或外观保存失败。

随后执行 `flutter test --no-pub test/ui/contact/contact_application_detail_accept_real_ui_test.dart --reporter expanded`，**3 项通过，退出码 0**。其中第一个用真实控件点击触发生产处理函数，日志明确显示 `eventCode: -1` 后申请总数从 1 变为 0，确认 U01 的详情接受失败路径。该测试现有断言把移除当成通过条件，因此测试通过不意味着交互正确；修复时必须调整预期。

合计 **49 项现有测试通过**。本轮没有新增测试，也没有修改应用代码；U07 保存失败仍需实施阶段的故障注入验证。

实施阶段建议分为三批：

1. **行为与可用性**：U01、U02、U06。用假的 SDK 返回一般失败／失效／异常，验证保留申请、重试、防重复点击和所有入口一致；测量实际点击区域与语义按钮；检查实际表面上的对比。
2. **共用布局**：U03、U04、U05。验证 320／390／720／800／834／1024／1100／1440 宽度、短窗口、1／1.5／2 倍字号；桌面 resize、手机键盘、平板横竖屏都保留会话状态。
3. **风格与发现性**：U07、U08。五种风格 × 浅／深色、系统明暗变化、保存 false／异常、连续点击、重启恢复、离开未应用，以及多账号滚动和导入文案。

风格概念图维持视觉比较用途；新的容量规则、按钮命中与故障恢复须在真实 Flutter 控件中验收，不能只在生成图片中表现出来。Claude Opus 只读方案评审与文档核验结果记录在 [review.md](./review.md)。
