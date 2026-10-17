[English](./CALLING_AND_EXTENSIONS.md)

# toxee 通话与扩展


本文档说明 toxee 中已经落地、但不属于基础聊天链路的扩展能力：音视频通话、UIKit 插件、局域网 Bootstrap 与 IRC 集成。

## 1. 通话架构

当前客户端的通话实现依赖三个层次：

- `FakeUIKit.startWithFfi()` 创建 `CallStateNotifier` 和 `CallServiceManager`
- `HomePage.initState()` 在 `Tim2ToxSdkPlatform` 设置完成后调用 `callServiceManager.initialize()`
- `CallServiceManager.initialize()` 依次初始化 `ToxAVService`、`CallBridgeService`、`TUICallKitAdapter`，并通过 `registerToxAVWithTUICore()` 注册到 TUICore

这意味着通话系统依赖 `Tim2ToxSdkPlatform` 已经就绪；否则 signaling listener 无法正确挂载。

## 2. 两条通话路径

### 2.1 Signaling 路径

这是 UIKit 触发的主路径：

1. 用户在 UIKit 中点击音视频通话按钮
2. TUICore 把调用转给 `TUICallKitAdapter`
3. `TUICallKitAdapter` 通过 `Tim2ToxSdkPlatform.invite()` 创建 signaling invite
4. 若能解析出好友 `friendNumber`，则同步调用 `ToxAVService.startCall()`
5. `CallBridgeService` 负责处理接受、拒绝、取消、超时等 signaling 事件
6. `CallStateNotifier` 驱动通话 UI 和悬浮层

### 2.2 Native ToxAV 路径

这是为了兼容 qTox 等外部 ToxAV 呼叫保留的路径：

1. `ToxAVService` 直接收到 native callback
2. `CallServiceManager` 把它映射成 `native_av_<friendNumber>` 形式的 inviteID
3. UI 仍通过 `CallStateNotifier` 进入统一的来电/通话状态机

因此，客户端既支持 UIKit signaling 路径，也支持纯 ToxAV 直连路径。

## 3. 通话记录写入

通话结束时，`CallServiceManager` 会回调 `FakeUIKit.onCallRecordNeeded`。随后 `FakeUIKit` 会：

- 构造自定义消息格式的通话记录
- 写入 `FfiChatService` 历史，确保历史消息查询可见
- 通过 event bus 发出实时事件
- 注入 UIKit `messageData`，保证当前打开会话立即刷新

这保证了“历史可追溯”和“当前会话实时刷新”同时成立。

## 4. UIKit 插件接入

### 4.1 sticker

- 在 `HomePage.initState()` 中优先于 message 组件注册
- 如果 `selfId` 尚未就绪，则在连接成功后补注册
- 这样可以避免 message input 初始化时拿不到 `stickerPluginInstance`

### 4.2 textTranslate / soundToText

- 在 HomePage 中按需懒注册
- 注册状态由 `_textTranslatePluginRegistered` 和 `_soundToTextPluginRegistered` 控制，避免重复接入

## 5. 局域网 Bootstrap

`LanBootstrapServiceManager` 负责桌面端本地 Bootstrap 服务：

- 自动探测本机可用 LAN IP
- 创建独立测试实例作为 Bootstrap 服务节点
- 暴露本机 IP、UDP 端口和 DHT 公钥给 UI
- 允许客户端在局域网内快速互连

这部分不是基础聊天必需能力，但对桌面局域网调试和演示很重要。

## 6. IRC 集成

`IrcAppManager` 负责 IRC 扩展：

- 动态加载 `libirc_client.dylib`
- 为 IRC channel 创建 / 恢复对应的 Tox group
- 维护 `channel -> groupId` 映射
- 调用 `FfiChatService.connectIrcChannel()` / `disconnectIrcChannel()` / `unloadIrcLibrary()`

客户端 UI 只负责安装状态、频道入口和交互，真正的 IRC 网络收发仍在 tim2tox 侧动态库实现。

## 7. ToxAV 构建矩阵与运行时可用性

通话功能只有在 `libtim2tox_ffi` 以 `BUILD_TOXAV`（opus + libvpx）编译时才真实
存在。自 2026-07 起，**所有构建路径默认开启 ToxAV 且缺依赖即报错**——此前
它是 opt-in（`--toxav`），所有发布产物都静默携带 no-op 通话 stub。

| 构建路径 | ToxAV | 编解码依赖来源 |
|---|---|---|
| `run_toxee.sh` / `build_ffi.sh`（macOS 开发） | 开 | Homebrew opus/libvpx，`bundle_dylib` 装订 |
| `tool/ci/build_tim2tox.sh`（五平台，含 `build-packages.yml` 发布） | 默认开；`--no-toxav` 显式关闭 | linux: apt `libopus-dev libvpx-dev`；macos: brew；windows: vcpkg `opus`/`libvpx`；android/ios: `tool/ci/build_av_deps.sh` 固定源码交叉编译 |
| `tool/build_android_ffi.sh`、`tool/build_ios_sim_ffi.sh`（开发环） | 默认开（`TOXAV=0` 关闭） | `tool/ci/build_av_deps.sh` |

防护措施：

- 运行时探针 `tim2tox_ffi_av_is_available()` → `CallAvBackend.isAvailable`
  → `CallServiceManager.isCallingAvailable`。只有加载的原生库带真实后端时
  UI 才展示通话按钮（`setUseCallKit`）——stub 或旧库会隐藏通话入口而不是
  静默失败。
- Marker 符号 `tim2tox_ffi_av_backend_toxav` 仅真实构建导出；
  `tool/ci/package_artifacts.sh` 打包前断言其存在，拒绝打包 stub 产物
  （逃生口 `TOXEE_ALLOW_STUB_AV=1`，发布产物禁用）。
- 视频通话入口另受 `CallMediaCapabilities.supportsVideoCapture()`（fork 中
  的 `useVideoCall` 数据位）门控：Windows/Linux 无摄像头采集后端，在补全
  之前仅提供语音通话。

## 7. 位置消息与"附近的人"

两者都只建立在 P2P 链路上，没有 toxee 服务器。面向用户的参考见
[LOCATION_AND_NEARBY.zh-CN.md](LOCATION_AND_NEARBY.zh-CN.md)；设计见
`doc/plans/LOCATION_AND_NEARBY_PLAN.md`。

- **位置消息** —— SDK 自带的 `createLocationMessage`（原生平台上是纯 Dart）加上
  `Tim2ToxSdkPlatform.sendMessage` 里已有的 `__location__:` 文本信封。toxee 补上
  输入框选项（`lib/ui/home/desktop_input_options.dart`、`mobile_attachment_policy.dart`，
  仅在账号的"位置"开关开启时显示）、发送路径 `lib/nearby/location_sender.dart`
  （开关 → 权限 → 一次定位 → 发送，单聊与群聊）和气泡
  `lib/ui/widgets/location_message_bubble.dart`（坐标、经由系统"在地图中打开"、
  复制；不依赖地图服务商）。
- **附近的人** —— tim2tox 的*会合群*
  （[RENDEZVOUS_GROUPS.zh-CN.md](../../third_party/tim2tox/doc/architecture/RENDEZVOUS_GROUPS.zh-CN.md)）：
  Chat ID 由 geohash 单元推导的 NGC 公开群
  （`SHA-256("toxee/nearby/v1|" + cell)` → 种子密钥对，`agentx-icu/c-toxcore` fork 上的
  `tox_group_new_with_seed`）。上层协议由 toxee 拥有（`lib/nearby/`）：在场记录与
  加好友意向，用每次会话的 Ed25519 密钥签名、X25519 + XChaCha20-Poly1305 封装；
  `NearbyService` 是状态机，`NearbyController` 是每会话单例（HomePage 启动时附着，
  在 `nearbyShutdown` 拆除阶段与 `paused` 时停止）。设置项：“位置”（总开关）与
  “对附近的人可见”，均按账号存储、默认关闭（`lib/util/prefs/location_prefs.dart`）。

## 8. 相关文档

- [architecture/HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.md)
- [../architecture/MAINTAINER_ARCHITECTURE.md](../architecture/MAINTAINER_ARCHITECTURE.md)
- [Tim2Tox ToxAV 与 signaling](../../third_party/tim2tox/doc/integration/TOXAV_AND_SIGNALING.md)
- [LOCATION_AND_NEARBY.zh-CN.md](LOCATION_AND_NEARBY.zh-CN.md)
