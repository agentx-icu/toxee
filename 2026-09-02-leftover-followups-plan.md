# 遗留项修复计划 — 2026-09-02

审计基线：toxee master `4ee9a3d`（PR #91 已合），open GitHub issue = 0，CI 全绿，
工作树干净。本计划覆盖审计出的全部遗留项，按"真功能缺口 → 记录在案的 follow-up →
代码内 TODO"排序。

约定：每一项都给出 **现状证据（file:line）→ 根因/缺口 → 方案 → 移动端影响 →
验收门 → 风险**。凡是"有意保留的限制"（iPad-only sweep、PR #64 的截图差异）不在
本计划内，且明确不应被后续 session 当作回归重新"发现"。

---

## L1 —— 群聊已读回执对等（GROUP receipt parity）【唯一的真功能缺口】

### 现状证据

- 群回执**已经在跑**：`_sendReceipt` 的 group 分支走 group ACTION 控制线，body 是
  legacy 4-key schema（`third_party/tim2tox/dart/lib/service/ffi_chat_service.dart:7896-7918`）。
- 但**关联不上**：群消息入站时接收端自铸 msgID
  —— `'${timestamp}_${sequence}_${from}_$gid'`（`ffi_chat_service.dart:6116-6118`），
  自动 received 回执回显的就是这个**接收端本地 id**（`:6163`）。
- 发送端 `_handleReceipt` 用回执里的 msgID 做 key 记 tally
  （`_messageReceivers` / `_messageReaders`，`ffi_chat_service.dart:7969-7981`），
  历史匹配只比 `msg.msgID == msgID`（`:8006`），**不看 altMsgIds**。
- UI 侧 `getMessageReadReceipts` 用 UIKit 自己那条消息的 msgID 去查
  `getMessageReaders(msgID)`（`third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:8114-8159`）
  —— 与接收端铸的 key 永远不相等 ⇒ 作者侧 readCount 恒为 0。
- 这一点在落地当天就被写进了 commit：tim2tox `325e868` 的
  "KNOWN LIMITATION"，并已指出修法方向：把 **`Tox_Group_Message_Id`
  （toxcore 两端本来就共享）串到事件行里，进 `altMsgIds`**。

### 为什么"需要 version-safe 的群控制帧传输"

回执 body 的校验是**精确键集**。C2C 路由要求恰好 4 键
`{'type','msgID','receiptType','sender'}`（`ffi_chat_service.dart:6430-6447`，
`_hasExactKeys`）；群 ACTION 路由走
`BinaryReplacementHistoryHook._decodeInternalProtocolCustomData`，允许 4 或 5 键
（多一个可选 `groupID`，`third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart:466-480`）。
**两条路都不接受任何计划外的新键。**

但两条路"不接受"的后果并不相同，这一点必须写清楚：C2C 是判 malformed 后**丢弃**
（`ffi_chat_service.dart:6206-6214`），而群 ACTION 校验失败会**fall through 去渲染**
（详见下面 I1）。所以新关联信息只能塞进**自由格式的 `msgID` 字段**，用前缀区分
—— 这正是 C2C 已验证过的手法（`bind:<sha256(text)>`，`ffi_chat_service.dart:7920-7936`）
—— 且群侧还要额外扛住"老 peer 认不出这个 msgID"的渲染风险。

### 关键事实核查：`Tox_Group_Message_Id` 确实是全组共享的

不是"每端各自生成"。`gc_send_message` 由**发送方**铸一个
`pseudo_msg_id = random_u32(chat->rng)`，**打包进广播报文本身**
（`third_party/tim2tox/third_party/c-toxcore/toxcore/group_chats.c:4772-4818`），
接收方从 PUBLIC group broadcast 报文里 `net_unpack_u32(data, &pseudo_msg_id)`
解出同一个值再交给 `c->message(...)`（同文件 `:4844-4849`）。
C++ 侧两端都已经拿在手里：

- 收：`ToxManager::onGroupMessageGroup(..., Tox_Group_Message_Id message_id, ...)`
  （`third_party/tim2tox/source/ToxManager.cpp:1790`）→
  `V2TIMManagerImpl::HandleGroupMessageGroup`（`source/V2TIMManagerImpl.cpp:502-503`）。
- 发：`SendGroupTextMessage` 已经捕获了 out 参数 `message_id`
  （`source/V2TIMManagerImpl.cpp:2471, 2538-2539`）。

但**发送侧 pseudo id 今天并没有 Dart 可见性**，这不是简单 plumbing，而是实打实的
FFI/ABI 工作：`tim2tox_ffi_send_group_text` 丢掉 `message_id`，只把 native bool
折成 `1/0` 返回（`third_party/tim2tox/ffi/tim2tox_ffi.cpp:2107-2119`），Dart 绑定也只是
`int Function(Pointer<Utf8>, Pointer<Utf8>)`
（`third_party/tim2tox/dart/lib/ffi/tim2tox_ffi.dart:647-651`）。
**缺的是从 C++ 把它交到 Dart**：轮询事件行今天是位置式的
`gtext:<groupID>|<sender>:<text>` / `gaction:<group>|<sender>:<body>`
（`ffi_chat_service.dart:3000, 6241`），没有 id 段。

### 路由矩阵（L1 范围）

| 路由 | 现状 | L1 范围 |
|---|---|---|
| 群普通文本 | native receive callback 有 `message_id`（`source/V2TIMManagerImpl.cpp:4761-4764`），但 simple listener 拼 `gtext:` 行时忽略 `msgID` 参数（`third_party/tim2tox/ffi/tim2tox_ffi.cpp:398-404`） | **in scope** |
| 群 ACTION 文本 | ACTION branch 丢掉 `message_id`，调用 `OnRecvGroupTextMessage("", ...)`（`source/V2TIMManagerImpl.cpp:4978-4981, 5317-5318`），simple listener 同样忽略 `msgID` | **in scope** |
| 群 CUSTOM packet | 走 `tox_group_send_custom_packet`，没有 `Tox_Group_Message_Id`（`source/V2TIMManagerImpl.cpp:2718-2758`） | **out of scope** |
| 群文件 | 明确 unsupported（`ffi_chat_service.dart:8371-8375`） | **out of scope** |
| legacy conference | 不走本计划的 group message id 线 | **out of scope** |

没有 pseudo id 的路由不做 lossy fallback；它们按上表直接划出 L1。

### 方案（先 I1 实证，再做 pseudo-id 关联）

**I1 — 先验证今天群回执是否已经污染历史（P1 首项）**

群 ACTION control 只有在 referenced `msgID` 已存在于接收端 history 或
`altMsgIds` 时才会被消费（`third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart:452-457`，
经 `_tryConsumeLegacyActionControl`，`ffi_chat_service.dart:6293-6337`）。gate
失败时，body 会 fall through 到
`ingestInboundGroupText(contentKind: action, forceEmit: true)`
（`ffi_chat_service.dart:6281-6288`），也就是**追加历史并 emit**。而回执 JSON
是 `PlainTextEnvelope`，不会被 envelope 层吞掉
（`third_party/tim2tox/dart/lib/utils/control_message_envelope.dart:65-113`）。

这使 I1 必须排在 P1 最前：今天的 auto received-receipt 对每条 inbound group text
都会触发（`ffi_chat_service.dart:6160-6164`），回显的却是**接收者本地铸的 msgID**
（`:6116-6118`），其他成员 history 里没有这个 id，理论上 gate 会在每个 peer
失败。`auto_tests/test/scenarios/` 目前没有 group receipt 场景，只有
`scenario_friend_read_receipt_test.dart`，所以这个问题可能一直没被覆盖到。

I1 新增三节点 auto_test：A 发一条 group text，B/C 自动回执后，断言每个 peer 的
history 都**没有 control-JSON ACTION 行**。如果复现，这就是 live 产品 bug
（垃圾行 + 群 history 污染），直接升为本计划 P0；L1 设计必须先修这条控制行污染，
而不是只追加 correlation。

**B — pseudo-id 关联（唯一方案，需动 native + FFI/ABI）**

1. **C++ → Dart**：给群事件行加一个**可选后缀段**，而不是改既有位置语义。
   建议 `gtext:<groupID>|<sender>|m<u32>:<text>`：解析端**先按新格式试，
   失败回落旧格式**，老 Dart 读新行/新 Dart 读旧行都不炸（这条线是**进程内**
   C++→Dart，不是 peer 之间的线，所以只需自洽，不涉及跨版本互通）。普通文本和
   ACTION 文本都在 scope 内；native ACTION branch 也必须保留 `message_id`。
   发送端新增 `_ex` / out-param export，把 `SendGroupTextMessage` 拿到的
   `message_id` 交回 Dart，并给 `tool/mcp_test/abi_audit.py` 补覆盖（参考 C2C
   拿 native msg id 进 `altMsgIds` 的先例，`ffi_chat_service.dart:5221`）。
2. **Dart 行身份**：收发两端都把 `gmid:<gid>|<senderPk>|<u32>` 写进
   `ChatMessage.altMsgIds`。**必须三元组作用域**：pseudo id 只是 32 位随机数，
   单靠它跨组/跨作者会碰撞。
3. **回执回显与混跑 gate**：群 `_sendReceipt` 的 `msgID` 字段可以发 `gmid:…`
   （键集不变），但不能再假设老 peer "只是 tally 到未知 key"。缺少 `gmid` alias
   的老 peer 会把回执 JSON 渲染成 group ACTION row。混跑门必须双向覆盖
   old→new 和 new→old，并断言**没有渲染控制行**；若不能保证这一点，wire
   `msgID` 字段就必须退回保留 legacy id。
4. **tally + live event 归一**：`_handleReceipt` 的群分支先把 wire msgID **解析成本地行**
   （复用 `message_history_persistence.dart:1026` 的
   `msg.msgID == id || msg.altMsgIds.contains(id)` 语义），**用解析出的本地
   `row.msgID` 作为 `_messageReaders` / `_messageReceivers` 的 key**，这样
   `getMessageReaders(UIKit 的 msgID)` 才对得上。live event 也必须改 key：
   `_handleReceipt` 今天用 incoming wire `msgID` 发 `receiptEvents`
   （`ffi_chat_service.dart:7973-7979`），platform 原样转发
   （`third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:2252-2258`），UIKit
   又按 msgID 存、按本地 `_message.msgID` 渲染
   （`third_party/chat-uikit-flutter/tencent_cloud_chat_common/lib/data/message/tencent_cloud_chat_message_data.dart:407-409, 416-424`，
   `third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_widgets/menu/tencent_cloud_chat_message_item_with_menu_container.dart:143, 344`）。
   如果 event 仍带 `gmid:…`，live label 不会刷新。解析不出来时保持今天的行为
   （按 wire id 记），不回退成丢弃。
5. **重试/离线队列**：resend 不是新 id / 新行。平台 resend 走
   `sendMessage(id: msgID, ...)` 并恢复 `result.data!.msgID = realMsgID`
   （`third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:6762-6779`），群发送建行时
   也 honour `clientMessageID`（`ffi_chat_service.dart:8161-8174`）。L1 必须在 retry
   成功后把新的 `gmid` alias **re-stamp 到既有本地行**，并覆盖 offline queue drain
   （`ffi_chat_service.dart:8249-8299`）。

**明确丢弃的兜底：内容哈希 echo**

不再保留 content-hash fallback。C2C 的 hash 只覆盖前 1024 UTF-8 bytes
（`ffi_chat_service.dart:7155-7165`），其正确性依赖"oldest unread"被消费
（`:7983-8006`）；群里同一条消息有 N 个读者，消费语义天然冲突。改成
"locate but do not consume"也无法区分重复 identical text，且没有 recovery path。
没有 pseudo id 的路由直接 out of scope（见路由矩阵），不走 lossy fallback。

### 移动端影响

修改点全在共享 Dart（`ffi_chat_service.dart` / `tim2tox_sdk_platform.dart`）
和 C++ core —— iOS/Android 与桌面走同一条码路，天然同修。iOS/Android 唯一额外
动作是重建 FFI 产物（`tool/build_android_ffi.sh` / `build_all.sh`）。

### 验收门

1. I1 auto_tests 三节点场景先跑：A 发一条 group text，B/C 自动回执后，断言每个
   peer 的 history 都没有 control-JSON ACTION 行；同一场景必须跑 wall-clock 和
   `RUN_VIRTUAL=1`（`third_party/tim2tox/auto_tests/README.md:138-173, 291-297`）。
2. tim2tox auto_tests 新增群回执关联场景：三节点（作者 A + 读者 B、C），
   断言 **A 侧 `getMessageReaders(A 自己的 msgID)` 从 0→1→2**，且回执不渲染成消息行。
3. 老/新混跑兼容：old→new 和 new→old 都要断言"不崩、不拒收、无渲染控制行"；
   若无法保证，就回退为 wire `msgID` 保留 legacy id。
4. `ChatMessage.altMsgIds` 已经持久化（`third_party/tim2tox/dart/lib/models/chat_message.dart:163, 191-194`），
   但 L1 必须新增 `gmid` alias 的显式 persistence round-trip：写入 → 重启/重载 →
   仍能按 alias 找到本地行。
5. 真 UI 一条：群消息已读人数标签在作者侧实时刷新（复用 `sweep_p1_chat` 的
   receipt 夹具模式，不新开 launch —— 遵守"真 UI 启动复用"约定）。
6. 常规门：`flutter test`、`flutter analyze`、`check_complexity.dart`、Tier 1。

### 风险

- 事件行格式改动会碰到轮询解析的多个分支（`ffi_chat_service.dart:2875-3000`
  有若干前缀嗅探），改错会静默吞消息 —— 必须先补解析层单测再改。
- pseudo id 只在**同一次发送**里稳定；resend 保留本地行 id，但 native 会给新
  pseudo id，必须 re-stamp `gmid` alias，尤其覆盖 offline queue drain。
- `_messageReaders` 是内存态、重启即清（`ffi_chat_service.dart:8045-8047` 有明示），
  本计划**不改这个设计**，只修关联。

**估算**：C++ + Dart + 测试，1 个中等 PR；建议单独成 PR，不与下面的小项混。

---

## L2 —— `_mentionedUsers` 修剪的 fork-input widget 测试（PR #81 记录的 follow-up）

**现状**：PR #81 的 `mobile_mention_deletion_clears_token` 只能在 **TEXT 契约**上
钉死（toxee 线上没有 `groupAtUserList`，修剪不可观测）。修剪逻辑本体在
`third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart:591-602`
（桌面同类逻辑在 `.../desktop/tencent_cloud_chat_message_input_desktop.dart:446-452`）。
我已确认：**fork 的 `tencent_cloud_chat_message/test/` 下没有对应用例**，
toxee 侧也没有。

**方案**：在 **toxee** 侧补（fork 是 path 依赖，toxee `test/` 可以直接挂 fork widget；
先例：`test/ui/chat/desktop_mention_insert_test.dart`）。新增
`test/ui/mobile/mobile_mention_prune_test.dart`：插入两个 mention → 删掉其中一个
token → 断言 `sendMessage` 收到的 `mentionedUsers` 只剩另一个 userID。
**桌面同测**（同一 PR 里覆盖 desktop 分支），符合"移动端对等"要求。

**验收门**：`flutter test`；不需要真机。**风险**：低。**估算**：小。

---

## L3 —— 全局搜索里"刚建的群"缺 joined-groups 快照（PR #80 记录的产品债）

**现状**：新建群不在 SDK 的 joined-groups 快照里，全局搜索只能靠 conversation
fallback 段命中；用例两条路都接受，产品侧没修。相关面：
`third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:9512-9542`
（`getJoinedGroupList` 由 `knownGroups` 派生并按 quitGroups 过滤）。

**方案**：先定性再修，**不要直接猜**。不要把根因压在
`ffi_chat_service.dart:6111-6115` 的 unawaited `_knownGroups.add` 上：那段是
**inbound message ingest**，不是建群路径。建群已经 add 并 await persistence
（`ffi_chat_service.dart:7463-7484`），platform 也 await 了这条路径
（`third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:9167-9181`）。

调查重心改为 native `SearchGroups`：它只对 cached native `group_info_` 做 name
match（`third_party/tim2tox/source/V2TIMGroupManagerImpl.cpp:1172-1188, 1237-1255`），
而全局搜索 fork SDK 会 delegate 到这里
（`third_party/chat-uikit-flutter/tencent_cloud_chat_common/lib/chat_sdk/components/tencent_cloud_chat_search_sdk.dart:85-97`）。
定性两步：
1. 建群后立即用 l3 对比 `getJoinedGroupList`、native `SearchGroups` 和全局搜索结果。
2. 把结论固化成断言，再按事实选择修 native cache 刷新还是 fork 搜索刷新。

若为 native `group_info_` 未刷新 → 建群/群信息变更路径同步更新 native cache；
若为 fork 搜索层缓存陈旧 → 让搜索模块监听群变更事件刷新。**移动端**：
共享 Dart / fork 模块，一处修全覆盖。

**验收门**：把现有 `global_search_group_opens_chat` 从"两条路都接受"**收紧为
只接受 joined-groups 段**，这就是回归门。**估算**：小-中（定性占大头）。

---

## L4 —— PR #72 KNOWN OPEN 的 Android 元素树损坏崩溃：复验并结案

**现状**：`3e7c469` 记了一个 KNOWN OPEN —— Android 上
`attachment_entry_buttons_render` 接 `restore_import_entry_guard` 会在 chat-input
帧损坏元素树（Duplicate GlobalKey + RenderFlex mutation），随后 logout 重建撞
`_dependents.isEmpty` 断言，整壳变 ErrorWidget 不可恢复；当时怀疑重复 push 消息路由。
**后续 PR #73（`d15d58c`）恰好修掉了两条怀疑线**：疑似模块级 GlobalKey 现在是
per-State（`third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_recording.dart:43-50`，
由 `third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart:412-429`
触达），compact duplicate-route guarding 也已经存在（`lib/ui/home_page.dart:724-792`）。
所以 L4 是 **REVALIDATION-ONLY**：除非原始 Android 序列仍复现，否则不发修复 PR。
但**从未用原始最小复现显式复验/结案**。

**方案**：不写新代码，先**复验**。在 Android pair 上按原序列跑这两个 case
（它们分布在 `tool/mcp_test/` 的 fixture-C 真 UI 用例里），跑 3 次：
- 全绿 ⇒ 在 CONTEXT/commit 里正式结案，并在对应 campaign 里把这条**序列**固化成
  常驻用例（防止再次回归）。
- 仍红 ⇒ 按 `adb logcat -d -b crash` + `run-as com.toxee.app cat files/logs/` 抓栈，
  转入独立根因 PR（**先抓证据再重装**，重装会抹掉日志 —— 见 batch 7 的教训）。

**估算**：半天量级，主要是机器时间。**优先级**：高于 L2/L3 —— 未结案的崩溃是最贵的未知。

---

## L5 —— 代码内 l10n TODO（4 处）

| 位置 | 内容 |
|---|---|
| `lib/ui/login_page.dart:1127` | `daysAgo/hoursAgo/minutesAgo` 用了空 `{plural}` 占位，英文退化成 "2 day ago" |
| `lib/ui/login_page.dart:1358` | `appTagline` 硬编码英文 |
| `lib/ui/settings/bootstrap_nodes_page.dart:339` | 硬编码失败文案，应复用既有 `failedToLoadBootstrapNodes` |
| `lib/ui/settings/bootstrap_nodes_page.dart:350` | `noBootstrapNodes` 硬编码 |

**方案**：`failedToLoadBootstrapNodes` 已经存在于每个 ARB
（`lib/l10n/app_en.arb:779-782`），UI 只是硬编码了字符串
（`lib/ui/settings/bootstrap_nodes_page.dart:339-344`），所以**复用既有 key**，
不要新增 `failedToLoadNodes`。`appTagline` / `noBootstrapNodes` 才是补 key
（7 个 arb：en/zh/zh_Hans/zh_Hant/ja/ko/ar 全部补齐，缺一个语言就会回退英文）。
第一处需要把 `daysAgo` 等改写成真正的 ICU
`{count, plural, ...}` 形式 —— **注意 `daysAgo` 在 7 个 arb 里都已存在**
（如 `lib/l10n/app_en.arb:1233`），是改写而非新增，改的时候要同步 `@daysAgo`
的 placeholder 元数据，否则 gen-l10n 会失败。

**移动端**：纯共享 UI 层，自动覆盖。**验收门**：`flutter gen-l10n` + `flutter test` +
`flutter analyze`。**估算**：小。可与 L2 合并成一个"清扫 PR"。

---

## L6 —— 联系人/申请页的 scroll-to-top（`lib/ui/home_page.dart:1593-1599`）

**现状**：底部导航重复点击当前 tab 时，只有 tab 0（会话）能回顶
（走 `TencentCloudChatConversationController.instance.scrollToTop()`），
tabs 1/2/3 因为对应 widget 没暴露 controller 而留空。

**方案**：在 fork 的 contact / applications 页把 `ScrollController` 通过与会话页
**同形状的 controller 单例**暴露出来，home 侧按 index 分发。**不要**在 toxee 侧
用 GlobalKey 反查 —— 那是绕过分层。settings 页若是 toxee 自有页面，可直接持有
controller，无需动 fork。

**移动端**：这本来就是移动端手势约定（桌面无底部导航），属于**移动端专项**，
桌面无对应面。**验收门**：真 UI 一条（重复点 tab 1 后列表回到顶部），挂进已有
`sweep_mobile_shell` 而非新开 launch。**估算**：小-中（要动 fork 两个模块）。

---

## L7 —— l3 harness 的群覆盖缺口（`lib/ui/testing/l3_debug_tools.dart` 的 `group_unsupported`）

**已完成 2026-09-29。下面保留原始判断与它错在哪，因为这一段的错误前提本身
比缺口更贵——它把后续工作导向了错误的方向。**

**原始现状描述（部分错误）**：说约 15 处对 group id 返回 `group_unsupported`，
并断定 `l3_mark_read` 的群分支**不能**走 `markConversationRead`，
「因为后者只发 C2C receipts」。

**实际情况**：

- 那条前提在写下时成立，之后**失效了**。群回执工作让
  `FfiChatService._sendReadReceiptsOnView` 按 `_knownGroups` 分派，群走
  `_sendGroupReadReceiptsOnView` 并真的上线发每个作者的回执。所以
  `cleanConversationUnreadMessageCount('group_<gid>')` →
  `markConversationRead` **就是**真实的群标已读路径，也正是会话行菜单
  「标为已读」走的入口。`drive_real_ui_pair_group_menu.dart` 里
  `runGroupMarkReadUnread`（S118/S133）的注释早就写明了这一点：
  「through the production path the docs wrongly believed was a no-op」。
- `l3_dump_state` **本来就有**完整的群分支（`conversation` / `conversationKind` /
  `messageCount` / `messages[]`），缺的只是 `unreadCount` 和 `isRead`。
  下面那个 `else if (isGroup)` 的 skip 只在「识别出是群但解析不出会话 id」时触发。
- `l3_open_chat` 确实支持群，但它**不会**到 `markGroupMessageAsRead`；打开群会把它
  绑为 active，由 UIKit 的消息列表对可见入站行调
  `cleanConversationUnreadMessageCount`。`markGroupMessageAsRead` 在本仓库里只有
  tim2tox 的 auto-test 在调。
- 真正的洞不是"标已读不能驱动"，而是**没有任何断言能证明群回执真的跨过了线**。
  C2C 有（`drive_real_ui_pair_p1_chat.dart` 的 `_p1cReadReceiptDoubleTick`：
  发送方那行 isReceived+isRead 翻转），群没有，而且群 dump 分支连 `isRead` 都不暴露，
  这种断言写不出来。
- 计数：19 处字面 `group_unsupported` 返回加一处 dump skip，不是 21；转掉一处后剩 18。

**实际做法**：

1. `l3_mark_read` 接受群目标，分支实现放在 `lib/ui/testing/l3_group_receipt_tools.dart`
   （那个文件本来就是为了不让被 pin 的 registry 继续增长而存在的），走与 C2C 同一个
   `cleanConversationUnreadMessageCount`。`groupId` 优先于任何解析结果与 active-peer
   兜底；**未知群和已退群显式拒绝**——对服务不认识的群，`markConversationRead` 会推进
   barrier、跳过回执遍历、然后照样返回成功，那是一次什么都没发的绿。
2. 群 dump 分支补 `unreadCount`（用 `getUnreadOf`，群的权威计数）和 `isRead`。
3. 新增双进程用例 `group_read_receipt_tick`（自己的 part 文件
   `drive_real_ui_pair_group_receipt.dart`）：A 发群消息 → B 用新分支标已读 →
   **A 自己那行的 `isRead` 必须 false → true**。这是唯一能证明往返的断言；
   B 用 `l3_mark_read` 而不是 `l3_mark_group_read`，因为后者需要 `force: "true"`
   （作者的 `needReadReceipt` 意图在 Tox 线上没有载体），而 forced 调用不能声称
   产品闸门被走过。
4. 另外 18 处拒绝保持不变，并已在代码里写明是**有意为之**。

**一个仍然成立的限制**：`l3_mark_read` 的群分支返回 `ok: true` 只说明读者的本地读态
推进了——回执遍历只扫已加载的历史、冷缓存会提前返回，而且发送不 await。工具的文档注释
里写明了这一点；能证明投递的只有第 3 条那个断言。

## 建议的批次与顺序

| 批次 | 内容 | 理由 |
|---|---|---|
| **P0** | L4（复验 Android 崩溃并结案） | 未结案崩溃是最贵的未知；不写新代码，先拿事实 |
| **P1** | I1 → L1 + L7（先验证群回执是否已渲染控制行，再做群回执对等 + 必需的 l3 群分支） | I1 若红直接升 P0；harness 是 L1 的验证前提 |
| **P2** | L2 + L5（mention 修剪测试 + l10n 清扫） | 低风险，可合成一个清扫 PR |
| **P3a** | L3（搜索快照） | tim2tox Dart + native search 问题，独立 PR |
| **P3b** | L6（scroll-to-top） | fork contact-controller + first-party applications/settings scroll-controller 工作，独立 PR |

P3 不再按"共同 fork commit"合并：L3 是 tim2tox Dart+native search，L6 是 fork
contact-controller 加 toxee 自有 applications/settings controller 分发
（`lib/ui/home_page.dart:1587-1600`，
`third_party/chat-uikit-flutter/tencent_cloud_chat_contact/lib/tencent_cloud_chat_contact_controller.dart:9-10`，
`lib/ui/applications/applications_page.dart:752-789`）。两者拆 PR，分别落地。

每批次遵守既有工作约定：草案 → codex 审 → 应用发现 → 重跑门
（analyze / flutter test / check_complexity / Tier 1 / 相关 l3 partition）→
codex 复核 → 合并。submodule 先提交推送，再提父仓 gitlink。

## 明确不在本计划内（不要当回归重新发现）

- `sweep_group_conf_member_extra` / `sweep_p1_chat` 仅 iPad —— 窄壳导航分支不存在。
- PR #64 记录的截图差异（设置页可滚动、各平台 Tox ID 不同、未读角标数值自洽）。
- `_messageReaders` / `_messageReceivers` 重启清零 —— 设计如此（回执从实时流量重建）。

## 待确认的观察项

#89 关掉了自 2026-08-02 起每天开的 25 个 nightly `ci-failure`（#43–#84）。
**今晚的 nightly 是那三处修复的第一次真实验证**，需在下一次会话开头确认没有新 issue，
那条战线才算真闭。

## 变更记录 (2026-09-02, codex review)

- finding 1：修正 L1 toxcore PUBLIC group broadcast 接收端 pseudo id citation 为 `group_chats.c:4844-4849`。
- finding 2：补明发送侧 pseudo id 今天不 Dart-visible，并把 `_ex` / out-param export 与 `abi_audit.py` 列为 L1 工作项。
- finding 3：替换 mixed-version 误判，新增 P1 首项 I1，要求先实证今天群回执是否渲染为 ACTION 控制行。
- finding 4：新增 L1 路由矩阵，明确 normal/action text in scope，custom/files/legacy conference out of scope。
- finding 5：删除 resend 新 id / 新行说法，改为 retry/offline queue 后对既有行 re-stamp `gmid` alias。
- finding 6：删除 content-hash echo fallback，并记录无 pseudo id 路由直接 out of scope。
- finding 7：要求 L1 同时 re-key live `receiptEvents`，避免 UI live label 仍按 `gmid` 失配。
- finding 8：从 L7 待补项移除已存在的 `l3_clear_group_history`，并把 `l3_mark_read` 接到真实 group read-receipt path。
- finding 9：替换 L3 根因假设，把调查重心从 inbound `_knownGroups.add` 改为 native `SearchGroups` cache。
- finding 10：修正 P3 batching rationale，把 L3 和 L6 拆成独立 PR。
- finding 11：把 L4 明确为 REVALIDATION-ONLY，并记录疑似修复已由 per-State key 和 duplicate-route guard 覆盖。
- finding 12：L5 改为复用既有 `failedToLoadBootstrapNodes` key，不新增 `failedToLoadNodes`。
- finding 13：强化验收门：I1 同跑 `RUN_VIRTUAL=1`、L7 显式处理 complexity ratchet、L1 增加 `gmid` alias persistence round-trip。
- 复核轮（confirm review）：修正 5 处新引入的失效路径引用（UIKit receipt store/render、search sdk、recording widget、applications_page、auto_tests README），并补齐 C2C 4 键丢弃 vs 群 ACTION 5 键 fall-through 的区别。

---

## 执行结果 (2026-09-02/03)

### P0 · L4 —— 复验通过，结案

Android pair 上按原序列跑 `rui-native-boundary-guards`（含
`attachment_entry_buttons_render` → `restore_import_entry_guard`）**5 次**：
4 次绿（7 PASS / 0 FAIL / 1 SKIP，`endClean=true`），1 次（run3）两次 attempt
都卡在启动期 `"connected"` 超时（`isConnected:false`，DHT 没连上），**根本没跑到
用例**。PR #72 记的元素树损坏崩溃**不复现** → 按计划"REVALIDATION-ONLY"结案。

顺带记录一个与 L4 无关的环境项：Android pair 冷启动偶发 DHT 连接超时（5 次里
2 次首 attempt 失败、1 次两次都失败）。不在本计划范围内。

### P1 · I1 —— **复现了，是 live 产品 bug**，已修

新增 `auto_tests/test/scenarios/scenario_group_receipt_control_row_test.dart`。
注入一条"引用了本端不认识的 msgID"的群回执（这正是**每一条**跨进程群回执今天
的样子）后：`rows 1 -> 2`，raw JSON 作为 ACTION 行进了历史并被渲染。

**根因层**：`_tryConsumeLegacyActionControl` 只有两种出口 —— 应用，或者
**fall through 去渲染**。修法是补上第三种、也是唯一安全的一种：**载荷带
tim2tox 自己控制帧签名的（`BinaryReplacementHistoryHook.isInternalProtocolCustomData`），
拒绝应用时一律 DROP，绝不渲染**。C2C legacy-ACTION 路径同样适用（同一类垃圾，
且"id 恰好存在与否"不该决定协议 JSON 是否出现在聊天里）；原先钉住旧行为的单测
已按新语义改写，并补了"非控制 ACTION 内容仍然渲染"的反向用例。

### P1 · L1 —— 关联层已打通（本次交付），意图层仍缺

**已交付并证明**（`scenario_group_receipt_control_row_test` 3/3）：

- C++：thread-local guard 在一次群消息投递期间发布 `Tox_Group_Message_Id`，
  FFI simple listener 在 `gtext:`/`gaction:` 头部追加**可选** `|m<pseudoId>` 段；
  发送侧新增两个 C 导出，回传首个分片的 pseudo id **和作者的 per-group 公钥**。
- **per-group 公钥是关键**：NGC 里对端看到的发送者是 per-group key，不是长期
  Tox ID。第一版按长期 ID 作用域，两端算出的 alias 不一致 —— 被测试当场抓到。
- Dart：`parseGroupHeader`（新 3 段 + 旧 2 段都解析）、收发两侧把
  `gmid:<gid>|<perGroupKey>|<id>` 写进 `altMsgIds`、回执回显 alias、
  `_messageReaders`/`_messageReceivers` **和 live `receiptEvents`** 一起改按
  **作者本地行 id** 归一（UIKit 查的就是这个 id）。
- 覆盖 codex 复审指出的两条真实路径：**hybrid 重复投递路径**（advanced listener
  先落库、轮询副本才带 pseudo id）会把 alias **merge 进已存在的行**并只回执一次；
  **离线队列 drain** 在任何 await 之前就把 alias 盖到既有行上。

**仍缺（L1 的剩余子项，不要当作已完成）**：作者的 `needReadReceipt` 意图**没有
Tox wire 载体** —— 它只是发送端本地行上的一个标志，入站行永远拿不到。fork 只对
`needReadReceipt == true` 的入站消息发群已读回执，所以**真实产品流量下 READ 回执
依然不会自动发出**（`received` 回执不受影响，已经通了）。这正是当初"需要
version-safe 群控制帧传输"要解决的另一半。在它落地前，`l3_mark_group_read` 需要
显式 `force=true` 才能驱动关联链路，且该参数在工具描述里写明了原因。

**已知限制（记录，非缺陷）**：分片消息只发布**首个分片**的 pseudo id；接收端本来
就为每个分片生成独立的行，所以关联绑定在第一行上。

### P1 · L7 —— 只补了 L1 需要的那一个

新增 `lib/ui/testing/l3_group_receipt_tools.dart`（`l3_mark_group_read`，走真实的
`sendMessageReadReceipts` 路径）。`l3_debug_tools.dart` 只多了 import + 注册两行，
复杂度基线按计划显式 re-pin 7242→7244 并写明理由。

### P2 · L5 —— 完成

`daysAgo/hoursAgo/minutesAgo` 改成真正的 ICU `{count, plural, ...}`（en 模板），
去掉 `{plural}` 占位符；阿拉伯语同步去掉该占位符（此前 app 一直传空串，渲染不变）；
`appTagline` / `noBootstrapNodes` 补齐 7 个 arb；失败文案复用既有
`failedToLoadBootstrapNodes`。顺带修掉 `settings_page.dart` 手工拼英文 "s" 的调用点
（它在所有非英语 locale 下都是错的）。

### 门禁

toxee `flutter test` 1818/0；`flutter analyze` 0 error；`check_complexity` exit 0；
tim2tox phases 1,3,4,12,14（RUN_VIRTUAL）36/36；MCP harness smoke 四道门全绿
（helpers / runner / `--validate-only` 48 scenarios / INDEX 178 playbooks）；
`abi_audit.py` exit 0（注：新导出属 Platform-path C API，不在 `Dart*` 二进制替换
ABI 审计范围内，其保护是 Dart `lookupFunction` 的签名匹配 + 场景测试）。

### 未做

L2（mention 修剪 widget 测试）、L3（全局搜索 joined-groups 快照）、
L6（tabs 回顶）仍按计划待办。

---

## 执行结果 (2026-09-03, 第二批 L2/L3/L6)

### P2 · L2 —— 完成，且证明了两个 composer 的驱动方式不同

新增 `test/ui/chat/mention_prune_test.dart`，覆盖 mobile + desktop 两侧：插入两个
mention → 在 token 内部退格 → 断言 **`sendTextMessage` 收到的 `mentionedUsers`
只剩另一个**（这正是 toxee 线上看不到的那一半，因为群消息没有 `groupAtUserList`）。

过程中差点误判成产品 bug，记录下来避免重犯：
- 第一版把断言写成 `isNot(contains('@Bob'))`，删掉一个字符后文本变 `@Bo`，**断言
  会假性通过** —— 已改成断言整段文本，token 必须整体消失。
- desktop 一开始"不修剪"，看着像产品缺陷；实际是**驱动方式错了**：mobile 用
  `_textEditingController.addListener(_onTextChanged)`（程序化写入会触发），
  desktop 用 `onChanged:`（程序化写入**不触发**）。`tester.enterText` 也不行 ——
  它需要 `EditableText` state，而这两个 composer 建在 `ExtendedEditableText` 上
  （fork 自己那些 harness seam 存在的同一个原因）。最终按框架真实顺序驱动：
  写 editing value → 调 `field.onChanged`。

### P3a · L3 —— 根因不是原假设，已修（native 层）

按修订后的计划先实证：新增
`third_party/tim2tox/auto_tests/test/scenarios/scenario_group_search_by_name_test.dart`，
**复现成功** —— 创建者能按名字搜到，**JOIN 进来的成员搜到空列表**。

根因确认在 native：`searchGroups` 不在 Platform path 上，走
`DartSearchGroups` → `V2TIMGroupManagerImpl::SearchGroups`，而它只拿
`group_info_` 里缓存的名字做匹配；JOIN 的一方只有
`EnsureGroupInfoExists` 塞的占位符（`groupName == groupID`），于是**按名字搜索
静默退化成按 ID 搜索**。live NGC 名字一直都在（`tox_group_get_name`）。

修复：新增 `ResolveGroupName()`（缓存名为真名则用缓存，否则读 live NGC 名），
匹配和返回的 `groupInfo.groupName` 都用它。两个坑：
- `ToxManager::getGroupName` 会拿 ToxManager 的 mutex，这条调用路径**已经持有**
  → searchGroups 直接死锁（现象：2 分钟超时）。改为按本文件既有惯例直接调
  `tox_group_get_*`。
- 解析出 live 名字后，`tox_inv_<friend>_<ms>` 邀请占位 id 也会匹配同一个关键字，
  **搜索结果里出现两行同名群**。已按 `IsTemporaryInviteGroupID` 跳过 —— 这是我自己
  引入的回归，不是既有问题。

真 UI 门禁按计划**收紧**：`global_search_group_opens_chat` 从"两条路都接受"改为
**必须命中 SDK groups 行**；只剩 conversation fallback 时打印明确诊断。
Android pair 实跑 `rui-c2c-extra`：`rowShown=true tapped=true bound=true
surface=true`，sweep `passed=1 flaky=0`。

### P3b · L6 —— 完成

- fork：`TencentCloudChatContactController` 暴露 `itemScrollController` +
  `scrollToTop()`（**必须是 `ItemScrollController`**：联系人列表是 `AzListView`，
  只接受这个类型；`scrollable_positioned_list_for_us` 由隐式传递依赖改为显式声明）。
- toxee：`ApplicationsPage` / `SettingsPage` 接受外部 `ScrollController`，
  `HomePage` 自己持有这两个 controller 并按 tab index 分发 —— 不用 GlobalKey 反查。
- 覆盖：`test/ui/mobile/contacts_scroll_to_top_test.dart`（真列表驱动 + 未挂载时
  no-op）。**诚实说明**：HomePage 的分发本身在 `test/` 里无法 hermetic 地 pump
  （`build()` 会绑定 UIKit 全局并构建所有 tab，见既有
  `home_bottom_nav_real_ui_test.dart` 的同款说明），所以这里钉的是分发所依赖的
  controller 契约。

复杂度门：`applications_page.dart` 因为构造函数参数展开 +7 行顶穿 pin，已按计划
**带理由 re-pin**（功能只有 4 行，其余是 formatter 展开）；`settings_page.dart`
通过精简注释回到 pin 之内，未 re-pin。

### 第二批 codex 审核（3 轮，最终 APPROVE）

首轮 NEEDS-CHANGES 三条，全部核实成立并修复：

1. **HIGH：`SearchGroups` 的候选集是"`groups_`，除非它是空的"**。`groups_` 只由
   CreateGroup 写入，JOIN 进来的群只登记在 manager 的
   `group_id_to_group_number_` 里 —— 所以**"建过群的节点搜不到自己加入的群"**，
   而我的测试恰好因为 joiner 从没建过群（`groups_` 为空走了 fallback）才通过。
   已改为两个注册表的**并集**去重；测试补上混合态（member 先建自己的群再搜）。
2. **HIGH：数据竞争**。`ResolveGroupName` 直接读 manager 的私有 map，而 join/quit/
   promotion 在 manager mutex 下改它；结果路径读 `group_info_` 也没有加锁。已改走
   既有的加锁访问器 `GetGroupNumberFromID`，并把 `group_info_` 的拷贝放进
   `group_mutex_`。（注意：`ToxManager::getGroupName` 不能用 —— 它拿 ToxManager 的
   mutex，本调用路径可能已经持有，实测直接死锁。）
3. **MEDIUM：`ItemScrollController` 是单挂载的**，用单例字段被每个联系人列表绑定，
   两个列表同时存在时 debug 会 assert。已改为 **per-State 持有 + 向组件控制器注册**
   （与 PR #73 的 per-State trashIconKey 同一模式）。

复核轮又指出两点，也都修了：注册表必须是**栈**而不是单槽（新列表 pop 后，下面那个
可见列表要重新成为目标，否则 scrollToTop 静默失效）；栈要**有界**（永不 unregister
的 State 会无限增长）。最终四个排序/边界用例全部覆盖。

**最终门禁**：toxee `flutter test` **1825/0**；`flutter analyze` 0 error；
`check_complexity` exit 0；tim2tox phases 1,3,4,12,14（RUN_VIRTUAL）**37/37**；
MCP harness 四道门全绿；Android 真机 `global_search_group_opens_chat`
`rowShown=true tapped=true bound=true surface=true`。
