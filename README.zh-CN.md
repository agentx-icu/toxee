# toxee

> Language: [English](README.md) | **简体中文**
>
> 基于 Tim2Tox 的 Flutter 聊天客户端 / 示例应用

---

## 5 分钟内理解本项目

- **toxee 是什么**：一个可运行的 Flutter 聊天 App，用 Tencent Cloud Chat UIKit 做界面，用 **tox** 做后端，走 Tox P2P 网络。
- **Tim2Tox 是什么**：连接 UIKit 与 tox 的兼容层/框架（在 `third_party/tim2tox`，上游仓库：[agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)）；不是聊天应用本身。
- **架构一句话总结**：toxee 通过「二进制替换 + Platform」混合架构接入 Tim2Tox，大部分 SDK 调用走 `NativeLibraryManager -> Dart*`，历史/轮询/通话等由 `Tim2ToxSdkPlatform -> FfiChatService` 补足。
- **最短跑起来**：克隆 -> `dart run tool/bootstrap_deps.dart` -> `flutter pub get` -> `./build_all.sh --platform macos --mode debug` 或 `./run_toxee.sh`。

深层实现与按角色阅读路径见 [doc/README.md](doc/README.md)。

---

## 项目简介

**toxee** 是**基于 tox 的 Flutter 聊天客户端 / 示例应用**。它展示如何将 tox 与 Tencent Cloud Chat UIKit 集成，实现去中心化 P2P 聊天：账号、会话、消息、好友、群组、Bootstrap、可选通话与扩展能力均在当前仓库内实现或对接。

**明确定义**：

- **它是**：一个可运行的 Flutter 应用，面向“想跑起来”的开发者和“想理解客户端与 Tim2Tox 关系”的维护者；同时作为集成 Tim2Tox 的参考实现。
- **它不是**：底层协议库（协议与 V2TIM 映射在 Tim2Tox 中实现）。
- **它不是**：通用 SDK（UI、账号体系、Bootstrap 配置、通话桥等是 toxee 自身实现，其他客户端需自行适配）。

---

## 功能截图

真实应用，一套 Flutter 代码，运行于**桌面（macOS）、Android、iPad 与 iOS**（点击图片查看原图）。全部图片位于 [`doc/product/assets/`](doc/product/assets)；完整功能展示见自包含产品页 **[`doc/product/index.html`](doc/product/index.html)**（在浏览器中打开）。

**同一个单聊，在每个平台上：**

| 桌面 | iPad | Android | iOS |
| :---: | :---: | :---: | :---: |
| [![macOS 上的聊天](doc/product/assets/desktop/c2c.png)](doc/product/assets/desktop/c2c.png) | [![iPad 上的聊天](doc/product/assets/ipad/c2c.png)](doc/product/assets/ipad/c2c.png) | [![Android 上的聊天](doc/product/assets/android/c2c.png)](doc/product/assets/android/c2c.png) | [![iOS 上的聊天](doc/product/assets/ios/c2c.png)](doc/product/assets/ios/c2c.png) |

**更多（桌面）：**

| 群聊 | 新的朋友 | 个人资料 & Tox ID 二维码 | 设置 |
| :---: | :---: | :---: | :---: |
| [![群聊](doc/product/assets/desktop/group_chat.png)](doc/product/assets/desktop/group_chat.png) | [![好友申请](doc/product/assets/desktop/new_application.png)](doc/product/assets/desktop/new_application.png) | [![个人资料与 Tox ID 二维码名片](doc/product/assets/desktop/self_profile.png)](doc/product/assets/desktop/self_profile.png) | [![设置](doc/product/assets/desktop/settings.png)](doc/product/assets/desktop/settings.png) |

> 这些截图由 `./tool/screenshots/capture.sh` 从运行中的应用自动生成 —— 详见 [`tool/screenshots/README.md`](tool/screenshots/README.md)。

---

## 这个项目解决什么问题

- **对使用者**：提供一个“开箱可跑”的 Tox 聊天客户端，使用现成 UIKit 界面与交互，无需从零写 UI。
- **对集成者**：展示如何做依赖引导（submodule、SDK 拉取与打补丁、`pubspec_overrides`）、如何实现 Tim2Tox 的接口注入（Preferences、Logger、Bootstrap 等）、如何安排 `init -> login -> startPolling -> Platform` 的启动顺序。
- **对维护者**：说明为何采用混合架构、二进制替换与 Platform 各自承担哪些能力、调用链与日志从哪里看，便于排错与扩展。

---

## 它与 Tim2Tox 的关系

| 维度 | Tim2Tox | toxee |
| --- | --- | --- |
| **角色** | 兼容层/框架：提供 C++ 核心、C FFI、Dart 封装与 SDK Platform 实现，供任意 Flutter 客户端接入。 | 客户端/示例应用：消费 Tim2Tox，实现账号、UI、Bootstrap、历史、通话桥等。 |
| **位置** | `third_party/tim2tox`（submodule，上游：[agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)）。 | 本仓库根目录。 |
| **依赖方向** | Tim2Tox 不依赖 toxee；通过接口注入依赖偏好、日志、Bootstrap 等能力。 | toxee 依赖 `tim2tox_dart`，并实现 Tim2Tox 所需接口、构造 `FfiChatService`、设置 Platform 路径。 |

**调用关系（简化）**：

```text
toxee (UI / 账号 / Bootstrap / 适配层)
    |
    |-- setNativeLibraryName('tim2tox_ffi') -> SDK 加载 libtim2tox_ffi
    |-- FfiChatService(prefs, logger, bootstrap, ...) -> Tim2Tox 服务层
    |-- Tim2ToxSdkPlatform(ffiService) -> Platform 路径入口
    '-- FakeUIKit / FakeMessageManager / ... -> 将 Tim2Tox 数据适配为 UIKit 模型
                    |
                    v
            Tim2Tox (dart / ffi / C++)
                    |
                    v
            c-toxcore (Tox P2P)
```

---

## 当前架构概览

当前采用**混合架构**：既做**二进制替换**（SDK 仍通过 `NativeLibraryManager -> Dart*` 调用 Tim2Tox），又设置 **`Tim2ToxSdkPlatform`**（历史、部分回调、通话等走 `FfiChatService`）。

**为什么是混合架构，而不是纯二进制替换或纯 Platform？**

- **纯二进制替换**：最少改业务代码，但历史消息、`clearHistoryMessage`、`groupQuitNotification`、Bootstrap 配置、轮询与通话等需要 Dart 侧状态与持久化，仅靠 C++ 回调无法完整实现；UIKit 的 `getHistoryMessageList` 等会失败或行为不完整。
- **纯 Platform**：所有 SDK 调用都走 Platform，需要实现的方法多、与 SDK 版本强绑定，迁移与维护成本高；且当前 SDK 在 `isCustomPlatform` 路由下，部分能力仍依赖原生库加载，纯 Platform 难以完全替代。
- **混合架构**：大部分调用沿用“换库不换接口”的二进制替换，保持与现有 SDK 调用习惯一致；仅把“必须由 Dart 实现”的能力（历史、轮询、Bootstrap、通话桥、部分回调）交给 `Platform + FfiChatService`，兼顾兼容性与功能完整性。详见 [doc/architecture/HYBRID_ARCHITECTURE.md](doc/architecture/HYBRID_ARCHITECTURE.md)。

**调用链（ASCII）**：

```text
                    UIKit / 业务
                           |
         +-----------------+-----------------+
         |                                   |
   TIMManager.instance          getHistoryMessageList / ...
         |                                   |
   NativeLibraryManager             Tim2ToxSdkPlatform
   bindings.DartXXX()                      |
         |                                   |
         +-----------------+-----------------+
                           |
              libtim2tox_ffi (dart_compat_* / tim2tox_ffi_*)
                           |
              FfiChatService（轮询、历史、登录状态）
                           |
              V2TIM*Manager / ToxManager -> c-toxcore
```

---

## 仓库结构

| 路径 | 职责与边界 |
| --- | --- |
| `lib/` | 应用 Dart 代码：UI、启动、适配层、工具。 |
| `lib/bootstrap/` | 启动早期工作：日志与路径、`setNativeLibraryName('tim2tox_ffi')`、原生日志文件设置。 |
| `lib/adapters/` | Tim2Tox 接口实现：Preferences、Logger、Bootstrap、EventBus、ConversationManager 等，注入给 `FfiChatService`。 |
| `lib/sdk_fake/` | 适配层：将 `FfiChatService` / Tim2Tox 数据转换为 UIKit 所需的 Fake 模型与 Provider。 |
| `lib/ui/` | 页面与组件：登录、首页、会话、设置、Bootstrap 等；主要使用 UIKit 组件，少量自定义页。 |
| `lib/util/` | 工具：`AppLogger`、偏好、Bootstrap 节点列表、主题/语言等。 |
| `lib/startup/` | 启动流程：账号恢复、Bootstrap 决策、`init -> login -> startPolling`，以及超时与错误处理。 |
| `lib/call/` | 通话 UI 与效果，包括 TUICallKit 适配和来电 overlay。 |
| `tool/` | 依赖引导工具，尤其是 `bootstrap_deps.dart`，负责 submodule、SDK 拉取、打补丁与 `pubspec_overrides`。 |
| `third_party/` | 依赖：Tim2Tox、Tencent Cloud Chat SDK、chat-uikit-flutter 等，通过 submodule 或脚本获取。 |
| `doc/` | 架构、构建、排障、接入与维护文档。 |

---

## 快速开始

**从零开始的最短启动路径**（在仓库根目录执行）：

```bash
# 1. 克隆（若尚未克隆）
git clone <repo-url> toxee && cd toxee

# 2. 依赖引导：submodule、SDK 拉取与打补丁、
#    以及 pubspec_overrides 生成
dart run tool/bootstrap_deps.dart

# 3. 拉取 Dart / Flutter 依赖
flutter pub get

# 4. 构建并运行（会先构建 tim2tox FFI 库）
./build_all.sh --platform macos --mode debug

# 或使用运行脚本（构建 + 启动 + 可选日志 tail）
./run_toxee.sh
```

若出现 `package_config.json` 解析错误，可先执行 `dart tool/bootstrap_deps.dart`（不用 `run`）再执行 `flutter pub get`。完整步骤与常见问题见 [doc/getting-started.md](doc/getting-started.md)、[doc/operations/DEPENDENCY_BOOTSTRAP.md](doc/operations/DEPENDENCY_BOOTSTRAP.md)。

---

## 构建与运行

- **统一构建**：`./build_all.sh --platform <macos|ios|android|...> --mode <debug|release>`
- **仅运行**：`./run_toxee.sh`（其他平台辅助脚本包括 `run_toxee_ios.sh`、`run_toxee_android.sh` 等）
- 详细平台步骤、依赖布局和部署说明见 [doc/operations/BUILD_AND_DEPLOY.md](doc/operations/BUILD_AND_DEPLOY.md)、[doc/operations/DEPENDENCY_BOOTSTRAP.md](doc/operations/DEPENDENCY_BOOTSTRAP.md)、[doc/operations/DEPENDENCY_LAYOUT.md](doc/operations/DEPENDENCY_LAYOUT.md)。调试问题见 [doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md)。

## GitHub Actions 打包

仓库现已包含 [`.github/workflows/build-packages.yml`](.github/workflows/build-packages.yml)。它会在 `push`、`pull_request`、tag push 和手动触发时执行，并为以下平台生成构建产物：

- **Windows**
- **Linux**
- **macOS**
- **Android**
- **iOS**

每个平台 job 都会把 `dist/<platform>/` 目录作为 GitHub Actions artifact 上传。桌面端 job 会先构建宿主平台的 Tim2Tox FFI 动态库，再把它一起打进应用产物。Android 会同时产出 `app-release.apk` 和 `app-release.aab`；如果配置了 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 这 4 个 secrets，workflow 会自动使用 release keystore 签名，否则继续沿用项目当前的 debug-key release 签名。

桌面端当前的安装型产物分别是：

- **Windows**：`toxee-windows-x64-release.msi`（另附 `.zip` 便携包）
- **macOS**：`toxee-macos-release.dmg`（另附 `.zip` 包）
- **Linux**：`toxee-linux-x64-release.AppImage`（另附 `.tar.gz` 包）

iOS 现在分两种模式：

- 如果配置了 `IOS_CERTIFICATE_P12_BASE64`、`IOS_CERTIFICATE_PASSWORD`、`IOS_PROVISIONING_PROFILE_BASE64`，workflow 会执行带签名的 `flutter build ios --release`，并产出真实可安装的 `.ipa`。
- 如果没有这些 secrets，iOS job 仍会执行未签名校验构建，但**不会**把这个 IPA 发布到 GitHub Releases；此时只会在 `dist/ios/NOTES.txt` 中说明未配置签名。

对于 Android/iOS，如果工作区里还没有可注入的 Tim2Tox 移动端原生库，CI 也会继续把这个限制写进 `dist/<platform>/NOTES.txt`。在正式发布模式下，如果 Android 的 JNI `libtim2tox_ffi.so` 没有被 staged，APK/AAB 也不会再进入 GitHub Release，避免把“能编译”误认为“已经完成原生注入”。

同一个 workflow 也支持发布到 **GitHub Releases**：

- 推送 `v1.2.3` 这样的 tag，会自动构建所有平台并发布 GitHub Release。
- 或者手动执行 `workflow_dispatch`，把 `publish_release` 设为 `true`，并填写 `release_tag`；如果是预发布版本，还可以把 `prerelease` 设为 `true`。
- 发布 job 会下载当前 run 的构建产物，只把通过发布门禁的真正可安装包上传到 Release，并额外生成 `SHA256SUMS.txt`。
- Release 文案使用 GitHub 的 `--generate-notes` 自动生成；各平台额外的打包说明会作为附带构建说明文件一起上传。

---

## 文档入口

完整文档索引与按角色阅读路径（新用户 / 接入方 / 维护者）从 [doc/README.md](doc/README.md) 开始。

常用入口：

- [依赖引导](doc/operations/DEPENDENCY_BOOTSTRAP.md)
- [排障](doc/TROUBLESHOOTING.md)
- [混合架构](doc/architecture/HYBRID_ARCHITECTURE.md)
- [接入指南](doc/integration/INTEGRATION_GUIDE.md)
- [维护者视角](doc/architecture/MAINTAINER_ARCHITECTURE.md)

---

## 适用场景与非目标

**适用**：

- 想快速跑通一个基于 Tox 的 Flutter 聊天应用。
- 需要参考如何将 Tim2Tox 集成进客户端，包括依赖引导、接口注入、启动顺序和混合架构拆分。
- 计划在 toxee 基础上做扩展或定制（UI、Bootstrap、通话、插件等）。

**非目标**：

- 仅需 Tox 协议库或通用 IM SDK。这种情况应直接使用 Tim2Tox 或 c-toxcore，而不是 toxee。
- 需要与腾讯云 IM 服务端互通。toxee 以后端为 Tox P2P，并不连接腾讯云 IM。

---

## 已知限制

- **平台重点**：日常构建与开发主要围绕 macOS；iOS/Android 需要按各平台配置与脚本验证。
- **历史与回调归属**：历史消息在 Dart 侧（`FfiChatService` / `MessageHistoryPersistence`）维护。混合架构下要避免二进制替换路径与 Platform 路径重复写历史或重复回调；这依赖 `BinaryReplacementHistoryHook` 等约定来保证。
- **多实例**：toxee 使用 Tim2Tox 默认的单例式流程。多实例能力主要用于 Tim2Tox 的 auto tests，不属于客户端默认工作流。
- **依赖管理**：项目依赖 submodule 与脚本拉取的 SDK/UIKit 内容。首次克隆或依赖变化后，必须先执行 `dart run tool/bootstrap_deps.dart`，再执行 `flutter pub get`。

---

## 新贡献者 onboarding

- 先完整走一遍快速开始，确认本地可以登录、发消息并看到会话列表。
- 阅读本 README 的「5 分钟内理解本项目」「它与 Tim2Tox 的关系」「当前架构概览」，再按 [doc/README.md](doc/README.md) 中与你角色匹配的阅读路径继续。
- 如果你要改启动、日志或依赖引导，先看 `lib/main.dart`、`lib/bootstrap/logging_bootstrap.dart`、`tool/bootstrap_deps.dart`。
- 如果你要改消息、会话或历史，先看 `lib/sdk_fake/` 和 [doc/architecture/HYBRID_ARCHITECTURE.md](doc/architecture/HYBRID_ARCHITECTURE.md)。
- 如果需要修改 Tim2Tox 本体，请在 `third_party/tim2tox` 中工作（上游：[agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)），本地文档入口见 [third_party/tim2tox/doc/README.md](third_party/tim2tox/doc/README.md)。

---

## 许可证

见 [LICENSE](LICENSE)。
